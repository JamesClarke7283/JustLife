"""Run resident and travel checks in an isolated project and save directory."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile

TESTS = ('test_residents_validation.gd', 'test_residents.gd', 'test_residents_fresh_load.gd', 'test_residents_queued.gd', 'test_neighborhood.gd')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('This runner requires Linux XDG isolation before importing older saves.')
    source = args.source.resolve()
    work = source / 'dist' / 'test-work'
    work.mkdir(parents=True, exist_ok=True)
    (source / 'dist' / '.gdignore').touch()
    snapshot = Path(tempfile.mkdtemp(prefix='resident-checks-', dir=work))
    for name in ('scripts', 'scenes', 'assets'):
        # Ignore only the heavyweight character rig/grip models; a bare
        # '*_rig*' glob also matched assets/ui/rotate_right.svg.
        ignore = shutil.ignore_patterns('*character_rig*', '*character_grip*', '*_surface_grip*', '*_broad_grip*') if name == 'assets' else None
        shutil.copytree(source / name, snapshot / name, ignore=ignore)
    (snapshot / 'tests').mkdir()
    for name in TESTS:
        shutil.copy2(source / 'tests' / name, snapshot / 'tests' / name)
    lines = []
    skip = False
    for line in (source / 'project.godot').read_text().splitlines():
        if line.startswith('['):
            skip = line in ('[autoload]', '[editor_plugins]', '[mcp_toolkit]')
        if not skip:
            lines.append(line)
    (snapshot / 'project.godot').write_text('\n'.join(lines) + '\n')
    evidence = snapshot / 'evidence'
    evidence.mkdir()
    (evidence / '.gdignore').touch()
    for name in ('userdata', 'save_data', 'tmp'):
        (evidence / name).mkdir()
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(evidence / 'userdata'), JUSTLIFE_DATA_DIR=str(evidence / 'save_data'), TMPDIR=str(evidence / 'tmp'))
    hashes = {str(p.relative_to(snapshot)): hashlib.sha256(p.read_bytes()).hexdigest() for directory in ('scripts', 'scenes', 'assets', 'tests') for p in (snapshot / directory).rglob('*') if p.is_file() and p.suffix != '.import'}
    (evidence / 'source_hashes.json').write_text(json.dumps(hashes, indent=2))
    godot = shutil.which('godot') or 'godot'
    commands = [('import', ['--editor', '--import', '--quit'])]
    for name in TESTS:
        commands.append((Path(name).stem, ['--script', 'res://tests/' + name]))
        if name == 'test_residents_queued.gd':
            commands.append(('test_residents_queued_fresh', ['--script', 'res://tests/' + name, '--', '--consume-absent']))
    results = []
    for phase, arguments in commands:
        log = evidence / (phase + '.log')
        with log.open('w') as output:
            result = subprocess.run([godot, '--headless', '--path', str(snapshot), *arguments], env=env, stdout=output, stderr=subprocess.STDOUT, timeout=240)
        text = log.read_text()
        failed = result.returncode != 0 or 'SCRIPT ERROR:' in text or '\nERROR:' in text
        results.append({'phase': phase, 'exit_code': result.returncode, 'failed': failed, 'warnings': text.count('WARNING:'), 'log': str(log)})
        print(f'{phase}: {"FAIL" if failed else "PASS"} ({text.count("WARNING:")} warnings)', flush=True)
        if failed:
            break
    changed = [name for name, digest in hashes.items() if not (snapshot / name).exists() or hashlib.sha256((snapshot / name).read_bytes()).hexdigest() != digest]
    (evidence / 'results.json').write_text(json.dumps({'snapshot': str(snapshot), 'phases': results, 'changed_inputs': changed}, indent=2))
    print('EVIDENCE=' + str(evidence), flush=True)
    return 1 if changed or len(results) != len(commands) or any(r['failed'] for r in results) else 0

if __name__ == '__main__':
    raise SystemExit(main())
