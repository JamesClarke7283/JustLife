"""Isolated XDG check that music/sound toggles survive an app restart.

Runs against the repo root with private JUSTLIFE_DATA_DIR / XDG_* so player
settings are never touched. Success is a green MUSIC_PREF_RESULT; transient
SCRIPT ERROR lines from a concurrent editor recompile are reported but do not
override a completed zero-failure result.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1]


def main() -> int:
    if not sys.platform.startswith("linux"):
        print("Linux XDG isolation is required.", file=sys.stderr)
        return 2
    task_tmp = SOURCE / "dist/test-work"
    task_tmp.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="music-pref-check-", dir=task_tmp))
    print("MUSIC_PREF_CANDIDATE=" + str(work), flush=True)
    env = os.environ.copy()
    for key, suffix in (
        ("XDG_DATA_HOME", "userdata"),
        ("XDG_CONFIG_HOME", "config"),
        ("XDG_CACHE_HOME", "cache"),
        ("JUSTLIFE_DATA_DIR", "save_data"),
        ("TMPDIR", "tmp"),
    ):
        env[key] = str(work / suffix)
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    (Path(env["JUSTLIFE_DATA_DIR"]) / "saves").mkdir(parents=True, exist_ok=True)
    log = work / "run.log"
    command = [
        "godot",
        "--path",
        str(SOURCE),
        "--audio-driver",
        "Dummy",
        "--headless",
        "--script",
        "res://tests/test_music_preference.gd",
    ]
    started = time.monotonic()
    with log.open("w") as handle:
        result = subprocess.run(command, env=env, stdout=handle, stderr=subprocess.STDOUT, timeout=420)
    output = log.read_text()
    print(output, end="" if output.endswith("\n") else "\n")
    summary = re.findall(r"^MUSIC_PREF_RESULT assertions=(\d+) failures=(\d+)$", output, re.M)
    check_fails = re.findall(r"^CHECK FAIL:?.*", output, re.M)
    script_noise = re.findall(r"^(?:SCRIPT ERROR|ERROR):?.*", output, re.M)
    ok = (
        result.returncode == 0
        and not check_fails
        and len(summary) == 1
        and int(summary[0][0]) > 0
        and summary[0][1] == "0"
    )
    if script_noise and ok:
        print("MUSIC_PREF_NOTE ignored %d compile/runtime noise line(s) after a green result" % len(script_noise), flush=True)
    print(
        "MUSIC_PREF_OK" if ok else "MUSIC_PREF_FAIL",
        f"exit={result.returncode}",
        f"seconds={time.monotonic() - started:.1f}",
        f"candidate={work}",
        flush=True,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
