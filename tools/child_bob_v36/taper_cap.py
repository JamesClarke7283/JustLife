"""Focused positions-only lower cap refinement of frozen Bob concept 2."""
import argparse,bpy,hashlib,json,math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import source_facts as witness
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--source-sha256',required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);src=a.source.resolve();out=a.output.resolve();pin=a.source_sha256
assert out!=src and out not in src.parents
assert hashlib.sha256(src.read_bytes()).hexdigest()==pin
assert not out.exists();out.mkdir(parents=True)
witness.OWNED={'Hair_Bob_Cap'}
bpy.ops.wm.open_mainfile(filepath=str(src));bpy.context.view_layer.update()
def materials():
 return {m.name:{'rna':witness.scalar_rna(m),'props':witness.serial(dict(m.items())),'nodes':{n.name:{'rna':witness.scalar_rna(n),'inputs':{s.identifier:witness.serial(s.default_value)for s in n.inputs if hasattr(s,'default_value')}}for n in m.node_tree.nodes}if m.node_tree else {},'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier)for l in m.node_tree.links]if m.node_tree else []}for m in bpy.data.materials}
before=witness.objects();mat=materials();assert witness.digest({'objects':before['objects'],'materials':mat})=='cafc3a39bfb9ba2a158ecd3ff3f3012c8459ea06408848bc01f7c6d569038c29';cap=bpy.data.objects['Hair_Bob_Cap'];old=[v.co.copy()for v in cap.data.vertices]
def smooth(lo,hi,x):
 t=max(0,min(1,(x-lo)/(hi-lo)));return t*t*(3-2*t)
changes=[]
for i,v in enumerate(cap.data.vertices):
 co=v.co.copy();z=co.z
 if z>=1.05:continue
 angle=math.atan2(co.x,.0096645-co.y);aa=abs(angle)
 influence=smooth(.69,.99,aa)
 if not influence:continue
 band=1-smooth(.978,1.05,z);edge=1-smooth(.978,1.006,z)
 # Pull the lower mass inward, strongest below the ear and at the cut edge.
 # The protected ear meshes remain unchanged and are independently checked.
 taper=.008*band*influence*(1+.08*smooth(1.8,2.8,aa))
 taper+=.0012*edge*math.exp(-((aa-1.06)/.23)**2)
 radius=math.hypot(co.x,co.y-.0096645);target=radius-taper
 co.x*=target/radius;co.y=.0096645+(co.y-.0096645)*target/radius
 # Round the two front terminations and keep a shallow unequal nape curve.
 tip=.0065*math.exp(-((aa-1.06)/.20)**2)
 nape=.0032*math.exp(-((aa-3.02)/.36)**2)*(1+.16*math.sin(angle))
 co.z+=edge*(tip+nape)*influence
 v.co=co
 if co!=old[i]:changes.append(i)
cap.data.update();bpy.context.view_layer.update();after=witness.objects();assert materials()==mat
assert before['objects'].keys()==after['objects'].keys()
for name,record in before['objects'].items():
 other=after['objects'][name]
 if name!='Hair_Bob_Cap':assert record==other,name
 else:assert {k:v for k,v in record.items()if k!='geometry_sha256'}=={k:v for k,v in other.items()if k!='geometry_sha256'}
for k,v in before['owned']['Hair_Bob_Cap'].items():
 if k!='mesh_positions':assert v==after['owned']['Hair_Bob_Cap'][k],k
assert all(list(v.co)==list(old[i])for i,v in enumerate(cap.data.vertices)if old[i].z>=1.05)
dest=out/'characters_child.blend';bpy.ops.wm.save_as_mainfile(filepath=str(dest))
assert hashlib.sha256(src.read_bytes()).hexdigest()==pin
(out/'stage_check.json').write_text(json.dumps({'stage':'cap-only lower band on concept2','input_sha256':pin,'output_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'protected_objects_exact_to_concept2':361,'materials_exact':True,'owned_position_only':['Hair_Bob_Cap'],'changed_vertices':len(changes),'changed_indices':changes,'upper_cap_z_ge_1_05_exact':True,'before_signature':witness.digest({'objects':before['objects'],'materials':mat}),'after_signature':witness.digest({'objects':after['objects'],'materials':mat})},indent=2)+'\n')
print('BOB_LOWER_CAP_ONLY',len(changes),'vertices; 361 objects protected',dest)
