"""Original JustLife makeup surfaces: a lip colour and a lid/cheek colour.

    blender -b --python tools/create_makeup.py
    blender -b --python tools/create_makeup.py -- --family all --export

The accepted character models carry one shared `Lips` material and no lid or
cheek surface at all, so a player has nothing to tint. This adds two dedicated
surfaces to each family, derived from that family's own head geometry:

  * `Makeup_Lips`  a thin shell over the authored lips, scaled a hair proud of
                   them so the colour reads without z-fighting the mouth.
  * `Makeup_Lids`  a pair of shallow lids following the upper eye line, plus a
                   soft cheek wash, so an eye look and a blush are possible.

Both are authored in the model's own Head space, so they ride every head joint
and identity control exactly as the lashes and brows already do. Exports do not
replace character*.glb: the surfaces are added to the four family authoring
sources and exported with the same variant set the wardrobe pass uses.
"""
import bpy, bmesh, math, pathlib, sys, argparse, tempfile, os, hashlib, json
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--family", choices=["adult", "child", "teen", "elder", "all"], default="all")
parser.add_argument("--export", action="store_true")
parser.add_argument("--save", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
FAMILIES = ["adult", "child", "teen", "elder"] if args.family == "all" else [args.family]
D = bpy.data
MADE = ("Makeup_Lips", "Makeup_Lids")


def world_points(o):
    dg = bpy.context.evaluated_depsgraph_get()
    e = o.evaluated_get(dg)
    return [e.matrix_world @ v.co for v in e.data.vertices]


def surface(fn, u_steps, v_steps, close_u=True, close_v=False):
    """A UV-grid surface, the same helper the wardrobe pass uses."""
    bm = bmesh.new()
    verts = []
    for i in range(u_steps + (0 if close_u else 1)):
        column = []
        for j in range(v_steps + (0 if close_v else 1)):
            column.append(bm.verts.new(fn(i / u_steps if close_u else i / u_steps, j / v_steps)))
        verts.append(column)
    xs = u_steps if close_u else u_steps + 1
    ys = v_steps if close_v else v_steps + 1
    for i in range(xs):
        for j in range(ys):
            a = verts[i][j]
            b = verts[(i + 1) % xs][j]
            c = verts[(i + 1) % xs][(j + 1) % ys]
            d = verts[i][(j + 1) % ys]
            try:
                bm.faces.new((a, b, c, d))
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def new_mesh_object(name, bm, material, parent):
    me = D.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = D.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()
    if material in D.materials:
        me.materials.append(D.materials[material])
    for f in me.polygons:
        f.use_smooth = True
    return o


def material(name, hexcolor, rough=.55):
    if name in D.materials:
        return D.materials[name]
    rgb = [int(hexcolor[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
    m = D.materials.new(name)
    m.diffuse_color = (*linear, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = m.diffuse_color
    p.inputs["Roughness"].default_value = rough
    return m


def author(family):
    root = D.objects["Character"]
    head = D.objects["Head"]
    # One neutral authored colour each; the game overrides both at runtime.
    material("Makeup_Lips", "A8564F", .42)
    material("Makeup_Lids", "8A5A6E", .48)
    # The authored upper and lower lip shells give this family's own mouth to
    # follow, so the makeup sits on the real lip surface at every identity
    # control's extreme rather than on a guessed ellipse.
    lip_objects = [D.objects[n] for n in ("Lips_Upper_soft", "Lips_Lower_soft") if n in D.objects]
    if not lip_objects:
        raise RuntimeError(f"{family}: no authored lips to build makeup from")
    lip_pts = [p for o in lip_objects for p in world_points(o)]
    lip_centre = sum(lip_pts, Vector()) / len(lip_pts)
    lip_radius = max((p - lip_centre).xy.length for p in lip_pts) or .02
    # Sort the authored shell into rows around the mouth's own centre, then sweep
    # each point a millimetre outward so the colour cannot z-fight the lips.
    ordered = sorted(lip_pts, key=lambda p: math.atan2(p.z - lip_centre.z, p.x - lip_centre.x))

    def lip_shell(u, v):
        index = int(round((u % 1.0) * (len(ordered) - 1)))
        row = ordered[index]
        outward = row - lip_centre
        outward.z *= .55
        if outward.length < 1e-6:
            outward = Vector((0, 1, 0))
        outward.normalize()
        return row + outward * .0016 + Vector((0, 0, (v - .5) * .003))
    new_mesh_object("Makeup_Lips", surface(lip_shell, 44, 5, True, False), "Makeup_Lips", head)

    # --- Lids: a shallow arc over each eye, plus a cheek wash beneath it.
    for side, sgn in (("L", 1), ("R", -1)):
        eye = D.objects.get("Eyes_Iris" + ("" if sgn > 0 else ".001")) or D.objects.get("Eyes_Iris")
        if eye is None:
            continue
        pts = world_points(eye)
        centre = sum(pts, Vector()) / len(pts)
        radius = max((p - centre).xy.length for p in pts)
        # The lid sits on the upper half of the eye and reaches a little past it.
        def lid(u, v, centre=centre, radius=radius):
            a = math.pi * (1.0 + u)              # a half turn across the top
            R = radius * (1.30 + .34 * v)        # v lifts the lid onto the brow
            return Vector((
                centre.x + math.cos(a) * R,
                centre.y + .0025 * (.4 + v),
                centre.z + math.sin(a) * R * .62 + v * .004,
            ))
        new_mesh_object("Makeup_Lids" + ("" if sgn > 0 else ".001"), surface(lid, 18, 6, True, False), "Makeup_Lids", head)
        # A soft cheek wash on the cheekbone below and outboard of the eye: an
        # elliptical disc laid on the face, so a blush reads without covering
        # the eye it belongs to.
        cheek_c = Vector((centre.x + sgn * radius * .55, centre.y + .0022, centre.z - radius * 2.05))

        def cheek(u, v, c=cheek_c, radius=radius):
            a = u * math.tau
            b = v * math.tau
            rr = radius * 1.15
            return Vector((
                c.x + math.cos(a) * rr * (1.0 + .12 * math.cos(b)),
                c.y,
                c.z + math.sin(a) * rr * .58 * (1.0 + .12 * math.sin(b)),
            ))
        new_mesh_object("Makeup_Cheek" + ("" if sgn > 0 else ".001"), surface(cheek, 22, 8, True, True), "Makeup_Lids", head)
    for name in MADE:
        for o in D.objects:
            if o.name.startswith(name):
                o.hide_render = False
                o.hide_viewport = False
                o.hide_set(False)
    return {"lips": len(lip_pts), "surfaces": len([o for o in D.objects if o.name.startswith(MADE)])}


def descendants(node):
    yield node
    for child in node.children:
        yield from descendants(child)


def export_variant(blend, variant, out):
    width = 1.12 if "broad" in variant else 1.0
    low = variant.endswith("_lod")
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    root = D.objects["Character"]
    root.scale.x = width
    for o in descendants(root):
        if o.type == "MESH" and o.data.shape_keys:
            for key in o.data.shape_keys.key_blocks:
                key.value = 0
        if low:
            if o.type == "MESH" and o.data.shape_keys is None:
                mod = o.modifiers.new("Live camera reduction", "DECIMATE")
                mod.ratio = .12 if o.name.endswith("_Cap") else (.38 if "Leg" in o.name else .22)
                if o.modifiers.find("Soft skeletal deformation") >= 0:
                    bpy.context.view_layer.objects.active = o
                    bpy.ops.object.modifier_move_up(modifier=mod.name)
            elif o.type == "CURVE":
                o.data.resolution_u = 2
                o.data.bevel_resolution = 1
    for bone in D.objects["LifeRig"].pose.bones:
        bone.rotation_euler = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    for o in descendants(root):
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.context.view_layer.update()
    bpy.context.evaluated_depsgraph_get().update()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".export-", dir=out) as folder:
        path = pathlib.Path(folder) / (variant + ".glb")
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                                  export_apply=True, export_yup=True, export_animations=False,
                                  export_morph=True, export_skins=True, export_extras=True,
                                  export_cameras=False, export_lights=False)
        os.replace(path, out / path.name)
    return hashlib.sha256((out / (variant + ".glb")).read_bytes()).hexdigest()


report = {}
for family in FAMILIES:
    blend = ROOT / "art" / ("characters.blend" if family == "adult" else f"characters_{family}.blend")
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    facts = author(family)
    if args.export or args.save:
        bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    report[family] = {"source": str(blend.relative_to(ROOT)), "facts": facts, "objects": len(D.objects)}
    if args.export:
        base = "character" if family == "adult" else f"character_{family}"
        hashes = {}
        for variant in [base, base + "_broad", base + "_lod", base + "_broad_lod"]:
            hashes[variant + ".glb"] = export_variant(blend, variant, ROOT / "assets/models")
        report[family]["exports"] = hashes
print("JUSTLIFE_MAKEUP_REPORT " + json.dumps(report))
