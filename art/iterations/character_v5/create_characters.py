"""JustLife original character asset generator. Blender 5.x, background safe.
Run: blender --background --python tools/create_characters.py
"""
import bpy, math, os, random
from mathutils import Vector
from math import sin, cos, pi
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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
    loft('Top_Sleeve_'+side,[(1.14,.047,.055,.009,s*.227),(1.155,.055,.061,.008,s*.225),(1.25,.057,.064,.005,s*.211),(1.345,.065,.064,.004,s*.172),(1.383,.045,.048,.005,s*.142)],top,arm,24,2)
    cuff=[(s*.227+.049*sin(2*pi*i/32),.009-.057*cos(2*pi*i/32),1.154) for i in range(33)];bezline('Top_Sleeve_cuff',cuff,.004,top_inner,arm)
    fore=empty('Forearm_'+side,(s*.244,.007,1.087),arm)
    loft('Skin_Forearm_'+side,[(.827,.023,.024,-.013,s*.264),(.884,.025,.026,-.008,s*.262),(.951,.031,.031,.005,s*.257),(1.025,.034,.033,.01,s*.252),(1.09,.035,.035,.008,s*.244),(1.154,.040,.043,.004,s*.230),(1.194,.041,.045,.003,s*.222)],skin,fore,24,2)
    # Palm and individual tapering fingers; small nails are intentionally subtle.
    palm=uv('Skin_Palm_'+side,(s*.267,-.019,.825),(.031,.023,.045),skin,fore)
    for i in range(4):
        x=s*(.246+i*.012); length=[.045,.056,.052,.041][i]
        tube('Skin_Finger_'+side+str(i),[(x,-.021,.808),(x+s*.003,-.026,.79),(x+s*.004,-.03,.808-length)], [.0078,.0075,.0055],skin,fore,10,2)
    tube('Skin_Thumb_'+side,[(s*.244,-.017,.845),(s*.227,-.029,.824),(s*.229,-.038,.804)],[.012,.009,.006],skin,fore,12,2)
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
loft('Skin_Nose',[(1.538,.012,.005,-.112,0),(1.543,.024,.01,-.117,0),(1.559,.024,.015,-.122,0),(1.570,.018,.014,-.120,0),(1.586,.012,.012,-.111,0),(1.614,.010,.006,-.101,0),(1.627,.009,.003,-.10,0)],skin,head,20,2)
for s in [-1,1]:
    uv('Skin_Nostril_wing',(s*.018,-.120,1.550),(.009,.011,.006),skin,head,24,12)
    uv('Nose_Nostril',(s*.014,-.128,1.545),(.005,.004,.0018),nostril,head,20,10)
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
    nr=12;nt=48; vs=[]
    for i in range(nr):
        for j in range(nt):
            a=2*pi*j/nt; frontness=(cos(a)+1)/2; limit=back*(1-frontness)+front*frontness
            phi=.012+(limit-.012)*i/(nr-1); wave=.003*sin(a*10+phi*4)*sin(phi)
            vs.append(((.119*wide+wave)*sin(phi)*sin(a),.012-(.114+wave)*sin(phi)*cos(a),1.623+.137*height*cos(phi)+.010*sin(a-.4)*sin(phi)**2))
    fs=[]
    for i in range(nr-1):
        for j in range(nt):fs.append((i*nt+j,i*nt+(j+1)%nt,(i+1)*nt+(j+1)%nt,(i+1)*nt+j))
    o=mesh(name,vs,fs,hair,parent,1); solid=o.modifiers.new('Hair shell','SOLIDIFY');solid.thickness=.007;return o
crop=empty('Hair_Crop',(0,0,0),head)
haircap('Hair_Crop_Cap',crop,1.94,1.15)
# broad swept fringe locks, with dark parted roots and thin sculpted highlights
for i in range(9):
    d=i/8
    pts=[(.067-.008*d,-.027+.019*d,1.746-.013*d),(.045-.022*d,-.086,1.755-.008*d),(-.008-.048*d,-.110-.004*d,1.736-.026*d),(-.073-.023*d,-.081-.016*d,1.671-.016*d)]
    tube('Hair_Crop_Swept_lock',pts,[.017,.023,.019,.002],hair,crop,10,2,flat=.55)
    bezline('Hair_Crop_Strand',[(p[0]-.003,p[1]-.009,p[2]+.002) for p in pts],.0011,hair_highlight,crop)
for i in range(6):
    t=i/5
    pts=[(.075-.034*t,-.006+.03*t,1.733),(.039-.088*t,.0+.054*t,1.764-.013*t),(-.062-.035*t,.033+.035*t,1.71-.012*t),(-.101+.026*t,.075+.024*t,1.636)]
    tube('Hair_Crop_Crown',pts,[.017,.022,.025,.004],hair,crop,12,2,flat=.64)
for s in [-1,1]:tube('Hair_Crop_Sideburn',[(s*.105,-.036,1.682),(s*.117,-.022,1.637),(s*.111,-.014,1.602)],[.019,.014,.004],hair,crop,10,2,.6)
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
# Mark exports with original content metadata.
root['asset_author']='JustLife original procedural sculpture';root['forward']='Godot +Z';root['height_m']=1.79
root['hair_variants']='Hair_Crop, Hair_Bob, Hair_Curls';root['default_hair']='Hair_Crop'
# Export every variant; consumers select one hair group after instancing.
def descendants(o):
    yield o
    for child in o.children:yield from descendants(child)
def export(path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in descendants(root):o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
export('assets/models/character.glb')
# Broader shoulder/waist frame shares exact node names and clothing/appearance contract.
# Horizontal frame adjustment is baked at the mesh/object hierarchy level via a root scale.
root.scale.x=1.12
export('assets/models/character_broad.glb')
root.scale.x=1.0
# Live-camera LOD retains identical pivots and material slots.
lodmods=[];curves=[]
for ob in descendants(root):
    if ob.type=='MESH':
        mod=ob.modifiers.new('Live camera reduction','DECIMATE');mod.ratio=.22;lodmods.append((ob,mod))
    elif ob.type=='CURVE':
        curves.append((ob.data,ob.data.resolution_u,ob.data.bevel_resolution));ob.data.resolution_u=2;ob.data.bevel_resolution=1
export('assets/models/character_lod.glb')
root.scale.x=1.12;export('assets/models/character_broad_lod.glb');root.scale.x=1.0
for ob,mod in lodmods:ob.modifiers.remove(mod)
for data,res,bev in curves:data.resolution_u=res;data.bevel_resolution=bev
# Preserve all variants in source but isolate the intended default for a studio portrait.
for group in (bob,curls):
    for o in descendants(group):o.hide_render=True
# Render-only studio set is not included in the GLBs.
studio=empty('Studio')
floor=mat('Studio_sand','DCD7C8',.9)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.001));o=bpy.context.object;o.name='Studio_floor';o.data.materials.append(floor);parent_keep(o,studio)
world=bpy.data.worlds.new('Studio world') if not bpy.data.worlds else bpy.data.worlds[0];bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.71,.76,.72,1);world.node_tree.nodes['Background'].inputs[1].default_value=.5
for name,loc,energy,size in [('Key',(-3,-4,5),450,4),('Fill',(3,-2,3),180,3),('Rim',(1,3,4),500,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler();parent_keep(o,studio)
bpy.ops.object.camera_add(location=(2.5,-6.4,2.7));cam=bpy.context.object;cam.name='Character_Portrait';cam.rotation_euler=(Vector((0,0,.94))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.06;parent_keep(cam,studio)
sc=bpy.context.scene;sc.camera=cam;sc.render.engine='CYCLES';sc.cycles.samples=48;sc.render.resolution_x=900;sc.render.resolution_y=1100;sc.render.resolution_percentage=100
sc.view_settings.view_transform='AgX';sc.render.image_settings.file_format='PNG';sc.render.filepath=os.path.join(ROOT,'art/character_preview.png');sc.render.film_transparent=False
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art/characters.blend'))
bpy.ops.render.render(write_still=True)
# Close portrait for checking face features, plus hairstyle variants.
cam.location=(.67,-3.7,1.93);cam.rotation_euler=(Vector((0,-.005,1.61))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.56;sc.render.resolution_x=900;sc.render.resolution_y=900;sc.render.filepath=os.path.join(ROOT,'art/character_face.png');bpy.ops.render.render(write_still=True)
for style,group in [('bob',bob),('curls',curls)]:
    for gr in (crop,bob,curls):
        for ob in descendants(gr):ob.hide_render=(gr!=group)
    sc.render.resolution_x=720;sc.render.resolution_y=720;sc.cycles.samples=32
    sc.render.filepath=os.path.join(ROOT,'art/character_'+style+'_preview.png');bpy.ops.render.render(write_still=True)
print('JUSTLIFE CHARACTER EXPORT COMPLETE')
