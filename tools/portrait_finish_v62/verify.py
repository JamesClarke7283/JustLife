"""Focused source/contact and generated-profile face-surface verification."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--author-report', type=Path, required=True)
ap.add_argument('--profiles', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
owned = 'Skin_Head_continuous'


def array(collection, field, width):
    data = np.empty(len(collection) * width, dtype=np.float32)
    collection.foreach_get(field, data)
    return data.reshape((-1, width))


def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    head = bpy.data.objects[owned]
    keys = {key.name: array(key.data, 'co', 3) for key in head.data.shape_keys.key_blocks}
    all_objects = {}
    for obj in bpy.data.objects:
        digest = hashlib.sha256()
        meta = {'type': obj.type, 'parent': obj.parent.name if obj.parent else None,
                'matrix': [float(v) for row in obj.matrix_world for v in row]}
        if obj.type == 'MESH':
            meta['materials'] = [m.name if m else None for m in obj.data.materials]
            if obj.name != owned:
                digest.update(array(obj.data.vertices, 'co', 3).tobytes())
                if obj.data.shape_keys:
                    for key in obj.data.shape_keys.key_blocks:
                        digest.update(key.name.encode())
                        digest.update(array(key.data, 'co', 3).tobytes())
            for poly in obj.data.polygons:
                digest.update(np.asarray(tuple(poly.vertices) + (poly.material_index,), dtype=np.int32).tobytes())
            for uv in obj.data.uv_layers:
                digest.update(uv.name.encode())
                digest.update(array(uv.data, 'uv', 2).tobytes())
            for color in obj.data.color_attributes:
                digest.update((color.name + color.domain + color.data_type).encode())
                digest.update(array(color.data, 'color', 4).tobytes())
            for vertex in obj.data.vertices:
                digest.update(json.dumps([(g.group, g.weight) for g in vertex.groups]).encode())
            meta['static_data'] = digest.hexdigest()
        all_objects[obj.name] = meta
    head.data.calc_loop_triangles()
    triangles = np.asarray([tuple(t.vertices) for t in head.data.loop_triangles], dtype=np.int32)
    anchors = {name: list(bpy.data.objects['Character'][name]) if name == 'mouth_anchor' else
               json.dumps(bpy.data.objects['Character'][name].to_dict(), sort_keys=True)
               for name in ('mouth_anchor', 'mouth_identity_offsets') if name in bpy.data.objects['Character']}
    return keys, all_objects, triangles, anchors


before, before_meta, triangles, before_anchors = snapshot(args.baseline)
after, after_meta, after_triangles, after_anchors = snapshot(args.candidate)
assert before_meta == after_meta, 'Non-coordinate object/mesh data changed'
assert before_anchors == after_anchors, 'Mouth anchor metadata changed'
assert np.array_equal(triangles, after_triangles)
assert before.keys() == after.keys()
operator_ids = {row['vertex'] for row in json.loads(args.author_report.read_text())['diagnostics']}
protected = sorted(set(range(len(before['Basis']))) - operator_ids)
for name in before:
    assert np.array_equal(before[name][protected], after[name][protected]), ('Protected head points changed', name)
head = bpy.data.objects[owned]
for prop in ('orbit_inner_0', 'orbit_inner_1', 'orbit_shared_0', 'orbit_shared_1'):
    ids = list(head[prop])
    assert all(np.array_equal(before[name][ids], after[name][ids]) for name in before)


def posed(stores, values):
    points = stores['Basis'].astype(np.float64)
    for name, amount in values.items():
        if name in stores and amount != 0:
            points += (stores[name].astype(np.float64) - stores['Basis']) * amount
    return points


def cross(points):
    return np.cross(points[triangles[:, 1]] - points[triangles[:, 0]], points[triangles[:, 2]] - points[triangles[:, 0]])


profiles = json.loads(args.profiles.read_text())['generated_profiles']
cases = [('neutral', {})]
for index, profile in enumerate(profiles):
    values = {name: float(profile.get(name.lower(), 0)) for name in before if name != 'Basis'}
    cases.append(('generated_' + str(index), values))
unsigned = dict.fromkeys(('Face_Round', 'Jaw_Strong', 'Nose_Wide', 'Eye_Spacing'), 1.)
signed = ('Nose_Length', 'Lip_Fullness', 'Chin_Length', 'Face_Length', 'Mouth_Width', 'Nose_Bridge')
cases += [('unsigned_max', unsigned), ('signed_positive', dict(unsigned, **dict.fromkeys(signed, 1.))),
          ('signed_negative', dict(unsigned, **dict.fromkeys(signed, -1.))),
          ('smile_max', dict(unsigned, Smile=1.)), ('blink_max', dict(unsigned, Blink=1.))]
checks, failures = [], []
for label, values in cases:
    a, b = cross(posed(before, values)), cross(posed(after, values))
    area_a, area_b = np.linalg.norm(a, axis=1), np.linalg.norm(b, axis=1)
    valid = area_a > 1e-10
    flips = np.flatnonzero((np.sum(a * b, axis=1) < 0) & valid)
    collapsed = np.flatnonzero((area_b < area_a * .1) & valid)
    checks.append({'case': label, 'flipped_triangles': len(flips), 'collapsed_triangles': len(collapsed),
                   'minimum_area_ratio': float(np.min(area_b[valid] / area_a[valid]))})
    if len(flips) or len(collapsed):
        failures.append({'case': label, 'flips': flips.tolist(), 'collapsed': collapsed.tolist()})
report = {'candidate': str(args.candidate), 'sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
          'protected_non_head_objects': len(before_meta) - 1, 'protected_head_vertices': len(protected),
          'topology_uv_color_material_weight_object_data_unchanged': True,
          'mouth_anchor_and_orbital_target_coordinates_exact': True,
          'surface_checks': checks, 'failures': failures}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
assert not failures, failures
print('FACIAL_FINISH_PASS', json.dumps(report))
