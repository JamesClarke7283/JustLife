"""Render head-on face close-ups for iris, mouth and brow inspection.

    blender -b --python tools/render_face_probe.py -- --family all --out evidence/face60

For every age family this loads the editable source, hides every hairstyle
except the production default, and renders a front orthographic head crop plus
a three-quarter view. Evidence only; the game never loads these frames.
"""
import bpy, sys, argparse, pathlib

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--family',choices=['adult','child','teen','elder','all'],default='all')
parser.add_argument('--out',type=pathlib.Path,default=ROOT/'evidence/face60')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
FAMILIES=['adult','child','teen','elder'] if args.family=='all' else [args.family]
SOURCES={'adult':'art/characters.blend','child':'art/characters_child.blend','teen':'art/characters_teen.blend','elder':'art/characters_elder.blend'}
HAIR_PREFIXES=('Hair_Bob','Hair_Buzz','Hair_Crop','Hair_Pony','Hair_Long','Hair_Curls','Curls')
DEFAULT_HAIR='Hair_Bob'

def stage(path: pathlib.Path) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    for o in bpy.data.objects:
        if o.type=='MESH' and o.name.startswith(HAIR_PREFIXES):
            keep=o.name.startswith(DEFAULT_HAIR)
            o.hide_render=not keep
            o.hide_viewport=not keep
            if hasattr(o,'hide_set'):o.hide_set(not keep)
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.samples=32
    try:
        prefs=bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type='OPTIX'
        prefs.get_devices()
        for d in prefs.devices:d.use=True
        scene.cycles.device='GPU'
    except Exception as error:
        print('GPU_UNAVAILABLE',error)
    scene.render.resolution_x=760;scene.render.resolution_y=560
    scene.render.image_settings.file_format='PNG'
    scene.view_settings.view_transform='AgX'
    def view(location,target,scale):
        cam_data=bpy.data.cameras.new('face_probe');cam_data.lens=50
        cam=bpy.data.objects.new('face_cam',cam_data)
        scene.collection.objects.link(cam)
        cam.location=location
        aim=bpy.data.objects.new('face_aim',None)
        scene.collection.objects.link(aim);aim.location=target
        track=cam.constraints.new('TRACK_TO');track.target=aim;track.track_axis='TRACK_NEGATIVE_Z';track.up_axis='UP_Y'
        cam_data.type='ORTHO';cam_data.ortho_scale=scale
        scene.camera=cam
    head=bpy.data.objects.get('Head')
    if head:
        world=head.matrix_world.translation
    else:
        world=__import__('mathutils').Vector((0,0,1.6))
    # Front orthographic head crop and a gentle three-quarter for depth cues.
    view((world.x,world.y-2.6,world.z),(world.x,world.y,world.z),.34)
    bpy.context.scene.render.filepath=str(args.out/f'{family}_front.png')
    bpy.ops.render.render(write_still=True)
    print('RENDERED',family,'front')
    view((world.x+1.4,world.y-2.2,world.z+.25),(world.x,world.y,world.z),.4)
    bpy.context.scene.render.filepath=str(args.out/f'{family}_three_quarter.png')
    bpy.ops.render.render(write_still=True)
    print('RENDERED',family,'three_quarter')

args.out.mkdir(parents=True,exist_ok=True)
for family in FAMILIES:
    stage(ROOT/SOURCES[family])
print('FACE_PROBE_COMPLETE')
