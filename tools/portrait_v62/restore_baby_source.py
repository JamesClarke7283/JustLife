"""Restore the missing baby source using its exact released authoring recipe.

This imports the matching generator's build() function without invoking its
production-writing main(). All output is placed in the supplied candidate
directory. A baseline GLB is retained for decoded comparison with the release.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import bpy

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--output', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
root_path = Path(__file__).resolve().parents[2]
source = root_path / 'tools/baby_v60/create_baby.py'
manifest = json.loads((source.parent / 'manifest.json').read_text())
assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest['generator_sha256']
assert hashlib.sha256((source.parent / 'crawl_pose.py').read_bytes()).hexdigest() == manifest['pose_spec_sha256']
sys.path.insert(0, str(source.parent))
sys.argv = [str(source)]
spec = importlib.util.spec_from_file_location('portrait_baby_recipe', source)
recipe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipe)
root, rig, hair_groups, studio = recipe.build()
recipe.ensure_uvs()
recipe.reset_expressions()
args.output.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str((args.output / 'characters_baby.blend').resolve()))
bpy.ops.object.select_all(action='DESELECT')
for obj in recipe.descendants(root):
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(filepath=str((args.output / 'character_baby.glb').resolve()),
                          export_format='GLB', use_selection=True, export_apply=True,
                          export_yup=True, export_animations=False, export_morph=True,
                          export_skins=True, export_extras=True, export_cameras=False, export_lights=False)
print('BABY_SOURCE_RESTORED', args.output)
