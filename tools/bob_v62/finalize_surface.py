"""Normalize the reviewed Bob material graph for lossless standard glTF export.

This migration only converts a legacy Multiply node to the supported Mix Color
equivalent and clamps image edges. It does not change geometry or appearance.
Fresh surface.py runs already create this final material graph.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import bpy

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--input', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--')+1:])
bpy.ops.wm.open_mainfile(filepath=str(a.input.resolve()))
m = bpy.data.materials['Hair_Bob_Surface']
nodes, links = m.node_tree.nodes, m.node_tree.links
old = [n for n in nodes if n.type == 'MIX_RGB']
assert len(old) == 1
old = old[0]
assert old.blend_type == 'MULTIPLY' and old.inputs[0].default_value == 1.0
texture = old.inputs[1].links[0].from_socket
color = tuple(old.inputs[2].default_value)
target = old.outputs[0].links[0].to_socket
new = nodes.new('ShaderNodeMix'); new.data_type = 'RGBA'; new.blend_type = 'MULTIPLY'
new.inputs[0].default_value = 1.0
aa = next(s for s in new.inputs if s.identifier == 'A_Color')
bb = next(s for s in new.inputs if s.identifier == 'B_Color')
cc = next(s for s in new.outputs if s.type == 'RGBA')
bb.default_value = color
links.new(texture, aa); links.new(cc, target)
nodes.remove(old)
textures = [n for n in nodes if n.type == 'TEX_IMAGE']
assert len(textures) == 3
for node in textures:
    node.extension = 'EXTEND'
bpy.ops.wm.save_as_mainfile(filepath=str(a.output.resolve()))
report = {'input': str(a.input.resolve()), 'output': str(a.output.resolve()),
          'scope': 'Hair_Bob_Surface material graph only; geometry unchanged',
          'base_color_factor': color, 'image_nodes': len(textures),
          'texture_wrap': 'CLAMP_TO_EDGE', 'source_material_graph': 'supported Mix Color Multiply',
          'candidate_sha256': hashlib.sha256(a.output.read_bytes()).hexdigest()}
a.report.write_text(json.dumps(report, indent=2)+'\n')
print('BOB_MATERIAL_FINALIZED', json.dumps(report))
