"""Give every mesh in one candidate Blender source a planar UV layer.

The released baby generator calls its own `ensure_uvs()` before export, which
projection-maps any mesh that shipped without a UV layer. Candidate sources
authored through the portrait/identity tool chain skip that step, so a mesh
that begins life without UVs (the infant brow ribbons) reaches the exporter
bare and Godot then reports "UVs are required to generate tangents" on import.

This tool applies the same projection rule to a candidate: it only ever adds a
UV layer to meshes that have none, and it never touches a mesh that already
has UVs, so re-running it is idempotent and every existing UV is preserved
byte for byte. No other object data, shape key, material or transform changes.

    blender -b --threads 2 --python tools/ensure_candidate_uvs.py -- \
      --source <candidate.blend> --output <new.blend> --report <report.json>
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve()
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))

added = {}
for ob in bpy.data.objects:
    if ob.type != 'MESH' or ob.data.uv_layers:
        continue
    layer = ob.data.uv_layers.new(name='SurfaceUV')
    for poly in ob.data.polygons:
        normal = poly.normal
        drop = max(range(3), key=lambda axis: abs(normal[axis]))
        axes = [axis for axis in range(3) if axis != drop]
        for loop_index in poly.loop_indices:
            point = ob.data.vertices[ob.data.loops[loop_index].vertex_index].co
            layer.data[loop_index].uv = ((point[axes[0]] + .5) * .5, (point[axes[1]] + .5) * .5)
    added[ob.name] = len(ob.data.polygons)

# Re-check: no mesh may leave this tool without a UV layer.
remaining = [o.name for o in bpy.data.objects if o.type == 'MESH' and not o.data.uv_layers]
assert not remaining, ('Meshes still lack UVs', remaining)

bpy.context.preferences.filepaths.save_version = 0
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
report = {'source': str(args.source.resolve()),
          'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
          'output': str(args.output.resolve()),
          'uv_layers_added': added,
          'policy': 'Only meshes without a UV layer are projected; existing UVs are untouched.',
          'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest()}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('ENSURE_UVS_DONE', json.dumps(report))
