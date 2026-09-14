extends SceneTree

func _initialize() -> void:
	if OS.get_environment("JUSTLIFE_BOB_IMPORT_ISOLATED") != "1":
		push_error("Run tools/bob_v62/run_import_inspection.py; this probe must not run in the live project.")
		quit(1)
		return
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var file := ProjectSettings.globalize_path("res://art/experiments/bob_v62/strands_ready_models/character.glb")
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		file = arguments[0]
	assert(document.append_from_file(file, state) == OK)
	var scene := document.generate_scene(state)
	var inspected := []
	for child in scene.find_children("Hair_Bob_*", "MeshInstance3D", true, false):
		var mesh: Mesh = child.mesh
		for surface in range(mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.surface_get_material(surface)
			var arrays := mesh.surface_get_arrays(surface)
			var has_tangents: bool = arrays[Mesh.ARRAY_TANGENT] != null and arrays[Mesh.ARRAY_TANGENT].size() > 0
			assert(material.normal_enabled and material.normal_texture != null)
			assert(material.albedo_texture != null and material.roughness_texture != null)
			assert(has_tangents)
			inspected.append({"node": child.name, "material": material.resource_name,
				"normal_enabled": material.normal_enabled, "normal_scale": material.normal_scale,
				"roughness_texture": true, "generated_tangents": has_tangents})
	assert(inspected.size() == 4)
	print("BOB_IMPORT_VERIFIED ", JSON.stringify(inspected))
	scene.free()
	quit()
