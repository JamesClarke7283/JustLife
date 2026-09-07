"""Run rendered public-flow checks in an isolated temporary project and userdata.

No editor plugin, autoload, MCP registration or live-project runtime is started.
Uses the installed Godot executable and actual DISPLAY renderer, not headless.
The source tree is only read; screenshots/reports stay in the returned temp path.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time

def run():
    parser=argparse.ArgumentParser()
    parser.add_argument("--source",type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument("--godot",default=shutil.which("godot") or "godot")
    parser.add_argument("--timeout",type=int,default=240)
    args=parser.parse_args()
    root=Path(tempfile.mkdtemp(prefix="justlife-playthrough-"))
    source=args.source.resolve()
    for folder in ("assets","scripts","scenes","tests"):
        shutil.copytree(source/folder,root/folder)
    if (source/".godot/imported").is_dir():
        shutil.copytree(source/".godot/imported",root/".godot/imported")
    for metadata in ("uid_cache.bin",):
        if (source/".godot"/metadata).is_file():
            shutil.copy2(source/".godot"/metadata,root/".godot"/metadata)
    shutil.copy2(source/"icon.svg",root/"icon.svg")
    # Use the actual project render settings, stripped of addon registration.
    lines=(source/"project.godot").read_text().splitlines()
    clean=[];skip=False
    for line in lines:
        if line.startswith("["):
            skip=line in ("[autoload]","[editor_plugins]","[mcp_toolkit]")
        if not skip:
            clean.append(line)
    (root/"project.godot").write_text("\n".join(clean)+"\n")
    env=os.environ.copy()
    env["XDG_DATA_HOME"]=str(root/"userdata")
    env["XDG_CONFIG_HOME"]=str(root/"config")
    env["XDG_CACHE_HOME"]=str(root/"cache")
    manifests={str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest()
               for folder in ("scripts","tests","scenes") for p in (source/folder).glob("*") if p.is_file()}
    (root/"source_snapshot.json").write_text(json.dumps({"source":str(source),"time":time.time(),"hashes":manifests},indent=2))
    print("ISOLATED_PLAYTHROUGH="+str(root),flush=True)
    # Headless is used only for import. Gameplay runs below have an actual window.
    with (root/"import.log").open("w") as log:
        imported=subprocess.run([args.godot,"--headless","--editor","--path",str(root),"--import"],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
    if imported.returncode:
        raise SystemExit("Import failed; inspect "+str(root/"import.log"))
    results=[]
    for stage,extras in (("playthrough",[]),("resume",["--","--resume-only"])):
        command=[args.godot,"--path",str(root),"--resolution","1440x900","--audio-driver","Dummy","--script","res://tests/test_playthrough.gd",*extras]
        with (root/f"{stage}.log").open("w") as log:
            try:
                result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
                code=result.returncode
            except subprocess.TimeoutExpired:
                code=124
        log_text=(root/f"{stage}.log").read_text()
        runtime_errors=re.findall(r"^(?:SCRIPT ERROR|ERROR):.*",log_text,re.M)
        result_path=root/"art/playthrough"/("resume_results.json" if stage=="resume" else "playthrough_results.json")
        if runtime_errors or not result_path.is_file():
            code=code or 1
        print(stage+" exit="+str(code)+" runtime_errors="+str(len(runtime_errors))+" log="+str(root/f"{stage}.log"),flush=True)
        results.append({"stage":stage,"exit_code":code,"runtime_errors":runtime_errors,"report_exists":result_path.is_file()})
        # Resume requires the first stage to have written a save, but failures in
        # other assertions should not hide a useful persistence verification.
        if stage=="playthrough" and not list((root/"userdata").rglob("playthrough_expected.json")):
            break
    (root/"run_results.json").write_text(json.dumps(results,indent=2))
    print("EVIDENCE="+str(root/"art/playthrough"),flush=True)
    raise SystemExit(0 if all(r["exit_code"]==0 for r in results) else 1)

if __name__=="__main__":
    run()
