"""Original matching Juniper landing rail kit, kept separate from the frozen stair.

Span endpoints are local (0,0,0) and (1,0,0). Posts are separate so corners
share one post. All geometry is above the local floor datum, in metres.
"""
from pathlib import Path
import bpy, hashlib, json

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art/architecture'
bpy.ops.wm.read_factory_settings(use_empty=True)
materials={}
for name,hexcode in [('oak','BC9369'),('sage','557A6B'),('cream','EFE9DA'),('brass','BB9A5E')]:
    color=[int(hexcode[i:i+2],16)/255 for i in (0,2,4)]
    color=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in color]
    material=bpy.data.materials.new('Juniper '+name);material.diffuse_color=(*color,1)
    material.use_nodes=True;shader=material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=material.diffuse_color
    shader.inputs['Roughness'].default_value=.4 if name=='brass' else .65
    shader.inputs['Metallic'].default_value=.6 if name=='brass' else 0
    materials[name]=material

def xyz(p):return (p[0],-p[2],p[1])
def box(name,p,size,material,parts):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p));o=bpy.context.object;o.name=name
    o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(materials[material])
    bevel=o.modifiers.new('Crafted edge','BEVEL');bevel.width=.003;bevel.segments=2
    o.modifiers.new('Planar normals','WEIGHTED_NORMAL');parts.append(o)
def marker(name,p,parts):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o)
    o.location=xyz(p);parts.append(o)
def export(name,parts):
    bpy.context.view_layer.update();graph=bpy.context.evaluated_depsgraph_get();copies=[]
    for material in sorted({o.data.materials[0].name for o in parts if o.type=='MESH'}):
        group=[]
        for o in parts:
            if o.type!='MESH' or o.data.materials[0].name!=material:continue
            mesh=bpy.data.meshes.new_from_object(o.evaluated_get(graph),depsgraph=graph)
            obj=bpy.data.objects.new('Export part',mesh);bpy.context.collection.objects.link(obj)
            obj.matrix_world=o.matrix_world.copy();group.append(obj)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in group:obj.select_set(True)
        bpy.context.view_layer.objects.active=group[0]
        if len(group)>1:bpy.ops.object.join()
        bpy.context.object.name=name+' '+material;copies.append(bpy.context.object)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies+[o for o in parts if o.type=='EMPTY']:obj.select_set(True)
    path=ROOT/'assets/models'/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    for obj in copies:bpy.data.objects.remove(obj,do_unlink=True)
    return hashlib.sha256(path.read_bytes()).hexdigest()

span=[]
box('Continuous oak landing rail',(.5,1,0),(1,.055,.072),'oak',span)
box('Sage lower rail',(.5,.085,0),(1,.060,.040),'sage',span)
for i in range(1,10):box('Landing baluster %02d'%i,(i*.1,.5425,0),(.025,.865,.025),'cream',span)
marker('RailStart',(0,0,0),span);marker('RailEnd',(1,0,0),span)
span_hash=export('juniper_guard_span',span)
post=[]
box('Landing newel',(0,.52,0),(.068,1.04,.068),'sage',post)
box('Landing newel foot',(0,.075,0),(.078,.15,.086),'sage',post)
box('Landing oak cap',(0,1.058,0),(.078,.036,.085),'oak',post)
box('Landing brass collar',(0,.925,0),(.069,.018,.070),'brass',post)
marker('PostBase',(0,0,0),post);post_hash=export('juniper_guard_post',post)
# Editable authoring arrangement only; export origins above stay unchanged.
for obj in post:obj.location.x-=.25
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'juniper_guardrails.blend'))
(OUT/'guardrail_geometry.json').write_text(json.dumps({'status':'Private authored kit; awaiting integrated rendered and clearance review','span_axis':'+X','span_length':1,'rail_top':1.0275,'post_top':1.076,'post_max_half_width':.039,'post_max_half_depth':.043,'placement':'Use one post per boundary/junction. Span begins/ends at post centers; keep landing exit clear. Offset guard footprint onto the supported slab, not into stair opening.','hashes':{'juniper_guard_span.glb':span_hash,'juniper_guard_post.glb':post_hash},'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},indent=2))
print('GUARDRAIL_KIT_CREATED',span_hash,post_hash)
