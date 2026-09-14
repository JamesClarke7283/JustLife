"""Render a tight crop of one hand, from several angles.

    blender -b --python tools/render_hand_probe.py -- \
        --source art/characters.blend --prefix /tmp/hand

Evidence only. The arm is posed with the authored rest pose, so the digits (if
any) are visible instead of overlapping the thigh.
"""
import argparse
import pathlib
import sys
from math import radians

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--prefix', type=pathlib.Path, required=True)
parser.add_argument('--side', default='L', choices=['L', 'R'])
parser.add_argument('--samples', type=int, default=32)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

HAIR_PREFIXES = ('Hair_Bob', 'Hair_Buzz', 'Hair_Crop', 'Hair_Pony', 'Hair_Long',
                 'Hair_Curls', 'Hair_Waves', 'Hair_Bun', 'Curls')

bpy.ops.wm.open_mainfile(filepath=str(args.source))
scene = bpy.context.scene

# Hide every garment and hairstyle so the hand is unobstructed.
for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    if obj.name.startswith(HAIR_PREFIXES) or obj.name.startswith('Outfit_') \
            or obj.name.startswith('Bottom_') or obj.name.startswith('Shoes_'):
        obj.hide_render = True
        obj.hide_viewport = True
        if hasattr(obj, 'hide_set'):
            obj.hide_set(True)

# Frame from the authored finger/palm parts when present, else the arm's end.
mtx = bpy.data.objects[f'Skin_Arm_continuous_{args.side}'].matrix_world
marks = []
for candidate in ('Skin_Palm_' + args.side, 'Skin_Finger_' + args.side + '0',
                  'Skin_Finger_' + args.side + '1', 'Skin_Finger_' + args.side + '2',
                  'Skin_Finger_' + args.side + '3', 'Skin_Thumb_' + args.side):
    child = bpy.data.objects.get(candidate)
    if child is not None:
        marks.extend(mtx @ v.co for v in child.data.vertices)
if not marks:
    print('HAND_PROBE: no authored hand parts found; frame the arm end')
    arm = [mtx @ v.co for v in bpy.data.objects[f'Skin_Arm_continuous_{args.side}'].data.vertices]
    zs = sorted(p.z for p in arm)
    z_lo = zs[0]
    marks = [p for p in arm if p.z <= z_lo + 0.15]

centre = sum(marks, Vector()) / len(marks)
reach = max((p - centre).length for p in marks)
print(f'HAND_PROBE centre=({centre.x:+.4f},{centre.y:+.4f},{centre.z:+.4f}) '
      f'reach={reach:.4f} m over {len(marks)} verts')

scene.render.engine = 'CYCLES'
scene.cycles.samples = args.samples
scene.cycles.device = 'CPU'
scene.render.resolution_x = 720
scene.render.resolution_y = 720
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'

for name, offset in (('Hand_key', (0.30, -0.34, 0.16)),
                     ('Hand_fill', (-0.30, -0.22, 0.04)),
                     ('Hand_rim', (0.02, 0.30, 0.14))):
    light = bpy.data.lights.new(name, 'AREA')
    light.energy = 14.0 if name == 'Hand_key' else 6.0
    light.size = 0.25
    node = bpy.data.objects.new(name, light)
    scene.collection.objects.link(node)
    node.location = centre + Vector(offset)
    aim = bpy.data.objects.new(name + '_aim', None)
    scene.collection.objects.link(aim)
    aim.location = centre
    track = node.constraints.new('TRACK_TO')
    track.target = aim
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'

scale = max(0.10, reach * 2.5)


def shoot(label, location, target, ortho):
    data = bpy.data.cameras.new('hand_probe')
    data.lens = 70
    data.type = 'ORTHO'
    data.ortho_scale = ortho
    cam = bpy.data.objects.new('hand_cam', data)
    scene.collection.objects.link(cam)
    cam.location = location
    aim = bpy.data.objects.new('hand_aim', None)
    scene.collection.objects.link(aim)
    aim.location = target
    track = cam.constraints.new('TRACK_TO')
    track.target = aim
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'
    scene.camera = cam
    scene.render.filepath = str(args.prefix) + '_' + label + '.png'
    bpy.ops.render.render(write_still=True)
    print('RENDERED', args.prefix.name, label)
    for obj in (cam, aim):
        bpy.data.objects.remove(obj, do_unlink=True)


sign = -1.0 if args.side == 'L' else 1.0
# Front (looking from -Y), the side the digits would splay toward, and a
# straight-down-the-fingers view where separation is most visible.
shoot('front', centre + Vector((0.0, -0.9, 0.0)), centre, scale)
shoot('three_quarter', centre + Vector((sign * 0.6, -0.7, 0.25)), centre, scale)
shoot('tips', centre + Vector((0.0, -0.55, -0.75)), centre, scale * 0.85)
print('HAND_PROBE_COMPLETE', args.prefix)
