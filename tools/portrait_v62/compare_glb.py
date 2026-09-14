"""Compare resolved GLB primitive data independently of buffer/accessor layout."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'child_bob_v36'))
from decoded_gltf import decoded_document

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('baseline', type=Path)
ap.add_argument('candidate', type=Path)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args()
a, b = decoded_document(args.baseline), decoded_document(args.candidate)
changes = []


def compare_accessor(label, ia, ib, indices_a=None, indices_b=None):
    left, right = a['accessors'][ia], b['accessors'][ib]
    va, vb = left['decoded_values'], right['decoded_values']
    if indices_a is not None:
        va = [va[i] for i in indices_a]
        vb = [vb[i] for i in indices_b]
    assert left['componentType'] == right['componentType'] and left['type'] == right['type'], label
    assert len(va) == len(vb), (label, len(va), len(vb))
    if va != vb:
        changed = sum(x != y for x, y in zip(va, vb))
        maximum = max(abs(v - w) for x, y in zip(va, vb) for v, w in zip(x, y))
        changes.append({'attribute': label, 'changed_rows': changed, 'total_rows': len(va), 'max_difference': maximum})


assert len(a['meshes']) == len(b['meshes'])
bm = {m['name']: m for m in b['meshes']}
for ma in a['meshes']:
    mb = bm[ma['name']]
    assert len(ma['primitives']) == len(mb['primitives'])
    assert ma.get('extras') == mb.get('extras')
    for i, (pa, pb) in enumerate(zip(ma['primitives'], mb['primitives'])):
        label = f"{ma['name']}/{i}"
        assert set(pa['attributes']) == set(pb['attributes']), label
        assert pa.get('material') == pb.get('material'), label
        indices_a = [v[0] for v in a['accessors'][pa['indices']]['decoded_values']]
        indices_b = [v[0] for v in b['accessors'][pb['indices']]['decoded_values']]
        assert len(indices_a) == len(indices_b), label
        for key in pa['attributes']:
            compare_accessor(label + '/' + key, pa['attributes'][key], pb['attributes'][key], indices_a, indices_b)
        assert len(pa.get('targets', [])) == len(pb.get('targets', [])), label
        for j, (ta, tb) in enumerate(zip(pa.get('targets', []), pb.get('targets', []))):
            assert set(ta) == set(tb)
            for key in ta:
                compare_accessor(label + f'/morph{j}/' + key, ta[key], tb[key], indices_a, indices_b)
for i, (sa, sb) in enumerate(zip(a.get('skins', []), b.get('skins', []))):
    assert {k: v for k, v in sa.items() if k != 'inverseBindMatrices'} == {k: v for k, v in sb.items() if k != 'inverseBindMatrices'}
    compare_accessor(f'skin{i}/inverseBindMatrices', sa['inverseBindMatrices'], sb['inverseBindMatrices'])
metadata_changes = [k for k in a if k not in ('meshes', 'accessors', 'buffers', 'bufferViews', 'skins') and a[k] != b.get(k)]
report = {'baseline': str(args.baseline), 'candidate': str(args.candidate),
          'meshes': len(a['meshes']), 'metadata_changes': metadata_changes,
          'resolved_data_changes': changes, 'exact_resolved_match': not changes and not metadata_changes}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
