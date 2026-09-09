"""Run occupied-activity recovery, bounded retry controls and actual Save/fresh checks privately."""
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

STAGES = (
    ('natural', 'test_activity_flow', 'natural'),
    ('admission', 'test_activity_admission', 'checks'),
    ('replan_components', 'test_activity_replans', 'components'),
    ('replan_live', 'test_activity_replans', 'live'),
    ('observation_producer', 'test_activity_observation', 'produce'),
    ('observation_fresh', 'test_activity_observation', 'fresh'),
)
SEED = 'life_1788966286736_90579531'
FIXTURE = 'tests/fixtures/activity_owner_occupied.json'
SCRIPTS = {row[1] for row in STAGES} | {
    'test_busy_resources', 'test_courtesy', 'test_public_twofloor', 'test_playthrough',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux XDG isolation is required; this runner never uses player data.')
    source = args.source.resolve()
    temporary = source / 'dist/test-work'
    temporary.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='activity-flow-check-', dir=temporary))
    project = work / 'justlife-playthrough-activity-flow'
    print('ACTIVITY_FLOW_CANDIDATE=' + str(work), flush=True)
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths'])
    paths.update({'project.godot', 'icon.svg', 'tests/regression_inputs.json',
                  'tests/run_activity_flow.py', FIXTURE})
    paths.update('tests/' + name + '.gd' for name in SCRIPTS)
    paths.update(name + '.uid' for name in tuple(paths)
                 if name.endswith('.gd') and (source / (name + '.uid')).is_file())
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    source_inputs = {}
    for name in sorted(paths):
        original = source / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not original.resolve().is_relative_to(source) or not original.is_file():
            raise ValueError('Invalid or missing private snapshot input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        source_inputs[name] = sha(original)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', config.read_text(), flags=re.S))
    copied_inputs = {name: sha(project / name) for name in paths}
    env = os.environ.copy()
    env_keys = ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR', 'TMPDIR')
    for key, suffix in zip(env_keys, ('userdata', 'config', 'cache', 'userdata/save_data', 'tmp')):
        env[key] = str(project / suffix)
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    save_dir = Path(env['JUSTLIFE_DATA_DIR']) / 'saves'
    save_dir.mkdir(parents=True, exist_ok=True)
    (project / 'evidence').mkdir()
    shutil.copy2(project / FIXTURE, save_dir / (SEED + '.json'))
    receipt = {'source': str(source), 'source_inputs': source_inputs, 'copied_inputs': copied_inputs,
               'environment': {key: env[key] for key in env_keys}, 'runs': [],
               'timing_scope': 'Bounded functional checks; elapsed seconds are not a performance benchmark.'}
    observed_slot = ''
    for stage, script, phase in (('import', '', ''),) + STAGES:
        evidence = work / 'evidence' / stage
        evidence.mkdir(parents=True)
        command = ['godot', '--path', str(project), '--headless', '--audio-driver', 'Dummy']
        command += ['--editor', '--import', '--quit'] if stage == 'import' else ['--script', 'res://tests/' + script + '.gd', '--', '--phase=' + phase]
        if stage == 'observation_fresh':
            if not re.fullmatch(r'life_[0-9]+_[0-9]+', observed_slot) or observed_slot == SEED:
                raise ValueError('A validated actual producer slot is required for fresh continuation.')
            command.append('--slot=' + observed_slot)
        report_path = project / 'evidence' / (phase + '.json')
        if stage != 'import' and report_path.exists():
            shutil.copy2(report_path, evidence / 'prior_report.json')
            report_path.unlink()
        save_inputs = {p.name: sha(p) for p in save_dir.glob('*.json')}
        (evidence / 'save_inputs.json').write_text(json.dumps(save_inputs, indent=2) + '\n')
        started = time.monotonic()
        error = ''
        try:
            with (evidence / 'run.log').open('w') as log:
                code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
        except subprocess.TimeoutExpired:
            code, error = 124, 'Owned subprocess exceeded180 seconds and was killed/reaped.'
        except OSError as exc:
            code, error = 127, str(exc)
        output = (evidence / 'run.log').read_text()
        issues = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|CHECK FAIL).*', output, re.M)
        issues += re.findall(r'^.*(?:ObjectDB instances leaked|resources still in use).*$', output, re.M)
        summary = re.findall(r'^BUSY_RESULT assertions=(\d+) failures=(\d+)$', output, re.M)
        drift = lambda base, pins: [name for name, expected in pins.items() if not (base / name).is_file() or sha(base / name) != expected]
        source_drift = drift(source, source_inputs)
        copy_drift = drift(project, copied_inputs)
        save_drift = drift(save_dir, save_inputs)
        report_error = ''
        report = None
        if stage != 'import':
            try:
                report = json.loads(report_path.read_text())
                if report.get('scenario') != phase or report.get('failures') != [] or len(summary) != 1 or type(report.get('assertions')) is not int or report['assertions'] != int(summary[0][0]):
                    report_error = 'Requested phase report disagrees with its terminal result.'
                shutil.copy2(report_path, evidence / 'report.json')
                if stage == 'observation_producer' and not report_error:
                    natural_path = project / 'evidence/natural.json'
                    natural = json.loads(natural_path.read_text())
                    prefix_exact = report.get('initial') == natural.get('initial') and report.get('steps') == natural.get('steps', [])[:107]
                    (evidence / 'prefix.json').write_text(json.dumps({
                        'natural_report_sha256': sha(natural_path),
                        'producer_report_sha256': sha(report_path),
                        'complete_initial_and107_rows_exact': prefix_exact,
                    }, indent=2) + '\n')
                    if not prefix_exact:
                        report_error = "Producer differs from this run's complete natural107-row prefix."
                    saves = report.get('saves', [])
                    if len(saves) != 1 or len(report.get('steps', [])) != 107:
                        report_error = 'Producer did not save its single actual107-row observation.'
                    else:
                        observed_slot = saves[0].get('slot', '')
                        if not re.fullmatch(r'life_[0-9]+_[0-9]+', observed_slot) or observed_slot == SEED or not (save_dir / (observed_slot + '.json')).is_file():
                            report_error = 'Producer returned an invalid actual named slot.'
                        else:
                            shutil.copy2(save_dir / (observed_slot + '.json'), evidence / 'actual_observation_slot.json')
                if stage == 'observation_fresh' and len(report.get('steps', [])) > 493:
                    report_error = 'Fresh continuation exceeds the original remaining493-call budget.'
            except (OSError, ValueError, TypeError, KeyError) as exc:
                report_error = str(exc)
        ok = code == 0 and not issues and not source_drift and not copy_drift and not save_drift and not report_error and (stage == 'import' or len(summary) == 1 and int(summary[0][0]) > 0 and summary[0][1] == '0')
        save_outputs = {p.name: sha(p) for p in save_dir.glob('*.json')}
        (evidence / 'save_outputs.json').write_text(json.dumps(save_outputs, indent=2) + '\n')
        record = {'stage': stage, 'phase': phase, 'command': command, 'exit_code': code, 'error': error,
                  'seconds': time.monotonic() - started, 'issues': issues, 'summary': summary,
                  'source_drift': source_drift, 'copy_drift': copy_drift, 'save_drift': save_drift,
                  'report_error': report_error, 'ok': ok, 'log_sha256': sha(evidence / 'run.log')}
        receipt['runs'].append(record)
        (evidence / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        (work / 'run_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(record), flush=True)
        if not ok:
            return 1
    print('ACTIVITY_FLOW_RESULT all6 phases passed; actual observation save: ' + observed_slot, flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
