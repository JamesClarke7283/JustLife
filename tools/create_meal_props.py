"""Original JustLife garden supper. Run: blender -b --python tools/create_meal_props.py.

All paths are relative to this project. Blender is Z-up; GLB is metre-scaled Y-up.
Food remains an independently scalable node. The fork points toward Godot -Z.
"""
from pathlib import Path
import bpy
import bmesh
import math
import random
import json
import hashlib
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/meals"
EVIDENCE = ART / "studio"
MODELS = ROOT / "assets/models"
for path in [ART, EVIDENCE, MODELS]:
    path.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
asset_collection = bpy.data.collections.new("JustLife Garden Supper — editable originals")
scene.collection.children.link(asset_collection)
M = {}
ACTIVE = []


def material(name, color, roughness=.58, metal=0):
    rgb = [int(color[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metal
    M[name] = mat


for spec in [
    ("Cream stoneware", "EFE9DA", .29), ("Muted teal glaze", "537F76", .32),
    ("Toasted grain", "B48748", .67), ("Light grain", "D5AD68", .64),
    ("Golden squash", "D78B2F", .5), ("Roasted edge", "9A592A", .6),
    ("Carrot", "D88344", .52), ("Zucchini skin", "4E7151", .5),
    ("Zucchini flesh", "CED28B", .6), ("Seed", "EBE1B0", .59),
    ("Garden pea", "7E9F59", .52), ("Basil leaf", "55835A", .57),
    ("Basil vein", "82A26D", .62), ("Roasted tomato", "B95D47", .49),
    ("Tomato interior", "D18459", .55), ("Brushed steel", "8E9C9B", .31, .92),
    ("Ground", "E5DFD1", .78),
]:
    material(*spec)


def link(obj):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    asset_collection.objects.link(obj)
    ACTIVE.append(obj)
    return obj


def empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    asset_collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    obj.empty_display_size = .02
    ACTIVE.append(obj)
    return obj


def mesh(name, verts, faces, mat, parent=None, smooth=False):
    data = bpy.data.meshes.new(name + " geometry")
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=.0000001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    asset_collection.objects.link(obj)
    ACTIVE.append(obj)
    data.materials.append(M[mat])
    for face in data.polygons:
        face.use_smooth = smooth
    obj.parent = parent
    return obj


def bevel(obj, width=.001, segments=3):
    mod = obj.modifiers.new("Soft crafted edges", "BEVEL")
    mod.width = width
    mod.segments = segments
    obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    return obj


def lathe(name, profile, mat, parent, ellipse=1.0, segments=80):
    verts = [(r*math.cos(i*math.tau/segments), r*math.sin(i*math.tau/segments)*ellipse, z)
             for r, z in profile for i in range(segments)]
    faces = []
    for j in range(len(profile)):
        nxt = (j+1) % len(profile)
        for i in range(segments):
            k = (i+1) % segments
            faces.append((j*segments+i, j*segments+k, nxt*segments+k, nxt*segments+i))
    return mesh(name, verts, faces, mat, parent, True)


def tube(name, points, radius, mat, parent, sides=10, closed=False):
    verts = []
    for i, pt in enumerate(points):
        direction = Vector(points[(i+1) % len(points)])-Vector(points[i-1 if i else (-1 if closed else 0)])
        direction.normalize()
        axis = direction.cross(Vector((0, 0, 1)))
        if axis.length < .01:
            axis = direction.cross(Vector((1, 0, 0)))
        axis.normalize()
        other = direction.cross(axis).normalized()
        for j in range(sides):
            verts.append(Vector(pt)+radius*(math.cos(j*math.tau/sides)*axis+math.sin(j*math.tau/sides)*other))
    faces = []
    for i in range(len(points) if closed else len(points)-1):
        for j in range(sides):
            faces.append((i*sides+j, i*sides+(j+1)%sides, ((i+1)%len(points))*sides+(j+1)%sides, ((i+1)%len(points))*sides+j))
    if not closed:
        faces += [tuple(reversed(range(sides))), tuple((len(points)-1)*sides+j for j in range(sides))]
    return mesh(name, verts, faces, mat, parent, True)


def grain(name, p, scale, mat, parent, angle=0):
    # Small independent grains; joined for efficient runtime drawing after modeling.
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=p)
    obj = link(bpy.context.object)
    obj.name = name
    obj.scale = scale
    obj.rotation_euler.z = angle
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(M[mat])
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.parent = parent
    return obj


def prism(name, outline, height, mat, parent, position=(0, 0, 0), rotation=0, edge=.001):
    count = len(outline)
    verts = [(x, y, z) for z in [-height/2, height/2] for x, y in outline]
    faces = [tuple(reversed(range(count))), tuple(range(count, count*2))]
    faces += [(i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count)]
    obj = mesh(name, verts, faces, mat, parent)
    obj.location = position
    obj.rotation_euler.z = rotation
    if edge:
        bevel(obj, edge, 2)
    return obj


def squash(p, angle, parent, scale=1):
    outline = [(-.028, -.011), (.019, -.012), (.030, .002), (.011, .013), (-.025, .010)]
    outline = [(x*scale, y*scale) for x, y in outline]
    obj = prism("Roasted squash wedge", outline, .021*scale, "Golden squash", parent, p, angle, .003*scale)
    # Caramelized end and lengthwise roasting crease make a cut vegetable readable.
    for dx in [-.014, .013]:
        patch = prism("Squash roast mark", [(-.002, -.008), (.0015, -.007), (.002, .008), (-.001, .009)], .0007,
                      "Roasted edge", obj, (dx*scale, 0, .0107*scale), .1, .0005)


def zucchini(p, angle, parent, scale=1):
    count = 24
    radius = .022*scale
    outline = [(radius*math.cos(i*math.tau/count), radius*math.sin(i*math.tau/count)) for i in range(count)]
    obj = prism("Zucchini round with skin", outline, .008*scale, "Zucchini skin", parent, p, angle, .0007)
    flesh = [(x*.87, y*.87) for x, y in outline]
    prism("Fresh cut zucchini face", flesh, .0009, "Zucchini flesh", obj, (0, 0, .0043*scale), 0, .0003)
    for i in range(5):
        a = i*math.tau/5
        grain("Zucchini seed", (.009*scale*math.cos(a), .009*scale*math.sin(a), .0051*scale),
              (.0027*scale, .0012*scale, .0005), "Seed", obj, a)


def leaf(p, angle, parent, scale=1):
    verts = []
    for j in range(9):
        t = j/8
        width = math.sin(math.pi*t)**.8*.012*scale
        y = (t-.5)*.054*scale
        center_z = math.sin(t*math.pi)*.004*scale
        verts += [(-width, y, center_z-.002*scale), (0, y, center_z), (width, y, center_z-.002*scale)]
    faces = []
    for j in range(8):
        for k in range(2):
            faces.append((j*3+k, j*3+k+1, (j+1)*3+k+1, (j+1)*3+k))
    obj = mesh("Basil pointed leaf", verts, faces, "Basil leaf", parent, True)
    obj.location = p
    obj.rotation_euler.z = angle
    solid = obj.modifiers.new("Leaf thickness", "SOLIDIFY")
    solid.thickness = .0006
    tube("Basil midrib", [(0, (t/8-.5)*.052*scale, math.sin(t/8*math.pi)*.004*scale+.0005) for t in range(9)],
         .00045, "Basil vein", obj, 6)


def food(root, serving):
    bed = .026 if serving else .015
    group = empty("Food", (0, 0, bed), root)
    group["consumption_axis"] = "+Y in Godot"
    group["consumption_scale_min"] = 0.0
    rng = random.Random(911 if serving else 417)
    rx, ry = (.176, .126) if serving else (.080, .066)
    def edge_scale(angle):
        return 1 + (.05 if serving else .10)*math.sin(angle*3+.7) + .045*math.sin(angle*7-.4) + .024*math.cos(angle*13)

    def mound_height(x, y):
        angle = math.atan2(y/ry, x/rx)
        radius = math.sqrt((x/rx)**2+(y/ry)**2)/edge_scale(angle)
        # A piled, tapered bed with uneven lobes, without a biscuit-like vertical edge.
        envelope = max(0, 1-radius**1.65)
        height = (.033 if serving else .027)*envelope**.72
        height += .0025*math.sin(x*113+y*37)*math.cos(y*129-x*17)*envelope
        height += .003*math.exp(-((x/rx+.30)**2+(y/ry-.2)**2)*12)
        return height + (0 if serving else -.0025)

    # The perimeter is deliberately lobed, and surface height tapers into the dish.
    seg, rings = 48, 9
    verts = []
    for j in range(rings):
        r = j/(rings-1)
        for i in range(seg):
            a = i*math.tau/seg
            x = math.cos(a)*rx*r*edge_scale(a)
            y = math.sin(a)*ry*r*edge_scale(a)
            verts.append((x, y, mound_height(x, y)))
    faces = [(j*seg+i, j*seg+(i+1)%seg, (j+1)*seg+(i+1)%seg, (j+1)*seg+i)
             for j in range(rings-1) for i in range(seg)]
    obj = mesh("Garden grain bed", verts, faces, "Toasted grain", group, True)
    solid = obj.modifiers.new("Mound underside", "SOLIDIFY")
    solid.thickness = .0015
    for i in range(440 if serving else 155):
        a = rng.random()*math.tau
        r = math.sqrt(rng.random())*.99
        x, y = math.cos(a)*rx*r*edge_scale(a), math.sin(a)*ry*r*edge_scale(a)
        z = mound_height(x, y)+.0017
        grain("Toasted individual grain", (x, y, z), (.0045, .0022, .0019),
              "Light grain" if i%3 else "Toasted grain", group, rng.random()*math.tau)
    positions = [(-.11, -.054, .030), (.008, -.061, .04), (.097, .025, .035), (-.061, .066, .038)] if serving else [(-.037, -.025, .021), (.012, -.034, .024)]
    for i, p in enumerate(positions):
        p = (p[0], p[1], mound_height(p[0], p[1])+.010)
        squash(p, .35+i*1.4, group, 1.05 if serving else .85)
    positions = [(-.102, .023, .037), (.055, .065, .037), (.130, -.04, .026), (-.025, -.065, .036)] if serving else [(.043, .018, .022), (.012, .042, .028)]
    for i, p in enumerate(positions):
        p = (p[0], p[1], mound_height(p[0], p[1])+.0045)
        zucchini(p, .5+i, group, 1.12 if serving else .88)
    for i in range(12 if serving else 5):
        a = i*2.399+.2
        radius = (.12 if serving else .05)*(0.7 if i%2 else 1)
        x, y = math.cos(a)*radius, math.sin(a)*radius*.7
        p = (x, y, mound_height(x, y)+.005)
        prism("Bias cut carrot", [(-.013, -.005), (.008, -.008), (.014, .003), (-.008, .008)], .008,
              "Carrot", group, p, a, .002)
    for i in range(26 if serving else 12):
        a = rng.random()*math.tau
        r = .3+rng.random()*.7
        x, y = math.cos(a)*rx*r*.88, math.sin(a)*ry*r*.88
        z = mound_height(x, y)+.0045
        grain("Garden pea", (x, y, z), (.0048, .0048, .0045), "Garden pea", group)
    for i in range(7 if serving else 3):
        a = i*2.399+.8
        r = .67
        x, y = math.cos(a)*rx*r, math.sin(a)*ry*r
        p = (x, y, mound_height(x, y)+.006)
        tomato = prism("Roasted tomato quarter", [(-.012, -.007), (.010, -.006), (.014, .004), (0, .010)], .010,
                       "Roasted tomato", group, p, a, .003)
        prism("Tomato cut flesh", [(-.007, -.003), (.006, -.004), (.008, .003), (0, .006)], .0009,
              "Tomato interior", tomato, (0, 0, .0055), 0, .0005)
    leaf((-.029, .016, .05 if serving else .031), -.45, group, 1.05 if serving else .8)
    leaf((-.051, .008, .048 if serving else .029), .92, group, .85 if serving else .68)
    return group


def ceramic(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("MealServing" if serving else "MealPlate")
    root["original_artwork"] = "JustLife garden supper; original editable geometry"
    root["unit"] = "metre"
    root["bottom_y_m"] = 0.0
    root["food_node"] = "Food"
    root["width_m"] = .50 if serving else .30
    if serving:
        profile = [(0, .003), (.13, .003), (.15, 0), (.163, .003), (.181, .012), (.20, .034), (.212, .056),
                   (.213, .061), (.209, .065), (.203, .063), (.197, .05), (.182, .029), (.166, .018), (0, .018)]
        lathe("Hand glazed serving casserole", profile, "Cream stoneware", root, .78)
        lathe("Teal rolled serving rim", [(.204, .062), (.209, .066), (.214, .064), (.215, .060), (.211, .057), (.206, .058)], "Muted teal glaze", root, .78)
        for side in [-1, 1]:
            pts = [(side*(.194+.048*math.sin(t*math.pi)), -.052*math.cos(t*math.pi), .044+.002*math.sin(t*math.pi)) for t in [i/24 for i in range(25)]]
            tube("Open ceramic ear handle", pts, .0075, "Cream stoneware", root, 12)
            empty("GripLeft" if side < 0 else "GripRight", (side*.2395, 0, .046), root)
        root["grip_left_godot"] = [-.2395, .046, 0]
        root["grip_right_godot"] = [.2395, .046, 0]
        root["servings_nominal"] = 4
    else:
        profile = [(0, .003), (.064, .003), (.075, 0), (.083, .001), (.111, .008), (.14, .016), (.149, .020),
                   (.15, .023), (.148, .026), (.14, .026), (.12, .017), (.09, .012), (0, .012)]
        lathe("Shallow stoneware dinner plate", profile, "Cream stoneware", root)
        lathe("Fine teal plate rim", [(.144, .0254), (.148, .0264), (.149, .0256), (.148, .0248), (.144, .0249)], "Muted teal glaze", root)
        empty("Grip", (0, 0, .009), root)
        root["grip_godot"] = [0, .009, 0]
    food(root, serving)
    return root, ACTIVE.copy()


def fork():
    global ACTIVE
    ACTIVE = []
    root = empty("MealFork")
    root["unit"] = "metre"
    root["grip_godot"] = [0, 0, 0]
    root["bite_point_godot"] = [0, .003, -.14]
    root["forward_axis_godot"] = "-Z"
    root["food_facing_axis_godot"] = "+Y"
    root["original_artwork"] = "JustLife short four-tine dinner fork"
    # A shaped forged neck and handle with a flattened oval grip and real tine gaps.
    outline = [(-.003, -.058), (-.006, -.052), (-.007, -.031), (-.006, .006), (-.004, .049),
               (-.010, .077), (-.014, .089), (-.014, .101), (.014, .101), (.014, .089), (.010, .077),
               (.004, .049), (.006, .006), (.007, -.031), (.006, -.052), (.003, -.058)]
    body = prism("Forged fork handle and shoulder", outline, .0028, "Brushed steel", root, edge=.001)
    # Neck rises slightly above grip; tines hold food away from fingers.
    for v in body.data.vertices:
        v.co.z += max(0, min(1, (v.co.y-.04)/.06))*.003
    for i, x in enumerate([-.0105, -.0035, .0035, .0105]):
        outline = [(x-.0023, .095), (x-.0021, .129), (x-.0012, .1385), (x, .14),
                   (x+.0012, .1385), (x+.0021, .129), (x+.0023, .095)]
        prism("Fork tine %d" % (i+1), outline, .0023, "Brushed steel", root, (0, 0, .003), edge=.00065)
    prism("Muted teal handle inlay", [(-.0032, -.043), (-.0038, -.023), (-.0028, .016),
                                      (.0028, .016), (.0038, -.023), (.0032, -.043)], .0006,
          "Muted teal glaze", root, (0, 0, .00165), edge=.0007)
    empty("Grip", (0, 0, 0), root)
    empty("BitePoint", (0, .14, .003), root)
    return root, ACTIVE.copy()


def bake_runtime_mesh(name, source_objects, parent):
    """Merge source components while retaining editable originals in the .blend."""
    verts, faces, material_indices, smooth_faces, materials = [], [], [], [], []
    deps = bpy.context.evaluated_depsgraph_get()
    inverse = parent.matrix_world.inverted()
    for obj in source_objects:
        evaluated = obj.evaluated_get(deps)
        data = evaluated.to_mesh()
        matrix = inverse @ obj.matrix_world
        offset = len(verts)
        verts.extend(matrix @ v.co for v in data.vertices)
        for polygon in data.polygons:
            faces.append(tuple(offset+i for i in polygon.vertices))
            mat = data.materials[polygon.material_index]
            if mat not in materials: materials.append(mat)
            material_indices.append(materials.index(mat))
            smooth_faces.append(polygon.use_smooth)
        evaluated.to_mesh_clear()
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    for mat in materials: data.materials.append(mat)
    for i, polygon in enumerate(data.polygons):
        polygon.material_index = material_indices[i]
        polygon.use_smooth = smooth_faces[i]
    data.update()
    obj = bpy.data.objects.new(name, data)
    asset_collection.objects.link(obj)
    obj.parent = parent
    return obj


assets = [("meal_serving", *ceramic(True)), ("meal_plate", *ceramic(False)), ("meal_fork", *fork())]
for filename, root, objs in assets:
    # Blender requires globally unique names, whereas each GLB owns its namespace.
    # Canonical empty names are exported independently, then source names restored.
    empty_names = {obj: obj.name for obj in bpy.data.objects if obj.type == "EMPTY"}
    for obj, name in empty_names.items(): obj.name = "SOURCE_" + name
    for obj in objs:
        if obj.type == "EMPTY": obj.name = empty_names[obj].split(".")[0]
    bpy.context.view_layer.update()
    food_group = next((obj for obj in objs if obj.type == "EMPTY" and obj.name == "Food"), None)
    food_parts = set(food_group.children_recursive) if food_group else set()
    groups = [("FoodGeometry", [obj for obj in food_parts if obj.type == "MESH"], food_group)] if food_group else []
    groups.append(("DishGeometry" if food_group else "ForkGeometry", [obj for obj in objs if obj.type == "MESH" and obj not in food_parts], root))
    baked = [bake_runtime_mesh(name, parts, parent) for name, parts, parent in groups]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [obj for obj in objs if obj.type == "EMPTY"] + baked: obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(MODELS/(filename+".glb")), export_format="GLB",
                             use_selection=True, export_apply=True, export_extras=True,
                             export_yup=True, export_animations=False, export_cameras=False, export_lights=False)
    for obj in baked:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(data)
    for index, obj in enumerate(empty_names): obj.name = "RESTORE_EMPTY_%d" % index
    for obj, name in empty_names.items(): obj.name = name

# Move only the review scene roots after export; the GLBs keep canonical origins.
assets[0][1].location = (-.14, .13, 0)
assets[1][1].location = (.18, -.16, 0)
assets[2][1].location = (.385, -.15, .006)
assets[2][1].rotation_euler.z = -.2
studio = bpy.data.collections.new("Studio — excluded from exports")
scene.collection.children.link(studio)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.001))
ground = bpy.context.object
ground.name = "Studio ground"
ground.data.materials.append(M["Ground"])
for col in list(ground.users_collection): col.objects.unlink(ground)
studio.objects.link(ground)
bpy.ops.object.camera_add(location=(.81, -1.14, 1.12))
camera = bpy.context.object
camera.rotation_euler = (Vector((.03, 0, .02))-camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = .95
scene.camera = camera
for col in list(camera.users_collection): col.objects.unlink(camera)
studio.objects.link(camera)
for p, energy, size in [((-.55, -.40, 1.1), 55, .72), ((.75, .18, .85), 30, .60), ((-.1, .75, .75), 38, .50)]:
    bpy.ops.object.light_add(type="AREA", location=p)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, .02))-light.location).to_track_quat("-Z", "Y").to_euler()
    for col in list(light.users_collection): col.objects.unlink(light)
    studio.objects.link(light)
scene.world = bpy.data.worlds.new("Warm meal studio")
scene.world.use_nodes = True
scene.world.node_tree.nodes.get("Background").inputs[0].default_value = (.30, .32, .31, 1)
scene.world.node_tree.nodes.get("Background").inputs[1].default_value = .45
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = -1.15
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(EVIDENCE/"garden_supper_studio.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ART/"garden_supper.blend"))
bpy.ops.render.render(write_still=True)
manifest = {"original_artwork": True, "source": "art/meals/garden_supper.blend", "generator": "tools/create_meal_props.py",
            "source_sha256": hashlib.sha256((ART/"garden_supper.blend").read_bytes()).hexdigest(),
            "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "preview": "art/meals/studio/garden_supper_studio.png", "assets": {}}
for filename, root, objs in assets:
    path = MODELS/(filename+".glb")
    manifest["assets"][filename] = {"path": str(path.relative_to(ROOT)), "root": root.name,
                                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                    "objects": len(objs), "bytes": path.stat().st_size}
(ART/"manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
print("JUSTLIFE_MEAL_PROPS_READY", json.dumps(manifest))
