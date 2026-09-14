"""Verify collar morph continuity, closure and actual globe occlusion."""
import argparse
import json
import itertools
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
ap.add_argument('--extended-identity', action='store_true', help='Add32 mixed new3 corner contexts against prior unsigned/signed extrema')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
OBJECT_DATA = {}
POINT_CACHE = {}
TOPOLOGY = {}
INCIDENCE = {}


def posed(obj, values):
    cache_key = (obj.name, tuple(sorted((key, float(value)) for key, value in values.items() if value != 0)))
    if cache_key in POINT_CACHE:
        return POINT_CACHE[cache_key]
    if obj.name not in OBJECT_DATA:
        keys = obj.data.shape_keys.key_blocks
        basis = np.asarray([tuple(v.co) for v in keys['Basis'].data], dtype=np.float64)
        deltas = {key.name: np.asarray([tuple(v.co) for v in key.data], dtype=np.float64) - basis
                  for key in keys if key.name != 'Basis'}
        OBJECT_DATA[obj.name] = (basis, deltas, np.asarray(obj.matrix_world, dtype=np.float64))
    basis, deltas, matrix = OBJECT_DATA[obj.name]
    ps = basis.copy()
    for key, amount in values.items():
        if key in deltas and amount != 0:
            ps += deltas[key] * amount
    world = ps @ matrix[:3, :3].T + matrix[:3, 3]
    result = [Vector(row) for row in world]
    POINT_CACHE[cache_key] = result
    return result


def tree(obj, values):
    if obj.name not in TOPOLOGY:
        TOPOLOGY[obj.name] = [tuple(p.vertices) for p in obj.data.polygons]
    return BVHTree.FromPolygons(posed(obj, values), TOPOLOGY[obj.name])


def front(bvh, x, z):
    point, _, _, _ = bvh.ray_cast(Vector((x, -2, z)), Vector((0, 1, 0)), 4)
    return point.y if point is not None else 10.0


checks = []
eye_suffixes = ('', '.001') if 'Eyes_Sclera' in bpy.data.objects else ('_L', '_R')
cases = [('neutral', {}), ('all_existing_max', dict.fromkeys(('Face_Round', 'Jaw_Strong', 'Nose_Wide', 'Eye_Spacing'), 1.0)),
         ('new_max', dict.fromkeys(('Nose_Length', 'Lip_Fullness', 'Chin_Length'), 1.0)),
         ('new_min', dict.fromkeys(('Nose_Length', 'Lip_Fullness', 'Chin_Length'), -1.0))]
if args.extended_identity:
    new = ('Face_Length', 'Mouth_Width', 'Nose_Bridge')
    available = {key.name for obj in bpy.data.objects if obj.type == 'MESH' and obj.data.shape_keys
                 for key in obj.data.shape_keys.key_blocks}
    assert set(new) <= available, ('extended controls absent', set(new) - available)
    unsigned = dict.fromkeys(('Face_Round', 'Jaw_Strong', 'Nose_Wide', 'Eye_Spacing'), 1.0)
    signed = ('Nose_Length', 'Lip_Fullness', 'Brow_Arch', 'Chin_Length')
    contexts = [('neutral', {}), ('old_unsigned_max', unsigned),
                ('old_all_positive', dict(unsigned, **dict.fromkeys(signed, 1.0))),
                ('old_signed_negative', dict(unsigned, **dict.fromkeys(signed, -1.0)))]
    for context_name, context in contexts:
        for signs in itertools.product((-1.0, 1.0), repeat=3):
            values = dict(context, **dict(zip(new, signs)))
            cases.append(('extended_' + context_name + '_' + ''.join('p' if v > 0 else 'm' for v in signs), values))
for label, values in cases:
    POINT_CACHE.clear()
    values = dict(values, Blink=1.0)
    head = tree(bpy.data.objects['Skin_Head_continuous'], values)
    collars = [tree(bpy.data.objects['Skin_Upper_lid_' + str(sign)], values) for sign in (-1, 1)
               if 'Skin_Upper_lid_' + str(sign) in bpy.data.objects]
    for sign, suffix in zip((-1, 1), eye_suffixes):
        obj = bpy.data.objects.get('Skin_Upper_lid_' + str(sign))
        if obj:
            ps = posed(obj, values)
            gaps = [(ps[i] - ps[(64 - i) % 64]).length for i in range(33)]
        else:
            obj = bpy.data.objects['Skin_Head_continuous']
            ids = list(obj['orbit_inner_' + str(0 if sign == -1 else 1)])
            ps = posed(obj, values)
            basis = posed(obj, {})
            globe = bpy.data.objects['Eyes_Sclera' + suffix]
            gp = posed(globe, {})
            cx = (min(p.x for p in gp) + max(p.x for p in gp)) * .5
            cz = (min(p.z for p in gp) + max(p.z for p in gp)) * .5
            halves = [[ps[i] for i in ids if (basis[i].z - cz - .060 * sign * (basis[i].x - cx) >= 0) == upper]
                      for upper in (True, False)]
            halves = [sorted(points, key=lambda p: p.x) for points in halves]
            def interpolate(points, x):
                for a, b in zip(points[:-1], points[1:]):
                    if a.x <= x <= b.x:
                        return a.lerp(b, (x - a.x) / (b.x - a.x))
                return None
            lo = max(points[0].x for points in halves)
            hi = min(points[-1].x for points in halves)
            gaps = [(interpolate(halves[0], lo + (hi - lo) * i / 100) -
                     interpolate(halves[1], lo + (hi - lo) * i / 100)).length for i in range(101)]
            shared = list(obj['orbit_shared_' + str(0 if sign == -1 else 1)])
            if obj.name not in INCIDENCE:
                incidence = {}
                for face in obj.data.polygons:
                    for i, a in enumerate(face.vertices):
                        edge = tuple(sorted((a, face.vertices[(i + 1) % len(face.vertices)])))
                        incidence[edge] = incidence.get(edge, 0) + 1
                INCIDENCE[obj.name] = incidence
            incidence = INCIDENCE[obj.name]
            assert all(incidence[tuple(sorted((a, shared[(i + 1) % len(shared)])))] == 2 for i, a in enumerate(shared))
        assert all(v.co == obj.data.shape_keys.key_blocks['Basis'].data[i].co for i, v in enumerate(obj.data.vertices))
        # Identity translation fields can introduce tiny upper/lower depth
        # differences; closure remains well below a creator-camera pixel.
        assert max(gaps) < .0003, (label, sign, 'closure gap', max(gaps))
        globe = bpy.data.objects['Eyes_Sclera' + suffix]
        gp = posed(globe, values)
        globe_tree = tree(globe, values)
        low = Vector(tuple(min(p[i] for p in gp) for i in range(3)))
        high = Vector(tuple(max(p[i] for p in gp) for i in range(3)))
        sampled, exposed = 0, []
        for ix in range(41):
            x = low.x + (high.x - low.x) * (ix + .5) / 41
            for iz in range(25):
                z = low.z + (high.z - low.z) * (iz + .5) / 25
                eye_y = front(globe_tree, x, z)
                if eye_y == 10:
                    continue
                skin_y = min([front(head, x, z)] + [front(c, x, z) for c in collars])
                sampled += 1
                if eye_y < skin_y - .0001:
                    exposed.append((x, z, skin_y - eye_y))
        checks.append({'case': label, 'side': sign, 'closure_gap_max_m': max(gaps),
                       'globe_samples': sampled, 'exposed_globe_samples': len(exposed),
                       'maximum_exposure_m': max((p[2] for p in exposed), default=0)})
        assert not exposed, (label, sign, 'visible sclera at full Blink', len(exposed), exposed[:3])
def contains(polygon, x, z):
    inside = False
    for i, a in enumerate(polygon):
        b = polygon[i - 1]
        if (a.z > z) != (b.z > z) and x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x:
            inside = not inside
    return inside


aperture_checks = []
head_obj = bpy.data.objects['Skin_Head_continuous']
if 'orbit_inner_0' in head_obj:
    for label, case_values in cases:
        for blink in (0.0, .5):
            POINT_CACHE.clear()
            values = dict(case_values, Blink=blink)
            head_tree = tree(head_obj, values)
            hp = posed(head_obj, values)
            for eye_index, suffix in enumerate(eye_suffixes):
                polygon = [hp[i] for i in head_obj['orbit_inner_' + str(eye_index)]]
                globe = bpy.data.objects['Eyes_Sclera' + suffix]
                gp = posed(globe, values)
                globe_tree = tree(globe, values)
                low = Vector(tuple(min(p[i] for p in gp) for i in range(3)))
                high = Vector(tuple(max(p[i] for p in gp) for i in range(3)))
                outside, exposed = 0, []
                for ix in range(41):
                    x = low.x + (high.x - low.x) * (ix + .5) / 41
                    for iz in range(25):
                        z = low.z + (high.z - low.z) * (iz + .5) / 25
                        eye_y = front(globe_tree, x, z)
                        if eye_y == 10 or contains(polygon, x, z):
                            continue
                        skin_y = front(head_tree, x, z)
                        outside += 1
                        if eye_y < skin_y - .00015:
                            exposed.append((x, z, skin_y - eye_y))
                aperture_checks.append({'case': label, 'blink': blink, 'side': eye_index,
                                        'outside_aperture_samples': outside, 'exposed_globe_samples': len(exposed)})
                assert not exposed, ('globe pokethrough outside aperture', label, blink, eye_index, len(exposed), exposed[:3])
report = {'source': str(args.source), 'extended_identity': args.extended_identity,
          'case_definitions': [{'name': name, 'values': values} for name, values in cases],
          'full_blink_checks': checks, 'open_and_partial_blink_checks': aperture_checks}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('SOCKET_CLOSURE_PASS', json.dumps(report))
