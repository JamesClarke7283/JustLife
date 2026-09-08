"""Private main-scene sanitation checks with fresh-process save restoration."""
from pathlib import Path
import argparse, hashlib, json, os, re, shutil, subprocess, sys, tempfile
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--capture',action='store_true');a=p.parse_args()
if not sys.platform.startswith("linux"):p.error("This verification runner requires Linux XDG isolation.")
source=a.source.resolve();work=Path(tempfile.mkdtemp(prefix='justlife-sanitation-'));print('SANITATION_CANDIDATE='+str(work),flush=True)
for folder in ('scripts','assets','scenes'):shutil.copytree(source/folder,work/folder,ignore=shutil.ignore_patterns('*_rig*','*_grip*'))
(work/'tests').mkdir()
for name in ('test_sanitation.gd','test_sanitation_busy.gd','test_sanitation_travel.gd'):shutil.copy2(source/'tests'/name,work/'tests'/name)
s=(source/'project.godot').read_text();s=re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)','',s,flags=re.S);(work/'project.godot').write_text(s)
env=os.environ.copy();env['XDG_DATA_HOME']=str(work/'userdata');env['XDG_CONFIG_HOME']=str(work/'config');env['XDG_CACHE_HOME']=str(work/'cache');env['JUSTLIFE_DATA_DIR']=str(work/'save_data')
manifest={str(f.relative_to(work)):hashlib.sha256(f.read_bytes()).hexdigest() for f in work.rglob('*') if f.is_file() and not f.name.endswith('.import')}
results=[]
for phase in ('import','first','resume','busy','travel'):
 cmd=['godot','--path',str(work)]
 if phase=='import':cmd+=['--headless','--editor','--import']
 else:
  if not a.capture:cmd+=['--headless']
  script={'busy':'test_sanitation_busy.gd','travel':'test_sanitation_travel.gd'}.get(phase,'test_sanitation.gd')
  cmd+=['--script','res://tests/'+script,'--']
  if phase=='busy':cmd+=['--busy']
  if phase=='resume':cmd+=['--resume']
  if a.capture:cmd+=['--capture']
 with (work/(phase+'.log')).open('w') as log:
  result=subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=150)
 text=(work/(phase+'.log')).read_text();errors=re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING):.*',text,re.M)
 summaries=re.findall(r'Sanitation(?: travel)?: (\d+) checks, (\d+) failures\.',text)
 ok=result.returncode==0 and not errors and (phase=='import' or bool(summaries))
 results.append(dict(phase=phase,exit_code=result.returncode,errors=errors,summaries=summaries,ok=ok));print(phase+': '+str(results[-1]),flush=True)
 (work/'run_receipt.json').write_text(json.dumps({'source':str(source),'runs':results,'inputs':manifest,'changed':[r for r,h in manifest.items() if hashlib.sha256((work/r).read_bytes()).hexdigest()!=h]},indent=2))
 if not ok:raise SystemExit(1)
