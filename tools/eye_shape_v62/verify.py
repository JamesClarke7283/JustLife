"""Check actual orbital geometry, optical occlusion and corrective composition."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import KEY, OWNED, OrbitalField, array, frozen_digest, local, posed, world

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', type=Path, required=True)
p.add_argument('--candidate', type=Path, required=True)
p.add_argument('--author-report', type=Path, required=True)
p.add_argument('--profiles', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
authored = json.loads(a.author_report.read_text())
assert hashlib.sha256(a.baseline.read_bytes()).hexdigest() == authored['source_sha256']
assert hashlib.sha256(a.candidate.read_bytes()).hexdigest() == authored['output_sha256']
bpy.ops.wm.open_mainfile(filepath=str(a.baseline.resolve()))
before = {o.name: frozen_digest(o) for o in bpy.data.objects}
old_keys = {o.name: {k.name: array(k.data).astype(np.float64) for k in o.data.shape_keys.key_blocks}
            for o in bpy.data.objects if o.name in authored['owned']}
bpy.ops.wm.open_mainfile(filepath=str(a.candidate.resolve()))
bpy.context.view_layer.update()
assert before == {o.name: frozen_digest(o) for o in bpy.data.objects}
field = OrbitalField(authored['degrees'])
head = bpy.data.objects['Skin_Head_continuous']
head.data.calc_loop_triangles()
triangles = np.asarray([tuple(t.vertices) for t in head.data.loop_triangles], dtype=np.int32)
globes = sorted((o for o in bpy.data.objects if o.type == 'MESH'
                 and o.name.startswith('Eyes_Sclera')), key=lambda o: world(o, local(o))[:, 0].mean())
topology = {o.name: [tuple(f.vertices) for f in o.data.polygons] for o in [head, *globes]}


def tree(obj, points):
    return BVHTree.FromPolygons([Vector(x) for x in points], topology[obj.name])


def front(bvh, x, z):
    position, _, _, _ = bvh.ray_cast(Vector((x, -2., z)), Vector((0., 1., 0.)), 4.)
    return position.y if position is not None else 10.


def contains(polygon, x, z):
    inside = False
    for i, point in enumerate(polygon):
        other = polygon[i - 1]
        if (point[2] > z) != (other[2] > z) and x < (other[0] - point[0]) * (z - point[2]) / (other[2] - point[2]) + point[0]:
            inside = not inside
    return inside


def old_pose(obj, values):
    keys = old_keys[obj.name]
    basis = keys['Basis']
    points = basis.copy()
    for name, value in values.items():
        if name in keys and value:
            points += (keys[name] - basis) * value
    return world(obj, points)


def cross(points):
    return np.cross(points[triangles[:, 1]] - points[triangles[:, 0]],
                    points[triangles[:, 2]] - points[triangles[:, 0]])


unsigned = dict.fromkeys(('Face_Round', 'Jaw_Strong', 'Nose_Wide', 'Eye_Spacing'), 1.)
signed = ('Nose_Length', 'Lip_Fullness', 'Brow_Arch', 'Chin_Length', 'Face_Length', 'Mouth_Width', 'Nose_Bridge')
contexts = [('neutral', {}), ('unsigned_max', unsigned),
            ('signed_positive', dict(unsigned, **dict.fromkeys(signed, 1.))),
            ('signed_negative', dict(unsigned, **dict.fromkeys(signed, -1.)))]
profiles = json.loads(a.profiles.read_text())['generated_profiles']
for index, profile in enumerate(profiles):
    contexts.append(('generated_' + str(index), {key: float(profile.get(key.lower(), 0.))
                                                for key in [*unsigned, *signed]}))
checks, failures = [], []
for (label, values), tilt, blink in itertools.product(contexts, (-1., 0., 1.), (0., .5, 1.)):
    values = dict(values, **{KEY: tilt, 'Blink': blink})
    hp = posed(head, values)
    head_tree = tree(head, hp)
    old = old_pose(head, values)
    normals_a, normals_b = cross(old), cross(hp)
    areas_a, areas_b = np.linalg.norm(normals_a, axis=1), np.linalg.norm(normals_b, axis=1)
    valid = areas_a > 1e-10
    flips = int(np.sum((np.sum(normals_a * normals_b, axis=1) < 0) & valid))
    collapsed = int(np.sum((areas_b < areas_a * .2) & valid))
    exact_error = 0.
    for name in authored['owned']:
        obj = bpy.data.objects[name]
        wp = world(obj, local(obj))
        params = field.parameters(obj, wp)
        original_pose = old_pose(obj, values)
        direct = original_pose + tilt * field.linear(original_pose - params[0], params)
        exact_error = max(exact_error, float(np.linalg.norm(posed(obj, values) - direct, axis=1).max()))
    sampled, exposed = 0, []
    for side, globe in enumerate(globes):
        gp = posed(globe, values)
        globe_tree = tree(globe, gp)
        low, high = gp.min(axis=0), gp.max(axis=0)
        aperture = hp[list(head['orbit_inner_' + str(side)])]
        for ix, iz in itertools.product(range(31), range(19)):
            x = low[0] + (high[0] - low[0]) * (ix + .5) / 31
            z = low[2] + (high[2] - low[2]) * (iz + .5) / 19
            eye_y = front(globe_tree, x, z)
            if eye_y == 10. or (blink < 1. and contains(aperture, x, z)):
                continue
            sampled += 1
            skin_y = front(head_tree, x, z)
            if eye_y < skin_y - .00015:
                exposed.append((side, float(x), float(z), float(skin_y - eye_y)))
    row = {'context': label, 'eye_tilt': tilt, 'blink': blink,
           'flipped_triangles': flips, 'collapsed_triangles': collapsed,
           'direct_transform_max_error_m': exact_error,
           'outside_aperture_samples': sampled, 'exposed_globe_samples': len(exposed)}
    checks.append(row)
    if flips or collapsed or exact_error > 1e-6 or exposed or sampled == 0:
        failures.append(dict(row, exposure_examples=exposed[:5]))
report = {'candidate': str(a.candidate.resolve()), 'sha256': authored['output_sha256'],
          'old_object_states_exact': len(before), 'cases': checks,
          'total_globe_samples': sum(row['outside_aperture_samples'] for row in checks),
          'failures': failures, 'production_promoted': False}
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('EYE_TILT_CHECKED', len(checks), 'cases;', len(failures), 'failures;', a.report)
assert not failures, failures[:3]
