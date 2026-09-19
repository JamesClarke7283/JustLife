"""Original JustLife vehicle and garage models.

Run:
    blender -b --factory-startup -t 2 --python-exit-code 2 \
        --python tools/create_vehicles.py

Ten car styles and five garages, each authored at its small catalogue footprint
and exported as its own GLB under `assets/models/`. Every model carries exactly
one joined mesh named `Tint`: the painted body panels on a car, the door - or
the fascia trim of the open carport - on a garage. Coordinates are Godot metres
- x right, y up, z toward the front of the vehicle - with ground contact at
y = 0.
"""
import argparse, math, pathlib, sys
import bpy
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODELS = ROOT / 'assets/models'
ART = ROOT / 'art/vehicles'
GROUP = 'VEHICLES'

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
             ('teal','417A71'),('coral','C97C66'),('gold','C8A562'),
             ('dark','263E3C'),('black','1D292B'),('green','48794B'),
             ('blue','7CA4AA'),('linen','DECFAF'),('rust','9A5A44'),
             ('brick','8C5A4A'),('mustard','D2A24B'),('plum','6E5470'),
             ('sky','9EC1CF'),('rose','D9A0A0'),('graphite','4A4F55'),
             ('concrete','B4B2AA'),('chalk','F0EEE6'),('rubber','2C3133'),
             ('glass','9FBDC6'),('felt','5C6B62'),('timber','C09A6B'),
             ('slate','5A6068'),('tile','A8583F')]:
    mat(n, h)
mat('steel', 'B9BEC2', .35, .45)
mat('chrome', 'D2D8DC', .3, .6)
mat('lamp', 'FBF3D8', .25, 0, 1.2)
mat('tail_lamp', 'C0392B', .35, 0, .8)
mat('tint_neutral', 'D8D8D0', .6, 0)

# ---------------------------------------------------------------- primitives
active = []
TINT = []

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
    """`p` and `s` are Godot metres: position (x, y, z), size (x, y, z)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o = bpy.context.object; o.dimensions = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Soft crafted edges', 'BEVEL')
        mod.width = bevel; mod.segments = 3
        o.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return _finish(o, n, m, tint)

def cyl(n, p, r, h, m, top=None, axis='Y', tint=False):
    """A cylinder of radius `r` and length `h` lying along the named Godot axis."""
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

def rot(o, x=0.0, y=0.0, z=0.0):
    """Godot-space rotation: `x` pitches about Godot X (a rake), `y` rolls about
    Godot Z (a roof slope) and `z` yaws about Godot Y (a door swing)."""
    o.rotation_euler = (x, y, z); return o

def span(n, a, b, w, thick, m, bevel=.008, tint=False):
    """A flat panel spanning Godot points `a` to `b` in the vehicle's centre
    plane, `w` wide across the vehicle. Used for every raked screen and slope."""
    dy, dz = b[0]-a[0], b[1]-a[1]
    ln = math.hypot(dy, dz)
    o = box(n, (0, (a[0]+b[0])/2, (a[1]+b[1])/2), (w, ln, thick), m, bevel, tint)
    return rot(o, x=math.atan2(dz, dy))

def join_tint(name='Tint', m='tint_neutral'):
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

def ground_contact(name):
    """Ground contact is part of the contract: a tilted panel or a rounded tyre
    can dip below y = 0, so snap the whole model up to rest exactly on it."""
    bpy.context.view_layer.update()
    low = min((o.matrix_world @ v.co).z for o in active for v in o.data.vertices)
    if abs(low) > .0005:
        for o in active:
            o.location.z -= low
        print('  %s: shifted %+.4f m to sit exactly on the ground' % (name, -low))

# ---------------------------------------------------------------- cars
# Every car is authored at the catalogue footprint of 4.20 x 1.80 m so the
# catalogue's uniform scale reaches the intended size. Bodies are 1.62 m wide
# and the mirrors take the model out to 1.80. Lengths are set by placing the
# bumpers at z = +/-2.00, which is where the 4.20 m comes from.
LEN, WID = 4.20, 1.62
BZ, BD = 2.00, .20          # bumper centre and depth

def car_body(length, sill, belt, under=.24, m='white'):
    box('Underbody', (0, under/2+.01, 0), (WID-.08, under, length), 'graphite', .020)
    box('Body shell', (0, (sill+belt)/2, 0), (WID, belt-sill, length), m, .060, tint=True)

def bonnet(z0, z1, y, width, m='white'):
    box('Bonnet', (0, y+.025, (z0+z1)/2), (width, .05, abs(z1-z0)), m, .012, tint=True)

def boot_deck(z0, z1, y, width, m='white'):
    box('Boot deck', (0, y+.025, (z0+z1)/2), (width, .05, abs(z1-z0)), m, .012, tint=True)

def cabin_roof(z0, z1, y, width, m='white'):
    box('Cabin roof', (0, y, (z0+z1)/2), (width, .09, abs(z1-z0)), m, .050, tint=True)

def screen(n, a, b, width, m='glass'):
    span(n, a, b, width, .06, m)

def car_bumpers(y, h=.24, m='graphite'):
    box('Front bumper', (0, y, BZ), (WID+.10, h, BD), m, .014)
    box('Rear bumper', (0, y, -BZ), (WID+.10, h, BD), m, .014)

def car_lights(y, w=.34, h=.15):
    for sx in (-1, 1):
        box('Headlight', (sx*.56, y, BZ-.10), (w, h, .12), 'lamp', .010)
        box('Tail light', (sx*.58, y, -(BZ-.10)), (.28, h+.01, .12), 'tail_lamp', .010)

def car_side_glass(y, zs, height, lengths, m='glass'):
    for z, ln in zip(zs, lengths):
        for sx in (-1, 1):
            box('Side window', (sx*.78, y, z), (.04, height, ln), m, .008)

def car_pillars(y, zs, height, m='graphite'):
    for z in zs:
        for sx in (-1, 1):
            box('Window pillar', (sx*.78, y, z), (.06, height, .09), m, .008)

def car_doors(zs, lengths, sill, belt, m='white'):
    for z, ln in zip(zs, lengths):
        for sx in (-1, 1):
            box('Body door', (sx*.81, (sill+belt)/2, z), (.04, belt-sill-.06, ln), m,
                .006, tint=True)
            box('Door handle', (sx*.83, belt-.10, z+ln*.34), (.03, .04, .16), 'chrome',
                .006)

def car_mirrors(y, z):
    for sx in (-1, 1):
        rod('Mirror stalk', (sx*.80, y, z), (sx*.85, y+.01, z+.03), .014, 'graphite')
        box('Mirror', (sx*.88, y+.02, z+.03), (.06, .10, .17), 'graphite', .010)

def car_axles(front_z, rear_z, r, w, track, hub=.52):
    for z in (front_z, rear_z):
        for sx in (-1, 1):
            cyl('Wheel tyre', (sx*track, r, z), r, w, 'rubber', axis='X')
            disc('Wheel hub', (sx*(track+w/2), r, z), r*hub, .02, 'chrome', axis='X')

def car_plate(z=-BZ+.03, y=.34):
    box('Number plate', (0, y, z), (.52, .11, .02), 'ivory', .004)

def car_seats(xs, y, z):
    for x in xs:
        box('Cabin seat', (x, y, z), (.50, .50, .22), 'graphite', .015)

def car_rails(y, z0, z1):
    for sx in (-1, 1):
        rod('Roof rail', (sx*.62, y, z0), (sx*.62, y, z1), .020, 'chrome')

def car_saloon_a():
    """Five-door saloon: one continuous cabin and a steeply raked tailgate."""
    car_body(4.20, .24, 1.06)
    bonnet(.55, 2.04, 1.06, 1.46)
    cabin_roof(1.17, -1.45, 1.455, 1.42)
    screen('Windscreen', (1.06, 1.77), (1.425, 1.17), 1.38)
    screen('Tailgate glass', (.86, -1.85), (1.425, -1.45), 1.36)
    car_side_glass(1.21, (.16, -.86), .32, (.52, .52))
    car_pillars(1.21, (1.05, .10, -1.02), .34)
    car_doors((.58, -.34), (.46, .46), .24, 1.06)
    car_bumpers(.44)
    car_lights(.72)
    car_mirrors(1.06, .90)
    car_axles(1.30, -1.30, .34, .24, .72)
    car_plate()

def car_saloon_b():
    """Four-door saloon: three boxes, a short cabin and a separate boot deck."""
    car_body(4.20, .24, 1.06)
    bonnet(.60, 2.04, 1.06, 1.46)
    boot_deck(-2.04, -1.02, 1.06, 1.46)
    cabin_roof(1.10, -1.10, 1.455, 1.42)
    screen('Windscreen', (1.06, 1.72), (1.425, 1.10), 1.38)
    screen('Rear window', (1.06, -1.62), (1.425, -1.10), 1.36)
    car_side_glass(1.21, (.10, -.90), .32, (.50, .50))
    car_pillars(1.21, (1.00, .06, -.98), .34)
    car_doors((.72, -.24), (.48, .48), .24, 1.06)
    car_bumpers(.44)
    car_lights(.72)
    car_mirrors(1.04, .94)
    car_axles(1.30, -1.30, .34, .24, .72)
    car_plate()

def car_hatchback():
    """Compact hatchback: short cabin, near-vertical tailgate, tall glasshouse."""
    car_body(4.20, .22, 1.02)
    bonnet(1.25, 2.04, 1.02, 1.38)
    cabin_roof(.90, -1.20, 1.455, 1.36)
    screen('Windscreen', (1.02, 1.40), (1.425, .90), 1.32)
    screen('Tailgate glass', (.86, -1.92), (1.425, -1.20), 1.30)
    car_side_glass(1.20, (.02, -.72), .32, (.48, .46))
    car_pillars(1.20, (.86, -.06, -1.14), .34)
    car_doors((.40, -.42), (.46, .44), .22, 1.02)
    car_bumpers(.42, .22)
    car_lights(.70, w=.32)
    car_mirrors(1.00, .70)
    car_axles(1.22, -1.26, .32, .22, .68)
    car_plate()

def car_estate():
    """Estate: the roofline runs unbroken to the tail, with roof rails."""
    car_body(4.20, .24, 1.06)
    bonnet(.60, 2.04, 1.06, 1.46)
    cabin_roof(1.00, -2.04, 1.455, 1.42)
    screen('Windscreen', (1.06, 1.72), (1.425, 1.00), 1.38)
    screen('Tailgate glass', (.94, -2.14), (1.425, -2.04), 1.36)
    car_side_glass(1.21, (.30, -.80, -1.70), .32, (.42, .60, .30))
    car_pillars(1.21, (.94, -.02, -1.44), .34)
    car_doors((.62, -.36), (.46, .46), .24, 1.06)
    car_rails(1.52, -2.02, 1.00)
    car_bumpers(.44)
    car_lights(.72)
    car_mirrors(1.06, 1.00)
    car_axles(1.40, -1.40, .34, .24, .72)
    car_plate()

def car_coupe():
    """Coupe: a low fastback roof and two long doors, with no rear doors."""
    car_body(4.20, .24, 1.02)
    bonnet(.85, 2.04, 1.02, 1.46)
    boot_deck(-2.04, -1.60, 1.06, 1.42)
    cabin_roof(.85, -1.60, 1.32, 1.36)
    screen('Windscreen', (1.02, 1.62), (1.275, .85), 1.32)
    screen('Fastback glass', (1.00, -2.14), (1.275, -1.60), 1.34)
    car_side_glass(1.14, (-.24,), .20, (.56,))
    car_pillars(1.14, (.60,), .22)
    car_doors((.34, -.54), (.70, .70), .24, 1.02)
    car_bumpers(.38, .20)
    car_lights(.64)
    car_mirrors(1.02, .72)
    car_axles(1.32, -1.32, .33, .25, .72)
    car_plate()

def car_van():
    """Panel van: a tall slab body with no rear side glass and a sliding door."""
    car_body(4.20, .26, 1.37)
    box('Cab roof', (0, 1.70, .70), (1.60, .08, 1.30), 'white', .040, tint=True)
    box('Cargo crown', (0, 1.88, -1.00), (1.64, .12, 2.16), 'white', .050, tint=True)
    bonnet(1.35, 2.04, 1.37, 1.48)
    screen('Windscreen', (1.37, 2.12), (1.66, 1.35), 1.42)
    car_side_glass(1.55, (.98,), .30, (.36,))
    car_pillars(1.20, (1.34,), .60)
    car_doors((1.06,), (.56,), .26, 1.37)
    box('Sliding door', (.82, 1.24, .0), (.04, .90, 1.10), 'white', .006, tint=True)
    box('Cargo doors', (0, 1.30, -2.06), (1.58, 1.20, .05), 'white', .010, tint=True)
    car_bumpers(.42, .24)
    car_lights(1.06)
    car_mirrors(1.34, 1.58)
    car_axles(1.32, -1.42, .36, .26, .74)
    car_seats((-.42, .42), 1.05, 1.08)
    car_plate()

def car_minibus():
    """People carrier: a one-box shape with glass all round and three seat rows."""
    car_body(4.20, .25, 1.27)
    box('Cabin roof', (0, 1.80, -.10), (1.60, .10, 3.60), 'white', .050, tint=True)
    bonnet(1.40, 2.04, 1.27, 1.46)
    screen('Windscreen', (1.27, 2.08), (1.75, 1.40), 1.40)
    screen('Tailgate glass', (.90, -2.08), (1.75, -2.00), 1.36)
    car_side_glass(1.45, (1.00, .20, -.70, -1.60), .34, (.36, .50, .48, .30))
    car_pillars(1.45, (1.32, .76, .00, -1.06, -1.80), .36)
    car_doors((.96, -.04), (.52, .52), .25, 1.27)
    car_rails(1.88, -1.86, 1.30)
    car_bumpers(.42, .24)
    car_lights(1.00)
    car_mirrors(1.38, 1.66)
    car_axles(1.34, -1.36, .36, .26, .74)
    car_seats((-.42, .42), 1.05, .92)
    car_seats((-.42, .42), 1.05, -.16)
    car_plate()

def car_suv():
    """SUV: a tall body, roof rails, big wheels and chunky bumpers."""
    car_body(4.20, .32, 1.16)
    bonnet(1.30, 2.04, 1.16, 1.48)
    cabin_roof(1.30, -2.00, 1.76, 1.56)
    screen('Windscreen', (1.16, 1.95), (1.71, 1.30), 1.42)
    screen('Tailgate glass', (.80, -2.12), (1.71, -2.00), 1.40)
    car_side_glass(1.43, (.20, -.92), .54, (.48, .46))
    car_pillars(1.43, (1.04, -.08, -1.52), .56)
    car_doors((.76, -.28), (.48, .46), .32, 1.16)
    car_rails(1.84, -1.94, .80)
    box('Side step', (0, .34, .40), (1.62, .06, 1.20), 'graphite', .010)
    box('Side step', (0, .34, -.92), (1.62, .06, 1.00), 'graphite', .010)
    car_bumpers(.38, .28)
    car_lights(1.10)
    car_mirrors(1.40, 1.16)
    car_axles(1.34, -1.38, .40, .28, .74)
    car_plate()

def car_offroader():
    """Boxy off-roader: flat panels, a spare wheel on the tail and a roof rack."""
    car_body(4.20, .36, 1.13)
    bonnet(1.36, 2.04, 1.13, 1.54)
    cabin_roof(1.36, -1.86, 1.80, 1.52)
    screen('Windscreen', (1.13, 1.58), (1.75, 1.36), 1.46)
    screen('Tailgate glass', (.70, -1.96), (1.75, -1.86), 1.42)
    car_side_glass(1.44, (.70, -.58), .60, (.50, .48))
    car_pillars(1.44, (1.20, .06, -1.52), .62)
    car_doors((.98, -.52), (.46, .46), .36, 1.13)
    box('Roof rack', (0, 1.90, -.60), (1.40, .08, 2.40), 'graphite', .010)
    for sx in (-1, 1):
        rod('Rack rail', (sx*.84, 2.00, -1.76), (sx*.84, 2.00, .56), .022, 'steel')
    car_bumpers(.40, .28)
    cyl('Spare wheel', (0, 1.00, -2.12), .36, .26, 'rubber', axis='Z')
    disc('Spare hub', (0, 1.00, -2.26), .19, .02, 'chrome', axis='Z')
    car_lights(1.20)
    car_mirrors(1.42, 1.40)
    car_axles(1.36, -1.36, .42, .30, .76)

def car_pickup():
    """Pickup: a crew cab in front and an open load bed behind."""
    car_body(4.20, .30, 1.06)
    box('Cab body', (0, .78, 1.02), (1.62, .52, 2.00), 'white', .055, tint=True)
    box('Cab roof', (0, 1.42, .86), (1.52, .10, 1.72), 'white', .050, tint=True)
    bonnet(1.02, 2.04, 1.06, 1.50)
    screen('Windscreen', (1.06, 1.60), (1.375, .86), 1.42)
    screen('Cab rear glass', (.90, -.16), (1.375, .12), 1.40)
    car_side_glass(1.20, (1.10, .30), .32, (.42, .40))
    car_pillars(1.20, (1.52, .66), .34)
    car_doors((1.44, .58), (.44, .42), .30, 1.06)
    box('Bed floor', (0, .62, -1.18), (1.60, .14, 1.66), 'white', .020, tint=True)
    for sx in (-1, 1):
        box('Bed side', (sx*.80, .92, -1.18), (.06, .52, 1.66), 'graphite', .010)
    box('Bed tailgate', (0, .92, -2.00), (1.62, .52, .06), 'graphite', .010)
    box('Bed headboard', (0, .96, -.34), (1.62, .58, .06), 'graphite', .010)
    car_bumpers(.42, .22)
    car_lights(1.04)
    car_mirrors(1.26, 1.40)
    car_axles(1.60, -1.34, .38, .28, .74)
    car_plate(-1.97)

# ---------------------------------------------------------------- garages
def garage_slab(width=3.34, depth=3.14):
    box('Garage slab', (0, .04, 0), (width, .08, depth), 'concrete', .010)

def garage_walls(width, depth, eaves, m):
    box('Garage back wall', (0, eaves/2, -depth/2), (width, eaves, .14), m, .010)
    for sx in (-1, 1):
        box('Garage side wall', (sx*(width/2-.07), eaves/2, 0), (.14, eaves, depth),
            m, .010)

def pitched_roof(width, depth, eaves, ridge, m='tile'):
    """Two slopes rising from the eaves at |x| = width/2 to the ridge at x = 0."""
    run, rise = width/2, ridge-eaves
    ang = math.atan2(rise, run)
    ln = math.hypot(run, rise)
    for sx in (-1, 1):
        o = box('Garage roof slope', (sx*run/2, (eaves+ridge)/2, 0),
                (ln, .10, depth+.16), m, .008)
        rot(o, y=-sx*ang)
    rod('Roof ridge cap', (0, ridge+.03, -(depth/2+.08)), (0, ridge+.03, depth/2+.08),
        .05, m)
    for z in (-(depth/2+.07), depth/2+.07):
        for i in range(3):
            y = eaves + (i+.5)*rise/3
            box('Roof gable', (0, y, z), (width*(ridge-y)/rise-.06, .12, .08), m, .006)

def flat_roof(width, depth, y, fascia_m, m='slate'):
    box('Roof slab', (0, y, 0), (width+.16, .12, depth+.16), m, .010)
    box('Roof fascia front', (0, y-.14, depth/2+.08), (width+.16, .18, .06), fascia_m,
        .008, tint=True)
    for sx in (-1, 1):
        box('Roof fascia side', (sx*(width/2+.08), y-.14, 0), (.06, .18, depth+.16),
            fascia_m, .008, tint=True)

def roller_door(x, y0, y1, half_w, z, slats, m='white'):
    for i in range(slats):
        y = y0 + (i+.5)*(y1-y0)/slats
        box('Roller door slat', (x, y, z), (half_w*2, (y1-y0)/slats*.92, .07), m, .006,
            tint=True)
    for sx in (-1, 1):
        box('Door guide', (x+sx*(half_w+.05), (y0+y1)/2, z), (.10, y1-y0+.14, .16),
            'graphite', .010)

def garage_brick():
    """Brick garage with one roller door and a pitched roof."""
    garage_slab()
    garage_walls(3.20, 3.00, 2.00, 'brick')
    for sx in (-1, 1):
        box('Brick pier', (sx*1.20, 1.00, 1.44), (1.00, 2.00, .16), 'brick', .010)
    box('Brick lintel', (0, 1.88, 1.44), (1.60, .30, .16), 'brick', .010)
    for i in range(4):
        box('Brick course', (0, .26+i*.50, 1.53), (3.22, .06, .03), 'tile', .002)
    pitched_roof(3.20, 3.00, 2.00, 2.34)
    roller_door(0, .10, 1.74, .80, 1.40, 9, 'white')

def garage_timber():
    """Timber-clad garage with two swing doors standing ajar."""
    garage_slab()
    garage_walls(3.20, 3.00, 2.00, 'timber')
    # Cladding covers the closed back and side walls; the front holds the doors.
    for sx in (-1, 1):
        for i in range(10):
            box('Timber cladding', (sx*1.615, .19+i*.20, 0), (.04, .18, 2.92),
                'oak_light', .004)
    for i in range(10):
        box('Timber cladding', (0, .19+i*.20, -1.505), (3.20, .18, .04), 'oak_light', .004)
    for sx in (-1, 1):
        box('Door jamb', (sx*1.52, 1.00, 1.44), (.22, 2.00, .16), 'timber', .010)
    box('Door lintel', (0, 1.90, 1.44), (2.86, .28, .16), 'timber', .010)
    pitched_roof(3.20, 3.00, 2.00, 2.34)
    for sx in (-1, 1):
        o = box('Swing door', (sx*.70, .92, 1.50), (.72, 1.78, .07), 'white', .012,
                tint=True)
        rot(o, z=sx*.14)
        box('Door step', (sx*.70, .04, 1.52), (.74, .06, .28), 'concrete', .006)
        for y in (.48, .92):
            box('Door strap', (sx*.70, y, 1.545), (.62, .05, .10), 'steel', .004)

def garage_lean_to():
    """Lean-to car port: a back wall, part side walls, an open front and a
    shallow single-slope roof falling toward the front."""
    garage_slab()
    box('Garage back wall', (0, 1.10, -1.43), (3.20, 2.20, .14), 'timber', .010)
    for sx in (-1, 1):
        box('Garage side wall', (sx*1.53, 1.22, -.64), (.14, 2.44, 1.74), 'brick', .010)
        box('Carport post', (sx*1.46, 1.12, 1.36), (.16, 2.24, .16), 'timber', .010)
        box('Post pad', (sx*1.46, .04, 1.36), (.30, .06, .30), 'concrete', .006)
    o = box('Lean-to roof', (0, 2.28, 0), (3.26, .12, 3.16), 'slate', .010)
    rot(o, x=-.10)
    for i in range(4):
        y = 1.98 + i*.10
        rod('Roof purlin', (-1.40, y+.19, -1.50), (1.40, y-.19, 1.50), .030, 'steel')
    for sx in (-1, 1):
        box('Carport beam', (sx*1.50, 2.20, 0), (.10, .20, 3.10), 'timber', .008)
        box('Gutter', (sx*1.62, 2.14, 0), (.10, .12, 3.10), 'graphite', .008)
    box('Roof fascia', (0, 2.16, 1.55), (3.26, .20, .08), 'graphite', .008, tint=True)

def garage_double():
    """Extra-wide double garage with two roller doors and a pitched roof."""
    garage_slab()
    garage_walls(3.20, 3.00, 1.80, 'concrete')
    for x in (-1.52, 0, 1.52):
        box('Brick pier', (x, .90, 1.44), (.26, 1.80, .16), 'brick', .010)
    box('Brick lintel', (0, 1.66, 1.44), (3.12, .32, .16), 'brick', .010)
    for sx in (-1, 1):
        roller_door(sx*.78, .10, 1.52, .62, 1.40, 8, 'white')
    pitched_roof(3.20, 3.00, 1.80, 2.30)

def garage_carport():
    """Open carport: six posts, a slab roof and no walls."""
    garage_slab(3.36, 3.16)
    for sx in (-1, 0, 1):
        for sz in (-1, 1):
            box('Carport post', (sx*1.44, 1.10, sz*1.36), (.16, 2.20, .16), 'timber',
                .010)
            box('Post pad', (sx*1.44, .05, sz*1.36), (.30, .06, .30), 'concrete', .006)
    for sz in (-1, 1):
        rod('Carport beam', (-1.58, 2.22, sz*1.34), (1.58, 2.22, sz*1.34), .070, 'timber')
    for sx in (-1, 0, 1):
        rod('Carport rafter', (sx*1.44, 2.24, -1.50), (sx*1.44, 2.24, 1.50), .055, 'timber')
    flat_roof(3.20, 3.00, 2.34, 'teal')
    for sx in (-1, 1):
        box('Shelving unit', (sx*1.30, .51, -.90), (.24, 1.02, 1.14), 'timber', .010)
        for i in range(3):
            box('Shelf', (sx*1.30, .30+i*.32, -.90), (.30, .05, 1.14), 'oak_light', .006)

catalog = {
    'car_saloon_a': car_saloon_a,
    'car_saloon_b': car_saloon_b,
    'car_hatchback': car_hatchback,
    'car_estate': car_estate,
    'car_coupe': car_coupe,
    'car_van': car_van,
    'car_minibus': car_minibus,
    'car_suv': car_suv,
    'car_offroader': car_offroader,
    'car_pickup': car_pickup,
    'garage_brick': garage_brick,
    'garage_timber': garage_timber,
    'garage_lean_to': garage_lean_to,
    'garage_double': garage_double,
    'garage_carport': garage_carport,
}

parser = argparse.ArgumentParser()
parser.add_argument('--only', choices=tuple(catalog))
parser.add_argument('--source-out', default='art/vehicles/vehicles.blend')
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
    root.location = ((idx % 4)*5, (idx//4)*5, 0)

bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_'+GROUP+'_COMPLETE', len(catalog))
