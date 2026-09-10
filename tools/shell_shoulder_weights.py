"""Harmonic shoulder weights for the jacket and hoodie shells.

The garment shells were bound with an analytic blend by width alone, so the
shoulder cap took partial arm weight wherever it sat over the arm's silhouette
and tore when the arm rose. This repeats the reviewed casual-shirt repair
(tools/adult_casual_drape/author_weights.py) on the jacket and hoodie shells of
every age family: the lower sleeves seed as arm, the central torso and collar
seed as body, shell vertices lying over the upper-arm skin are protected as
arm, and a harmonic field solved across the shoulder band gives the blend.
Spine and elbow fractions keep their authored values.

  blender -b --python tools/shell_shoulder_weights.py -- --family all --save
  blender -b --python tools/shell_shoulder_weights.py -- --family adult --render /tmp/out --raise 150

Thresholds are the adult ones scaled by each family's shell height and width.
"""
import argparse, json, math, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
D = bpy.data
FAMILIES = ['adult', 'child', 'teen', 'elder']
SHELLS = ['Outfit_Jacket_Shell', 'Outfit_Hoodie_Shell']
ADULT_TOP = 1.417   # adult shell collar height
ADULT_HALF = 0.298  # adult shell half width
GROUPS = {'Root', 'Spine', 'Arm_L', 'Arm_R', 'Forearm_L', 'Forearm_R'}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--family', default='all')
parser.add_argument('--save', action='store_true', help='write the repaired weights back into the family blend')
parser.add_argument('--render', type=Path, help='render the hoodie with the left arm raised before and after the repair')
parser.add_argument('--raise', dest='raise_degrees', type=float, default=150.0, help='left upper-arm rotation for the render, degrees')
parser.add_argument('--axis', default='x', help='pose bone axis for the raise render')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
families = FAMILIES if args.family == 'all' else [args.family]


def smooth(a, b, v):
    t = max(0., min(1., (v - a) / (b - a)))
    return t * t * (3 - 2 * t)


def weights(o, i):
    return {o.vertex_groups[g.group].name: float(g.weight) for g in o.data.vertices[i].groups if g.weight > 0}


def geometry(o):
    o.data.calc_loop_triangles()
    src = o.data.shape_keys.key_blocks['Basis'].data if o.data.shape_keys else o.data.vertices
    pts = [o.matrix_world @ v.co for v in src]
    tris = [tuple(t.vertices) for t in o.data.loop_triangles]
    return pts, tris, BVHTree.FromPolygons(pts, tris, all_triangles=True)


def solve(shell, arms, zs, xs):
    pts, tris, _ = geometry(shell)
    n = len(pts)
    nb = [set() for _ in range(n)]
    for e in shell.data.edges:
        a, b = e.vertices
        nb[a].add(b); nb[b].add(a)
    def components_below(cut):
        remaining = {i for i, p in enumerate(pts) if p.z < cut}
        found = []
        while remaining:
            stack = [min(remaining)]; remaining.remove(stack[0]); comp = []
            while stack:
                i = stack.pop(); comp.append(i)
                new = nb[i] & remaining; remaining -= new; stack.extend(sorted(new))
            found.append(comp)
        found.sort(key=lambda ids: sum(pts[i].x for i in ids) / len(ids))
        return found
    # The shell's sleeves join its body along a seam; the highest cut under
    # which the mesh splits into left sleeve, torso and right sleeve marks the
    # armpit, and everything below it seeds by that connectivity.
    cut = 1.25 * zs; comps = []
    while cut > .95 * zs:
        comps = components_below(cut)
        if len(comps) == 3 and len(comps[1]) >= len(comps[0]) and len(comps[1]) >= len(comps[2]): break
        cut -= .01 * zs
    seeds = {}
    rule = 'lower sleeves and torso by connectivity below the armpit cut'
    if len(comps) == 3:
        for ci, ids in enumerate(comps):
            for i in ids: seeds[i] = 0. if ci == 1 else 1.
    else:
        rule = 'lower band by width (connectivity did not split into sleeves and torso)'
        cut = 1.20 * zs
        for i, p in enumerate(pts):
            if p.z < cut: seeds[i] = 1. if abs(p.x) >= .207 * xs else 0.
    for i, p in enumerate(pts):
        if abs(p.x) <= .12 * xs or p.z >= 1.385 * zs: seeds[i] = 0.
    # Shell over the upper-arm skin follows the arm: a looser sleeve sits
    # farther from the skin than the fitted shirt, so the support radius is wider.
    support = 0
    for i, p in enumerate(pts):
        if i in seeds or not (cut <= p.z <= 1.37 * zs and abs(p.x) >= .145 * xs): continue
        side = 'L' if p.x < 0 else 'R'
        obj, apts, atris, tree = arms[side]
        hit, normal, ti, dist = tree.find_nearest(p)
        if hit is None or ti is None: continue
        if dist <= .03 * zs and all(weights(obj, j) == {'Arm_' + side: 1.} for j in atris[ti]):
            seeds[i] = 1.; support += 1
    deg = max(len(s) for s in nb)
    idx = np.zeros((n, deg), dtype=np.int64); w = np.zeros((n, deg))
    for i, s in enumerate(nb):
        for k, j in enumerate(sorted(s)):
            idx[i, k] = j; w[i, k] = 1. / (pts[i] - pts[j]).length
    wsum = w.sum(1)
    field = np.full(n, .5); fixed = np.zeros(n, bool)
    for i, v in seeds.items():
        field[i] = v; fixed[i] = True
    free = ~fixed
    iterations = 0
    for iterations in range(1, 60001):
        new = (w * field[idx]).sum(1) / wsum
        new[fixed] = field[fixed]
        change = float(np.abs(new - field)[free].max()) if free.any() else 0.
        field = new
        if change <= 1e-8: break
    facts = {'vertices': n, 'armpit_cut': cut, 'components_below_cut': [len(c) for c in comps], 'seed_rule': rule, 'seeds': len(seeds),
             'upper_arm_support': support, 'free': int(free.sum()), 'iterations': iterations, 'final_change': change}
    return pts, field, facts


def apply(shell, pts, field, zs):
    n = len(pts)
    old = [weights(shell, i) for i in range(n)]
    new = []
    for i, p in enumerate(pts):
        side = 'L' if p.x < 0 else 'R'
        torso = old[i].get('Root', 0) + old[i].get('Spine', 0)
        spine = old[i].get('Spine', 0) / torso if torso > 0 else smooth(1.02 * zs, 1.20 * zs, p.z)
        arm = old[i].get('Arm_' + side, 0) + old[i].get('Forearm_' + side, 0)
        elbow = old[i].get('Forearm_' + side, 0) / arm if arm > 0 else 1 - smooth(1.025 * zs, 1.17 * zs, p.z)
        a = float(field[i])
        vals = {'Root': (1 - a) * (1 - spine), 'Spine': (1 - a) * spine, 'Arm_' + side: a * (1 - elbow), 'Forearm_' + side: a * elbow}
        total = sum(vals.values())
        new.append({k: v / total for k, v in vals.items() if v / total > 1e-6})
    for g in shell.vertex_groups:
        g.remove(list(range(n)))
    for i, v in enumerate(new):
        for g, a in v.items(): shell.vertex_groups[g].add([i], a, 'REPLACE')
    actual = [weights(shell, i) for i in range(n)]
    changed = sum(1 for a, b in zip(old, actual) if any(abs(a.get(k, 0) - b.get(k, 0)) > 1e-6 for k in set(a) | set(b)))
    return {'changed_vertices': changed, 'groups_used': sorted({k for v in actual for k in v})}


def render(family, label, out):
    scene = bpy.context.scene
    scene.camera = D.objects['Character_Portrait']; scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 600; scene.render.resolution_y = 900
    offs = ('Outfit_Casual', 'Outfit_Jacket', 'Outfit_Cardigan', 'Outfit_Tee', 'Outfit_Hoodie', 'Bottom_Continuous', 'Bottom_Cuff', 'Bottom_Shorts',
            'Hair_Bob', 'Hair_Crop', 'Hair_Curls', 'Hair_Long', 'Hair_Pony', 'Hair_Buzz', 'Skin_Leg_continuous')
    on = ('Outfit_Hoodie', 'Bottom_Continuous', 'Bottom_Cuff', 'Hair_Crop')
    for o in D.objects:
        if o.type in ('MESH', 'CURVE', 'EMPTY'): o.hide_render = False
        if o.name.startswith(offs): o.hide_render = True
        if o.name.startswith(on): o.hide_render = False
    rig = D.objects['LifeRig']
    for bone in rig.pose.bones: bone.rotation_mode = 'XYZ'; bone.rotation_euler = (0, 0, 0)
    bone = rig.pose.bones['Arm_L']
    angle = math.radians(args.raise_degrees)
    bone.rotation_euler = {'x': (angle, 0, 0), 'y': (0, angle, 0), 'z': (0, 0, angle)}[args.axis]
    bpy.context.view_layer.update()
    out.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out / f'{family}_hoodie_raised_{label}.png')
    bpy.ops.render.render(write_still=True)
    for bone in rig.pose.bones: bone.rotation_euler = (0, 0, 0)


report = {}
for family in families:
    blend = ROOT / 'art' / ('characters.blend' if family == 'adult' else f'characters_{family}.blend')
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    bpy.context.view_layer.update()
    if args.render: render(family, 'before', args.render)
    shell0 = D.objects['Outfit_Jacket_Shell']
    pts0 = [shell0.matrix_world @ v.co for v in shell0.data.vertices]
    zs = max(p.z for p in pts0) / ADULT_TOP
    xs = max(abs(p.x) for p in pts0) / ADULT_HALF
    arms = {}
    for side in ['L', 'R']:
        o = D.objects['Skin_Arm_continuous_' + side]
        arms[side] = (o, *geometry(o))
    report[family] = {'source': str(blend.relative_to(ROOT)), 'height_scale': zs, 'width_scale': xs, 'shells': {}}
    for name in SHELLS:
        shell = D.objects.get(name)
        if shell is None: continue
        pts, field, facts = solve(shell, arms, zs, xs)
        facts.update(apply(shell, pts, field, zs))
        report[family]['shells'][name] = facts
    if args.render: render(family, 'after', args.render)
    if args.save:
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(blend))
        report[family]['saved'] = True
print('JUSTLIFE_SHOULDER_REPORT ' + json.dumps(report))
