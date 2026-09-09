"""Isolated synchronous preview and save ownership control; --capture opens a window."""
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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--capture', action='store_true')
args = parser.parse_args()
if not sys.platform.startswith('linux'):
    parser.error('This runner requires Linux XDG isolation and will not use platform player-data folders.')
source = args.source.resolve()
task_tmp = source / 'dist/test-work'
task_tmp.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(prefix='save-preview-', dir=task_tmp))
print('SAVE_PREVIEW_CANDIDATE=' + str(work), flush=True)
for name in ('scripts', 'scenes', 'assets'):
    shutil.copytree(source / name, work / name)
(work / 'tests').mkdir()
shutil.copy2(source / 'tests/test_save_preview.gd', work / 'tests/test_save_preview.gd')
shutil.copy2(Path(__file__), work / 'tests/run_save_preview.py')
project = re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '',
                 (source / 'project.godot').read_text(), flags=re.S)
(work / 'project.godot').write_text(project)
inputs = {str(p.relative_to(work)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in work.rglob('*') if p.is_file() and not p.name.endswith('.import')}
env = os.environ.copy()
env['TMPDIR'] = str(task_tmp)
env['XDG_DATA_HOME'] = str(work)
env['JUSTLIFE_DATA_DIR'] = str(work / 'save_data')
env['XDG_CONFIG_HOME'] = str(work / 'config')
env['XDG_CACHE_HOME'] = str(work / 'cache')
runs = []
for phase in ('import', 'preview'):
    command = ['godot', '--path', str(work), '--audio-driver', 'Dummy']
    if phase == 'import':
        command += ['--headless', '--editor', '--import']
    else:
        if not args.capture:
            command += ['--headless']
        command += ['--script', 'res://tests/test_save_preview.gd']
    started = time.monotonic()
    timed_out = False
    startup_error = ''
    try:
        with (work / (phase + '.log')).open('w') as log:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        exit_code = result.returncode
    except subprocess.TimeoutExpired:
        # subprocess.run terminates and reaps its owned child before raising.
        timed_out = True
        exit_code = 124
    except OSError as error:
        startup_error = str(error)
        exit_code = 127
    output = (work / (phase + '.log')).read_text()
    errors = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING):.*', output, re.M)
    summaries = re.findall(r'Save preview: (\d+) checks, (\d+) failures\.', output)
    ok = exit_code == 0 and not errors and (phase == 'import' or bool(summaries))
    runs.append({'phase': phase, 'command': command, 'exit_code': exit_code,
                 'timed_out': timed_out, 'startup_error': startup_error,
                 'elapsed_seconds': time.monotonic() - started,
                 'errors': errors, 'summaries': summaries, 'ok': ok})
    drift = [name for name, expected in inputs.items()
             if hashlib.sha256((work / name).read_bytes()).hexdigest() != expected]
    (work / 'run_receipt.json').write_text(json.dumps({'source': str(source), 'work': str(work),
        'captured': args.capture, 'inputs': inputs, 'runs': runs, 'drift': drift}, indent=2) + '\n')
    print(runs[-1], flush=True)
    if not ok or drift:
        raise SystemExit(1)
