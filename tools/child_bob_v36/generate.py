"""Reproduce grouped child Bob and its cap taper from pinned local inputs.

Outputs a new private directory. Never promotes or modifies an input. All native
stages/witnesses and four exports use separate single-thread Blender processes.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path
from transfer_bob import transfer
from verify_exports import verify

HERE = Path(__file__).resolve().parent
CONTRACT = json.loads((HERE / 'native_contract.json').read_text())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--baseline-models', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--blender', default='blender')
args = parser.parse_args()
source, base, out = args.source.resolve(), args.baseline_models.resolve(), args.output.resolve()
assert not out.exists(), 'Choose a new output directory'
assert out != source and out not in source.parents and out != base and out not in base.parents
assert sha(source) == CONTRACT['source_sha256']
for stem, pin in CONTRACT['baseline_glbs'].items():
    assert sha(base / (stem + '.glb')) == pin, stem
for name in ['art', 'assets/models', 'evidence', 'raw_exports']:
    (out / name).mkdir(parents=True, exist_ok=True)
binary = shutil.which(args.blender)
assert binary, 'Blender executable not found'
receipt = {'status': 'running', 'source_sha256': sha(source),
           'input_glbs': CONTRACT['baseline_glbs'], 'blender_sha256': sha(Path(binary)),
           'script_pins': {f.name: sha(f) for f in sorted(HERE.glob('*')) if f.is_file()},
           'runs': [], 'exports': []}

def save_receipt():
    (out / 'evidence/reproduction.json').write_text(json.dumps(receipt, indent=2) + '\n')

def run(label, script, *arguments):
    command = [binary, '--background', '--factory-startup', '-t', '1',
               '--python-exit-code', '2', '--python', str(HERE / script), '--', *map(str, arguments)]
    record = {'label': label, 'command': command}
    receipt['runs'].append(record)
    save_receipt()
    log = out / 'evidence' / (label + '.log')
    start = time.monotonic()
    with log.open('w') as handle:
        result = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT)
    record.update(returncode=result.returncode, seconds=time.monotonic()-start, log_sha256=sha(log))
    save_receipt()
    assert result.returncode == 0, 'Failed process retained: ' + str(log)

def witness(label, path):
    output = out / 'evidence' / (label + '.json')
    run(label, 'native_witness.py', '--source', path, '--output', output)
    return json.loads(output.read_text())

def protected_native(before, after, owned):
    assert before['scene'] == after['scene']
    assert before['materials'] == after['materials']
    a, b = before['facts'], after['facts']
    assert a['objects'].keys() == b['objects'].keys()
    for name, old in a['objects'].items():
        new = b['objects'][name]
        if name not in owned:
            assert old == new, name
        else:
            assert {k: v for k, v in old.items() if k != 'geometry_sha256'} == {k: v for k, v in new.items() if k != 'geometry_sha256'}, name
            for key, value in a['owned'][name].items():
                if key != 'mesh_positions':
                    assert value == b['owned'][name][key], (name, key)

initial = witness('baseline_native', source)
assert initial['native_signature'] == CONTRACT['baseline_native_signature']
run('group_bob', 'sculpt_bob.py', '--source', source, '--output', out / 'grouped')
grouped_source = out / 'grouped/characters_child.blend'
grouped = witness('grouped_native', grouped_source)
assert grouped['native_signature'] == CONTRACT['grouped_native_signature']
owned = set(CONTRACT['scope']['owned_meshes'])
protected_native(initial, grouped, owned)
run('taper_cap', 'taper_cap.py', '--source', grouped_source,
    '--source-sha256', sha(grouped_source), '--output', out / 'tapered')
blend = out / 'art/characters_child.blend'
shutil.copy2(out / 'tapered/characters_child.blend', blend)
final = witness('candidate_native', blend)
assert final['native_signature'] == CONTRACT['candidate_native_signature']
protected_native(initial, final, owned)
protected_native(grouped, final, {'Hair_Bob_Cap'})
a = grouped['facts']['owned']['Hair_Bob_Cap']['mesh_positions']
b = final['facts']['owned']['Hair_Bob_Cap']['mesh_positions']
assert len(a) == len(b) == 1920
changed = [i for i, (x, y) in enumerate(zip(a, b)) if x != y]
assert changed == CONTRACT['scope']['cap_taper_changed_indices']
assert all(x == y for x, y in zip(a, b) if x[2] >= 1.05)
protection = {'baseline_signature': initial['native_signature'],
              'grouped_signature': grouped['native_signature'],
              'final_signature': final['native_signature'],
              'protected_objects_exact_to_baseline': 337,
              'protected_objects_exact_to_grouped': 361,
              'owned_nonposition_channels_exact': True, 'materials_exact': True,
              'startup_scene_exact': True, 'taper_changed_cap_vertices': len(changed),
              'taper_upper_cap_z_ge_1_05_exact': True}
(out / 'evidence/native_protection.json').write_text(json.dumps(protection, indent=2) + '\n')
for stem in CONTRACT['baseline_glbs']:
    run('export_' + stem, 'export_variant.py', '--source', blend,
        '--source-sha256', sha(blend), '--output-root', out / 'raw_exports', '--variant', stem)
    raw = out / 'raw_exports' / (stem + '.glb')
    target = out / 'assets/models' / (stem + '.glb')
    assert sha(raw) == CONTRACT['raw_glbs'][stem], 'Raw export differs from reviewed raw: ' + stem
    original = base / (stem + '.glb')
    if stem == 'character_child_lod':
        transfer(original, raw, target, out / 'evidence/standard_lod_transfer.json', owned)
    else:
        shutil.copy2(raw, target)
    proof = verify(original, raw, target, owned)
    receipt['exports'].append(proof)
    assert sha(target) == CONTRACT['candidate_glbs'][stem], 'Final differs from reviewed GLB: ' + stem
    save_receipt()
assert sha(source) == CONTRACT['source_sha256']
for stem, pin in CONTRACT['baseline_glbs'].items():
    assert sha(base / (stem + '.glb')) == pin
assert all(sha(HERE / name) == pin for name, pin in receipt['script_pins'].items())
receipt.update(status='pass', input_and_scripts_unchanged=True,
               output_source_sha256=sha(blend), output_glbs=CONTRACT['candidate_glbs'],
               native_protection=protection)
save_receipt()
print('CHILD_BOB_REPRODUCTION_OK 4 exact GLBs; 337 protected native objects; 314 protected exported meshes per variant')
