from pathlib import Path
import argparse,sys,json,hashlib
import bpy,bmesh
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);source=a.source.resolve();before=hashlib.sha256(source.read_bytes()).hexdigest();bpy.ops.wm.open_mainfile(filepath=str(source))
def value(x):
 if isinstance(x,(str,int,float,bool))or x is None:return x
 try:return [value(y)for y in x]
 except TypeError:return str(x)
def props(x):return {k:value(x[k])for k in sorted(x.keys())if not k.startswith('_')}
def material(m):
 nodes=[];links=[]
 if m.node_tree:
  for n in m.node_tree.nodes:
   d={'name':n.name,'type':n.bl_idname,'inputs':{s.identifier:value(s.default_value)for s in n.inputs if hasattr(s,'default_value')}}
   for k in ['layer_name','blend_type','operation','attribute_name','uv_map']:
    if hasattr(n,k):d[k]=value(getattr(n,k))
   nodes.append(d)
  links=[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier)for l in m.node_tree.links]
 return {'name':m.name,'use_nodes':m.use_nodes,'diffuse_color':list(m.diffuse_color),'surface_render_method':m.surface_render_method,'nodes':sorted(nodes,key=lambda x:x['name']),'links':sorted(links),'properties':props(m)}
objects={};topology={}
for obj in sorted(bpy.data.objects,key=lambda x:x.name):
 d={'name':obj.name,'type':obj.type,'transform':[list(row)for row in obj.matrix_world],'parent':obj.parent.name if obj.parent else None,'collections':sorted(c.name for c in obj.users_collection),'hide_render':obj.hide_render,'hide_viewport':obj.hide_viewport,'hide_set':obj.hide_get(),'properties':props(obj),'modifiers':[(m.name,m.type)for m in obj.modifiers]}
 if obj.type=='MESH':
  mesh=obj.data;mesh.calc_loop_triangles();attrs={}
  for attr in mesh.color_attributes:attrs[attr.name]={'domain':attr.domain,'type':attr.data_type,'values':[list(x.color)for x in attr.data]}
  d['mesh']={'name':mesh.name,'vertices':[list(v.co)for v in mesh.vertices],'edges':[list(e.vertices)for e in mesh.edges],'polygons':[{'vertices':list(f.vertices),'smooth':f.use_smooth,'material':f.material_index}for f in mesh.polygons],'colors':attrs,'uvs':{uv.name:[list(x.uv)for x in uv.data]for uv in mesh.uv_layers},'materials':[m.name for m in mesh.materials],'properties':props(mesh),'shape_keys':mesh.shape_keys is not None}
  if obj.name.startswith('Tree_'):
   bm=bmesh.new();bm.from_mesh(mesh);topology[obj.name]={'vertices':len(bm.verts),'edges':len(bm.edges),'faces':len(bm.faces),'triangles':len(mesh.loop_triangles),'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'inconsistent_edge_winding':sum(not e.is_contiguous for e in bm.edges),'zero_area_faces':sum(f.calc_area()<1e-12 for f in bm.faces),'volume':bm.calc_volume(signed=True),'euler_characteristic':len(bm.verts)-len(bm.edges)+len(bm.faces)};bm.free()
 objects[obj.name]=d
facts={'objects':objects,'materials':{m.name:material(m)for m in bpy.data.materials},'collections':{c.name:{'objects':sorted(o.name for o in c.objects),'children':sorted(x.name for x in c.children),'hide_render':c.hide_render,'hide_viewport':c.hide_viewport}for c in bpy.data.collections},'unit_settings':{'system':bpy.context.scene.unit_settings.system,'scale_length':bpy.context.scene.unit_settings.scale_length}}
a.out.parent.mkdir(parents=True,exist_ok=True);fact_bytes=json.dumps(facts,sort_keys=True,separators=(',',':')).encode();result={'source':str(source),'source_sha256':before,'source_sha256_after':hashlib.sha256(source.read_bytes()).hexdigest(),'facts_sha256':hashlib.sha256(fact_bytes).hexdigest(),'facts':facts,'runtime_topology':topology,'blender':bpy.app.version_string,'scope':'Exact recorded object transforms, collection memberships/visibility, custom properties, base mesh positions/edges/polygons/smooth/material assignment, UVs/color attributes, material graph input values/links and unit settings. Not every Blender RNA field or container byte reproduction.'};assert result['source_sha256']==result['source_sha256_after'];a.out.write_text(json.dumps(result,indent=2)+'\n');print('NATIVE_TREE_SIGNATURE_OK',result['facts_sha256'],len(objects),len(topology))
