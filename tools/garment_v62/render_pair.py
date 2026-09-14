"""One sequential native job for a verified matched garment image pair."""
import argparse
import json
from pathlib import Path
import runpy
import sys

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True, help='Fresh output stem, without extension')
ap.add_argument('--outfit', choices=('Tee', 'Casual'), default='Tee')
ap.add_argument('--pose', default='rest')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
script = Path(__file__).with_name('render.py')
receipts = {}
for label, source in [('baseline', args.baseline), ('candidate', args.candidate)]:
    output = args.output.with_name(args.output.name + '_' + label).with_suffix('.png')
    assert not output.with_suffix('.json').exists(), 'Refusing to replace a prior image receipt'
    assert not output.with_stem(output.stem + '_front').exists()
    assert not output.with_stem(output.stem + '_three_quarter').exists()
    sys.argv = [str(script), '--', '--source', str(source), '--output', str(output),
                '--outfit', args.outfit, '--pose', args.pose, '--paired']
    runpy.run_path(str(script), run_name='__main__')
    receipts[label] = json.loads(output.with_suffix('.json').read_text())

base, candidate = receipts['baseline'], receipts['candidate']
settings = ('outfit', 'pose', 'engine', 'samples', 'resolution', 'view_transform',
            'camera_ortho_scale', 'lights', 'world_color', 'world_strength',
            'diagnostic_cloth_color', 'diagnostic_cloth_roughness')
for key in settings:
    assert base[key] == candidate[key], ('Mismatched rendering setting', key)
assert len(base['renders']) == len(candidate['renders']) == 2
for first, second in zip(base['renders'], candidate['renders']):
    for key in ('angle_degrees', 'camera_position', 'camera_euler'):
        assert first[key] == second[key], ('Mismatched view', key)
receipt = {'matched_settings_verified': True, 'source_files_unchanged':
           base['source_unchanged'] and candidate['source_unchanged'],
           'baseline': base, 'candidate': candidate}
args.output.with_suffix('.json').write_text(json.dumps(receipt, indent=2) + '\n')
print('GARMENT_MATCHED_PAIR_COMPLETE', args.output, flush=True)
