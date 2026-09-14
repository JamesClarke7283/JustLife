"""Author orbital skin and closing eyelid margins in candidate sources.

The inherited fused socket has detached shelves at the canthi. A new smooth
almond collar spans the eye margin to actual forehead/cheek skin. With the
reviewed --weld option, the temporary overlay and inherited head ridge are
replaced by one shared head mesh. --relaxed-blink fits the closed patch to
surrounding face curvature. This intentionally changes eyelid topology.
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils import Matrix
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
ap.add_argument('--eye-depth', type=float, default=0.0, help='Adult-scaled posterior globe shift in world metres')
ap.add_argument('--weld', action='store_true', help='Replace the inherited socket region with a genuinely shared head topology')
ap.add_argument('--soft-blink', action='store_true', help='Contract the closed canthi and use a smooth closed-seam depth arc')
ap.add_argument('--relaxed-blink', action='store_true', help='Reconstruct a smooth closed-lid patch from the measured surrounding face')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve()
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
D = bpy.data
eye_suffixes = ('', '.001') if 'Eyes_Sclera' in D.objects else ('_L', '_R')
baby = eye_suffixes[0] == '_L'
for suffix in eye_suffixes:
    globe = D.objects['Eyes_Sclera' + suffix]
    globe_points = {key.name: [globe.matrix_world @ v.co for v in key.data]
                    for key in globe.data.shape_keys.key_blocks}
    def bounds_center(ps):
        return Vector(tuple((min(p[i] for p in ps) + max(p[i] for p in ps)) * .5 for i in range(3)))
    neutral_center = bounds_center(globe_points['Basis'])
    shifts = {name: bounds_center(ps) - neutral_center for name, ps in globe_points.items()}
    # A cheek/jaw slider must not shear the eyeball. Every globe layer shares
    # one rigid translation, which also lets upper and lower closed margins
    # remain coincident when Blink combines with identity extremes.
    for prefix in ('Eyes_Sclera', 'Eyes_Iris', 'Eyes_Iris_edge', 'Eyes_Pupil', 'Eyes_Catchlight'):
        obj = D.objects[prefix + suffix]
        basis = [v.co.copy() for v in obj.data.shape_keys.key_blocks['Basis'].data]
        inverse = obj.matrix_world.to_3x3().inverted()
        for name in shifts:
            if name not in obj.data.shape_keys.key_blocks:
                obj.shape_key_add(name=name)
        for key in obj.data.shape_keys.key_blocks:
            if key.name == 'Basis':
                continue
            delta = inverse @ shifts.get(key.name, Vector())
            for i, v in enumerate(key.data):
                v.co = basis[i] + delta
if args.eye_depth:
    for suffix in eye_suffixes:
        globe = D.objects['Eyes_Sclera' + suffix]
        ps = [globe.matrix_world @ v.co for v in globe.data.shape_keys.key_blocks['Basis'].data]
        eye_scale = (max(p.x for p in ps) - min(p.x for p in ps)) / .05096
        for prefix in ('Eyes_Sclera', 'Eyes_Iris', 'Eyes_Iris_edge', 'Eyes_Pupil', 'Eyes_Catchlight'):
            obj = D.objects[prefix + suffix]
            delta = obj.matrix_world.to_3x3().inverted() @ Vector((0, args.eye_depth * eye_scale, 0))
            for key in obj.data.shape_keys.key_blocks:
                for v in key.data:
                    v.co += delta
            for i, v in enumerate(obj.data.vertices):
                v.co = obj.data.shape_keys.key_blocks['Basis'].data[i].co
            obj.data.update()
head = D.objects['Skin_Head_continuous']
head.data.calc_loop_triangles()
triangles = [tuple(t.vertices) for t in head.data.loop_triangles]
head_keys = {key.name: [head.matrix_world @ v.co for v in key.data] for key in head.data.shape_keys.key_blocks}
head_trees = {name: BVHTree.FromPolygons(ps, triangles, all_triangles=True) for name, ps in head_keys.items()}
report = {'source': str(args.source), 'eye_depth_adult_m': args.eye_depth,
          'eye_identity_rigid': True, 'reference_aperture_m': [.0450, .023 if baby else .0133], 'eyes': [], 'head': {}}


def smooth(value):
    t = max(0, min(1, value))
    return t * t * (3 - 2 * t)


def center(ps):
    return Vector(tuple((min(p[i] for p in ps) + max(p[i] for p in ps)) * .5 for i in range(3)))


def hit(tree, x, z):
    p, normal, index, distance = tree.ray_cast(Vector((x, -2, z)), Vector((0, 1, 0)), 4)
    return p, index


def sample(tree, x, z):
    p, _ = hit(tree, x, z)
    assert p is not None, ('surface missing', x, z)
    return p.y


def head_delta(key, p):
    if key == 'Basis':
        return Vector()
    point, index = hit(head_trees['Basis'], p.x, p.z)
    assert point is not None
    ids = triangles[index]
    return barycentric_transform(point, *(head_keys['Basis'][i] for i in ids),
                                  *(head_keys[key][i] for i in ids)) - point


eyes = []
for sign, suffix in zip((-1, 1), eye_suffixes):
    globe = D.objects['Eyes_Sclera' + suffix]
    gp = {key.name: [globe.matrix_world @ v.co for v in key.data] for key in globe.data.shape_keys.key_blocks}
    center0 = center(gp['Basis'])
    scale = (max(p.x for p in gp['Basis']) - min(p.x for p in gp['Basis'])) / .05096
    gt = {name: BVHTree.FromPolygons(ps, [tuple(p.vertices) for p in globe.data.polygons]) for name, ps in gp.items()}
    shifts = {name: center(ps) - center0 for name, ps in gp.items()}
    eyes.append({'sign': sign, 'suffix': suffix, 'center': center0, 'scale': scale, 'trees': gt, 'shifts': shifts,
                 'inner_rx': .0225, 'inner_upper': .013 if baby else .0075,
                 'inner_lower': .010 if baby else .0058, 'outer_rx': .032, 'outer_rz': .032 if baby else .020})
    if args.relaxed_blink:
        eye = eyes[-1]
        samples, depths = [], []
        # Fit the surrounding skin on several radial bands, avoiding the old
        # protruding socket shelf inside the replacement region. The full
        # closed lid should become one softly curved skin patch, not two
        # wedges converging at a pointed canthus.
        for radius in (1.0, 1.08, 1.16):
            for i in range(64):
                theta = 2 * math.pi * i / 64
                u, v = radius * math.cos(theta), radius * math.sin(theta)
                x = center0.x + eye['outer_rx'] * scale * u
                z = center0.z + eye['outer_rz'] * scale * v + .060 * sign * (x - center0.x)
                samples.append((1, u, v, u * u, u * v, v * v))
                depths.append(sample(head_trees['Basis'], x, z))
        eye['closed_surface'] = np.linalg.lstsq(np.asarray(samples), np.asarray(depths), rcond=None)[0].tolist()


def closed_surface(eye, p):
    c, scale = eye['center'], eye['scale']
    u = (p.x - c.x) / (eye['outer_rx'] * scale)
    v = (p.z - c.z - .060 * eye['sign'] * (p.x - c.x)) / (eye['outer_rz'] * scale)
    return sum(a * b for a, b in zip(eye['closed_surface'], (1, u, v, u * u, u * v, v * v)))


def collar(eye, theta, f, key):
    scale, c, sign = eye['scale'], eye['center'], eye['sign']
    co, si = math.cos(theta), math.sin(theta)
    upper = si >= 0
    inner = Vector((c.x + eye['inner_rx'] * scale * co, 0,
                    c.z + eye['inner_upper' if upper else 'inner_lower'] * scale * si + .060 * sign * eye['inner_rx'] * scale * co))
    outer = Vector((c.x + eye['outer_rx'] * scale * co, 0,
                    c.z + eye['outer_rz'] * scale * si + .060 * sign * eye['outer_rx'] * scale * co))
    base_inner, base_outer = inner.copy(), outer.copy()
    shift = eye['shifts'].get(key, Vector())
    inner += shift
    outer += head_delta(key, outer)
    if key == 'Blink':
        # The upper and lower margins meet at the same curved line. The
        # unchanged globe Blink retreat then removes the sclera completely.
        inner.z = c.z + .060 * sign * eye['inner_rx'] * scale * co - .0012 * scale * abs(si)
        inner.x = c.x + eye['inner_rx'] * scale * co
        base_inner.z = inner.z
        surface = sample(head_trees['Basis'], inner.x, inner.z)
        globe_surface = sample(eye['trees']['Basis'], inner.x, inner.z)
        inner.y = min(surface, globe_surface) - .0008 * scale
        if args.soft_blink or args.relaxed_blink:
            # The old min(skin, globe) depth switches surfaces abruptly near
            # each canthus and produces a triangular closed-lid peak. A
            # quadratic depth arc is smooth across the entire closed seam;
            # mild horizontal contraction lets the corners relax into skin.
            closed_rx = eye['inner_rx'] * .90 * scale
            inner.x = c.x + closed_rx * co
            inner.z = c.z + .060 * sign * closed_rx * co - .0008 * scale * (1 - co * co)
            base_inner.x, base_inner.z = inner.x, inner.z
            center_y = sample(eye['trees']['Basis'], c.x, c.z) - .0008 * scale
            end_x = c.x + (closed_rx if co >= 0 else -closed_rx)
            end_z = c.z + .060 * sign * (end_x - c.x)
            end_y = sample(head_trees['Basis'], end_x, end_z) - .0008 * scale
            inner.y = center_y + (end_y - center_y) * co * co
    else:
        tree = eye['trees'].get(key, eye['trees']['Basis'])
        inner.y = sample(tree, inner.x, inner.z) - .00065 * scale
    outer.y = sample(head_trees['Basis'], base_outer.x, base_outer.z) + head_delta(key, base_outer).y + .00015 * scale
    p = inner.lerp(outer, f)
    # A frontal tangent at the fine margin avoids a raised, upward-facing
    # white rim. The outer tangent matches the surrounding skin, so the short
    # collar blends directly into cheek/forehead instead of forming a bag.
    near_outer = base_inner.lerp(base_outer, .96)
    near_y = sample(head_trees['Basis'], near_outer.x, near_outer.z) + head_delta(key, near_outer).y
    tangent = max(-.020 * scale, min(.020 * scale, (outer.y - near_y) / .04))
    p.y = (2 * f**3 - 3 * f**2 + 1) * inner.y + (-2 * f**3 + 3 * f**2) * outer.y + (f**3 - f**2) * tangent
    if key == 'Blink' and args.relaxed_blink:
        p.y = closed_surface(eye, p) + (outer.y - closed_surface(eye, outer)) * smooth(f)
    if key == 'Blink':
        closed_globe, _ = hit(eye['trees']['Blink'], p.x, p.z)
        if closed_globe is not None:
            p.y = min(p.y, closed_globe.y - .0012 * scale)
    return p


def annulus_coordinates(eye, p):
    dx = (p.x - eye['center'].x) / eye['scale']
    dz = (p.z - eye['center'].z) / eye['scale'] - .060 * eye['sign'] * dx
    rx_in, rx_out = eye['inner_rx'], eye['outer_rx']
    rz_in = eye['inner_upper' if dz >= 0 else 'inner_lower']
    rz_out = eye['outer_rz']
    if (dx / rx_out) ** 2 + (dz / rz_out) ** 2 >= 1:
        return None
    if (dx / rx_in) ** 2 + (dz / rz_in) ** 2 <= 1:
        return math.atan2(dz / rz_in, dx / rx_in), -1.0
    lo, hi = 0.0, 1.0
    for _ in range(18):
        f = (lo + hi) * .5
        radius_x = rx_in + (rx_out - rx_in) * f
        radius_z = rz_in + (rz_out - rz_in) * f
        if (dx / radius_x) ** 2 + (dz / radius_z) ** 2 > 1:
            lo = f
        else:
            hi = f
    f = (lo + hi) * .5
    return math.atan2(dz / (rz_in + (rz_out - rz_in) * f), dx / (rx_in + (rx_out - rx_in) * f)), f


# Cache geometric parameters in the untouched head Basis. Each corresponding
# identity target is recessed beneath its own matching collar surface.
parameters = {}
for eye_index, eye in enumerate(eyes):
    for i, p in enumerate(head_keys['Basis']):
        if p.y > -.025 * eye['scale']:
            continue
        uv = annulus_coordinates(eye, p)
        if uv is not None:
            parameters[i] = (eye_index, *uv)
inverse = head.matrix_world.inverted()
for key in head.data.shape_keys.key_blocks:
    original = head_keys[key.name]
    changed = 0
    maximum = 0.0
    for index, (eye_index, theta, f) in parameters.items():
        eye = eyes[eye_index]
        p = original[index].copy()
        if f < 0:
            tree = eye['trees'].get(key.name, eye['trees']['Basis'])
            q, _ = hit(tree, p.x, p.z)
            if q is None:
                continue
            target = q.y + .004 * eye['scale']
        else:
            target = collar(eye, theta, f, key.name).y + .0012 * eye['scale']
            if f > .80:
                target = p.y + max(0, target - p.y) * (1 - smooth((f - .80) / .20))
        delta = max(0, target - p.y)
        if delta > 0:
            p.y += delta
            key.data[index].co = inverse @ p
            changed += 1
            maximum = max(maximum, delta)
    report['head'][key.name] = {'vertices_recessed': changed, 'maximum_depth_m': maximum}
for i, v in enumerate(head.data.vertices):
    v.co = head.data.shape_keys.key_blocks['Basis'].data[i].co
head.data.update()

lash_material = D.materials.new('Lashes')
lash_material.use_nodes = True
lash_material.diffuse_color = (.025, .016, .012, 1)
bsdf = lash_material.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value = lash_material.diffuse_color
bsdf.inputs['Roughness'].default_value = .70


def install(obj, mesh, stores):
    obj.data = mesh
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    inverse = obj.matrix_world.inverted()
    for key_name, ps in stores.items():
        key = obj.shape_key_add(name=key_name)
        key.value = 0
        if key_name in ('Nose_Length', 'Lip_Fullness', 'Chin_Length'):
            key.slider_min = -1
        for i, p in enumerate(ps):
            key.data[i].co = inverse @ p
    for i, v in enumerate(mesh.vertices):
        v.co = obj.data.shape_keys.key_blocks['Basis'].data[i].co
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    uv_layer = mesh.uv_layers.new(name='UVMap')
    columns = 33 if mesh.name.startswith('Lash_') else 64
    rows = len(mesh.vertices) // columns
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = ((loop.vertex_index % columns) / (columns - 1),
                                       (loop.vertex_index // columns) / max(1, rows - 1))
    mesh.update()


for eye in eyes:
    n, rows = 64, 11
    stores = {key: [collar(eye, 2 * math.pi * i / n, row / (rows - 1), key)
                    for row in range(rows) for i in range(n)] for key in head_keys}
    faces = [(row * n + i, (row + 1) * n + i, (row + 1) * n + (i + 1) % n, row * n + (i + 1) % n)
             for row in range(rows - 1) for i in range(n)]
    mesh = D.meshes.new('Integrated_orbit_' + str(eye['sign']))
    mesh.from_pydata(stores['Basis'], [], faces)
    mesh.materials.append(D.materials['Skin'])
    obj = D.objects.get('Skin_Upper_lid_' + str(eye['sign']))
    if obj is None:
        obj = D.objects.new('Skin_Upper_lid_' + str(eye['sign']), mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = D.objects['Head']
        obj.matrix_world = Matrix.Identity(4)
    install(obj, mesh, stores)
    # A very narrow tapered lash ribbon defines the upper margin at the
    # creator's actual camera distance without individual floating strands.
    lash_stores = {}
    for key in head_keys:
        ps = []
        for row in range(2):
            for i in range(33):
                theta = math.pi * i / 32
                taper = math.sin(theta) ** .5
                p = collar(eye, theta, row * .033 * taper, key)
                p.y -= .00018 * eye['scale']
                ps.append(p)
        lash_stores[key] = ps
    lash_faces = [(i, 33 + i, 33 + i + 1, i + 1) for i in range(32)]
    mesh = D.meshes.new('Lash_Upper_' + str(eye['sign']))
    mesh.from_pydata(lash_stores['Basis'], [], lash_faces)
    mesh.materials.append(lash_material)
    lash = D.objects.new('Lash_Upper_' + str(eye['sign']), mesh)
    bpy.context.scene.collection.objects.link(lash)
    lash.parent = obj.parent
    lash.matrix_world = obj.matrix_world.copy()
    install(lash, mesh, lash_stores)
    report['eyes'].append({'sign': eye['sign'], 'scale': eye['scale'], 'collar_vertices': len(stores['Basis']),
                            'keys': list(stores), 'lash_vertices': 66})

if args.weld:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from socket_weld import weld_head
    report['weld'] = weld_head(head, head_keys, triangles, eyes, collar)

# Brows need a distinct tint from the hairstyle: pale blonde/grey hair should
# not erase facial definition. Copy the existing authored material settings;
# runtime may recolor this slot without changing any non-brow assignment.
brow_objects = [o for o in D.objects if o.type == 'MESH' and o.name.startswith('Hair_Brow')]
if brow_objects:
    assert all(len(o.data.materials) == 1 for o in brow_objects)
    brow_material = brow_objects[0].data.materials[0].copy()
    brow_material.name = 'Brows'
    for obj in brow_objects:
        obj.data.materials.clear()
        obj.data.materials.append(brow_material)
    report['brow_material'] = {'name': brow_material.name, 'objects': [o.name for o in brow_objects],
                               'scope': 'copied settings; all non-brow assignments preserved'}

for obj in D.objects:
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            key.value = 0.0

args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('ORBITAL_COLLAR_AUTHORED', json.dumps(report))
