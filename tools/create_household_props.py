"""Original JustLife household props: a kitchen pedal bin, an acoustic guitar on
a wooden floor stand, and a violin on a display stand with its bow. Run:
blender -b --python tools/create_household_props.py.

Coordinates are Godot metres: x right, y up, z toward the front of the
furnishing. The palette, the soft-bevel box and smooth-shaded ellipsoid
construction, the per-model root Empty and the glTF export call mirror
tools/create_furniture_v2.py and tools/create_furniture_v60.py. Each primitive
helper names its axis in Godot terms, so a disc's facing is never a guess:
axis='y' stacks the piece along +y (the disc lies flat), axis='z' makes the
disc face the room, axis='x' points it right.
"""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(71)
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
def spin(o,angle): o.rotation_euler[1]=angle; return o

# ---------------------------------------------------------------- Kitchen
def rubbish_bin():
    # A kitchen pedal bin. The graphite body tapers from a .132 base to a .218
    # rim, which is what lets the coral pedal's .09 face reach the .225 footprint
    # limit. The steel lid is a genuinely closed flat disc whose top sits exactly
    # at y=.72, ringed by the 6 mm rim lip and, just inside it, the liner ring, so
    # the lid the runtime closes over the top lands on a real surface: the model
    # has no hole through it.
    cyl('Bin body',(0,.35,0),.132,.70,'graphite',top=.218)
    for i in range(8):
        a=math.pi/4*i+math.pi/8
        rod('Bin rib',(math.cos(a)*.140,.06,math.sin(a)*.140),(math.cos(a)*.212,.62,math.sin(a)*.212),.006,'graphite')
    cyl('Bin base rim',(0,.012,0),.140,.024,'black')
    cyl('Bin lid',(0,.714,0),.190,.012,'steel')
    torus('Bin liner ring',(0,.7145,0),.196,.0035,'steel')
    torus('Bin rim lip',(0,.7140,0),.2185,.0030,'steel',major_segments=40)
    box('Bin hinge boss',(0,.706,-.196),(.100,.026,.048),'brass',.005)
    rod('Bin hinge pin',(-.075,.712,-.196),(.075,.712,-.196),.008,'brass')
    box('Bin pedal bracket',(0,.045,.150),(.060,.022,.040),'steel',.004)
    box('Bin pedal',(0,.048,.179),(.115,.028,.090),'coral',.006)
    rod('Bin pedal pivot',(-.065,.044,.185),(.065,.044,.185),.007,'steel')

# ---------------------------------------------------------------- Music
def guitar():
    # An acoustic guitar standing upright in a low walnut A-frame stand. The
    # soundbox is a rounded lower bout and a narrower upper bout in oak_light,
    # carrying a walnut top plate that is proud of it by a few millimetres; the
    # .09 soundhole is a black disc set just proud of that plate under a gold
    # rosette. The .57 neck rises to a headstock that tops out at exactly y=1.05.
    # The guitar's lower edge nests in the coral cradle's linen felt pad.
    ell('Guitar lower bout',(0,.20,.015),(.18,.15,.045),'oak_light')
    ell('Guitar upper bout',(0,.425,.015),(.145,.115,.040),'oak_light')
    ell('Guitar lower soundboard',(0,.200,.050),(.176,.146,.014),'walnut')
    ell('Guitar upper soundboard',(0,.425,.046),(.141,.111,.013),'walnut')
    # The soundboard's front face is at z=.064 on the lower bout, so the hole and
    # its rosette are set a hair proud of that plane to stay visible from the room.
    cyl('Guitar soundhole',(0,.295,.0605),.045,.014,'black',axis='z')
    torus('Guitar rosette',(0,.295,.0645),.053,.0035,'gold',axis='z')
    box('Guitar bridge',(0,.115,.060),(.110,.024,.018),'dark',.004)
    box('Guitar neck',(0,.765,.048),(.052,.570,.026),'walnut',.005)
    box('Guitar fretboard',(0,.755,.064),(.048,.530,.012),'dark',.004)
    for i in range(7):box('Guitar fret',(0,.535+i*.075,.071),(.046,.005,.004),'steel',0)
    box('Guitar nut',(0,.985,.070),(.046,.010,.010),'ivory',.002)
    box('Guitar headstock',(0,1.012,.048),(.078,.076,.022),'walnut',.006)
    for s in (-1,1):
        for y in (.988,1.0125,1.037):
            rod('Guitar peg',(s*.028,y,.048),(s*.085,y,.048),.005,'steel')
            cyl('Guitar peg knob',(s*.090,y,.048),.012,.014,'gold',axis='x',verts=12)
    for x in (-.020,-.012,-.004,.004,.012,.020):
        rod('Guitar string',(x,.115,.070),(x,.985,.074),.0016,'ivory')
    for s in (-1,1):
        # The feet stop at y=.014, so the rod's own radius puts the leg's lowest
        # surface on the floor instead of sinking the model below y=0.
        rod('Stand leg',(s*.205,.014,.25),(s*.220,.11,.01),.014,'walnut')
        rod('Stand leg',(s*.220,.11,.01),(s*.170,.014,-.25),.014,'walnut')
        # The arm leans in and its tip lands on the bout's widest point, so the
        # stand visibly grips the guitar instead of standing beside it.
        rod('Stand arm',(s*.215,.105,.010),(s*.152,.270,.010),.013,'walnut')
    box('Stand cradle',(0,.035,-.075),(.26,.070,.100),'coral',.02)
    box('Cradle felt',(0,.074,-.075),(.24,.014,.090),'linen',.006)

def violin():
    # A violin resting on a low walnut cradle stand with its bow leaning across
    # it. Two walnut bouts joined by a narrow waist give the classic outline,
    # with a dark purfling shell a few millimetres proud of the silhouette. Neck
    # and scroll carry the instrument to exactly y=.65; the .62 bow runs from the
    # floor at the front right, skims the upper bout's right edge and finishes
    # just past the scroll, inside the declared footprint and height.
    ell('Violin lower bout',(0,.175,0),(.105,.095,.030),'walnut')
    ell('Violin upper bout',(0,.3175,0),(.083,.0725,.028),'walnut')
    box('Violin waist',(0,.265,0),(.132,.075,.048),'walnut',.02)
    ell('Violin purfling lower',(0,.175,-.004),(.1085,.0985,.024),'dark')
    ell('Violin purfling upper',(0,.3175,-.004),(.0865,.076,.022),'dark')
    box('Violin purfling waist',(0,.265,-.002),(.138,.081,.040),'dark',.012)
    for s in (-1,1):
        spin(box('Violin f-hole',(s*.045,.215,.030),(.013,.062,.006),'black',.002),s*.30)
    box('Violin bridge',(0,.155,.033),(.040,.016,.014),'oak_light',.003)
    box('Violin tailpiece',(0,.128,.038),(.032,.062,.010),'dark',.003)
    box('Violin chinrest',(-.058,.145,.046),(.058,.058,.032),'dark',.018)
    box('Violin neck',(0,.4875,.004),(.036,.225,.024),'walnut',.005)
    box('Violin fretboard',(0,.478,.018),(.034,.205,.010),'dark',.003)
    box('Violin pegbox',(0,.612,.008),(.030,.058,.020),'walnut',.005)
    cyl('Violin scroll',(0,.628,.028),.021,.016,'walnut',axis='z',verts=16)
    ell('Violin scroll curl',(0,.630,.030),(.012,.012,.008),'walnut',segments=12,ring_count=8)
    for s in (-1,1):
        for y in (.593,.617):
            rod('Violin peg',(s*.012,y,.010),(s*.052,y,.010),.004,'gold')
            cyl('Violin peg knob',(s*.056,y,.010),.009,.012,'gold',axis='x',verts=12)
    for x in (-.018,-.006,.006,.018):
        rod('Violin string',(x,.160,.038),(x,.585,.026),.0014,'ivory')
    # A low walnut cradle: a base plate whose side cheeks hug the lower bout,
    # lined with linen felt, plus a felt rest the body sits on.
    box('Stand base',(0,.012,0),(.40,.024,.28),'walnut',.010)
    for s in (-1,1):
        box('Stand cheek',(s*.122,.085,0),(.028,.170,.20),'walnut',.010)
        box('Stand felt',(s*.106,.095,0),(.008,.150,.18),'linen',.003)
    box('Stand rest',(0,.055,0),(.22,.062,.18),'linen',.006)
    # The bow leans upright in the stand's front-right corner: its frog rests on
    # the base slab and the stick rises past the upper bout's right flank to just
    # beside the pegbox, so the .62 stick is visibly propped and stays inside the
    # declared footprint. The hair rides on the stick's far side, which leaves the
    # walnut stick facing the room instead of a bare ribbon of ivory.
    rod('Bow stick',(.145,.030,.100),(.038,.620,-.060),.005,'walnut')
    rod('Bow hair',(.131,.030,.090),(.024,.620,-.070),.0035,'ivory')
    ell('Bow frog',(.145,.032,.100),(.011,.014,.011),'dark',segments=12,ring_count=8)
    ell('Bow tip',(.039,.618,-.058),(.009,.013,.008),'ivory',segments=12,ring_count=8)

catalog={'rubbish_bin':rubbish_bin,'guitar':guitar,'violin':violin}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/furniture_props.blend')
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
HEIGHT={'rubbish_bin':.72,'guitar':1.05,'violin':.65}
SPAN={'rubbish_bin':.45,'guitar':.53,'violin':.47}
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
scene.world=bpy.data.worlds.new('Props review studio')
scene.world.color=(.30,.31,.33)
outdir=ROOT/'art/props_review'; outdir.mkdir(parents=True,exist_ok=True)
az,el=math.radians(38),math.radians(17)
for name in catalog:
    centre=bpy.data.objects[name].location+Vector((0,0,HEIGHT[name]/2))
    offset=Vector((math.sin(az),-math.cos(az),math.sin(el))).normalized()
    camera.location=centre+offset*(HEIGHT[name]*3.1)
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=max(SPAN[name]*1.30,HEIGHT[name]*4/3*1.16)
    scene.render.filepath=str(outdir/f'{name}.png')
    bpy.ops.render.render(write_still=True)
    print('JUSTLIFE_PROPS_REVIEW_RENDER', scene.render.filepath)
for o in studio:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_HOUSEHOLD_PROPS_COMPLETE', len(catalog))
