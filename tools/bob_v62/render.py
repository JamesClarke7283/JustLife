"""Matched 2-thread head views, evidence only, no source mutation."""
import argparse
import sys
from pathlib import Path
import bpy
from mathutils import Vector

p = argparse.ArgumentParser()
p.add_argument('--source', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--views', default='front,three_quarter,back')
p.add_argument('--adaptive', action='store_true', help='Frame a measured age-family head')
p.add_argument('--resolution', type=int, default=640)
p.add_argument('--style', default='Hair_Bob', help='Exact authored hair group to show')
p.add_argument('--outfit', default='', help='Optional outfit prefix for matched portraits')
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(a.source.resolve()))
scene = bpy.context.scene
hair_roots={'Hair_Crop','Hair_Bob','Hair_Curls','Hair_Pony','Hair_Long','Hair_Buzz','Hair_Waves','Hair_Bun'}
for o in bpy.data.objects:
    ancestry = {o.name}
    ancestor = o.parent
    while ancestor:
        ancestry.add(ancestor.name)
        ancestor = ancestor.parent
    if o.type in ('MESH', 'CURVE') and (hair_roots.intersection(ancestry) or o.name.startswith('Curls')):
        keep = a.style in ancestry
        o.hide_render = not keep; o.hide_viewport = not keep; o.hide_set(not keep)
    if a.outfit and o.type in ('MESH','CURVE') and any(n.startswith('Outfit_') for n in ancestry):
        keep=any(n.startswith(a.outfit) for n in ancestry)
        o.hide_render=not keep;o.hide_viewport=not keep;o.hide_set(not keep)
for bone in bpy.data.objects['LifeRig'].pose.bones:
    bone.rotation_euler = (0, 0, 0)
for o in list(bpy.data.objects):
    if o.type in ('LIGHT', 'CAMERA'):
        bpy.data.objects.remove(o, do_unlink=True)

aim = Vector((0, .004, 1.607))
view_scale = 1.0
ortho = .43
if a.adaptive:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from fit import bounds, evaluated_mesh
    head_bounds = bounds(evaluated_mesh(bpy.data.objects['Skin_Head_continuous'])[0])
    pivot = bpy.data.objects['Head'].matrix_world.translation
    span = head_bounds[2][1]-pivot.z
    bob_bounds = bounds([point for o in bpy.data.objects[a.style].children if o.type=='MESH'
                         for point in evaluated_mesh(o)[0]])
    aim = Vector((pivot.x,pivot.y,pivot.z+.54*span))
    ortho = max(span*1.62, (bob_bounds[0][1]-bob_bounds[0][0])*1.48)
    view_scale = ortho/.43
for name, loc, watts, light_size in [('Key', (-.55, -.70, 2.10), 30.0, .55),
                              ('Fill', (.65, -.25, 1.85), 16.0, .50),
                              ('Rim', (.05, .6, 2.0), 24.0, .45)]:
    data = bpy.data.lights.new('BobEvidence_' + name, 'AREA')
    data.energy = watts*view_scale**2; data.shape = 'DISK'; data.size = light_size*view_scale
    o = bpy.data.objects.new('BobEvidence_' + name, data)
    scene.collection.objects.link(o); o.location = aim+(Vector(loc)-Vector((0,.004,1.607)))*view_scale
    o.rotation_euler = (aim - o.location).to_track_quat('-Z', 'Y').to_euler()
world = bpy.data.worlds.new('BobEvidence_neutral')
world.use_nodes = True
world.node_tree.nodes.get('Background').inputs['Color'].default_value = (.19, .21, .20, 1)
world.node_tree.nodes.get('Background').inputs['Strength'].default_value = .6
scene.world = world
scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 12
scene.cycles.use_denoising = True
scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
scene.render.resolution_x = a.resolution; scene.render.resolution_y = a.resolution
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
cam_data = bpy.data.cameras.new('BobEvidence_camera')
cam_data.type = 'ORTHO'; cam_data.ortho_scale = ortho
cam = bpy.data.objects.new('BobEvidence_camera', cam_data)
scene.collection.objects.link(cam); scene.camera = cam
views = {'front': (0, -2.0, 1.64), 'three_quarter': (1.45, -2.0, 1.72),
         'back': (.65, 2.0, 1.76), 'left': (-1.45, -2.0, 1.72)}
a.output.mkdir(parents=True, exist_ok=True)
for name in a.views.split(','):
    cam.location = aim+(Vector(views[name])-Vector((0,.004,1.607)))*view_scale
    cam.rotation_euler = (aim - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(a.output / (name + '.png'))
    bpy.ops.render.render(write_still=True)
    print('BOB_RENDERED', scene.render.filepath)
