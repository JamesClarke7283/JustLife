"""Drive real Godot engine frames through a durable, isolated 180-day game.

Segments resume the same saved household. Each invocation snapshots the current
production scripts, so a reproduced bug can be fixed and play can continue.
No needs, clocks, money, positions, or action completion states are injected.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--days", type=int, default=180)
    parser.add_argument("--segment-days", type=int, default=30)
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--library-excursion", action="store_true", help="One gated, paused library round trip from day 48 onward; paired checkpoints remain at home.")
    parser.add_argument("--rendering-method", choices=("gl_compatibility", "mobile", "forward_plus"))
    parser.add_argument("--resolution", default="1440x900")
    parser.add_argument("--timeout", type=int, default=21600)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    root = source / "dist/test-work/justlife-playthrough-sustained"
    for record in (root / "sessions").glob("*/process.json"):
        try:
            pid = int(json.loads(record.read_text())["pid"])
            command = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if str(root).encode() in command:
            parser.error(f"Playthrough engine {pid} is still running; checkpoint it before resuming.")
    if root.exists() and not args.resume:
        parser.error("Existing playthrough preserved. Use --resume or move it aside.")
    if args.resume and not (root / "userdata").is_dir():
        parser.error("No saved playthrough to resume.")
    if args.resume:
        journals = list((root / "userdata").rglob("sustained_journal.json"))
        if len(journals) != 1:
            parser.error("No unambiguous checkpoint journal to resume; existing files preserved.")
        try:
            previous = json.loads(journals[0].read_text())
            if not previous.get("checkpoints") or "slot" not in previous["checkpoints"][-1]:
                raise ValueError("No committed checkpoint")
        except (ValueError, KeyError, TypeError) as error:
            parser.error("Invalid checkpoint journal; existing files preserved: " + str(error))
    root.mkdir(parents=True, exist_ok=True)
    for folder in ("scripts", "tests", "scenes"):
        shutil.copytree(source / folder, root / folder, dirs_exist_ok=True)
    if not args.resume:
        shutil.copytree(source / "assets", root / "assets")
        shutil.copytree(source / ".godot/imported", root / ".godot/imported")
        shutil.copy2(source / "icon.svg", root / "icon.svg")
    for metadata in ("uid_cache.bin", "global_script_class_cache.cfg"):
        if (source / ".godot" / metadata).exists():
            shutil.copy2(source / ".godot" / metadata, root / ".godot" / metadata)
    clean, skip = [], False
    for line in (source / "project.godot").read_text().splitlines():
        if line.startswith("["):
            skip = line in ("[autoload]", "[editor_plugins]", "[mcp_toolkit]")
        if not skip:
            clean.append(line)
    (root / "project.godot").write_text("\n".join(clean) + "\n")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    records = root / "sessions" / stamp
    records.mkdir(parents=True)
    (records / "source.json").write_text(json.dumps({
        "command": vars(args), "hashes": {
            str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for directory in ("scripts", "tests") for p in (root / directory).glob("*.gd")
        }}, indent=2))
    env = dict(os.environ, XDG_DATA_HOME=str(root / "userdata"),
               JUSTLIFE_DATA_DIR=str(root / "userdata/save_data"),
               XDG_CONFIG_HOME=str(root / "config"), XDG_CACHE_HOME=str(root / "cache"),
               JUSTLIFE_TOTAL_DAYS=str(args.days), JUSTLIFE_SEGMENT_DAYS=str(args.segment_days),
               JUSTLIFE_SUSTAINED_RESUME="1" if args.resume else "0",
               JUSTLIFE_LIBRARY_EXCURSION="1" if args.library_excursion else "0")
    godot = shutil.which("godot") or "godot"
    if not args.resume:
        with (records / "import.log").open("w") as log:
            result = subprocess.run([godot, "--headless", "--editor", "--path", str(root), "--import"], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        if result.returncode:
            raise SystemExit("Import failed: " + str(records / "import.log"))
    command = [godot, "--path", str(root), "--audio-driver", "Dummy", "--fixed-fps", "15", "--disable-vsync", "--resolution", args.resolution, "--script", "res://tests/test_sustained_play.gd"]
    if args.rendering_method:
        command.extend(["--rendering-method", args.rendering_method])
    if not args.render:
        command.append("--headless")
    print("PLAYTHROUGH=" + str(root), flush=True)
    print("LOG=" + str(records / "game.log"), flush=True)
    (root / "checkpoint.request").unlink(missing_ok=True)
    timed_out = False
    with (records / "game.log").open("w") as log:
        with subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT) as process:
            (records / "process.json").write_text(json.dumps({"pid": process.pid, "command": command}))
            try:
                return_code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                (root / "checkpoint.request").touch()
                try:
                    return_code = process.wait(timeout=60)
                except subprocess.TimeoutExpired:
                    process.kill()
                    return_code = process.wait()
    errors = [line for line in (records / "game.log").read_text().splitlines()
              if line.startswith(("SCRIPT ERROR:", "ERROR:"))]
    code = 124 if timed_out else return_code or (1 if errors else 0)
    result_data = {"exit": code, "timed_out": timed_out, "runtime_errors": errors, "complete": False}
    journals = list((root / "userdata").rglob("sustained_journal.json"))
    if len(journals) == 1:
        journal = json.loads(journals[0].read_text())
        end = journal["checkpoints"][-1]["at"]
        result_data.update(complete=bool(journal.get("complete", False)),
                           elapsed_days=(end - journal["start"]) / 1440,
                           target_days=(journal["target"] - journal["start"]) / 1440)
    (records / "result.json").write_text(json.dumps(result_data, indent=2))
    print("EXIT=" + str(code), flush=True)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
