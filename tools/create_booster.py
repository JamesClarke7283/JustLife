"""Original small desk booster cushion for child Lifelets, authored in Blender."""
import bpy, math
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
def material(name,color):
    rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
    rgb=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb]
    mat=bpy.data.materials.new(name);mat.diffuse_color=(*rgb,1);mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(*rgb,1);shader.inputs['Roughness'].default_value=.92
    return mat
fabric=material('Soft sage linen','80A698');seam=material('Cream piping','E9E6CF')
bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,.09))
cushion=bpy.context.object;cushion.name='Booster cushion';cushion.dimensions=(.51,.53,.18)
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
bevel=cushion.modifiers.new('Soft cushion corners','BEVEL');bevel.width=.032;bevel.segments=5
cushion.modifiers.new('Soft face normals','WEIGHTED_NORMAL');cushion.data.materials.append(fabric)
for face in cushion.data.polygons:face.use_smooth=True
curve=bpy.data.curves.new('Piped seam','CURVE');curve.dimensions='3D';curve.bevel_depth=.002;curve.bevel_resolution=2
spline=curve.splines.new('POLY');points=[]
for cx,cy,start in [(.22,.23,0),(-.22,.23,90),(-.22,-.23,180),(.22,-.23,270)]:
    for step in range(13):
        a=math.radians(start+step*7.5);points.append((cx+.035*math.cos(a),cy+.035*math.sin(a),.09,1))
spline.points.add(len(points)-1)
for point,value in zip(spline.points,points):point.co=value
spline.use_cyclic_u=True
piping=bpy.data.objects.new('Cream edge piping',curve);bpy.context.collection.objects.link(piping);curve.materials.append(seam)
bpy.context.view_layer.objects.active=piping;piping.select_set(True);cushion.select_set(False)
bpy.ops.object.convert(target='MESH');piping=bpy.context.object
parent=bpy.data.objects.new('DeskBooster',None);bpy.context.collection.objects.link(parent)
parent['support_height_m']=.18;parent['width_m']=.51;parent['depth_m']=.53;parent['original_artwork']='JustLife'
cushion.parent=parent;piping.parent=parent
bpy.ops.object.select_all(action='DESELECT')
for obj in [parent,cushion,piping]:obj.select_set(True)
bpy.context.view_layer.objects.active=parent
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/desk_booster.glb'),export_format='GLB',use_selection=True,export_apply=True,export_extras=True,export_animations=False)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=700;scene.render.resolution_y=600;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Cushion studio');scene.world.color=(.3,.3,.3)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003));bpy.context.object.data.materials.append(material('Studio floor','EAE7DF'))
bpy.ops.object.camera_add(location=(.7,-.9,.8));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,.05))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=.85;scene.camera=camera
for position,power,size in [((-.4,-.4,1.1),80,.8),((.7,.3,.6),35,.6)]:
    bpy.ops.object.light_add(type='AREA',location=position);light=bpy.context.object;light.data.energy=power;light.data.size=size
    light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
(ROOT/'art/furniture').mkdir(parents=True,exist_ok=True)
scene.render.filepath=str(ROOT/'art/furniture/desk_booster.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/furniture/desk_booster.blend'))
bpy.ops.render.render(write_still=True)
print('JUSTLIFE_DESK_BOOSTER_COMPLETE')
