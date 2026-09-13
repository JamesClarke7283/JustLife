"""Export one character GLB variant from a candidate blend, in a fresh process.

Mirrors tools/create_wardrobe.py export_variant exactly: rest pose, zeroed
morphs, broad x-scale 1.12, live-LOD decimation (caps 0.12, leg pieces 0.38,
everything else 0.22) and the qualified glTF export call.

    blender --background --python tools/hair_lock_v60/export_variant.py -- \
        --source <blend> --output-root <dir> --variant character_lod
"""
import bpy, argparse, hashlib, os, sys, tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--source-sha256', required=True)
parser.add_argument('--output-root', type=Path, required=True)
parser.add_argument('--variant',
                    choices=[b + s for b in ('character', 'character_child', 'character_teen', 'character_elder')
                             for s in ('', '_broad', '_lod', '_broad_lod')], required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
blend = args.source.resolve()
assert hashlib.sha256(blend.read_bytes()).hexdigest() == args.source_sha256, 'Candidate blend hash mismatch'
assert not (args.output_root.resolve() / (args.variant + '.glb')).exists(), 'Refuse existing variant destination'

def descendants(node):
    yield node
    for child in node.children:
        yield from descendants(child)

width = 1.12 if 'broad' in args.variant else 1.0
low = args.variant.endswith('_lod')
bpy.ops.wm.open_mainfile(filepath=str(blend))
D = bpy.data
root = D.objects['Character']
root.scale.x = width
for o in descendants(root):
    if o.type == 'MESH' and o.data.shape_keys:
        for key in o.data.shape_keys.key_blocks:
            key.value = 0
    if low:
        if o.type == 'MESH' and o.data.shape_keys is None:
            mod = o.modifiers.new('Live camera reduction', 'DECIMATE')
            mod.ratio = .12 if o.name.endswith('_Cap') else (.38 if 'Leg' in o.name else .22)
            if o.modifiers.find('Soft skeletal deformation') >= 0:
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.modifier_move_up(modifier=mod.name)
        elif o.type == 'CURVE':
            o.data.resolution_u = 2
            o.data.bevel_resolution = 1
for bone in D.objects['LifeRig'].pose.bones:
    bone.rotation_euler = (0, 0, 0)
bpy.ops.object.select_all(action='DESELECT')
for o in descendants(root):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.context.view_layer.update()
bpy.context.evaluated_depsgraph_get().update()
out = args.output_root.resolve()
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='.export-', dir=out) as folder:
    path = Path(folder) / (args.variant + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_morph=True, export_skins=True,
                              export_extras=True, export_cameras=False, export_lights=False)
    os.replace(path, out / path.name)
print('VARIANT_EXPORTED', args.variant, hashlib.sha256((out / (args.variant + '.glb')).read_bytes()).hexdigest())
