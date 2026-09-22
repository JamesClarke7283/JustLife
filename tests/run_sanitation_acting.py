"""Isolated original-character acting, action ownership and contact verification."""
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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--capture', action='store_true', help='Open a temporary Forward+ game window and save actual frame captures.')
args = parser.parse_args()
if not sys.platform.startswith('linux'):
    parser.error('This runner requires Linux XDG data isolation.')
source = args.source.resolve()
work = Path(tempfile.mkdtemp(prefix='sanitation-acting-'))
print('ACTING_CANDIDATE=' + str(work), flush=True)
for name in ('scripts', 'assets', 'scenes'):
    shutil.copytree(source / name, work / name, ignore=shutil.ignore_patterns('character_rig*', '*_grip*'))
(work / 'tests').mkdir()
shutil.copy2(source / 'tests/test_sanitation_acting.gd', work / 'tests/test_sanitation_acting.gd')
project = re.sub(r'\[(autoload|editor_plugins|mcp_toolkit)\]\n.*?(?=\n\[|\Z)', '', (source / 'project.godot').read_text(), flags=re.S)
(work / 'project.godot').write_text(project)
env = os.environ.copy()
for key, folder in [('XDG_DATA_HOME', 'userdata'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('JUSTLIFE_DATA_DIR', 'save_data')]:
    env[key] = str(work / folder)
inputs = {str(p.relative_to(work)): hashlib.sha256(p.read_bytes()).hexdigest() for p in work.rglob('*') if p.is_file() and not p.name.endswith('.import')}
runs = []
for phase in ('import', 'acting'):
    cmd = ['godot', '--path', str(work)]
    if phase == 'import':
        cmd += ['--headless', '--editor', '--import']
    else:
        if not args.capture:
            cmd += ['--headless']
        cmd += ['--script', 'res://tests/test_sanitation_acting.gd', '--', '--after']
        if args.capture:
            cmd += ['--capture']
    with (work / (phase + '.log')).open('w') as log:
        result = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180)
    output = (work / (phase + '.log')).read_text()
    errors = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING):.*', output, re.M)
    summaries = re.findall(r'Acting: (\d+) checks, (\d+) failures\.', output)
    ok = result.returncode == 0 and not errors and (phase == 'import' or bool(summaries))
    runs.append(dict(phase=phase, exit_code=result.returncode, errors=errors, summaries=summaries, ok=ok))
    changed = [name for name, digest in inputs.items() if hashlib.sha256((work / name).read_bytes()).hexdigest() != digest]
    (work / 'run_receipt.json').write_text(json.dumps(dict(source=str(source), runs=runs, inputs=inputs, changed=changed), indent=2))
    print(runs[-1], flush=True)
    if not ok or changed:
        raise SystemExit(1)
