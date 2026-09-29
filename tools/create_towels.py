"""Original JustLife beach towels and garden towel rack.

Run:  blender -b --factory-startup -t 2 --python-exit-code 2 --python tools/create_towels.py

Coordinates are Godot metres: x right, y up, z toward the front of the item. The
helpers mirror tools/create_outdoor_water.py so the pieces match the shipped
artwork; everything is built from primitives and small generated cloth grids.

Authors four models, each exported as its own GLB and never over an existing file:

  beach_towel_a.glb  a spread flat towel with a stripe band and fringe
  beach_towel_b.glb  a neatly folded stack of four towels
  beach_towel_c.glb  a rolled towel tied with two bands
  towel_rack.glb     a free-standing weathered-wood garden rack

Every model carries exactly one mesh named `Tint`, the surface the player's colour
choice repaints. For a towel that is the main cloth; stripes, fringe and ties are
separate cream/white meshes. For the rack it is the painted post caps, rail
collars and shelf trim (visible even with towels hung), while the wood keeps its
own materials.

The rack also carries two empties, `TowelRail_L` (-x) and `TowelRail_R` (+x), on
the axis of the top rail at its two towel-bearing ends. The game draws hanging
towels itself between those two points, so no towel is modelled on the rack.

Footprints (metres, authored size; the catalogue scales a rack uniformly by
x1 / x1.45 / x2 about the origin):

  towels  <= 0.80 (x) by 0.45 (z), <= 0.20 tall, origin at the footprint centre
  rack    <= 0.60 (x) by 0.28 (z), <= 0.95 tall, origin at the floor centre
"""
import bpy, bmesh, math, pathlib, argparse, sys, random
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODELS = ROOT/'assets/models'
ART = ROOT/'art/towels'
GROUP = 'TOWELS'

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0

M = {}
active = []


def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb = [int(hexcolor[i:i+2], 16)/255 for i in (0, 2, 4)]
    linear = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*linear, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = m.diffuse_color
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    if emit:
        p.inputs['Emission Color'].default_value = m.diffuse_color
        p.inputs['Emission Strength'].default_value = emit
    M[name] = m
    return m


for n, h, r in [('cloth', '8FBFC4', .92),          # default Tint colour of the towels
                ('cloth_rack', '4E8F86', .55),     # default Tint colour of the rack
                ('cream', 'F1E9D6', .90), ('white', 'FBF7EC', .90),
                ('stripe', 'E6D8B8', .90),
                ('weathered', '9B8A72', .88),      # sun-bleached grey-brown timber
                ('weathered_dark', '7B6B58', .90), # end grain, braces and slats in shade
                ('graphite', '4A4F55', .55), ('steel', 'B9BEC2', .35)]:
    mat(n, h, r)
M['steel'].node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value = .45


def xyz(p):
    return (p[0], -p[2], p[1])


def finish(o, n, m):
    o.name = n
    o.data.materials.append(M[m])
    active.append(o)
    return o


def select_only(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def apply_mods(o):
    if not o.modifiers:
        return o
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o],
                                   selected_editable_objects=[o]):
        for md in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=md.name)
            except Exception:
                o.modifiers.remove(md)
    return o


def weld(name, objs, matname=None):
    """Join primitive parts into one mesh object (needed for Tint and the wood groups)."""
    objs = [o for o in objs if o.name in bpy.data.objects]
    if not objs:
        return None
    for o in objs:
        apply_mods(o)
    if len(objs) > 1:
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
    o = bpy.context.object if len(objs) > 1 else objs[0]
    o.name = name
    if matname:
        o.data.materials.clear()
        o.data.materials.append(M[matname])
        for poly in o.data.polygons:
            poly.material_index = 0
    for x in objs:
        if x in active:
            active.remove(x)
    active.append(o)
    return o


def yaw(o, deg):
    o.rotation_euler[2] = math.radians(deg)
    return o


def box(n, p, s, m, bevel=.008, seg=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o = bpy.context.object
    o.dimensions = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b = o.modifiers.new('Soft crafted edges', 'BEVEL')
        b.width = bevel
        b.segments = seg
        b.limit_method = 'ANGLE'
    return finish(o, n, m)


def ell(n, p, s, m, seg=20, ring=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, location=xyz(p))
    o = bpy.context.object
    o.scale = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for f in o.data.polygons:
        f.use_smooth = True
    return finish(o, n, m)


def cyl(n, p, r, h, m, top=None, axis='Y', bevel=.008, verts=24):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r,
                                    radius2=r if top is None else top,
                                    depth=h, location=xyz(p))
    o = bpy.context.object
    if axis == 'X':
        o.rotation_euler = (0, math.pi/2, 0)
    elif axis == 'Z':
        o.rotation_euler = (math.pi/2, 0, 0)
    if bevel:
        b = o.modifiers.new('Rounded rims', 'BEVEL')
        b.width = bevel
        b.segments = 2
    for f in o.data.polygons:
        f.use_smooth = True
    return finish(o, n, m)


def rod(n, a, b, r, m, verts=12):
    av, bv = Vector(xyz(a)), Vector(xyz(b))
    d = bv - av
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length,
                                        location=(av+bv)/2)
    o = bpy.context.object
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return finish(o, n, m)


def mesh_object(name, bm, m, smooth=True):
    """Turn a finished bmesh (already in Blender coordinates) into a tracked object."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    for f in me.polygons:
        f.use_smooth = smooth
    return finish(o, name, m)


# ---------------------------------------------------------------- Cloth
# One height field shared by the towel, its stripes and its fringe so the bands
# lie on the cloth instead of floating over it.
HALF_X, HALF_Z = .36, .215          # cloth body; the fringe adds .04 at each x end
BASE = .011                          # cloth thickness on the floor


def cloth_h(x, z):
    """Gentle undulation of a towel spread out on the ground (metres above the floor)."""
    u, v = x/HALF_X, z/HALF_Z
    wave = (.0080*math.sin(2*math.pi*(x+.05)/.44+.6)*math.cos(math.pi*z/.50+.3)
            + .0050*math.sin(2*math.pi*(z-.35*x)/.27+1.1)
            + .0032*math.cos(2*math.pi*x/.17-.4)*math.cos(math.pi*z/.32))
    lift = .0075*max(0.0, abs(u)-.70)**2/.09*max(0.0, abs(v)-.55)/.45   # corners curl up a little
    return BASE+.0058+wave+lift


def cloth_patch(name, x0, x1, z0, z1, lift, m, thick=.0014, nx=None, nz=None):
    """A thin strip lying on the cloth surface over the rectangle x0..x1, z0..z1."""
    nx = nx or max(2, int((x1-x0)/.030))
    nz = nz or max(2, int((z1-z0)/.030))
    bm = bmesh.new()
    top = [[bm.verts.new(xyz((x0+(x1-x0)*i/nx, cloth_h(x0+(x1-x0)*i/nx, z0+(z1-z0)*j/nz)+lift,
                              z0+(z1-z0)*j/nz))) for j in range(nz+1)] for i in range(nx+1)]
    bot = [[bm.verts.new((v.co.x, v.co.y, v.co.z-thick)) for v in row] for row in top]
    for i in range(nx):
        for j in range(nz):
            bm.faces.new((top[i][j], top[i][j+1], top[i+1][j+1], top[i+1][j]))
            bm.faces.new((bot[i][j], bot[i+1][j], bot[i+1][j+1], bot[i][j+1]))
    for i in range(nx):
        bm.faces.new((top[i][0], top[i+1][0], bot[i+1][0], bot[i][0]))
        bm.faces.new((top[i][nz], bot[i][nz], bot[i+1][nz], top[i+1][nz]))
    for j in range(nz):
        bm.faces.new((top[0][j], bot[0][j], bot[0][j+1], top[0][j+1]))
        bm.faces.new((top[nx][j], top[nx][j+1], bot[nx][j+1], bot[nx][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, m)


def cloth_slab(name, m):
    """The spread towel body: undulating top, flat base on the floor, rounded rim."""
    nx, nz = 30, 18
    bm = bmesh.new()
    top = [[bm.verts.new(xyz((-HALF_X+2*HALF_X*i/nx, cloth_h(-HALF_X+2*HALF_X*i/nx, -HALF_Z+2*HALF_Z*j/nz),
                              -HALF_Z+2*HALF_Z*j/nz))) for j in range(nz+1)] for i in range(nx+1)]
    bot = [[bm.verts.new(xyz((-HALF_X+2*HALF_X*i/nx, 0.0, -HALF_Z+2*HALF_Z*j/nz)))
            for j in range(nz+1)] for i in range(nx+1)]
    for i in range(nx):
        for j in range(nz):
            bm.faces.new((top[i][j], top[i][j+1], top[i+1][j+1], top[i+1][j]))
            bm.faces.new((bot[i][j], bot[i+1][j], bot[i+1][j+1], bot[i][j+1]))
    for i in range(nx):
        bm.faces.new((top[i][0], top[i+1][0], bot[i+1][0], bot[i][0]))
        bm.faces.new((top[i][nz], bot[i][nz], bot[i+1][nz], top[i+1][nz]))
    for j in range(nz):
        bm.faces.new((top[0][j], bot[0][j], bot[0][j+1], top[0][j+1]))
        bm.faces.new((top[nx][j], top[nx][j+1], bot[nx][j+1], bot[nx][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_object(name, bm, m)
    b = o.modifiers.new('Soft towel rim', 'BEVEL')
    b.width = .0045
    b.segments = 2
    b.limit_method = 'ANGLE'
    b.angle_limit = math.radians(50)
    return o


def tassel(n, x, z, direction, length, rng, m):
    """One fringe tuft lying flat on the floor, slightly fanned and drooped."""
    a = math.radians(rng.uniform(-14, 14))
    ex = x+direction*length*math.cos(a)
    ez = z+length*math.sin(a)
    return rod(n, (x, .0050, z), (ex, .0046, ez), rng.uniform(.0030, .0040), m, verts=6)


def towel_flat():
    """Spread towel: rippled cloth, a stripe band with pinstripes at each end, fringe."""
    body = cloth_slab('Cloth', 'cloth')
    bands, pins = [], []
    for s in (-1, 1):
        a, b = s*.215, s*.290
        bands.append(cloth_patch('Stripe band', min(a, b), max(a, b), -HALF_Z, HALF_Z, .0018,
                                 'stripe', nx=6, nz=30))
        for x in (.190, .316):
            pins.append(cloth_patch('Stripe pin', s*x-.006, s*x+.006, -HALF_Z, HALF_Z, .0017,
                                    'cream', nx=2, nz=30))
    weld('Stripe bands', bands, 'stripe')
    weld('Pinstripes', pins, 'cream')
    rng = random.Random(41)
    tufts = []
    for s in (-1, 1):
        for i in range(17):
            z = -.200+i*.025
            tufts.append(tassel('Fringe tuft', s*(HALF_X-.004), z, s, .040+rng.uniform(-.006, .004), rng, 'white'))
    weld('Fringe', tufts, 'white')
    weld('Tint', [body], 'cloth')


def turn(objs, cx, cz, deg):
    """Yaw a cluster about the vertical axis through (cx, cz) in Godot coordinates."""
    if not deg:
        return
    c, s_ = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    for o in objs:
        px_, py_ = o.location.x-cx, o.location.y+cz
        o.location.x = cx+px_*c-py_*s_
        o.location.y = -cz+px_*s_+py_*c
        o.rotation_euler[2] += math.radians(deg)


def folded_layer(name, cx, cz, w, d, h, y0, m, bevel=.014):
    return box(name, (cx, y0+h/2, cz), (w, h, d), m, bevel, 3)


def towel_stack():
    """Four towels folded in thirds and stacked; the fold edge faces the front."""
    cloth, bands, hem = [], [], []
    layers = [(.62, .41, .046, 0.0, .000, .000),
              (.60, .40, .043, 1.3, .006, -.004),
              (.61, .405, .045, -1.1, -.005, .002),
              (.58, .39, .042, 0.8, .004, .003)]
    y = 0.0
    for i, (w, d, h, rot, dx, dz) in enumerate(layers):
        layer = [folded_layer('Folded towel', dx, dz, w, d, h, y, 'cloth')]
        # Stripe band wrapped round the folded front edge, and a hem seam on the fold.
        band = box('Stack stripe', (dx, y+h*.52, dz+d/2+.0006), (w-.030, h*.30, .0032), 'stripe', .0008, 2)
        seam = box('Stack seam', (dx, y+h*.14, dz+d/2+.0004), (w-.026, .0028, .0028), 'cream', 0, 1)
        turn(layer+[band, seam], dx, dz, rot)
        cloth += layer
        bands.append(band)
        hem.append(seam)
        y += h*.97
    top_y = y
    # Two pinstripes across the top towel, matching the flat towel's pattern.
    tw, td, dx4, dz4 = layers[-1][0], layers[-1][1], layers[-1][4], layers[-1][5]
    for xo in (.172, .214):
        stripe = box('Stack top pin', (dx4+xo, top_y+.0004, dz4), (.010, .0030, td-.030), 'cream', .0008, 1)
        turn([stripe], dx4, dz4, layers[-1][3])
        bands.append(stripe)
    # A folded-over flap of the top towel with fringe tufts at the right-hand end.
    rng = random.Random(7)
    tufts = []
    for i in range(9):
        z = -.140+i*.0335
        tufts.append(rod('Stack fringe', (.286, top_y*.90, z), (.286+.030+rng.uniform(-.003, .003),
                                                                top_y*.90-.010, z+rng.uniform(-.008, .008)),
                         .0036, 'white', verts=6))
    weld('Stack stripes', bands, 'stripe')
    weld('Stack seams', hem, 'cream')
    weld('Stack fringe', tufts, 'white')
    weld('Tint', cloth, 'cloth')


def spiral_prism(name, x0, x1, rad0, pitch, turns, thick, off_out, off_in, m, steps=96, lift=0.0):
    """A strip wound as an Archimedean spiral in the y/z plane, extruded from x0 to x1.

    off_out / off_in trim the strip's outer / inner edge inward from the full
    thickness, so a thin cream stripe can follow the middle of the wound cloth.
    """
    outer, inner = [], []
    for i in range(steps+1):
        th = turns*2*math.pi*i/steps
        r = rad0+pitch*th/(2*math.pi)
        outer.append((r-off_out, th))
        inner.append((max(r-thick+off_in, .002), th))
    pts = [(r*math.cos(th), r*math.sin(th)) for r, th in outer]
    pts += [(r*math.cos(th), r*math.sin(th)) for r, th in reversed(inner)]
    bm = bmesh.new()
    n = len(pts)
    a = [bm.verts.new((x0, p[1], p[0]+lift)) for p in pts]
    b = [bm.verts.new((x1, p[1], p[0]+lift)) for p in pts]
    for i in range(n):
        j = (i+1) % n
        bm.faces.new((a[i], b[i], b[j], a[j]))
    caps = [bm.faces.new(list(reversed(ring)) if flip else ring) for ring, flip in ((a, True), (b, False))]
    bm.normal_update()              # the fill below needs real cap normals, or it fills the gaps too
    bmesh.ops.triangulate(bm, faces=caps, quad_method='BEAUTY', ngon_method='EAR_CLIP')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, m)


def towel_rolled():
    """A towel rolled along x: a real spiral end, a cream stripe ring on each end, two ties."""
    rad0, pitch, turns, thick = .030, .0195, 3.0, .0165
    length = .56
    half = length/2
    rr_out = rad0+pitch*turns
    ry = rr_out+.0075                # the roll rests on its two tie bands, so the ties touch the floor
    roll = spiral_prism('Roll', -half, half, rad0, pitch, turns, thick, 0, 0, 'cloth', lift=ry)
    sm = roll.modifiers.new('Soft roll edge', 'BEVEL')
    sm.width = .0022
    sm.segments = 2
    sm.limit_method = 'ANGLE'
    core = cyl('Roll core', (0, ry, 0), rad0-thick+.002, length-.010, 'cloth', axis='X', bevel=.002, verts=16)
    weld('Tint', [roll, core], 'cloth')
    # Cream stripe following the middle of the wound cloth, proud of each end face.
    stripes = [spiral_prism('Roll end stripe', half+.0005, half+.0021, rad0, pitch, turns, thick,
                            .0055, .0055, 'cream', lift=ry),
               spiral_prism('Roll end stripe', -half-.0021, -half-.0005, rad0, pitch, turns, thick,
                            .0055, .0055, 'cream', lift=ry)]
    weld('Roll end stripes', stripes, 'cream')
    bands = []
    for x in (-.16, .16):
        bands.append(cyl('Roll tie', (x, ry, 0), rr_out+.0055, .044, 'stripe', axis='X', bevel=.004, verts=36))
        bands.append(cyl('Roll tie edge', (x, ry, 0), rr_out+.0075, .009, 'cream', axis='X', bevel=.0025, verts=36))
    weld('Roll ties', bands, 'stripe')
    rng = random.Random(11)
    tufts = []
    for i in range(12):
        a_ = i*2*math.pi/12+.2
        rr = rr_out-.010
        tufts.append(rod('Roll fringe', (half+.002, ry+rr*math.sin(a_)*.98, rr*math.cos(a_)),
                         (half+.026+rng.uniform(-.005, .005), ry+rr*math.sin(a_)*.98-.006, rr*math.cos(a_)*1.03),
                         .0034, 'white', verts=6))
    weld('Roll fringe', tufts, 'white')
    for o in active:                 # only one end carries fringe: centre the footprint
        o.location.x -= .014


# ---------------------------------------------------------------- Rack
def rack():
    """Free-standing weathered-wood towel rack.

    Two end frames, each a pair of feet crossing a tapered post; a round top rail
    the towels drape over, a lower slatted shelf and a mid stretcher. Authored small
    (0.58 x 0.28 x 0.90); the game scales it uniformly for medium and large.
    """
    px = .245                      # post centre x
    post_h = .855
    rail_y = .845
    wood = []
    for s in (-1, 1):
        wood.append(box('Post', (s*px, post_h/2+.02, 0), (.052, post_h, .052), 'weathered', .008, 2))
        # Foot beam crossing under the post, with rounded ends and a low brace to each end.
        wood.append(box('Foot', (s*px, .0185, 0), (.060, .037, .270), 'weathered', .010, 2))
        for t in (-1, 1):
            wood.append(rod('Foot brace', (s*px, .038, t*.090), (s*px, .330, t*.010), .011, 'weathered_dark'))
            wood.append(box('Foot cap', (s*px, .0185, t*.1355), (.062, .037, .004), 'weathered_dark', .002, 1))
    weld('Frame', wood, 'weathered')
    shelf = []
    for i, z in enumerate((-.075, 0.0, .075)):
        shelf.append(box('Shelf slat', (0, .212, z), (.462, .020, .062), 'weathered_dark', .005, 2))
    for s in (-1, 1):
        shelf.append(box('Shelf cleat', (s*(px-.032), .185, 0), (.012, .034, .214), 'weathered', .003, 1))
    weld('Shelf', shelf, 'weathered_dark')
    mid = [rod('Mid stretcher', (-px+.02, .545, 0), (px-.02, .545, 0), .011, 'weathered')]
    weld('Stretcher', mid, 'weathered')
    top = [rod('Top rail', (-px-.026, rail_y, 0), (px+.026, rail_y, 0), .0195, 'weathered', verts=20)]
    weld('Rail', top, 'weathered')
    # The painted accent: domed post caps, rail collars and the shelf trim board.
    paint = []
    for s in (-1, 1):
        paint.append(ell('Post cap', (s*px, post_h+.020, 0), (.036, .028, .036), 'cloth_rack'))
        paint.append(cyl('Rail collar', (s*(px-.052), rail_y, 0), .028, .016, 'cloth_rack', axis='X',
                         bevel=.003, verts=24))
        paint.append(cyl('Rail end', (s*(px+.0345), rail_y, 0), .026, .012, 'cloth_rack', top=.022, axis='X',
                         bevel=.003, verts=24))
    paint.append(box('Shelf trim', (0, .195, .112), (.462, .018, .014), 'cloth_rack', .004, 2))
    weld('Tint', paint, 'cloth_rack')
    for name, x in (('TowelRail_L', -.205), ('TowelRail_R', .205)):
        e = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(e)
        e.empty_display_type = 'ARROWS'
        e.empty_display_size = .03
        e.location = xyz((x, rail_y, 0))
        active.append(e)


# ---------------------------------------------------------------- Catalogue
catalog = [
    ('beach_towel', 'a', towel_flat),
    ('beach_towel', 'b', towel_stack),
    ('beach_towel', 'c', towel_rolled),
    ('towel_rack', None, rack),
]


def stem(kind, style):
    return kind if style is None else f'{kind}_{style}'


parser = argparse.ArgumentParser()
parser.add_argument('--only', nargs='+', metavar='STEM', help='build only the named stems')
parser.add_argument('--source-out', default=str(ART/'towels.blend'))
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])

ART.mkdir(parents=True, exist_ok=True)
MODELS.mkdir(parents=True, exist_ok=True)
selected = catalog
if args.only:
    wanted = set(args.only)
    selected = [row for row in catalog if stem(row[0], row[1]) in wanted]
    unknown = wanted - {stem(row[0], row[1]) for row in selected}
    if unknown:
        raise SystemExit('unknown item(s): '+', '.join(sorted(unknown)))

# Refuse to replace anything already on disk, before a single mesh is built.
for kind, style, _ in selected:
    destination = MODELS/f'{stem(kind, style)}.glb'
    if destination.exists():
        raise RuntimeError('Refusing to replace an existing model: '+str(destination))

tally = 0
for idx, (kind, style, fn) in enumerate(selected):
    active = []
    fn()
    root = bpy.data.objects.new(stem(kind, style), None)
    bpy.context.collection.objects.link(root)
    for o in active:
        if o.parent is None:
            o.parent = root
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for o in active:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(MODELS/f'{stem(kind, style)}.glb'),
                              export_format='GLB', use_selection=True,
                              export_apply=True, export_animations=False)
    root.location = ((idx % 4)*1.6, (idx//4)*1.6, 0)
    # Every model shares one scene, so free the surface names the catalogue looks
    # for (`Tint`, part names) for the next model to claim.
    for o in active + [root]:
        o.name = f'{stem(kind, style)}__{o.name}'
        if getattr(o.data, 'name', None) is not None:
            o.data.name = o.name
    tally += 1

bpy.ops.wm.save_as_mainfile(filepath=str(args.source_out))
print(f'JUSTLIFE_{GROUP}_COMPLETE', tally)
