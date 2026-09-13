"""Measure hair-lock cross-section shape (roundness vs flat plank).

    blender -b --python tools/probe_hair_locks.py -- --source art/characters.blend

For every `Hair_*_Lock*` mesh, clusters vertices along the lock's long axis and
reports the median cross-section width:depth ratio through principal-component
analysis of the whole mesh plus per-ring extents. Read-only.
"""
import argparse
import pathlib
import statistics
import sys

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--style', default='Bob')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

bpy.ops.wm.open_mainfile(filepath=str(args.source))

needle = f'Hair_{args.style}_Lock'
locks = [o for o in bpy.data.objects
         if o.type == 'MESH' and o.name.startswith(needle)]
print(f'{len(locks)} locks matching {needle}*')

rows = []
for obj in sorted(locks, key=lambda o: o.name):
    mesh = obj.data
    points = [obj.matrix_world @ v.co for v in mesh.vertices]
    centre = Vector((0.0, 0.0, 0.0))
    for p in points:
        centre += p
    centre /= len(points)

    # Principal axes via power iteration on the covariance matrix.
    cov = [[0.0] * 3 for _ in range(3)]
    for p in points:
        d = p - centre
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]
    axes = []
    remaining = [Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))]
    work = [row[:] for row in cov]
    for _ in range(3):
        v = Vector((1.0, 0.7, 0.3)).normalized()
        for _ in range(80):
            nv = Vector((sum(work[0][k] * v[k] for k in range(3)),
                         sum(work[1][k] * v[k] for k in range(3)),
                         sum(work[2][k] * v[k] for k in range(3))))
            if nv.length < 1e-12:
                break
            v = nv.normalized()
        axes.append(v)
        lam = sum(sum(work[i][k] * v[k] for k in range(3)) * v[i] for i in range(3))
        for i in range(3):
            for j in range(3):
                work[i][j] -= lam * v[i] * v[j]
    extents = []
    for axis in axes:
        vals = [(p - centre).dot(axis) for p in points]
        extents.append(max(vals) - min(vals))
    long_axis = max(extents)
    others = sorted(extents)[:2]
    ratio = others[0] / others[1] if others[1] > 1e-9 else 0.0
    rows.append((obj.name, len(mesh.vertices), long_axis, others[1], others[0], ratio))

print(f'{"lock":26s} {"verts":>5s} {"length":>8s} {"width":>8s} {"depth":>8s} {"depth/width":>11s}')
for name, verts, length, width, depth, ratio in rows:
    print(f'{name:26s} {verts:5d} {length:8.4f} {width:8.4f} {depth:8.4f} {ratio:11.3f}')

if rows:
    ratios = [r[5] for r in rows]
    print(f'median depth/width = {statistics.median(ratios):.3f}  '
          f'(1.0 = round rope, near 0 = flat plank)')
