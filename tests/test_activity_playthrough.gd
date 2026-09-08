extends "res://tests/test_playthrough.gd"
## Actual normal-speed kitchen activities, prop transitions and pause review.
var pose_evidence: Array = []

func _run() -> void:
	screenshot_dir = "res://art/activity_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.set_sound(false)
	app.household.member_action_finished.connect(func(_id: String, action: Dictionary) -> void:completed.append(str(action.id)))
	await _enter_new_game()
	await press("Look")
	await press("Female")
	await press("Crop")
	await press("Wardrobe")
	await press("Casual")
	await press("Coastal")
	await press("Find my home", true)
	await press("Willow Cottage")
	await press("Start living", true)
	app.household.set_speed(0)
	app.sim.autonomy = false
	await _kitchen_action("cook", "stove", "01", 25)
	await _kitchen_action("snack", "fridge", "02", 8)
	await _cancellation_transition()
	var file := FileAccess.open(screenshot_dir.path_join("activity_diagnostics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(pose_evidence, "  "));file.close()
	_write_report()
	app.queue_free()
	await frames(3)
	print("ACTIVITY_RESULT assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _prop_state() -> Dictionary:
	var result: Dictionary = {"action":app.sim.get_current_action().duplicate(true),"speed":app.sim.speed,"time":app.player._action_time,"actor":vec(app.player.position),"visual":str(app.player.visual.transform),"props":{}}
	for key: String in ["_snack", "_cooking_bowl", "_cooking_spoon", "_bowl_center", "_spoon_tip"]:
		var node: Node3D = app.player.get(key)
		result.props[key] = {"visible":node.is_visible_in_tree(),"position":vec(node.global_position),"transform":str(node.global_transform)}
	return result

func _kitchen_action(action_id: String, furnishing: String, prefix: String, cost: int) -> void:
	var original_position: Vector3 = app.player.position
	var prior_funds: int = app.sim.funds
	await queue_via_menu(furnishing, action_id)
	await press("▶")
	check(app.sim.speed == 1, action_id + ": visible speed control selects normal time.")
	await frames(8)
	check(not app.player._cooking_bowl.is_visible_in_tree() and not app.player._snack.is_visible_in_tree(), action_id + ": props remain absent during approach.")
	if action_id == "cook":await screenshot(prefix + "a_normal_approach", false, false)
	if not await wait_until(func() -> bool: return active_is(action_id, 0.13), "real normal-speed approach to " + furnishing, 40):return
	check(app.player.position.distance_to(original_position) > 0.20, action_id + ": actual walking precedes activity.")
	check(app.sim.funds == prior_funds - cost, action_id + ": ingredients charged once on arrival.")
	check(app.player._cooking_bowl.is_visible_in_tree() if action_id == "cook" else app.player._snack.is_visible_in_tree(), action_id + ": held food or bowl appears during active performance.")
	pose_evidence.append(_prop_state())
	await screenshot(prefix + "b_normal_activity", true, false)
	if action_id == "snack":
		await wait_until(func() -> bool: return app.player._action_time >= 1.40, "normal-speed food reaches bite phase", 8)
	await press("Ⅱ")
	var paused: Dictionary = _prop_state()
	await create_timer(.45).timeout
	check(equivalent(_prop_state(), paused), action_id + ": pause holds game progress, body and held props exactly.")
	pose_evidence.append(paused)
	await screenshot(prefix + "c_paused_activity", true)
	var saved_angle: float = app.world.camera_angle
	app.world.camera_angle += PI / 2.0
	app.world.update_camera()
	await screenshot(prefix + "d_paused_side", true)
	app.world.camera_angle = saved_angle
	app.world.update_camera()
	await _close_detail(prefix + "d_contact_detail")
	await press("▶")
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "normal-speed completion of " + action_id, 20)
	await create_timer(.5).timeout
	check(completed.has(action_id), action_id + ": real frame processing emits completion.")
	check(not app.player._cooking_bowl.is_visible_in_tree() and not app.player._snack.is_visible_in_tree(), action_id + ": held props disappear after completing the activity.")
	await screenshot(prefix + "e_completed", true, false)
	app.household.set_speed(0)

func _close_detail(label_text: String) -> void:
	# Inspection camera stays inside the kitchen: the ordinary rotated overview
	# is retained above, where the exterior wall can hide the hands.
	var old_transform: Transform3D = app.world.camera.transform
	var old_size: float = app.world.camera.size
	app.world.camera.size = 3.5
	var body: Node3D = app.player.visual
	app.world.camera.position = body.global_position - body.global_basis.x.normalized() * 1.8 + Vector3.UP * 1.6 + body.global_basis.z.normalized() * .05
	app.world.camera.look_at(body.global_position + Vector3.UP * 1.15, Vector3.UP)
	await screenshot(label_text, false)
	app.world.camera.transform = old_transform
	app.world.camera.size = old_size

func _cancellation_transition() -> void:
	await queue_via_menu("stove", "cook")
	await press("▶")
	if not await wait_until(func() -> bool: return active_is("cook", .10), "second actual cook for cancellation", 30):return
	await press("Cancel action")
	await queue_via_menu("fridge", "snack")
	await frames(20)
	check(not app.player._cooking_bowl.is_visible_in_tree() and not app.player._cooking_spoon.is_visible_in_tree(), "Cancellation removes cooking props while routing to the next furnishing.")
	await screenshot("03_cancelled_cook_to_snack", true, false)
	await wait_until(func() -> bool: return active_is("snack", .25), "snack follows cancelled cook", 20)
	await press("Ⅱ")
	check(not app.player._cooking_bowl.is_visible_in_tree() and app.player._snack.is_visible_in_tree(), "Later snack has only its own food prop.")
	await screenshot("04_after_cancellation_snack", true)
