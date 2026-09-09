"""Run genuine current-floor passage, phase saves and bounded ownership controls privately."""
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

SEED = 'life_1788975081557_584989380'
FIXTURE = 'tests/fixtures/current_floor_passage.json'
STAGES = (
    ('natural', 'test_current_floor', None),
    ('produce_retreat', 'test_current_floor_phases', None),
    ('fresh_retreat', 'test_current_floor_phases', 'produce_retreat'),
    ('produce_hold', 'test_current_floor_phases', None),
    ('fresh_hold', 'test_current_floor_phases', 'produce_hold'),
    ('controls', 'test_current_floor_controls', 'produce_hold'),
    ('build', 'test_current_floor_build', 'produce_hold'),
    ('mutations', 'test_current_floor_build', 'produce_hold'),
)
HELPERS = {'test_activity_flow', 'test_busy_resources', 'test_courtesy',
           'test_public_twofloor', 'test_playthrough'}
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux private XDG isolation is required.')
    source = args.source.resolve()
    parent = source / 'dist/test-work'
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='current-floor-check-', dir=parent))
    project = work / 'justlife-playthrough-current-floor'
    print('CURRENT_FLOOR_CANDIDATE=' + str(work), flush=True)
    scripts = {row[1] for row in STAGES} | HELPERS
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths'])
    paths |= {'project.godot', 'icon.svg', 'tests/regression_inputs.json', FIXTURE, 'tests/run_current_floor.py'}
    paths |= {'tests/' + name + '.gd' for name in scripts}
    paths |= {name + '.uid' for name in tuple(paths) if name.endswith('.gd') and (source / (name + '.uid')).is_file()}
    source_pins = {}
    for name in sorted(paths):
        original = source / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not original.resolve().is_relative_to(source) or not original.is_file():
            raise ValueError('Invalid or missing input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        source_pins[name] = sha(original)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', config.read_text(), flags=re.S))
    copy_pins = {name: sha(project / name) for name in paths}
    env = os.environ.copy()
    keys = ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR', 'TMPDIR')
    for key, suffix in zip(keys, ('userdata', 'config', 'cache', 'userdata/save_data', 'tmp')):
        env[key] = str(project / suffix)
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    save_dir = Path(env['JUSTLIFE_DATA_DIR']) / 'saves'
    save_dir.mkdir()
    evidence_dir = project / 'evidence'
    evidence_dir.mkdir()
    (Path(env['JUSTLIFE_DATA_DIR']) / 'save_import.json').write_text(json.dumps({'complete': True, 'entries': [], 'ok': True, 'version': 1}) + '\n')
    receipt = {'source': str(source), 'source_inputs': source_pins, 'copied_inputs': copy_pins,
               'environment': {k: env[k] for k in keys}, 'runs': [], 'timing_scope': 'Functional bounds; no performance claim.'}
    producers = {}
    for phase, script, producer in (('import', '', None),) + STAGES:
        evidence = work / 'evidence' / phase
        evidence.mkdir(parents=True)
        command = ['godot', '--path', str(project), '--headless', '--audio-driver', 'Dummy']
        report_path = evidence_dir / (phase + '.json')
        if phase == 'import':
            command += ['--editor', '--import', '--quit']
        else:
            command += ['--script', 'res://tests/' + script + '.gd', '--', '--phase=' + phase]
            # Only agent-owned staged copies are removed; originals and generated files
            # are independently archived under work/evidence before the next phase.
            for old in save_dir.glob('*.json'):
                old.unlink()
            if producer is None:
                required, slot = source / FIXTURE, SEED
            else:
                prior = producers[producer]
                required, slot = prior['path'], prior['slot']
                (evidence_dir / 'contract.json').write_text(json.dumps({'slot': slot, 'phase': prior['phase'], 'save_sha256': sha(required)}, indent=2) + '\n')
            shutil.copy2(required, save_dir / (slot + '.json'))
            shutil.copy2(source / FIXTURE, evidence_dir / 'original_slot.json')
            (evidence_dir / 'test_phase.txt').write_text(phase)
            if report_path.exists():
                shutil.copy2(report_path, evidence / 'prior_report.json')
                report_path.unlink()
        save_pins = {p.name: sha(p) for p in save_dir.glob('*.json')}
        runtime_pins = {p.name: sha(p) for p in evidence_dir.glob('*') if p.is_file() and p.name in {'contract.json', 'test_phase.txt', 'original_slot.json'}}
        (evidence / 'inputs.json').write_text(json.dumps({'saves': save_pins, 'evidence': runtime_pins}, indent=2) + '\n')
        started = time.monotonic()
        with (evidence / 'run.log').open('w') as output:
            child = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT)
            active = {'phase': phase, 'pid': child.pid, 'command': command}
            (work / 'ACTIVE.json').write_text(json.dumps(active, indent=2) + '\n')
            print('ACTIVE ' + json.dumps(active), flush=True)
            try:
                code = child.wait(timeout=240)
            except subprocess.TimeoutExpired:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait()
                code = 124
        raw = (evidence / 'run.log').read_text()
        issues = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|CHECK FAIL).*', raw, re.M)
        issues += re.findall(r'^.*(?:ObjectDB instances leaked|resources still in use).*$', raw, re.M)
        summary = re.findall(r'^CURRENT_FLOOR_RESULT assertions=(\d+) failures=(\d+) phase=(\w+)$', raw, re.M)
        drift = lambda base, pins: [name for name, h in pins.items() if not (base / name).is_file() or sha(base / name) != h]
        changed = {'source': drift(source, source_pins), 'copy': drift(project, copy_pins),
                   'saves': drift(save_dir, save_pins), 'evidence': drift(evidence_dir, runtime_pins)}
        report_error = ''
        if phase != 'import':
            try:
                data = json.loads(report_path.read_text())
                if type(data.get('assertions')) is not int or not isinstance(data.get('failures'), list) or summary != [(str(data['assertions']), str(len(data['failures'])), phase)] or data.get('phase') != phase:
                    raise ValueError('Actual report disagrees with terminal count, failures or requested phase.')
                shutil.copy2(report_path, evidence / 'report.json')
                event_path = evidence_dir / (phase + '_events.jsonl')
                if event_path.is_file():
                    shutil.copy2(event_path, evidence / event_path.name)
                if phase.startswith('produce_'):
                    natural_path = work / 'evidence/natural/report.json'
                    natural = json.loads(natural_path.read_text())
                    count = 6 if phase.endswith('retreat') else 18
                    exact = len(data['rows']) == count and data['rows'] == natural['rows'][:count]
                    (evidence / 'prefix.json').write_text(json.dumps({'natural_sha256': sha(natural_path), 'producer_sha256': sha(report_path), 'rows': count, 'exact_prefix': exact}, indent=2) + '\n')
                    if not exact:
                        raise ValueError('Actual producer differs from its complete natural prefix.')
                    slot = data['saved']['slot']
                    if not re.fullmatch(r'life_[0-9]+_[0-9]+', slot) or slot == SEED or slot + '.json' in save_pins:
                        raise ValueError('Producer did not create a distinct actual named slot.')
                    actual = save_dir / (slot + '.json')
                    archived = evidence / 'actual_slot.json'
                    shutil.copy2(actual, archived)
                    producers[phase] = {'slot': slot, 'phase': data['saved']['phase'], 'path': archived}
                if phase.startswith('fresh_') and (len(data['rows']) > 200 or data['at'] >= data['deadline']):
                    raise ValueError('Fresh passage exceeds its original saved deadline/call cap.')
                if phase == 'natural' and len(data['stair_continuation']['rows']) > 400:
                    raise ValueError('Original-stair continuation exceeds its declared cap.')
            except (OSError, ValueError, TypeError, KeyError) as exc:
                report_error = str(exc)
        ok = code == 0 and not issues and not any(changed.values()) and not report_error and (phase == 'import' or len(summary) == 1 and summary[0][1] == '0')
        record = {'phase': phase, 'exit_code': code, 'seconds': time.monotonic() - started,
                  'issues': issues, 'summary': summary, 'drift': changed, 'report_error': report_error,
                  'log_sha256': sha(evidence / 'run.log'), 'ok': ok}
        (evidence / 'save_outputs.json').write_text(json.dumps({p.name: sha(p) for p in save_dir.glob('*.json')}, indent=2) + '\n')
        receipt['runs'].append(record)
        (evidence / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        (work / 'run_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(record), flush=True)
        if not ok:
            return 1
    print('CURRENT_FLOOR_WRAPPER all8 phases passed.', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
