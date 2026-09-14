"""Compare evaluated vertex positions, not only raw data, in export pose."""
import argparse
import json
from pathlib import Path
import sys

import bpy
import numpy as np

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--before', type=Path, required=True)
ap.add_argument('--after', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])


def evaluated(path):
    bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    authored_pose = {obj.name + '/' + bone.name: {'matrix_basis': [float(v) for row in bone.matrix_basis for v in row],
                                               'location': list(bone.location), 'scale': list(bone.scale)}
                     for obj in bpy.data.objects if obj.type == 'ARMATURE' for bone in obj.pose.bones}
    head_transform = [float(v) for row in bpy.data.objects['Head'].matrix_world for v in row]
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                key.value = 0
        if obj.type == 'ARMATURE':
            for bone in obj.pose.bones:
                bone.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    result = {}
    for obj in bpy.data.objects:
        if obj.type not in ('MESH', 'CURVE'):
            continue
        ev = obj.evaluated_get(dg)
        mesh = ev.to_mesh()
        flat = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get('co', flat)
        matrix = np.asarray(ev.matrix_world, dtype=np.float64)
        points = flat.reshape((-1, 3)).astype(np.float64) @ matrix[:3, :3].T + matrix[:3, 3]
        result[obj.name] = points
        ev.to_mesh_clear()
    return result, authored_pose, head_transform


before, before_pose, before_head = evaluated(args.before)
after, after_pose, after_head = evaluated(args.after)
assert set(before) == set(after)
assert before_head == after_head, 'Head object transform changed'
for name in before_pose:
    assert before_pose[name]['location'] == after_pose[name]['location'], ('pose location', name)
    assert before_pose[name]['scale'] == after_pose[name]['scale'], ('pose scale', name)
maximum, rows = 0., []
for name, points in before.items():
    target = after[name]
    assert points.shape == target.shape, name
    error = float(np.max(np.linalg.norm(points - target, axis=1))) if len(points) else 0.
    assert error < 1e-7, (name, 'evaluated geometry changed', error)
    maximum = max(maximum, error)
    if name == 'Skin_Head_continuous':
        rows.append({'object': name, 'vertices': len(points), 'before_min': points.min(axis=0).tolist(),
                     'before_max': points.max(axis=0).tolist(), 'after_min': target.min(axis=0).tolist(),
                     'after_max': target.max(axis=0).tolist(), 'maximum_delta_m': error})
report = {'before': str(args.before), 'after': str(args.after), 'evaluated_objects_compared': len(before),
          'maximum_world_vertex_delta_m': maximum, 'head_bounds': rows,
          'head_object_matrix_world_preserved': before_head,
          'before_authored_pose_bones': before_pose, 'after_authored_pose_bones': after_pose}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('EVALUATED_NEUTRAL_EQUIVALENCE_PASS', len(before), 'objects;', maximum, 'm maximum vertex delta')
