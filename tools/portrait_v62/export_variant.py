"""Export one reviewed portrait source using the released family conventions."""
import argparse
import hashlib
import os
from pathlib import Path
import sys
import tempfile

import bpy

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--source-sha256', required=True)
ap.add_argument('--output-root', type=Path, required=True)
ap.add_argument('--variant', choices=[b + s for b in ('character', 'character_child', 'character_teen', 'character_elder', 'character_baby')
                                    for s in ('', '_broad', '_lod', '_broad_lod')], required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert hashlib.sha256(args.source.read_bytes()).hexdigest() == args.source_sha256
destination = args.output_root.resolve() / (args.variant + '.glb')
assert not destination.exists(), 'Refuse existing variant destination'
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
root = bpy.data.objects['Character']
baby = str(root.get('age_stage', '')) == 'baby'
root.scale.x = 1.12 if 'broad' in args.variant else 1.0


def descendants(obj):
    yield obj
    for child in obj.children:
        yield from descendants(child)


for obj in descendants(root):
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            key.value = 0
    if args.variant.endswith('_lod'):
        if obj.type == 'MESH' and obj.data.shape_keys is None:
            mod = obj.modifiers.new('Live camera reduction', 'DECIMATE')
            if baby:
                mod.ratio = .32 if 'Head' in obj.name or 'Body' in obj.name else .40
            else:
                mod.ratio = .12 if obj.name.endswith('_Cap') else (.38 if 'Leg' in obj.name else .22)
            if obj.modifiers.find('Soft skeletal deformation') >= 0:
                bpy.context.view_layer.objects.active = obj
                bpy.ops.object.modifier_move_up(modifier=mod.name)
        elif obj.type == 'CURVE' and not baby:
            obj.data.resolution_u = 2
            obj.data.bevel_resolution = 1
for bone in bpy.data.objects['LifeRig'].pose.bones:
    bone.rotation_euler = (0, 0, 0)
bpy.ops.object.select_all(action='DESELECT')
for obj in descendants(root):
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.context.view_layer.update()
bpy.context.evaluated_depsgraph_get().update()
args.output_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='.portrait-export-', dir=args.output_root) as temporary:
    path = Path(temporary) / destination.name
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True, export_animations=False,
                              export_morph=True, export_skins=True, export_extras=True,
                              export_cameras=False, export_lights=False)
    os.replace(path, destination)
print('PORTRAIT_VARIANT_EXPORTED', args.variant, hashlib.sha256(destination.read_bytes()).hexdigest())
