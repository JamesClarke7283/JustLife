"""Apply the reviewed skin-weight repair after the exact drape stage."""
from pathlib import Path
import argparse,collections,json,math,sys
sys.dont_write_bytecode=True
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent;sys.path.insert(0,str(W.parent/'adult_eyes'))
import source_facts as f
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--source-sha256',required=True)
parser.add_argument('--baseline-facts',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
spec={'source':{'path':str(args.source.resolve()),'sha256':args.source_sha256},
 'baseline_facts':{'path':str(args.baseline_facts.resolve()),'sha256':'0c5e100d9a07b549d0925743076fa5420c9776d05eb8d0957d0627282ad1ee1d'},
 'helper':{'path':str(W.parent/'adult_eyes/source_facts.py'),'sha256':'495d216ce051409f61a618f548df150893ea8603581547b77cdf85012a5862ae'}}
for item in spec.values():assert f.sha(Path(item['path']))==item['sha256'],item
SOURCE=Path(spec['source']['path']);OUT=args.output.resolve();assert not OUT.exists()
SHIRT='Outfit_Casual_Shirt'
TRIMS=['Outfit_Casual_Top_Hem','Outfit_Casual_Top_Fold','Outfit_Casual_Top_Fold.001','Outfit_Casual_Top_Sleeve_cuff','Outfit_Casual_Top_Sleeve_cuff.001']
OWNED={SHIRT,*TRIMS};GROUPS={'Root','Spine','Arm_L','Arm_R','Forearm_L','Forearm_R'}
CUT=1.20;SUPPORT_RADIUS=.012;MAX_ITERATIONS=10000;RESIDUAL_LIMIT=1e-10
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update();f.OWNED=OWNED
before=f.objects();assert before['objects']==json.loads(Path(spec['baseline_facts']['path']).read_text())['after']
assert len(before['objects'])==362
for name in OWNED:assert not bpy.data.objects[name].data.shape_keys

def material_facts():
 return {m.name:{'rna':f.scalar_rna(m),'props':f.serial(dict(m.items())),'nodes':{n.name:{'type':n.bl_idname,'rna':f.scalar_rna(n),'inputs':{s.name:f.serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},'links':[[l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name] for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}
material_before=f.digest(material_facts())
def smooth(a,b,v):
 t=max(0.,min(1.,(v-a)/(b-a)));return t*t*(3-2*t)
def weights(obj,i):return {obj.vertex_groups[g.group].name:float(g.weight) for g in obj.data.vertices[i].groups if g.weight>0}
def geometry(obj):
 obj.data.calc_loop_triangles()
 values=obj.data.shape_keys.key_blocks['Basis'].data if obj.data.shape_keys else obj.data.vertices
 points=[obj.matrix_world@v.co for v in values];triangles=[tuple(t.vertices) for t in obj.data.loop_triangles]
 return points,triangles,BVHTree.FromPolygons(points,triangles,all_triangles=True)
def barycentric(point,tri):
 a,b,c=tri;v0=b-a;v1=c-a;v2=point-a
 d00=v0.dot(v0);d01=v0.dot(v1);d11=v1.dot(v1);d20=v2.dot(v0);d21=v2.dot(v1)
 den=d00*d11-d01*d01;assert den>0,'Degenerate transfer triangle'
 v=(d11*d20-d01*d21)/den;z=(d00*d21-d01*d20)/den;raw=[1-v-z,v,z]
 bounded=[max(0.,min(1.,x)) for x in raw];total=math.fsum(bounded);assert total>0
 return raw,[x/total for x in bounded]
shirt=bpy.data.objects[SHIRT];points,triangles,shirt_tree=geometry(shirt);assert len(points)==6002
neighbors=[set() for _ in points]
for edge in shirt.data.edges:
 a,b=edge.vertices;assert a!=b and (points[a]-points[b]).length>0
 neighbors[a].add(b);neighbors[b].add(a)
remaining={i for i,p in enumerate(points) if p.z<CUT};components=[]
while remaining:
 stack=[min(remaining)];remaining.remove(stack[0]);component=[]
 while stack:
  i=stack.pop();component.append(i);new=neighbors[i]&remaining;remaining.difference_update(new);stack.extend(sorted(new,reverse=True))
 components.append(sorted(component))
components.sort(key=lambda ids:math.fsum(points[i].x for i in ids)/len(ids))
assert [len(ids) for ids in components]==[462,1883,465],'Unexpected lower sleeve/torso topology'
assert math.fsum(points[i].x for i in components[0])/462<-.15
assert abs(math.fsum(points[i].x for i in components[1])/1883)<.01
assert math.fsum(points[i].x for i in components[2])/465>.15
seeds={};reasons={}
def seed(i,value,reason):
 if i in seeds:assert seeds[i]==value,('Conflicting region seeds',i,reasons[i],reason)
 seeds[i]=value;reasons.setdefault(i,[]).append(reason)
for ci,ids in enumerate(components):
 for i in ids:seed(i,0. if ci==1 else 1.,['left_lower_sleeve','lower_torso','right_lower_sleeve'][ci])
for i,p in enumerate(points):
 if abs(p.x)<=.12 or p.z>=1.385:seed(i,0.,'central_torso_or_collar')
arm_data={side:(bpy.data.objects['Skin_Arm_continuous_'+side],*geometry(bpy.data.objects['Skin_Arm_continuous_'+side])) for side in ['L','R']}
support=[]
for i,p in enumerate(points):
 if i in seeds or not (1.22<=p.z<=1.37 and abs(p.x)>=.145):continue
 side='L' if p.x<0 else 'R';obj,ps,tris,tree=arm_data[side];hit,normal,ti,distance=tree.find_nearest(p)
 assert hit is not None and ti is not None
 ids=tris[ti];fully_upper=all(weights(obj,j)=={'Arm_'+side:1.} for j in ids)
 if distance<=SUPPORT_RADIUS and fully_upper:
  seed(i,1.,'protected_upper_arm_support')
  support.append({'vertex':i,'side':side,'skin_triangle':ti,'skin_vertices':list(ids),'distance_m':distance,'skin_nearest_point':list(hit)})
assert all(any(row['side']==side for row in support) for side in ['L','R']),'No actual upper-arm support seeds'
# Positive inverse-edge-length graph Laplacian, deterministic Jacobi order.
weighted=[]
for i,adj in enumerate(neighbors):
 terms=[(j,1./(points[i]-points[j]).length) for j in sorted(adj)];assert terms
 weighted.append((terms,math.fsum(w for _,w in terms)))
field=[seeds.get(i,.5) for i in range(len(points))];free=[i for i in range(len(points)) if i not in seeds]
for iteration in range(1,MAX_ITERATIONS+1):
 following=field.copy();change=0.
 for i in free:
  terms,total=weighted[i];value=math.fsum(weight*field[j] for j,weight in terms)/total
  assert 0.<=value<=1.;following[i]=value;change=max(change,abs(value-field[i]))
 field=following
 if change<=RESIDUAL_LIMIT:break
else:raise AssertionError('Harmonic field did not converge within declared bound')
residual=max((abs(field[i]-math.fsum(weight*field[j] for j,weight in weighted[i][0])/weighted[i][1]) for i in free),default=0.)
assert residual<=RESIDUAL_LIMIT and all(field[i]==value for i,value in seeds.items())
report={'source_sha256':spec['source']['sha256'],'owned_objects':sorted(OWNED),'changed_data':'Six owned skin-weight arrays only; every coordinate/topology/UV/key/object/rig/material/body/other-outfit datum protected.','parameters':{'cut_height':CUT,'support_radius_m':SUPPORT_RADIUS,'max_iterations':MAX_ITERATIONS,'residual_limit':RESIDUAL_LIMIT,'edge_rule':'positive inverse native-world edge length'},'components':components,'seeds':[{'vertex':i,'arm_weight':seeds[i],'reasons':reasons[i]} for i in sorted(seeds)],'support_seeds':support,'solve':{'iterations':iteration,'max_last_change':change,'residual':residual,'min':min(field),'max':max(field),'free_vertices':len(free)},'torso_fallback':[],'arm_fallback':[],'trim_transfers':{},'weight_changes':{},'failures':[]}

def normalize(values):
 assert set(values)<=GROUPS and all(math.isfinite(v) and v>=0 for v in values.values())
 total=math.fsum(values.values());assert total>0
 return {name:values[name]/total for name in sorted(values) if values[name]>0}
main_weights=[]
for i,p in enumerate(points):
 old=weights(shirt,i);assert set(old)<=GROUPS
 side='L' if p.x<0 else 'R';other='R' if side=='L' else 'L'
 assert old.get('Arm_'+other,0)==old.get('Forearm_'+other,0)==0
 torso=old.get('Root',0)+old.get('Spine',0)
 if torso>0:spine=old.get('Spine',0)/torso
 else:
  spine=smooth(1.02,1.20,p.z);report['torso_fallback'].append({'vertex':i,'height':p.z,'spine_fraction':spine,'rule':'original smoothstep(1.02,1.20,height); Root gets one minus Spine'})
 arm=old.get('Arm_'+side,0)+old.get('Forearm_'+side,0)
 if arm>0:elbow=old.get('Forearm_'+side,0)/arm
 else:
  elbow=1-smooth(1.025,1.17,p.z);report['arm_fallback'].append({'vertex':i,'height':p.z,'forearm_fraction':elbow,'rule':'original one minus smoothstep(1.025,1.17,height)'})
 a=field[i];main_weights.append(normalize({'Root':(1-a)*(1-spine),'Spine':(1-a)*spine,'Arm_'+side:a*(1-elbow),'Forearm_'+side:a*elbow}))
proposed={SHIRT:main_weights}
for name in TRIMS:
 obj=bpy.data.objects[name];rows=[];values=[]
 for i,v in enumerate(obj.data.vertices):
  p=obj.matrix_world@v.co;hit,normal,ti,distance=shirt_tree.find_nearest(p);assert hit is not None
  ids=triangles[ti];raw,bary=barycentric(hit,[points[j] for j in ids]);value=normalize({group:math.fsum(coefficient*main_weights[j].get(group,0.) for j,coefficient in zip(ids,bary)) for group in sorted(GROUPS)})
  if abs(p.x)>=.12:
   other='R' if p.x<0 else 'L';assert value.get('Arm_'+other,0)==value.get('Forearm_'+other,0)==0
  values.append(value);rows.append({'vertex':i,'shirt_triangle':ti,'shirt_vertices':list(ids),'distance_m':distance,'raw_barycentric':raw,'bounded_barycentric':bary})
 proposed[name]=values;report['trim_transfers'][name]=rows
# Only now apply the complete proposed arrays. All geometry was used read-only.
for name,new in proposed.items():
 obj=bpy.data.objects[name];old=[weights(obj,i) for i in range(len(obj.data.vertices))]
 assert len(new)==len(old) and all(set(v)<=GROUPS for v in old)
 memberships={group.index:[] for group in obj.vertex_groups}
 for vertex in obj.data.vertices:
  for membership in vertex.groups:memberships[membership.group].append(vertex.index)
 for group in obj.vertex_groups:
  if memberships[group.index]:group.remove(memberships[group.index])
 for i,value in enumerate(new):
  for group,amount in value.items():obj.vertex_groups[group].add([i],amount,'REPLACE')
 actual=[weights(obj,i) for i in range(len(old))]
 report['weight_changes'][name]={'changed_vertices':[i for i,(a,b) in enumerate(zip(old,actual)) if a!=b],'minimum_sum':min(math.fsum(v.values()) for v in actual),'maximum_sum':max(math.fsum(v.values()) for v in actual),'max_abs_sum_error':max(abs(math.fsum(v.values())-1.) for v in actual),'maximum_groups':max(len(v) for v in actual)}
 assert all(0<len(value)<=4 and all(math.isfinite(v) and 0<=v<=1 for v in value.values()) for value in actual)
 if name==SHIRT:
  for i in components[1]:assert not any(group.startswith(('Arm_','Forearm_')) for group in actual[i])
bpy.context.view_layer.update();after=f.objects()
assert before['objects'].keys()==after['objects'].keys()
for name,old in before['objects'].items():
 new=after['objects'][name]
 allowed={'geometry_sha256','geometry_contract_sha256'} if name in OWNED else set()
 assert {k:v for k,v in old.items() if k not in allowed}=={k:v for k,v in new.items() if k not in allowed},('Protected object fact',name)
for name in OWNED:
 old,new=before['owned'][name],after['owned'][name]
 assert {k:v for k,v in old.items() if k!='weights'}=={k:v for k,v in new.items() if k!='weights'},('Protected native geometry',name)
assert f.digest(material_facts())==material_before
assert all(report['weight_changes'][name]['changed_vertices'] for name in OWNED)
report['material_sha256']=material_before;report['protected_native_objects']=356
report['limits']='Weight-only unrendered candidate. Harmonic/support choices need the unchanged28-view actual production pose gate; no solved reach, LOD, continuous-collision or promotion claim.'
(OUT/'art').mkdir(parents=True)
(OUT/'author_report.json').write_text(json.dumps(report,indent=2)+'\n')
(OUT/'object_facts.json').write_text(json.dumps({'before':before['objects'],'after':after['objects']},indent=2)+'\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'art/characters.blend'))
for item in spec.values():assert f.sha(Path(item['path']))==item['sha256']
print('CASUAL_WEIGHT_CANDIDATE',len(OWNED),'owned weight arrays; source geometry exact; visual gate pending')
