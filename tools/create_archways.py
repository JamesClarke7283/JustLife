"""Author three open archway frames for the Build catalogue.

Each style is `assets/models/archway_<style>.glb`. The passage is empty so a
Lifelet walks through the frame. Colours recolour the Tint surface at runtime.

Styles: round, roman, tudor.

Run via Blender MCP (`exec` this file) or:
  blender --background --python tools/create_archways.py
"""
import bpy
import bmesh
import pathlib

ROOT = pathlib.Path("/home/impulse/Projects/JustLife")
OUT = ROOT / "assets" / "models"


def gl(x, y, z):
    return (x, -z, y)


def material(name, hexcolor, rough=0.55):
    rgb = [int(hexcolor[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Roughness"].default_value = rough
    return m


def box(scene, name, mat, lo, hi, parent):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    s = [max(0.01, hi[i] - lo[i]) for i in range(3)]
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


def fresh_scene(name):
    scene = bpy.data.scenes.new(name)
    return scene


def join_tint(parts):
    if not parts:
        return
    with bpy.context.temp_override(
        active_object=parts[0],
        selected_editable_objects=parts,
        selected_objects=parts,
    ):
        bpy.ops.object.join()
    parts[0].name = "Tint"


def build(style, scene):
    tint = material("Tint", "eae7d7", 0.62)
    root = bpy.data.objects.new(f"archway_{style}", None)
    scene.collection.objects.link(root)
    parts = []
    # Jambs leave a clear walkway about 0.96 m wide and 2.05 m tall.
    parts.append(box(scene, "Tint", tint, (-0.62, 0.0, -0.07), (-0.46, 2.15, 0.07), root))
    parts.append(box(scene, "Tint", tint, (0.46, 0.0, -0.07), (0.62, 2.15, 0.07), root))
    if style == "round":
        # Semicircular head built from short segments. The middle stays open.
        spring = 1.55
        radius = 0.54
        steps = 7
        import math
        for i in range(steps):
            a0 = math.pi * (i / steps)
            a1 = math.pi * ((i + 1) / steps)
            x0 = -radius * math.cos(a0)
            x1 = -radius * math.cos(a1)
            y0 = spring + radius * math.sin(a0)
            y1 = spring + radius * math.sin(a1)
            lo = (min(x0, x1) - 0.06, min(y0, y1) - 0.04, -0.07)
            hi = (max(x0, x1) + 0.06, max(y0, y1) + 0.06, 0.07)
            parts.append(box(scene, "Tint", tint, lo, hi, root))
    elif style == "roman":
        # Flat lintel, square opening.
        parts.append(box(scene, "Tint", tint, (-0.62, 2.05, -0.08), (0.62, 2.28, 0.08), root))
        parts.append(box(scene, "Tint", tint, (-0.5, 1.98, -0.05), (0.5, 2.06, 0.05), root))
    else:
        # Tudor point: two sloping rails meeting above the walkway.
        parts.append(box(scene, "Tint", tint, (-0.58, 1.9, -0.07), (-0.05, 2.05, 0.07), root))
        parts.append(box(scene, "Tint", tint, (0.05, 1.9, -0.07), (0.58, 2.05, 0.07), root))
        parts.append(box(scene, "Tint", tint, (-0.22, 2.02, -0.07), (0.0, 2.28, 0.07), root))
        parts.append(box(scene, "Tint", tint, (0.0, 2.02, -0.07), (0.22, 2.28, 0.07), root))
        parts.append(box(scene, "Tint", tint, (-0.1, 2.22, -0.07), (0.1, 2.42, 0.07), root))
    join_tint(parts)
    return root


def main():
    written = []
    for style in ("round", "roman", "tudor"):
        scene = fresh_scene(f"archway_{style}")
        build(style, scene)
        path = OUT / f"archway_{style}.glb"
        prev = bpy.context.window.scene if bpy.context.window else None
        if bpy.context.window:
            bpy.context.window.scene = scene
        for obj in bpy.data.objects:
            obj.select_set(obj.name in [o.name for o in scene.objects])
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_active_scene=True)
        if prev is not None:
            bpy.context.window.scene = prev
        written.append(str(path))
        for obj in list(scene.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.scenes.remove(scene)
    return {"written": written, "count": len(written)}


result = main()
