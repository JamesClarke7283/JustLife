"""Build JustLife from an isolated snapshot without development editor services."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, tempfile, time

def run():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1],help='Frozen project source to package; defaults to this workspace.')
    parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'dist'/'JustLife')
    args=parser.parse_args()
    source=args.source.resolve()
    target=args.output.resolve();target.mkdir(parents=True,exist_ok=True)
    snapshot=Path(tempfile.mkdtemp(prefix='justlife-release-'))
    def excluded_studies(directory,names):
        relative=Path(directory).relative_to(source)
        if relative==Path('assets/models'):
            return [name for name in names if '_rig' in name or '_grip' in name]
        if relative==Path('assets/audio'):
            return [name for name in names if name=='measurements.json']
        return []
    for directory in ('assets','scripts','scenes','licenses'):
        # Match the existing export exclusions before copying/importing large
        # local studies; they are not needed to build the production package.
        shutil.copytree(source/directory,snapshot/directory,ignore=excluded_studies if directory=='assets' else None)
    for file in ('icon.svg','export_presets.cfg','CREDITS.md'):
        shutil.copy2(source/file,snapshot/file)
    lines=[];skip=False
    for line in (source/'project.godot').read_text().splitlines():
        if line.startswith('['):skip=line in ('[autoload]','[editor_plugins]','[mcp_toolkit]')
        if not skip:lines.append(line)
    (snapshot/'project.godot').write_text('\n'.join(lines)+'\n')
    if (source/'.godot/imported').is_dir():
        shutil.copytree(source/'.godot/imported',snapshot/'.godot/imported',ignore=shutil.ignore_patterns('*_rig*','*_grip*','measurements.json-*'))
    hashes={str(p.relative_to(snapshot)):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ('scripts','scenes','assets') for p in (snapshot/folder).rglob('*') if p.is_file() and p.suffix!='.import'}
    godot=shutil.which('godot') or 'godot'
    version=subprocess.check_output([godot,'--version'],text=True).strip()
    template_version='.'.join(version.split('.')[:4])
    templates=Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))/'godot'/'export_templates'/template_version
    preset=(snapshot/'export_presets.cfg').read_text()
    for configuration in ('debug','release'):
        template=templates/('linux_'+configuration+'.x86_64')
        if not template.is_file():raise SystemExit('Missing Godot export template: '+str(template))
        preset=preset.replace('custom_template/'+configuration+'=""','custom_template/'+configuration+'="'+str(template)+'"')
    (snapshot/'export_presets.cfg').write_text(preset)
    env=os.environ.copy();env['XDG_DATA_HOME']=str(snapshot/'userdata')
    env['JUSTLIFE_DATA_DIR']=str(snapshot/'userdata'/'save_data')
    executable=target/'JustLife.x86_64'
    commands=[['--headless','--editor','--path',str(snapshot),'--import'],['--headless','--path',str(snapshot),'--export-release','Linux',str(executable)]]
    for phase,args in zip(('import','export'),commands):
        with (snapshot/(phase+'.log')).open('w') as log:
            result=subprocess.run([godot,*args],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=300)
        logtext=(snapshot/(phase+'.log')).read_text()
        if result.returncode or 'SCRIPT ERROR:' in logtext or '\nERROR:' in logtext:
            raise SystemExit('Build failed; inspect '+str(snapshot/(phase+'.log')))
    shutil.copytree(source/'licenses',target/'licenses',dirs_exist_ok=True)
    for file in ('README.md','CREDITS.md'):shutil.copy2(source/file,target/file)
    (target/'build_manifest.json').write_text(json.dumps({'built_at_unix':time.time(),'engine':subprocess.check_output([godot,'--version'],text=True).strip(),'source':str(source),'snapshot':str(snapshot),'sha256':hashlib.sha256(executable.read_bytes()).hexdigest(),'source_hashes':hashes},indent=2))
    print('EXECUTABLE='+str(executable));print('SNAPSHOT='+str(snapshot))
if __name__=='__main__':run()
