"""Run the invited-neighbor lifecycle in a retained Linux snapshot; --capture adds actual UI images."""
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

TESTS = ('test_home_visit.gd', 'test_home_visit_fresh.gd', 'test_home_visit_controls.gd',
         'test_home_visit_departure_fresh.gd', 'test_home_visit_custody.gd', 'test_home_visit_render.gd')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux XDG isolation is required; this runner never uses player data folders.')
    source = args.source.resolve()
    task_tmp = source / 'dist/test-work'
    task_tmp.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='home-visit-check-', dir=task_tmp))
    print('HOME_VISIT_CANDIDATE=' + str(work), flush=True)
    project = work / 'project'
    manifest = json.loads((source / 'tests/regression_inputs.json').read_text())
    paths = set(manifest['paths']) | {'project.godot', 'icon.svg', 'tests/regression_inputs.json', 'tests/run_home_visits.py'}
    paths.update('tests/' + name for name in TESTS)
    paths.update(name + '.uid' for name in tuple(paths) if name.endswith('.gd') and (source / (name + '.uid')).is_file())
    source_hashes = {}
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
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
    env.update(XDG_DATA_HOME=str(work / 'userdata'), XDG_CONFIG_HOME=str(work / 'config'),
               XDG_CACHE_HOME=str(work / 'cache'), JUSTLIFE_DATA_DIR=str(work / 'save_data'), TMPDIR=str(task_tmp))
    for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR'):
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    phases = [('import', None, [])]
    for phase, test, extra in [
        ('legacy', 'test_home_visit.gd', []),
        ('legacy_fresh', 'test_home_visit_fresh.gd', []),
        ('controls', 'test_home_visit_controls.gd', []),
        ('departure_fresh', 'test_home_visit_departure_fresh.gd', []),
        ('cooking', 'test_home_visit_custody.gd', []),
        ('canonical', 'test_home_visit.gd', ['--', '--canonical-fixture']),
        ('canonical_fresh', 'test_home_visit_fresh.gd', ['--', '--greeting-only']),
    ]:
        phases.append((phase, test, extra))
    if args.capture:
        phases.append(('render', 'test_home_visit_render.gd', []))
    runs = []
    reports = work / 'userdata/godot/app_userdata/JustLife'
    for phase, test, extra in phases:
        evidence = work / 'evidence' / phase
        evidence.mkdir(parents=True)
        command = ['godot', '--path', str(project), '--audio-driver', 'Dummy']
        if phase == 'render':
            command += ['--resolution', '1440x900']
        else:
            command += ['--headless']
        command += ['--editor', '--import', '--quit'] if test is None else ['--script', 'res://tests/' + test, *extra]
        started = time.monotonic()
        error = ''
        try:
            with (evidence / 'run.log').open('w') as log:
                result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
            error = 'Owned subprocess timed out after 240 seconds; subprocess.run killed and reaped it.'
        except OSError as exc:
            code = 127
            error = str(exc)
        output = (evidence / 'run.log').read_text()
        problems = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|CHECK FAIL):?.*', output, re.M)
        summary = re.findall(r'^HOME_VISIT (\d+)/(\d+)$', output, re.M)
        drift = [name for name, expected in frozen.items() if digest(project / name) != expected]
        ok = code == 0 and not problems and not drift and (test is None or (len(summary) == 1 and int(summary[0][0]) > 0 and summary[0][1] == '0'))
        for name in ('home_visit_result.json', 'home_visit_slots.json', 'home_visit_departure_slot.json'):
            if (reports / name).is_file():
                shutil.copy2(reports / name, evidence / name)
        if phase == 'render' and (reports / 'home_visit').is_dir():
            shutil.copytree(reports / 'home_visit', evidence / 'images')
        record = {'phase': phase, 'command': command, 'exit_code': code, 'error': error,
                  'elapsed_seconds': time.monotonic() - started, 'problems': problems,
                  'summary': summary, 'drift': drift, 'ok': ok, 'log_sha256': digest(evidence / 'run.log')}
        runs.append(record)
        (evidence / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        (work / 'run_receipt.json').write_text(json.dumps({'source': str(source), 'source_inputs': source_hashes,
            'frozen_inputs': frozen, 'environment': {key: env[key] for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR', 'TMPDIR')}, 'runs': runs}, indent=2) + '\n')
        print(record, flush=True)
        if not ok:
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
