"""Run the Bob import probe in an isolated Godot project without MCP autoloads."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('candidate', type=Path)
a = p.parse_args()
candidate = a.candidate.resolve()
assert candidate.is_file()
probe = Path(__file__).with_name('inspect_import.gd')
with tempfile.TemporaryDirectory(prefix='justlife-bob-import-') as directory:
    temporary = Path(directory)
    project = temporary / 'project'
    project.mkdir()
    # A minimal copy is sufficient: the probe only uses Godot's built-in GLTF
    # importer. No application scenes, autoloads, addons or live registry paths
    # are inherited from the user's working project.
    (project / 'project.godot').write_text('config_version=5\n\n[application]\nconfig/name="JustLife isolated Bob import"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    shutil.copy2(probe, project / 'inspect_import.gd')
    environment = dict(os.environ)
    environment['JUSTLIFE_BOB_IMPORT_ISOLATED'] = '1'
    for variable, folder in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        environment[variable] = str(temporary / folder)
    subprocess.run(['godot', '--headless', '--path', str(project), '--script',
                    'inspect_import.gd', '--', str(candidate)], env=environment, check=True)
