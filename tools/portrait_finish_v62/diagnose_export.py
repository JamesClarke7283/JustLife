"""Compare exported additive normal targets with normals of the posed surface."""
import argparse
import json
from pathlib import Path
import struct

import numpy as np

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--glb', type=Path, required=True)
ap.add_argument('--profiles', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args()
raw = args.glb.read_bytes()
assert struct.unpack_from('<4sII', raw) == (b'glTF', 2, len(raw))
offset = 12
while offset < len(raw):
    size, kind = struct.unpack_from('<II', raw, offset)
    chunk = raw[offset + 8:offset + 8 + size]
    if kind == 0x4E4F534A:
        doc = json.loads(chunk)
    elif kind == 0x004E4942:
        binary = chunk
    offset += 8 + size


def accessor(index):
    a = doc['accessors'][index]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    dtype = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}[a['componentType']]
    item = np.dtype(dtype).itemsize
    values = np.zeros((a['count'], width), dtype=dtype)
    if 'bufferView' in a:
        view = doc['bufferViews'][a['bufferView']]
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        values[:] = np.ndarray(values.shape, dtype=dtype, buffer=binary, offset=start,
                               strides=(view.get('byteStride', width * item), item))
    if 'sparse' in a:
        s = a['sparse']
        ix, vv = s['indices'], s['values']
        iv, vview = doc['bufferViews'][ix['bufferView']], doc['bufferViews'][vv['bufferView']]
        idtype = {5121: 'u1', 5123: '<u2', 5125: '<u4'}[ix['componentType']]
        ids = np.frombuffer(binary, dtype=idtype, count=s['count'], offset=iv.get('byteOffset', 0) + ix.get('byteOffset', 0))
        vals = np.frombuffer(binary, dtype=dtype, count=s['count'] * width,
                             offset=vview.get('byteOffset', 0) + vv.get('byteOffset', 0)).reshape((-1, width))
        values[ids] = vals
    return values.astype(np.float64)


def normalized(values):
    return values / np.maximum(np.linalg.norm(values, axis=1)[:, None], 1e-15)


def surface_normals(points, triangles, groups):
    face = normalized(np.cross(points[triangles[:, 1]] - points[triangles[:, 0]],
                               points[triangles[:, 2]] - points[triangles[:, 0]]))
    normals = np.zeros((int(groups.max()) + 1, 3))
    for corner in range(3):
        vi = triangles[:, corner]
        u = normalized(points[triangles[:, (corner + 1) % 3]] - points[vi])
        v = normalized(points[triangles[:, (corner + 2) % 3]] - points[vi])
        angle = np.arccos(np.clip(np.sum(u * v, axis=1), -1, 1))
        np.add.at(normals, groups[vi], face * angle[:, None])
    return normalized(normals)[groups]


node = next(n for n in doc['nodes'] if n.get('name') == 'Skin_Head_continuous')
mesh = doc['meshes'][node['mesh']]
assert len(mesh['primitives']) == 1
prim = mesh['primitives'][0]
basis = accessor(prim['attributes']['POSITION'])
normals = accessor(prim['attributes']['NORMAL'])
triangles = accessor(prim['indices']).astype(np.int32).reshape((-1, 3))
names = mesh['extras']['targetNames']
targets = prim['targets']
profiles = json.loads(args.profiles.read_text())['generated_profiles']
# Export UV/color seams duplicate vertices. Merge only coincident base points;
# the head source intentionally has no sharp or custom normals.
_, groups = np.unique(np.round(basis, 7), axis=0, return_inverse=True)
cases = [('neutral', {})] + [('generated_' + str(i), p) for i, p in enumerate(profiles)]
report = {'glb': str(args.glb), 'node': node, 'bounds': [basis.min(axis=0).tolist(), basis.max(axis=0).tolist()],
          'targets': names, 'cases': []}
report['skin_meshes_near_chin'] = []
for other in doc['nodes']:
    if 'mesh' not in other or 'skin' not in other or not other.get('name', '').startswith(('Skin_', 'Body_', 'Outfit_Tee', 'Outfit_Casual')):
        continue
    for part in doc['meshes'][other['mesh']]['primitives']:
        ps = accessor(part['attributes']['POSITION'])
        lo, hi = ps.min(axis=0), ps.max(axis=0)
        if lo[1] < 1.49 and hi[1] > 1.435 and lo[2] < .09 and hi[2] > .035:
            report['skin_meshes_near_chin'].append({'node': other['name'], 'bounds': [lo.tolist(), hi.tolist()]})
for label, profile in cases:
    points, blended = basis.copy(), normals.copy()
    for name, target in zip(names, targets):
        amount = float(profile.get(name.lower(), 0))
        if amount:
            points += amount * accessor(target['POSITION'])
            if 'NORMAL' in target:
                blended += amount * accessor(target['NORMAL'])
    calculated = surface_normals(points, triangles, groups)
    error = np.degrees(np.arccos(np.clip(np.sum(normalized(blended) * calculated, axis=1), -1, 1)))
    # Node points are already Y-up world-proportioned in this asset. Save the
    # worst errors and coordinates as a diagnostic, not an aesthetic verdict.
    ids = np.argsort(error)[-40:][::-1]
    regions = {}
    for zone, mask in {
        'chin': (np.abs(basis[:, 0]) < .035) & (basis[:, 1] > 1.435) & (basis[:, 1] < 1.490) & (basis[:, 2] > .026),
        'cheek': (np.abs(basis[:, 0]) > .038) & (np.abs(basis[:, 0]) < .082) & (basis[:, 1] > 1.485) & (basis[:, 1] < 1.560) & (basis[:, 2] > .035),
    }.items():
        zids = np.flatnonzero(mask)
        ranked = sorted(zids, key=lambda i: error[i], reverse=True)[:12]
        regions[zone] = {'vertices': len(zids), 'median_error_deg': float(np.median(error[zids])),
                         'max_error_deg': float(error[zids].max()),
                         'worst': [{'vertex': int(i), 'basis': basis[i].tolist(),
                                    'posed': points[i].tolist(), 'error_deg': float(error[i])} for i in ranked]}
    report['cases'].append({'case': label, 'median_error_deg': float(np.median(error)),
                            'p95_error_deg': float(np.percentile(error, 95)), 'max_error_deg': float(error.max()),
                            'regions': regions,
                            'worst': [{'vertex': int(i), 'basis': basis[i].tolist(), 'posed': points[i].tolist(),
                                       'error_deg': float(error[i]), 'blended': normalized(blended)[i].tolist(),
                                       'calculated': calculated[i].tolist()} for i in ids]})
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('EXPORT_NORMAL_DIAGNOSTIC', json.dumps({'glb': report['glb'], 'bounds': report['bounds'], 'targets': names}))
print('CASES', json.dumps([{k: v for k, v in c.items() if k not in ('worst', 'regions')} | {
    'regions': {name: {k: v for k, v in zone.items() if k != 'worst'} for name, zone in c['regions'].items()}
} for c in report['cases']]))
