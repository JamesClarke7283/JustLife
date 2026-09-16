"""JustLife culinary expansion art generator, Blender 5.2.1.

    blender -b --python tools/create_recipe_props_v64.py

Authors 5 new recipes across the cooking progression:
1. grilled_cheese (Level 1)
2. garden_salad (Level 2)
3. pancake_stack (Level 3)
4. sunday_roast (Level 6)
5. layer_cake (Level 8)

Generates 10 GLBs (serving and plate for each), adhering strictly to:
- Y-up metre scale
- 2 runtime meshes: DishGeometry (parented to root) and FoodGeometry (parented to Food)
- Grip points: GripLeft/GripRight for serving, Grip for plate
- Bounded dimensions (serving <= 0.50m x 0.335m, plate <= 0.30m x 0.30m, underside Y=0)
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
asset_collection = bpy.data.collections.new("JustLife culinary v64 — editable originals")
scene.collection.children.link(asset_collection)
M = {}
ACTIVE = []


def material(name, color, roughness=0.58, metal=0):
    rgb = [int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metal
    M[name] = mat


def empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    asset_collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    obj.empty_display_size = 0.02
    ACTIVE.append(obj)
    return obj


def mesh(name, verts, faces, mat, parent=None, smooth=False):
    data = bpy.data.meshes.new(name + " geometry")
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0000001)
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


def lathe(name, profile, mat, parent, ellipse=1.0, segments=64):
    """Revolve a (radius, height) profile about Z. Profile radius r is along X, r*ellipse along Y."""
    verts = []
    for r, z in profile:
        for i in range(segments):
            a = 2 * math.pi * i / segments
            verts.append((r * math.cos(a), r * ellipse * math.sin(a), z))
    faces = []
    rings = len(profile)
    for ring in range(rings - 1):
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((ring * segments + i, ring * segments + j,
                          (ring + 1) * segments + j, (ring + 1) * segments + i))
    return mesh(name, verts, faces, mat, parent, True)


def prism(name, outline, height, mat, parent, position=(0, 0, 0), rotation=0):
    """Extrude a 2D outline upward with flat top/bottom."""
    n = len(outline)
    cos_r = math.cos(rotation)
    sin_r = math.sin(rotation)
    verts = []
    px, py, pz = position
    for x, y in outline:
        rx = x * cos_r - y * sin_r + px
        ry = x * sin_r + y * cos_r + py
        verts.append((rx, ry, pz))
    for x, y in outline:
        rx = x * cos_r - y * sin_r + px
        ry = x * sin_r + y * cos_r + py
        verts.append((rx, ry, pz + height))
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(range(n, 2 * n)))
    return mesh(name, verts, faces, mat, parent, False)


def tube(name, points, radius, mat, parent, sides=8):
    """A swept tube along a 3D path."""
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
        up = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
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
    return mesh(name, verts, faces, mat, parent, True)


def metadata(root, recipe, serving):
    root["original_artwork"] = "JustLife original " + recipe + "; modeled without external assets"
    root["unit"] = "metre"
    root["recipe"] = recipe
    root["bottom_y_m"] = 0.0
    root["food_node"] = "Food"
    if serving:
        for side in [-1, 1]:
            empty("GripLeft" if side < 0 else "GripRight", (side * 0.2395, 0, 0.046), root)
        root["grip_left_godot"] = [-0.2395, 0.046, 0]
        root["grip_right_godot"] = [0.2395, 0.046, 0]
    else:
        empty("Grip", (0, 0, 0.009), root)
        root["grip_godot"] = [0, 0.009, 0]


def standard_plate(root):
    lathe("Dinner plate with low rolled edge",
          [(0, 0.003), (0.065, 0.003), (0.075, 0), (0.083, 0.001), (0.112, 0.008), (0.141, 0.016),
           (0.149, 0.020), (0.150, 0.023), (0.148, 0.026), (0.140, 0.026), (0.119, 0.017), (0.088, 0.012), (0, 0.012)],
          "Cream stoneware", root)
    lathe("Teal line at rim", [(0.143, 0.0244), (0.147, 0.026), (0.148, 0.0258), (0.147, 0.0242)],
          "Muted teal glaze", root)


def standard_serving_platter(root, mat="Cream stoneware", rim_mat="Muted teal glaze", ellipse=0.75):
    # Platter: max X radius = 0.20, max Y radius = 0.20 * 0.75 = 0.15. Max width=0.40m, max depth=0.30m.
    lathe("Oval serving platter",
          [(0, 0.004), (0.130, 0.004), (0.150, 0), (0.165, 0.006), (0.190, 0.024),
           (0.202, 0.040), (0.202, 0.045), (0.194, 0.041), (0.170, 0.022), (0.140, 0.012), (0, 0.012)],
          mat, root, ellipse=ellipse)
    # Rim accent
    lathe("Platter rim accent", [(0.195, 0.041), (0.201, 0.0445), (0.201, 0.0435), (0.195, 0.040)],
          rim_mat, root, ellipse=ellipse)
    # Ear handles reaching 0.2395 for standard carrying grip
    for side in [-1, 1]:
        points = [(side * (0.195 + 0.045 * math.sin(t * math.pi)),
                   -0.035 * math.cos(t * math.pi),
                   0.042 + 0.004 * math.sin(t * math.pi)) for t in [i / 16 for i in range(17)]]
        tube("Platter ear handle", points, 0.006, mat, root, 8)


def bake_runtime_mesh(name, source_objects, parent):
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


# Materials definition
material("Cream stoneware", "f2ead9", 0.50)
material("Muted teal glaze", "6f9a93", 0.55)
material("Warm wood", "7d4e2d", 0.65)
material("Toasted golden bread", "d9a352", 0.70)
material("Dark toasted crust", "85491d", 0.75)
material("Melted cheddar cheese", "f5a623", 0.35)
material("Leaf lettuce light", "5f9e3d", 0.60)
material("Leaf lettuce dark", "3b6b22", 0.60)
material("Ripe tomato red", "c92e1e", 0.40)
material("Crisp cucumber", "7cb342", 0.50)
material("Carrot shred", "f07822", 0.55)
material("Golden pancake", "e5b86e", 0.70)
material("Pancake edge rim", "b87a32", 0.75)
material("Butter pat", "ffea75", 0.30)
material("Amber maple syrup", "a0480e", 0.20)
material("Roast beef slices", "5e301d", 0.60)
material("Roast beef bark", "33180c", 0.75)
material("Crisp roast potato", "d4a84b", 0.65)
material("Glazed baby carrot", "e86717", 0.45)
material("Rich savory gravy", "40200e", 0.30)
material("Vanilla buttercream", "fcf8f0", 0.45)
material("Golden sponge cake", "f7dc99", 0.75)
material("Berry jam filling", "8a1c35", 0.35)
material("Fresh red raspberry", "a81d39", 0.40)
material("Cake stand ceramic", "eae4d8", 0.35)


# -----------------------------------------------------------------------------
# 1. Grilled Cheese
# -----------------------------------------------------------------------------
def make_sandwich_triangle(name, pos, rot_z, parent, scale=1.0):
    s = 0.045 * scale
    outline = [(-s, -s * 0.7), (s, -s * 0.7), (0, s * 0.9)]
    prism(name + "_bottom_bread", outline, 0.0075 * scale, "Toasted golden bread", parent, (pos[0], pos[1], pos[2]), rot_z)
    c_outline = [(-s * 1.05, -s * 0.75), (s * 1.05, -s * 0.75), (0, s * 0.95)]
    prism(name + "_cheese", c_outline, 0.005 * scale, "Melted cheddar cheese", parent, (pos[0], pos[1], pos[2] + 0.007 * scale), rot_z)
    prism(name + "_top_bread", outline, 0.0075 * scale, "Toasted golden bread", parent, (pos[0], pos[1], pos[2] + 0.0115 * scale), rot_z)
    for g in [-0.018 * scale, 0.0, 0.018 * scale]:
        g_outline = [(-s * 0.7, -0.0015 * scale), (s * 0.7, -0.0015 * scale), (s * 0.7, 0.0015 * scale), (-s * 0.7, 0.0015 * scale)]
        prism(name + "_grill", g_outline, 0.001 * scale, "Dark toasted crust", parent, (pos[0] + g * 0.5, pos[1] + g * 0.5, pos[2] + 0.019 * scale), rot_z + 0.6)


def grilled_cheese(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("GrilledCheeseServing" if serving else "GrilledCheesePlate")
    metadata(root, "grilled_cheese", serving)
    if serving:
        standard_serving_platter(root, "Cream stoneware", "Muted teal glaze", ellipse=0.75)
    else:
        standard_plate(root)
    food = empty("Food", (0, 0, 0), root)
    if serving:
        z_base = 0.014
        triangles = [
            ((-0.08, -0.03, z_base), 0.3),
            ((-0.03, -0.04, z_base + 0.004), -0.2),
            ((0.03, -0.03, z_base), 0.4),
            ((0.08, -0.02, z_base + 0.003), -0.3),
            ((-0.04, 0.03, z_base + 0.008), 1.1),
            ((0.04, 0.04, z_base + 0.009), 0.8),
        ]
        for i, (pos, rot) in enumerate(triangles):
            make_sandwich_triangle("ServingTri_%d" % i, pos, rot, food, scale=1.0)
    else:
        z_base = 0.013
        make_sandwich_triangle("PlateTri_0", (-0.025, -0.015, z_base), 0.25, food, scale=0.95)
        make_sandwich_triangle("PlateTri_1", (0.028, 0.02, z_base + 0.006), -0.4, food, scale=0.95)
    return root, ACTIVE.copy()


# -----------------------------------------------------------------------------
# 2. Garden Salad
# -----------------------------------------------------------------------------
def salad_leaf(name, pos, rot_z, parent, mat="Leaf lettuce light", scale=1.0):
    s = 0.025 * scale
    outline = [(-s * 0.6, -s), (0, -s * 1.2), (s * 0.6, -s), (s * 0.9, -s * 0.3),
               (s * 0.7, s * 0.5), (0, s * 1.1), (-s * 0.7, s * 0.5), (-s * 0.9, -s * 0.3)]
    prism(name, outline, 0.002 * scale, mat, parent, pos, rot_z)


def cucumber_slice(name, pos, rot_z, parent, scale=1.0):
    r = 0.014 * scale
    outline = [(r * math.cos(i * math.pi / 6), r * math.sin(i * math.pi / 6)) for i in range(12)]
    prism(name, outline, 0.003 * scale, "Crisp cucumber", parent, pos, rot_z)


def tomato_wedge(name, pos, rot_z, parent, scale=1.0):
    r = 0.015 * scale
    outline = [(0, 0), (r, 0), (r * 0.8, r * 0.7), (0, r)]
    prism(name, outline, 0.007 * scale, "Ripe tomato red", parent, pos, rot_z)


def garden_salad(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("GardenSaladServing" if serving else "GardenSaladPlate")
    metadata(root, "garden_salad", serving)
    if serving:
        lathe("Salad serving bowl",
              [(0, 0.004), (0.090, 0.004), (0.110, 0), (0.125, 0.008), (0.155, 0.035),
               (0.180, 0.075), (0.182, 0.082), (0.174, 0.082), (0.150, 0.045), (0.120, 0.015), (0, 0.015)],
              "Warm wood", root, ellipse=0.85)
        lathe("Bowl rim", [(0.174, 0.082), (0.182, 0.082), (0.181, 0.080), (0.175, 0.080)],
              "Cream stoneware", root, ellipse=0.85)
        for side in [-1, 1]:
            points = [(side * (0.178 + 0.062 * math.sin(t * math.pi)),
                       -0.030 * math.cos(t * math.pi),
                       0.052 + 0.006 * math.sin(t * math.pi)) for t in [i / 16 for i in range(17)]]
            tube("Bowl ear handle", points, 0.006, "Warm wood", root, 8)
    else:
        standard_plate(root)
    food = empty("Food", (0, 0, 0), root)
    rng = random.Random(88 if serving else 880)
    num_leaves = 38 if serving else 14
    z_base = 0.035 if serving else 0.013
    max_rad = 0.125 if serving else 0.075
    y_mult = 0.85 if serving else 1.0
    for i in range(num_leaves):
        a = rng.uniform(0, 2 * math.pi)
        r = math.sqrt(rng.uniform(0.05, 1.0)) * max_rad
        x = r * math.cos(a)
        y = r * math.sin(a) * y_mult
        z = z_base + rng.uniform(0, 0.025 if serving else 0.012)
        mat_leaf = "Leaf lettuce light" if (i % 2 == 0) else "Leaf lettuce dark"
        salad_leaf("Leaf_%d" % i, (x, y, z), rng.uniform(0, 2 * math.pi), food, mat_leaf, scale=rng.uniform(0.85, 1.25))
    num_cucumbers = 8 if serving else 3
    for i in range(num_cucumbers):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.02, max_rad * 0.9)
        cucumber_slice("Cuke_%d" % i, (r * math.cos(a), r * math.sin(a) * y_mult, z_base + 0.015 + rng.uniform(0, 0.015)), rng.uniform(0, 2 * math.pi), food)
    num_tomatoes = 7 if serving else 3
    for i in range(num_tomatoes):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.02, max_rad * 0.85)
        tomato_wedge("Tom_%d" % i, (r * math.cos(a), r * math.sin(a) * y_mult, z_base + 0.018 + rng.uniform(0, 0.015)), rng.uniform(0, 2 * math.pi), food)
    for i in range(12 if serving else 5):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.01, max_rad * 0.9)
        prism("Carrot_%d" % i, [(-0.012, -0.0015), (0.012, -0.0015), (0.012, 0.0015), (-0.012, 0.0015)],
              0.0015, "Carrot shred", food, (r * math.cos(a), r * math.sin(a) * y_mult, z_base + 0.022), rng.uniform(0, 2 * math.pi))
    return root, ACTIVE.copy()


# -----------------------------------------------------------------------------
# 3. Pancake Stack
# -----------------------------------------------------------------------------
def pancake(name, pos, radius, height, parent):
    prof = [
        (0, pos[2]),
        (radius * 0.75, pos[2]),
        (radius * 0.95, pos[2] + height * 0.25),
        (radius, pos[2] + height * 0.5),
        (radius * 0.95, pos[2] + height * 0.75),
        (radius * 0.75, pos[2] + height),
        (0, pos[2] + height),
    ]
    p = lathe(name, prof, "Golden pancake", parent, ellipse=1.0, segments=36)
    p.location = (pos[0], pos[1], 0)
    rim_prof = [(radius * 0.93, pos[2] + height * 0.3), (radius, pos[2] + height * 0.5), (radius * 0.93, pos[2] + height * 0.7)]
    lathe(name + "_rim", rim_prof, "Pancake edge rim", parent, ellipse=1.0, segments=36).location = (pos[0], pos[1], 0)


def pancake_stack(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("PancakeStackServing" if serving else "PancakeStackPlate")
    metadata(root, "pancake_stack", serving)
    if serving:
        standard_serving_platter(root, "Cream stoneware", "Muted teal glaze", ellipse=0.75)
    else:
        standard_plate(root)
    food = empty("Food", (0, 0, 0), root)
    stack_count = 4 if serving else 2
    r = 0.075 if serving else 0.060
    h = 0.012
    z = 0.014 if serving else 0.013
    for i in range(stack_count):
        pancake("Cake_%d" % i, (0, 0, z + i * (h * 0.92)), r * (1.0 - i * 0.03), h, food)
    top_z = z + stack_count * (h * 0.92)
    bw = 0.012
    prism("ButterPat", [(-bw, -bw), (bw, -bw), (bw, bw), (-bw, bw)], 0.008, "Butter pat", food, (0, 0, top_z), 0.35)
    lathe("SyrupPoolTop", [(0, top_z + 0.0005), (r * 0.65, top_z + 0.0005), (r * 0.65, top_z + 0.002), (0, top_z + 0.002)], "Amber maple syrup", food, 1.0, 24)
    drip_points = [(r * 0.85 * math.cos(t), r * 0.85 * math.sin(t), top_z - 0.018 * (t / math.pi)) for t in [0.2 * i for i in range(12)]]
    tube("SyrupDrip", drip_points, 0.0035, "Amber maple syrup", food, 6)
    return root, ACTIVE.copy()


# -----------------------------------------------------------------------------
# 4. Sunday Roast
# -----------------------------------------------------------------------------
def roast_potato(name, pos, size, parent):
    r = 0.018 * size
    h = 0.022 * size
    outline = [(r * math.cos(i * math.pi / 4), r * math.sin(i * math.pi / 4)) for i in range(8)]
    prism(name, outline, h, "Crisp roast potato", parent, pos, random.uniform(0, 3.14))


def glazed_carrot(name, pos, length, parent):
    pts = [(pos[0], pos[1] + (t - 0.5) * length, pos[2] + 0.003 * math.sin(t * math.pi)) for t in [i / 8 for i in range(9)]]
    tube(name, pts, 0.0055, "Glazed baby carrot", parent, 6)


def sunday_roast(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("SundayRoastServing" if serving else "SundayRoastPlate")
    metadata(root, "sunday_roast", serving)
    if serving:
        standard_serving_platter(root, "Cream stoneware", "Muted teal glaze", ellipse=0.75)
    else:
        standard_plate(root)
    food = empty("Food", (0, 0, 0), root)
    z_base = 0.014 if serving else 0.013
    if serving:
        roast_outline = [(-0.065, -0.040), (0.065, -0.040), (0.075, 0.035), (-0.075, 0.035)]
        prism("RoastMain", roast_outline, 0.040, "Roast beef slices", food, (-0.02, 0.0, z_base), 0.05)
        bark_outline = [(-0.067, -0.042), (0.067, -0.042), (0.077, 0.037), (-0.077, 0.037)]
        prism("RoastBark", bark_outline, 0.003, "Roast beef bark", food, (-0.02, 0.0, z_base + 0.040), 0.05)
        for s in range(3):
            s_outline = [(-0.060, -0.006), (0.060, -0.006), (0.060, 0.006), (-0.060, 0.006)]
            prism("RoastSlice_%d" % s, s_outline, 0.032, "Roast beef slices", food, (-0.02 + s * 0.005, -0.055 - s * 0.014, z_base), 0.2 - s * 0.1)
        pot_locs = [
            (0.08, 0.02, z_base),
            (0.09, -0.03, z_base),
            (0.07, -0.065, z_base),
            (-0.09, 0.02, z_base),
            (-0.10, -0.03, z_base)
        ]
        for i, p in enumerate(pot_locs):
            roast_potato("Potato_%d" % i, p, 1.1, food)
        carrot_locs = [
            (0.04, 0.06, z_base + 0.005),
            (-0.03, 0.065, z_base + 0.005),
            (0.01, 0.07, z_base + 0.008),
            (-0.07, 0.055, z_base + 0.004)
        ]
        for i, c in enumerate(carrot_locs):
            glazed_carrot("Carrot_%d" % i, c, 0.045, food)
        lathe("GravyPool", [(0, z_base + 0.001), (0.130, z_base + 0.001), (0.130, z_base + 0.003), (0, z_base + 0.003)],
              "Rich savory gravy", food, ellipse=0.72, segments=32)
    else:
        for s in range(2):
            s_outline = [(-0.045, -0.006), (0.045, -0.006), (0.045, 0.006), (-0.045, 0.006)]
            prism("PlateSlice_%d" % s, s_outline, 0.025, "Roast beef slices", food, (-0.02, -0.015 - s * 0.016, z_base), 0.1)
        roast_potato("PlatePotato_0", (0.045, -0.02, z_base), 0.95, food)
        roast_potato("PlatePotato_1", (0.035, 0.03, z_base), 0.90, food)
        glazed_carrot("PlateCarrot_0", (-0.02, 0.045, z_base + 0.004), 0.04, food)
        glazed_carrot("PlateCarrot_1", (0.01, 0.055, z_base + 0.004), 0.038, food)
        lathe("PlateGravy", [(0, z_base + 0.001), (0.075, z_base + 0.001), (0.075, z_base + 0.0025), (0, z_base + 0.0025)],
              "Rich savory gravy", food, 1.0, 24)
    return root, ACTIVE.copy()


# -----------------------------------------------------------------------------
# 5. Layer Cake
# -----------------------------------------------------------------------------
def piped_rosette(name, pos, radius, parent):
    r = radius
    prof = [(0, pos[2]), (r * 0.5, pos[2]), (r, pos[2] + r * 0.4), (r * 0.7, pos[2] + r * 0.8), (0, pos[2] + r * 1.1)]
    lathe(name, prof, "Vanilla buttercream", parent, 1.0, 12).location = (pos[0], pos[1], 0)


def fresh_raspberry(name, pos, radius, parent):
    prof = [(0, pos[2]), (radius * 0.8, pos[2]), (radius, pos[2] + radius * 0.6), (radius * 0.5, pos[2] + radius * 1.0), (0, pos[2] + radius * 1.1)]
    lathe(name, prof, "Fresh red raspberry", parent, 1.0, 12).location = (pos[0], pos[1], 0)


def layer_cake(serving):
    global ACTIVE
    ACTIVE = []
    root = empty("LayerCakeServing" if serving else "LayerCakePlate")
    metadata(root, "layer_cake", serving)
    if serving:
        lathe("CakeStand",
              [(0, 0.003), (0.080, 0.003), (0.090, 0), (0.095, 0.006), (0.050, 0.018),
               (0.025, 0.035), (0.025, 0.055), (0.060, 0.070), (0.160, 0.070), (0.165, 0.075),
               (0.165, 0.078), (0.155, 0.078), (0, 0.078)],
              "Cake stand ceramic", root, ellipse=0.90)
        for side in [-1, 1]:
            points = [(side * (0.165 + 0.075 * math.sin(t * math.pi)),
                       -0.030 * math.cos(t * math.pi),
                       0.058 + 0.005 * math.sin(t * math.pi)) for t in [i / 16 for i in range(17)]]
            tube("CakeStand handle", points, 0.006, "Cake stand ceramic", root, 8)
    else:
        standard_plate(root)
    food = empty("Food", (0, 0, 0), root)
    if serving:
        z = 0.078
        lathe("CakeTier1_Frosting",
              [(0, z), (0.125, z), (0.125, z + 0.045), (0, z + 0.045)],
              "Vanilla buttercream", food, ellipse=0.90, segments=48)
        z2 = z + 0.045
        lathe("CakeTier2_Frosting",
              [(0, z2), (0.080, z2), (0.080, z2 + 0.040), (0, z2 + 0.040)],
              "Vanilla buttercream", food, ellipse=0.90, segments=36)
        for i in range(14):
            a = 2 * math.pi * i / 14
            rx = 0.118 * math.cos(a)
            ry = 0.118 * 0.90 * math.sin(a)
            piped_rosette("RosetteT1_%d" % i, (rx, ry, z + 0.045), 0.008, food)
        for i in range(10):
            a = 2 * math.pi * i / 10
            rx = 0.074 * math.cos(a)
            ry = 0.074 * 0.90 * math.sin(a)
            piped_rosette("RosetteT2_%d" % i, (rx, ry, z2 + 0.040), 0.007, food)
        fresh_raspberry("TopBerry_Center", (0, 0, z2 + 0.040), 0.009, food)
        for i in range(4):
            a = 2 * math.pi * i / 4
            fresh_raspberry("TopBerry_%d" % i, (0.028 * math.cos(a), 0.028 * 0.90 * math.sin(a), z2 + 0.040), 0.0075, food)
    else:
        z = 0.013
        wedge_outline = [(-0.015, -0.035), (0.065, 0.0), (-0.015, 0.035)]
        prism("Sponge1", wedge_outline, 0.014, "Golden sponge cake", food, (0, 0, z), 0.2)
        prism("Jam1", wedge_outline, 0.003, "Berry jam filling", food, (0, 0, z + 0.014), 0.2)
        prism("Sponge2", wedge_outline, 0.014, "Golden sponge cake", food, (0, 0, z + 0.017), 0.2)
        prism("Jam2", wedge_outline, 0.003, "Berry jam filling", food, (0, 0, z + 0.031), 0.2)
        prism("Sponge3", wedge_outline, 0.014, "Golden sponge cake", food, (0, 0, z + 0.034), 0.2)
        prism("TopFrosting", wedge_outline, 0.005, "Vanilla buttercream", food, (0, 0, z + 0.048), 0.2)
        piped_rosette("PlateRosette", (0.015, 0.005, z + 0.053), 0.009, food)
        fresh_raspberry("PlateBerry", (0.015, 0.005, z + 0.060), 0.007, food)
    return root, ACTIVE.copy()


# -----------------------------------------------------------------------------
# Asset list & Export loop
# -----------------------------------------------------------------------------
BUILDERS = [
    ("meal_grilled_cheese_serving", grilled_cheese, True),
    ("meal_grilled_cheese_plate", grilled_cheese, False),
    ("meal_garden_salad_serving", garden_salad, True),
    ("meal_garden_salad_plate", garden_salad, False),
    ("meal_pancake_stack_serving", pancake_stack, True),
    ("meal_pancake_stack_plate", pancake_stack, False),
    ("meal_sunday_roast_serving", sunday_roast, True),
    ("meal_sunday_roast_plate", sunday_roast, False),
    ("meal_layer_cake_serving", layer_cake, True),
    ("meal_layer_cake_plate", layer_cake, False),
]

for filename, builder, serving in BUILDERS:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for data_mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(data_mesh)
    
    root, objs = builder(serving)
    root_name = root.name
    
    kept_names = [o.name for o in objs if o.type == "EMPTY"]
    food_group = [o for o in objs if o.type == "EMPTY" and o.name == "Food"][0]
    food_parts = set(food_group.children_recursive)
    food_meshes = [o for o in food_parts if o.type == "MESH"]
    dish_meshes = [o for o in objs if o.type == "MESH" and o not in food_parts]
    
    groups = [("FoodGeometry", food_meshes, food_group),
              ("DishGeometry", dish_meshes, root)]
    baked = [m for m in (bake_runtime_mesh(name, parts, parent) for name, parts, parent in groups) if m]
    
    bpy.ops.object.select_all(action="DESELECT")
    for name in kept_names:
        bpy.data.objects[name].select_set(True)
    for m in baked:
        m.select_set(True)
    bpy.context.view_layer.objects.active = root
    
    out_path = MODELS / (filename + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_extras=True,
        export_yup=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False
    )

print("JUSTLIFE_RECIPE_V64_EXPORT_SUCCESS")

