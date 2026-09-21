"""Original JustLife vehicles, iteration 66: a detached two-car garage and a
modern electric car. Run: blender -b --python tools/create_vehicles_v66.py.

Coordinates are Godot metres: x right, y up, z toward the front of the piece.
The garage faces +z (the door opening, header and rolled-up sectional panel are
at +z, the solid back wall at -z) so a car drives in toward -z and the whole
interior reads from the street. The electric car also faces +z: its bonnet,
smooth nose and light bar are at +z and its boot deck at -z. Both pieces are
built on the palette, the soft-bevel box / smooth cylinder construction, the
per-model root Empty and the use_selection glTF export of
tools/create_kitchen_props_v65.py, and each primitive helper names its axis in
Godot terms, so a disc's facing is never a guess: axis='y' stacks the piece
along +y (the disc lies flat), axis='z' makes the disc face the room, axis='x'
points it right. ramp() adds the one construction the vehicles needed that the
furniture helpers lacked: a plate strung between two y/z points, used for the
raked windscreen, the sloping tailgate glass and the A pillars that follow it.

Every part bottom sits on y=0 and the roof cap tops out below the declared
heights, so the game can drop either piece straight onto the lot floor. The
garage's interior stay-clear volume (x -2.0..+2.0, z -2.5..+2.5) holds nothing
but the 60 mm floor slab, so two 1.80 m cars park side by side.
"""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(66)
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
# The four car surfaces the game names when it repaints a vehicle. Body is the
# paint and Glass the glazing, so those two must keep those exact names.
mat('Body','C6D2DA',.22,.45); mat('Glass','5E7C8A',.14,.15)
mat('Tyre','22262B',.88,0); mat('Hub','D5D8D6',.30,.60)
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
def cyl(n,p,r,h,m,top=None,axis='y',verts=32,bevel=.005):
    bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    if axis=='z':o.rotation_euler=(math.pi/2,0,0)
    elif axis=='x':o.rotation_euler=(0,math.pi/2,0)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
    if bevel:
        mod=o.modifiers.new('Rounded rims','BEVEL'); mod.width=bevel; mod.segments=2; mod.limit_method='ANGLE'
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
def ramp(n,za,ya,zb,yb,w,thick,m,bevel=.02,x=0.0,extend=0.0):
    # A plate whose +z edge is the point (za, ya) and whose -z edge is (zb, yb),
    # so it descends toward +z when ya < yb (the windscreen rake) and toward -z
    # when the front edge is the high one (the tailgate glass). tilt() leans the
    # +z edge down, which is exactly atan2 of the two edge heights over the
    # z span; the plate's thickness is normal to the slope, not vertical.
    dz,dy=za-zb,yb-ya
    o=box(n,(x,(ya+yb)/2,(za+zb)/2),(w,thick,math.hypot(dz,dy)+extend),m,bevel)
    return tilt(o,math.atan2(dy,dz))

# ---------------------------------------------------------------- Garage
def garage():
    # A detached two-car garage on a 4.60 x 5.80 m pad, 2.59 m to the ridge cap
    # so the 2.60 m footprint is never broken. Four corner posts on a .12 thick
    # shell: the back wall (-z) and both side walls are solid, the front (+z) is
    # a 4.28 m wide opening between the posts with the header over it, and the
    # sectional door is rolled up under that header, so the opening stays clear
    # to 1.99 m and a car drives straight in. Only the .06 floor slab sits
    # inside the x -2.0..+2.0, z -2.5..+2.5 stay-clear volume, and the door
    # tracks hug the side walls at x +-.12 so nothing narrows the two bays.
    box('Garage floor slab',(0,.030,0),(4.59,.060,5.79),'graphite',.020)
    box('Garage back wall',(0,1.130,-2.835),(4.59,2.14,.12),'cream',.030)
    for s in (-1,1):
        box('Garage side wall',(s*2.235,1.130,0),(.12,2.14,5.79),'cream',.030)
        for z in (2.815,-2.815):
            box('Garage corner post',(s*2.215,1.130,z),(.16,2.14,.16),'teal',.020)
        box('Garage door track',(s*2.115,2.145,-.050),(.05,.06,5.60),'steel',.008)
    box('Garage door header',(0,2.125,2.765),(4.43,.15,.15),'teal',.020)
    box('Garage door panel',(0,1.980,2.815),(4.20,.16,.10),'white',.025)
    for y in (1.945,1.985,2.025):
        rod('Garage door slat',(-2.08,y,2.868),(2.08,y,2.868),.012,'graphite')
    box('Garage sign',(0,2.125,2.845),(1.30,.13,.03),'cream',.006)
    box('Garage sign stripe',(0,2.125,2.862),(1.10,.05,.012),'teal',.003)
    box('Garage roof slab',(0,2.320,0),(4.59,.24,5.79),'teal',.040)
    box('Garage roof cap',(0,2.480,0),(4.50,.08,5.70),'dark',.020)
    box('Garage ridge cap',(0,2.555,0),(.26,.07,5.79),'dark',.025)

# ---------------------------------------------------------------- Electric car
def electric_car():
    # A modern electric car on a 1.80 x 4.20 m footprint, 1.48 m to the roof:
    # no grille, just a smooth nose with a full-width light bar and a matching
    # bar at the tail. The bonnet (top .91) sits below the beltline (.94) so the
    # glasshouse reads: 54 degree windscreen, a 1.70 m roof, a 30 degree
    # tailgate over a short rear deck. The lower body is split into a rocker
    # between the arches and two valances, so all four .335 wheels stand in
    # open arches with their tyre walls proud of the .87 body, hub caps out to
    # .889 and only the .895 wing mirrors reaching the declared width.
    box('Car underbody',(0,.300,0),(1.32,.16,3.96),'graphite',.020)
    box('Car rocker',(0,.470,-.030),(1.74,.34,1.91),'Body',.100)
    box('Car front valance',(0,.470,1.878),(1.74,.34,.405),'Body',.070)
    box('Car rear valance',(0,.470,-1.908),(1.74,.34,.345),'Body',.070)
    box('Car beltline',(0,.790,-.015),(1.74,.30,4.14),'Body',.090)
    box('Car sill cladding',(0,.420,-.030),(1.50,.12,1.85),'graphite',.005)
    for s in (-1,1):
        for z in (1.300,-1.360):box('Car arch eyebrow',(s*.874,.660,z),(.012,.08,.80),'graphite',.004)
        box('Car sill cladding',(s*.873,.420,-.030),(.02,.12,1.85),'graphite',.005)
        box('Car door seam front',(s*.872,.720,.620),(.008,.56,.02),'graphite',0)
        box('Car door seam rear',(s*.872,.720,-.600),(.008,.56,.02),'graphite',0)
        box('Car mirror arm',(s*.850,.935,.550),(.065,.07,.075),'graphite',.008)
        box('Car mirror housing',(s*.872,.985,.505),(.046,.11,.13),'Body',.012)
        box('Car mirror glass',(s*.872,.985,.437),(.038,.085,.012),'mirror_glass',.002)
        for z in (.300,-.900):box('Car door handle',(s*.875,.860,z),(.014,.05,.15),'steel',.003)
    box('Car hood',(0,.800,1.440),(1.70,.22,1.22),'Body',.090)
    box('Car cowl',(0,.900,.700),(1.68,.06,.12),'graphite',.012)
    box('Car roof',(0,1.440,-.030),(1.70,.075,.86),'Body',.060)
    box('Car nose',(0,.660,1.985),(1.70,.44,.20),'Body',.080)
    box('Car front bumper',(0,.440,1.980),(1.64,.24,.18),'graphite',.050)
    box('Car front light bar',(0,.800,2.072),(1.40,.055,.045),'bulb',.008)
    box('Car front plate',(0,.440,2.075),(.38,.11,.02),'cream',.003)
    box('Car rear light bar',(0,.860,-2.072),(1.42,.05,.045),'ember',.008)
    box('Car rear plate',(0,.440,-2.075),(.38,.11,.02),'cream',.003)
    box('Car rear diffuser',(0,.360,-2.030),(1.30,.14,.12),'graphite',.020)
    # The glazing, then the pillars that follow the same two rakes.
    ramp('Car windscreen',.700,.930,.360,1.400,1.62,.045,'Glass',.012)
    ramp('Car tailgate glass',-.460,1.420,-1.560,.955,1.66,.045,'Glass',.012)
    for s in (-1,1):
        ramp('Car A pillar',.700,.930,.360,1.400,.075,.055,'Body',.008,x=s*.790,extend=.020)
        box('Car B pillar',(s*.818,1.190,-.070),(.055,.36,.06),'Body',.008)
        box('Car front side window',(s*.815,1.190,.190),(.045,.34,.42),'Glass',.012)
        box('Car rear side window',(s*.815,1.190,-.280),(.045,.34,.34),'Glass',.012)
        for z in (1.300,-1.360):
            cyl('Car tyre',(s*.775,.335,z),.335,.20,'Tyre',axis='x',verts=32,bevel=.030)
            cyl('Car hub',(s*.862,.335,z),.185,.035,'Hub',axis='x',verts=24,bevel=.008)
            cyl('Car hub centre',(s*.878,.335,z),.055,.022,'steel',axis='x',verts=14,bevel=.004)
        box('Car headlamp',(s*.620,.760,2.068),(.26,.10,.05),'bulb',.010)
        box('Car tail lamp',(s*.630,.620,-2.068),(.28,.10,.05),'ember',.010)
    rod('Car wiper',(-.450,.935,.685),(.100,.935,.685),.008,'graphite')
    box('Car charge flap',(-.874,.800,-1.550),(.012,.17,.20),'graphite',.004)
    cyl('Car charge hinge',(-.876,.690,-1.550),.022,.014,'steel',axis='x',verts=12,bevel=.004)

# The exported file name is the catalogue kind the game loads, so the two-car
# garage ships as `car_garage.glb` rather than the internal name `garage`, which
# is already taken by the older five-style garage family.
EXPORT_NAME={'garage':'car_garage','electric_car':'electric_car'}
catalog={'garage':garage,'electric_car':electric_car}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/vehicles_v66.blend')
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
    out=ROOT/'assets/models'/f'{EXPORT_NAME[name]}.glb'
    bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    print('JUSTLIFE_VEHICLES_EXPORT', name, out.stat().st_size)
    root.location=((idx%6)*4,(idx//6)*4,0)

# Review renders are not part of the exported assets: a studio of three area
# lights plus a sun, shot on a 3/4 view from the front right, orthographic so
# each piece is framed to its own declared height.
HEIGHT={'garage':2.60,'electric_car':1.50}
SPAN={'garage':6.40,'electric_car':4.40}
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
world=bpy.data.worlds.new('Vehicles review studio'); world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
bg.inputs['Color'].default_value=(.30,.31,.33,1); bg.inputs['Strength'].default_value=1.0
scene.world=world
outdir=ROOT/'art/vehicles_v66_review'; outdir.mkdir(parents=True,exist_ok=True)
az,el=math.radians(38),math.radians(17)
for name in catalog:
    centre=bpy.data.objects[name].location+Vector((0,0,HEIGHT[name]/2))
    offset=Vector((math.sin(az),-math.cos(az),math.sin(el))).normalized()
    camera.location=centre+offset*(HEIGHT[name]*3.1)
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=max(SPAN[name]*1.30,HEIGHT[name]*4/3*1.16)
    scene.render.filepath=str(outdir/f'{name}.png')
    bpy.ops.render.render(write_still=True)
    print('JUSTLIFE_VEHICLES_REVIEW_RENDER', scene.render.filepath)
for o in studio:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_VEHICLES_V66_COMPLETE', len(catalog))
