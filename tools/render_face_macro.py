"""Render tight facial crops (eyes, nose, mouth) plus a matched head view.

Evidence only. The game never loads these frames; no source file is modified.

    blender -b --python tools/render_face_macro.py -- \
        --source art/characters.blend --prefix evidence/face61/before_adult

Each crop is framed from the live production objects so the same tool can
compare a before and an after source at identical camera positions.
"""
import argparse
import pathlib
import sys

import bpy
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--prefix', type=pathlib.Path, required=True)
parser.add_argument('--engine', choices=['eevee', 'cycles'], default='cycles')
parser.add_argument('--samples', type=int, default=24)
parser.add_argument('--width', type=int, default=640)
parser.add_argument('--height', type=int, default=480)
parser.add_argument('--hair', default='Hair_Bob', help='hairstyle to keep visible')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

HAIR_PREFIXES = ('Hair_Bob', 'Hair_Buzz', 'Hair_Crop', 'Hair_Pony', 'Hair_Long',
                 'Hair_Curls', 'Curls')


def world_center(name_prefixes):
    """Average world origin of every mesh whose name starts with a prefix."""
    points = []
    for obj in bpy.data.objects:
        if obj.type != 'MESH':
            continue
        if any(obj.name.startswith(p) for p in name_prefixes):
            points.append(obj.matrix_world.translation)
    if not points:
        return None
    total = Vector((0.0, 0.0, 0.0))
    for point in points:
        total += point
    return total / len(points)


def stage(engine, samples):
    scene = bpy.context.scene
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and obj.name.startswith(HAIR_PREFIXES):
            keep = obj.name.startswith(args.hair)
            obj.hide_render = not keep
            obj.hide_viewport = not keep
            if hasattr(obj, 'hide_set'):
                obj.hide_set(not keep)

    if engine == 'eevee':
        for candidate in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
            try:
                scene.render.engine = candidate
                break
            except TypeError:
                continue
        try:
            scene.eevee.taa_render_samples = samples
        except AttributeError:
            pass
    else:
        scene.render.engine = 'CYCLES'
        scene.cycles.samples = samples
        scene.cycles.device = 'CPU'

    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'

    # Neutral three-point fill so surface detail is legible at close range.
    for name, offset in (('Macro_key', (0.35, -0.55, 0.32)),
                         ('Macro_fill', (-0.45, -0.40, 0.10)),
                         ('Macro_rim', (0.0, 0.35, 0.28))):
        if bpy.data.objects.get(name):
            continue
        light = bpy.data.lights.new(name, 'AREA')
        light.energy = 22.0 if name == 'Macro_key' else 11.0
        light.size = 0.35
        node = bpy.data.objects.new(name, light)
        scene.collection.objects.link(node)
        target = Vector((0.0, 0.0, 1.58)) + Vector(offset)
        node.location = target
        aim = bpy.data.objects.new(name + '_aim', None)
        scene.collection.objects.link(aim)
        aim.location = Vector((0.0, -0.02, 1.58))
        track = node.constraints.new('TRACK_TO')
        track.target = aim
        track.track_axis = 'TRACK_NEGATIVE_Z'
        track.up_axis = 'UP_Y'


def view(location, target, scale):
    scene = bpy.context.scene
    data = bpy.data.cameras.new('macro_probe')
    data.lens = 65
    data.type = 'ORTHO'
    data.ortho_scale = scale
    cam = bpy.data.objects.new('macro_cam', data)
    scene.collection.objects.link(cam)
    cam.location = location
    aim = bpy.data.objects.new('macro_aim', None)
    scene.collection.objects.link(aim)
    aim.location = target
    track = cam.constraints.new('TRACK_TO')
    track.target = aim
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'
    scene.camera = cam
    return cam


def shoot(label, focus, scale, tilt=0.0):
    """Render one crop framed on `focus`; tilt moves the camera up/down."""
    scene = bpy.context.scene
    cam = view((focus.x, focus.y - 2.4, focus.z + tilt), focus, scale)
    scene.render.filepath = str(args.prefix) + '_' + label + '.png'
    bpy.ops.render.render(write_still=True)
    print('RENDERED', args.prefix.name, label)
    for obj in bpy.data.objects:
        if obj.name in ('macro_cam', 'macro_aim'):
            bpy.data.objects.remove(obj, do_unlink=True)


def world_bounds(name):
    """World-space bounding box of one named mesh, or None."""
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != 'MESH':
        return None
    corners = [obj.matrix_world @ v.co for v in obj.data.vertices]
    if not corners:
        return None
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return lo, hi


def front_y(names):
    """Frontmost (most negative Y) surface point of the named meshes."""
    values = []
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != 'MESH':
            continue
        values.extend((obj.matrix_world @ v.co).y for v in obj.data.vertices)
    return min(values) if values else 0.0


bpy.ops.wm.open_mainfile(filepath=str(args.source))
stage(args.engine, args.samples)

# Frame from real mesh bounds: object origins sit inside the skull and are not
# a usable reference for a head crop.
head_bounds = world_bounds('Skin_Head_continuous')
eye_bounds = world_bounds('Eyes_Sclera')
mouth_bounds = world_bounds('Lips_Upper_soft')
assert head_bounds, 'Skin_Head_continuous not found; cannot frame the crops'
head_lo, head_hi = head_bounds
head_height = head_hi.z - head_lo.z
head_center_x = (head_lo.x + head_hi.x) * 0.5
# Crop planes sit just in front of the named features so nothing else occludes.
eye_front = front_y(('Eyes_Sclera', 'Eyes_Iris'))
mouth_front = front_y(('Lips_Upper_soft', 'Lips_Lower_soft'))
face_front = min(eye_front, mouth_front) - 0.02

eye_z = (eye_bounds[0].z + eye_bounds[1].z) * 0.5 if eye_bounds else head_lo.z + head_height * 0.72
mouth_z = (mouth_bounds[0].z + mouth_bounds[1].z) * 0.5 if mouth_bounds else head_lo.z + head_height * 0.30

print('FRAMING', {'head_lo': tuple(head_lo), 'head_hi': tuple(head_hi),
                  'eye_z': eye_z, 'mouth_z': mouth_z, 'front': face_front})

# Orthographic framing ignores depth, so each crop is centred straight on the
# feature line and read from the front.
shoot('eyes', Vector((head_center_x, face_front, eye_z)), 0.155)
shoot('mouth', Vector((head_center_x, face_front, mouth_z)), 0.130)
shoot('face', Vector((head_center_x, face_front, (eye_z + mouth_z) * 0.5)), 0.250)
shoot('head', Vector((head_center_x, face_front, head_lo.z + head_height * 0.55)), 0.360)
bpy.context.scene.render.filepath = str(args.prefix) + '_three_quarter.png'
bpy.ops.render.render(write_still=True)
print('RENDERED', args.prefix.name, 'three_quarter')
print('FACE_MACRO_COMPLETE', args.prefix)
