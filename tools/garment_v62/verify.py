"""Fresh native preservation and real-armature pose checks for both shirts."""
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
from common import OWNED, POSES, capture_pose, facts, rig_anchors, set_pose, trim_tree, world_points

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])


def gather():
    """Actual evaluated meshes from the unchanged weighted armature, not a mock."""
    original = capture_pose()
    result = {}
    skin_objects = [o for o in bpy.data.objects if o.type == 'MESH'
                    and o.name.startswith('Skin_Arm_continuous')]
    # Shirt sleeves should cover these upper-arm vertices. Lower exposed arm,
    # cuffs and hands are deliberately not classified as garment penetrations.
    anchors = rig_anchors()
    scale = abs(anchors['Arm_R'].x) / .18
    selection = {o.name: [i for i, p in enumerate(world_points(o))
                         if anchors['Forearm_R'].z + .095 * scale < p.z
                         and p.z < anchors['Arm_R'].z + .006 * scale]
                 for o in skin_objects}
    for pose in POSES:
        set_pose(pose, original)
        shirts = {name: np.asarray([p[:] for p in world_points(bpy.data.objects[name], True)], dtype=np.float64)
                  for name in OWNED}
        skin = {}
        for o in skin_objects:
            ps = world_points(o, True)
            skin[o.name] = [ps[i] for i in selection[o.name]]
        result[pose] = {'shirts': shirts, 'skin': skin}
        print('GARMENT_POSE_EVALUATED', pose, flush=True)
    set_pose('rest', original)
    return result


def signed_skin_distance(cloth, triangles, skin):
    tree = BVHTree.FromPolygons([Vector(p) for p in cloth], triangles, all_triangles=True)
    distances = []
    for name in sorted(skin):
        for p in skin[name]:
            hit, normal, _, _ = tree.find_nearest(p)
            assert hit is not None
            distances.append((p - hit).dot(normal))
    return np.asarray(distances)


baseline_sha = hashlib.sha256(args.baseline.read_bytes()).hexdigest()
candidate_sha = hashlib.sha256(args.candidate.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(args.baseline.resolve()))
bpy.context.view_layer.update()
before = facts()
print('GARMENT_BASELINE_SNAPSHOTTED', len(before['objects']), 'objects', flush=True)
scale = abs(rig_anchors()['Arm_R'].x) / .18
tree = trim_tree()
pinned = {name: [i for i, p in enumerate(world_points(bpy.data.objects[name]))
                 if tree.find(p)[2] <= .009 * scale] for name in OWNED}
triangles = {}
for name in OWNED:
    obj = bpy.data.objects[name]
    obj.data.calc_loop_triangles()
    triangles[name] = [tuple(t.vertices) for t in obj.data.loop_triangles]
old_poses = gather()
bpy.ops.wm.open_mainfile(filepath=str(args.candidate.resolve()))
bpy.context.view_layer.update()
after = facts()
print('GARMENT_CANDIDATE_SNAPSHOTTED', len(after['objects']), 'objects', flush=True)
failures = []
assert set(before['objects']) == set(after['objects'])
changed = []
for name, source in before['objects'].items():
    candidate = after['objects'][name]
    if source == candidate:
        continue
    changed.append(name)
    assert name in OWNED, ('Protected object changed on fresh reopen', name)
    assert {k: v for k, v in source.items() if k != 'geometry_sha256'} == {k: v for k, v in candidate.items() if k != 'geometry_sha256'}, name
    for key, value in before['owned'][name].items():
        if key != 'mesh_positions':
            assert value == after['owned'][name][key], (name, key)
    assert all(before['owned'][name]['mesh_positions'][i] == after['owned'][name]['mesh_positions'][i] for i in pinned[name])
assert set(changed) == set(OWNED)
new_poses = gather()
checks = []
for pose in POSES:
    for name in OWNED:
        a, b = old_poses[pose]['shirts'][name], new_poses[pose]['shirts'][name]
        ids = np.asarray(triangles[name], dtype=np.int32)
        n0 = np.cross(a[ids[:, 1]] - a[ids[:, 0]], a[ids[:, 2]] - a[ids[:, 0]])
        n1 = np.cross(b[ids[:, 1]] - b[ids[:, 0]], b[ids[:, 2]] - b[ids[:, 0]])
        area0, area1 = np.linalg.norm(n0, axis=1), np.linalg.norm(n1, axis=1)
        valid = area0 > 1e-12
        flips = int(np.count_nonzero(np.sum(n0[valid] * n1[valid], axis=1) < 0))
        minimum = float(np.min(area1[valid] / area0[valid]))
        if flips or minimum < .05:
            failures.append([pose, name, 'triangle_orientation_or_area', flips, minimum])
        skin_before = signed_skin_distance(a, triangles[name], old_poses[pose]['skin'])
        skin_after = signed_skin_distance(b, triangles[name], new_poses[pose]['skin'])
        new_exposure = (skin_after > .0005 * scale) & (skin_after > np.maximum(skin_before, 0.) + .0005 * scale)
        exposed = int(np.count_nonzero(new_exposure))
        if exposed:
            failures.append([pose, name, 'new_upper_arm_exposure', exposed,
                             float(np.max(skin_after[new_exposure]))])
        checks.append({'pose': pose, 'shirt': name, 'triangles_tested': int(np.count_nonzero(valid)),
                       'orientation_reversals_from_same_source_pose': flips,
                       'minimum_triangle_area_ratio': minimum,
                       'protected_trim_vertex_count': len(pinned[name]),
                       'upper_arm_skin_samples': len(skin_after),
                       'source_skin_vertices_outside_cloth_over_0_5mm': int(np.count_nonzero(skin_before > .0005 * scale)),
                       'candidate_skin_vertices_outside_cloth_over_0_5mm': int(np.count_nonzero(skin_after > .0005 * scale)),
                       'new_or_worsened_upper_arm_exposure': exposed,
                       'max_skin_distance_increase_m': float(np.max(skin_after - skin_before))})
assert hashlib.sha256(args.baseline.read_bytes()).hexdigest() == baseline_sha
assert hashlib.sha256(args.candidate.read_bytes()).hexdigest() == candidate_sha
report = {'baseline': str(args.baseline.resolve()), 'baseline_sha256': baseline_sha,
          'candidate': str(args.candidate.resolve()), 'candidate_sha256': candidate_sha,
          'changed_objects': changed, 'protected_objects': len(before['objects']) - len(changed),
          'input_garment_geometry_sha256': {name: before['objects'][name]['geometry_sha256'] for name in OWNED},
          'output_garment_geometry_sha256': {name: after['objects'][name]['geometry_sha256'] for name in OWNED},
          'fresh_reopen_exact_topology_uv_weights_rig_material_assignments_other_objects': True,
          'pose_checks': checks, 'failures': failures, 'passed': not failures,
          'limits': 'Compared with identical source poses using actual ARMATURE evaluation. Existing source intersections are reported separately; this is not arbitrary-pose cloth simulation.'}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('GARMENT_' + ('PASS' if not failures else 'FAIL'), len(checks), 'pose checks', len(failures), 'failures', args.report, flush=True)
assert not failures, failures[:10]
