"""Render all 5 new JustLife recipes in Cycles studio setup."""
from pathlib import Path
import bpy, math
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "assets/models"
ART = ROOT / "art/recipes"
EVIDENCE = ART / "studio"
EVIDENCE.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

# Import all 5 servings and 5 plates in a neat showcase grid
recipes = ["grilled_cheese", "garden_salad", "pancake_stack", "sunday_roast", "layer_cake"]
for i, r in enumerate(recipes):
    # Serving row (back)
    p_serving = MODELS / ("meal_" + r + "_serving.glb")
    bpy.ops.import_scene.gltf(filepath=str(p_serving))
    root_s = bpy.context.selected_objects[0]
    while root_s.parent: root_s = root_s.parent
    root_s.location = ((i - 2) * 0.46, 0.22, 0)
    
    # Plate row (front)
    p_plate = MODELS / ("meal_" + r + "_plate.glb")
    bpy.ops.import_scene.gltf(filepath=str(p_plate))
    root_p = bpy.context.selected_objects[0]
    while root_p.parent: root_p = root_p.parent
    root_p.location = ((i - 2) * 0.46, -0.18, 0)

# Studio ground
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.001))
ground = bpy.context.object
g_mat = bpy.data.materials.new("StudioGround")
g_mat.use_nodes = True
g_mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.85, 0.82, 0.77, 1)
g_mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.75
ground.data.materials.append(g_mat)

# Camera
bpy.ops.object.camera_add(location=(0, -2.2, 1.8))
cam = bpy.context.object
cam.rotation_euler = (Vector((0, 0.05, 0.04)) - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.data.type = "ORTHO"
cam.data.ortho_scale = 2.5
scene.camera = cam

# Three-point lighting
for p, energy, size in [((-1.5, -1.2, 2.2), 120, 1.2), ((1.8, 0.4, 1.8), 85, 1.0), ((-0.2, 1.5, 1.6), 75, 1.0)]:
    bpy.ops.object.light_add(type="AREA", location=p)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 0.04)) - light.location).to_track_quat("-Z", "Y").to_euler()

scene.world = bpy.data.worlds.new("Warm recipe studio")
scene.world.use_nodes = True
scene.world.node_tree.nodes.get("Background").inputs[0].default_value = (0.32, 0.34, 0.33, 1)
scene.world.node_tree.nodes.get("Background").inputs[1].default_value = 0.5

scene.render.engine = "CYCLES"
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = -0.9
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(EVIDENCE / "recipe_v64_showcase.png")

bpy.ops.render.render(write_still=True)
print("SHOWCASE_RENDER_COMPLETE")
