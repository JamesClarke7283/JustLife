"""Add four signed, proportionate facial identity morphs to a candidate.

Nose, mouth and chin fields act on all contacting skin/detail surfaces. Brow
arch follows the true forehead. Existing geometry and morph values remain
unchanged; new controls use neutral zero and range from -1 to +1.
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve()
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
D = bpy.data
KEYS = ('Nose_Length', 'Lip_Fullness', 'Brow_Arch', 'Chin_Length')
head = D.objects['Skin_Head_continuous']
root = D.objects['Character']
is_baby = str(root.get('age_stage', '')) == 'baby'


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def points(obj, key='Basis'):
    store = obj.data.shape_keys.key_blocks.get(key, obj.data.shape_keys.key_blocks['Basis']).data if obj.data.shape_keys else obj.data.vertices
    return [obj.matrix_world @ v.co for v in store]


def center(ps):
    return Vector(tuple((min(p[i] for p in ps) + max(p[i] for p in ps)) * .5 for i in range(3)))


eyes = sorted((o for o in D.objects if o.type == 'MESH' and o.name.startswith('Eyes_Sclera')), key=lambda o: center(points(o)).x)
assert len(eyes) == 2
eye_centers = [center(points(o)) for o in eyes]
scale = (eye_centers[1].x - eye_centers[0].x) / .08554
amplitude_scale = scale * (.40 if is_baby else 1.0)
mouth = D.objects['Lips_Smile_seam']
mouth_points = points(mouth)
mouth_width = max(abs(p.x) for p in mouth_points)
mouth_center = center([p for p in mouth_points if abs(p.x) < mouth_width * .12])
nostrils = [o for o in D.objects if o.type == 'MESH' and o.name.startswith('Nose_Nostril')]
assert nostrils
nose_center = center([p for o in nostrils for p in points(o)])
head_points = points(head)
head.data.calc_loop_triangles()
triangles = [tuple(t.vertices) for t in head.data.loop_triangles]
bvh = BVHTree.FromPolygons(head_points, triangles, all_triangles=True)


def skin_hit(x, z):
    hit, normal, index, distance = bvh.ray_cast(Vector((x, -2, z)), Vector((0, 1, 0)), 4)
    assert hit is not None, (x, z)
    return hit, index


# The released infant has no brows. Give it a pair of fine original ribbons
# attached to the existing head, including its existing identity deformations.
new_brows = []
if is_baby and not any(o.name.startswith('Hair_Brow') for o in D.objects):
    for sign, suffix in ((-1, 'L'), (1, 'R')):
        eye = eye_centers[0 if sign < 0 else 1]
        vertices, attachment = [], []
        n = 33
        for row in range(5):
            across = (row - 2) / 2
            for j in range(n):
                t = j / (n - 1)
                x = sign * (abs(eye.x) - .016 * scale + .034 * scale * t)
                z = eye.z + .031 * scale + .0030 * scale * math.sin(math.pi * t) - .0015 * scale * t
                z += across * .00145 * scale * (1 - .78 * t * t)
                hit, index = skin_hit(x, z)
                p = Vector((x, hit.y - .00035 * scale, z))
                vertices.append(p)
                attachment.append((hit, triangles[index]))
        faces = []
        for row in range(4):
            for j in range(n - 1):
                face = (row * n + j, row * n + j + 1, (row + 1) * n + j + 1, (row + 1) * n + j)
                faces.append(face if sign > 0 else tuple(reversed(face)))
        mesh = D.meshes.new('Hair_Brow_' + suffix)
        mesh.from_pydata(vertices, [], faces)
        mesh.materials.append(D.materials['Hair'])
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        obj = D.objects.new('Hair_Brow_' + suffix, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = D.objects['Head']
        obj.matrix_world = Matrix.Identity(4)
        obj.shape_key_add(name='Basis')
        for source_key in head.data.shape_keys.key_blocks:
            if source_key.name in ('Basis', 'Blink', 'Smile'):
                continue
            target = obj.shape_key_add(name=source_key.name)
            target.value = 0
            key_points = points(head, source_key.name)
            for i, (hit, ids) in enumerate(attachment):
                before = [head_points[j] for j in ids]
                after = [key_points[j] for j in ids]
                displacement = barycentric_transform(hit, *before, *after) - hit
                target.data[i].co = vertices[i] + displacement
        new_brows.append(obj.name)


def field(name, p):
    x, y, z = p
    # In front of the ears only; the back of the skull and neck are protected.
    front = 1 - smooth(-.050 * scale, -.008 * scale, y)
    if name == 'Nose_Length':
        dx = x / (.025 * scale)
        dz = (z - nose_center.z - .009 * scale) / (.022 * scale)
        w = math.exp(-dx ** 4 - dz ** 4) * front
        return Vector((0, -.0050 * amplitude_scale * w, -.0020 * amplitude_scale * w))
    if name == 'Lip_Fullness':
        horizontal = max(0.0, 1 - (x / max(.001, mouth_width * 1.01)) ** 2) ** 2
        dz = z - mouth_center.z
        support = math.exp(-(dz / (.015 * scale)) ** 4) * horizontal * front
        return Vector((0, -.0024 * amplitude_scale * support,
                       .0013 * amplitude_scale * math.tanh(dz / (.0035 * scale)) * support))
    if name == 'Chin_Length':
        # Infant anatomy has a shorter mouth-to-neck interval than the adult.
        distance = (.014 if is_baby else .038) * scale
        center_z = mouth_center.z - distance
        span = (.010 if is_baby else .023) * scale
        w = math.exp(-(x / (.062 * scale)) ** 2 - ((z - center_z) / span) ** 2)
        w *= 1 - smooth(mouth_center.z - (.011 if is_baby else .028) * scale,
                         mouth_center.z - (.005 if is_baby else .014) * scale, z)
        w *= front
        return Vector((0, .0008 * amplitude_scale * w, -.0070 * amplitude_scale * w))
    return Vector()


owned_prefixes = ('Skin_Head_continuous', 'Skin_Nose', 'Skin_Upper_lid', 'Lips_', 'Nose_', 'Ear_', 'Jewelry')
report = {'source': str(args.source), 'new_keys': list(KEYS), 'scale': scale,
          'amplitude_scale': amplitude_scale, 'baby': is_baby, 'new_brows': new_brows, 'objects': {}}
for obj in list(D.objects):
    if obj.type != 'MESH' or not obj.name.startswith(owned_prefixes):
        continue
    ps = points(obj)
    inv = obj.matrix_world.to_3x3().inverted()
    changes = {}
    for name in ('Nose_Length', 'Lip_Fullness', 'Chin_Length'):
        displacements = [field(name, p) for p in ps]
        maximum = max(d.length for d in displacements)
        if maximum < 1e-7:
            continue
        if not obj.data.shape_keys:
            obj.shape_key_add(name='Basis')
        assert obj.data.shape_keys.key_blocks.get(name) is None, (obj.name, name, 'already authored')
        key = obj.shape_key_add(name=name)
        key.slider_min = -1
        key.slider_max = 1
        key.value = 0
        for i, d in enumerate(displacements):
            key.data[i].co = obj.data.shape_keys.key_blocks['Basis'].data[i].co + inv @ d
        changes[name] = maximum
    if changes:
        report['objects'][obj.name] = changes

for obj in [o for o in D.objects if o.type == 'MESH' and o.name.startswith('Hair_Brow')]:
    ps = points(obj)
    inner, outer = min(abs(p.x) for p in ps), max(abs(p.x) for p in ps)
    inv = obj.matrix_world.inverted()
    if not obj.data.shape_keys:
        obj.shape_key_add(name='Basis')
    assert obj.data.shape_keys.key_blocks.get('Brow_Arch') is None
    key = obj.shape_key_add(name='Brow_Arch')
    key.slider_min = -1
    key.slider_max = 1
    key.value = 0
    for i, p in enumerate(ps):
        t = max(0, min(1, (abs(p.x) - inner) / (outer - inner)))
        dz = (.0040 * math.sin(math.pi * t) ** 1.35 - .0005 * t * t) * amplitude_scale
        previous_hit, _ = skin_hit(p.x, p.z)
        hit, _ = skin_hit(p.x, p.z + dz)
        key.data[i].co = inv @ Vector((p.x, hit.y + p.y - previous_hit.y, p.z + dz))
    report['objects'][obj.name] = {'Brow_Arch': .0040 * amplitude_scale}

# Export metadata describes all authorable controls; the existing four names
# remain in the same order for old profiles and external tooling.
existing = str(root.get('identity_morphs', 'Face_Round,Jaw_Strong,Nose_Wide,Eye_Spacing')).split(',')
root['identity_morphs'] = ','.join(existing + [k for k in KEYS if k not in existing])
root['portrait_revision'] = 62
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('PORTRAIT_IDENTITY_AUTHORED', json.dumps(report))
