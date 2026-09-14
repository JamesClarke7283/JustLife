#!/usr/bin/env python3
"""Install checksum-pinned release tools on an Ubuntu x86_64 CI runner."""

import argparse
import hashlib
import os
from pathlib import Path
import time
import urllib.error
import urllib.request
import zipfile


GODOT_VERSION = "4.7.2"
BUTLER_VERSION = "15.31.0"
DOWNLOADS = {
    "editor": (
        f"https://github.com/godotengine/godot/releases/download/{GODOT_VERSION}-stable/"
        f"Godot_v{GODOT_VERSION}-stable_linux.x86_64.zip",
        "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4",
    ),
    "templates": (
        f"https://github.com/godotengine/godot/releases/download/{GODOT_VERSION}-stable/"
        f"Godot_v{GODOT_VERSION}-stable_export_templates.tpz",
        "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011",
    ),
    "butler": (
        f"https://github.com/itchio/butler/releases/download/v{BUTLER_VERSION}/butler-linux-amd64.zip",
        "1e536377187894ef5fe7f35edfb29df256df63e50e7f6b97ebd54bc5aba4c055",
    ),
}


def install_archive(name: str, destination: Path) -> Path:
    url, expected_hash = DOWNLOADS[name]
    archive = destination / f"{name}.zip"
    print(f"Downloading {url}", flush=True)
    for attempt in range(3):
        digest = hashlib.sha256()
        try:
            with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    digest.update(chunk)
                    output.write(chunk)
            break
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 2:
                raise
            print(f"Download interrupted; retrying {name}", flush=True)
            time.sleep(5 * (attempt + 1))
    if digest.hexdigest() != expected_hash:
        archive.unlink()
        raise RuntimeError(f"Checksum mismatch for {name}; refusing to extract or run it")
    extracted = destination / name
    extracted.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            if not (extracted / entry.filename).resolve().is_relative_to(extracted.resolve()):
                raise RuntimeError(f"Unsafe archive entry: {entry.filename}")
        package.extractall(extracted)
    archive.unlink()
    print(f"Verified SHA-256 for {name}", flush=True)
    return extracted


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=("godot", "butler"))
    parser.add_argument("--directory", required=True, type=Path)
    args = parser.parse_args()
    destination = args.directory.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    outputs = {}
    if args.tool == "godot":
        editor = install_archive("editor", destination)
        executable = editor / f"Godot_v{GODOT_VERSION}-stable_linux.x86_64"
        executable.chmod(0o755)
        templates = install_archive("templates", destination) / "templates"
        version = (templates / "version.txt").read_text().strip()
        if version != f"{GODOT_VERSION}.stable":
            raise RuntimeError(f"Unexpected export template version: {version}")
        outputs = {"godot": executable, "templates": templates}
    else:
        directory = install_archive("butler", destination) / "linux-amd64"
        executable = directory / "butler"
        executable.chmod(0o755)
        outputs = {"butler": executable}
    for name, path in outputs.items():
        if not path.exists():
            raise RuntimeError(f"Missing installed {name}: {path}")
        print(f"{name}={path}")
    if output_file := os.environ.get("GITHUB_OUTPUT"):
        with open(output_file, "a", encoding="utf-8") as output:
            for name, path in outputs.items():
                output.write(f"{name}={path}\n")


if __name__ == "__main__":
    main()
