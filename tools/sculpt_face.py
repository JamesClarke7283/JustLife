"""Reproduce the original JustLife adult local eye/lip revision23.

Use a fresh Blender process with the qualified authoring/export boundary:
blender --background --factory-startup -t 6 --python-exit-code 2 \
  --python tools/sculpt_face.py -- --source art/source/face_v23/characters_clothing_v22.blend \
  --output-root /absolute/new/output

The hash-pinned input is immutable. Output must be a separate new/empty folder.
Only adult art/characters.blend and four adult GLBs, plus audits, are emitted.
"""
import bpy,math,json,hashlib,struct,sys,argparse,subprocess
from pathlib import Path
from mathutils import Vector
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--output-root',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
SOURCE=args.source.resolve();P=args.output_root.resolve();TOOLS=Path(__file__).resolve().parent
launch_args=sys.argv[:sys.argv.index('--')]
thread_flag='-t' if '-t' in launch_args else '--threads'
assert thread_flag in launch_args and launch_args[launch_args.index(thread_flag)+1]=='6','Use the documented fresh authoring process with -t 6'
assert '--background' in launch_args and '--factory-startup' in launch_args,'Use a fresh background factory-startup process'
PIN='6de0bf9235efd9f9768ec1ca59945066cbec151b0364313fdd7c1c11f1a3d74f'
assert SOURCE!=P and P not in SOURCE.parents,'Output tree must not contain immutable input'
assert not P.exists() or (P.is_dir() and not any(P.iterdir())),'Choose a new or empty output directory'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==PIN,'Requires exact approved clothing-v22 adult source'
TABLE_PIN='1943d18d1654f714db9ff9ae71d814e91b9b2373deeba38d6e2839b5eb10a963'
TABLE=TOOLS/'face_v23_socket.json'
assert hashlib.sha256(TABLE.read_bytes()).hexdigest()==TABLE_PIN,'Socket table changed; review before authoring'
plan=json.loads(TABLE.read_text())
assert plan['revision']==23 and plan['object']=='Skin_Head_continuous'
assert len(plan['changes'])==289 and len(plan['allowed_basis_ids'])==292
assert len({c['index'] for c in plan['changes']})==289
for sub in ['art','assets/models','evidence']:(P/sub).mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
assert bpy.data.objects['Character']['rig_version']==18 and bpy.data.objects['Character']['surface_revision']==2
anchor=Vector((0,.005,1.458));scale=.91
IDENTITY={'Face_Round','Jaw_Strong','Nose_Wide','Eye_Spacing'}
OWNED={'Skin_Head_continuous','Skin_Upper_lid_-1','Skin_Upper_lid_1','Lips_Upper_soft','Lips_Lower_soft'}
def smooth(a,b,t):
 t=max(0,min(1,(t-a)/(b-a)));return t*t*(3-2*t)
def unscale(world):return anchor+(world-anchor)/scale
def quant(v):return Vector(tuple(round(x/(2**-22))*(2**-22) for x in v))
def local_delta(o,delta):return quant(o.matrix_world.to_3x3().inverted()@(delta*scale))
def shape_deltas(o):
 keys=o.data.shape_keys.key_blocks;base=keys['Basis'].data
 return {k.name:[tuple(float(p.co[j])-float(b.co[j]) for j in range(3)) for p,b in zip(k.data,base)] for k in keys if k.name in IDENTITY or (k.name=='Smile')}
def head_weight(p):
 side=-1 if p.x<0 else 1;dx=p.x-side*.047
 if abs(dx)>=.030:return 0.0
 arch=math.sqrt(max(0,1-(dx/.030)**2))
 drop=(1.611+dx*.065*side-p.z)/max(.1,arch)
 return smooth(.006,.010,drop)*(1-smooth(.020,.030,drop))*smooth(.03,.25,arch)*(1-smooth(-.070,-.030,p.y))*arch

def lip_delta(p,upper):
 q=abs(p.x)/.033;full=max(0,1-q*q)
 if q>=.94 or full<.01:return Vector()
 seam=1.512+.0065*q*q
 contour=(.0047*full+.0016*math.exp(-((abs(p.x)-.011)/.006)**2)) if upper else -.006*full
 f=max(0,min(1,(p.z-seam)/contour))
 # A broad, low projection keeps the existing seam and outer attachment exact.
 plane=math.sin(math.pi*f)**1.25
 corners=1-smooth(.80,.94,q)
 return Vector((0,-(.0007 if upper else .0010)*plane*(full**1.15)*corners,0))

def lid_fields(p,side):
 dx=p.x-side*.047
 arch=math.sqrt(max(0,1-(dx/.030)**2))
 if arch<.04:return Vector(),Vector()
 inner=1.611+dx*.065*side+.010*arch
 f=max(0,min(1,(p.z-inner)/(.012*arch)))
 corner=smooth(.04,.25,arch)
 margin_drop=.0028*arch
 old_margin=.008-.108*max(.01,1-(p.x/.111)**2)**.15-.0048*arch
 globe_margin=-.0775-.026*math.sqrt(max(0,1-(dx/.028)**2-((inner-margin_drop-1.611)/.014)**2))-.00085
 recess=min(.0045,max(-.0020,globe_margin-old_margin))*((1-f)**1.5)*corner
 opened=Vector((0,recess,-margin_drop*((1-f)**1.5)*corner))
 # Full Blink has already retreated the unchanged globe by12mm. Recess the
 # formerly raised lid panel toward that socket while fixing the outer edge.
 closed=(.0013*(1-f)+.0030*math.sin(math.pi*f)**1.5)*arch*corner
 return opened,Vector((0,closed,0))

source_key_values={o.name:{k.name:k.value for k in o.data.shape_keys.key_blocks} for o in bpy.data.objects if o.type=='MESH' and o.data.shape_keys}
before={};report={'source_sha256':PIN,'owned_objects':sorted(OWNED),'changes':{},'identity_failures':[],'scope':'First authored stage of revision23: local lower-orbital attachment,2.8mm central open upper-margin lowering in authored coordinates with unchanged closed height, recessed full-Blink surface and small rounded lip projection. The compact upper-socket attachment table is applied next. Seam, eye objects, corners, rig and garments protected.'}
for name in sorted(OWNED):
 o=bpy.data.objects[name];keys=o.data.shape_keys.key_blocks
 assert all(k.relative_key==keys['Basis'] for k in keys if k.name!='Basis')
 basis=[v.co.copy() for v in keys['Basis'].data];oldkeys={k.name:[v.co.copy() for v in k.data] for k in keys};identity=shape_deltas(o)
 points=[unscale(o.matrix_world@v) for v in basis];deltas=[Vector() for v in basis];closed=[Vector() for v in basis]
 if name=='Skin_Head_continuous':
  weights=[head_weight(p) for p in points];adj=[set() for p in points]
  for poly in o.data.polygons:
   ids=list(poly.vertices)
   for a,b in zip(ids,ids[1:]+ids[:1]):adj[a].add(b);adj[b].add(a)
  ys=[p.y for p in points];relaxed=ys[:]
  for iteration in range(3):
   relaxed=[y+.4*weights[i]*(sum(relaxed[j] for j in adj[i])/len(adj[i])-y) if adj[i] and weights[i]>0 else y for i,y in enumerate(relaxed)]
  for i,(p,w) in enumerate(zip(points,weights)):
   ease=.0018*w+max(-.0005,min(.0005,relaxed[i]-ys[i]))*w
   deltas[i]=local_delta(o,Vector((0,ease,0))) if w>0 else Vector()
 elif name.startswith('Lips_'):
  deltas=[local_delta(o,lip_delta(p,name=='Lips_Upper_soft')) for p in points]
 else:
  side=-1 if name.endswith('-1') else 1
  for i,p in enumerate(points):
   # Original vertices with zero Blink displacement define the fixed outer/corner boundary.
   if oldkeys['Blink'][i]==basis[i]:continue
   opened,shut=lid_fields(p,side);deltas[i]=local_delta(o,opened);closed[i]=local_delta(o,shut)
 for i,delta in enumerate(deltas):
  o.data.vertices[i].co+=delta
  for key in keys:key.data[i].co=oldkeys[key.name][i]+delta
  if name.startswith('Skin_Upper_lid'):keys['Blink'].data[i].co=oldkeys['Blink'][i]+closed[i]
 o.data.update()
 after_identity=shape_deltas(o)
 for key,values in identity.items():
  changed=[i for i,(a,b) in enumerate(zip(values,after_identity[key])) if a!=b]
  if changed:report['identity_failures'].append({'object':name,'key':key,'vertices':changed,'max_delta':max(abs(a-b) for i in changed for a,b in zip(values[i],after_identity[key][i]))})
 changed=[i for i,(a,b) in enumerate(zip(basis,keys['Basis'].data)) if a!=b.co]
 blink_changed=[i for i,(a,b) in enumerate(zip(oldkeys.get('Blink',[]),keys['Blink'].data if keys.get('Blink') else [])) if a!=b.co]
 report['changes'][name]={'basis_vertices':changed,'blink_target_vertices':blink_changed,'total_vertices':len(basis),'maximum_basis_delta':max((d.length for d in deltas),default=0),'maximum_closed_target_delta':max((d.length for d in closed),default=0)}

assert not report['identity_failures'],report['identity_failures']
(P/'evidence/local_face_edit.json').write_text(json.dumps(report,indent=2)+'\n')
# Apply the measured upper-orbital attachment to the exact intermediate sculpt.
# Mesh coordinates and each key retain their original, possibly different Basis offset.
bpy.context.view_layer.update()
o=bpy.data.objects[plan['object']];keys=o.data.shape_keys.key_blocks;basis=keys['Basis']
key_before={k.name:[p.co.copy() for p in k.data] for k in keys};mesh_before=[v.co.copy() for v in o.data.vertices]
for change in plan['changes']:
 i=change['index'];assert i in plan['allowed_basis_ids']
 assert list(basis.data[i].co)==change['basis_before'],('Intermediate Basis drift',i)
 d=Vector(change['delta']);assert d.x==0 and d.z==0 and 0<d.y<=.001419
 o.data.vertices[i].co+=d
 for k in keys:k.data[i].co+=d
changed={c['index'] for c in plan['changes']}
for i in range(len(basis.data)):
 if i not in changed:
  assert o.data.vertices[i].co==mesh_before[i]
  assert all(k.data[i].co==key_before[k.name][i] for k in keys)
 for k in keys:
  previous=tuple(float(key_before[k.name][i][j])-float(key_before['Basis'][i][j]) for j in range(3))
  current=tuple(float(k.data[i].co[j])-float(basis.data[i].co[j]) for j in range(3))
  assert previous==current,('Relative head morph drift',i,k.name)
o.data.update();bpy.context.view_layer.update()
assert source_key_values=={o.name:{k.name:k.value for k in o.data.shape_keys.key_blocks} for o in bpy.data.objects if o.type=='MESH' and o.data.shape_keys},'Source key values changed'
bpy.context.preferences.filepaths.save_version=0
blend=P/'art/characters.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
blend_sha256=hashlib.sha256(blend.read_bytes()).hexdigest()
launch={'authoring_argv':sys.argv,'blender_version':bpy.app.version_string,'blender_build_hash':bpy.app.build_hash.decode(),'binary_sha256':hashlib.sha256(Path(bpy.app.binary_path).read_bytes()).hexdigest(),'exports':[]}
for stem in ['character','character_broad','character_lod','character_broad_lod']:
 command=[bpy.app.binary_path,'--background','--factory-startup','-t','1','--python-exit-code','2','--python',str(TOOLS/'export_face_variant.py'),'--','--source',str(blend),'--source-sha256',blend_sha256,'--output-root',str(P/'assets/models'),'--variant',stem]
 item={'variant':stem,'command':command,'returncode':None};launch['exports'].append(item)
 (P/'evidence/export_launch.json').write_text(json.dumps(launch,indent=2)+'\n')
 with (P/'evidence'/('export_'+stem+'.log')).open('w') as log:
  result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=False)
 item['returncode']=result.returncode
 (P/'evidence/export_launch.json').write_text(json.dumps(launch,indent=2)+'\n')
 assert result.returncode==0,'Variant export failed; raw output/log retained: '+stem
sys.path.insert(0,str(TOOLS))
from verify_face_exports import verify_all
verified=verify_all(P/'assets/models')
outputs=['art/characters.blend']+['assets/models/'+stem+'.glb' for stem in ['character','character_broad','character_lod','character_broad_lod']]
manifest={'face_revision':23,'rig_version':18,'surface_revision':2,'garment_revision':22,'source_sha256':PIN,'blender_version':bpy.app.version_string,'blender_build_hash':bpy.app.build_hash.decode(),'blender_binary_sha256':launch['binary_sha256'],'authoring_threads':6,'export_threads':1,'sources':{name:hashlib.sha256((TOOLS/name).read_bytes()).hexdigest() for name in ['sculpt_face.py','face_v23_socket.json','export_face_variant.py','verify_face_exports.py']},'outputs':{name:hashlib.sha256((P/name).read_bytes()).hexdigest() for name in outputs},'decoded_output_digests':verified,'owned_objects':sorted(OWNED),'upper_socket_basis_ids':sorted(changed),'scope':'Original adult upper-lid/lip surface sculpt and two bounded head-orbital masks. Eye geometry, seam/corners, identity POSITION deltas, rig, hair, garments and all nonadult assets remain protected; only upper-lid Blink target changes.'}
(P/'face_v23_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==PIN
print('FACE_EXPORT_COMPLETE',len(OWNED),'owned objects;',len(changed),'upper-socket Basis edits; four decoded guards exact')
