"""Author the reviewed original casual-shirt/shared-trouser field."""
from pathlib import Path
import argparse, json, math, sys
sys.dont_write_bytecode = True
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P = Path(__file__).resolve().parent
sys.path.insert(0, str(P)); sys.path.insert(0, str(P.parent/'adult_eyes'))
import source_facts as w
from field import shirt_delta, trouser_delta

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
SOURCE = args.source.resolve()
PIN = '2a181222579a14efebf1cbe4bc99ea7719cbe3d53152e7127192c9f7b1820933'
OUT = args.output.resolve()
SHIRT = 'Outfit_Casual_Shirt'
PANTS = 'Bottom_Continuous_trousers'
TRIMS = ['Outfit_Casual_Top_Hem', 'Outfit_Casual_Top_Fold', 'Outfit_Casual_Top_Fold.001',
         'Outfit_Casual_Top_Sleeve_cuff', 'Outfit_Casual_Top_Sleeve_cuff.001']
OWNED = [SHIRT]+TRIMS+[PANTS]
assert w.sha(SOURCE) == PIN and not OUT.exists()
(OUT/'art').mkdir(parents=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE)); bpy.context.view_layer.update()
w.OWNED = set(OWNED)
before = w.objects()['objects']


def material_facts():
    return {m.name: {'rna': w.scalar_rna(m), 'props': w.serial(dict(m.items())),
        'nodes': {n.name: {'type': n.bl_idname, 'rna': w.scalar_rna(n),
            'inputs': {s.name: w.serial(s.default_value) for s in n.inputs if hasattr(s, 'default_value')}}
            for n in m.node_tree.nodes} if m.node_tree else {},
        'links': [[l.from_node.name, l.from_socket.name, l.to_node.name, l.to_socket.name]
                  for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}


mat_before = w.digest(material_facts())
old = {}
for name in OWNED:
    obj = bpy.data.objects[name]; obj.data.calc_loop_triangles()
    old[name] = {'mesh': [v.co.copy() for v in obj.data.vertices],
        'keys': {k.name: [v.co.copy() for v in k.data] for k in obj.data.shape_keys.key_blocks} if obj.data.shape_keys else {},
        'polygons': [list(p.vertices) for p in obj.data.polygons],
        'triangles': [list(t.vertices) for t in obj.data.loop_triangles]}
assert len(old[SHIRT]['mesh']) == 6002 and not old[SHIRT]['keys']
assert set(old[PANTS]['keys']) == {'Basis', 'Sit'}


def world(name, values=None):
    obj = bpy.data.objects[name]
    if values is None:
        values = ([v.co for v in obj.data.shape_keys.key_blocks['Basis'].data]
                  if obj.data.shape_keys else [v.co for v in obj.data.vertices])
    return [obj.matrix_world@v for v in values]


def tree(name, ps):
    return BVHTree.FromPolygons(ps, old[name]['polygons'])


report = {'source_sha256': PIN, 'owned_meshes': OWNED,
    'scope': 'Seven mesh coordinates only. Casual shoulder/cap/hem and its moved folds/cuffs; shared trouser leg drape below .850m. Head, body skin, rig/hinges, hand/foot geometry, neckline/placket/buttons, trouser upper yoke/waist/pockets/cuffs, other outfits and materials protected.',
    'coordinate_system': 'Native world metres; body has no adult head .91 coordinate inversion.',
    'relative_rounding': [], 'mesh_basis_rounding': [], 'changes': {}, 'geometry': {},
    'arm_clearance': [], 'hem_over_trousers': [], 'fold_attachment': {},
    'failures': [], 'limits': 'Neutral coordinate/clearance checks do not qualify arm reach, walking, skinned Sit, LOD, other-outfit composition or visual style.'}
old_world = {n: world(n, old[n]['keys'].get('Basis', old[n]['mesh'])) for n in OWNED}
old_trees = {n: tree(n, old_world[n]) for n in [SHIRT, PANTS]}


def local_delta(obj, p):
    raw = trouser_delta(p) if obj.name == PANTS else shirt_delta(p)
    v = obj.matrix_world.to_3x3().inverted()@Vector(raw)
    return Vector(tuple(round(float(a)/(2**-22))*(2**-22) for a in v))


for name in OWNED:
    obj = bpy.data.objects[name]; snap = old[name]
    basis = snap['keys'].get('Basis', snap['mesh'])
    deltas = [local_delta(obj, p) for p in old_world[name]]
    for i, delta in enumerate(deltas):
        obj.data.vertices[i].co = snap['mesh'][i]+delta
        if obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                key.data[i].co = snap['keys'][key.name][i]+delta
        if name == PANTS:
            assert delta.z == 0
            if old_world[name][i].z >= .850 or old_world[name][i].z <= .145:
                assert delta.length == 0, ('fixed trouser yoke/crotch/ankle edge', i)
        elif old_world[name][i].z >= 1.402:
            assert delta.length == 0, ('fixed neckline', name, i)
    obj.data.update()
    if obj.data.shape_keys:
        keys = obj.data.shape_keys.key_blocks
        for key in keys:
            for i, point in enumerate(key.data):
                previous = [float(snap['keys'][key.name][i][j])-float(basis[i][j]) for j in range(3)]
                current = [float(point.co[j])-float(keys['Basis'].data[i].co[j]) for j in range(3)]
                if previous != current:
                    report['relative_rounding'].append([name, key.name, i, previous, current])
                if deltas[i].length == 0: assert point.co == snap['keys'][key.name][i]
        for i, point in enumerate(obj.data.vertices):
            previous = [float(snap['mesh'][i][j])-float(basis[i][j]) for j in range(3)]
            current = [float(point.co[j])-float(keys['Basis'].data[i].co[j]) for j in range(3)]
            if previous != current:
                report['mesh_basis_rounding'].append([name, i, previous, current])
    report['changes'][name] = {'ids': [i for i, d in enumerate(deltas) if d.length],
        'max_local_displacement': max(d.length for d in deltas),
        'world_bounds_before': [[min(p[j] for p in old_world[name]) for j in range(3)],
                                [max(p[j] for p in old_world[name]) for j in range(3)]]}

bpy.context.view_layer.update()
new_world = {n: world(n) for n in OWNED}
new_trees = {n: tree(n, new_world[n]) for n in [SHIRT, PANTS]}

# The fixed collar/placket/buttons and shared trouser attachments are outside the
# quantized field. Verify the region assumption on their actual current data.
for name, facts in before.items():
    if name in OWNED or facts['type'] not in ['MESH', 'CURVE']: continue
    field = shirt_delta if name.startswith('Outfit_Casual_') else trouser_delta if name.startswith('Bottom_') else None
    if field is None: continue
    obj = bpy.data.objects[name]
    if obj.type == 'MESH':
        samples = [obj.matrix_world@v.co for v in obj.data.vertices]
    else:
        samples = [obj.matrix_world@p.co for spline in obj.data.splines for p in spline.bezier_points]
        samples += [obj.matrix_world@Vector(p.co[:3]) for spline in obj.data.splines for p in spline.points]
    for p in samples:
        assert all(round(float(v)/(2**-22)) == 0 for v in field(p)), ('unowned attachment requires movement', name, list(p))

# Actual neutral arm skin against old/new cloth at the same world height.
# Existing signed gaps remain recorded. A new crossing from previously covered
# skin is a failure; no body edit or increased clearance tolerance repairs it.
for arm_name, side in [('Skin_Arm_continuous_L', -1), ('Skin_Arm_continuous_R', 1)]:
    obj = bpy.data.objects[arm_name]; obj.data.calc_loop_triangles()
    ps = world(arm_name)
    samples = [(str(i), p) for i, p in enumerate(ps)]
    samples += [('triangle '+str(i), sum((ps[j] for j in t.vertices), Vector())/3)
                for i, t in enumerate(obj.data.loop_triangles)]
    for index, p in samples:
        if not (1.175 <= p.z <= 1.340): continue
        amount = (1.361-p.z)/(1.361-1.087)
        origin = Vector((side*(.180+.064*amount), .007*amount, p.z))
        direction = Vector((p.x-origin.x, p.y-origin.y, 0))
        radius = direction.length
        if radius == 0: continue
        direction.normalize()
        hits = [t.ray_cast(origin, direction, .6)[0] for t in [old_trees[SHIRT], new_trees[SHIRT]]]
        gaps = [None if h is None else (h-origin).length-radius for h in hits]
        report['arm_clearance'].append([arm_name, index, list(p), gaps])
        if gaps[0] is not None and gaps[0] >= 0 and (gaps[1] is None or gaps[1] < 0):
            report['failures'].append(['new uncovered arm sample', arm_name, index, gaps])

# Test the actual hem binding against the shared trouser outer surface, not the
# shirt's hidden closed bottom cap. The waist itself is an exact protected region.
name = 'Outfit_Casual_Top_Hem'
for i, (a, b) in enumerate(zip(old_world[name], new_world[name])):
    gaps = []
    for point, bvh in [(a, old_trees[PANTS]), (b, new_trees[PANTS])]:
        origin = Vector((0, .008, point.z)); direction = point-origin
        direction.z = 0; radius = direction.length
        direction.normalize()
        hit = bvh.ray_cast(origin, direction, .5)[0]
        gaps.append(None if hit is None else radius-(hit-origin).length)
    report['hem_over_trousers'].append([i, list(a), list(b), gaps])
    if (gaps[0] is None or gaps[0] >= 0) and (gaps[1] is None or gaps[1] < 0):
        report['failures'].append(['new hem/trouser crossing', i, gaps])

for name in ['Outfit_Casual_Top_Fold', 'Outfit_Casual_Top_Fold.001']:
    rows = []
    for i, (a, b) in enumerate(zip(old_world[name], new_world[name])):
        gaps = []
        for point, bvh in [(a, old_trees[SHIRT]), (b, new_trees[SHIRT])]:
            hit = bvh.ray_cast(Vector((point.x, -1, point.z)), Vector((0, 1, 0)), 2)[0]
            gaps.append(None if hit is None else float(hit.y-point.y))
        rows.append([i, list(a), list(b), gaps])
        if gaps[0] is not None and (gaps[1] is None or gaps[1]-gaps[0] > .001 or (gaps[0] >= 0 and gaps[1] < -.001)):
            report['failures'].append(['fold support changes by more than declared 1mm margin', name, i, gaps])
    report['fold_attachment'][name] = rows

# Native triangle diagnostics use corresponding original diagonals as well as
# actual new triangulation. Sit here means the corrective coordinate shape, not
# the armature-bent seated pose; a real seated gate belongs after a visual win.
for name in OWNED:
    obj = bpy.data.objects[name]; obj.data.calc_loop_triangles()
    new_tris = [list(t.vertices) for t in obj.data.loop_triangles]
    poses = ['Basis', 'Sit'] if name == PANTS else ['Mesh']
    records = {}
    for pose in poses:
        prior_values = old[name]['keys'][pose] if pose != 'Mesh' else old[name]['mesh']
        values = [v.co for v in obj.data.shape_keys.key_blocks[pose].data] if pose != 'Mesh' else [v.co for v in obj.data.vertices]
        a, b = world(name, prior_values), world(name, values)
        modes = {}
        for label, triangles in [('original_diagonals', old[name]['triangles']), ('new_diagonals', new_tris)]:
            turns, collapsed = [], []
            for ids in triangles:
                p, q, r = [a[i] for i in ids]; u, v, z = [b[i] for i in ids]
                n0, n1 = (q-p).cross(r-p), (v-u).cross(z-u)
                if n0.dot(n1) < 0:
                    turns.append([ids, [list(p), list(q), list(r)], [list(u), list(v), list(z)], n0.length*.5, n1.length*.5])
                if n0.length > 1e-12 and n1.length < 1e-12: collapsed.append(ids)
            modes[label] = {'normal_turn_over90': turns, 'new_collapsed': collapsed}
            if collapsed: report['failures'].append(['new collapsed triangles', name, pose, label, collapsed])
        records[pose] = modes
    report['geometry'][name] = records

after = w.objects()['objects']
assert before.keys() == after.keys() and w.digest(material_facts()) == mat_before
for name, facts in before.items():
    for key, value in facts.items():
        if name in OWNED and key == 'geometry_sha256': continue
        if value != after[name][key]: report['failures'].append(['protected fact', name, key])
(OUT/'object_facts.json').write_text(json.dumps({'before': before, 'after': after}, indent=2)+'\n')
(OUT/'author_report.json').write_text(json.dumps(report, indent=2)+'\n')
assert not report['failures'], report['failures'][:5]
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'art/characters.blend'))
assert w.sha(SOURCE) == PIN
print('CASUAL_DRAPE_AUTHORED', len(OWNED), 'owned meshes; protected facts exact; neutral samples only, visual and posed gates pending')
