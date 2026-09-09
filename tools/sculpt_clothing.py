"""Reproduce original JustLife adult garment revision 22 from immutable v18 source.

blender --background --factory-startup -t 6 --python-exit-code 2 \
  --python tools/sculpt_clothing.py -- --source art/source/clothing_v22/characters_v18.blend \
  --output-root /absolute/new/output

Output includes adult art/characters.blend, four adult GLBs and audit sidecars.
The input must match the accepted v18 hash and cannot be inside the output tree.
"""
import bpy, math, json, hashlib, struct, os, tempfile, argparse, sys, subprocess
from pathlib import Path
from mathutils import Vector
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--output-root',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
SOURCE=args.source.resolve();P=args.output_root.resolve()
assert SOURCE!=P and P not in SOURCE.parents,'Output tree must not contain the immutable source'
assert not P.exists() or not any(P.iterdir()),'Choose a new or empty output directory'
EXPECTED='bab2d4e1a261a6b12cbf4c913e59a62f05890b06ab5b54cadee07d545588a81f'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==EXPECTED,'Requires exact accepted v18 adult source'
for sub in ['art','assets/models','evidence']:(P/sub).mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
root=bpy.data.objects['Character']
assert root['rig_version']==18 and root['surface_revision']==2

def smooth(a,b,t):
 t=max(0,min(1,(t-a)/(b-a)));return t*t*(3-2*t)
def gauss(t,c,w):return math.exp(-((t-c)/w)**2)
def sign(t):return -1 if t<0 else 1

def shirt_delta(p):
 x,y,z=p;ax=abs(x);s=sign(x);d=Vector()
 torso=1-smooth(.145,.196,ax)
 # Ease below chest, retaining broad fullness and the original neck/placket.
 ease=gauss(z,1.14,.10)*torso
 d.x=s*.007*ease*smooth(.065,.125,ax)
 d.y=sign(y)*.007*ease*smooth(.02,.07,abs(y))
 # A shoulder falls from the neck into a sewn sleeve, rather than a round cap.
 d.z-=.020*gauss(ax,.184,.052)*gauss(z,1.367,.037)
 sleeve=smooth(.153,.215,ax)*gauss(z,1.275,.10)
 d.y-=y*.075*sleeve
 d.x-=s*.010*gauss(z,1.31,.063)*smooth(.221,.25,ax)
 # Shallow physical armhole inset; the original continuous skinning is retained.
 seam_x=.154+.27*(1.372-z)
 seam=gauss(ax,seam_x,.008)*smooth(1.22,1.26,z)*(1-smooth(1.385,1.40,z))
 d.y-=sign(y)*.0054*seam*smooth(.019,.045,abs(y))
 # Give the lower sleeve a calm lengthwise fold ending in a defined opening.
 angle=math.atan2(y-.005,ax-(.205+.15*(1.28-z)))
 crease=.0026*math.cos(3*angle+.4)*gauss(z,1.188,.039)*smooth(.163,.20,ax)
 d.x+=s*math.cos(angle)*crease;d.y+=math.sin(angle)*crease
 # Relaxed shaped hem, with a small side rise and visible folded edge.
 hem=gauss(z,1.045,.034)*torso
 d.z+=hem*(.009*smooth(.10,.15,ax)-.004*(1-smooth(.02,.11,ax)))
 d.y+=sign(y)*.003*hem*smooth(.02,.055,abs(y))
 # Sparse compression folds arise at the side waist, with broad fall between.
 front=1-smooth(-.055,-.012,y)
 line=1.077+.44*(ax-.065)
 ridge=(gauss(z,line,.008)-.50*gauss(z,line+.012,.009))*gauss(ax,.103,.045)
 d.y-=.0048*ridge*front
 d.y-=.0023*gauss(x,.072,.014)*gauss(z,1.19,.10)*front
 return d

def cardigan_hem_delta(p):
 # Ease only the original lower rear and rear-side hem over the fuller trousers.
 ease=smooth(.004,.062,p.y)*(1-smooth(.985,1.145,p.z))
 return Vector((sign(p.x)*.010*ease*smooth(.105,.16,abs(p.x)),.028*ease,-.017*ease))

def profile(z,points):
 for i in range(len(points)-1):
  a,av=points[i];b,bv=points[i+1]
  if z<=b:
   t=max(0,min(1,(z-a)/(b-a)));return av+(bv-av)*t
 return points[-1][1]

def pants_delta(p):
 x,y,z=p;ax=abs(x);s=sign(x);d=Vector()
 # Relaxed trousers fall from the accepted hip to a slightly open shoe break.
 # Broad, smoothly varying cross sections replace local circumferential ridges.
 center=.089-.013*smooth(.60,.95,z);lx=ax-center;dy=y-.012
 old_w=profile(z,[(.12,.0405),(.15,.0445),(.30,.048),(.48,.055),(.64,.065),(.78,.077),(.88,.081)])
 new_w=profile(z,[(.12,.049),(.30,.0515),(.48,.0575),(.64,.067),(.78,.0785),(.88,.082)])
 old_d=profile(z,[(.12,.044),(.15,.046),(.30,.053),(.48,.059),(.64,.072),(.78,.081),(.88,.086)])
 new_d=profile(z,[(.12,.049),(.30,.054),(.48,.061),(.64,.074),(.78,.083),(.88,.086)])
 leg=1-smooth(.80,.93,z)
 d.x+=s*lx*(new_w/old_w-1)*leg
 d.y+=dy*(new_d/old_d-1)*leg
 # A single shallow pressed plane along each front leg, fading before the hip.
 # Its very broad fall is non-periodic and does not form a knee ring.
 front=1-smooth(-.050,-.016,y)
 d.y-=.0023*gauss(lx,0,.026)*gauss(z,.58,.27)*front
 # The accepted fused hip had two sphere-like thigh crowns. Re-drape the front
 # fabric over their junction while retaining side and rear hip fullness.
 # The shaped crotch is still present below this panel; no anatomy is moved.
 ellipse=.010-.087*math.sqrt(max(.02,1-(min(ax,.162)/.166)**2))
 plane=smooth(.841,.903,z)*(1-smooth(.965,1.023,z))*front
 d.y+=(ellipse-y)*plane*.72
 # Subtle diagonal tension under each pocket, broad enough for the LOD surface.
 tension=gauss(z,.955-.38*ax,.030)*gauss(ax,.105,.047)*front
 d.y-=.0022*tension
 return d

def serial(v):
 if hasattr(v,'to_list'):return v.to_list()
 if isinstance(v,(str,int,float,bool)):return v
 try:return list(v)
 except:return str(v)
def mesh_digest(o,include_co=True):
 h=hashlib.sha256()
 def f(v):h.update(struct.pack('<f',v))
 if o.type=='MESH':
  for v in o.data.vertices:
   if include_co:
    for q in v.co:f(q)
   for g in v.groups:h.update(struct.pack('<If',g.group,g.weight))
  for poly in o.data.polygons:
   h.update(struct.pack('<I',poly.material_index));h.update(bytes([poly.use_smooth]))
   for i in poly.vertices:h.update(struct.pack('<I',i))
  for layer in o.data.uv_layers:
   h.update(layer.name.encode())
   for uv in layer.data:
    for q in uv.uv:f(q)
  if o.data.shape_keys:
   for key in o.data.shape_keys.key_blocks:
    h.update(key.name.encode())
    if include_co:
     for point in key.data:
      for q in point.co:f(q)
 elif o.type=='CURVE':
  for sp in o.data.splines:
   for pt in sp.bezier_points:
    if include_co:
     for v in [pt.co,pt.handle_left,pt.handle_right]:
      for q in v:f(q)
 return h.hexdigest()
def facts():
 return {o.name:{'geometry':mesh_digest(o),'channels':mesh_digest(o,False),'matrix':[list(r) for r in o.matrix_local],'props':{k:serial(v) for k,v in o.items()},'materials':[m.name if m else None for m in o.data.materials] if o.type in ['MESH','CURVE'] else [],'parent':o.parent.name if o.parent else None,'bones':{b.name:[list(r) for r in b.matrix_local] for b in o.data.bones} if o.type=='ARMATURE' else None} for o in bpy.data.objects if o.name!='Studio'}
before=facts();changes=[]
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from reauthor_trousers import rebuild
new_topology=set(rebuild(bpy.data.objects['Bottom_Continuous_trousers'],P/'evidence/v4_transfer.json'))
for name in new_topology:changes.append(dict(name=name,new_topology=True))
for o in bpy.data.objects:
 field=None
 if o.type=='MESH' and o.name.startswith('Outfit_Casual_'):field=shirt_delta
 elif o.name.startswith('Bottom_Cuff'):field=pants_delta
 elif o.name=='Outfit_Cardigan_Body':field=cardigan_hem_delta
 if field is None:continue
 world=o.matrix_world.copy();inv=world.to_3x3().inverted()
 maximum=0.0
 if o.type=='MESH':
  original=[v.co.copy() for v in o.data.vertices]
  for i,co in enumerate(original):
   delta=inv@field(world@co);maximum=max(maximum,delta.length)
   o.data.vertices[i].co=co+delta
   if o.data.shape_keys:
    for key in o.data.shape_keys.key_blocks:key.data[i].co+=delta
  o.data.update()
 elif o.type=='CURVE':
  for spline in o.data.splines:
   for point in spline.bezier_points:
    for attr in ['co','handle_left','handle_right']:
     co=getattr(point,attr).copy();delta=inv@field(world@co);maximum=max(maximum,delta.length);setattr(point,attr,co+delta)
 changes.append(dict(name=o.name,max_displacement_m=maximum))
# Make the original tiny round placket a flat sewn band; buttons keep their original design.
o=bpy.data.objects['Outfit_Casual_Top_Front_placket']
for v in o.data.vertices:v.co.x*=3.4
# Raise the existing binding into a hem band with thickness, without adding noisy trim.
o=bpy.data.objects['Outfit_Casual_Top_Hem']
for v in o.data.vertices:v.co.z+=(v.co.z-1.043)*.55
# The neckline, buttons and placket should remain attached; the displacement field is
# shared rather than moving the main garment while leaving these details behind.
bpy.context.view_layer.update();after=facts()
changed={n for n in before if before[n]!=after[n]}
allowed={c['name'] for c in changes}
assert changed<=allowed,changed-allowed
assert all(before[n]['channels']==after[n]['channels'] for n in before if n not in new_topology),'Topology, weights, UV, morph names must remain exact'
for n in before:
 for k in ['matrix','props','materials','parent','bones']:assert before[n][k]==after[n][k],(n,k)
receipt={'source_sha256':EXPECTED,'blender':bpy.app.version_string,'changed':changes,'actual_changed':sorted(changed),'unchanged_object_count':len(before)-len(changed),'objects':{'before':before,'after':after},'broad_scale':1.12,'scope':'Adult casual shirt, shared trousers/pockets, and a local CardiganBody rear-hem ease; rig, skin, hair, other cardigan parts and Jacket retained'}
(P/'evidence/sculpt_preservation.json').write_text(json.dumps(receipt,indent=2))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(P/'art/characters.blend'))

# Fresh scene reopen alone did not stabilize protected n-gon hair evaluation.
# Each variant uses a fresh single-thread Blender process, and exact decoded
# guards reject any remaining drift rather than altering exported geometry.
blend=P/'art/characters.blend'
blend_sha256=hashlib.sha256(blend.read_bytes()).hexdigest()
for stem in ['character','character_broad','character_lod','character_broad_lod']:
 command=[bpy.app.binary_path,'--background','--factory-startup','-t','1','--python-exit-code','2','--python',str(Path(__file__).with_name('export_character_variant.py')),'--','--source',str(blend),'--source-sha256',blend_sha256,'--output-root',str(P/'assets/models'),'--variant',stem]
 with (P/'evidence'/('export_'+stem+'.log')).open('w') as log:
  result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=False)
 assert result.returncode==0,'Variant export failed; raw output/log retained: '+stem
from verify_character_exports import verify_all
verified=verify_all(P/'assets/models')
print('CLOTHING_EXPORT_COMPLETE',len(changed),'changed objects')

# A separate garment revision leaves the accepted rig18/surface2 contract truthful.
files=['art/characters.blend']+['assets/models/'+name+'.glb' for name in ['character','character_broad','character_lod','character_broad_lod']]
manifest={'garment_revision':22,'garment_correction':'cardigan_rear_hem','rig_version':18,'surface_revision':2,'blender_version':bpy.app.version_string,'source_sha256':EXPECTED,'blender_build_hash':bpy.app.build_hash.decode(),'export_worker_sha256':hashlib.sha256(Path(__file__).with_name('export_character_variant.py').read_bytes()).hexdigest(),'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'decoded_output_digests':verified,'export_guard_sha256':hashlib.sha256(Path(__file__).with_name('verify_character_exports.py').read_bytes()).hexdigest(),'helper_sha256':hashlib.sha256(Path(__file__).with_name('reauthor_trousers.py').read_bytes()).hexdigest(),'outputs':{name:hashlib.sha256((P/name).read_bytes()).hexdigest() for name in files},'scope':'Original adult casual shirt, continuous shared trousers, attached pocket trims and local CardiganBody rear-hem ease; nonadult assets unchanged.'}
(P/'garment_v22_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
