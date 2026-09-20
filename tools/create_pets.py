"""Original JustLife pets and pet accessories. Run: blender -b --python tools/create_pets.py.

Adds the two household animals the game walks around the home - a cat and a
dog - plus the twin feeding bowl, the climbing tree and the garden kennel.
Coordinates are Godot metres: x right, y up, z toward the front of the pet, so
both animals look down +z and stand on y=0.  Head and Tail carry their object
origin at the joint the game turns them about; every part is built from Blender
primitives with flat Principled materials.
"""
import bpy, bmesh, math, pathlib, argparse, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name); m.diffuse_color=(*linear,1)
    m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=m.diffuse_color
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    if emit:
        p.inputs['Emission Color'].default_value=m.diffuse_color; p.inputs['Emission Strength'].default_value=emit
    M[name]=m; return m
# The six pet materials are replaced by name at runtime, so these are placeholders.
for n,h in [('Fur','C9A87C'),('Fur_Mark','F4ECE0'),('Nose','C98A8A'),('Eyes','41594B'),('Paw_Pads','C99A9A'),('Collar','BE5A4B'),('Wood','8A6238'),('Ceramic','E6E0D2'),('Fabric','9AA7BE'),('Accent','C97C4E'),('Water','7FB6C6'),('Paint','7FA8C6'),('Paint_Mark','F4F1E6'),('Leash','6E7C8A')]: mat(n,h)
for n,r,m in [('Ceramic',.30,0),('Nose',.45,0),('Eyes',.22,0),('Water',.12,0),('Collar',.55,0),('Paw_Pads',.55,0),('Leash',.60,0)]:
    M[n].node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=r
active=[]
def xyz(p): return (p[0],-p[2],p[1])
def finish(o,n,m):
    o.name=n; o.data.materials.append(M[m]); active.append(o); return o
def box(n,p,s,m,bevel=.03):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p)); o=bpy.context.object; o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL'); mod.width=bevel; mod.segments=3
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return finish(o,n,m)
def ell(n,p,s,m,seg=20,ring=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=ring,location=xyz(p)); o=bpy.context.object; o.scale=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def cyl(n,p,r,h,m,top=None,axis='Y',bevel=.012):
    bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    if axis=='X':o.rotation_euler=(0,math.pi/2,0)
    elif axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    if bevel:
        mod=o.modifiers.new('Rounded rims','BEVEL'); mod.width=bevel; mod.segments=3; mod.angle_limit=.9
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def rod(n,a,b,r,m):
    av,bv=Vector(xyz(a)),Vector(xyz(b)); d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return finish(o,n,m)
def torus(n,p,major,minor,m,axis='Y',bevel=0):
    bpy.ops.mesh.primitive_torus_add(major_segments=36,minor_segments=10,major_radius=major,minor_radius=minor,location=xyz(p)); o=bpy.context.object
    if axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    if bevel:
        mod=o.modifiers.new('Rounded rim','BEVEL'); mod.width=bevel; mod.segments=3
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def prism(n,p,s,m):
    # Gable ends and pitched roofs: a solid triangular prism, apex up, running along z.
    w,d=s[0]/2,s[2]/2; h=s[1]
    verts=[(-w,0,-d),(w,0,-d),(0,h,-d),(-w,0,d),(w,0,d),(0,h,d)]
    faces=[(0,1,2),(3,5,4),(0,2,5,3),(1,4,5,2),(0,3,4,1)]
    me=bpy.data.meshes.new(n); me.from_pydata([xyz((p[0]+x,p[1]+y,p[2]+z)) for x,y,z in verts],[],faces); me.validate(); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.new(n,me); bpy.context.collection.objects.link(o)
    return finish(o,n,m)
def merge(o,others,n):
    # Join primitives into one object, so a pivoted part keeps its markings with it.
    group=[o]+[x for x in others]
    for x in group:
        if x in active:active.remove(x)
    bpy.ops.object.select_all(action='DESELECT')
    for x in group:x.select_set(True)
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.join()
    j=bpy.context.object; j.name=n; active.append(j); return j
def pivot(o,world_point):
    # Move the object origin onto a Godot-space joint, leaving the geometry where it is.
    scene=bpy.context.scene; scene.cursor.location=xyz(world_point)
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True); bpy.context.view_layer.objects.active=o
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    scene.cursor.location=(0,0,0); return o
def attach(o,holder):
    # Parent without moving, so ears ride along when the game turns the head.
    o.parent=holder; o.matrix_parent_inverse=holder.matrix_world.inverted(); return o
def leg(n,hip,foot,r,paw):
    # A tapered limb and its marked paw joined into one part, pivoted at the hip.
    bot=foot[1]+paw[1]*.6
    limb=cyl('Leg limb',(hip[0],(hip[1]+bot)/2,hip[2]),r,hip[1]-bot,'Fur',top=r*.72,bevel=r*.30)
    foot_pad=ell('Paw',(foot[0],paw[1],foot[2]+paw[2]*.30),paw,'Fur_Mark',14,10)
    sole=ell('Paw pad',(foot[0],paw[1]*.42,foot[2]+paw[2]*.62),(paw[0]*.62,paw[1]*.42,paw[2]*.62),'Paw_Pads',10,8)
    return pivot(merge(limb,[foot_pad,sole],n),hip)
def tail(n,points,radii,base):
    # A tapering tail of segments and ball joints, joined into one part; the final
    # segment takes the marking colour so the tip reads as a different shade.
    segs=[]; last=len(points)-2
    for i in range(len(points)-1):
        m='Fur_Mark' if i==last else 'Fur'
        segs.append(rod('Tail segment',points[i],points[i+1],(radii[i]+radii[i+1])/2,m))
        if i<last:segs.append(ell('Tail joint',points[i+1],(radii[i+1],radii[i+1],radii[i+1]),m,12,8))
    return pivot(merge(segs[0],segs[1:],n),base)

# ---------------------------------------------------------------- Pets
def pet_cat():
    # A slim cat: 0.28 m shoulder, upright pointed ears, tail carried level behind.
    body=ell('Body',(0,.200,-.055),(.085,.080,.225),'Fur')
    merge(body,[ell('Neck',(0,.200,.150),(.062,.070,.075),'Fur')],'Body')
    ell('Chest mark',(0,.215,.125),(.052,.058,.040),'Fur_Mark',14,10)
    head=ell('Head',(0,.245,.251),(.075,.070,.075),'Fur')
    head=merge(head,[ell('Muzzle',(0,.222,.311),(.036,.030,.033),'Fur_Mark',14,10),
                     ell('Nose',(0,.234,.339),(.015,.012,.011),'Nose',10,8),
                     ell('Eye_L',(-.042,.262,.303),(.018,.020,.014),'Eyes',12,8),
                     ell('Eye_R',(.042,.262,.303),(.018,.020,.014),'Eyes',12,8)],'Head')
    pivot(head,(0,.230,.191))
    for side,x in (('L',-.042),('R',.042)):
        ear=cyl('Ear',(x,.320,.261),.026,.060,'Fur',top=.004,bevel=.008)
        ear.rotation_euler[1]=.22 if x>0 else -.22
        inner=cyl('Ear inner',(x*.88,.320,.275),.014,.040,'Fur_Mark',top=.002,bevel=.005)
        inner.rotation_euler[1]=ear.rotation_euler[1]
        attach(pivot(merge(ear,[inner],f'Ear_{side}'),(x,.288,.261)),head)
    for n,x,z,hip in (('Leg_FL',-.052,.100,.150),('Leg_FR',.052,.100,.150),('Leg_BL',-.055,-.190,.160),('Leg_BR',.055,-.190,.160)):
        leg(n,(x,hip,z),(x,0,z),.028,(.033,.023,.036))
    tail('Tail',[(0,.230,-.245),(0,.295,-.295),(0,.335,-.352),(0,.345,-.430),(0,.338,-.500)],[.019,.016,.013,.011,.009],(0,.230,-.245))
    torus('Collar',(0,.245,.190),.058,.010,'Collar',axis='Z')
    # A leash clip on the collar, so the collar a player recolours also reads as
    # the thing a leash attaches to.
    ell('Collar tag',(0,.196,.246),(.012,.012,.010),'Collar',10,8)
    # A short trailing leash loop, so a leash colour is something a player can
    # actually see on the pet.
    torus('Leash',(0,.170,.300),.055,.008,'Leash',axis='X',bevel=.004)


def pet_dog():
    # A sturdier dog: 0.50 m shoulder, heavier chest than the cat, long muzzle,
    # folded floppy ears and a sweeping tail.
    body=ell('Body',(0,.365,-.090),(.115,.130,.270),'Fur')
    merge(body,[ell('Neck',(0,.410,.230),(.092,.098,.090),'Fur'),
                ell('Chest',(0,.335,.120),(.128,.145,.145),'Fur')],'Body')
    ell('Chest mark',(0,.310,.225),(.075,.085,.035),'Fur_Mark',16,10)
    head=ell('Head',(0,.475,.358),(.100,.098,.095),'Fur')
    head=merge(head,[ell('Muzzle',(0,.442,.468),(.052,.048,.078),'Fur_Mark',16,10),
                     ell('Nose',(0,.462,.533),(.024,.019,.017),'Nose',10,8),
                     ell('Eye_L',(-.055,.500,.418),(.020,.022,.016),'Eyes',12,8),
                     ell('Eye_R',(.055,.500,.418),(.020,.022,.016),'Eyes',12,8)],'Head')
    pivot(head,(0,.450,.305))
    for side,x in (('L',-.106),('R',.106)):
        ear=ell('Ear',(x,.445,.338),(.026,.072,.048),'Fur',16,10)
        ear.rotation_euler[1]=.30 if x>0 else -.30
        inner=ell('Ear inner',(x,.445,.371),(.016,.050,.016),'Fur_Mark',12,8)
        inner.rotation_euler[1]=ear.rotation_euler[1]
        attach(pivot(merge(ear,[inner],f'Ear_{side}'),(x*.95,.500,.343)),head)
    for n,x,z,hip in (('Leg_FL',-.075,.115,.280),('Leg_FR',.075,.115,.280),('Leg_BL',-.078,-.255,.280),('Leg_BR',.078,-.255,.280)):
        leg(n,(x,hip,z),(x,0,z),.045,(.050,.030,.058))
    tail('Tail',[(0,.430,-.300),(0,.425,-.372),(0,.400,-.436),(0,.372,-.492),(0,.362,-.548)],[.030,.025,.021,.018,.015],(0,.430,-.300))
    torus('Collar',(0,.410,.275),.096,.013,'Collar',axis='Z')
    ell('Collar tag',(0,.330,.345),(.018,.018,.014),'Collar',10,8)
    torus('Leash',(0,.285,.430),.085,.011,'Leash',axis='X',bevel=.005)

# ---------------------------------------------------------------- Accessories
def pet_bowl():
    # One compact feeding station 0.40 x 0.32 m and 0.12 m high: a wooden tray
    # with a fabric liner, the food bowl with a little kibble, and the smaller
    # paired water bowl.
    box('Bowl tray',(0,.016,0),(.40,.032,.32),'Wood',.014)
    box('Tray liner',(0,.033,0),(.36,.014,.28),'Fabric',.010)
    cyl('Food bowl',(-.095,.076,0),.061,.075,'Ceramic',top=.085,bevel=.008)
    torus('Food bowl rim',(-.095,.112,0),.085,.008,'Accent')
    ell('Kibble',(-.095,.108,0),(.066,.020,.066),'Accent',16,10)
    for i in range(3):
        a=i*2.1
        ell('Kibble bit',(-.095+math.sin(a)*.036,.118,math.cos(a)*.036),(.014,.010,.014),'Accent',10,8)
    cyl('Water bowl',(.105,.076,0),.047,.075,'Ceramic',top=.065,bevel=.008)
    torus('Water bowl rim',(.105,.112,0),.065,.008,'Accent')
    cyl('Water',(.105,.108,0),.052,.010,'Water',bevel=.004)
def cat_tree():
    # Base, wrapped post, top platform and a ground-level cubby with an open
    # front; 0.55 x 0.55 m footprint and 1.25 m to the platform cushion.
    box('Tree base',(0,.030,0),(.55,.060,.55),'Wood',.020)
    cyl('Tree post',(0,.610,-.160),.055,1.140,'Wood')
    for y in (.300,.620,.940):torus('Post wrap',(0,y,-.160),.062,.014,'Fabric')
    box('Cubby side',(-.165,.290,.100),(.030,.460,.360),'Wood',.010)
    box('Cubby side',(.165,.290,.100),(.030,.460,.360),'Wood',.010)
    box('Cubby back',(0,.290,-.065),(.360,.460,.030),'Wood',.010)
    box('Cubby roof',(0,.510,.095),(.360,.030,.350),'Wood',.010)
    box('Cubby panel',(-.130,.290,.265),(.100,.460,.030),'Wood',.010)
    box('Cubby panel',(.130,.290,.265),(.100,.460,.030),'Wood',.010)
    box('Cubby lintel',(0,.388,.265),(.360,.215,.030),'Wood',.010)
    box('Cubby pad',(0,.075,.100),(.300,.030,.300),'Fabric',.010)
    box('Top platform',(0,1.170,-.110),(.500,.060,.330),'Wood',.015)
    box('Platform cushion',(0,1.225,-.110),(.440,.050,.270),'Fabric',.015)
    rod('Toy string',(.180,1.140,-.170),(.180,.960,-.170),.006,'Accent')
    ell('Toy ball',(.180,.940,-.170),(.035,.035,.035),'Accent',14,10)
    cyl('Water dish',(-.225,.075,-.225),.045,.030,'Ceramic')
def kennel():
    # A gable-roofed dog house, 0.95 x 1.10 m footprint and 0.85 m to the ridge:
    # plank walls around an open doorway, a bed and a dish inside.
    box('Kennel floor',(0,.025,0),(.950,.050,1.100),'Wood',.010)
    box('Kennel back wall',(0,.325,-.525),(.950,.550,.050),'Wood',.010)
    box('Kennel side wall',(-.450,.325,0),(.050,.550,1.100),'Wood',.010)
    box('Kennel side wall',(.450,.325,0),(.050,.550,1.100),'Wood',.010)
    box('Kennel panel',(-.315,.325,.525),(.270,.550,.050),'Wood',.010)
    box('Kennel panel',(.315,.325,.525),(.270,.550,.050),'Wood',.010)
    box('Kennel lintel',(0,.540,.525),(.360,.120,.050),'Wood',.010)
    prism('Kennel roof',(0,.600,0),(.950,.250,1.100),'Wood')
    box('Door jamb',(-.185,.265,.540),(.030,.430,.020),'Accent',.006)
    box('Door jamb',(.185,.265,.540),(.030,.430,.020),'Accent',.006)
    box('Door head',(0,.495,.540),(.400,.030,.020),'Accent',.006)
    box('Kennel sign',(.315,.510,.540),(.170,.060,.010),'Accent',.004)
    box('Kennel bed',(0,.090,-.130),(.720,.080,.720),'Fabric',.030)
    cyl('Kennel dish',(-.330,.065,-.350),.050,.035,'Ceramic',bevel=.006)

catalog={'pet_cat':pet_cat,'pet_dog':pet_dog,'pet_bowl':pet_bowl,'cat_tree':cat_tree,'kennel':kennel}
def pet_bed_cat():
    # An indoor cat bed: a low oval basket with a raised rim and a cushion, so a
    # cat has its own place to curl up inside the house. 0.62 x 0.52 m.
    ell('Cat bed base',(0,.055,0),(.310,.055,.260),'Wood',24,14)
    ell('Cat bed cushion',(0,.098,0),(.278,.048,.228),'Fabric',24,14)
    ell('Cat bed bolster',(0,.128,0),(.300,.062,.250),'Fabric',24,14)
    ell('Cat bed hollow',(0,.150,0),(.230,.050,.180),'Accent',24,14)
    for i in range(8):
        a=i*math.tau/8.0
        ell('Cat bed tuft',(math.sin(a)*.235,.150,math.cos(a)*.190),(.022,.030,.022),'Accent',10,8)
def pet_bed_dog():
    # An indoor dog bed: the same idea, wider and with a higher back so a dog can
    # lean against it. 0.92 x 0.68 m.
    ell('Dog bed base',(0,.060,0),(.460,.060,.340),'Wood',24,14)
    ell('Dog bed cushion',(0,.108,0),(.420,.056,.300),'Fabric',24,14)
    ell('Dog bed bolster',(0,.150,0),(.446,.075,.326),'Fabric',24,14)
    ell('Dog bed hollow',(0,.178,0),(.352,.060,.236),'Accent',24,14)
    box('Dog bed back',(0,.215,-.290),(.720,.200,.090),'Fabric',.030)
    for i in range(10):
        a=i*math.tau/10.0
        ell('Dog bed tuft',(math.sin(a)*.370,.178,math.cos(a)*.268),(.026,.034,.026),'Accent',10,8)
def pet_toy_cat():
    # A cat toy: a fabric mouse on a cord with a little bell, 0.18 m.
    ell('Cat toy body',(0,.055,0),(.070,.045,.048),'Fabric',16,10)
    ell('Cat toy ear',(-.026,.096,.010),(.020,.026,.008),'Fabric',10,8)
    ell('Cat toy ear',(.026,.096,.010),(.020,.026,.008),'Fabric',10,8)
    rod('Cat toy cord',(0,.075,-.055),(0,.130,-.115),.004,'Accent')
    ell('Cat toy bell',(0,.132,-.126),(.020,.020,.020),'Accent',12,8)
    rod('Cat toy tail',(.030,.050,-.040),(.085,.038,-.090),.004,'Accent')
def pet_toy_dog():
    # A dog toy: a knotted rope bone with two solid ends, 0.26 m.
    cyl('Dog toy shaft',(0,.055,0),.022,.150,'Accent',axis='Z',bevel=.008)
    for z in (-.088,.088):
        ell('Dog toy knob',(0,.055,z),(.062,.052,.048),'Accent',16,10)
    for z in (-.045,.045):
        torus('Dog toy knot',(0,.055,z),.030,.012,'Fabric',axis='Z')
def cat_toy_box():
    # A low open box of six cat toys, painted with a cat paw print on the front.
    box('Box floor',(0,.021,0),(.560,.042,.400),'Wood',.012)
    box('Box front',(0,.185,.190),(.560,.330,.030),'Paint',.010)
    box('Box back',(0,.185,-.190),(.560,.330,.030),'Paint',.010)
    box('Box left',(-.265,.185,0),(.030,.330,.400),'Paint',.010)
    box('Box right',(.265,.185,0),(.030,.330,.400),'Paint',.010)
    # The cat paw print: one large pad and four toe beans, proud of the front face.
    ell('Paw pad',(0,.170,.213),(.075,.052,.014),'Paint_Mark',18,12)
    for i in range(4):
        a=math.pi*(.18+.24*i)
        ell('Paw toe',(math.cos(a)*.098,.196+(i%2)*.004,.213),(.026,.028,.012),'Paint_Mark',12,8)
    _six_toys('cat',.560,.400)
def dog_toy_box():
    # The same box for a dog's six toys, painted with a dog paw print: a broader
    # pad with taller, blunter toes so the two boxes read apart at a glance.
    box('Box floor',(0,.021,0),(.560,.042,.400),'Wood',.012)
    box('Box front',(0,.185,.190),(.560,.330,.030),'Paint',.010)
    box('Box back',(0,.185,-.190),(.560,.330,.030),'Paint',.010)
    box('Box left',(-.265,.185,0),(.030,.330,.400),'Paint',.010)
    box('Box right',(.265,.185,0),(.030,.330,.400),'Paint',.010)
    ell('Paw pad',(0,.168,.213),(.088,.058,.014),'Paint_Mark',18,12)
    for i in range(4):
        a=math.pi*(.16+.24*i)
        ell('Paw toe',(math.cos(a)*.108,.200+(i%2)*.004,.216),(.032,.036,.014),'Paint_Mark',12,8)
    _six_toys('dog',.560,.400)
def _six_toys(kind, width, depth):
    # Six toys sitting in the box, three across and two deep, so a full box
    # reads as a full box from any angle.
    for row in range(2):
        for col in range(3):
            x=-.170+col*.170
            z=-.100+row*.200
            if kind=='cat':
                ell('Toy pelt',(x,.105,z),(.048,.030,.034),'Accent',12,8)
                ell('Toy pelt ear',(x-.018,.132,z),(.014,.018,.006),'Fabric',10,6)
                ell('Toy pelt ear',(x+.018,.132,z),(.014,.018,.006),'Fabric',10,6)
                torus('Toy feather',(x,.160,z),.020,.005,'Fabric')
            else:
                cyl('Toy bone',(x,.100,z),.016,.100,'Accent',axis='X',bevel=.006)
                for dx in (-.058,.058):
                    ell('Toy bone knob',(x+dx,.100,z),(.036,.032,.030),'Accent',12,8)
catalog={'pet_cat':pet_cat,'pet_dog':pet_dog,'pet_bowl':pet_bowl,'cat_tree':cat_tree,'kennel':kennel,
         'pet_bed_cat':pet_bed_cat,'pet_bed_dog':pet_bed_dog,
         'pet_toy_cat':pet_toy_cat,'pet_toy_dog':pet_toy_dog,
         'cat_toy_box':cat_toy_box,'dog_toy_box':dog_toy_box}
def gpt(w): return (w.x,w.z,-w.y)
def gverts(o):
    # Vertices of the evaluated mesh, so the figures match what export_apply writes.
    e=o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [gpt(e.matrix_world@v.co) for v in e.data.vertices]
def span(objs,i):
    v=[p[i] for o in objs if o.type=='MESH' for p in gverts(o)]; return min(v),max(v)
def measure(objs): return tuple(round(b-a,3) for a,b in (span(objs,i) for i in range(3)))
def report(name,objs):
    parts={o.name:o for o in objs}
    y0,y1=span(objs,1)
    line=f'MODEL {name}: {len(objs)} parts, size {measure(objs)} (x,y,z) m, floor {y0:+.3f}'
    if name in ('pet_cat','pet_dog'):
        # Contract asks for a shoulder height, a nose-to-tail-base length and a tail
        # length. Both pets face +z, so the nose is the head's frontmost point and
        # the tail hangs behind at negative z; its length is measured from its pivot.
        shoulder=max(p[1] for p in gverts(parts['Body']))
        nose=max(p[2] for p in gverts(parts['Head']))
        base=gpt(parts['Tail'].matrix_world.translation)
        reach=max((Vector(p)-Vector(base)).length for p in gverts(parts['Tail']))
        line+=f', shoulder {shoulder:.3f} m, nose-to-tail-base {nose-base[2]:.3f} m, tail pivot-to-tip {reach:.3f} m'
        line+=f", Head origin {gpt(parts['Head'].matrix_world.translation)}, Tail origin {base}"
    print(line)
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/pets.blend')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if args.only:catalog={args.only:catalog[args.only]}
for idx,(name,fn) in enumerate(catalog.items()):
    active=[]; fn()
    root=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(root)
    for o in active:
        if o.parent is None:o.parent=root
    bpy.ops.object.select_all(action='DESELECT'); root.select_set(True)
    for o in active:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models'/f'{name}.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    # Parented parts (ears, tails) only carry a fresh matrix_world once the
    # dependency graph has run, so refresh it before measuring.
    bpy.context.view_layer.update()
    report(name,active)
    # Blender names are unique per file, so prefix the parked copy: the next pet
    # must be free to claim Body/Head/Tail again for its own export.
    for o in active:o.name=f'{name} {o.name}'
    root.location=((idx%6)*4,(idx//6)*4,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_PETS_COMPLETE', len(catalog))
