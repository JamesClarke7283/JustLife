"""Verify neutral preservation and signed facial-identity deformation bounds."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

NEW = ('Nose_Length', 'Lip_Fullness', 'Brow_Arch', 'Chin_Length')
OLD = ('Face_Round', 'Jaw_Strong', 'Nose_Wide', 'Eye_Spacing')
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])


def digest(points):
    h = hashlib.sha256()
    for p in points:
        h.update(struct.pack('<3f', *p.co))
    return h.hexdigest()


def facts():
    result = {}
    for obj in bpy.data.objects:
        f = {'type': obj.type, 'parent': obj.parent.name if obj.parent else None,
             'matrix': tuple(c for row in obj.matrix_world for c in row),
             'modifiers': [(m.name, m.type) for m in obj.modifiers]}
        if obj.type == 'MESH':
            f['mesh'] = digest(obj.data.vertices)
            f['topology'] = hashlib.sha256(str([tuple(p.vertices) for p in obj.data.polygons]).encode()).hexdigest()
            f['keys'] = {k.name: digest(k.data) for k in obj.data.shape_keys.key_blocks if k.name not in NEW} if obj.data.shape_keys else {}
            f['materials'] = [m.name if m else None for m in obj.data.materials]
        if obj.type == 'ARMATURE':
            f['bones'] = [(b.name, tuple(b.head_local), tuple(b.tail_local)) for b in obj.data.bones]
        result[obj.name] = f
    return result


bpy.ops.wm.open_mainfile(filepath=str(args.baseline.resolve()))
before = facts()
bpy.ops.wm.open_mainfile(filepath=str(args.candidate.resolve()))
after = facts()
added = set(after) - set(before)
assert added <= {'Hair_Brow_L', 'Hair_Brow_R'}, added
assert not set(before) - set(after)
for name, source in before.items():
    candidate = after[name]
    # A previously unkeyed mesh acquires an identical Basis before new keys.
    if source.get('keys') == {} and candidate.get('keys'):
        assert candidate['keys'] == {'Basis': source['mesh']}, name
        candidate = dict(candidate, keys={})
    assert source == candidate, ('Existing source changed', name)

root = bpy.data.objects['Character']
head = bpy.data.objects['Skin_Head_continuous']
scale = float(root.get('height_m', 1.76)) / 1.76
found = set()
for obj in bpy.data.objects:
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            if key.name in NEW:
                assert key.slider_min == -1 and key.slider_max == 1
                assert key.value == 0
                assert any((p.co - obj.data.shape_keys.key_blocks['Basis'].data[i].co).length > 1e-7 for i, p in enumerate(key.data))
                found.add(key.name)
assert found == set(NEW), found


def posed(obj, values):
    keys = obj.data.shape_keys.key_blocks
    basis = [v.co.copy() for v in keys['Basis'].data]
    for name, value in values.items():
        if name not in keys or value == 0:
            continue
        for i, v in enumerate(keys[name].data):
            basis[i] += (v.co - keys['Basis'].data[i].co) * value
    return [obj.matrix_world @ p for p in basis]


head.data.calc_loop_triangles()
triangles = [tuple(t.vertices) for t in head.data.loop_triangles]
cases = [('all_positive', dict.fromkeys(NEW, 1.0)), ('all_negative', dict.fromkeys(NEW, -1.0)),
         ('mixed', dict(zip(NEW, [1.0, -1.0, -1.0, 1.0]))),
         ('identity_max_positive', {**dict.fromkeys(OLD, 1.0), **dict.fromkeys(NEW, 1.0)}),
         ('identity_max_negative', {**dict.fromkeys(OLD, 1.0), **dict.fromkeys(NEW, -1.0)})]
for key in NEW:
    for sign in (-1, 1):
        cases.append((key + ('_min' if sign < 0 else '_max'), {key: float(sign)}))
checks = []
for label, values in cases:
    baseline_values = {k: v for k, v in values.items() if k in OLD}
    base = posed(head, baseline_values)
    ps = posed(head, values)
    flips = 0
    min_area = 1.0
    max_move = max((p - q).length for p, q in zip(ps, base))
    for ids in triangles:
        a, b, c = (base[i] for i in ids)
        p, q, r = (ps[i] for i in ids)
        normal = (b - a).cross(c - a)
        target = (q - p).cross(r - p)
        if normal.length < 1e-10:
            continue
        min_area = min(min_area, target.length / normal.length)
        flips += int(normal.dot(target) < 0)
    assert flips == 0, (label, 'triangle orientation reversals', flips)
    assert min_area > .05, (label, 'collapsed triangles', min_area)
    tree = BVHTree.FromPolygons(ps, triangles, all_triangles=True)
    buried = []
    max_brow_depth = -1.0
    for brow in (o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Hair_Brow')):
        for p in posed(brow, values):
            hit, _, _, _ = tree.ray_cast(Vector((p.x, -2, p.z)), Vector((0, 1, 0)), 4)
            if hit is None:
                continue
            depth = p.y - hit.y
            max_brow_depth = max(depth, max_brow_depth)
            if depth > .00025:
                buried.append(depth)
    checks.append({'case': label, 'head_orientation_reversals': flips, 'minimum_triangle_area_ratio': min_area,
                   'max_head_displacement': max_move, 'brow_vertices_over_0_25mm_inside_skin': len(buried),
                   'maximum_brow_skin_depth': max_brow_depth})
    assert not buried, (label, 'brow inside forehead', len(buried), max(buried))
report = {'baseline': str(args.baseline), 'candidate': str(args.candidate),
          'neutral_and_existing_morphs_exact': True, 'protected_existing_objects': len(before),
          'added_objects': sorted(added), 'new_morphs': sorted(found), 'signed_extreme_checks': checks}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('PORTRAIT_IDENTITY_PASS', json.dumps(report))
