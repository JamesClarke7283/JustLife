"""Run household courtesy movement and fresh-save controls in a retained private Linux snapshot."""
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
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux XDG isolation is required; this runner never uses player data folders.')
    source = args.source.resolve()
    task_tmp = source / 'dist/test-work'
    task_tmp.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='courtesy-check-', dir=task_tmp))
    print('COURTESY_CANDIDATE=' + str(work), flush=True)
    project = work / 'justlife-playthrough-courtesy'
    manifest = json.loads((source / 'tests/regression_inputs.json').read_text())
    paths = set(manifest['paths']) | {'project.godot', 'icon.svg', 'tests/regression_inputs.json',
        'tests/run_courtesy.py', 'tests/test_courtesy.gd', 'tests/fixtures/courtesy_first_crowd.json',
        'tests/test_playthrough.gd', 'tests/test_public_twofloor.gd'}
    paths.update(name + '.uid' for name in tuple(paths) if name.endswith('.gd') and (source / (name + '.uid')).is_file())
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    source_hashes = {}
    for name in sorted(paths):
        path = source / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not path.resolve().is_relative_to(source) or not path.is_file():
            raise ValueError('Invalid or missing snapshot input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        source_hashes[name] = digest(path)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', config.read_text(), flags=re.S))
    frozen = {name: digest(project / name) for name in paths}
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(project / 'userdata'), XDG_CONFIG_HOME=str(project / 'config'),
               XDG_CACHE_HOME=str(project / 'cache'), JUSTLIFE_DATA_DIR=str(project / 'userdata/save_data'), TMPDIR=str(project / 'tmp'))
    env_keys = ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR', 'TMPDIR')
    for key in env_keys:
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    save_dir = Path(env['JUSTLIFE_DATA_DIR']) / 'saves'
    save_dir.mkdir(parents=True, exist_ok=True)
    fixture = project / 'tests/fixtures/courtesy_first_crowd.json'
    original_slot = save_dir / 'life_1788942682044_57282849.json'
    shutil.copy2(fixture, original_slot)
    runs = []
    for phase, extra in [('import', None), ('natural_no_save', ['--no-phase-saves']), ('natural', []), ('fresh', []), ('controls', []), ('waiter_producer', []), ('waiter_fresh', [])]:
        evidence = work / 'evidence' / phase
        evidence.mkdir(parents=True)
        command = ['godot', '--path', str(project), '--audio-driver', 'Dummy', '--headless']
        command += ['--editor', '--import', '--quit'] if extra is None else ['--script', 'res://tests/test_courtesy.gd', '--', '--courtesy-phase=' + phase, *extra]
        save_inputs = {path.name: digest(path) for path in save_dir.glob('*.json')}
        (evidence / 'save_inputs.json').write_text(json.dumps(save_inputs, indent=2) + '\n')
        started = time.monotonic()
        error = ''
        try:
            with (evidence / 'run.log').open('w') as log:
                result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=300)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
            error = 'Owned subprocess timed out after 300 seconds; subprocess.run killed and reaped it.'
        except OSError as exc:
            code = 127
            error = str(exc)
        output = (evidence / 'run.log').read_text()
        problems = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|CHECK FAIL):?.*', output, re.M)
        summary = re.findall(r'^COURTESY_RESULT assertions=(\d+) failures=(\d+)$', output, re.M)
        drift = [name for name, expected in frozen.items() if digest(project / name) != expected]
        ok = code == 0 and not problems and not drift and (extra is None or (len(summary) == 1 and int(summary[0][0]) > 0 and summary[0][1] == '0'))
        if extra is not None and (project / 'evidence' / (phase + '.json')).is_file():
            shutil.copy2(project / 'evidence' / (phase + '.json'), evidence / (phase + '.json'))
        changed_saves = [name for name, expected in save_inputs.items() if not (save_dir / name).is_file() or digest(save_dir / name) != expected]
        save_outputs = {path.name: digest(path) for path in save_dir.glob('*.json')}
        (evidence / 'save_outputs.json').write_text(json.dumps(save_outputs, indent=2) + '\n')
        ok = ok and not changed_saves
        record = {'phase': phase, 'command': command, 'exit_code': code, 'error': error,
                  'elapsed_seconds': time.monotonic() - started, 'problems': problems,
                  'summary': summary, 'drift': drift, 'changed_existing_saves': changed_saves, 'ok': ok, 'log_sha256': digest(evidence / 'run.log')}
        runs.append(record)
        (evidence / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        (work / 'run_receipt.json').write_text(json.dumps({'source': str(source), 'source_inputs': source_hashes,
            'frozen_inputs': frozen, 'environment': {key: env[key] for key in env_keys}, 'runs': runs}, indent=2) + '\n')
        print(record, flush=True)
        if not ok:
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
