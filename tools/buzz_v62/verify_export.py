"""Compare actual exported non-Buzz accessors/materials and Buzz MASK contract."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--baseline-sha256',required=True)
p.add_argument('--candidate',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args()


class GLB:
    def __init__(self,path):
        self.raw=path.read_bytes()
        assert struct.unpack_from('<4sII',self.raw)==(b'glTF',2,len(self.raw))
        offset=12
        while offset<len(self.raw):
            size,kind=struct.unpack_from('<II',self.raw,offset)
            chunk=self.raw[offset+8:offset+8+size]
            if kind==0x4e4f534a:self.data=json.loads(chunk)
            elif kind==0x004e4942:self.binary=chunk
            offset+=8+size
        self.nodes={n['name']:n for n in self.data['nodes'] if 'mesh' in n}

    def accessor(self,index):
        acc=self.data['accessors'][index]
        count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[acc['type']]
        code={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}[acc['componentType']]
        width=struct.calcsize('<'+code*count)
        if 'bufferView' in acc:
            view=self.data['bufferViews'][acc['bufferView']]
            start=view.get('byteOffset',0)+acc.get('byteOffset',0)
            stride=view.get('byteStride',width)
            raw=bytearray(b''.join(self.binary[start+i*stride:start+i*stride+width] for i in range(acc['count'])))
        else:raw=bytearray(acc['count']*width)
        if 'sparse' in acc:
            sparse=acc['sparse'];ix=sparse['indices'];va=sparse['values']
            iv=self.data['bufferViews'][ix['bufferView']];vv=self.data['bufferViews'][va['bufferView']]
            ib=iv.get('byteOffset',0)+ix.get('byteOffset',0)
            vb=vv.get('byteOffset',0)+va.get('byteOffset',0)
            fmt='<'+{5121:'B',5123:'H',5125:'I'}[ix['componentType']]
            size=struct.calcsize(fmt);last=-1
            for i in range(sparse['count']):
                target=struct.unpack_from(fmt,self.binary,ib+i*size)[0]
                assert last<target<acc['count'];last=target
                raw[target*width:(target+1)*width]=self.binary[vb+i*width:vb+(i+1)*width]
        return (acc['type'],acc['componentType'],acc['count'],acc.get('normalized',False),bytes(raw))

    def image(self,index):
        image=self.data['images'][index];view=self.data['bufferViews'][image['bufferView']]
        start=view.get('byteOffset',0)
        return (image.get('mimeType'),hashlib.sha256(self.binary[start:start+view['byteLength']]).hexdigest())

    def material(self,index):
        def normalize(obj,key=''):
            if isinstance(obj,list):return [normalize(v) for v in obj]
            if not isinstance(obj,dict):return obj
            value={k:normalize(v,k) for k,v in obj.items()}
            if key.endswith('Texture') and 'index' in obj:
                tex=self.data['textures'][obj['index']]
                value['index']={'image':self.image(tex['source']),
                                'sampler':self.data.get('samplers',[])[tex['sampler']] if 'sampler' in tex else None}
            return value
        return normalize(self.data['materials'][index])


old,new=GLB(a.baseline),GLB(a.candidate)
assert hashlib.sha256(old.raw).hexdigest()==a.baseline_sha256
assert old.nodes.keys()==new.nodes.keys(), 'Mesh node inventory changed'
assert len(old.data['nodes'])==len(new.data['nodes'])
for on,nn in zip(old.data['nodes'],new.data['nodes']):
    if on.get('name')=='Hair_Buzz_Cap':continue
    for key in ('name','children','translation','rotation','scale','matrix','skin','extras'):
        assert on.get(key)==nn.get(key),(on.get('name'),key)
assert old.data['skins']==new.data['skins'], 'Skin/rig export changed'
checked=0;mesh_count=0;color_meshes=[]
for name,node in old.nodes.items():
    if name=='Hair_Buzz_Cap':continue
    om=old.data['meshes'][node['mesh']];nm=new.data['meshes'][new.nodes[name]['mesh']]
    assert om.get('extras')==nm.get('extras') and om.get('weights')==nm.get('weights'),name
    assert len(om['primitives'])==len(nm['primitives'])
    for op,np in zip(om['primitives'],nm['primitives']):
        assert op['attributes'].keys()==np['attributes'].keys(),name
        pairs=list(zip(op['attributes'].values(),np['attributes'].values()))+[(op['indices'],np['indices'])]
        assert len(op.get('targets',[]))==len(np.get('targets',[]))
        for ot,nt in zip(op.get('targets',[]),np.get('targets',[])):
            assert ot.keys()==nt.keys()
            pairs.extend(zip(ot.values(),nt.values()))
        for oi,ni in pairs:
            assert old.accessor(oi)==new.accessor(ni),(name,'accessor',oi,ni)
            checked+=1
        assert old.material(op['material'])==new.material(np['material']),(name,'material')
        if 'COLOR_0' in np['attributes']:color_meshes.append(name)
    mesh_count+=1
cap_node=new.nodes['Hair_Buzz_Cap'];cap=new.data['meshes'][cap_node['mesh']]
assert set(cap['extras']['targetNames'])=={'Face_Round','Jaw_Strong','Eye_Spacing','Face_Length'}
assert all(v==0 for v in cap.get('weights',[]))
assert len(cap['primitives'])==1
mat=new.data['materials'][cap['primitives'][0]['material']]
assert mat['name']=='Hair_Buzz_Surface'
assert mat['alphaMode']=='MASK' and mat.get('alphaCutoff',.5)==.5
pbr=mat['pbrMetallicRoughness']
assert pbr['baseColorFactor']!=[1.,1.,1.,1.]
assert 'baseColorTexture' in pbr and 'metallicRoughnessTexture' in pbr and 'normalTexture' in mat
assert 'COLOR_0' in new.data['meshes'][new.nodes['Skin_Head_continuous']['mesh']]['primitives'][0]['attributes']
root=next(n for n in new.data['nodes'] if n.get('name')=='Character')
assert root.get('scale',[1,1,1])==[1,1,1]
assert len(root['extras']['identity_morphs'].split(','))==11
assert len(root['extras']['mouth_identity_offsets'])==11
report={'baseline':str(a.baseline.resolve()),'baseline_sha256':a.baseline_sha256,
        'candidate':str(a.candidate.resolve()),'candidate_sha256':hashlib.sha256(new.raw).hexdigest(),
        'non_buzz_meshes_exact':mesh_count,'non_buzz_accessors_exact':checked,
        'color_meshes_exact':sorted(set(color_meshes)),
        'non_buzz_materials_transforms_extras_skins_exact':True,
        'buzz_material':mat,'buzz_morph_names':cap['extras']['targetNames'],
        'standard_root_and_eleven_identity_mouth_metadata':True,'passed':True}
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps(report,indent=2)+'\n')
print('BUZZ_EXPORT_PRESERVED',json.dumps(report),flush=True)
