extends SceneTree
## Run in the isolated project prepared by verify_hair_assets.py.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func collect(node: Node, output: Dictionary) -> void:
	if node is MeshInstance3D and not str(node.name).begins_with("Hair_Bob") and not str(node.name).begins_with("Hair_Curls"):
		output[str(node.name)] = node
	for child in node.get_children():
		collect(child, output)

func skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := skeleton(child)
		if found != null:
			return found
	return null

func hair_metadata(node: Node) -> Dictionary:
	var metadata: Dictionary = node.get_meta("extras", {})
	if metadata.has("hair_revision"):
		return metadata
	for child in node.get_children():
		var found := hair_metadata(child)
		if not found.is_empty():
			return found
	return {}

func _run() -> void:
	for age in ["adult", "child"]:
		var baseline: Node3D = load("res://models/" + age + "_v18.glb").instantiate()
		var candidate: Node3D = load("res://models/" + age + "_candidate.glb").instantiate()
		root.add_child(baseline)
		root.add_child(candidate)
		var metadata := hair_metadata(candidate)
		check(metadata.get("hair_revision", 0) == 19, age + " hair revision")
		check(metadata.get("hair_study_revision", 0) == 14, age + " study revision")
		var old_rig := skeleton(baseline)
		var new_rig := skeleton(candidate)
		check(old_rig != null and new_rig != null, age + " skeletons present")
		if old_rig != null and new_rig != null:
			check(old_rig.get_bone_count() == new_rig.get_bone_count(), age + " bone count")
			for index in old_rig.get_bone_count():
				check(old_rig.get_bone_name(index) == new_rig.get_bone_name(index), age + " bone name " + str(index))
				check(old_rig.get_bone_global_rest(index).is_equal_approx(new_rig.get_bone_global_rest(index)), age + " bone rest " + str(index))
		var old_meshes := {}
		var new_meshes := {}
		collect(baseline, old_meshes)
		collect(candidate, new_meshes)
		check(old_meshes.size() == new_meshes.size(), age + " non-hair mesh count")
		for mesh_name in old_meshes:
			check(new_meshes.has(mesh_name), age + " retained " + mesh_name)
			if not new_meshes.has(mesh_name):
				continue
			var old_instance: MeshInstance3D = old_meshes[mesh_name]
			var new_instance: MeshInstance3D = new_meshes[mesh_name]
			check(old_instance.transform.is_equal_approx(new_instance.transform), age + " mesh transform " + mesh_name)
			check(old_instance.get_blend_shape_count() == new_instance.get_blend_shape_count(), age + " morph count " + mesh_name)
			for index in new_instance.get_blend_shape_count():
				check(old_instance.mesh.get_blend_shape_name(index) == new_instance.mesh.get_blend_shape_name(index), age + " morph name " + mesh_name)
				check(is_zero_approx(new_instance.get_blend_shape_value(index)), age + " neutral morph " + mesh_name)
			check(old_instance.mesh.get_surface_count() == new_instance.mesh.get_surface_count(), age + " surface count " + mesh_name)
			for surface in mini(old_instance.mesh.get_surface_count(), new_instance.mesh.get_surface_count()):
				var old_arrays := old_instance.mesh.surface_get_arrays(surface)
				var new_arrays := new_instance.mesh.surface_get_arrays(surface)
				for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
					check(old_arrays[attribute] == new_arrays[attribute], age + " imported geometry/skin " + mesh_name + ":" + str(attribute))
		baseline.free()
		candidate.free()
	print("HAIR_ASSET_CHECKS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
