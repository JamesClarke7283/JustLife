"""Sequential neutralization, native preservation and one fresh preview export."""
import argparse
import hashlib
import json
import runpy
import sys
from pathlib import Path

import bpy

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--authored',type=Path,required=True)
p.add_argument('--folder',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
root=Path(__file__).resolve().parents[1]
ready=a.folder/'ready.blend'
assert not ready.exists() and not (a.folder/'models'/'character.glb').exists()


def stage(name,path,args):
    print('BUZZ_STAGE_START',name,flush=True)
    sys.argv=['blender','--',*map(str,args)]
    runpy.run_path(str(path),run_name='__main__')
    print('BUZZ_STAGE_PASS',name,flush=True)


stage('neutralize',root/'portrait_v62'/'finalize_native.py',
      ['--source',a.authored,'--output',ready,'--report',a.folder/'neutralize.json'])
assert tuple(bpy.data.objects['Character'].scale)==(1.,1.,1.), 'Source must use standard adult root'
stage('fresh_native_preservation',root/'buzz_v62'/'verify_composition.py',
      ['--baseline',a.baseline,'--candidate',ready,'--report',a.folder/'native_preservation.json'])
sha=hashlib.sha256(ready.read_bytes()).hexdigest()
stage('export',root/'portrait_v62'/'export_variant.py',
      ['--source',ready,'--source-sha256',sha,'--output-root',a.folder/'models','--variant','character'])
glb=a.folder/'models'/'character.glb'
receipt={'ready':str(ready.resolve()),'ready_sha256':sha,
         'glb':str(glb.resolve()),'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),
         'stages_passed':['neutralize','fresh_native_preservation','export']}
(a.folder/'export_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('BUZZ_FINAL_EXPORT_READY',json.dumps(receipt),flush=True)
