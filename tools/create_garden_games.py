"""Original JustLife garden game and activity models.

Run:
    blender -b --factory-startup -t 2 --python-exit-code 2 \
        --python tools/create_garden_games.py

Fifty garden game and activity kinds, each authored at its small catalogue
footprint and exported as its own GLB under `assets/models/`. Every model
carries exactly one joined mesh named `Tint`: the surface a player's colour
choice repaints at runtime. Coordinates are Godot metres - x right, y up, z
toward the front of the object - with ground contact at y = 0.
"""
import argparse, bmesh, math, pathlib, sys
import bpy
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODELS = ROOT / 'assets/models'
ART = ROOT / 'art/garden_games'
GROUP = 'GARDEN_GAMES'

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------- materials
M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb = [int(hexcolor[i:i+2], 16)/255 for i in (0, 2, 4)]
    linear = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name); m.diffuse_color = (*linear, 1)
    m.use_nodes = True; p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = m.diffuse_color
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    if emit:
        p.inputs['Emission Color'].default_value = m.diffuse_color
        p.inputs['Emission Strength'].default_value = emit
    M[name] = m; return m

for n, h in [('oak','AB7951'),('oak_light','D7AE7E'),('walnut','624435'),
             ('cream','EFE9DA'),('white','FAF6EA'),('ivory','F6F1E4'),
             ('teal','417A71'),('teal_light','86ADA0'),('coral','C97C66'),
             ('gold','C8A562'),('dark','263E3C'),('black','1D292B'),
             ('green','48794B'),('leaf_light','749752'),('soil','42352D'),
             ('blue','7CA4AA'),('linen','DECFAF'),('water','B7D9DB'),
             ('rust','9A5A44'),('brick','8C5A4A'),('mustard','D2A24B'),
             ('plum','6E5470'),('sky','9EC1CF'),('rose','D9A0A0'),
             ('graphite','4A4F55'),('concrete','B4B2AA'),('chalk','F0EEE6'),
             ('rubber','33383A'),('net','E8E4D8'),('plastic','DCE3E0'),
             ('hemp','C9B183'),('felt','5C6B62')]:
    mat(n, h)
mat('steel', 'B9BEC2', .35, .45)
mat('brass', 'C8A562', .4, .35)
mat('mirror_glass', 'EAF2F6', .25, 0, .35)
mat('ember', 'C0392B', .5, 0, .6)
mat('tint_neutral', 'D8D8D0', .6, 0)

# ---------------------------------------------------------------- primitives
active = []   # every object of the model currently being built
TINT = []     # objects that merge into the model's single `Tint` surface

def xyz(p):
    return (p[0], -p[2], p[1])

def _apply(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True); bpy.context.view_layer.objects.active = o
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)

def _finish(o, n, m, tint):
    o.name = n; o.data.materials.append(M[m]); active.append(o)
    if tint:
        TINT.append(o)
    return o

def box(n, p, s, m, bevel=.03, tint=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o = bpy.context.object; o.dimensions = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Soft crafted edges', 'BEVEL')
        mod.width = bevel; mod.segments = 3
        o.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return _finish(o, n, m, tint)

def ell(n, p, s, m, tint=False):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=xyz(p))
    o = bpy.context.object; o.scale = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for f in o.data.polygons:
        f.use_smooth = True
    return _finish(o, n, m, tint)

def cyl(n, p, r, h, m, top=None, axis='Y', tint=False):
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=r, radius2=r if top is None else top,
                                    depth=h, location=xyz(p))
    o = bpy.context.object
    if axis == 'X':
        o.rotation_euler = (0, math.pi/2, 0)
    elif axis == 'Z':
        o.rotation_euler = (math.pi/2, 0, 0)
    mod = o.modifiers.new('Rounded rims', 'BEVEL'); mod.width = .012; mod.segments = 3
    for f in o.data.polygons:
        f.use_smooth = True
    return _finish(o, n, m, tint)

def disc(n, p, r, h, m, axis='Y', verts=16, tint=False):
    """Low-poly flat cylinder, for the many small discs a board game needs."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=xyz(p))
    o = bpy.context.object
    if axis == 'X':
        o.rotation_euler = (0, math.pi/2, 0)
    elif axis == 'Z':
        o.rotation_euler = (math.pi/2, 0, 0)
    return _finish(o, n, m, tint)

def rod(n, a, b, r, m, tint=False):
    av, bv = Vector(xyz(a)), Vector(xyz(b)); d = bv - av
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=r, depth=d.length,
                                        location=(av+bv)/2)
    o = bpy.context.object; o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return _finish(o, n, m, tint)

# Torus planes, in Godot terms: 'H' lies flat on the ground, 'V' stands upright
# facing the player, 'S' stands upright facing along the player's left.
PLANE = {'H': (0, 0, 0), 'V': (math.pi/2, 0, 0), 'S': (0, math.pi/2, 0)}
def torus(n, p, major, minor, m, plane='H', tint=False):
    bpy.ops.mesh.primitive_torus_add(major_segments=32, minor_segments=10,
                                     major_radius=major, minor_radius=minor,
                                     location=xyz(p))
    o = bpy.context.object; o.rotation_euler = PLANE[plane]
    for f in o.data.polygons:
        f.use_smooth = True
    return _finish(o, n, m, tint)

def half_torus(n, p, major, minor, m, plane='V', keep='upper', tint=False):
    """Half a ring. `keep` names the Godot half-space that survives: an upper
    arch, a horseshoe open to the front, or a loop open to the back."""
    o = torus(n, p, major, minor, m, plane=plane, tint=tint)
    R = o.rotation_euler.to_matrix()
    def outside(face):
        w = R @ face.calc_center_median()
        g = Vector((w.x, w.z, -w.y))
        return {'upper': g.y < -1e-6, 'front': g.z < -1e-6,
                'back': g.z > 1e-6, 'left': g.x > 1e-6}[keep]
    me = o.data; bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if outside(f)], context='FACES')
    bm.to_mesh(me); bm.free(); me.update()
    return o

def join_tint(name='Tint', m='tint_neutral'):
    """Merge every surface the colour choice repaints into one mesh named `Tint`."""
    objs = [o for o in TINT if o.name in bpy.data.objects]
    if not objs:
        return None
    for o in objs:
        _apply(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    g = bpy.context.object
    # The exporter names a glTF mesh after the Blender mesh datablock, so both
    # the datablock and the object carry the name that must reach every GLB.
    stale = bpy.data.meshes.get(name)
    if stale is not None and stale is not g.data:
        stale.name = 'Superseded tint'
    g.name = name; g.data.name = name
    g.data.materials.clear(); g.data.materials.append(M[m])
    for f in g.data.polygons:
        f.material_index = 0
    for o in objs[1:]:
        if o in active:
            active.remove(o)
    TINT.clear()
    return g

def rot(o, x=0.0, y=0.0, z=0.0):
    """Rotation in Godot terms: `x` pitches about Godot X, `y` rolls about
    Godot Z, `z` yaws about Godot Y."""
    o.rotation_euler = (x, y, z); return o

def ground_contact(name):
    """Ground contact is part of the contract: a tilted rod's rim, a rounded
    tyre or a leaning sheet can sit a centimetre off the ground or dip below it,
    so snap the whole model so its lowest vertex is exactly at y = 0."""
    bpy.context.view_layer.update()
    low = min((o.matrix_world @ v.co).z for o in active for v in o.data.vertices)
    if abs(low) > .0005:
        for o in active:
            o.location.z -= low
        print('  %s: shifted %+.4f m to sit exactly on the ground' % (name, -low))

# ---------------------------------------------------------------- ball games
def game_trampoline():
    """1.5 x 1.5 round trampoline with a safety net."""
    for i in range(6):
        a = i*math.pi/3 + math.pi/6
        rod('Splayed leg', (math.sin(a)*.44, 0, math.cos(a)*.44),
            (math.sin(a)*.62, .38, math.cos(a)*.62), .022, 'graphite')
    torus('Frame rail', (0, .38, 0), .70, .045, 'graphite')
    cyl('Jumping mat', (0, .41, 0), .62, .022, 'rubber', tint=True)
    torus('Safety pad', (0, .40, 0), .70, .058, 'rubber', tint=True)
    for i in range(16):
        a = i*math.pi/8
        rod('Net cord', (math.sin(a)*.69, .40, math.cos(a)*.69),
            (math.sin(a)*.69, .57, math.cos(a)*.69), .006, 'net')
    torus('Net top line', (0, .57, 0), .69, .011, 'net')

def game_hopscotch():
    """1.0 x 1.8 paving grid with the numbers raised as painted tiles."""
    zs = [-.72, -.48, -.24, .00, .24, .48, .72]
    for row, z in enumerate(zs):
        for i, x in enumerate([0] if row % 2 == 0 else [-.24, .24]):
            box('Paving slab', (x, .02, z), (.46, .04, .24), 'concrete', .008)
            box('Painted number', (x, .045, z), (.09, .012, .13), 'chalk', 0, tint=True)
            box('Number stroke', (x, .052, z+.04), (.13, .012, .022), 'chalk', 0, tint=True)
            box('Number stroke', (x, .052, z-.02), (.13, .012, .022), 'chalk', 0, tint=True)
    for z in (-.86, .86):
        box('Court frame', (0, .015, z), (.98, .03, .04), 'mustard', .008, tint=True)
    for x in (-.49, .49):
        box('Court frame', (x, .015, 0), (.04, .03, 1.76), 'mustard', .008, tint=True)

def game_hoop():
    """0.7 x 0.7 ground hoop leaning back on a stand."""
    box('Hoop base', (0, .025, .30), (.34, .05, .28), 'graphite', .012)
    cyl('Hoop post', (0, .28, .30), .030, .50, 'graphite')
    rod('Hoop arm', (0, .50, .30), (0, .46, .06), .024, 'graphite')
    o = torus('Ground hoop', (0, .42, .0), .35, .028, 'plastic', plane='V', tint=True)
    rot(o, math.radians(46), 0, 0)
    rod('Hoop brace', (0, .12, .30), (0, .40, .02), .016, 'graphite')

def game_skipping_rope():
    """0.5 x 0.5 coiled skipping rope with two handles."""
    for r, y in [(.24, .030), (.205, .052), (.170, .074)]:
        torus('Coiled rope', (0, y, 0), r, .013, 'hemp')
    rod('Rope end', (.17, .070, .02), (.21, .035, -.05), .012, 'hemp')
    rod('Rope end', (-.17, .070, .02), (-.21, .035, -.05), .012, 'hemp')
    for x in (-.20, .20):
        rod('Rope handle', (x, .035, -.06), (x, .035, -.24), .026, 'oak_light', tint=True)
        rod('Handle ferrule', (x, .035, -.06), (x, .035, -.09), .030, 'brass')

def game_dartboard():
    """0.6 x 0.4 dartboard on a fold-out stand."""
    for sx in (-1, 1):
        rod('Stand leg', (sx*.26, .03, -.22), (sx*.12, .54, -.05), .022, 'oak')
        rod('Stand foot', (sx*.26, .025, -.26), (sx*.26, .025, .14), .022, 'oak')
    rod('Stand crossbar', (-.24, .10, -.19), (.24, .10, -.19), .018, 'oak')
    cyl('Dartboard', (0, .60, 0), .28, .05, 'dark', axis='Z', tint=True)
    disc('Board face', (0, .60, .030), .235, .008, 'ivory', axis='Z')
    disc('Score ring', (0, .60, .036), .165, .008, 'coral', axis='Z')
    disc('Score ring', (0, .60, .042), .095, .008, 'ivory', axis='Z')
    disc('Bullseye', (0, .60, .048), .036, .010, 'coral', axis='Z')

def game_croquet():
    """2.0 x 1.2 croquet set - hoops, two mallets and balls."""
    for x in (-.72, 0, .72):
        half_torus('Croquet hoop', (x, .19, -.44), .17, .014, 'white', plane='V', keep='upper')
        for sx in (-1, 1):
            rod('Hoop foot', (x+sx*.17, .19, -.44), (x+sx*.19, .01, -.44), .014, 'white')
    for i, x in enumerate((-.60, .54)):
        cyl('Mallet head', (x, .05, .22-i*.10), .048, .24, 'oak', axis='X', tint=True)
        rod('Mallet shaft', (x, .055, .22-i*.10), (x+.30, .60, .10-i*.10), .015,
            'oak_light', tint=True)
        ell('Croquet ball', (x+.18, .046, .48-i*.96), (.046, .046, .046),
            'coral' if i else 'mustard')
    ell('Croquet ball', (.10, .046, .56), (.046, .046, .046), 'teal')
    cyl('Starting peg', (.24, .09, -.56), .024, .18, 'brass', top=.016)

def game_ring_toss():
    """0.9 x 0.9 peg board with throwing rings."""
    box('Peg board', (0, .30, 0), (.84, .06, .54), 'oak_light', .012, tint=True)
    for sx in (-1, 1):
        rod('Board leg', (sx*.34, .02, -.24), (sx*.34, .30, -.10), .020, 'oak')
        rod('Board leg', (sx*.34, .02, .20), (sx*.34, .30, .06), .020, 'oak')
    rod('Leg brace', (-.34, .04, -.02), (.34, .04, -.02), .016, 'oak')
    for i in range(3):
        for j in range(3):
            cyl('Toss peg', (-.24+i*.24, .39, -.18+j*.17), .011, .12, 'brass')
    for x, y, z in [(-.24, .45, -.18), (-.24, .50, -.18), (0, .45, -.01),
                    (.24, .45, .16), (.24, .50, .16)]:
        torus('Throwing ring', (x, y, z), .055, .012, 'rubber', plane='H', tint=True)
    for x, z in [(-.38, .38), (.38, -.38)]:
        torus('Throwing ring', (x, .014, z), .055, .012, 'rubber', plane='H', tint=True)

def game_mini_golf():
    """1.8 x 0.9 putting green with a hole, flag and club."""
    box('Putting green', (0, .025, 0), (1.78, .05, .88), 'leaf_light', .012, tint=True)
    for z in (-.44, .44):
        box('Green rail', (0, .045, z), (1.80, .05, .05), 'walnut', .008)
    for x in (-.89, .89):
        box('Green rail', (x, .045, 0), (.05, .05, .88), 'walnut', .008)
    disc('Cup liner', (.48, .052, .06), .055, .02, 'dark')
    cyl('Flag pole', (.48, .45, .06), .012, .80, 'steel')
    box('Flag', (.62, .74, .06), (.24, .17, .012), 'coral', .004)
    rod('Golf shaft', (-.62, .06, -.30), (-.30, .70, -.12), .013, 'graphite')
    box('Putter head', (-.66, .06, -.30), (.11, .035, .05), 'graphite', .008)
    ell('Golf ball', (-.10, .07, .20), (.025, .025, .025), 'white')

def game_bowling():
    """0.8 x 1.4 lane mat with pins and a ball."""
    box('Lane mat', (0, .012, 0), (.80, .024, 1.40), 'felt', .008, tint=True)
    box('Foul line', (0, .028, -.50), (.80, .01, .05), 'chalk', 0)
    box('Pin spot', (0, .028, .44), (.40, .01, .40), 'chalk', 0)
    for x, z in [(0, .42), (-.13, .56), (.13, .56), (-.26, .70), (0, .70), (.26, .70)]:
        cyl('Bowling pin', (x, .17, z), .050, .30, 'ivory', top=.022, tint=True)
        torus('Pin neck', (x, .27, z), .036, .010, 'ivory', plane='H', tint=True)
    ell('Bowling ball', (-.14, .080, -.58), (.080, .080, .080), 'dark')
    for i in range(3):
        disc('Finger hole', (-.14+((i % 2)*.04-.02), .148, -.58+(i//2)*.04), .011, .02, 'black')

def game_table_tennis():
    """2.4 x 1.2 folding table with a net and two bats."""
    for x in (-1.02, 1.02):
        for z in (-.46, .46):
            box('Table leg', (x, .36, z), (.07, .72, .07), 'graphite', .012)
    rod('Table brace', (-1.02, .22, 0), (1.02, .22, 0), .018, 'graphite')
    box('Table top', (0, .73, 0), (2.34, .06, 1.14), 'teal', .012, tint=True)
    box('Centre line', (0, .764, 0), (2.34, .006, .012), 'white', 0)
    box('Net', (0, .81, 0), (2.40, .15, .014), 'net', .004)
    box('Net band', (0, .885, 0), (2.40, .032, .018), 'white', .004)
    for x in (-1.18, 1.18):
        box('Net post', (x, .76, 0), (.04, .34, .04), 'graphite', .006)
    for i, (x, z) in enumerate([(-.60, -.22), (.60, .22)]):
        disc('Bat blade', (x, .765, z), .082, .016, 'rubber' if i else 'ember')
        rod('Bat handle', (x, .775, z+.09), (x, .775, z+.20), .016, 'oak_light')
    ell('Table tennis ball', (.06, .78, .30), (.021, .021, .021), 'white')

def game_badminton():
    """1.6 x 1.0 net on posts with two rackets."""
    for x in (-.76, .76):
        cyl('Net post', (x, .50, -.16), .030, 1.00, 'steel')
        box('Post base', (x, .022, -.16), (.24, .044, .34), 'graphite', .01)
    for y in (.52, .62, .72, .82, .92):
        rod('Net cord', (-.74, y, -.16), (.74, y, -.16), .007, 'net')
    for i in range(6):
        rod('Net cord', (-.60+i*.24, .50, -.16), (-.60+i*.24, .92, -.16), .007, 'net')
    box('Net band', (0, .965, -.16), (1.52, .05, .014), 'white', .004, tint=True)
    for i, (x, z) in enumerate([(-.34, -.46), (.36, -.50)]):
        o = torus('Racket frame', (x, .16, z), .105, .012, 'plastic', plane='V', tint=True)
        rot(o, .18 if not i else -.12, 0, 0)
        rod('Racket string', (x-.08, .16, z), (x+.08, .16, z), .004, 'white')
        rod('Racket string', (x, .08, z), (x, .24, z), .004, 'white')
        rod('Racket shaft', (x, .05, z), (x-.14, .03, z), .012, 'plastic', tint=True)
        rod('Racket grip', (x-.14, .03, z), (x-.26, .028, z), .019, 'rubber')
    ell('Shuttlecock', (.05, .03, .30), (.03, .04, .03), 'white')

def game_football_goal():
    """2.0 x 0.9 goal with a net."""
    for x in (-.92, .92):
        cyl('Goal post', (x, .43, 0), .035, .86, 'white', tint=True)
        rod('Goal base rail', (x, .035, 0), (x, .035, -.82), .028, 'white', tint=True)
        rod('Goal back stay', (x, .86, 0), (x, .035, -.82), .024, 'white', tint=True)
    rod('Goal crossbar', (-.92, .86, 0), (.92, .86, 0), .035, 'white', tint=True)
    for i in range(7):
        rod('Back netting', (-.84+i*.28, .03, -.82), (-.84+i*.28, .80, -.82), .005, 'net')
    for y in (.20, .40, .60, .78):
        rod('Back netting', (-.90, y, -.82), (.90, y, -.82), .005, 'net')
    for sx in (-1, 1):
        for y in (.30, .58):
            rod('Side netting', (sx*.92, y, -.78), (sx*.92, y, -.06), .005, 'net')

def game_basketball():
    """0.9 x 0.9 hoop on a pole with a backboard."""
    box('Hoop base', (0, .05, -.20), (.60, .10, .46), 'graphite', .014)
    for sx in (-1, 1):
        disc('Base wheel', (sx*.24, .05, .02), .05, .05, 'rubber', axis='X')
    cyl('Hoop pole', (0, .80, -.16), .042, 1.44, 'graphite')
    rod('Hoop brace', (0, .30, -.14), (0, 1.05, .02), .020, 'graphite')
    box('Backboard', (0, 1.55, .06), (.84, .60, .03), 'white', .008, tint=True)
    for x in (-.15, .15):
        box('Backboard target', (x, 1.42, .078), (.016, .22, .004), 'coral', 0)
    for y in (1.32, 1.52):
        box('Backboard target', (0, y, .078), (.32, .016, .004), 'coral', 0)
    torus('Hoop ring', (0, 1.30, .26), .12, .013, 'coral', plane='H')
    for i in range(8):
        a = i*math.pi/4
        rod('Hoop net', (math.sin(a)*.12, 1.29, .26+math.cos(a)*.12),
            (math.sin(a)*.07, 1.13, .26+math.cos(a)*.07), .005, 'white')
    torus('Hoop net', (0, 1.12, .26), .07, .007, 'white', plane='H')

def game_bean_bags():
    """0.8 x 0.8 target board with bean bags."""
    o = box('Target board', (0, .56, -.20), (.80, .56, .035), 'oak_light', .010, tint=True)
    rot(o, -.28, 0, 0)
    for sx in (-1, 1):
        rod('Board leg', (sx*.32, .02, -.02), (sx*.32, .42, -.24), .022, 'oak')
    rod('Board brace', (-.36, .22, -.11), (.36, .22, -.11), .018, 'oak')
    for x, y in [(-.20, .70), (.20, .70), (0, .44)]:
        torus('Target ring', (x, y, -.13), .095, .016, 'coral', plane='V')
    for i in range(4):
        x = -.27 + i*.18
        o = ell('Bean bag', (x, .048, .24+(i % 2)*.10), (.078, .048, .105),
                ['teal', 'mustard', 'plum', 'rose'][i], tint=True)
        rot(o, 0, 0, (i*.3)-.4)

def game_horseshoes():
    """1.2 x 1.0 two stakes with horseshoes."""
    for sx in (-1, 1):
        cyl('Pit stake', (sx*.30, .19, -.36), .020, .38, 'steel')
        box('Stake pad', (sx*.30, .012, -.36), (.30, .024, .30), 'soil', .006)
    for x, z, yaw in [(-.50, -.08, .32), (-.18, -.40, .55), (.22, .06, -.32), (.50, -.34, -.50)]:
        o = half_torus('Horseshoe', (x, .020, z), .085, .017, 'steel',
                       plane='H', keep='front', tint=True)
        rot(o, 0, 0, yaw)
        ell('Horseshoe tip', (x-.085*math.cos(yaw), .020, z-.085*math.sin(yaw)),
            (.017, .017, .017), 'steel')
        ell('Horseshoe tip', (x+.085*math.cos(yaw), .020, z+.085*math.sin(yaw)),
            (.017, .017, .017), 'steel')
    o = half_torus('Horseshoe', (.14, .10, .40), .085, .017, 'steel',
                   plane='V', keep='upper', tint=True)
    rot(o, .18, 0, 0)

def game_boules():
    """0.8 x 0.8 boules carry case with metal balls."""
    box('Boules case', (0, .075, 0), (.78, .15, .52), 'walnut', .014, tint=True)
    for i in range(5):
        box('Case plank', (-.30+i*.15, .078, .265), (.12, .15, .008), 'oak_light', .002)
    for z in (-.25, .25):
        box('Case rim', (0, .152, z), (.80, .028, .04), 'oak_light', .006)
    box('Case lining', (0, .142, 0), (.70, .028, .44), 'felt', 0)
    for i in range(3):
        for j in range(2):
            ell('Boule', (-.20+i*.20, .178, -.13+j*.26), (.042, .042, .042), 'steel')
    ell('Jack', (.30, .020, .37), (.022, .022, .022), 'coral')
    ell('Stray boule', (-.32, .042, -.37), (.042, .042, .042), 'steel')
    half_torus('Case handle', (0, .16, 0), .16, .013, 'hemp', plane='V', keep='upper')

# ---------------------------------------------------------------- target games
def game_skittles():
    """1.0 x 0.6 skittle row with a ball."""
    box('Skittle lane', (0, .010, 0), (.98, .02, .58), 'felt', .008)
    for x in (-.42, -.25, -.08, .08, .25, .42):
        cyl('Skittle', (x, .22, 0), .052, .44, 'ivory', top=.024, tint=True)
        torus('Skittle neck', (x, .36, 0), .040, .012, 'coral', plane='H', tint=True)
    ell('Skittle ball', (0, .085, .22), (.085, .085, .085), 'dark')
    for i in range(3):
        disc('Finger hole', ((i % 2)*.05-.025, .155, .22+(i//2)*.05), .012, .02, 'black')

def game_quotis():
    """0.9 x 0.9 quoit board with rubber quoits."""
    o = box('Quoit board', (0, .50, -.18), (.80, .58, .035), 'oak', .010)
    rot(o, -.22, 0, 0)
    for sx in (-1, 1):
        rod('Board leg', (sx*.32, .02, -.04), (sx*.32, .40, -.26), .022, 'oak')
    torus('Board ring', (0, .64, -.11), .145, .016, 'coral', plane='V')
    cyl('Hooking peg', (0, .64, -.02), .014, .10, 'steel', axis='Z')
    for x, y, z, m in [(0, .56, -.02, 'rubber'), (-.26, .028, .26, 'mustard'),
                       (-.10, .028, .40, 'coral'), (-.34, .028, .34, 'teal')]:
        torus('Quoit', (x, y, z), .105, .030, m, plane='H', tint=True)

def game_shuffleboard():
    """2.2 x 0.7 long board with pucks."""
    for x in (-.98, -.30, .30, .98):
        box('Board foot', (x, .05, 0), (.10, .10, .50), 'graphite', .010)
    box('Shuffle board', (0, .125, 0), (2.10, .05, .64), 'oak_light', .012, tint=True)
    for z in (-.31, .31):
        box('Board rail', (0, .17, z), (2.10, .05, .04), 'walnut', .008)
    for x in (-.60, 0, .60):
        box('Scoring line', (x, .155, 0), (.02, .012, .60), 'chalk', 0)
    for i, x in enumerate((-.80, -.20, .30, .70)):
        disc('Shuffle puck', (x, .162, ((i % 2)*.22)-.11), .056, .024,
             'graphite' if i % 2 else 'ember', axis='Y')
    disc('Shuffle puck', (.10, .162, .18), .056, .024, 'ember')
    disc('Shuffle puck', (.50, .162, -.16), .056, .024, 'graphite')

def game_connect_four():
    """0.8 x 0.6 standing grid with discs."""
    box('Grid base', (0, .03, 0), (.78, .06, .58), 'graphite', .012)
    for sx in (-1, 1):
        box('Grid foot', (sx*.30, .03, 0), (.16, .06, .60), 'graphite', .012)
        rod('Grid upright', (sx*.36, .05, -.17), (sx*.36, .95, -.17), .028, 'graphite')
        rod('Grid upright', (sx*.36, .05, .17), (sx*.36, .95, .17), .028, 'graphite')
    box('Grid back plate', (0, .60, 0), (.78, .62, .022), 'graphite', .008, tint=True)
    rod('Grid top rail', (-.36, .95, -.17), (-.36, .95, .17), .028, 'graphite')
    rod('Grid top rail', (.36, .95, -.17), (.36, .95, .17), .028, 'graphite')
    for i in range(6):
        for j in range(5):
            disc('Grid disc', (-.325+i*.13, .28+j*.125, .02), .052, .022,
                 'ember' if (i+j) % 2 else 'mustard', axis='Z')

def game_giant_chess():
    """1.8 x 1.8 chess mat with oversized pieces."""
    box('Chess mat', (0, .012, 0), (1.74, .024, 1.74), 'ivory', .008)
    for z in (-.87, .87):
        box('Mat border', (0, .026, z), (1.80, .03, .04), 'walnut', .006)
    for x in (-.87, .87):
        box('Mat border', (x, .026, 0), (.04, .03, 1.80), 'walnut', .006)
    for i in range(8):
        for j in range(8):
            if (i+j) % 2:
                box('Chess square', (-.76+i*.217, .030, -.76+j*.217),
                    (.213, .012, .213), 'walnut', 0, tint=True)
    for x, z in [(-.55, -.55), (-.33, -.55), (-.55, .55)]:
        cyl('Pawn body', (x, .23, z), .075, .28, 'white', top=.055)
        ell('Pawn head', (x, .41, z), (.062, .062, .062), 'white')
        disc('Pawn base', (x, .10, z), .095, .04, 'white')
    cyl('Queen body', (0, .26, -.33), .085, .36, 'ivory', top=.06)
    ell('Queen crown', (0, .47, -.33), (.070, .050, .070), 'ivory')
    disc('Queen base', (0, .11, -.33), .105, .04, 'ivory')
    cyl('King body', (.44, .28, -.10), .085, .40, 'white', top=.06)
    ell('King crown', (.44, .51, -.10), (.070, .055, .070), 'white')
    box('King cross', (.44, .58, -.10), (.02, .10, .02), 'white', 0)
    box('King cross', (.44, .60, -.10), (.08, .02, .02), 'white', 0)
    box('Rook body', (0, .22, .44), (.16, .30, .16), 'ivory', .008)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box('Rook merlon', (sx*.05+(0 if sz > 0 else 0), .40, .44+sz*.05),
                (.05, .09, .05), 'ivory', 0)
    box('Knight body', (.33, .20, .33), (.15, .26, .15), 'white', .008)
    o = box('Knight head', (.33, .38, .35), (.13, .18, .13), 'white', .008)
    rot(o, .35, 0, 0)

def game_checkers():
    """0.9 x 0.9 board with counters."""
    box('Checker board', (0, .03, 0), (.86, .05, .86), 'oak_light', .012)
    for i in range(8):
        for j in range(8):
            if (i+j) % 2:
                box('Board square', (-.375+i*.107, .058, -.375+j*.107),
                    (.105, .008, .105), 'walnut', 0)
    for z in (-.43, .43):
        box('Board edge', (0, .05, z), (.90, .035, .04), 'walnut', .006)
    for x in (-.43, .43):
        box('Board edge', (x, .05, 0), (.04, .035, .90), 'walnut', .006)
    for x, z in [(-.26, -.26), (.26, .26)]:
        for k in range(3):
            disc('Checker counter', (x, .070+k*.026, z), .048, .024,
                 'ember' if z < 0 else 'graphite', axis='Y', tint=True)
    for x, z in [(-.16, .16), (.16, -.16)]:
        disc('Checker counter', (x, .070, z), .048, .024, 'ember', axis='Y', tint=True)

def game_dominoes():
    """1.0 x 0.7 oversized dominoes."""
    box('Domino mat', (0, .008, 0), (.96, .016, .60), 'felt', 0)
    layout = [(-.36, .0, .26, 0), (-.36, .0, -.14, 0), (.02, .0, .24, .40),
              (.30, .0, .08, -.35), (.10, .0, -.26, .55)]
    for x, z, yaw, _ in layout:
        o = box('Domino tile', (x, .022, z), (.17, .028, .34), 'ivory', .008, tint=True)
        rot(o, 0, 0, yaw)
        rod('Tile divider', (x-.085*math.cos(yaw), .024, z+.085*math.sin(yaw)),
            (x+.085*math.cos(yaw), .024, z-.085*math.sin(yaw)), .006, 'graphite')
        for k in range(3):
            disc('Domino pip', (x-.05+(k % 2)*.10, .010, z-.10+k*.09), .016, .012,
                 'graphite', axis='Y')
    o = box('Domino tile', (.32, .10, -.24), (.17, .028, .34), 'ivory', .008, tint=True)
    rot(o, .45, 0, -.25)

def game_jenga():
    """0.6 x 0.6 stacked block tower."""
    h, L, W = .062, .57, .19
    for layer in range(6):
        for i in range(3):
            if layer % 2 == 0:
                pos, size = (-W+i*W, h/2+layer*h, 0), (W, h, L)
            else:
                pos, size = (0, h/2+layer*h, -W+i*W), (L, h, W)
            box('Jenga block', pos, size, 'oak' if layer % 2 else 'oak_light', .006,
                tint=layer in (2, 4))
    # Two spare blocks rest on the tower, so the footprint stays 0.6 x 0.6.
    box('Spare block', (0, .372+h/2, 0), (L, h, W), 'oak_light', .006, tint=True)
    box('Spare block', (0, .372+h*1.5, 0), (W, h, L), 'oak_light', .006, tint=True)

def game_twister():
    """1.6 x 1.2 mat with coloured spots."""
    box('Twister mat', (0, .014, 0), (1.56, .028, 1.16), 'ivory', .008)
    for i in range(6):
        for j in range(4):
            disc('Twister spot', (-.65+i*.26, .032, -.39+j*.26), .125, .012,
                 'coral', axis='Y', tint=True)
    box('Spinner board', (.56, .035, .42), (.26, .03, .26), 'ivory', .008)
    disc('Spinner dial', (.56, .052, .42), .090, .012, 'chalk', axis='Y')
    o = rod('Spinner needle', (.56, .062, .42), (.65, .062, .42), .010, 'ember')
    rot(o, 0, 0, .7)

# ---------------------------------------------------------------- climbing
def game_obstacle_course():
    """2.6 x 2.0 course of hurdles and a crawl tunnel."""
    # Two full-width hurdles at the far and near ends, a crawl tunnel between.
    for z in (-.88, .88):
        for sx in (-1, 1):
            cyl('Hurdle upright', (sx*1.24, .31, z), .025, .62, 'plastic')
            box('Hurdle foot', (sx*1.24, .02, z), (.12, .04, .36), 'graphite', .008)
        for y in (.46, .62):
            rod('Hurdle bar', (-1.26, y, z), (1.26, y, z), .022, 'white', tint=True)
    for x in (-1.20, -.60, 0, .60, 1.20):
        half_torus('Tunnel rib', (x, .0, 0), .44, .022, 'steel', plane='S', keep='upper')
    for k in range(6):
        a = math.pi/12 + k*math.pi/6
        rod('Tunnel skin', (-1.20, math.sin(a)*.455, math.cos(a)*.455),
            (1.20, math.sin(a)*.455, math.cos(a)*.455), .014, 'net', tint=True)
    for sz in (-1, 1):
        rod('Tunnel base rail', (-1.20, .03, sz*.48), (1.20, .03, sz*.48), .020, 'steel')

def game_balance_beam():
    """1.8 x 0.4 low beam on feet."""
    box('Balance beam', (0, .29, 0), (1.76, .14, .18), 'oak', .014, tint=True)
    for x in (-.78, 0, .78):
        box('Beam foot', (x, .11, 0), (.16, .22, .38), 'walnut', .012)
        rod('Beam brace', (x, .22, -.18), (x, .29, -.02), .016, 'walnut')
        rod('Beam brace', (x, .22, .18), (x, .29, .02), .016, 'walnut')

def game_monkey_bars():
    """2.0 x 1.0 frame with rungs and a platform."""
    for sx in (-1, 1):
        for sz in (-1, 1):
            cyl('Frame upright', (sx*.90, .80, sz*.30), .040, 1.60, 'steel')
        rod('Frame top rail', (sx*.90, 1.60, -.30), (sx*.90, 1.60, .30), .035, 'steel')
    for i in range(6):
        rod('Climbing rung', (-.88, 1.60, -.25+i*.10), (.88, 1.60, -.25+i*.10), .030,
            'plastic', tint=True)
    box('Platform deck', (0, .60, -.50), (1.90, .06, .44), 'oak_light', .012, tint=True)
    for sx in (-1, 1):
        cyl('Platform leg', (sx*.82, .30, -.50), .035, .60, 'steel')
    for y in (.18, .38, .58):
        rod('Ladder rung', (-.30, y, -.16), (.30, y, -.16), .022, 'steel')
    for sx in (-1, 1):
        rod('Ladder rail', (sx*.30, .10, -.16), (sx*.30, .64, -.34), .022, 'steel')

def game_parallel_bars():
    """0.9 x 1.6 two low bars on posts."""
    for sx in (-1, 1):
        for sz in (-1, 1):
            cyl('Bar post', (sx*.36, .36, sz*.70), .035, .72, 'steel')
            box('Post foot', (sx*.36, .02, sz*.70), (.16, .04, .18), 'graphite', .008)
        rod('Parallel bar', (sx*.36, .74, -.79), (sx*.36, .74, .79), .035, 'oak_light', tint=True)
        rod('Base rail', (sx*.36, .04, -.70), (sx*.36, .04, .70), .028, 'steel')
    for sz in (-1, 1):
        rod('Cross brace', (-.36, .05, sz*.70), (.36, .05, sz*.70), .024, 'steel')

def game_pull_up_bar():
    """0.9 x 0.9 frame with a bar and grips."""
    for sx in (-1, 1):
        cyl('Frame upright', (sx*.40, .85, 0), .040, 1.70, 'steel')
        box('Frame foot', (sx*.36, .03, 0), (.18, .06, .44), 'graphite', .012)
        rod('Frame brace', (sx*.40, .34, 0), (sx*.30, .02, .42), .020, 'steel')
        rod('Frame brace', (sx*.40, .34, 0), (sx*.30, .02, -.42), .020, 'steel')
    rod('Pull-up bar', (-.42, 1.64, 0), (.42, 1.64, 0), .032, 'steel', tint=True)
    for x in (-.20, .20):
        cyl('Bar grip', (x, 1.64, 0), .045, .15, 'rubber', axis='X', tint=True)

def game_climbing_net():
    """1.6 x 0.8 climbing net on a frame."""
    for sx in (-1, 1):
        for sz in (-1, 1):
            cyl('Frame post', (sx*.74, .75, sz*.36), .035, 1.50, 'steel')
        rod('Frame top rail', (sx*.74, 1.50, -.36), (sx*.74, 1.50, .36), .030, 'steel')
        rod('Frame base rail', (sx*.74, .04, -.36), (sx*.74, .04, .36), .026, 'steel')
        rod('Frame brace', (sx*.74, .30, -.36), (sx*.74, .80, .36), .018, 'steel')
    for i in range(6):
        rod('Net rope', (-.66+i*.264, .06, 0), (-.66+i*.264, 1.46, 0), .007, 'hemp', tint=True)
    for k in range(4):
        rod('Net rope', (-.70, .20+k*.34, 0), (.70, .20+k*.34, 0), .007, 'hemp', tint=True)

def game_slackline():
    """2.2 x 0.5 line strung between two stakes."""
    for sx in (-1, 1):
        cyl('Slackline stake', (sx*.96, .26, 0), .030, .52, 'oak')
        box('Anchor plate', (sx*.96, .022, 0), (.30, .044, .50), 'graphite', .010)
        rod('Stake brace', (sx*.96, .10, -.20), (sx*.96, .32, 0), .014, 'steel')
        rod('Stake brace', (sx*.96, .10, .20), (sx*.96, .32, 0), .014, 'steel')
    rod('Slackline', (-.96, .44, 0), (.96, .44, 0), .012, 'plastic', tint=True)
    box('Line ratchet', (-.90, .36, 0), (.10, .07, .07), 'steel', .008, tint=True)
    for sx in (-1, 1):
        rod('Anchor peg', (sx*.96, .26, 0), (sx*1.10, .02, 0), .012, 'steel')

def game_stilts_race():
    """0.8 x 0.6 race blocks with ropes."""
    for i, (x, z) in enumerate([(-.26, -.18), (.26, .18)]):
        box('Race block', (x, .035, z), (.30, .07, .22), 'coral' if i else 'teal', .010,
            tint=True)
        for sx in (-1, 1):
            rod('Race rope', (x+sx*.09, .07, z), (x+sx*.06, .48, z), .008, 'hemp')
        rod('Race handle', (x-.09, .50, z), (x+.09, .50, z), .018, 'oak_light', tint=True)

def game_hook_a_duck():
    """1.0 x 0.7 fairground duck-hook stall."""
    for x in (-.44, .44):
        for z in (-.18, .18):
            box('Stall leg', (x, .28, z), (.07, .56, .07), 'walnut', .010)
    box('Duck trough floor', (0, .575, 0), (.98, .05, .48), 'teal', .010, tint=True)
    for z in (-.24, .24):
        box('Duck trough wall', (0, .65, z), (1.02, .16, .05), 'teal', .008, tint=True)
    for x in (-.49, .49):
        box('Duck trough wall', (x, .65, 0), (.05, .16, .48), 'teal', .008, tint=True)
    box('Trough water', (0, .610, 0), (.90, .03, .40), 'water', .004)
    for i in range(5):
        x = -.36 + i*.18
        z = ((i % 2)*.12)-.06
        ell('Fairground duck', (x, .690, z), (.085, .060, .10), 'mustard')
        ell('Duck head', (x, .760, z-.06), (.045, .045, .045), 'mustard')
        box('Duck beak', (x, .750, z-.11), (.035, .022, .040), 'coral', .004)
    for x in (-.48, .48):
        rod('Hook rail post', (x, .73, -.20), (x, .96, -.20), .022, 'steel')
    rod('Hook rail', (-.48, .96, -.20), (.48, .96, -.20), .026, 'steel')
    for i in range(4):
        half_torus('Hook', (-.30+i*.20, .92, -.20), .042, .009, 'steel', plane='V', keep='upper')
    box('Prize shelf', (0, .30, .36), (.90, .04, .18), 'walnut', .008)
    for sx in (-1, 1):
        rod('Shelf brace', (sx*.40, .27, .32), (sx*.40, .10, .24), .014, 'steel')
    box('Prize box', (-.26, .40, .36), (.11, .16, .10), 'coral', .008)
    ell('Prize ball', (0, .39, .36), (.055, .055, .055), 'rose')
    cyl('Prize cup', (.26, .39, .36), .052, .14, 'gold', top=.058)

# ---------------------------------------------------------------- play
def game_sandpit_toys():
    """0.7 x 0.7 bucket, spade, sieve and moulds."""
    cyl('Sand bucket', (-.14, .11, -.14), .150, .22, 'mustard', top=.115, tint=True)
    half_torus('Bucket handle', (-.14, .22, -.14), .155, .011, 'steel', plane='V', keep='upper')
    rod('Spade shaft', (-.02, .020, .16), (.24, .020, .30), .014, 'oak')
    ell('Spade blade', (.28, .028, .33), (.055, .028, .075), 'plastic')
    cyl('Sand sieve', (.25, .028, -.20), .105, .05, 'plastic', top=.105)
    torus('Sieve rim', (.25, .050, -.20), .105, .010, 'plastic', plane='H')
    cyl('Sand mould', (-.30, .028, .16), .060, .055, 'teal', top=.060)
    box('Sand mould', (-.16, .032, .28), (.09, .064, .09), 'coral', .008)
    ell('Sand mould', (-.30, .038, -.02), (.055, .038, .055), 'plum')
    ell('Sand ball', (.02, .045, .06), (.045, .045, .045), 'rose')

def game_water_table():
    """1.0 x 0.6 raised tray with a channel, wheel and boats."""
    for x in (-.44, .44):
        for z in (-.22, .22):
            box('Table leg', (x, .28, z), (.06, .56, .06), 'oak', .010)
    box('Tray floor', (0, .575, 0), (.96, .05, .56), 'teal', .012, tint=True)
    for z in (-.26, .26):
        box('Tray wall', (0, .655, z), (1.00, .13, .04), 'teal', .008, tint=True)
    for x in (-.48, .48):
        box('Tray wall', (x, .655, 0), (.04, .13, .56), 'teal', .008, tint=True)
    box('Water', (0, .605, 0), (.90, .03, .46), 'water', .004)
    box('Channel chute', (.30, .60, 0), (.30, .04, .34), 'teal', .008, tint=True)
    for sx in (-1, 1):
        cyl('Wheel axle post', (sx*.34, .64, 0), .018, .10, 'oak')
    cyl('Water wheel', (0, .78, 0), .120, .05, 'oak', axis='X')
    for i in range(6):
        a = i*math.pi/3
        o = box('Wheel paddle', (0, .78+math.sin(a)*.070, math.cos(a)*.070),
                (.05, .09, .04), 'oak', .004)
        rot(o, a, 0, 0)
    rod('Wheel axle', (-.36, .78, 0), (.36, .78, 0), .018, 'steel')
    for i, (x, z) in enumerate([(-.20, .16), (.16, -.14)]):
        box('Toy boat hull', (x, .68, z), (.16, .05, .09), ['coral', 'mustard'][i], .010)
        rod('Toy boat mast', (x, .80, z), (x, .92, z), .008, 'oak')
        box('Toy boat sail', (x+.05, .86, z), (.10, .10, .008), 'white', 0)

def game_mud_kitchen():
    """1.1 x 0.7 rustic counter with a hob, pots and a sink."""
    for x in (-.48, .48):
        for z in (-.26, .26):
            box('Kitchen leg', (x, .30, z), (.07, .60, .07), 'walnut', .010)
    box('Counter top', (0, .63, 0), (1.10, .07, .66), 'oak', .012, tint=True)
    box('Back splash', (0, .74, -.31), (1.10, .18, .04), 'walnut', .008)
    box('Lower shelf', (0, .22, 0), (1.04, .05, .30), 'walnut', .008)
    for x in (-.34, -.14):
        disc('Hob ring', (x, .672, -.12), .075, .014, 'graphite', axis='Y')
    cyl('Cooking pot', (-.34, .74, .16), .085, .13, 'steel', top=.085)
    rod('Pot handle', (-.26, .76, .16), (-.20, .76, .16), .012, 'graphite')
    cyl('Frying pan', (-.04, .70, .20), .105, .05, 'graphite')
    rod('Pan handle', (.04, .70, .26), (.20, .70, .32), .014, 'graphite')
    box('Sink rim', (.34, .645, .02), (.30, .06, .28), 'graphite', .008)
    box('Sink bowl', (.34, .620, .02), (.24, .03, .22), 'steel', .004)
    rod('Sink tap', (.34, .72, -.10), (.34, .84, -.10), .016, 'steel')
    rod('Sink spout', (.34, .84, -.10), (.34, .84, .04), .014, 'steel')
    rod('Spoon', (-.44, .70, .22), (-.30, .70, .32), .010, 'oak_light')
    ell('Spoon bowl', (-.28, .70, .33), (.035, .014, .045), 'oak_light')

def game_bubble_station():
    """0.7 x 0.7 bubble machine with a wand tray."""
    for x in (-.24, .24):
        for z in (-.13, .13):
            box('Stand leg', (x, .26, z), (.05, .52, .05), 'oak', .008)
    box('Stand top', (0, .53, 0), (.62, .05, .32), 'oak_light', .010)
    box('Machine case', (-.16, .68, 0), (.28, .26, .24), 'plastic', .012, tint=True)
    cyl('Machine nozzle', (-.16, .70, .16), .045, .06, 'graphite', axis='Z')
    torus('Bubble ring', (-.16, .70, .25), .090, .012, 'plastic', plane='V')
    ell('Bubble', (-.16, .74, .40), (.11, .11, .11), 'water')
    box('Wand tray', (.20, .565, -.02), (.24, .03, .22), 'teal', .008)
    for i in range(3):
        rod('Wand handle', (.12+i*.08, .585, -.10), (.12+i*.08, .585, .02), .008, 'oak')
        torus('Wand loop', (.12+i*.08, .60, .04), .038, .007, 'plastic', plane='H')
    cyl('Bubble mix', (.24, .60, .13), .050, .16, 'water')

def game_kite():
    """0.6 x 0.6 folded kite with a spool of line."""
    o = box('Kite sail', (-.05, .012, .05), (.34, .012, .34), 'coral', .006, tint=True)
    rot(o, 0, 0, math.pi/4)
    rod('Kite spine', (-.29, .022, .05), (.19, .022, .05), .007, 'graphite')
    rod('Kite spar', (-.05, .022, .29), (-.05, .022, -.19), .007, 'graphite')
    # The tails are folded back alongside the sail rather than trailing free.
    for i in range(4):
        o = box('Kite tail', (-.20+i*.10, .014, -.26), (.09, .010, .06), 'mustard', 0)
        rot(o, 0, 0, .18)
    rod('Kite line', (-.02, .030, -.16), (.20, .060, -.22), .004, 'net')
    cyl('Line spool', (.20, .105, -.22), .062, .08, 'oak', axis='X')
    for sx in (-1, 1):
        disc('Spool flange', (.20+sx*.045, .105, -.22), .088, .013, 'oak_light', axis='X')
    rod('Spool handle', (.20, .105, -.22), (.20, .225, -.22), .012, 'steel')

def game_skate_ramp():
    """1.6 x 1.2 quarter pipe with coping."""
    # A quarter pipe swept about Godot X: the deck is flat at y = 0, the arc
    # centre sits at (y 0, z .45) and the lip is a vertical face at y = 1.
    R, th = 1.0, .048
    for k in range(7):
        a = math.radians(7 + k*13.4)
        o = box('Ramp riding surface', (0, R*math.sin(a), .45 - R*math.cos(a)),
                (1.50, .30, th), 'oak_light', .006, tint=True)
        rot(o, x=a)
    box('Ramp deck', (0, .02, -.58), (1.50, .06, .26), 'oak_light', .006, tint=True)
    for sx in (-1, 1):
        box('Ramp side wall', (sx*.77, .50, -.10), (.06, 1.00, .90), 'graphite', .010)
        box('Ramp base rail', (sx*.77, .03, -.58), (.08, .06, .26), 'graphite', .008)
        box('Ramp back panel', (sx*.77, .50, .40), (.06, 1.00, .06), 'graphite', .008)
    rod('Ramp coping', (-.80, 1.00, .42), (.80, 1.00, .42), .028, 'steel')

def game_roller_skates():
    """0.6 x 0.5 pair of quad skates."""
    for x, z, yaw in [(-.17, -.08, 0), (.17, .12, .55)]:
        for y, s in [(.27, (.11, .26, .13)), (.42, (.11, .10, .13))]:
            o = box('Skate boot', (x, y, z), s, 'ivory', .020, tint=True)
            rot(o, 0, 0, yaw)
        o = box('Skate sole', (x, .125, z), (.12, .04, .27), 'graphite', .010)
        rot(o, 0, 0, yaw)
        o = box('Skate truck', (x, .085, z), (.14, .05, .16), 'steel', .008)
        rot(o, 0, 0, yaw)
        for sz in (-.10, .10):
            for sx in (-.055, .055):
                o = disc('Skate wheel', (x+sx, .035, z+sz), .034, .028, 'rubber', axis='X')
                rot(o, 0, 0, yaw)
        o = ell('Skate toe stop', (x, .075, z+.17), (.033, .033, .028), 'rubber')
        rot(o, 0, 0, yaw)
        for k in range(2):
            o = rod('Skate lace', (x-.05, .44-k*.05, z-.03), (x+.05, .44-k*.05, z-.03),
                    .005, 'cream')
            rot(o, 0, 0, yaw)

def game_space_hopper():
    """0.6 x 0.6 hopper ball with a handle."""
    ell('Hopper ball', (0, .28, 0), (.28, .28, .28), 'rose')
    torus('Hopper band', (0, .28, 0), .268, .036, 'plastic', plane='H', tint=True)
    torus('Hopper seat ring', (0, .04, 0), .115, .030, 'rubber', plane='H')
    half_torus('Hopper handle', (0, .44, 0), .22, .022, 'plastic', plane='V', keep='upper',
               tint=True)
    rod('Hopper grip', (-.10, .64, 0), (.10, .64, 0), .025, 'rubber', tint=True)

def game_pogo_stick():
    """0.5 x 0.5 pogo stick with a footplate."""
    box('Pogo floor base', (0, .018, 0), (.48, .036, .48), 'rubber', .010)
    cyl('Pogo socket', (0, .05, 0), .070, .07, 'steel')
    cyl('Pogo foot', (0, .10, 0), .045, .12, 'rubber', top=.036)
    for k in range(5):
        torus('Pogo spring', (0, .21+k*.062, 0), .055, .018, 'steel', plane='H')
    cyl('Pogo spring cap', (0, .18, 0), .062, .03, 'steel')
    cyl('Pogo shaft', (0, .72, 0), .028, .48, 'plastic', tint=True)
    for sx in (-1, 1):
        box('Pogo footplate', (sx*.12, .50, 0), (.14, .022, .20), 'plastic', .008, tint=True)
        rod('Footplate brace', (sx*.12, .48, 0), (0, .44, 0), .014, 'steel')
    rod('Pogo handlebar', (-.24, .99, 0), (.24, .99, 0), .022, 'steel')
    for sx in (-1, 1):
        cyl('Pogo grip', (sx*.18, .99, 0), .035, .13, 'rubber', axis='X')

def game_hula_hoop():
    """0.8 x 0.8 stack of two hoops on a stand."""
    box('Hoop stand base', (0, .025, .10), (.30, .05, .30), 'graphite', .012)
    cyl('Hoops stand post', (0, .36, .10), .028, .72, 'graphite')
    for y in (.37, .64):
        o = torus('Hula hoop', (0, y, .04), .37, .028, 'plastic', plane='V', tint=True)
        rot(o, math.radians(14), 0, 0)
        rod('Hoop peg', (0, y, .10), (0, y-.02, .04), .012, 'graphite')

def game_stilts():
    """0.6 x 0.6 pair of wooden stilts."""
    for sx in (-1, 1):
        z = sx*.16
        box('Stilt pole', (sx*.26, .56, z), (.070, 1.12, .070), 'oak', .010, tint=True)
        box('Stilt footplate', (sx*.26, .44, z+.10), (.14, .035, .30), 'oak_light', .008,
            tint=True)
        rod('Footplate brace', (sx*.26, .44, z+.23), (sx*.26, .62, z+.05), .012, 'steel')
        cyl('Stilt rubber foot', (sx*.26, .02, z), .048, .04, 'rubber')

def game_diy_den():
    """1.4 x 1.4 sheet-and-pole den."""
    for sz in (-1, 1):
        for sx in (-1, 1):
            rod('Den pole', (sx*.58, 0, sz*.56), (0, 1.00, sz*.52), .022, 'oak')
            rod('Den peg', (sx*.60, .10, sz*.58), (sx*.66, .02, sz*.64), .014, 'steel')
    rod('Den ridge pole', (0, 1.00, -.56), (0, 1.00, .56), .022, 'oak')
    s = math.atan2(1.00, .62)
    for sx in (-1, 1):
        o = box('Den sheet', (sx*.29, .50, 0), (1.10, .028, 1.16), 'linen', .008, tint=True)
        rot(o, y=s if sx > 0 else -s)
    o = box('Den sheet', (0, .58, -.54), (1.16, .92, .030), 'linen', .008, tint=True)
    rot(o, x=math.radians(-34))
    box('Den groundsheet', (0, .010, 0), (1.24, .02, 1.24), 'felt', .004)

def game_playhouse():
    """1.4 x 1.4 playhouse with a door, window and pitched roof."""
    box('Playhouse floor', (0, .04, 0), (1.36, .08, 1.36), 'oak_light', .010)
    box('Playhouse back wall', (0, .50, -.66), (1.36, .85, .07), 'cream', .010)
    for sx in (-1, 1):
        box('Playhouse side wall', (sx*.66, .50, 0), (.07, .85, 1.36), 'cream', .010)
        box('Window frame', (sx*.70, .52, .06), (.04, .42, .42), 'teal', .006)
        box('Window glass', (sx*.715, .52, .06), (.02, .32, .32), 'sky', .004)
        box('Playhouse front wall', (sx*.475, .50, .66), (.37, .85, .07), 'cream', .010)
    box('Door lintel', (0, .86, .66), (.58, .26, .07), 'cream', .010)
    ey, ry, hw = .85, 1.30, .70
    s = math.atan2(ry-ey, hw)
    for sx in (-1, 1):
        ln = math.hypot(hw, ry-ey)
        o = box('Playhouse roof', (sx*hw/2, (ry+ey)/2, 0), (ln, .055, 1.50), 'brick', .008)
        rot(o, 0, s if sx > 0 else -s, 0)
    rod('Roof ridge', (0, ry+.02, -.77), (0, ry+.02, .77), .022, 'brick')
    # Bargeboards follow the roof pitch at each gable end, so they trim the roof
    # instead of standing proud of it.
    for sz in (-1, 1):
        for sx in (-1, 1):
            o = box('Roof bargeboard', (sx*hw/2, (ry+ey)/2 -.02, sz*.72),
                    (ln-.04, .07, .05), 'brick', .006)
            rot(o, y=s if sx > 0 else -s)
    box('Playhouse door', (0, .44, .665), (.52, .78, .05), 'oak', .008, tint=True)
    ell('Door knob', (.20, .42, .70), (.022, .022, .022), 'brass')

def game_wendy_house():
    """1.2 x 1.2 open-fronted play hut with a counter and bench."""
    box('Hut floor', (0, .035, 0), (1.20, .07, 1.20), 'oak_light', .010)
    box('Hut back wall', (0, .50, -.58), (1.20, .95, .07), 'oak', .010)
    for sx in (-1, 1):
        box('Hut side wall', (sx*.58, .50, 0), (.07, .95, 1.20), 'oak', .010)
        box('Hut window', (sx*.62, .62, .10), (.04, .38, .38), 'teal', .006)
        box('Hut glass', (sx*.635, .62, .10), (.02, .28, .28), 'sky', .004)
    box('Hut roof', (0, 1.06, 0), (1.20, .08, 1.20), 'walnut', .010)
    box('Hut fascia', (0, 1.10, .60), (1.20, .20, .05), 'walnut', .008)
    box('Hut counter top', (0, .64, .44), (1.08, .07, .30), 'oak_light', .010)
    box('Hut counter front', (0, .46, .58), (1.08, .30, .05), 'teal', .008, tint=True)
    for sx in (-1, 1):
        cyl('Counter leg', (sx*.46, .32, .44), .030, .62, 'oak')
    box('Hut sign', (0, .88, .60), (.44, .22, .04), 'cream', .008)
    box('Hut bench seat', (0, .42, -.28), (.80, .06, .30), 'oak_light', .010)
    for sx in (-1, 1):
        box('Bench leg', (sx*.32, .21, -.28), (.08, .42, .26), 'oak', .008)
    box('Hut bench back', (0, .60, -.42), (.80, .34, .06), 'oak', .008)

def game_parachute():
    """2.0 x 2.0 folded play parachute with handles."""
    for i, s in enumerate([1.96, 1.76, 1.56, 1.36, 1.16, .96]):
        o = box('Folded chute', (0, .024+i*.046, 0), (s, .046, s),
                'linen' if i % 2 else 'net', .012, tint=i < 2)
        rot(o, 0, 0, (i*.12 if i % 2 else -.06))
    for i in range(8):
        a = i*math.pi/4
        torus('Chute handle', (math.sin(a)*.93, .022, math.cos(a)*.93), .07, .013,
              'mustard', plane='H')
    box('Chute strap', (0, .30, 0), (.30, .02, .30), 'mustard', .004)

def game_beanbag_chairs():
    """0.9 x 0.9 stack of two beanbag seats."""
    ell('Beanbag base', (0, .30, 0), (.440, .300, .440), 'linen')
    ell('Beanbag seat', (.05, .60, .04), (.420, .300, .420), 'teal', tint=True)
    disc('Beanbag seam', (0, .62, 0), .30, .02, 'linen', axis='Y')
    half_torus('Beanbag tab', (.44, .54, 0), .07, .014, 'teal', plane='S', keep='upper',
               tint=True)
    ell('Beanbag top', (.05, .82, .04), (.30, .10, .30), 'teal', tint=True)

catalog = {
    'game_trampoline': game_trampoline,
    'game_hopscotch': game_hopscotch,
    'game_hoop': game_hoop,
    'game_skipping_rope': game_skipping_rope,
    'game_dartboard': game_dartboard,
    'game_croquet': game_croquet,
    'game_ring_toss': game_ring_toss,
    'game_mini_golf': game_mini_golf,
    'game_bowling': game_bowling,
    'game_table_tennis': game_table_tennis,
    'game_badminton': game_badminton,
    'game_football_goal': game_football_goal,
    'game_basketball': game_basketball,
    'game_bean_bags': game_bean_bags,
    'game_horseshoes': game_horseshoes,
    'game_boules': game_boules,
    'game_skittles': game_skittles,
    'game_quotis': game_quotis,
    'game_shuffleboard': game_shuffleboard,
    'game_connect_four': game_connect_four,
    'game_giant_chess': game_giant_chess,
    'game_checkers': game_checkers,
    'game_dominoes': game_dominoes,
    'game_jenga': game_jenga,
    'game_twister': game_twister,
    'game_obstacle_course': game_obstacle_course,
    'game_balance_beam': game_balance_beam,
    'game_monkey_bars': game_monkey_bars,
    'game_parallel_bars': game_parallel_bars,
    'game_pull_up_bar': game_pull_up_bar,
    'game_sandpit_toys': game_sandpit_toys,
    'game_water_table': game_water_table,
    'game_mud_kitchen': game_mud_kitchen,
    'game_bubble_station': game_bubble_station,
    'game_kite': game_kite,
    'game_skate_ramp': game_skate_ramp,
    'game_roller_skates': game_roller_skates,
    'game_space_hopper': game_space_hopper,
    'game_pogo_stick': game_pogo_stick,
    'game_hula_hoop': game_hula_hoop,
    'game_stilts': game_stilts,
    'game_diy_den': game_diy_den,
    'game_playhouse': game_playhouse,
    'game_wendy_house': game_wendy_house,
    'game_climbing_net': game_climbing_net,
    'game_slackline': game_slackline,
    'game_stilts_race': game_stilts_race,
    'game_parachute': game_parachute,
    'game_beanbag_chairs': game_beanbag_chairs,
    'game_hook_a_duck': game_hook_a_duck,
}

parser = argparse.ArgumentParser()
parser.add_argument('--only', choices=tuple(catalog))
parser.add_argument('--source-out', default='art/garden_games/garden_games.blend')
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if args.only:
    catalog = {args.only: catalog[args.only]}

# Refuse before writing anything, so a second run cannot clobber reviewed art.
existing = [MODELS/(k+'.glb') for k in catalog if (MODELS/(k+'.glb')).exists()]
if existing:
    raise RuntimeError('Refusing to replace %d existing model file(s); first is %s'
                       % (len(existing), existing[0]))

ART.mkdir(parents=True, exist_ok=True)

def build(name, fn):
    global active
    active = []
    TINT.clear()
    fn()
    ground_contact(name)
    if TINT:
        join_tint()
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for o in active:
        if o.parent is None:
            o.parent = root
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for o in active:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(MODELS/(name+'.glb')), export_format='GLB',
                              use_selection=True, export_apply=True, export_animations=False)
    return root

for idx, (name, fn) in enumerate(catalog.items()):
    root = build(name, fn)
    root.location = ((idx % 6)*4, (idx//6)*4, 0)

bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_'+GROUP+'_COMPLETE', len(catalog))
