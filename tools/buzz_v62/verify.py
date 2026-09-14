"""Verify tight Buzz scalp clearance and exact coupling to native head morphs."""
import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils.bvhtree import BVHTree

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import evaluated

bpy.ops.wm.open_mainfile(filepath=str(a.source.resolve()))
head=bpy.data.objects['Skin_Head_continuous'];cap=bpy.data.objects['Hair_Buzz_Cap']
indices=list(cap['buzz_source_head_indices'])
hk=head.data.shape_keys.key_blocks;ck=cap.data.shape_keys.key_blocks
saved_h={k.name:k.value for k in hk};saved_c={k.name:k.value for k in ck}
for k in hk:k.value=0
for k in ck:k.value=0
bpy.context.view_layer.update()
head0,_,_=evaluated(head);cap0,_,_=evaluated(cap)
offset=[point-head0[index] for point,index in zip(cap0,indices)]
cases={'neutral':{}}
active=[k for k in ck if k.name!='Basis']
for key in active:
    cases[key.name+'_max']={key.name:1.0}
    if key.slider_min<0:cases[key.name+'_min']={key.name:-1.0}
cases['round_and_jaw']={'Face_Round':1.0,'Jaw_Strong':1.0}
cases['all_positive']={key.name:1.0 for key in active}
cases['mixed']={key.name:(-.6 if key.slider_min<0 else .65) for key in active}
results={}
for label,settings in cases.items():
    for key in hk:key.value=settings.get(key.name,0)
    for key in ck:key.value=settings.get(key.name,0)
    bpy.context.view_layer.update()
    hp,_,hf=evaluated(head);cp,_,cf=evaluated(cap)
    skull=BVHTree.FromPolygons(hp,hf)
    values=[]
    for point in cp:
        hit,normal,_,_=skull.find_nearest(point)
        values.append((point-hit).dot(normal))
    coupling=max((point-hp[index]-rest).length for point,index,rest in zip(cp,indices,offset))
    results[label]={'settings':settings,'vertices':len(cp),'minimum_signed_clearance':min(values),
                    'penetrating_vertices':sum(value<-.0001 for value in values),
                    'maximum_coupling_error':coupling}
    print('BUZZ_SCALP_CASE',label,json.dumps(results[label]),flush=True)
for key in hk:key.value=saved_h[key.name]
for key in ck:key.value=saved_c[key.name]
assert not cap.modifiers, 'Close crop must not acquire a thick shell modifier'
report={'source':str(a.source.resolve()),'cases':results,
        'surface_model':'Scalp-backed, alpha-masked hair surface with no hollow shell',
        'material':cap.data.materials[0].name}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
assert not any(record['penetrating_vertices'] for record in results.values())
assert max(record['maximum_coupling_error'] for record in results.values())<2e-6
print('BUZZ_SCALP_VERIFIED',str(a.report.resolve()),flush=True)
