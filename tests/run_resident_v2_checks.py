"""Freeze a private Godot source and run neighborhood, V2 travel and custody checks."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1])
    args=parser.parse_args();source=args.source.resolve()
    base=source/'dist'/'test-work';base.mkdir(parents=True,exist_ok=True)
    (source/'dist'/'.gdignore').touch()
    snapshot=Path(tempfile.mkdtemp(prefix='resident-v2-checks-',dir=base))
    for folder in ('scripts','scenes','assets','tests'):
        shutil.copytree(source/folder,snapshot/folder)
    lines=[];skip=False
    for line in (source/'project.godot').read_text().splitlines():
        if line.startswith('['):skip=line in ('[autoload]','[editor_plugins]','[mcp_toolkit]')
        if not skip:lines.append(line)
    (snapshot/'project.godot').write_text('\n'.join(lines)+'\n')
    evidence=snapshot/'evidence';evidence.mkdir();(evidence/'.gdignore').touch()
    userdata=evidence/'userdata';save=evidence/'save_data'
    for directory in (userdata,save,evidence/'tmp',userdata/'godot/app_userdata/JustLife/regression/stair_integration'):
        directory.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy();env.update(XDG_DATA_HOME=str(userdata),JUSTLIFE_DATA_DIR=str(save),TMPDIR=str(base))
    def inputs():
        return {str(p.relative_to(snapshot)):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ('scripts','scenes','assets','tests') for p in (snapshot/folder).rglob('*') if p.is_file() and p.suffix not in ('.import','.uid')}
    hashes=inputs();(evidence/'inputs.json').write_text(json.dumps(hashes,indent=2,sort_keys=True))
    commands=[('import',['--editor','--import','--quit'])]
    for name,extra in [('test_residents_validation',[]),('test_residents',[]),('test_residents_fresh_load',[]),('test_residents_queued',[]),('test_residents_queued',['--','--consume-absent']),('test_neighborhood',[]),('test_residents_v2',[]),('test_residents_v2',['--','--consume']),('test_residents_v2_food',[]),('test_residents_v2_household',[]),('test_stair_controller',[])]:
        commands.append((name+('_fresh' if extra else ''),['--script','res://tests/'+name+'.gd',*extra]))
    results=[]
    for phase,arguments in commands:
        log=evidence/(phase+'.log')
        try:
            with log.open('w') as out:run=subprocess.run([shutil.which('godot') or 'godot','--headless','--path',str(snapshot),*arguments],env=env,stdout=out,stderr=subprocess.STDOUT,timeout=300)
            code=run.returncode
        except subprocess.TimeoutExpired:code=124
        output=log.read_text();failed=code!=0 or 'SCRIPT ERROR:' in output or '\nERROR:' in output
        results.append({'phase':phase,'exit_code':code,'failed':failed,'warnings':output.count('WARNING:'),'log':str(log)})
        print(phase+': '+('FAIL' if failed else 'PASS')+' ('+str(output.count('WARNING:'))+' warnings)',flush=True)
        if failed:break
    after=inputs();changed=sorted(key for key in hashes if hashes[key]!=after.get(key))
    (evidence/'results.json').write_text(json.dumps({'source':str(source),'snapshot':str(snapshot),'phases':results,'changed_inputs':changed},indent=2))
    print('EVIDENCE='+str(evidence),flush=True)
    return int(bool(changed) or len(results)!=len(commands) or any(result['failed'] for result in results))
if __name__=='__main__':raise SystemExit(main())
