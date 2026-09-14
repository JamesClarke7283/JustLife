"""Locally fair cheek/chin surfaces with a curvature-preserving MLS operator.

Only coordinates of the existing head mesh and its supported targets change.
The orbital patch, mouth support, nasal core and unrelated character art are
protected. A shared linear neighborhood operator removes high-frequency
surface and delta irregularities without replacing broad identity forms.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
ap.add_argument('--iterations', type=int, default=3)
ap.add_argument('--radius', type=float, default=.010)
ap.add_argument('--region', choices=('lower-face', 'chin'), default='lower-face')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve()
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
head = bpy.data.objects['Skin_Head_continuous']
keys = head.data.shape_keys.key_blocks
matrix = np.asarray(head.matrix_world, dtype=np.float64)
inverse = np.linalg.inv(matrix)
original = {key.name: np.asarray([tuple(v.co) for v in key.data], dtype=np.float64) @ matrix[:3, :3].T + matrix[:3, 3]
            for key in keys}
basis = original['Basis']


def smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * t * (t * (t * 6 - 15) + 10)


eye_points = [o.matrix_world @ v.co for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Eyes_Sclera')
              for v in o.data.shape_keys.key_blocks['Basis'].data]
eye_z = (min(p.z for p in eye_points) + max(p.z for p in eye_points)) * .5
lip_points = [o.matrix_world @ v.co for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Lips_')
              for v in o.data.shape_keys.key_blocks['Basis'].data]
lip_lo, lip_hi = min(p.z for p in lip_points), max(p.z for p in lip_points)
lip_half = max(abs(p.x) for p in lip_points)
x, y, z = basis.T
front = 1 - smooth(-.040, -.014, y)
lateral = 1 - smooth(.083, .107, np.abs(x))
height = smooth(lip_lo - .060, lip_lo - .042, z) * (1 - smooth(eye_z - .034, eye_z - .023, z))
mouth_protection = (1 - smooth(lip_half + .005, lip_half + .016, np.abs(x))) * smooth(lip_lo - .010, lip_lo - .004, z) * (1 - smooth(lip_hi + .004, lip_hi + .010, z))
nose_protection = (1 - smooth(.021, .037, np.abs(x))) * smooth(lip_hi + .004, lip_hi + .014, z)
mask = front * lateral * height * (1 - mouth_protection) * (1 - nose_protection)
if args.region == 'chin':
    # A second, bounded underside pass spans the sparse transition on both
    # sides. Keep the already accepted cheeks, mouth support and jaw corners
    # fixed; the larger neighborhood supplies the missing smooth curvature.
    chin_width = 1 - smooth(.022, .044, np.abs(x))
    chin_height = smooth(lip_lo - .075, lip_lo - .056, z) * (1 - smooth(lip_lo - .023, lip_lo - .011, z))
    chin_front = 1 - smooth(-.028, -.008, y)
    mask = chin_width * chin_height * chin_front * (1 - mouth_protection)
protected_orbit = set()
for prop in ('orbit_inner_0', 'orbit_inner_1', 'orbit_shared_0', 'orbit_shared_1'):
    protected_orbit.update(int(i) for i in head[prop])
mask[list(protected_orbit)] = 0
active = np.flatnonzero(mask > 1e-8)
kd = KDTree(len(basis))
for i, p in enumerate(basis):
    kd.insert(Vector(p), i)
kd.balance()
operators = {}
diagnostics = []
for i in active:
    nearby = [(j, distance) for _, j, distance in kd.find_range(Vector(basis[i]), args.radius) if j != i]
    if len(nearby) < 14:
        continue
    ids = np.asarray([j for j, _ in nearby], dtype=np.int32)
    offsets = basis[ids] - basis[i]
    weights = np.exp(-np.sum(offsets * offsets, axis=1) / (args.radius * .72)**2)
    _, _, axes = np.linalg.svd(offsets * np.sqrt(weights[:, None]), full_matrices=False)
    local = offsets @ axes.T
    u, v = local[:, 0] / args.radius, local[:, 1] / args.radius
    design = np.column_stack((np.ones(len(u)), u, v, u * u, u * v, v * v))
    weighted = design * np.sqrt(weights[:, None])
    operator = np.linalg.pinv(weighted, rcond=1e-7)[0] * np.sqrt(weights)
    # Reject a poorly supported/extrapolating fit near a true boundary.
    if np.sum(np.abs(operator)) > 3.5:
        continue
    operators[int(i)] = (ids, operator)
    residual = operator @ basis[ids] - basis[i]
    diagnostics.append({'vertex': int(i), 'world': basis[i].tolist(), 'mask': float(mask[i]),
                        'normal_fit_error_m': float(np.linalg.norm(residual)), 'neighbors': len(ids)})

outputs = {name: points.copy() for name, points in original.items()}
changes = {}
for iteration in range(args.iterations):
    updates = {name: np.zeros_like(points) for name, points in outputs.items()}
    for i, (ids, operator) in operators.items():
        base_delta = operator @ outputs['Basis'][ids] - outputs['Basis'][i]
        length = np.linalg.norm(base_delta)
        factor = mask[i] * .78 * min(1.0, .0012 / max(length, 1e-15))
        # Use one identical linear operator/limiter for Basis and every key,
        # so an arbitrary signed morph combination remains the same locally
        # faired surface rather than receiving independently clipped fields.
        for name, current in outputs.items():
            updates[name][i] = (operator @ current[ids] - current[i]) * factor
    for name in outputs:
        outputs[name] += updates[name]
for name, points in original.items():
    current = outputs[name]
    displacement = np.linalg.norm(current - points, axis=1)
    changes[name] = {'changed_vertices': int(np.count_nonzero(displacement > 1e-9)),
                     'maximum_world_displacement_m': float(displacement.max())}
    local = (current - matrix[:3, 3]) @ inverse[:3, :3].T
    for i in operators:
        keys[name].data[i].co = Vector(local[i])
    # Never rewrite protected vertices through floating-point transforms.
    assert all(np.array_equal(current[i], points[i]) for i in protected_orbit)
for i, vertex in enumerate(head.data.vertices):
    vertex.co = keys['Basis'].data[i].co
head.data.update()
for key in keys:
    key.value = 0
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
report = {'source': str(args.source), 'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
          'output': str(args.output), 'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
          'scope': 'Head coordinates and supported key targets only; unchanged topology/materials/UVs/colors/weights/non-head art/anchors',
          'iterations': args.iterations, 'radius_m': args.radius, 'region': args.region, 'operator_vertices': len(operators),
          'protected_orbital_indices': len(protected_orbit), 'changes': changes,
          'largest_initial_defects': sorted(diagnostics, key=lambda row: row['normal_fit_error_m'], reverse=True)[:40],
          'diagnostics': diagnostics}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('LOCAL_FACE_FAIRING_AUTHORED', json.dumps({k: v for k, v in report.items()
                                              if k not in ('diagnostics', 'largest_initial_defects')}))
