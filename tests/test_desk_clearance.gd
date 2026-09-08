extends "res://tests/test_school_presentation.gd"
## Focused rerender after desk-clearance changes. No repeated progression/save run.

func _run() -> void:
	screenshot_dir = "res://art/desk_clearance"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene = app
	await frames(4);app.set_sound(false)
	await _create_school_household()
	await press("School record",true);await press("Online classes")
	await press("▶")
	if await wait_until(func()->bool:return active_is("school",.065),"actual child route and settled class pose",45):
		await _school_pose("20_child_desk_clearance")
		var joints: Dictionary = {}
		for side: String in ["L","R"]:
			joints["shoulder_"+side] = str(app.player._joints["Arm_"+side].global_position)
			joints["elbow_"+side] = str(app.player._joints["Forearm_"+side].global_position)
			joints["palm_"+side] = str(app.player._joints["Forearm_"+side].to_global(app.player._palm_offset(side)))
		evidence.append({"joints":joints,"activity":app.sim.get_current_action().duplicate(true),"display_height":app.player.get_display_height()})
	await press("Ⅱ")
	var support_before: int = _visible_boosters()
	await press("Cancel action")
	check(app.sim.action_queue.is_empty() and app.sim.education.attended == 0,"Canceling the inspected partial class clears it without attendance credit.")
	await frames(6)
	check(support_before == 1 and _visible_boosters() == 1 and app.player._sit_amount > .99,"Paused cancel retains the visible booster under the frozen seated child.")
	var at: Vector3 = app.player.position+Vector3(0,.86,0)
	app.world.camera.size = 2.5
	app.world.camera.position = at+Vector3(-2.8,.8,.10)
	app.world.camera.look_at(at,Vector3.UP)
	await screenshot("21_paused_cancel_support",false,false)
	await press("▶")
	await create_timer(1.0).timeout
	await press("Ⅱ")
	check(_visible_boosters() == 0 and app.player._sit_amount < .05,"Resuming after cancel releases the temporary booster as the child leaves the seated pose.")
	await screenshot("22_resumed_cancel_support_released",false,false)
	_write_report()
	app.queue_free();await frames(3)
	print("DESK_CLEARANCE_RESULT assertions=%d failures=%d" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _visible_boosters() -> int:
	var count: int = 0
	for booster: Node3D in app.world._desk_boosters.values():
		if is_instance_valid(booster) and booster.is_visible_in_tree():count += 1
	return count
