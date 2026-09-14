"""Matched whole-face finish diagnostic using evaluated geometry and crisp light."""
import argparse
import math
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--angle', type=float, default=25)
ap.add_argument('--elevation', type=float, default=.477453)
ap.add_argument('--perspective-distance', type=float)
ap.add_argument('--fov', type=float, default=28.)
ap.add_argument('--focus-world', type=float, nargs=3)
ap.add_argument('--resolution', type=int, default=512)
ap.add_argument('--samples', type=int, default=16)
ap.add_argument('--studio-yaw', type=float, help='Use creator light directions inverse-rotated by this actor yaw in radians')
ap.add_argument('--profiles', type=Path)
ap.add_argument('--profile-index', type=int, default=5)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
profile = json.loads(args.profiles.read_text())['generated_profiles'][args.profile_index] if args.profiles else {}
for obj in list(bpy.data.objects):
    if obj.type in ('MESH', 'CURVE'):
        keep = obj.name.startswith(('Skin_Head', 'Skin_Nose', 'Skin_Ear', 'Eyes_', 'Hair_Brow', 'Lash_', 'Nose_', 'Lips_', 'Ear_', 'Jewelry'))
        if not keep:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        obj.hide_render = False
    if obj.type == 'LIGHT':
        obj.hide_render = True
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            key.value = float(profile.get(key.name.lower(), 0)) if key.name != 'Basis' else 0
bpy.context.view_layer.update()
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = args.samples
scene.cycles.use_denoising = True
scene.render.resolution_x = args.resolution
scene.render.resolution_y = args.resolution
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
head = bpy.data.objects['Skin_Head_continuous'].evaluated_get(bpy.context.evaluated_depsgraph_get())
points = [head.matrix_world @ v.co for v in head.data.vertices]
low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
focus = Vector((0, -.065, (low.z + high.z) * .5 - .012))
if args.focus_world:
    focus = Vector(args.focus_world)
lights = [('Finish_Key', (.25, -.50, .35), 20, .065),
          ('Finish_Fill', (-.30, -.25, .02), 5, .22)]
if args.studio_yaw is not None:
    lights = [('Finish_Key', (-1.6, 2.6, 2.8), 300, .18),
              ('Finish_Fill', (1.8, 1.7, 2.), 70, .05),
              ('Finish_Rim', (.5, 2.2, -1.6), 70, .05)]
for name, offset, energy, size in lights:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.size = energy, size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    if args.studio_yaw is None:
        obj.location = focus + Vector(offset)
    else:
        x, y, z = offset
        c, s = math.cos(args.studio_yaw), math.sin(args.studio_yaw)
        obj.location = Vector((c * x - s * z, -(s * x + c * z), y))
    obj.rotation_euler = (focus - obj.location).to_track_quat('-Z', 'Y').to_euler()
data = bpy.data.cameras.new('Finish_Diagnostic')
data.type = 'ORTHO'
data.ortho_scale = .30
if args.perspective_distance:
    data.type = 'PERSP'
    data.lens_unit = 'FOV'
    data.angle = math.radians(args.fov)
camera = bpy.data.objects.new('Finish_Diagnostic', data)
scene.collection.objects.link(camera)
angle = math.radians(args.angle)
distance = args.perspective_distance or 2.4
camera.location = focus + Vector((math.sin(angle) * distance, -math.cos(angle) * distance,
                                  math.tan(math.radians(args.elevation)) * distance))
camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = camera
args.output.parent.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(args.output.resolve())
bpy.ops.render.render(write_still=True)
print('FINISH_RENDERED', args.output)
