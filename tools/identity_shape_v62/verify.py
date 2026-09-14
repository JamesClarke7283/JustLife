"""Verify exact preservation, shared fields and signed composed native geometry."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import struct
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import CONTACT_PREFIXES, Geometry, NEW, OLD, mean, mouth_offsets, points, posed

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--baseline', type=Path, required=True)
ap.add_argument('--candidate', type=Path, required=True)
ap.add_argument('--report', type=Path, required=True)
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])


def digest(coords):
    h = hashlib.sha256()
    for p in coords:
        h.update(struct.pack('<3f', *p.co))
    return h.hexdigest()


def hashed(value):
    return hashlib.sha256(repr(value).encode()).hexdigest()


def facts():
    result = {}
    for o in bpy.data.objects:
        row = {'type': o.type, 'parent': o.parent.name if o.parent else None,
               'parent_type': o.parent_type, 'parent_bone': o.parent_bone,
               'matrix': tuple(v for r in o.matrix_world for v in r),
               'modifiers': [(m.name, m.type, getattr(getattr(m, 'object', None), 'name', None))
                             for m in o.modifiers]}
        if o.type == 'MESH':
            row['vertices'] = digest(o.data.vertices)
            row['topology'] = hashed([(tuple(p.vertices), p.material_index, p.use_smooth)
                                      for p in o.data.polygons])
            row['uv'] = hashed([(uv.name, [tuple(v.uv) for v in uv.data]) for uv in o.data.uv_layers])
            row['materials'] = [m.name if m else None for m in o.data.materials]
            row['weights'] = hashed([(g.name, g.index) for g in o.vertex_groups] +
                                    [[(g.group, g.weight) for g in v.groups] for v in o.data.vertices])
            row['orbital_indices'] = {key: list(o[key]) for key in
                                      ('orbit_inner_0', 'orbit_inner_1', 'orbit_shared_0', 'orbit_shared_1')
                                      if key in o}
            row['keys'] = {k.name: {'geometry': digest(k.data), 'relative': k.relative_key.name,
                                  'slider_min': k.slider_min, 'slider_max': k.slider_max,
                                  'value': k.value, 'mute': k.mute, 'group': k.vertex_group}
                           for k in o.data.shape_keys.key_blocks if k.name not in NEW} if o.data.shape_keys else {}
        if o.type == 'ARMATURE':
            row['bones'] = [(b.name, tuple(b.head_local), tuple(b.tail_local),
                             tuple(v for r in b.matrix_local for v in r),
                             b.parent.name if b.parent else None) for b in o.data.bones]
        result[o.name] = row
    return result


bpy.ops.wm.open_mainfile(filepath=str(args.baseline.resolve()))
bpy.context.view_layer.update()
before = facts()
neutral_anchor = list(bpy.data.objects['Character']['mouth_anchor'])
bpy.ops.wm.open_mainfile(filepath=str(args.candidate.resolve()))
bpy.context.view_layer.update()
after = facts()
failures = []
assert set(before) == set(after), 'Objects added or removed'
for name, a in before.items():
    b = after[name]
    if not a.get('keys') and b.get('keys'):
        assert set(b['keys']) == {'Basis'} and b['keys']['Basis']['geometry'] == a['vertices'], name
        b = dict(b, keys={})
    assert a == b, ('Existing object, topology, weights, rig, or key changed', name)
g = Geometry()


class PoseCache:
    """Vectorized checks of the native targets, without evaluating or editing them."""
    def __init__(self):
        self.meshes = {}

    def array(self, obj, values):
        if obj.name not in self.meshes:
            blocks = obj.data.shape_keys.key_blocks if obj.data.shape_keys else None
            basis = np.array([v.co[:] for v in blocks['Basis'].data] if blocks
                             else [v.co[:] for v in obj.data.vertices], dtype=np.float64)
            deltas = {k.name: np.array([v.co[:] for v in k.data], dtype=np.float64) - basis
                      for k in blocks if k.name != 'Basis'} if blocks else {}
            matrix = np.array(obj.matrix_world, dtype=np.float64)
            self.meshes[obj.name] = basis, deltas, matrix
        basis, deltas, matrix = self.meshes[obj.name]
        local = basis.copy()
        for name, value in values.items():
            if value and name in deltas:
                local += deltas[name] * value
        return local @ matrix[:3, :3].T + matrix[:3, 3]

    def points(self, obj, values):
        return [Vector(p) for p in self.array(obj, values)]


pose_cache = PoseCache()
posed = pose_cache.points
assert list(g.root['mouth_anchor']) == neutral_anchor
offsets = mouth_offsets(g)
assert set(g.root['mouth_identity_offsets'].keys()) == {k.lower() for k in OLD + NEW}
for key, expected in offsets.items():
    assert max(abs(a - b) for a, b in zip(g.root['mouth_identity_offsets'][key], expected)) < 1e-8

found = set()
field_checks = []
affected = []
for o in bpy.data.objects:
    if o.type != 'MESH' or not o.name.startswith(CONTACT_PREFIXES):
        continue
    blocks = o.data.shape_keys.key_blocks if o.data.shape_keys else None
    base = points(o)
    worst = 0.
    for name in NEW:
        expected = [g.field(name, p) for p in base]
        maximum = max(v.length for v in expected)
        if blocks and name in blocks:
            found.add(name)
            key = blocks[name]
            assert (key.slider_min, key.slider_max, key.value) == (-1., 1., 0.)
            assert key.relative_key.name == 'Basis' and maximum > 1e-7
            target = points(o, name)
            error = max(((b - a) - e).length for a, b, e in zip(base, target, expected))
            worst = max(worst, error)
            assert error < 4e-7, ('Shared field mismatch', o.name, name, error)
        else:
            assert maximum < 1e-7, ('Missing contacting surface key', o.name, name, maximum)
    if blocks and any(k in blocks for k in NEW):
        o.data.calc_loop_triangles()
        affected.append((o, [tuple(t.vertices) for t in o.data.loop_triangles]))
        field_checks.append({'object': o.name, 'maximum_world_field_rounding_m': worst})
assert found == set(NEW)

# All six endpoints and all eight signed corners. Repeat the corners against
# three prior-identity extremes and expression contexts. Old deformations are
# compared with their own baseline, so pre-existing issues are not disguised.
contexts = [({}, 'neutral'), (dict.fromkeys(OLD[:4], 1.), 'old_unsigned_max'),
            ({**dict.fromkeys(OLD[:4], 1.), **dict.fromkeys(OLD[4:], 1.)}, 'old_all_positive'),
            ({**dict.fromkeys(OLD[:4], 1.), **dict.fromkeys(OLD[4:], -1.)}, 'old_signed_negative'),
            ({'Smile': 1., 'Blink': 1.}, 'smile_blink')]
if g.orbits:
    contexts += [({**context, 'Blink': 1.}, label + '_blink')
                 for context, label in contexts[1:4]]
cases = [(k + ('_min' if sign < 0 else '_max'), {}, {k: float(sign)})
         for k in NEW for sign in (-1, 1)]
for context, label in contexts:
    for signs in itertools.product((-1., 1.), repeat=3):
        values = dict(zip(NEW, signs))
        cases.append((label + '_' + ''.join('p' if v > 0 else 'm' for v in signs), context, values))

head_tris = next(ts for o, ts in affected if o == g.head)
checks = []
# Pair the nearest native upper/lower lip vertices once, retaining their exact
# attachment identities across every deformation. Also test near-head lip rim
# vertices against a fixed corresponding head triangle via nearest surfaces.
upper = bpy.data.objects['Lips_Upper_soft']
lower = bpy.data.objects['Lips_Lower_soft']
u0, l0 = points(upper), points(lower)
lip_pairs = []
for i in range(0, len(u0), max(1, len(u0) // 80)):
    j = min(range(len(l0)), key=lambda j: (u0[i] - l0[j]).length_squared)
    if (u0[i] - l0[j]).length < .0015 * g.ipd / .08554:
        lip_pairs.append((i, j))
assert lip_pairs, 'No measured lip seam contact pairs'

for label, context, new_values in cases:
    values = {**context, **new_values}
    row = {'case': label, 'values': values, 'meshes': []}
    head_before, head_after = posed(g.head, context), posed(g.head, values)
    tree_before = BVHTree.FromPolygons(head_before, head_tris, all_triangles=True)
    tree_after = BVHTree.FromPolygons(head_after, head_tris, all_triangles=True)
    for o, triangles in affected:
        base, target = pose_cache.array(o, context), pose_cache.array(o, values)
        indices = np.asarray(triangles, dtype=np.int32)
        n0 = np.cross(base[indices[:, 1]] - base[indices[:, 0]],
                      base[indices[:, 2]] - base[indices[:, 0]])
        n1 = np.cross(target[indices[:, 1]] - target[indices[:, 0]],
                      target[indices[:, 2]] - target[indices[:, 0]])
        area0, area1 = np.linalg.norm(n0, axis=1), np.linalg.norm(n1, axis=1)
        valid = area0 >= 1e-10
        tested = int(np.count_nonzero(valid))
        flips = int(np.count_nonzero(np.sum(n0[valid] * n1[valid], axis=1) < 0))
        minimum = float(np.min(area1[valid] / area0[valid])) if tested else 1.
        row['meshes'].append({'object': o.name, 'triangles_tested': tested,
                              'orientation_reversals': flips, 'minimum_area_ratio': minimum})
        if flips or minimum <= .05:
            failures.append([label, o.name, 'orientation_or_area', flips, minimum])
    brow_regressions, max_depth_increase = 0, 0.
    for brow in (o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Hair_Brow')):
        for a, b in zip(posed(brow, context), posed(brow, values)):
            ha = tree_before.ray_cast(Vector((a.x, -2., a.z)), Vector((0., 1., 0.)), 4.)[0]
            hb = tree_after.ray_cast(Vector((b.x, -2., b.z)), Vector((0., 1., 0.)), 4.)[0]
            if ha is not None and hb is not None:
                increase = (b.y - hb.y) - (a.y - ha.y)
                max_depth_increase = max(max_depth_increase, increase)
                brow_regressions += int(increase > .00015 and b.y - hb.y > .00025)
    row['brow_coupling'] = {'burial_regressions': brow_regressions,
                            'max_depth_increase_m': max_depth_increase}
    if brow_regressions:
        failures.append([label, 'brow_burial', brow_regressions])
    ua, la = posed(upper, context), posed(lower, context)
    ub, lb = posed(upper, values), posed(lower, values)
    stretch = []
    for i, j in lip_pairs:
        old_gap, new_gap = (ua[i] - la[j]).length, (ub[i] - lb[j]).length
        stretch.append(new_gap - old_gap)
        if new_gap > old_gap * 1.35 + .00005:
            failures.append([label, 'lip_join_gap', i, j, old_gap, new_gap])
    # A surface field can move both lips coherently while different sampling of
    # the supporting head opens a crack. Measure the thin outer rim as well.
    rim_changes = []
    for lip, base, target in ((upper, ua, ub), (lower, la, lb)):
        for i in range(0, len(base), max(1, len(base) // 120)):
            old_distance = tree_before.find_nearest(base[i])[3]
            if old_distance is None or old_distance > .0005:
                continue
            new_distance = tree_after.find_nearest(target[i])[3]
            if new_distance is not None:
                rim_changes.append(new_distance - old_distance)
                if new_distance > old_distance * 1.35 + .0002:
                    failures.append([label, 'lip_skin_contact', lip.name, i, old_distance, new_distance])
    row['lip_coupling'] = {'measured_join_pairs': len(lip_pairs),
                           'max_join_gap_increase_m': max(stretch),
                           'measured_head_rim_samples': len(rim_changes),
                           'max_rim_distance_increase_m': max(rim_changes, default=0.)}
    if g.orbits:
        orbit_checks = []
        for orbit in g.orbits:
            ids = orbit['inner']
            aperture_change = max((head_after[i] - head_before[i]).length for i in ids)
            if aperture_change > 1e-7:
                failures.append([label, 'welded_aperture_moved', orbit['side'], aperture_change])
            check = {'side': orbit['side'], 'max_new_aperture_change_m': aperture_change}
            if values.get('Blink') == 1.:
                gap = max((head_after[ids[i]] - head_after[ids[(64 - i) % 64]]).length
                          for i in range(33))
                if gap >= .0003:
                    failures.append([label, 'welded_blink_gap', orbit['side'], gap])
                suffix = '' if orbit['side'] == 0 else '.001'
                globe = bpy.data.objects['Eyes_Sclera' + suffix]
                globe_points = posed(globe, values)
                globe_tree = BVHTree.FromPolygons(globe_points,
                                                  [tuple(p.vertices) for p in globe.data.polygons])
                low = Vector(tuple(min(p[i] for p in globe_points) for i in range(3)))
                high = Vector(tuple(max(p[i] for p in globe_points) for i in range(3)))
                samples, exposure, max_exposure = 0, 0, 0.
                for ix in range(41):
                    x = low.x + (high.x - low.x) * (ix + .5) / 41
                    for iz in range(25):
                        z = low.z + (high.z - low.z) * (iz + .5) / 25
                        origin, direction = Vector((x, -2., z)), Vector((0., 1., 0.))
                        eye_hit = globe_tree.ray_cast(origin, direction, 4.)[0]
                        if eye_hit is None:
                            continue
                        head_hit = tree_after.ray_cast(origin, direction, 4.)[0]
                        samples += 1
                        distance = head_hit.y - eye_hit.y if head_hit is not None else 10.
                        if distance > .0001:
                            exposure += 1
                            max_exposure = max(max_exposure, distance)
                if exposure:
                    failures.append([label, 'welded_blink_globe_exposure', orbit['side'], exposure, max_exposure])
                check.update({'closed_gap_max_m': gap, 'globe_ray_samples': samples,
                              'exposed_globe_samples': exposure, 'max_globe_exposure_m': max_exposure})
            orbit_checks.append(check)
        row['welded_orbit_checks'] = orbit_checks
    checks.append(row)
    print('IDENTITY_SHAPE_CASE', label, 'failures', len(failures), flush=True)

report = {'baseline': str(args.baseline.resolve()), 'candidate': str(args.candidate.resolve()),
          'baseline_sha256': hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
          'candidate_sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
          'neutral_topology_weights_rig_hair_old_keys_exact': True,
          'protected_objects': len(before), 'new_controls': list(NEW),
          'mouth_anchor_unchanged': neutral_anchor, 'mouth_identity_offsets': offsets,
          'anchors': g.report(), 'shared_field_checks': field_checks,
          'pose_check_precision': 'Native float32 shape targets composed in float64 for vectorized geometry checks; no scene edits.',
          'signed_endpoint_and_composition_cases': checks, 'failures': failures,
          'passed': not failures}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('IDENTITY_SHAPE_' + ('PASS' if not failures else 'FAIL'),
      len(checks), 'cases', len(failures), 'failures', args.report, flush=True)
assert not failures, failures[:12]
