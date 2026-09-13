"""Round the flat hair locks and seal every open hair shell.

Two defects in the qualified v60 hair are addressed here.

**Flat planks.** v60 measures each lock's root-ring aspect (depth/width) and
holds that ratio constant down the entire lock. Locks are authored flat at the
scalp, so a measured median depth/width of 0.505 makes every strand read as a
plank in profile, and the free length has no volume at all. v61 keeps the
authored root aspect (roots must stay flat against the scalp) but ramps the
section toward circular along the lock. The cross-section *area* is held
constant, so hair mass is unchanged and only the shape rounds out. Measured on
the current adult source: median depth/width 0.505 -> above 0.85.

**Zero-thickness sheets.** Hair objects whose mesh has boundary edges and no
SOLIDIFY modifier render as open sheets; at close range they read as fins
sticking out of the silhouette. Every such object gets a closed 0.007 m shell,
matching the thickness the hair caps already carry.

The pass is purely a cross-section reshape: every ring keeps its own centre and
its own principal frame, so no spine, sway, twist or UV value is disturbed and
the root ring stays byte-exact. Ownership is declared and asserted — the author
fails if any object outside the declared set changes.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

STYLES = ('Hair_Bob', 'Hair_Long', 'Hair_Waves')
RING = 12                       # vertices per cross-section ring
# How far each ring has travelled from the authored root aspect toward a
# circular section, indexed by the ring's own normalised position along the
# lock. The scalp ring stays flat; the free length rounds out.
ROUND_AT = (0.0, 0.55, 0.85, 0.95, 1.0, 1.0, 1.0, 1.0)
ASPECT_FLOOR = 0.50             # never let an authored root degenerate to a blade
SHELL_THICKNESS = 0.007         # matches the thickness the hair caps already carry
# Shells are sealed by material, because thickness must match the surface's
# scale. `Hair` is the main hair shell (caps, back, knot, tail): these are
# body-scale and currently render see-through. `Hair_highlight` ribbons are
# 3-6 mm decorative strips (Hair_Bob_Strand, Hair_Curls_Ridge) and a 7 mm shell
# would double their thickness, so they are deliberately left alone.
SEAL_MATERIALS = ('Hair',)

# Prominent garment openings authored as zero-thickness open sheets. glTF
# materials are single-sided by default, so Godot culls their back faces and
# the inside of the garment shows through as the collar/hood sliver the reviews
# keep recording. Thin garment trim (hems, cuffs, plackets, pockets, ribs,
# drawstrings) is excluded for the same reason as the highlight ribbons.
GARMENT_SEALS = (
    'Outfit_Hoodie_Hood',
    'Outfit_Casual_Top_Collar_binding',
    'Outfit_Cardigan_Binding',
    'Outfit_Cardigan_Binding.001',
)


def digest_object(o):
    h = hashlib.sha256()

    def feed(s):
        h.update(str(s).encode())
        h.update(b'\x00')

    feed(o.name)
    feed(o.parent.name if o.parent else '')
    for attr in ('location', 'rotation_euler', 'scale'):
        feed(tuple(round(c, 7) for c in getattr(o, attr)))
    feed(o.hide_render); feed(o.hide_viewport)
    if o.type == 'MESH':
        me = o.data
        feed(me.name)
        feed([s.material.name if s.material else '' for s in o.material_slots])
        feed(tuple(round(c, 7) for v in me.vertices for c in v.co))
        feed(tuple(tuple(e.vertices) for e in me.edges))
        feed(tuple((tuple(p.vertices), p.material_index, p.use_smooth) for p in me.polygons))
        for layer in me.uv_layers:
            feed(('uv', layer.name, tuple(round(c, 6) for d in layer.data for c in d.uv)))
        feed(tuple(g.name for g in o.vertex_groups))
        feed(tuple((vi, tuple((o.vertex_groups[g.group].name, round(g.weight, 6)) for g in v.groups))
                   for vi, v in enumerate(me.vertices) if len(v.groups)))
        if me.shape_keys:
            feed(tuple(k.name for k in me.shape_keys.key_blocks))
            feed(tuple(round(k.value, 7) for k in me.shape_keys.key_blocks))
            for k in me.shape_keys.key_blocks[1:]:
                feed(tuple(round(c, 7) for v in k.data for c in v.co))
    elif o.type == 'CURVE':
        for spline in o.data.splines:
            if spline.type == 'BEZIER':
                feed(tuple(round(c, 7) for pt in spline.bezier_points for c in pt.co))
            else:
                feed(tuple(round(c, 7) for pt in spline.points for c in pt.co))
    for m in o.modifiers:
        feed((m.name, m.type))
        for prop in ('levels', 'render_levels', 'ratio', 'thickness', 'offset', 'use_even_offset',
                     'use_flip_normals', 'offset_type', 'show_viewport', 'show_render'):
            if hasattr(m, prop):
                feed((prop, getattr(m, prop)))
        if m.type == 'ARMATURE':
            feed('armature:' + (m.object.name if m.object else ''))
    return h.hexdigest()


def principal_axes(points):
    """Covariance eigenvectors (major, second) of a ring's point cloud."""
    c = sum(points, Vector()) / len(points)
    d = [p - c for p in points]
    k = len(d)
    xx = sum(v.x * v.x for v in d) / k; yy = sum(v.y * v.y for v in d) / k; zz = sum(v.z * v.z for v in d) / k
    xy = sum(v.x * v.y for v in d) / k; xz = sum(v.x * v.z for v in d) / k; yz = sum(v.y * v.z for v in d) / k
    cov = ((xx, xy, xz), (xy, yy, yz), (xz, yz, zz))

    def power(matrix):
        v = Vector((1.0, 0.3, 0.7))
        for _ in range(60):
            nv = Vector((matrix[0][0] * v.x + matrix[0][1] * v.y + matrix[0][2] * v.z,
                         matrix[1][0] * v.x + matrix[1][1] * v.y + matrix[1][2] * v.z,
                         matrix[2][0] * v.x + matrix[2][1] * v.y + matrix[2][2] * v.z))
            if nv.length < 1e-18:
                break
            v = nv.normalized()
        return v

    u = power(cov)
    lam = sum(cov[i][j] * u[i] * u[j] for i in range(3) for j in range(3))
    second = power([[cov[i][j] - lam * u[i] * u[j] for j in range(3)] for i in range(3)])
    return u, second


def ring_indices(count):
    """Split a lock's vertex indices into cross-section rings (and any pole)."""
    if count % RING == 0:
        return [list(range(i, i + RING)) for i in range(0, count, RING)], None
    remainder = count - 1
    assert remainder % RING == 0 and remainder > 0, f'unexpected lock vertex count {count}'
    rings = [list(range(i, i + RING)) for i in range(0, remainder, RING)]
    return rings, count - 1


def measure_ring(points):
    """Centre, principal frame, semi-axes and each vertex's angle in that frame."""
    c = sum(points, Vector()) / len(points)
    u, v = principal_axes(points)
    a = max(abs((p - c).dot(u)) for p in points)
    b = max(abs((p - c).dot(v)) for p in points)
    angles = [math.atan2((p - c).dot(v), (p - c).dot(u)) for p in points]
    return c, u, v, a, b, angles


def ramp_at(position):
    """Rounding fraction for a ring at `position` in [0, 1] along the lock."""
    if position <= 0:
        return ROUND_AT[0]
    scaled = position * (len(ROUND_AT) - 1)
    low = int(scaled)
    if low >= len(ROUND_AT) - 1:
        return ROUND_AT[-1]
    frac = scaled - low
    return ROUND_AT[low] * (1 - frac) + ROUND_AT[low + 1] * frac


def round_lock(o):
    """Reshape one lock's rings toward circular, holding each section's area."""
    me = o.data
    mw = o.matrix_world
    world = [mw @ v.co for v in me.vertices]
    rings, pole = ring_indices(len(me.vertices))
    assert len(rings) >= 3, f'{o.name}: expected at least three rings'

    measured = [measure_ring([world[i] for i in ring]) for ring in rings]
    root_b = measured[0][4]
    root_a = measured[0][3]
    assert root_a > 1e-6, f'{o.name}: degenerate root ring'
    root_aspect = max(ASPECT_FLOOR, min(0.95, root_b / root_a))

    inv = mw.inverted()
    aspect_trace = []
    for index, ring in enumerate(rings):
        c, u, v, a, b, angles = measured[index]
        position = index / (len(rings) - 1)
        target_aspect = root_aspect + (1.0 - root_aspect) * ramp_at(position)
        aspect_trace.append(round(target_aspect, 4))
        if index == 0 or abs(target_aspect - (b / a)) < 1e-9:
            continue  # the scalp ring keeps its authored section byte-exactly
        # Hold a*b constant so mass does not change; only the shape rounds out.
        new_a = math.sqrt((a * b) / target_aspect)
        new_b = new_a * target_aspect
        for slot, vertex_index in enumerate(ring):
            theta = angles[slot]
            point = c + u * (new_a * math.cos(theta)) + v * (new_b * math.sin(theta))
            me.vertices[vertex_index].co = inv @ point

    me.update()
    facts = {'name': o.name, 'verts': len(me.vertices), 'faces': len(me.polygons),
             'rings': len(rings), 'root_aspect': round(root_aspect, 4),
             'station_aspect': aspect_trace,
             'materials': [s.material.name for s in o.material_slots],
             'modifiers': [(m.name, m.type) for m in o.modifiers],
             'uv_layers': [u.name for u in me.uv_layers]}
    assert pole is None or pole == len(me.vertices) - 1
    assert facts['uv_layers'] == ['SurfaceUV'], f'{o.name}: uv layers changed'
    assert aspect_trace[-1] > aspect_trace[0], f'{o.name}: section never rounds'
    assert max(aspect_trace) <= 1.0001, f'{o.name}: over-rounded section'
    # The scalp ring must be bit-identical to the input.
    for slot, vertex_index in enumerate(rings[0]):
        assert (mw @ me.vertices[vertex_index].co - world[vertex_index]).length <= 1e-9, \
            f'{o.name}: root ring moved'
    return facts


def surface_material(o):
    return o.data.materials[0].name if o.data.materials else ''


def boundary_edges(me):
    """Count edges used by exactly one face (an open shell's free border)."""
    used = {}
    for poly in me.polygons:
        for key in poly.edge_keys:
            used[key] = used.get(key, 0) + 1
    return sum(1 for count in used.values() if count == 1)


def seal_shell(o):
    """Close an open shell so it never renders as a zero-thickness sheet.

    The modifier is moved to the front of the stack so the armature (and any
    LOD decimation) evaluates the finished, closed surface rather than a
    sheet that is only closed after deformation.
    """
    open_edges = boundary_edges(o.data)
    add = o.modifiers.new('Hair shell', 'SOLIDIFY')
    add.thickness = SHELL_THICKNESS
    bpy.context.view_layer.objects.active = o
    while o.modifiers.find(add.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=add.name)
    return {'name': o.name, 'open_edges': open_edges, 'thickness': SHELL_THICKNESS,
            'material': surface_material(o),
            'modifier_order': [m.name for m in o.modifiers]}


bpy.ops.wm.open_mainfile(filepath=str(args.input))
D = bpy.data
before_digests = {o.name: digest_object(o) for o in D.objects}
report = {'input': str(args.input), 'objects_total': len(D.objects)}

lock_reports = {}
for style in STYLES:
    entries = [round_lock(o) for o in D.objects if o.name.split('.')[0] == style + '_Lock']
    assert len(entries) == 12, f'{style}: expected 12 locks, found {len(entries)}'
    lock_reports[style] = entries
report['locks'] = lock_reports

sealed = []
for o in sorted(D.objects, key=lambda x: x.name):
    if o.type != 'MESH':
        continue
    if surface_material(o) not in SEAL_MATERIALS and o.name not in GARMENT_SEALS:
        continue
    if any(m.type == 'SOLIDIFY' for m in o.modifiers):
        continue
    if o.data.shape_keys is not None:
        continue  # morph-driven meshes keep their authored single surface
    if boundary_edges(o.data) == 0:
        continue
    sealed.append(seal_shell(o))
report['sealed_shells'] = sealed

after_digests = {o.name: digest_object(o) for o in D.objects}
assert set(after_digests) == set(before_digests), 'object set changed'
changed = sorted(name for name in before_digests if before_digests[name] != after_digests[name])
expected = sorted([o.name for o in D.objects if o.name.split('.')[0] in {s + '_Lock' for s in STYLES}]
                  + [entry['name'] for entry in sealed])
assert changed == expected, f'unexpected changed objects: {set(changed) ^ set(expected)}'
report['changed_objects'] = len(changed)
report['unchanged_objects'] = len(D.objects) - len(changed)

args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(args.output), copy=False)
report['output'] = str(args.output)
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('AUTHOR_COMPLETE ' + json.dumps({'changed': report['changed_objects'],
                                       'unchanged': report['unchanged_objects'],
                                       'sealed': len(sealed)}))
