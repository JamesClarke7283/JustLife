"""Read the five immutable Bob-shaping inputs from pinned local Git history.

This avoids duplicating the former production GLBs in the source tree. A checkout
with the pinned commit's objects is required; this command does not fetch or edit
the repository. Pass a new output directory outside any existing source input.
"""
import argparse, hashlib, json, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = json.loads((HERE / 'native_contract.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repository', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repository = args.repository.resolve()
output = args.output.resolve()
assert not output.exists(), 'Choose a new output directory'
pins = {'art/characters_child.blend': CONTRACT['source_sha256']}
pins.update({'assets/models/' + name + '.glb': pin
             for name, pin in CONTRACT['baseline_glbs'].items()})
payloads = {}
for relative, expected in pins.items():
    result = subprocess.run(
        ['git', '-C', str(repository), 'show',
         CONTRACT['input_commit'] + ':' + relative],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert hashlib.sha256(result.stdout).hexdigest() == expected, relative
    payloads[relative] = result.stdout
for relative, content in payloads.items():
    target = output / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
(output / 'input_receipt.json').write_text(json.dumps({
    'commit': CONTRACT['input_commit'], 'pins': pins,
    'git_invocation_read_only': True, 'network_used': False
}, indent=2) + '\n')
print('CHILD_BOB_INPUTS_EXACT', len(pins))
