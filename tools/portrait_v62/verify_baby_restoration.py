"""Verify reconstructed baby surfaces despite glTF vertex/triangle reordering.

The released parametric recipe is not bit deterministic under Blender CPU
subdivision. This report checks actual indexed triangle connectivity, paired
joint influence maps, and positions against an explicit ten micrometre bound.
"""
import argparse
from collections import Counter, defaultdict
import itertools
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'child_bob_v36'))
from decoded_gltf import decoded_document

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--release', type=Path, required=True)
ap.add_argument('--reconstructed', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args()
a, b = decoded_document(args.release), decoded_document(args.reconstructed)
assert all(a.get(k) == b.get(k) for k in ('asset', 'scene', 'scenes', 'nodes', 'materials'))
assert len(a.get('skins', [])) == len(b.get('skins', []))
bm = {m['name']: m for m in b['meshes']}
results = []
cell = 1e-4
limit = 1e-5
neighbors = list(itertools.product((-1, 0, 1), repeat=3))


def values(document, index):
    return document['accessors'][index]['decoded_values']


for ma in a['meshes']:
    mb = bm[ma['name']]
    assert ma.get('extras') == mb.get('extras')
    for pa, pb in zip(ma['primitives'], mb['primitives']):
        posa, posb = values(a, pa['attributes']['POSITION']), values(b, pb['attributes']['POSITION'])
        bins = defaultdict(list)
        representatives = []

        def nearby(p):
            key = tuple(math.floor(x / cell) for x in p)
            for delta in neighbors:
                yield from bins[tuple(k + d for k, d in zip(key, delta))]

        def nearest(p):
            candidates = [(sum((x - y) ** 2 for x, y in zip(p, representatives[i])), i) for i in nearby(p)]
            return min(candidates) if candidates else (math.inf, None)

        mapb = []
        for p in posb:
            distance, index = nearest(p)
            if distance > 1e-14:
                index = len(representatives)
                representatives.append(p)
                bins[tuple(math.floor(x / cell) for x in p)].append(index)
            mapb.append(index)
        mapa, maximum = [], 0.0
        for p in posa:
            distance, index = nearest(p)
            maximum = max(maximum, math.sqrt(distance))
            assert distance <= limit * limit, (ma['name'], 'surface point moved', p, math.sqrt(distance))
            mapa.append(index)
        ia = [row[0] for row in values(a, pa['indices'])]
        ib = [row[0] for row in values(b, pb['indices'])]
        assert len(ia) == len(ib)
        ta = Counter(tuple(sorted(mapa[index] for index in ia[i:i + 3])) for i in range(0, len(ia), 3))
        tb = Counter(tuple(sorted(mapb[index] for index in ib[i:i + 3])) for i in range(0, len(ib), 3))
        assert ta == tb, (ma['name'], 'triangle topology mismatch', len(ta - tb), len(tb - ta))
        influence_error = 0.0
        if 'JOINTS_0' in pa['attributes']:
            ja, jb = values(a, pa['attributes']['JOINTS_0']), values(b, pb['attributes']['JOINTS_0'])
            wa, wb = values(a, pa['attributes']['WEIGHTS_0']), values(b, pb['attributes']['WEIGHTS_0'])
            by_position = {}
            for index, (joints, weights) in enumerate(zip(jb, wb)):
                by_position[mapb[index]] = {j: w for j, w in zip(joints, weights) if w > 0}
            for index, (joints, weights) in enumerate(zip(ja, wa)):
                source = {j: w for j, w in zip(joints, weights) if w > 0}
                target = by_position[mapa[index]]
                influence_error = max(influence_error, max(abs(source.get(j, 0) - target.get(j, 0)) for j in source.keys() | target.keys()))
            assert influence_error < 4e-6, (ma['name'], influence_error)
        results.append({'mesh': ma['name'], 'triangles': len(ia) // 3,
                        'surface_max_error_m': maximum, 'joint_influence_max_error': influence_error})
report = {'release': str(args.release), 'reconstructed': str(args.reconstructed),
          'scene_material_rig_metadata_exact': True, 'mesh_count': len(a['meshes']),
          'indexed_triangle_connectivity_equal': True,
          'surface_error_bound_m': limit, 'explanation': 'Same released generator; Blender subdivision arithmetic and glTF ordering differ. No visible surface or rig change within explicit measured bounds.',
          'meshes': results}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('BABY_RESTORATION_VERIFIED', len(results), 'meshes', max(r['surface_max_error_m'] for r in results), 'm surface bound')
