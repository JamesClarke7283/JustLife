"""Author baby transport, curtains, and an adult playground slide.

Exports glTF into assets/models/ the way other JustLife creators do.

Run: blender --background --python tools/create_family_extras.py
"""
import bpy, math, pathlib
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models"
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
M = {}

def mat(name, hexcolor, rough=.62, metal=0):
    rgb = [int(hexcolor[i:i+2], 16) / 255 for i in (0, 2, 4)]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Roughness"].default_value = rough
    if metal:
        b.inputs["Metallic"].default_value = metal
    M[name] = m
    return m

for n, h in [
    ("oak", "AB7951"), ("cream", "EFE9DA"), ("coral", "C97C66"), ("teal", "417A71"),
    ("steel", "B9BEC2"), ("dark", "263E3C"), ("linen", "DECFAF"), ("sky", "9EC1CF"),
    ("rose", "D9A0A0"), ("graphite", "4A4F55"), ("mustard", "C9A05A"), ("blue", "6F8FA8"),
]:
    mat(n, h)
mat("tint", "C97C66")  # catalogue Tint surface

active = []

def xyz(p):
    return (p[0], -p[2], p[1])

def finish(o, n, m):
    o.name = n
    o.data.materials.append(M[m])
    active.append(o)
    return o

def box(n, p, s, m, bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o = bpy.context.object
    o.dimensions = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b = o.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        b.limit_method = "ANGLE"
    return finish(o, n, m)

def cyl(n, p, r, h, m):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=xyz(p))
    o = bpy.context.object
    return finish(o, n, m)

def clear():
    global active
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    active = []

def export_family(kind):
    # Parent under an empty named like other catalogue exports.
    root = bpy.data.objects.new(kind, None)
    bpy.context.collection.objects.link(root)
    for o in active:
        o.parent = root
    # Mark primary tint mesh for catalogue colouring.
    for o in active:
        if "Tint" in o.name or o.name.endswith("_tint"):
            if o.data.materials:
                o.data.materials[0].name = "Tint"
    path = OUT / f"{kind}.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=False)
    print("exported", path)
    clear()

def pram():
    box("Body_tint", (0, .42, 0), (.72, .28, .48), "tint")
    box("Hood", (0, .62, -.08), (.7, .22, .36), "cream")
    cyl("Wheel_FL", (-.28, .12, .22), .11, .05, "dark")
    cyl("Wheel_FR", (.28, .12, .22), .11, .05, "dark")
    cyl("Wheel_BL", (-.28, .12, -.22), .11, .05, "dark")
    cyl("Wheel_BR", (.28, .12, -.22), .11, .05, "dark")
    box("Handle", (0, .95, -.28), (.55, .04, .04), "steel")
    export_family("baby_pram")

def pushchair():
    box("Seat_tint", (0, .55, .02), (.42, .12, .38), "tint")
    box("Back", (0, .72, -.14), (.4, .32, .06), "blue")
    box("Footrest", (0, .38, .18), (.36, .04, .16), "steel")
    cyl("Wheel_FL", (-.2, .1, .18), .09, .04, "dark")
    cyl("Wheel_FR", (.2, .1, .18), .09, .04, "dark")
    cyl("Wheel_BL", (-.2, .1, -.18), .09, .04, "dark")
    cyl("Wheel_BR", (.2, .1, -.18), .09, .04, "dark")
    box("Handle", (0, 1.0, -.22), (.4, .03, .03), "steel")
    export_family("pushchair")

def baby_car_seat():
    box("Base_tint", (0, .12, 0), (.42, .12, .42), "tint")
    box("Shell", (0, .38, -.02), (.4, .4, .38), "coral")
    box("Cushion", (0, .28, .04), (.3, .12, .28), "cream")
    export_family("baby_car_seat")

def child_car_seat():
    box("Base_tint", (0, .14, 0), (.46, .14, .44), "tint")
    box("Back", (0, .5, -.16), (.42, .55, .08), "teal")
    box("Seat", (0, .28, .04), (.4, .1, .32), "cream")
    box("Arm_L", (-.2, .38, .02), (.05, .18, .28), "steel")
    box("Arm_R", (.2, .38, .02), (.05, .18, .28), "steel")
    export_family("child_car_seat")

def curtains():
    # Two hanging panels with a rod — snaps over windows as wall-mounted decor.
    box("Rod", (0, 1.5, 0), (1.35, .04, .04), "steel")
    box("Panel_L_tint", (-.34, .75, .02), (.55, 1.4, .04), "tint")
    box("Panel_R", (.34, .75, .02), (.55, 1.4, .04), "linen")
    export_family("curtains")

def adult_slide():
    box("Ladder_L", (-.35, 1.0, -.9), (.08, 2.0, .08), "steel")
    box("Ladder_R", (.35, 1.0, -.9), (.08, 2.0, .08), "steel")
    for i in range(5):
        box(f"Rung_{i}", (0, .3 + i * .35, -.9), (.7, .05, .05), "oak")
    box("Platform", (0, 1.9, -.55), (.9, .08, .5), "oak")
    # Sloped chute approximated as stepped boxes.
    for i in range(6):
        t = i / 5.0
        box(f"Chute_{i}_tint", (0, 1.7 - t * 1.5, -.2 + t * 1.4), (.7, .08, .35), "tint")
    export_family("adult_slide")

def toy_chest():
    box("Chest_tint", (0, .35, 0), (.9, .55, .55), "tint")
    box("Lid", (0, .66, -.05), (.92, .08, .58), "oak")
    export_family("toy_chest")

if __name__ == "__main__":
    clear()
    pram()
    pushchair()
    baby_car_seat()
    child_car_seat()
    curtains()
    adult_slide()
    toy_chest()
    print("family extras done")
