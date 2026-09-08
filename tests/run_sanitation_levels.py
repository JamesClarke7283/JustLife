"""Isolated physical-floor, sanitation and real-car acceptance checks on Linux."""
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
parser.add_argument('--only', choices=('all', 'v2', 'car'), default='all')
parser.add_argument('--capture', action='store_true', help='Run only the Forward+ floor/picking/mop capture gate.')
args = parser.parse_args()
if not sys.platform.startswith('linux'):
    parser.error('This verification runner requires Linux XDG isolation.')
source = args.source.resolve()
work = Path(tempfile.mkdtemp(prefix='justlife-sanitation-levels-'))
print('SANITATION_LEVELS_CANDIDATE=' + str(work), flush=True)
for folder in ('scripts', 'assets', 'scenes'):
    shutil.copytree(source / folder, work / folder)
(work / 'tests').mkdir()
for test in (source / 'tests').glob('test_sanitation*.gd'):
    shutil.copy2(test, work / 'tests' / test.name)
project = (source / 'project.godot').read_text()
project = re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', project, flags=re.S)
(work / 'project.godot').write_text(project)
env = os.environ.copy()
env.update(XDG_DATA_HOME=str(work / 'userdata'), XDG_CONFIG_HOME=str(work / 'config'),
           XDG_CACHE_HOME=str(work / 'cache'), JUSTLIFE_DATA_DIR=str(work / 'save_data'))
digest = lambda file: hashlib.sha256(file.read_bytes()).hexdigest()
inputs = {str(file.relative_to(work)): digest(file) for file in work.rglob('*')
          if file.is_file() and not file.name.endswith('.import')}
phases = [('import', '', [])]
if args.capture:
    phases += [('render', 'test_sanitation_levels_render.gd', [])]
else:
    if args.only == 'all':
        phases += [('first', 'test_sanitation.gd', []), ('resume', 'test_sanitation.gd', ['--resume']),
                   ('busy', 'test_sanitation_busy.gd', ['--busy'])]
    if args.only in ('all', 'car'):
        phases += [('travel', 'test_sanitation_travel.gd', [])]
    if args.only in ('all', 'v2'):
        phases += [('levels', 'test_sanitation_levels.gd', []), ('pending', 'test_sanitation_pending.gd', []),
                   ('restore_targets', 'test_sanitation_restore_targets.gd', []),
                   ('physical', 'test_sanitation_physical.gd', []),
                   ('physical_resume', 'test_sanitation_physical.gd', ['--resume']),
                   ('support', 'test_sanitation_support.gd', [])]
runs = []
for phase, script, extra in phases:
    command = ['godot', '--path', str(work)]
    if phase != 'render':
        command += ['--headless']
    if phase == 'import':
        command += ['--editor', '--import']
    else:
        command += ['--script', 'res://tests/' + script]
        if extra:
            command += ['--'] + extra
    start = time.monotonic()
    timed_out = False
    with (work / (phase + '.log')).open('w') as log:
        try:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=360 if phase == 'travel' else 240)
            code = result.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            code = -1
    text = (work / (phase + '.log')).read_text()
    errors = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING|FAIL):.*', text, re.M)
    summaries = re.findall(r'Sanitation(?: [a-z]+)?: (\d+) checks, (\d+) failures\.', text)
    ok = code == 0 and not errors and (phase == 'import' or bool(summaries))
    runs.append(dict(phase=phase, exit_code=code, timed_out=timed_out, seconds=time.monotonic()-start,
                     errors=errors, summaries=summaries, ok=ok))
    changed = [name for name, expected in inputs.items() if digest(work / name) != expected]
    (work / 'run_receipt.json').write_text(json.dumps(dict(source=str(source), runs=runs,
                                                         inputs=inputs, changed=changed), indent=2))
    print(runs[-1], flush=True)
    if not ok or changed:
        raise SystemExit(1)
