"""Check brief pre-work recovery policy in a retained, isolated Linux project."""
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
        parser.error('This runner requires Linux XDG data isolation.')
    source = args.source.resolve()
    temporary = source / 'dist/test-work'
    temporary.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='prework-recovery-', dir=temporary))
    print('PREWORK_RECOVERY_CANDIDATE=' + str(work), flush=True)
    project = work / 'justlife-playthrough-prework'
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths'])
    paths.update({'project.godot', 'icon.svg', 'tests/regression_inputs.json',
                  'tests/run_prework_recovery.py', 'tests/test_prework_recovery.gd',
                  'tests/test_autonomy_policy.gd'})
    paths.update(name + '.uid' for name in tuple(paths)
                 if name.endswith('.gd') and (source / (name + '.uid')).is_file())
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    source_pins = {}
    for name in sorted(paths):
        original = source / name
        if (Path(name).is_absolute() or '..' in Path(name).parts
                or not original.resolve().is_relative_to(source) or not original.is_file()):
            raise ValueError('Invalid snapshot input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        source_pins[name] = digest(original)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)',
                             '', config.read_text(), flags=re.S))
    copy_pins = {name: digest(project / name) for name in paths}
    overrides = {key: str(project / directory) for key, directory in (
        ('XDG_DATA_HOME', 'userdata'), ('XDG_CONFIG_HOME', 'config'),
        ('XDG_CACHE_HOME', 'cache'), ('JUSTLIFE_DATA_DIR', 'userdata/save_data'), ('TMPDIR', 'tmp'))}
    for directory in overrides.values():
        Path(directory).mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(overrides)
    assert env.get('HOME') == os.environ.get('HOME')
    receipt = {'source': str(source), 'source_inputs': source_pins, 'copied_inputs': copy_pins,
               'environment': overrides, 'home_unchanged': True, 'runs': []}
    for phase, extra in [('import', ['--editor', '--import', '--quit']),
                         ('checks', ['--script', 'res://tests/test_prework_recovery.gd'])]:
        command = ['godot', '--headless', '--path', str(project), '--audio-driver', 'Dummy', *extra]
        started = time.monotonic()
        error = ''
        log = work / (phase + '.log')
        try:
            with log.open('x') as stream:
                result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=120)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code, error = 124, 'Owned Godot process killed and reaped after 120 seconds.'
        except OSError as exc:
            code, error = 127, str(exc)
        output = log.read_text()
        diagnostics = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|CHECK FAIL).*|^.*(?:ObjectDB instances leaked|resources still in use).*$', output, re.M)
        drift = {label: [name for name, pin in pins.items()
                         if not (base / name).is_file() or digest(base / name) != pin]
                 for label, base, pins in [('source', source, source_pins), ('copy', project, copy_pins)]}
        summaries = re.findall(r'^PREWORK_RECOVERY (\d+) checks, (\d+) failures$', output, re.M)
        # The unchanged test prints one final counter and exits; it writes no JSON report.
        # Exact final count guards against a partial run being accepted as this 40-check suite.
        report_ok = phase == 'import' or summaries == [('40', '0')]
        ok = code == 0 and not error and not diagnostics and not any(drift.values()) and report_ok
        record = {'phase': phase, 'command': command, 'exit_code': code, 'error': error,
                  'seconds': time.monotonic() - started, 'diagnostics': diagnostics, 'drift': drift,
                  'summaries': summaries, 'expected_checks': 40 if phase == 'checks' else None,
                  'terminal_summary_matches': report_ok, 'log_sha256': digest(log), 'ok': ok}
        receipt['runs'].append(record)
        receipt['ok'] = all(run['ok'] for run in receipt['runs'])
        (work / 'run_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(record), flush=True)
        if not ok:
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
