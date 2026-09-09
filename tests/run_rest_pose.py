"""Check paused fresh-load sleeping presentation in a private Godot copy."""
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
        parser.error('This runner requires Linux XDG isolation.')
    source = args.source.resolve()
    temp = source / 'dist/test-work'
    temp.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='rest-pose-', dir=temp))
    project = work / 'justlife-playthrough-rest'
    print('REST_WORK=' + str(work), flush=True)
    paths = set(json.loads((source / 'tests/regression_inputs.json').read_text())['paths'])
    paths.update({'project.godot', 'icon.svg', 'tests/regression_inputs.json',
                  'tests/run_rest_pose.py', 'tests/test_rest_pose.gd',
                  'tests/test_playthrough.gd', 'tests/test_public_twofloor.gd',
                  'tests/test_courtesy_beneficiary_base.gd',
                  'tests/fixtures/courtesy_stair_clear.json'})
    paths.update(p + '.uid' for p in tuple(paths)
                 if p.endswith('.gd') and (source / (p + '.uid')).is_file())
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    source_pins = {}
    for name in sorted(paths):
        path = source / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not path.resolve().is_relative_to(source) or not path.is_file():
            raise ValueError('Invalid private input: ' + name)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        source_pins[name] = sha(path)
    config = project / 'project.godot'
    config.write_text(re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', config.read_text(), flags=re.S))
    project_pins = {name: sha(project / name) for name in paths}
    inputs = {'source': str(source), 'source_files': source_pins,
              'project': str(project), 'project_files': project_pins,
              'configuration_change': 'Remove editor-only addons/autoload/MCP blocks from private copy.'}
    (work / 'INPUTS.json').write_text(json.dumps(inputs, indent=2) + '\n')
    def verify():
        for name, digest in source_pins.items():
            assert sha(source / name) == digest, name
        for name, digest in project_pins.items():
            assert sha(project / name) == digest, name
    results = []
    original = project / 'tests/fixtures/courtesy_stair_clear.json'
    assert sha(original) == '1b40410cf9f85af78af2d484360a3679454d7e251523f52e6ef686e9ddfbcb95'
    for mode in ('import', 'selected', 'producer', 'nonselected'):
        phase = work / mode
        phase.mkdir()
        env = os.environ.copy()
        mapping = {'XDG_DATA_HOME': 'userdata', 'XDG_CONFIG_HOME': 'config',
                   'XDG_CACHE_HOME': 'cache', 'TMPDIR': 'tmp', 'JUSTLIFE_DATA_DIR': 'save_data'}
        for key, part in mapping.items():
            env[key] = str(phase / part)
            Path(env[key]).mkdir()
        (phase / 'save_data/saves').mkdir()
        (phase / 'evidence').mkdir()
        fixture = original
        slot = 'life_1788959163926_31350169'
        if mode == 'nonselected':
            fixture = work / 'producer/evidence/actual_nonselected.json'
            slot = 'rest_actual_nonselected'
            assert results[-1]['status'] == 'pass'
            assert sha(fixture) == sha(work / 'producer/save_data/saves/rest_actual_nonselected.json')
        destination = phase / 'save_data/saves' / (slot + '.json')
        shutil.copyfile(fixture, destination)
        fixture_sha = sha(fixture)
        env.update(REST_RUN_ROOT=str(phase), REST_MODE=mode, REST_SLOT=slot)
        command = ['godot', '--headless', '--path', str(project), '--audio-driver', 'Dummy']
        command += ['--editor', '--import', '--quit'] if mode == 'import' else ['--script', 'res://tests/test_rest_pose.gd']
        receipt = {'mode': mode, 'command': command, 'environment': {k: env[k] for k in (*mapping, 'REST_RUN_ROOT', 'REST_MODE', 'REST_SLOT')},
                   'fixture': str(fixture), 'fixture_sha256': fixture_sha,
                   'inputs_sha256': sha(work / 'INPUTS.json'), 'status': 'running'}
        (phase / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        verify()
        start = time.monotonic()
        with (phase / 'run.log').open('w') as log:
            try:
                code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120).returncode
            except subprocess.TimeoutExpired:
                code = 'timeout'
        log = (phase / 'run.log').read_text()
        issues = [line for line in log.splitlines() if re.search(r'ERROR:|WARNING:|SCRIPT ERROR|leaked|still in use', line)]
        summaries = re.findall(r'REST_POSE (\d+) checks, (\d+) failures', log)
        if mode != 'import':
            report_path = phase / 'evidence/rest.json'
            if not report_path.is_file():
                issues.append('Missing rest report.')
            else:
                report = json.loads(report_path.read_text())
                if len(summaries) != 1 or (report.get('checks'), len(report.get('failures', []))) != tuple(map(int, summaries[0])) or report.get('mode') != mode:
                    issues.append('Report and terminal summary disagree.')
                receipt['report_sha256'] = sha(report_path)
        verify()
        assert sha(fixture) == fixture_sha and sha(destination) == fixture_sha
        passed = code == 0 and not issues and (mode == 'import' or len(summaries) == 1 and summaries[0][1] == '0')
        receipt.update(status='pass' if passed else 'failed', exit_code=code,
                       seconds=time.monotonic() - start, issues=issues, summaries=summaries,
                       log_sha256=sha(phase / 'run.log'))
        (phase / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        results.append(receipt)
        (work / 'RESULT.json').write_text(json.dumps(results, indent=2) + '\n')
        print(json.dumps({'mode': mode, 'status': receipt['status'], 'summaries': summaries, 'issues': issues}), flush=True)
        if not passed:
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
