"""Measure the hand's proportions against human reference ratios.

    blender -b --python tools/probe_hand_proportions.py -- --source art/characters.blend

The hand reads stubby: the digits look short against the palm and the palm reads
as a flat slab. This measures the actual numbers so a change can be judged
against them, and compares the palm's thickness against its width.

Hand orientation: the arm hangs down its own Z axis, hand at low Z, fingers
extending further down. The palm's width runs along X and its thickness along Y.
"""
import argparse
import pathlib
import sys

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--side', default='L', choices=['L', 'R'])
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

bpy.ops.wm.open_mainfile(filepath=str(args.source))
name = f'Skin_Arm_continuous_{args.side}'
obj = bpy.data.objects[name]
mtx = obj.matrix_world
pts = [mtx @ v.co for v in obj.data.vertices]
sign = -1.0 if args.side == 'L' else 1.0

# The hand occupies the outermost part of the arm. Find the wrist as the
# narrowest cross-section near the hand end, which is where the forearm meets
# the palm.
zs = sorted(p.z for p in pts)
z_lo, z_hi = zs[0], zs[-1]
band = [p for p in pts if p.z <= z_lo + 0.20]


def cross_width(z0, z1):
    sel = [p for p in pts if z0 <= p.z < z1]
    if len(sel) < 4:
        return None
    return (max(p.x for p in sel) - min(p.x for p in sel),
            max(p.y for p in sel) - min(p.y for p in sel), len(sel))


print(f'{name}: {len(pts)} verts, z range [{z_lo:+.4f},{z_hi:+.4f}]')
print('  cross-sections from the fingertips upward (1 mm steps):')
print(f'  {"z":>8s} {"width X":>9s} {"thick Y":>9s} {"aspect":>7s} {"verts":>6s}')
step = 0.004
z = z_lo
rows = []
while z < z_lo + 0.20:
    got = cross_width(z, z + step)
    if got:
        w, th, n = got
        rows.append((z, w, th, w / th if th > 1e-6 else 0.0, n))
    z += step
for z, w, th, aspect, n in rows:
    print(f'  {z:8.4f} {w * 1000:8.1f}m {th * 1000:8.1f}m {aspect:7.2f} {n:6d}')

if rows:
    widest = max(rows, key=lambda r: r[1])
    thinnest = min(rows[:max(1, len(rows) // 2)], key=lambda r: r[1])
    print(f'  palm width  = {widest[1] * 1000:.1f} mm at z={widest[0]:+.4f}')
    print(f'  wrist width = {thinnest[1] * 1000:.1f} mm at z={thinnest[0]:+.4f}')
    print(f'  palm thickness = {widest[2] * 1000:.1f} mm (aspect {widest[3]:.2f})')
    print(f'  hand length below the wrist = {(widest[0] - z_lo) * 1000:.1f} mm')
    print('  human reference: a hand is ~100 mm long and ~85 mm wide with a')
    print('  palm roughly 30 mm thick, so width/thickness near 2.8 and a hand')
    print('  length close to its width.')
