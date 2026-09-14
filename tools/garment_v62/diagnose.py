"""Read-only localized shoulder failure measurements, without full snapshots."""
import argparse
import json
from pathlib import Path
import sys
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import rig_anchors, world_points

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
name = 'Outfit_Tee_Shirt'
bpy.ops.wm.open_mainfile(filepath=str(args.baseline.resolve()))
bpy.context.view_layer.update()
obj = bpy.data.objects[name]
obj.data.calc_loop_triangles()
ids = np.array([t.vertices[:] for t in obj.data.loop_triangles], dtype=np.int32)
a = np.array([p[:] for p in world_points(obj, True)])
skin = []
for o in bpy.data.objects:
    if o.type == 'MESH' and o.name.startswith('Skin_Arm_continuous'):
        skin.extend([p for p in world_points(o, True) if 1.182 < p.z < 1.367])
bpy.ops.wm.open_mainfile(filepath=str(args.candidate.resolve()))
bpy.context.view_layer.update()
b = np.array([p[:] for p in world_points(bpy.data.objects[name], True)])
n0 = np.cross(a[ids[:, 1]] - a[ids[:, 0]], a[ids[:, 2]] - a[ids[:, 0]])
n1 = np.cross(b[ids[:, 1]] - b[ids[:, 0]], b[ids[:, 2]] - b[ids[:, 0]])
flip_ids = np.flatnonzero(np.sum(n0 * n1, axis=1) < 0)
tree0 = BVHTree.FromPolygons([Vector(p) for p in a], ids.tolist(), all_triangles=True)
tree1 = BVHTree.FromPolygons([Vector(p) for p in b], ids.tolist(), all_triangles=True)
exposed = []
for p in skin:
    hit0, normal0, _, _ = tree0.find_nearest(p)
    hit1, normal1, face, _ = tree1.find_nearest(p)
    d0, d1 = (p - hit0).dot(normal0), (p - hit1).dot(normal1)
    if d1 > .0005 and d1 > max(d0, 0.) + .0005:
        exposed.append({'skin': list(p), 'source_signed': d0, 'candidate_signed': d1,
                        'face': face, 'shirt_vertices': ids[face].tolist(),
                        'shirt_source': a[ids[face]].tolist(),
                        'shirt_candidate': b[ids[face]].tolist()})
report = {'baseline': str(args.baseline), 'candidate': str(args.candidate),
          'flipped_triangles': [{'triangle': int(i), 'vertices': ids[i].tolist(),
             'source': a[ids[i]].tolist(), 'candidate': b[ids[i]].tolist(),
             'source_area': float(np.linalg.norm(n0[i]) * .5),
             'candidate_area': float(np.linalg.norm(n1[i]) * .5),
             'normal_cosine': float(n0[i].dot(n1[i]) / np.linalg.norm(n0[i]) / np.linalg.norm(n1[i]))}
             for i in flip_ids], 'new_exposure': exposed}
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('GARMENT_DIAGNOSED', len(flip_ids), 'flips', len(exposed), 'exposure samples', flush=True)
