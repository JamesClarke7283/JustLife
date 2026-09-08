extends SceneTree

var checks := 0
var errors: Array[String] = []
var report := {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)

func mesh_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for descendant in node.find_children("*", "MeshInstance3D", true, false):
		var instance := descendant as MeshInstance3D
		var box := instance.global_transform * instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func run() -> void:
	for id in ["serving", "plate", "fork"]:
		var packed := load("res://assets/models/meal_" + id + ".glb") as PackedScene
		check(packed != null, id + " imported through Godot as PackedScene")
		if packed == null: continue
		var model := packed.instantiate() as Node3D
		root.add_child(model)
		var bounds := mesh_bounds(model)
		var node_names: Array = []
		var mesh_count := 0
		var surfaces := 0
		var vertices := 0
		var triangles := 0
		for node in model.find_children("*", "", true, false):
			node_names.append(str(node.name))
			if node is MeshInstance3D:
				mesh_count += 1
				surfaces += node.mesh.get_surface_count()
				for surface in range(node.mesh.get_surface_count()):
					vertices += node.mesh.surface_get_array_len(surface)
					triangles += node.mesh.surface_get_array_index_len(surface) / 3
		var entry := {"root": str(model.name), "nodes": node_names, "bounds_min": xyz(bounds.position),
			"bounds_size": xyz(bounds.size), "mesh_count": mesh_count, "material_surfaces": surfaces,
			"vertices": vertices, "triangles": triangles}
		check(bounds.size.is_finite() and bounds.size.length() > .1, id + " has finite metre-scale geometry")
		check(mesh_count <= 2 and surfaces <= 16, id + " batches geometry into practical draw surfaces")
		if id != "fork":
			check(abs(bounds.position.y) < .0002, id + " bottom contacts y=0")
			check(abs(bounds.size.x - (.50 if id == "serving" else .30)) < .004, id + " width matches serving/table scale")
			var food := model.find_child("Food", true, false) as Node3D
			check(food != null, id + " exposes exact Food node")
			var dish := model.find_child("DishGeometry", true, false) as MeshInstance3D
			check(dish != null and not food.is_ancestor_of(dish), id + " ceramic is outside consumable Food subtree")
			if food != null:
				entry["food_pivot"] = xyz(food.global_position)
				var original_dish := dish.global_transform
				food.scale.y = .1
				food.hide()
				check(dish.is_visible_in_tree() and dish.global_transform == original_dish, id + " shrinking/hiding food preserves ceramic")
		else:
			var grip := model.find_child("Grip", true, false) as Node3D
			var bite := model.find_child("BitePoint", true, false) as Node3D
			check(grip != null and bite != null, "Fork has exact grip and bite marker nodes")
			if grip != null and bite != null:
				entry["grip"] = xyz(grip.global_position)
				entry["bite"] = xyz(bite.global_position)
				check(grip.global_position.length() < .00001, "Fork grip is at canonical origin")
				check(bite.global_position.is_equal_approx(Vector3(0, .003, -.14)), "Fork bite marker points toward Godot -Z at14cm")
				check(abs(bounds.position.z + .14) < .001, "Real tine geometry reaches the bite marker")
		report[id] = entry
		model.free()
	report["checks"] = checks
	report["errors"] = errors
	var file := FileAccess.open("user://meal_import_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("MEAL_IMPORT %d checks, %d failures" % [checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
