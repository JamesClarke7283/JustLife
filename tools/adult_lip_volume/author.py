"""Reproduce the reviewed fuller-height adult lips from the pinned V4 Blend.

Run through generate.py to retain isolation, input pins and native material checks.
"""
from pathlib import Path
import argparse, bisect, json, math, struct, sys
sys.dont_write_bytecode = True
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'adult_eyes'))
sys.path.insert(0, str(HERE.parent / 'adult_face_volume'))
import source_facts as w
import smile_field
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
SOURCE = args.source.resolve()
PIN = '5b88ef9f415be618ce1586b49ea51a5086ddc660a460430b1752ce6e3ae2c42e'
assert w.sha(SOURCE) == PIN
out = args.output.resolve()
assert not out.exists()
(out / 'art').mkdir(parents=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
OWNED=['Lips_Upper_soft','Lips_Lower_soft','Lips_Smile_seam'];w.OWNED=set(OWNED)
before=w.objects();old={};head=bpy.data.objects['Skin_Head_continuous']
head_points=[head.matrix_world@v.co for v in head.data.shape_keys.key_blocks['Basis'].data]
head_tree=BVHTree.FromPolygons(head_points,[list(p.vertices) for p in head.data.polygons])
for name in OWNED:
 o=bpy.data.objects[name];o.data.calc_loop_triangles();keys=o.data.shape_keys.key_blocks
 old[name]={'mesh':[v.co.copy() for v in o.data.vertices],
            'keys':{k.name:[v.co.copy() for v in k.data] for k in keys},
            'world':[o.matrix_world@v.co for v in keys['Basis'].data],
            'triangles':[list(t.vertices) for t in o.data.loop_triangles]}
def support(x,z):
 hit,_,_,_=head_tree.ray_cast(Vector((x,-1,z)),Vector((0,1,0)),2)
 assert hit is not None and hit.y<-.05,('head support',x,z)
 return float(hit.y)
def smooth(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*t*(t*(t*6-15)+10)
def side(x):return 1-smooth(.70,.96,abs(x)/.030030004680156708)
report={'source_sha256':PIN,'scope':'Only three lip/seam meshes; head/chin, width, corners and contact anchor fixed. Shared positive vertical expansion around the actual join, depth refitted to head Basis, reduced seam sections. One unrendered trial.',
        'relative_rounding':[],'mesh_basis_rounding':[],'changes':{},'failures':[],
        'profile':{'inner_protrusion_m':.00110,'root_protrusion_m':-.00012,'upper_roll_m':.00175,'lower_roll_m':.00210,
                   'curve':'inner*(1-S(f)) + root*S(f) + roll*16*f^2*(1-f)^2; f from actual current front-sheet bounds',
                   'shell':'One common positive Z map at each actual X/Z; old front field sampled at original Z, head Basis at mapped Z; no i+585 coordinate replacement.',
                   'side_fade':'C2 fade at |x| / existing half-width .70..96; corner vertices remain unchanged'},
        'seam':{'depth_scale':.24,'height_scale':.24,'centers':'Original native-local coordinate sums are exact; transformed per-vertex float32 world-mean differences are explicitly recorded, with the contact anchor unchanged.'}}
def install(name,targets):
 o=bpy.data.objects[name];snapshot=old[name];keys=o.data.shape_keys.key_blocks
 deltas=[new-prior for new,prior in zip(targets,snapshot['keys']['Basis'])]
 for i,d in enumerate(deltas):
  o.data.vertices[i].co=snapshot['mesh'][i]+d
  for k in keys:k.data[i].co=snapshot['keys'][k.name][i]+d
 o.data.update()
 assert all(keys['Basis'].data[i].co==targets[i] for i in range(len(targets)))
 for k in keys:
  for i,v in enumerate(k.data):
   prior=[float(snapshot['keys'][k.name][i][j])-float(snapshot['keys']['Basis'][i][j]) for j in range(3)]
   now=[float(v.co[j])-float(keys['Basis'].data[i].co[j]) for j in range(3)]
   if prior!=now:report['relative_rounding'].append([name,k.name,i,prior,now])
 for i,v in enumerate(o.data.vertices):
  prior=[float(snapshot['mesh'][i][j])-float(snapshot['keys']['Basis'][i][j]) for j in range(3)]
  now=[float(v.co[j])-float(keys['Basis'].data[i].co[j]) for j in range(3)]
  if prior!=now:report['mesh_basis_rounding'].append([name,i,prior,now])
 report['changes'][name]={'changed_vertices':[i for i,d in enumerate(deltas) if d.length>0],
                          'maximum_local_displacement':max(d.length for d in deltas)}
def interpolate(z,rows):
 if z<=rows[0][0]:return rows[0][1]
 if z>=rows[-1][0]:return rows[-1][1]
 i=bisect.bisect_left([v[0] for v in rows],z);a,b=rows[i-1],rows[i]
 return a[1]+(b[1]-a[1])*((z-a[0])/(b[0]-a[0]))
def front_columns(name):
 points=old[name]['world'];half=len(points)//2;assert half==585
 groups=[]
 for i in sorted(range(half),key=lambda i:points[i].x):
  if not groups or abs(points[i].x-points[groups[-1][0]].x)>1e-7:groups.append([])
  groups[-1].append(i)
 return [(math.fsum(float(points[i].x) for i in ids)/len(ids),sorted((float(points[i].z),float(points[i].y)) for i in ids),ids) for ids in groups]
all_columns={name:front_columns(name) for name in OWNED[:2]}
join_rows=[(x,rows[0][0]) for x,rows,ids in all_columns['Lips_Upper_soft']]
def join_z(x):return interpolate(x,join_rows)
report['height']={'central_scale':1.45,'scale_range':[1.,1.45],'map':'join_z(x)+(1+.45*side(x))*(old_z-join_z(x))','join':'Piecewise-linear actual upper front-sheet inner boundary, shared by upper/lower/front/back/bridge; original joined rows reported separately.'}
for name,upper in [('Lips_Upper_soft',True),('Lips_Lower_soft',False)]:
 o=bpy.data.objects[name];points=old[name]['world'];half=len(points)//2
 columns=all_columns[name];xs=[v[0] for v in columns]
 def front_field(x,z):
  j=min(len(columns)-1,max(1,bisect.bisect_left(xs,x)))
  a,b=columns[j-1],columns[j];t=max(0.,min(1.,(x-a[0])/(b[0]-a[0])))
  lo=a[1][0][0]+(b[1][0][0]-a[1][0][0])*t
  hi=a[1][-1][0]+(b[1][-1][0]-a[1][-1][0])*t
  old_y=interpolate(z,a[1])+(interpolate(z,b[1])-interpolate(z,a[1]))*t
  f=max(0.,min(1.,(z-lo)/(hi-lo))) if hi>lo else 1.
  if not upper:f=1-f
  return old_y,f
 inv=o.matrix_world.to_3x3().inverted();targets=[]
 for i,p in enumerate(points):
  amount=side(p.x)
  if amount==0:targets.append(old[name]['keys']['Basis'][i].copy());continue
  old_y,f=front_field(p.x,p.z);s=smooth(0,1,f)
  relief=.00110*(1-s)-.00012*s+(.00175 if upper else .00210)*16*f*f*(1-f)*(1-f)
  joined=join_z(p.x);mapped_z=joined+(1+.45*amount)*(float(p.z)-joined)
  old_head=support(p.x,p.z);new_head=support(p.x,mapped_z)
  dy=(new_head-old_head)+(old_head-relief-old_y)*amount
  local=inv@Vector((0,dy,mapped_z-float(p.z)));assert local.x==0
  local.y=round(local.y/(2**-22))*(2**-22);local.z=round(local.z/(2**-22))*(2**-22)
  targets.append(old[name]['keys']['Basis'][i]+local)
 install(name,targets)
 assert all((o.matrix_world@v.co).x==old[name]['world'][i].x for i,v in enumerate(o.data.shape_keys.key_blocks['Basis'].data))
 for i,p in enumerate(points):
  if side(p.x)==0:assert o.data.shape_keys.key_blocks['Basis'].data[i].co==old[name]['keys']['Basis'][i]

# Shrink each native seam section about its actual center. Preserve native-local
# sums and anchor; report derived float32 world-mean rounding without redistribution.
name='Lips_Smile_seam';o=bpy.data.objects[name];basis=old[name]['keys']['Basis'];targets=[p.copy() for p in basis]
assert len(basis)%8==0
for first in range(0,len(basis),8):
 ids=list(range(first,first+8));center=[math.fsum(float(basis[i][j]) for i in ids)/8 for j in range(3)]
 world_center=[math.fsum(float(old[name]['world'][i][j]) for i in ids)/8 for j in range(3)]
 amount=side(world_center[0]);scale=1-.76*amount
 if amount==0:continue
 for axis in [1,2]:
  original_sum=math.fsum(float(basis[i][axis]) for i in ids)
  for i in ids:targets[i][axis]=center[axis]+(float(basis[i][axis])-center[axis])*scale
  targets[ids[-1]][axis]=original_sum-math.fsum(float(targets[i][axis]) for i in ids[:-1])
  assert math.fsum(float(targets[i][axis]) for i in ids)==original_sum
install(name,targets)
bpy.context.view_layer.update();after=w.objects()
for name,facts in before['objects'].items():
 for key,value in facts.items():
  if name in OWNED and key=='geometry_sha256':continue
  if after['objects'][name][key]!=value:report['failures'].append([name,key])
assert before['objects'].keys()==after['objects'].keys() and not report['failures'],report['failures']

# Existing Smile vectors remain appropriate: all edited points stay in the same
# shared mouth plateau, so the actual authored field is exactly unchanged.
params=json.loads((HERE.parent/'adult_face_volume/contract.json').read_text())['smile_parameters'];pivot=Vector((0,.005,1.458))
smile_changes=[];sections={};geometry={};shell={}
def cut(points,triangles,x):
 result=[]
 for ids in triangles:
  vs=[points[i] for i in ids];hits=[]
  for a,b in zip(vs,vs[1:]+vs[:1]):
   if a.x==x:hits.append(a)
   if (a.x-x)*(b.x-x)<0:hits.append(a+(b-a)*((x-a.x)/(b.x-a.x)))
  unique=[]
  for v in hits:
   if not any(v==q for q in unique):unique.append(v)
  if len(unique)==2:result.append([list(v) for v in unique])
 return result
for name in OWNED:
 o=bpy.data.objects[name];current=[o.matrix_world@v.co for v in o.data.shape_keys.key_blocks['Basis'].data]
 for i,(a,b) in enumerate(zip(old[name]['world'],current)):
  prior=smile_field.smile_delta(pivot+(a-pivot)/.91,**params);now=smile_field.smile_delta(pivot+(b-pivot)/.91,**params)
  if prior!=now:smile_changes.append([name,i,prior,now])
 o.data.calc_loop_triangles();triangles=[list(t.vertices) for t in o.data.loop_triangles];flips=[];collapsed=[];turns=[]
 for ids in triangles:
  a,b,c=[old[name]['world'][i] for i in ids];d,e,f=[current[i] for i in ids];n0=(b-a).cross(c-a);n1=(e-d).cross(f-d)
  if n0.y*n1.y<0:flips.append(ids)
  if n0.length>1e-12 and n1.length<1e-12:collapsed.append(ids)
  if n0.dot(n1)<0:turns.append(ids)
 geometry[name]={'triangles':len(triangles),'projected_XZ_sign_changes':flips,'new_collapsed':collapsed,'normal_over90':turns}
 sections[name]={'before':{str(x):cut(old[name]['world'],triangles,x) for x in [0,.0091,.0182,.026]},'after':{str(x):cut(current,triangles,x) for x in [0,.0091,.0182,.026]}}
 if name!='Lips_Smile_seam':
  half=len(current)//2
  faces=[[list(f.vertices) for f in o.data.polygons if all((i<half)==front for i in f.vertices)] for front in [True,False]]
  scans=[]
  for phase,pts in [('before',old[name]['world']),('after',current)]:
   trees=[BVHTree.FromPolygons(pts,fs) for fs in faces];rows=[]
   for x in [0,.0091,.0182,.026,-.0091,-.0182,-.026]:
    for k in range(101):
     z=1.497+k*.00020;hits=[tree.ray_cast(Vector((x,-1,z)),Vector((0,1,0)),2)[0] for tree in trees]
     if all(v is not None for v in hits):rows.append({'x':x,'z':z,'signed_back_minus_front':float(hits[1].y-hits[0].y)})
   scans.append((phase,rows))
  shell[name]=dict(scans)
report['smile_policy']={'existing_relative_deltas_translated_with_Basis':True,'actual_shared_field_changed_points':smile_changes}
report['geometry']=geometry;report['shell_scans']=shell
report['seam']['native_ring_ids']=list(range(384,392))
report['seam']['before_center']=[math.fsum(float(old['Lips_Smile_seam']['world'][i][j]) for i in range(384,392))/8 for j in range(3)]
seam=bpy.data.objects['Lips_Smile_seam'];report['seam']['after_center']=[math.fsum(float((seam.matrix_world@seam.data.shape_keys.key_blocks['Basis'].data[i].co)[j]) for i in range(384,392))/8 for j in range(3)]
ring_means=[]
for first in range(0,len(old['Lips_Smile_seam']['world']),8):
 ids=list(range(first,first+8))
 prior_local=[math.fsum(float(old['Lips_Smile_seam']['keys']['Basis'][i][j]) for i in ids)/8 for j in range(3)]
 now_local=[math.fsum(float(seam.data.shape_keys.key_blocks['Basis'].data[i].co[j]) for i in ids)/8 for j in range(3)]
 prior_world=[math.fsum(float(old['Lips_Smile_seam']['world'][i][j]) for i in ids)/8 for j in range(3)]
 now_world=[math.fsum(float((seam.matrix_world@seam.data.shape_keys.key_blocks['Basis'].data[i].co)[j]) for i in ids)/8 for j in range(3)]
 assert prior_local==now_local
 ring_means.append({'ids':ids,'old_native_local':prior_local,'new_native_local':now_local,'old_float32_world_mean':prior_world,'new_float32_world_mean':now_world,'world_mean_difference':[b-a for a,b in zip(prior_world,now_world)]})
report['seam']['ring_means']=ring_means
report['seam']['max_float32_world_mean_difference']=max(abs(v) for row in ring_means for v in row['world_mean_difference'])
report['seam']['central_native_local_exact']=ring_means[48]['old_native_local']==ring_means[48]['new_native_local']
report['seam']['mouth_anchor']=list(bpy.data.objects['Character']['mouth_anchor'])
join_pairs=[]
upper_points=old['Lips_Upper_soft']['world'];lower_points=old['Lips_Lower_soft']['world']
for x,rows,ids in all_columns['Lips_Upper_soft']:
 ui=min(ids,key=lambda i:upper_points[i].z)
 li=min(range(585),key=lambda i:abs(lower_points[i].x-upper_points[ui].x)+abs(lower_points[i].z-upper_points[ui].z))
 ua=bpy.data.objects['Lips_Upper_soft'].matrix_world@bpy.data.objects['Lips_Upper_soft'].data.shape_keys.key_blocks['Basis'].data[ui].co
 la=bpy.data.objects['Lips_Lower_soft'].matrix_world@bpy.data.objects['Lips_Lower_soft'].data.shape_keys.key_blocks['Basis'].data[li].co
 join_pairs.append({'ids':[ui,li],'before_upper':list(upper_points[ui]),'before_lower':list(lower_points[li]),'after_upper':list(ua),'after_lower':list(la),'before_gap_m':(upper_points[ui]-lower_points[li]).length,'after_gap_m':(ua-la).length})
report['joined_rim_pairs']=join_pairs
report['height']['actual_center_rows']={}
report['attachment_rows']={}
for name in OWNED[:2]:
 o=bpy.data.objects[name];upper=name=='Lips_Upper_soft';rows=[];attachments=[]
 for x,values,ids in all_columns[name]:
  if abs(x)<1e-7:
   for i in sorted(ids,key=lambda i:old[name]['world'][i].z):
    p=o.matrix_world@o.data.shape_keys.key_blocks['Basis'].data[i].co
    rows.append({'id':i,'before':list(old[name]['world'][i]),'after':list(p),'actual_head_y':support(p.x,p.z),'protrusion_m':support(p.x,p.z)-float(p.y)})
  edge=max(ids,key=lambda i:old[name]['world'][i].z) if upper else min(ids,key=lambda i:old[name]['world'][i].z)
  p=o.matrix_world@o.data.shape_keys.key_blocks['Basis'].data[edge].co
  attachments.append({'id':edge,'world':list(p),'signed_head_protrusion_m':support(p.x,p.z)-float(p.y)})
 report['height']['actual_center_rows'][name]=rows;report['attachment_rows'][name]=attachments
assert not smile_changes,smile_changes[:3]
(out/'author_report.json').write_text(json.dumps(report,indent=2)+'\n')
(out/'object_facts.json').write_text(json.dumps({'before':before['objects'],'after':after['objects']},indent=2)+'\n')
(out/'sections.json').write_text(json.dumps(sections,indent=2)+'\n')
assert all(not geometry[name]['projected_XZ_sign_changes'] and not geometry[name]['new_collapsed'] for name in OWNED[:2]),geometry
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(out/'art/characters.blend'))
assert w.sha(SOURCE)==PIN
print('LIP_ROLL_CANDIDATE',json.dumps({'changed':{n:len(v['changed_vertices']) for n,v in report['changes'].items()},'relative_roundings':len(report['relative_rounding']),'mesh_basis_roundings':len(report['mesh_basis_rounding']),'seam':report['seam'],'geometry':geometry}))
