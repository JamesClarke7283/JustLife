"""Author candidate-only signed, coupled proportion controls from native anchors."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import CONTACT_PREFIXES, Geometry, NEW, OLD, mouth_offsets, points

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve()
assert not args.output.exists(), 'Use a fresh candidate filename; never overwrite a reviewed source.'
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
g = Geometry()
for orbit in g.orbits:
    for name in NEW:
        maximum = max(g.field(name, p).length for p in orbit['points'])
        assert maximum < 1e-7, ('Field moves welded eye aperture', orbit['side'], name, maximum)
anchor_before = list(g.root['mouth_anchor'])
report = {'source': str(args.source.resolve()),
          'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
          'output': str(args.output.resolve()), 'anchors': g.report(), 'objects': {}}
for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.name.startswith(CONTACT_PREFIXES):
        continue
    base = points(obj)
    inverse = obj.matrix_world.to_3x3().inverted()
    for name in NEW:
        delta = [g.field(name, p) for p in base]
        maximum = max(v.length for v in delta)
        if maximum < 1e-7:
            continue
        if not obj.data.shape_keys:
            obj.shape_key_add(name='Basis', from_mix=False)
        assert name not in obj.data.shape_keys.key_blocks, (obj.name, name)
        key = obj.shape_key_add(name=name, from_mix=False)
        key.slider_min, key.slider_max, key.value = -1., 1., 0.
        basis = obj.data.shape_keys.key_blocks['Basis']
        for i, vertex in enumerate(key.data):
            vertex.co = basis.data[i].co + inverse @ delta[i]
        report['objects'].setdefault(obj.name, {})[name] = {
            'affected_vertices': sum(v.length > 1e-7 for v in delta),
            'max_displacement_m': maximum}
g.root['identity_morphs'] = ','.join(OLD + NEW)
g.root['mouth_identity_offsets'] = mouth_offsets(g)
assert list(g.root['mouth_anchor']) == anchor_before
report['mouth_anchor_unchanged'] = anchor_before
report['mouth_identity_offsets'] = mouth_offsets(g)
report['neutral_geometry_policy'] = 'Preserved exactly; all new keys are relative to existing Basis, neutral zero.'
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
report['output_sha256'] = hashlib.sha256(args.output.read_bytes()).hexdigest()
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('IDENTITY_SHAPE_AUTHORED', json.dumps(report))
