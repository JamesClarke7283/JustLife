"""Author the two newest hairstyles into the four character sources.

    blender -b --python tools/create_hair_styles.py
    blender -b --python tools/create_hair_styles.py -- --family all --export

Adds `Hair_Braids` and `Hair_Topknot` to each family, then exports that family's
four production variants. Both are built from that family's own authored head and
hair geometry, and this tool is strictly additive:

  * it only ever *creates* objects whose names start with `Hair_Braids_` or
    `Hair_Topknot_`, so re-running it replaces just those two styles;
  * it never touches any other object, group or material.

That matters because the older `create_wardrobe.py` derives `Hair_Long`,
`Hair_Pony`, `Hair_Waves` and `Hair_Buzz` by duplicating `Hair_Bob` — a step that
was correct when it was written but now rebuilds those four styles from a Bob
that iteration 62 replaced, discarding their reviewed geometry and materials.
This tool therefore leaves them alone entirely.

The two styles share the accepted convention: pieces hang under the `Head` pivot
and are weighted from the same source surface the other styles use, so they ride
every identity control and joint with no runtime special case.
"""
import argparse
import hashlib
import json
import math
import pathlib
import sys
import tempfile
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--family", choices=["adult", "child", "teen", "elder", "all"], default="all")
parser.add_argument("--export", action="store_true")
parser.add_argument("--save", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
FAMILIES = ["adult", "child", "teen", "elder"] if args.family == "all" else [args.family]
D = bpy.data
GROUPS = ["Root", "Spine", "Head", "Arm_L", "Forearm_L", "Arm_R", "Forearm_R", "Leg_L", "Shin_L", "Leg_R", "Shin_R"]
MINE = ("Hair_Braids", "Hair_Topknot")


def link(o, parent):
    if o.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(o)
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()


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
    """Weight a piece from an authored surface, exactly as the other styles are."""
    ensure_groups(o)
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


def surface(fn, nu, nv, closed_u=False, closed_v=False):
    bm = bmesh.new()
    verts = [[bm.verts.new(fn(i / (nu if closed_u else nu - 1), j / (nv if closed_v else nv - 1)))
              for j in range(nv)] for i in range(nu)]
    for i in range(nu if closed_u else nu - 1):
        for j in range(nv if closed_v else nv - 1):
            a = verts[i][j]; b = verts[(i + 1) % nu][j]
            c = verts[(i + 1) % nu][(j + 1) % nv]; d = verts[i][(j + 1) % nv]
            try:
                bm.faces.new((a, b, c, d))
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def world_points(o):
    dg = bpy.context.evaluated_depsgraph_get()
    e = o.evaluated_get(dg)
    return [e.matrix_world @ v.co for v in e.data.vertices]


def remove_mine():
    """Clear only this tool's own two styles, so a re-run is idempotent."""
    for o in [o for o in D.objects if o.name.startswith(MINE)]:
        data = o.data
        D.objects.remove(o)
        if data is not None and data.users == 0:
            (D.meshes if isinstance(data, bpy.types.Mesh) else D.curves).remove(data)


def ref_cap():
    """The family's authored Bob cap: the accepted silhouette to sit hair on."""
    for name in ("Hair_Bob_Cap", "Hair_Crop_Cap"):
        if name in D.objects:
            return D.objects[name]
    raise RuntimeError("no authored cap to build from")


def author(family):
    root = D.objects["Character"]
    rig = D.objects["LifeRig"]
    head = D.objects["Head"]
    cap = ref_cap()
    remove_mine()
    pts = world_points(cap)
    scale = max((p - (sum(pts, Vector()) / len(pts))).xy.length for p in pts)
    top = max(p.z for p in pts)
    centre = sum(pts, Vector()) / len(pts)
    back = [p for p in pts if p.y > centre.y + .02 * scale]
    back_y = (sum(p.y for p in back) / len(back)) if back else centre.y
    rig_source = D.objects.get("Hair_Bob_Sweep") or D.objects.get("Hair_Long_Back") or cap
    made = []

    # ---- Braids: the cap mass gathered into two plaits that fall forward over
    # the shoulders, with the bandings a real braid carries.
    braids = D.objects.new("Hair_Braids", None)
    link(braids, head)
    bcap = new_mesh_object("Hair_Braids_Cap", surface(
        lambda u, v: _cap_point(u, v, pts, centre, scale), 40, 8, True, False), "Hair", braids)
    bcap.matrix_world = cap.matrix_world.copy()
    for side, sgn in (("L", 1), ("R", -1)):
        start = Vector((sgn * .055 * scale, back_y - .010 * scale, top - .235 * scale))

        def plait(u, v, start=start, sgn=sgn):
            t = v
            a = u * math.tau
            band = .006 * scale * math.sin(t * math.tau * 3.5)   # three-strand banding
            lean = sgn * .022 * scale * t * t                    # drifts outward over the shoulder
            drop = -(.255 * scale) * t                           # falls down the front
            forward = -.020 * scale * t * t                      # eases in front of the collarbone
            axis = start + Vector((lean, forward, drop))
            r = (.028 * scale * (1 - .55 * t) + band) * max(0.0, 1 - .15 * t)
            return axis + Vector((math.cos(a) * r, math.sin(a) * r, 0))
        made.append(new_mesh_object("Hair_Braids_Fall" + ("" if side == "L" else ".001"),
                                    surface(plait, 20, 26, True, True), "Hair", braids))
        for k, at in enumerate((.42, .86)):
            c = start + Vector((sgn * .022 * scale * at * at, -.020 * scale * at * at, -.255 * scale * at))

            def tie(u, v, c=c, at=at):
                a = u * math.tau
                b = v * math.tau
                R = .022 * scale * (1 - .55 * at)
                r = .005 * scale
                return c + Vector((math.cos(a) * (R + r * math.cos(b)),
                                   math.sin(a) * (R + r * math.cos(b)), r * math.sin(b)))
            made.append(new_mesh_object("Hair_Braids_Tie%d" % k + ("" if side == "L" else ".001"),
                                        surface(tie, 20, 8, True, True), "Jewelry", braids))

    # ---- Topknot: the mass gathered high on the crown, leaving the nape clear.
    topknot = D.objects.new("Hair_Topknot", None)
    link(topknot, head)
    tcap = new_mesh_object("Hair_Topknot_Cap", surface(
        lambda u, v: _cap_point(u, v, pts, centre, scale, lift=.012), 40, 8, True, False), "Hair", topknot)
    tcap.matrix_world = cap.matrix_world.copy()
    knot_c = Vector((centre.x, centre.y - .012 * scale, top + .052 * scale))

    def knot(u, v):
        a = u * math.tau
        b = v * math.tau
        r = .050 * scale * (1 + .10 * math.cos(3 * a)) * (1 - .18 * b)
        return knot_c + Vector((math.cos(a) * math.sin(b) * r,
                                math.sin(a) * math.sin(b) * r * .92,
                                math.cos(b) * r * .88))
    made.append(new_mesh_object("Hair_Topknot_Knot", surface(knot, 26, 16, True, True), "Hair", topknot))

    def band(u, v):
        a = u * math.tau
        r = .034 * scale
        base = knot_c + Vector((0, 0, -.040 * scale))
        return base + Vector((math.cos(a) * r, math.sin(a) * r, .010 * scale * math.sin(v * math.tau)))
    made.append(new_mesh_object("Hair_Topknot_Band", surface(band, 22, 8, True, True), "Jewelry", topknot))

    for o in made:
        skin_like(o, rig_source, rig)
        o.hide_render = False
        o.hide_viewport = False
        o.hide_set(False)
    return {"scale": round(scale, 4), "pieces": len(made), "objects": len(D.objects)}


def _cap_point(u, v, pts, centre, scale, lift=0.0):
    """A point on the family's own cap silhouette, swept as a closed shell."""
    a = u * math.tau
    t = v
    # Radius follows the authored cap's own outline in that direction.
    direction = Vector((math.cos(a), math.sin(a), 0))
    far = max((p - centre).xy.dot(Vector((math.cos(a), math.sin(a)))) for p in pts)
    r = far * (1.0 - .06 * t)
    return Vector((centre.x + direction.x * r,
                   centre.y + direction.y * r,
                   pts[0].z + (max(p.z for p in pts) - pts[0].z) * (.55 + .45 * (1 - t)) + lift))


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
    before = {o.name for o in D.objects}
    facts = author(family)
    after = {o.name for o in D.objects}
    removed = sorted(before - after)
    if removed:
        raise RuntimeError(f"{family}: this tool must only add, but removed {removed}")
    if args.export or args.save:
        bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    report[family] = {"source": str(blend.relative_to(ROOT)), "facts": facts,
                      "added": sorted(n for n in after - before)}
    if args.export:
        base = "character" if family == "adult" else f"character_{family}"
        report[family]["exports"] = {
            v + ".glb": export_variant(blend, v, ROOT / "assets/models")
            for v in [base, base + "_broad", base + "_lod", base + "_broad_lod"]}
print("JUSTLIFE_HAIR_STYLES_REPORT " + json.dumps(report))
