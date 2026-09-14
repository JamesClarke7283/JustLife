"""Original, recolourable facial colour zones and iris fibres; no geometry edits.

Low-frequency vertex paint follows measured facial landmarks and every morph.
The glTF exporter carries it as COLOR_0 multiplied by the selected complexion
or eye colour. It introduces no photograph, external texture or baked lighting.
Only candidate files are written. Geometry, UVs, weights and contacts stay exact.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'identity_shape_v62'))
from common import Geometry, points, smooth

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert a.source.resolve() != a.output.resolve() and not a.output.exists()
bpy.ops.wm.open_mainfile(filepath=str(a.source.resolve()))
bpy.context.view_layer.update()


def geometry_digest():
    h = hashlib.sha256()
    def feed(value):
        h.update(repr(value).encode()); h.update(b'\0')
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        feed((obj.name, obj.type, obj.parent.name if obj.parent else '', obj.parent_type, obj.parent_bone))
        feed(tuple(tuple(row) for row in obj.matrix_basis))
        feed(tuple(tuple(row) for row in obj.matrix_parent_inverse))
        feed(tuple((m.name, m.type) for m in obj.modifiers))
        if obj.type == 'MESH':
            mesh = obj.data
            h.update(np.asarray([v.co[:] for v in mesh.vertices], dtype='<f4').tobytes())
            feed(tuple((tuple(f.vertices), f.material_index, f.use_smooth) for f in mesh.polygons))
            feed(tuple((tuple(e.vertices), e.use_edge_sharp) for e in mesh.edges))
            feed(tuple((uv.name, tuple(tuple(v.uv) for v in uv.data)) for uv in mesh.uv_layers))
            feed(tuple(g.name for g in obj.vertex_groups))
            feed(tuple(tuple((g.group, g.weight) for g in v.groups) for v in mesh.vertices))
            if mesh.shape_keys:
                for key in mesh.shape_keys.key_blocks:
                    feed((key.name, key.value, key.slider_min, key.slider_max))
                    h.update(np.asarray([v.co[:] for v in key.data], dtype='<f4').tobytes())
        elif obj.type == 'ARMATURE':
            feed(tuple((b.name, b.parent.name if b.parent else '', tuple(tuple(r) for r in b.matrix_local)) for b in obj.data.bones))
            feed(tuple((b.name, tuple(tuple(r) for r in b.matrix_basis)) for b in obj.pose.bones))
        elif obj.type == 'CURVE':
            feed(tuple((s.type, tuple(tuple(v.co) for v in s.bezier_points), tuple(tuple(v.co) for v in s.points)) for s in obj.data.splines))
    return h.hexdigest()


before = geometry_digest()
g = Geometry()
owned = {}
materials = {}


def material(source, name, roughness):
    if name in materials:
        return materials[name]
    assert name not in bpy.data.materials, ('Already authored', name)
    mat = source.copy()
    mat.name = name
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    assert not bsdf.inputs['Base Color'].is_linked
    color = tuple(bsdf.inputs['Base Color'].default_value)
    attr = nodes.new('ShaderNodeVertexColor')
    attr.layer_name = 'JustLife_Surface'
    attr.label = 'Original complexion-neutral surface colour'
    mix = nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    input_a = next(s for s in mix.inputs if s.name == 'A' and s.type == 'RGBA')
    input_b = next(s for s in mix.inputs if s.name == 'B' and s.type == 'RGBA')
    output = next(s for s in mix.outputs if s.type == 'RGBA')
    input_b.default_value = color
    links.new(attr.outputs['Color'], input_a)
    links.new(output, bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = roughness
    if 'Specular IOR Level' in bsdf.inputs:
        bsdf.inputs['Specular IOR Level'].default_value = .28 if name.startswith('Skin') else .35
    materials[name] = mat
    return mat


def paint(obj, mat_name, roughness, colors):
    mesh = obj.data
    assert mesh.users == 1 and len(mesh.materials) == 1
    assert 'JustLife_Surface' not in mesh.color_attributes
    attr = mesh.color_attributes.new(name='JustLife_Surface', type='FLOAT_COLOR', domain='POINT')
    assert len(colors) == len(mesh.vertices)
    rgba = np.asarray([(*c, 1.0) for c in colors], dtype=np.float32)
    assert np.isfinite(rgba).all() and rgba.min() >= 0 and rgba.max() <= 1
    attr.data.foreach_set('color', rgba.reshape(-1))
    mesh.color_attributes.active_color = attr
    mesh.materials[0] = material(mesh.materials[0], mat_name, roughness)
    owned[obj.name] = {'material': mat_name, 'vertices': len(colors),
                       'linear_rgb_min': rgba[:, :3].min(axis=0).tolist(),
                       'linear_rgb_max': rgba[:, :3].max(axis=0).tolist()}


def face_color(point):
    # Broad biological colour zones, not painted shadows or photographic pores.
    x, y, z = point
    ipd = g.ipd
    front = 1.0 - smooth(g.eye.y + ipd * .25, g.eye.y + ipd * .8, y)
    cheek_z = g.mouth.z + g.face_height * .65
    cheek = math.exp(-((abs(x - g.eye.x) - ipd * .61) / (ipd * .40))**2
                     - ((z - cheek_z) / (g.face_height * .42))**2) * front
    nose = math.exp(-((x - g.nose.x) / (g.nose_half * 1.25))**2
                    - ((z - g.nose.z) / (g.nose_mouth * .70))**2) * front
    # Small cool transition below the eyes, much gentler than eye-bag shading.
    under_eye = math.exp(-((abs(x - g.eye.x) - ipd * .5) / (ipd * .26))**2
                        - ((z - g.eye.z + g.eye_height * .62) / (g.eye_height * .52))**2) * front
    warmth = min(1.0, .84 * cheek + .32 * nose)
    return (1.0 - .012 * under_eye, 1.0 - .075 * warmth - .009 * under_eye,
            1.0 - .066 * warmth)


paint(g.head, 'Skin_Face_Surface', .57, [face_color(p) for p in points(g.head)])
for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.name.startswith('Eyes_Iris') or obj.name.startswith('Eyes_Iris_edge'):
        continue
    ps = points(obj)
    cx = (min(v.x for v in ps) + max(v.x for v in ps)) * .5
    cz = (min(v.z for v in ps) + max(v.z for v in ps)) * .5
    rx = (max(v.x for v in ps) - min(v.x for v in ps)) * .5
    rz = (max(v.z for v in ps) - min(v.z for v in ps)) * .5
    colors = []
    for v in ps:
        x, z = (v.x - cx) / rx, (v.z - cz) / rz
        radius, angle = min(1., math.hypot(x, z)), math.atan2(z, x)
        fibres = (.5 + .5 * math.sin(21.0 * angle + .6 * math.sin(7.0 * angle) + radius * 2.2))
        fibres *= smooth(.35, .62, radius) * (1.0 - smooth(.90, 1.0, radius))
        edge = smooth(.80, 1.0, radius)
        pigment = .88 + .12 * fibres - .12 * edge
        amber = math.exp(-((radius - .49) / .11)**2)
        colors.append((min(1., pigment + .055 * amber), pigment, pigment - .045 * amber))
    paint(obj, 'Eyes_Iris_Surface', .29, colors)

# Keep the white globe's authored colour neutral under the warm portrait key.
# A copied material avoids changing unowned eye whites in any other datablock.
for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.name.startswith('Eyes_Sclera'):
        continue
    ps = points(obj)
    cx = (min(v.x for v in ps) + max(v.x for v in ps)) * .5
    rx = (max(v.x for v in ps) - min(v.x for v in ps)) * .5
    colors = [(1., 1. - .045 * smooth(.55, .95, abs(v.x - cx) / rx),
               1. - .055 * smooth(.55, .95, abs(v.x - cx) / rx)) for v in ps]
    paint(obj, 'Eyes_Sclera_Surface', .24, colors)
mat = materials['Eyes_Sclera_Surface']
mix = next(n for n in mat.node_tree.nodes if n.type == 'MIX')
next(s for s in mix.inputs if s.name == 'B' and s.type == 'RGBA').default_value = (.86, .89, .91, 1.)

after = geometry_digest()
assert before == after, 'Surface authoring must not change any geometry, UV, rig or morph'
a.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(a.output.resolve()))
report = {'source': str(a.source.resolve()), 'source_sha256': hashlib.sha256(a.source.read_bytes()).hexdigest(),
          'output': str(a.output.resolve()), 'output_sha256': hashlib.sha256(a.output.read_bytes()).hexdigest(),
          'geometry_uv_weights_rig_morphs_exact': before == after, 'geometry_digest': after,
          'owned_surfaces': owned, 'original_vertex_paint': True, 'external_images': 0}
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('SKIN_SURFACE_AUTHORED', json.dumps(report))
