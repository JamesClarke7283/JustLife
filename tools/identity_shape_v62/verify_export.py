"""Read-only GLB contract check for the candidate's controls and anchor extras."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--glb', type=Path, required=True)
ap.add_argument('--author-report', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args()
raw = args.glb.read_bytes()
magic, version, length = struct.unpack_from('<4sII', raw)
assert (magic, version, length) == (b'glTF', 2, len(raw))
size, kind = struct.unpack_from('<II', raw, 12)
assert kind == 0x4E4F534A
data = json.loads(raw[20:20 + size])
authored = json.loads(args.author_report.read_text())
root = next(n for n in data['nodes'] if n['name'] == 'Character')
extras = root['extras']
assert extras['mouth_anchor'] == authored['mouth_anchor_unchanged']
assert extras['mouth_identity_offsets'] == authored['mouth_identity_offsets']
new = {'Face_Length', 'Mouth_Width', 'Nose_Bridge'}
head = next(n for n in data['nodes'] if n['name'] == 'Skin_Head_continuous')
head_mesh = data['meshes'][head['mesh']]
head_targets = head_mesh['extras']['targetNames']
assert new <= set(head_targets)
assert all(value == 0 for value in head_mesh.get('weights', []))
assert len(extras['mouth_identity_offsets']) == 11
assert len(data['skins']) > 0
ocular = []
for node in data['nodes']:
    if 'mesh' not in node:
        continue
    mesh = data['meshes'][node['mesh']]
    targets = mesh.get('extras', {}).get('targetNames', [])
    assert all(v == 0 for v in mesh.get('weights', [])), node.get('name')
    if node.get('name', '').startswith(('Eyes_', 'Skin_Upper_lid', 'Hair_Brow')):
        assert not new.intersection(targets), ('Unexpected ocular deformation', node['name'])
        ocular.append(node['name'])
report = {'glb': str(args.glb.resolve()), 'sha256': hashlib.sha256(raw).hexdigest(),
          'bytes': len(raw), 'head_morphs': head_targets,
          'mouth_anchor_exact': True, 'eleven_measured_offsets_exact': True,
          'neutral_morph_weights_zero': True, 'ocular_meshes_without_new_deformations': ocular,
          'skins': len(data['skins']), 'passed': True}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('IDENTITY_SHAPE_EXPORT_PASS', json.dumps(report))
