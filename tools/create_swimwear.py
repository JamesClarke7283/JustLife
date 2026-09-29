"""Author the original Swim look and export a standalone GLB for each age family.

    blender -b --factory-startup --python tools/create_swimwear.py -- --family all --export

A classic scoop-neck one-piece swimsuit with straps, high-cut leg holes and a
side stripe, fitted to every family's own accepted geometry (art/characters*.blend).
The output follows tools/create_look_garments.py exactly: a rigged root exported
with the shared `LifeRig` skeleton, a group named `Outfit_Swim`, skinned meshes
weighted to the same eleven bone groups, and materials named for what the game
recolours them by.

  assets/models/looks/{adult,child,teen,elder}_swim.glb

Meshes in the `Outfit_Swim` group (the game finds them with find_child):

  Outfit_Swim_Suit     material Top       the swimsuit itself: scoop neck, straps, leg holes
  Outfit_Swim_Skin     material Skin      bare chest, back and shoulders under the suit
  Outfit_Swim_Stripe   material Bottom    a contrasting racing stripe down each side
  Outfit_Swim_Binding  material Top_seam  piping round the neck, armholes and leg holes

Why the look carries its own skin: the base character has no torso skin at all
(Skin_Head_continuous, Skin_Arm_continuous_L/R and Skin_Leg_continuous are the only
bare surfaces, and the torso is always clothed), so any garment with an open neck
or armholes needs skin beneath it. `Outfit_Swim_Skin` is that torso; it recolours
with the Lifelet's skin tone exactly as the arms and legs do.

Wiring in the game (scripts/actor.gd), none of which the GLBs can do for themselves:

  * LOOK_OUTFITS needs "swim": "Outfit_Swim" (the loaded root is renamed to it).
  * Every base `Bottom_*` mesh under the character model must be hidden while this
    look is worn, and `Skin_Leg_continuous` shown. _apply_bottom_visibility shows
    Bottom_Shorts* for bottom=1, and never touches Bottom_Waistband, Bottom_Belt_loop*,
    Bottom_Button or Bottom_Pocket*, all of which would poke through a fitted suit.
  * The look GLBs are authored at the standard (frame 0) width. The broad frame is
    the same model scaled x1.12 about the origin, so a frame-1 Lifelet needs
    `_look_root.scale.x = 1.12` or its thighs show through the leg holes.
  * Recolouring is the existing one: Top -> top_color, Top_seam -> top_color darkened,
    Bottom -> bottom_color (the stripe), Skin -> skin_color (the bare torso).

Nothing here replaces or edits an existing asset: it never overwrites a GLB, it
never writes the source .blend files, and it never touches character*.glb.
"""
import bpy, bmesh, math, sys, argparse, pathlib, tempfile, os, hashlib, json, struct
from mathutils import Vector, kdtree
from mathutils.bvhtree import BVHTree

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--family", choices=["adult", "child", "teen", "elder", "all"], default="all")
parser.add_argument("--export", action="store_true", help="write assets/models/looks/<family>_swim.glb")
parser.add_argument("--preview", type=pathlib.Path, default=None, help="render preview PNGs into this directory")
parser.add_argument("--pose", default="rest", help="comma list of rest,arms,sit for --preview")
parser.add_argument("--views", default="front,side,back,q", help="comma list of views for --preview")
parser.add_argument("--zoom", default=None, help="x,z,scale: add close-up views of that point (metres)")
parser.add_argument("--hide", default="", help="comma list of object-name prefixes to hide in --preview (debugging)")
parser.add_argument("--debug", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
FAMILIES = ["adult", "child", "teen", "elder"] if args.family == "all" else [args.family]
GROUPS = ["Root", "Spine", "Head", "Arm_L", "Forearm_L", "Arm_R", "Forearm_R", "Leg_L", "Shin_L", "Leg_R", "Shin_R"]
LOOK = "Outfit_Swim"
D = bpy.data
BLENDS = {"adult": "characters", "child": "characters_child", "teen": "characters_teen", "elder": "characters_elder"}

CLOTH_GAP = 0.0048     # fabric stands this far off the skin under it (metres)
SKIN_GAP = 0.0065      # ... and the bare skin shell sits this far inside the fabric


def log(*a):
    if args.debug:
        print("[swim]", *a)


# ---------------------------------------------------------------- scene helpers
# These mirror tools/create_look_garments.py so the export is structured identically.
def link(o, parent):
    if o.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(o)
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()


def empty(name, parent):
    e = D.objects.new(name, None)
    link(e, parent)
    return e


def ensure_groups(o):
    for g in GROUPS:
        if g not in o.vertex_groups:
            o.vertex_groups.new(name=g)


def skinned_object(name, bm, material, parent, rig):
    """Turn a finished bmesh (world metres, canonical weight indices) into a skinned object."""
    me = D.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(D.materials[material])
    o = D.objects.new(name, me)
    link(o, parent)
    ensure_groups(o)
    for p in me.polygons:
        p.use_smooth = True
    arm = o.modifiers.new("Soft skeletal deformation", "ARMATURE")
    arm.object = rig
    return o


# ---------------------------------------------------------------- bmesh helpers
def source_bmesh(obj):
    """World-space bmesh of a source mesh with weights re-indexed to GROUPS order.

    The source meshes list their vertex groups in different orders, so weights are
    carried by group *name* to keep every piece of the look on one canonical index.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    dl = bm.verts.layers.deform.verify()
    names = [g.name for g in obj.vertex_groups]
    for v in bm.verts:
        w = {names[i]: x for i, x in v[dl].items() if i < len(names)}
        v[dl].clear()
        for n, x in w.items():
            if n in GROUPS:
                v[dl][GROUPS.index(n)] = x
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    return bm


def all_geom(bm):
    return list(bm.verts) + list(bm.edges) + list(bm.faces)


def boundary_loops(bm):
    """Closed boundary loops as ordered vertex lists (largest first)."""
    edges = [e for e in bm.edges if e.is_boundary]
    adj = {}
    for e in edges:
        for v in e.verts:
            adj.setdefault(v, []).append(e)
    seen, loops = set(), []
    for e in edges:
        if e in seen:
            continue
        loop, cur, v = [], e, e.verts[0]
        start = v
        while True:
            seen.add(cur)
            loop.append(v)
            v2 = cur.other_vert(v)
            nxt = [x for x in adj[v2] if x not in seen]
            if not nxt:
                break
            cur, v = nxt[0], v2
            if v == start:
                break
        loops.append(loop)
    loops.sort(key=len, reverse=True)
    return loops


def loop_edges(loop):
    out = []
    n = len(loop)
    for i in range(n):
        a, b = loop[i], loop[(i + 1) % n]
        for edge in a.link_edges:
            if edge.other_vert(a) == b:
                out.append(edge)
                break
    return out


def components(bm):
    seen, out = set(), []
    for f in bm.faces:
        if f in seen:
            continue
        stack, comp = [f], []
        seen.add(f)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.edges:
                for g in e.link_faces:
                    if g not in seen:
                        seen.add(g)
                        stack.append(g)
        out.append(comp)
    out.sort(key=len, reverse=True)
    return out


def keep_largest(bm):
    comps = components(bm)
    doomed = [f for c in comps[1:] for f in c]
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
    stray = [v for v in bm.verts if not v.link_faces]
    if stray:
        bmesh.ops.delete(bm, geom=stray, context="VERTS")
    bm.verts.ensure_lookup_table()


def prune_spurs(bm, passes=2):
    """Drop the flaps and one-face slivers a curved cut leaves along a mesh edge."""
    for _ in range(passes):
        flaps = [f for f in bm.faces if sum(1 for e in f.edges if e.is_boundary) >= 2]
        if not flaps:
            break
        bmesh.ops.delete(bm, geom=flaps, context="FACES")
        stray = [v for v in bm.verts if not v.link_faces]
        if stray:
            bmesh.ops.delete(bm, geom=stray, context="VERTS")
    bm.verts.ensure_lookup_table()


def delete_where(bm, keep):
    doomed = [v for v in bm.verts if not keep(v.co)]
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.verts.ensure_lookup_table()
    keep_largest(bm)
    prune_spurs(bm)
    keep_largest(bm)


def cut_plane(bm, z, above):
    """Cut the mesh on the horizontal plane z and keep the part above (or below)."""
    bmesh.ops.bisect_plane(bm, geom=all_geom(bm), plane_co=(0.0, 0.0, z), plane_no=(0.0, 0.0, 1.0),
                           clear_inner=above, clear_outer=not above)
    stray = [v for v in bm.verts if not v.link_faces]
    if stray:
        bmesh.ops.delete(bm, geom=stray, context="VERTS")
    bm.verts.ensure_lookup_table()
    bm.normal_update()


def offset_along_normals(bm, d):
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * d


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def loop_bbox(loop):
    xs = [v.co.x for v in loop]
    ys = [v.co.y for v in loop]
    return min(xs), max(xs), min(ys), max(ys), sum(v.co.z for v in loop) / len(loop)


def smooth_loop(loop, tree, passes=24, strength=0.5):
    """Relax a cut boundary so it reads as a drawn seam, staying on the surface."""
    n = len(loop)
    pts = [v.co.copy() for v in loop]
    for _ in range(passes):
        nxt = []
        for i in range(n):
            mid = (pts[i - 1] + pts[(i + 1) % n]) * 0.5
            nxt.append(pts[i].lerp(mid, strength))
        pts = nxt
    for v, p in zip(loop, pts):
        hit = tree.find_nearest(p) if tree is not None else None
        v.co = hit[0] if hit and hit[0] is not None else p


# ---------------------------------------------------------------- the garment
def measure(family, rig, tee, legs):
    """Landmarks in metres, measured from this family's own meshes."""
    tee_pts = [tee.matrix_world @ v.co for v in tee.data.vertices]
    z_top = max(p.z for p in tee_pts)
    z_hem = min(p.z for p in tee_pts)
    cap = [p for p in tee_pts if p.z > z_top - 0.010]
    leg_pts = [legs.matrix_world @ v.co for v in legs.data.vertices]
    crotch = min(p.z for p in leg_pts if abs(p.x) < 0.02)
    leg_top = max(p.z for p in leg_pts)
    st = {
        "z_top": z_top, "z_hem": z_hem, "H": z_top - z_hem,
        "cap_x": max(abs(p.x) for p in cap),
        "cap_y": sum(p.y for p in cap) / len(cap),
        "crotch": crotch, "leg_top": leg_top,
        "hip": {s: rig.data.bones["Leg_" + s].head_local.copy() for s in ("L", "R")},
        "shoulder": {s: rig.data.bones["Arm_" + s].head_local.copy() for s in ("L", "R")},
    }
    st["k"] = st["H"] / 0.431            # adult torso height is the reference
    st["family"] = family
    return st


def build_tank(tee, st):
    """The Tee's torso with the sleeves removed and the sleeve holes closed.

    Same sleeve test as create_look_garments.delete_sleeves. The holes are closed
    so the shell is watertight: the skin shell must not show the arm sockets, and
    the fabric must not have slits under the arms.
    """
    bm = source_bmesh(tee)
    dl = bm.verts.layers.deform.active
    arm = {GROUPS.index(g) for g in GROUPS if "Arm" in g}
    spine = GROUPS.index("Spine")
    doomed = []
    for v in bm.verts:
        a = sum(v[dl].get(g, 0.0) for g in arm)
        if a > 0.12 and a >= v[dl].get(spine, 0.0) * 0.7:
            doomed.append(v)
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.verts.ensure_lookup_table()
    keep_largest(bm)
    prune_spurs(bm, passes=4)        # shed the sleeve-root flaps: they would become hairs beside the armhole
    keep_largest(bm)
    slit_z, slit_centres = [], []
    for loop in boundary_loops(bm):
        slit_z.append(min(v.co.z for v in loop))
        slit_centres.append(sum((v.co for v in loop), Vector()) / len(loop))
        res = bmesh.ops.holes_fill(bm, edges=loop_edges(loop), sides=len(loop))
        bm.normal_update()
        if res["faces"]:
            bmesh.ops.triangulate(bm, faces=res["faces"], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.verts.ensure_lookup_table()
    # Relax the ragged ring the sleeve cut leaves and the flat patch closing it.
    around = []
    for c in slit_centres:
        around += [v for v in bm.verts if (v.co - c).length < 0.10 * st["k"]]
    around = list(set(around))
    for _ in range(40):
        bmesh.ops.smooth_vert(bm, verts=around, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    st["slit_z"] = sum(slit_z) / len(slit_z) if slit_z else st["z_top"] - 0.19 * st["k"]
    return bm


LEG_HOLE = [  # (angle around the leg in degrees, edge height above the crotch in metres)
    (0, 0.150), (40, 0.158), (90, 0.128), (120, 0.088), (145, 0.042), (165, 0.004), (180, -0.016),
    (195, 0.004), (215, 0.014), (240, 0.024), (270, 0.048), (315, 0.115), (360, 0.150)]


LEG_CUT = {"adult": 1.0, "child": 0.70, "teen": 0.90, "elder": 0.90}   # how high the leg holes sweep


def leg_edge(phi, family="adult"):
    """Height of the leg-hole edge above the crotch at angle phi (degrees) round a leg."""
    phi = phi % 360.0
    for (a0, h0), (a1, h1) in zip(LEG_HOLE, LEG_HOLE[1:]):
        if a0 <= phi <= a1:
            h = h0 + (h1 - h0) * smoothstep((phi - a0) / (a1 - a0))
            return h * LEG_CUT[family] if h > 0 else h
    return LEG_HOLE[0][1]


def build_lower(legs, st, z_ring):
    """The pelvis and upper thighs: the leg skin, cut at the leg holes and lifted off the skin.

    The base body has no torso above the leg skin's top edge, so the suit's top ring
    is extruded straight up to a level plane just clear of that edge. That keeps the
    ring the torso joins to above every bare surface, whatever the pose does to the
    hip skin beneath.
    """
    bm = source_bmesh(legs)
    dl = bm.verts.layers.deform.active
    rim = [(v.co.copy(), dict(v[dl].items())) for v in bm.verts if v.co.z > st["leg_top"] - 0.006]
    kd = kdtree.KDTree(len(rim))
    for i, (p, _) in enumerate(rim):
        kd.insert(Vector((p.x, p.y, 0.0)), i)
    kd.balance()
    keep_largest(bm)
    crotch = st["crotch"]

    def keep(p):
        side = "L" if p.x < 0 else "R"
        hip = st["hip"][side]
        lateral = (p.x - hip.x) * (-1.0 if side == "L" else 1.0)
        front = -(p.y - hip.y)
        phi = math.degrees(math.atan2(front, lateral))
        return p.z >= crotch + leg_edge(phi, st["family"])

    offset_along_normals(bm, CLOTH_GAP)
    delete_where(bm, keep)
    top = max(boundary_loops(bm), key=lambda l: sum(v.co.z for v in l) / len(l))
    res = bmesh.ops.extrude_edge_only(bm, edges=loop_edges(top))
    for v in [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]:
        v.co.z = z_ring
        # The extruded ring takes the weights of the skin's own top edge, so it rides
        # exactly where the hip skin beneath it does.
        wr = rim[kd.find(Vector((v.co.x, v.co.y, 0.0)))[1]][1]
        v[dl].clear()
        for g, w in wr.items():
            v[dl][g] = w
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    return bm


def strip_arm_weights(bm):
    """Bare arms swing on their own: keep the torso pieces off the arm bones."""
    dl = bm.verts.layers.deform.verify()
    arm = {GROUPS.index(g) for g in GROUPS if "Arm" in g}
    spine = GROUPS.index("Spine")
    for v in bm.verts:
        w = v[dl]
        moved = sum(w.get(g, 0.0) for g in arm)
        for g in arm:
            if g in w:
                del w[g]
        if moved > 0:
            w[spine] = w.get(spine, 0.0) + moved
        total = sum(w.values())
        if total > 0:
            for g in list(w.keys()):
                w[g] = w[g] / total


def blend_to_ring(bm, ring, z0, height):
    """Fade the torso's weights into the pelvis ring's over `height` above z0.

    The hip skin the suit is lifted from follows the thighs a little, while the torso
    stays on the spine. Joining the two with matching weights at the ring lets the
    waist fold when the Lifelet sits instead of tearing a gap open at the join.
    """
    dl = bm.verts.layers.deform.verify()
    kd = kdtree.KDTree(len(ring))
    for i, (p, _) in enumerate(ring):
        kd.insert(Vector((p.x, p.y, 0.0)), i)
    kd.balance()
    for v in bm.verts:
        s = smoothstep((v.co.z - z0) / height)
        if s >= 1.0:
            continue
        wr = ring[kd.find(Vector((v.co.x, v.co.y, 0.0)))[1]][1]
        wt = dict(v[dl].items())
        mixed = {g: s * wt.get(g, 0.0) + (1.0 - s) * wr.get(g, 0.0) for g in set(wt) | set(wr)}
        total = sum(mixed.values()) or 1.0
        v[dl].clear()
        for g, w in mixed.items():
            v[dl][g] = w / total


def taper(bm, z_u, z_hi, sx, sy, cy_from, cy_to):
    """Ease the torso down to the pelvis: x and y scale toward the hem ring, smoothly."""
    for v in bm.verts:
        t = smoothstep((z_hi - v.co.z) / (z_hi - z_u))
        if t <= 0.0:
            continue
        v.co.x *= 1.0 + t * (sx - 1.0)
        y = v.co.y
        y_target = cy_to + (y - cy_from) * sy
        v.co.y = y + t * (y_target - y)


def upper_keep_factory(st):
    """Neckline, straps and armholes as a keep-test on the tank's vertices."""
    k = st["k"]
    z_top, H = st["z_top"], st["H"]
    wx = st["cap_x"]
    x_in = 0.50 * wx
    x_out = 0.92 * wx
    W = st["W"]
    z_pit = st["slit_z"] + 0.048 * k
    d_front = 0.30 * H
    d_back = 0.17 * H
    cy = st["cap_y"]
    p = 2.3

    def scoop(ax, depth):
        return z_top - depth * (1.0 - min(1.0, (ax / x_in)) ** p) ** (1.0 / p)

    def keep(c):
        ax = abs(c.x)
        if ax <= x_in:
            return c.z <= scoop(ax, d_front if c.y < cy else d_back)
        if ax <= x_out:
            return True
        u = min(1.0, (ax - x_out) / max(W - x_out, 1e-4))
        # A concave scoop: the edge drops steeply beside the strap, then sweeps out to the armpit.
        arm_z = z_top - (z_top - z_pit) * math.sqrt(max(0.0, 1.0 - (1.0 - u) ** 2))
        return c.z <= arm_z

    st["x_in"], st["x_out"], st["z_pit"] = x_in, x_out, z_pit
    return keep


def resample(loop_pts, spacing):
    """Even-arc resample of a closed polyline."""
    n = len(loop_pts)
    seg = [(loop_pts[(i + 1) % n] - loop_pts[i]).length for i in range(n)]
    total = sum(seg)
    count = max(12, int(total / spacing))
    out, acc, i = [], 0.0, 0
    for j in range(count):
        target = total * j / count
        while acc + seg[i] < target and i < n - 1:
            acc += seg[i]
            i += 1
        t = (target - acc) / max(seg[i], 1e-9)
        out.append(loop_pts[i].lerp(loop_pts[(i + 1) % n], t))
    return out


PIPING = [(-0.0028, 0.0002), (-0.0032, 0.0022), (-0.0018, 0.0038), (0.0010, 0.0045),
          (0.0048, 0.0042), (0.0084, 0.0030), (0.0114, 0.0016), (0.0136, 0.0006)]


def shoulder_caps(st):
    """A soft deltoid on each shoulder, so the bare arm joins the torso instead of hanging beside it.

    The base arm is a capsule that starts below the shoulder line (a sleeve always
    hides the join). Each cap is an ellipsoid centred on the top of the arm and
    weighted wholly to that arm's bone, so it turns with the arm like a ball joint.
    """
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    for side in ("L", "R"):
        arm = D.objects["Skin_Arm_continuous_" + side]
        pts = [arm.matrix_world @ v.co for v in arm.data.vertices]
        z_max = max(p.z for p in pts)
        ring = [p for p in pts if z_max - 0.055 * st["k"] < p.z < z_max - 0.035 * st["k"]]
        cx = sum(p.x for p in ring) / len(ring)
        cy = sum(p.y for p in ring) / len(ring)
        rx = max(abs(p.x - cx) for p in ring)
        ry = max(abs(p.y - cy) for p in ring)
        pivot = st["shoulder"][side]
        centre = Vector((pivot.x, pivot.y, pivot.z - 0.006 * st["k"]))
        res = bmesh.ops.create_uvsphere(bm, u_segments=18, v_segments=12, radius=1.0)
        gi = GROUPS.index("Arm_" + side)
        for v in res["verts"]:
            v.co = Vector((centre.x + v.co.x * rx * 1.05, centre.y + v.co.y * ry * 1.05,
                           centre.z + v.co.z * 0.045 * st["k"]))
            v[dl][gi] = 1.0
    bm.normal_update()
    return bm


def relax_path(pts, passes, strength=0.5):
    n = len(pts)
    for _ in range(passes):
        pts = [pts[i].lerp((pts[i - 1] + pts[(i + 1) % n]) * 0.5, strength) for i in range(n)]
    return pts


def build_binding(suit_bm, loops, scale, nearest_weights):
    """A rolled piping strip that follows every open edge of the suit.

    The strip runs along a heavily relaxed copy of each seam and overhangs the raw
    edge slightly, so the small steps of the cut are hidden under it rather than
    traced by it.
    """
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    suit_bm.normal_update()
    tree = BVHTree.FromBMesh(suit_bm)
    for loop in loops:
        raw = [v.co.copy() for v in loop]
        rs = resample(raw, 0.0055 * (0.6 + 0.4 * scale))
        rs = relax_path(rs, 26)
        n = len(rs)
        cen, nrm = [], []
        for p in rs:
            loc, nor, _, _ = tree.find_nearest(p)
            cen.append(loc)
            nrm.append(nor.normalized())
        cen = relax_path(cen, 6)
        found = [tree.find_nearest(p) for p in cen]
        cen = [f[0] for f in found]
        face_at = [f[2] for f in found]
        nrm = [v.normalized() for v in relax_path(nrm, 8)]
        # which way is "into the fabric" for this whole loop
        votes = 0.0
        for v in loop[::3]:
            f = v.link_faces[0]
            inward = f.calc_center_median() - v.co
            i = min(range(n), key=lambda j: (cen[j] - v.co).length_squared)
            t = (cen[(i + 1) % n] - cen[i - 1]).normalized()
            votes += nrm[i].cross(t).dot(inward)
        sign = 1.0 if votes > 0 else -1.0
        rows = []
        for i in range(n):
            t = (cen[(i + 1) % n] - cen[i - 1]).normalized()
            d = nrm[i].cross(t) * sign
            d = (d - nrm[i] * d.dot(nrm[i])).normalized()
            row = []
            for a, h in PIPING:
                v = bm.verts.new(cen[i] + d * (a * scale) + nrm[i] * (h * scale))
                for gi, w in nearest_weights(cen[i], face_at[i]).items():
                    v[dl][gi] = w
                row.append(v)
            rows.append(row)
        for i in range(n):
            r0, r1 = rows[i], rows[(i + 1) % n]
            for j in range(len(PIPING) - 1):
                try:
                    bm.faces.new((r0[j], r0[j + 1], r1[j + 1], r1[j]))
                except ValueError:
                    pass
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    score = 0.0
    for f in bm.faces[:600]:
        hit = tree.find_nearest(f.calc_center_median())
        if hit and hit[1] is not None:
            score += f.normal.dot(hit[1])
    if score < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    bm.verts.ensure_lookup_table()
    return bm


def build_stripe(suit_bm, st, side, nearest_weights):
    """A racing stripe on one side of the suit, projected onto the fabric from outside."""
    tree = BVHTree.FromBMesh(suit_bm)
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    theta0 = math.radians(66.0)
    half_w = 0.0085 * (0.55 + 0.45 * st["k"])
    z0, z1 = st["z_pit"] - 0.045 * st["k"], st["crotch"] - 0.01
    # Where the middle of the body is at each height: a stooped torso sits forward of its hips.
    levels = {}
    for v in suit_bm.verts:
        levels.setdefault(int(round(v.co.z / 0.01)), []).append(v.co.y)
    mids = {k_: (min(ys) + max(ys)) / 2 for k_, ys in levels.items()}

    keys = sorted(mids)

    def centre_y(z):
        f = z / 0.01
        lo = max([k_ for k_ in keys if k_ <= f], default=keys[0])
        hi = min([k_ for k_ in keys if k_ >= f], default=keys[-1])
        if hi == lo:
            return mids[lo]
        t = (f - lo) / (hi - lo)
        return mids[lo] * (1.0 - t) + mids[hi] * t
    step = 0.0042
    rows = []
    z = z0
    cols = (-1.0, -1.0 / 3.0, 1.0 / 3.0, 1.0)
    while z > z1:
        row = []
        r_guess = 0.12 * (0.55 + 0.45 * st["k"])
        for c in cols:
            th = theta0 + c * half_w / r_guess
            out_dir = Vector((side * math.sin(th), -math.cos(th), 0.0))
            origin = Vector((0.0, centre_y(z), z)) + out_dir * 0.9
            hit = tree.ray_cast(origin, -out_dir)
            if hit[0] is None or hit[1].dot(out_dir) < 0.25:   # missed, or hit the far side's inner face
                row.append(None)
            else:
                row.append((hit[0] + hit[1] * 0.0014, hit[1], hit[2], hit[0]))
        rows.append(row)
        z -= step
    verts = []
    for row in rows:
        vr = []
        for item in row:
            if item is None:
                vr.append(None)
            else:
                v = bm.verts.new(item[0])
                for gi, w in nearest_weights(item[3], item[2]).items():
                    v[dl][gi] = w
                vr.append(v)
        verts.append(vr)
    for i in range(len(verts) - 1):
        for j in range(len(cols) - 1):
            q = (verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1])
            if any(x is None for x in q):
                continue
            if (q[0].co - q[1].co).length > step * 3.0 or (q[0].co - q[3].co).length > half_w * 2.0:
                continue
            try:
                bm.faces.new(q)
            except ValueError:
                pass
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    if bm.faces:
        f0 = bm.faces[0]
        hit = tree.find_nearest(f0.calc_center_median())
        if hit and hit[1] is not None and f0.normal.dot(hit[1]) < 0:
            bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    stray = [v for v in bm.verts if not v.link_faces]
    if stray:
        bmesh.ops.delete(bm, geom=stray, context="VERTS")
    keep_largest(bm)                 # one clean ribbon: drop any fragment beside the armhole edge
    return bm


def merge_into(dest, src):
    """Append every element of src to dest (weights included); returns the src->dest vertex map."""
    dl_d = dest.verts.layers.deform.verify()
    dl_s = src.verts.layers.deform.active
    vmap = {}
    for v in src.verts:
        nv = dest.verts.new(v.co)
        if dl_s is not None:
            for g, w in v[dl_s].items():
                nv[dl_d][g] = w
        vmap[v] = nv
    for f in src.faces:
        try:
            dest.faces.new([vmap[v] for v in f.verts])
        except ValueError:
            pass
    dest.verts.ensure_lookup_table()
    return vmap


def weight_lookup(bm):
    """Weights sampled from a surface by barycentric interpolation at a point on it.

    Accent pieces ride a millimetre or two above the suit, so they must take the
    suit's weights as interpolated across the face beneath them; borrowing the
    nearest vertex's weights would let them shear away from it wherever the
    weights change quickly, such as the waist.
    """
    from mathutils import interpolate
    dl = bm.verts.layers.deform.active
    bm.faces.ensure_lookup_table()

    def at(point, face_index):
        face = bm.faces[face_index]
        verts = list(face.verts)
        coords = [v.co for v in verts]
        try:
            bary = interpolate.poly_3d_calc(coords, point)
        except Exception:
            bary = [1.0 / len(verts)] * len(verts)
        out = {}
        for v, b in zip(verts, bary):
            for g, w in v[dl].items():
                out[g] = out.get(g, 0.0) + w * b
        total = sum(out.values()) or 1.0
        return {g: w / total for g, w in out.items()}
    return at


def build_swim(family):
    rig = D.objects["LifeRig"]
    root = D.objects["Character"]
    tee = D.objects["Outfit_Tee_Shirt"]
    legs = D.objects["Skin_Leg_continuous"]
    for o in [o for o in D.objects if o.name.startswith(LOOK)]:
        D.objects.remove(o)
    st = measure(family, rig, tee, legs)
    tank = build_tank(tee, st)
    st["W"] = max(abs(v.co.x) for v in tank.verts)
    k = st["k"]
    log(family, {a: (round(b, 4) if isinstance(b, float) else b) for a, b in st.items() if a not in ("hip", "shoulder", "family")})

    # --- join heights: the torso is cut a little above the tee hem, the pelvis ring sits
    # just above the leg skin's top edge, and the small gap between them is bridged.
    z_u = st["z_hem"] + 0.030 * k
    lower = build_lower(legs, st, st["leg_top"] + 0.012 * k)

    # --- torso shells
    suit_up = tank.copy()
    skin_up = tank.copy()
    offset_along_normals(suit_up, -0.0035)
    offset_along_normals(skin_up, -0.0035 - SKIN_GAP)
    cut_plane(suit_up, z_u, above=True)
    keep_largest(suit_up)
    hem_u = min(boundary_loops(suit_up), key=lambda l: abs(sum(v.co.z for v in l) / len(l) - z_u))
    ring_u = loop_bbox(hem_u)
    lower_loops = boundary_loops(lower)
    hem_l = max(lower_loops, key=lambda l: sum(v.co.z for v in l) / len(l))
    ring_l = loop_bbox(hem_l)
    log("hem ring upper", [round(x, 4) for x in ring_u], "lower", [round(x, 4) for x in ring_l])
    sx = ((ring_l[1] - ring_l[0]) / (ring_u[1] - ring_u[0]))
    sy = ((ring_l[3] - ring_l[2]) / (ring_u[3] - ring_u[2]))
    cy_u, cy_l = (ring_u[2] + ring_u[3]) / 2, (ring_l[2] + ring_l[3]) / 2
    z_hi = z_u + 0.55 * st["H"]
    for b in (suit_up, skin_up):
        taper(b, z_u, z_hi, sx, sy, cy_u, cy_l)
    cut_plane(skin_up, z_u - 0.012 * k, above=True)
    keep_largest(skin_up)
    suit_up.normal_update()
    skin_up.normal_update()

    # --- neckline, straps, armholes
    keep = upper_keep_factory(st)
    delete_where(suit_up, keep)
    strip_arm_weights(suit_up)
    strip_arm_weights(skin_up)
    dl_lower = lower.verts.layers.deform.active
    ring_weights = [(v.co.copy(), dict(v[dl_lower].items())) for v in hem_l]
    blend_to_ring(suit_up, ring_weights, z_u, 0.12 * k)
    blend_to_ring(skin_up, ring_weights, z_u, 0.12 * k)

    # --- assemble the suit: upper + lower, bridged at the hem
    hem_u = min(boundary_loops(suit_up), key=lambda l: abs(sum(v.co.z for v in l) / len(l) - z_u))
    vmap = merge_into(suit_up, lower)
    suit = suit_up
    suit.verts.ensure_lookup_table()
    hem_l_new = [vmap[v] for v in hem_l]
    edges = loop_edges(hem_u) + loop_edges(hem_l_new)
    bmesh.ops.bridge_loops(suit, edges=edges, use_pairs=False, use_cyclic=False, use_merge=False,
                           merge_factor=0.5, twist_offset=0)
    bmesh.ops.recalc_face_normals(suit, faces=list(suit.faces))
    suit.verts.ensure_lookup_table()
    suit.normal_update()

    # --- smooth every open edge (neck, armholes, leg holes)
    tree = BVHTree.FromBMesh(suit)
    loops = boundary_loops(suit)
    for loop in loops:
        smooth_loop(loop, tree)
    suit.normal_update()
    low = sorted(suit.verts, key=lambda v: v.co.z)[:6]
    log("suit verts", len(suit.verts), "loops", [len(l) for l in loops], "crotch", round(st["crotch"], 4),
        "lowest", [tuple(round(c, 3) for c in v.co) for v in low])

    # --- accents
    look_weights = weight_lookup(suit)
    bind_scale = 0.6 + 0.4 * k
    binding = build_binding(suit, loops, bind_scale, look_weights)
    stripes = [build_stripe(suit, st, s, look_weights) for s in (-1, 1)]
    stripe = stripes[0]
    for extra in stripes[1:]:
        merge_into(stripe, extra)
        extra.free()

    merge_into(skin_up, shoulder_caps(st))
    group = empty(LOOK, root)
    objs = {
        "Outfit_Swim_Skin": skinned_object("Outfit_Swim_Skin", skin_up, "Skin", group, rig),
        "Outfit_Swim_Suit": skinned_object("Outfit_Swim_Suit", suit, "Top", group, rig),
        "Outfit_Swim_Stripe": skinned_object("Outfit_Swim_Stripe", stripe, "Bottom", group, rig),
        "Outfit_Swim_Binding": skinned_object("Outfit_Swim_Binding", binding, "Top_seam", group, rig),
    }
    tank.free()
    return group, objs, st


# ---------------------------------------------------------------- export
def descendants(node):
    yield node
    for child in node.children:
        yield from descendants(child)


def export_look(family, group, out):
    name = "%s_swim.glb" % family
    target = out / name
    if target.exists():
        raise RuntimeError("Refusing to replace an existing look: " + str(target))
    bpy.ops.object.select_all(action="DESELECT")
    for o in descendants(group):
        o.hide_set(False)
        o.select_set(True)
    rig = D.objects["LifeRig"]
    rig.hide_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = group
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".export-", dir=out) as folder:
        path = pathlib.Path(folder) / name
        bpy.ops.export_scene.gltf(
            filepath=str(path), export_format="GLB", use_selection=True, export_apply=True,
            export_yup=True, export_animations=False, export_morph=False, export_skins=True,
            export_extras=True, export_cameras=False, export_lights=False)
        raw = path.read_bytes()
        json_length = struct.unpack_from("<I", raw, 12)[0]
        document = json.loads(raw[20:20 + json_length])
        if not document.get("skins"):
            raise RuntimeError("Look export lost its skin: " + name)
        for mesh in document.get("meshes", []):
            for primitive in mesh["primitives"]:
                if not {"JOINTS_0", "WEIGHTS_0"} <= primitive["attributes"].keys():
                    raise RuntimeError("Look export has an unskinned garment: " + name)
        os.replace(path, target)
    return hashlib.sha256(target.read_bytes()).hexdigest()


# ---------------------------------------------------------------- preview
def recolor_for_preview():
    def setcol(mat, hexc):
        rgb = [int(hexc[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        lin = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
        if mat.use_nodes:
            b = mat.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Base Color"].default_value = (*lin, 1)
        mat.diffuse_color = (*lin, 1)

    def shade(hexc, f):
        return "".join("%02x" % int(max(0, min(1, int(hexc[i:i + 2], 16) / 255 * f)) * 255) for i in (0, 2, 4))
    skin, top, bot = "bf825f", "658a83", "675d73"
    for m in D.materials:
        base = m.name.split(".")[0]
        if base in ("Skin", "Skin_Face_Surface"):
            setcol(m, skin)
        elif base == "Top":
            setcol(m, top)
        elif base == "Top_seam":
            setcol(m, shade(top, .8))
        elif base == "Bottom":
            setcol(m, bot)
        elif base == "Bottom_seam":
            setcol(m, shade(bot, .81))


def apply_pose(rig, pose):
    """Rest, both arms raised sideways, or seated (hips and knees at ninety degrees)."""
    from mathutils import Matrix
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

    def spin(name, axis, degrees):
        pb = rig.pose.bones[name]
        head = pb.head.copy()
        rot = Matrix.Translation(head) @ Matrix.Rotation(math.radians(degrees), 4, axis) @ Matrix.Translation(-head)
        pb.matrix = rot @ pb.matrix
        bpy.context.view_layer.update()
    if pose == "arms":
        spin("Arm_L", "Y", 100)
        spin("Arm_R", "Y", -100)
    elif pose == "sit":
        for s in ("L", "R"):
            spin("Leg_" + s, "X", -88)
            spin("Shin_" + s, "X", 88)
    bpy.context.view_layer.update()


def render_preview(family, objs, st, outdir, poses):
    from mathutils import Matrix
    show = ("Skin_", "Outfit_Swim", LOOK)
    for o in D.objects:
        if o.type in ("MESH", "CURVE"):
            keep = o.name.startswith(show) or o.name.startswith("Head")
            o.hide_render = not keep
            o.hide_viewport = not keep
        if o.name == "Studio_floor" or o.type == "LIGHT":
            o.hide_render = True
    for prefix in [h for h in args.hide.split(",") if h]:
        for o in D.objects:
            if o.name.startswith(prefix):
                o.hide_render = True
    recolor_for_preview()
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 900
    w = D.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.78, 0.8, 1)
    sc.world = w

    def light(name, loc, energy):
        ld = D.lights.new(name, "SUN")
        ld.energy = energy
        lo = D.objects.new(name, ld)
        sc.collection.objects.link(lo)
        lo.rotation_euler = (-Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    light("k", (-2, -3, 3), 3.0)
    light("f", (3, -2, 1), 1.2)
    light("b", (0, 3, 2), 1.0)
    cam_d = D.cameras.new("cam")
    cam = D.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam_d.type = "ORTHO"
    cam_d.clip_end = 50
    k = st["k"]
    zc = st["crotch"] + 0.30 * k + 0.05
    cam_d.ortho_scale = 0.98 * (0.55 + 0.45 * k) + 0.10
    rig = D.objects["LifeRig"]
    outdir.mkdir(parents=True, exist_ok=True)
    views = {"front": ((0, -4, zc), (math.pi / 2, 0, 0)),
             "side": ((4, 0, zc), (math.pi / 2, 0, math.pi / 2)),
             "back": ((0, 4, zc), (math.pi / 2, 0, math.pi)),
             "q": ((-2.4, -2.9, zc + 0.3), None)}
    wanted = args.views.split(",")
    if args.zoom:
        zx, zz, zs = [float(t) for t in args.zoom.split(",")]
        views = {"zoomf": ((zx, -4, zz), (math.pi / 2, 0, 0)),
                 "zoomq": ((zx - 2.4, -2.9, zz + 0.5), None),
                 "zooms": ((4, 0, zz), (math.pi / 2, 0, math.pi / 2)),
                 "zoomb": ((zx, 4, zz), (math.pi / 2, 0, math.pi))}
        wanted = [v for v in wanted if v.startswith("zoom")] or list(views)
    for pose in poses:
        apply_pose(rig, pose)
        if pose == "arms":
            cam_d.ortho_scale = (0.98 * (0.55 + 0.45 * k) + 0.10) * 1.5
        elif pose == "sit":
            cam_d.ortho_scale = (0.98 * (0.55 + 0.45 * k) + 0.10) * 1.2
        for vn, (loc, rot) in views.items():
            if vn not in wanted or (pose != "rest" and vn in ("side", "back")):
                continue
            if args.zoom:
                cam_d.ortho_scale = zs
                cam.location = loc
                zc_use = zz
            else:
                zc_use = zc
            cam.location = loc
            if rot is None:
                cam.rotation_euler = (Vector((zx if args.zoom else 0, 0, zc_use)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            else:
                cam.rotation_euler = rot
            sc.render.filepath = str(outdir / ("%s_%s_%s.png" % (family, pose, vn)))
            bpy.ops.render.render(write_still=True)
    apply_pose(rig, "rest")


# ---------------------------------------------------------------- main
report = {}
for family in FAMILIES:
    blend = ROOT / "art" / (BLENDS[family] + ".blend")
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    group, objs, st = build_swim(family)
    for o in D.objects:
        if o.name.startswith(LOOK):
            o.hide_render = False
            o.hide_viewport = False
    entry = {"source": str(blend.relative_to(ROOT)),
             "meshes": {n: len(o.data.vertices) for n, o in objs.items()}}
    if args.export:
        entry["sha256"] = export_look(family, group, ROOT / "assets/models/looks")
    if args.preview:
        render_preview(family, objs, st, args.preview, args.pose.split(","))
    report[family] = entry
print("JUSTLIFE_SWIMWEAR " + json.dumps(report))
