"""Reproduce occupied-furnishing waiting, FIFO, Build and fresh-load checks in private Linux data."""
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
    parser.add_argument('--prepare-only', action='store_true', help='Validate and freeze the private copy without launching Godot.')
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux XDG isolation is required; this runner never uses player data folders.')
    source = args.source.resolve()
    task_tmp = source / 'dist/test-work'
    task_tmp.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='busy-resource-check-', dir=task_tmp))
    project = work / 'justlife-playthrough-busy-resources'
    print('BUSY_RESOURCE_CANDIDATE=' + str(work), flush=True)
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths']) | {
        'project.godot', 'icon.svg', 'tests/regression_inputs.json', 'tests/run_busy_resources.py',
        'tests/test_busy_resources.gd', 'tests/fixtures/busy_bed_approach.json',
        'tests/test_courtesy.gd', 'tests/test_playthrough.gd', 'tests/test_public_twofloor.gd'}
    paths.update(name + '.uid' for name in tuple(paths) if name.endswith('.gd') and (source / (name + '.uid')).is_file())
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    source_inputs = {}
    for name in sorted(paths):
        original = source / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not original.resolve().is_relative_to(source) or not original.is_file():
            raise ValueError('Invalid or missing snapshot input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        source_inputs[name] = digest(original)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', config.read_text(), flags=re.S))
    copied_inputs = {name: digest(project / name) for name in paths}
    env = os.environ.copy()
    env_keys = ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR', 'TMPDIR')
    for key, suffix in zip(env_keys, ('userdata', 'config', 'cache', 'userdata/save_data', 'tmp')):
        env[key] = str(project / suffix)
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    (project / 'evidence').mkdir(parents=True, exist_ok=True)
    save_dir = Path(env['JUSTLIFE_DATA_DIR']) / 'saves'
    save_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(project / 'tests/fixtures/busy_bed_approach.json', save_dir / 'life_1788953596100_30587280.json')
    receipt = {'source': str(source), 'source_inputs': source_inputs, 'copied_inputs': copied_inputs,
               'environment': {key: env[key] for key in env_keys}, 'runs': [], 'prepared_only': args.prepare_only}
    (work / 'run_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if args.prepare_only:
        return 0
    phases = ('import', 'natural_complete', 'fresh', 'explicit', 'fifo', 'fresh_fifo', 'negative',
              'witness_negative', 'build_arrived', 'build_pair', 'build_target')
    for phase in phases:
        evidence = work / 'evidence' / phase
        evidence.mkdir(parents=True)
        command = ['godot', '--path', str(project), '--headless', '--audio-driver', 'Dummy']
        command += ['--editor', '--import', '--quit'] if phase == 'import' else ['--script', 'res://tests/test_busy_resources.gd', '--', '--phase=' + phase]
        saves_before = {f.name: digest(f) for f in save_dir.glob('*.json')}
        indices_before = {f.name: digest(f) for f in (project / 'evidence').glob('*_slots.json')}
        (evidence / 'save_inputs.json').write_text(json.dumps(saves_before, indent=2) + '\n')
        (evidence / 'index_inputs.json').write_text(json.dumps(indices_before, indent=2) + '\n')
        started = time.monotonic()
        error = ''
        try:
            with (evidence / 'run.log').open('w') as log:
                code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=300).returncode
        except subprocess.TimeoutExpired:
            code, error = 124, 'Owned subprocess exceeded 300 seconds and was killed/reaped by subprocess.run.'
        except OSError as exc:
            code, error = 127, str(exc)
        output = (evidence / 'run.log').read_text()
        issues = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|CHECK FAIL).*', output, re.M)
        summary = re.findall(r'^BUSY_RESULT assertions=(\d+) failures=(\d+)$', output, re.M)
        drift = lambda base, pins: [name for name, expected in pins.items() if not (base / name).is_file() or digest(base / name) != expected]
        source_drift = drift(source, source_inputs)
        copy_drift = drift(project, copied_inputs)
        save_drift = drift(save_dir, saves_before)
        index_drift = drift(project / 'evidence', indices_before)
        report_error = ''
        audit = None
        if phase != 'import':
            report = project / 'evidence' / (phase + '.json')
            try:
                audit = json.loads(report.read_text())
                if audit.get('scenario') != phase or audit.get('failures') != [] or len(summary) != 1 or audit.get('assertions') != int(summary[0][0]):
                    report_error = 'Phase report does not match the requested scenario and terminal result.'
                shutil.copy2(report, evidence / report.name)
            except (OSError, ValueError, TypeError) as exc:
                report_error = str(exc)
        ok = code == 0 and not issues and not source_drift and not copy_drift and not save_drift and not index_drift and not report_error and (phase == 'import' or len(summary) == 1 and int(summary[0][0]) > 0 and summary[0][1] == '0')
        record = {'phase': phase, 'command': command, 'exit_code': code, 'error': error,
                  'seconds': time.monotonic() - started, 'issues': issues, 'summary': summary,
                  'source_drift': source_drift, 'copy_drift': copy_drift, 'save_drift': save_drift,
                  'index_drift': index_drift, 'report_error': report_error, 'ok': ok,
                  'log_sha256': digest(evidence / 'run.log')}
        (evidence / 'save_outputs.json').write_text(json.dumps({f.name: digest(f) for f in save_dir.glob('*.json')}, indent=2) + '\n')
        (evidence / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        receipt['runs'].append(record)
        (work / 'run_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(record), flush=True)
        if not ok:
            return 1
        if phase in ('natural_complete', 'fifo'):
            entries = audit.get('saves', [])
            if len(entries) != 1 or not re.fullmatch(r'life_\d+_\d+', str(entries[0].get('slot', ''))) or not (save_dir / (entries[0]['slot'] + '.json')).is_file():
                raise ValueError('Producer did not supply one actual named checkpoint.')
            name = 'natural_slots.json' if phase == 'natural_complete' else 'fifo_slots.json'
            (project / 'evidence' / name).write_text(json.dumps({'saves': [{'slot': entries[0]['slot']}]}, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
