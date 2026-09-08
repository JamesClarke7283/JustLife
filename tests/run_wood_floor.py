#!/usr/bin/env python3
"""Qualify canonical wood materials in a retained isolated Godot project.

Optional --capture-public-slot uses an existing public two-floor checkpoint for
matched artwork views. It copies the original file and never changes it.
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
    parser.add_argument("--capture-public-slot", type=Path,
                        help="Opens a renderer; coordinate desktop ownership first.")
    args = parser.parse_args()
    source = args.source.resolve()
    paths = json.loads((source / "tests/regression_inputs.json").read_text())["paths"]
    paths = list(dict.fromkeys([*paths, "project.godot", "icon.svg",
        "assets/shaders/wood_floor.gdshader", "tests/test_wood_floor.gd",
        "tests/test_starter_floor_finish.gd", "tests/test_live_floor_view.gd",
        "tests/wood_floor_live_control.gd", "tests/capture_wood_floor.gd"]))
    for relative in paths:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or not (source / path).is_file():
            raise ValueError(f"Invalid or missing source input: {relative}")
    output = Path(tempfile.mkdtemp(prefix="wood-floor-checks-"))
    original = {path: digest(source / path) for path in paths}
    for relative in paths:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, target)
    project = output / "project.godot"
    project.write_text(re.sub(r"\n\[(?:autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)",
                              "", project.read_text(), flags=re.S))
    copied = {path: digest(output / path) for path in paths}
    evidence = output / "evidence"
    evidence.mkdir()
    fixture = None
    if args.capture_public_slot:
        supplied = args.capture_public_slot.resolve()
        fixture = {"source": str(supplied), "sha256": digest(supplied)}
        shutil.copy2(supplied, evidence / "original_public_slot.json")
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(output / "userdata"),
        JUSTLIFE_DATA_DIR=str(output / "userdata/save_data"),
        XDG_CONFIG_HOME=str(output / "config"), XDG_CACHE_HOME=str(output / "cache"))
    plans = [("import", ["--headless", "--editor", "--import"]),
        ("wood", ["--headless", "--script", "res://tests/test_wood_floor.gd"]),
        ("starter", ["--headless", "--script", "res://tests/test_starter_floor_finish.gd"]),
        ("live", ["--headless", "--script", "res://tests/wood_floor_live_control.gd"])]
    if fixture:
        plans.append(("capture", ["--resolution", "1440x900", "--audio-driver", "Dummy",
                                  "--script", "res://tests/capture_wood_floor.gd"]))
    receipt = {"source": str(source), "output": str(output), "source_hashes": original,
               "copied_hashes": copied, "fixture": fixture, "runs": []}
    print(f"WOOD_FLOOR_PROJECT={output}", flush=True)
    for label, extra in plans:
        command = [args.godot, "--path", str(output), *extra]
        log_path = evidence / f"{label}.log"
        with log_path.open("w") as log:
            try:
                code = subprocess.run(command, env=env, stdout=log,
                    stderr=subprocess.STDOUT, timeout=180).returncode
            except subprocess.TimeoutExpired:
                code = 124
        text = log_path.read_text()
        problems = re.findall(r"^(?:ERROR:|SCRIPT ERROR:|WARNING:|CHECK FAIL).*", text, re.M)
        summaries = re.findall(r"^(?:WOOD_FLOOR |STARTER_FLOOR_FINISH |LIVE_FLOOR_VIEW |WOOD_CAPTURE ).*$", text, re.M)
        ok = code == 0 and not problems and (label == "import" or bool(summaries))
        receipt["runs"].append({"stage": label, "exit_code": code,
            "ok": ok, "problems": problems, "summaries": summaries,
            "log_sha256": digest(log_path)})
        print(f"{label}: exit={code}, problems={len(problems)}", flush=True)
        if not ok:
            break
    receipt["changed_source"] = [p for p, h in original.items() if digest(source / p) != h]
    receipt["changed_copy"] = [p for p, h in copied.items() if digest(output / p) != h]
    if fixture:
        receipt["fixture_unchanged"] = digest(Path(fixture["source"])) == fixture["sha256"]
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return int(any(not run["ok"] for run in receipt["runs"])
               or bool(receipt["changed_source"] or receipt["changed_copy"])
               or receipt.get("fixture_unchanged") is False)


if __name__ == "__main__":
    raise SystemExit(main())
