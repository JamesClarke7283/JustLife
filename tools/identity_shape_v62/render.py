"""Same-camera head diagnostic; source neutral geometry is never saved."""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import Geometry, NEW

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--angle', type=float, default=0.)
ap.add_argument('--values', default='')
ap.add_argument('--compare-extremes', action='store_true',
                help='Render negative and positive endpoints from one loaded scene.')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
values = dict((k, float(v)) for k, v in (item.split('=') for item in args.values.split(',') if item))
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
g = Geometry()
focus = Vector((g.eye.x, g.eye.y, g.eye.z - g.face_height * .35))
for o in list(bpy.data.objects):
    if o.type in ('MESH', 'CURVE'):
        keep = o.name.startswith(('Skin_Head', 'Skin_Upper_lid', 'Skin_Nose', 'Eyes_',
                                   'Hair_Brow', 'Lash_', 'Nose_', 'Lips_', 'Ear_', 'Jewelry_'))
        o.hide_render = not keep
    if o.type == 'LIGHT':
        o.hide_render = True
    if o.type == 'MESH' and o.data.shape_keys:
        for k in o.data.shape_keys.key_blocks:
            k.value = values.get(k.name, 0.)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.resolution_x = 440
scene.render.resolution_y = 560
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
for name, offset, energy in [('Identity_Key', (.30, -.42, .30), 16.),
                              ('Identity_Fill', (-.40, -.30, .10), 7.)]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size = energy, 'DISK', .40
    o = bpy.data.objects.new(name, data)
    scene.collection.objects.link(o)
    o.location = focus + Vector(offset)
    o.rotation_euler = (focus - o.location).to_track_quat('-Z', 'Y').to_euler()
data = bpy.data.cameras.new('Identity_Diagnostic')
data.type = 'ORTHO'
data.ortho_scale = g.ipd * 4.20
camera = bpy.data.objects.new('Identity_Diagnostic', data)
scene.collection.objects.link(camera)
angle = math.radians(args.angle)
camera.location = focus + Vector((math.sin(angle) * 2.4, -math.cos(angle) * 2.4, .015))
camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = camera
args.output.parent.mkdir(parents=True, exist_ok=True)
cases = [('negative', dict.fromkeys(NEW, -1.)), ('positive', dict.fromkeys(NEW, 1.))] if args.compare_extremes else [('', values)]
for label, case in cases:
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.data.shape_keys:
            for k in o.data.shape_keys.key_blocks:
                k.value = case.get(k.name, 0.)
    output = args.output.with_stem(args.output.stem + '_' + label) if label else args.output
    scene.render.filepath = str(output.resolve())
    bpy.ops.render.render(write_still=True)
    print('IDENTITY_DIAGNOSTIC_RENDERED', output, flush=True)
