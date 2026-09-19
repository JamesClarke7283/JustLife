"""Original JustLife birthday cake. Blender builds the game prop and review render."""
import bpy, math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
materials = {}
objects = []

def material(name, color, roughness=.6, emission=0):
    rgb = [int(color[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in rgb]
    m = bpy.data.materials.new(name); m.diffuse_color = (*rgb, 1); m.use_nodes = True
    shader = m.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*rgb, 1)
    shader.inputs['Roughness'].default_value = roughness
    if emission:
        shader.inputs['Emission Color'].default_value = (*rgb, 1)
        shader.inputs['Emission Strength'].default_value = emission
    materials[name] = m

for name, color in [('porcelain','EDF1E4'),('sponge','D5A76E'),('icing','FFF0D9'),('filling','D0827E'),('berry','A74357'),('leaf','558064'),('teal','72ABA3'),('coral','DFA291'),('wick','55402E')]:
    material(name, color, .35 if name == 'porcelain' else .6)
material('flame','FFD79C',.6,2.0)

def position(p): return (p[0], -p[2], p[1])
def finish(obj, name, color):
    obj.name = name; obj.data.materials.append(materials[color]); objects.append(obj)
    for polygon in obj.data.polygons: polygon.use_smooth = True
    return obj
def cylinder(name, p, radius, height, color, bevel=.002):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=radius, depth=height, location=position(p))
    obj=bpy.context.object
    modifier=obj.modifiers.new('Soft rounded edge','BEVEL');modifier.width=bevel;modifier.segments=3
    obj.modifiers.new('Corner normals','WEIGHTED_NORMAL')
    return finish(obj,name,color)
def oval(name, p, scale, color):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=position(p))
    obj=bpy.context.object;obj.scale=(scale[0],scale[2],scale[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(obj,name,color)

cylinder('Serving plate',(0,.006,0),.145,.012,'porcelain')
cylinder('Vanilla sponge',(0,.051,0),.111,.077,'sponge',.004)
cylinder('Berry filling',(0,.052,0),.112,.007,'filling',.002)
cylinder('Vanilla frosting',(0,.095,0),.114,.017,'icing',.006)
for i in range(28):
    angle=math.tau*i/28
    oval('Piped cream',(math.cos(angle)*.105,.105,math.sin(angle)*.105),(.011,.009,.011),'icing')
for i in range(7):
    angle=math.tau*i/7+.18
    oval('Frosting drip',(math.cos(angle)*.110,.085,math.sin(angle)*.110),(.008,.014,.008),'icing')
for i in range(5):
    angle=math.tau*i/5+.5
    p=(math.cos(angle)*.078,.116,math.sin(angle)*.078)
    oval('Berry',p,(.012,.015,.012),'berry')
    leaf=oval('Berry leaf',(p[0]+.01,p[1]-.005,p[2]),(.013,.002,.006),'leaf')
    leaf.rotation_euler.z=angle
for i in range(3):
    angle=math.tau*i/3+.2
    x,z=math.cos(angle)*.039,math.sin(angle)*.039
    cylinder('Candle_%d'%i,(x,.135,z),.0045,.066,'teal' if i%2==0 else 'coral',.001)
    cylinder('Wick_%d'%i,(x,.171,z),.0008,.006,'wick',.0003)
    oval('Flame_%d'%i,(x,.181,z),(.004,.010,.004),'flame')

root=bpy.data.objects.new('BirthdayCake',None);bpy.context.collection.objects.link(root)
root['width_m']=.29;root['height_m']=.192;root['plate_grip_height_m']=.006
root['flame_height_m']=.181;root['original_artwork']='JustLife'
for obj in objects:obj.parent=root
bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
for obj in objects:obj.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/birthday_cake.glb'),export_format='GLB',use_selection=True,export_apply=True,export_extras=True,export_animations=False)

# Review lighting is not part of the exported asset.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002))
plane=bpy.context.object
material('backdrop','E9E7DC');plane.data.materials.append(materials['backdrop'])
bpy.ops.object.camera_add(location=(.37,-.49,.37));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,.08))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=.45;bpy.context.scene.camera=camera
for pos,energy,size in [((-.4,-.3,.6),25,.4),((.4,.2,.4),10,.3)]:
    bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object
    light.data.energy=energy;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32
scene.render.resolution_x=800;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Birthday studio')
scene.world.color=(.25,.25,.25)
(ROOT/'art/celebration').mkdir(parents=True,exist_ok=True)
scene.render.filepath=str(ROOT/'art/celebration/birthday_cake.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/celebration/birthday_cake.blend'))
bpy.ops.render.render(write_still=True)
print('JUSTLIFE_BIRTHDAY_CAKE_COMPLETE')
