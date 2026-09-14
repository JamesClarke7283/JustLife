"""Candidate orbital transforms and their exact relative-morph composition."""
import hashlib
import json
import math

import bpy
import numpy as np

KEY = 'Eye_Tilt'
PREFIX = 'Corrective__Eye_Tilt__'
OWNED = ('Skin_Head', 'Skin_Nose', 'Skin_Upper_lid', 'Eyes_',
         'Hair_Brow', 'Lash_', 'Nose_')


def array(collection, field='co', width=3):
    result = np.empty(len(collection) * width, dtype=np.float32)
    collection.foreach_get(field, result)
    return result.reshape((-1, width))


def local(obj, name='Basis'):
    keys = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
    return array(keys.get(name, keys['Basis']).data if keys else obj.data.vertices)


def world(obj, values):
    matrix = np.asarray(obj.matrix_world, dtype=np.float64)
    return values @ matrix[:3, :3].T + matrix[:3, 3]


def smooth(a, b, values):
    t = np.clip((values - a) / (b - a), 0., 1.)
    return t * t * (3. - 2. * t)


def frozen_digest(obj):
    """All old geometry/keys, topology, shading, weights and object/rig state.

    The new relative targets are excluded, so a before/after match means the
    neutral model and pre-existing animation were not silently re-authored.
    Material datablocks are untouched by this author, including their nodes.
    """
    digest = hashlib.sha256()
    def feed(value):
        digest.update(repr(value).encode()); digest.update(b'\0')
    feed((obj.name, obj.type, obj.parent.name if obj.parent else None,
          obj.parent_type, obj.parent_bone, tuple(map(tuple, obj.matrix_basis)),
          tuple(map(tuple, obj.matrix_parent_inverse))))
    feed([(m.name, m.type) for m in obj.modifiers])
    if obj.type == 'MESH':
        mesh = obj.data
        digest.update(array(mesh.vertices).tobytes())
        feed([(tuple(p.vertices), p.material_index, p.use_smooth) for p in mesh.polygons])
        feed([(tuple(e.vertices), e.use_edge_sharp) for e in mesh.edges])
        feed([m.name if m else None for m in mesh.materials])
        feed([g.name for g in obj.vertex_groups])
        feed([[(g.group, g.weight) for g in v.groups] for v in mesh.vertices])
        for uv in mesh.uv_layers:
            feed(uv.name); digest.update(array(uv.data, 'uv', 2).tobytes())
        for color in mesh.color_attributes:
            feed((color.name, color.domain, color.data_type))
            digest.update(array(color.data, 'color', 4).tobytes())
        if mesh.shape_keys:
            for key in mesh.shape_keys.key_blocks:
                if key.name == KEY or key.name.startswith(PREFIX):
                    continue
                feed((key.name, key.value, key.slider_min, key.slider_max))
                digest.update(array(key.data).tobytes())
    elif obj.type == 'ARMATURE':
        feed([(b.name, b.parent.name if b.parent else None, tuple(map(tuple, b.matrix_local)))
              for b in obj.data.bones])
        feed([(b.name, tuple(map(tuple, b.matrix_basis))) for b in obj.pose.bones])
    elif obj.type == 'CURVE':
        feed([(s.type, [tuple(v.co) for v in s.bezier_points], [tuple(v.co) for v in s.points])
              for s in obj.data.splines])
    return digest.hexdigest()


class OrbitalField:
    def __init__(self, degrees=10.):
        eyes = sorted((o for o in bpy.data.objects if o.type == 'MESH'
                       and o.name.startswith('Eyes_Sclera')),
                      key=lambda o: world(o, local(o))[:, 0].mean())
        assert len(eyes) == 2
        self.centers = []
        for obj in eyes:
            ps = world(obj, local(obj))
            self.centers.append((ps.min(axis=0) + ps.max(axis=0)) * .5)
        self.scale = (self.centers[1][0] - self.centers[0][0]) / .08554
        self.degrees = degrees

    def parameters(self, obj, basis):
        centers = np.asarray(self.centers)
        side = np.argmin(abs(basis[:, None, 0] - centers[None, :, 0]), axis=1)
        pivot = centers[side]
        delta = basis - pivot
        radius = np.sqrt((delta[:, 0] / (.031 * self.scale)) ** 2
                         + (delta[:, 2] / (.030 * self.scale)) ** 2)
        weight = (1. - smooth(1.05, 1.85, radius))
        weight *= 1. - smooth(.012 * self.scale, .062 * self.scale, delta[:, 1])
        if obj.name.startswith('Eyes_'):
            # The entire optical assembly rotates together, preserving round
            # irises and the white/iris/pupil layering, not stretching pixels.
            weight[:] = 1.
        angle = np.deg2rad(self.degrees) * np.where(side == 0, -1., 1.)
        return pivot, weight, np.cos(angle), np.sin(angle)

    @staticmethod
    def linear(vectors, params):
        _, weight, cosine, sine = params
        result = np.zeros_like(vectors, dtype=np.float64)
        result[:, 0] = ((cosine - 1.) * vectors[:, 0] - sine * vectors[:, 2]) * weight
        result[:, 2] = (sine * vectors[:, 0] + (cosine - 1.) * vectors[:, 2]) * weight
        return result


def expanded(values):
    result = dict(values)
    tilt = float(result.get(KEY, 0.))
    for name, amount in list(values.items()):
        if name not in ('Basis', KEY) and not name.startswith('Corrective__'):
            result[PREFIX + name] = tilt * amount
    return result


def posed(obj, values):
    basis = local(obj).astype(np.float64)
    points = basis.copy()
    keys = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
    if keys:
        for name, value in expanded(values).items():
            if name in keys and value:
                points += (array(keys[name].data).astype(np.float64) - basis) * value
    return world(obj, points)
