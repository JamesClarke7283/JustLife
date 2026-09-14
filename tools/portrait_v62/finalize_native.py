"""Save a neutral export-pose copy, preserving authored object/bone scales."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import sys

import bpy

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve()
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))


def authored_digest():
    digest = hashlib.sha256()
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        digest.update((obj.name + '\0' + obj.type).encode())
        if obj.type != 'MESH':
            continue
        digest.update(json.dumps([m.name if m else None for m in obj.data.materials]).encode())
        for vertex in obj.data.vertices:
            digest.update(struct.pack('<3f', *vertex.co))
            for group in vertex.groups:
                digest.update(struct.pack('<If', group.group, group.weight))
        for polygon in obj.data.polygons:
            digest.update(struct.pack('<I', polygon.material_index))
            digest.update(struct.pack('<' + str(len(polygon.vertices)) + 'I', *polygon.vertices))
        for uv in obj.data.uv_layers:
            digest.update(uv.name.encode())
            for vertex in uv.data:
                digest.update(struct.pack('<2f', *vertex.uv))
        if obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                digest.update(key.name.encode())
                for vertex in key.data:
                    digest.update(struct.pack('<3f', *vertex.co))
    return digest.hexdigest()


before = authored_digest()
changed = []
for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.data.shape_keys:
        continue
    for key in obj.data.shape_keys.key_blocks:
        if key.value != 0:
            changed.append({'object': obj.name, 'key': key.name, 'old_value': key.value})
            key.value = 0.0
    basis = obj.data.shape_keys.key_blocks['Basis']
    assert all(v.co == basis.data[i].co for i, v in enumerate(obj.data.vertices)), obj.name
reset_bones = []
pose_scales = {}
for obj in bpy.data.objects:
    if obj.type != 'ARMATURE':
        continue
    for bone in obj.pose.bones:
        before_location, before_scale = bone.location.copy(), bone.scale.copy()
        pose_scales[obj.name + '/' + bone.name] = list(before_scale)
        if any(v != 0 for v in bone.rotation_euler):
            reset_bones.append(obj.name + '/' + bone.name)
        # Match export_variant.py exactly. An authored bone scale or offset
        # is not animation noise and must never be reset by normalization.
        bone.rotation_euler = (0, 0, 0)
        assert bone.location == before_location and bone.scale == before_scale
assert authored_digest() == before, 'Authored mesh/UV/weight/morph/material data changed'
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
report = {'source': str(args.source), 'output': str(args.output), 'reset_key_values': changed,
          'reset_rotation_euler_bones': reset_bones, 'preserved_pose_bone_scales': pose_scales,
          'authored_data_digest_before_and_after': before,
          'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
          'geometry_changed': False}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('NATIVE_NEUTRALIZED', json.dumps(report))
