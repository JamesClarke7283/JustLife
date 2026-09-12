"""JustLife original baby character generator. Blender 5.x, background safe.

The baby is an original parametric sculpt: a small (0.55 m) rounded infant with
the *same* armature contract as the four older age families (identical bone
names, identical empty pivots, identical material names), so scripts/actor.gd's
landmark reader, joint lookup, wardrobe switching and blend-shape discovery keep
working without a second code path.

Nothing here copies a Sims asset: every surface is a loft, tube or sphere built
from the tables below, and every run of the same source produces byte-identical
geometry (no voxel remeshing, no random seeds).

Run:
  blender --background --python tools/baby_v60/create_baby.py -- --family baby --export

Outputs (with --export):
  assets/models/character_baby.glb, _broad.glb, _lod.glb, _broad_lod.glb
  art/characters_baby.blend
and, with --evidence-dir, the front/side/crawl evidence renders.
"""
import argparse
import hashlib
import json
import math
import os
import pathlib
import sys
import tempfile

import bpy
import bmesh
from math import cos, pi, sin
from mathutils import Matrix, Vector

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent

parser = argparse.ArgumentParser()
parser.add_argument("--family", choices=["baby", "all"], default="baby")
parser.add_argument("--export", action="store_true")
parser.add_argument("--save", action="store_true", help="write art/characters_baby.blend (implied by --export)")
parser.add_argument("--source", action="store_true", help="only rebuild art/characters_baby.blend, no GLBs")
parser.add_argument("--preview-dir", type=pathlib.Path, default=None)
parser.add_argument("--evidence-dir", type=pathlib.Path, default=None)
parser.add_argument("--manifest", type=pathlib.Path, default=HERE / "manifest.json")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

D = bpy.data
# The generator reads exactly these files at run time; their hashes are the
# provenance of the contract this model was authored against.
CONTRACT_INPUTS = [
    "scripts/actor.gd",
    "scripts/lifecycle.gd",
    "tools/create_characters.py",
]

# ---------------------------------------------------------------------------
# Contract: bone heads (Blender metres, Z up, the face toward -Y) and the
# empty pivots that carry attached props. Names are the family contract.
# ---------------------------------------------------------------------------
BONES = [
    ("Root", (0.0, 0.0, 0.0), None),
    ("Spine", (0.0, -0.004, 0.270), "Root"),
    ("Head", (0.0, 0.004, 0.395), "Spine"),
    ("Arm_L", (-0.058, 0.0, 0.360), "Spine"),
    ("Arm_R", (0.058, 0.0, 0.360), "Spine"),
    ("Forearm_L", (-0.078, 0.004, 0.276), "Arm_L"),
    ("Forearm_R", (0.078, 0.004, 0.276), "Arm_R"),
    ("Leg_L", (-0.026, 0.006, 0.245), "Root"),
    ("Leg_R", (0.026, 0.006, 0.245), "Root"),
    ("Shin_L", (-0.030, 0.006, 0.135), "Leg_L"),
    ("Shin_R", (0.030, 0.006, 0.135), "Leg_R"),
]
BONE_TAIL = 0.055
GROUPS = [name for name, _, _ in BONES]
HEIGHT_M = 0.55
HIP_Z = 0.245
KNEE_Z = 0.135
HEAD_Z = 0.395
# One proportion pass over the whole head group, exactly like the adult's
# `head.scale`: authored at a neutral scale, then pulled toward the head pivot
# so the infant silhouette stays big-headed without an oversized cranium shell.
# The authored skull rings, shared by the head loft and the hair shell.
# The head's centre and radius, used to scale the hair shell about the skull.
HEAD_CENTRE = 0.462
HEAD_RADIUS = 0.093
HEAD_RING_ROWS = [
    (0.393, .032, .030, .013),
    (0.405, .048, .046, .009),
    (0.418, .062, .061, .005),
    (0.432, .073, .073, .001),
    (0.448, .080, .082, -.002),
    (0.465, .084, .087, -.004),
    (0.483, .084, .087, -.004),
    (0.501, .080, .083, -.002),
    (0.518, .071, .075, .000),
    (0.534, .056, .060, .003),
    (0.546, .032, .036, .004),
    (0.553, .011, .013, .004),
]
ELBOW_Z = 0.276
WRIST_Z = 0.206
SHOULDER_X = 0.058

# ---------------------------------------------------------------------------
# Helpers (same primitive vocabulary as tools/create_characters.py)
# ---------------------------------------------------------------------------
def link(o, parent):
    if o.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(o)


def parent_keep(o, p):
    if p:
        bpy.context.view_layer.update()
        mw = o.matrix_world.copy()
        o.parent = p
        o.matrix_world = mw
    return o


def empty(name, loc=(0, 0, 0), p=None):
    o = D.objects.new(name, None)
    link(o, p)
    o.location = loc
    return parent_keep(o, p)


def mat(name, hexcol, rough=.55, metal=0.0):
    srgb = tuple(int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4))
    c = tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in srgb)
    m = D.materials.new(name)
    m.diffuse_color = (*c, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*c, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m


def mesh(name, verts, faces, ma, p=None, sub=0):
    me = D.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = D.objects.new(name, me)
    link(o, p)
    if ma:
        me.materials.append(ma)
    for poly in me.polygons:
        poly.use_smooth = True
    if sub:
        mod = o.modifiers.new("Sculpted smooth surface", "SUBSURF")
        mod.levels = sub
        mod.render_levels = sub
    return parent_keep(o, p)


def uv(name, loc, sc, ma, p=None, seg=24, rings=14):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = sc
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if ma:
        o.data.materials.append(ma)
    for f in o.data.polygons:
        f.use_smooth = True
    return parent_keep(o, p)


def loft(name, rings, ma, p=None, n=24, sub=1, caps=True):
    """rings: z, halfwidth, halfdepth, yoffset, xoffset -- a closed elliptical tube."""
    vs = []
    for z, w, d, y, x in rings:
        for j in range(n):
            a = 2 * pi * j / n
            vs.append((x + w * sin(a), y - d * cos(a), z))
    fs = []
    for i in range(len(rings) - 1):
        for j in range(n):
            fs.append((i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j))
    if caps:
        fs += [tuple(range(n - 1, -1, -1)), tuple((len(rings) - 1) * n + j for j in range(n))]
    return mesh(name, vs, fs, ma, p, sub)


def tube(name, points, radii, ma, p=None, n=12, sub=1, flat=1.0):
    pts = [Vector(v) for v in points]
    vs = []
    for i, v in enumerate(pts):
        tangent = (pts[min(i + 1, len(pts) - 1)] - pts[max(0, i - 1)]).normalized()
        up = Vector((0, 1, 0))
        if abs(tangent.dot(up)) > .95:
            up = Vector((1, 0, 0))
        a = tangent.cross(up).normalized()
        b = tangent.cross(a).normalized()
        rr = radii[i]
        for j in range(n):
            t = 2 * pi * j / n
            vs.append(v + a * rr * cos(t) + b * rr * sin(t) * flat)
    fs = []
    for i in range(len(pts) - 1):
        for j in range(n):
            fs.append((i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j))
    fs += [tuple(range(n - 1, -1, -1)), tuple((len(pts) - 1) * n + j for j in range(n))]
    return mesh(name, vs, fs, ma, p, sub)


def solid(o, thickness):
    m = o.modifiers.new("Soft garment thickness", "SOLIDIFY")
    m.thickness = thickness
    m.offset = 0.0
    return o


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def _head_halfwidth(z, rings):
    """Interpolated authored half-width at a height, for lateral face weights."""
    if z <= rings[0][0]:
        return rings[0][1]
    if z >= rings[-1][0]:
        return rings[-1][1]
    for index in range(len(rings) - 1):
        low, high = rings[index], rings[index + 1]
        if low[0] <= z <= high[0]:
            t = (z - low[0]) / (high[0] - low[0])
            return low[1] + (high[1] - low[1]) * t
    return rings[-1][1]


# ---------------------------------------------------------------------------
# Authoring
# ---------------------------------------------------------------------------
def build():
    for m in list(D.materials):
        D.materials.remove(m)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    skin = mat("Skin", "C08A63", .58)
    ear_detail = mat("Ear_detail", "AF7457", .6)
    nose_detail = mat("Nose_detail", "7A4A38", .58)
    lips = mat("Lips", "C0716C", .56)
    hair = mat("Hair", "6B4A33", .7)
    hair_hl = mat("Hair_highlight", "855F42", .72)
    top = mat("Top", "8FB6A8", .82)
    top_seam = mat("Top_seam", "6E968A", .86)
    bottom = mat("Bottom", "8A9BC0", .82)
    bottom_seam = mat("Bottom_seam", "6C7B9C", .86)
    shoes = mat("Shoes", "EFE7D8", .66)
    shoes_sole = mat("Shoes_sole", "D5C9B4", .68)
    shoes_accent = mat("Shoes_accent", "C98E7A", .66)
    eye_white = mat("Eyes_white", "F6EEE2", .3)
    iris = mat("Eyes", "5F7F70", .3)
    iris_edge = mat("Eyes_edge", "39493F", .32)
    pupil = mat("Eyes_pupil", "23292A", .3)
    catch = mat("Eyes_catchlight", "FFFFFF", .14)

    root = empty("Character")

    # ---- Torso: a soft barrel with a round belly and a short neck.
    torso_rings = [
        (0.170, .026, .023, .012),
        (0.186, .044, .038, .010),
        (0.204, .055, .047, .008),
        (0.226, .061, .052, .005),
        (0.248, .063, .054, .002),
        (0.272, .064, .055, -.004),
        (0.296, .062, .053, -.005),
        (0.318, .059, .050, -.002),
        (0.338, .057, .047, .001),
        (0.354, .055, .044, .003),
        (0.366, .050, .041, .004),
        (0.376, .038, .034, .005),
        (0.386, .029, .029, .005),
    ]
    torso = loft("Skin_Body_continuous", [(z, w, d, y, 0.0) for z, w, d, y in torso_rings], skin, root, 28, 2)

    # ---- Head: cranium wider than the jaw, so the silhouette reads infant.
    head = empty("Head", (0, 0.004, HEAD_Z), root)
    head_rings = HEAD_RING_ROWS
    headskin = loft("Skin_Head_continuous", [(z, w, d, y, 0.0) for z, w, d, y in head_rings], skin, head, 28, 2)
    # Sculpt the infant profile into the surface itself (the family pattern):
    # a fuller forehead, round cheeks and a soft small chin, plus a flatter
    # face plane so the button features sit on a real face rather than a ball.
    for vertex in headskin.data.vertices:
        x, y, z = vertex.co
        front = 1 - smoothstep(-.040, .020, y)
        lateral = abs(x) / max(.0001, _head_halfwidth(z, head_rings))
        cheek = math.exp(-((z - .448) / .017) ** 2) * math.exp(-((lateral - .84) / .26) ** 2)
        chin = math.exp(-(x / .026) ** 2) * math.exp(-((z - .410) / .014) ** 2)
        vertex.co.y -= .0038 * cheek + .0012 * chin
    parent_keep(headskin, root)  # the skin follows the bone; details ride the pivot

    # Ears sit slightly proud of the temple, with a warm inner concha.
    for s in (-1, 1):
        sign = "L" if s < 0 else "R"
        uv("Skin_Ear_" + sign, (s * .078, .002, .4485), (.0075, .014, .019), skin, head, 20, 12)
        uv("Ear_detail_" + sign, (s * .0815, -.003, .4475), (.004, .0075, .010), ear_detail, head, 16, 10)

    # Button nose and a small soft mouth; both are flattened round volumes.
    nose_y = face_surface_y(headskin, 0.0, .4262)
    uv("Skin_Nose", (0, nose_y - .0018, .4262), (.0122, .0100, .0090), skin, head, 20, 12)
    for s in (-1, 1):
        uv("Nose_Nostril_" + ("L" if s < 0 else "R"), (s * .0062, nose_y - .0062, .4222),
           (.0033, .0023, .0019), nose_detail, head, 12, 8)
    mouth_y = face_surface_y(headskin, 0.0, .4085)
    uv("Lips_Upper_soft", (0, mouth_y + .0032, .4112), (.0138, .0086, .0044), lips, head, 20, 12)
    uv("Lips_Lower_soft", (0, mouth_y + .0038, .4040), (.0128, .0078, .0044), lips, head, 20, 12)
    tube("Lips_Smile_seam", [(-.0138, mouth_y + .0012, .4078), (-.0072, mouth_y - .0026, .4068),
                             (0, mouth_y - .0040, .4063), (.0072, mouth_y - .0026, .4068),
                             (.0138, mouth_y + .0012, .4078)], [.0012] * 5, nose_detail, head, 8, 1)

    # Big round eyes, layered the way the family does it: a shallow sclera lens
    # seated on the real face plane, then iris edge, iris, pupil and catchlight
    # each a thin disc just in front of the last. Every depth is measured from
    # the sculpted surface, so the eye cannot sink into the head.
    eyes = []
    for s in (-1, 1):
        side = "L" if s < 0 else "R"
        x = s * .032
        face_y = face_surface_y(headskin, x, .4520)
        eyes.append(uv("Eyes_Sclera_" + side, (x, face_y + .0060, .4520), (.0172, .0076, .0190), eye_white, head, 26, 16))
        front = face_y - .0048
        eyes.append(uv("Eyes_Iris_edge_" + side, (x, front + .0016, .4505), (.0100, .0016, .0100), iris_edge, head, 22, 12))
        eyes.append(uv("Eyes_Iris_" + side, (x, front + .0012, .4505), (.0088, .0016, .0088), iris, head, 22, 12))
        eyes.append(uv("Eyes_Pupil_" + side, (x, front + .0008, .4505), (.0043, .0016, .0043), pupil, head, 16, 10))
        eyes.append(uv("Eyes_Catchlight_" + side, (x - s * .0032, front + .0004, .4540), (.0022, .0016, .0022), catch, head, 12, 8))

    # ---- Arms: chubby upper arm into a closed fist, matching the family A-pose.
    arms = {}
    for s in (-1, 1):
        side = "L" if s < 0 else "R"
        arm = empty("Arm_" + side, (s * SHOULDER_X, 0, 0.360), root)
        fore = empty("Forearm_" + side, (s * 0.078, 0.004, ELBOW_Z), arm)
        points = [(s * .052, 0, .366), (s * .064, .001, .338), (s * .078, .004, ELBOW_Z),
                  (s * .083, .001, .248), (s * .086, -.004, .222), (s * .088, -.012, .202)]
        radii = [.029, .027, .0245, .0225, .0225, .0255]
        arm_mesh = tube("Skin_Arm_continuous_" + side, points, radii, skin, root, 14, 2)
        # Thumb folded across the fist; the fist is the last swelling of the tube.
        thumb = tube("Skin_Thumb_" + side, [(s * .076, -.014, .226), (s * .084, -.022, .215), (s * .088, -.026, .206)],
                     [.0088, .0078, .0054], skin, root, 10, 1)
        uv("Skin_Finger_" + side + "_tip", (s * .088, -.014, .195), (.0130, .0120, .0100), skin, root, 16, 10)
        arms[side] = (arm, arm_mesh, thumb, fore)

    # ---- Legs: thigh into a rounded ankle; the bootie covers the foot.
    legs = {}
    for s in (-1, 1):
        side = "L" if s < 0 else "R"
        leg = empty("Leg_" + side, (s * .026, .006, HIP_Z), root)
        shin = empty("Shin_" + side, (s * .030, .006, KNEE_Z), leg)
        points = [(s * .026, .004, .250), (s * .028, .006, .210), (s * .030, .006, KNEE_Z),
                  (s * .030, .002, .104), (s * .030, -.004, .062)]
        radii = [.031, .030, .027, .022, .019]
        leg_mesh = tube("Skin_Leg_continuous_" + side, points, radii, skin, root, 14, 2)
        legs[side] = (leg, leg_mesh, shin)

    # ---- Booties: the family asks every Shin pivot for authored Shoes_* meshes.
    for s in (-1, 1):
        side = "L" if s < 0 else "R"
        shin = legs[side][2]
        uv("Shoes_Sole_" + side, (s * .030, -.014, .022), (.026, .040, .019), shoes_sole, shin, 22, 12)
        uv("Shoes_Upper_" + side, (s * .030, -.008, .040), (.025, .036, .026), shoes, shin, 22, 12)
        uv("Shoes_Cuff_" + side, (s * .030, .010, .055), (.022, .018, .016), shoes, shin, 18, 10)
        tube("Shoes_Accent_" + side, [(s * .046, -.028, .026), (s * .030, -.046, .022), (s * .014, -.028, .026)],
             [.0032] * 3, shoes_accent, shin, 8, 1)

    # ---- Romper: a two-tone onesie. The torso piece is the outfit; the hip and
    # leg pieces answer the shared bottom switch, exactly like the trousers.
    romper_rings = [
        (0.298, .070, .059, -.004),
        (0.318, .065, .055, -.002),
        (0.338, .062, .051, .001),
        (0.354, .060, .048, .003),
        (0.366, .055, .045, .004),
        (0.376, .043, .038, .005),
    ]
    loft("Outfit_Casual_Romper", [(z, w, d, y, 0.0) for z, w, d, y in romper_rings], top, root, 28, 2)
    collar = []
    for i in range(33):
        a = 2 * pi * i / 32
        collar.append((.048 * sin(a), .005 - .043 * cos(a), .377))
    tube("Outfit_Casual_Collar", collar, [.006] * 33, top_seam, root, 8, 1)
    for s in (-1, 1):
        side = "L" if s < 0 else "R"
        tube("Outfit_Casual_Sleeve_" + side, [(s * .048, .001, .360), (s * .064, .002, .330), (s * .070, .003, .312)],
             [.031, .030, .028], top, root, 14, 1)

    hip_rings = [
        (0.190, .052, .045, .010),
        (0.206, .062, .053, .008),
        (0.230, .066, .057, .005),
        (0.256, .067, .058, -.001),
        (0.278, .066, .057, -.004),
        (0.300, .067, .056, -.004),
    ]
    loft("Bottom_Continuous_Romper", [(z, w, d, y, 0.0) for z, w, d, y in hip_rings], bottom, root, 28, 2)
    for s in (-1, 1):
        side = "L" if s < 0 else "R"
        tube("Bottom_Continuous_Romper_Leg_" + side,
             [(s * .026, .005, .230), (s * .028, .006, .200), (s * .028, .006, .170)],
             [.034, .033, .030], bottom, root, 14, 1)
        # The shorts alternative: a soft ruffle over the top of the bare thigh.
        tube("Bottom_Shorts_Cuff_" + side,
             [(s * .026, .006, .212), (s * .027, .006, .196), (s * .027, .006, .180)],
             [.038, .042, .040], bottom_seam, root, 16, 1)

    # ---- Hair: three original styles, all riding the Head pivot.
    hair_groups = {}
    # `grow` is the distance the shell sits off the scalp, along each skinned
    # normal. `hairline` raises the hem across the brow so the forehead stays
    # clear; `nape` lets the back hair fall below it. Nothing wraps the face.
    # `hem_front` is the hem at the very front of the shell: it must clear the
    # eyes, whose top edge is authored at z = 0.473. `hem_nape` is the hem at the
    # back, below the ears at z = 0.456, so the shell wraps the whole cranium.
    for style, grow, hem_front, hem_nape, nape in (("Hair_Crop", .0100, .482, .450, .016),
                                                   ("Hair_Bob", .0125, .480, .438, .056),
                                                   ("Hair_Curls", .0170, .484, .444, .034)):
        group = empty(style, (0, 0, 0), head)
        hair_groups[style] = group
        cap = hair_shell("." + style, grow, hem_front, hem_nape, nape)
        parent_keep(cap, group)
        if style == "Hair_Bob":
            for s in (-1, 1):
                tube(style + "_Lock", [(s * .090, .010, .480), (s * .094, .026, .452),
                                       (s * .092, .038, .420)],
                     [.023, .021, .013], hair, group, 12, 1)
        elif style == "Hair_Curls":
            for i in range(9):
                a = i * 2 * pi / 9
                uv(style + "_Puff", (.062 * sin(a), .010 + .064 * cos(a), .516 + .011 * cos(a * 2)),
                   (.024, .024, .022), hair, group, 16, 10)
        else:
            scale = 1.0 + grow / HEAD_RADIUS
            top = _shell_z(HEAD_RING_ROWS[-1][0], scale)
            tube(style + "_Crown", [(0, _shell_ring(top - .004, scale)[2] + .002, top - .004),
                                    (0, _shell_ring(top - .022, scale)[2] + .004, top - .022),
                                    (0, _shell_ring(top - .044, scale)[2] + .004, top - .044)],
                 [.0030, .0075, .0030], hair_hl, group, 10, 1, .55)

    # ---- Armature: the family bone contract, one child per authored pivot.
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    rig = bpy.context.object
    rig.name = "LifeRig"
    rig.data.name = "LifeRig"
    rig.data.edit_bones.remove(rig.data.edit_bones[0])
    for name, co, parent in BONES:
        b = rig.data.edit_bones.new(name)
        b.head = co
        b.tail = Vector(co) + Vector((0, 0, BONE_TAIL))
        b.roll = 0
        if parent:
            b.parent = rig.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    parent_keep(rig, root)

    # ---- Skinning: the family's analytic weights, no remesh, no heat diffusion.
    bind(torso, root, "torso")
    bind(headskin, root, "head")
    for side, (_, arm_mesh, thumb, _) in arms.items():
        bind(arm_mesh, root, "arm", side)
        bind(thumb, root, "arm", side)
    for side, (_, leg_mesh, _) in legs.items():
        bind(leg_mesh, root, "leg", side)
    for name in ("Outfit_Casual_Romper",):
        bind(D.objects[name], root, "torso")
    for s in (-1, 1):
        bind(D.objects["Outfit_Casual_Sleeve_" + ("L" if s < 0 else "R")], root, "arm", "L" if s < 0 else "R")
    lower = [D.objects["Bottom_Continuous_Romper"]]
    for s in (-1, 1):
        lower.append(D.objects["Bottom_Continuous_Romper_Leg_" + ("L" if s < 0 else "R")])
        lower.append(D.objects["Bottom_Shorts_Cuff_" + ("L" if s < 0 else "R")])
    for ob in lower:
        bind(ob, root, "lower")

    # ---- Expressions and identity sliders, on the same shared field the
    # creator already drives for every other age.
    headskin.shape_key_add(name="Basis")
    blink = headskin.shape_key_add(name="Blink")
    smile = headskin.shape_key_add(name="Smile")
    for i, v in enumerate(headskin.data.vertices):
        x, y, z = v.co
        if 0.424 < z < 0.484 and abs(x) < .068 and y < -.035:
            w = math.exp(-((abs(x) - .034) / .024) ** 2 - ((z - .454) / .014) ** 2)
            blink.data[i].co.z -= .014 * w
            blink.data[i].co.y += .0024 * w
        if 0.396 < z < 0.424 and abs(x) < .032 and y < -.052:
            w = math.exp(-((abs(x) - .012) / .012) ** 2 - ((z - .408) / .011) ** 2)
            smile.data[i].co.z += .004 * w
            smile.data[i].co.y -= .0013 * w
    for ob in eyes:
        ob.shape_key_add(name="Basis")
        key = ob.shape_key_add(name="Blink")
        key.value = 0
        # The globe retreats behind the closing lid, exactly like the family's
        # globe_blink: +Y is backward, so the sphere slides into the socket.
        retreat = .008 if ob.name.startswith("Eyes_Sclera") else .010
        for i, v in enumerate(ob.data.vertices):
            key.data[i].co.y += retreat
    # The romper legs answer the shared seated corrective.
    for ob in lower:
        if ob.name.startswith("Bottom_Continuous") or ob.name.startswith("Bottom_Shorts"):
            bind_sit(ob, .135)

    bind_identity([headskin] + [ob for ob in eyes if ob.name.startswith(("Eyes_Sclera", "Eyes_Iris", "Eyes_Pupil"))])

    # ---- Landmarks the runtime reads back out of the exported extras.
    root["asset_author"] = "JustLife original procedural sculpture"
    root["forward"] = "Godot +Z"
    root["age_stage"] = "baby"
    root["age_revision"] = 1
    root["rig_version"] = 18
    root["height_m"] = HEIGHT_M
    root["hip_height"] = HIP_Z
    root["knee_height"] = KNEE_Z
    root["head_height"] = HEAD_Z
    root["hair_variants"] = "Hair_Crop, Hair_Bob, Hair_Curls"
    root["default_hair"] = "Hair_Crop"
    root["identity_morphs"] = "Face_Round,Jaw_Strong,Nose_Wide,Eye_Spacing"
    root["wardrobe_variants"] = "Outfit_Casual"
    root["grip_morphs"] = ""
    mouth_world = Vector((0, face_surface_y(headskin, 0.0, .4085) - .0020, .408))
    palm_world = {"L": Vector((-.088, -.012, .202)), "R": Vector((.088, -.012, .202))}
    root["mouth_anchor"] = godot_vector(D.objects["Head"].matrix_world.inverted() @ mouth_world)
    for side in ("l", "r"):
        fore = D.objects["Forearm_" + side.upper()]
        root["palm_anchor_" + side] = godot_vector(fore.matrix_world.inverted() @ palm_world[side.upper()])
    root["bone_landmarks"] = ";".join(
        name + ":" + ",".join(str(v) for v in godot_vector(Vector(co)))
        for name, co, _ in BONES
    )

    # Studio renders show the default style; every other group stays exported.
    for style, group in hair_groups.items():
        for node in descendants(group):
            node.hide_render = style != "Hair_Crop"

    studio = studio_setup(root)
    return root, rig, hair_groups, studio


def hair_shell(name, grow, hem_front, hem_nape, nape):
    """A hair volume that is a true offset of the authored skull.

    The shell is a copy of the skull's own ring table scaled about the head
    centre, so it strictly contains the skin at every height -- a dome cannot be
    cleared by a purely radial offset, and a scaled copy is exact. The hem is
    then a smooth curve rather than a ring boundary: it arcs up over the brow,
    sweeps back past the temples, and drops to the nape.
    """
    count = 28
    steps = 9
    scale = 1.0 + grow / HEAD_RADIUS
    top = _shell_z(HEAD_RING_ROWS[-1][0], scale)
    verts = []
    for j in range(count):
        a = 2 * pi * j / count
        face = .5 + .5 * cos(a)               # 1 at the face, 0 at the nape
        hem = _shell_z(hem_front + (hem_nape - hem_front) * (1.0 - face) ** .7
                       - nape * (1.0 - face) ** 1.5, scale)
        for k in range(steps):
            t = k / float(steps)
            z = hem + (top - hem) * (t ** .80)
            # The hem seals onto the scalp: the radius factor starts at the skin
            # itself and reaches the full shell offset a short way up, so the
            # hairline is a rounded edge rather than a thin horizontal shelf.
            w, d, y = _shell_ring(z, 1.0 + (scale - 1.0) * smoothstep(0.0, .16, t))
            verts.append((w * sin(a), y - d * cos(a), z))
    # A single apex seals the crown, so the shell is a closed volume.
    apex = len(verts)
    verts.append((0.0, _shell_ring(top, scale)[2], top))
    faces = []
    for k in range(steps - 1):
        for j in range(count):
            faces.append((k * count + j, k * count + (j + 1) % count,
                          (k + 1) * count + (j + 1) % count, (k + 1) * count + j))
    for j in range(count):
        faces.append(((steps - 1) * count + j, (steps - 1) * count + (j + 1) % count, apex))
    shell = mesh(name + "_Cap", verts, faces, D.materials["Hair"], None, 2)
    solid(shell, .0028)
    return shell


def _shell_z(z, scale):
    return HEAD_CENTRE + (z - HEAD_CENTRE) * scale


def _shell_ring(z, scale):
    """Skull half-width, half-depth and y at shell height `z`, scaled about the centre."""
    z_skin = HEAD_CENTRE + (z - HEAD_CENTRE) / scale
    w, d, y = ring_at(z_skin)
    return w * scale, d * scale, HEAD_CENTRE + (y - HEAD_CENTRE) * scale


def face_surface_y(headskin, x, z):
    """The sculpted face surface depth at (x, z), taken from the skull's own vertices.

    Features are placed relative to this rather than a constant, so they stay on
    the face whatever the cheek and chin sculpt does.
    """
    best = None
    best_distance = 1e9
    for vertex in headskin.data.vertices:
        point = vertex.co
        if point.y > .010:
            continue
        distance = (point.x - x) ** 2 + (point.z - z) ** 2
        if distance < best_distance:
            best_distance = distance
            best = point
    return best.y if best is not None else -0.086


def ring_at(z):
    """Interpolate the authored skull ring at height `z`: half-width, half-depth, y."""
    rows = HEAD_RING_ROWS
    if z <= rows[0][0]:
        return rows[0][1], rows[0][2], rows[0][3]
    if z >= rows[-1][0]:
        return rows[-1][1], rows[-1][2], rows[-1][3]
    for index in range(len(rows) - 1):
        low, high = rows[index], rows[index + 1]
        if low[0] <= z <= high[0]:
            t = (z - low[0]) / (high[0] - low[0])
            return (low[1] + (high[1] - low[1]) * t,
                    low[2] + (high[2] - low[2]) * t,
                    low[3] + (high[3] - low[3]) * t)
    return rows[-1][1], rows[-1][2], rows[-1][3]


def godot_vector(point):
    return [round(point.x, 6), round(point.z, 6), round(-point.y, 6)]


def apply_mesh(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    return bpy.context.object


def bind(ob, root, mode, side=""):
    """Analytic skin weights on the authored coordinates, then one armature."""
    ob = apply_mesh(ob)
    parent_keep(ob, root)
    mw = ob.matrix_world.copy()
    ob.data.transform(mw)
    ob.matrix_world.identity()
    groups = {name: ob.vertex_groups.new(name=name) for name in GROUPS}
    for v in ob.data.vertices:
        x, y, z = v.co
        weights = {}
        if mode == "torso":
            spine = smoothstep(.238, .282, z)
            head = smoothstep(.358, .398, z)
            weights = {"Root": (1 - spine) * (1 - head), "Spine": spine * (1 - head), "Head": head}
        elif mode == "head":
            weights = {"Head": 1.0}
        elif mode == "arm":
            upper = smoothstep(.252, .300, z)
            weights = {"Arm_" + side: upper, "Forearm_" + side: 1.0 - upper}
        elif mode == "leg":
            weights = {"Leg_" + side: smoothstep(KNEE_Z - .026, KNEE_Z + .026, z),
                       "Shin_" + side: 1.0 - smoothstep(KNEE_Z - .026, KNEE_Z + .026, z)}
        else:  # lower: romper hips, leg tubes and cuffs across both legs
            shin = 1 - smoothstep(.104, .168, z)
            leg = smoothstep(.104, .168, z) * (1 - smoothstep(.205, .255, z))
            torso = smoothstep(.205, .255, z)
            lateral = smoothstep(-.008, .008, x)
            spine = smoothstep(.255, .310, z)
            weights = {"Shin_L": shin * (1 - lateral), "Shin_R": shin * lateral,
                       "Leg_L": leg * (1 - lateral), "Leg_R": leg * lateral,
                       "Root": torso * (1 - spine), "Spine": torso * spine}
        for name, value in weights.items():
            if value > .0001:
                groups[name].add([v.index], value, "REPLACE")
    modifier = ob.modifiers.new("Soft skeletal deformation", "ARMATURE")
    modifier.object = D.objects["LifeRig"]
    modifier.use_deform_preserve_volume = False
    return ob


def bind_sit(ob, knee_z):
    """A bounded seated corrective on the garment over the knees."""
    basis = [v.co.copy() for v in ob.data.vertices]
    ob.shape_key_add(name="Basis")
    key = ob.shape_key_add(name="Sit")
    key.value = 0
    for i, v in enumerate(ob.data.vertices):
        weight = math.exp(-((basis[i].z - knee_z) / .045) ** 2)
        key.data[i].co = basis[i] + Vector((0.0, 0.020 * weight, 0.006 * weight))
    return ob


def identity_delta(name, co):
    x, y, z = co
    front = 1 - smoothstep(-.035, .020, y)
    if name == "Face_Round":
        w = math.exp(-((z - .460) / .055) ** 4) * smoothstep(.392, .420, z)
        return Vector((.011 * math.tanh(x / .032) * w, -.0040 * front * w,
                       .0045 * math.exp(-(x / .038) ** 2 - ((z - .414) / .022) ** 2)))
    if name == "Jaw_Strong":
        w = math.exp(-((z - .416) / .024) ** 4) * smoothstep(.390, .410, z)
        return Vector((.013 * math.tanh(x / .028) * w, -.0045 * front * w,
                       -.0028 * math.exp(-(x / .032) ** 2 - ((z - .408) / .016) ** 2)))
    if name == "Nose_Wide":
        w = math.exp(-(x / .022) ** 4 - ((z - .432) / .018) ** 4) * (1 - smoothstep(-.078, -.052, y))
        return Vector((.0075 * math.tanh(x / .008) * w, -.0013 * w, 0.0))
    if name == "Eye_Spacing":
        w = (1 - smoothstep(.056, .090, abs(x))) * (1 - smoothstep(.016, .040, abs(z - .452))) * front
        return Vector((.0055 * math.tanh(x / .007) * w, 0.0, 0.0))
    return Vector()


def bind_identity(objects):
    """The shared four-slider identity field, mirrored from create_characters.py."""
    names = ["Face_Round", "Jaw_Strong", "Nose_Wide", "Eye_Spacing"]
    for ob in objects:
        if ob.data.shape_keys is None:
            ob.shape_key_add(name="Basis")
        for name in names:
            key = ob.shape_key_add(name=name)
            key.value = 0
            for index, vertex in enumerate(ob.data.vertices):
                key.data[index].co = vertex.co + identity_delta(name, vertex.co)


def studio_setup(root):
    """Render-only studio; never exported."""
    studio = empty("Studio")
    floor = mat("Studio_sand", "DCD7C8", .9)
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -.001))
    o = bpy.context.object
    o.name = "Studio_floor"
    o.data.materials.append(floor)
    parent_keep(o, studio)
    world = D.worlds.new("Studio world") if not D.worlds else D.worlds[0]
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (.74, .78, .74, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = .6
    for name, loc, energy, size in (("Key", (-1.2, -1.6, 2.0), 90, 2.0),
                                    ("Fill", (1.2, -0.8, 1.2), 40, 1.6),
                                    ("Rim", (0.4, 1.2, 1.6), 70, 1.4)):
        bpy.ops.object.light_add(type="AREA", location=loc)
        o = bpy.context.object
        o.name = name
        o.data.energy = energy
        o.data.shape = "DISK"
        o.data.size = size
        o.rotation_euler = (Vector((0, 0, .3)) - o.location).to_track_quat("-Z", "Y").to_euler()
        parent_keep(o, studio)
    bpy.ops.object.camera_add()
    cam = bpy.context.object
    cam.name = "Character_Portrait"
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = .78
    parent_keep(cam, studio)
    bpy.context.scene.camera = cam
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 700
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    scene.render.image_settings.file_format = "PNG"
    return studio


def camera_view(cam, location, target, ortho):
    cam.location = Vector(location)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = ortho


def ensure_uvs():
    for ob in D.objects:
        if ob.type != "MESH" or ob.data.uv_layers:
            continue
        layer = ob.data.uv_layers.new(name="SurfaceUV")
        for poly in ob.data.polygons:
            normal = poly.normal
            drop = max(range(3), key=lambda axis: abs(normal[axis]))
            axes = [axis for axis in range(3) if axis != drop]
            for loop_index in poly.loop_indices:
                point = ob.data.vertices[ob.data.loops[loop_index].vertex_index].co
                layer.data[loop_index].uv = ((point[axes[0]] + .5) * .5, (point[axes[1]] + .5) * .5)


def reset_expressions():
    for ob in D.objects:
        if ob.type == "MESH" and ob.data.shape_keys:
            for key in ob.data.shape_keys.key_blocks:
                if key.name != "Basis":
                    key.value = 0.0


def descendants(node):
    yield node
    for child in node.children:
        yield from descendants(child)


def export(path):
    root = D.objects["Character"]
    reset_expressions()
    ensure_uvs()
    bpy.ops.object.select_all(action="DESELECT")
    for o in descendants(root):
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    final_path = ROOT / path
    # Publish atomically so a running Godot editor cannot import a half file.
    with tempfile.TemporaryDirectory(prefix=".justlife-export-", dir=str(final_path.parent)) as temporary:
        open(os.path.join(temporary, ".gdignore"), "w").close()
        staged = os.path.join(temporary, final_path.name)
        bpy.ops.export_scene.gltf(filepath=staged, export_format="GLB", use_selection=True,
                                  export_apply=True, export_yup=True, export_animations=False,
                                  export_morph=True, export_skins=True, export_extras=True,
                                  export_cameras=False, export_lights=False)
        os.replace(staged, final_path)
    reset_expressions()
    return hashlib.sha256(final_path.read_bytes()).hexdigest()


def lod_modifiers(root, low):
    added = []
    for o in descendants(root):
        if o.type == "MESH" and o.data.shape_keys is None:
            mod = o.modifiers.new("Live camera reduction", "DECIMATE")
            mod.ratio = .32 if "Head" in o.name or "Body" in o.name else .40
            if o.modifiers.find("Soft skeletal deformation") >= 0:
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.modifier_move_up(modifier=mod.name)
            added.append((o, mod))
        elif o.type == "CURVE":
            added.append((o, None))
    return added


def clear_lod(added):
    for o, mod in added:
        if mod is not None:
            o.modifiers.remove(mod)


def posed_bounds(root):
    """World bounds of the evaluated (armature-deformed) character."""
    graph = bpy.context.evaluated_depsgraph_get()
    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    for node in descendants(root):
        if node.type != "MESH":
            continue
        evaluated = node.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        matrix = evaluated.matrix_world
        for vertex in mesh.vertices:
            point = matrix @ vertex.co
            low = Vector((min(low.x, point.x), min(low.y, point.y), min(low.z, point.z)))
            high = Vector((max(high.x, point.x), max(high.y, point.y), max(high.z, point.z)))
        evaluated.to_mesh_clear()
    return low, high


def render_evidence(rig, directory):
    directory.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    cam = D.objects["Character_Portrait"]
    scene.render.resolution_x = 700
    scene.render.resolution_y = 800
    for label, location, ortho in (("front", (0.0, -1.6, .30), .74), ("side", (1.5, -0.06, .30), .74)):
        camera_view(cam, location, (0, 0, .30), ortho)
        scene.render.filepath = str(directory / ("baby_%s.png" % label))
        bpy.ops.render.render(write_still=True)
    # The crawl pose is the shared numeric contract in crawl_pose.py, which
    # scripts/actor.gd mirrors in _baby_crawl_pose / _baby_crawl_offset.
    sys.path.insert(0, str(HERE))
    import crawl_pose
    crawl_pose.apply(rig, 0.0, crawl_pose.solve_offset(rig, 0.0))
    bpy.context.view_layer.update()
    # The crawl body lies along the floor, so frame its measured bounds rather
    # than the standing pivot. The camera is placed from the real posed geometry.
    low, high = posed_bounds(D.objects["Character"])
    centre = (low + high) * .5
    reach = max(high.x - low.x, high.y - low.y, high.z - low.z) * .62
    for label, (dx, dy, dz) in (("crawl_side", (1.6, -0.10, .30)),
                                ("crawl_front", (0.24, -1.5, .26))):
        eye = centre + Vector((dx * reach, dy * reach, dz))
        camera_view(cam, eye, (centre.x, centre.y, centre.z * .55), reach * 2.4)
        scene.render.filepath = str(directory / ("baby_%s.png" % label))
        bpy.ops.render.render(write_still=True)
    crawl_pose.clear(rig)


def main():
    root, rig, hair_groups, studio = build()
    report = {"family": "baby", "objects": len(D.objects), "height_m": HEIGHT_M}
    if args.export or args.save or args.source:
        bpy.context.preferences.filepaths.save_version = 0
        blend = ROOT / "art" / "characters_baby.blend"
        bpy.ops.wm.save_as_mainfile(filepath=str(blend))
        report["source"] = str(blend.relative_to(ROOT))
        report["source_sha256"] = hashlib.sha256(blend.read_bytes()).hexdigest()
    if args.export:
        outputs = {}
        for variant, width, low in (("character_baby", 1.0, False),
                                    ("character_baby_broad", 1.12, False),
                                    ("character_baby_lod", 1.0, True),
                                    ("character_baby_broad_lod", 1.12, True)):
            added = lod_modifiers(root, low) if low else []
            root.scale.x = width
            outputs[variant + ".glb"] = export("assets/models/" + variant + ".glb")
            root.scale.x = 1.0
            clear_lod(added)
        report["exports"] = outputs
    if args.preview_dir:
        args.preview_dir.mkdir(parents=True, exist_ok=True)
        scene = bpy.context.scene
        cam = D.objects["Character_Portrait"]
        camera_view(cam, (0.35, -1.5, .38), (0, 0, .30), .82)
        scene.render.filepath = str(args.preview_dir / "baby_preview_v6.png")
        bpy.ops.render.render(write_still=True)
    if args.evidence_dir:
        render_evidence(rig, args.evidence_dir)
        report["evidence"] = sorted(str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p)
                                    for p in args.evidence_dir.glob("*.png"))
    manifest = {
        "tool": "baby_v60",
        "blender": bpy.app.version_string,
        "blender_build": bpy.app.build_hash.decode(),
        "generator_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
        "pose_spec_sha256": hashlib.sha256((HERE / "crawl_pose.py").read_bytes()).hexdigest(),
        "contract_inputs": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in CONTRACT_INPUTS},
        "policy": ("Authored parametrically from this source only: no voxel remesh and no random "
                   "state. A rerun rebuilds the same glTF JSON and the same vertex/index "
                   "counts; the exporter may reorder the binary buffers, so the recorded "
                   "hashes are provenance for this run rather than a cross-run promise. "
                   "Exports through the create_characters "
                   "export steps (rest pose, zeroed morphs, broad x-scale 1.12, decimated LOD)."),
        "report": report,
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=1) + "\n")
    print("JUSTLIFE_BABY_REPORT " + json.dumps(report))


if __name__ == "__main__":
    main()
