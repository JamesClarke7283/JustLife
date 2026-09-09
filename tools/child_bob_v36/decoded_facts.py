"""Exact preservation by accessor consumer, allowing explicit owned sharing.

A rebuilt ribbon may share an identical index/UV buffer with another rebuilt
ribbon. Expand each consumer to its exact decoded accessor plus storage metadata;
check protected sharing separately. No float tolerance, payload repair or index
ordering normalization is applied to the decoded vertex/triangle arrays.
"""
import copy,json,hashlib,sys,struct
from pathlib import Path
from decoded_gltf import decoded_document
OWNED='Outfit_Casual_Shirt'
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
