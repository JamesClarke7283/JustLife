"""Weld a replacement eyelid annulus into a triangulated head, preserving keys.

Called by socket.py after authoring the eye/lash assemblies. The original
head keys are passed explicitly: the intermediate recessed overlay is never
used as the final skin. Each outer collar vertex belongs to the actual head
triangles, allowing the final skin normals to blend across a shared edge.
"""
import math

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform


def weld_head(head, original_keys, triangles, eyes, collar):
    basis = original_keys['Basis']
    coordinates = {key: [p.copy() for p in points] for key, points in original_keys.items()}
    influences = [{g.group: g.weight for g in v.groups} for v in head.data.vertices]
    group_names = [group.name for group in head.vertex_groups]
    # UVs are continuous enough for a plain skin material. Preserve the
    # existing outside vertex UVs and interpolate the clipped edge UVs.
    uv = [Vector((0, 0)) for _ in basis]
    counts = [0 for _ in basis]
    active_uv = head.data.uv_layers.active
    if active_uv:
        for loop in head.data.loops:
            uv[loop.vertex_index] += active_uv.data[loop.index].uv
            counts[loop.vertex_index] += 1
        uv = [p / max(counts[i], 1) for i, p in enumerate(uv)]
    original_tree = BVHTree.FromPolygons(basis, triangles, all_triangles=True)
    def surface_uv(p):
        hit, _, index, _ = original_tree.ray_cast(Vector((p.x, -2, p.z)), Vector((0, 1, 0)), 4)
        assert hit is not None
        ids = triangles[index]
        target = barycentric_transform(hit, *(basis[i] for i in ids),
                                       *(Vector((uv[i].x, uv[i].y, 0)) for i in ids))
        return Vector((target.x, target.y))
    faces = list(triangles)
    orbital_reports = []
    eye_loops = []
    shared_loops = []

    for eye in eyes:
        c, scale, sign = eye['center'], eye['scale'], eye['sign']

        def implicit(p):
            dx = (p.x - c.x) / scale
            dz = (p.z - c.z) / scale - .060 * sign * dx
            return (dx / eye['outer_rx']) ** 2 + (dz / eye['outer_rz']) ** 2 - 1

        edge_intersections = {}
        boundary_edges = []
        kept_faces = []

        def intersection(a, b):
            edge = tuple(sorted((a, b)))
            if edge in edge_intersections:
                return edge_intersections[edge]
            a, b = edge
            pa, pb = coordinates['Basis'][a], coordinates['Basis'][b]
            lo, hi = 0.0, 1.0
            negative_at_lo = implicit(pa) < 0
            for _ in range(30):
                mid = (lo + hi) * .5
                if (implicit(pa.lerp(pb, mid)) < 0) == negative_at_lo:
                    lo = mid
                else:
                    hi = mid
            t = (lo + hi) * .5
            index = len(coordinates['Basis'])
            for key, ps in coordinates.items():
                ps.append(ps[a].lerp(ps[b], t))
            influences.append({g: influences[a].get(g, 0) * (1 - t) + influences[b].get(g, 0) * t
                               for g in influences[a].keys() | influences[b].keys()})
            uv.append(uv[a].lerp(uv[b], t))
            edge_intersections[edge] = index
            return index

        for face in faces:
            if any(coordinates['Basis'][i].y > -.025 * scale for i in face):
                kept_faces.append(face)
                continue
            inside = [implicit(coordinates['Basis'][i]) < 0 for i in face]
            if not any(inside):
                kept_faces.append(face)
                continue
            if all(inside):
                continue
            polygon, cut = [], []
            for j, b in enumerate(face):
                a = face[j - 1]
                in_a, in_b = inside[j - 1], inside[j]
                if in_a != in_b:
                    new = intersection(a, b)
                    polygon.append(new)
                    cut.append(new)
                if not in_b:
                    polygon.append(b)
            assert len(cut) == 2, ('invalid clip', cut)
            boundary_edges.append(tuple(cut))
            for i in range(1, len(polygon) - 1):
                kept_faces.append((polygon[0], polygon[i], polygon[i + 1]))
        faces = kept_faces
        adjacency = {}
        for a, b in boundary_edges:
            adjacency.setdefault(a, []).append(b)
            adjacency.setdefault(b, []).append(a)
        assert adjacency and all(len(set(v)) == 2 for v in adjacency.values()), ('non-manifold cut', sign)
        start = min(adjacency)
        loop = [start]
        previous, current = None, start
        while True:
            nxt = next(v for v in adjacency[current] if v != previous)
            if nxt == start:
                break
            loop.append(nxt)
            previous, current = current, nxt
            assert len(loop) <= len(adjacency), 'cut did not form one loop'
        assert len(loop) == len(adjacency), 'multiple socket boundary loops'

        def angle(index):
            p = coordinates['Basis'][index]
            dx = (p.x - c.x) / scale
            dz = (p.z - c.z) / scale - .060 * sign * dx
            return math.atan2(dz / eye['outer_rz'], dx / eye['outer_rx']) % (2 * math.pi)

        loop = sorted(loop, key=angle)
        # Verify angular order really follows the retained mesh's edges.
        edges = {frozenset(e) for e in boundary_edges}
        assert all(frozenset((loop[i], loop[(i + 1) % len(loop)])) in edges for i in range(len(loop)))
        boundary_angles = [angle(i) for i in loop]
        n, rows = 64, 9
        theta = [2 * math.pi * i / n for i in range(n)]
        def outer_at(key, value):
            for j, lower in enumerate(boundary_angles):
                upper = boundary_angles[(j + 1) % len(loop)]
                if j == len(loop) - 1:
                    upper += 2 * math.pi
                v = value + (2 * math.pi if value < boundary_angles[0] else 0)
                if lower <= v <= upper:
                    return coordinates[key][loop[j]].lerp(coordinates[key][loop[(j + 1) % len(loop)]],
                                                          (v - lower) / (upper - lower))
            raise AssertionError(('missing boundary angle', value))
        rings = []
        for row in range(rows - 1):
            f = row / (rows - 1)
            ring = []
            for i in range(n):
                index = len(coordinates['Basis'])
                ring.append(index)
                for key, ps in coordinates.items():
                    p = collar(eye, theta[i], f, key)
                    # Use the exact corresponding clipped source vertex as
                    # the endpoint for every morph, not a separate ray hit.
                    delta = outer_at(key, theta[i]) - collar(eye, theta[i], 1.0, key)
                    p += delta * (f * f * (3 - 2 * f))
                    ps.append(p)
                influences.append(dict(influences[loop[0]]))
                uv.append(surface_uv(coordinates['Basis'][-1]))
            rings.append(ring)
        for row in range(rows - 2):
            for i in range(n):
                j = (i + 1) % n
                faces.append((rings[row][i], rings[row + 1][i], rings[row + 1][j], rings[row][j]))
        # The eyelid's regular inner rings guarantee paired top/bottom Blink
        # vertices. An angular zipper joins their last ring to the irregular
        # clipped head boundary without duplicate vertices or T-junctions.
        events = sorted([(value, 0, i) for i, value in enumerate(theta)] +
                        [(value, 1, i) for i, value in enumerate(boundary_angles)])
        inner_previous, outer_previous = n - 1, len(loop) - 1
        for _, side, index in events:
            if side == 0:
                faces.append((rings[-1][inner_previous], loop[outer_previous], rings[-1][index]))
                inner_previous = index
            else:
                faces.append((rings[-1][inner_previous], loop[outer_previous], loop[index]))
                outer_previous = index
        eye_loops.append(rings[0])
        shared_loops.append(loop)
        orbital_reports.append({'side': sign, 'shared_boundary_vertices': len(loop), 'radial_rows': rows,
                                'new_collar_vertices': n * (rows - 1)})

    used = sorted({i for face in faces for i in face})
    remap = {old: new for new, old in enumerate(used)}
    inverse = head.matrix_world.inverted()
    mesh = bpy.data.meshes.new('Skin_Head_welded_orbits')
    mesh.from_pydata([inverse @ coordinates['Basis'][i] for i in used], [],
                     [tuple(remap[i] for i in face) for face in faces])
    mesh.materials.append(bpy.data.materials['Skin'])
    head.data = mesh
    head.vertex_groups.clear()
    for name in group_names:
        head.vertex_groups.new(name=name)
    for key, ps in coordinates.items():
        block = head.shape_key_add(name=key)
        block.value = 0
        if key in ('Nose_Length', 'Lip_Fullness', 'Brow_Arch', 'Chin_Length'):
            block.slider_min = -1
        for new, old in enumerate(used):
            block.data[new].co = inverse @ ps[old]
    for new, old in enumerate(used):
        for group, weight in influences[old].items():
            head.vertex_groups[group].add([new], weight, 'REPLACE')
    uv_layer = mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        poly.use_smooth = True
        for loop_index in poly.loop_indices:
            uv_layer.data[loop_index].uv = uv[used[mesh.loops[loop_index].vertex_index]]
    mesh.update()
    for eye in eyes:
        old_lid = bpy.data.objects.get('Skin_Upper_lid_' + str(eye['sign']))
        if old_lid:
            bpy.data.objects.remove(old_lid, do_unlink=True)
    for i, loop in enumerate(eye_loops):
        head['orbit_inner_' + str(i)] = [remap[v] for v in loop]
        head['orbit_shared_' + str(i)] = [remap[v] for v in shared_loops[i]]
    return {'vertices_before': len(basis), 'vertices_after': len(used), 'faces_after': len(faces),
            'eyes': orbital_reports, 'method': 'shared clipped head boundary, unified shape keys and smooth normals'}
