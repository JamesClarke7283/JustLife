"""Export a desktop release from a private, development-service-free snapshot.

Requires a Godot editor and its matching export templates. Builds retain their
snapshot and logs for inspection and never launch the game or touch player saves.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile


ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {
    "linux": ("Linux", "JustLife.x86_64", "linux_release.x86_64"),
    "windows": ("Windows Desktop", "JustLife.exe", "windows_release_x86_64.exe"),
    "macos": ("macOS", "JustLife.zip", "macos.zip"),
}
SOURCE_FOLDERS = ("assets", "scripts", "scenes", "licenses")
SOURCE_FILES = ("icon.svg", "export_presets.cfg", "README.md", "CREDITS.md")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def template_version(engine_version):
    # Both 4.7.stable.official.<hash> and 4.7.2.stable.official.<hash>.
    match = re.match(r"^(\d+\.\d+(?:\.\d+)?\.[^.\s]+)(?:\.|$)", engine_version)
    if not match:
        raise ValueError(f"Unrecognized Godot version: {engine_version}")
    return match.group(1)


def installed_templates(version):
    if sys.platform == "win32":
        data = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming"))
        return data / "Godot/export_templates" / version
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Godot/export_templates" / version
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return data / "godot/export_templates" / version


def prepare_snapshot(source, snapshot, platform=None):
    def excluded_studies(directory, names):
        relative = Path(directory).relative_to(source)
        if relative == Path("assets/models"):
            return [name for name in names if "_rig" in name or "_grip" in name]
        if relative == Path("assets/audio"):
            return [name for name in names if name == "measurements.json"]
        return []

    snapshot.mkdir()
    for folder in SOURCE_FOLDERS:
        shutil.copytree(source / folder, snapshot / folder, ignore=excluded_studies)
    for name in SOURCE_FILES:
        shutil.copy2(source / name, snapshot / name)

    lines = []
    skip = False
    for line in (source / "project.godot").read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            skip = line in ("[autoload]", "[editor_plugins]", "[mcp_toolkit]")
        if not skip:
            lines.append(line)
    if platform == "macos":
        # Universal macOS exports need Apple Silicon texture imports. Apply
        # this before import, only in the snapshot, preserving editor settings.
        key = "textures/vram_compression/import_etc2_astc"
        section = ""
        updated = []
        for line in lines:
            if line.startswith("["):
                section = line
            if section == "[rendering]" and line.partition("=")[0].strip() == key:
                continue
            updated.append(line)
            if line == "[rendering]":
                updated.append(key + "=true")
        if "[rendering]" not in lines:
            updated.extend(["", "[rendering]", key + "=true"])
        lines = updated
    (snapshot / "project.godot").write_text("\n".join(lines) + "\n", encoding="utf-8")


def set_release_template(preset_text, preset_name, template):
    sections = re.split(r"(?=^\[preset\.\d+(?:\.options)?\]$)", preset_text, flags=re.M)
    preset_id = None
    for section in sections:
        match = re.match(r"\[preset\.(\d+)\]\n", section)
        if match and f'name="{preset_name}"' in section.splitlines():
            preset_id = match.group(1)
            break
    if preset_id is None:
        raise ValueError(f"Missing export preset: {preset_name}")
    for index, section in enumerate(sections):
        if section.startswith(f"[preset.{preset_id}.options]\n"):
            # JSON string quoting is compatible with this Godot String setting.
            setting = "custom_template/release=" + json.dumps(template.as_posix())
            section, count = re.subn(r"^custom_template/release=.*$", lambda _: setting, section, flags=re.M)
            if count != 1:
                raise ValueError(f"Missing custom_template/release in {preset_name}")
            sections[index] = section
            return "".join(sections)
    raise ValueError(f"Missing export options: {preset_name}")


def isolated_environment(work, templates, version):
    env = os.environ.copy()
    for variable, folder in {
        "XDG_DATA_HOME": "data",
        "XDG_CONFIG_HOME": "config",
        "XDG_CACHE_HOME": "cache",
        "APPDATA": "data",
        "LOCALAPPDATA": "local-data",
        "JUSTLIFE_DATA_DIR": "save-data",
    }.items():
        path = work / folder
        path.mkdir(exist_ok=True)
        env[variable] = str(path)
    # Keep standard template lookups available after isolating editor data.
    # The Windows custom template also retains its sibling runtime DLLs.
    engine_folder = "Godot" if sys.platform == "win32" else "godot"
    private_templates = work / "data" / engine_folder / "export_templates" / version
    private_templates.parent.mkdir(parents=True)
    try:
        private_templates.symlink_to(templates, target_is_directory=True)
    except OSError:
        shutil.copytree(templates, private_templates)
    return env


def run_phase(godot, arguments, env, log_path, timeout):
    print(f"{log_path.stem.upper()}_LOG={log_path}", flush=True)
    with log_path.open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(
                [godot, *arguments], env=env, stdout=log,
                stderr=subprocess.STDOUT, timeout=timeout,
            )
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"Build timed out after {timeout}s; inspect {log_path}") from error
    text = log_path.read_text(encoding="utf-8", errors="replace")
    # Godot can emit terminal colors even when redirected. Keep the raw log,
    # but remove CSI/OSC escapes before matching errors or displaying its tail.
    text = re.sub(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[@-_])", "", text)
    if result.returncode or re.search(r"^(?:SCRIPT )?ERROR:", text, flags=re.M):
        print("\n".join(text.splitlines()[-40:]), file=sys.stderr)
        raise RuntimeError(f"Build failed (exit {result.returncode}); inspect {log_path}")


def package_documents(snapshot, package, artifact, platform):
    shutil.copytree(snapshot / "licenses", package / "licenses")
    for name in ("README.md", "CREDITS.md"):
        shutil.copy2(snapshot / name, package / name)
    if platform == "macos":
        # Append alongside the .app without extracting/repacking its executable
        # and framework entries, preserving Godot's Unix permissions/symlinks.
        with zipfile.ZipFile(artifact, "a", compression=zipfile.ZIP_DEFLATED) as archive:
            members = archive.infolist()
            if not any(".app/Contents/MacOS/" in member.filename and member.file_size for member in members):
                raise RuntimeError(f"macOS export contains no application executable: {artifact}")
            for name in ("README.md", "CREDITS.md"):
                archive.write(package / name, name)
            for path in sorted((package / "licenses").rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(package).as_posix())


def run(argv=None, *, default_platform=None, default_output=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=PLATFORMS, default=default_platform, required=default_platform is None)
    parser.add_argument("--source", type=Path, default=ROOT, help="Frozen project source; defaults to this workspace.")
    parser.add_argument("--output", type=Path, default=default_output, help="Package directory; defaults to dist/JustLife-<platform> (dist/JustLife through export_linux.py).")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="Godot editor executable or PATH command.")
    parser.add_argument("--templates", type=Path, help="Directory containing this editor version's extracted export templates.")
    parser.add_argument("--work-dir", type=Path, help="Parent directory for retained snapshots and build logs.")
    parser.add_argument("--timeout", type=int, default=900, help="Maximum seconds for each import/export phase (default: 900).")
    parser.add_argument("--reuse-import-cache", action="store_true", help="Copy the source import cache; use only with a matching Godot version.")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    source = args.source.resolve()
    target = (args.output or ROOT / "dist" / f"JustLife-{args.platform}").resolve()
    for name in (*SOURCE_FOLDERS, *SOURCE_FILES, "project.godot"):
        if not (source / name).exists():
            parser.error(f"Missing release source: {source / name}")
    if target == source or target in source.parents or any(target == source / folder or source / folder in target.parents for folder in SOURCE_FOLDERS):
        parser.error("--output must be separate from the release source files")
    godot = shutil.which(args.godot)
    if not godot:
        parser.error(f"Godot editor not found: {args.godot}")
    engine = subprocess.check_output([godot, "--version"], text=True, timeout=30).strip()
    version = template_version(engine)
    templates = (args.templates or installed_templates(version)).resolve()
    version_file = templates / "version.txt"
    if version_file.is_file() and version_file.read_text(encoding="utf-8").strip() != version:
        parser.error(f"Export templates in {templates} do not match Godot {version}")
    preset_name, artifact_name, template_name = PLATFORMS[args.platform]
    template = templates / template_name
    if not template.is_file():
        parser.error(f"Missing matching Godot {version} export template: {template}")
    if args.work_dir:
        args.work_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="justlife-release-", dir=args.work_dir)).resolve()
    snapshot = work / "project"
    package = work / "package"
    package.mkdir()
    print(f"SNAPSHOT={snapshot}", flush=True)
    prepare_snapshot(source, snapshot, args.platform)
    if args.reuse_import_cache and (source / ".godot/imported").is_dir():
        shutil.copytree(
            source / ".godot/imported", snapshot / ".godot/imported",
            ignore=shutil.ignore_patterns("*_rig*", "*_grip*", "measurements.json-*"),
        )
    preset_path = snapshot / "export_presets.cfg"
    preset_path.write_text(set_release_template(preset_path.read_text(encoding="utf-8"), preset_name, template), encoding="utf-8")
    hashes = {
        path.relative_to(snapshot).as_posix(): sha256(path)
        for folder in ("scripts", "scenes", "assets")
        for path in sorted((snapshot / folder).rglob("*"))
        if path.is_file() and path.suffix != ".import"
    }
    env = isolated_environment(work, templates, version)
    artifact = package / artifact_name
    run_phase(godot, ["--headless", "--editor", "--path", str(snapshot), "--import"], env, work / "import.log", args.timeout)
    run_phase(godot, ["--headless", "--path", str(snapshot), "--export-release", preset_name, str(artifact)], env, work / "export.log", args.timeout)
    if not artifact.is_file() or not artifact.stat().st_size:
        raise RuntimeError(f"Export did not produce {artifact}")
    if args.platform == "linux":
        artifact.chmod(artifact.stat().st_mode | 0o111)
    package_documents(snapshot, package, artifact, args.platform)
    manifest = {
        "built_at_unix": time.time(), "engine": engine, "platform": args.platform,
        "architecture": "universal" if args.platform == "macos" else "x86_64",
        "source": str(source), "snapshot": str(snapshot), "artifact": artifact_name,
        "sha256": sha256(artifact), "source_hashes": hashes,
        "package_hashes": {path.relative_to(package).as_posix(): sha256(path) for path in sorted(package.rglob("*")) if path.is_file()},
    }
    (package / "build_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    # Only completed builds update the destination. Keep existing extra files:
    # the legacy Linux command has always supported refreshing a package folder.
    shutil.copytree(package, target, dirs_exist_ok=True)
    print(f"ARTIFACT={target / artifact_name}")
    if args.platform != "macos":
        print(f"EXECUTABLE={target / artifact_name}")
    print(f"PACKAGE={target}")


if __name__ == "__main__":
    try:
        run()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
