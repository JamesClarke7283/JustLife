"""Matched garment form renders; posed/render-only edits are never saved."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import POSES, capture_pose, rig_anchors, set_pose

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--outfit', choices=('Tee', 'Casual'), default='Tee')
ap.add_argument('--pose', choices=tuple(POSES), default='rest')
ap.add_argument('--angle', type=float, default=0.)
ap.add_argument('--paired', action='store_true')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
source_sha = hashlib.sha256(args.source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
set_pose(args.pose, capture_pose())
for obj in bpy.data.objects:
    if obj.type in ('MESH', 'CURVE'):
        obj.hide_render = not obj.name.startswith(('Outfit_' + args.outfit + '_',
                                                   'Skin_Head_continuous', 'Skin_Arm_continuous',
                                                   'Skin_Upperarm_fill'))
    elif obj.type == 'LIGHT':
        obj.hide_render = True
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 12
scene.cycles.use_denoising = True
scene.render.resolution_x = 840 if args.pose != 'rest' else 560
scene.render.resolution_y = 560
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
world = bpy.data.worlds.new('Garment_Diagnostic_World')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (.055, .065, .070, 1.)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = .35
scene.world = world
# Same neutral preview cloth for every pair; material assignments in the
# candidate source remain exact and this diagnostic scene is never saved.
cloth = bpy.data.materials.new('Garment_Diagnostic_Only')
cloth.use_nodes = True
bsdf = cloth.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value = (.34, .36, .34, 1.)
bsdf.inputs['Roughness'].default_value = .83
for obj in bpy.data.objects:
    if obj.type == 'MESH' and obj.name == 'Outfit_' + args.outfit + '_Shirt':
        for i in range(len(obj.data.materials)):
            obj.data.materials[i] = cloth
anchors = rig_anchors()
scale = abs(anchors['Arm_R'].x) / .18
focus = Vector((0., 0., anchors['Arm_R'].z - .13 * scale))
light_receipt = []
for name, offset, energy in [('Garment_Key', (.50, -.70, .50), 45.),
                              ('Garment_Fill', (-.60, -.35, .10), 20.)]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size = energy, 'DISK', .55 * scale
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = focus + Vector(offset) * scale
    obj.rotation_euler = (focus - obj.location).to_track_quat('-Z', 'Y').to_euler()
    light_receipt.append({'name': name, 'position': list(obj.location),
                          'rotation_euler': list(obj.rotation_euler), 'energy': data.energy,
                          'size': data.size, 'color': list(data.color)})
camera_data = bpy.data.cameras.new('Garment_Diagnostic')
camera_data.type = 'ORTHO'
camera_data.ortho_scale = (.91 if args.pose != 'rest' else .61) * scale
camera = bpy.data.objects.new('Garment_Diagnostic', camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
args.output.parent.mkdir(parents=True, exist_ok=True)
receipt = {'source': str(args.source.resolve()), 'source_sha256': source_sha,
           'outfit': args.outfit, 'pose': args.pose, 'engine': 'CYCLES_CPU',
           'samples': scene.cycles.samples, 'resolution': [scene.render.resolution_x,
           scene.render.resolution_y], 'view_transform': scene.view_settings.view_transform,
           'camera_ortho_scale': camera_data.ortho_scale, 'lights': light_receipt,
           'world_color': [.055, .065, .070, 1.], 'world_strength': .35,
           'diagnostic_cloth_color': [.34, .36, .34, 1.], 'diagnostic_cloth_roughness': .83,
           'renders': []}
for label, degrees in ([('front', 0.), ('three_quarter', 35.)] if args.paired else [('', args.angle)]):
    angle = math.radians(degrees)
    camera.location = focus + Vector((math.sin(angle) * 2.4, -math.cos(angle) * 2.4, .035))
    camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
    output = args.output.with_stem(args.output.stem + '_' + label) if label else args.output
    scene.render.filepath = str(output.resolve())
    bpy.ops.render.render(write_still=True)
    receipt['renders'].append({'image': str(output.resolve()), 'angle_degrees': degrees,
                               'camera_position': list(camera.location),
                               'camera_euler': list(camera.rotation_euler),
                               'sha256': hashlib.sha256(output.read_bytes()).hexdigest()})
    print('GARMENT_RENDERED', output, flush=True)
assert hashlib.sha256(args.source.read_bytes()).hexdigest() == source_sha
receipt['source_unchanged'] = True
args.output.with_suffix('.json').write_text(json.dumps(receipt, indent=2) + '\n')
