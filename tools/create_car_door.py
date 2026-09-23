"""Author the swinging car door used when Lifelets get into the shared car.

The Juniper car body is one sculpted shell, so the door that opens is its own
model: a leaf on a hinge that LifeCarEntry places over the body's door line and
swings, plus the dark doorway it reveals.

glTF/Godot axes: x outward from the car side, y up, z toward the car's front.
  Hinge   empty at the origin (the door's front edge); rotate it about y.
  Tint    outer skin, recoloured to the car's paint, x 0 .. +0.025.
  Frame   window frame set 0.11 m inboard to follow the cabin's tumblehome.
  Glass   the door's window.
  Handle  pull handle near the rear edge at beltline height.
  Trim    inner door card.
  Opening the dark doorway, a sibling of Hinge so it stays put while the leaf
          swings; shown only while the door is open.
The leaf runs 1.1 m rearward (z 0 .. -1.1); a shorter door scales z.

Run headless:  blender --background --python tools/create_car_door.py
Run live (Blender MCP): exec the file; it builds in its own scene.
"""
import bpy, bmesh, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "car_door.glb"
LENGTH = 1.1
LOW, BELT, TOP = .32, .95, 1.50
INBOARD = .11


def gl(x, y, z):
    return (x, -z, y)


def material(name, hexcolor, rough=.5, metal=0.0, alpha=1.0):
    rgb = [int(hexcolor[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    return m


def box(scene, name, mat, lo, hi, parent):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    s = [hi[i] - lo[i] for i in range(3)]
    for v in bm.verts:
        g = (c[0] + v.co.x * s[0], c[1] + v.co.y * s[1], c[2] + v.co.z * s[2])
        v.co = gl(*g)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    o = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(o)
    o.parent = parent
    return o


def build(scene):
    paint = material("Tint", "4A6B5C", .35, .2)
    dark = material("door_trim", "2F3437", .8)
    chrome = material("door_chrome", "C9CDD0", .25, .9)
    glass = material("door_glass", "B7CFD3", .05, 0.0, .35)
    void = material("door_opening", "15191B", .95)
    root = bpy.data.objects.new("car_door", None)
    scene.collection.objects.link(root)
    hinge = bpy.data.objects.new("Hinge", None)
    scene.collection.objects.link(hinge)
    hinge.parent = root
    # Skin, split into the parts one joined Tint mesh needs.
    skin = [box(scene, "Tint", paint, (0, LOW, -LENGTH), (.025, BELT, 0), hinge)]
    frame = [
        box(scene, "Frame", paint, (-INBOARD - .02, TOP - .04, -LENGTH + .08), (-INBOARD + .02, TOP, -.02), hinge),
        box(scene, "Frame", paint, (-INBOARD - .02, BELT, -.06), (-INBOARD + .02, TOP, -.02), hinge),
        box(scene, "Frame", paint, (-INBOARD - .02, BELT, -LENGTH + .08), (-INBOARD + .02, TOP, -LENGTH + .12), hinge),
        box(scene, "Frame", paint, (-INBOARD - .01, BELT - .02, -LENGTH), (.02, BELT + .02, 0), hinge),
    ]
    box(scene, "Glass", glass, (-INBOARD - .005, BELT + .02, -LENGTH + .12), (-INBOARD + .005, TOP - .04, -.06), hinge)
    box(scene, "Handle", chrome, (.025, BELT - .05, -LENGTH + .08), (.045, BELT - .02, -LENGTH + .26), hinge)
    box(scene, "Trim", dark, (-.05, LOW + .03, -LENGTH + .03), (0, BELT - .02, -.03), hinge)
    box(scene, "Opening", void, (-.03, LOW + .02, -LENGTH + .02), (-.005, TOP - .03, -.02), root)
    # One Tint mesh for the catalogue-style recolour.
    parts = skin + frame
    with bpy.context.temp_override(active_object=parts[0], selected_editable_objects=parts, selected_objects=parts, scene=scene):
        bpy.ops.object.join()
    parts[0].name = "Tint"
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", use_active_scene=True)
    return str(OUT)


def main():
    window = bpy.context.window
    if window is None:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        return build(bpy.context.scene)
    scene = bpy.data.scenes.new("car_door")
    previous = window.scene
    window.scene = scene
    try:
        return build(scene)
    finally:
        for o in list(scene.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        window.scene = previous
        bpy.data.scenes.remove(scene)
        for me in list(bpy.data.meshes):
            if me.users == 0:
                bpy.data.meshes.remove(me)
        for m in list(bpy.data.materials):
            if m.users == 0 and m.name.split(".")[0] in ("Tint", "door_trim", "door_chrome", "door_glass", "door_opening"):
                bpy.data.materials.remove(m)


if __name__ == "__main__" or bpy.app.background:
    print(main())
