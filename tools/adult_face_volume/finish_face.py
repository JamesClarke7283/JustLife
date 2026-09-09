"""Apply the reviewed shared Smile and measured neutral mouth-anchor transport."""
import argparse, json, sys
from pathlib import Path
import bpy
from mathutils import Vector

P = Path(__file__).resolve().parent
sys.path.insert(0, str(P.parent / 'adult_eyes'))
import source_facts as witness
sys.path.insert(0, str(P))
import smile_field

parser = argparse.ArgumentParser()
parser.add_argument('--spec', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
spec = json.loads(args.spec.read_text())
source = Path(spec['source'])
assert witness.sha(source) == spec['source_sha256']
out = args.output.resolve()
assert not out.exists()
(out / 'art').mkdir(parents=True)
bpy.ops.wm.open_mainfile(filepath=str(source))
bpy.context.view_layer.update()
witness.OWNED = set(smile_field.OWNED)
before = witness.objects()
anchor = Vector((0, .005, 1.458))
scale = .91
report = {'source_sha256': spec['source_sha256'],
          'spec_sha256': witness.sha(args.spec),
          'field_sha256': witness.sha(P / 'smile_field.py'),
          'smile_parameters': spec['smile_parameters'],
          'changes': {}, 'failures': []}
for name in sorted(smile_field.OWNED):
    obj = bpy.data.objects[name]
    keys = obj.data.shape_keys.key_blocks
    key, basis = keys['Smile'], keys['Basis']
    assert key.relative_key == basis
    inverse = obj.matrix_world.to_3x3().inverted()
    changed, peak = [], 0.0
    for index, point in enumerate(basis.data):
        authored = anchor + (obj.matrix_world @ point.co - anchor) / scale
        delta = inverse @ (Vector(smile_field.smile_delta(authored, **spec['smile_parameters'])) * scale)
        old = key.data[index].co.copy()
        key.data[index].co = point.co + delta
        if old != key.data[index].co:
            changed.append(index)
        peak = max(peak, delta.length)
    obj.data.update()
    report['changes'][name] = {'changed': changed, 'max_local_delta': peak}

# Transport the existing neutral seam contact offset using the same native
# ring vertices, in Head-local coordinates, rather than a guessed face depth.
root = bpy.data.objects['Character']
assert list(root['mouth_anchor']) == spec['old_mouth_anchor']
seam = bpy.data.objects['Lips_Smile_seam']
head_inverse = bpy.data.objects['Head'].matrix_world.inverted()
points = [head_inverse @ (seam.matrix_world @ seam.data.shape_keys.key_blocks['Basis'].data[i].co)
          for i in spec['native_seam_ring_ids']]
center = sum(points, Vector()) / len(points)
center_godot = [center.x, center.z, -center.y]
assert max(abs(a - b) for a, b in zip(center_godot, spec['new_seam_center_head_godot'])) < 1e-7
unrounded = [a + n - o for a, n, o in zip(spec['old_mouth_anchor'], center_godot,
                                       spec['old_seam_center_head_godot'])]
new_anchor = [round(v, 6) for v in unrounded]
assert new_anchor == spec['new_mouth_anchor']
root['mouth_anchor'] = new_anchor
report['mouth_anchor'] = {'old': spec['old_mouth_anchor'], 'new': new_anchor,
                         'native_seam_ring_ids': spec['native_seam_ring_ids'],
                         'actual_new_seam_center_head_godot': center_godot,
                         'unrounded': unrounded}

bpy.context.view_layer.update()
after = witness.objects()
assert before['objects'].keys() == after['objects'].keys()
for name, facts in before['objects'].items():
    for key, value in facts.items():
        if name in smile_field.OWNED and key == 'geometry_sha256':
            continue
        if name == 'Character' and key == 'props':
            expected = dict(value)
            expected['mouth_anchor'] = new_anchor
            assert after['objects'][name][key] == expected
            continue
        if after['objects'][name][key] != value:
            report['failures'].append([name, key])
for name in smile_field.OWNED:
    for key, value in before['owned'][name].items():
        if key == 'keys':
            for shape, coords in value.items():
                if shape != 'Smile' and after['owned'][name]['keys'][shape] != coords:
                    report['failures'].append([name, 'keys', shape])
        elif after['owned'][name][key] != value:
            report['failures'].append([name, key])
(out / 'finish_report.json').write_text(json.dumps(report, indent=2) + '\n')
assert not report['failures'], report['failures']
(out / 'object_facts.json').write_text(json.dumps({'before': before['objects'], 'after': after['objects']}, indent=2) + '\n')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'art/characters.blend'))
assert witness.sha(source) == spec['source_sha256']
print('FACE_FINISHED', json.dumps({'smile_meshes': len(report['changes']), 'mouth_anchor': new_anchor}))
