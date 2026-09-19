extends "res://tests/test_school_playthrough.gd"
## Bounded rendered follow-up: true keyboard contact and birthday stages.
## Uses actual public flow; scene/actor transforms are only read, camera inspected.

func _run() -> void:
	screenshot_dir = "res://art/school_presentation"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene = app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(member_id: String,action: Dictionary):member_completed.append(member_id + ":" + str(action.id)))
	await _create_school_household()
	check(_visible_text_contains("Get a snack from the fridge."),"Child starts with a visibly attainable snack want.")
	check(not _visible_text_contains("Cook your first fresh meal."),"Child's pinned first want no longer asks for unavailable cooking.")
	await screenshot("15_attainable_child_want")
	await _school_activities()
	await press("School record",true)
	check(_visible_text_contains("1 class attended") and _visible_text_contains("1 assignment") and not _visible_text_contains("1 classes") and not _visible_text_contains("1 assignments"),"One completed class and assignment use singular wording in the public record.")
	await screenshot("16_correct_singular_record")
	await press("Back to life")
	await _birthday_details()
	_write_report()
	app.queue_free();await frames(3)
	print("SCHOOL_PRESENTATION_RESULT assertions=%d failures=%d" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _school_pose(label_text: String) -> void:
	await press("Ⅱ")
	var old_transform: Transform3D = app.world.camera.transform
	var old_size: float = app.world.camera.size
	var at: Vector3 = app.player.position+Vector3(0,.86,0)
	var yaw: float = float(app.player._activity_anchor.yaw)
	var facing: Basis = Basis(Vector3.UP,yaw)
	var palms: Dictionary = {}
	var errors: Dictionary = {}
	for side: String in ["L","R"]:
		var palm: Vector3 = app.player._joints["Forearm_"+side].to_global(app.player._palm_offset(side))
		var target: Vector3 = app.player._activity_anchor.hand_center+facing*Vector3((-.105 if side == "L" else .105),0,0)
		palms[side] = str(palm);errors[side] = palm.distance_to(target)
		check(float(errors[side]) < .04,label_text+": "+side+" palm reaches within4cm of its actual world keyboard target.")
	evidence.append({"capture":label_text,"anchor":str(app.player._activity_anchor),"palms":palms,"palm_errors_m":errors,"visual_transform":str(app.player.visual.global_transform),"model":app.player._model.scene_file_path})
	for angle: String in ["over_shoulder","side"]:
		app.world.camera.size = 2.5
		app.world.camera.position = at+facing*(Vector3(-1.3,1.05,-1.8) if angle == "over_shoulder" else Vector3(-2.8,.8,.10))
		app.world.camera.look_at(at,Vector3.UP)
		await screenshot(label_text+"_"+angle,false,false)
	app.world.camera.transform = old_transform;app.world.camera.size = old_size
	await press("▶")

func _birthday_details() -> void:
	await press("My Lifelet")
	await press("Celebrate a birthday")
	await press("Celebrate · ℒ30")
	await press("▶")
	for phase: Dictionary in _birthday_phases():
		if not await wait_until(func()->bool:return active_is("birthday") and app.player._motion_action == "birthday" and app.player._action_time >= float(phase.time),str(phase.label),45):continue
		await press("Ⅱ")
		check(app.player._birthday_cake.is_visible_in_tree() == bool(phase.cake),str(phase.label)+": actual birthday prop visibility matches its phase.")
		var visible_flames: int = 0
		for flame: Node3D in app.player._cake_flames:
			if flame.is_visible_in_tree():visible_flames += 1
		check((visible_flames > 0) == bool(phase.flames),str(phase.label)+": candle flames visibly change for blowing out.")
		var old_transform: Transform3D = app.world.camera.transform
		var old_size: float = app.world.camera.size
		var facing: Basis = app.player.visual.global_basis.orthonormalized()
		var at: Vector3 = app.player.position+Vector3(0,.83,0)
		app.world.camera.size = 2.45
		app.world.camera.position = at+Vector3(2.4,1.1,1.3)
		app.world.camera.look_at(at,Vector3.UP)
		await screenshot(str(phase.label),false,false)
		evidence.append({"capture":phase.label,"action_time":app.player._action_time,"visible_flames":visible_flames,"cake_visible":app.player._birthday_cake.is_visible_in_tree(),"cake_position":str(app.player._birthday_cake.global_position)})
		app.world.camera.transform = old_transform;app.world.camera.size = old_size
		await press("▶")
	await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"birthday completes after visible phases",20)
	await press("Ⅱ")
	check(app.sim.character.age_stage == "teen" and member_completed.has("player:birthday"),"Actual birthday still completes after visible blow-out and applause phases.")

func _birthday_phases() -> Array:
	return [{"label":"17_cake_blow","time":2.55,"cake":true,"flames":true},{"label":"18_candles_out","time":3.40,"cake":true,"flames":false},{"label":"19_birthday_applause","time":4.80,"cake":false,"flames":false}]
