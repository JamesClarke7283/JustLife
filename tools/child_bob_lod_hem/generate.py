"""Reproduce only the Bob cap LOD rim correction; never promote outputs.

The accepted editable native source and both full models are copied byte exactly.
Each LOD reopens that source in its own Blender process. Historical v36 helpers
remain unmodified, and a stricter cap-only witness follows their guarded transfer.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = json.loads((HERE / 'contract.json').read_text())
HELPERS = HERE.parent / 'child_bob_v36'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--baseline-models', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--blender', default='blender')
    args = parser.parse_args()
    source, base, out = args.source.resolve(), args.baseline_models.resolve(), args.output.resolve()
    assert not out.exists(), 'Choose a new output directory'
    assert out != source and out not in source.parents
    assert out != base and out not in base.parents and base not in out.parents
    assert HERE not in out.parents and out not in HERE.parents
    assert sha(source) == CONTRACT['source_sha256'], 'Native input differs from accepted v36'
    for stem, pin in CONTRACT['baseline_glbs'].items():
        assert sha(base / (stem + '.glb')) == pin, stem
    for name, pin in CONTRACT['helper_pins'].items():
        assert sha(HELPERS / name) == pin, name
    sys.path.insert(0, str(HELPERS))
    from transfer_bob import transfer, projected_sharing
    from decoded_facts import expand, digest
    binary = shutil.which(args.blender)
    assert binary, 'Blender executable not found'
    for name in ['art', 'assets/models', 'raw_exports', 'evidence']:
        (out / name).mkdir(parents=True, exist_ok=True)
    receipt = {'status': 'running', 'source_sha256': sha(source),
               'input_glbs': CONTRACT['baseline_glbs'], 'blender_sha256': sha(Path(binary)),
               'script_pins': {f.name: sha(f) for f in sorted(HERE.glob('*')) if f.is_file()},
               'helper_pins': CONTRACT['helper_pins'], 'runs': [], 'exports': []}
    def save():
        (out / 'evidence/reproduction.json').write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    shutil.copy2(source, out / 'art/characters_child.blend')
    for stem in ['character_child', 'character_child_broad']:
        shutil.copy2(base / (stem + '.glb'), out / 'assets/models' / (stem + '.glb'))
    for stem in ['character_child_lod', 'character_child_broad_lod']:
        command = [binary, '--background', '--factory-startup', '--threads', '1',
                   '--python-exit-code', '2', '--python', str(HERE / 'export_lod.py'), '--',
                   '--source', str(source), '--source-sha256', CONTRACT['source_sha256'],
                   '--output-root', str(out / 'raw_exports'), '--variant', stem]
        record = {'variant': stem, 'command': command}
        receipt['runs'].append(record); save()
        log = out / 'evidence' / (stem + '.log')
        started = time.monotonic()
        with log.open('w') as handle:
            result = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT)
        record.update(returncode=result.returncode, seconds=time.monotonic()-started,
                      log_sha256=sha(log), addon_traceback_retained='ModuleNotFoundError' in log.read_text())
        save()
        assert result.returncode == 0, 'Failed export retained: ' + str(log)
        raw, target = out / 'raw_exports' / (stem + '.glb'), out / 'assets/models' / (stem + '.glb')
        assert sha(raw) == CONTRACT['raw_glbs'][stem], 'Raw output differs from visual candidate'
        accepted = base / (stem + '.glb')
        transfer(accepted, raw, target, out / 'evidence' / (stem + '_transfer.json'),
                 set(CONTRACT['inherited_transfer_owned_meshes']))
        a, b, authored = expand(accepted), expand(target), expand(raw)
        assert a['root'] == b['root'] == authored['root']
        assert a['meshes'].keys() == b['meshes'].keys() == authored['meshes'].keys()
        assert sorted(n for n in a['meshes'] if a['meshes'][n] != b['meshes'][n]) == ['Hair_Bob_Cap']
        protected = set(a['meshes']) - {'Hair_Bob_Cap'}
        assert len(protected) == CONTRACT['protected_decoded_mesh_count'] == 338
        assert projected_sharing(a, protected) == projected_sharing(b, protected)
        assert b['meshes']['Hair_Bob_Cap'] == authored['meshes']['Hair_Bob_Cap']
        assert sha(target) == CONTRACT['candidate_glbs'][stem]
        receipt['exports'].append({'variant': stem, 'output_sha256': sha(target),
            'only_changed_mesh': 'Hair_Bob_Cap', 'protected_meshes_exact': len(protected),
            'protected_sharing_exact': True, 'root_node_rig_material_exact': True,
            'cap_exact_to_Blender': True,
            'protected_digest': digest({n: a['meshes'][n] for n in sorted(protected)})})
        save()
    assert sha(source) == sha(out / 'art/characters_child.blend') == CONTRACT['source_sha256']
    for stem, pin in CONTRACT['baseline_glbs'].items():
        assert sha(base / (stem + '.glb')) == pin
        if not stem.endswith('_lod'):
            assert sha(out / 'assets/models' / (stem + '.glb')) == pin
    assert all(sha(HERE / n) == pin for n, pin in receipt['script_pins'].items())
    assert all(sha(HELPERS / n) == pin for n, pin in CONTRACT['helper_pins'].items())
    receipt.update(status='pass', native_and_full_models_byte_exact=True,
                   inputs_and_scripts_unchanged=True)
    save()
    print('BOB_CAP_LOD_REPRODUCTION_EXACT', out)

if __name__ == '__main__':
    main()
