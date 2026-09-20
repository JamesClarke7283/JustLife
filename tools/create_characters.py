"""JustLife original character asset generator. Blender 5.x, background safe.
Run: blender --background --python tools/create_characters.py
"""
import bpy, math, os, random, sys, shutil, tempfile
from mathutils import Vector
from math import sin, cos, pi
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AGE='adult'
SURFACE='--surface-repair' in sys.argv
GRIP='--grip' in sys.argv or SURFACE
if '--age' in sys.argv:
    AGE=sys.argv[sys.argv.index('--age')+1]
    if AGE not in ['adult','child','teen','elder']:raise ValueError('Unknown age stage: '+AGE)
ART_PREFIX='character_rig' if AGE=='adult' else 'character_'+AGE
SOURCE_NAME='characters.blend' if AGE=='adult' else 'characters_'+AGE+'.blend'
if GRIP:
    ART_PREFIX='character_grip' if AGE=='adult' else ART_PREFIX+'_grip'
    SOURCE_NAME=SOURCE_NAME.replace('.blend','_grip.blend')
if SURFACE:
    ART_PREFIX='character_'+AGE+'_surface'
    SOURCE_NAME='characters_'+AGE+'_surface.blend'
random.seed(19)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials): bpy.data.materials.remove(m)

def mat(name,hexcol,rough=.55,metal=0):
    srgb=tuple(int(hexcol[i:i+2],16)/255 for i in (0,2,4)); c=tuple(v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in srgb); m=bpy.data.materials.new(name); m.diffuse_color=(*c,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*c,1); p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    return m
skin=mat('Skin','BF825F',.57); lips=mat('Lips','9D504C',.57); ear_inner=mat('Ear_detail','B27355'); nostril=mat('Nose_detail','794C3C')
hair=mat('Hair','32221F',.67); hair_highlight=mat('Hair_highlight','48302A',.72); hair_dark=mat('Hair_shadow','211C1B',.6)
top=mat('Top','658A83',.83); top_seam=mat('Top_seam','4D716C',.87); top_inner=mat('Top_inner','F7EADC',.84)
bottom=mat('Bottom','675D73',.83); bottom_seam=mat('Bottom_seam','514957',.85)
shoes=mat('Shoes','E9E4D9',.65); sole=mat('Shoes_sole','C6BDAE',.68); shoeaccent=mat('Shoes_accent','A26D56',.65)
eye_white=mat('Eyes_white','F3E6D8',.3); iris=mat('Eyes','547365',.29); iris_edge=mat('Eyes_edge','31413B',.32); pupil=mat('Eyes_pupil','1E2521',.3); catch=mat('Eyes_catchlight','FFFFFF',.15)
gold=mat('Jewelry','D4AD68',.27,.7)

def parent_keep(o,p):
    if p:
        bpy.context.view_layer.update(); mw=o.matrix_world.copy(); o.parent=p; o.matrix_world=mw
    return o

def empty(name,loc=(0,0,0),p=None):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.location=loc; return parent_keep(o,p)

def mesh(name,verts,faces,ma,p=None,sub=0):
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update(); o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o)
    if ma: me.materials.append(ma)
    for poly in me.polygons: poly.use_smooth=True
    if sub: mod=o.modifiers.new('Sculpted smooth surface','SUBSURF'); mod.levels=sub; mod.render_levels=sub
    return parent_keep(o,p)

def uv(name,loc,sc,ma,p=None,seg=32,rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=loc); o=bpy.context.object; o.name=name; o.scale=sc; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if ma:o.data.materials.append(ma)
    for f in o.data.polygons:f.use_smooth=True
    return parent_keep(o,p)

def loft(name,rings,ma,p=None,n=24,sub=1):
    # rings: z, halfwidth, halfdepth, yoffset, xoffset
    vs=[]
    for z,w,d,y,x in rings:
        for j in range(n):
            a=2*pi*j/n; vs.append((x+w*sin(a),y-d*cos(a),z))
    fs=[]
    for i in range(len(rings)-1):
        for j in range(n): fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    fs += [tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+j for j in range(n))]
    return mesh(name,vs,fs,ma,p,sub)

def tube(name,points,radii,ma,p=None,n=10,sub=1,flat=1):
    pts=[Vector(v) for v in points]; vs=[]
    for i,v in enumerate(pts):
        tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized(); up=Vector((0,1,0))
        if abs(tangent.dot(up))>.95:up=Vector((1,0,0))
        a=tangent.cross(up).normalized(); b=tangent.cross(a).normalized()
        rr=radii[i] if isinstance(radii,list) else radii
        for j in range(n):
            t=2*pi*j/n; q=v+a*rr*cos(t)+b*rr*sin(t)*flat; vs.append(q)
    fs=[]
    for i in range(len(pts)-1):
        for j in range(n):fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    fs+=[tuple(range(n-1,-1,-1)),tuple((len(pts)-1)*n+j for j in range(n))]
    return mesh(name,vs,fs,ma,p,sub if 'Hair_Bob' in name else min(sub,1))

def bezline(name,pts,radius,ma,p=None):
    cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'; cu.resolution_u=4; cu.bevel_depth=radius; cu.bevel_resolution=2
    sp=cu.splines.new('BEZIER'); sp.bezier_points.add(len(pts)-1)
    for b,co in zip(sp.bezier_points,pts):b.co=co;b.handle_left_type='AUTO';b.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,cu); bpy.context.collection.objects.link(o); cu.materials.append(ma); return parent_keep(o,p)

def almond(name,x,z,ma,p):
    n=40; vs=[(x,-.112,z)]; width=.0305; h=.011
    for j in range(n):
        t=2*pi*j/n; xx=width*cos(t); zz=h*sin(t)*(.68+.32*abs(sin(t)))
        vs.append((x+xx,-.100 + abs(xx)*.11,z+zz+(xx*.08 if x>0 else -xx*.08)))
    fs=[(0,j+1,(j+1)%n+1) for j in range(n)]
    return mesh(name,vs,fs,ma,p,1)

root=empty('Character')
finger_paths={}
# Garment silhouette is modeled in contoured rings, with softly dropped shoulders.
loft('Top_Blouse',[(1.022,.143,.086,.003,0),(1.035,.157,.094,.003,0),(1.06,.160,.096,.002,0),(1.10,.143,.084,0,0),(1.19,.148,.087,-.001,0),(1.28,.174,.095,-.002,0),(1.34,.180,.085,.001,0),(1.385,.158,.068,.003,0),(1.411,.099,.050,.003,0),(1.416,.057,.046,.001,0)],top,root,32,2)
loft('Skin_Neck',[(1.382,.049,.042,.005,0),(1.419,.049,.041,.005,0),(1.46,.046,.042,.009,0),(1.484,.053,.048,.012,0)],skin,root,24,2)
# Ribbed crew neckline follows actual neck; the small placket and cuffs read at gameplay scale.
pts=[]
for i in range(33):
    a=2*pi*i/32; pts.append((.057*sin(a),.001-.047*cos(a),1.414-.006*cos(a)))
bezline('Top_Collar_binding',pts,.006,top_inner,root)
bezline('Top_Front_placket',[(0,-.066,1.39),(0,-.091,1.33),(0,-.098,1.28)],.0022,top_seam,root)
for z,y in [(1.375,-.078),(1.34,-.091),(1.301,-.098)]:uv('Top_Pearl_button',(0,y-.002,z),(.004,.002,.004),top_inner,root,16,8)
# Small folds and stitched hem soften the clean fitted silhouette.
pts=[(.15*sin(2*pi*i/48),.003-.091*cos(2*pi*i/48),1.043) for i in range(49)];bezline('Top_Hem',pts,.0027,top_seam,root)
for s in [-1,1]:
    bezline('Top_Fold',[(s*.102,-.078,1.071),(s*.086,-.084,1.09),(s*.078,-.086,1.113)],.0017,top_seam,root)
# Trouser yoke and waistband; upper legs start underneath.
# Shaped trouser yoke blends into two leg openings rather than a rounded pelvis cap.
pv=[]; nf=64
for z,w,d,y,blend in [(1.05,.137,.08,.005,0),(1.025,.143,.085,.005,0),(.977,.158,.091,.009,.08),(.933,.16,.091,.011,.45),(.902,.16,.087,.012,1)]:
    for j in range(nf):
        a=2*pi*j/nf; x=w*sin(a); yy=y-d*cos(a)
        if a<pi:
            b=-pi/2+2*a; xx=.08+.079*sin(b); yy2=.012-.087*cos(b)
        else:
            b=pi/2+2*(a-pi); xx=-.08+.079*sin(b); yy2=.012-.087*cos(b)
        pv.append((x*(1-blend)+xx*blend,yy*(1-blend)+yy2*blend,z-.014*blend*abs(cos(a))**6))
pf=[]
for r in range(4):
    for j in range(nf):pf.append((r*nf+j,r*nf+(j+1)%nf,(r+1)*nf+(j+1)%nf,(r+1)*nf+j))
mesh('Bottom_Hip',pv,pf,bottom,root,2)
loft('Bottom_Waistband',[(1.021,.140,.082,.005,0),(1.024,.142,.084,.005,0),(1.048,.14,.083,.005,0),(1.051,.138,.081,.005,0)],bottom_seam,root,32,1)
# belt loops and a small warm metal fastening
for x in [-.11,.11]:bezline('Bottom_Belt_loop',[(x,-.045,1.051),(x,-.052,1.032),(x,-.054,1.02)],.0034,bottom,root)
uv('Bottom_Button',(0,-.081,1.037),(.005,.002,.005),gold,root,16,8)
for s in [-1,1]:
    bezline('Bottom_Pocket',[(s*.084,-.067,1.011),(s*.112,-.063,.978),(s*.133,-.05,.959)],.002,bottom_seam,root)
    # Legs with local pivots, smooth separate forms hide joints inside overlapping cloth.
    leg=empty('Leg_'+('L' if s<0 else 'R'),(s*.078,.012,.922),root)
    loft('Bottom_Thigh_'+str(s),[(.49,.054,.059,.011,s*.087),(.55,.061,.063,.014,s*.086),(.64,.067,.073,.017,s*.085),(.78,.079,.083,.018,s*.082),(.876,.083,.087,.012,s*.079),(.96,.075,.079,.009,s*.076)],bottom,leg,24,2)
    shin=empty('Shin_'+('L' if s<0 else 'R'),(s*.087,.012,.548),leg)
    loft('Bottom_Shin_'+str(s),[(.121,.041,.044,.009,s*.09),(.137,.046,.047,.009,s*.09),(.27,.048,.052,.014,s*.09),(.40,.056,.061,.018,s*.089),(.505,.055,.059,.012,s*.088),(.593,.054,.060,.011,s*.087)],bottom,shin,24,2)
    cuff=[(s*.09+.043*sin(2*pi*i/32),.009-.045*cos(2*pi*i/32),.14) for i in range(33)]; bezline('Bottom_Cuff',cuff,.002,bottom_seam,shin)
    bezline('Bottom_Pressed_crease',[(s*.086,-.067,.87),(s*.086,-.069,.72),(s*.087,-.048,.58)],.0013,bottom_seam,leg)
    # Rounded, low-top sneakers, with separate rubber foxing, tongue, piping and laces.
    uv('Shoes_Sole_'+str(s),(s*.09,-.037,.035),(.056,.115,.027),sole,shin)
    uv('Shoes_Upper_'+str(s),(s*.09,-.043,.063),(.054,.106,.047),shoes,shin)
    uv('Shoes_Heel_'+str(s),(s*.09,.031,.09),(.043,.047,.043),shoes,shin)
    uv('Shoes_Tongue_'+str(s),(s*.09,-.016,.103),(.029,.045,.012),shoes,shin)
    for i in range(4):
        y=-.003-i*.017; z=.117-i*.004
        bezline('Shoes_Laces',[(s*.09-.024,y,z),(s*.09,y-.003,z+.001),(s*.09+.024,y,z)],.0023,top_inner,shin)
    bezline('Shoes_Accent',[(s*.09+s*.047,.015,.079),(s*.09+s*.050,-.01,.068),(s*.09+s*.048,-.063,.059)],.004,shoeaccent,shin)
    # Upper arm / elbow / wrist in a relaxed pose instead of a T-pose.
    side='L' if s<0 else 'R'; arm=empty('Arm_'+side,(s*.18,0,1.361),root)
    loft('Top_Sleeve_'+side,[(1.14,.047,.055,.009,s*.227),(1.155,.055,.061,.008,s*.225),(1.25,.057,.064,.005,s*.211),(1.345,.057,.059,.004,s*.172),(1.383,.043,.046,.005,s*.142)],top,arm,24,2)
    cuff=[(s*.227+.049*sin(2*pi*i/32),.009-.057*cos(2*pi*i/32),1.154) for i in range(33)];bezline('Top_Sleeve_cuff',cuff,.004,top_inner,arm)
    fore=empty('Forearm_'+side,(s*.244,.007,1.087),arm)
    loft('Skin_Forearm_'+side,[(.827,.023,.024,-.013,s*.264),(.884,.025,.026,-.008,s*.262),(.951,.031,.031,.005,s*.257),(1.025,.034,.033,.01,s*.252),(1.09,.035,.035,.008,s*.244),(1.154,.040,.043,.004,s*.230),(1.194,.041,.045,.003,s*.222)],skin,fore,24,2)
    # Palm and individual tapering fingers; small nails are intentionally subtle.
    palm=loft('Skin_Palm_'+side,[(.797,.027,.013,-.016,s*.267),(.807,.032,.015,-.014,s*.267),(.822,.031,.017,-.014,s*.267),(.848,.027,.021,-.012,s*.265),(.868,.023,.021,-.010,s*.263),(.880,.022,.021,-.009,s*.263)],skin,fore,24,2)
    for i in range(4):
        x=s*(.2460+i*.0142);length=[.045,.056,.052,.041][i];finger_width=[.95,1,.97,.86][i]
        inward=[.0015,.001,0,-.0015][i];lift=[.001,.002,.005,.008][i]
        curl_y=[(-.014,-.009,-.007),(-.013,-.006,-.003),(-.009,0,.006),(-.006,.006,.012)][i]
        points=[(x,-.019,.809),(x+s*inward*.35,curl_y[0],.808-length*.32),(x+s*inward*.8,curl_y[1],.808-length*.68+lift*.25),(x+s*inward,curl_y[2],.808-length+lift)]
        finger_paths[(side,i)]=[Vector(point) for point in points]
        tube('Skin_Finger_'+side+str(i),points,[.0068*finger_width,.0066*finger_width,.0056*finger_width,.0048*finger_width],skin,fore,12,2)
        tangent=(Vector(points[-1])-Vector(points[-2])).normalized();tip_center=Vector(points[-1])-tangent*.005
        pad=uv('Skin_Finger_'+side+str(i)+'_tip',tip_center,(.0045*finger_width,.0045*finger_width,.0065),skin,fore,16,12)
        pad.rotation_euler=tangent.to_track_quat('Z','Y').to_euler()
    tube('Skin_Thumb_'+side,[(s*.244,-.017,.845),(s*.227,-.029,.824),(s*.229,-.038,.804)],[.011,.008,.0055],skin,fore,12,2)
    uv('Skin_Thumb_'+side+'_tip',(s*.229,-.038,.808),(.0055,.0055,.007),skin,fore,16,12)
    # Tiny stud earring coordinates are on the head, created below.
# Sculpted head: jaw, cheekbones, temples and forehead are a single continuous surface.
head=empty('Head',(0,.005,1.458),root)
headrings=[(1.444,.018,.026,-.018,0),(1.458,.041,.048,-.004,0),(1.478,.062,.067,-.003,0),(1.503,.083,.080,.001,0),(1.538,.100,.091,.004,0),(1.574,.113,.104,.006,0),(1.611,.111,.108,.008,0),(1.651,.107,.107,.010,0),(1.691,.095,.094,.012,0),(1.726,.068,.068,.012,0),(1.744,.028,.034,.012,0),(1.748,.003,.005,.012,0)]
headmesh=loft('Skin_Face',headrings,skin,head,48,2)
# Eyes are shaped almonds, with a radial iris and layered eyelid contours.
for s in [-1,1]:
    x=s*.047; z=1.612; almond('Eyes_Almond',x,z,eye_white,head)
    uv('Eyes_Iris_edge',(x,-.112,z),(.0108,.0025,.0108),iris_edge,head,32,16)
    uv('Eyes_Iris',(x,-.114,z),(.0087,.0019,.0087),iris,head,32,16)
    uv('Eyes_Pupil',(x,-.1155,z),(.0048,.0011,.0055),pupil,head,24,12)
    uv('Eyes_Light',(x-.003,-.117,z+.0039),(.0022,.001,.0022),catch,head,16,8)
    upper=[];lower=[]
    for i in range(13):
        t=pi*i/12; xx=.0305*cos(t); zz=.011*sin(t)*(.68+.32*abs(sin(t)))
        upper.append((x+xx,-.105-.011*sin(t)+abs(xx)*.10,z+zz*1.07+(xx*.08*s)))
        lower.append((x+xx,-.102-.012*sin(t)+abs(xx)*.10,z-zz*.86+(xx*.08*s)))
    bezline('Skin_Upper_eyelid',upper,.0024,skin,head); bezline('Skin_Lower_eyelid',lower,.0022,skin,head)
    bezline('Hair_Lash',[(v[0],v[1]-.0033,v[2]-.0003) for v in upper],.0009,hair_dark,head)
    bezline('Skin_Eye_crease',[(x-.026,-.095,1.631),(x,-.102,1.635),(x+.026,-.095,1.631)],.0009,skin,head)
    # Brows taper toward the temples and have softly arched silhouette.
    tube('Hair_Brow',[(s*.023,-.107,1.642),(s*.037,-.111,1.647),(s*.055,-.109,1.648),(s*.070,-.101,1.644),(s*.079,-.094,1.639)],[.003,.005,.0044,.0032,.0009],hair,head,10,2,flat=.7)
    ear=uv('Skin_Ear',(s*.111,.006,1.574),(.021,.029,.039),skin,head)
    uv('Ear_Concha',(s*.126,-.015,1.575),(.007,.015,.022),ear_inner,head)
    bezline('Skin_Ear_helix',[(s*.119,-.017,1.548),(s*.13,-.02,1.566),(s*.13,-.018,1.59),(s*.12,-.012,1.6)],.0045,skin,head)
    uv('Jewelry_Stud',(s*.125,-.014,1.549),(.004,.004,.004),gold,head,20,12)
# Nose has a formed bridge, curved tip and nostril wings.
loft('Skin_Nose',[(1.541,.012,.005,-.109,0),(1.547,.026,.009,-.113,0),(1.562,.027,.014,-.118,0),(1.573,.020,.012,-.116,0),(1.586,.014,.009,-.108,0),(1.604,.012,.005,-.099,0),(1.612,.011,.003,-.098,0)],skin,head,20,2)
for s in [-1,1]:
    uv('Skin_Nostril_wing',(s*.020,-.115,1.553),(.010,.010,.006),skin,head,24,12)
    uv('Nose_Nostril',(s*.016,-.123,1.548),(.005,.004,.0018),nostril,head,20,10)
# Fuse the nasal bridge and alar wings into one smoothly joined volume.
bpy.ops.object.select_all(action='DESELECT')
noseparts=[ob for ob in list(head.children) if ob.name.startswith('Skin_Nose') or ob.name.startswith('Skin_Nostril')]
for ob in noseparts:ob.select_set(True)
bpy.context.view_layer.objects.active=noseparts[0]
bpy.ops.object.convert(target='MESH');bpy.ops.object.join();noseobj=bpy.context.object;noseobj.name='Skin_Nose'
noseobj.data.remesh_voxel_size=.0015;bpy.ops.object.voxel_remesh()
for poly in noseobj.data.polygons:poly.use_smooth=True
smooth=noseobj.modifiers.new('Sculpt polish','SMOOTH');smooth.factor=.7;smooth.iterations=3
# Defined cupid bow, understated natural lip color and smile crease.
tube('Lips_Upper',[(-.027,-.096,1.516),(-.017,-.11,1.522),(-.008,-.115,1.524),(0,-.117,1.52),(.008,-.115,1.524),(.017,-.11,1.522),(.027,-.096,1.516)],[.0009,.0035,.004,.003,.004,.0035,.0009],lips,head,10,2,flat=.9)
tube('Lips_Lower',[(-.027,-.097,1.515),(-.017,-.11,1.512),(0,-.118,1.509),(.017,-.11,1.512),(.027,-.097,1.515)],[.001,.004,.0055,.004,.001],lips,head,10,2)
bezline('Lips_Seam',[(-.026,-.10,1.516),(-.014,-.115,1.516),(0,-.120,1.515),(.014,-.115,1.516),(.026,-.10,1.516)],.0011,nostril,head)
# Three original hairstyles share the same hair material for game recoloring.
def haircap(name,parent,back,front,wide=1,height=1):
    nr=20;nt=96; vs=[]
    for i in range(nr):
        for j in range(nt):
            a=2*pi*j/nt; frontness=(cos(a)+1)/2; limit=back*(1-frontness)+front*frontness
            phi=.012+(limit-.012)*i/(nr-1); wave=(.0018*sin(a*14+phi*7+2*sin(a))+.00065*sin(a*34+phi*13))*sin(phi)
            vs.append(((.119*wide+wave)*sin(phi)*sin(a),.012-(.114+wave)*sin(phi)*cos(a),1.623+.137*height*cos(phi)+.010*sin(a-.4)*sin(phi)**2))
    fs=[]
    for i in range(nr-1):
        for j in range(nt):fs.append((i*nt+j,i*nt+(j+1)%nt,(i+1)*nt+(j+1)%nt,(i+1)*nt+j))
    o=mesh(name,vs,fs,hair,parent,1); solid=o.modifiers.new('Hair shell','SOLIDIFY');solid.thickness=.007;return o
crop=empty('Hair_Crop',(0,0,0),head)
haircap('Hair_Crop_Cap',crop,1.94,1.15)
def attached_crop(points):
    if not SURFACE:return points
    result=[]
    for point in points:
        local=Vector((point[0]/.119,(point[1]-.012)/.114,(point[2]-1.623)/.137)).normalized()
        normal=Vector((local.x/.119,local.y/.114,local.z/.137)).normalized()
        result.append(Vector((local.x*.119,.012+local.y*.114,1.623+local.z*.137))+normal*.0025)
    return result
# broad swept fringe locks, with dark parted roots and thin sculpted highlights
for i in range(9):
    d=i/8
    pts=[(.067-.008*d,-.027+.019*d,1.746-.013*d),(.045-.022*d,-.086,1.755-.008*d),(-.008-.048*d,-.110-.004*d,1.736-.026*d),(-.073-.023*d,-.081-.016*d,1.671-.016*d)]
    pts=attached_crop(pts)
    tube('Hair_Crop_Swept_lock',pts,[.017,.023,.019,.002],hair,crop,10,2,flat=.55)
    if not SURFACE:bezline('Hair_Crop_Strand',[(p[0]-.003,p[1]-.009,p[2]+.002) for p in pts],.0011,hair_highlight,crop)
for i in range(6):
    t=i/5
    pts=[(.075-.034*t,-.006+.03*t,1.733),(.039-.088*t,.0+.054*t,1.764-.013*t),(-.062-.035*t,.033+.035*t,1.71-.012*t),(-.101+.026*t,.075+.024*t,1.636)]
    pts=attached_crop(pts)
    tube('Hair_Crop_Crown',pts,[.017,.022,.025,.004],hair,crop,12,2,flat=.64)
for s in [-1,1]:tube('Hair_Crop_Sideburn',[(s*.105,-.036,1.682),(s*.117,-.022,1.637),(s*.111,-.014,1.602)],[.019,.014,.004],hair,crop,10,2,.6)
for i in range(5):
    d=i/4
    pts=[(.055+.007*d,-.01+.02*d,1.737),(.079+.004*d,-.055+.019*d,1.725),(.108-.008*d,-.069+.027*d,1.684),(.111-.006*d,-.032+.027*d,1.623+.017*d)]
    pts=attached_crop(pts)
    tube('Hair_Crop_Part_fan',pts,[.011,.016,.014,.003],hair,crop,12,2,.58)
    if not SURFACE:bezline('Hair_Crop_Part_ridge',[(p[0]+.004,p[1]-.005,p[2]+.004) for p in pts[1:3]],.0007,hair_highlight,crop)
bob=empty('Hair_Bob',(0,0,0),head);haircap('Hair_Bob_Cap',bob,2.37,1.19,1.055,1.04)
for s in [-1,1]:
    for j in range(6):
        d=j/5; x=s*(.097+.025*sin(d*pi)); y=-.071+.032*j
        pts=[(s*.068,y*.65,1.719),(x,y,1.637),(x+s*.007,y+.007,1.553),(s*.09,y+.014,1.502)]
        tube('Hair_Bob_Lock',pts,[.021,.028,.027,.014],hair,bob,12,2,.7)
        bezline('Hair_Bob_Strand',[(p[0]+s*.012,p[1]-.004,p[2]) for p in pts[1:3]],.0012,hair_highlight,bob)
for i in range(5):
    d=i/4;tube('Hair_Bob_Fringe',[(.075,-.047,1.732),(.02-.026*d,-.106,1.732),(-.079-.015*d,-.102,1.66-.025*d)],[.022,.026,.003],hair,bob,12,2,.55)
curls=empty('Hair_Curls',(0,0,0),head);haircap('Hair_Curls_Cap',curls,2.08,1.24,1.06,1.02)
# Golden-angle distribution avoids artificial stacked rows in the curly silhouette.
for i in range(170):
    a=i*pi*(3-math.sqrt(5)); polar=math.acos(1-1.30*(i+.5)/170)
    x=.12*sin(polar)*sin(a); y=.012-.116*sin(polar)*cos(a); z=1.624+.139*cos(polar)
    if cos(a)>.36 and z<1.66:continue
    x+=random.uniform(-.004,.004);y+=random.uniform(-.004,.004);z+=random.uniform(-.003,.003)
    rr=random.uniform(.018,.025)
    ob=uv('Hair_Curls_Coil',(x,y,z),(rr,rr*.91,rr*1.05),hair,curls,16,12);ob.rotation_euler=(random.random(),random.random(),a)
    if i%3==0:
        normal=Vector((x/.12,(y-.012)/.116,(z-1.624)/.139)).normalized(); tangent=normal.cross(Vector((0,0,1)))
        if tangent.length<.1:tangent=normal.cross(Vector((0,1,0)))
        tangent.normalize();bitangent=normal.cross(tangent).normalized();pts=[]
        for k in range(8):
            t=k*pi*1.4/7;r=rr*.5*(1-k/15)
            pts.append(Vector((x,y,z))+normal*rr*.89+tangent*r*cos(t)+bitangent*r*sin(t))
        bezline('Hair_Curls_Ridge',pts,.0011,hair_highlight,curls)
# ---- Character sculpt / deformation pass 9 ---------------------------------
# Preserve the external articulation pivots for attached props while continuous
# anatomical and garment meshes are driven by a real skeleton.
def apply_mesh(ob):
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target='MESH'); return bpy.context.object

def fuse(name,objects,voxel=.0025,polish=3):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
    ob=bpy.context.object;ob.name=name;ob.data.remesh_voxel_size=voxel;bpy.ops.object.voxel_remesh()
    for f in ob.data.polygons:f.use_smooth=True
    sm=ob.modifiers.new('Surface sculpt polish','SMOOTH');sm.factor=.72;sm.iterations=polish
    bpy.ops.object.modifier_apply(modifier=sm.name)
    return ob

def smoothstep(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)

# Remove the old floating facial outlines, eyes and tubular mouth.
for ob in list(bpy.data.objects):
    if ob.name.startswith(('Eyes_','Skin_Upper_eyelid','Skin_Lower_eyelid','Skin_Eye_crease','Hair_Lash','Lips_')):
        bpy.data.objects.remove(ob,do_unlink=True)
# Sculpt the existing facial surface instead of attaching cheek/chin volumes.
face=bpy.data.objects['Skin_Face']
for index,v in enumerate(face.data.vertices):
    row=index//48;a=2*pi*(index%48)/48;z,w,d,y,_=headrings[row]
    if cos(a)>0:
        amount=smoothstep(1.47,1.53,z)*(1-smoothstep(1.625,1.68,z))
        frontal=cos(a)*(1-amount)+(cos(a)**.30)*amount
        v.co.y=y-d*frontal
        cheek=math.exp(-((abs(v.co.x)-.061)/.038)**2-((z-1.562)/.031)**2)
        chin=math.exp(-(v.co.x/.045)**2-((z-1.48)/.025)**2)
        v.co.y-=.0025*cheek+.003*chin
if SURFACE:
    # A continuous muzzle, philtrum and chin support the nose and lip boundary.
    # Sculpt the subdivided surface so the transition is smooth in strict profile.
    face=apply_mesh(face)
    for vertex in face.data.vertices:
        x,y,z=vertex.co
        front=1-smoothstep(-.025,.020,y)
        muzzle=.022*math.exp(-(x/.045)**2-((z-1.518)/.035)**2)
        philtrum=.012*math.exp(-(x/.029)**2-((z-1.548)/.026)**2)
        chin=.012*math.exp(-(x/.034)**2-((z-1.480)/.025)**2)
        brow=.004*math.exp(-((abs(x)-.047)/.038)**2-((z-1.643)/.018)**2)
        vertex.co.y-=front*(muzzle+philtrum+chin+brow)
for ob in list(bpy.data.objects):
    if ob.name.startswith('Skin_Ear_helix'):bpy.data.objects.remove(ob,do_unlink=True)

headpieces=[ob for ob in list(head.children) if ob.name.startswith('Skin_')]
headpieces.append(bpy.data.objects['Skin_Neck'])
headskin=fuse('Skin_Head_continuous',headpieces,.0015,4)
parent_keep(headskin,root)
# Recessed eyes, with continuous lower sockets and separately deforming upper lids.
for sign in [-1,1]:
    cutter=uv('Socket_cut',(sign*.047,-.099,1.611),(.0305,.025,.0115),None,None,40,24)
    bpy.context.view_layer.objects.active=headskin
    boolean=headskin.modifiers.new('Recessed orbital opening','BOOLEAN');boolean.operation='DIFFERENCE';boolean.solver='EXACT';boolean.object=cutter
    bpy.ops.object.modifier_apply(modifier=boolean.name);bpy.data.objects.remove(cutter,do_unlink=True)
upper_lids=[];lower_lids=[headskin]
for sign in [-1,1]:
    for upper in [True,False]:
        vs=[];n=25
        for row in range(4):
            f=row/3
            for j in range(n):
                t=pi*j/(n-1);dx=.030*cos(t);arch=sin(t);z=1.611+dx*.065*sign
                z+=arch*(.0100*(1-f)+.022*f) if upper else -arch*(.0085*(1-f)+.019*f)
                x=sign*.047+dx;face=.008-.108*max(.01,1-(x/.111)**2)**.15
                projection=.0048 if upper else .0032
                front=face-projection*arch;edge=face+.002
                if upper and row>0 and arch>.1:
                    hit,surface,normal,index=headskin.ray_cast(Vector((x,-1,z)),Vector((0,1,0)))
                    if hit and surface.y<0:edge=surface.y+.0015
                vs.append((x,front*(1-f)+edge*f,z))
        fs=[]
        for r in range(3):
            for j in range(n-1):
                face=(r*n+j,r*n+j+1,(r+1)*n+j+1,(r+1)*n+j)
                fs.append(tuple(reversed(face)) if upper else face)
        ob=mesh('Skin_Upper_lid_'+str(sign) if upper else 'Skin_Lower_socket',vs,fs,skin,head if upper else root,1)
        solid=ob.modifiers.new('Delicate lid thickness','SOLIDIFY');solid.thickness=.0015;solid.offset=0
        if upper:upper_lids.append((ob,sign))
        else:lower_lids.append(ob)
headskin=fuse('Skin_Head_continuous',lower_lids,.0012,3);parent_keep(headskin,root)
def facial_surface_y(x,z):
    bpy.context.view_layer.update()
    inverse=headskin.matrix_world.inverted()
    hit,point,normal,index=headskin.ray_cast(inverse@Vector((x,-1,z)),inverse.to_3x3()@Vector((0,1,0)))
    if not hit:raise ValueError('Missing facial surface at '+str((x,z)))
    return (headskin.matrix_world@point).y
if SURFACE:
    for ob in list(bpy.data.objects):
        if ob.name.startswith('Nose_Nostril'):bpy.data.objects.remove(ob,do_unlink=True)
    for sign in [-1,1]:
        vs=[];cx=sign*.016;cz=1.550
        vs.append((cx,facial_surface_y(cx,cz)-.00045,cz))
        for j in range(32):
            t=2*pi*j/32;x=cx+.0042*cos(t);z=cz+.00165*sin(t)
            vs.append((x,facial_surface_y(x,z)-.00025,z))
        mesh('Nose_Nostril',vs,[(0,j+1,(j+1)%32+1) for j in range(32)],nostril,head)
    for ob in list(bpy.data.objects):
        if ob.name.startswith('Hair_Brow'):bpy.data.objects.remove(ob,do_unlink=True)
    for sign in [-1,1]:
        vs=[];n=41
        for row in range(5):
            across=(row-2)/2
            for j in range(n):
                t=j/(n-1);x=sign*(.023+.057*t)
                center=1.641+.007*sin(pi*t)-.003*t
                width=(.0022+.0017*sin(pi*t))*(1-.72*t*t)
                z=center+width*across
                y=facial_surface_y(x,z)-.00035-.0011*(1-across*across)*sin(pi*t)**.35
                vs.append((x,y,z))
        fs=[]
        for row in range(4):
            for j in range(n-1):
                poly=(row*n+j,row*n+j+1,(row+1)*n+j+1,(row+1)*n+j)
                fs.append(poly if sign>0 else tuple(reversed(poly)))
        mesh('Hair_Brow',vs,fs,hair,head,1)
# Upper lids close as a controlled surface, with the outer skin edge held fixed.
for ob,sign in upper_lids:
    ob=apply_mesh(ob);ob.shape_key_add(name='Basis');blink=ob.shape_key_add(name='Blink');blink.value=0
    for i,v in enumerate(ob.data.vertices):
        x,y,z=v.co;dx=(x-sign*.047)/.030;arch=math.sqrt(max(0,1-dx*dx))
        if arch<.04:continue
        lid_inner_z=1.611+(x-sign*.047)*.065*sign+.0100*arch
        f=max(0,min(1,(z-lid_inner_z)/(.0120*arch)))
        amount=(1-f)**1.35
        blink.data[i].co.z-=.0185*arch*amount;blink.data[i].co.y+=.0016*arch*amount
# Globe and iris retreat slightly behind the closing lid; they never turn into a wire outline.
def globe_blink(ob):
    ob=apply_mesh(ob)
    if SURFACE:
        for vertex in ob.data.vertices:vertex.co.y+=.0025
    ob.shape_key_add(name='Basis');key=ob.shape_key_add(name='Blink');key.value=0
    for i,v in enumerate(ob.data.vertices):key.data[i].co.y+=.012
    return ob
for sign in [-1,1]:
    x=sign*.047;z=1.611
    globe_blink(uv('Eyes_Sclera',(x,-.080,z),(.028,.026,.014),eye_white,head,40,24))
    # A clipped iris preserves its natural round center inside the almond opening.
    for name,rad,y,ma in [('Eyes_Iris_edge',.0111,-.1051,iris_edge),('Eyes_Iris',.0095,-.106,iris),('Eyes_Pupil',.0046,-.1068,pupil)]:
        n=40;vs=[(x,y-.0005,z+.0005)]
        for j in range(n):
            t=2*pi*j/n;vs.append((x+rad*cos(t),y,z+max(-.0082,min(.0093,rad*sin(t)+.0005))))
        fs=[(0,j+1,(j+1)%n+1) for j in range(n)]
        if SURFACE:
            projection={'Eyes_Iris_edge':.0002,'Eyes_Iris':.0004,'Eyes_Pupil':.00065}[name]
            vs=[(x,0,z+.0005)]
            for row in range(1,7):
                f=row/6
                for j in range(n):
                    t=2*pi*j/n;dz=max(-.0082,min(.0093,rad*sin(t)+.0005))
                    vs.append((x+f*rad*cos(t),0,z+.0005*(1-f)+f*dz))
            for row in range(5):
                for j in range(n):
                    a=1+row*n+j;b=1+row*n+(j+1)%n
                    fs.append((a,b,b+n,a+n))
            vs=[(px,-.080-.026*math.sqrt(max(0,1-((px-x)/.028)**2-((pz-z)/.014)**2))-projection,pz) for px,py,pz in vs]
        globe_blink(mesh(name,vs,fs,ma,head))
    catch_y=-.1075 if not SURFACE else -.080-.026*math.sqrt(1-(.0028/.028)**2-(.0032/.014)**2)-.0008
    globe_blink(uv('Eyes_Catchlight',(x-.0028,catch_y,z+.0032),(.0015,.0003,.0015),catch,head,16,12))
# A closed, faintly smiling mouth: lip volume transitions into the surrounding face.
def lip_surface(name,upper):
    vs=[];n=33
    for r in range(5):
        f=r/4
        for j in range(n):
            x=-.033+.066*j/(n-1);q=abs(x)/.033;full=max(0,1-q*q)
            seam=1.512+.0065*q*q
            contour=(.0047*full+.0016*math.exp(-((abs(x)-.011)/.006)**2)) if upper else -.006*full
            z=seam+f*contour
            y=-.088-.016*full*(1-.53*f)-.0018*sin(pi*f)*full
            if SURFACE:
                y=facial_surface_y(x,z)-full*(.0025*(1-f)+.0022*sin(pi*f))+.00025*f
            vs.append((x,y,z))
    fs=[]
    for r in range(4):
        for j in range(n-1):
            face=(r*n+j,r*n+j+1,(r+1)*n+j+1,(r+1)*n+j)
            fs.append(face if upper else tuple(reversed(face)))
    ob=mesh(name,vs,fs,lips,head,1);sol=ob.modifiers.new('Lip volume','SOLIDIFY');sol.thickness=.0015
    return ob
lip_objects=[lip_surface('Lips_Upper_soft',True),lip_surface('Lips_Lower_soft',False)]
seam_points=[(-.032,-.089,1.518),(-.018,-.099,1.514),(0,-.105,1.512),(.018,-.099,1.514),(.032,-.089,1.518)]
if SURFACE:
    seam_points=[]
    for j in range(25):
        x=-.032+.064*j/24;q=abs(x)/.033;z=1.512+.0065*q*q
        seam_points.append((x,facial_surface_y(x,z)-.0025*(1-q*q)-.0004,z))
bezline('Lips_Smile_seam',seam_points,.0006,nostril,head)
surface_mouth_y=facial_surface_y(0,1.512)-.003 if SURFACE else None
# Smoothly fuse upper arm, elbow, palm, thumb and all fingers, then skin the result.
armskin=[]
for s in [-1,1]:
    side='L' if s<0 else 'R'
    upper=tube('Skin_Upperarm_fill_'+side,[(s*.168,.006,1.345),(s*.205,.005,1.276),(s*.228,.005,1.187)],[.041,.039,.038],skin,root,20,2)
    parts=[upper]+[ob for ob in list(bpy.data.objects) if ob.name.startswith(('Skin_Forearm_'+side,'Skin_Palm_'+side,'Skin_Finger_'+side,'Skin_Thumb_'+side))]
    arm=fuse('Skin_Arm_continuous_'+side,parts,.0018,3);parent_keep(arm,root);armskin.append(arm)
# Continuous trousers eliminate the former yoke and knee seams completely.
bpy.data.objects.remove(bpy.data.objects['Bottom_Hip'],do_unlink=True)
hip=loft('Bottom_Hip_volume',[(.84,.032,.025,.012,0),(.875,.11,.060,.012,0),(.94,.153,.087,.01,0),(1.03,.137,.08,.005,0),(1.05,.136,.079,.005,0)],bottom,root,32,2)
pants=fuse('Bottom_Continuous_trousers',[hip]+[ob for ob in list(bpy.data.objects) if ob.name.startswith(('Bottom_Thigh_','Bottom_Shin_'))],.0025,24);parent_keep(pants,root)
for ob in list(bpy.data.objects):
    if ob.name.startswith('Bottom_Pressed_crease'):bpy.data.objects.remove(ob,do_unlink=True)
# Project pocket trim onto the final continuous cloth surface.
for ob in list(bpy.data.objects):
    if ob.type=='CURVE' and ob.name.startswith('Bottom_Pocket'):
        for sp in ob.data.splines:
            for point in sp.bezier_points:
                x,y,z=point.co;hit,co,normal,idx=pants.ray_cast(Vector((x,-1,z)),Vector((0,1,0)))
                if hit:point.co.y=co.y-.0015
# Original casual shirt, now a single tailored surface through both shoulders.
casual=empty('Outfit_Casual',(0,0,0),root)
shirt=fuse('Outfit_Casual_Shirt',[bpy.data.objects['Top_Blouse'],bpy.data.objects['Top_Sleeve_L'],bpy.data.objects['Top_Sleeve_R']],.0025,3);parent_keep(shirt,casual)
for ob in list(bpy.data.objects):
    if ob.name.startswith('Top_'):
        # Preserve the original material names for recoloring, and label each wardrobe node.
        ob.name='Outfit_Casual_'+ob.name;parent_keep(ob,casual)
# Outfit 1: a cropped bomber with structured shoulders, long sleeves and ribbed edges.
jacket=empty('Outfit_Jacket',(0,0,0),root)
jacket_body=loft('Outfit_Jacket_Body',[(1.018,.148,.088,.004,0),(1.05,.164,.096,.004,0),(1.13,.177,.103,.004,0),(1.25,.187,.105,.004,0),(1.34,.181,.091,.004,0),(1.399,.141,.062,.004,0),(1.417,.057,.048,.004,0)],top,jacket,32,2)
jacket_parts=[jacket_body]
for s in [-1,1]:
    sleeve=loft('Outfit_Jacket_Sleeve',[(.875,.031,.032,-.008,s*.264),(.903,.037,.037,-.006,s*.263),(1.03,.047,.047,.01,s*.248),(1.17,.052,.054,.006,s*.229),(1.3,.058,.063,.005,s*.196),(1.382,.054,.055,.004,s*.154)],top,jacket,24,2);jacket_parts.append(sleeve)
jacket_shell=fuse('Outfit_Jacket_Shell',jacket_parts,.0028,3);parent_keep(jacket_shell,jacket)
loft('Outfit_Jacket_Waist_rib',[(1.012,.147,.087,.004,0),(1.017,.150,.09,.004,0),(1.052,.154,.092,.004,0),(1.055,.150,.089,.004,0)],top_seam,jacket,32,1)
loft('Outfit_Jacket_Stand_collar',[(1.404,.060,.049,.004,0),(1.432,.057,.047,.004,0),(1.434,.054,.044,.004,0),(1.405,.054,.045,.004,0)],top_seam,jacket,32,1)
bezline('Outfit_Jacket_Zip',[(0,-.088,1.027),(0,-.102,1.16),(0,-.102,1.27),(0,-.072,1.375),(0,-.047,1.424)],.0021,top_inner,jacket)
uv('Outfit_Jacket_Zip_pull',(0,-.107,1.288),(.005,.003,.010),gold,jacket,16,10)
for s in [-1,1]:
    cuff=loft('Outfit_Jacket_Cuff',[(.866,.031,.032,-.009,s*.264),(.872,.033,.034,-.008,s*.264),(.91,.035,.036,-.006,s*.263),(.916,.034,.035,-.006,s*.263)],top_seam,jacket,24,1)
    bezline('Outfit_Jacket_Pocket',[(s*.087,-.091,1.071),(s*.111,-.091,1.10),(s*.130,-.084,1.14)],.004,top_seam,jacket)
    for j in range(6):
        a=(j-2.5)*.33;bezline('Outfit_Jacket_Rib',[(s*.264+.032*sin(a),-.009-.033*cos(a),.872),(s*.263+.034*sin(a),-.006-.036*cos(a),.908)],.0008,top_inner,jacket)
# Outfit 2: long V-neck cardigan over an inset cream tee, with soft patch pockets.
cardigan=empty('Outfit_Cardigan',(0,0,0),root)
loft('Outfit_Cardigan_Tee',[(1.0,.139,.079,0,0),(1.15,.142,.082,0,0),(1.29,.161,.086,0,0),(1.37,.122,.061,0,0),(1.403,.052,.045,0,0)],top_inner,cardigan,32,2)
rings=[(.962,.16,.092,.10),(1.00,.164,.095,.10),(1.10,.160,.096,.12),(1.20,.170,.098,.19),(1.30,.179,.095,.35),(1.38,.142,.065,.68),(1.414,.062,.049,.85)]
vs=[];nf=49
for z,w,d,opening in rings:
    for j in range(nf):
        a=opening+(2*pi-2*opening)*j/(nf-1);vs.append((w*sin(a),.002-d*cos(a),z))
fs=[]
for r in range(len(rings)-1):
    for j in range(nf-1):fs.append((r*nf+j,r*nf+j+1,(r+1)*nf+j+1,(r+1)*nf+j))
coat=mesh('Outfit_Cardigan_Body',vs,fs,top,cardigan,2);solid=coat.modifiers.new('Soft knit thickness','SOLIDIFY');solid.thickness=.006
for s in [-1,1]:
    loft('Outfit_Cardigan_Sleeve',[(.875,.032,.033,-.009,s*.264),(.91,.039,.039,-.007,s*.263),(1.07,.048,.049,.009,s*.245),(1.21,.055,.057,.006,s*.220),(1.34,.056,.060,.004,s*.176),(1.385,.043,.046,.004,s*.145)],top,cardigan,24,2)
    edge=[(s*w*sin(opening),.000-d*cos(opening),z) for z,w,d,opening in rings]
    bezline('Outfit_Cardigan_Binding',edge,.005,top_seam,cardigan)
    # Patch pockets have a broad soft plane and a clearly rolled opening.
    pocket=uv('Outfit_Cardigan_Pocket',(s*.102,-.081,1.051),(.043,.012,.039),top,cardigan,24,16)
    bezline('Outfit_Cardigan_Pocket_rim',[(s*.061,-.087,1.078),(s*.101,-.096,1.078),(s*.142,-.085,1.078)],.003,top_seam,cardigan)
for z in [1.025,1.085,1.145]:uv('Outfit_Cardigan_Button',(.018,-.096,z),(.005,.003,.005),gold,cardigan,16,10)
# Soften the cardigan shoulder union while preserving its open front and inset tee.
# Its shell remains a separate knit panel; sleeves meet underneath dropped shoulders.
# A real armature drives smooth deformations for clothing and anatomical surfaces.
bpy.ops.object.armature_add(enter_editmode=True,location=(0,0,0));rig=bpy.context.object;rig.name='LifeRig';rig.data.name='LifeRig'
rig.data.edit_bones.remove(rig.data.edit_bones[0])
bone_specs=[('Root',(0,0,0),None),('Spine',(0,0,1.10),'Root'),('Head',(0,.005,1.458),'Spine'),('Arm_L',(-.18,0,1.361),'Spine'),('Arm_R',(.18,0,1.361),'Spine'),('Forearm_L',(-.244,.007,1.087),'Arm_L'),('Forearm_R',(.244,.007,1.087),'Arm_R'),('Leg_L',(-.078,.012,.922),'Root'),('Leg_R',(.078,.012,.922),'Root'),('Shin_L',(-.087,.012,.548),'Leg_L'),('Shin_R',(.087,.012,.548),'Leg_R')]
for name,co,parent in bone_specs:
    b=rig.data.edit_bones.new(name);b.head=co;b.tail=Vector(co)+Vector((0,0,.12));b.roll=0
    if parent:b.parent=rig.data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT');parent_keep(rig,root)

def bind(ob,mode='garment'):
    ob=apply_mesh(ob);parent_keep(ob,root if mode!='garment' else ob.parent)
    # Move the object origin to world identity, so analytic weights use authored coordinates.
    mw=ob.matrix_world.copy();ob.data.transform(mw);ob.matrix_world.identity()
    groups={name:ob.vertex_groups.new(name=name) for name,_,_ in bone_specs}
    for v in ob.data.vertices:
        x,y,z=v.co;weights={}
        if mode=='head':
            h=smoothstep(1.412,1.468,z);weights={'Spine':1-h,'Head':h}
        elif mode=='pants':
            shin=1-smoothstep(.44,.66,z);hip=1-smoothstep(.875,1.025,z);right=smoothstep(-.035,.035,x)
            weights={'Root':1-hip,'Leg_L':hip*(1-right)*(1-shin),'Leg_R':hip*right*(1-shin),'Shin_L':hip*(1-right)*shin,'Shin_R':hip*right*shin}
        else:
            side='L' if x<0 else 'R'
            # Garment torso fades smoothly through shoulder/axilla into the sleeve.
            arm=smoothstep(.125,.207,abs(x))
            if mode=='arm':arm=1.0
            elbow=1-smoothstep(1.025,1.17,z)
            spine=smoothstep(1.02,1.20,z)
            weights={'Root':(1-arm)*(1-spine),'Spine':(1-arm)*spine,'Arm_'+side:arm*(1-elbow),'Forearm_'+side:arm*elbow}
        for name,value in weights.items():
            if value>.0001:groups[name].add([v.index],value,'REPLACE')
    mod=ob.modifiers.new('Soft skeletal deformation','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False
    return ob
# Retopology reduction preserves the sculpted silhouette without shipping voxel density.
for ob,target in [(headskin,18000),(pants,12000),(shirt,12000),(jacket_shell,16000)]+[(a,9000) for a in armskin]:
    triangles=sum(len(p.vertices)-2 for p in ob.data.polygons)
    if triangles>target:
        bpy.context.view_layer.objects.active=ob
        dec=ob.modifiers.new('Game surface retopology','DECIMATE');dec.ratio=target/triangles;dec.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=dec.name)
headskin=bind(headskin,'head');pants=bind(pants,'pants')
for ob in armskin:bind(ob,'arm')
for group in [casual,jacket,cardigan]:
    for ob in list(group.children):
        if ob.type in ['MESH','CURVE']:bind(ob,'garment')
# Pose-space corrective prevents harsh pinching at the hip and patella in seated poses.
from mathutils import Matrix
for name in ['Leg_L','Leg_R','Shin_L','Shin_R']:
    rig.pose.bones[name].rotation_mode='XYZ';rig.pose.bones[name].rotation_euler.x=(-pi/2 if name.startswith('Leg') else pi/2)
bpy.context.view_layer.update()
transforms={name:rig.pose.bones[name].matrix@rig.data.bones[name].matrix_local.inverted() for name,_,_ in bone_specs}
adjacency=[set() for _ in pants.data.vertices]
for edge in pants.data.edges:
    a,b=edge.vertices;adjacency[a].add(b);adjacency[b].add(a)
matrices=[];posed=[];strength=[]
for vertex in pants.data.vertices:
    matrix=Matrix(((0.,0.,0.,0.),)*4)
    for assignment in vertex.groups:
        name=pants.vertex_groups[assignment.group].name
        if name in transforms:matrix+=transforms[name]*assignment.weight
    matrices.append(matrix);posed.append(matrix@vertex.co)
    z=vertex.co.z;strength.append(.42*max(math.exp(-((z-.548)/.13)**4),.7*math.exp(-((z-.905)/.10)**4)))
for iteration in range(7):
    new=[]
    for index,point in enumerate(posed):
        if not adjacency[index]:new.append(point);continue
        average=sum((posed[j] for j in adjacency[index]),Vector())/len(adjacency[index])
        new.append(point.lerp(average,strength[index]))
    posed=new
pants.shape_key_add(name='Basis');sit_key=pants.shape_key_add(name='Sit');sit_key.value=0
for index,vertex in enumerate(pants.data.vertices):
    corrected=matrices[index].inverted_safe()@posed[index];delta=corrected-vertex.co
    if delta.length>.026:delta=delta.normalized()*.026
    sit_key.data[index].co=vertex.co+delta
for name in ['Leg_L','Leg_R','Shin_L','Shin_R']:rig.pose.bones[name].rotation_euler.x=0
bpy.context.view_layer.update()
# Expressions are geometry morphs on the continuous facial skin and soft lips.
headskin.shape_key_add(name='Basis');blink=headskin.shape_key_add(name='Blink');smile=headskin.shape_key_add(name='Smile')
for i,v in enumerate(headskin.data.vertices):
    x,y,z=v.co
    if 1.58<z<1.615 and abs(x)<.09 and y<-.088:
        blink.data[i].co.z+=.0008*math.exp(-((abs(x)-.047)/.033)**2)
    if 1.486<z<1.55 and abs(x)<.055 and y<-.065:
        w=math.exp(-((abs(x)-.028)/.022)**2-((z-1.514)/.025)**2)
        smile.data[i].co.z+=.004*w
for ob in lip_objects:
    ob=apply_mesh(ob);ob.shape_key_add(name='Basis');key=ob.shape_key_add(name='Smile')
    for i,v in enumerate(ob.data.vertices):key.data[i].co.z+=.004*(min(1,abs(v.co.x)/.033)**1.3)
# Identity controls share a continuous displacement field across all facial pieces.
# This keeps eyes, lids, eyebrows, nostrils and mouth attached at slider extremes.
def identity_delta(name,co):
    x,y,z=co;ax=abs(x);front=1-smoothstep(-.063,.025,y)
    if name=='Face_Round':
        w=math.exp(-((z-1.545)/.064)**4)*smoothstep(1.459,1.487,z)*(.25+.75*smoothstep(.025,.065,ax))
        return Vector((.011*math.tanh(x/.035)*w,-.0045*math.exp(-((ax-.061)/.036)**2-((z-1.557)/.042)**2)*front,.0035*math.exp(-(x/.05)**2-((z-1.483)/.025)**2)))
    if name=='Jaw_Strong':
        w=math.exp(-((z-1.501)/.037)**4)*smoothstep(1.458,1.480,z)*smoothstep(.025,.067,ax)
        return Vector((.014*math.tanh(x/.028)*w,-.005*math.exp(-((z-1.495)/.042)**2)*front,-.003*math.exp(-(x/.038)**2-((z-1.482)/.022)**2)))
    if name=='Nose_Wide':
        w=math.exp(-(x/.033)**4-((z-1.562)/.027)**4)*(1-smoothstep(-.103,-.08,y))
        return Vector((.0085*math.tanh(x/.01)*w,-.0012*w,0))
    if name=='Eye_Spacing':
        w=(1-smoothstep(.079,.114,ax))*(1-smoothstep(.024,.052,abs(z-1.611)))*front
        return Vector((.0065*math.tanh(x/.009)*w,0,0))
    return Vector()
identity_names=['Face_Round','Jaw_Strong','Nose_Wide','Eye_Spacing']
identity_objects=[headskin]+[ob for ob in list(head.children) if ob.type in ['MESH','CURVE'] and ob.name.startswith(('Skin_Upper_lid','Eyes_','Lips_','Hair_Brow','Nose_','Ear_','Jewelry'))]
for ob in identity_objects:
    if ob.type!='MESH' or not ob.data.shape_keys:ob=apply_mesh(ob)
    if not ob.data.shape_keys:ob.shape_key_add(name='Basis')
    # The smile crease follows the lip corners instead of remaining fixed beneath them.
    if ob.name.startswith('Lips_Smile_seam') and not ob.data.shape_keys.key_blocks.get('Smile'):
        smile_key=ob.shape_key_add(name='Smile');smile_key.value=0
        for index,vertex in enumerate(ob.data.vertices):smile_key.data[index].co.z+=.004*(min(1,abs(vertex.co.x)/.033)**1.3)
    world=ob.matrix_world.copy();inverse=world.to_3x3().inverted()
    for name in identity_names:
        deltas=[inverse@identity_delta(name,world@vertex.co) for vertex in ob.data.vertices]
        if max((delta.length for delta in deltas),default=0)<.000001:continue
        key=ob.shape_key_add(name=name);key.slider_min=0;key.slider_max=1;key.value=0
        for index,delta in enumerate(deltas):key.data[index].co=ob.data.vertices[index].co+delta
root['identity_morphs']=','.join(identity_names)

if GRIP:
    # A reversible power grip preserves the continuous wrist and palm. Individual
    # finger centerlines bend toward the palmar surface, with the cross-section
    # rotated along each curve instead of crushing the fingers into a flat fan.
    for ob in armskin:
        side='L' if ob.name.endswith('_L') else 'R';sign=-1 if side=='L' else 1
        ob.shape_key_add(name='Basis');grip=ob.shape_key_add(name='Hand_Grip_'+side);grip.value=0
        curves=[]
        for i in range(4):
            points=finger_paths[(side,i)];lengths=[(points[j+1]-points[j]).length for j in range(3)]
            curves.append((points,lengths,sum(lengths)))
        thumb_path=[Vector((sign*.244,-.017,.845)),Vector((sign*.227,-.029,.824)),Vector((sign*.229,-.038,.804))]
        for vertex in ob.data.vertices:
            point=vertex.co.copy();x,y,z=point
            if z>.855:continue
            closest=None
            for points,lengths,total in curves:
                distance_along=0
                for segment in range(3):
                    start=points[segment];direction=points[segment+1]-start
                    t=max(0,min(1,(point-start).dot(direction)/direction.length_squared))
                    center=start+direction*t;distance=(point-center).length
                    if closest is None or distance<closest[0]:closest=(distance,center,direction.normalized(),(distance_along+lengths[segment]*t)/total,points[0],total)
                    distance_along+=lengths[segment]
            distance,center,tangent,progress,start,length=closest
            thumb_distance=10
            for a,b in zip(thumb_path,thumb_path[1:]):
                direction=b-a;t=max(0,min(1,(point-a).dot(direction)/direction.length_squared))
                thumb_distance=min(thumb_distance,(point-(a+direction*t)).length)
            thumb_priority=smoothstep(-.004,.004,distance-thumb_distance)
            thumb=thumb_priority*(1-smoothstep(.015,.026,thumb_distance))*(1-smoothstep(.815,.849,z))
            weight=(1-thumb_priority)*(1-smoothstep(.810,.824,z))*(1-smoothstep(.012,.020,distance))*smoothstep(0,.15,progress)
            angle=3.0*progress;radius=length/3.0
            target=Vector((center.x,start.y-radius*(1-cos(angle)),start.z-radius*sin(angle)))
            rest_angle=math.atan2(tangent.y,-tangent.z)
            rotation=Matrix.Rotation(-angle-rest_angle,3,'X')
            grip.data[vertex.index].co=point.lerp(target+rotation@(point-center),weight)+Vector((sign*.023,-.012,.007))*thumb
        adjacency=[set() for _ in ob.data.vertices]
        for edge in ob.data.edges:
            a,b=edge.vertices;adjacency[a].add(b);adjacency[b].add(a)
        positions=[vertex.co.copy() for vertex in grip.data]
        relaxation=[.26*smoothstep(.785,.806,v.co.z)*(1-smoothstep(.848,.866,v.co.z)) for v in ob.data.vertices]
        for iteration in range(5):
            positions=[point.lerp(sum((positions[j] for j in adjacency[i]),Vector())/len(adjacency[i]),relaxation[i]) if adjacency[i] else point for i,point in enumerate(positions)]
        for vertex,point in zip(grip.data,positions):vertex.co=point

# Adult proportion pass: preserve all limb/furniture hinges while reducing the
# oversized head and bringing palms/fingers into scale with the forearms.
head.scale=(.91,.91,.91)
head_anchor=Vector((0,.005,1.458))
head_basis=[vertex.co.copy() for vertex in headskin.data.shape_keys.key_blocks['Basis'].data]
for key in headskin.data.shape_keys.key_blocks:
    for index,vertex in enumerate(key.data):
        point=vertex.co.copy();weight=smoothstep(1.415,1.464,head_basis[index].z)
        vertex.co=point.lerp(head_anchor+(point-head_anchor)*.91,weight)
def hand_proportion(point,side):
    anchor=Vector((side*.263,-.012,.884));weight=1-smoothstep(.856,.916,point.z);delta=point-anchor
    target=anchor+Vector((delta.x*1.18,delta.y*1.18,delta.z*1.25))
    return point.lerp(target,weight)
for ob in armskin:
    side=-1 if ob.name.endswith('_L') else 1
    if ob.data.shape_keys:
        for key in ob.data.shape_keys.key_blocks:
            for vertex in key.data:vertex.co=hand_proportion(vertex.co.copy(),side)
        for vertex,source in zip(ob.data.vertices,ob.data.shape_keys.key_blocks['Basis'].data):vertex.co=source.co
    else:
        for vertex in ob.data.vertices:vertex.co=hand_proportion(vertex.co.copy(),side)
root['rig_version']=18 if SURFACE else (17 if GRIP else 16);root['wardrobe_variants']='Outfit_Casual, Outfit_Jacket, Outfit_Cardigan'
if SURFACE:root['surface_revision']=2

# Mark exports with original content metadata.
root['asset_author']='JustLife original procedural sculpture';root['forward']='Godot +Z';root['height_m']=1.76
root['hair_variants']='Hair_Crop, Hair_Bob, Hair_Curls';root['default_hair']='Hair_Crop'
# Export every variant; consumers select one hair group after instancing.
def descendants(o):
    yield o
    for child in o.children:yield from descendants(child)

# Age anatomy is authored as a continuous rest-space transformation. Each stage
# has independently placed hip, knee, shoulder and head landmarks; the child is
# about five heads tall, while the teen has a lighter, longer adolescent frame.
# Morphs and rigid facial details share the same field so expressions stay joined.
AGE_HEIGHTS={'adult':1.76,'child':1.18,'teen':1.55,'elder':1.72}
AGE_Z={
 'child':[(0,0),(.14,.09),(.548,.335),(.922,.58),(1.10,.70),(1.361,.858),(1.458,.925),(1.76,1.18)],
 'teen':[(0,0),(.14,.123),(.548,.48),(.922,.81),(1.10,.965),(1.361,1.19),(1.458,1.274),(1.76,1.55)],
 'elder':[(0,0),(.14,.14),(.548,.545),(.922,.912),(1.10,1.085),(1.361,1.335),(1.458,1.425),(1.76,1.72)]}

def interpolate_age_height(z):
    if AGE=='adult':return z
    knots=AGE_Z[AGE]
    if z<=knots[0][0]:return z*(knots[1][1]/knots[1][0])
    if z>=knots[-1][0]:return knots[-1][1]+(z-knots[-1][0])*(knots[-1][1]-knots[-2][1])/(knots[-1][0]-knots[-2][0])
    for index in range(len(knots)-1):
        a,b=knots[index:index+2]
        if z<=b[0] or index==len(knots)-2:
            t=(z-a[0])/(b[0]-a[0]);slope=(b[1]-a[1])/(b[0]-a[0])
            prev=knots[max(0,index-1)];nex=knots[min(len(knots)-1,index+2)]
            m0=(b[1]-prev[1])/(b[0]-prev[0]);m1=(nex[1]-a[1])/(nex[0]-a[0])
            return (2*t**3-3*t*t+1)*a[1]+(t**3-2*t*t+t)*m0*(b[0]-a[0])+(-2*t**3+3*t*t)*b[1]+(t**3-t*t)*m1*(b[0]-a[0])

def age_warp(point):
    if AGE=='adult':return point.copy()
    x,y,z=point;face=smoothstep(1.405,1.48,z)
    if AGE=='child':
        width=.68+.04*smoothstep(.90,1.32,z)+.135*face
        # School-age bodies have a straighter trunk and less pronounced hips.
        # Keep these adjustments medial so they do not move elbow/wrist rests.
        torso=1-smoothstep(.145,.20,abs(x))
        width+=torso*(.060*math.exp(-((z-1.13)/.13)**4)-.025*math.exp(-((z-.96)/.095)**4))
        depth=.70+.15*face
        # A shorter soft nose and full cheeks belong to the base child identity.
        nose=math.exp(-(x/.036)**4-((z-1.550)/.026)**4)*(1-smoothstep(-.100,-.080,y))
        bridge=math.exp(-(x/.025)**4-((z-1.580)/.028)**4)*(1-smoothstep(-.100,-.080,y))
        y+=.008*nose+.004*bridge
        x+=.004*math.tanh(x/.02)*math.exp(-((z-1.470)/.034)**4)*smoothstep(1.43,1.453,z)
        lower_face=smoothstep(1.410,1.445,z)*(1-smoothstep(1.598,1.616,z))*(1-smoothstep(-.045,-.005,y))
        z+=.12*(1.605-z)*lower_face+.004*nose
    elif AGE=='teen':
        width=.86+.025*smoothstep(.90,1.30,z)+.030*face;depth=.87+.045*face
    else:
        width=1.0+.018*math.exp(-((z-1.02)/.18)**2);depth=1.0
        # The mild forward posture affects the shoulder and head rests together.
        y-=.050*smoothstep(.88,1.46,z)
        front=1-smoothstep(-.075,-.035,y+.05*face)
        cheek=math.exp(-((abs(x)-.056)/.027)**2-((z-1.548)/.028)**2)*front
        jowl=math.exp(-((abs(x)-.052)/.035)**2-((z-1.49)/.024)**2)*front
        x+=math.tanh(x/.02)*(.005*jowl-.0035*cheek)
        y+=.007*cheek-.0025*jowl
        z-=.0045*cheek+.003*jowl
        # Soft nasolabial and under-eye folds are depressions in the continuous
        # facial surface, not detached dark curves laid over the skin.
        fold_x=.025+.23*(1.553-z)
        fold=math.exp(-((abs(x)-fold_x)/.005)**2-((z-1.538)/.029)**4)*front
        eye_fold=math.exp(-((abs(x)-.044)/.026)**4-((z-1.582)/.004)**2)*front
        forehead=sum(math.exp(-(x/.070)**4-((z-line)/.0033)**2) for line in [1.645,1.659])*front
        y+=.003*fold+.0030*eye_fold+.0017*forehead
    return Vector((x*width,y*depth,interpolate_age_height(z)))

def godot_vector(point):return [round(point.x,6),round(point.z,6),round(-point.y,6)]

if AGE!='adult':
    # Convert the last decorative curves before baking age rest positions. Bone
    # and attachment orientations remain identity even when the elder leans.
    for ob in list(descendants(root)):
        if ob.type=='CURVE':apply_mesh(ob)
    bpy.context.view_layer.update()
    members=list(descendants(root));old_world={ob:ob.matrix_world.copy() for ob in members}
    age_geometry={}
    for ob in members:
        if ob.type!='MESH':continue
        keys=ob.data.shape_keys.key_blocks if ob.data.shape_keys else None
        basis=keys['Basis'].data if keys else ob.data.vertices
        rounds=keys.get('Face_Round') if keys else None
        base_round=.30 if AGE=='child' else (.10 if AGE=='teen' else 0)
        source_sets=list(keys) if keys else [None]
        shape_sets=[]
        for key in source_sets:
            points=key.data if key else ob.data.vertices;aged=[]
            for index,vertex in enumerate(points):
                point=vertex.co.copy()
                if rounds:
                    delta=rounds.data[index].co-basis[index].co
                    point+=delta*base_round
                    if key and key.name=='Face_Round':point-=delta*base_round
                if key and AGE=='child' and key.name in ['Jaw_Strong','Nose_Wide','Eye_Spacing']:
                    amplitude={'Jaw_Strong':.45,'Nose_Wide':.70,'Eye_Spacing':.70}[key.name]
                    point-=(vertex.co-basis[index].co)*(1-amplitude)
                aged.append(age_warp(old_world[ob]@point))
            shape_sets.append(aged)
        age_geometry[ob]=shape_sets
    for ob in members:
        if ob.type=='EMPTY':ob.matrix_world=Matrix.Translation(age_warp(old_world[ob].translation))
    bpy.context.view_layer.update()
    rig.matrix_world=Matrix.Identity(4)
    for ob,shape_sets in age_geometry.items():
        ob.matrix_world=Matrix.Identity(4)
        if ob.data.shape_keys:
            for key,points in zip(ob.data.shape_keys.key_blocks,shape_sets):
                for vertex,point in zip(key.data,points):vertex.co=point
            for vertex,point in zip(ob.data.vertices,shape_sets[0]):vertex.co=point
        else:
            for vertex,point in zip(ob.data.vertices,shape_sets[0]):vertex.co=point
    bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name,position,parent in bone_specs:
        bone=rig.data.edit_bones[name];bone.head=age_warp(Vector(position));bone.tail=bone.head+Vector((0,0,.1));bone.roll=0
    bpy.ops.object.mode_set(mode='OBJECT');bpy.context.view_layer.update()
    if AGE=='elder':
        for material,color in [(hair,'8D8983'),(hair_highlight,'BBB6AE'),(hair_dark,'66645F')]:
            rgb=tuple(int(color[i:i+2],16)/255 for i in (0,2,4));linear=tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb)
            material.diffuse_color=(*linear,1);material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*linear,1)
        for ob in descendants(root):
            if ob.type=='MESH' and ob.name.startswith('Hair_Brow'):
                ob.data.materials.clear();ob.data.materials.append(hair_dark)
        root['default_hair_color']='#8D8983'

if AGE=='elder':
    # Fine crease ribbons hug the final aged surface. Barycentric attachment to
    # the actual head triangles carries every expression/identity displacement,
    # avoiding floating curve details when the creator changes facial shapes.
    head_keys=headskin.data.shape_keys.key_blocks
    def barycentric(point,a,b,c):
        v0=b-a;v1=c-a;v2=point-a;d00=v0.dot(v0);d01=v0.dot(v1);d11=v1.dot(v1);d20=v2.dot(v0);d21=v2.dot(v1)
        denominator=d00*d11-d01*d01
        if abs(denominator)<1e-15:return (1,0,0)
        v=(d11*d20-d01*d21)/denominator;w=(d00*d21-d01*d20)/denominator
        return (1-v-w,v,w)
    def attached_crease(name,points,width=.00060):
        vertices=[];bindings=[];n=len(points)
        for index,(x,z) in enumerate(points):
            taper=max(.06,sin(pi*index/(n-1)))**.6
            for offset in [-1,1]:
                sample=age_warp(Vector((x,-.095,z+offset*width*taper)))
                hit,co,normal,poly_index=headskin.ray_cast(Vector((sample.x,-1,sample.z)),Vector((0,1,0)))
                if not hit:return
                polygon=headskin.data.polygons[poly_index];indices=list(polygon.vertices[:3])
                weights=barycentric(co,*(headskin.data.vertices[i].co for i in indices))
                vertices.append(co+normal*.00015);bindings.append((indices,weights))
        faces=[(i*2,i*2+1,i*2+3,i*2+2) for i in range(n-1)]
        faces=[tuple(reversed(face)) if (vertices[face[1]]-vertices[face[0]]).cross(vertices[face[2]]-vertices[face[0]]).y>0 else face for face in faces]
        crease=mesh('Skin_Age_'+name,vertices,faces,ear_inner,head)
        crease.shape_key_add(name='Basis')
        for source_key in head_keys:
            if source_key.name=='Basis':continue
            target=crease.shape_key_add(name=source_key.name);target.value=0
            for index,(indices,weights) in enumerate(bindings):
                delta=sum(((source_key.data[j].co-head_keys['Basis'].data[j].co)*weight for j,weight in zip(indices,weights)),Vector())
                target.data[index].co=vertices[index]+delta
    for row,z in enumerate([1.634,1.645]):
        attached_crease('Forehead_'+str(row),[(x,z+.004*cos(pi*x/.105)) for x in [-.047+i*.094/32 for i in range(33)]],.00047)
    for side in [-1,1]:
        attached_crease('Smile_fold_'+str(side),[(side*(.025+.018*t+.004*sin(pi*t)),1.542-.038*t) for t in [i/24 for i in range(25)]],.00055)
        for row in range(2):
            attached_crease('Eye_corner_'+str(side)+'_'+str(row),[(side*(.067+.014*t),1.594-row*.003-(.004+row*.004)*t) for t in [i/16 for i in range(17)]],.00040)

if SURFACE:
    # This bounded face repair must preserve the independently accepted hand
    # sculpture and grip exactly. Voxel remeshing/decimation can choose different
    # vertices after unrelated scene changes, so reuse those frozen mesh blocks.
    baseline_name='characters_grip.blend' if AGE=='adult' else 'characters_'+AGE+'_grip.blend'
    baseline_path=os.path.join(ROOT,'art/source/grip_v3',baseline_name)
    previous_objects=set(bpy.data.objects)
    targets={side:bpy.data.objects['Skin_Arm_continuous_'+side] for side in ['L','R']}
    with bpy.data.libraries.load(baseline_path,link=False) as (available,loaded):
        loaded.objects=['Skin_Arm_continuous_L','Skin_Arm_continuous_R']
    for source in loaded.objects:
        side='L' if source.name.startswith('Skin_Arm_continuous_L') else 'R'
        target=targets[side]
        target.vertex_groups.clear()
        for group in source.vertex_groups:target.vertex_groups.new(name=group.name)
        target.data=source.data
        target.data.materials.clear();target.data.materials.append(skin)
    for ob in set(bpy.data.objects)-previous_objects:bpy.data.objects.remove(ob,do_unlink=True)

bpy.context.view_layer.update()
root['age_stage']=AGE;root['age_revision']={'adult':1,'child':3,'teen':1,'elder':3}[AGE];root['height_m']=AGE_HEIGHTS[AGE]
root['hip_height']=round(interpolate_age_height(.922),6);root['knee_height']=round(interpolate_age_height(.548),6)
root['head_height']=round(interpolate_age_height(1.458),6)
mouth_world=age_warp(Vector((0,-.0951,1.5071)))
if SURFACE:mouth_world=age_warp(head_anchor+(Vector((0,surface_mouth_y,1.512))-head_anchor)*.91)
palm_r=age_warp(Vector((.268,-.019, .816)));palm_l=age_warp(Vector((-.268,-.019,.816)))
root['mouth_anchor']=godot_vector(head.matrix_world.inverted()@mouth_world)
root['palm_anchor_l']=godot_vector(bpy.data.objects['Forearm_L'].matrix_world.inverted()@palm_l)
root['palm_anchor_r']=godot_vector(bpy.data.objects['Forearm_R'].matrix_world.inverted()@palm_r)
if GRIP:
    for side,sign in [('l',-1),('r',1)]:
        contact=age_warp(hand_proportion(Vector((sign*.267,-.036,.809)),sign))
        pivot=bpy.data.objects['Forearm_'+side.upper()]
        root['grip_anchor_'+side]=godot_vector(pivot.matrix_world.inverted()@contact)
    root['grip_morphs']='Hand_Grip_L,Hand_Grip_R'
root['bone_landmarks']=';'.join(name+':'+','.join(map(str,godot_vector(age_warp(Vector(position))))) for name,position,parent in bone_specs)

def ensure_uvs():
    for ob in bpy.data.objects:
        if ob.type!='MESH' or ob.data.uv_layers:continue
        uv=ob.data.uv_layers.new(name='SurfaceUV')
        for poly in ob.data.polygons:
            normal=poly.normal;drop=max(range(3),key=lambda axis:abs(normal[axis]));axes=[axis for axis in range(3) if axis!=drop]
            for loop_index in poly.loop_indices:
                point=ob.data.vertices[ob.data.loops[loop_index].vertex_index].co
                uv.data[loop_index].uv=((point[axes[0]]+.5)*.5,(point[axes[1]]+.5)*.5)

def reset_expressions():
    for ob in bpy.data.objects:
        if ob.type=='MESH' and ob.data.shape_keys:
            for key in ob.data.shape_keys.key_blocks:
                if key.name!='Basis':key.value=0.0

def export(path):
    reset_expressions()
    ensure_uvs()
    bpy.ops.object.select_all(action='DESELECT')
    for o in descendants(root):o.select_set(True)
    bpy.context.view_layer.objects.active=root
    final_path=os.path.join(ROOT,path)
    # Atomically publish a complete file so a running Godot editor cannot start
    # importing a partially written GLB while another character is generating.
    with tempfile.TemporaryDirectory(prefix='.justlife-export-',dir=os.path.dirname(final_path)) as temporary:
        open(os.path.join(temporary,'.gdignore'),'w').close()
        temporary_path=os.path.join(temporary,os.path.basename(final_path))
        bpy.ops.export_scene.gltf(filepath=temporary_path,export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_animations=False,export_morph=True,export_skins=True,export_extras=True,export_cameras=False,export_lights=False)
        os.replace(temporary_path,final_path)
    reset_expressions()
FILE_STEM='character_rig' if AGE=='adult' else 'character_'+AGE
BROAD_STEM='character_broad_rig' if AGE=='adult' else 'character_'+AGE+'_broad'
if GRIP and AGE!='adult':FILE_STEM+='_grip';BROAD_STEM+='_grip'
if SURFACE:
    FILE_STEM='character_'+AGE+'_surface_grip'
    BROAD_STEM='character_'+AGE+'_broad_surface_grip'
export('assets/models/'+FILE_STEM+'.glb')
# Broader shoulder/waist frame shares exact node names and clothing/appearance contract.
# Horizontal frame adjustment is baked at the mesh/object hierarchy level via a root scale.
root.scale.x=1.12
export('assets/models/'+BROAD_STEM+'.glb')
root.scale.x=1.0
# Live-camera LOD retains identical pivots and material slots.
lodmods=[];curves=[]
for ob in descendants(root):
    if ob.type=='MESH' and ob.data.shape_keys is None:
        mod=ob.modifiers.new('Live camera reduction','DECIMATE');mod.ratio=.12 if ob.name.endswith('_Cap') else .22;lodmods.append((ob,mod))
        if ob.modifiers.find('Soft skeletal deformation')>=0:
            bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_move_up(modifier=mod.name)
    elif ob.type=='CURVE':
        curves.append((ob.data,ob.data.resolution_u,ob.data.bevel_resolution));ob.data.resolution_u=2;ob.data.bevel_resolution=1
export('assets/models/'+FILE_STEM+'_lod.glb')
root.scale.x=1.12;export('assets/models/'+BROAD_STEM+'_lod.glb');root.scale.x=1.0
for ob,mod in lodmods:ob.modifiers.remove(mod)
for data,res,bev in curves:data.resolution_u=res;data.bevel_resolution=bev
# Preserve all variants in source but isolate the intended default for a studio portrait.
for group in (bob,curls,jacket,cardigan):
    for o in descendants(group):o.hide_render=True
# Render-only studio set is not included in the GLBs.
studio=empty('Studio')
floor=mat('Studio_sand','DCD7C8',.9)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.001));o=bpy.context.object;o.name='Studio_floor';o.data.materials.append(floor);parent_keep(o,studio)
world=bpy.data.worlds.new('Studio world') if not bpy.data.worlds else bpy.data.worlds[0];bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.71,.76,.72,1);world.node_tree.nodes['Background'].inputs[1].default_value=.5
for name,loc,energy,size in [('Key',(-3,-4,5),450,4),('Fill',(3,-2,3),180,3),('Rim',(1,3,4),500,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler();parent_keep(o,studio)
bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='Character_Portrait';cam.data.type='ORTHO';parent_keep(cam,studio)
def camera_view(location,target,ortho,face=False):
    ratio=AGE_HEIGHTS[AGE]/1.76
    cam.location=Vector(location)*ratio;cam.rotation_euler=(age_warp(Vector(target))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale=ortho*({'adult':1,'child':.85,'teen':.915,'elder':1}[AGE] if face else ratio)
camera_view((2.5,-6.4,2.7),(0,0,.94),2.06)
sc=bpy.context.scene;sc.camera=cam;sc.render.engine='CYCLES';sc.cycles.samples=48;sc.render.resolution_x=900;sc.render.resolution_y=1100;sc.render.resolution_percentage=100
sc.view_settings.view_transform='AgX';sc.render.image_settings.file_format='PNG';sc.render.filepath=os.path.join(ROOT,'art/'+ART_PREFIX+'_preview.png');sc.render.film_transparent=False
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art/'+SOURCE_NAME))
bpy.ops.render.render(write_still=True)
# Close portrait for checking face features, plus hairstyle variants.
camera_view((.67,-3.7,1.93),(0,-.005,1.61),.56,True);sc.render.resolution_x=900;sc.render.resolution_y=900;sc.render.filepath=os.path.join(ROOT,'art/'+ART_PREFIX+'_face.png');bpy.ops.render.render(write_still=True)
if '--preview-only' not in sys.argv:
    for style,group in [('bob',bob),('curls',curls)]:
        for gr in (crop,bob,curls):
            for ob in descendants(gr):ob.hide_render=(gr!=group)
        sc.render.resolution_x=720;sc.render.resolution_y=720;sc.cycles.samples=32
        sc.render.filepath=os.path.join(ROOT,'art/'+ART_PREFIX+'_'+style+'_preview.png');bpy.ops.render.render(write_still=True)
    for gr in (crop,bob,curls):
        for ob in descendants(gr):ob.hide_render=(gr!=crop)
    camera_view((2.5,-6.4,2.7),(0,0,.94),2.06)
    sc.render.resolution_x=760;sc.render.resolution_y=980
    for style,group in [('jacket',jacket),('cardigan',cardigan)]:
        for gr in (casual,jacket,cardigan):
            for ob in descendants(gr):ob.hide_render=(gr!=group)
        sc.render.filepath=os.path.join(ROOT,'art/'+ART_PREFIX+'_'+style+'.png');bpy.ops.render.render(write_still=True)
    # Deformation QA renders: complete skin and cloth remain continuous under joint motion.
    for gr in (casual,jacket,cardigan):
        for ob in descendants(gr):ob.hide_render=(gr!=casual)
    def pose_joints(values):
        for name,_,_ in bone_specs:
            rig.pose.bones[name].rotation_mode='XYZ';rig.pose.bones[name].rotation_euler=(0,0,0)
            if name not in ['Root','Spine']:bpy.data.objects[name].rotation_euler=(0,0,0)
        for name,rot in values.items():
            rig.pose.bones[name].rotation_euler=rot
            if name not in ['Root','Spine']:bpy.data.objects[name].rotation_euler=rot
    pose_joints({'Leg_L':(-.38,0,0),'Leg_R':(.33,0,0),'Shin_R':(.48,0,0),'Arm_L':(.22,0,0),'Arm_R':(-.22,0,0),'Forearm_R':(-.22,0,0),'Head':(.02,0,.08)})
    sc.render.filepath=os.path.join(ROOT,'art/'+ART_PREFIX+'_walk.png');bpy.ops.render.render(write_still=True)
    pose_joints({'Leg_L':(-pi/2,0,0),'Leg_R':(-pi/2,0,0),'Shin_L':(pi/2,0,0),'Shin_R':(pi/2,0,0),'Arm_L':(-.30,0,0),'Arm_R':(-.30,0,0),'Forearm_L':(-1.0,0,0),'Forearm_R':(-1.0,0,0)})
    root.location.z=-(root['hip_height']-root['knee_height']+.016)
    pants.data.shape_keys.key_blocks['Sit'].value=1
    sc.render.filepath=os.path.join(ROOT,'art/'+ART_PREFIX+'_sit.png');bpy.ops.render.render(write_still=True)
    root.location.z=0;pants.data.shape_keys.key_blocks['Sit'].value=0;pose_joints({})
    # Identity QA uses fixed lighting and camera so shape comparisons remain meaningful.
    camera_view((.12,-3.7,1.82),(0,-.005,1.60),.46,True)
    sc.render.resolution_x=620;sc.render.resolution_y=620;sc.cycles.samples=24
    def identity_pose(values):
        reset_expressions()
        for ob in descendants(root):
            if ob.type=='MESH' and ob.data.shape_keys:
                for key in ob.data.shape_keys.key_blocks:
                    if key.name!='Basis':key.value=values.get(key.name,0)
    identity_presets=[('neutral',{})]+[(name,{name:1}) for name in identity_names]+[('all_extremes',{name:1 for name in identity_names}),('extremes_blink',dict({name:1 for name in identity_names},Blink=1)),('extremes_smile',dict({name:1 for name in identity_names},Smile=1))]
    identity_prefix=ART_PREFIX+'_identity_' if GRIP else ('character_identity_' if AGE=='adult' else 'character_'+AGE+'_identity_')
    for label,values in identity_presets:
        identity_pose(values);sc.render.filepath=os.path.join(ROOT,'art/'+identity_prefix+label+'.png');bpy.ops.render.render(write_still=True)
    identity_pose({name:1 for name in identity_names})
    camera_view((1.25,-3.7,1.88),(0,-.005,1.60),.46,True)
    for label,group in [('Crop',crop),('Bob',bob),('Curls',curls)]:
        for gr in (crop,bob,curls):
            for ob in descendants(gr):ob.hide_render=(gr!=group)
        # Match the small live silhouette adjustment used for a broad lower face.
        if group==bob:group.scale.x=1.07
        sc.render.filepath=os.path.join(ROOT,'art/'+identity_prefix+label+'_threequarter.png');bpy.ops.render.render(write_still=True)
        group.scale.x=1
    identity_pose({})
if '--promote' in sys.argv:
    standard_stem='character' if AGE=='adult' else 'character_'+AGE
    copies=[('assets/models/'+source+suffix+'.glb','assets/models/'+target+suffix+'.glb') for source,target in [(FILE_STEM,standard_stem),(BROAD_STEM,standard_stem+'_broad')] for suffix in ['', '_lod']]
    copies.append(('art/'+SOURCE_NAME,'art/characters'+('' if AGE=='adult' else '_'+AGE)+'.blend'))
    for source,target in copies:
        if source==target:continue
        destination=os.path.join(ROOT,target)
        with tempfile.TemporaryDirectory(prefix='.justlife-promote-',dir=os.path.dirname(destination)) as temporary:
            open(os.path.join(temporary,'.gdignore'),'w').close()
            staged=os.path.join(temporary,os.path.basename(target));shutil.copy2(os.path.join(ROOT,source),staged)
            os.replace(staged,destination)
print('JUSTLIFE CHARACTER EXPORT COMPLETE')
