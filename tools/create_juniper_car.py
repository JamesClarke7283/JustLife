"""Original JustLife shared neighborhood car, authored reproducibly in Blender."""
from pathlib import Path
import bpy, math
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name,hex,rough=.4,metal=0):
    rgb=[int(hex[i:i+2],16)/255 for i in (0,2,4)];rgb=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*rgb,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
    return m
sage=mat('Juniper enamel','668B7B',.27,.25);cream=mat('Warm ivory roof','EEEAD8',.4);rubber=mat('Graphite rubber','303D3C',.92);chrome=mat('Brushed champagne alloy','B9B29D',.28,.72);glass=mat('Smoked blue glazing','628488',.17);lamp=mat('Headlight opal','F5EBD0',.22);tail=mat('Coral tail lamps','BE6257',.3);seat=mat('Oat upholstery','A8997E',.9)
def box(name,at,scale,material,bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=at);o=bpy.context.object;o.name=name;o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
    if bevel:
        mod=o.modifiers.new('Rounded formed corners','BEVEL');mod.width=bevel;mod.segments=3;o.modifiers.new('Surface normals','WEIGHTED_NORMAL')
    return o
# Blender front is -Y; glTF conversion places the nose along Godot +Z.
box('Rounded lower body',(0,0,.62),(1.76,3.65,.61),sage,.18)
box('Beltline sill',(0,0,.96),(1.74,3.18,.12),cream,.04)
box('Cabin glass',(0,.13,1.24),(1.53,1.97,.64),glass,.16)
box('Ivory roof',(0,.19,1.59),(1.61,1.98,.13),cream,.13)
box('Short sculpted hood',(0,-1.25,1.0),(1.63,1.06,.18),sage,.12)
box('Rear hatch deck',(0,1.38,1.0),(1.63,.68,.18),sage,.12)
for side in [-1,1]:
    for y in [-.71,.24,1.03]:box('Window pillar',(side*.765,y,1.28),(.065,.085,.58),cream,.018)
    box('Door handle',(side*.885,.35,.93),(.038,.23,.045),chrome,.015)
    box('Side mirror',(side*.98,-.7,1.14),(.22,.26,.13),sage,.05)
    for y in [-1.15,1.15]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.34,depth=.22,location=(side*.82,y,.37),rotation=(0,math.pi/2,0));o=bpy.context.object;o.name='Wheel rubber';o.data.materials.append(rubber);b=o.modifiers.new('Tire shoulders','BEVEL');b.width=.035;b.segments=3
        bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=.19,depth=.235,location=(side*.83,y,.37),rotation=(0,math.pi/2,0));o=bpy.context.object;o.name='Wheel hub';o.data.materials.append(chrome);b=o.modifiers.new('Hub rim','BEVEL');b.width=.016;b.segments=2
    box('Headlight',(side*.57,-1.80,.78),(.32,.065,.21),lamp,.055)
    box('Tail light',(side*.61,1.80,.78),(.21,.065,.23),tail,.045)
box('Front bumper',(0,-1.83,.50),(1.60,.10,.10),chrome,.04);box('Rear bumper',(0,1.83,.50),(1.60,.10,.10),chrome,.04)
box('Grille',(0,-1.825,.72),(.65,.025,.16),rubber,.025)
for i in range(6):box('Grille slat',(-.27+i*.108,-1.842,.72),(.025,.015,.12),chrome,.004)
box('License plate',(0,-1.894,.5),(.35,.012,.11),cream,.005)
parent=bpy.data.objects.new('JuniperSharedCar',None);bpy.context.collection.objects.link(parent);parent['original_artwork']='JustLife';parent['design']='Juniper neighborhood shared car';parent['length_m']=3.85
for obj in list(bpy.context.scene.objects):
    if obj!=parent:obj.parent=parent
(ROOT/'art/transport').mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/transport/juniper_car.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/juniper_car.glb'),export_format='GLB',export_apply=True,export_extras=True,export_animations=False)
print('JUSTLIFE_JUNIPER_CAR_EXPORTED')
