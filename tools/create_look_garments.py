"""Author original Formal, Athletic, Sleep and Party clothes and export standalone look GLBs.

    blender -b --python tools/create_look_garments.py -- --family all --export

Each look is derived from that family's accepted jacket, tee, hoodie or cardigan
geometry, then reshaped so the five wardrobe types read as different garments.
Exports do not replace character*.glb. Existing objects outside these four
Outfit_* groups are left untouched.
"""
import bpy, bmesh, math, sys, argparse, pathlib, tempfile, os, hashlib, json, struct
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--family", choices=["adult", "child", "teen", "elder", "all"], default="all")
parser.add_argument("--export", action="store_true")
parser.add_argument("--save", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
FAMILIES = ["adult", "child", "teen", "elder"] if args.family == "all" else [args.family]
GROUPS = ["Root", "Spine", "Head", "Arm_L", "Forearm_L", "Arm_R", "Forearm_R", "Leg_L", "Shin_L", "Leg_R", "Shin_R"]
LOOKS = ("Outfit_Formal", "Outfit_Athletic", "Outfit_Sleep", "Outfit_Party")
D = bpy.data


def link(o, parent):
    if o.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(o)
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()


def empty(name, parent):
    e = D.objects.new(name, None)
    link(e, parent)
    return e


def new_mesh_object(name, bm, material, parent):
    me = D.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(D.materials[material])
    o = D.objects.new(name, me)
    link(o, parent)
    for p in me.polygons:
        p.use_smooth = True
    return o


def ensure_groups(o):
    for g in GROUPS:
        if g not in o.vertex_groups:
            o.vertex_groups.new(name=g)


def skin_like(o, source, rig):
    ensure_groups(o)
    for existing in list(o.modifiers):
        if existing.type == "ARMATURE":
            o.modifiers.remove(existing)
    mod = o.modifiers.new("Weights", "DATA_TRANSFER")
    mod.object = source
    mod.use_vert_data = True
    mod.data_types_verts = {"VGROUP_WEIGHTS"}
    mod.vert_mapping = "NEAREST"
    mod.layers_vgroup_select_src = "ALL"
    mod.layers_vgroup_select_dst = "NAME"
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    arm = o.modifiers.new("Soft skeletal deformation", "ARMATURE")
    arm.object = rig


def rigid_group(o, group, rig):
    ensure_groups(o)
    o.vertex_groups[group].add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    arm = o.modifiers.new("Soft skeletal deformation", "ARMATURE")
    arm.object = rig


def duplicate(src, name, parent):
    o = src.copy()
    o.data = src.data.copy()
    o.name = name
    o.data.name = name
    link(o, parent)
    o.matrix_world = src.matrix_world.copy()
    for m in list(o.modifiers):
        if m.type != "ARMATURE":
            o.modifiers.remove(m)
    return o


def surface(fn, nu, nv, closed_u=False, closed_v=False):
    bm = bmesh.new()
    verts = [[bm.verts.new(fn(i / (nu if closed_u else nu - 1), j / (nv if closed_v else nv - 1))) for j in range(nv)] for i in range(nu)]
    for i in range(nu if closed_u else nu - 1):
        for j in range(nv if closed_v else nv - 1):
            a = verts[i][j]
            b = verts[(i + 1) % nu][j]
            c = verts[(i + 1) % nu][(j + 1) % nv]
            d = verts[i][(j + 1) % nv]
            try:
                bm.faces.new((a, b, c, d))
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def delete_where(o, pred):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    doomed = [v for v in bm.verts if pred(o.matrix_world @ v.co)]
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()


def world_points(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def bounds(o):
    pts = world_points(o)
    return Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))), Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))


def lengthen(o, drop, flare=0.0, from_frac=0.42):
    lo, hi = bounds(o)
    waist = lo.z + (hi.z - lo.z) * from_frac
    inv = o.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        w = o.matrix_world @ v.co
        if w.z >= waist:
            continue
        t = (waist - w.z) / max(waist - lo.z, 1e-4)
        w.z -= drop * t
        if flare:
            w.x += math.copysign(flare * t * abs(w.x), w.x) if abs(w.x) > 1e-4 else 0.0
            w.y += flare * t * 0.35
        v.co = inv @ w
    bm.to_mesh(o.data)
    bm.free()


def remove_previous():
    for o in [o for o in D.objects if o.name.startswith(LOOKS)]:
        data = o.data
        D.objects.remove(o)
        if data is not None and data.users == 0:
            (D.meshes if isinstance(data, bpy.types.Mesh) else D.curves).remove(data)


def author(family):
    root = D.objects["Character"]
    rig = D.objects["LifeRig"]
    shirt = D.objects["Outfit_Casual_Shirt"]
    shell = D.objects["Outfit_Jacket_Shell"]
    tee = D.objects.get("Outfit_Tee_Shirt") or shirt
    hoodie = D.objects.get("Outfit_Hoodie_Shell") or shell
    cardigan = D.objects.get("Outfit_Cardigan_Body") or D.objects.get("Outfit_Cardigan")
    if cardigan is None or cardigan.type != "MESH":
        cardigan = shirt
    remove_previous()
    s_lo, s_hi = bounds(shirt)
    j_lo, j_hi = bounds(shell)
    scale = (s_hi.x - s_lo.x) / 0.556

    formal = empty("Outfit_Formal", root)
    coat = duplicate(shell, "Outfit_Formal_Coat", formal)
    lengthen(coat, 0.22 * scale, 0.06, 0.38)
    skin_like(coat, shell, rig)
    for n, suffix in [("Outfit_Jacket_Cuff", "Cuff"), ("Outfit_Jacket_Cuff.001", "Cuff.001"), ("Outfit_Jacket_Stand_collar", "Collar")]:
        if n in D.objects:
            duplicate(D.objects[n], "Outfit_Formal_" + suffix, formal)
    for sgn, tag in ((1, ""), (-1, ".001")):
        def lapel(u, v, sgn=sgn):
            z = j_hi.z - 0.015 * scale - 0.32 * scale * u
            x = sgn * (0.018 + 0.10 * u + 0.055 * v) * scale
            y = j_lo.y - 0.012 * scale - 0.01 * scale * u
            return Vector((x, y, z))
        lap = new_mesh_object("Outfit_Formal_Lapel" + tag, surface(lapel, 10, 5), "Top_seam", formal)
        skin_like(lap, shell, rig)

    def necktie(u, v):
        z = j_hi.z - 0.05 * scale - 0.24 * scale * v
        width = 0.026 * scale * (1.0 - 0.45 * v) * (1.0 + 0.15 * math.sin(math.pi * u))
        x = (u - 0.5) * width
        y = j_lo.y - 0.006 * scale
        return Vector((x, y, z))

    tie = new_mesh_object("Outfit_Formal_Tie", surface(necktie, 8, 12), "Bottom", formal)
    rigid_group(tie, "Spine", rig)

    athletic = empty("Outfit_Athletic", root)
    tank = duplicate(tee, "Outfit_Athletic_Tank", athletic)
    arm_x = (s_hi.x - s_lo.x) * 0.34
    arm_z = s_lo.z + (s_hi.z - s_lo.z) * 0.52
    delete_where(tank, lambda p: abs(p.x) > arm_x and p.z > arm_z)
    skin_like(tank, tee, rig)
    if "Outfit_Tee_Hem" in D.objects:
        duplicate(D.objects["Outfit_Tee_Hem"], "Outfit_Athletic_Hem", athletic)
    t_pts = world_points(tank)
    for sgn, tag in ((1, ""), (-1, ".001")):
        hole = [p for p in t_pts if p.x * sgn > 0.08 * scale and p.z > arm_z - 0.04 * scale]
        if len(hole) < 6:
            continue
        cc = sum(hole, Vector()) / len(hole)
        rr = sum((p - cc).length for p in hole) / len(hole)

        def bind(u, v, cc=cc, rr=rr):
            a = u * math.tau
            b = v * math.tau
            R = rr * 0.92
            r = 0.008 * scale
            return cc + Vector((math.cos(a) * (R + r * math.cos(b)), math.sin(a) * (R + r * math.cos(b)) * 0.55, r * math.sin(b)))

        band = new_mesh_object("Outfit_Athletic_Binding" + tag, surface(bind, 20, 8, True, True), "Top_seam", athletic)
        skin_like(band, tank, rig)

    def stripe(u, v):
        x = (-0.16 + 0.32 * u) * scale
        z = s_lo.z + (s_hi.z - s_lo.z) * (0.58 + 0.08 * v)
        y = min(p.y for p in t_pts if abs(p.x - x) < 0.04 * scale and abs(p.z - z) < 0.05 * scale) - 0.008 * scale if t_pts else s_lo.y
        return Vector((x * (1 - 0.08 * v), y, z))

    chevron = new_mesh_object("Outfit_Athletic_Chevron", surface(stripe, 12, 4), "Top_seam", athletic)
    skin_like(chevron, tank, rig)

    sleep = empty("Outfit_Sleep", root)
    robe = duplicate(hoodie, "Outfit_Sleep_Robe", sleep)
    lengthen(robe, 0.28 * scale, 0.10, 0.36)
    skin_like(robe, hoodie, rig)
    if "Outfit_Hoodie_Cuff" in D.objects:
        duplicate(D.objects["Outfit_Hoodie_Cuff"], "Outfit_Sleep_Cuff", sleep)
        duplicate(D.objects["Outfit_Hoodie_Cuff.001"], "Outfit_Sleep_Cuff.001", sleep)

    def shawl(u, v):
        a = (u - 0.5) * math.radians(210)
        R = (0.10 + 0.02 * v) * scale
        z = j_hi.z - 0.02 * scale + 0.04 * scale * math.cos(a) * v
        return Vector((math.sin(a) * R, math.cos(a) * R * 0.55 + 0.01 * scale, z))

    collar = new_mesh_object("Outfit_Sleep_Shawl", surface(shawl, 22, 6), "Top", sleep)
    rigid_group(collar, "Spine", rig)
    h_lo, h_hi = bounds(robe)
    sash_z = h_lo.z + (h_hi.z - h_lo.z) * 0.58

    def sash(u, v):
        a = u * math.tau
        R = 0.17 * scale
        r = 0.018 * scale
        return Vector((math.cos(a) * (R + r * math.cos(v * math.tau)), math.sin(a) * (R * 0.72 + r * math.sin(v * math.tau)), sash_z + r * math.sin(v * math.tau)))

    belt = new_mesh_object("Outfit_Sleep_Sash", surface(sash, 28, 8, True, True), "Bottom", sleep)
    rigid_group(belt, "Spine", rig)

    party = empty("Outfit_Party", root)
    wrap = duplicate(cardigan, "Outfit_Party_Wrap", party)
    lengthen(wrap, 0.12 * scale, 0.12, 0.30)
    skin_like(wrap, cardigan, rig)
    for n, suffix in [("Outfit_Cardigan_Sleeve", "Sleeve"), ("Outfit_Cardigan_Sleeve.001", "Sleeve.001")]:
        if n in D.objects:
            duplicate(D.objects[n], "Outfit_Party_" + suffix, party)
    c_lo, c_hi = bounds(wrap)

    def diagonal(u, v):
        t = u
        z = c_hi.z - 0.04 * scale - (c_hi.z - c_lo.z) * 0.62 * t
        x = (-0.18 + 0.38 * t) * scale + (v - 0.5) * 0.05 * scale
        y = c_lo.y - 0.012 * scale
        return Vector((x, y, z))

    sash_p = new_mesh_object("Outfit_Party_Sash", surface(diagonal, 16, 5), "Bottom", party)
    skin_like(sash_p, wrap, rig)
    for i, drop in enumerate((0.10, 0.16, 0.07)):
        def panel(u, v, i=i, drop=drop):
            x = (-0.16 + 0.16 * i + 0.14 * u) * scale
            z = c_lo.z - drop * scale * v
            y = c_lo.y + 0.02 * scale * v
            return Vector((x * (1 + 0.08 * v), y, z))
        hem = new_mesh_object("Outfit_Party_Hem" + ("" if i == 0 else ".%03d" % i), surface(panel, 8, 6), "Top", party)
        skin_like(hem, wrap, rig)

    for o in D.objects:
        if o.name.startswith(LOOKS):
            o.hide_render = False
            o.hide_viewport = False
            o.hide_set(False)
    return {"scale": round(scale, 4), "family": family}


def descendants(node):
    yield node
    for child in node.children:
        yield from descendants(child)


def export_look(family, look, category, out):
    root = D.objects.get(look)
    if root is None:
        return ""
    bpy.ops.object.select_all(action="DESELECT")
    for o in descendants(root):
        o.hide_set(False)
        o.select_set(True)
    # Skin export requires the armature itself in a selection-only export.
    # Selecting just the clothes silently bakes out all joints and weights.
    rig = D.objects["LifeRig"]
    rig.hide_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = root
    out.mkdir(parents=True, exist_ok=True)
    name = "%s_%s.glb" % (family, category)
    with tempfile.TemporaryDirectory(prefix=".export-", dir=out) as folder:
        path = pathlib.Path(folder) / name
        bpy.ops.export_scene.gltf(
            filepath=str(path),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
            export_animations=False,
            export_morph=False,
            export_skins=True,
            export_extras=True,
            export_cameras=False,
            export_lights=False,
        )
        raw = path.read_bytes()
        json_length = struct.unpack_from("<I", raw, 12)[0]
        document = json.loads(raw[20:20 + json_length])
        if not document.get("skins"):
            raise RuntimeError("Look export lost its skin: " + name)
        for mesh in document.get("meshes", []):
            for primitive in mesh["primitives"]:
                if not {"JOINTS_0", "WEIGHTS_0"} <= primitive["attributes"].keys():
                    raise RuntimeError("Look export has an unskinned garment: " + name)
        os.replace(path, out / name)
    return hashlib.sha256((out / name).read_bytes()).hexdigest()


report = {}
for family in FAMILIES:
    blend = ROOT / "art" / ("characters.blend" if family == "adult" else "characters_%s.blend" % family)
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    facts = author(family)
    report[family] = {"source": str(blend.relative_to(ROOT)), "facts": facts}
    if args.export:
        hashes = {}
        for look, category in (("Outfit_Formal", "formal"), ("Outfit_Athletic", "athletic"), ("Outfit_Sleep", "sleep"), ("Outfit_Party", "party")):
            hashes[category] = export_look(family, look, category, ROOT / "assets/models/looks")
        report[family]["exports"] = hashes
    if args.save:
        bpy.ops.wm.save_as_mainfile(filepath=str(blend))
print("JUSTLIFE_LOOK_GARMENTS " + json.dumps(report))
