"""Freeze a private oven candidate, parse it, then run three rendered processes.
No source editor, addons, original userdata, or runtime source mutations.
Use --parse-only while the independently owned pose and assets are evolving.
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--parse-only", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve()
    root = Path(tempfile.mkdtemp(prefix="justlife-playthrough-"))
    def excluded_local_files(directory, names):
        relative = Path(directory).relative_to(source)
        if relative == Path("assets/models"):
            return [name for name in names if "_rig" in name or "_grip" in name]
        if relative == Path("assets/audio"):
            return [name for name in names if name == "measurements.json"]
        return [name for name in names if name == "__pycache__"]

    for folder in ("assets", "scripts", "scenes", "tests"):
        shutil.copytree(source / folder, root / folder, ignore=excluded_local_files)
    # Copy this exact authored harness alongside production from --source.
    for name in ("test_oven_playthrough.gd", "run_oven_playthrough.py"):
        shutil.copy2(Path(__file__).with_name(name), root / "tests" / name)
    shutil.copy2(source / "icon.svg", root / "icon.svg")
    clean = []
    skip = False
    for line in (source / "project.godot").read_text().splitlines():
        if line.startswith("["):
            skip = line in ("[autoload]", "[editor_plugins]", "[mcp_toolkit]")
        if not skip:
            clean.append(line)
    (root / "project.godot").write_text("\n".join(clean) + "\n")
    env = os.environ.copy()
    for key, folder in (("XDG_DATA_HOME", "userdata"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        env[key] = str(root / folder)
    hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ("scripts", "tests", "scenes", "assets")
              for p in (root / folder).rglob("*") if p.is_file()}
    (root / "source_snapshot.json").write_text(json.dumps({"source": str(source), "created": time.time(), "hashes": hashes}, indent=2))
    print("ISOLATED_OVEN_PLAYTHROUGH=" + str(root), flush=True)

    def invoke(label, command):
        with (root / (label + ".log")).open("w") as log:
            try:
                code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout).returncode
            except subprocess.TimeoutExpired:
                code = 124
        content = (root / (label + ".log")).read_text()
        errors = re.findall(r"^(?:SCRIPT ERROR|ERROR):.*", content, re.M)
        print(f"{label} exit={code} errors={len(errors)}", flush=True)
        return {"label": label, "exit": code, "errors": errors}

    results = []
    for label, command in (
        ("import", [args.godot, "--headless", "--editor", "--path", str(root), "--import"]),
        ("parse", [args.godot, "--headless", "--path", str(root), "--script", "res://tests/test_oven_playthrough.gd", "--check-only"]),
    ):
        result = invoke(label, command)
        results.append(result)
        if result["exit"] or result["errors"]:
            (root / "run_results.json").write_text(json.dumps(results, indent=2))
            raise SystemExit(1)
    if not args.parse_only:
        for stage in (1, 2, 3):
            result = invoke(f"stage_{stage}", [args.godot, "--path", str(root), "--resolution", "1440x900", "--audio-driver", "Dummy", "--script", "res://tests/test_oven_playthrough.gd", "--", f"--oven-stage={stage}"])
            report = root / "art" / "oven_playthrough" / f"stage_{stage}_results.json"
            result["report_exists"] = report.is_file()
            if report.is_file():
                data = json.loads(report.read_text())
                result["assertions"] = data["assertions"]
                result["failures"] = data["failures"]
            results.append(result)
            if result["exit"] or result["errors"] or not result["report_exists"] or result.get("failures"):
                break
            if stage < 3 and not list((root / "userdata").rglob(f"oven_stage_{stage}_expected.json")):
                result["missing_checkpoint"] = True
                break
    (root / "run_results.json").write_text(json.dumps(results, indent=2))
    print("EVIDENCE=" + str(root / "art" / "oven_playthrough"), flush=True)
    failed = any(r["exit"] or r["errors"] or r.get("failures") or r.get("missing_checkpoint") or r.get("report_exists") is False for r in results)
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    run()
