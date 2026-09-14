#!/usr/bin/env python3
"""Run character checks in a retained private project, never the live editor.

Examples:
  python3 tests/run_character_quality.py --tests character_identity adoption
  python3 tests/run_character_quality.py --tests actor actor_ages baby_stage
  python3 tests/run_character_quality.py --render probe_character61
  python3 tests/run_character_quality.py --resume /tmp/justlife-character-quality-EXAMPLE
  python3 tests/run_character_quality.py --tests make_baby --import-cache /tmp/justlife-character-quality-EXAMPLE

--render with no names renders every selected test. With names, only those
tests render; all other --tests entries remain headless. Rendering needs an
available display and coordinated window ownership. Logs, isolated save data,
the exact copied inputs and results.json remain in the printed temporary root.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

from run_regressions import digest, environment, private_config, run_process, safe_source


def test_path(source: Path, value: str) -> str:
    value = value.removeprefix("res://")
    if not value.startswith("tests/"):
        name = value.removesuffix(".gd")
        if not name.startswith(("test_", "probe_")):
            name = "test_" + name
        value = "tests/" + name + ".gd"
    if not value.endswith(".gd"):
        value += ".gd"
    safe_source(source, value)
    return value


def copy_inputs(source: Path, project: Path, selected: list[str]) -> dict[str, str]:
    # Copy all runtime sources explicitly so a new class cannot be omitted by
    # an older dependency manifest. Keep test inputs limited to the selected
    # scripts and their literal res://tests/... dependencies.
    paths = {"project.godot", "tests/run_character_quality.py", "tests/run_regressions.py"}
    if (source / "icon.svg").is_file():
        paths.add("icon.svg")
    for folder in ("scripts", "scenes", "assets"):
        for path in (source / folder).rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                paths.add(path.relative_to(source).as_posix())
    pending = list(selected)
    while pending:
        relative = pending.pop()
        if relative in paths:
            continue
        original = safe_source(source, relative)
        paths.add(relative)
        if original.suffix == ".gd":
            if (source / (relative + ".uid")).is_file():
                paths.add(relative + ".uid")
            pending.extend(re.findall(r'''["']res://(tests/[^"']+)["']''', original.read_text()))
    hashes = {}
    for relative in sorted(paths):
        original = safe_source(source, relative)
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        hashes[relative] = digest(target)
    config = project / "project.godot"
    config.write_text(private_config(config.read_text()))
    return hashes


def assertion_summary(output: str) -> dict:
    """Recognize maintained terminal counters without counting PASS chatter."""
    summaries = []
    for line in output.splitlines():
        match = re.search(r"(\d+)\s+(?:checks|assertions)\b.*?(\d+)\s+failures\b", line)
        if match:
            summaries.append({"checks": int(match[1]), "failures": int(match[2]), "line": line})
            continue
        if "RESULT " in line and "{" in line:
            try:
                payload = json.loads(line[line.index("{"):])
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict) and isinstance(payload.get("checks"), int):
                failures = payload.get("failures")
                if isinstance(failures, list):
                    failures = len(failures)
                if isinstance(failures, int):
                    summaries.append({"checks": payload["checks"], "failures": failures, "line": line})
                    continue
        match = re.search(r"\b(?:\w*RESULT|\w*TESTS)\s+(\d+)\s*/\s*(\d+)\s*$", line)
        if match:
            summaries.append({"checks": int(match[1]), "failures": int(match[2]), "line": line})
    if not summaries:
        return {"checks": None, "failures": None, "summary_found": False, "summary_lines": []}
    return {"checks": summaries[-1]["checks"], "failures": summaries[-1]["failures"],
            "summary_found": True, "summary_lines": [entry["line"] for entry in summaries]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tests", nargs="+", help="Test names or source-relative .gd test paths")
    parser.add_argument("--render", nargs="*", metavar="TEST", default=None,
                        help="Render named probes/tests, or all selected tests when no names follow")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--timeout", type=float, default=600, help="Maximum seconds for each owned Godot process, including initial imports")
    parser.add_argument("--resume", type=Path, help="Resume an unchanged private copy after a timeout; retain previous logs")
    parser.add_argument("--import-cache", type=Path, help="Copy generated import cache from an earlier private run into a fresh snapshot; changed assets still reimport")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("This runner requires Linux XDG isolation.")
    if not 0 < args.timeout <= 3600:
        parser.error("--timeout must be in (0, 3600].")
    source = args.source.resolve()
    previous = None
    try:
        if args.resume:
            previous = json.loads((args.resume.resolve() / "results.json").read_text())
            if previous["source"] != str(source) or args.tests or args.render is not None:
                parser.error("--resume retains its original --source and test/render selection; do not supply a new selection.")
        selection = previous["tests"] if previous else (args.tests or ([] if args.render else ["character_identity", "adoption"]))
        selected = [test_path(source, value) for value in selection]
        rendered = {test_path(source, value) for value in args.render} if args.render else set()
        if previous:
            rendered = set(previous["rendered"])
        selected = list(dict.fromkeys(selected + sorted(rendered)))
        if args.render == []:
            rendered = set(selected)
        if not selected:
            parser.error("Choose at least one --tests or --render script.")
        executable = shutil.which(args.godot)
        if not executable:
            parser.error("Godot executable is unavailable: " + args.godot)
    except (OSError, ValueError, KeyError) as exc:
        parser.error(str(exc))
    output = args.resume.resolve() if previous else Path(tempfile.mkdtemp(prefix="justlife-character-quality-"))
    project = output / "project"
    receipt = output / "results.json"
    result = previous or {"source": str(source), "project": str(project), "evidence": str(output),
              "tests": selected, "rendered": sorted(rendered), "status": "running", "steps": [],
              "scope": "Character model/schema tests in an immutable private project snapshot; rendered probes are evidence, not a visual score."}
    print("CHARACTER_QUALITY_EVIDENCE=" + str(output), flush=True)

    def save() -> None:
        receipt.write_text(json.dumps(result, indent=2) + "\n")

    try:
        if previous:
            if output.is_relative_to(source) or result["project"] != str(project) or project.is_symlink():
                raise ValueError("Resume target must be the recorded private project outside source.")
            changed = [name for name, pin in result["copied_hashes"].items() if digest(safe_source(project, name)) != pin]
            if changed:
                raise ValueError("Cannot resume changed copied inputs: " + ", ".join(changed))
            if private_config((project / "project.godot").read_text()) != (project / "project.godot").read_text():
                raise ValueError("Resume project no longer has the isolated configuration.")
        else:
            result["source_hashes"] = copy_inputs(source, project, selected)
            result["copied_hashes"] = {name: digest(project / name) for name in result["source_hashes"]}
            if args.import_cache:
                cache_root = args.import_cache.resolve()
                cache_receipt = json.loads((cache_root / "results.json").read_text())
                cache_project = cache_root / "project"
                if (cache_root.is_relative_to(source) or cache_receipt["project"] != str(cache_project)
                        or cache_project.is_symlink()):
                    raise ValueError("Import cache must belong to a recorded private runner project outside source.")
                cache_config = (cache_project / "project.godot").read_text()
                if private_config(cache_config) != cache_config:
                    raise ValueError("Import cache project no longer has the isolated configuration.")
                asset_pins = {name: pin for name, pin in cache_receipt["copied_hashes"].items() if name.startswith("assets/")}
                if any(digest(safe_source(cache_project, name)) != pin for name, pin in asset_pins.items()):
                    raise ValueError("Import cache assets changed after their recorded snapshot.")
                # Actual copies, never symlinks or shared writable caches. The
                # editor import below validates source/parameter hashes and
                # rebuilds any asset changed in this new source snapshot.
                shutil.copytree(cache_project / ".godot/imported", project / ".godot/imported")
                result["private_import_cache"] = str(cache_root)
        result["status"] = "running"
        result.pop("error", None)
        env, _ = environment(output / "import")
        result["home_unchanged"] = env.get("HOME") == os.environ.get("HOME")
        save()
        print("Importing the private project (editor tooling disabled).", flush=True)
        history = result.setdefault("import_attempts", [])
        if previous and not history and "import" in result:
            history.append(result["import"])
        import_log = output / ("import.log" if not history else "import-%d.log" % (len(history) + 1))
        result["import"] = run_process([executable, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                                        "--editor", "--import", "--quit"], env, import_log, args.timeout)
        history.append(result["import"])
        save()
        if not result["import"]["ok"]:
            raise ValueError("Private import failed; see " + str(import_log))
        for relative in selected:
            if any(step["test"] == relative and step["ok"] for step in result["steps"]):
                continue
            label = Path(relative).stem
            group = output / "runs" / label
            env, user = environment(group)
            command = [executable, "--audio-driver", "Dummy", "--path", str(project)]
            if relative not in rendered:
                command.append("--headless")
            command.extend(["--script", "res://" + relative])
            print("Running " + relative + (" (rendered)" if relative in rendered else " (headless)"), flush=True)
            attempts = sum(step["test"] == relative for step in result["steps"])
            log = group / ("output.log" if not attempts else "output-%d.log" % (attempts + 1))
            record = run_process(command, env, log, args.timeout)
            record.update(assertion_summary(Path(record["log"]).read_text(errors="replace")))
            is_probe = label.startswith("probe_")
            record.update(test=relative, rendered=relative in rendered, user_data=str(user),
                          game_data=env["JUSTLIFE_DATA_DIR"], assertion_gate=not is_probe)
            if record["summary_found"] and record["failures"] != 0:
                record["ok"] = False
            if not is_probe:
                record["ok"] = record["ok"] and record["summary_found"] and record["checks"] > 0 and record["failures"] == 0
            result["steps"].append(record)
            save()
            print(json.dumps({key: record[key] for key in ("test", "exit_code", "checks", "failures", "ok", "log")}), flush=True)
        result["source_changed"] = [name for name, pin in result["source_hashes"].items()
                                    if not (source / name).is_file() or digest(source / name) != pin]
        result["copied_inputs_changed"] = [name for name, pin in result["copied_hashes"].items()
                                           if not (project / name).is_file() or digest(project / name) != pin]
        result["tested_source_matches_current"] = not result["source_changed"]
        # Source can be edited concurrently by another developer. Report its
        # drift explicitly; never claim that a newer checkout was tested.
        latest = {step["test"]: step for step in result["steps"]}
        result["status"] = "passed" if all(latest[test]["ok"] for test in selected) and not result["copied_inputs_changed"] else "failed"
        result["checks"] = sum(step["checks"] or 0 for step in latest.values())
        result["assertion_failures"] = sum(step["failures"] or 0 for step in latest.values())
        save()
        print("CHARACTER_QUALITY_RESULT " + json.dumps({key: result[key] for key in (
            "status", "checks", "assertion_failures", "tested_source_matches_current", "evidence")}), flush=True)
        return 0 if result["status"] == "passed" else 1
    except (OSError, ValueError, KeyError) as exc:
        result.update(status="failed", error=str(exc))
        save()
        print("Character quality run failed: " + str(exc), file=sys.stderr, flush=True)
        return 1
    except KeyboardInterrupt:
        result["status"] = "interrupted"
        save()
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
