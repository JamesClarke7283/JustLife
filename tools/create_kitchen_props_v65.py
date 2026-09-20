"""Original JustLife kitchen props, iteration 65: a counter-top espresso machine
and a small grocery delivery van. Run:
blender -b --python tools/create_kitchen_props_v65.py.

Coordinates are Godot metres: x right, y up, z toward the front of the piece.
The espresso machine's working face (front panel, group head, portafilter, drip
tray, cup shelf) is at +z; the van's cab, windscreen and headlights are at +z
and its cargo doors at -z, so it drives toward +z. The palette, the soft-bevel
box and smooth-shaded ellipsoid construction, the per-model root Empty and the
glTF export call mirror tools/create_household_props.py and
tools/create_furniture_v60.py. Each primitive helper names its axis in Godot
terms, so a disc's facing is never a guess: axis='y' stacks the piece along +y
(the disc lies flat), axis='z' makes the disc face the room, axis='x' points it
right.
"""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(65)
bpy.ops.wm.read_factory_settings(use_empty=True)
M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*linear,1)
    m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value=m.diffuse_color
    b.inputs['Roughness'].default_value=rough
    b.inputs['Metallic'].default_value=metal
    if emit:b.inputs['Emission Color'].default_value=m.diffuse_color;b.inputs['Emission Strength'].default_value=emit
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
def box(n,p,s,m,bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p)); o=bpy.context.object; o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL'); mod.width=bevel; mod.segments=2; mod.limit_method='ANGLE'
    return finish(o,n,m)
def ell(n,p,s,m,segments=20,ring_count=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=ring_count,location=xyz(p)); o=bpy.context.object; o.scale=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def cyl(n,p,r,h,m,top=None,axis='y',verts=32):
    bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    if axis=='z':o.rotation_euler=(math.pi/2,0,0)
    elif axis=='x':o.rotation_euler=(0,math.pi/2,0)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
    mod=o.modifiers.new('Rounded rims','BEVEL'); mod.width=.005; mod.segments=2; mod.limit_method='ANGLE'
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def rod(n,a,b,r,m):
    av,bv=Vector(xyz(a)),Vector(xyz(b)); d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return finish(o,n,m)
def torus(n,p,major,minor,m,axis='y',major_segments=28,minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(major_segments=major_segments,minor_segments=minor_segments,major_radius=major,minor_radius=minor,location=xyz(p)); o=bpy.context.object
    if axis=='z':o.rotation_euler=(math.pi/2,0,0)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def tilt(o,pitch): o.rotation_euler[0]=pitch; return o

# ---------------------------------------------------------------- Kitchen
def coffee_machine():
    # A counter-top espresso machine .42 square and .86 tall. The column only
    # takes the back half of the depth (-.15 to .06): the whole front strip is
    # left to the group head, the portafilter hanging under it, the drip tray,
    # and the cup shelf the espresso cup actually stands on, so none of the
    # working parts hide inside the body silhouette. The bean hopper on top is
    # crowned by a low brass lid dome whose highlight is exactly y=.86, so the
    # declared height is the lid and not the column. Everything the barista
    # touches faces +z.
    box('Machine plinth',(0,.012,-.010),(.38,.024,.396),'black',.008)
    box('Machine body',(0,.320,-.045),(.38,.60,.21),'graphite',.070)
    box('Machine top plate',(0,.628,-.045),(.36,.026,.19),'steel',.006)
    box('Front panel',(0,.440,.075),(.24,.16,.05),'steel',.008)
    cyl('Front panel dial',(0,.440,.102),.042,.020,'brass',top=.034,axis='z')
    cyl('Front panel dial cap',(0,.440,.114),.014,.012,'graphite',axis='z',verts=16)
    for s in (-1,1):cyl('Front panel light',(s*.090,.495,.102),.011,.014,'ember',axis='z',verts=16)
    cyl('Steam knob',(.196,.400,-.010),.020,.026,'brass',axis='x',verts=16)
    box('Group head',(0,.280,.105),(.14,.09,.10),'black',.012)
    cyl('Portafilter',(0,.215,.135),.052,.022,'steel',axis='z')
    rod('Portafilter handle',(0,.215,.146),(0,.215,.170),.012,'walnut')
    ell('Portafilter knob',(0,.215,.176),(.0125,.0125,.0125),'walnut',segments=12,ring_count=8)
    box('Drip tray',(0,.065,.135),(.32,.070,.14),'steel',.008)
    for z in (.090,.115,.140,.165,.190):rod('Drip tray bar',(-.150,.1045,z),(.150,.1045,z),.0045,'graphite')
    box('Cup shelf',(-.115,.155,.130),(.13,.014,.12),'steel',.005)
    rod('Cup shelf post',(-.175,.026,.075),(-.175,.148,.075),.008,'steel')
    rod('Cup shelf post',(-.055,.026,.182),(-.055,.148,.182),.008,'steel')
    cyl('Espresso cup',(-.115,.197,.125),.033,.070,'white',top=.028,axis='y',verts=20)
    torus('Espresso cup handle',(-.115,.197,.156),.024,.007,'white',axis='z')
    rod('Steam wand',(.085,.290,.095),(.155,.155,.115),.009,'steel')
    rod('Steam wand grip',(.092,.272,.097),(.110,.235,.102),.016,'black')
    rod('Steam wand tip',(.145,.172,.112),(.155,.155,.115),.013,'steel')
    box('Bean hopper',(0,.720,-.060),(.24,.16,.18),'black',.050)
    box('Hopper lid',(0,.815,-.060),(.25,.030,.19),'steel',.008)
    ell('Hopper lid dome',(0,.838,-.060),(.11,.0215,.09),'brass',segments=24,ring_count=10)
    box('Hopper latch',(0,.815,.042),(.070,.020,.024),'brass',.005)

# ---------------------------------------------------------------- Delivery
def delivery_van():
    # A small grocery delivery van: 2.30 long, 1.30 wide, 1.90 to the top of the
    # cargo roof. The cab is at +z with a 20 degree windscreen, one window per
    # door and wing mirrors on the belt line; the squarer cargo box starts behind
    # it and steps .31 above the cab roof, so the silhouette reads as a van and
    # not a car. The four .60 tyres sit at z=+.70 and z=-.62 and reach x=+-.610,
    # just proud of the .60 body sides, so the dark rubber reads from the side
    # while the bumpers stop inside the 1.15 half-length and the mirrors define
    # the .65 width.
    box('Van underbody',(0,.300,-.020),(.98,.14,1.96),'graphite',.010)
    box('Van body',(0,.600,.010),(1.20,.50,2.22),'white',.020)
    box('Van waist stripe',(0,.670,.010),(1.21,.09,2.22),'teal',.010)
    box('Van cargo box',(0,1.365,-.380),(1.16,.97,1.44),'white',.020)
    box('Van cargo roof',(0,1.848,-.375),(1.18,.10,1.44),'white',.020)
    box('Van cab',(0,1.170,.530),(1.18,.66,.42),'white',.020)
    box('Van cab roof',(0,1.545,.543),(1.18,.09,.41),'white',.020)
    box('Van wiper cowl',(0,.875,1.030),(1.18,.05,.18),'graphite',.008)
    tilt(box('Van windscreen',(0,1.205,.855),(1.18,.64,.05),'screen',.006),math.radians(-20))
    rod('Van wiper',(-.340,.910,.985),(.060,.910,.985),.008,'graphite')
    box('Van grille',(0,.620,1.125),(.52,.16,.02),'graphite',.006)
    for s in (-1,1):
        box('Van side sill',(s*.585,.330,-.020),(.05,.10,1.96),'graphite',.010)
        box('Van headlight',(s*.420,.740,1.128),(.22,.14,.03),'bulb',.006)
        box('Van side window',(s*.598,1.330,.760),(.030,.30,.40),'screen',.006)
        box('Van door seam',(s*.605,.950,.350),(.012,.90,.02),'graphite',.004)
        box('Van door handle',(s*.606,.980,.550),(.018,.06,.03),'brass',.005)
        box('Van mirror arm',(s*.590,1.280,1.000),(.06,.02,.02),'graphite',.004)
        box('Van mirror housing',(s*.628,1.300,1.010),(.031,.14,.10),'graphite',.006)
        box('Van mirror glass',(s*.642,1.300,1.010),(.008,.11,.075),'mirror_glass',.003)
        box('Van tail light',(s*.500,.700,-1.108),(.10,.22,.03),'ember',.005)
        box('Van rear door handle',(s*.180,1.250,-1.115),(.14,.05,.03),'brass',.006)
        for z in (.70,-.62):
            cyl('Van tyre',(s*.525,.300,z),.30,.17,'black',axis='x',verts=28)
            cyl('Van wheel hub',(s*.612,.300,z),.150,.030,'steel',axis='x',verts=20)
            cyl('Van hub boss',(s*.628,.300,z),.055,.022,'brass',axis='x',verts=14)
    box('Van front bumper',(0,.420,1.065),(1.14,.16,.15),'graphite',.020)
    box('Van number plate',(0,.440,1.140),(.34,.10,.016),'cream',.004)
    box('Van rear bumper',(0,.440,-1.070),(1.14,.15,.15),'graphite',.020)
    box('Van rear door seam',(0,1.380,-1.113),(.018,.93,.02),'graphite',.004)

catalog={'coffee_machine':coffee_machine,'delivery_van':delivery_van}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/kitchen_props_v65.blend')
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

# Review renders are not part of the exported assets: a studio of three area
# lights plus a sun, shot on a 3/4 view from the front right, orthographic so
# each piece is framed to its own declared height.
HEIGHT={'coffee_machine':.86,'delivery_van':1.90}
SPAN={'coffee_machine':.46,'delivery_van':2.70}
bpy.ops.mesh.primitive_plane_add(size=60,location=(0,0,-.002))
backdrop=bpy.context.object
backdrop.data.materials.append(mat('review_backdrop','E9E7DC'))
studio=[backdrop]
bpy.ops.object.camera_add(); camera=bpy.context.object
camera.data.type='ORTHO'; bpy.context.scene.camera=camera
studio.append(camera)
for pos,energy,size in [((-.9,-1.3,2.6),135,1.6),((1.6,-0.7,1.3),50,1.0),((0.2,1.8,1.1),32,1.0)]:
    loc=Vector(pos); bpy.ops.object.light_add(type='AREA',location=loc); light=bpy.context.object
    light.data.energy=energy; light.data.shape='DISK'; light.data.size=size
    light.rotation_euler=(-loc).to_track_quat('-Z','Y').to_euler()
    studio.append(light)
bpy.ops.object.light_add(type='SUN',location=(0,0,4)); sun=bpy.context.object
sun.data.energy=1.9
sun.data.angle=math.radians(12)
sun.rotation_euler=(Vector((0,0,4))-Vector((2.4,-4,5))).to_track_quat('-Z','Y').to_euler()
studio.append(sun)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=64
scene.view_settings.view_transform='AgX'
scene.render.resolution_x=640; scene.render.resolution_y=480; scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Kitchen props review studio')
scene.world.color=(.30,.31,.33)
outdir=ROOT/'art/kitchen_props_review'; outdir.mkdir(parents=True,exist_ok=True)
az,el=math.radians(38),math.radians(17)
for name in catalog:
    centre=bpy.data.objects[name].location+Vector((0,0,HEIGHT[name]/2))
    offset=Vector((math.sin(az),-math.cos(az),math.sin(el))).normalized()
    camera.location=centre+offset*(HEIGHT[name]*3.1)
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=max(SPAN[name]*1.30,HEIGHT[name]*4/3*1.16)
    scene.render.filepath=str(outdir/f'{name}.png')
    bpy.ops.render.render(write_still=True)
    print('JUSTLIFE_KITCHEN_PROPS_REVIEW_RENDER', scene.render.filepath)
for o in studio:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_KITCHEN_PROPS_V65_COMPLETE', len(catalog))
