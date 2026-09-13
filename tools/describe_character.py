"""Inventory the authored objects of a character blend for art work.

    blender -b --python tools/describe_character.py -- --source art/characters.blend

Prints one line per object: name, vertex/face counts, material, modifiers and
world-space bounds. Read-only; nothing is saved.
"""
import argparse
import pathlib
import sys

import bpy

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--filter', default='', help='substring filter on object name')
parser.add_argument('--sort', choices=['name', 'verts'], default='name')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

bpy.ops.wm.open_mainfile(filepath=str(args.source))

rows = []
for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    if args.filter and args.filter.lower() not in obj.name.lower():
        continue
    mesh = obj.data
    material = mesh.materials[0].name if mesh.materials else '-'
    modifiers = ','.join(f'{m.type}' for m in obj.modifiers) or '-'
    corners = [obj.matrix_world @ v.co for v in mesh.vertices]
    if corners:
        xs = [c.x for c in corners]
        ys = [c.y for c in corners]
        zs = [c.z for c in corners]
        bounds = (f'x[{min(xs):+.3f},{max(xs):+.3f}] '
                  f'y[{min(ys):+.3f},{max(ys):+.3f}] '
                  f'z[{min(zs):+.3f},{max(zs):+.3f}]')
    else:
        bounds = 'empty'
    rows.append((obj.name, len(mesh.vertices), len(mesh.polygons), material,
                 modifiers, bounds, len(mesh.shape_keys.key_blocks) if mesh.shape_keys else 0))

if args.sort == 'verts':
    rows.sort(key=lambda r: -r[1])
else:
    rows.sort(key=lambda r: r[0])

print(f'{"object":42s} {"verts":>6s} {"faces":>6s} {"keys":>4s} {"material":16s} {"modifiers":22s} bounds')
for name, verts, faces, material, modifiers, bounds, keys in rows:
    print(f'{name:42s} {verts:6d} {faces:6d} {keys:4d} {material:16s} {modifiers:22s} {bounds}')
print('TOTAL_MESHES', len(rows))
print('TOTAL_VERTS', sum(r[1] for r in rows))
