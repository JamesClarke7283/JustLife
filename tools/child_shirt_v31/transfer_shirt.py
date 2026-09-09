"""Transfer only one freshly Blender-authored shirt primitive into accepted GLB.

All other mesh accessors remain byte-for-byte payloads from the accepted asset.
No rounding, hair UV correction, index normalization or geometric reconstruction.
"""
import argparse,copy,hashlib,json,struct
from pathlib import Path
from decoded_facts import expand
OWNED_NODE='Outfit_Casual_Shirt';OWNED_MESH='Top_Blouse'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):
 raw=path.read_bytes();assert struct.unpack_from('<III',raw)==(0x46546c67,2,len(raw));at=12;chunks={}
 while at<len(raw):
  size,kind=struct.unpack_from('<II',raw,at);at+=8;assert kind not in chunks;chunks[kind]=raw[at:at+size];at+=size
 assert set(chunks)=={0x4e4f534a,0x004e4942}
 doc=json.loads(chunks[0x4e4f534a]);assert len(doc['buffers'])==1 and not doc.get('images') and not doc.get('animations')
 return doc,chunks[0x004e4942]
def locate(doc):
 found=[n for n in doc['nodes']if n.get('name')==OWNED_NODE];assert len(found)==1
 node=found[0];mesh=doc['meshes'][node['mesh']];assert mesh['name']==OWNED_MESH and len(mesh['primitives'])==1
 primitive=mesh['primitives'][0];assert not primitive.get('targets')
 assert set(primitive['attributes'])=={'POSITION','NORMAL','TEXCOORD_0','JOINTS_0','WEIGHTS_0'}
 consumers=dict(primitive['attributes']);consumers['indices']=primitive['indices']
 return node,mesh,primitive,consumers
def transfer(canonical,authored,output,report):
 assert not output.exists();a,ab=read(canonical);b,bb=read(authored);ea=expand(canonical);eb=expand(authored)
 an,am,ap,ai=locate(a);bn,bm,bp,bi=locate(b)
 assert ea['root']==eb['root'],'Fresh authored export changed node/material/skin hierarchy'
 assert an==bn and a['skins'][an['skin']]==b['skins'][bn['skin']],'Skin joint/inverse-bind mapping differs'
 assert set(ea['meshes'])==set(eb['meshes'])
 assert {k:v for k,v in am.items()if k!='primitives'}=={k:v for k,v in bm.items()if k!='primitives'}
 assert {k:v for k,v in ap.items()if k not in ['attributes','indices']}=={k:v for k,v in bp.items()if k not in ['attributes','indices']}
 assert len(set(ai.values()))==len(ai) and len(set(bi.values()))==len(bi)
 av={i:a['accessors'][i]['bufferView']for i in ai.values()};bv={i:b['accessors'][i]['bufferView']for i in bi.values()}
 assert len(set(av.values()))==len(av) and len(set(bv.values()))==len(bv)
 for doc,owned,views in [(a,set(ai.values()),set(av.values())),(b,set(bi.values()),set(bv.values()))]:
  for index,accessor in enumerate(doc['accessors']):
   used={accessor['bufferView']}if'bufferView'in accessor else set()
   if'sparse'in accessor:used|={accessor['sparse'][s]['bufferView']for s in ['indices','values']}
   assert not used&views or index in owned,'An owned bufferView is shared with a protected accessor'
  for group in (ea if doc is a else eb)['aliases']:
   assert not any(name==OWNED_MESH for name,_,_ in group),'Owned accessor shared with another consumer'
 result=copy.deepcopy(a);replacement={};changes=[]
 for semantic,old_index in ai.items():
  new_index=bi[semantic];old_view=av[old_index];new_view=bv[new_index]
  fresh=copy.deepcopy(b['accessors'][new_index]);assert 'sparse'not in fresh
  fresh['bufferView']=old_view;result['accessors'][old_index]=fresh
  view=b['bufferViews'][new_view];assert view.get('buffer',0)==0
  replacement[old_view]=bb[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
  result['bufferViews'][old_view]=copy.deepcopy(view)
  changes.append({'semantic':semantic,'canonical_accessor':old_index,'authored_accessor':new_index,'before_count':a['accessors'][old_index]['count'],'after_count':fresh['count']})
 binary=bytearray()
 for index,view in enumerate(result['bufferViews']):
  while len(binary)%4:binary.append(0)
  if index in replacement:payload=replacement[index]
  else:
   old=a['bufferViews'][index];payload=ab[old.get('byteOffset',0):old.get('byteOffset',0)+old['byteLength']]
  view['buffer']=0;view['byteOffset']=len(binary);view['byteLength']=len(payload);binary.extend(payload)
 result['buffers'][0]['byteLength']=len(binary)
 js=json.dumps(result,separators=(',',':'),ensure_ascii=False).encode();js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4)
 raw=struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary
 output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(raw)
 ec=expand(output);assert ec['root']==ea['root'];assert ec['aliases']==ea['aliases']
 assert ec['meshes'][OWNED_MESH]==eb['meshes'][OWNED_MESH],'Transferred shirt differs from actual Blender-derived primitive'
 for name in ea['meshes']:
  if name!=OWNED_MESH:assert ec['meshes'][name]==ea['meshes'][name],name
 # At full detail the Blender edit must preserve exact decoded UV/skin/topology.
 if not output.stem.endswith('_lod'):
  old=ea['meshes'][OWNED_MESH]['primitives'][0];new=ec['meshes'][OWNED_MESH]['primitives'][0]
  assert old['indices']==new['indices']
  for name in ['TEXCOORD_0','JOINTS_0','WEIGHTS_0']:assert old['attributes'][name]==new['attributes'][name]
 note={'canonical_sha256':sha(canonical),'authored_sha256':sha(authored),'output_sha256':sha(output),'owned_node':OWNED_NODE,'owned_mesh':OWNED_MESH,'protected_meshes_exact':len(ea['meshes'])-1,'root_material_skin_joint_mapping_exact':True,'owned_primitive_exact_to_authored_export':True,'protected_accessor_aliases_exact':True,'changes':changes,'raw_export_nonowned_differences_excluded':[n for n in ea['meshes']if n!=OWNED_MESH and ea['meshes'][n]!=eb['meshes'][n]],'method':__doc__}
 report.write_text(json.dumps(note,indent=2)+'\n');return note
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--canonical',type=Path,required=True);p.add_argument('--authored',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=transfer(a.canonical,a.authored,a.output,a.report);print('SHIRT_ONLY_TRANSFER_OK',r['protected_meshes_exact'],a.output.name)
