#!/usr/bin/env python3
"""Drive an isolated Godot pet selection fixture with XTest mouse events via xdotool.

The project must already contain its private test/script snapshot and import
cache. Xvfb may be an extracted local binary; this runner installs no software
and never sends input to the desktop's display.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--xvfb", type=Path, required=True)
    parser.add_argument("--display", default=":98")
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    project = args.project.resolve()
    if args.display in (":0", os.environ.get("DISPLAY")):
        raise SystemExit("Refusing the user's desktop display")
    number = args.display.removeprefix(":").split(".")[0]
    if not number.isdigit() or Path(f"/tmp/.X11-unix/X{number}").exists():
        raise SystemExit("The requested isolated display is already occupied")
    evidence = project / "evidence"
    evidence.mkdir(exist_ok=True)
    for name in ("pointer_request.json", "pointer_reply.json", "result.json"):
        (evidence / name).unlink(missing_ok=True)
    env = dict(os.environ, DISPLAY=args.display,
               JUSTLIFE_DATA_DIR=str(project / "userdata" / "save_data"),
               XDG_DATA_HOME=str(project / "userdata"),
               XDG_CONFIG_HOME=str(project / "config"),
               XDG_CACHE_HOME=str(project / "cache"),
               LIBGL_ALWAYS_SOFTWARE="1", LP_NUM_THREADS="2")
    for name in ("userdata", "config", "cache"):
        (project / name).mkdir(exist_ok=True)
    engine = None
    server = None
    clicks = []
    try:
        with (project / "xvfb.log").open("w") as xlog, (project / "test.log").open("w") as log:
            server = subprocess.Popen([str(args.xvfb.resolve()), args.display,
                                       "-screen", "0", "1440x900x24", "-nolisten", "tcp", "-ac"],
                                      stdout=xlog, stderr=subprocess.STDOUT)
            for _ in range(100):
                if Path(f"/tmp/.X11-unix/X{number}").exists():
                    break
                if server.poll() is not None:
                    raise RuntimeError("Private X server failed")
                time.sleep(.05)
            engine = subprocess.Popen(["godot", "--path", str(project), "--audio-driver", "Dummy",
                                       "--rendering-method", "gl_compatibility", "--disable-vsync",
                                       "--resolution", "960x600", "--fixed-fps", "15",
                                       "--script", "res://tests/test_pet_pointer_interaction.gd"],
                                      env=env, stdout=log, stderr=subprocess.STDOUT)
            print(f"Private display {args.display}, Xvfb PID {server.pid}, Godot PID {engine.pid}", flush=True)
            started = time.monotonic()
            last = 0
            while engine.poll() is None:
                if time.monotonic() - started > args.timeout:
                    raise TimeoutError("Pet native pointer fixture exceeded its bound")
                try:
                    request = json.loads((evidence / "pointer_request.json").read_text())
                except (OSError, json.JSONDecodeError):
                    time.sleep(.04)
                    continue
                if int(request["sequence"]) <= last:
                    time.sleep(.04)
                    continue
                window = subprocess.check_output(["xdotool", "search", "--pid", str(engine.pid)], env=env, timeout=5, text=True).splitlines()[-1]
                subprocess.run(["xdotool", "windowfocus", "--sync", window], env=env, timeout=5, check=True)
                subprocess.run(["xdotool", "mousemove", "--sync", "--window", window,
                                str(request["x"]), str(request["y"])], env=env, timeout=5, check=True)
                time.sleep(.1)
                if request["action"] == "click":
                    subprocess.run(["xdotool", "click", "1"], env=env, timeout=5, check=True)
                pointer = subprocess.check_output(["xdotool", "getmouselocation", "--shell"], env=env, timeout=5, text=True)
                reply = dict(request, ok=True, display=args.display, window=window,
                             engine_pid=engine.pid, pointer=pointer,
                             wall_elapsed=time.monotonic()-started)
                clicks.append(reply)
                temp = evidence / "pointer_reply.tmp"
                temp.write_text(json.dumps(reply))
                temp.replace(evidence / "pointer_reply.json")
                last = int(request["sequence"])
                print(f"XTest {request['action']} #{last}: ({request['x']}, {request['y']})", flush=True)
            result = json.loads((evidence / "result.json").read_text())
            result["driver"] = {"display":args.display, "engine_exit":engine.returncode,
                                "mouse_backend":"xdotool XTest", "events":clicks}
            (evidence / "result.json").write_text(json.dumps(result, indent=2))
            print(f"PET_SELECTION_NATIVE: {result['checks']} checks, {len(result['failures'])} failures; engine exit {engine.returncode}")
            return 0 if engine.returncode == 0 and result["checks"] >= 20 and not result["failures"] and len(clicks) >= 6 else 1
    finally:
        for process in (engine, server):
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
