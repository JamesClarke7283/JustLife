"""Read-only cloth/rig/trim measurements before choosing a shoulder correction."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import OWNED, bounds, rig_anchors, trim_objects, trim_tree, world_points

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
report = {'source': str(args.source.resolve()),
          'sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
          'anchors': {k: list(v) for k, v in rig_anchors().items()}, 'shirts': {}, 'trims': {}, 'skin': {}}
tree = trim_tree()
for name in OWNED:
    obj = bpy.data.objects[name]
    ps = world_points(obj)
    evaluated = world_points(obj, True)
    row = {'vertices': len(ps), 'shape_keys': list(obj.data.shape_keys.key_blocks.keys()) if obj.data.shape_keys else [],
           'bounds': bounds(ps), 'evaluated_bounds': bounds(evaluated),
           'max_rest_evaluation_change_m': max((p - q).length for p, q in zip(ps, evaluated)),
           'modifiers': [(m.name, m.type) for m in obj.modifiers],
           'within_9mm_trim': sum(tree.find(p)[2] <= .009 for p in ps),
           'shoulder_columns': [], 'upper_cross_sections': []}
    for ix in range(5, 29):
        x = ix * .01
        near = [p for p in ps if abs(abs(p.x) - x) < .004]
        if near:
            top = max(p.z for p in near)
            upper = [p for p in near if p.z > top - .010]
            row['shoulder_columns'].append({'abs_x': x, 'highest_z': top,
                                             'upper_y_min': min(p.y for p in upper),
                                             'upper_y_max': max(p.y for p in upper)})
    for iz in range(120, 141, 2):
        z = iz * .01
        near = [p for p in ps if abs(p.z - z) < .004]
        if near:
            row['upper_cross_sections'].append({'z': z, 'bounds': bounds(near)})
    report['shirts'][name] = row
for obj in trim_objects():
    report['trims'][obj.name] = bounds(world_points(obj))
for obj in bpy.data.objects:
    if obj.type == 'MESH' and obj.name.startswith(('Skin_Arm_continuous', 'Skin_Upperarm_fill')):
        ps = world_points(obj, True)
        report['skin'][obj.name] = {'vertices': len(ps), 'bounds': bounds(ps)}
assert hashlib.sha256(args.source.read_bytes()).hexdigest() == report['sha256']
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('GARMENT_INSPECTED', json.dumps(report))
