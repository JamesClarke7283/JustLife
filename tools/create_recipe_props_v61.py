"""JustLife mushroom soup and berry crumble art, Blender 5.2.1.

    blender -b --python tools/create_recipe_props_v61.py

Adds two recipes to the cookbook. It is a separate script from
`tools/create_recipe_props.py` on purpose: that file is the reviewed, pinned
generator for the herb-pasta and harvest-bake art, and extending it would mean
re-running its export chain over assets that are already qualified. This script
authors only the two new dishes and writes only their four GLBs, so the existing
assets are never rewritten.

It reuses the shared construction vocabulary (lathe/tube/prism/rounded_loft)
by importing nothing and simply re-declaring the small helpers it needs, keeping
the same metre scale and Y-up export the other dishes use.
"""
from pathlib import Path
import bpy, bmesh, math, random, json, hashlib
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/recipes"
EVIDENCE = ART / "studio"
MODELS = ROOT / "assets/models"
for directory in (ART, EVIDENCE, MODELS):
    directory.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
asset_collection = bpy.data.collections.new("JustLife recipe v61 — editable originals")
scene.collection.children.link(asset_collection)
M = {}
ACTIVE = []


def material(name, color, roughness=.58, metal=0):
    rgb = [int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    rgb = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metal
    M[name] = mat


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
    if parent:
        obj.parent = parent
    obj.data.materials.append(M[mat] if isinstance(mat, str) else mat)
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    return obj


def lathe(name, profile, mat, parent, ellipse=1.0, segments=80):
    """Revolve a (radius, height) profile about Z."""
    verts = []
    for r, z in profile:
        for i in range(segments):
            a = 2 * math.pi * i / segments
            verts.append((r * math.sin(a), r * ellipse * math.cos(a), z))
    faces = []
    rings = len(profile)
    for ring in range(rings - 1):
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((ring * segments + i, ring * segments + j,
                          (ring + 1) * segments + j, (ring + 1) * segments + i))
    return mesh(name, verts, faces, mat, parent, True)


def prism(name, outline, height, mat, parent, position=(0, 0, 0), rotation=0, edge=.001):
    """Extrude a 2D outline upward, with a rounded top edge."""
    n = len(outline)
    verts = []
    for x, y in outline:
        verts.append((x, y, 0.0))
    for x, y in outline:
        verts.append((x * (1 - edge), y * (1 - edge), height))
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(range(n, 2 * n)))
    obj = mesh(name, verts, faces, mat, parent, True)
    obj.location = position
    obj.rotation_euler = (0, 0, rotation)
    return obj


def rounded_outline(hx, hy, radius, segments=9):
    """A rounded rectangle outline, used for cut-food silhouettes."""
    pts = []
    corners = [(hx - radius, hy - radius, 0), (-(hx - radius), hy - radius, math.pi / 2),
               (-(hx - radius), -(hy - radius), math.pi), (hx - radius, -(hy - radius), 3 * math.pi / 2)]
    for cx, cy, start in corners:
        for i in range(segments + 1):
            a = start + (math.pi / 2) * i / segments
            pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return pts


def tube(name, points, radius, mat, parent, sides=10, closed=False):
    """A swept tube through a polyline."""
    verts = []
    faces = []
    for index, point in enumerate(points):
        p = Vector(point)
        ahead = Vector(points[min(index + 1, len(points) - 1)])
        behind = Vector(points[max(index - 1, 0)])
        tangent = (ahead - behind)
        if tangent.length < 1e-9:
            tangent = Vector((0, 0, 1))
        tangent.normalize()
        up = Vector((0, 0, 1)) if abs(tangent.z) < .9 else Vector((1, 0, 0))
        side = tangent.cross(up).normalized()
        up2 = side.cross(tangent).normalized()
        for k in range(sides):
            a = 2 * math.pi * k / sides
            verts.append(tuple(p + side * (radius * math.cos(a)) + up2 * (radius * math.sin(a))))
    for index in range(len(points) - 1):
        for k in range(sides):
            k1 = (k + 1) % sides
            faces.append((index * sides + k, index * sides + k1,
                          (index + 1) * sides + k1, (index + 1) * sides + k))
    obj = mesh(name, verts, faces, mat, parent, True)
    return obj


def metadata(root, recipe, serving):
    root["original_artwork"] = "JustLife original " + recipe + "; modeled without external assets"
    root["unit"] = "metre"
    root["recipe"] = recipe
    root["bottom_y_m"] = 0.0
    root["food_node"] = "Food"
    if serving:
        for side in [-1, 1]:
            empty("GripLeft" if side < 0 else "GripRight", (side * .2395, 0, .046), root)
        root["grip_left_godot"] = [-.2395, .046, 0]
        root["grip_right_godot"] = [.2395, .046, 0]
    else:
        empty("Grip", (0, 0, .009), root)
        root["grip_godot"] = [0, .009, 0]


def plate(root):
    lathe("Dinner plate with low rolled edge",
          [(0, .003), (.065, .003), (.075, 0), (.083, .001), (.112, .008), (.141, .016),
           (.149, .020), (.150, .023), (.148, .026), (.140, .026), (.119, .017), (.088, .012), (0, .012)],
          "Cream stoneware", root)
    lathe("Teal line at rim", [(.143, .0244), (.147, .026), (.148, .0258), (.147, .0242)],
          "Muted teal glaze", root)


def bake_runtime_mesh(name, source_objects, parent):
    """Batch a group of meshes into one runtime child, as the other dishes do."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in source_objects:
        obj.select_set(True)
    if not source_objects:
        return None
    active = source_objects[0]
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    joined.parent = parent
    return joined


# --- Mushroom soup ---------------------------------------------------------
material("Muted teal glaze", "6f9a93", .55)
material("Cream stoneware", "f2ead9", .5)
material("Warm broth", "c8a86a", .42)
material("Mushroom cap", "8d7157", .62)
material("Mushroom stem", "e6dcc8", .6)
material("Herb fleck", "5f7f4e", .6)
material("Crumble topping", "c69a62", .68)
material("Berry", "7d3550", .45)
material("Syrup sheen", "5e2438", .3)
material("Cream swirl", "f4ecdc", .45)


def soup(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("MushroomSoupServing" if serving else "MushroomSoupPlate")
    metadata(root, "mushroom_soup", serving)
    if serving:
        bowl = lathe("Deep soup bowl, teal outside and cream inside",
                     [(0, .004), (.112, .004), (.126, 0), (.140, .005), (.162, .024),
                      (.180, .056), (.190, .080), (.188, .084), (.180, .080),
                      (.166, .052), (.146, .026), (0, .026)],
                     "Muted teal glaze", root, .92)
        bowl.data.materials.append(M["Cream stoneware"])
        for face in bowl.data.polygons:
            radial = face.normal.x * face.center.x + face.normal.y * face.center.y / (.92 * .92)
            inside = radial < -.0001 or (face.normal.z > .7 and face.center.z >= .025)
            face.material_index = 1 if inside or face.center.z > .079 else 0
        # Broth surface sits just inside the rim.
        lathe("Broth surface", [(0, .060), (.150, .060), (.150, .062), (0, .062)], "Warm broth", root, .92)
    else:
        plate(root)
    soup_food(root, serving)
    return root, ACTIVE.copy()


def pebble(name, radius, height, mat, parent, seed, sides=14):
    """A small irregular rounded granule — a crumb, not a cube."""
    rng = random.Random(seed)
    rings = [(1.0, 0.0), (0.92, 0.35), (0.70, 0.72), (0.38, 0.94), (0.0, 1.0)]
    verts = []
    faces = []
    for ri, (rscale, hscale) in enumerate(rings):
        jitter = rng.uniform(.82, 1.08)
        if ri == len(rings) - 1:
            verts.append((0.0, 0.0, height))
            continue
        for k in range(sides):
            a = 2 * math.pi * k / sides
            rr = radius * rscale * jitter * rng.uniform(.88, 1.12)
            verts.append((rr * math.cos(a), rr * math.sin(a), height * hscale * jitter))
    ring_starts = [0, sides, 2 * sides, 3 * sides]
    for ri in range(len(ring_starts) - 1):
        for k in range(sides):
            k1 = (k + 1) % sides
            faces.append((ring_starts[ri] + k, ring_starts[ri] + k1,
                          ring_starts[ri + 1] + k1, ring_starts[ri + 1] + k))
    apex = len(verts) - 1
    for k in range(sides):
        k1 = (k + 1) % sides
        faces.append((ring_starts[-1] + k, ring_starts[-1] + k1, apex))
    obj = mesh(name, verts, faces, mat, parent, True)
    obj.rotation_euler = (rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(0, math.pi))
    return obj


def soup_food(root, serving):
    food = empty("Food", (0, 0, 0), root)
    rng = random.Random(61 if serving else 610)
    # A cream swirl sitting on the broth, so the surface is not a flat disc.
    for i in range(26):
        a = i * .52
        r = .012 + i * .0042
        prism("Cream swirl %d" % i, rounded_outline(.010, .0035, .0016, 5), .0016,
              "Cream swirl", food, (r * math.sin(a), r * math.cos(a) * .92, .0625), a + 1.2, .0005)
    # Sliced mushrooms: a domed cap over a short stem, tilted so each reads as
    # a slice rather than a flat disc.
    for i in range(9):
        a = 2 * math.pi * i / 9 + rng.uniform(-.30, .30)
        # sqrt keeps the slices area-uniform, so they spread over the bowl
        # rather than bunching near the centre.
        r = math.sqrt(rng.uniform(.06, 1.0)) * .112
        size = rng.uniform(.70, 1.30)
        x, y = r * math.sin(a), r * math.cos(a) * .92
        cap = lathe("Mushroom cap %d" % i,
                    [(0, 0), (.0135 * size, 0), (.0215 * size, .0034), (.0240 * size, .0072),
                     (.0195 * size, .0110), (.0105 * size, .0132), (0, .0140)],
                    "Mushroom cap", food, 1.0, 22)
        cap.location = (x, y, .0620 + rng.uniform(0, .0022))
        cap.rotation_euler = (rng.uniform(-.22, .22), rng.uniform(-.22, .22), rng.uniform(0, math.pi))
        if i % 2 == 0:
            stem = lathe("Mushroom stem %d" % i,
                         [(0, 0), (.0085 * size, 0), (.0090 * size, .0028), (0, .0044)],
                         "Mushroom stem", food, 1.0, 14)
            stem.location = (x + .005 * size, y - .004 * size, .0608)
    # Herb flecks scattered across the surface.
    for i in range(11):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(.018, .112)
        prism("Herb fleck %d" % i, rounded_outline(.0065, .0032, .0014, 5), .0013,
              "Herb fleck", food, (r * math.sin(a), r * math.cos(a) * .92, .0638),
              rng.uniform(0, math.pi), .0004)


# --- Berry crumble ---------------------------------------------------------
def crumble(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("BerryCrumbleServing" if serving else "BerryCrumblePlate")
    metadata(root, "berry_crumble", serving)
    if serving:
        dish = lathe("Shallow baking dish, teal outside and cream inside",
                     [(0, .004), (.118, .004), (.130, 0), (.142, .006), (.166, .030),
                      (.176, .048), (.176, .052), (.168, .048), (.150, .026),
                      (.128, .014), (0, .014)],
                     "Muted teal glaze", root, 1.25)
        dish.data.materials.append(M["Cream stoneware"])
        for face in dish.data.polygons:
            radial = face.normal.x * face.center.x + face.normal.y * face.center.y / (1.25 * 1.25)
            inside = radial < -.0001 or (face.normal.z > .7 and face.center.z >= .013)
            face.material_index = 1 if inside or face.center.z > .047 else 0
    else:
        plate(root)
    crumble_food(root, serving)
    return root, ACTIVE.copy()


def crumble_food(root, serving):
    food = empty("Food", (0, 0, 0), root)
    rng = random.Random(62 if serving else 620)
    # Fruit layer with a slightly domed top, so the filling is not a flat slab.
    lathe("Baked berry layer",
          [(0, .016), (.104, .016), (.140, .022), (.152, .028), (.148, .034),
           (.120, .038), (0, .040)],
          "Berry", food, 1.25, 44)
    # Crumble: many irregular granules at varied heights, not a grid of cubes.
    for i in range(128):
        a = rng.uniform(0, 2 * math.pi)
        r = math.sqrt(rng.uniform(0, 1)) * .146
        x, y = r * math.sin(a), r * math.cos(a) * 1.25
        height = rng.uniform(.006, .016)
        radius = rng.uniform(.0055, .0125)
        pebble("Crumble granule %d" % i, radius, height, "Crumble topping", food,
               600 + i, 12).location = (x, y, .034 + rng.uniform(0, .008))
    # Berries pushed up through the topping at varied depth.
    for i in range(9):
        a = 2 * math.pi * i / 9 + rng.uniform(-.35, .35)
        r = rng.uniform(.035, .125)
        size = rng.uniform(.85, 1.35)
        berry = lathe("Berry %d" % i,
                      [(0, 0), (.0085 * size, 0), (.0110 * size, .0044), (.0100 * size, .0092),
                       (.0055 * size, .0118), (0, .0122)],
                      "Berry", food, 1.0, 20)
        berry.location = (r * math.sin(a), r * math.cos(a) * 1.25, .036 + rng.uniform(0, .006))
    # A syrup sheen pooling at the outer edge.
    lathe("Syrup sheen", [(.090, .0405), (.152, .0355), (.152, .0362), (.090, .0412)],
          "Syrup sheen", food, 1.25, 48)


# --- export ------------------------------------------------------------------
assets = [
    ("meal_mushroom_soup_serving", *soup(True)),
    ("meal_mushroom_soup_plate", *soup(False)),
    ("meal_berry_crumble_serving", *crumble(True)),
    ("meal_berry_crumble_plate", *crumble(False)),
]

for filename, root, objs in assets:
    # Operate by name from here on: joining a group deletes its members, so the
    # stored Python references into `objs` do not all survive.
    root_name = root.name
    kept_names = [o.name.split(".")[0] for o in objs if o.type == "EMPTY"]
    originals = {obj: obj.name for obj in bpy.data.objects if obj.type == "EMPTY"}
    # Park every empty under a unique placeholder so the canonical short names
    # are free, then give the kept ones back their canonical names.
    for index, obj in enumerate(originals):
        obj.name = "PLACEHOLDER_%d" % index
    by_original = {originals[obj]: obj for obj in originals}
    for name in kept_names:
        by_original[name].name = name
    bpy.context.view_layer.update()
    food_group = bpy.data.objects["Food"]
    food_parts = set(food_group.children_recursive)
    food_meshes = [o for o in food_parts if o.type == "MESH"]
    dish_meshes = [bpy.data.objects[n] for n in
                   [o.name for o in objs if o.type == "MESH" and o not in food_parts]]
    groups = [("FoodGeometry", food_meshes, food_group),
              ("DishGeometry", dish_meshes, bpy.data.objects[root_name])]
    baked = [mesh for mesh in
             (bake_runtime_mesh(name, parts, parent) for name, parts, parent in groups) if mesh]
    bpy.ops.object.select_all(action="DESELECT")
    for name in kept_names:
        bpy.data.objects[name].select_set(True)
    for mesh in baked:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects[root_name]
    bpy.ops.export_scene.gltf(filepath=str(MODELS / (filename + ".glb")), export_format="GLB",
                              use_selection=True, export_apply=True, export_extras=True,
                              export_yup=True, export_animations=False, export_cameras=False,
                              export_lights=False)
    for mesh in baked:
        data = mesh.data
        bpy.data.objects.remove(mesh, do_unlink=True)
        bpy.data.meshes.remove(data)
    # Back to the authoring names for the next dish in the list.
    for index, obj in enumerate(originals):
        obj.name = "RESTORE_%d" % index
    for obj, name in originals.items():
        obj.name = name

# One matched studio comparison of the two new dishes.
for index, (_, root, _) in enumerate(assets):
    root.location = (-.31 if index < 2 else .31, .10 if index % 2 == 0 else -.18, 0)

studio = bpy.data.collections.new("Studio — excluded from exports")
scene.collection.children.link(studio)


def studio_link(obj):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    studio.objects.link(obj)


bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.001))
ground = bpy.context.object
ground.name = "Warm studio ground"
ground.data.materials.append(M["Cream stoneware"])
studio_link(ground)
bpy.ops.object.camera_add(location=(0, -1.5, 1.45))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, .022)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.29
scene.camera = camera
studio_link(camera)
for p, energy, size in [((-.70, -.55, 1.15), 65, .8), ((.8, .12, .90), 38, .7), ((-.1, .8, .8), 40, .65)]:
    bpy.ops.object.light_add(type="AREA", location=p)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, .02)) - light.location).to_track_quat("-Z", "Y").to_euler()
    studio_link(light)
scene.world = bpy.data.worlds.new("Warm recipe studio")
scene.world.use_nodes = True
scene.world.node_tree.nodes.get("Background").inputs[0].default_value = (.30, .32, .31, 1)
scene.world.node_tree.nodes.get("Background").inputs[1].default_value = .45
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1400
scene.render.resolution_y = 950
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = -1.05
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(EVIDENCE / "recipe_v61_comparison.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ART / "recipe_v61.blend"))
bpy.ops.render.render(write_still=True)

manifest = {
    "original_artwork": True,
    "source": "art/recipes/recipe_v61.blend",
    "generator": "tools/create_recipe_props_v61.py",
    "preview": "art/recipes/studio/recipe_v61_comparison.png",
    "source_sha256": hashlib.sha256((ART / "recipe_v61.blend").read_bytes()).hexdigest(),
    "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "blender_version": bpy.app.version_string,
    "assets": {},
}
for filename, root, objs in assets:
    p = MODELS / (filename + ".glb")
    manifest["assets"][filename] = {
        "path": str(p.relative_to(ROOT)), "root": root.name,
        "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
        "source_objects": len(objs), "bytes": p.stat().st_size}
(ART / "manifest_v61.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("JUSTLIFE_RECIPE_V61_READY", json.dumps(manifest))
