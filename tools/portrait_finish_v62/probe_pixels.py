"""Map diagnostic image pixels to actual neutral head triangles."""
import argparse
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
for o in bpy.data.objects:
    if o.type == 'MESH' and o.data.shape_keys:
        for key in o.data.shape_keys.key_blocks:
            key.value = 0
bpy.context.view_layer.update()
head = bpy.data.objects['Skin_Head_continuous'].evaluated_get(bpy.context.evaluated_depsgraph_get())
points = [head.matrix_world @ v.co for v in head.data.vertices]
head.data.calc_loop_triangles()
tris = [tuple(t.vertices) for t in head.data.loop_triangles]
bvh = BVHTree.FromPolygons(points, tris, all_triangles=True)
low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
focus = Vector((0, -.065, (low.z + high.z) * .5 - .012))
camera = focus + Vector((math.sin(math.radians(25)) * 2.4, -math.cos(math.radians(25)) * 2.4, .02))
rotation = (focus - camera).to_track_quat('-Z', 'Y')
right, up, forward = (rotation @ Vector(v) for v in ((1, 0, 0), (0, 1, 0), (0, 0, -1)))
result = []
for x, y in ((239, 389), (244, 396), (246, 400), (228, 382), (248, 382), (335, 306), (342, 300)):
    origin = camera + right * ((x + .5) / 512 - .5) * .30 + up * (.5 - (y + .5) / 512) * .30
    p, normal, index, _ = bvh.ray_cast(origin, forward, 5)
    if p is not None:
        ids = tris[index]
        result.append({'pixel': [x, y], 'world': list(p), 'normal': list(normal), 'triangle': list(ids),
                       'vertices': [list(points[i]) for i in ids]})
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(result, indent=2) + '\n')
print('DIAGNOSTIC_PIXEL_SURFACES', json.dumps(result))
