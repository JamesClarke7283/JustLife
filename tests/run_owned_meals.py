"""Run the earned owned-portion approach, fresh saves, and autonomy controls in private Linux data."""
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
    work = Path(tempfile.mkdtemp(prefix='owned-meal-check-', dir=task_tmp))
    print('OWNED_MEAL_CANDIDATE=' + str(work), flush=True)
    project = work / 'justlife-playthrough-owned-meal'
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths']) | {
        'project.godot', 'icon.svg', 'tests/regression_inputs.json', 'tests/run_owned_meals.py',
        'tests/test_owned_meal.gd', 'tests/test_owned_meal_controls.gd', 'tests/fixtures/owned_meal_approach.json',
        'tests/test_courtesy.gd', 'tests/test_playthrough.gd', 'tests/test_public_twofloor.gd',
        'tests/test_meal_autonomy.gd', 'tests/test_autonomy_policy.gd'}
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
    env_keys = ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR', 'TMPDIR')
    for key, suffix in zip(env_keys, ('userdata', 'config', 'cache', 'userdata/save_data', 'tmp')):
        env[key] = str(project / suffix)
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    save_dir = Path(env['JUSTLIFE_DATA_DIR']) / 'saves'
    save_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(project / 'tests/fixtures/owned_meal_approach.json', save_dir / 'life_1788951101795_688290719.json')
    (project / 'evidence').mkdir(parents=True, exist_ok=True)
    runs = []
    for phase, script in [('import', None), ('natural', 'test_owned_meal.gd'), ('fresh', 'test_owned_meal.gd'),
                          ('components', 'test_owned_meal_controls.gd'), ('policy', 'test_autonomy_policy.gd')]:
        evidence = work / 'evidence' / phase
        evidence.mkdir(parents=True)
        command = ['godot', '--path', str(project), '--headless', '--audio-driver', 'Dummy']
        command += ['--editor', '--import', '--quit'] if script is None else ['--script', 'res://tests/' + script, '--', '--phase=' + phase]
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
        summary = re.findall(r'^(?:OWNED_MEAL_RESULT|OWNED_CONTROLS_RESULT) assertions=(\d+) failures=(\d+)$', output, re.M)
        if phase == 'policy':
            summary = re.findall(r'^AUTONOMY_POLICY (\d+) checks, (\d+) failures$', output, re.M)
        drift = [name for name, expected in frozen.items() if not (project / name).is_file() or digest(project / name) != expected]
        source_drift = [name for name, expected in source_hashes.items() if not (source / name).is_file() or digest(source / name) != expected]
        changed_saves = [name for name, expected in save_inputs.items() if not (save_dir / name).is_file() or digest(save_dir / name) != expected]
        ok = code == 0 and not problems and not drift and not source_drift and not changed_saves and (script is None or (len(summary) == 1 and int(summary[0][0]) > 0 and summary[0][1] == '0'))
        report_name = ('components' if phase == 'components' else phase) + '.json'
        report = project / 'evidence' / report_name
        report_ok = phase in ('import', 'policy')
        if report.is_file():
            shutil.copy2(report, evidence / report_name)
            parsed = json.loads(report.read_text())
            report_ok = len(summary) == 1 and parsed.get('assertions') == int(summary[0][0]) and parsed.get('failures') == []
        ok = ok and report_ok
        save_outputs = {path.name: digest(path) for path in save_dir.glob('*.json')}
        (evidence / 'save_outputs.json').write_text(json.dumps(save_outputs, indent=2) + '\n')
        record = {'phase': phase, 'command': command, 'exit_code': code, 'error': error,
                  'elapsed_seconds': time.monotonic() - started, 'problems': problems,
                  'summary': summary, 'drift': drift, 'source_drift': source_drift,
                  'report_ok': report_ok, 'changed_existing_saves': changed_saves,
                  'ok': ok, 'log_sha256': digest(evidence / 'run.log')}
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
