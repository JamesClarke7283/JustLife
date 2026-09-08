"""Original Juniper floor mop. Run with Blender --background --python tools/create_mop.py."""
from pathlib import Path
import bpy
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
def material(name, color, roughness):
    m = bpy.data.materials.new(name); m.diffuse_color = (*color, 1); m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*color, 1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = roughness
    return m
wood=material('Warm ash handle',(.47,.32,.16),.46)
sage=material('Sage enamel',(.18,.40,.33),.34)
cotton=material('Woven cotton mop',(.83,.86,.78),.95)
def cube(name, pos, scale, mat, bevel=.014):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos); o=bpy.context.object; o.name=name; o.dimensions=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
    m=o.modifiers.new('Soft manufactured edges','BEVEL');m.width=bevel;m.segments=3
    o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o
def pole(name, a, b, radius, mat):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=radius,depth=d.length,location=(a+b)*.5)
    o=bpy.context.object;o.name=name;o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');o.data.materials.append(mat)
    for f in o.data.polygons:f.use_smooth=True
# Blender Z-up -> Godot Y-up; Blender +Y maps to Godot -Z.
cube('Cotton pad',(0,0,.019),(.39,.16,.034),cotton)
cube('Sage mop head',(0,0,.040),(.32,.10,.032),sage)
for x in [-.18,-.15,-.12,-.09,-.06,-.03,0,.03,.06,.09,.12,.15,.18]:
    cube('Cotton seam',(x,0,.006),(.012,.162,.008),cotton,.003)
pole('Ash handle',(0,0,.06),(0,.38,1.25),.018,wood)
pole('Sage grip',(0,.344,1.138),(0,.38,1.25),.024,sage)
pole('Head socket',(0,0,.045),(0,.05,.20),.030,sage)
(ROOT/'art/sanitation').mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/sanitation/juniper_mop.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/juniper_mop.glb'),export_format='GLB',export_yup=True,export_apply=True)
print('Original Juniper mop exported.')
