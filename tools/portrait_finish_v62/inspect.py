"""Measure local surface defects in the integrated head without editing it."""
import argparse
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
head = bpy.data.objects['Skin_Head_continuous']
keys = head.data.shape_keys.key_blocks
ps = [head.matrix_world @ v.co for v in keys['Basis'].data]
kd = KDTree(len(ps))
for i, p in enumerate(ps):
    kd.insert(p, i)
kd.balance()
features = {}
for prefix in ('Eyes_Sclera', 'Lips_'):
    points = [o.matrix_world @ v.co for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(prefix)
              for v in (o.data.shape_keys.key_blocks['Basis'].data if o.data.shape_keys else o.data.vertices)]
    features[prefix] = {'min': [min(p[i] for p in points) for i in range(3)],
                        'max': [max(p[i] for p in points) for i in range(3)]}
residuals = []
for i, p in enumerate(ps):
    if p.y > -.018 or p.z > features['Eyes_Sclera']['min'][2] or abs(p.x) > .085:
        continue
    neighbors = [(q, j, d) for q, j, d in kd.find_range(p, .008) if j != i]
    if len(neighbors) < 12:
        continue
    points = np.asarray([tuple(q - p) for q, _, _ in neighbors])
    weights = np.exp(-np.sum(points * points, axis=1) / .006**2)
    _, _, axes = np.linalg.svd(points * np.sqrt(weights[:, None]), full_matrices=False)
    local = points @ axes.T
    u, v, height = local.T
    design = np.column_stack((np.ones(len(u)), u, v, u * u, u * v, v * v))
    fit = np.linalg.lstsq(design * np.sqrt(weights[:, None]), height * np.sqrt(weights), rcond=None)[0]
    residuals.append({'vertex': i, 'world': list(p), 'residual_m': float(fit[0]), 'neighbors': len(neighbors)})
report = {'source': str(args.source), 'head_bounds': {'min': [min(p[i] for p in ps) for i in range(3)],
                                                   'max': [max(p[i] for p in ps) for i in range(3)]},
          'feature_bounds': features, 'highest_local_fit_residuals': sorted(residuals, key=lambda p: abs(p['residual_m']), reverse=True)[:60],
          'keys': list(keys.keys()), 'orbit_shared_count': [len(head[k]) for k in ('orbit_shared_0', 'orbit_shared_1')]}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('SURFACE_INSPECTION', json.dumps(report))
