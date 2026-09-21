"""Run bounded stair-clear and empty-queue walk ownership/save regressions privately."""
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

STAGES = [
    ('clear_natural', 'test_courtesy_clear', 'natural', 'clear_natural', 'stair'),
    ('clear_producer', 'test_courtesy_clear_phases', 'producer', 'clear_phases', 'stair'),
    ('clear_fresh', 'test_courtesy_clear_phases', 'fresh', 'clear_phases', 'stair'),
    ('cancel_producer', 'test_courtesy_clear_cancel', 'producer', 'clear_cancel', 'stair'),
    ('cancel_fresh', 'test_courtesy_clear_cancel', 'fresh', 'clear_cancel', 'stair'),
    ('clear_controls', 'test_courtesy_clear_controls', 'controls', 'clear_controls', 'stair'),
    ('custody_producer', 'test_courtesy_clear_custody', 'producer', 'clear_custody', 'stair'),
    ('custody_fresh', 'test_courtesy_clear_custody', 'fresh', 'clear_custody', 'stair'),
    ('clear_bounds', 'test_courtesy_clear_bounds', 'controls', 'clear_bounds', 'stair'),
    ('walk_natural', 'test_courtesy_walk_recovery', 'natural', 'walk_observation', 'walk'),
    ('walk_retreat_producer', 'test_courtesy_walk_recovery', 'produce', 'walk_observation', 'walk'),
    ('walk_retreat_fresh', 'test_courtesy_walk_recovery', 'fresh', 'walk_observation', 'walk'),
    ('walk_hold_producer', 'test_courtesy_walk_hold', 'produce', 'walk_observation', 'walk'),
    ('walk_hold_fresh', 'test_courtesy_walk_hold', 'fresh', 'walk_observation', 'walk'),
    ('walk_controls', 'test_courtesy_walk_controls', 'controls', 'walk_controls', 'walk'),
    ('walk_immediate_producer', 'test_courtesy_walk_immediate', 'producer', 'walk_immediate', 'walk'),
    ('walk_immediate_fresh', 'test_courtesy_walk_immediate', 'fresh', 'walk_immediate', 'walk'),
]
SCRIPTS = {row[1] for row in STAGES} | {'test_courtesy_beneficiary_base', 'test_courtesy_walk_observation'}
FIXTURES = {
    'courtesy_stair_clear.json': 'life_1788959163926_31350169',
    'courtesy_empty_walk.json': 'life_1788958789245_369321256',
    'courtesy_first_crowd.json': 'life_1788942682044_57282849',
}


def report_errors(path, summary, phase, mode, observed_walk):
    """Check an actually emitted report against this process's terminal result."""
    if not path.is_file():
        return ['Expected phase report was not created.']
    try:
        report = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        return ['Cannot parse phase report: ' + str(exc)]
    if not isinstance(report, dict) or len(summary) != 1:
        return ['Report or terminal summary has invalid shape.']
    count, failures, _ = summary[0]
    errors = []
    field = 'checks' if observed_walk else 'assertions'
    if type(report.get(field)) is not int or report[field] != int(count):
        errors.append('Report count disagrees with the terminal summary.')
    if not isinstance(report.get('failures'), list) or len(report['failures']) != int(failures):
        errors.append('Report failures disagree with the terminal summary.')
    if 'phase' in report and report['phase'] != phase:
        errors.append('Report names a different phase.')
    if 'mode' in report and report['mode'] != mode:
        errors.append('Report names a different producer/fresh mode.')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--group', choices=('all', 'stair', 'walk'), default='all')
    parser.add_argument('--timeout', type=int, default=420,
                        help='Per-process cap in seconds. Since the iteration-50 clock the walk-controls phase needs about '
                             '250 s on an idle machine and more on a loaded one; the former 180 s cap killed it mid-run.')
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('This runner requires Linux XDG isolation and never uses player data.')
    source = args.source.resolve()
    task_tmp = source / 'dist/test-work'
    task_tmp.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='courtesy-beneficiaries-', dir=task_tmp))
    print('BENEFICIARY_CANDIDATE=' + str(work), flush=True)
    project = work / 'justlife-playthrough-beneficiaries'
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths'])
    paths.update({'project.godot', 'icon.svg', 'tests/regression_inputs.json',
                  'tests/run_courtesy_beneficiaries.py', 'tests/test_playthrough.gd',
                  'tests/test_public_twofloor.gd'})
    paths.update('tests/' + name + '.gd' for name in SCRIPTS)
    paths.update('tests/fixtures/' + name for name in FIXTURES)
    paths.update('tests/fixtures/' + name for name in (
        'legacy_ordinary_retreat.json', 'legacy_ordinary_hold.json',
        'courtesy_pre_kind_reader.gd', 'courtesy_pre_walk_reader.gd'))
    paths.update(name + '.uid' for name in tuple(paths)
                 if name.endswith('.gd') and (source / (name + '.uid')).is_file())
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    source_hashes = {}
    for name in sorted(paths):
        path = source / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not path.resolve().is_relative_to(source) or not path.is_file():
            raise ValueError('Invalid or missing private snapshot input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        source_hashes[name] = sha(path)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', config.read_text(), flags=re.S))
    frozen = {name: sha(project / name) for name in paths}
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(project / 'userdata'), XDG_CONFIG_HOME=str(project / 'config'),
               XDG_CACHE_HOME=str(project / 'cache'), JUSTLIFE_DATA_DIR=str(project / 'userdata/save_data'), TMPDIR=str(project / 'tmp'))
    env_keys = ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'JUSTLIFE_DATA_DIR', 'TMPDIR')
    for key in env_keys:
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    save_dir = Path(env['JUSTLIFE_DATA_DIR']) / 'saves'
    save_dir.mkdir(parents=True, exist_ok=True)
    (project / 'evidence').mkdir()
    (project / 'userdata/evidence').mkdir()
    for fixture, slot in FIXTURES.items():
        shutil.copy2(project / 'tests/fixtures' / fixture, save_dir / (slot + '.json'))
    phases = [('import', '', '', '', '')] + [row for row in STAGES if args.group == 'all' or row[4] == args.group]
    runs = []
    for phase, script, mode, report_name, _ in phases:
        evidence = work / 'evidence' / phase
        evidence.mkdir(parents=True)
        command = ['godot', '--path', str(project), '--audio-driver', 'Dummy', '--headless']
        command += ['--editor', '--import', '--quit'] if phase == 'import' else ['--script', 'res://tests/' + script + '.gd', '--', '--resume-only']
        env['CLEAR_MODE'] = mode
        observed_walk = report_name == 'walk_observation'
        if observed_walk:
            directed = script == 'test_courtesy_walk_hold'
            env.update(WALK_RUN_ROOT=str(project / 'userdata'), WALK_CANDIDATE_TOKEN=sha(project / 'scripts/courtesy.gd'),
                       WALK_TEST_MODE=mode, WALK_PHASE='hold' if directed else ('' if mode == 'natural' else 'retreat'),
                       WALK_SLOT=('crowd_public_walk_actual_hold' if directed else 'walk_actual_retreat') if mode == 'fresh' else FIXTURES['courtesy_first_crowd.json' if directed else 'courtesy_empty_walk.json'])
        report = project / 'userdata/evidence/diagnostic.json' if observed_walk else project / 'evidence' / (report_name + '.json')
        previous_report_sha256 = None
        if phase != 'import' and report.exists():
            previous_report_sha256 = sha(report)
            shutil.copy2(report, evidence / 'prior_report.json')
            report.unlink()  # A previous phase's shared filename cannot satisfy this one.
        save_inputs = {path.name: sha(path) for path in save_dir.glob('*.json')}
        (evidence / 'save_inputs.json').write_text(json.dumps(save_inputs, indent=2) + '\n')
        started = time.monotonic()
        error = ''
        try:
            with (evidence / 'run.log').open('w') as log:
                result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
            error = 'Owned subprocess reached its %d-second cap and was killed and reaped.' % args.timeout
        except OSError as exc:
            code, error = 127, str(exc)
        output = (evidence / 'run.log').read_text()
        problems = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|CHECK FAIL):?.*', output, re.M)
        summary = re.findall(r'^COMPOSED_RESULT assertions=(\d+) failures=(\d+) phase=(\w+)$', output, re.M)
        if observed_walk:
            summary = [(count, failures, 'walk_observation') for count, failures in re.findall(r'^WALK_DIAG (\d+) checks, (\d+) failures$', output, re.M)]
            problems += re.findall(r'^WALK_DIAG_FAIL .*', output, re.M)
        drift = [name for name, expected in frozen.items() if not (project / name).is_file() or sha(project / name) != expected]
        source_drift = [name for name, expected in source_hashes.items() if not (source / name).is_file() or sha(source / name) != expected]
        changed_saves = [name for name, expected in save_inputs.items() if not (save_dir / name).is_file() or sha(save_dir / name) != expected]
        ok = code == 0 and not problems and not drift and not source_drift and not changed_saves
        report_problems = []
        if phase != 'import':
            ok = ok and len(summary) == 1 and int(summary[0][0]) > 0 and summary[0][1] == '0' and summary[0][2] == report_name
            expected_phase = mode + '_' + env['WALK_PHASE'] if observed_walk else report_name
            report_problems = report_errors(report, summary, expected_phase, mode, observed_walk)
            ok = ok and not report_problems
            if report.is_file():
                shutil.copy2(report, evidence / 'report.json')
            if observed_walk:
                for path in (project / 'userdata/evidence').glob('*.json'):
                    shutil.copy2(path, evidence / path.name)
            for path in (project / 'evidence').glob('*slot*.json'):
                shutil.copy2(path, evidence / path.name)
        save_outputs = {path.name: sha(path) for path in save_dir.glob('*.json')}
        (evidence / 'save_outputs.json').write_text(json.dumps(save_outputs, indent=2) + '\n')
        record = {'phase': phase, 'command': command, 'mode': mode, 'exit_code': code, 'error': error,
                  'elapsed_seconds': time.monotonic() - started, 'problems': problems, 'summary': summary,
                  'input_drift': drift, 'source_drift': source_drift, 'changed_existing_saves': changed_saves,
                  'report_problems': report_problems, 'previous_report_sha256': previous_report_sha256,
                  'ok': ok, 'log_sha256': sha(evidence / 'run.log')}
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
