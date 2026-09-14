"""Measure the hand: does it carry separated digits, or is it a fused paddle?

    blender -b --python tools/probe_hand_shape.py -- --source art/characters.blend

The arm is authored as loose parts (palm, four fingers, thumb, tips) and then
fused into one continuous `Skin_Arm_continuous_*` surface, so the export has no
node named "Finger" whether or not the digits survived. Whether the finished
hand reads as a hand is therefore a *geometric* question: cut the hand across
its width and count how many separate blobs the cross-section contains. One blob
down the whole hand is a mitten; several are real digits.

The arm hangs down its own Z axis (shoulder at high Z, hand at low Z), so the
slices run along Z and the blobs are counted in the XY plane.
"""
import argparse
import pathlib
import sys

import bpy

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--side', default='L')
parser.add_argument('--slices', type=int, default=10)
parser.add_argument('--gap', type=float, default=0.004,
                    help='XY distance below which cross-section points join one blob')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

bpy.ops.wm.open_mainfile(filepath=str(args.source))

name = f'Skin_Arm_continuous_{args.side}'
obj = bpy.data.objects.get(name)
assert obj is not None, f'{name} not found'
mtx = obj.matrix_world
points = [mtx @ v.co for v in obj.data.vertices]

# Locate the hand from the authored sub-parts rather than guessing: the palm and
# fingers are named objects in the source, and their extents bound the hand.
marks = []
for candidate in ('Skin_Palm_' + args.side, 'Skin_Finger_' + args.side + '0',
                  'Skin_Finger_' + args.side + '1', 'Skin_Finger_' + args.side + '2',
                  'Skin_Finger_' + args.side + '3', 'Skin_Thumb_' + args.side):
    child = bpy.data.objects.get(candidate)
    if child is not None:
        marks.extend(mtx @ v.co for v in child.data.vertices)
if marks:
    z_lo = min(p.z for p in marks)
    z_hi = max(p.z for p in marks)
    print(f'hand bounds from authored parts: z[{z_lo:+.4f},{z_hi:+.4f}] '
          f'({z_hi - z_lo:.4f} m tall)')
else:
    zs = [p.z for p in points]
    z_lo, z_hi = min(zs), min(zs) + (max(zs) - min(zs)) * 0.20
    print(f'hand bounds from the outer 20%: z[{z_lo:+.4f},{z_hi:+.4f}]')

hand = [p for p in points if z_lo - 0.002 <= p.z <= z_hi + 0.002]
print(f'{name}: {len(points)} verts total, {len(hand)} in the hand band')


def blobs(cell_points, gap):
    """Greedy single-link clustering of 2D points with a distance threshold."""
    parent = list(range(len(cell_points)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    g2 = gap * gap
    for i in range(len(cell_points)):
        ax, ay = cell_points[i]
        for j in range(i + 1, len(cell_points)):
            bx, by = cell_points[j]
            dx, dy = ax - bx, ay - by
            if dx * dx + dy * dy <= g2:
                ra, rb = find(i), find(j)
                if ra != rb:
                    parent[rb] = ra
    groups = {}
    for i in range(len(cell_points)):
        groups.setdefault(find(i), []).append(cell_points[i])
    return list(groups.values())


print(f'  slices along Z, blobs clustered in XY with a {args.gap * 1000:.0f} mm gap')
print(f'  {"z":>8s} {"verts":>6s} {"blobs":>6s}  {"blob widths (mm)":s}')
step = (z_hi - z_lo) / max(1, args.slices)
widest_counts = []
for i in range(args.slices):
    a = z_lo + i * step
    b = a + step
    band = [(p.x, p.y) for p in hand if a <= p.z < b]
    if len(band) < 3:
        continue
    found = blobs(band, args.gap)
    widths = []
    for group in found:
        xs = [p[0] for p in group]
        ys = [p[1] for p in group]
        widths.append(max(max(xs) - min(xs), max(ys) - min(ys)) * 1000.0)
    widths.sort(reverse=True)
    widest_counts.append(len(found))
    print(f'  {a + step / 2:8.4f} {len(band):6d} {len(found):6d}  '
          + ' '.join(f'{w:.1f}' for w in widths[:6]))

if widest_counts:
    print(f'  max blobs at any slice = {max(widest_counts)} '
          f'(a mitten would stay at 1; four fingers plus a thumb would reach 5 at the fingertips)')
