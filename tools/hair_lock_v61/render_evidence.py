"""Before/after evidence renders for the hair-lock and hood-seat revision.

    blender --background --python tools/hair_lock_v60/render_evidence.py -- \
        --family adult --before <pinned blend> --after <candidate blend> \
        --out evidence/hair61 [--solo-style Hair_Long]

Renders, per version (before/after): the Bob style in front, three-quarter,
walk, arms_out and arms_forward; Long and Waves in front and three-quarter;
plus a 30-degree side 60 mm collar close-up of the hoodie. Evidence only; the
game never loads these frames.
"""
import bpy, sys, argparse, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--family', choices=['adult', 'child', 'teen', 'elder'], required=True)
parser.add_argument('--before', type=pathlib.Path, required=True)
parser.add_argument('--after', type=pathlib.Path, required=True)
parser.add_argument('--out', type=pathlib.Path, default=ROOT / 'evidence/hair61')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

POSES = {
    'arms_out': {'Arm_L': (-1.45, 0, 0), 'Arm_R': (-1.45, 0, 0), 'Forearm_L': (-.15, 0, 0), 'Forearm_R': (-.15, 0, 0)},
    'arms_forward': {'Arm_L': (-.9, 0, 0), 'Arm_R': (-.9, 0, 0), 'Forearm_L': (-1.0, 0, 0), 'Forearm_R': (-1.0, 0, 0)},
    'walk': {'Leg_L': (-.38, 0, 0), 'Leg_R': (.33, 0, 0), 'Shin_R': (.48, 0, 0), 'Arm_L': (.22, 0, 0),
             'Arm_R': (-.22, 0, 0), 'Forearm_R': (-.22, 0, 0), 'Head': (.02, 0, .08)},
}
HAIR_PREFIXES = ('Hair_Bob', 'Hair_Buzz', 'Hair_Crop', 'Hair_Pony', 'Hair_Long', 'Hair_Curls',
                 'Hair_Waves', 'Hair_Bun', 'Curls')
# (style shown, pose, camera, output stem)
SHOTS = [
    ('Hair_Bob', 'rest', 'front', ''),
    ('Hair_Bob', 'rest', 'three_quarter', ''),
    ('Hair_Bob', 'walk', 'body', ''),
    ('Hair_Bob', 'arms_out', 'body', ''),
    ('Hair_Bob', 'arms_forward', 'body', ''),
    ('Hair_Long', 'rest', 'front', 'long_'),
    ('Hair_Long', 'rest', 'three_quarter', 'long_'),
    ('Hair_Waves', 'rest', 'front', 'waves_'),
    ('Hair_Waves', 'rest', 'three_quarter', 'waves_'),
    ('Hair_Bob', 'rest', 'hood_side30', 'hood_'),
]


def stage(path, style, pose):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    rig = bpy.data.objects['LifeRig']
    for bone in rig.pose.bones:
        bone.rotation_euler = (0, 0, 0)
    if pose in POSES:
        for name, rot in POSES[pose].items():
            bone = rig.pose.bones.get(name)
            if bone:
                bone.rotation_mode = 'XYZ'
                bone.rotation_euler = rot
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.startswith(HAIR_PREFIXES):
            keep = o.name.startswith(style)
            o.hide_render = not keep
            o.hide_viewport = not keep
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'OPTIX'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = 'GPU'
    except Exception as error:
        print('GPU_UNAVAILABLE', error)
    scene.render.resolution_x = 900
    scene.render.resolution_y = 760
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    return scene


def shoot(path, style, pose, kind, filepath):
    scene = stage(path, style, pose)
    head = bpy.data.objects.get('Head')
    shell = bpy.data.objects.get('Outfit_Hoodie_Shell')
    head_z = head.matrix_world.translation.z if head else 1.45
    shell_top = max((shell.matrix_world @ v.co).z for v in shell.data.vertices) if shell else head_z - 0.1
    hx = head.matrix_world.translation.x if head else 0.0
    hy = head.matrix_world.translation.y if head else 0.0

    cam_data = bpy.data.cameras.new('evidence')
    cam = bpy.data.objects.new('evidence_cam', cam_data)
    scene.collection.objects.link(cam)
    aim = bpy.data.objects.new('evidence_aim', None)
    scene.collection.objects.link(aim)
    track = cam.constraints.new('TRACK_TO')
    track.target = aim
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'
    face_z = shell_top + 0.20
    if kind == 'front':
        cam_data.lens = 50; cam_data.type = 'ORTHO'; cam_data.ortho_scale = 0.62
        cam.location = (hx, hy - 2.6, face_z); aim.location = (hx, hy, face_z)
    elif kind == 'three_quarter':
        cam_data.lens = 50; cam_data.type = 'ORTHO'; cam_data.ortho_scale = 0.66
        cam.location = (hx + 1.3, hy - 2.1, face_z + 0.08); aim.location = (hx, hy, face_z)
    elif kind == 'body':
        cam_data.lens = 50; cam_data.type = 'ORTHO'; cam_data.ortho_scale = 2.06
        cam.location = (2.5, -6.4, 2.7); aim.location = (0, 0, .94)
    elif kind == 'hood_side30':
        from math import sin, cos, radians
        center = bpy.data.objects['Character'].matrix_world.translation
        collar_z = shell_top - 0.02
        cam_data.lens = 60; cam_data.type = 'PERSP'
        cam.location = (center.x + sin(radians(30)) * 0.7, center.y - cos(radians(30)) * 0.7, collar_z)
        aim.location = (center.x, center.y + 0.02, collar_z)
    scene.camera = cam
    scene.render.filepath = str(filepath)
    bpy.ops.render.render(write_still=True)
    print('RENDERED', filepath)


args.out.mkdir(parents=True, exist_ok=True)
for tag, path in (('before', args.before), ('after', args.after)):
    for style, pose, kind, prefix in SHOTS:
        name = f'{args.family}_{prefix}{pose if kind == "body" else kind}_{tag}.png'
        if prefix == 'hood_':
            name = f'{args.family}_hood_side30_{tag}.png'
        shoot(path, style, pose, kind, args.out / name)
print('EVIDENCE_COMPLETE', args.family)
