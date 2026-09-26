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
    parser.add_argument("--resume-from",type=Path,help="Adoption only: copy a prior isolated playthrough userdata directory for a fresh-process diagnostic replay")
    parser.add_argument("--timeout",type=int,default=240)
    parser.add_argument("--adoption-ui-only",action="store_true",help="Adoption only: verify public candidate/review/cancel at actual 960×600; no transaction or overnight replay")
    parser.add_argument("--adoption-oven",action="store_true",help="Adoption suite: preserve an actual paid oven loading pose while adopting; grants fixture Cooking XP before play")
    parser.add_argument("--continue-family",action="store_true",help="Keep the isolated 180-day household and play on from its latest save")
    parser.add_argument("--suite",choices=("offlot_school","offlot_career","home","neighborhood","menus","bench","creator","family","activity","lifecycle","school","school_presentation","desk","chair","grip","genealogy","grip_birthday","family_rewards","surface","autonomy_week","wait_priority","supported_homework","speech_lifetime","meals","meals_build","recipes","meal_placement","dense_meals","standing_dining","adoption","catalogue_week","loveseat","couch","ninety_day_progress","one_eighty_day_family"),default="home")
    args=parser.parse_args()
    if args.adoption_ui_only and (args.suite!="adoption" or args.resume_from):parser.error("--adoption-ui-only requires fresh --suite adoption")
    if args.adoption_oven and args.suite!="adoption":parser.error("--adoption-oven requires --suite adoption")
    if args.continue_family and args.suite!="one_eighty_day_family":parser.error("--continue-family requires --suite one_eighty_day_family")
    if args.resume_from and (args.suite!="adoption" or args.resume_from.name!="userdata" or not args.resume_from.parent.name.startswith("justlife-playthrough-") or not args.resume_from.is_dir()):
        parser.error("--resume-from requires an adoption playthrough's isolated userdata directory")
    source_root=args.source.resolve()
    if args.suite=="one_eighty_day_family":
        # Isolated from the player's ~/.justlife saves. Wiping this folder only
        # removes an earlier copy of this same playthrough.
        root=source_root/"dist"/"test-work"/"justlife-playthrough-one-eighty"
        if root.name!="justlife-playthrough-one-eighty" or root.parent.name!="test-work":
            parser.error("refusing to reset a playthrough directory outside dist/test-work")
        if root.exists() and not args.continue_family:
            shutil.rmtree(root)
        if not args.continue_family:
            root.mkdir(parents=True)
        elif not (root/"project.godot").is_file():
            parser.error("nothing to continue; the isolated playthrough directory is missing")
    else:
        root=Path(tempfile.mkdtemp(prefix="justlife-playthrough-"))
    script={"adoption":"test_adoption_playthrough.gd","catalogue_week":"test_catalogue_week.gd","offlot_career":"test_offlot_career_ui.gd","offlot_school":"test_offlot_school_ui.gd","home":"test_playthrough.gd","neighborhood":"test_neighborhood_playthrough.gd","menus":"test_menu_edges.gd","bench":"test_bench_playthrough.gd","creator":"test_creator_playthrough.gd","family":"test_family_playthrough.gd","activity":"test_activity_playthrough.gd","lifecycle":"test_lifecycle_playthrough.gd","school":"test_school_playthrough.gd","school_presentation":"test_school_presentation.gd","desk":"test_desk_clearance.gd","chair":"test_shared_chair.gd","grip":"test_grip_playthrough.gd","genealogy":"test_genealogy_playthrough.gd","grip_birthday":"test_grip_birthday.gd","family_rewards":"test_family_rewards_playthrough.gd","surface":"test_surface_playthrough.gd","wait_priority":"test_wait_priority_playthrough.gd","autonomy_week":"test_autonomy_week.gd","supported_homework":"test_supported_homework_ui.gd","speech_lifetime":"test_speech_lifetime.gd","meals":"test_meal_playthrough.gd","meals_build":"test_meal_build_ui.gd","recipes":"test_recipe_playthrough.gd","meal_placement":"test_meal_placement_ui.gd","dense_meals":"test_dense_meals.gd","standing_dining":"test_standing_dining_ui.gd","ninety_day_progress":"test_ninety_day_progress.gd","loveseat":"test_loveseat_watchers.gd","couch":"test_couch_playthrough.gd","ninety_day_progress":"test_ninety_day_progress.gd","one_eighty_day_family":"test_one_eighty_day_family.gd"}[args.suite]
    evidence_folder={"adoption":"adoption_playthrough","catalogue_week":"catalogue_week","offlot_career":"offlot_career","offlot_school":"offlot_school","home":"playthrough","neighborhood":"neighborhood_playthrough","menus":"menu_edges","bench":"bench_playthrough","creator":"creator_playthrough","family":"family_playthrough","activity":"activity_playthrough","lifecycle":"lifecycle_playthrough","school":"school_playthrough","school_presentation":"school_presentation","desk":"desk_clearance","chair":"shared_chair","grip":"activity_playthrough","genealogy":"genealogy_playthrough","grip_birthday":"grip_birthday","family_rewards":"family_rewards","surface":"activity_playthrough","wait_priority":"wait_priority","autonomy_week":"autonomy_week","supported_homework":"supported_homework","speech_lifetime":"speech_lifetime","meals":"meals_playthrough","meals_build":"meals_playthrough","recipes":"recipe_playthrough","meal_placement":"meal_placement","dense_meals":"dense_meals","standing_dining":"standing_dining","ninety_day_progress":"ninety_day_progress","loveseat":"loveseat_watchers","couch":"couch_seating","ninety_day_progress":"ninety_day_progress","one_eighty_day_family":"one_eighty_day_family"}[args.suite]
    expected_file={"adoption":"adoption_expected.json","catalogue_week":"catalogue_expected.json","offlot_career":"offlot_career_expected.json","offlot_school":"offlot_school_expected.json","home":"playthrough_expected.json","neighborhood":"neighborhood_expected.json","menus":"menu_edges_no_resume.json","bench":"bench_no_resume.json","creator":"creator_no_resume.json","family":"family_expected.json","activity":"activity_no_resume.json","lifecycle":"lifecycle_expected.json","school":"school_expected.json","school_presentation":"school_presentation_no_resume.json","desk":"desk_no_resume.json","chair":"chair_no_resume.json","grip":"grip_no_resume.json","genealogy":"genealogy_expected.json","grip_birthday":"grip_birthday_no_resume.json","family_rewards":"family_rewards_no_resume.json","surface":"surface_no_resume.json","wait_priority":"wait_priority_expected.json","autonomy_week":"autonomy_expected.json","supported_homework":"supported_homework_expected.json","speech_lifetime":"speech_lifetime_no_resume.json","meals":"meals_expected.json","meals_build":"meals_expected.json","recipes":"recipe_expected.json","meal_placement":"meal_placement_expected.json","dense_meals":"dense_meals_expected.json","standing_dining":"standing_dining_expected.json","ninety_day_progress":"ninety_day_no_resume.json","loveseat":"loveseat_no_resume.json","couch":"couch_expected.json","ninety_day_progress":"ninety_day_no_resume.json","one_eighty_day_family":"one_eighty_expected.json"}[args.suite]
    source=args.source.resolve()
    if not args.continue_family:
        for folder in ("assets","scripts","scenes","tests"):
            shutil.copytree(source/folder,root/folder)
    # Allows rerunning a frozen production snapshot with a corrected harness.
    for harness in ("test_offlot_career_ui.gd","test_offlot_school_ui.gd","test_playthrough.gd", "test_neighborhood_playthrough.gd", "test_menu_edges.gd", "test_bench_playthrough.gd", "test_creator_playthrough.gd", "test_family_playthrough.gd", "test_activity_playthrough.gd", "test_lifecycle_playthrough.gd", "test_school_playthrough.gd", "test_school_presentation.gd", "test_desk_clearance.gd", "test_shared_chair.gd", "test_grip_playthrough.gd", "test_genealogy_playthrough.gd", "test_grip_birthday.gd", "test_family_rewards_playthrough.gd", "test_surface_playthrough.gd", "test_autonomy_week.gd", "test_wait_priority_playthrough.gd", "test_supported_homework_ui.gd", "test_speech_lifetime.gd", "test_meal_playthrough.gd", "test_meal_build_ui.gd", "test_recipe_playthrough.gd", "test_meal_placement_ui.gd", "test_dense_meals.gd", "food_setdown_observer.gd", "test_standing_dining_ui.gd", "test_adoption_playthrough.gd", "test_catalogue_week.gd", "test_loveseat_watchers.gd", "test_couch_playthrough.gd", "test_ninety_day_progress.gd", "test_one_eighty_day_family.gd"):
        if Path(__file__).with_name(harness).is_file():
            shutil.copy2(Path(__file__).with_name(harness),root/"tests"/harness)
    if (source/".godot/imported").is_dir() and not args.continue_family:
        shutil.copytree(source/".godot/imported",root/".godot/imported")
    for metadata in ("uid_cache.bin",):
        if (source/".godot"/metadata).is_file():
            shutil.copy2(source/".godot"/metadata,root/".godot"/metadata)
    if not args.continue_family:
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
    if args.resume_from:
        shutil.copytree(args.resume_from,root/"userdata")
        receipt={"source":str(args.resume_from.resolve()),"hashes":{str(p.relative_to(args.resume_from)):hashlib.sha256(p.read_bytes()).hexdigest() for p in args.resume_from.rglob("*") if p.is_file()}}
        (root/"resume_checkpoint_manifest.json").write_text(json.dumps(receipt,indent=2))
    env=os.environ.copy()
    env["XDG_DATA_HOME"]=str(root/"userdata")
    env["JUSTLIFE_DATA_DIR"]=str(root/"userdata"/"save_data")
    env["XDG_CONFIG_HOME"]=str(root/"config")
    env["XDG_CACHE_HOME"]=str(root/"cache")
    env["JUSTLIFE_KEEP_OPEN"]="1"
    if args.continue_family:
        env["JUSTLIFE_CONTINUE"]="1"
        prior=root/"playthrough.log"
        if prior.is_file():
            shutil.copy2(prior, root/"playthrough_through_day104.log")
    manifests={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest()
               for folder in ("scripts","tests","scenes") for p in (root/folder).glob("*") if p.is_file()}
    for p in (root/"assets").rglob("*.glb"):
        manifests[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
    (root/"source_snapshot.json").write_text(json.dumps({"source":str(source),"time":time.time(),"hashes":manifests},indent=2))
    print("ISOLATED_PLAYTHROUGH="+str(root),flush=True)
    if not args.continue_family:
        # Headless is used only for import. Gameplay runs below have an actual window.
        with (root/"import.log").open("w") as log:
            imported=subprocess.run([args.godot,"--headless","--editor","--path",str(root),"--import"],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
        if imported.returncode or "SCRIPT ERROR" in (root/"import.log").read_text():
            raise SystemExit("Import failed; inspect "+str(root/"import.log"))
    results=[]
    stages=(("resume",["--","--resume-only"]),) if args.resume_from else (("playthrough",[]),("resume",["--","--resume-only"]))
    for stage,extras in stages:
        if args.adoption_oven:extras=[*extras,"--adoption-oven"] if extras else ["--","--adoption-oven"]
        if args.adoption_ui_only:extras=[*extras,"--adoption-ui-only"] if extras else ["--","--adoption-ui-only"]
        command=[args.godot,"--path",str(root),"--resolution","1440x900","--audio-driver","Dummy","--script","res://tests/"+script,*extras]
        if script=="test_catalogue_week.gd" and args.timeout<2400:
            print("WARNING: catalogue_week's in-process watchdog fires at 2400 s; pass --timeout 2400 so a timeout kill cannot precede the result line",flush=True)
        with (root/f"{stage}.log").open("w") as log:
            try:
                result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
                code=result.returncode
            except subprocess.TimeoutExpired:
                code=124
                # A process-level successor of the in-process RESULT line: a
                # killed stage still leaves a visible, greppable result marker.
                print(stage.upper()+"_RESULT incomplete — runner killed the stage at the %d s timeout"%args.timeout,flush=True)
        log_text=(root/f"{stage}.log").read_text()
        runtime_errors=re.findall(r"^(?:SCRIPT ERROR|ERROR):.*",log_text,re.M)
        result_path=root/"art"/evidence_folder/("resume_results.json" if stage=="resume" else "playthrough_results.json")
        if runtime_errors or not result_path.is_file():
            code=code or 1
        print(stage+" exit="+str(code)+" runtime_errors="+str(len(runtime_errors))+" log="+str(root/f"{stage}.log"),flush=True)
        results.append({"stage":stage,"exit_code":code,"runtime_errors":runtime_errors,"report_exists":result_path.is_file()})
        # Resume requires the first stage to have written a save, but failures in
        # other assertions should not hide a useful persistence verification.
        if stage=="playthrough" and not list((root/"userdata").rglob(expected_file)):
            break
    (root/"run_results.json").write_text(json.dumps(results,indent=2))
    print("EVIDENCE="+str(root/"art"/evidence_folder),flush=True)
    if args.suite=="one_eighty_day_family":
        dest=source/"evidence"/"one_eighty_day_family"
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True)
        produced=root/"art"/"one_eighty_day_family"
        if produced.is_dir():
            for item in produced.iterdir():
                target=dest/item.name
                if item.is_dir():
                    shutil.copytree(item,target)
                else:
                    shutil.copy2(item,target)
        for name in ("playthrough.log","resume.log","import.log","run_results.json"):
            if (root/name).is_file():
                shutil.copy2(root/name,dest/name)
        for path in (root/"userdata").rglob("*"):
            if path.is_file() and ("glitch" in path.name or path.name.startswith("one_eighty")):
                shutil.copy2(path,dest/path.name)
        print("EVIDENCE_COPY="+str(dest),flush=True)
    raise SystemExit(0 if all(r["exit_code"]==0 for r in results) else 1)

if __name__=="__main__":
    run()
