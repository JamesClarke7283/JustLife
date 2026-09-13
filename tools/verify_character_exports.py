"""Fail closed on revision22 decoded exports; no geometry repair or tolerance.

Container padding and binary buffer offsets are irrelevant. All decoded accessor
values/schema and every other glTF field, including named nodes, skins, materials,
primitive references and exporter version, must equal the qualified revision.
"""
import copy, hashlib, json, math, struct
from pathlib import Path

PINS = {'character.glb': 'dd4d3212a92424054d59a38ffb04fa423a37145f1894209ded75141e4b02bfa3', 'character_broad.glb': '0d5769b314bf7df253d59546d998d80308a9d0bf0169101f6b8a8983f4dd5dfc', 'character_lod.glb': 'eab1c6a9c5b3eed0f3a1fb24f847b0f9b464a0e7ba5dede3bb820634b46ae3dd', 'character_broad_lod.glb': '3e45a79df7a8d67678f6f24b00a029780e88554420a2c1b7218e24eb4006aaa0'} # Qualified hair-lock v61 rounded lock sections and sealed shells.
FORMATS = {5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}
COUNTS = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}

def semantic_digest(path):
    raw=Path(path).read_bytes()
    assert struct.unpack_from('<III',raw)==(0x46546c67,2,len(raw))
    chunks={};at=12
    while at<len(raw):
        size,kind=struct.unpack_from('<II',raw,at);at+=8
        assert kind not in chunks and at+size<=len(raw)
        chunks[kind]=raw[at:at+size];at+=size
    assert set(chunks)=={0x4e4f534a,0x004e4942}
    data=json.loads(chunks[0x4e4f534a]);binary=chunks[0x004e4942]
    assert len(data['buffers'])==1 and 'uri' not in data['buffers'][0]
    declared=data['buffers'][0]['byteLength']
    assert isinstance(declared,int) and 0<=declared<=len(binary) and len(binary)-declared<=3
    for view in data['bufferViews']:
        offset=view.get('byteOffset',0);length=view['byteLength']
        assert isinstance(offset,int) and isinstance(length,int) and offset>=0 and length>=0 and offset+length<=declared
    def read(view,offset,count,columns,kind):
        v=data['bufferViews'][view];assert v.get('buffer',0)==0
        fmt='<'+FORMATS[kind]*columns;size=struct.calcsize(fmt)
        stride=v.get('byteStride',size);assert stride>=size
        assert count==0 or offset+(count-1)*stride+size<=v['byteLength']
        base=v.get('byteOffset',0)+offset
        return [struct.unpack_from(fmt,binary,base+i*stride) for i in range(count)]
    decoded=[]
    for a in data['accessors']:
        count=a['count'];columns=COUNTS[a['type']]
        values=read(a['bufferView'],a.get('byteOffset',0),count,columns,a['componentType']) if 'bufferView' in a else [(0,)*columns for _ in range(count)]
        if 'sparse' in a:
            s=a['sparse'];ix=s['indices'];vv=s['values']
            assert ix['componentType'] in [5121,5123,5125]
            indices=read(ix['bufferView'],ix.get('byteOffset',0),s['count'],1,ix['componentType'])
            replacements=read(vv['bufferView'],vv.get('byteOffset',0),s['count'],columns,a['componentType'])
            for (index,),value in zip(indices,replacements):
                assert 0<=index<count;values[index]=value
        assert all(all(not isinstance(value,float) or math.isfinite(value) for value in row) for row in values)
        record={k:v for k,v in a.items() if k not in ['bufferView','byteOffset','sparse']}
        if 'sparse' in a:
            # Sparse binary placement is layout; count, component type and any
            # extension/extra metadata remain part of the exact contract.
            record['sparse_metadata']={k:v for k,v in a['sparse'].items() if k not in ['indices','values']}
            for name in ['indices','values']:
                record['sparse_metadata'][name]={k:v for k,v in a['sparse'][name].items() if k not in ['bufferView','byteOffset']}
        record['decoded_values']=values;decoded.append(record)
    result=copy.deepcopy(data)
    result['buffers']=[{k:v for k,v in buffer.items() if k!='byteLength'} for buffer in data['buffers']]
    result['bufferViews']=[{k:v for k,v in view.items() if k not in ['buffer','byteOffset','byteLength','byteStride']} for view in data['bufferViews']]
    result['accessors']=decoded
    payload=json.dumps(result,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    return hashlib.sha256(payload).hexdigest()

def verify_all(directory):
    results={name:semantic_digest(Path(directory)/name) for name in PINS}
    failures=[name for name,digest in results.items() if digest!=PINS[name]]
    assert not failures,'Decoded revision22 export drift; retain raw files and inspect: '+', '.join(failures)
    return results
