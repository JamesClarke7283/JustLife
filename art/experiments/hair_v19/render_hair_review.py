"""Render the original hair study and its production baseline with matched views.

blender -b -t 4 --python art/experiments/hair_v19/render_hair_review.py -- --age adult
Add --baseline for production v18, --quick for previews, --extremes for broad
frame plus combined identity morphs. This never saves or changes loaded sources.
"""
import argparse
import bpy
import hashlib
import json
import sys
from pathlib import Path
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--age', choices=['adult', 'child', 'teen', 'elder'], default='adult')
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--quick', action='store_true')
parser.add_argument('--extremes', action='store_true')
parser.add_argument('--views', nargs='+', default=['front', 'left', 'right', 'threequarter', 'creator'])
parser.add_argument('--styles', nargs='+', default=['bob', 'curls'])
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
stage = Path(__file__).resolve().parent
project = stage.parents[2]
source = project/'art'/('characters.blend' if args.age == 'adult' else f'characters_{args.age}.blend') if args.baseline else stage/f'characters_{args.age}_hair_v19.blend'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source))
root = bpy.data.objects['Character']
scene = bpy.context.scene
camera = scene.camera
scene.render.resolution_percentage = 100
scene.render.resolution_x = scene.render.resolution_y = 600 if args.quick else 900
scene.cycles.samples = 12 if args.quick else 40
scene.cycles.use_denoising = True
ratio = {'adult': 1, 'child': .82, 'teen': .91, 'elder': 1}[args.age]
center = Vector((0, -.008 if args.age != 'elder' else -.04, root['head_height'] + .139*ratio))
views = {'front': (0, -3, .015), 'left': (-3, 0, 0), 'right': (3, 0, 0), 'threequarter': (1.8, -3, .015), 'back': (0, 3, .015), 'creator': (.2, -4, .08)}

def descendants(ob):
    yield ob
    for child in ob.children:
        yield from descendants(child)

for ob in descendants(root):
    if ob.type == 'MESH' and ob.data.shape_keys:
        for key in ob.data.shape_keys.key_blocks:
            if key.name != 'Basis':
                key.value = 1.0 if args.extremes and key.name in ['Face_Round', 'Jaw_Strong', 'Nose_Wide', 'Eye_Spacing'] else 0.0
if args.extremes:
    root.scale.x *= 1.12
    bpy.data.objects['Hair_Bob'].scale.x *= 1.07

revision = 'v18' if args.baseline else f"r{int(root.get('hair_study_revision', 0))}"
rendered = []
camera_records = []
for style in args.styles:
    assert style in ['crop', 'bob', 'curls']
    for name in ['Hair_Crop', 'Hair_Bob', 'Hair_Curls']:
        for ob in descendants(bpy.data.objects[name]):
            ob.hide_render = name.lower() != 'hair_'+style
    for label in args.views:
        target = center.copy()
        camera.data.type = 'ORTHO'
        camera.data.ortho_scale = .47*ratio
        if label == 'creator':
            target = Vector((0, 0, float(root['height_m']) * .49))
            camera.data.ortho_scale = float(root['height_m']) * 1.12
        camera.location = target+Vector(views[label])
        camera.rotation_euler = (target-camera.location).to_track_quat('-Z', 'Y').to_euler()
        suffix = '_broad_identity_max' if args.extremes else ''
        destination = stage/f'{revision}_{args.age}_{style}_{label}{suffix}.png'
        scene.render.filepath = str(destination)
        bpy.ops.render.render(write_still=True)
        rendered.append(destination.name)
        camera_records.append({'image': destination.name, 'location': list(camera.location), 'rotation_euler': list(camera.rotation_euler), 'ortho_scale': camera.data.ortho_scale})
report = {'source': str(source.relative_to(project)), 'source_sha256': source_hash, 'age': args.age, 'baseline': args.baseline, 'broad_identity_extremes': args.extremes, 'render_engine': scene.render.engine, 'samples': scene.cycles.samples, 'resolution': [scene.render.resolution_x, scene.render.resolution_y], 'images': rendered, 'cameras': camera_records, 'lights': {ob.name: {'location': list(ob.location), 'rotation_euler': list(ob.rotation_euler), 'energy': ob.data.energy, 'color': list(ob.data.color)} for ob in bpy.data.objects if ob.type == 'LIGHT'}}
selection = '_'.join(args.styles)+'_'+'_'.join(args.views)
(stage/f'{revision}_{args.age}_{selection}_review{suffix}_preservation.json').write_text(json.dumps(report, indent=2)+'\n')
print('HAIR REVIEW COMPLETE', json.dumps(report))
