"""Author coherent portrait eye geometry and surface-fitted eyebrows.

The production v61 iris Mesh.vertices disagrees with its Basis morph. Rebuild
the visible discs against the true sclera surface for every existing morph,
and fit eyebrows to the actual head for each supported identity morph.
Only candidate destinations are written; use export_variant.py to export.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
ap.add_argument('--iris-only', action='store_true')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert args.source.resolve() != args.output.resolve(), 'Candidate output required'
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
bpy.context.view_layer.update()
D = bpy.data
report = {'source': str(args.source), 'sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
          'iris': [], 'brows': []}


def points(obj, key='Basis'):
    keys = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
    verts = keys.get(key, keys['Basis']).data if keys else obj.data.vertices
    return [obj.matrix_world @ v.co for v in verts]


def tree(obj, key='Basis'):
    return BVHTree.FromPolygons(points(obj, key), [tuple(p.vertices) for p in obj.data.polygons])


def surface(bvh, x, z):
    hit, _, _, _ = bvh.ray_cast(Vector((x, -2.0, z)), Vector((0, 1, 0)), 4.0)
    return hit.y if hit is not None else None


def bounds(ps):
    return Vector(tuple(min(p[i] for p in ps) for i in range(3))), Vector(tuple(max(p[i] for p in ps) for i in range(3)))


eye_suffixes = ('', '.001') if 'Eyes_Sclera' in D.objects else ('_L', '_R')
for suffix in eye_suffixes:
    sclera = D.objects['Eyes_Sclera' + suffix]
    if suffix in ('_L', '_R'):
        inverse = sclera.matrix_world.inverted()
        for key in sclera.data.shape_keys.key_blocks:
            original = points(sclera, key.name)
            lo, hi = bounds(original)
            center_z = (lo.z + hi.z) * .5
            for i, p in enumerate(original):
                p.z = center_z + (p.z - center_z) * .72
                key.data[i].co = inverse @ p
        for i, vertex in enumerate(sclera.data.vertices):
            vertex.co = sclera.data.shape_keys.key_blocks['Basis'].data[i].co
        sclera.data.update()
    ps = points(sclera)
    lo, hi = bounds(ps)
    center = (lo + hi) * .5
    eye_scale = (hi.x - lo.x) / .05096
    # Iris diameter is 40% of the globe width, with a soft circular silhouette.
    radius = (.0144 if suffix in ('_L', '_R') else .0103) * eye_scale
    iris_center = center.copy()
    iris_center.z += .0004 * eye_scale
    near = min(range(len(ps)), key=lambda i: (ps[i] - Vector((center.x, lo.y, center.z))).length)
    keys = sclera.data.shape_keys.key_blocks
    sclera_trees = {key.name: tree(sclera, key.name) for key in keys}
    shifts = {key.name: points(sclera, key.name)[near] - ps[near] for key in keys}
    for prefix, relative_radius, depth in [('Eyes_Iris_edge', 1.0, .00020),
                                         ('Eyes_Iris', .92, .00038),
                                         ('Eyes_Pupil', .405, .00057)]:
        obj = D.objects[prefix + suffix]
        old = points(obj)
        old_lo, old_hi = bounds(old)
        old_center = (old_lo + old_hi) * .5
        half = (old_hi - old_lo) * .5
        coords = [((p.x - old_center.x) / half.x, (p.z - old_center.z) / half.z) for p in old]
        inv = obj.matrix_world.inverted()
        maximum_mismatch = max((v.co - obj.data.shape_keys.key_blocks['Basis'].data[i].co).length
                               for i, v in enumerate(obj.data.vertices))
        for name in keys.keys():
            if name not in obj.data.shape_keys.key_blocks:
                obj.shape_key_add(name=name)
        for key in obj.data.shape_keys.key_blocks:
            shift = shifts.get(key.name, Vector())
            bvh = sclera_trees.get(key.name, sclera_trees['Basis'])
            for i, (u, v) in enumerate(coords):
                x = iris_center.x + u * radius * relative_radius + shift.x
                z = iris_center.z + v * radius * relative_radius + shift.z
                y = surface(bvh, x, z)
                assert y is not None, (obj.name, key.name, x, z)
                thickness = 0
                if suffix in ('_L', '_R'):
                    # Infant layers were actual UV spheres, unlike the adult
                    # patches: retain a fine thickness so opposite surfaces
                    # do not become coincident, z-fighting colored polygons.
                    thickness = .00010 * eye_scale * ((old[i].y - old_center.y) / half.y + 1) * .5
                key.data[i].co = inv @ Vector((x, y - depth * eye_scale + thickness, z))
        for i, vertex in enumerate(obj.data.vertices):
            vertex.co = obj.data.shape_keys.key_blocks['Basis'].data[i].co
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.update()
        report['iris'].append({'name': obj.name, 'repaired_mesh_basis_mismatch': maximum_mismatch,
                               'diameter': 2 * radius * relative_radius,
                               'morphs': list(obj.data.shape_keys.key_blocks.keys())})

    # Keep the authored catchlight, but seat it on the same eye surface after
    # the iris contour changes. Every morph remains coupled to its sclera.
    catch = D.objects['Eyes_Catchlight' + suffix]
    old = points(catch)
    clo, chi = bounds(old)
    cc = (clo + chi) * .5
    target = iris_center + Vector((-.0029 * eye_scale, 0, .0035 * eye_scale))
    inv = catch.matrix_world.inverted()
    for name in keys.keys():
        if name not in catch.data.shape_keys.key_blocks:
            catch.shape_key_add(name=name)
    for key in catch.data.shape_keys.key_blocks:
        shift = shifts.get(key.name, Vector())
        bvh = sclera_trees.get(key.name, sclera_trees['Basis'])
        for i, p in enumerate(old):
            x = target.x + (p.x - cc.x) * .78 + shift.x
            z = target.z + (p.z - cc.z) * .78 + shift.z
            y = surface(bvh, x, z)
            assert y is not None
            key.data[i].co = inv @ Vector((x, y - .00080 * eye_scale + (p.y - cc.y) * .5, z))
    for i, v in enumerate(catch.data.vertices):
        v.co = catch.data.shape_keys.key_blocks['Basis'].data[i].co
    catch.data.update()

head = D.objects['Skin_Head_continuous']
head_trees = {key.name: tree(head, key.name) for key in head.data.shape_keys.key_blocks}
for suffix in (() if args.iris_only else ('', '.001')):
    obj = D.objects['Hair_Brow' + suffix]
    old = points(obj)
    lo, hi = bounds(old)
    scale = (hi.x - lo.x) / .05187
    inv = obj.matrix_world.inverted()
    old_depths = [p.y - surface(head_trees['Basis'], p.x, p.z) for p in old]
    for key in obj.data.shape_keys.key_blocks:
        key_points = points(obj, key.name)
        bvh = head_trees.get(key.name, head_trees['Basis'])
        for i, p in enumerate(key_points):
            skin_y = surface(bvh, p.x, p.z)
            assert skin_y is not None
            # Preserve ribbon thickness while bringing the full existing brow
            # just above the forehead. It was entirely occluded in v61.
            depth = .00042 * scale + max(0.0, max(old_depths) - old_depths[i]) * .62
            p.y = skin_y - depth
            key.data[i].co = inv @ p
    for i, vertex in enumerate(obj.data.vertices):
        vertex.co = obj.data.shape_keys.key_blocks['Basis'].data[i].co
    obj.data.update()
    report['brows'].append({'name': obj.name, 'previously_occluded_vertices': sum(d > 0 for d in old_depths),
                            'vertices': len(old), 'old_depth_range': [min(old_depths), max(old_depths)]})

for obj in D.objects:
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            key.value = 0.0
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('PORTRAIT_V62_AUTHORED', json.dumps(report))
