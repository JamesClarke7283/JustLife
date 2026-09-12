"""Original JustLife furniture, iteration 60 living-room set. Run: blender -b --python tools/create_furniture_v60.py.

Adds the three iteration-60 pieces: a storybook reading nook (a bench in front
of an open bookcase), a teatime coffee table with a decorative book-and-cup
prop, and a reading arc floor lamp. Coordinates are Godot metres: x right, y
up, z toward the front of the furnishing. Seats face +z; standing activities
happen at +z. The helpers mirror tools/create_furniture_v2.py so the pieces
match the production palette and soft-bevel construction.
"""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(60)
bpy.ops.wm.read_factory_settings(use_empty=True)
M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    m=bpy.data.materials.new(name)
    m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value=(rgb[0],rgb[1],rgb[2],1)
    b.inputs['Roughness'].default_value=rough
    if metal:b.inputs['Metallic'].default_value=metal
    if emit:b.inputs['Emission Color'].default_value=(rgb[0],rgb[1],rgb[2],1);b.inputs['Emission Strength'].default_value=emit
    M[name]=m; return m
for n,h in [('oak','AB7951'),('oak_light','D7AE7E'),('walnut','624435'),('cream','EFE9DA'),('white','FAF6EA'),('teal','417A71'),('teal_light','86ADA0'),('coral','C97C66'),('gold','C8A562'),('dark','263E3C'),('black','1D292B'),('green','48794B'),('leaf_light','749752'),('soil','42352D'),('blue','7CA4AA'),('screen','406C72'),('linen','DECFAF'),('book','B6B29C'),('water','B7D9DB'),('rust','9A5A44'),('brick','8C5A4A'),('mustard','D2A24B'),('plum','6E5470'),('sky','9EC1CF'),('rose','D9A0A0'),('graphite','4A4F55'),('ivory','F6F1E4')]: mat(n,h)
mat('flame','F2A93B',.9,0,6.0); mat('ember','E0602A',.9,0,2.5)
mat('mirror_glass','F2F7FA',.3,0,1.0); mat('brass','C8A562',.4,.35); mat('steel','B9BEC2',.35,.45)
mat('bulb','FFF3D8',.4,0,3.2)
M['gold'].node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value=.65
active=[]
def xyz(p): return (p[0],-p[2],p[1])
def finish(o,n,m):
    o.name=n; o.data.materials.append(M[m]); active.append(o); return o
def box(n,p,s,m,bevel=.03):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p)); o=bpy.context.object; o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        b=o.modifiers.new('Bevel','BEVEL'); b.width=bevel; b.segments=2; b.limit_method='ANGLE'
    return finish(o,n,m)
def ell(n,p,s,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=xyz(p)); o=bpy.context.object; o.scale=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
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
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return finish(o,n,m)
def torus(n,p,major,minor,m,axis='Y'):
    bpy.ops.mesh.primitive_torus_add(major_segments=36,minor_segments=10,major_radius=major,minor_radius=minor,location=xyz(p)); o=bpy.context.object
    if axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def legs(w,d,h,m='oak',inset=.10,size=.065):
    for x in [-w/2+inset,w/2-inset]:
        for z in [-d/2+inset,d/2-inset]:box('Tapered leg',(x,h/2,z),(size,h,size),m,.012)

# ---------------------------------------------------------------- Activities
def book_nook():
    # An open-backed oak bookcase behind a cushioned bench: the reading spot is
    # the seat, so the bench front (z .34) stays inside the .75 footprint and
    # the shelf spines sit at the reader's eye line.
    for x in [-.70,.70]:box('Nook side',(x,.85,-.30),(.05,1.70,.42),'oak',.012)
    box('Nook top',(0,1.68,-.30),(1.45,.04,.44),'oak',.008)
    for y in [.52,.98,1.32]:box('Nook shelf',(0,y,-.30),(1.35,.035,.40),'oak',.008)
    box('Nook back rail',(0,1.10,-.505),(1.35,.9,.02),'oak',.006)
    spines=['book','coral','teal','plum','sky','rust','green','mustard','rose','blue']
    for row,y in enumerate([.545,.545,1.005,1.005,1.345,1.345]):
        x=-.62
        while x<.60:
            w=random.uniform(.035,.06); h=random.uniform(.24,.30)
            box('Shelf book',(x+w/2,y+h/2,-.30),(w,h,.26),spines[(row*3+int(x*13))%len(spines)],.006)
            x+=w+.012
    box('Bench frame',(0,.20,.14),(1.40,.16,.40),'walnut',.015)
    box('Bench cushion',(0,.345,.14),(1.42,.13,.42),'teal',.05)
    for x in [-.62,.62]:box('Bench leg',(x,.09,.14),(.06,.18,.34),'walnut',.012)
    box('Nook tome',(0,.465,.02),(.24,.05,.18),'rust',.008)
    box('Nook open book',(0,.475,.26),(.22,.03,.16),'cream',.006)

# ---------------------------------------------------------------- Decor
def coffee_table():
    # A low oval-top table for the sofa's front. The book stack and teacup are
    # part of the model, so the tabletop never reads as bare; plates set down
    # by hand share the same .46 top through the meal surface table.
    bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=1,depth=.045,location=xyz((0,.46,0))); o=bpy.context.object; o.scale=(.525,.31,1); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    finish(o,'Coffee top','oak_light')
    bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=1,depth=.03,location=xyz((0,.155,0))); o=bpy.context.object; o.scale=(.42,.22,1); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    finish(o,'Coffee under-shelf','oak')
    for x in [-.40,.40]:
        for z in [-.16,.16]:
            box('Coffee leg',(x,.225,z),(.055,.45,.055),'walnut',.012)
    box('Coffee book',(0,.515,.05),(.30,.045,.22),'teal',.008)
    box('Coffee book 2',(0,.4875,.04),(.26,.035,.19),'coral',.006)
    cyl('Coffee saucer',(.28,.4835,.16),.075,.012,'white',axis='Y')
    cyl('Teatime cup',(.28,.515,.16),.045,.075,'rose',.038,axis='Y')
    torus('Cup handle',(.345,.515,.16),.032,.008,'rose',axis='Z')
    for y in [.505,.525]:cyl('Cup steam',(.28,y+.01,.16),.008,.02,'ivory',axis='Y')

def floor_lamp():
    # A reading arc: weighted base, rising stem and an arched arm that hands a
    # drum shade over the reading spot in front (+z). The warm pool of light
    # itself is a runtime OmniLight3D (world.gd), switchable from the menu.
    cyl('Lamp base',(0,.02,0),.17,.04,'dark',axis='Y')
    cyl('Lamp stem',(0,.5,-.12),.018,.92,'brass',axis='Y')
    rod('Lamp arm',(0,.96,-.12),(0,1.52,.10),.016,'brass')
    rod('Lamp arm front',(0,1.52,.10),(0,1.60,.34),.016,'brass')
    cyl('Lamp shade',(0,1.50,.38),.15,.26,'linen',top=.12,axis='Y')
    ell('Lamp bulb',(0,1.46,.38),(.05,.05,.05),'bulb')
    cyl('Lamp switch',(0,.30,-.135),.012,.02,'coral',axis='Y')

catalog={'book_nook':book_nook,'coffee_table':coffee_table,'floor_lamp':floor_lamp}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/furniture_v60.blend')
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
    root.location=((idx%6)*4,(idx//6)*4,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_FURNITURE_V60_COMPLETE', len(catalog))
