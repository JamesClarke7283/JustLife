"""Census open shells (boundary edges) and solidify status across a character.

    blender -b --python tools/census_open_shells.py -- --source art/characters.blend

A mesh with boundary edges and no SOLIDIFY modifier renders as a
zero-thickness sheet. Read-only.
"""
import argparse
import pathlib
import sys

import bpy

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--min-edges', type=int, default=1)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

bpy.ops.wm.open_mainfile(filepath=str(args.source))


def boundary_edges(me):
    used = {}
    for poly in me.polygons:
        for key in poly.edge_keys:
            used[key] = used.get(key, 0) + 1
    return sum(1 for count in used.values() if count == 1)


rows = []
for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    open_edges = boundary_edges(obj.data)
    if open_edges < args.min_edges:
        continue
    solidify = any(m.type == 'SOLIDIFY' for m in obj.modifiers)
    keys = len(obj.data.shape_keys.key_blocks) if obj.data.shape_keys else 0
    rows.append((obj.name, open_edges, solidify, keys, len(obj.data.vertices),
                 obj.data.materials[0].name if obj.data.materials else '-'))

rows.sort(key=lambda r: -r[1])
print(f'{"object":40s} {"open":>6s} {"solid":>6s} {"keys":>5s} {"verts":>6s} material')
for name, open_edges, solidify, keys, verts, material in rows:
    print(f'{name:40s} {open_edges:6d} {str(solidify):>6s} {keys:5d} {verts:6d} {material}')

unsealed = [r for r in rows if not r[2]]
print(f'\nopen-shell meshes: {len(rows)}; without SOLIDIFY: {len(unsealed)}')
for name, open_edges, _, keys, verts, material in unsealed:
    print(f'  UNSHIELDED {name}: {open_edges} boundary edges, {verts} verts, {material}')
