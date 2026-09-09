"""Reproduce the two authored adult eye stages from a pinned native input.

All outputs are new private files. No editor instance or repository source is changed.
"""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,time
HERE=Path(__file__).resolve().parent

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 source=p.add_mutually_exclusive_group(required=True)
 source.add_argument('--repository',type=Path,help='Local Git repository containing the pinned input commit')
 source.add_argument('--input-blend',type=Path,help='Standalone byte-exact original input instead of Git')
 p.add_argument('--output',type=Path,required=True);p.add_argument('--blender',default='blender')
 a=p.parse_args();out=a.output.resolve();contract=json.loads((HERE/'contract.json').read_text())
 if out.exists():p.error('Output must not exist; prior attempts are retained.')
 if a.repository and out==a.repository.resolve():p.error('Output must be separate from repository.')
 if a.input_blend and out in a.input_blend.resolve().parents:p.error('Output must not contain the input.')
 out.mkdir(parents=True);(out/'inputs').mkdir();(out/'logs').mkdir()
 baseline=out/'inputs/characters.blend'
 if a.repository:
  raw=subprocess.check_output(['git','-C',str(a.repository.resolve()),'show',contract['baseline']['commit']+':'+contract['baseline']['path']])
  baseline.write_bytes(raw)
 else:shutil.copy2(a.input_blend.resolve(),baseline)
 if sha(baseline)!=contract['baseline']['sha256']:raise ValueError('Baseline bytes differ from the reviewed input.')
 tools={p.name:sha(p) for p in HERE.iterdir() if p.is_file()}
 receipt={'baseline':contract['baseline'],'tools':tools,'phases':[],'outputs':{},'status':'started'}
 def write(): (out/'RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
 write()
 def run(name,script,args,threads):
  cmd=[a.blender,'--background','-t',str(threads),'--python',str(HERE/script),'--',*map(str,args)]
  path=out/'logs'/f'{name}.log';started=time.monotonic()
  with path.open('w') as stream:
   try:code=subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT,timeout=240).returncode
   except subprocess.TimeoutExpired:code=124
  rec={'phase':name,'command':cmd,'exit_code':code,'seconds':time.monotonic()-started,'log_sha256':sha(path)}
  receipt['phases'].append(rec);write()
  if code:receipt['status']='failed';write();raise RuntimeError('Failed phase retained: '+name)
 run('sculpt_socket','sculpt_socket.py',['--source',baseline,'--source-sha256',sha(baseline),'--output-root',out/'socket'],6)
 socket=out/'socket/art/characters.blend'
 run('blend_lids','blend_lids.py',['--source',socket,'--source-sha256',sha(socket),'--reference',baseline,'--reference-sha256',sha(baseline),'--output-root',out/'final'],6)
 final=out/'final/art/characters.blend'
 run('native_reopen','verify_native.py',['--source',final,'--contract',HERE/'contract.json','--report',out/'final/evidence/native_reopen.json'],1)
 for stem in ('character','character_broad','character_lod','character_broad_lod'):
  run(stem,'export_variant.py',['--source',final,'--source-sha256',sha(final),'--output-root',out/'final/assets/models','--variant',stem],1)
  path=out/'final/assets/models'/f'{stem}.glb';rel=str(path.relative_to(out/'final'));receipt['outputs'][rel]=sha(path)
  if sha(path)!=contract['expected_outputs'][rel]:receipt['status']='failed export reproduction';write();raise ValueError('Export differs: '+rel)
 assert sha(baseline)==contract['baseline']['sha256']
 assert all(sha(HERE/name)==value for name,value in tools.items())
 receipt['outputs']['art/characters.blend']=sha(final)
 receipt['native_byte_exact']=sha(final)==contract['expected_outputs']['art/characters.blend']
 receipt['native_recorded_values_exact']=True
 receipt['status']='complete';write();print('ADULT_EYE_REPRODUCTION_COMPLETE',out)
 return 0
if __name__=='__main__':raise SystemExit(main())
