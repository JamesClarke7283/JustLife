extends SceneTree
var checks: int = 0
var failures: Array[String] = []

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures.append(detail)
		push_error(detail)

func bounds(node: Node3D) -> AABB:
	var result: AABB
	var first: bool = true
	for part: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var current: AABB = part.global_transform * part.get_aabb()
		result = current if first else result.merge(current)
		first = false
	return result

func run() -> void:
	var new_recipes: Array[String] = ["grilled_cheese", "garden_salad", "pancake_stack", "sunday_roast", "layer_cake"]
	for recipe: String in new_recipes:
		for size: String in ["serving", "plate"]:
			var id: String = recipe + "_" + size
			var packed: PackedScene = load("res://assets/models/meal_" + id + ".glb")
			check(packed != null, id + " imports as PackedScene")
			if packed == null: continue
			var model: Node3D = packed.instantiate()
			root.add_child(model)
			var box: AABB = bounds(model)
			check(box.position.is_finite() and box.size.is_finite(), id + " bounds are finite")
			check(absf(box.position.y) < 0.0001, id + " actual underside is Godot Y=0 (got " + str(box.position.y) + ")")
			check(box.size.x <= (0.50 if size == "serving" else 0.30) + 0.0001, id + " stays within width (got " + str(box.size.x) + ")")
			check(box.size.z <= (0.335 if size == "serving" else 0.30) + 0.0001, id + " stays within depth (got " + str(box.size.z) + ")")
			var food: Node3D = model.find_child("Food", true, false)
			var dish: MeshInstance3D = model.find_child("DishGeometry", true, false)
			check(food != null and dish != null, id + " exposes named Food and DishGeometry")
			if food != null and dish != null:
				check(not food.is_ancestor_of(dish), id + " ceramic is outside Food subtree")
			var meshes: int = 0
			var surfaces: int = 0
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				meshes += 1
				surfaces += mesh.mesh.get_surface_count()
			check(meshes == 2 and surfaces <= 16, id + " is batched into two meshes with bounded materials (meshes=" + str(meshes) + ", surfaces=" + str(surfaces) + ")")
			if size == "serving":
				for side in ["Left", "Right"]:
					var marker: Node3D = model.find_child("Grip" + side, true, false)
					var expected_pos := Vector3(-0.2395 if side == "Left" else 0.2395, 0.046, 0)
					check(marker != null and marker.global_position.distance_to(expected_pos) < 0.0001, id + " preserves " + side + " grip")
			else:
				var marker: Node3D = model.find_child("Grip", true, false)
				var expected_pos := Vector3(0, 0.009, 0)
				check(marker != null and marker.global_position.distance_to(expected_pos) < 0.0001, id + " preserves plate grip")
			model.free()
	print("RECIPE_V64_IMPORT: %d checks, %d failures." % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("run")
