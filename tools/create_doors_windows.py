"""Author five house-door and five house-window styles for the Build catalogue.

Each style is `assets/models/house_door_<a..e>.glb` or `house_window_<a..e>.glb`.
Colours recolour the `Tint` surface at runtime (LifeCatalogVariants).

Art contract (glTF/Godot: x across, y up, z into the room):
  Door:  origin on the floor at the wall face; leaf ~0.96×2.1 m, thickness ~0.05.
  Window: origin at sill centre; frame ~1.76×1.4 m matching window_panel aperture.

Run headless: blender --background --python tools/create_doors_windows.py
Run live (Blender MCP): exec this file.
"""
import bpy
import bmesh
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models"


def gl(x, y, z):
    return (x, -z, y)


def material(name, hexcolor, rough=0.55, metal=0.0, alpha=1.0):
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


def fresh_scene(name):
    scene = bpy.data.scenes.new(name)
    for obj in list(scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
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


def export(scene, path):
    bpy.context.window.scene = scene if bpy.context.window else scene
    # Prefer active scene export; fall back to explicit scene objects.
    for obj in scene.objects:
        obj.select_set(True)
    root = next((o for o in scene.objects if o.parent is None and o.type == "EMPTY"), None)
    if root:
        bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )


def build_door(style, scene):
    tint = material("Tint", "8faf9f", 0.45, 0.05)
    hard = material("door_hardware", "c9cdd0", 0.25, 0.85)
    glass = material("door_glass", "b7cfd3", 0.05, 0.0, 0.3)
    root = bpy.data.objects.new(f"house_door_{style}", None)
    scene.collection.objects.link(root)
    parts = []
    # Shared slab.
    parts.append(box(scene, "Tint", tint, (-0.48, 0.02, -0.02), (0.48, 2.08, 0.04), root))
    if style == "a":
        # Flat slab with simple panels.
        parts.append(box(scene, "Tint", tint, (-0.38, 1.15, 0.04), (0.38, 1.95, 0.055), root))
        parts.append(box(scene, "Tint", tint, (-0.38, 0.15, 0.04), (0.38, 0.95, 0.055), root))
    elif style == "b":
        # Half-lite glass upper.
        parts.append(box(scene, "Tint", tint, (-0.38, 0.12, 0.04), (0.38, 1.05, 0.055), root))
        box(scene, "Glass", glass, (-0.36, 1.15, 0.01), (0.36, 1.95, 0.03), root)
        parts.append(box(scene, "Tint", tint, (-0.4, 1.1, 0.04), (0.4, 1.18, 0.06), root))
        parts.append(box(scene, "Tint", tint, (-0.4, 1.92, 0.04), (0.4, 2.0, 0.06), root))
    elif style == "c":
        # Arched top rail suggestion via stepped head.
        parts.append(box(scene, "Tint", tint, (-0.42, 1.85, 0.04), (0.42, 2.08, 0.06), root))
        parts.append(box(scene, "Tint", tint, (-0.3, 1.2, 0.04), (0.3, 1.75, 0.055), root))
        parts.append(box(scene, "Tint", tint, (-0.36, 0.15, 0.04), (0.36, 1.05, 0.055), root))
    elif style == "d":
        # Four-panel cottage.
        for y0, y1 in ((0.15, 0.95), (1.1, 1.9)):
            for x0, x1 in ((-0.38, -0.04), (0.04, 0.38)):
                parts.append(box(scene, "Tint", tint, (x0, y0, 0.04), (x1, y1, 0.055), root))
    else:
        # French double-lite look on one leaf.
        box(scene, "Glass", glass, (-0.36, 0.35, 0.01), (0.36, 1.85, 0.03), root)
        for y in (0.3, 1.05, 1.8):
            parts.append(box(scene, "Tint", tint, (-0.4, y, 0.04), (0.4, y + 0.06, 0.06), root))
        parts.append(box(scene, "Tint", tint, (-0.02, 0.3, 0.04), (0.02, 1.9, 0.06), root))
    box(scene, "Handle", hard, (0.32, 0.95, 0.04), (0.4, 1.05, 0.08), root)
    join_tint(parts)
    return root


def build_window(style, scene):
    tint = material("Tint", "efeadb", 0.5)
    glass = material("window_glass", "b7cfd3", 0.05, 0.0, 0.22)
    root = bpy.data.objects.new(f"house_window_{style}", None)
    scene.collection.objects.link(root)
    # Match window_panel aperture ~1.76 × 1.38, origin at centre of pane.
    hw, hh = 0.88, 0.69
    parts = []
    # Outer frame.
    parts.append(box(scene, "Tint", tint, (-hw - 0.06, -hh - 0.06, -0.04), (hw + 0.06, -hh, 0.04), root))
    parts.append(box(scene, "Tint", tint, (-hw - 0.06, hh, -0.04), (hw + 0.06, hh + 0.06, 0.04), root))
    parts.append(box(scene, "Tint", tint, (-hw - 0.06, -hh, -0.04), (-hw, hh, 0.04), root))
    parts.append(box(scene, "Tint", tint, (hw, -hh, -0.04), (hw + 0.06, hh, 0.04), root))
    box(scene, "Glass", glass, (-hw + 0.02, -hh + 0.02, -0.01), (hw - 0.02, hh - 0.02, 0.01), root)
    if style == "a":
        # Cross muntin.
        parts.append(box(scene, "Tint", tint, (-0.03, -hh, -0.02), (0.03, hh, 0.03), root))
        parts.append(box(scene, "Tint", tint, (-hw, -0.03, -0.02), (hw, 0.03, 0.03), root))
    elif style == "b":
        # Two vertical lites.
        parts.append(box(scene, "Tint", tint, (-0.03, -hh, -0.02), (0.03, hh, 0.03), root))
    elif style == "c":
        # Six-pane grid.
        for x in (-hw / 3, hw / 3):
            parts.append(box(scene, "Tint", tint, (x - 0.02, -hh, -0.02), (x + 0.02, hh, 0.03), root))
        for y in (-hh / 3, hh / 3):
            parts.append(box(scene, "Tint", tint, (-hw, y - 0.02, -0.02), (hw, y + 0.02, 0.03), root))
    elif style == "d":
        # Arch bar across the top third.
        parts.append(box(scene, "Tint", tint, (-hw, hh / 3 - 0.02, -0.02), (hw, hh / 3 + 0.02, 0.03), root))
        parts.append(box(scene, "Tint", tint, (-0.03, hh / 3, -0.02), (0.03, hh, 0.03), root))
    else:
        # Wide picture window: thick outer only (already built) + sill ledge.
        parts.append(box(scene, "Tint", tint, (-hw - 0.08, -hh - 0.1, -0.02), (hw + 0.08, -hh - 0.04, 0.08), root))
    join_tint(parts)
    return root


def main():
    written = []
    # Keep the user's open file intact: build in throwaway scenes.
    for style in "abcde":
        scene = fresh_scene(f"door_{style}")
        build_door(style, scene)
        path = OUT / f"house_door_{style}.glb"
        # Export by temporarily making this the context scene.
        prev = bpy.context.window.scene if bpy.context.window else None
        if bpy.context.window:
            bpy.context.window.scene = scene
        for obj in bpy.data.objects:
            obj.select_set(obj.name in [o.name for o in scene.objects])
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_active_scene=True)
        if prev is not None:
            bpy.context.window.scene = prev
        written.append(str(path))
        # Remove throwaway scene data.
        for obj in list(scene.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.scenes.remove(scene)

    for style in "abcde":
        scene = fresh_scene(f"window_{style}")
        build_window(style, scene)
        path = OUT / f"house_window_{style}.glb"
        prev = bpy.context.window.scene if bpy.context.window else None
        if bpy.context.window:
            bpy.context.window.scene = scene
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_active_scene=True)
        if prev is not None:
            bpy.context.window.scene = prev
        written.append(str(path))
        for obj in list(scene.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.scenes.remove(scene)

    return {"written": written, "count": len(written)}


result = main()
