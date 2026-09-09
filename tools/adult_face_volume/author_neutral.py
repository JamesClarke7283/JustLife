"""Original-production, four-object lower-face neutral sculpture. No export/render."""
from pathlib import Path
import argparse, hashlib, json, math, sys
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P = Path(__file__).resolve().parent
sys.path.insert(0, str(P.parent / 'adult_eyes'))
import source_facts as witness
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
out = args.output.resolve()
assert not out.exists()
out.mkdir()
(out / 'art').mkdir()
source = args.source.resolve()
PIN = '2f2dec8e9919482c10aa76975595bd053e379ecea3d4728c1b77603ee14e961c'
assert witness.sha(source) == PIN
bpy.ops.wm.open_mainfile(filepath=str(source))
bpy.context.view_layer.update()
OWNED = ['Skin_Head_continuous', 'Lips_Upper_soft', 'Lips_Lower_soft', 'Lips_Smile_seam']
witness.OWNED = set(OWNED)
before = witness.objects()
head = bpy.data.objects[OWNED[0]]
pivot = Vector((0, 0.005, 1.458))
SCALE = 0.91

# Quintic C2 fades avoid the original clamped quadratic corner kink.
def fade(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * t * (t * (t * 6 - 15) + 10)

def band(a, b, c, d, x):
    return fade(a, b, x) * (1 - fade(c, d, x))

def authored(world):
    return pivot + (world - pivot) / SCALE

def global_co(o, v):
    return o.matrix_world @ v
old = {}
for name in OWNED:
    o = bpy.data.objects[name]
    keys = o.data.shape_keys.key_blocks
    assert all((k.relative_key == keys['Basis'] for k in keys))
    old[name] = {'mesh': [v.co.copy() for v in o.data.vertices], 'keys': {k.name: [v.co.copy() for v in k.data] for k in keys}, 'world': [global_co(o, v.co) for v in keys['Basis'].data]}
    o.data.calc_loop_triangles()
    old[name]['triangles'] = [list(t.vertices) for t in o.data.loop_triangles]

def tree(o, points):
    return BVHTree.FromPolygons(points, [list(p.vertices) for p in o.data.polygons])
old_head_tree = tree(head, old[head.name]['world'])

def front(tree, x, z):
    hit, normal, index, distance = tree.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)), 2.0)
    assert hit is not None and hit.y < -0.045, ('missing facial support', x, z)
    return float(hit.y)
landmarks = [(z, None) for z in [1.465, 1.473, 1.48, 1.486, 1.491, 1.497, 1.504, 1.508, 1.515, 1.524, 1.53, 1.535]]
xs = [x for x, y in landmarks]
baseline = [-front(old_head_tree, 0, x) for x in xs]
ys = [None] * len(xs)
slopes = [None] * len(xs)

# Protect upper face, outer width and back; all values are Blender world metres.
def weight(world):
    x, y, z = world
    return band(1.459, 1.47, 1.519, 1.535, z) * (1 - fade(0.045, 0.074, abs(x))) * (1 - fade(-0.05, -0.018, y))

# Broad chin, muzzle and corner support. These are art fields, not anatomical targets.
def shared(world):
    x, y, z = world
    ax = abs(x)
    w = weight(world)
    chin = 0.014 * math.exp(-(x / 0.048) ** 2 - ((z - 1.48) / 0.0145) ** 2)
    muzzle = 0.0046 * math.exp(-(x / 0.062) ** 2 - ((z - 1.511) / 0.024) ** 2)
    corner = 0.0034 * math.exp(-((ax - 0.032) / 0.028) ** 2 - ((z - 1.51) / 0.024) ** 2) * fade(0.008, 0.025, ax)
    q = abs(authored(world).x) / 0.033
    corner_drop = -0.0014 * fade(0, 1, q) * band(1.485, 1.498, 1.52, 1.535, z)
    return Vector((0, -(chin + muzzle + corner) * w, corner_drop * w))

def quant_local(o, world_delta):
    v = o.matrix_world.to_3x3().inverted() @ world_delta
    return Vector(tuple((round(c / 2 ** (-22)) * 2 ** (-22) for c in v)))
report = {'input_sha256': PIN, 'scope': 'V4 neutral only; original production input; four meshes; broad smooth world chin/muzzle/corner field with local neighbor regularization, followed by actual-surface lip fitting. No exact landmark target or visual acceptance.', 'owned_objects': OWNED, 'landmarks': [{'world_height': x, 'production_depth': b, 'art_target_depth': y, 'delta': d, 'delta_slope': m} for (x, y), b, d, m in zip(landmarks, baseline, ys, slopes)], 'changes': {}, 'relative_rounding': [], 'mesh_basis_rounding': [], 'failures': [], 'mouth_width': 'Original authored .033 halfwidth retained; no X displacement.', 'corner_curve': 'Original authored 1.512+.0065*q^2, minus WORLD .0014*smootherstep(q), with shared smooth height/outer-width fade; report actual native center/ends separately.'}

# Translate mesh and every key together; enumerate actual float32 relative differences.
def install(name, deltas):
    o = bpy.data.objects[name]
    snapshot = old[name]
    keys = o.data.shape_keys.key_blocks
    for i, d in enumerate(deltas):
        o.data.vertices[i].co = snapshot['mesh'][i] + d
        for k in keys:
            k.data[i].co = snapshot['keys'][k.name][i] + d
    o.data.update()
    for k in keys:
        for i, v in enumerate(k.data):
            prior = tuple((float(snapshot['keys'][k.name][i][j]) - float(snapshot['keys']['Basis'][i][j]) for j in range(3)))
            now = tuple((float(v.co[j]) - float(keys['Basis'].data[i].co[j]) for j in range(3)))
            if prior != now:
                report['relative_rounding'].append([name, k.name, i, prior, now])
    for i, v in enumerate(o.data.vertices):
        prior = tuple((float(snapshot['mesh'][i][j]) - float(snapshot['keys']['Basis'][i][j]) for j in range(3)))
        now = tuple((float(v.co[j]) - float(keys['Basis'].data[i].co[j]) for j in range(3)))
        if prior != now:
            report['mesh_basis_rounding'].append([name, i, prior, now])
    report['changes'][name] = {'vertices': len(deltas), 'changed': [i for i, d in enumerate(deltas) if d.length > 0], 'max_local_displacement': max((d.length for d in deltas))}
# Regularize deltas over existing edges, never the original shape or its identity vectors.
points = old[head.name]['world']
raw = [shared(p) for p in points]
neighbors = [[] for p in points]
for e in head.data.edges:
    a, b = e.vertices
    length = (points[a] - points[b]).length
    if length > 0:
        neighbors[a].append((b, 1 / length))
        neighbors[b].append((a, 1 / length))
smoothed = [d.copy() for d in raw]
for iteration in range(8):
    nxt = []
    for i, p in enumerate(points):
        w = weight(p)
        if not neighbors[i] or w == 0:
            nxt.append(Vector())
            continue
        total = sum((v for j, v in neighbors[i]))
        average = sum((smoothed[j] * v for j, v in neighbors[i]), Vector()) / total
        nxt.append((raw[i] * 0.35 + average * 0.65) * w)
    smoothed = nxt
report['regularization'] = {'iterations': 8, 'retained_raw_weight': 0.35, 'neighbor_weight': 0.65, 'edge_weight': 'inverse world edge length', 'boundary': 'C2 world support weight reapplied each pass; original upper/side/back remain exactly fixed'}
install(head.name, [quant_local(head, d) for d in smoothed])
new_head_tree = tree(head, [global_co(head, v.co) for v in head.data.shape_keys.key_blocks['Basis'].data])
# Refit both solidified lip surfaces to the actual smoothed head BVH.
for name, upper in [('Lips_Upper_soft', True), ('Lips_Lower_soft', False)]:
    o = bpy.data.objects[name]
    lip_tree = tree(o, old[name]['world'])
    deltas = []
    thickness = []
    params = []
    for i, p in enumerate(old[name]['world']):
        a = authored(p)
        q = abs(a.x) / 0.033
        full = max(0.0, 1 - q * q)
        seam = 1.512 + 0.0065 * q * q
        contour = 0.0047 * full + 0.0016 * math.exp(-((abs(a.x) - 0.011) / 0.006) ** 2) if upper else -0.006 * full
        f = (a.z - seam) / contour if abs(contour) > 1e-08 else 1.0
        u = max(0.0, min(1.0, f))
        corner = 1 - fade(0.7, 1.0, q)
        target = p + shared(p)
        ceiling = 0.00065 if upper else 0.00055
        limit = 0.18 * abs(contour) * SCALE
        amplitude = ceiling * limit / (ceiling + limit)
        target.z += (1 if upper else -1) * amplitude * math.sin(math.pi * u) ** 2 * corner
        old_front = front(lip_tree, p.x, p.z)
        back = max(0.0, float(p.y) - old_front)
        seam_depth = 0.00075 * (1 - fade(0, 1, u))
        belly = (0.00125 if upper else 0.00155) * math.sin(math.pi * u) ** 2
        protrusion = (seam_depth + belly) * corner
        target.y = front(new_head_tree, target.x, target.z) - protrusion + back * 0.55
        deltas.append(quant_local(o, target - p))
        thickness.append(back)
        params.append((f, protrusion))
    install(name, deltas)
    report['changes'][name]['old_front_to_back_depth_range'] = [min(thickness), max(thickness)]
    report['changes'][name]['new_front_protrusion_range'] = [min((p[1] for p in params)), max((p[1] for p in params))]
# Carry the thin native seam with the supported join; retain its radial thickness.
o = bpy.data.objects['Lips_Smile_seam']
deltas = []
assert len(old[o.name]['world']) % 8 == 0
rings = [list(range(i, i + 8)) for i in range(0, len(old[o.name]['world']), 8)]
center_ids = min(rings, key=lambda ids: abs(math.fsum((float(old[o.name]['world'][i].x) for i in ids)) / 8))
edge_set = {tuple(sorted(e.vertices)) for e in o.data.edges}
assert all((tuple(sorted((center_ids[i], center_ids[(i + 1) % 8]))) in edge_set for i in range(8))), ('native bevel ring topology', center_ids)
for p in old[o.name]['world']:
    a = authored(p)
    q = abs(a.x) / 0.033
    corner = 1 - fade(0.7, 1, q)
    target = p + shared(p)
    seam_z = 1.512 + 0.0065 * q * q
    seam_world_z = float(pivot.z + (seam_z - pivot.z) * SCALE)
    old_center_depth = front(old_head_tree, p.x, seam_world_z) - (0.0025 * max(0, 1 - q * q) + 0.0004) * SCALE
    radial = float(p.y) - old_center_depth
    target.y = front(new_head_tree, target.x, target.z) - 0.00078 * corner + radial
    deltas.append(quant_local(o, target - p))
install(o.name, deltas)
bpy.context.view_layer.update()
after = witness.objects()
for name, facts in before['objects'].items():
    for key, value in facts.items():
        if name in OWNED and key == 'geometry_sha256':
            continue
        if value != after['objects'][name][key]:
            report['failures'].append([name, key])
assert before['objects'].keys() == after['objects'].keys()
assert not report['failures'], report['failures']
# Independent exact protection outside the local face mask.
protected = {'upper_z_world_1_535': [], 'lateral_abs_x_world_074': []}
for i, p in enumerate(old[head.name]['world']):
    for group, condition in [('upper_z_world_1_535', p.z >= 1.535), ('lateral_abs_x_world_074', abs(p.x) >= 0.074)]:
        if condition:
            assert head.data.vertices[i].co == old[head.name]['mesh'][i]
            assert all((k.data[i].co == old[head.name]['keys'][k.name][i] for k in head.data.shape_keys.key_blocks))
            protected[group].append(i)
report['protected_head_vertices'] = protected

# Anchor measurement uses fsum affine coordinates; the finisher also checks native Vectors.
def affine(m, p):
    return [math.fsum((float(m[i][j]) * float(p[j]) for j in range(3))) + float(m[i][3]) for i in range(3)]

def center(points):
    return [math.fsum((p[j] for p in points)) / len(points) for j in range(3)]
seam = bpy.data.objects['Lips_Smile_seam']
hp = bpy.data.objects['Head']
inverse = hp.matrix_world.inverted()
old_center = center([affine(seam.matrix_world, old[seam.name]['keys']['Basis'][i]) for i in center_ids])
new_center = center([affine(seam.matrix_world, seam.data.shape_keys.key_blocks['Basis'].data[i].co) for i in center_ids])
old_local = affine(inverse, old_center)
new_local = affine(inverse, new_center)
delta = [b - a for a, b in zip(old_local, new_local)]
old_anchor = list(bpy.data.objects['Character']['mouth_anchor'])
godot_delta = [delta[0], delta[2], -delta[1]]
proposed = [float(a) + b for a, b in zip(old_anchor, godot_delta)]
anchor_report = {'mesh': seam.name, 'mesh_datablock': seam.data.name, 'native_basis_ring_ids': center_ids, 'selection': 'Eight-vertex native bevel rings, each contiguous ring confirmed by cyclic edges; select smallest absolute mean original world X. Same eight IDs before/after.', 'old_world_blender': old_center, 'new_world_blender': new_center, 'world_delta_blender': [b - a for a, b in zip(old_center, new_center)], 'old_head_local_blender': old_local, 'new_head_local_blender': new_local, 'head_local_delta_blender': delta, 'head_local_delta_godot': godot_delta, 'old_property': old_anchor, 'proposed_property_unrounded': proposed, 'proposed_property_round6': [round(v, 6) for v in proposed], 'property_changed': False, 'head_world_matrix': witness.matrix(hp.matrix_world), 'inverse_head_matrix': witness.matrix(inverse)}
sections = {'scope': 'Actual native Basis triangle intersections in Blender WORLD coordinates. No expression, export, renderer or anatomical guarantee.', 'before': {}, 'after': {}}

def cut(points, tris, x):
    result = []
    for ids in tris:
        vertices = [points[i] for i in ids]
        hits = []
        for a, b in zip(vertices, vertices[1:] + vertices[:1]):
            if a.x == x:
                hits.append(a.copy())
            if (a.x - x) * (b.x - x) < 0:
                hits.append(a + (b - a) * ((x - a.x) / (b.x - a.x)))
        unique = []
        for h in hits:
            if not any((h == v for v in unique)):
                unique.append(h)
        if len(unique) == 2 and max((h.z for h in unique)) >= 1.462 and (min((h.z for h in unique)) <= 1.54) and (min((h.y for h in unique)) < -0.055):
            result.append([list(v) for v in unique])
    return result
# Inspect existing and newly derived triangles; this is not a complete intersection test.
geometry_checks = {}
for name in OWNED:
    o = bpy.data.objects[name]
    prior = old[name]['world']
    current = [global_co(o, v.co) for v in o.data.shape_keys.key_blocks['Basis'].data]
    triangles = old[name]['triangles']
    for phase, points in [('before', prior), ('after', current)]:
        sections[phase][name] = {str(x): cut(points, triangles, x) for x in [0.0, 0.015, 0.03, 0.045]}
    collapsed = []
    opposed = []
    ratios = []
    for j, (a, b, c) in enumerate(triangles):
        n0 = (prior[b] - prior[a]).cross(prior[c] - prior[a])
        n1 = (current[b] - current[a]).cross(current[c] - current[a])
        if n0.length > 1e-12:
            ratios.append(n1.length / n0.length)
            if n1.length < 1e-12:
                collapsed.append(j)
            if n0.dot(n1) < 0:
                opposed.append(j)
    geometry_checks[name] = {'triangles': len(triangles), 'new_collapsed_from_nondegenerate': collapsed, 'normal_over90_degrees': opposed, 'area_ratio_range': [min(ratios), max(ratios)]}
report['geometry_checks'] = geometry_checks
for name in ['Lips_Upper_soft', 'Lips_Lower_soft']:
    o = bpy.data.objects[name]
    o.data.calc_loop_triangles()
    before_points = old[name]['world']
    after_points = [global_co(o, v.co) for v in o.data.shape_keys.key_blocks['Basis'].data]
    signs = []
    for t in o.data.loop_triangles:
        ids = list(t.vertices)
        a, b, c = [before_points[i] for i in ids]
        d, e, f = [after_points[i] for i in ids]
        n0 = (b - a).cross(c - a)
        n1 = (e - d).cross(f - d)
        if n0.y * n1.y < 0:
            signs.append({'native_ids': ids, 'old_XZ_area': float(n0.y), 'new_XZ_area': float(n1.y), 'old_unit_normal': list(n0.normalized()), 'new_unit_normal': list(n1.normalized())})
    report['geometry_checks'][name]['all_actual_derived_projected_sign_changes'] = signs
report['actual_center_profile'] = [{'height': z, 'before_depth': -front(old_head_tree, 0, z), 'after_depth': -front(new_head_tree, 0, z), 'target': target} for z, target in landmarks]
# Preserve the specific nearly horizontal closing-shell face diagnosis.
edge_ids = [27, 249, 612]
lower = bpy.data.objects['Lips_Lower_soft']
lower_old = old[lower.name]['world']
lower_new = [global_co(lower, v.co) for v in lower.data.shape_keys.key_blocks['Basis'].data]
lower_tree = tree(lower, lower_old)

def edge_facts(points):
    a, b, c = [points[i] for i in edge_ids]
    n = (b - a).cross(c - a)
    cent = (a + b + c) / 3
    return {'ids': edge_ids, 'world_points': [list(v) for v in [a, b, c]], 'unit_normal': list(n.normalized()), 'projected_XZ_area': float(n.y), 'area_double': float(n.length), 'centroid': list(cent)}
report['lower_closing_edge'] = {'production': edge_facts(lower_old), 'v4': edge_facts(lower_new), 'old_vertex_depths_behind_front': [float(lower_old[i].y) - front(lower_tree, lower_old[i].x, lower_old[i].z) for i in edge_ids]}
(out / 'author_report.json').write_text(json.dumps(report, indent=2) + '\n')
(out / 'object_facts.json').write_text(json.dumps({'before': before['objects'], 'after': after['objects']}, indent=2) + '\n')
(out / 'native_sections.json').write_text(json.dumps(sections, indent=2) + '\n')
(out / 'mouth_anchor.json').write_text(json.dumps(anchor_report, indent=2) + '\n')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'art/characters.blend'))
assert witness.sha(source) == PIN
print('LOWER_FACE_V4_AUTHORED', json.dumps({'changed': {n: len(d['changed']) for n, d in report['changes'].items()}, 'geometry': geometry_checks, 'anchor': anchor_report['proposed_property_round6'], 'relative_rounding': len(report['relative_rounding']), 'mesh_basis_rounding': len(report['mesh_basis_rounding'])}))
