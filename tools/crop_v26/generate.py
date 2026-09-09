"""Reproduce the original adult Crop source from the accepted face-v23 source.

Run with ordinary Python. All three native stages start in fresh t6 Blender processes;
each of the four final adult GLB exports starts in a separate fresh t1 process.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,shutil,time
TOOLS=Path(__file__).resolve().parent
ROOT=TOOLS.parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',type=Path,default=ROOT/'art/source/crop_v26/characters_face_v23.blend')
p.add_argument('--output-root',type=Path,required=True)
p.add_argument('--blender',default='blender')
a=p.parse_args();out=a.output_root.resolve();source=a.source.resolve()
assert not out.exists()or not any(out.iterdir()),'Use a fresh empty output directory'
assert out not in source.parents and out!=source
out.mkdir(parents=True,exist_ok=True);(out/'evidence').mkdir()
binary=shutil.which(a.blender);assert binary,'Blender executable not found'
receipt={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest(),'steps':[],'outputs':{}}
def run(label,script,arguments):
 command=[binary,'--background','--factory-startup','-t','6','--python-exit-code','2','--python',str(TOOLS/script),'--',*arguments]
 item={'label':label,'command':command,'returncode':None};receipt['steps'].append(item)
 (out/'evidence/reproduction.json').write_text(json.dumps(receipt,indent=2)+'\n')
 started=time.monotonic()
 with (out/'evidence'/(label+'.log')).open('w')as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
 item.update({'returncode':result.returncode,'seconds':time.monotonic()-started})
 (out/'evidence/reproduction.json').write_text(json.dumps(receipt,indent=2)+'\n')
 assert result.returncode==0,'Failed stage retained: '+label
run('fit_seed','fit_seed.py',['--source',str(source),'--output-root',str(out/'seed'),'--skip-exports'])
seed=out/'seed/art/characters.blend';seed_sha=hashlib.sha256(seed.read_bytes()).hexdigest()
run('feather_flow','feather_flow.py',['--source',str(seed),'--source-sha256',seed_sha,'--output-root',str(out/'feathered'),'--skip-exports'])
feathered=out/'feathered/art/characters.blend';feathered_sha=hashlib.sha256(feathered.read_bytes()).hexdigest()
run('cap_clearance','fit_clearance.py',['--source',str(feathered),'--source-sha256',feathered_sha,'--output-root',str(out/'final')])
for path in [seed,feathered,out/'final/art/characters.blend',*sorted((out/'final/assets/models').glob('*.glb'))]:
 receipt['outputs'][str(path.relative_to(out))]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size':path.stat().st_size}
(out/'evidence/reproduction.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('CROP_PIPELINE_COMPLETE',len(receipt['steps']),'native stages',4,'fresh exports')
