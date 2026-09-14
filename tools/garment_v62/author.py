"""Tailor the two adult shirt meshes without changing channels or attachments."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import OWNED, facts, gaussian, rig_anchors, smooth, trim_objects, trim_tree, world_points
from pose_safety import constrain as constrain_poses

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
ap.add_argument('--iterations', type=int, default=0)
ap.add_argument('--sleeve-reduction', type=float, default=0.)
ap.add_argument('--profile-strength', type=float, default=.85)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve() and not args.output.exists()
assert 0 <= args.iterations <= 100 and 0 <= args.sleeve_reduction <= .20
assert 0 <= args.profile_strength <= 1.
source_sha = hashlib.sha256(args.source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
before = facts()
print('GARMENT_SOURCE_SNAPSHOTTED', len(before['objects']), 'objects', flush=True)
shirts = [bpy.data.objects[name] for name in OWNED]
assert all(len(o.data.vertices) == 6002 and o.data.shape_keys is None for o in shirts)
# Accept later composed head/hair sources, but never tailor an already-tailored
# shirt a second time. The guard covers the full original mesh data, not a file
# checksum, so unrelated authorized source composition remains possible.
original_shirt_sha = 'e8c130a0ed2dc6da850b49d3c232f09c1a501898507c559707a5802ca919b17a'
assert all(before['objects'][o.name]['geometry_sha256'] == original_shirt_sha for o in shirts), 'Expected untouched original adult shirt geometry'
source = np.asarray([p[:] for p in world_points(shirts[0])], dtype=np.float64)
assert np.max(np.abs(source - np.asarray([p[:] for p in world_points(shirts[1])]))) < 1e-7
anchors = rig_anchors()
scale = abs(anchors['Arm_R'].x) / .18
collar = bpy.data.objects['Outfit_Casual_Top_Collar_binding']
collar_half = max(abs(p.x) for p in world_points(collar))
cuffs = [o for o in trim_objects() if o.name.startswith('Outfit_Casual_') and 'Sleeve_cuff' in o.name]
cuff_points = [p for o in cuffs for p in world_points(o)]
cuff_z = (min(p.z for p in cuff_points) + max(p.z for p in cuff_points)) * .5
cuff_x = sum(abs(p.x) for p in cuff_points) / len(cuff_points)
shoulder_x, shoulder_z = abs(anchors['Arm_R'].x), anchors['Arm_R'].z
inner_x, outer_x = collar_half + .010 * scale, shoulder_x + .045 * scale
tree = trim_tree()
distances = np.array([tree.find(Vector(p))[2] for p in source])
pinned = np.flatnonzero(distances <= .009 * scale)
guard = np.array([smooth(.009 * scale, .024 * scale, distance)
                  * smooth(cuff_z + .050 * scale, cuff_z + .090 * scale, p[2])
                  * smooth(collar_half + .005 * scale, collar_half + .055 * scale, abs(p[0]))
                  for p, distance in zip(source, distances)])

# Measure the actual projected top contour by triangle/plane intersections,
# using the envelope of both sides. No shoulder-height anchors are guessed.
shirts[0].data.calc_loop_triangles()
triangles = np.array([t.vertices[:] for t in shirts[0].data.loop_triangles], dtype=np.int32)
tri = source[triangles]
def top_at(x):
    hits = []
    for side in (-1., 1.):
        plane = side * x
        for edge in ((0, 1), (1, 2), (2, 0)):
            a, b = tri[:, edge[0]], tri[:, edge[1]]
            valid = ((a[:, 0] <= plane) & (b[:, 0] >= plane) | (a[:, 0] >= plane) & (b[:, 0] <= plane))
            valid &= np.abs(a[:, 0] - b[:, 0]) > 1e-12
            aa, bb = a[valid], b[valid]
            if len(aa):
                t = (plane - aa[:, 0]) / (bb[:, 0] - aa[:, 0])
                hits.append(float(np.max(aa[:, 2] + t * (bb[:, 2] - aa[:, 2]))))
    assert hits, ('No shirt contour at x', x)
    # Edge sets may contain unequal maxima; the envelope is the physical edge.
    return max(hits)

samples_x = np.linspace(inner_x, outer_x, 81)
old_top = np.array([top_at(x) for x in samples_x])
t = (samples_x - inner_x) / (outer_x - inner_x)
target_top = old_top[0] + (old_top[-1] - old_top[0]) * (.90 * t + .10 * t * t)
contour_delta = target_top - old_top
# The measured decimated contour contains sub-centimeter sampling kinks.
# Smooth the displacement (not the garment mesh) before applying a broad field.
kernel = np.exp(-.5 * (np.arange(-6, 7) / 2.5) ** 2)
kernel /= np.sum(kernel)
contour_delta = np.convolve(np.pad(contour_delta, 6, mode='edge'), kernel, mode='valid')
shaped = source.copy()
for i, p in enumerate(source):
    ax = abs(p[0])
    if inner_x < ax < outer_x:
        top = float(np.interp(ax, samples_x, old_top))
        delta = float(np.interp(ax, samples_x, contour_delta))
        taper = smooth(inner_x, inner_x + .014 * scale, ax) * (1. - smooth(outer_x - .014 * scale, outer_x, ax))
        shaped[i, 2] += delta * args.profile_strength * gaussian(p[2], top, .034 * scale) * guard[i] * taper

# Broad fairing removes the narrow pinched inset and rounds the join across
# adjacent triangles. Exact native trim-near vertices and lower drape are fixed.
edges = np.array([e.vertices[:] for e in shirts[0].data.edges], dtype=np.int32)
src = np.concatenate((edges[:, 0], edges[:, 1]))
dst = np.concatenate((edges[:, 1], edges[:, 0]))
degree = np.bincount(src, minlength=len(source))
assert np.all(degree > 0), 'Unexpected isolated garment vertices'
for _ in range(args.iterations):
    total = np.zeros_like(shaped)
    np.add.at(total, src, shaped[dst])
    average = total / degree[:, None]
    shaped += (average - shaped) * (.28 * guard[:, None])
    displacement = shaped - source
    length = np.linalg.norm(displacement, axis=1)
    over = length > .014 * scale
    shaped[over] = source[over] + displacement[over] * ((.014 * scale) / length[over, None])

# Reduce sleeve fullness about the measured arm-to-cuff line, not the torso's
# origin. This keeps natural ease around the arm instead of flattening depth.
for i, p in enumerate(source):
    fraction = max(0., min(1., (shoulder_z - p[2]) / (shoulder_z - cuff_z)))
    axis_x = shoulder_x + (cuff_x - shoulder_x) * fraction
    axis_y = anchors['Forearm_R'].y * fraction
    weight = smooth(shoulder_x - .035 * scale, shoulder_x + .035 * scale, abs(p[0]))
    weight *= gaussian(p[2], shoulder_z - .085 * scale, .085 * scale) * guard[i]
    sign = -1. if p[0] < 0 else 1.
    shaped[i, 0] -= sign * (abs(shaped[i, 0]) - axis_x) * args.sleeve_reduction * weight
    shaped[i, 1] -= (shaped[i, 1] - axis_y) * args.sleeve_reduction * weight

# Constrain the proposal against the actual arm surface. The source's cap has
# less than 2 mm of clearance in places, so global sleeve shrinking is unsafe.
# Backtracking keeps existing tight contacts rather than pushing through skin;
# smooth geodesic falloff avoids a hard per-vertex projection ridge.
skin_vertices, skin_faces = [], []
for obj in bpy.data.objects:
    if obj.type == 'MESH' and obj.name.startswith('Skin_Arm_continuous'):
        points = world_points(obj, True)
        assert len(points) == len(obj.data.vertices), ('Unexpected skin topology modifier', obj.name)
        offset = len(skin_vertices)
        skin_vertices.extend(points)
        obj.data.calc_loop_triangles()
        skin_faces.extend([tuple(offset + v for v in tri.vertices) for tri in obj.data.loop_triangles])
assert skin_vertices and skin_faces
skin_tree = BVHTree.FromPolygons(skin_vertices, skin_faces, all_triangles=True)
proposal = shaped - source
retained = np.ones(len(source))
clearance_limited = []
for i, p in enumerate(source):
    if np.linalg.norm(proposal[i]) < 1e-10:
        continue
    hit, normal, _, distance = skin_tree.find_nearest(Vector(p))
    if distance > .030 * scale:
        continue
    minimum = min((Vector(p) - hit).dot(normal), .0025 * scale)
    def safe(fraction):
        sample = Vector(p + proposal[i] * fraction)
        target, direction, _, _ = skin_tree.find_nearest(sample)
        return (sample - target).dot(direction) >= minimum - 1e-8 * scale
    if not safe(1.):
        low, high = 0., 1.
        for _ in range(14):
            middle = (low + high) * .5
            if safe(middle):
                low = middle
            else:
                high = middle
        retained[i] = low
        clearance_limited.append(i)

def soften_limits():
    for _ in range(5):
        limit = retained.copy()
        np.minimum.at(limit, src, retained[dst] + .20)
        retained[:] = np.minimum(retained, limit)

soften_limits()
# A few narrow source triangles have unstable normal directions at the old
# armhole crease. Limit only their local deformation, with a smooth neighbor
# falloff; do not let those triangles fold as the shoulder is reshaped.
n0 = np.cross(source[triangles[:, 1]] - source[triangles[:, 0]],
              source[triangles[:, 2]] - source[triangles[:, 0]])
a0 = np.linalg.norm(n0, axis=1)
barrier_limited = set()
for barrier_iteration in range(30):
    shaped = source + proposal * retained[:, None]
    n1 = np.cross(shaped[triangles[:, 1]] - shaped[triangles[:, 0]],
                  shaped[triangles[:, 2]] - shaped[triangles[:, 0]])
    a1 = np.linalg.norm(n1, axis=1)
    bad = (np.sum(n0 * n1, axis=1) < .20 * a0 * a1) | (a1 < .10 * a0)
    if not np.any(bad):
        break
    affected = np.unique(triangles[bad])
    barrier_limited.update(int(i) for i in affected)
    retained[affected] *= .5
    soften_limits()
assert not np.any(bad), 'Local shoulder barrier did not converge'
print('GARMENT_CONSTRAINED', len(clearance_limited), 'clearance vertices',
      len(barrier_limited), 'triangle vertices', barrier_iteration, 'barrier iterations', flush=True)
shaped, pose_report = constrain_poses(shirts[0], source, shaped, triangles, edges, scale)
assert np.array_equal(shaped[pinned], source[pinned])
delta = shaped - source
report = {'source': str(args.source.resolve()), 'source_sha256': source_sha,
          'author_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'output': str(args.output.resolve()), 'parameters': {'iterations': args.iterations,
          'sleeve_reduction': args.sleeve_reduction, 'profile_strength': args.profile_strength},
          'scale': scale, 'measured_anchors': {'collar_halfwidth': collar_half,
          'cuff_z': cuff_z, 'cuff_x': cuff_x, 'shoulder_x': shoulder_x, 'shoulder_z': shoulder_z},
          'profile': [{'x': float(x), 'old_top_z': float(z), 'target_top_z': float(target)}
                      for x, z, target in zip(samples_x, old_top, target_top)],
          'smoothed_profile_delta_m': contour_delta.tolist(),
          'pinned_ids': pinned.tolist(), 'shirts': {}}
report['surface_constraints'] = {'minimum_clearance_m': .0025 * scale,
    'existing_tighter_clearance_preserved': True,
    'clearance_limited_vertices': len(clearance_limited),
    'triangle_barrier_vertices': len(barrier_limited),
    'barrier_iterations': barrier_iteration,
    'proposal_displacement_sum_m': float(np.sum(np.linalg.norm(proposal, axis=1))),
    'retained_displacement_sum_m': float(np.sum(np.linalg.norm(delta, axis=1)))}
report['actual_pose_constraints'] = pose_report
for obj in shirts:
    inverse = obj.matrix_world.to_3x3().inverted()
    for i, v in enumerate(obj.data.vertices):
        if np.linalg.norm(delta[i]) > 1e-10:
            v.co += inverse @ Vector(delta[i])
    obj.data.update()
    actual = [i for i, v in enumerate(obj.data.vertices)
              if list(v.co) != before['owned'][obj.name]['mesh_positions'][i]]
    current_world = world_points(obj)
    report['shirts'][obj.name] = {'changed_vertices': len(actual),
                                 'max_displacement_m': max((current_world[i] - Vector(source[i])).length for i in actual),
                                 'exact_trim_guard_vertices': len(pinned)}
bpy.context.view_layer.update()
after = facts()
assert set(before['objects']) == set(after['objects'])
changed = []
for name, row in before['objects'].items():
    candidate = after['objects'][name]
    if row == candidate:
        continue
    changed.append(name)
    assert name in OWNED, ('Unowned data changed', name)
    assert {k: v for k, v in row.items() if k != 'geometry_sha256'} == {k: v for k, v in candidate.items() if k != 'geometry_sha256'}, name
    for key, value in before['owned'][name].items():
        if key != 'mesh_positions':
            assert value == after['owned'][name][key], (name, key)
    assert all(before['owned'][name]['mesh_positions'][i] == after['owned'][name]['mesh_positions'][i] for i in pinned)
assert set(changed) == set(OWNED)
report['actual_changed_objects'] = changed
report['protected_objects'] = len(before['objects']) - len(changed)
report['topology_weights_uv_materials_rig_other_objects_exact'] = True
assert hashlib.sha256(args.source.read_bytes()).hexdigest() == source_sha
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
report['output_sha256'] = hashlib.sha256(args.output.read_bytes()).hexdigest()
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('GARMENT_AUTHORED', json.dumps({k: v for k, v in report.items() if k not in ('profile', 'pinned_ids')}), flush=True)
