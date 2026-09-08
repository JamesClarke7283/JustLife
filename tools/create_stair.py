"""Original JustLife Juniper stair. Blender background, private study only.

Godot local coordinates: bottom front edge (0,0,0), ascent along +Z,
15 risers of .20m, .25m going, 1.25m total width. World adds level datum.
"""
from pathlib import Path
import argparse, hashlib, json, math, sys
import bpy, bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art/architecture"
parser = argparse.ArgumentParser()
parser.add_argument("--render", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
asset = bpy.data.collections.new("Juniper stair — authored geometry")
bpy.context.scene.collection.children.link(asset)
studio = bpy.data.collections.new("Studio — excluded from export")
bpy.context.scene.collection.children.link(studio)
objects, anchors, materials = [], {}, {}

def xyz(v):
    return (v[0], -v[2], v[1])

def color(name, value, roughness=.65, metallic=0):
    rgb = [int(value[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    shader = m.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = m.diffuse_color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    materials[name] = m

for spec in [("warm oak", "BC9369"), ("oak endgrain", "A77F56"),
             ("warm plaster", "EFE9DA"), ("sage joinery", "557A6B"),
             ("soft brass", "BB9A5E", .4, .6), ("studio stone", "D8D9CF")]:
    color(*spec)

def own(o, collection):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    collection.objects.link(o)

def finish(o, name, material, bevel=0, collection=asset):
    o.name = name
    own(o, collection)
    o.data.materials.append(materials[material])
    if bevel:
        mod = o.modifiers.new("Small crafted edge", "BEVEL")
        mod.width, mod.segments = bevel, 2
        mod = o.modifiers.new("Weighted planar normals", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    if collection == asset:
        objects.append(o)
    return o

def box(name, center, size, material, bevel=.006, collection=asset):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(center))
    o = bpy.context.object
    o.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, name, material, bevel, collection)

def prism(name, x0, x1, profile, material, bevel=0):
    # Profile is (along,height); a single closed stair section, not floating boxes.
    vertices = [xyz((x, y, z)) for x in (x0, x1) for z, y in profile]
    n = len(profile)
    faces = [tuple(range(n-1, -1, -1)), tuple(range(n, 2*n))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    asset.objects.link(o)
    return finish(o, name, material, bevel)

def beam(name, start, end, width, thickness, material, bevel=.006):
    a, b = Vector(xyz(start)), Vector(xyz(end))
    o = box(name, (0, 0, 0), (width, (b-a).length, thickness), material, bevel)
    o.location = (a+b)/2
    o.rotation_euler = (b-a).to_track_quat("Z", "Y").to_euler()
    return o

def anchor(name, position):
    o = bpy.data.objects.new(name, None)
    asset.objects.link(o)
    o.location = xyz(position)
    o.empty_display_size = .035
    o.empty_display_type = "PLAIN_AXES"
    objects.append(o)
    anchors[name] = list(position)

profile = [(0, 0), (3.75, 0), (3.75, 3-.035)]
for index in range(14, -1, -1):
    profile.append((index*.25, (index+1)*.2-.035))
    if index:
        profile.append((index*.25, index*.2-.035))
prism("Closed plaster stair body", -.563, .563, profile, "warm plaster", .002)

for index in range(15):
    front = index*.25 - (.012 if index else 0)
    rear = (index+1)*.25
    top = (index+1)*.2
    box("Oak tread %02d" % (index+1), (0, top-.0175, (front+rear)/2),
        (1.135, .035, rear-front), "warm oak", .005)
    # A restrained endgrain band at the rounded front nose.
    box("Tread nose %02d" % (index+1), (0, top-.021, front+.007),
        (1.116, .012, .007), "oak endgrain", .002)
    anchor("Tread_%02d" % (index+1), (0, top, index*.25+.125))

for side in (-1, 1):
    x = side*.585
    prism("Sage side stringer %s" % side, x-.035, x+.035,
          [(0, 0), (3.75, 2.87), (3.75, 3.11), (0, .11)], "sage joinery", .005)
    for suffix, z, base, top in [("lower", .10, 0, 1.21), ("upper", 3.65, 2.84, 4.05)]:
        box("%s newel %s" % (suffix, side), (x, (base+top)/2, z),
            (.068, top-base, .068), "sage joinery", .007)
        box("%s newel foot %s" % (suffix, side), (x, base+.075, z),
            (.078, .15, .086), "sage joinery", .005)
        box("%s oak newel cap %s" % (suffix, side), (x, top+.018, z),
            (.078, .036, .085), "warm oak", .007)
        box("%s inset brass collar %s" % (suffix, side), (x, top-.115, z),
            (.069, .018, .070), "soft brass", .002)
    beam("Continuous oak handrail %s" % side, (x, 1.17, .10), (x, 4.01, 3.65),
         .072, .055, "warm oak", .009)
    for index in range(28):
        z = .1875 + .125*index
        base = math.ceil(z/.25)*.2-.055
        top = 1.09+.8*z
        box("Baluster %s %02d" % (side, index), (x, (base+top)/2, z),
            (.025, top-base, .025), "warm plaster", .003)

anchor("LowerLanding", (0, 0, -.5))
anchor("RunBegin", (0, 0, 0))
anchor("RunEnd", (0, 3, 3.75))
anchor("UpperLanding", (0, 3, 4.25))

bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
triangles, vertices, bounds = 0, 0, []
for o in objects:
    if o.type != "MESH":
        continue
    evaluated = o.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    triangles += len(mesh.loop_triangles)
    vertices += len(mesh.vertices)
    bm = bmesh.new(); bm.from_mesh(mesh)
    assert all(e.is_manifold for e in bm.edges), o.name
    assert all(f.area > 1e-10 for f in mesh.polygons), o.name
    bm.free()
    bounds.extend(evaluated.matrix_world @ v.co for v in mesh.vertices)
    evaluated.to_mesh_clear()
physical_min = [min(v[i] for v in bounds) for i in range(3)]
physical_max = [max(v[i] for v in bounds) for i in range(3)]
assert max(abs(physical_min[0]), abs(physical_max[0])) <= .62501
assert physical_min[1] >= -3.751 and physical_max[1] <= .001
assert physical_min[2] >= -.001
assert triangles < 40000, triangles

# Keep the editable pieces in Blender, batch the static export by material.
# Evaluated copies retain actual bevel geometry and normals; landmarks stay named.
export_objects=[]
for material_name in sorted({o.data.materials[0].name for o in objects if o.type=="MESH"}):
    copies=[]
    for original in objects:
        if original.type!="MESH" or original.data.materials[0].name!=material_name:continue
        mesh=bpy.data.meshes.new_from_object(original.evaluated_get(depsgraph),depsgraph=depsgraph)
        duplicate=bpy.data.objects.new("Export part",mesh)
        asset.objects.link(duplicate);duplicate.matrix_world=original.matrix_world.copy();copies.append(duplicate)
    bpy.ops.object.select_all(action="DESELECT")
    for duplicate in copies:duplicate.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join()
    combined=bpy.context.object;combined.name="Juniper "+material_name;export_objects.append(combined)
bpy.ops.object.select_all(action="DESELECT")
for o in export_objects+[o for o in objects if o.type=="EMPTY"]:o.select_set(True)
bpy.context.view_layer.objects.active=export_objects[0]
glb = ROOT / "assets/models/juniper_stair.glb"
bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                          export_apply=True, export_animations=False, export_extras=True,
                          export_yup=True)
export_count=len(export_objects)
for duplicate in export_objects:bpy.data.objects.remove(duplicate,do_unlink=True)
metadata = {"status":"Private architecture candidate, not playable or promoted",
            "origin":"Lower run front edge; ascent +Z; Y relative to lower walk datum",
            "width":1.25, "run":3.75, "rise":3, "risers":15, "going":.25,
            "riser":.2, "minimum_rail_clear_width":1.098, "anchors":anchors,
            "triangles":triangles, "vertices":vertices,
            "authored_mesh_objects":sum(o.type=="MESH" for o in objects), "exported_mesh_objects":export_count,
            "glb_sha256":hashlib.sha256(glb.read_bytes()).hexdigest(),
            "generator_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(OUT/"stair_geometry.json").write_text(json.dumps(metadata, indent=2))

box("Studio ground", (0, -.04, 1.5), (8, .08, 9), "studio stone", .01, studio)
# A cutaway upper landing shows the real endpoint and stairwell opening.
box("Upper landing slab", (0, 2.92, 4.425), (3, .16, 1.35), "warm plaster", .004, studio)
box("Landing support wall", (0, 1.42, 5.035), (3, 2.84, .13), "warm plaster", .004, studio)
world = bpy.data.worlds.new("Soft daylight")
bpy.context.scene.world = world; world.use_nodes=True
world.node_tree.nodes["Background"].inputs["Color"].default_value=(.72,.78,.77,1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value=.65
for name, p, energy, size in [("Broad daylight",(-3,7,-2),1250,5),
                               ("Soft fill",(5,5,1),650,4)]:
    data=bpy.data.lights.new(name,"AREA");data.energy=energy;data.shape="DISK";data.size=size
    light=bpy.data.objects.new(name,data);studio.objects.link(light);light.location=xyz(p)
    light.rotation_euler=(Vector(xyz((0,1.5,2)))-light.location).to_track_quat("-Z","Y").to_euler()
camera_data=bpy.data.cameras.new("Architecture review")
camera=bpy.data.objects.new("Architecture review",camera_data);studio.objects.link(camera)
bpy.context.scene.camera=camera;camera_data.type="ORTHO";camera_data.ortho_scale=7.3
scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.samples=48
scene.cycles.use_denoising=True;scene.render.resolution_x=1280;scene.render.resolution_y=1000
scene.render.resolution_percentage=100;scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="AgX"
views=[("stair_hero",(6,5,-5),(0,1.75,2)),("stair_side",(7,3,1.875),(0,1.8,1.875))]
for name,p,target in views:
    camera.location=xyz(p)
    camera.rotation_euler=(Vector(xyz(target))-camera.location).to_track_quat("-Z","Y").to_euler()
    if name=="stair_hero":
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/"juniper_stair.blend"))
    if args.render:
        scene.render.filepath=str(OUT/(name+".png"));bpy.ops.render.render(write_still=True)
print("STAIR_ART_OK",json.dumps({k:v for k,v in metadata.items() if k!="anchors"}))
