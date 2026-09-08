"""Exercise home storage and migration in isolated roots and fresh Godot processes.

HOME/USERPROFILE are never changed. JUSTLIFE_DATA_DIR and XDG_DATA_HOME point to
private directories; no real player save is read, created, overwritten or deleted.
"""
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


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--godot', default=shutil.which('godot') or 'godot')
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("This runner currently requires Linux XDG isolation; it will not touch platform user-data folders.")
    source = args.source.resolve()
    work = Path(tempfile.mkdtemp(prefix='justlife-storage-')).resolve()
    project = work / 'project'
    project.mkdir()
    shutil.copytree(source / 'scripts', project / 'scripts')
    (project / 'tests').mkdir()
    for name in ('test_save_storage.gd', 'test_save_library.gd'):
        shutil.copy2(source / 'tests' / name, project / 'tests' / name)
    (project / 'project.godot').write_text('[application]\nconfig/name="JustLife"\n')
    source_hashes = {str(p.relative_to(project)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in project.rglob('*') if p.is_file()}
    results = []
    print('ISOLATED_STORAGE=' + str(work), flush=True)

    def environment(case, root_override=None):
        case_dir = work / case
        case_dir.mkdir(exist_ok=True)
        env = os.environ.copy()
        env['JUSTLIFE_DATA_DIR'] = str(case_dir / 'save_data') if root_override is None else root_override
        env['XDG_DATA_HOME'] = str(case_dir / 'userdata')
        env['XDG_CONFIG_HOME'] = str(case_dir / 'config')
        env['XDG_CACHE_HOME'] = str(case_dir / 'cache')
        return env

    def godot(label, env, phase=None, script='test_save_storage.gd'):
        command = [args.godot, '--headless', '--path', str(project)]
        command += ['--editor', '--import'] if phase is None else ['--script', 'res://tests/' + script, '--', phase]
        log_path = work / (label + '.log')
        with log_path.open('w') as log:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=90)
        text = log_path.read_text()
        errors = re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING):.*', text, re.M)
        summaries = re.findall(r'Save (?:library|storage [^:]+): (\d+) checks, (\d+) failures\.', text)
        ok = result.returncode == 0 and not errors and (phase is None or bool(summaries))
        results.append(dict(label=label, exit_code=result.returncode, errors=errors, summaries=summaries, ok=ok))
        print(label + ': ' + ('PASS' if ok else 'FAIL') + ' ' + str(summaries), flush=True)
        if not ok:
            raise RuntimeError('Inspect ' + str(log_path))

    try:
        godot('import', environment('import'))
        godot('paths', environment('paths'), 'paths')
        env = environment('justlife-release-check-storage')
        env['XDG_DATA_HOME'] = str(work / 'justlife-release-check-storage')
        env['JUSTLIFE_DATA_DIR'] = str(work / 'justlife-release-check-storage' / 'save_data')
        godot('probe_valid', env, 'probe_valid')
        env['JUSTLIFE_DATA_DIR'] = str(work / 'different_save_data')
        godot('probe_mismatch', env, 'probe_invalid')
        godot('probe_invalid', environment('probe_invalid'), 'probe_invalid')
        godot('library', environment('library'), 'run', 'test_save_library.gd')
        env = environment('migration')
        godot('fixture', env, 'fixture')
        godot('migrate', env, 'migrate')
        godot('restart', env, 'restart')
        env = environment('legacy')
        godot('legacy_fixture', env, 'legacy_fixture')
        godot('legacy', env, 'legacy')
        old_file = next((work / 'legacy' / 'userdata').rglob('justlife_save.json'))
        old_digest = hashlib.sha256(old_file.read_bytes()).hexdigest()
        # Fresh process re-opening a completed record must not resurrect legacy.
        godot('legacy_deleted_restart', env, 'empty')
        assert old_file.is_file() and hashlib.sha256(old_file.read_bytes()).hexdigest() == old_digest
        for case in ('recovery', 'changed_destination', 'changed_source'):
            env = environment(case)
            godot(case + '_fixture', env, 'recovery_fixture')
            if case == 'recovery':
                godot(case, env, 'recover')
            else:
                changed = (work / case / 'save_data' / 'saves' / 'recovery.json') if case == 'changed_destination' else next((work / case / 'userdata').rglob('recovery.json'))
                changed.write_bytes(b'changed while migration was interrupted')
                marker = changed.read_bytes()
                godot(case, env, 'blocked')
                assert changed.read_bytes() == marker
        for label, root_override in (('relative_root', 'relative/unsafe'), ('empty_root', ''), ('resource_root', 'user://unsafe')):
            godot(label, environment(label, root_override), 'blocked')
        for case, source_path, destination_path in (
            ('source_traversal', 'saves/../../outside.json', 'saves/safe.json'),
            ('destination_traversal', 'saves/safe.json', '../outside.json'),
        ):
            env = environment(case)
            root_path = Path(env['JUSTLIFE_DATA_DIR'])
            root_path.mkdir()
            record = root_path / 'save_import.json'
            record.write_text(json.dumps({'version': 1, 'complete': False, 'entries': [
                {'id': 'safe', 'legacy': False, 'files': [{'source': source_path,
                    'destination': destination_path, 'source_hash': '0' * 64, 'wrap_legacy': False}]}]}))
            original_record = record.read_bytes()
            godot(case, env, 'blocked')
            assert record.read_bytes() == original_record and not (root_path / 'saves' / 'safe.json').exists()
        env = environment('damaged_record')
        record = Path(env['JUSTLIFE_DATA_DIR']) / 'save_import.json'
        record.parent.mkdir()
        record.write_text('{damaged')
        godot('damaged_record', env, 'blocked')
        assert record.read_text() == '{damaged'
        if os.name != 'nt':
            outside = work / 'outside'
            outside.mkdir()
            marker = outside / 'untouched.txt'
            marker.write_text('Keep this file unchanged')
            for case in ('linked_root', 'linked_ancestor', 'linked_saves', 'linked_record', 'linked_record_temp'):
                env = environment(case)
                root_path = Path(env['JUSTLIFE_DATA_DIR'])
                if case == 'linked_root':
                    root_path.symlink_to(outside, target_is_directory=True)
                elif case == 'linked_ancestor':
                    root_path.symlink_to(outside, target_is_directory=True)
                    env['JUSTLIFE_DATA_DIR'] = str(root_path / 'child')
                else:
                    root_path.mkdir()
                    if case == 'linked_saves':
                        (root_path / 'saves').symlink_to(outside, target_is_directory=True)
                    else:
                        (root_path / ('save_import.json.tmp' if case.endswith('temp') else 'save_import.json')).symlink_to(marker)
                godot(case, env, 'blocked')
                assert marker.read_text() == 'Keep this file unchanged' and set(outside.iterdir()) == {marker}
            env = environment('linked_old_source')
            godot('linked_old_setup', env, 'legacy_fixture')
            old = next((work / 'linked_old_source' / 'userdata').rglob('justlife_save.json'))
            old.unlink()
            old.symlink_to(marker)
            godot('linked_old_source', env, 'empty')
            assert marker.read_text() == 'Keep this file unchanged'
        after = {name: hashlib.sha256((project / name).read_bytes()).hexdigest() for name in source_hashes}
        assert after == source_hashes
    finally:
        (work / 'results.json').write_text(json.dumps({'source': str(source), 'hashes': source_hashes, 'results': results}, indent=2))
    print('All storage cases passed; evidence=' + str(work), flush=True)


if __name__ == '__main__':
    run()
