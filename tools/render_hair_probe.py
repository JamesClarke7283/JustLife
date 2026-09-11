"""Render Hair_Long held-pose comparisons for the current drape tuning.

    blender -b --python tools/render_hair_probe.py -- --family all --out evidence/hair59

For every age family this loads the committed (HEAD) editable source and the
working-tree source, hides every hairstyle except Hair_Long, poses the rig
(arms out, arms forward, walk) and renders matched pairs. Evidence only; the
game never loads these frames.
"""
import bpy, sys, os, argparse, subprocess, pathlib

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--family',choices=['adult','child','teen','elder','all'],default='all')
parser.add_argument('--out',type=pathlib.Path,default=ROOT/'evidence/hair59')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
FAMILIES=['adult','child','teen','elder'] if args.family=='all' else [args.family]
SOURCES={'adult':'art/characters.blend','child':'art/characters_child.blend','teen':'art/characters_teen.blend','elder':'art/characters_elder.blend'}
POSES={
 'arms_out':{'Arm_L':(-1.45,0,0),'Arm_R':(-1.45,0,0),'Forearm_L':(-.15,0,0),'Forearm_R':(-.15,0,0)},
 'arms_forward':{'Arm_L':(-.9,0,0),'Arm_R':(-.9,0,0),'Forearm_L':(-1.0,0,0),'Forearm_R':(-1.0,0,0)},
 'walk':{'Leg_L':(-.38,0,0),'Leg_R':(.33,0,0),'Shin_R':(.48,0,0),'Arm_L':(.22,0,0),'Arm_R':(-.22,0,0),'Forearm_R':(-.22,0,0),'Head':(.02,0,.08)},
}
HAIR_PREFIXES=('Hair_Bob','Hair_Buzz','Hair_Crop','Hair_Pony','Hair_Long','Hair_Curls','Hair_Waves','Curls')

def stage(path: pathlib.Path, pose: str) -> None:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    rig=bpy.data.objects['LifeRig']
    for name in POSES[pose]:
        bone=rig.pose.bones.get(name)
        if bone:bone.rotation_mode='XYZ';bone.rotation_euler=POSES[pose][name]
    for o in bpy.data.objects:
        if o.type=='MESH' and o.name.startswith(HAIR_PREFIXES):
            long_hair=o.name.startswith('Hair_Long')
            o.hide_render=not long_hair
            o.hide_viewport=not long_hair
            o.hide_set(not long_hair) if hasattr(o,'hide_set') else None
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.samples=24
    try:
        prefs=bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type='OPTIX'
        prefs.get_devices()
        for d in prefs.devices:d.use=True
        scene.cycles.device='GPU'
    except Exception as error:
        print('GPU_UNAVAILABLE',error)
    scene.render.resolution_x=760;scene.render.resolution_y=980
    scene.render.image_settings.file_format='PNG'
    scene.view_settings.view_transform='AgX'
    def view(location,target,scale):
        cam_data=bpy.data.cameras.new('probe');cam_data.lens=50
        cam=bpy.data.objects.new('probe_cam',cam_data)
        scene.collection.objects.link(cam)
        cam.location=location
        direction=bpy.data.objects.new('probe_dir',None)
        scene.collection.objects.link(direction);direction.location=target
        track=cam.constraints.new('TRACK_TO');track.target=direction;track.track_axis='TRACK_NEGATIVE_Z';track.up_axis='UP_Y'
        cam_data.ortho_scale=scale;cam_data.type='ORTHO'
        scene.camera=cam
    view((2.5,-6.4,2.7),(0,0,.94),2.06)

for family in FAMILIES:
    head=subprocess.run(['git','show','HEAD:'+SOURCES[family]],cwd=ROOT,capture_output=True).stdout
    scratch=ROOT/'dist/tmp';scratch.mkdir(parents=True,exist_ok=True)
    before=scratch/('hair_before_'+family+'.blend')
    print('PROBE_HEAD_LEN',len(head),'BEFORE_PATH',before)
    before.write_bytes(head)
    print('PROBE_WROTE',before.stat().st_size)
    for label,path in (('before',before),('after',ROOT/SOURCES[family])):
        for pose in POSES:
            stage(path,pose)
            bpy.context.scene.render.filepath=str(args.out/f'{family}_{pose}_{label}.png')
            bpy.ops.render.render(write_still=True)
            print('RENDERED',family,pose,label)
    before.unlink(missing_ok=True)
print('HAIR_PROBE_COMPLETE')
