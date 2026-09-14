"""Refine only the original Buzz material, retaining candidate A geometry."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--input',type=Path,required=True)
p.add_argument('--source-sha256',required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
assert a.input.resolve()!=a.output.resolve()
assert hashlib.sha256(a.input.read_bytes()).hexdigest()==a.source_sha256
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import bounds,evaluated,fingerprint
from surface import material

bpy.ops.wm.open_mainfile(filepath=str(a.input.resolve()))
D=bpy.data.objects
before={o.name:fingerprint(o) for o in D}
cap=D['Hair_Buzz_Cap']
assert len(cap.data.materials)==1 and cap.data.materials[0].name=='Hair_Buzz_Surface'
assert cap.data.materials[0].users==1, 'Material refinement cannot affect another style'
span=bounds(evaluated(D['Skin_Head_continuous'])[0])[2][1]-D['Head'].matrix_world.translation.z
cap.data.materials.clear()
a.output.parent.mkdir(parents=True,exist_ok=True)
folder=a.output.parent/'textures'; folder.mkdir(parents=True,exist_ok=True)
cap.data.materials.append(material(bpy.data.materials['Hair'],folder,span))
assert {o.name:fingerprint(o) for o in D}==before, 'Material-only pass changed scene geometry/state'
assert hashlib.sha256(a.input.read_bytes()).hexdigest()==a.source_sha256
bpy.ops.wm.save_as_mainfile(filepath=str(a.output.resolve()))
report={'input':str(a.input.resolve()),'output':str(a.output.resolve()),
        'source_sha256':a.source_sha256,
        'candidate_sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),
        'scope':'Only Hair_Buzz_Surface shader and original packed images',
        'exact_scene_objects_including_buzz_geometry_and_keys':len(before),
        'density_boundary_changes':'Softer front-corner transition; shorter temple point, still within scalp patch',
        'artwork':'110000 deterministic randomly scattered short follicles; rank-based coverage fade',
        'external_pixels_used':False}
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps(report,indent=2)+'\n')
print('BUZZ_MATERIAL_REFINED',json.dumps(report),flush=True)
