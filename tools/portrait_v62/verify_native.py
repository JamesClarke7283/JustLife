"""Verify portrait candidate ownership, Basis parity and coherent iris morphs."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
OWNED = {prefix + suffix for prefix in ('Eyes_Iris', 'Eyes_Iris_edge', 'Eyes_Pupil',
                                       'Eyes_Catchlight', 'Hair_Brow') for suffix in ('', '.001')}


def facts():
    output = {}
    for o in bpy.data.objects:
        meta = {'type': o.type, 'parent': o.parent.name if o.parent else None,
                'matrix': [v for row in o.matrix_world for v in row],
                'modifiers': [(m.name, m.type) for m in o.modifiers]}
        if o.type == 'MESH':
            digest = hashlib.sha256()
            for v in o.data.vertices:
                digest.update(struct.pack('<3f', *v.co))
            for p in o.data.polygons:
                digest.update(struct.pack('<' + str(len(p.vertices)) + 'I', *p.vertices))
            if o.data.shape_keys:
                meta['keys'] = list(o.data.shape_keys.key_blocks.keys())
                for k in o.data.shape_keys.key_blocks:
                    for v in k.data:
                        digest.update(struct.pack('<3f', *v.co))
            meta['geometry'] = digest.hexdigest()
            meta['vertices'] = len(o.data.vertices)
            meta['polygons'] = len(o.data.polygons)
            meta['materials'] = [m.name if m else None for m in o.data.materials]
        if o.type == 'ARMATURE':
            meta['bones'] = [(b.name, tuple(b.head_local), tuple(b.tail_local),
                              b.parent.name if b.parent else None) for b in o.data.bones]
        output[o.name] = meta
    return output


bpy.ops.wm.open_mainfile(filepath=str(args.baseline.resolve()))
baseline = facts()
bpy.ops.wm.open_mainfile(filepath=str(args.candidate.resolve()))
candidate = facts()
assert set(baseline) == set(candidate)
changed = []
for name, before in baseline.items():
    after = candidate[name]
    if before == after:
        continue
    assert name in OWNED, ('Unowned object changed', name)
    changed.append(name)
    assert {k: v for k, v in before.items() if k != 'geometry'} == {k: v for k, v in after.items() if k != 'geometry'}, name
assert set(changed) == OWNED
eye_checks = []
for name in sorted(OWNED):
    o = bpy.data.objects[name]
    basis = o.data.shape_keys.key_blocks['Basis']
    assert all(v.co == basis.data[i].co for i, v in enumerate(o.data.vertices)), name
    if not name.startswith(('Eyes_Iris', 'Eyes_Pupil')):
        continue
    widths, heights = [], []
    for key in o.data.shape_keys.key_blocks:
        ps = [o.matrix_world @ v.co for v in key.data]
        widths.append(max(p.x for p in ps) - min(p.x for p in ps))
        heights.append(max(p.z for p in ps) - min(p.z for p in ps))
        assert all(all(abs(c) < 3 for c in p) for p in ps)
    # Identity controls translate a rigid circular iris without distorting it.
    assert max(widths) - min(widths) < 1e-6, (name, widths)
    assert max(heights) - min(heights) < 1e-6, (name, heights)
    assert abs(widths[0] - heights[0]) < 1e-6, (name, widths, heights)
    eye_checks.append({'mesh': name, 'morph_count': len(widths), 'diameter': widths[0]})

report = {'baseline': str(args.baseline), 'candidate': str(args.candidate),
          'changed_objects': sorted(changed), 'protected_objects': len(candidate) - len(changed),
          'rig_and_topology_preserved': True, 'mesh_basis_exact': True, 'round_iris_all_morphs': eye_checks}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('PORTRAIT_NATIVE_PASS', json.dumps(report))
