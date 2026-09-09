"""Check home-sidewalk passing, blocked routes and resident lifecycle in a private Godot project."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('This runner requires Linux XDG isolation.')
    source = args.source.resolve()
    output = args.output.resolve() if args.output else source / 'dist/test-work'
    output.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='pedestrian-check-', dir=output))
    (work / '.gdignore').touch()
    project = work / 'project'
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths'])
    paths.update(['project.godot', 'icon.svg', 'tests/regression_inputs.json',
                  'tests/test_pedestrians.gd', 'tests/test_pedestrian_controls.gd',
                  'tests/run_pedestrian_checks.py'])
    paths.update(name + '.uid' for name in tuple(paths)
                 if name.endswith('.gd') and (source / (name + '.uid')).is_file())
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    original = {}
    for name in sorted(paths):
        path = source / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not path.resolve().is_relative_to(source) or not path.is_file():
            raise ValueError('Invalid source input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        original[name] = sha(path)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', config.read_text(), flags=re.S))
    frozen = {name: sha(project / name) for name in paths}
    env = os.environ.copy()
    isolated = {'XDG_DATA_HOME': 'userdata', 'XDG_CONFIG_HOME': 'config',
                'XDG_CACHE_HOME': 'cache', 'JUSTLIFE_DATA_DIR': 'save_data', 'TMPDIR': 'tmp'}
    for key, folder in isolated.items():
        directory = work / folder
        directory.mkdir()
        env[key] = str(directory)
    phases = [('import', ['--editor', '--import', '--quit'])]
    for case in ['flow1', 'flow3', 'flow8', 'obstacle', 'endpoint', 'legacy']:
        phases.append((case, ['--script', 'res://tests/test_pedestrians.gd', '--', case]))
    for case in ['overlap', 'generation_retry', 'guest_cache']:
        phases.append((case, ['--script', 'res://tests/test_pedestrian_controls.gd', '--', case]))
    runs = []
    print('PEDESTRIAN_CHECK=' + str(work), flush=True)
    for phase, arguments in phases:
        command = ['godot', '--headless', '--audio-driver', 'Dummy', '--path', str(project), *arguments]
        log = work / (phase + '.log')
        started = time.monotonic()
        try:
            with log.open('w') as out:
                code = subprocess.run(command, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=180).returncode
        except subprocess.TimeoutExpired:
            code = 124
        text = log.read_text()
        diagnostics = [line for line in text.splitlines() if re.search(r'ERROR:|WARNING:|leaked|still in use', line)]
        summary = re.findall(r'^PEDESTRIANS(?:_EXTRA)?_RESULT (\d+)/(\d+)$', text, re.M)
        report = work / 'userdata/godot/app_userdata/JustLife' / ('pedestrians_' + phase + '.json')
        facts = json.loads(report.read_text()) if report.is_file() else None
        drift = [name for name, pin in frozen.items() if sha(project / name) != pin]
        source_drift = [name for name, pin in original.items() if sha(source / name) != pin]
        ok = code == 0 and not diagnostics and not drift and not source_drift
        if phase != 'import':
            ok = ok and len(summary) == 1 and int(summary[0][0]) > 0 and int(summary[0][1]) == 0
            ok = ok and facts is not None and facts['checks'] == int(summary[0][0]) and facts['failures'] == 0
        record = {'phase': phase, 'command': command, 'exit_code': code,
                  'seconds': time.monotonic() - started, 'diagnostics': diagnostics,
                  'summary': summary, 'report': facts, 'drift': drift, 'source_drift': source_drift,
                  'log_sha256': sha(log), 'ok': ok}
        runs.append(record)
        receipt = {'source': str(source), 'source_inputs': original, 'project_inputs': frozen,
                   'environment': {key: env[key] for key in isolated}, 'runs': runs}
        (work / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps({'phase': phase, 'ok': ok, 'summary': summary, 'diagnostics': diagnostics}), flush=True)
        if not ok:
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
