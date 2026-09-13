"""Measure how much of the eyeball the upper lid actually occludes.

    blender -b --python tools/probe_eye_coverage.py -- --source art/characters.blend

For each eye, walks up the eyeball in height bands and compares the frontmost
(more negative Y) point of the sclera with the frontmost point of the skin
around it. Where the sclera is in front of the lid, the eyeball pokes through
the eyelid and the whole ball reads as visible — the "googly" look. Read-only.
"""
import argparse
import pathlib
import sys

import bpy

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--bands', type=int, default=14)
parser.add_argument('--side', default='both', choices=['both', 'left', 'right'])
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

bpy.ops.wm.open_mainfile(filepath=str(args.source))

SKIN_EYE = ('Skin_Upper_lid', 'Skin_Lower', 'Skin_Eye', 'Skin_Head_continuous')
SCLERA = ('Eyes_Sclera',)


def cloud(prefixes):
    pts = []
    for obj in bpy.data.objects:
        if obj.type != 'MESH':
            continue
        if not any(obj.name.startswith(p) for p in prefixes):
            continue
        m = obj.matrix_world
        pts.extend([(m @ v.co, obj.name) for v in obj.data.vertices])
    return pts


sclera = cloud(SCLERA)
skin = cloud(SKIN_EYE)
print(f'sclera verts={len(sclera)}  eye-area skin verts={len(skin)}')

for side, sign in (('left', -1.0), ('right', 1.0)):
    if args.side != 'both' and args.side != side:
        continue
    scl = [p for p, n in sclera if (p.x < 0) == (sign < 0)]
    if not scl:
        print(f'{side}: no sclera')
        continue
    xs = [p.x for p in scl]
    centre_x = (min(xs) + max(xs)) / 2.0
    zs = [p.z for p in scl]
    z_lo, z_hi = min(zs), max(zs)
    near = [p for p, n in skin if abs(p.x - centre_x) < 0.020]

    print(f'\n{side}: centre x={centre_x:+.4f}  eye z=[{z_lo:.4f},{z_hi:.4f}]  '
          f'nearby skin verts={len(near)}')
    print(f'  {"z":>8s} {"sclera front y":>15s} {"lid front y":>13s} {"gap":>9s}  verdict')
    step = (z_hi - z_lo) / args.bands
    covered = 0
    exposed = 0
    for i in range(args.bands):
        z0 = z_lo + i * step
        z1 = z0 + step
        band_scl = [p for p in scl if z0 <= p.z < z1]
        band_lid = [p for p in near if z0 <= p.z < z1]
        if not band_scl:
            continue
        scl_front = min(p.y for p in band_scl)
        lid_front = min((p.y for p in band_lid), default=None)
        if lid_front is None:
            print(f'  {z0 + step / 2:8.4f} {scl_front:15.4f} {"none":>13s} {"-":>9s}  exposed (no skin)')
            exposed += 1
            continue
        gap = scl_front - lid_front  # negative => sclera is in front of the lid
        verdict = 'EXPOSED' if gap < 0 else 'covered'
        if gap < 0:
            exposed += 1
        else:
            covered += 1
        print(f'  {z0 + step / 2:8.4f} {scl_front:15.4f} {lid_front:13.4f} {gap:9.4f}  {verdict}')
    print(f'  bands covered={covered} exposed={exposed}')
