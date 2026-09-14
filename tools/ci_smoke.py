"""Validate a desktop package and run a bounded smoke check on its native CI host."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile


HOSTS = {"linux": "linux", "windows": "win32", "macos": "darwin"}


def require_file(path):
    if not path.is_file() or not path.stat().st_size:
        raise RuntimeError(f"Missing or empty package file: {path}")
    return path


def command(arguments, log):
    result = subprocess.run(
        [str(value) for value in arguments], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, errors="replace", timeout=120,
    )
    with log.open("a", encoding="utf-8") as output:
        output.write("$ " + " ".join(str(value) for value in arguments) + "\n" + result.stdout + "\n")
    if result.returncode:
        raise RuntimeError(f"Package validation failed (exit {result.returncode}); inspect {log}")
    return result.stdout


def package_executable(platform, package, work):
    manifest = json.loads(require_file(package / "build_manifest.json").read_text(encoding="utf-8"))
    hashes = manifest.get("package_hashes")
    artifact = {"linux": "JustLife.x86_64", "windows": "JustLife.exe", "macos": "JustLife.zip"}[platform]
    if not isinstance(hashes, dict) or artifact not in hashes:
        raise RuntimeError("Build manifest is missing package hashes or the primary artifact hash")
    for name, expected in hashes.items():
        path = (package / name).resolve()
        if not path.is_relative_to(package):
            raise RuntimeError(f"Build manifest path leaves the package: {name}")
        digest = hashlib.sha256()
        with require_file(path).open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected:
            raise RuntimeError(f"Package checksum mismatch: {name}")
    if platform == "linux":
        executable = require_file(package / "JustLife.x86_64")
    elif platform == "windows":
        # Agility SDK and PIX DLLs are optional; recorded files were checked above.
        executable = require_file(package / "JustLife.exe")
        with executable.open("rb") as stream:
            dos = stream.read(64)
            if len(dos) != 64 or dos[:2] != b"MZ":
                raise RuntimeError("Windows executable has no valid DOS header")
            stream.seek(int.from_bytes(dos[60:64], "little"))
            if stream.read(6) != b"PE\x00\x00\x64\x86":
                raise RuntimeError("Windows executable is not a PE image with x86_64 machine 0x8664")
    else:
        validation_log = work / "validation.log"
        unpacked = work / "unpacked"
        command(["ditto", "-x", "-k", require_file(package / "JustLife.zip"), unpacked], validation_log)
        applications = list(unpacked.glob("*.app"))
        if len(applications) != 1:
            raise RuntimeError("macOS ZIP must contain exactly one top-level application bundle")
        application = applications[0]
        with require_file(application / "Contents/Info.plist").open("rb") as stream:
            executable_name = plistlib.load(stream).get("CFBundleExecutable", "")
        if not executable_name or Path(executable_name).name != executable_name:
            raise RuntimeError("macOS bundle has an invalid CFBundleExecutable")
        executable = require_file(application / "Contents/MacOS" / executable_name)
        architectures = command(["lipo", "-archs", executable], validation_log).split()
        if not {"x86_64", "arm64"}.issubset(architectures):
            raise RuntimeError(f"macOS executable is not universal: {architectures}")
        # Validate integrity, including nested code, without imposing Developer ID trust.
        command(["codesign", "--verify", "--deep", "--strict", "--verbose=2", application], validation_log)
        command(["codesign", "--display", "--verbose=4", application], validation_log)
    if platform != "windows" and not os.access(executable, os.X_OK):
        raise RuntimeError(f"Package executable has lost execute permission: {executable}")
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=HOSTS, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != HOSTS[args.platform]:
        parser.error(f"{args.platform} smoke checks require a native {HOSTS[args.platform]} host")
    # macOS user:// uses the account's Application Support directory. Only a
    # disposable hosted runner may run this check; HOME is never redirected.
    if args.platform == "macos" and (
        os.environ.get("GITHUB_ACTIONS") != "true"
        or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted"
    ):
        parser.error("macOS smoke checks require a disposable GitHub-hosted Actions runner")
    package = args.package.resolve()
    if not package.is_dir():
        parser.error(f"Package directory does not exist: {package}")
    args.work_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="justlife-smoke-", dir=args.work_dir)).resolve()
    print(f"SMOKE_WORK={work}", flush=True)
    executable = package_executable(args.platform, package, work)
    env = os.environ.copy()
    for variable, folder in {
        "XDG_DATA_HOME": "data", "XDG_CONFIG_HOME": "config", "XDG_CACHE_HOME": "cache",
        "APPDATA": "data", "LOCALAPPDATA": "local-data", "JUSTLIFE_DATA_DIR": "saves",
    }.items():
        directory = work / folder
        directory.mkdir(exist_ok=True)
        env[variable] = str(directory)
    log = work / "smoke.log"
    engine_log = work / "engine.log"
    print(f"SMOKE_LOG={log}", flush=True)
    with log.open("w", encoding="utf-8") as output:
        try:
            result = subprocess.run(
                [str(executable), "--headless", "--quit-after", "30", "--log-file", str(engine_log)],
                cwd=work, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=120,
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"Smoke check timed out after 120s; inspect {work}") from error
    text = log.read_text(encoding="utf-8", errors="replace")
    if engine_log.exists():
        text += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    print("\n".join(text.splitlines()[-40:]), flush=True)
    # Godot's known shutdown warnings remain diagnostic; errors fail the check.
    if result.returncode or re.search(r"^\s*(?:SCRIPT )?ERROR:", text, flags=re.M):
        raise RuntimeError(f"Smoke check failed (exit {result.returncode}); inspect {work}")
    print(f"SMOKE_OK={args.platform}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
