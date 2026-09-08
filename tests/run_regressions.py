#!/usr/bin/env python3
"""Run selected Godot regressions in a new, retained Linux sandbox.

Never imports or runs the supplied source directory. Only the explicit input
manifest and selected tests are copied. See REGRESSIONS.md for evidence scope.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass, field
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

MOVEMENT_CASES = ("walk_up", "walk_down", "cancel_empty", "cancel_later")
FOOD_CASES = ("serving_empty", "serving_later", "partial_empty", "partial_later")
SUMMARIES = {
    "building_modules": "BUILDING_MODULES", "build_world_levels": "BUILD_WORLD_LEVELS",
    "world_legacy_ingress": "WORLD_LEGACY_INGRESS", "build_transactions": "BUILD_TRANSACTIONS",
    "build_history": "BUILD_HISTORY", "build_protection": "BUILD_PROTECTION",
    "furnishing_protection": "FURNISHING_PROTECTION", "cutaway_decorations": "CUTAWAY_DECORATION_CONTROLS",
    "roof_geometry": "ROOF_GEOMETRY", "roof_world": "ROOF_WORLD", "roof_transactions": "ROOF_TRANSACTIONS",
    "stair_controller": "STAIR_CONTROLLER", "stair_rotated_controller": "STAIR_ROTATED_CONTROLLER",
    "stair_motion": "STAIR_MOTION", "stair_collision": "STAIR_SHOE_COLLISION",
    "stair_reconstruction": "STAIR_RECONSTRUCTION", "stair_save": "STAIR_SAVE",
    "stair_save_process": "STAIR_SAVE_PROCESS", "stair_save_rejection": "STAIR_SAVE_REJECTIONS",
    "meal_floor_levels": "MEAL_FLOOR_LEVELS", "stair_food_custody": "STAIR_FOOD_PROCESS",
    "stair_food_clear_failure": "FOOD_CLEAR_FAILURE", "stair_leftover_save": "STAIR_LEFTOVER",
    "build_food_save": "BUILD_FOOD_SAVE", "adoption_journeys": "ADOPTION_JOURNEYS",
    "adoption_journey_custody": "ADOPTION_JOURNEY_CUSTODY", "waiting_autonomy": "WAITING_AUTONOMY",
    "action_duration_compatibility": "DURATION_COMPATIBILITY",
}
GROUPS = ("duration", "architecture", "build", "protection", "controller", "stair-save",
          "food", "leftover", "food-clear", "build-food", "adoption", "motion", "waiting")
ERROR = re.compile(r"^(?:SCRIPT ERROR:|ERROR:|Parse Error:|CHECK FAIL|FAIL\b)", re.MULTILINE)

@dataclass
class Step:
    suite: str
    stage: str = ""
    case: str = ""
    requires: tuple[str, ...] = ()
    creates: tuple[str, ...] = ()
    env: dict[str, str] = field(default_factory=dict)

    @property
    def label(self) -> str:
        return "_".join(x for x in (self.suite, self.case, self.stage) if x)


def pair(suite: str, case: str, prefix: str) -> list[Step]:
    expected = f"regression/stair_save/{prefix}_{case}_expected.json"
    return [Step(suite, "produce", case, creates=(expected,)),
            Step(suite, "consume", case, requires=(expected,))]


def plan(groups: list[str], movement: list[str], food: list[str]) -> list[tuple[str, list[Step]]]:
    result = []
    simple = {
        "duration": ["action_duration_compatibility"],
        "architecture": ["building_modules", "build_world_levels", "world_legacy_ingress",
                         "cutaway_decorations", "roof_geometry", "roof_world", "meal_floor_levels"],
        "build": ["build_transactions", "build_history", "roof_transactions"],
        "protection": ["build_protection", "furnishing_protection"],
        "controller": ["stair_controller", "stair_rotated_controller"],
        "waiting": ["waiting_autonomy"],
        "motion": ["stair_reconstruction", "stair_collision", "stair_motion"],
    }
    for group in dict.fromkeys(groups):
        if group in simple:
            # Standalones also get separate save/report directories.
            result += [(group + "-" + suite, [Step(suite)]) for suite in simple[group]]
        elif group == "stair-save":
            result.append(("stair-save-same-process", [Step("stair_save")]))
            for case in movement:
                steps = pair("stair_save_process", case, "fresh")
                if case == "cancel_later":
                    steps.append(Step("stair_save_rejection", requires=("regression/stair_save/fresh_cancel_later_expected.json",)))
                result.append((group + "-" + case, steps))
        elif group in ("food", "build-food"):
            for case in food:
                result.append((group + "-" + case, pair("stair_food_custody" if group == "food" else "build_food_save", case, "food")))
        elif group == "leftover":
            base = pair("stair_food_custody", "partial_empty", "food")[0]
            result.append((group, [base,
                Step("stair_leftover_save", "produce", "partial_empty",
                     requires=("regression/stair_save/food_partial_empty_expected.json",),
                     creates=("regression/stair_save/leftover_expected.json",)),
                Step("stair_leftover_save", "consume", "partial_empty",
                     requires=("regression/stair_save/leftover_expected.json",))]))
        elif group == "food-clear":
            result.append((group, [pair("stair_food_custody", "partial_later", "food")[0],
                Step("stair_food_clear_failure", requires=("regression/stair_save/food_partial_later_expected.json",))]))
        elif group == "adoption":
            expected = "adoption_custody_expected.json"
            result.append(("adoption-basic", [Step("adoption_journeys")]))
            result.append(("adoption-custody", [
                Step("adoption_journey_custody", "produce", creates=(expected,), env={"ADOPTION_JOURNEY_STAGE": "produce"}),
                Step("adoption_journey_custody", "consume", requires=(expected,), env={"ADOPTION_JOURNEY_STAGE": "consume"})]))
    return result


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_source(source: Path, relative: str) -> Path:
    path = source / relative
    if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(source):
        raise ValueError(f"Input escapes source: {relative}")
    if not path.is_file():
        raise ValueError(f"Missing required input: {relative}")
    return path


def private_config(text: str) -> str:
    # Runtime editor tooling is not part of these gameplay tests. Disable it
    # only in the copied project; retain renderer/physics and other settings.
    section = ""
    output = []
    for line in text.splitlines():
        if line.startswith("["):
            section = line.strip()
        if section == "[autoload]" and line.strip() and not line.startswith(("[", ";")):
            if line.startswith("MCPRuntimeServer="):
                continue
            raise ValueError("Unrecognized autoload requires an explicit runner input review")
        if section == "[editor_plugins]" and line.startswith("enabled="):
            line = "enabled=PackedStringArray()"
        if section == "[application]" and line.startswith(("config/name=", "config/use_custom_user_dir=", "config/custom_user_dir_name=")):
            continue
        output.append(line)
        if line == "[application]":
            output.extend(['config/name="JustLifeRegression"', 'config/use_custom_user_dir=false'])
    return "\n".join(output) + "\n"


def copy_project(source: Path, destination: Path) -> dict[str, str]:
    manifest = json.loads(safe_source(source, "tests/regression_inputs.json").read_text())
    paths = set(manifest["paths"]) | {"project.godot", "tests/regression_inputs.json", "tests/run_regressions.py"}
    paths |= {f"tests/test_{name}.gd" for name in SUMMARIES}
    paths |= {"tests/blocked_food_setdown.gd", "tests/rejecting_load_controller.gd"}
    paths |= {p + ".uid" for p in list(paths) if p.endswith(".gd") and (source / (p + ".uid")).is_file()}
    hashes = {}
    for relative in sorted(paths):
        src = safe_source(source, relative)
        out = destination / relative
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, out)
        hashes[relative] = digest(src)
    config = destination / "project.godot"
    config.write_text(private_config(config.read_text()))
    return hashes


def environment(group: Path) -> tuple[dict[str, str], Path]:
    env = os.environ.copy()
    for key in ("STAIR_SAVE_CASE", "STAIR_SAVE_STAGE", "ADOPTION_JOURNEY_STAGE"):
        env.pop(key, None)
    for key, folder in (("XDG_DATA_HOME", "xdg-data"), ("XDG_CONFIG_HOME", "xdg-config"),
                        ("XDG_CACHE_HOME", "xdg-cache"), ("JUSTLIFE_DATA_DIR", "data")):
        path = group / folder
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    user = group / "xdg-data/godot/app_userdata/JustLifeRegression"
    for folder in ("stair_save", "stair_motion", "stair_integration", "evidence"):
        (user / "regression" / folder).mkdir(parents=True, exist_ok=True)
    return env, user


def run_process(command: list[str], env: dict[str, str], log: Path, timeout: float, marker: str = "") -> dict:
    started = time.monotonic()
    timed_out = False
    with log.open("w") as stream:
        proc = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = proc.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as exc:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            if isinstance(exc, KeyboardInterrupt):
                raise
            timed_out = True
            code = proc.returncode
    output = log.read_text(errors="replace")
    summaries = [line for line in output.splitlines() if marker and line.startswith(marker + " ")]
    return {"command": command, "pid": proc.pid, "exit_code": code,
            "seconds": round(time.monotonic() - started, 3), "timed_out": timed_out,
            "log": str(log), "summaries": summaries,
            "errors": [line for line in output.splitlines() if ERROR.match(line)],
            "warnings": [line for line in output.splitlines() if "WARNING:" in line],
            "ok": code == 0 and not timed_out and not ERROR.search(output) and (not marker or bool(summaries))}


def verify_fixture(user: Path, name: str, env: dict[str, str]) -> None:
    path = user / name
    if not path.is_file():
        raise ValueError(f"Required producer receipt is missing: {path}")
    data = json.loads(path.read_text())
    slot = data.get("slot", "")
    if not isinstance(slot, str) or not re.fullmatch(r"life_[A-Za-z0-9_]+", slot):
        raise ValueError(f"Producer receipt has no safe named slot: {path}")
    # Covers original user:// saves and the explicit desktop data-root API.
    if not any((root / "saves" / (slot + ".json")).is_file() for root in (user, Path(env["JUSTLIFE_DATA_DIR"]))):
        raise ValueError(f"Producer's named save does not exist in this group: {slot}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--group", action="append", choices=GROUPS, required=True)
    parser.add_argument("--movement-case", action="append", choices=MOVEMENT_CASES)
    parser.add_argument("--food-case", action="append", choices=FOOD_CASES)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, help="New directory outside source; default: retained system temp directory")
    parser.add_argument("--timeout", type=float, default=300, help="Maximum seconds per process")
    parser.add_argument("--render", action="store_true", help="Allow the explicit motion group to open its rendered test window")
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("This runner currently isolates Linux XDG and desktop data roots only; other platforms must not fall back to real user data.")
    if args.timeout <= 0 or args.timeout > 3600:
        parser.error("--timeout must be in (0, 3600]")
    if "motion" in args.group and not args.render:
        parser.error("The motion group captures rendered frames; explicitly pass --render and coordinate window ownership.")
    source = args.source.resolve()
    if args.output:
        output = args.output.resolve()
        if output.is_relative_to(source) or output.exists():
            parser.error("--output must be a new directory outside --source")
        output.mkdir(parents=True)
    else:
        output = Path(tempfile.mkdtemp(prefix="justlife-regression-"))
    print(f"Evidence: {output}", flush=True)
    project = output / "project"
    result = {"source": str(source), "output": str(output), "groups": args.group,
              "scope": "Controlled regression APIs and isolated named-save processes. No pointer UI, full-home or release qualification.",
              "steps": [], "status": "running"}
    receipt = output / "results.json"
    def save() -> None:
        receipt.write_text(json.dumps(result, indent=2) + "\n")
    try:
        hashes = copy_project(source, project)
        result["source_hashes"] = hashes
        result["copied_hashes"] = {name: digest(project / name) for name in hashes}
        save()
        executable = shutil.which(args.godot)
        if not executable:
            raise ValueError(f"Godot executable unavailable: {args.godot}")
        env, _ = environment(output / "import")
        imported = run_process([executable, "--headless", "--path", str(project), "--editor", "--import"], env, output / "import.log", args.timeout)
        result["import"] = imported
        save()
        if not imported["ok"]:
            raise ValueError("Isolated import failed; see import.log")
        for group_name, steps in plan(args.group, args.movement_case or list(MOVEMENT_CASES), args.food_case or list(FOOD_CASES)):
            group = output / "groups" / group_name
            env, user = environment(group)
            for step in steps:
                for fixture in step.requires:
                    verify_fixture(user, fixture, env)
                step_env = env | step.env
                if step.case:
                    step_env["STAIR_SAVE_CASE"] = step.case
                    step_env["STAIR_SAVE_STAGE"] = step.stage
                command = [executable, "--path", str(project)]
                if step.suite != "stair_motion":
                    command.append("--headless")
                command += ["--script", f"res://tests/test_{step.suite}.gd"]
                print(f"Running {group_name}/{step.label}", flush=True)
                record = run_process(command, step_env, group / (step.label + ".log"), args.timeout, SUMMARIES[step.suite])
                record.update({"group": group_name, "suite": step.suite, "stage": step.stage, "case": step.case,
                               "user_data": str(user), "game_data": env["JUSTLIFE_DATA_DIR"]})
                result["steps"].append(record)
                save()
                if not record["ok"]:
                    raise ValueError(f"Failed {step.label}; see {record['log']}")
                for fixture in step.creates:
                    verify_fixture(user, fixture, env)
        changed = [name for name, before in hashes.items() if digest(safe_source(source, name)) != before]
        result["source_changed"] = changed
        copied_changed = [name for name, before in result["copied_hashes"].items() if digest(project / name) != before]
        result["copied_inputs_changed"] = copied_changed
        if changed or copied_changed:
            raise ValueError("Source or copied inputs changed during execution; qualification rejected")
        result["status"] = "passed"
        save()
        print(f"PASS {len(result['steps'])} processes; receipts: {receipt}", flush=True)
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        result.update(status="failed", error=str(exc))
        save()
        print(f"FAIL: {exc}\nEvidence: {receipt}", file=sys.stderr, flush=True)
        return 1
    except KeyboardInterrupt:
        result.update(status="interrupted")
        save()
        return 130

if __name__ == "__main__":
    raise SystemExit(main())
