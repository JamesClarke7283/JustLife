"""Add a signed canthal-tilt control with coupled lids, lashes and optical layers.

Corrective targets preserve the same orbital affine transform when old identity
keys, Blink or Smile are active. Runtime weight is eye_tilt * source_weight.
No neutral geometry, pre-existing key, UV, material or rig is changed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import KEY, PREFIX, OWNED, OrbitalField, array, frozen_digest, local, world

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--source-sha256', required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
p.add_argument('--degrees', type=float, default=10.)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert a.source.resolve() != a.output.resolve() and not a.output.exists()
assert hashlib.sha256(a.source.read_bytes()).hexdigest() == a.source_sha256
assert 0 < a.degrees <= 15
bpy.ops.wm.open_mainfile(filepath=str(a.source.resolve()))
bpy.context.view_layer.update()
before = {o.name: frozen_digest(o) for o in bpy.data.objects}
field = OrbitalField(a.degrees)
owned, corrections = {}, set()
for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.name.startswith(OWNED):
        continue
    assert obj.data.users == 1
    basis = local(obj).astype(np.float64)
    wp = world(obj, basis)
    params = field.parameters(obj, wp)
    neutral_delta = field.linear(wp - params[0], params)
    if np.max(np.linalg.norm(neutral_delta, axis=1)) < 1e-7:
        continue
    assert obj.data.shape_keys, ('Expected retained relative-key Basis', obj.name)
    old = {key.name: array(key.data).astype(np.float64) for key in obj.data.shape_keys.key_blocks}
    assert KEY not in old and not any(name.startswith(PREFIX) for name in old)
    matrix = np.asarray(obj.matrix_world, dtype=np.float64)[:3, :3]
    inverse = np.linalg.inv(matrix)
    rows = {}
    def add(name, delta):
        key = obj.shape_key_add(name=name, from_mix=False)
        key.slider_min, key.slider_max, key.value = -1., 1., 0.
        result = basis + delta @ inverse.T
        key.data.foreach_set('co', result.astype(np.float32).reshape(-1))
        rows[name] = {'vertices': int(np.sum(np.linalg.norm(delta, axis=1) > 1e-7)),
                      'max_displacement_m': float(np.max(np.linalg.norm(delta, axis=1)))}
    add(KEY, neutral_delta)
    for name, target in old.items():
        if name == 'Basis':
            continue
        delta = field.linear((target - basis) @ matrix.T, params)
        if np.max(np.linalg.norm(delta, axis=1)) <= 1e-7:
            continue
        add(PREFIX + name, delta)
        corrections.add(name)
    owned[obj.name] = rows
after = {o.name: frozen_digest(o) for o in bpy.data.objects}
assert before == after, 'Old neutral, geometry, keys or other protected state changed'
root = bpy.data.objects['Character']
identity = str(root['identity_morphs']).split(',')
assert KEY not in identity
root['identity_morphs'] = ','.join(identity + [KEY])
offsets = root['mouth_identity_offsets'].to_dict()
offsets[KEY.lower()] = [0., 0., 0.]
root['mouth_identity_offsets'] = offsets
root['orbital_correctives'] = {PREFIX + name: [KEY.lower(), name.lower()] for name in sorted(corrections)}
a.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(a.output.resolve()))
report = {'source': str(a.source.resolve()), 'source_sha256': a.source_sha256,
          'output': str(a.output.resolve()), 'output_sha256': hashlib.sha256(a.output.read_bytes()).hexdigest(),
          'degrees': a.degrees, 'scale': field.scale, 'eye_centers': [x.tolist() for x in field.centers],
          'preserved_object_count': len(before), 'old_state_exact': before == after,
          'owned': owned, 'corrective_sources': sorted(corrections),
          'corrective_weight_contract': 'eye_tilt * source_weight; including Blink and Smile',
          'production_promoted': False}
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('EYE_TILT_AUTHORED', json.dumps(report))
