"""Original JustLife outdoor water and garden hardware collection.

Run:  blender -b --factory-startup -t 2 --python-exit-code 2 --python tools/create_outdoor_water.py

Authors every pool, hot tub, pool extra, fence style, bollard light and wall
lantern the outdoor catalogue needs. Coordinates are Godot metres: x right,
y up, z toward the front of the item. The helpers mirror
tools/create_furniture_v2.py so the pieces match the shipped artwork; each
family is built from primitives only and exports as its own GLB.

Colour-variant kinds carry exactly one extra mesh named `Tint` (the surface a
player's colour choice repaints); pools and hot tubs also carry one mesh named
`Water`. Nothing here reads an external mesh, bitmap or texture.
"""
import bpy, math, pathlib, argparse, sys
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODELS = ROOT/'assets/models'
ART = ROOT/'art/outdoor_water'
GROUP = 'OUTDOOR_WATER'

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


for n, h in [('oak', 'AB7951'), ('oak_light', 'D7AE7E'), ('walnut', '624435'),
             ('cream', 'EFE9DA'), ('white', 'FAF6EA'), ('teal', '417A71'),
             ('teal_light', '86ADA0'), ('coral', 'C97C66'), ('gold', 'C8A562'),
             ('dark', '263E3C'), ('black', '1D292B'), ('green', '48794B'),
             ('leaf_light', '749752'), ('soil', '42352D'), ('blue', '7CA4AA'),
             ('linen', 'DECFAF'), ('water', 'B7D9DB'), ('rust', '9A5A44'),
             ('mustard', 'D2A24B'), ('sky', '9EC1CF'), ('rose', 'D9A0A0'),
             ('graphite', '4A4F55'), ('ivory', 'F6F1E4'), ('paving', 'D8D2C4'),
             ('stone', 'C6C1B4'), ('timber', '8E6B4F'), ('red', 'B4402F'),
             ('navy', '38546B'), ('sage', '93A98B'), ('tint_pale', 'E9E4D8')]:
    mat(n, h)
mat('chrome', 'D7DBDE', .22, .85)
mat('brass', 'C8A562', .40, .50)
mat('steel', 'B9BEC2', .35, .45)
mat('glow', 'FFF2D2', .35, 0, 3.4)


def water_material():
    """Pale blue, semi-transparent water. The parent never recolours it."""
    m = mat('pool_water', '9FD8E8', .10)
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Alpha'].default_value = .62
    m.diffuse_color = (*m.diffuse_color[:3], .62)
    for attr, val in (('blend_method', 'BLEND'), ('surface_render_method', 'BLENDED'),
                      ('show_transparent_back', False)):
        if hasattr(m, attr):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    return m


water_material()


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


def yaw(o, deg):
    o.rotation_euler[2] = math.radians(deg)
    return o


def pitch(o, rad):
    o.rotation_euler[1] = rad
    return o


def tilt(o, rad):
    o.rotation_euler[0] = rad
    return o


def scale_apply(o, s):
    o.scale = s
    select_only(o)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def apply_mods(o):
    if not o.modifiers:
        return o
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o],
                                   selected_editable_objects=[o]):
        for m in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception:
                o.modifiers.remove(m)
    return o


def weld(name, objs, matname=None):
    """Join primitive parts into one mesh object (needed for Tint and Water).

    With `matname` the joined surface is pinned to that single authored
    material, so the catalogue can recolour it by name even when the parts it
    was assembled from were built with materials of their own.
    """
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


def box(n, p, s, m, bevel=.03):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o = bpy.context.object
    o.dimensions = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b = o.modifiers.new('Soft crafted edges', 'BEVEL')
        b.width = bevel
        b.segments = 2
        b.limit_method = 'ANGLE'
    return finish(o, n, m)


def ell(n, p, s, m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=xyz(p))
    o = bpy.context.object
    o.scale = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for f in o.data.polygons:
        f.use_smooth = True
    return finish(o, n, m)


def cyl(n, p, r, h, m, top=None, axis='Y', bevel=.012, verts=32):
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


def torus(n, p, major, minor, m, axis='Y', seg=28, mseg=10, zs=1.0):
    bpy.ops.mesh.primitive_torus_add(major_segments=seg, minor_segments=mseg,
                                     major_radius=major, minor_radius=minor,
                                     location=xyz(p))
    o = bpy.context.object
    if zs != 1.0:
        scale_apply(o, (1, 1, zs))
    if axis == 'Z':
        o.rotation_euler = (math.pi/2, 0, 0)
    elif axis == 'X':
        o.rotation_euler = (0, math.pi/2, 0)
    for f in o.data.polygons:
        f.use_smooth = True
    return finish(o, n, m)


def arc_band(n, cx, cz, r_in, r_out, a0, a1, h, seg, m, bevel=.018):
    """A flat annulus section built from tangential primitives (curved coping)."""
    rmid = (r_in+r_out)/2
    step = math.radians(abs(a1-a0))/max(seg, 1)
    length = 2*rmid*math.sin(step/2)*1.08
    out = []
    for i in range(seg):
        phi = math.radians(a0+(a1-a0)*(i+.5)/seg)
        o = box(n, (cx+rmid*math.cos(phi), h/2, cz+rmid*math.sin(phi)),
                (length, h, r_out-r_in), m, bevel)
        yaw(o, -(math.degrees(phi)+90))
        out.append(o)
    return out


def free_ranges(discs, i, samples=144, test=0.32, wall=.06, min_span=7.0):
    """Angular spans of disc i that sit outside every other disc's paved rim."""
    cx, cz, r = discs[i]
    flags = []
    for k in range(samples):
        a = 2*math.pi*k/samples
        px, pz = cx+(r+test)*math.cos(a), cz+(r+test)*math.sin(a)
        blocked = False
        for j, (ox, oz, orr) in enumerate(discs):
            if j != i and math.hypot(px-ox, pz-oz) < orr+wall:
                blocked = True
                break
        flags.append(not blocked)
    if all(flags):
        return [(0.0, 360.0)]
    start = flags.index(False)
    flags = flags[start:]+flags[:start]
    out, s = [], None
    for k, f in enumerate(flags+[False]):
        if f and s is None:
            s = k
        elif not f and s is not None:
            d0 = (start+s)*360/samples
            d1 = (start+k)*360/samples
            if d1-d0 >= min_span:
                out.append((d0, d1))
            s = None
    return out


def settle(objs=None):
    """Drop everything built so far until its lowest vertex rests on y=0.

    Wall-mounted pieces hang below their own origin by construction, so the
    brief's ground contact has to be restored explicitly.
    """
    objs = list(active if objs is None else objs)
    bpy.context.view_layer.update()
    low = min((o.matrix_world @ v.co)[2] for o in objs for v in o.data.vertices)
    for o in objs:
        o.location.z -= low

# ---------------------------------------------------------------- Pools
# Each pool is authored at the 5.60 x 3.80 m footprint the garden ring on the
# starter lot can actually fit: x half 2.80, z half 1.90, 0.35 m high.
def pool_classic():
    """Rectangular pool: paved surround, plaster basin, corner steps, water."""
    tint = []
    for z in (-1.70, 1.70):
        tint.append(box('Coping', (0, .175, z), (5.60, .35, .40), 'tint_pale', .02))
    for x in (-2.60, 2.60):
        tint.append(box('Coping', (x, .175, 0), (.40, .35, 3.00), 'tint_pale', .02))
    weld('Tint', tint, 'tint_pale')
    for z in (-1.425, 1.425):
        box('Pool wall', (0, .19, z), (4.80, .32, .15), 'white', .012)
    for x in (-2.325, 2.325):
        box('Pool wall', (x, .19, 0), (.15, .32, 3.00), 'white', .012)
    box('Basin floor', (0, .03, 0), (4.80, .06, 3.00), 'stone', .008)
    for z in (-1.33, 1.33):
        box('Waterline tile', (0, .24, z), (4.50, .06, .05), 'sky', 0)
    # Step entry descending into the basin at the -x / +z corner.
    for x, top in ((-2.065, .30), (-1.695, .20), (-1.325, .10)):
        box('Pool step', (x, top/2, .90), (.37, top, .90), 'white', .012)
    box('Water', (0, .16, 0), (4.40, .02, 2.60), 'pool_water', 0)
    cyl('Skimmer lid', (2.16, .354, .80), .10, .014, 'chrome', .004)
    cyl('Drain', (0, .07, 0), .07, .02, 'chrome', .004)


def pool_roman():
    """Roman pool: rounded ends, a tiered central step and a shallow side ledge."""
    tint = []
    for z in (-1.70, 1.70):
        tint.append(box('Straight coping', (0, .175, z), (1.84, .35, .40), 'tint_pale', .02))
    tint += arc_band('Rounded coping', .90, 0, 1.50, 1.90, -90, 90, .35, 12, 'tint_pale')
    tint += arc_band('Rounded coping', -.90, 0, 1.50, 1.90, 90, 270, .35, 12, 'tint_pale')
    weld('Tint', tint, 'tint_pale')
    for z in (-1.425, 1.425):
        box('Pool wall', (0, .19, z), (1.84, .32, .15), 'white', .012)
    arc_band('Rounded wall', .90, 0, 1.42, 1.50, -90, 90, .32, 10, 'white', .012)
    arc_band('Rounded wall', -.90, 0, 1.42, 1.50, 90, 270, .32, 10, 'white', .012)
    floor = [box('Basin floor', (0, .03, 0), (1.84, .06, 3.00), 'stone', .008)]
    water = [box('Water', (0, .16, 0), (1.80, .02, 2.60), 'pool_water', 0)]
    for cx in (-.90, .90):
        floor.append(cyl('Basin floor', (cx, .03, 0), 1.50, .06, 'stone', .006))
        water.append(cyl('Water', (cx, .16, 0), 1.38, .02, 'pool_water', 0))
    weld('Water', water, 'pool_water')
    for o in floor:
        apply_mods(o)
    # Central entry: three tiers stepping down into the basin.
    cyl('Central step', (0, .055, 0), .80, .11, 'white', .008)
    cyl('Central step', (0, .105, 0), .60, .11, 'white', .008)
    cyl('Central step', (0, .155, 0), .40, .11, 'white', .008)
    for z in (-1.00, 1.00):
        box('Shallow ledge', (0, .07, z), (2.10, .14, .80), 'stone', .008)
    cyl('Drain', (0, .07, .95), .06, .02, 'chrome', .004)


def pool_lagoon():
    """Freeform lagoon: irregular lobed outline with a curved beach entry."""
    lobes = [(-1.18, -.30, 1.24), (.33, .24, 1.19), (1.44, -.30, .99)]
    tint, floors, waters = [], [], []
    for i, (cx, cz, r) in enumerate(lobes):
        for a0, a1 in free_ranges(lobes, i):
            span = max(4, int(round((a1-a0)/18.0)))
            tint += arc_band('Lagoon coping', cx, cz, r-.06, r+.34, a0, a1, .35, span,
                             'tint_pale', .012)
            arc_band('Lagoon wall', cx, cz, r-.10, r+.02, a0, a1, .32, span, 'white', .012)
        floors.append(cyl('Lagoon floor', (cx, .03, cz), r-.09, .06, 'stone', .006))
        waters.append(cyl('Water', (cx, .16, cz), r-.14, .02, 'pool_water', 0))
    weld('Tint', tint, 'tint_pale')
    weld('Water', waters, 'pool_water')
    for o in floors:
        apply_mods(o)
    # Curved beach entry: three submerged shelves inside the left lobe.
    for r, top in ((1.05, .12), (.76, .20), (.47, .28)):
        cyl('Beach shelf', (-1.18, top/2, -.30), r, top, 'stone', .008)
    cyl('Drain', (1.44, .07, -.30), .06, .02, 'chrome', .004)


# ---------------------------------------------------------------- Hot tubs
def hot_tub_round():
    """Round tub: moulded rim band, four headrests, an internal step and jets."""
    torus('Tub wall', (0, .36, 0), .82, .09, 'cream', zs=4.0, seg=32)
    cyl('Tub floor', (0, .05, 0), .78, .10, 'white', .006)
    cyl('Water', (0, .60, 0), .76, .02, 'pool_water', 0)
    torus('Tint', (0, .745, 0), .80, .10, 'tint_pale', zs=1.15, seg=32)
    for i in range(4):
        phi = math.pi/2+1.15+i*math.pi/2
        o = ell('Headrest', (.70*math.cos(phi), .80, .70*math.sin(phi)),
                (.15, .08, .13), 'graphite')
        yaw(o, -(math.degrees(phi)+90))
        ell('Jet', (.69*math.cos(phi), .44, .69*math.sin(phi)), (.055, .055, .055), 'steel')
    box('Step', (0, .16, -.77), (.56, .32, .38), 'graphite', .02)
    cyl('Drain', (0, .11, 0), .07, .02, 'chrome', .004)


def hot_tub_square():
    """Square tub: slatted surround, corner step and a moulded rim band."""
    for z in (-.92, .92):
        box('Tub wall', (0, .37, z), (2.00, .74, .16), 'cream', .014)
    for x in (-.92, .92):
        box('Tub wall', (x, .37, 0), (.16, .74, 1.68), 'cream', .014)
    for k in range(4):
        for i in range(4):
            u = -.60+i*.40
            if k < 2:
                box('Surround slat', (u, .39, (-1, 1)[k]*.995), (.28, .58, .035), 'timber', .004)
            else:
                box('Surround slat', ((-1, 1)[k-2]*.995, .39, u), (.035, .58, .28), 'timber', .004)
    tint = []
    for z in (-.86, .86):
        tint.append(box('Rim', (0, .80, z), (2.00, .12, .28), 'tint_pale', .02))
    for x in (-.86, .86):
        tint.append(box('Rim', (x, .80, 0), (.28, .12, 1.44), 'tint_pale', .02))
    weld('Tint', tint, 'tint_pale')
    box('Tub floor', (0, .05, 0), (1.75, .10, 1.75), 'white', .006)
    box('Water', (0, .60, 0), (1.66, .02, 1.66), 'pool_water', 0)
    box('Corner seat', (.62, .23, -.60), (.44, .46, .48), 'cream', .014)
    box('Corner tread', (.62, .115, -.21), (.44, .23, .30), 'cream', .014)
    for x in (-.55, .55):
        o = ell('Headrest', (x, .80, -.62), (.15, .08, .13), 'linen')
        yaw(o, 0)
    for i in range(4):
        ell('Jet', (.60*math.cos(i*1.57+.8), .42, .60*math.sin(i*1.57+.8)),
            (.055, .055, .055), 'steel')
    cyl('Drain', (0, .11, 0), .07, .02, 'chrome', .004)


def hot_tub_oval():
    """Oval tub: reclining backrest at one end, moulded rim and a step."""
    w = torus('Tub wall', (0, .36, 0), .55, .09, 'cream', seg=32)
    scale_apply(w, (1.719, 1.25, 4.0))
    f = cyl('Tub floor', (0, .05, 0), .58, .10, 'white', .006)
    scale_apply(f, (1.46, 1.08, 1.0))
    wt = cyl('Water', (0, .60, 0), .57, .02, 'pool_water', 0)
    scale_apply(wt, (1.46, 1.08, 1.0))
    r = torus('Tint', (0, .745, 0), .55, .11, 'tint_pale', seg=32)
    scale_apply(r, (1.62, 1.20, 1.0))
    back = ell('Backrest', (-.42, .58, 0), (.36, .13, .34), 'linen')
    tilt_ = pitch(back, .38)
    rod('Backrest roll', (-.68, .74, -.28), (-.68, .74, .28), .055, 'linen')
    for z in (-.30, .30):
        ell('Headrest', (-.42, .74, z), (.10, .10, .09), 'graphite')
    box('Step', (-.62, .14, -.775), (.40, .28, .35), 'cream', .014)
    for i in range(4):
        phi = i*1.57+.6
        ell('Jet', (.66*math.cos(phi), .42, .48*math.sin(phi)), (.055, .055, .055), 'steel')
    cyl('Drain', (0, .11, 0), .07, .02, 'chrome', .004)


# ---------------------------------------------------------------- Pool extras
def plate(n, a, b, w, th, m, bevel=.012, up='Z'):
    """Flat slab spanning Godot points a->b: w across, th thick along local up."""
    av, bv = Vector(xyz(a)), Vector(xyz(b))
    d = bv-av
    bpy.ops.mesh.primitive_cube_add(size=1, location=(av+bv)/2)
    o = bpy.context.object
    o.rotation_euler = d.to_track_quat('Y', up).to_euler()
    o.scale = (w, d.length, th)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b = o.modifiers.new('Soft crafted edges', 'BEVEL')
        b.width = bevel
        b.segments = 2
        b.limit_method = 'ANGLE'
    return finish(o, n, m)


def rail_path(n, pts, r, m):
    return [rod(n, pts[i], pts[i+1], r, m) for i in range(len(pts)-1)]


def pool_ladder():
    """Chrome ladder: two rails curving over the pool edge, three rungs."""
    path = [(-.27, .00), (-.27, .78), (-.22, .97), (-.08, 1.07),
            (.08, 1.07), (.22, .97), (.27, .78), (.27, .44)]
    tint = []
    for x in (-.26, .26):
        tint += rail_path('Handrail', [(x, y, z) for z, y in path], .024, 'chrome')
    weld('Tint', tint, 'chrome')
    for y in (.16, .38, .60):
        rod('Rung', (-.26, y, -.27), (.26, y, -.27), .019, 'steel')
    for x in (-.26, .26):
        box('Rail foot', (x, .02, .27), (.10, .04, .10), 'steel', .008)
    for x in (-.26, .26):
        rod('Rail brace', (x, .78, -.27), (x, .44, .27), .016, 'steel')


def flume(name, pts, width, m, wall_h=.16, tint=False):
    """Segmented moulded flume following a 3D centreline."""
    parts = []
    for i in range(len(pts)-1):
        a, b = pts[i], pts[i+1]
        dx, dz = b[0]-a[0], b[2]-a[2]
        n_ = math.hypot(dx, dz) or 1.0
        ox, oz = -dz/n_, dx/n_
        off = width/2
        parts.append(plate(name+' chute', a, b, width, .05, m, .008))
        for s in (-1, 1):
            ao = (a[0]+ox*off*s, a[1]+wall_h/2, a[2]+oz*off*s)
            bo = (b[0]+ox*off*s, b[1]+wall_h/2, b[2]+oz*off*s)
            parts.append(plate(name+' chute wall', ao, bo, .055, wall_h, m, .008))
    return parts


def slide_common(name):
    """Shared tower: ladder, platform, corner posts and handrails."""
    parts = [box(name+' platform', (0, .72, .88), (1.00, .07, .50), 'white', .014)]
    for x in (-.55, .55):
        for z in (.64, 1.12):
            parts.append(rod('Tower post', (x, .70, z), (x, 1.50, z), .024, 'chrome'))
            parts.append(box('Tower foot', (x, .02, z), (.13, .04, .13), 'steel', .006))
            parts.append(cyl('Post cap', (x, 1.52, z), .034, .05, 'brass', top=.012,
                             bevel=.004, verts=12))
    for z in (.64, 1.12):
        parts.append(box('Tower top rail', (0, 1.50, z), (1.15, .05, .05), 'chrome', .008))
    for x in (-.55, .55):
        parts.append(box('Tower side rail', (x, 1.50, .88), (.05, .05, .48), 'chrome', .008))
    for x in (-.34, .34):
        parts.append(rod('Ladder stile', (x, .02, 1.34), (x, .70, 1.12), .022, 'steel'))
        parts.append(box('Ladder foot', (x, .02, 1.36), (.11, .04, .11), 'steel', .006))
    for t in (.18, .38, .58):
        y = .02+t*.68
        z = 1.34-t*.22
        parts.append(rod('Ladder rung', (-.34, y, z), (.34, y, z), .018, 'steel'))
    return parts


def pool_slide_curved():
    """Moulded slide with a single sweeping bend."""
    slide_common('Curved slide')
    weld('Tint', flume('Curved slide', [(0, .70, .60), (0, .63, .22), (.04, .54, -.10),
                                        (.12, .43, -.40), (.22, .31, -.68),
                                        (.32, .18, -.90), (.38, .08, -1.04)],
                       .50, 'tint_pale'), 'tint_pale')


def pool_slide_straight():
    """Plain raked chute: a straight descending flume."""
    slide_common('Straight slide')
    weld('Tint', flume('Straight slide', [(0, .70, .60), (0, .60, .18), (0, .49, -.22),
                                          (0, .38, -.60), (0, .27, -.90),
                                          (0, .16, -1.06)], .62, 'tint_pale'),
         'tint_pale')
    for x in (-.34, .34):
        rod('Side rail', (x, .70, .60), (x, .16, -1.06), .020, 'chrome')


def pool_slide_spiral():
    """Moulded slide that turns a full circle on the way down."""
    slide_common('Spiral slide')
    pts = [(0, .70, .60)]
    for k in range(13):
        t = k/12
        a = math.radians(90+400*t)
        r = .26+.08*t
        pts.append((r*math.cos(a), .68-.51*t, .10+r*math.sin(a)))
    pts.append((0, .12, -1.06))
    weld('Tint', flume('Spiral slide', pts, .44, 'tint_pale'), 'tint_pale')


def pool_ring():
    """Rubber ring: a torus with a valve stem and a contrasting panel band."""
    torus('Rubber ring', (0, .075, 0), .34, .11, 'sage', seg=32, zs=.68)
    band = box('Contrast panel', (-.34, .075, 0), (.22, .15, .08), 'tint_pale', .02)
    weld('Tint', [band], 'tint_pale')
    cyl('Valve stem', (.30, .12, 0), .045, .06, 'graphite', .01)
    cyl('Valve collar', (.30, .085, 0), .055, .03, 'steel', .008)


def pool_noodle():
    """Long foam noodle lying along x with a rolled-back end."""
    body = cyl('Foam noodle', (-.60, .08, 0), .08, 1.35, 'tint_pale', .02, axis='X')
    torus('Rolled end', (.10, .08, 0), .06, .026, 'tint_pale', axis='X', seg=20, mseg=10)
    weld('Tint', [body], 'tint_pale')
    settle()


def pool_light():
    """Submerged pool light: sealed housing, lens ring and mounting collar."""
    cyl('Light housing', (0, .045, 0), .11, .09, 'white', .01)
    torus('Mounting collar', (0, .014, 0), .108, .014, 'steel', seg=28)
    weld('Tint', [torus('Lens ring', (0, .086, 0), .092, .014, 'chrome', seg=28)],
         'chrome')
    cyl('Lens', (0, .09, 0), .082, .012, 'glow', .004)
    for i in range(4):
        a = i*1.5708+.4
        cyl('Collar screw', (.105*math.cos(a), .012, .105*math.sin(a)), .012, .012,
            'steel', .002, verts=8)


def post_box():
    """Garden post box: post, letter box with domed lid, door, handle and flag."""
    cyl('Box post', (0, .38, 0), .055, .76, 'timber', .01)
    cyl('Post base plate', (0, .015, 0), .11, .03, 'graphite', .006)
    box('Post brace', (0, .70, 0), (.10, .10, .10), 'timber', .01)
    box('Letter box', (0, .88, 0), (.32, .30, .34), 'red', .018)
    ell('Domed lid', (0, 1.02, 0), (.19, .14, .20), 'red')
    box('Lid rim', (0, 1.005, 0), (.35, .03, .37), 'red', .012)
    box('Letter slot', (0, .96, .172), (.20, .028, .016), 'black', .004)
    box('Slot hood', (0, .995, .182), (.24, .02, .05), 'red', .008)
    weld('Tint', [box('Box door', (0, .85, .172), (.26, .22, .022), 'tint_pale', .012)],
         'tint_pale')
    rod('Door hinge', (-.115, .85, .185), (-.115, .85, .16), .012, 'steel')
    cyl('Door handle', (.10, .80, .19), .016, .035, 'steel', .004, verts=10)
    rod('Flag post', (.17, 1.00, .02), (.17, 1.14, .02), .014, 'graphite')
    box('Flag', (.22, 1.10, .02), (.11, .10, .012), 'coral', .004)


# ---------------------------------------------------------------- Fences
def fence_frame(depth=.12):
    """Two timber posts at +/-0.95 with caps: shared by all ten panel styles."""
    for x in (-.95, .95):
        box('Fence post', (x, .60, 0), (.10, 1.20, depth), 'timber', .012)
        box('Post cap', (x, 1.24, 0), (.15, .08, depth), 'timber', .012)


def fence_01():
    """Closeboard: overlapping vertical pales with two rails behind."""
    fence_frame()
    tint = []
    for i in range(8):
        u = -.78+i*.223
        tint.append(box('Closeboard pale', (u, .60, 0), (.20, 1.12, .10), 'tint_pale', .008))
    weld('Tint', tint, 'tint_pale')
    for y in (.22, .98):
        box('Fence rail', (0, y, -.037), (1.80, .08, .04), 'timber', .006)


def fence_02():
    """Picket: slender pales with gaps and pointed tops."""
    fence_frame()
    tint = []
    for i in range(10):
        u = -.765+i*.17
        tint.append(box('Picket pale', (u, .58, 0), (.095, 1.02, .095), 'tint_pale', .006))
        p = cyl('Picket point', (u, 1.11, 0), .067, .10, 'tint_pale', top=.004,
                bevel=.004, verts=4)
        yaw(p, 45)
        tint.append(p)
    weld('Tint', tint, 'tint_pale')
    for y in (.24, .92):
        box('Fence rail', (0, y, -.037), (1.78, .09, .04), 'timber', .006)


def fence_03():
    """Horizontal slat boards with a shadow gap."""
    fence_frame()
    tint = []
    for i in range(8):
        tint.append(box('Slat board', (0, .20+i*.128, 0), (1.78, .105, .10),
                        'tint_pale', .006))
    weld('Tint', tint, 'tint_pale')


def fence_04():
    """Trellis top over a solid base panel."""
    fence_frame()
    tint = [box('Base panel', (0, .28, 0), (1.80, .52, .10), 'tint_pale', .008)]
    for i in range(9):
        tint.append(box('Trellis lath', (-.80+i*.20, .79, 0), (.045, .52, .05),
                        'tint_pale', .004))
    weld('Tint', tint, 'tint_pale')
    for y in (.58, .78, 1.00):
        box('Trellis rail', (0, y, -.037), (1.80, .04, .044), 'timber', .004)


def fence_05():
    """Post-and-rail: three broad rails between the posts."""
    fence_frame()
    tint = []
    for y in (.22, .60, .98):
        tint.append(box('Post and rail', (0, y, 0), (1.80, .11, .10), 'tint_pale', .008))
    weld('Tint', tint, 'tint_pale')


def fence_06():
    """Square lattice held in a framed panel."""
    fence_frame()
    tint = []
    for i in range(8):
        u = -.79+i*.226
        tint.append(box('Lattice strip', (u, .62, -.02), (.05, 1.02, .05),
                        'tint_pale', .004))
        tint.append(box('Lattice strip', (0, .19+i*.125, .02), (1.02, .05, .05),
                        'tint_pale', .004))
    weld('Tint', tint, 'tint_pale')
    for x in (-.90, .90):
        box('Frame stile', (x, .62, 0), (.08, 1.06, .10), 'timber', .006)
    for y in (.09, 1.15):
        box('Frame rail', (0, y, 0), (1.82, .08, .10), 'timber', .006)


def fence_07():
    """Woven hazel hurdle: horizontal rods through alternating uprights."""
    fence_frame()
    tint = []
    for i in range(7):
        tint.append(rod('Hurdle rod', (-.88, .09+i*.16, -.018), (.88, .09+i*.16, -.018),
                        .028, 'tint_pale'))
    weld('Tint', tint, 'tint_pale')
    for i in range(11):
        u = -.85+i*.17
        s = 1 if i % 2 == 0 else -1
        rod('Hurdle upright', (u, .02, s*.028), (u, 1.14, -s*.028), .024, 'timber')


def fence_08():
    """Feather-edge boards under a capping rail."""
    fence_frame()
    tint = []
    for i in range(9):
        tint.append(box('Feather-edge board', (-.80+i*.20, .62, 0), (.21, 1.06, .10),
                        'tint_pale', .006))
    weld('Tint', tint, 'tint_pale')
    box('Capping rail', (0, 1.15, 0), (1.80, .10, .12), 'timber', .012)


def fence_09():
    """Metal railing bars with finial tops."""
    fence_frame()
    tint = []
    for i in range(11):
        u = -.80+i*.16
        tint.append(rod('Railing bar', (u, .06, 0), (u, 1.08, 0), .018, 'steel'))
    weld('Tint', tint, 'steel')
    for y in (.10, .55, 1.02):
        box('Railing rail', (0, y, 0), (1.76, .05, .06), 'steel', .006)
    for i in range(11):
        u = -.80+i*.16
        cyl('Railing finial', (u, 1.14, 0), .03, .10, 'steel', top=.005,
            bevel=.004, verts=12)


def fence_10():
    """Ranch: crossed diagonal rails under a straight top rail."""
    fence_frame()
    tint = []
    # Yaw would only spin these in plan; the diagonal needs a roll about the
    # panel's depth axis, which is the helpers' pitch().
    for z, deg in ((-.015, -72.0), (.015, 72.0)):
        tint.append(pitch(box('Crossed rail', (0, .585, z), (.10, 1.99, .03),
                              'tint_pale', .006), math.radians(deg)))
    weld('Tint', tint, 'tint_pale')
    box('Top rail', (0, 1.10, 0), (1.86, .10, .10), 'timber', .008)


# ---------------------------------------------------------------- Garden lights
def pane(n, p, s):
    """Emissive glazing slab: every light gets one."""
    return box(n, p, s, 'glow', 0)


def stake_bollard(post_top=.66, r=.05):
    """Ground stake plus the tinted post shared by every bollard."""
    cyl('Ground stake', (0, .07, 0), .022, .14, 'graphite', top=.005, bevel=.004, verts=12)
    weld('Tint', [cyl('Light post', (0, post_top/2+.02, 0), r, post_top, 'tint_pale')],
         'tint_pale')


def garden_light_01():
    """Square lantern head."""
    stake_bollard()
    box('Lantern case', (0, .74, 0), (.15, .22, .15), 'black', .01)
    pane('Lantern pane', (0, .74, .007), (.11, .17, .152))
    cyl('Lantern hood', (0, .875, 0), .115, .06, 'black', top=.03, bevel=.006, verts=4)
    cyl('Lantern finial', (0, .915, 0), .022, .035, 'black', top=.004, bevel=.003, verts=10)


def garden_light_02():
    """Louvred hat bollard."""
    stake_bollard()
    cyl('Lamp drum', (0, .73, 0), .085, .20, 'black', bevel=.006, verts=20)
    for i in range(5):
        cyl('Louvre ring', (0, .655+i*.038, 0), .098, .016, 'steel', bevel=.004, verts=20)
    pane('Lamp pane', (0, .73, .008), (.13, .17, .17))
    cyl('Lamp hat', (0, .86, 0), .105, .045, 'black', top=.03, bevel=.006, verts=20)


def garden_light_03():
    """Globe on a short post."""
    stake_bollard(post_top=.58)
    cyl('Globe collar', (0, .615, 0), .055, .05, 'brass', bevel=.006, verts=20)
    ell('Globe', (0, .775, 0), (.105, .105, .105), 'glow')
    cyl('Globe cap', (0, .878, 0), .045, .035, 'brass', bevel=.006, verts=16)


def garden_light_04():
    """Wide cone hood over a drum."""
    stake_bollard()
    cyl('Lamp drum', (0, .70, 0), .07, .16, 'black', bevel=.006, verts=20)
    pane('Lamp pane', (0, .70, .013), (.11, .13, .13))
    cyl('Cone hood', (0, .845, 0), .115, .10, 'black', top=.012, bevel=.008, verts=24)
    cyl('Hood finial', (0, .905, 0), .018, .04, 'black', top=.004, bevel=.003, verts=10)


def garden_light_05():
    """Tall box louvre head."""
    stake_bollard()
    box('Louvre box', (0, .745, 0), (.20, .26, .17), 'black', .01)
    for i in range(4):
        box('Louvre slot', (0, .665+i*.06, .088), (.15, .022, .012), 'glow', 0)
    box('Louvre lid', (0, .895, 0), (.22, .04, .20), 'black', .008)
    cyl('Lid finial', (0, .93, 0), .02, .05, 'black', top=.004, bevel=.003, verts=10)


def garden_light_06():
    """Post with twin shaded heads on a cross arm."""
    stake_bollard(post_top=.70, r=.04)
    box('Cross arm', (0, .745, 0), (.18, .05, .06), 'black', .008)
    box('Cross brace', (0, .745, 0), (.05, .05, .20), 'black', .008)
    for s in (-1, 1):
        cyl('Lamp shade', (s*.055, .80, 0), .055, .05, 'black', top=.034,
            bevel=.005, verts=16)
        pane('Lamp pane', (s*.055, .785, 0), (.075, .045, .075))
    ell('Lamp cap', (0, .775, 0), (.03, .03, .03), 'brass')
    cyl('Lamp finial', (0, .845, 0), .015, .04, 'black', top=.004, bevel=.003, verts=10)


def garden_light_07():
    """Wide mushroom cap on a slim post."""
    stake_bollard(post_top=.62, r=.04)
    cyl('Mushroom stem', (0, .68, 0), .05, .08, 'black', bevel=.006, verts=16)
    o = ell('Mushroom cap', (0, .76, 0), (.115, .065, .115), 'black')
    pane('Cap pane', (0, .715, 0), (.19, .02, .19))


def garden_light_08():
    """Cylinder guard: a barred cage around an emissive core."""
    stake_bollard(post_top=.54)
    cyl('Guard base', (0, .585, 0), .10, .05, 'black', bevel=.008, verts=24)
    cyl('Lamp core', (0, .74, 0), .072, .26, 'glow', bevel=.006, verts=20)
    for i in range(8):
        a = i*math.pi/4
        rod('Guard bar', (.095*math.cos(a), .58, .095*math.sin(a)),
            (.095*math.cos(a), .90, .095*math.sin(a)), .014, 'black')
    cyl('Guard rim', (0, .90, 0), .105, .04, 'black', bevel=.008, verts=24)
    cyl('Guard cap', (0, .935, 0), .06, .035, 'black', top=.02, bevel=.006, verts=16)


def garden_light_09():
    """Tiered pagoda roof."""
    stake_bollard(post_top=.50, r=.045)
    box('Pagoda body', (0, .63, 0), (.15, .20, .15), 'black', .01)
    pane('Pagoda pane', (0, .63, .003), (.12, .16, .16))
    for i, (r, h) in enumerate(((.115, .045), (.088, .04), (.060, .035))):
        cyl('Pagoda tier', (0, .745+i*.042, 0), r, h, 'black', top=r*.55,
            bevel=.006, verts=4)
    cyl('Pagoda finial', (0, .87, 0), .018, .04, 'brass', top=.004, bevel=.003, verts=10)


def garden_light_10():
    """Sphere on a slender stem."""
    stake_bollard(post_top=.70, r=.032)
    cyl('Stem collar', (0, .73, 0), .048, .04, 'brass', bevel=.006, verts=16)
    ell('Glass sphere', (0, .80, 0), (.108, .108, .108), 'glow')
    cyl('Stem finial', (0, .888, 0), .03, .035, 'brass', top=.012, bevel=.004, verts=12)


def wall_lantern(pw=.19, ph=.30):
    """Back plate (the Tint surface) shared by every wall lantern."""
    weld('Tint', [box('Back plate', (0, ph/2, -.135), (pw, ph, .028),
                      'tint_pale', .008)], 'tint_pale')


def garden_light_wall_01():
    """Half-lantern against the back plate."""
    wall_lantern()
    box('Lantern back', (0, .19, -.095), (.16, .22, .07), 'black', .006)
    cyl('Half lantern body', (0, .19, .04), .085, .20, 'black', bevel=.006, verts=20)
    pane('Half lantern pane', (0, .19, .053), (.13, .16, .16))
    cyl('Lantern roof', (0, .325, .04), .105, .05, 'black', top=.025, bevel=.006, verts=16)
    cyl('Lantern finial', (0, .365, .04), .016, .09, 'black', top=.004, bevel=.003, verts=10)
    settle()


def garden_light_wall_02():
    """Coach lamp with a tapered body and a bottom finial."""
    wall_lantern(pw=.21)
    box('Coach back', (0, .19, -.095), (.17, .24, .07), 'black', .006)
    cyl('Coach body', (0, .17, .04), .075, .22, 'black', top=.05, bevel=.006, verts=6)
    pane('Coach pane', (0, .17, .048), (.11, .18, .15))
    cyl('Coach roof', (0, .34, .04), .10, .10, 'black', top=.015, bevel=.006, verts=6)
    cyl('Coach drop', (0, .035, .04), .022, .06, 'brass', top=.005, bevel=.004, verts=10)
    settle()


def garden_light_wall_03():
    """Arm and globe."""
    wall_lantern(pw=.21)
    rod('Lamp arm', (0, .24, -.12), (0, .22, .05), .018, 'black')
    rod('Arm brace', (0, .13, -.12), (0, .21, .03), .012, 'black')
    cyl('Globe collar', (0, .245, .07), .045, .05, 'brass', bevel=.006, verts=16)
    ell('Glass globe', (0, .22, .07), (.095, .095, .095), 'glow')
    cyl('Globe cap', (0, .325, .07), .035, .04, 'brass', bevel=.005, verts=16)
    cyl('Globe finial', (0, .375, .07), .014, .07, 'brass', top=.004, bevel=.003, verts=10)
    settle()


def garden_light_wall_04():
    """Downlight hood on a tall bracket."""
    wall_lantern()
    box('Hood bracket', (0, .29, -.075), (.10, .22, .09), 'black', .008)
    box('Hood arm', (0, .20, 0), (.08, .16, .14), 'black', .008)
    cyl('Downlight hood', (0, .12, .06), .105, .07, 'black', top=.075, bevel=.008, verts=20)
    pane('Downlight pane', (0, .072, .06), (.16, .022, .16))
    cyl('Hood rim', (0, .082, .06), .10, .02, 'steel', bevel=.005, verts=20)
    settle()


def garden_light_wall_05():
    """Two-way corner lantern: opposed heads on one plate."""
    wall_lantern(pw=.16)
    box('Corner back', (0, .21, -.075), (.13, .26, .12), 'black', .008)
    cyl('Corner post', (0, .21, .05), .045, .26, 'black', bevel=.006, verts=16)
    for s in (-1, 1):
        box('Corner lantern', (s*.055, .19, .05), (.11, .20, .15), 'black', .008)
        pane('Corner pane', (s*.055, .19, .048), (.08, .16, .17))
    cyl('Corner cap', (0, .375, .05), .055, .06, 'black', top=.02, bevel=.005, verts=16)
    cyl('Corner finial', (0, .415, .05), .014, .05, 'black', top=.004, bevel=.003, verts=10)
    settle()


def garden_light_wall_06():
    """Square louvre lantern."""
    wall_lantern()
    box('Louvre lantern', (0, .19, .045), (.20, .26, .17), 'black', .008)
    for i in range(3):
        box('Louvre opening', (0, .11+i*.08, .132), (.15, .024, .012), 'glow', 0)
    box('Louvre roof', (0, .345, .045), (.22, .05, .20), 'black', .008)
    cyl('Louvre finial', (0, .385, .045), .018, .05, 'black', top=.004, bevel=.003, verts=10)
    settle()


def garden_light_wall_07():
    """Round bulkhead drum under a cowl."""
    wall_lantern(pw=.17)
    cyl('Bulkhead drum', (0, .19, .03), .095, .18, 'black', bevel=.008, verts=20)
    cyl('Bulkhead pane', (0, .19, .108), .082, .03, 'glow', bevel=.004, verts=20,
        axis='Z')
    torus('Bulkhead ring', (0, .19, .105), .092, .016, 'steel', axis='Z', seg=24)
    for i in range(4):
        a = i*math.pi/2+.78
        cyl('Bulkhead clip', (.078*math.cos(a), .19+.078*math.sin(a), .116), .014, .018,
            'steel', axis='Z', bevel=.002, verts=10)
    box('Bulkhead cowl', (0, .345, 0), (.20, .04, .13), 'black', .008)
    cyl('Bulkhead finial', (0, .395, 0), .016, .04, 'black', top=.004, bevel=.003, verts=10)
    settle()


def garden_light_wall_08():
    """Up-and-down lantern: opposed panes on a drum."""
    wall_lantern(pw=.21)
    cyl('Twin drum', (0, .20, .03), .085, .15, 'black', bevel=.008, verts=20)
    cyl('Upper pane', (0, .245, .043), .075, .15, 'glow', axis='Z', bevel=.004, verts=20)
    cyl('Lower pane', (0, .155, .043), .075, .15, 'glow', axis='Z', bevel=.004, verts=20)
    cyl('Twin hood', (0, .30, .03), .10, .05, 'black', top=.06, bevel=.006, verts=20)
    cyl('Twin rim', (0, .10, .03), .098, .03, 'black', top=.085, bevel=.006, verts=20)
    cyl('Twin finial', (0, .375, .03), .016, .06, 'black', top=.004, bevel=.003, verts=10)
    settle()


def garden_light_wall_09():
    """Scroll bracket carrying a lantern."""
    wall_lantern(pw=.17)
    pts = [(-.09, .28, -.12), (0, .30, -.08), (.05, .31, -.01), (.02, .31, .05)]
    for i in range(len(pts)-1):
        rod('Scroll arm', pts[i], pts[i+1], .014, 'black')
    cyl('Scroll stem', (.02, .22, .06), .012, .22, 'black', top=.012, bevel=.003, verts=10)
    box('Scroll lantern', (.02, .13, .06), (.20, .18, .13), 'black', .008)
    pane('Scroll pane', (.02, .13, .053), (.14, .15, .16))
    cyl('Scroll base', (.02, .03, .06), .022, .04, 'black', bevel=.004, verts=12)
    cyl('Scroll cap', (.02, .365, .06), .020, .07, 'black', top=.008, bevel=.003, verts=10)
    ell('Scroll tip', (.02, .40, .06), (.022, .022, .022), 'brass')
    settle()


def garden_light_wall_10():
    """Small sconce with a shallow hood and a bottom knob."""
    wall_lantern(pw=.16)
    box('Sconce back', (0, .18, -.085), (.13, .22, .09), 'black', .006)
    box('Sconce body', (0, .18, .03), (.17, .18, .16), 'black', .008)
    pane('Sconce pane', (0, .18, .033), (.13, .15, .17))
    box('Sconce hood', (0, .30, .03), (.22, .04, .20), 'black', .008)
    cyl('Sconce finial', (0, .36, .03), .016, .08, 'black', top=.006, bevel=.003, verts=10)
    cyl('Sconce knob', (0, .06, .03), .018, .05, 'brass', top=.008, bevel=.003, verts=10)
    settle()


# ---------------------------------------------------------------- Catalogue
# (kind, style or None, builder)
catalog = [
    ('pool', 'classic', pool_classic),
    ('pool', 'roman', pool_roman),
    ('pool', 'lagoon', pool_lagoon),
    ('hot_tub', 'round', hot_tub_round),
    ('hot_tub', 'square', hot_tub_square),
    ('hot_tub', 'oval', hot_tub_oval),
    ('pool_ladder', None, pool_ladder),
    ('pool_slide', 'curved', pool_slide_curved),
    ('pool_slide', 'straight', pool_slide_straight),
    ('pool_slide', 'spiral', pool_slide_spiral),
    ('pool_ring', None, pool_ring),
    ('pool_noodle', None, pool_noodle),
    ('pool_light', None, pool_light),
    ('post_box', None, post_box),
    ('fence', '01', fence_01),
    ('fence', '02', fence_02),
    ('fence', '03', fence_03),
    ('fence', '04', fence_04),
    ('fence', '05', fence_05),
    ('fence', '06', fence_06),
    ('fence', '07', fence_07),
    ('fence', '08', fence_08),
    ('fence', '09', fence_09),
    ('fence', '10', fence_10),
    ('garden_light', '01', garden_light_01),
    ('garden_light', '02', garden_light_02),
    ('garden_light', '03', garden_light_03),
    ('garden_light', '04', garden_light_04),
    ('garden_light', '05', garden_light_05),
    ('garden_light', '06', garden_light_06),
    ('garden_light', '07', garden_light_07),
    ('garden_light', '08', garden_light_08),
    ('garden_light', '09', garden_light_09),
    ('garden_light', '10', garden_light_10),
    ('garden_light_wall', '01', garden_light_wall_01),
    ('garden_light_wall', '02', garden_light_wall_02),
    ('garden_light_wall', '03', garden_light_wall_03),
    ('garden_light_wall', '04', garden_light_wall_04),
    ('garden_light_wall', '05', garden_light_wall_05),
    ('garden_light_wall', '06', garden_light_wall_06),
    ('garden_light_wall', '07', garden_light_wall_07),
    ('garden_light_wall', '08', garden_light_wall_08),
    ('garden_light_wall', '09', garden_light_wall_09),
    ('garden_light_wall', '10', garden_light_wall_10),
]


def stem(kind, style):
    return kind if style is None else f'{kind}_{style}'


parser = argparse.ArgumentParser()
parser.add_argument('--only', nargs='+', metavar='STEM',
                    help='build only the named stems, e.g. --only pool_roman '
                         'pool_classic pool_lagoon')
parser.add_argument('--source-out', default=str(ART/'outdoor_water.blend'))
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
    root.location = ((idx % 6)*4, (idx//6)*4, 0)
    # Every model shares one scene, so free the surface names the catalogue
    # looks for (`Tint`, `Water`, part names) for the next model to claim.
    for o in active + [root]:
        o.name = f'{stem(kind, style)}__{o.name}'
        if getattr(o.data, 'name', None) is not None:
            o.data.name = o.name
    tally += 1

bpy.ops.wm.save_as_mainfile(filepath=str(args.source_out))
print(f'JUSTLIFE_{GROUP}_COMPLETE', tally)
