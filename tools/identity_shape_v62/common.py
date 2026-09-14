"""Measured, world-space identity fields; no neutral or existing-key edits."""
import math
import bpy
from mathutils import Vector

NEW = ('Face_Length', 'Mouth_Width', 'Nose_Bridge')
OLD = ('Face_Round', 'Jaw_Strong', 'Nose_Wide', 'Eye_Spacing',
       'Nose_Length', 'Lip_Fullness', 'Brow_Arch', 'Chin_Length')
CONTACT_PREFIXES = ('Skin_Head', 'Skin_Nose', 'Skin_Upper_lid', 'Skin_Ear',
                    'Lips_', 'Nose_', 'Ear_', 'Jewelry', 'Lash_', 'Hair_Brow')


def smooth(a, b, value):
    """Smoothstep that also accepts an empty or inverted band.

    A degenerate band (b <= a) cannot fade across a region that does not exist.
    Returning a constant 1 keeps such a caller's own masking in charge instead
    of silently collapsing its field to zero through a negative denominator.
    The infant neck band below the mouth is exactly this case.
    """
    if b <= a:
        return 1. if value >= b else 0.
    t = max(0., min(1., (value - a) / (b - a)))
    return t * t * (3. - 2. * t)


def points(obj, key='Basis'):
    blocks = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
    store = blocks.get(key, blocks['Basis']).data if blocks else obj.data.vertices
    return [obj.matrix_world @ v.co for v in store]


def mean(ps):
    return Vector(tuple(math.fsum(p[i] for p in ps) / len(ps) for i in range(3)))


def center(ps):
    return Vector(tuple((min(p[i] for p in ps) + max(p[i] for p in ps)) * .5
                        for i in range(3)))


def seam_ring(obj):
    """Find the tube's actual closed, central circumferential edge cycle.

    Both shipped adult and infant seams use transverse octagons. Validate the
    topology rather than silently assuming an adult vertex offset for infants.
    Ring means describe the centerline; select its measured median-X ring.
    """
    ps = points(obj)
    edges = {tuple(sorted(e.vertices)) for e in obj.data.edges}
    rings = []
    assert len(ps) % 8 == 0, ('Unexpected seam tube topology', obj.name, len(ps))
    for first in range(0, len(ps), 8):
        ids = list(range(first, first + 8))
        assert all(tuple(sorted((ids[j], ids[(j + 1) % 8]))) in edges
                   for j in range(8)), ('Seam ring is not closed', ids)
        rings.append((ids, mean([ps[i] for i in ids])))
    middle_x = (rings[0][1].x + rings[-1][1].x) * .5
    ids, position = min(rings, key=lambda row: abs(row[1].x - middle_x))
    assert abs(position.x - middle_x) < (rings[-1][1] - rings[0][1]).length * .02
    return ids, position


class Geometry:
    def __init__(self):
        self.root = bpy.data.objects['Character']
        self.head = bpy.data.objects['Skin_Head_continuous']
        self.seam = bpy.data.objects['Lips_Smile_seam']
        self.ring, self.mouth = seam_ring(self.seam)
        eyes = sorted((o for o in bpy.data.objects if o.type == 'MESH'
                       and o.name.startswith('Eyes_Sclera')),
                      key=lambda o: center(points(o)).x)
        assert len(eyes) == 2
        eye_centers = [center(points(o)) for o in eyes]
        self.eye = mean(eye_centers)
        self.ipd = (eye_centers[1] - eye_centers[0]).length
        self.eye_height = sum(max(p.z for p in points(o)) - min(p.z for p in points(o))
                              for o in eyes) * .5
        self.eye_medial = min(abs(p.x - self.eye.x) for o in eyes for p in points(o))
        nostrils = [p for o in bpy.data.objects if o.type == 'MESH'
                    and o.name.startswith('Nose_Nostril') for p in points(o)]
        assert nostrils
        self.nose = center(nostrils)
        self.nose_half = (max(p.x for p in nostrils) - min(p.x for p in nostrils)) * .5
        lips = [p for o in bpy.data.objects if o.type == 'MESH'
                and o.name.startswith('Lips_') for p in points(o)]
        self.mouth_half = max(abs(p.x - self.mouth.x) for p in lips)
        self.lip_halfheight = max(abs(p.z - self.mouth.z) for p in lips)
        self.head_low = min(p.z for p in points(self.head))
        self.face_height = self.eye.z - self.mouth.z
        self.nose_mouth = self.nose.z - self.mouth.z
        assert self.ipd > 0 and self.face_height > 0 and self.nose_mouth > 0
        self.age = str(self.root.get('age_stage', 'adult'))
        self.amplitude = {'baby': .35, 'child': .65, 'teen': .85}.get(self.age, 1.)
        self.orbits = []
        head_points = points(self.head)
        for side in (0, 1):
            inner_key, shared_key = 'orbit_inner_' + str(side), 'orbit_shared_' + str(side)
            if inner_key not in self.head:
                continue
            inner, shared = list(self.head[inner_key]), list(self.head[shared_key])
            assert len(inner) == 64 and len(shared) >= 3 and not set(inner).intersection(shared)
            assert all(0 <= i < len(head_points) for i in inner + shared)
            self.orbits.append({'side': side, 'inner': inner, 'shared': shared,
                                'points': [head_points[i] for i in inner]})
        assert len(self.orbits) in (0, 2), 'Incomplete welded orbital index metadata'

    def report(self):
        return {'age_stage': self.age, 'age_amplitude': self.amplitude,
                'eye_center_world': list(self.eye), 'interpupillary_distance_m': self.ipd,
                'eye_height_m': self.eye_height, 'nostril_center_world': list(self.nose),
                'eye_medial_distance_m': self.eye_medial,
                'nostril_halfwidth_m': self.nose_half, 'mouth_seam_ring': self.ring,
                'mouth_seam_center_world': list(self.mouth),
                'mouth_halfwidth_m': self.mouth_half, 'lip_halfheight_m': self.lip_halfheight,
                'head_lowest_world_z': self.head_low, 'eye_to_mouth_m': self.face_height,
                'welded_apertures': [{'side': orbit['side'], 'inner_vertices': len(orbit['inner']),
                                     'shared_vertices': len(orbit['shared']),
                                     'inner_max_field_m': {k: max(self.field(k, p).length for p in orbit['points'])
                                                           for k in NEW}}
                                    for orbit in self.orbits]}

    def field(self, key, p):
        x, y, z = p
        # Behind the anterior face, gently vanish before reaching the hairline.
        front = 1. - smooth(self.eye.y + self.ipd * .55,
                           self.eye.y + self.ipd * 1.15, y)
        if key == 'Face_Length':
            orbital = 1. - smooth(self.eye.z - self.eye_height * .95,
                                  self.eye.z - self.eye_height * .50, z)
            neck = smooth(self.head_low, max(self.mouth.z - self.face_height * .45,
                                             self.head_low), z)
            return Vector((0., 0., -.12 * self.amplitude * max(0., self.eye.z - z)
                           * orbital * neck * front))
        if key == 'Mouth_Width':
            lateral = 1. - smooth(self.mouth_half * 1.08, self.mouth_half * 2.45,
                                  abs(x - self.mouth.x))
            vertical = 1. - smooth(self.lip_halfheight * 1.05,
                                   max(self.lip_halfheight * 2.1, self.nose_mouth * .82),
                                   abs(z - self.mouth.z))
            return Vector((.24 * self.amplitude * (x - self.mouth.x)
                           * lateral * vertical * front, 0., 0.))
        if key == 'Nose_Bridge':
            top = self.eye.z + self.eye_height * .55
            t = max(0., min(1., (z - self.nose.z) / (top - self.nose.z)))
            vertical = math.sin(math.pi * t) ** 2
            # Terminate before the measured inner sclera/lid: changing a bridge
            # must not pull an unchanged eyeball's contacting lid away from it.
            lateral = 1. - smooth(self.nose_half * .35, self.eye_medial * .84,
                                  abs(x - self.nose.x))
            return Vector((0., -.09 * self.ipd * self.amplitude * vertical * lateral * front, 0.))
        raise ValueError(key)


def posed(obj, values):
    blocks = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
    if not blocks:
        return points(obj)
    basis = [v.co.copy() for v in blocks['Basis'].data]
    for name, value in values.items():
        if name not in blocks or value == 0:
            continue
        for i, v in enumerate(blocks[name].data):
            basis[i] += (v.co - blocks['Basis'].data[i].co) * value
    return [obj.matrix_world @ p for p in basis]


def mouth_offsets(g):
    inverse = bpy.data.objects['Head'].matrix_world.to_3x3().inverted()
    result = {}
    for key in OLD + NEW:
        target = points(g.seam, key)
        delta = inverse @ (mean([target[i] for i in g.ring]) - g.mouth)
        result[key.lower()] = [float(delta.x), float(delta.z), float(-delta.y)]
    return result
