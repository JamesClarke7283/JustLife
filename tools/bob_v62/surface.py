"""Add original directional strand relief and portable texture detail to Bob.

The cleared silhouette and attachment remain intact. All imagery is generated
from periodic mathematical strand fields inside Blender, packed in the source,
and exported as ordinary glTF albedo/normal/roughness textures. No photographic
or game texture is used. Only Hair_Bob descendants receive the new material.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--input', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert a.input.resolve() != a.output.resolve()


def fingerprint(o):
    h = hashlib.sha256()
    def feed(value):
        h.update(repr(value).encode()); h.update(b'\0')
    feed((o.name, o.type, o.parent.name if o.parent else '', o.parent_type, o.parent_bone))
    feed(tuple(tuple(row) for row in o.matrix_basis))
    feed(tuple(tuple(row) for row in o.matrix_parent_inverse))
    feed((o.hide_render, o.hide_viewport))
    if o.type == 'MESH':
        feed(tuple(tuple(v.co) for v in o.data.vertices))
        feed(tuple((tuple(p.vertices), p.material_index, p.use_smooth) for p in o.data.polygons))
        feed(tuple(m.name if m else '' for m in o.data.materials))
        feed(tuple((u.name, tuple(tuple(p.uv) for p in u.data)) for u in o.data.uv_layers))
        feed(tuple(g.name for g in o.vertex_groups))
        feed(tuple(tuple((g.group, g.weight) for g in v.groups) for v in o.data.vertices))
        if o.data.shape_keys:
            feed(tuple((k.name, k.value, tuple(tuple(v.co) for v in k.data)) for k in o.data.shape_keys.key_blocks))
    if o.type == 'CURVE':
        feed(tuple((s.type, tuple(tuple(v.co) for v in s.bezier_points), tuple(tuple(v.co) for v in s.points)) for s in o.data.splines))
    if o.type == 'ARMATURE':
        feed(tuple((b.name, b.parent.name if b.parent else '', tuple(tuple(row) for row in b.matrix_local), b.use_deform)
                   for b in o.data.bones))
        feed(tuple((b.name, tuple(tuple(row) for row in b.matrix_basis), b.rotation_mode) for b in o.pose.bones))
    feed(tuple((m.name, m.type) for m in o.modifiers))
    return h.hexdigest()


def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x*x*(3.0 - 2.0*x)


def scalar_smooth(x):
    x = max(0.0, min(1.0, x))
    return x*x*(3.0 - 2.0*x)


def field(u, v):
    """Periodic, irregular flowing groups plus finer intermittent strands."""
    tau = 2 * math.pi
    flow = u + .025 * np.sin(tau*u + .5) * (1-v)**2
    flow += .020 * np.sin(2*tau*u - .7) * np.sin(math.pi*v)
    flow += .009 * np.sin(3*tau*u + 1.2) * v*(1-v)
    broad = np.cos(tau*(17*flow + .16*np.sin(3*tau*flow) + .08*np.sin(tau*v)))
    sister = np.cos(tau*(31*flow + .12*np.sin(5*tau*flow + .5) - .045*np.sin(2*tau*v)))
    fine = np.cos(tau*(103*flow + .10*np.sin(7*tau*flow + 1) + .035*np.sin(3*tau*v)))
    finest = np.cos(tau*(181*flow - .13*np.sin(9*tau*flow - 2) + .08*np.cos(2*tau*v)))
    interrupted = .5 + .5*np.sin(tau*(v*2.0 + 4*u) + 1.7)
    root_fade = smooth((v-.06)/.18)
    height = root_fade*(.00042*broad + .00016*sister + .000055*fine + .000025*finest)
    # Neutral luminance modulation is multiplied by the player's hair color.
    shade = .86 + root_fade*(.073*broad + .028*sister + (.020+.012*interrupted)*fine + .010*finest)
    roughness = .72 + .035*(1-broad) + .012*sister + .008*fine
    return height, np.clip(shade, .70, 1.0), np.clip(roughness, .65, .82)


def image(name, rgb, folder, color_space):
    height, width = rgb.shape[:2]
    previous = bpy.data.images.get(name)
    if previous is not None and previous.users == 0:
        bpy.data.images.remove(previous)
    im = bpy.data.images.new(name, width=width, height=height, alpha=False, float_buffer=False)
    im.colorspace_settings.name = color_space
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[:, :, :3] = rgb
    im.pixels.foreach_set(rgba.reshape(-1))
    im.file_format = 'PNG'
    im.filepath_raw = str((folder / (name + '.png')).resolve())
    im.save()
    im.pack()
    return im


def material(source, folder):
    previous = bpy.data.materials.get('Hair_Bob_Surface')
    if previous is not None:
        assert previous.users == 0, 'Reset Bob with author.py before reapplying surface.py'
        bpy.data.materials.remove(previous)
    width = 2048; height = 1024
    u, v = np.meshgrid((np.arange(width)+.5)/width, (np.arange(height)+.5)/height)
    bump, shade, roughness = field(u, v)
    # Convert the height gradient to a small physical slope. U spans roughly
    # 0.75 m around the haircut, while V spans about 0.26 m of combed length.
    du = (np.roll(bump, -1, axis=1)-np.roll(bump, 1, axis=1))*width/2/.75
    dv = np.gradient(bump, axis=0)*height/.26
    normal = np.stack((-du, -dv, np.ones_like(du)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    albedo = image('JustLife_Bob_StrandTone', np.repeat(shade[:, :, None], 3, axis=2), folder, 'sRGB')
    normals = image('JustLife_Bob_StrandNormal', normal*.5+.5, folder, 'Non-Color')
    rough = image('JustLife_Bob_StrandRoughness', np.repeat(roughness[:, :, None], 3, axis=2), folder, 'Non-Color')
    mat = source.copy(); mat.name = 'Hair_Bob_Surface'
    mat['recolor_role'] = 'Hair'
    mat['artwork'] = 'Original JustLife procedural combed strand fields, revision 62'
    mat.use_nodes = True
    nodes = mat.node_tree.nodes; links = mat.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    color = tuple(bsdf.inputs['Base Color'].default_value)
    for inp in ('Base Color', 'Normal', 'Roughness'):
        for link in list(bsdf.inputs[inp].links):
            links.remove(link)
    tex = nodes.new('ShaderNodeTexImage'); tex.name = 'Original strand tone'; tex.image = albedo; tex.extension = 'EXTEND'
    # Use the current Mix Color node: the glTF exporter intentionally recognizes
    # this node's constant multiplier, but not the legacy MixRGB equivalent.
    multiply = nodes.new('ShaderNodeMix'); multiply.data_type = 'RGBA'; multiply.blend_type = 'MULTIPLY'
    multiply.inputs[0].default_value = 1.0
    input_a = next(s for s in multiply.inputs if s.identifier == 'A_Color')
    input_b = next(s for s in multiply.inputs if s.identifier == 'B_Color')
    output_color = next(s for s in multiply.outputs if s.type == 'RGBA')
    input_b.default_value = color
    links.new(tex.outputs['Color'], input_a); links.new(output_color, bsdf.inputs['Base Color'])
    tex_n = nodes.new('ShaderNodeTexImage'); tex_n.name = 'Original strand normal'; tex_n.image = normals; tex_n.extension = 'EXTEND'
    normal_node = nodes.new('ShaderNodeNormalMap'); normal_node.inputs['Strength'].default_value = .70
    links.new(tex_n.outputs['Color'], normal_node.inputs['Color']); links.new(normal_node.outputs['Normal'], bsdf.inputs['Normal'])
    tex_r = nodes.new('ShaderNodeTexImage'); tex_r.name = 'Original strand roughness'; tex_r.image = rough; tex_r.extension = 'EXTEND'
    links.new(tex_r.outputs['Color'], bsdf.inputs['Roughness'])
    if 'Specular IOR Level' in bsdf.inputs:
        bsdf.inputs['Specular IOR Level'].default_value = .30
    return mat


def cap_uv(o):
    """Fix the wrap per face corner, including the single crown pole."""
    layer = o.data.uv_layers['SurfaceUV']
    for poly in o.data.polygons:
        corners = [layer.data[i] for i in poly.loop_indices]
        has_pole = any(o.data.loops[i].vertex_index == 0 for i in poly.loop_indices)
        regular = [layer.data[i].uv.x for i in poly.loop_indices if o.data.loops[i].vertex_index != 0]
        seam = max(regular)-min(regular) > .5
        for i in poly.loop_indices:
            datum = layer.data[i]
            if o.data.loops[i].vertex_index != 0 and seam and datum.uv.x < .5:
                datum.uv.x += 1.0
        if has_pole:
            regular = [layer.data[i].uv.x for i in poly.loop_indices if o.data.loops[i].vertex_index != 0]
            for i in poly.loop_indices:
                if o.data.loops[i].vertex_index == 0:
                    layer.data[i].uv.x = sum(regular)/len(regular)


def sweep_uv(o, start_a, end_a, first_t, last_t, width):
    rows = 40; cols = 14
    assert len(o.data.vertices) == (rows+1)*(cols+1), o.name
    coords = []
    for i in range(rows+1):
        s = i/rows; center = start_a*(1-scalar_smooth(s))+end_a*scalar_smooth(s)
        t = first_t*(1-s)+last_t*s
        w = width*math.sin(math.pi*(s*.86+.10))**.48
        if s > .85:
            w *= 1.0-.96*scalar_smooth((s-.85)/.15)
        for j in range(cols+1):
            angle = center + w*(j/cols*2-1)
            coords.append((angle/(2*math.pi)+.5, t))
    for i, loop in enumerate(o.data.loops):
        o.data.uv_layers['SurfaceUV'].data[i].uv = coords[loop.vertex_index]


bpy.ops.wm.open_mainfile(filepath=str(a.input.resolve()))
bob = bpy.data.objects['Hair_Bob']
owned = list(bob.children)
assert {o.name for o in owned} == {'Hair_Bob_Cap', 'Hair_Bob_Sweep', 'Hair_Bob_TempleLayer', 'Hair_Bob_TuckLayer'}
assert not any(m and m.name == 'Hair_Bob_Surface' for o in owned for m in o.data.materials), \
    'Reset Bob with author.py before reapplying surface.py; do not accumulate relief'
protected = {o.name: fingerprint(o) for o in bpy.data.objects if o not in owned}
original_material = bpy.data.materials['Hair']
cap = bpy.data.objects['Hair_Bob_Cap']
assert len(cap.data.vertices) == 1+224*76
before_hem = [tuple(v.co) for v in cap.data.vertices[-224:]]
before_crown = tuple(cap.data.vertices[0].co)
normals = [v.normal.copy() for v in cap.data.vertices]
# Slight irregular physical relief follows the same field as the texture.
# The crown pole and entire hairline/hem boundary remain byte-identical.
for i, vert in enumerate(cap.data.vertices):
    if i == 0:
        continue
    row = (i-1)//224 + 1; col = (i-1)%224
    u = col/224; v = row/76
    h, _, _ = field(u, v)
    fade = scalar_smooth((v-.12)/.20)*scalar_smooth((.985-v)/.09)
    vert.co += normals[i]*float(h*.70*fade*cap.get('bob_fit_detail_local_scale', 1.0))
cap.data.update()
cap_uv(cap)
sweep_uv(bpy.data.objects['Hair_Bob_Sweep'], .20, -.90, .23, .995, .17)
sweep_uv(bpy.data.objects['Hair_Bob_TempleLayer'], -.45, -1.30, .32, .993, .13)
sweep_uv(bpy.data.objects['Hair_Bob_TuckLayer'], .66, 1.30, .40, .985, .12)
folder = a.output.parent / 'textures'
folder.mkdir(parents=True, exist_ok=True)
styled = material(original_material, folder)
for o in owned:
    o.data.materials.clear(); o.data.materials.append(styled)
assert [tuple(v.co) for v in cap.data.vertices[-224:]] == before_hem
assert tuple(cap.data.vertices[0].co) == before_crown
assert {o.name: fingerprint(o) for o in bpy.data.objects if o not in owned} == protected
a.output.parent.mkdir(parents=True, exist_ok=True)
a.report.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(a.output.resolve()))
report = {'input': str(a.input.resolve()), 'output': str(a.output.resolve()),
          'scope': 'Four Hair_Bob descendant meshes only; one added Bob material and three original packed maps',
          'protected_objects': len(protected), 'hem_exact': True, 'crown_pole_exact': True,
          'material': styled.name, 'runtime_recolor_role': 'Hair',
          'texture_dimensions': [2048, 1024], 'external_pixels_used': False,
          'candidate_sha256': hashlib.sha256(a.output.read_bytes()).hexdigest()}
a.report.write_text(json.dumps(report, indent=2)+'\n')
print('BOB_SURFACE_CANDIDATE', json.dumps(report))
