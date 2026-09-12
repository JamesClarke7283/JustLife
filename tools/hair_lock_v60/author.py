"""Re-author Bob/Long/Waves locks and seat the hoodie hood, one family blend.

    blender --background --python tools/hair_lock_v60/author.py -- \
        --input art/characters.blend --output dist/.../characters.blend \
        --report dist/.../report_adult.json

The pinned input is opened read-only; the candidate is written to --output and
the input file is never modified. Every object is digested before and after;
only the thirty-six intended objects (36 locks plus the hoodie hood) may
differ. Locks become rounded tapered tubes: the root ring keeps the original
vertices exactly, the cross-sections stay convex ellipses, the radius tapers
to a soft rounded pole tip, and the free end gains a slight deterministic
droop, twist and sway. The hood's lower roll is pressed at least eight
millimetres into the untouched shell surface so no background sliver remains
between cowl and shoulders; hood vertices beyond the blend band are untouched
and no new vertices are introduced, so the qualified skin weights stand.
"""
import bpy, bmesh, argparse, hashlib, json, math, sys
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

STYLES = ('Hair_Bob', 'Hair_Long', 'Hair_Waves')
RING = 12                                  # vertices per cross-section ring
STATIONS = (0.0, 0.16, 0.34, 0.54, 0.74, 0.90)   # ring stations along the spine
RADIUS = (1.0, 1.0, 0.96, 0.87, 0.68, 0.40)      # tip rounding per station
# per-style organic parameters, fractions of the lock spine length
TUNE = {
    'Hair_Bob':   {'sag': 0.10, 'twist': 0.30, 'sway': 0.020},
    'Hair_Long':  {'sag': 0.12, 'twist': 0.45, 'sway': 0.035},
    'Hair_Waves': {'sag': 0.11, 'twist': 0.55, 'sway': 0.045},
}
SWAY_FREQ = 1.15
HOOD_TARGET = 0.012    # pressed depth inside the shell
HOOD_NEAR = 0.045      # proximity criterion upper bound
HOOD_RAY_NEAR = 0.06   # full seat while hovering this close above the shell
HOOD_RAY_FAR = 0.12    # no seat beyond this hover height


def cr4(values, t):
    """Catmull-Rom through four values, endpoint-clamped, t in [0, 1]."""
    if t <= 0:
        return values[0]
    if t >= 1:
        return values[3]
    x = t * 3.0
    j = min(2, int(x))
    s = x - j
    p0 = values[max(0, j - 1)]; p1 = values[j]; p2 = values[j + 1]; p3 = values[min(3, j + 2)]
    return 0.5 * ((2 * p1) + (-p0 + p2) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * s * s * s)


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
            nv = Vector((matrix[0][0]*v.x + matrix[0][1]*v.y + matrix[0][2]*v.z,
                         matrix[1][0]*v.x + matrix[1][1]*v.y + matrix[1][2]*v.z,
                         matrix[2][0]*v.x + matrix[2][1]*v.y + matrix[2][2]*v.z))
            if nv.length < 1e-18:
                break
            v = nv.normalized()
        return v
    u = power(cov)
    lam = sum(cov[i][j] * u[i] * u[j] for i in range(3) for j in range(3))
    second = power([[cov[i][j] - lam * u[i] * u[j] for j in range(3)] for i in range(3)])
    return u, second


def ring_frame(points, tangent_hint):
    """Orthonormal (u, v, w): w along tangent_hint, u the ring's major axis."""
    u, v = principal_axes(points)
    w = u.cross(v).normalized()
    if w.dot(tangent_hint) < 0:
        w = -w
    v = w.cross(u).normalized()
    u = v.cross(w).normalized()
    return u, v, w


def rotation_between(a, b):
    c = max(-1.0, min(1.0, a.dot(b)))
    v = a.cross(b)
    if v.length < 1e-12:
        return Matrix.Identity(3) if c > 0 else Matrix.Rotation(math.pi, 3, Vector((0, 0, 1)))
    return Matrix.Rotation(math.acos(c), 3, v.normalized())


def orientation_sign(points, faces):
    """+1 when the wound face normals point outward from the volume centroid."""
    centroid = sum(points, Vector()) / len(points)
    total = 0.0
    for face in faces:
        vs = [points[i] for i in face]
        n = Vector((0.0, 0.0, 0.0))
        for i in range(len(vs)):
            a = vs[i]; b = vs[(i + 1) % len(vs)]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        fc = sum(vs, Vector()) / len(vs)
        total += n.dot(fc - centroid)
    return 1.0 if total > 0 else -1.0


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


def rebuild_lock(o):
    me = o.data
    assert len(me.vertices) == 48 and len(me.polygons) == 38, f'{o.name}: unexpected topology'
    mw = o.matrix_world
    world = [mw @ v.co for v in me.vertices]
    rings = [world[r * RING:(r + 1) * RING] for r in range(4)]
    centers = [sum(r, Vector()) / RING for r in rings]
    spine_len = sum((centers[i + 1] - centers[i]).length for i in range(3))
    ab = []
    for r in rings:
        u, v = principal_axes(r)
        c = sum(r, Vector()) / RING
        ab.append((max(abs((p - c).dot(u)) for p in r), max(abs((p - c).dot(v)) for p in r)))
    aspect = max(0.55, min(0.95, ab[0][1] / ab[0][0]))
    u0, v0, w0 = ring_frame(rings[0], centers[1] - centers[0])
    root_angles = []
    for p in rings[0]:
        d = p - centers[0]
        root_angles.append(math.atan2(d.dot(v0), d.dot(u0)))
    style = o.name.split('_Lock')[0]
    tune = TUNE[style]
    seed = sum(ord(c) for c in o.name)
    twist_sign = 1.0 if seed % 2 == 0 else -1.0
    phase = (seed % 628) / 100.0

    def spine(t):
        c = Vector((cr4([p.x for p in centers], t), cr4([p.y for p in centers], t), cr4([p.z for p in centers], t)))
        c.z -= tune['sag'] * spine_len * (t ** 1.7)
        return c

    # parallel-transported frames at every station after the root
    frames = [(u0, v0, w0)]
    for t in STATIONS[1:]:
        here = spine(t)
        ahead = spine(min(1.0, t + 0.02))
        tangent = (ahead - here).normalized()
        pu, pv, pw = frames[-1]
        rot = rotation_between(pw, tangent)
        nu = (rot @ pu).normalized()
        nw = tangent.copy()
        nv = nw.cross(nu).normalized()
        frames.append((nu, nv, nw))
    stations = []
    for si, t in enumerate(STATIONS):
        u, v, w = frames[si]
        sway = 0.0 if si == 0 else tune['sway'] * spine_len * math.sin(2.0 * math.pi * SWAY_FREQ * t + phase)
        a = cr4([x[0] for x in ab], t) * RADIUS[si]
        stations.append((spine(t) + u * sway, u, v, a, a * aspect))

    # Mesh data lives in object-local space. The root ring keeps the original
    # local vertices byte-exactly; generated rings convert from world space.
    inv = mw.inverted()
    orig_local = [v.co.copy() for v in me.vertices]
    verts = [orig_local[k] for k in range(RING)]
    ring_start = [0]
    for si in range(1, len(STATIONS)):
        c, u, v, a, b = stations[si]
        tau = twist_sign * tune['twist'] * STATIONS[si]
        base = len(verts)
        for k in range(RING):
            th = root_angles[k] + tau
            verts.append(inv @ (c + u * (a * math.cos(th)) + v * (b * math.sin(th))))
        ring_start.append(base)
    pole_index = len(verts)
    verts.append(inv @ spine(1.0))

    faces = []
    for seg in range(len(STATIONS) - 1):
        cur = ring_start[seg]; nxt = ring_start[seg + 1]
        for k in range(RING):
            k1 = (k + 1) % RING
            faces.append((cur + k, cur + k1, nxt + k1, nxt + k))
    last = ring_start[-1]
    for k in range(RING):
        k1 = (k + 1) % RING
        faces.append((last + k, last + k1, pole_index))
    faces.append(tuple(range(RING)))
    if orientation_sign(verts, faces) * orientation_sign(world, [tuple(p.vertices) for p in me.polygons]) < 0:
        faces = [tuple(reversed(f)) for f in faces]

    bm = bmesh.new()
    bvs = [bm.verts.new(p) for p in verts]
    for face in faces:
        bm.faces.new([bvs[i] for i in face])
    bm.faces.ensure_lookup_table()
    uv = bm.loops.layers.uv.new('SurfaceUV')

    def uv_at(k_index, t):
        tau = twist_sign * tune['twist'] * t
        return (((k_index + tau) % RING) / RING, t)

    n_side = (len(STATIONS) - 1) * RING
    for si, face in enumerate(bm.faces):
        face.smooth = True
        if si < n_side:
            seg, k = divmod(si, RING)
            t_cur, t_nxt = STATIONS[seg], STATIONS[seg + 1]
            ks = (k, (k + 1) % RING, (k + 1) % RING, k)
            ts = (t_cur, t_cur, t_nxt, t_nxt)
            for li, loop in enumerate(face.loops):
                loop[uv].uv = uv_at(ks[li], ts[li])
        elif si < n_side + RING:
            k = si - n_side
            ks = (k, (k + 1) % RING, k)
            ts = (STATIONS[-1], STATIONS[-1], 1.0)
            for li, loop in enumerate(face.loops):
                loop[uv].uv = uv_at(ks[li], ts[li])
        else:
            for li, loop in enumerate(face.loops):
                loop[uv].uv = ((li % RING) / RING, 0.0)
    bm.to_mesh(me)
    bm.free()
    me.validate(verbose=False)

    root_delta = max((mw @ me.vertices[k].co - rings[0][k]).length for k in range(RING))
    facts = {'name': o.name, 'verts': len(me.vertices), 'faces': len(me.polygons),
             'root_max_delta': round(root_delta, 9),
             'materials': [s.material.name for s in o.material_slots],
             'modifiers': [(m.name, m.type) for m in o.modifiers],
             'uv_layers': [u.name for u in me.uv_layers],
             'smooth': sorted(set(f.use_smooth for f in me.polygons))}
    facts['within_budget'] = facts['verts'] <= 2 * 48 and facts['faces'] <= 2 * 38
    assert facts['root_max_delta'] <= 1e-6, f"{o.name}: root ring moved {facts['root_max_delta']}"
    assert facts['within_budget'], f"{o.name}: budget exceeded {facts['verts']}v/{facts['faces']}f"
    assert facts['uv_layers'] == ['SurfaceUV'], f"{o.name}: uv layers changed"
    return facts


def signed_distance(tree, p):
    hit = tree.find_nearest(p)
    if hit[0] is None:
        return None
    q, n, _idx, dist = hit
    return (1.0 if (p - q).dot(n) >= 0 else -1.0) * dist


def hover_height(tree, p):
    """Distance straight down to the shell surface; None when nothing is below."""
    hit = tree.ray_cast(p + Vector((0, 0, -1e-5)), Vector((0, 0, -1)), 1.0)
    if hit[0] is None:
        return None
    return (p - hit[0]).length


def smooth_ramp(v, lo, hi):
    x = max(0.0, min(1.0, (hi - v) / (hi - lo)))
    return x * x * (3 - 2 * x)


def seat_hood(hood, shell):
    smw = shell.matrix_world
    spts = [smw @ v.co for v in shell.data.vertices]
    shell.data.calc_loop_triangles()
    tris = [tuple(t.vertices) for t in shell.data.loop_triangles]
    tree = BVHTree.FromPolygons(spts, tris, all_triangles=False)
    hm = hood.matrix_world
    inv = hm.inverted()
    plan = []
    deepest_before = 1.0
    for i in range(len(hood.data.vertices)):
        p = hm @ hood.data.vertices[i].co
        d0 = signed_distance(tree, p)
        if d0 is None:
            continue
        deepest_before = min(deepest_before, d0)
        if d0 <= -HOOD_TARGET:
            continue                       # already seated; leave buried fabric still
        t = hover_height(tree, p)
        w_d = smooth_ramp(d0, 0.020, HOOD_NEAR)
        w_ray = smooth_ramp(t, HOOD_RAY_NEAR, HOOD_RAY_FAR) if t is not None else 0.0
        wgt = max(w_d, w_ray)
        if wgt <= 0.0:
            continue
        q, n, _idx, dist = tree.find_nearest(p)
        plan.append((i, p, n, (d0 + HOOD_TARGET) * wgt, wgt))
    edge = [item for item in plan if item[4] >= 0.999]
    assert edge, 'no hood vertices seated onto the shell; unexpected geometry'
    moved = 0
    max_disp = 0.0
    zone_outside_before = sum(1 for _i, _p, _n, _push, _w in plan if signed_distance(tree, _p) > 0)
    for i, p, n, push, _wgt in plan:
        hood.data.vertices[i].co = inv @ (p - n * push)
        moved += 1
        max_disp = max(max_disp, push)
    edge_after = max(signed_distance(tree, hm @ hood.data.vertices[i].co) for i, _p, _n, _push, _w in edge)
    assert edge_after <= -0.008, f'hood seat depth insufficient: {edge_after}'
    return {'hood_vertices': len(hood.data.vertices), 'seated_vertices': len(plan),
            'edge_vertices': len(edge), 'zone_outside_before': zone_outside_before,
            'deepest_before': round(deepest_before, 6), 'moved': moved,
            'max_disp': round(max_disp, 6), 'edge_max_after': round(edge_after, 6)}

bpy.ops.wm.open_mainfile(filepath=str(args.input))
D = bpy.data
before_digests = {o.name: digest_object(o) for o in D.objects}
report = {'input': str(args.input), 'objects_total': len(D.objects)}

lock_reports = {}
for style in STYLES:
    entries = [rebuild_lock(o) for o in D.objects if o.name.split('.')[0] == style + '_Lock']
    assert len(entries) == 12, f'{style}: expected 12 locks, found {len(entries)}'
    lock_reports[style] = entries
report['locks'] = lock_reports
report['hood'] = seat_hood(D.objects['Outfit_Hoodie_Hood'], D.objects['Outfit_Hoodie_Shell'])

after_digests = {o.name: digest_object(o) for o in D.objects}
assert set(after_digests) == set(before_digests), 'object set changed'
changed = sorted(name for name in before_digests if before_digests[name] != after_digests[name])
expected = sorted([o.name for o in D.objects if o.name.split('.')[0] in {s + '_Lock' for s in STYLES}]
                  + ['Outfit_Hoodie_Hood'])
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
                                       'hood': report['hood']}))
