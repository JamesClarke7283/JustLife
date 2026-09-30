"""Check adult swing contact and the real game action in an isolated Godot copy."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true", help="Also capture the imported swings and their seated riders.")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    parent = source / "dist/test-work"
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="garden-swing-", dir=parent))
    project = work / "project"
    paths = set(json.loads((source / "tests/regression_inputs.json").read_text())["paths"])
    paths.update({"project.godot", "scripts/garden_swing.gd", "tests/test_garden_swing_motion.gd", "tests/run_garden_swing.py"})
    hashes = {}
    for name in sorted(paths):
        original = source / name
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        hashes[name] = hashlib.sha256(original.read_bytes()).hexdigest()
    config = project / "project.godot"
    config.write_text(re.sub(r"\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)", "", config.read_text(), flags=re.S))
    (work / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
    env = os.environ.copy()
    for key, folder in {"XDG_DATA_HOME": "userdata", "XDG_CONFIG_HOME": "config", "XDG_CACHE_HOME": "cache", "JUSTLIFE_DATA_DIR": "save_data", "TMPDIR": "tmp", "SWING_EVIDENCE_DIR": "evidence"}.items():
        env[key] = str(work / folder)
        Path(env[key]).mkdir()
    print("GARDEN_SWING_WORK=" + str(work), flush=True)
    runs = []
    for phase in ("import", "motion"):
        command = ["godot", "--path", str(project), "--audio-driver", "Dummy"]
        if phase == "import":
            command += ["--headless", "--editor", "--import", "--quit"]
        else:
            command += ["--rendering-method", "gl_compatibility", "--resolution", "960x600"] if args.render else ["--headless"]
            command += ["--script", "res://tests/test_garden_swing_motion.gd"]
        with (work / (phase + ".log")).open("w") as log:
            code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600).returncode
        output = (work / (phase + ".log")).read_text()
        issues = [line for line in output.splitlines() if re.search(r"ERROR:|SCRIPT ERROR|WARNING:|leaked|still in use", line)]
        ok = code == 0 and not issues
        if phase == "motion":
            report = json.loads((work / "evidence/result.json").read_text()) if (work / "evidence/result.json").is_file() else {}
            ok = ok and report.get("checks", 0) > 0 and report.get("failures") == []
        runs.append({"phase": phase, "command": command, "exit_code": code, "ok": ok, "issues": issues})
        (work / "runs.json").write_text(json.dumps(runs, indent=2) + "\n")
        print(json.dumps(runs[-1]), flush=True)
        if not ok:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
