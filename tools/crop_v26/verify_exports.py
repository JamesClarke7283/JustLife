"""Exact preservation by accessor consumer, allowing explicit owned sharing.

A rebuilt ribbon may share an identical index/UV buffer with another rebuilt
ribbon. Expand each consumer to its exact decoded accessor plus storage metadata;
check protected sharing separately. No float tolerance, payload repair or index
ordering normalization is applied to the decoded vertex/triangle arrays.
"""
import copy,json,hashlib,sys,struct
from pathlib import Path
from decoded_gltf import decoded_document
COORD={'Hair_Crop_Cap','Hair_Crop_Sideburn','Hair_Crop_Sideburn.001'}
REBUILD={'Hair_Crop_Crown'+(''if i==0 else '.%03d'%i)for i in range(6)}|{'Hair_Crop_Part_fan'+(''if i==0 else '.%03d'%i)for i in range(5)}
def digest(v):return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
def expand(path):
 data=decoded_document(path);raw=Path(path).read_bytes();size,kind=struct.unpack_from('<II',raw,12);native=json.loads(raw[20:20+size])
 assert kind==0x4e4f534a and not native.get('animations')and not native.get('images'),'Unexpected new accessor/buffer consumers'
 users={i:[]for i in range(len(data['accessors']))};view_users=set()
 def view(index):
  view_users.add(index)
  return {k:v for k,v in native['bufferViews'][index].items()if k not in ['buffer','byteOffset','byteLength','byteStride']}
 def accessor(index,consumer):
  users[index].append(consumer);a=copy.deepcopy(data['accessors'][index]);original=native['accessors'][index];storage={}
  if'bufferView'in original:storage['base']=view(original['bufferView'])
  if'sparse'in original:
   for key in ['indices','values']:storage[key]=view(original['sparse'][key]['bufferView'])
  a['storage_metadata']=storage;return a
 meshes={}
 for mesh in data['meshes']:
  name=mesh['name'];assert name not in meshes
  m=copy.deepcopy(mesh)
  for pi,primitive in enumerate(m['primitives']):
   for semantic,index in list(primitive.get('attributes',{}).items()):primitive['attributes'][semantic]=accessor(index,(name,pi,semantic))
   if'indices'in primitive:primitive['indices']=accessor(primitive['indices'],(name,pi,'indices'))
   for ti,target in enumerate(primitive.get('targets',[])):
    for semantic,index in list(target.items()):target[semantic]=accessor(index,(name,pi,f'target{ti}.{semantic}'))
  meshes[name]=m
 root={k:copy.deepcopy(v)for k,v in data.items()if k not in ['meshes','accessors','bufferViews']}
 for i,skin in enumerate(root.get('skins',[])):
  if'inverseBindMatrices'in skin:skin['inverseBindMatrices']=accessor(skin['inverseBindMatrices'],('__skin__',i,'inverseBindMatrices'))
 assert all(users.values()),'Unreferenced accessor must be reviewed explicitly'
 assert view_users==set(range(len(native['bufferViews']))),'Unreferenced bufferView must be reviewed explicitly'
 aliases=sorted([sorted(v)for v in users.values()if len(v)>1])
 return {'root':root,'meshes':meshes,'aliases':aliases,'accessor_count':len(users),'view_count':len(view_users)}
def compare(baseline,candidate,report,coord_allowed=True):
 a=expand(baseline);b=expand(candidate);low=candidate.stem.endswith('_lod');checks=[];changes=[]
 def check(ok,label):checks.append({'ok':bool(ok),'label':label})
 check(a['root']==b['root'],'Exact root, scenes, nodes, material/shader, skin and expanded inverse-bind data')
 check(set(a['meshes'])==set(b['meshes']),'Exact named mesh inventory')
 check(REBUILD|COORD<=set(a['meshes']),'All14 explicitly changed Crop meshes present')
 def protected_aliases(aliases):return [group for group in aliases if any(name not in REBUILD or semantic not in ['POSITION','NORMAL','indices','TEXCOORD_0']for name,pi,semantic in group)]
 check(protected_aliases(a['aliases'])==protected_aliases(b['aliases']),'Exact protected accessor sharing; new aliases limited to rebuilt Crop consumers')
 for name,ma in a['meshes'].items():
  mb=b['meshes'][name]
  check({k:v for k,v in ma.items()if k!='primitives'}=={k:v for k,v in mb.items()if k!='primitives'},'Exact mesh metadata '+name)
  check(len(ma['primitives'])==len(mb['primitives']),'Exact primitive count '+name)
  for pi,(pa,pb)in enumerate(zip(ma['primitives'],mb['primitives'])):
   check({k:v for k,v in pa.items()if k not in ['attributes','indices','targets']}=={k:v for k,v in pb.items()if k not in ['attributes','indices','targets']},'Exact primitive schema/material '+name)
   check(set(pa.get('attributes',{}))==set(pb.get('attributes',{})),'Exact attribute semantics '+name)
   check(pa.get('targets')==pb.get('targets'),'Exact expanded morph targets '+name)
   attrs=dict(pa.get('attributes',{}));attrs_b=dict(pb.get('attributes',{}))
   if'indices'in pa:attrs['indices']=pa['indices'];attrs_b['indices']=pb.get('indices')
   for semantic,aa in attrs.items():
    ab=attrs_b[semantic];rebuilt=name in REBUILD;coord=coord_allowed and name in COORD
    allowed=(rebuilt or coord)and(semantic in ['POSITION','NORMAL','indices']or((rebuilt or low)and semantic.startswith('TEXCOORD_')))
    if not allowed:check(aa==ab,'Protected decoded accessor exact '+name+'.'+semantic);continue
    excluded={'decoded_values','min','max'}|({'count'}if rebuilt or low else set())
    check({k:v for k,v in aa.items()if k not in excluded}=={k:v for k,v in ab.items()if k not in excluded},'Owned accessor schema/storage exact '+name+'.'+semantic)
    if aa!=ab:changes.append({'mesh':name,'primitive':pi,'semantic':semantic,'before_count':aa['count'],'after_count':ab['count'],'before_sha256':digest(aa),'after_sha256':digest(ab)})
 result={'checks':len(checks),'failures':[c for c in checks if not c['ok']],'all_checks':checks,'baseline':str(baseline),'candidate':str(candidate),'baseline_sha256':hashlib.sha256(baseline.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'owned_accessor_changes':changes,'sharing':{'before_accessors':a['accessor_count'],'after_accessors':b['accessor_count'],'before_views':a['view_count'],'after_views':b['view_count'],'before_aliases':a['aliases'],'after_aliases':b['aliases']},'policy':__doc__}
 report.write_text(json.dumps(result,indent=2)+'\n');assert not result['failures'],f"{len(result['failures'])} exact preservation failures: {report}"
 print('CROP_NAMED_DECODED',result['checks'],0,candidate.name);return result
if __name__=='__main__':compare(Path(sys.argv[1]),Path(sys.argv[2]),Path(sys.argv[3]),len(sys.argv)<5 or sys.argv[4]!='seed')
