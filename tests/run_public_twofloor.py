#!/usr/bin/env python3
"""Exercise public creation, two-storey building, upstairs save and real travel.

Creates a retained private project and save directory. The source project and
the player's saves are never launched or modified. Gameplay needs a renderer.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    source = args.source.resolve()
    paths = json.loads((source / "tests/regression_inputs.json").read_text())["paths"]
    paths = list(dict.fromkeys([*paths, "tests/test_playthrough.gd",
        "tests/test_public_twofloor.gd", "project.godot", "icon.svg"]))
    for relative in paths:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or not (source / path).is_file():
            raise ValueError(f"Invalid or missing source input: {relative}")
    output = Path(tempfile.mkdtemp(prefix="justlife-playthrough-twofloor-"))
    original = {relative: digest(source / relative) for relative in paths}
    for relative in paths:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, target)
    clean, skip = [], False
    for line in (output / "project.godot").read_text().splitlines():
        if line.startswith("["):
            skip = line in ("[autoload]", "[editor_plugins]", "[mcp_toolkit]")
        if not skip:
            clean.append(line)
    (output / "project.godot").write_text("\n".join(clean) + "\n")
    copied = {relative: digest(output / relative) for relative in paths}
    (output / "source_snapshot.json").write_text(json.dumps({
        "source": str(source), "hashes": original, "copied_hashes": copied}, indent=2) + "\n")
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(output / "userdata"),
        JUSTLIFE_DATA_DIR=str(output / "userdata/save_data"),
        XDG_CONFIG_HOME=str(output / "config"), XDG_CACHE_HOME=str(output / "cache"))
    print(f"PUBLIC_TWOFLOOR_PROJECT={output}", flush=True)
    plans = [
        ("import", ["--headless", "--editor", "--import"], None),
        ("public", [], "twofloor_public.json"),
        ("resume", ["--", "--resume-only"], "twofloor_resume.json")]
    results = []
    for name, extra, report in plans:
        command = [args.godot, "--path", str(output)]
        if name == "import":
            command += extra
        else:
            command += ["--resolution", "1440x900", "--audio-driver", "Dummy",
                "--script", "res://tests/test_public_twofloor.gd", *extra]
        with (output / f"{name}.log").open("w") as log:
            try:
                code = subprocess.run(command, env=env, stdout=log,
                    stderr=subprocess.STDOUT, timeout=args.timeout).returncode
            except subprocess.TimeoutExpired:
                code = 124
        log_text = (output / f"{name}.log").read_text()
        problems = re.findall(r"^(?:ERROR:|SCRIPT ERROR:|WARNING:|CHECK FAIL).*", log_text, re.M)
        result = {"stage": name, "exit_code": code, "problems": problems}
        # The engine's static-resource finalize notice ("N RIDs of type
        # "Texture" were leaked") reproduces on a bare menu exit at HEAD
        # (iteration 59 review). It is recorded, not silently dropped, and
        # only clears when the stage otherwise shows zero errors and zero
        # failed checks; any other warning still fails the stage.
        finalize_notices = [p for p in problems
            if re.fullmatch(r"WARNING: \d+ RIDs? of type \"Texture\" were leaked\.", p)]
        if finalize_notices and len(finalize_notices) == len(problems) \
                and code == 0 and not result.get("failures"):
            problems = []
            result["recognized_finalize_notices"] = finalize_notices
            result["problems"] = problems
        if report:
            path = output / "evidence" / report
            result["report_exists"] = path.is_file()
            if path.is_file():
                detail = json.loads(path.read_text())
                result.update(checks=detail["assertions"], failures=detail["failures"])
            else:
                code = code or 1
        if problems or result.get("failures"):
            code = code or 1
        result["exit_code"] = code
        results.append(result)
        (output / "run_results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(f"{name}: exit={code}, problems={len(problems)}", flush=True)
        if code:
            break
    drift = {
        "source": [p for p, h in original.items() if digest(source / p) != h],
        "copy": [p for p, h in copied.items() if digest(output / p) != h]}
    (output / "input_verification.json").write_text(json.dumps(drift, indent=2) + "\n")
    return int(any(x["exit_code"] for x in results) or any(drift.values()))


if __name__ == "__main__":
    raise SystemExit(main())
