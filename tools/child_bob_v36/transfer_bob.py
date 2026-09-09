"""Guarded owned-mesh transfer into accepted GLB; exact protected payloads.

Copy only the 25 Blender-authored Bob primitives, preserving all accepted
protected consumers and their sharing. Repack storage and discard accessors
made unused by that replacement; never normalize UVs/triangles or repair data.
"""
import argparse,copy,hashlib,json,struct
from pathlib import Path
from decoded_facts import expand,digest
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 raw=p.read_bytes();assert struct.unpack_from('<III',raw)==(0x46546c67,2,len(raw));chunks={};at=12
 while at<len(raw):
  size,kind=struct.unpack_from('<II',raw,at);at+=8;assert kind not in chunks;chunks[kind]=raw[at:at+size];at+=size
 assert set(chunks)=={0x4e4f534a,0x004e4942}
 doc=json.loads(chunks[0x4e4f534a]);assert len(doc['buffers'])==1 and not doc.get('images') and not doc.get('animations')
 return doc,chunks[0x004e4942]
def projected_sharing(doc,names):
 groups=[[u for u in group if u[0]in names]for group in doc['aliases']]
 return sorted(group for group in groups if len(group)>1)
def transfer(accepted,authored,output,report,owned):
 assert not output.exists();a,ab=read(accepted);b,bb=read(authored);ea,eb=expand(accepted),expand(authored)
 assert ea['root']==eb['root'];assert ea['meshes'].keys()==eb['meshes'].keys()
 protected=set(ea['meshes'])-owned;assert len(owned)==25 and len(protected)==314
 assert projected_sharing(ea,protected)==projected_sharing(eb,protected)
 result=copy.deepcopy(a)
 payloads=[ab[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]for v in a['bufferViews']]
 accessor_map={};view_map={}
 def fresh_accessor(index):
  if index in accessor_map:return accessor_map[index]
  record=copy.deepcopy(b['accessors'][index]);assert 'sparse'not in record and 'bufferView'in record
  vi=record['bufferView']
  if vi not in view_map:
   view=copy.deepcopy(b['bufferViews'][vi]);assert view.get('buffer',0)==0
   view_map[vi]=len(result['bufferViews']);result['bufferViews'].append(view)
   payloads.append(bb[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])
  record['bufferView']=view_map[vi];accessor_map[index]=len(result['accessors']);result['accessors'].append(record)
  return accessor_map[index]
 mesh_indices={m['name']:i for i,m in enumerate(a['meshes'])};fresh_indices={m['name']:i for i,m in enumerate(b['meshes'])}
 for name in sorted(owned):
  i=mesh_indices[name];j=fresh_indices[name];ma=a['meshes'][i];mb=b['meshes'][j]
  an=[n for n in a['nodes']if n.get('name')==name];bn=[n for n in b['nodes']if n.get('name')==name]
  assert len(an)==len(bn)==1 and an==bn and an[0]['mesh']==i and bn[0]['mesh']==j
  assert 'skin'not in an[0],('Bob mesh unexpectedly skinned',name)
  assert {k:v for k,v in ma.items()if k!='primitives'}=={k:v for k,v in mb.items()if k!='primitives'}
  assert len(ma['primitives'])==len(mb['primitives'])==1
  pa,pb=ma['primitives'][0],mb['primitives'][0]
  assert not pa.get('targets') and not pb.get('targets')
  assert set(pa['attributes'])==set(pb['attributes'])=={'POSITION','NORMAL','TEXCOORD_0'}
  assert {k:v for k,v in pa.items()if k not in ['attributes','indices']}=={k:v for k,v in pb.items()if k not in ['attributes','indices']}
  primitive=copy.deepcopy(pb);primitive['attributes']={key:fresh_accessor(value)for key,value in pb['attributes'].items()};primitive['indices']=fresh_accessor(pb['indices'])
  result['meshes'][i]['primitives']=[primitive]
 # Enumerate every known accessor consumer before removing orphaned old Bob
 # buffers. Original expanded documents reject unknown/unreferenced storage.
 consumers=[]
 for mesh in result['meshes']:
  for p in mesh['primitives']:
   consumers.extend((p['attributes'],k)for k in p.get('attributes',{}))
   if 'indices'in p:consumers.append((p,'indices'))
   for target in p.get('targets',[]):consumers.extend((target,k)for k in target)
 for skin in result.get('skins',[]):
  if 'inverseBindMatrices'in skin:consumers.append((skin,'inverseBindMatrices'))
 used=sorted({container[key]for container,key in consumers});remap={old:new for new,old in enumerate(used)}
 result['accessors']=[result['accessors'][i]for i in used]
 for container,key in consumers:container[key]=remap[container[key]]
 view_consumers=[]
 for accessor in result['accessors']:
  if 'bufferView'in accessor:view_consumers.append((accessor,'bufferView'))
  if 'sparse'in accessor:
   for key in ['indices','values']:view_consumers.append((accessor['sparse'][key],'bufferView'))
 views=sorted({container[key]for container,key in view_consumers});view_remap={old:new for new,old in enumerate(views)}
 result['bufferViews']=[result['bufferViews'][i]for i in views];payloads=[payloads[i]for i in views]
 for container,key in view_consumers:container[key]=view_remap[container[key]]
 binary=bytearray()
 for view,payload in zip(result['bufferViews'],payloads):
  binary+=b'\0'*((-len(binary))%4);view['buffer']=0;view['byteOffset']=len(binary);view['byteLength']=len(payload);binary.extend(payload)
 result['buffers'][0]['byteLength']=len(binary);binary+=b'\0'*((-len(binary))%4)
 js=json.dumps(result,separators=(',',':'),ensure_ascii=False).encode();js+=b' '*((-len(js))%4)
 raw=struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary
 output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(raw);ec=expand(output)
 assert ec['root']==ea['root'];assert ec['meshes'].keys()==ea['meshes'].keys()
 for name in protected:assert ec['meshes'][name]==ea['meshes'][name],('protected',name)
 for name in owned:assert ec['meshes'][name]==eb['meshes'][name],('authored Bob',name)
 assert projected_sharing(ec,protected)==projected_sharing(ea,protected)
 assert projected_sharing(ec,owned)==projected_sharing(eb,owned)
 data={'status':'pass','accepted_sha256':sha(accepted),'authored_sha256':sha(authored),'output_sha256':sha(output),'protected_meshes_exact':len(protected),'owned_meshes_exact_to_Blender':len(owned),'root_material_node_rig_exact':True,'protected_sharing_exact':True,'owned_internal_sharing_exact_to_Blender':True,'raw_export_protected_drift_excluded':sorted(n for n in protected if ea['meshes'][n]!=eb['meshes'][n]),'protected_payload_sha256':digest({n:ea['meshes'][n]for n in sorted(protected)}),'method':__doc__}
 report.write_text(json.dumps(data,indent=2)+'\n');return data
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--accepted',type=Path,required=True)
 p.add_argument('--authored',type=Path,required=True)
 p.add_argument('--output',type=Path,required=True)
 p.add_argument('--report',type=Path,required=True)
 p.add_argument('--contract','--ownership',dest='contract',type=Path,
                default=Path(__file__).resolve().with_name('native_contract.json'),
                help='Distributed contract with scope.owned_meshes and pinned variant hashes')
 args=p.parse_args();variant='character_child_lod'
 accepted,authored,contract=[path.resolve() for path in [args.accepted,args.authored,args.contract]]
 output,report=args.output.resolve(),args.report.resolve()
 if not all(path.is_file() for path in [accepted,authored,contract]):
  p.error('Accepted, authored and contract inputs must be existing files')
 if output==report or any(path in [accepted,authored,contract] for path in [output,report]):
  p.error('Output and report must be distinct from each other and every input')
 if output.exists() or report.exists():
  p.error('Output and report must both be new files; existing paths are never overwritten')
 if any(parent.exists() and not parent.is_dir() for path in [output,report] for parent in path.parents):
  p.error('Output and report parents must be directories')
 try:
  data=json.loads(contract.read_text())
  names=data['scope']['owned_meshes']
  if not isinstance(names,list) or not all(isinstance(name,str) for name in names):raise ValueError('owned mesh list')
  owned=set(names)
  expected={'Hair_Bob_Cap'}|{'Hair_Bob_'+kind+('' if i==0 else f'.{i:03}') for kind in ['Lock','Strand'] for i in range(12)}
  if owned!=expected or len(names)!=25:raise ValueError('exact 25 Bob mesh ownership required')
  if sha(accepted)!=data['baseline_glbs'][variant]:raise ValueError('accepted input hash differs from variant pin')
  if sha(authored)!=data['raw_glbs'][variant]:raise ValueError('authored input hash differs from variant pin')
  target_pin=data['candidate_glbs'][variant]
 except (KeyError,TypeError,ValueError) as error:
  p.error('Invalid contract or input: '+str(error))
 # Complete all input and collision checks before making any output directory.
 report.parent.mkdir(parents=True,exist_ok=True)
 result=transfer(accepted,authored,output,report,owned)
 if result['output_sha256']!=target_pin:
  p.error('Output differs from the qualified variant; generated output and report retained')
 print(json.dumps(result))

if __name__=='__main__':
 main()
