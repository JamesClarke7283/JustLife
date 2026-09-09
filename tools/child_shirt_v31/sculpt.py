"""Child casual sleeve shaping only. Fresh immutable source; topology/UV/skin exact."""
import argparse,bpy,hashlib,json,math,sys
from pathlib import Path
from mathutils import Vector,kdtree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from source_facts import objects
parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
a=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);a.source=a.source.resolve();a.output=a.output.resolve()
assert hashlib.sha256(a.source.read_bytes()).hexdigest()=='ac1cfe5dd4103c9062a961a6f468b35a13bc866dc6d094f1e8cdbebf3b4111c1'
assert not a.output.exists();a.output.mkdir(parents=True)
bpy.ops.wm.open_mainfile(filepath=str(a.source));before=objects();o=bpy.data.objects['Outfit_Casual_Shirt'];assert o.data.shape_keys is None
trim_names=['Outfit_Casual_Top_Collar_binding','Outfit_Casual_Top_Front_placket','Outfit_Casual_Top_Sleeve_cuff','Outfit_Casual_Top_Sleeve_cuff.001']
trim_pts=[ob.matrix_world@v.co for name in trim_names for ob in [bpy.data.objects[name]] for v in ob.data.vertices]
kd=kdtree.KDTree(len(trim_pts))
for i,v in enumerate(trim_pts):kd.insert(v,i)
kd.balance()
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def gauss(x,c,w):return math.exp(-((x-c)/w)**2)
changed=[];pinned=[]
for v in o.data.vertices:
 old=v.co.copy();x,y,z=old;ax=abs(x);sign=-1 if x<0 else 1
 distance=kd.find(old)[2]
 # The fall stays above the cuff and outside the collar/placket. The exact
 # source vertices nearest those retained trim surfaces remain bit-identical.
 guard=smooth(.009,.021,distance)*smooth(.745,.777,z)*(1-smooth(.883,.898,z))*smooth(.060,.098,ax)
 if distance<=.009:pinned.append(v.index)
 if guard==0:continue
 crown=min(gauss(ax,.135,.044),gauss(ax,.155,.039))*gauss(z,.853,.031)
 sleeve=smooth(.112,.157,ax)*gauss(z,.815,.052)
 delta=Vector((-sign*.0055*sleeve, -(y-.003)*.12*sleeve, -.0105*crown))*guard
 v.co=old+delta
 if v.co!=old:changed.append({'vertex':v.index,'before':list(old),'after':list(v.co),'distance_to_trim':distance})
o.data.update();bpy.context.view_layer.update();after=objects()
assert set(before['objects'])==set(after['objects']) and len(before['objects'])==362
for name,old in before['objects'].items():
 new=after['objects'][name]
 if name!=o.name:assert old==new,name
 else:assert {k:v for k,v in old.items() if k!='geometry_sha256'}=={k:v for k,v in new.items() if k!='geometry_sha256'}
assert before['owned'][o.name].keys()==after['owned'][o.name].keys()
for key,old in before['owned'][o.name].items():
 if key!='mesh_positions':assert old==after['owned'][o.name][key],key
assert all(before['owned'][o.name]['mesh_positions'][i]==after['owned'][o.name]['mesh_positions'][i]for i in pinned)
maximum=max((Vector(c['before'])-Vector(c['after'])).length for c in changed)
report={'source_sha256':hashlib.sha256(a.source.read_bytes()).hexdigest(),'owned_object':o.name,'protected_objects':361,'changed_vertices':len(changed),'max_displacement_m':maximum,'exact_trim_guard_vertices':pinned,'changes':changed,'topology_uv_weights_metadata_exact':True}
(a.output/'sculpt_report.json').write_text(json.dumps(report,indent=2)+'\n')
(a.output/'candidate_native_facts.json').write_text(json.dumps(after,sort_keys=True)+'\n')
unused=bpy.data.materials['Hair_shadow'];assert unused.users==0 and unused.use_fake_user is False
unused.use_fake_user=True
# Explicitly authorized source-maintenance flag; material appearance stays exact.
(a.output/'source_maintenance.json').write_text(json.dumps({'material':'Hair_shadow','property':'use_fake_user','before':False,'after':True,'reason':'Keep exact unused accepted material in ordinary editable mainfile; no material nodes/inputs/content change'},indent=2)+'\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(a.output/'characters_child.blend'))
print('CHILD_SHIRT_SCULPT_OK',len(changed),maximum,361,len(pinned))
