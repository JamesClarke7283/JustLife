"""Render native eye-tilt extremes with the same fixed camera and light."""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import KEY, expanded

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--output-root', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(a.source.resolve()))
head = bpy.data.objects['Skin_Head_continuous']
points = [head.matrix_world @ v.co for v in head.data.vertices]
lo, hi = min(v.z for v in points), max(v.z for v in points)
focus = Vector((0., -.065, (lo + hi) * .5))
for obj in bpy.data.objects:
    if obj.type in ('MESH', 'CURVE'):
        obj.hide_render = not obj.name.startswith(('Skin_Head', 'Skin_Nose', 'Skin_Ear',
            'Eyes_', 'Hair_Brow', 'Lash_', 'Nose_', 'Lips_', 'Ear_', 'Jewelry'))
    if obj.type == 'LIGHT':
        obj.hide_render = True
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
scene.cycles.samples = 16; scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 480
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
for name, offset, energy, size in [('Tilt_Key', (.25, -.5, .35), 20, .12),
                                  ('Tilt_Fill', (-.3, -.25, .02), 5, .22)]:
    light = bpy.data.lights.new(name, 'AREA'); light.energy, light.size = energy, size
    obj = bpy.data.objects.new(name, light); scene.collection.objects.link(obj)
    obj.location = focus + Vector(offset)
    obj.rotation_euler = (focus - obj.location).to_track_quat('-Z', 'Y').to_euler()
data = bpy.data.cameras.new('Tilt_Review'); data.type = 'ORTHO'; data.ortho_scale = .30
camera = bpy.data.objects.new('Tilt_Review', data); scene.collection.objects.link(camera)
camera.location = focus + Vector((0, -2.4, .015))
camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = camera
a.output_root.mkdir(parents=True, exist_ok=True)
for label, tilt, blink in [('negative', -1., 0.), ('neutral', 0., 0.),
                            ('positive', 1., 0.), ('positive_blink', 1., 1.)]:
    output = a.output_root / (label + '.png')
    assert not output.exists(), ('Preserve earlier review frame', output)
    values = expanded({KEY: tilt, 'Blink': blink})
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                key.value = values.get(key.name, 0.)
    bpy.context.view_layer.update()
    scene.render.filepath = str(output.resolve())
    bpy.ops.render.render(write_still=True)
    print('EYE_TILT_RENDERED', label, str(output.resolve()), flush=True)
