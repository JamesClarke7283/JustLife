"""A single lightweight orbital diagnostic render, with optional full Blink."""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--blink', type=float, default=0)
ap.add_argument('--angle', type=float, default=0)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
for obj in list(bpy.data.objects):
    if obj.type in ('MESH', 'CURVE'):
        keep = obj.name.startswith(('Skin_Head', 'Skin_Nose', 'Skin_Upper_lid', 'Eyes_', 'Hair_Brow', 'Lash_', 'Nose_', 'Lips_'))
        if not keep:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        obj.hide_render = False
    if obj.type == 'LIGHT':
        obj.hide_render = True
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            key.value = args.blink if key.name == 'Blink' else 0
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.cycles.use_denoising = True
scene.render.resolution_x = 480
scene.render.resolution_y = 300
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
eye = bpy.data.objects.get('Eyes_Sclera') or bpy.data.objects['Eyes_Sclera_L']
ps = [eye.matrix_world @ v.co for v in eye.data.shape_keys.key_blocks['Basis'].data]
eye_z = (min(p.z for p in ps) + max(p.z for p in ps)) * .5
focus = Vector((0, -.085, eye_z + .003))
for name, offset, energy in [('Orbit_Key', (.24, -.34, .25), 12), ('Orbit_Fill', (-.35, -.20, .08), 8)]:
    light = bpy.data.lights.new(name, 'AREA')
    light.energy = energy
    light.shape = 'DISK'
    light.size = .35
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = focus + Vector(offset)
    obj.rotation_euler = (focus - obj.location).to_track_quat('-Z', 'Y').to_euler()
data = bpy.data.cameras.new('Orbit_Diagnostic')
data.type = 'ORTHO'
data.ortho_scale = .22
camera = bpy.data.objects.new('Orbit_Diagnostic', data)
scene.collection.objects.link(camera)
angle = math.radians(args.angle)
camera.location = focus + Vector((math.sin(angle) * 2.4, -math.cos(angle) * 2.4, .03))
camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = camera
args.output.parent.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(args.output.resolve())
bpy.ops.render.render(write_still=True)
print('ORBIT_RENDERED', args.output)
