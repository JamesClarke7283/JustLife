"""Import and compare candidates to v18 in a private Godot project."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

stage = Path(__file__).resolve().parent
project = stage.parents[2]
with tempfile.TemporaryDirectory(prefix='justlife-playthrough-hair-assets-') as directory:
    work = Path(directory)
    (work/'models').mkdir()
    (work/'project.godot').write_text('config_version=5\n[application]\nconfig/name="JustLife hair asset audit"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    shutil.copy2(stage/'verify_hair_assets.gd', work/'verify.gd')
    for age in ['adult', 'child']:
        source = project/'assets/models'/('character.glb' if age == 'adult' else 'character_child.glb')
        shutil.copy2(source, work/'models'/f'{age}_v18.glb')
        shutil.copy2(project/f'assets/models/character_{age}_hair_v19_grip.glb', work/'models'/f'{age}_candidate.glb')
    env = os.environ.copy()
    for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        env[key] = str(work/name)
    for args in [['--editor', '--import'], ['--script', 'res://verify.gd']]:
        result = subprocess.run(['godot', '--headless', '--path', str(work), *args], env=env, text=True, capture_output=True)
        print(result.stdout)
        print(result.stderr)
        if result.returncode:
            raise SystemExit(result.returncode)
