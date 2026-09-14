"""Fresh-open comparison of all non-Buzz native data after neutralization."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--candidate',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import descendants,fingerprint,material_fingerprint,stable


def snapshot(path,require_neutral=False):
    bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    D=bpy.data.objects
    if require_neutral:
        assert tuple(D['Character'].scale)==(1.,1.,1.), 'Expected standard root'
        assert all(k.value==0 for o in D if o.type=='MESH' and o.data.shape_keys
                   for k in o.data.shape_keys.key_blocks), 'Non-neutral key value'
        assert all(tuple(b.rotation_euler)==(0.,0.,0.) for o in D if o.type=='ARMATURE'
                   for b in o.pose.bones), 'Non-neutral pose Euler rotation'
    # These are the only normalization changes authorized for final/export pose.
    D['Character'].scale.x=1
    for o in D:
        if o.type=='MESH' and o.data.shape_keys:
            for k in o.data.shape_keys.key_blocks:k.value=0
        if o.type=='ARMATURE':
            for b in o.pose.bones:b.rotation_euler=(0,0,0)
    bpy.context.view_layer.update()
    ignored={o.name for o in descendants(D['Hair_Buzz'])}
    objects={o.name:fingerprint(o) for o in D if o.name not in ignored}
    materials={m.name:material_fingerprint(m) for m in bpy.data.materials if m.name!='Hair_Buzz_Surface'}
    colors={o.name:[(c.name,c.domain,c.data_type,len(c.data)) for c in o.data.color_attributes]
            for o in D if o.type=='MESH' and o.name not in ignored and o.data.color_attributes}
    identities=str(D['Character']['identity_morphs']).split(',')
    assert len(identities)==11
    metadata={name:stable(D['Character'][name]) for name in ('identity_morphs','mouth_anchor','mouth_identity_offsets')}
    assert len(D['Character']['mouth_identity_offsets'])==11
    return objects,materials,colors,metadata


before=snapshot(a.baseline)
after=snapshot(a.candidate,True)
assert before==after, 'Non-Buzz object, shader, vertex colour or metadata changed'
report={'baseline':str(a.baseline.resolve()),'candidate':str(a.candidate.resolve()),
        'baseline_sha256':hashlib.sha256(a.baseline.read_bytes()).hexdigest(),
        'candidate_sha256':hashlib.sha256(a.candidate.read_bytes()).hexdigest(),
        'non_buzz_objects_exact':len(after[0]),'non_buzz_materials_exact':len(after[1]),
        'preserved_vertex_colors':after[2],'identity_and_mouth_metadata':after[3],
        'standard_root_and_neutral_pose':True,'passed':True}
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps(report,indent=2)+'\n')
print('BUZZ_INTEGRATION_PRESERVED',json.dumps(report),flush=True)
