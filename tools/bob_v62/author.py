"""Author an original, continuous side-parted bob on the existing Hair_Bob root.

Only descendants of Hair_Bob are replaced. The adult design coordinates can
optionally be fitted to an evaluated age-family skull, then stored in the
existing group's local space. The group, head attachment, source material and
every other scene object remain untouched. This is a candidate authoring tool,
never an automatic production promotion.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

P = argparse.ArgumentParser(description=__doc__)
P.add_argument('--input', type=Path, required=True)
P.add_argument('--output', type=Path, required=True)
P.add_argument('--report', type=Path, required=True)
P.add_argument('--fit-family', action='store_true', help='Fit design to evaluated skull, including baked age families')
A = P.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert A.input.resolve() != A.output.resolve(), 'Candidate must not replace its input'


def fingerprint(o):
    h = hashlib.sha256()
    def feed(v):
        h.update(repr(v).encode()); h.update(b'\0')
    feed((o.name, o.type, o.parent.name if o.parent else '', o.parent_type, o.parent_bone))
    feed(tuple(tuple(row) for row in o.matrix_basis))
    feed(tuple(tuple(row) for row in o.matrix_parent_inverse))
    feed((o.hide_render, o.hide_viewport))
    if o.type == 'MESH':
        feed(tuple(tuple(v.co) for v in o.data.vertices))
        feed(tuple((tuple(p.vertices), p.material_index, p.use_smooth) for p in o.data.polygons))
        feed(tuple(m.name if m else '' for m in o.data.materials))
        feed(tuple((u.name, tuple(tuple(p.uv) for p in u.data)) for u in o.data.uv_layers))
        feed(tuple(g.name for g in o.vertex_groups))
        feed(tuple(tuple((g.group, g.weight) for g in v.groups) for v in o.data.vertices))
        if o.data.shape_keys:
            feed(tuple((k.name, k.value, tuple(tuple(v.co) for v in k.data)) for k in o.data.shape_keys.key_blocks))
    if o.type == 'CURVE':
        feed(tuple((s.type, tuple(tuple(v.co) for v in s.bezier_points), tuple(tuple(v.co) for v in s.points)) for s in o.data.splines))
    if o.type == 'ARMATURE':
        feed(tuple((b.name, b.parent.name if b.parent else '', tuple(tuple(row) for row in b.matrix_local), b.use_deform)
                   for b in o.data.bones))
        feed(tuple((b.name, tuple(tuple(row) for row in b.matrix_basis), b.rotation_mode) for b in o.pose.bones))
    feed(tuple((m.name, m.type) for m in o.modifiers))
    return h.hexdigest()


def children(o):
    for c in o.children:
        yield c
        yield from children(c)


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def lerp(a, b, f):
    return a * (1 - f) + b * f


def sample(knots, x):
    """Monotone cubic interpolation, with a continuous slope through knots."""
    if x <= knots[0][0]:
        return knots[0][1]
    slopes = [(knots[i + 1][1] - knots[i][1]) / (knots[i + 1][0] - knots[i][0])
              for i in range(len(knots) - 1)]
    derivatives = [slopes[0]]
    for left, right in zip(slopes, slopes[1:]):
        derivatives.append(2 * left * right / (left + right) if left * right > 0 else 0.0)
    derivatives.append(slopes[-1])
    for i in range(len(knots) - 1):
        a, va = knots[i]; b, vb = knots[i + 1]
        if x <= b:
            f = max(0.0, min(1.0, (x - a) / (b - a)))
            return ((2*f**3 - 3*f**2 + 1) * va + (f**3 - 2*f**2 + f) * (b-a) * derivatives[i]
                    + (-2*f**3 + 3*f**2) * vb + (f**3-f**2) * (b-a) * derivatives[i+1])
    return knots[-1][1]


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


# A high side part, a long left face-frame and a graduated nape define the cut.
# This boundary is deliberately an arc, not equal-length individual spikes.
HEM = [(-math.pi, 1.523), (-2.5, 1.515), (-1.8, 1.501), (-1.4, 1.496),
       (-1.10, 1.501), (-.92, 1.520), (-.74, 1.616), (-.42, 1.661),
       (0.0, 1.687), (.34, 1.704), (.50, 1.706), (.67, 1.692),
       (.84, 1.651), (1.01, 1.551), (1.25, 1.514), (1.8, 1.504),
       (2.5, 1.518), (math.pi, 1.523)]


def hem(a):
    a = wrap(a)
    base = sample(HEM, a)
    # Tiny uneven grouped layers at the lower cut; avoid a sawtooth hem.
    layer = .0022 * math.sin(9 * a + .6 * math.sin(3 * a))
    layer += .0010 * math.sin(17 * a + .9)
    return base + layer * smooth((abs(a) - .85) / .50)


def profile(z):
    if z >= 1.66:
        fac = math.sqrt(max(0.0, 1.0 - ((z - 1.612) / .154) ** 2))
        return .126 * fac, .130 * fac
    return (sample([(1.49, .117), (1.515, .132), (1.555, .143), (1.58, .142),
                    (1.61, .134), (1.637, .125), (1.66, .119722)], z),
            sample([(1.49, .103), (1.515, .119), (1.565, .133),
                    (1.61, .132), (1.637, .1283), (1.66, .123523)], z))


def point(a, t, extra=0.0):
    """One uninterrupted scalp-to-cut surface with shallow directional channels."""
    end = hem(a)
    # Cosine latitude gives an even crown fan and enough lower-hem rows.
    travel = 1.0 - math.cos(t * math.pi / 2.0)
    z = lerp(1.766, end, travel)
    rx, ry = profile(z)
    center_x = .014 * math.exp(-((z - 1.751) / .046) ** 2)
    center_y = .012
    # Soft directional grouped fluting follows the sweep, not vertical rods.
    phase = a + .19 * math.sin(a - .5) * (1.0 - travel)
    phase += .09 * math.sin(2 * a + 1.5) * travel
    group = (.00120 * math.cos(13 * phase + .7 * math.sin(3 * phase)) +
             .00045 * math.cos(27 * phase + 1.8))
    group *= smooth(t / .26) * (.50 + .50 * smooth((travel - .35) / .45))
    x = center_x + (rx + group + extra) * math.sin(a)
    y = center_y - (ry + group + extra) * math.cos(a)
    # Recess the part into the scalp surface. It becomes a subtle dark channel
    # under normal lighting, and does not require a black painted stripe.
    part_x = .038 + .050 * y
    groove = .0021 * math.exp(-((x - part_x) / .0045) ** 2)
    groove *= smooth((z - 1.710) / .021) * smooth((.075 - y) / .025)
    z -= groove
    # The upper front rim grows from the actual scalp. A stand-off front edge
    # otherwise exposes a hollow dark cavity and reads like a fabric hood.
    contact = smooth((1.03 - abs(wrap(a))) / .28) * smooth((t - .83) / .17)
    if FIT is not None:
        return FIT.map(Vector((x, y, z)), a, t, extra)
    if contact > 0.0 and z < 1.739:
        direction = Vector((math.sin(a), -math.cos(a), 0.0))
        hit, normal, index, distance = SCALP.ray_cast(Vector((0, .012, z)), direction, .3)
        if hit is not None:
            target = hit + direction * (.005 + max(0, extra))
            x = lerp(x, target.x, contact)
            y = lerp(y, target.y, contact)
    return Vector((x, y, z))


def make_mesh(name, vertices, faces, root, material, uv):
    inv = root.matrix_world.inverted()
    me = bpy.data.meshes.new(name + '_sculpt')
    me.from_pydata([inv @ v for v in vertices], [], faces)
    me.update()
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = True
    layer = me.uv_layers.new(name='SurfaceUV')
    for poly in me.polygons:
        for loop_id in poly.loop_indices:
            layer.data[loop_id].uv = uv[me.loops[loop_id].vertex_index]
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.parent = root
    o.hide_render = False
    o.hide_viewport = False
    return o


def closed_cap(root, material):
    n = 224; rows = 76
    vertices = [point(0.0, 0.0)]
    uv = [(0.5, 0.0)]
    for i in range(1, rows + 1):
        t = i / rows
        for j in range(n):
            a = -math.pi + 2 * math.pi * j / n
            vertices.append(point(a, t))
            uv.append((j / n, t))
    faces = []
    # Outward face winding: the angular tangent crossed with latitude tangent.
    for j in range(n):
        faces.append((0, 1 + j, 1 + (j + 1) % n))
    for i in range(rows - 1):
        r = 1 + i * n; q = r + n
        for j in range(n):
            k = (j + 1) % n
            faces.append((r + j, q + j, q + k, r + k))
    o = make_mesh('Hair_Bob_Cap', vertices, faces, root, material, uv)
    # A real inward rim gives the face opening and hem thickness without
    # exposing backs of hair triangles in Godot's normal single-sided material.
    solid = o.modifiers.new('Finished hair shell', 'SOLIDIFY')
    solid.thickness = .0045 * DETAIL_LOCAL_SCALE
    solid.offset = -1.0
    solid.use_even_offset = True
    return o


def swept_layer(root, material, name, start_a, end_a, first_t, last_t, width, lift):
    """A broad scalp-attached shallow layer, fading in below the surface at root."""
    rows = 40; cols = 14
    verts = []; uv = []
    for i in range(rows + 1):
        s = i / rows
        a = lerp(start_a, end_a, smooth(s))
        t = lerp(first_t, last_t, s)
        w = width * (math.sin(math.pi * (s * .86 + .10)) ** .48)
        if s > .85:
            w *= lerp(1.0, .04, smooth((s - .85) / .15))
        for j in range(cols + 1):
            across = j / cols * 2 - 1
            # Both sides and the upper root are embedded in the continuous cap.
            section = max(0, 1 - across * across) ** .80
            raised = lift * section * math.sin(math.pi * s) ** .65 - .0015
            p = point(a + w * across, t, raised)
            # Ends follow the main cut but are soft, individually offset layers.
            if s > .87:
                p.z -= .0015 * (FIT.sz if FIT else 1.0) * smooth((s - .87) / .13) * section
            verts.append(p); uv.append((j / cols, s))
    faces = []
    for i in range(rows):
        for j in range(cols):
            q = i * (cols + 1) + j
            faces.append((q, q + cols + 1, q + cols + 2, q + 1))
    o = make_mesh(name, verts, faces, root, material, uv)
    solid = o.modifiers.new('Layer closed underside', 'SOLIDIFY')
    solid.thickness = .002 * DETAIL_LOCAL_SCALE; solid.offset = -1.0
    return o


bpy.ops.wm.open_mainfile(filepath=str(A.input.resolve()))
family = str(bpy.data.objects['Character'].get('age_stage', 'adult'))
assert A.fit_family or family == 'adult', \
    'This Bob design is authored for adult proportions; age variants need a separate fit pass'
root = bpy.data.objects['Hair_Bob']
head = bpy.data.objects['Skin_Head_continuous']
FIT = None
DETAIL_LOCAL_SCALE = 1.0
if A.fit_family:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from fit import SkullFit
    FIT = SkullFit(head, bpy.data.objects['Head'], root)
    root_scale = abs(root.matrix_world.to_scale().x)
    assert max(root.matrix_world.to_scale())-min(root.matrix_world.to_scale()) < 1e-5, 'Unexpected nonuniform Bob root'
    DETAIL_LOCAL_SCALE = FIT.detail_scale/root_scale
SCALP = BVHTree.FromPolygons([head.matrix_world @ v.co for v in head.data.vertices],
                            [tuple(p.vertices) for p in head.data.polygons])
original_children = list(children(root))
owned = {o.name for o in original_children}
outside = {o.name: fingerprint(o) for o in bpy.data.objects if o.name not in owned}
material = bpy.data.materials['Hair']
root_matrix = root.matrix_world.copy()
for o in reversed(original_children):
    bpy.data.objects.remove(o, do_unlink=True)

made = [closed_cap(root, material)]
# Three unequal surface sweeps make the side part legible. All begin embedded
# in the shared shell, and all follow its surface; none is a hanging cylinder.
made.append(swept_layer(root, material, 'Hair_Bob_Sweep', .20, -.90, .23, .995, .17, .0047))
made.append(swept_layer(root, material, 'Hair_Bob_TempleLayer', -.45, -1.30, .32, .993, .13, .0035))
made.append(swept_layer(root, material, 'Hair_Bob_TuckLayer', .66, 1.30, .40, .985, .12, .0033))
if FIT:
    made[0]['bob_fit_family'] = family
    made[0]['bob_fit_linear_scale'] = [FIT.sx, FIT.sy, FIT.sz]
    made[0]['bob_fit_detail_local_scale'] = DETAIL_LOCAL_SCALE
bpy.context.view_layer.update()
assert root.matrix_world == root_matrix
current = {o.name: fingerprint(o) for o in bpy.data.objects if o.name not in {x.name for x in made}}
assert current == outside, 'An object outside Hair_Bob changed'
for o in made:
    assert o.parent == root and len(o.data.uv_layers) == 1
    assert not o.data.shape_keys

A.output.parent.mkdir(parents=True, exist_ok=True)
A.report.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(A.output.resolve()))
report = {'input': str(A.input.resolve()), 'output': str(A.output.resolve()),
          'scope': 'Hair_Bob descendants only', 'unchanged_objects': len(outside),
          'removed': sorted(owned), 'created': [{'name': o.name, 'vertices': len(o.data.vertices),
                                              'faces': len(o.data.polygons)} for o in made],
          'source_sha256': hashlib.sha256(A.input.read_bytes()).hexdigest(),
          'candidate_sha256': hashlib.sha256(A.output.read_bytes()).hexdigest()}
if FIT:
    report['family'] = family
    report['fit'] = FIT.report()
A.report.write_text(json.dumps(report, indent=2) + '\n')
print('BOB_CANDIDATE', json.dumps(report))
