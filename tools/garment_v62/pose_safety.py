"""Local proposal backtracking measured from the actual weighted armature.

For fixed weights and a fixed pose, an ARMATURE modifier is affine in each
vertex position. Evaluate the original and proposed garment in Blender, then
interpolate those measured positions while finding a smooth local limit.
The final saved result still requires fresh independent native verification.
"""
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from common import POSES, capture_pose, rig_anchors, set_pose, world_points


def pose_channels():
    return {b.name: {key: tuple(getattr(b, key)) for key in
            ('location', 'scale', 'rotation_euler', 'rotation_quaternion', 'rotation_axis_angle')}
            for b in bpy.data.objects['LifeRig'].pose.bones}


def restore_channels(channels):
    for b in bpy.data.objects['LifeRig'].pose.bones:
        for key, value in channels[b.name].items():
            setattr(b, key, value)
    bpy.context.view_layer.update()


def nearest_skin(cloth, triangles, samples):
    tree = BVHTree.FromPolygons([Vector(p) for p in cloth], triangles.tolist(), all_triangles=True)
    distances, faces = [], []
    for p in samples:
        hit, normal, face, _ = tree.find_nearest(p)
        assert hit is not None
        distances.append((p - hit).dot(normal))
        faces.append(face)
    return np.asarray(distances), np.asarray(faces, dtype=np.int32)


def constrain(obj, source, proposed, triangles, edges, scale):
    assert len(obj.modifiers) == 1 and obj.modifiers[0].type == 'ARMATURE'
    assert obj.data.shape_keys is None
    original_pose = capture_pose()
    channels = pose_channels()
    local_source = [v.co.copy() for v in obj.data.vertices]
    world_inverse = obj.matrix_world.to_3x3().inverted()
    proposal = proposed - source
    skin_objects = [o for o in bpy.data.objects if o.type == 'MESH'
                    and o.name.startswith('Skin_Arm_continuous')]
    anchors = rig_anchors()
    selected = {o.name: [i for i, p in enumerate(world_points(o))
                        if anchors['Forearm_R'].z + .095 * scale < p.z
                        and p.z < anchors['Arm_R'].z + .006 * scale]
                for o in skin_objects}
    measured = {}
    try:
        for pose in POSES:
            set_pose(pose, original_pose)
            cloth = np.asarray([p[:] for p in world_points(obj, True)], dtype=np.float64)
            samples = []
            for skin in skin_objects:
                ps = world_points(skin, True)
                samples.extend(ps[i] for i in selected[skin.name])
            distance, _ = nearest_skin(cloth, triangles, samples)
            normals = np.cross(cloth[triangles[:, 1]] - cloth[triangles[:, 0]],
                               cloth[triangles[:, 2]] - cloth[triangles[:, 0]])
            measured[pose] = {'source': cloth, 'skin': samples, 'distance': distance,
                              'normals': normals, 'areas': np.linalg.norm(normals, axis=1)}
        set_pose('rest', original_pose)
        for i, v in enumerate(obj.data.vertices):
            if np.linalg.norm(proposal[i]) > 1e-10:
                v.co = local_source[i] + world_inverse @ Vector(proposal[i])
        obj.data.update()
        for pose in POSES:
            set_pose(pose, original_pose)
            proposed_pose = np.asarray([p[:] for p in world_points(obj, True)], dtype=np.float64)
            measured[pose]['delta'] = proposed_pose - measured[pose]['source']
            print('GARMENT_PROPOSAL_POSE_MEASURED', pose, flush=True)
    finally:
        for i, v in enumerate(obj.data.vertices):
            v.co = local_source[i]
        obj.data.update()
        restore_channels(channels)

    src = np.concatenate((edges[:, 0], edges[:, 1]))
    dst = np.concatenate((edges[:, 1], edges[:, 0]))
    retained = np.ones(len(source))
    limited = set()
    history = []
    for iteration in range(30):
        affected = set()
        row = {'iteration': iteration, 'poses': []}
        for pose, sample in measured.items():
            cloth = sample['source'] + sample['delta'] * retained[:, None]
            normals = np.cross(cloth[triangles[:, 1]] - cloth[triangles[:, 0]],
                               cloth[triangles[:, 2]] - cloth[triangles[:, 0]])
            area = np.linalg.norm(normals, axis=1)
            valid = sample['areas'] > 1e-12
            dot = np.sum(sample['normals'] * normals, axis=1)
            bad = valid & ((dot < .08 * sample['areas'] * area)
                           | (area < .10 * sample['areas']))
            affected.update(int(i) for i in np.unique(triangles[bad]))
            distance, faces = nearest_skin(cloth, triangles, sample['skin'])
            exposure = (distance > .00025 * scale) & (
                distance > np.maximum(sample['distance'], 0.) + .00025 * scale)
            affected.update(int(i) for i in np.unique(triangles[faces[exposure]]))
            row['poses'].append({'pose': pose, 'bad_triangles': int(np.count_nonzero(bad)),
                                 'new_exposure_samples_over_0_25mm': int(np.count_nonzero(exposure))})
        history.append(row)
        print('GARMENT_POSE_LIMIT', iteration, len(affected), 'affected vertices', flush=True)
        if not affected:
            break
        ids = np.array(sorted(affected), dtype=np.int32)
        limited.update(affected)
        retained[ids] *= .5
        # Fade local limits over edge rings; no hard single-vertex dent is
        # introduced to satisfy a numerical pose gate.
        for _ in range(6):
            cap = retained.copy()
            np.minimum.at(cap, src, retained[dst] + .20)
            retained = np.minimum(retained, cap)
    assert not affected, 'Actual-pose local deformation limits did not converge'
    result = source + proposal * retained[:, None]
    return result, {'method': 'affine interpolation of actual native ARMATURE evaluations',
                    'pose_count': len(POSES), 'skin_samples_per_pose': len(next(iter(measured.values()))['skin']),
                    'limited_vertices': len(limited), 'iterations': iteration,
                    'strict_new_exposure_threshold_m': .00025 * scale, 'history': history,
                    'incoming_displacement_sum_m': float(np.sum(np.linalg.norm(proposal, axis=1))),
                    'retained_displacement_sum_m': float(np.sum(np.linalg.norm(result - source, axis=1))),
                    'final_independent_native_verification_required': True}
