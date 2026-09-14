"""Native garment inspection helpers; no shipped source mutation."""
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector, kdtree

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'child_shirt_v31'))
import source_facts

OWNED = ('Outfit_Casual_Shirt', 'Outfit_Tee_Shirt')
source_facts.OWNED = set(OWNED)


def facts():
    return source_facts.objects()


def world_points(obj, evaluated=False):
    if not evaluated:
        return [obj.matrix_world @ v.co for v in obj.data.vertices]
    ob = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = ob.to_mesh()
    ps = [ob.matrix_world @ v.co for v in mesh.vertices]
    ob.to_mesh_clear()
    return ps


def bounds(ps):
    return {'min': [min(p[i] for p in ps) for i in range(3)],
            'max': [max(p[i] for p in ps) for i in range(3)]}


def smooth(a, b, value):
    t = max(0., min(1., (value - a) / (b - a)))
    return t * t * (3. - 2. * t)


def gaussian(value, center, radius):
    return math.exp(-((value - center) / radius) ** 2)


def trim_objects():
    return [o for o in bpy.data.objects if o.type == 'MESH'
            and o.name.startswith(('Outfit_Casual_', 'Outfit_Tee_'))
            and any(word in o.name for word in ('Collar_binding', 'Front_placket', 'Sleeve_cuff', 'Hem'))]


def trim_tree():
    ps = [p for obj in trim_objects() for p in world_points(obj)]
    assert ps
    tree = kdtree.KDTree(len(ps))
    for i, p in enumerate(ps):
        tree.insert(p, i)
    tree.balance()
    return tree


def rig_anchors():
    rig = bpy.data.objects['LifeRig']
    return {name: rig.matrix_world @ rig.data.bones[name].head_local
            for name in ('Spine', 'Arm_L', 'Arm_R', 'Forearm_L', 'Forearm_R')}


POSES = {
    'rest': {},
    'walk': {'Arm_L': ('X', .30), 'Arm_R': ('X', -.30),
             'Forearm_L': ('X', -.15), 'Forearm_R': ('X', -.25)},
    'reach': {'Arm_L': ('X', -.55), 'Arm_R': ('X', -.55),
              'Forearm_L': ('X', -.70), 'Forearm_R': ('X', -.70)},
    'arms_out': {'Arm_L': ('Y', .70), 'Arm_R': ('Y', -.70)},
    'one_arm_raised': {'Arm_R': ('Y', -1.05), 'Forearm_R': ('X', -.50)},
}


def capture_pose():
    return {bone.name: bone.matrix_basis.copy() for bone in bpy.data.objects['LifeRig'].pose.bones}


def set_pose(name, original):
    rig = bpy.data.objects['LifeRig']
    for bone in rig.pose.bones:
        bone.matrix_basis = original[bone.name].copy()
    for name, (axis, angle) in POSES[name].items():
        bone = rig.pose.bones[name]
        frame = bone.bone.matrix_local.to_3x3()
        rotation = frame.inverted() @ Matrix.Rotation(angle, 3, axis) @ frame
        bone.matrix_basis = original[name] @ rotation.to_4x4()
    bpy.context.view_layer.update()
