"""Author the original grouped Bob from the immutable b513 native input."""
import argparse,bpy,copy,hashlib,json,math,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
import source_facts as witness
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);src=a.source.resolve();out=a.output.resolve()
assert hashlib.sha256(src.read_bytes()).hexdigest()=='965ddff984888845dfbdbb7ccc92fb9f62331538b70917b07173b3edee3cdd80'
assert not out.exists();out.mkdir(parents=True)
owned={'Hair_Bob_Cap'}|{'Hair_Bob_'+kind+(''if i==0 else f'.{i:03}')for kind in ['Lock','Strand']for i in range(12)}
witness.OWNED=owned
bpy.ops.wm.open_mainfile(filepath=str(src));bpy.context.view_layer.update()
def materials():
 return {m.name:{'rna':witness.scalar_rna(m),'props':witness.serial(dict(m.items())),'nodes':{n.name:{'rna':witness.scalar_rna(n),'inputs':{s.identifier:witness.serial(s.default_value)for s in n.inputs if hasattr(s,'default_value')}}for n in m.node_tree.nodes}if m.node_tree else {},'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier)for l in m.node_tree.links]if m.node_tree else []}for m in bpy.data.materials}
before=witness.objects();mat=materials();assert len(before['objects'])==362
def smooth(lo,hi,x):
 t=max(0,min(1,(x-lo)/(hi-lo)));return t*t*(3-2*t)
CY=.0096645
def mesh_bvh(objects,x_factor=1.0):
 if not isinstance(objects,list):objects=[objects]
 vs=[];faces=[];deps=bpy.context.evaluated_depsgraph_get()
 for obj in objects:
  e=obj.evaluated_get(deps);m=e.to_mesh();m.calc_loop_triangles();offset=len(vs)
  vertices=[e.matrix_world@v.co for v in m.vertices]
  for v in vertices:v.x*=x_factor
  vs.extend(vertices);faces.extend([offset+i for i in t.vertices]for t in m.loop_triangles);e.to_mesh_clear()
 return BVHTree.FromPolygons(vs,faces,all_triangles=True)
# Head envelopes are sampled in the hair's unexpanded coordinate frame. This
# exactly accounts for the retained runtime Bob +7% X expansion at joint maxima.
anatomy=[bpy.data.objects[n]for n in ['Skin_Head_continuous','Ear_Concha','Ear_Concha.001']];keys=[]
for obj in bpy.data.objects:
 if obj.type=='MESH'and obj.data.shape_keys:
  for key in obj.data.shape_keys.key_blocks:keys.append((key,key.value))
envelopes=[]
for label,identity,smile,blink in [('neutral',0,0,0),('identity',1,0,0),('friendly',1,1,0),('blink',1,0,1)]:
 for key,_ in keys:
  if key.name in ['Face_Round','Jaw_Strong','Nose_Wide','Eye_Spacing']:key.value=identity
  elif key.name=='Smile':key.value=smile
  elif key.name=='Blink':key.value=blink
 bpy.context.view_layer.update();envelopes.append((label,mesh_bvh(anatomy,1/(1+.07*identity))))
for key,value in keys:key.value=value
bpy.context.view_layer.update()
def radius(tree,angle,z):
 direction=Vector((math.sin(angle),-math.cos(angle),0));origin=Vector((0,CY,z))+direction*.4
 point,_,_,distance=tree.ray_cast(origin,-direction,.5)
 return None if point is None or distance>=.4 else .4-distance
def head_radius(angle,z):
 hits=[r for _,tree in envelopes for r in [radius(tree,angle,z)]if r is not None]
 return max(hits)if hits else 0.0
cap=bpy.data.objects['Hair_Bob_Cap'];original=[v.co.copy()for v in cap.data.vertices];assert len(original)==1920
# The continuous native cap supplies the cut and broad flow. The unchanged
# fringe and front crown stay in place. Unequal lobes curve gently from the
# upper side toward the jaw/nape, rather than sitting on it as separate plates.
def wrap(angle):return (angle+math.pi)%(2*math.pi)-math.pi
def flow(angle,t):
 side=1 if angle>=0 else -1;aa=abs(angle)
 centers=[1.01+.11*t,1.72-.07*t,2.48-.13*t]
 if side<0:centers=[c+.045 for c in centers]
 return sum(a*math.exp(-((aa-c)/width)**2)for a,c,width in zip([.0027,.0018,.0024],centers,[.20,.28,.34]))
def hem(angle):
 aa=abs(wrap(angle))
 # Front side is a little longer; the nape rises, with three unequal shallow
 # breaks spread over each side, not six disconnected blunt tips.
 rise=.012*smooth(1.55,3.05,aa)
 breaks=.0037*math.exp(-((aa-1.45)/.14)**2)+.0025*math.exp(-((aa-2.24)/.20)**2)
 return .969+rise+breaks+.0015*math.sin(angle+.3)
for i in range(7,20):
 for j in range(96):
  angle=wrap(2*math.pi*j/96);aa=abs(angle);influence=smooth(.63,1.02,aa)
  if influence==0:continue
  old=original[i*96+j];co=old.copy()
  if i>=12:
   t=(i-12)/7;start=original[12*96+j]
   # End radius curls in under the full side volume. The actual anatomy
   # envelope below prevents this inward turn from cutting through ears/head.
   end_radius=1/math.sqrt((math.sin(angle)/.079)**2+(math.cos(angle)/.058)**2)
   sr=math.hypot(start.x,start.y-CY)
   r=(1-t)*sr+t*end_radius+.015*math.sin(math.pi*t)
   z=(1-t)*start.z+t*hem(angle)
   co=old.lerp(Vector((r*math.sin(angle),CY-r*math.cos(angle),z)),influence)
  radial=math.hypot(co.x,co.y-CY);actual=math.atan2(co.x,CY-co.y)
  # Sampling adjacent support points pads the evaluated smooth shell around
  # the separate ear tips, rather than merely clearing the central head.
  near=[head_radius(actual+da,co.z+dz)for da in [-.035,0,.035]for dz in [-.002,0,.002]]
  forward=.006*math.exp(-((abs(actual)-.91)/.28)**2)
  minimum=max(near)+.0055+forward
  radial=max(radial,minimum)
  t=(i-7)/12;radial+=flow(actual,t)*smooth(0,.32,t)*influence
  co.x=radial*math.sin(actual);co.y=CY-radial*math.cos(actual)
  cap.data.vertices[i*96+j].co=co
cap.data.update();bpy.context.view_layer.update();cap_tree=mesh_bvh(cap)
def cap_radius(angle,z):
 r=radius(cap_tree,angle,z)
 assert r is not None,('owned detail outside new shell',angle,z)
 return r
# Existing closed lock meshes and their dependent highlight strips are
# embedded behind the continuous shell. Their channels/material links remain
# editable and exact; visible broad flow is now sculpted in the cap itself.
# Keep them away from the new cut edge so no closed blunt tips emerge below it.
def name(kind,index):return 'Hair_Bob_'+kind+(''if index==0 else f'.{index:03}')
for index in range(12):
 side=-1 if index<6 else 1;group=(index%6)//2;partner=index%2
 center=[1.19,1.78,2.43][group]+(.10 if partner else 0)+(.025 if side<0 else 0)
 obj=bpy.data.objects[name('Lock',index)];assert len(obj.data.vertices)==48
 for ring in range(4):
  t=ring/3;z=1.106-.096*t
  for k in range(12):
   theta=2*math.pi*k/12;angle=side*(center+.10*t+.12*math.cos(theta))
   r=cap_radius(angle,z)-.012+.0015*math.sin(theta)
   obj.data.vertices[ring*12+k].co=(r*math.sin(angle),CY-r*math.cos(angle),z)
 obj.data.update()
 obj=bpy.data.objects[name('Strand',index)];old=[v.co.copy()for v in obj.data.vertices]
 low=min(v.z for v in old);high=max(v.z for v in old)
 for v,orig in zip(obj.data.vertices,old):
  t=(high-orig.z)/(high-low);z=1.095-.079*t;angle=side*(center+.10*t)
  r=cap_radius(angle,z)-.015
  # Preserve finite ribbon width/depth without any exposed patch perimeter.
  r+=(orig.x-old[0].x)*.01;angle+=(orig.y-old[0].y)*.02
  v.co=(r*math.sin(angle),CY-r*math.cos(angle),z)
 obj.data.update()
bpy.context.view_layer.update();after=witness.objects();assert materials()==mat
changed=[]
for n,old in before['objects'].items():
 new=after['objects'][n]
 if n not in owned:assert old==new,n
 else:
  assert {k:v for k,v in old.items()if k!='geometry_sha256'}=={k:v for k,v in new.items()if k!='geometry_sha256'},n
  for k,v in before['owned'][n].items():
   if k!='mesh_positions':assert v==after['owned'][n][k],(n,k)
  changes=[i for i,(a,b)in enumerate(zip(before['owned'][n]['mesh_positions'],after['owned'][n]['mesh_positions']))if a!=b]
  changed.append({'name':n,'changed_vertices':len(changes),'total_vertices':len(before['owned'][n]['mesh_positions'])})
assert set(after['objects'])==set(before['objects'])
assert hashlib.sha256(src.read_bytes()).hexdigest()=='965ddff984888845dfbdbb7ccc92fb9f62331538b70917b07173b3edee3cdd80'
destination=out/'characters_child.blend';bpy.ops.wm.save_as_mainfile(filepath=str(destination))
(out/'source_check.json').write_text(json.dumps({'protected_objects_exact':337,'owned_position_only':25,'materials_exact':True,'input_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),'changed':changed,'before_signature':witness.digest({'objects':before['objects'],'materials':mat}),'after_signature':witness.digest({'objects':after['objects'],'materials':mat})},indent=2)+'\n')
print('BOB_POSITION_CONCEPT_OK',337,len(changed),destination)
