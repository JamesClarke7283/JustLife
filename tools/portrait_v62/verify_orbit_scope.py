"""Verify exact non-facial preservation and final orbital authoring contracts."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

import bpy

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])


def snapshot():
    result = {}
    for obj in bpy.data.objects:
        meta = {'type': obj.type, 'parent': obj.parent.name if obj.parent else None,
                'matrix': [float(v) for row in obj.matrix_world for v in row],
                'modifiers': [(m.name, m.type) for m in obj.modifiers]}
        if obj.type == 'MESH':
            digest = hashlib.sha256()
            for v in obj.data.vertices:
                digest.update(struct.pack('<3f', *v.co))
                for g in v.groups:
                    digest.update(struct.pack('<If', g.group, g.weight))
            for p in obj.data.polygons:
                digest.update(struct.pack('<' + str(len(p.vertices)) + 'I', *p.vertices))
            meta['keys'] = []
            if obj.data.shape_keys:
                for key in obj.data.shape_keys.key_blocks:
                    meta['keys'].append(key.name)
                    for v in key.data:
                        digest.update(struct.pack('<3f', *v.co))
            meta['geometry_and_weights'] = digest.hexdigest()
            meta['groups'] = [g.name for g in obj.vertex_groups]
            meta['materials'] = [m.name if m else None for m in obj.data.materials]
            meta['material_faces'] = [sum(p.material_index == i for p in obj.data.polygons)
                                      for i in range(len(obj.data.materials))]
        if obj.type == 'ARMATURE':
            meta['bones'] = [(b.name, list(b.head_local), list(b.tail_local), b.parent.name if b.parent else None)
                             for b in obj.data.bones]
        result[obj.name] = meta
    return result, list(bpy.data.objects['Character']['mouth_anchor'])


bpy.ops.wm.open_mainfile(filepath=str(args.baseline.resolve()))
before, before_anchor = snapshot()
bpy.ops.wm.open_mainfile(filepath=str(args.candidate.resolve()))
after, after_anchor = snapshot()
assert before_anchor == after_anchor, 'mouth anchor changed'
removed = set(before) - set(after)
added = set(after) - set(before)
assert removed <= {'Skin_Upper_lid_-1', 'Skin_Upper_lid_1'}, removed
assert added == {'Lash_Upper_-1', 'Lash_Upper_1'}, added
protected, changed = [], []
for name in set(before) & set(after):
    a, b = before[name], after[name]
    if a == b:
        protected.append(name)
        continue
    changed.append(name)
    if name.startswith('Hair_Brow'):
        assert a['geometry_and_weights'] == b['geometry_and_weights']
        assert b['materials'] == ['Brows']
        assert {k: v for k, v in a.items() if k != 'materials'} == {k: v for k, v in b.items() if k != 'materials'}
    else:
        assert name == 'Skin_Head_continuous' or name.startswith('Eyes_'), ('unowned change', name)
        for key in ('type', 'parent', 'matrix', 'modifiers', 'groups', 'materials'):
            if name == 'Skin_Head_continuous' and key == 'materials':
                assert [m for m in a[key] if m] == b[key]
                assert all(a['material_faces'][i] == 0 for i, m in enumerate(a[key]) if m is None), 'Used empty material slot removed'
                continue
            assert a[key] == b[key], (name, key, a[key], b[key])
        assert set(a['keys']) <= set(b['keys']), (name, 'lost morph')

for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.data.shape_keys:
        continue
    keys = obj.data.shape_keys.key_blocks
    assert all(v.co == keys['Basis'].data[i].co for i, v in enumerate(obj.data.vertices)), ('Basis mismatch', obj.name)
    assert all(key.value == 0 for key in keys), ('active morph', obj.name)

uv_checks = []
for name in ('Skin_Head_continuous', 'Lash_Upper_-1', 'Lash_Upper_1'):
    obj = bpy.data.objects[name]
    assert obj.data.uv_layers.active is not None, ('UV missing', name)
    unique = {tuple(v.uv) for v in obj.data.uv_layers.active.data}
    assert len(unique) > 4, ('collapsed UVs', name)
    assert all(poly.use_smooth for poly in obj.data.polygons), ('flat face', name)
    uv_checks.append({'object': name, 'unique_uvs': len(unique), 'smooth_faces': len(obj.data.polygons)})

report = {'baseline': str(args.baseline), 'candidate': str(args.candidate),
          'candidate_sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
          'protected_object_count': len(protected), 'changed_objects': sorted(changed),
          'removed_objects': sorted(removed), 'added_objects': sorted(added),
          'rig_hierarchy_mouth_anchor_preserved': True, 'basis_exact_and_morph_values_zero': True,
          'uv_coverage': uv_checks}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('ORBIT_SCOPE_PASS', json.dumps(report))
