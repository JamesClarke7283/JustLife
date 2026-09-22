"""Author the nursery and child-bedroom set the household was missing.

A cot for a baby, a child's bed, a changing table, a potty, a baby bottle, a
jar of baby food and a set of baby toys. Each is its own family so Build & buy
can offer it and the household can name it, exactly like every other furnishing.

Run:  blender --background --python tools/create_nursery.py -- --source-out art/furniture_nursery.blend
"""
import bpy, math, random, sys, argparse, pathlib
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(71)
bpy.ops.wm.read_factory_settings(use_empty=True)
M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    m=bpy.data.materials.new(name); m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value=(rgb[0],rgb[1],rgb[2],1)
    b.inputs['Roughness'].default_value=rough
    if metal:b.inputs['Metallic'].default_value=metal
    if emit:b.inputs['Emission Color'].default_value=(rgb[0],rgb[1],rgb[2],1);b.inputs['Emission Strength'].default_value=emit
    M[name]=m; return m
for n,h in [('oak','AB7951'),('oak_light','D7AE7E'),('walnut','624435'),('cream','EFE9DA'),('white','FAF6EA'),
            ('teal','417A71'),('teal_light','86ADA0'),('coral','C97C66'),('gold','C8A562'),('dark','263E3C'),
            ('black','1D292B'),('green','48794B'),('leaf_light','749752'),('blue','7CA4AA'),('linen','DECFAF'),
            ('water','B7D9DB'),('mustard','D2A24B'),('plum','6E5470'),('sky','9EC1CF'),('rose','D9A0A0'),
            ('graphite','4A4F55'),('ivory','F6F1E4'),('milk','FFFDF6'),('apple','C9A05A'),('pea','8FA35E')]:
    mat(n,h)
mat('glass','F2F7FA',.3,0,0.6); mat('steel','B9BEC2',.35,.45); mat('brass','C8A562',.4,.35)

active=[]
def xyz(p): return (p[0],-p[2],p[1])
def finish(o,n,m):
    o.name=n; o.data.materials.append(M[m]); active.append(o); return o
def box(n,p,s,m,bevel=.03):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p)); o=bpy.context.object
    o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        b=o.modifiers.new('Bevel','BEVEL'); b.width=bevel; b.segments=2; b.limit_method='ANGLE'
    return finish(o,n,m)
def ell(n,p,s,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=xyz(p)); o=bpy.context.object
    o.scale=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def cyl(n,p,r,h,m,top=None,axis='Y'):
    bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    if axis=='Y':o.rotation_euler=(math.pi/2,0,0)
    elif axis=='Z':o.rotation_euler=(0,math.pi/2,0)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=False); o.dimensions=(r*2,h,r*2); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def rod(n,a,b,r,m):
    av,bv=Vector(xyz(a)),Vector(xyz(b)); d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object
    o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return finish(o,n,m)
def torus(n,p,major,minor,m,axis='Y'):
    bpy.ops.mesh.primitive_torus_add(major_segments=36,minor_segments=10,major_radius=major,minor_radius=minor,location=xyz(p)); o=bpy.context.object
    if axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def legs(w,d,h,m='oak',inset=.10,size=.065):
    for x in [-w/2+inset,w/2-inset]:
        for z in [-d/2+inset,d/2-inset]:box('Leg',(x,h/2,z),(size,h,size),m,.012)

# ------------------------------------------------------------------- Sleep

def cot():
    # A baby's cot: four corner posts, a slatted rail on all four sides, a
    # mattress in the base and a small mobile over the head end. The mattress top
    # is the sleeping surface, so it sits just below the rails at .46 m.
    w,d,h=1.24,.64,.62
    for x in [-w/2+.04,w/2-.04]:
        for z in [-d/2+.04,d/2-.04]:box('Cot post',(x,h/2+.06,z),(.05,h+.12,.05),'oak',.012)
    for y in [.20,.40]:  # two horizontal rails per long side
        box('Cot rail L',(-w/2+.04,y,-d/2+.04),(.035,.03,d-.08),'oak',.010)
        box('Cot rail R',(w/2-.04,y,-d/2+.04),(.035,.03,d-.08),'oak',.010)
    for x in [-w/2+i*(w/11) for i in range(1,11)]:
        for z in [-d/2+.04,d/2-.04]:box('Cot slat',(x,.30,z),(.022,.44,.022),'oak_light',.006)
    box('Cot base',(0,.20,-.0),(w-.10,.03,d-.10),'walnut',.010)
    box('Cot mattress',(0,.245,0),(w-.16,.06,d-.16),'sky',.030)
    box('Cot bumper',(0,.30,-d/2+.10),(w-.18,.10,.03),'rose',.012)
    # A mobile over the head end: a bar with three hanging shapes.
    rod('Cot mobile arm',(w/2-.04,h+.06,0),(w/2-.30,h+.18,0),.010,'oak')
    for i,mm in enumerate(['coral','mustard','teal']):
        rod('Cot mobile thread',(w/2-.30,h+.18,-.14+i*.14),(w/2-.30,h+.02,-.14+i*.14),.004,'graphite')
        ell('Cot mobile shape',(w/2-.30,h-.02,-.14+i*.14),(.045,.045,.045),mm)

def child_bed():
    # A low single bed a child can get into: a frame, a headboard, a mattress and
    # a folded blanket at the foot. Lower than an adult bed so it reads as one.
    w,d,h=1.02,1.94,.42
    for x in [-w/2+.06,w/2-.06]:
        for z in [-d/2+.06,d/2-.06]:box('Bed leg',(x,.22,z),(.07,.44,.07),'walnut',.012)
    box('Bed frame',(0,.30,0),(w,.10,d),'walnut',.014)
    box('Bed mattress',(0,.42,0),(w-.10,.20,d-.10),'ivory',.030)
    box('Bed headboard',(0,.70,-d/2+.04),(w,.52,.06),'oak',.014)
    for x in [-w/4,0,w/4]:box('Headboard slat',(x,.70,-d/2+.075),(.06,.34,.02),'oak_light',.006)
    box('Bed blanket',(0,.545,d/2-.42),(w-.08,.045,.72),'teal',.020)
    box('Bed pillow',(0,.545,-d/2+.30),(.62,.10,.30),'white',.030)
    # A guard rail on the open side, so the bed reads as a child's.
    rod('Bed rail front',(-w/2+.14,.58,0),(w/2-.14,.58,0),.016,'oak')
    for i in range(3):
        x=-w/4+i*(w/4)
        rod('Bed rail post',(x,.58,0),(x,.46,0),.014,'oak')

# ------------------------------------------------------------------- Care

def changing_table():
    # A waist-height table with a raised tray, a shelf of nappies under it and a
    # wipe tub on top, so the piece says what it is from across the room.
    w,d,h=1.10,.56,.90
    box('Changing top',(0,h,0),(w,.05,d),'cream',.014)
    box('Changing tray',(0,h+.055,0),(w-.16,.045,d-.16),'linen',.024)
    box('Changing rim L',(-w/2+.10,h+.10,0),(.03,.07,d-.12),'teal',.010)
    box('Changing rim R',(w/2-.10,h+.10,0),(.03,.07,d-.12),'teal',.010)
    box('Changing rim back',(0,h+.10,-d/2+.08),(w-.14,.07,.03),'teal',.010)
    for x in [-w/2+.07,w/2-.07]:
        for z in [-d/2+.07,d/2-.07]:box('Changing leg',(x,h/2-0.02,z),(.06,h-.04,.06),'oak',.012)
    box('Changing shelf',(0,.30,0),(w-.20,.035,d-.16),'oak_light',.010)
    # Stacked nappies on the shelf and a wipe tub on the table.
    for i in range(4):
        box('Nappy stack',(-.22+i*.02,.345+i*.028,0),(.30,.028,.22),'white',.006)
    box('Wipe tub',(w/2-.24,h+.10,d/2-.20),(.14,.12,.14),'sky',.020)
    box('Wipe lid',(w/2-.24,h+.17,d/2-.20),(.16,.02,.16),'teal',.008)

def potty():
    # A toddler's potty: a low seat ring on a bowl with a small back rest.
    ell('Potty bowl',(0,.09,0),(.20,.09,.17),'sky')
    torus('Potty seat',(0,.185,0),.135,.030,'white')
    box('Potty splash',(0,.20,.14),(.22,.14,.03),'sky',.010)

def bottle():
    # A baby bottle: a clear body, a teat and a collar.
    cyl('Bottle body',(0,.10,0),.036,.17,'glass',axis='Y')
    cyl('Bottle milk',(0,.08,0),.030,.11,'milk',axis='Y')
    cyl('Bottle collar',(0,.195,0),.040,.028,'teal',axis='Y')
    cyl('Bottle teat',(0,.235,0),.022,.055,'ivory',top=.012,axis='Y')

def baby_food():
    # A jar of baby food with its lid: the second half of what a baby eats.
    cyl('Jar body',(0,.055,0),.042,.11,'apple',axis='Y')
    cyl('Jar lid',(0,.118,0),.046,.022,'coral',axis='Y')
    torus('Jar label',(0,.055,0),.044,.008,'cream')

# ------------------------------------------------------------------- Play

def baby_toys():
    # A play mat with a rattle, a pair of soft blocks and a ring: the set a baby
    # reaches for, and what a parent picks up to play with them.
    box('Play mat',(0,.012,0),(.90,.024,.90),'mustard',.020)
    for i in range(4):
        box('Mat stripe',(-.32+i*.21,.028,0),(.10,.006,.86),['coral','teal','sky','rose'][i],.004)
    # A rattle: a handle with a ball and three beads.
    rod('Rattle handle',(-.24,.03,-.22),(-.24,.16,-.22),.018,'oak')
    ell('Rattle head',(-.24,.20,-.22),(.052,.052,.052),'coral')
    for i in range(3):
        ell('Rattle bead',(-.24+math.cos(i*2.1)*.075,.20+math.sin(i*2.1)*.02,-.22+math.sin(i*2.1)*.075),(.022,.022,.022),'mustard')
    # Soft blocks.
    for i,m in enumerate(['teal','rose','sky']):
        box('Soft block',(.06+i*.20,.075,.18),(.14,.14,.14),m,.030)
    torus('Play ring',(.24,.045,.30),.080,.024,'coral')

def baby_mobile_stars():
    rod('Mobile stem',(0,.70,0),(0,.85,0),.012,'oak')
    for i in range(4):
        a=i*math.pi/2
        x,z=math.cos(a)*.18,math.sin(a)*.18
        rod('Arm',(0,.85,0),(x,.85,z),.008,'oak')
        rod('Thread',(x,.85,z),(x,.55,z),.003,'graphite')
        box('Star',(x,.50,z),(.08,.02,.08),'mustard',.004)

def baby_mobile_cloud():
    rod('Mobile stem',(0,.70,0),(0,.85,0),.012,'oak')
    for i in range(3):
        a=i*2.1
        x,z=math.cos(a)*.16,math.sin(a)*.16
        rod('Arm',(0,.85,0),(x,.85,z),.008,'sky')
        rod('Thread',(x,.85,z),(x,.58,z),.003,'graphite')
        ell('Cloud',(x,.52,z),(.07,.04,.05),'white')

def baby_rattle():
    rod('Handle',(0,.04,0),(0,.14,0),.016,'oak')
    ell('Head',(0,.18,0),(.05,.05,.05),'coral')
    for i in range(3):
        ell('Bead',(math.cos(i*2.1)*.06,.18,math.sin(i*2.1)*.06),(.02,.02,.02),'mustard')

def rocking_chair():
    box('Seat',(0,.42,0),(.52,.04,.48),'oak',.012)
    box('Back',(0,.72,-.22),(.50,.55,.04),'oak',.012)
    for x in [-.22,.22]:
        box('Leg',(x,.22,.16),(.05,.44,.05),'walnut',.008)
        box('Leg',(x,.22,-.16),(.05,.44,.05),'walnut',.008)
    # Rockers
    for z in [-.28,.28]:
        cyl('Rocker',(0,.04,z),.04,.70,'walnut',axis='Z')

def baby_mat():
    box('Mat',(0,.015,0),(1.20,.03,1.20),'mustard',.020)
    for i in range(5):
        box('Stripe',(-.45+i*.22,.032,0),(.12,.006,1.10),['coral','teal','sky','rose','plum'][i],.004)
    ell('Bolster',(0,.06,-.45),(.35,.05,.10),'rose')

def children_picture(style):
    box('Frame',(0,.36,0),(.72,.72,.04),'oak',.010)
    box('Tint',(0,.36,.02),(.60,.60,.01),['coral','sky','mustard','teal','rose'][style%5],.004)

def dollhouse_classic():
    box('Body',(0,.45,0),(.90,.90,.50),'oak_light',.012)
    box('Roof',(0,.98,0),(.98,.16,.56),'coral',.010)
    for x in [-.22,.22]:
        box('Window',(x,.55,.26),(.18,.22,.02),'sky',.004)
    box('Door',(0,.28,.26),(.16,.36,.02),'walnut',.004)

def dollhouse_cottage():
    box('Body',(0,.40,0),(.85,.80,.48),'cream',.012)
    box('Roof',(0,.90,0),(.95,.20,.54),'teal',.010)
    box('Chimney',(.28,1.05,-.10),(.10,.28,.10),'coral',.006)
    box('Door',(0,.26,.25),(.14,.34,.02),'oak',.004)

def train_set_oval():
    torus('Track',(0,.02,0),.40,.03,'oak',axis='Y')
    box('Engine',(.40,.08,0),(.18,.10,.10),'coral',.008)
    box('Caboose',(-.40,.08,0),(.16,.10,.10),'teal',.008)

def train_set_figure8():
    torus('LoopA',(-.18,.02,0),.28,.025,'oak',axis='Y')
    torus('LoopB',(.18,.02,0),.28,.025,'oak',axis='Y')
    box('Engine',(0,.08,.28),(.16,.10,.10),'mustard',.008)

def child_rug():
    box('Tint',(0,.02,0),(1.6,.04,1.2),'rose',.020)
    box('Border',(0,.025,0),(1.50,.01,1.10),'cream',.004)

def child_desk_plain():
    box('Top',(0,.70,0),(.95,.04,.55),'oak',.012)
    for x in [-.40,.40]:
        for z in [-.20,.20]:
            box('Leg',(x,.35,z),(.05,.70,.05),'walnut',.008)

def child_desk_shelf():
    child_desk_plain()
    box('Shelf',(0,.40,0),(.80,.03,.40),'oak_light',.008)
    box('Back',(0,.55,-.24),(.90,.30,.03),'oak',.008)

def child_chair_plain():
    box('Seat',(0,.32,0),(.38,.04,.36),'oak',.010)
    box('Back',(0,.50,-.16),(.36,.36,.04),'oak',.010)
    for x in [-.14,.14]:
        for z in [-.12,.12]:
            box('Leg',(x,.16,z),(.04,.32,.04),'walnut',.006)

def child_chair_arms():
    child_chair_plain()
    for x in [-.18,.18]:
        box('Arm',(x,.42,0),(.04,.04,.30),'oak',.006)

def nursery_paint(style):
    # A wall panel sample: Tint surface for the ten-colour catalogue, pattern as
    # raised dots/stripes on the face so styles stay distinct after recolour.
    box('Tint',(0,1.1,0),(2.0,2.2,.04),'sky',.004)
    if style==0:  # stars
        for i in range(6):
            box('Star',(-.7+i*.28,1.3+((i%2)*.25),.03),(.08,.02,.08),'mustard',.002)
    elif style==1:  # clouds
        for i in range(4):
            ell('Cloud',(-.6+i*.4,1.4,.03),(.16,.08,.04),'white')
    elif style==2:  # stripes
        for i in range(5):
            box('Stripe',(-.8+i*.4,1.1,.03),(.12,2.0,.01),'cream',.002)
    elif style==3:  # dots
        for i in range(12):
            ell('Dot',(-.7+(i%4)*.45,0.7+(i//4)*.5,.03),(.06,.06,.02),'coral')
    else:  # animals
        for i,m in enumerate(['coral','teal','mustard']):
            ell('Critter',(-.5+i*.5,1.2,.03),(.12,.10,.04),m)

catalog={
    'cot':cot,'child_bed':child_bed,'changing_table':changing_table,'potty':potty,
    'baby_bottle':bottle,'baby_food':baby_food,'baby_toys':baby_toys,
    'baby_mobile_stars':baby_mobile_stars,'baby_mobile_cloud':baby_mobile_cloud,
    'baby_rattle':baby_rattle,'rocking_chair':rocking_chair,'baby_mat':baby_mat,
    'children_picture_01':lambda:children_picture(0),
    'children_picture_02':lambda:children_picture(1),
    'children_picture_03':lambda:children_picture(2),
    'children_picture_04':lambda:children_picture(3),
    'children_picture_05':lambda:children_picture(4),
    'dollhouse_classic':dollhouse_classic,'dollhouse_cottage':dollhouse_cottage,
    'train_set_oval':train_set_oval,'train_set_figure8':train_set_figure8,
    'child_rug':child_rug,
    'child_desk_plain':child_desk_plain,'child_desk_shelf':child_desk_shelf,
    'child_chair_plain':child_chair_plain,'child_chair_arms':child_chair_arms,
    'nursery_paint_stars':lambda:nursery_paint(0),
    'nursery_paint_clouds':lambda:nursery_paint(1),
    'nursery_paint_stripes':lambda:nursery_paint(2),
    'nursery_paint_dots':lambda:nursery_paint(3),
    'nursery_paint_animals':lambda:nursery_paint(4),
}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/furniture_nursery.blend')
parser.add_argument('--new-only',action='store_true',help='Export only the newly added families')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if args.only:catalog={args.only:catalog[args.only]}
elif args.new_only:
    skip={'cot','child_bed','changing_table','potty','baby_bottle','baby_food','baby_toys'}
    catalog={k:v for k,v in catalog.items() if k not in skip}
for idx,(name,fn) in enumerate(catalog.items()):
    active=[]; fn()
    root=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(root)
    for o in active:
        if o.parent is None:o.parent=root
    bpy.ops.object.select_all(action='DESELECT'); root.select_set(True)
    for o in active:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models'/f'{name}.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    root.location=((idx%6)*4,(idx//6)*4,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_NURSERY_COMPLETE', len(catalog))
