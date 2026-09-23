"""Author the ten curtain-set styles as distinct silhouettes.

Each style is its own model at assets/models/curtains_<01..10>.glb, as
LifeCatalogVariants expects: a style is a different shape, and the catalogue
colour repaints the fabric, which is authored on the `Tint` surface. Hardware
(poles, rings, finials, tiebacks, pelmets) keeps its own material.

Art contract, in glTF/Godot axes (x across the window, y up, z into the room):
  * origin on the floor at the wall face, back of the set at z = -0.07;
  * 2.4 m across, so both panels frame the 1.76 m window aperture;
  * the pole sits at 2.36 m, just above the window frame head (2.31 m).

Run headless:  blender --background --python tools/create_curtains.py
Run in a live session (Blender MCP): exec the file; it builds in its own scene
and leaves the open file untouched.
"""
import bpy, bmesh, math, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models"
POLE_Y = 2.36
HALF = 1.2
BACK = -0.07

MATS = {}
# Blender may suffix a material name that is still in use elsewhere in the
# session, so parts are grouped by the name the style asked for.
ROLE = {}


def mat(name, hexcolor, rough=.7, metal=0.0):
    if name in MATS:
        return MATS[name]
    rgb = [int(hexcolor[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    m = bpy.data.materials.new(name)
    ROLE[m.name] = name
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m


def gl(x, y, z):
    """glTF (x, y up, z toward the room) -> Blender (x, -z, y)."""
    return (x, -z, y)


class Build:
    def __init__(self, scene):
        self.scene = scene
        self.parts = {}

    def _obj(self, name, mesh, material):
        o = bpy.data.objects.new(name, mesh)
        self.scene.collection.objects.link(o)
        mesh.materials.append(material)
        self.parts.setdefault(ROLE.get(material.name, material.name), []).append(o)
        return o

    def grid(self, name, material, cols, rows, point):
        """A cloth sheet: `point(u, v)` gives the glTF position for u, v in 0..1."""
        bm = bmesh.new()
        verts = []
        for j in range(rows + 1):
            row = []
            for i in range(cols + 1):
                row.append(bm.verts.new(gl(*point(i / cols, j / rows))))
            verts.append(row)
        for j in range(rows):
            for i in range(cols):
                bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        o = self._obj(name, mesh, material)
        s = o.modifiers.new("Thickness", "SOLIDIFY")
        s.thickness = .012
        s.offset = 0
        return o

    def box(self, name, material, center, size):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co.x *= size[0]
            v.co.y *= size[2]
            v.co.z *= size[1]
            c = gl(*center)
            v.co.x += c[0]; v.co.y += c[1]; v.co.z += c[2]
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        return self._obj(name, mesh, material)

    def rod(self, name, material, a, b, radius, segments=12):
        """A cylinder between two glTF points."""
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=1.0)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        o = self._obj(name, mesh, material)
        pa, pb = gl(*a), gl(*b)
        from mathutils import Vector
        va, vb = Vector(pa), Vector(pb)
        d = vb - va
        o.location = (va + vb) / 2
        o.scale = (1, 1, d.length)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
        return o

    def ball(self, name, material, center, radius):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=radius)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        o = self._obj(name, mesh, material)
        o.location = gl(*center)
        return o

    def finish(self, kind):
        """Join each material's parts into one mesh; the fabric becomes `Tint`."""
        root = bpy.data.objects.new(kind, None)
        self.scene.collection.objects.link(root)
        names = {"fabric": "Tint", "pole": "Pole", "pole_dark": "Pole", "brass": "Hardware", "wood": "Pelmet", "sheer": "Sheer"}
        for material_name, objects in self.parts.items():
            for o in objects:
                for m in list(o.modifiers):
                    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o], selected_editable_objects=[o], scene=self.scene):
                        bpy.ops.object.modifier_apply(modifier=m.name)
                o.data.transform(o.matrix_basis)
                o.matrix_basis.identity()
            first = objects[0]
            if len(objects) > 1:
                with bpy.context.temp_override(active_object=first, selected_editable_objects=objects, selected_objects=objects, scene=self.scene):
                    bpy.ops.object.join()
            first.name = names.get(material_name, material_name.title())
            first.data.name = first.name
            first.parent = root
        path = OUT / f"{kind}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_active_scene=True, export_apply=True)
        return str(path)


def fold(u, folds, amplitude):
    return amplitude * math.sin(u * folds * math.tau)


def panel(b, name, x0, x1, y0, y1, folds=6, amp=.035, z=0.0, hem=None, gather=None, material=None, cols=28, rows=12):
    """A hanging panel from x0..x1 (glTF) between y0 (hem) and y1 (head).

    `hem(u)` shifts the hem height, `gather(v)` narrows the panel toward its
    outer edge at height v (0 hem .. 1 head), which is how a tieback reads.
    """
    outer = x0 if abs(x0) > abs(x1) else x1

    def point(u, v):
        x = x0 + (x1 - x0) * u
        if gather is not None:
            x = outer + (x - outer) * gather(v)
        bottom = y0 + (hem(u) if hem else 0.0)
        y = bottom + (y1 - bottom) * v
        depth = z + fold(u, folds, amp * (0.55 + 0.45 * (1 - v)))
        return (x, y, depth)

    return b.grid(name, material or mat("fabric", "C97C66", .85), cols, rows, point)


def pole(b, y=POLE_Y, reach=HALF + .08, radius=.016, finial="ball", material=None):
    m = material or mat("pole", "B9BEC2", .3, .8)
    b.rod("pole", m, (-reach, y, -.02), (reach, y, -.02), radius)
    for side in (-1, 1):
        b.box("bracket", m, (side * (reach - .1), y, -.045), (.02, .05, .05))
        if finial == "ball":
            b.ball("finial", m, (side * (reach + .03), y, -.02), .035)
        elif finial == "cone":
            b.rod("finial", m, (side * reach, y, -.02), (side * (reach + .07), y, -.02), .028, 8)


def rings(b, x0, x1, count, y=POLE_Y, material=None):
    m = material or mat("brass", "C9A05A", .35, .8)
    for i in range(count):
        x = x0 + (x1 - x0) * i / max(1, count - 1)
        b.rod("ring", m, (x - .006, y, -.02), (x + .006, y, -.02), .026, 10)


# ---------------------------------------------------------------- the styles

def style_01(b):
    """Classic pinch pleat, floor length, brass rings on a slim pole."""
    pole(b)
    for side in (-1, 1):
        x0, x1 = side * HALF, side * .52
        panel(b, "panel", x0, x1, .02, POLE_Y - .05, folds=7, amp=.03)
        rings(b, x0, x1, 7)


def style_02(b):
    """Tab top on a chunky wooden pole, sill length."""
    wood = mat("wood", "AB7951", .55)
    pole(b, radius=.024, finial="cone", material=wood)
    for side in (-1, 1):
        x0, x1 = side * (HALF - .02), side * .48
        panel(b, "panel", x0, x1, .80, POLE_Y - .1, folds=5, amp=.022)
        for i in range(6):
            x = x0 + (x1 - x0) * (i + .5) / 6
            b.box("tab", mat("fabric", "C97C66", .85), (x, POLE_Y - .04, -.02), (.05, .14, .06))


def style_03(b):
    """Tied back: panels gathered to the sides by brass holdbacks at 1.05 m."""
    pole(b)
    tie = .38

    def gather(v):
        # Full width at the head and hem, pinched at the tie height.
        return 1.0 - .72 * math.exp(-((v - tie) / .16) ** 2)

    for side in (-1, 1):
        panel(b, "panel", side * HALF, side * .15, .02, POLE_Y - .05, folds=8, amp=.03, gather=gather)
        b.ball("holdback", mat("brass", "C9A05A", .35, .8), (side * 1.12, .02 + (POLE_Y - .07) * tie, .02), .04)


def style_04(b):
    """Café curtains on a low rod across the lower half, with a short valance."""
    m = mat("pole", "B9BEC2", .3, .8)
    low = 1.58
    b.rod("cafe_rod", m, (-1.0, low, -.02), (1.0, low, -.02), .012)
    pole(b)
    for side in (-1, 1):
        panel(b, "cafe", side * .98, 0.0, .86, low - .03, folds=6, amp=.02)
    panel(b, "valance", -1.1, 1.1, POLE_Y - .32, POLE_Y - .03, folds=10, amp=.018, cols=40, rows=4)


def style_05(b):
    """Box pleat pelmet over full-length side panels."""
    wood = mat("wood", "EFE9DA", .6)
    b.box("pelmet_board", wood, (0, POLE_Y + .02, -.01), (2.44, .04, .12))
    for side in (-1, 1):
        panel(b, "panel", side * HALF, side * .55, .02, POLE_Y - .05, folds=6, amp=.03)
    for i in range(12):
        x = -1.1 + 2.2 * (i + .5) / 12
        b.box("box_pleat", mat("fabric", "C97C66", .85), (x, POLE_Y - .12, .045), (.17, .26, .03))


def style_06(b):
    """Swag and tails: a draped curve across the head with falling tails."""
    pole(b, finial="cone")

    def swag_point(u, v):
        x = -1.15 + 2.3 * u
        sag = .42 * math.sin(u * math.pi)
        top = POLE_Y - .03
        y = top - (sag + .08) * v - .06 * v
        return (x, y, .03 + .05 * math.sin(u * math.pi) * v)

    b.grid("swag", mat("fabric", "C97C66", .85), 32, 8, swag_point)
    for side in (-1, 1):
        panel(b, "tail", side * 1.2, side * .9, 1.35, POLE_Y - .04, folds=4, amp=.025,
              hem=lambda u, s=side: .45 * u)


def style_07(b):
    """Layered: a sheer across the window with coloured side panels over it."""
    pole(b)
    m = mat("pole", "B9BEC2", .3, .8)
    b.rod("sheer_rod", m, (-1.12, POLE_Y - .07, -.045), (1.12, POLE_Y - .07, -.045), .01)
    panel(b, "sheer", -1.05, 1.05, .05, POLE_Y - .1, folds=12, amp=.012, z=-.035,
          material=mat("sheer", "F3EEE2", .95), cols=40, rows=10)
    for side in (-1, 1):
        panel(b, "panel", side * HALF, side * .7, .02, POLE_Y - .05, folds=5, amp=.03, z=.02)


def style_08(b):
    """Eyelet wave folds on a black pole: deep, regular S-folds."""
    pole(b, radius=.019, material=mat("pole_dark", "3D4145", .35, .6))
    for side in (-1, 1):
        x0, x1 = side * HALF, side * .5
        panel(b, "panel", x0, x1, .02, POLE_Y - .02, folds=4, amp=.055)
        rings(b, x0, x1, 8, material=mat("pole_dark", "3D4145", .35, .6))


def style_09(b):
    """Pencil pleat under a shaped wooden pelmet, sill length."""
    wood = mat("wood", "AB7951", .55)

    def pelmet_point(u, v):
        x = -1.22 + 2.44 * u
        drop = .16 + .08 * math.cos(u * math.tau * 2)
        return (x, POLE_Y + .06 - drop * (1 - v), .06)

    b.grid("pelmet_face", wood, 40, 4, pelmet_point)
    b.box("pelmet_top", wood, (0, POLE_Y + .06, 0), (2.46, .03, .14))
    for side in (-1, 1):
        panel(b, "panel", side * 1.18, side * .45, .82, POLE_Y - .04, folds=12, amp=.015, cols=44)


def style_10(b):
    """Nursery scallops: panels with a scalloped hem under a bunting valance."""
    pole(b, material=mat("wood", "EFE9DA", .6))

    def scallop(u):
        return .06 * abs(math.sin(u * math.pi * 4))

    for side in (-1, 1):
        panel(b, "panel", side * HALF, side * .5, .02, POLE_Y - .05, folds=6, amp=.028, hem=scallop)
    for i in range(11):
        x = -1.1 + 2.2 * (i + .5) / 11

        def flag(u, v, cx=x):
            half = .09 * (1 - v)
            return (cx - half + 2 * half * u, POLE_Y - .06 - .2 * v, .05)

        b.grid("bunting", mat("fabric", "C97C66", .85), 2, 3, flag)


STYLES = [style_01, style_02, style_03, style_04, style_05, style_06, style_07, style_08, style_09, style_10]


def build(index, style):
    window = bpy.context.window
    if window is None:
        # Headless: there is no window to switch scenes on, so build in the
        # factory scene and empty it afterwards.
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MATS.clear()
        b = Build(bpy.context.scene)
        style(b)
        return b.finish(f"curtains_{index:02d}")
    scene = bpy.data.scenes.new(f"curtains_{index:02d}")
    previous = window.scene
    window.scene = scene
    MATS.clear()
    try:
        b = Build(scene)
        style(b)
        return b.finish(f"curtains_{index:02d}")
    finally:
        for o in list(scene.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        window.scene = previous
        bpy.data.scenes.remove(scene)
        for me in list(bpy.data.meshes):
            if me.users == 0:
                bpy.data.meshes.remove(me)
        for m in list(bpy.data.materials):
            if m.users == 0 and m.name in ROLE:
                bpy.data.materials.remove(m)
        ROLE.clear()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    return [build(i + 1, s) for i, s in enumerate(STYLES)]


if __name__ == "__main__" or bpy.app.background:
    print("\n".join(main()))
