"""Original JustLife memorial props: an indoor ceramic urn and an outdoor carved stone gravestone.

Run:
  blender -b --python tools/create_memorial_props.py

Exports:
  assets/models/furnishing_urn.glb
  assets/models/furnishing_tombstone.glb
  art/props_review/furnishing_urn.png
  art/props_review/furnishing_tombstone.png
"""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(71)
bpy.ops.wm.read_factory_settings(use_empty=True)

M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb = [int(hexcolor[i:i+2], 16)/255 for i in (0, 2, 4)]
    linear = [v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*linear, 1)
    m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = m.diffuse_color
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if emit:
        b.inputs['Emission Color'].default_value = m.diffuse_color
        b.inputs['Emission Strength'].default_value = emit
    M[name] = m
    return m

for n, h in [
    ('granite', '52555A'),
    ('slate', '383B40'),
    ('marble_white', 'F5F3ED'),
    ('ceramic_teal', '3E6B65'),
    ('gold_leaf', 'D4AF37'),
    ('brass_trim', 'B8934A'),
    ('stone_base', '44474D'),
    ('flower_white', 'FCFBF7'),
    ('flower_leaf', '4B6E40'),
    ('flower_gold', 'E2BA54'),
    ('black_slate', '222428')
]:
    mat(n, h)

M['gold_leaf'].node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value = .75
M['gold_leaf'].node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .30
M['brass_trim'].node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value = .60
M['ceramic_teal'].node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .25

active = []
def xyz(p): return (p[0], -p[2], p[1])

def finish(o, n, m):
    o.name = n
    o.data.materials.append(M[m])
    active.append(o)
    return o

def box(n, p, s, m, bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o = bpy.context.object
    o.dimensions = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = 'ANGLE'
    return finish(o, n, m)

def ell(n, p, s, m, segments=24, ring_count=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=ring_count, location=xyz(p))
    o = bpy.context.object
    o.scale = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for f in o.data.polygons: f.use_smooth = True
    return finish(o, n, m)

def cyl(n, p, r, h, m, top=None, axis='y', verts=32, bevel=.004):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if top is None else top, depth=h, location=xyz(p))
    o = bpy.context.object
    if axis == 'z': o.rotation_euler = (math.pi/2, 0, 0)
    elif axis == 'x': o.rotation_euler = (0, math.pi/2, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if bevel:
        mod = o.modifiers.new('Bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = 'ANGLE'
    for f in o.data.polygons: f.use_smooth = True
    return finish(o, n, m)

def torus(n, p, major, minor, m, axis='y', major_segments=32, minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(major_segments=major_segments, minor_segments=minor_segments, major_radius=major, minor_radius=minor, location=xyz(p))
    o = bpy.context.object
    if axis == 'z': o.rotation_euler = (math.pi/2, 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    for f in o.data.polygons: f.use_smooth = True
    return finish(o, n, m)

def build_urn():
    # Elegant ceramic indoor urn standing on a small carved brass-footed plinth.
    box('Urn Plinth', (0, .015, 0), (.22, .03, .22), 'slate', bevel=.006)
    cyl('Urn Foot Ring', (0, .035, 0), .085, .012, 'brass_trim', bevel=.003)
    cyl('Urn Lower Foot', (0, .055, 0), .078, .028, 'ceramic_teal', top=.065)
    torus('Urn Foot Trim', (0, .070, 0), .067, .005, 'gold_leaf')
    ell('Urn Body Lower', (0, .140, 0), (.115, .095, .115), 'ceramic_teal')
    ell('Urn Body Upper', (0, .215, 0), (.122, .085, .122), 'ceramic_teal')
    torus('Urn Gold Band Upper', (0, .250, 0), .110, .006, 'gold_leaf')
    torus('Urn Gold Band Lower', (0, .120, 0), .100, .005, 'gold_leaf')
    cyl('Urn Neck', (0, .285, 0), .082, .045, 'ceramic_teal', top=.072)
    torus('Urn Collar Rim', (0, .310, 0), .080, .007, 'brass_trim')
    ell('Urn Lid Dome', (0, .335, 0), (.075, .035, .075), 'ceramic_teal')
    cyl('Urn Lid Rim', (0, .318, 0), .082, .010, 'gold_leaf', bevel=.002)
    ell('Urn Lid Finial', (0, .370, 0), (.018, .026, .018), 'gold_leaf')
    cyl('Urn Lid Stem', (0, .352, 0), .007, .012, 'gold_leaf', bevel=.001)

def build_tombstone():
    # Outdoor stone gravestone with stepped plinth, rounded arched headstone,
    # carved inscription panel, and floral tribute relief.
    box('Grave Base Lower', (0, .04, 0), (.56, .08, .36), 'stone_base', bevel=.015)
    box('Grave Base Upper', (0, .11, 0), (.48, .06, .30), 'granite', bevel=.012)
    box('Grave Tablet', (0, .45, 0), (.38, .62, .12), 'granite', bevel=.018)
    cyl('Grave Crest Arch', (0, .76, 0), .19, .12, 'granite', axis='z', verts=32, bevel=.015)
    box('Grave Plaque Inset', (0, .46, .056), (.30, .40, .012), 'black_slate', bevel=.005)
    box('Grave Inset Trim Top', (0, .665, .058), (.31, .015, .014), 'gold_leaf', bevel=.002)
    box('Grave Inset Trim Bottom', (0, .255, .058), (.31, .015, .014), 'gold_leaf', bevel=.002)
    box('Grave Inset Trim Left', (-.152, .46, .058), (.015, .425, .014), 'gold_leaf', bevel=.002)
    box('Grave Inset Trim Right', (.152, .46, .058), (.015, .425, .014), 'gold_leaf', bevel=.002)
    ell('Grave Flower Center', (0, .74, .058), (.022, .022, .010), 'flower_gold')
    for i in range(5):
        ang = i * (2 * math.pi / 5)
        fx = math.cos(ang) * .038
        fy = .74 + math.sin(ang) * .038
        ell(f'Grave Petal {i}', (fx, fy, .058), (.016, .016, .008), 'flower_white')
    ell('Grave Ground Leaf L', (-.12, .145, .12), (.045, .015, .070), 'flower_leaf')
    ell('Grave Ground Leaf R', (.12, .145, .12), (.050, .016, .065), 'flower_leaf')
    ell('Grave Ground Blossom', (0, .155, .13), (.030, .025, .030), 'flower_white')

catalog = {
    'furnishing_urn': build_urn,
    'furnishing_tombstone': build_tombstone,
}

HEIGHT = {'furnishing_urn': .40, 'furnishing_tombstone': .90}
SPAN = {'furnishing_urn': .30, 'furnishing_tombstone': .65}

outdir = ROOT / 'art/props_review'
outdir.mkdir(parents=True, exist_ok=True)
models_dir = ROOT / 'assets/models'
models_dir.mkdir(parents=True, exist_ok=True)

for idx, (name, fn) in enumerate(catalog.items()):
    active = []
    fn()
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for o in active:
        if o.parent is None:
            o.parent = root
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for o in active:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    out_path = models_dir / f'{name}.glb'
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_animations=False
    )
    print(f'EXPORTED {name} -> {out_path}')
    root.location = (idx * 3, 0, 0)

# Studio review renders
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -.002))
backdrop = bpy.context.object
backdrop.data.materials.append(mat('review_backdrop', 'E9E7DC'))
studio = [backdrop]

bpy.ops.object.camera_add()
camera = bpy.context.object
camera.data.type = 'ORTHO'
bpy.context.scene.camera = camera
studio.append(camera)

for pos, energy, size in [((-.9, -1.3, 2.6), 120, 1.5), ((1.6, -0.7, 1.3), 45, 1.0), ((0.2, 1.8, 1.1), 30, 1.0)]:
    loc = Vector(pos)
    bpy.ops.object.light_add(type='AREA', location=loc)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (-loc).to_track_quat('-Z', 'Y').to_euler()
    studio.append(light)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.world = bpy.data.worlds.new('Props review studio')
scene.world.color = (.30, .31, .33)

az, el = math.radians(38), math.radians(17)
for name in catalog:
    centre = bpy.data.objects[name].location + Vector((0, 0, HEIGHT[name]/2))
    offset = Vector((math.sin(az), -math.cos(az), math.sin(el))).normalized()
    camera.location = centre + offset * (HEIGHT[name] * 3.1)
    camera.rotation_euler = (centre - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = max(SPAN[name]*1.30, HEIGHT[name]*1.25)
    render_target = outdir / f'{name}.png'
    scene.render.filepath = str(render_target)
    bpy.ops.render.render(write_still=True)
    print(f'PROPS_REVIEW_RENDER {render_target}')

print('MEMORIAL_PROPS_COMPLETE')
