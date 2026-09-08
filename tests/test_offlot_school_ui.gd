extends "res://tests/test_school_playthrough.gd"
## Actual exit/return movement and fresh-process away persistence. No time,
## needs, arrival, attendance or action-completion mutation by this harness.

func _run() -> void:
	screenshot_dir="res://art/offlot_school"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.notice.connect(func(message:String):notices.append(message))
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):member_completed.append(id+":"+str(action.id)))
	if resume_only:await _restore_and_return()
	else:
		await _create_school_household()
		if not app.sim.action_queue.is_empty():await press("Cancel action")
		var origin:Vector3=app.player.position
		await press("Go to school")
		check(str(app.sim.get_current_action().get("id",""))=="school_day" and not app.sim.is_away(),"Go to school queues a visible departure before marking the pupil away.")
		await press("▶")
		if await wait_until(func()->bool:return app.player.position.distance_to(origin)>.8,"child actually walking out toward school",20):
			check(app.player.visible and not app.sim.is_away(),"The pupil stays rendered while walking to the street.")
			await screenshot("05_walking_to_school",false)
		if await wait_until(func()->bool:return app.sim.is_away(),"real school exit arrival",45):
			await press("Ⅱ")
			_check_away("departure")
			check(app.player.position.distance_to(app.world.lot_exit_position(0))<.02,"School begins only after the actual actor reaches its lot exit.")
			check(app.sim.education.attended==0,"Departure grants no premature attendance reward.")
			await screenshot("06_at_school_household",false,false)
			await press_member(ADULT_NAME)
			check(app.household.selected_id()=="housemate_1" and app.player.visible,"An at-home adult remains selectable while the child is at school.")
			await queue_via_menu("bookshelf","read")
			await press("▶")
			await wait_until(func()->bool:return active_is("read",.1),"adult performs a home activity while child stays away",40)
			await press("Ⅱ")
			check(app.household.member_sim("player").is_away() and not app.world.actors.player.visible,"Controlling the adult leaves the child's school session running and its body away.")
			await screenshot("06b_adult_at_home",false,false)
			await press_member(CHILD_NAME)
			_check_away("switching back")
			var expected:Dictionary={"away":app.sim.get_state().away_state,"education":app.sim.education.duplicate(true),"position":vec(app.player.position),"day":app.sim.day,"minutes":app.sim.minutes}
			expected.away.exit_position=vec(expected.away.exit_position)
			await _public_save("Robin — away at school")
			var file:=FileAccess.open("user://offlot_school_expected.json",FileAccess.WRITE)
			file.store_string(JSON.stringify(expected));file.close()
	_write_report();app.queue_free();await frames(3)
	print("OFFLOT_SCHOOL_UI_RESULT assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _check_away(context:String) -> void:
	check(app.sim.is_away() and str(app.sim.get_away_state().phase)=="away",context+": the school session is away.")
	check(not app.player.visible,context+": the pupil has no phantom body on the home lot.")
	var target_ids:Array=app.world.simulation_targets().map(func(target:Dictionary):return str(target.id))
	check(not target_ids.has("player") and target_ids.has("lot_exit"),context+": away pupil is removed from home interactions while the exit stays registered.")
	for child:Node in app.player.get_children():
		if child is CollisionObject3D:check(child.collision_layer==0,context+": hidden pupil cannot be clicked through a phantom collision body.")
	check(_visible_text_contains("At school") and _visible_text_contains("15:00"),context+": selected household HUD explains school and return time.")
	check(app.world.actors.housemate_1.visible,context+": adult remains visible at home.")

func _restore_and_return() -> void:
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://offlot_school_expected.json"))
	await _public_load()
	await press("School")
	_check_away("fresh restart")
	check(equivalent(_away_snapshot(),expected.away),"Fresh process restores exact away phase, schedule, exit and reward flags.")
	check(equivalent(app.sim.education,expected.education),"Fresh process does not change attendance while loading away.")
	check(app.player.position.distance_to(Vector3(expected.position[0],expected.position[1],expected.position[2]))<.02,"Fresh process preserves the departure exit instead of spawning a home body.")
	await screenshot("07_restored_away",false,false)
	await press("▶▶▶")
	if await wait_until(func()->bool:return str(app.sim.get_away_state().get("phase",""))=="returning","scheduled school end at 15:00",40):
		await press("Ⅱ")
		check(app.sim.day==int(expected.day) and app.sim.minutes>=900 and app.sim.minutes<903,"Scheduled return begins at 15:00 through actual frame processing.")
		check(app.player.visible and app.sim.is_away(),"Returning pupil reappears at the street and is still travelling home.")
		check(app.sim.education.attended==1,"Scheduled school end grants exactly one attendance record.")
		await screenshot("08_returning_from_school",false,false)
		await press("▶")
		await wait_until(func()->bool:return not app.sim.is_away(),"actual return walk into front garden",15)
		await press("Ⅱ")
		check(app.player.position.distance_to(app.world.lot_return_position(0))<.02,"The pupil completes a real return path into the front garden.")
		check(app.sim.education.attended==1 and member_completed.count("player:school_day")==1,"Return completion reports one school day without a second reward.")
		check(app.world.simulation_targets().any(func(target:Dictionary):return str(target.id)=="player"),"Returned pupil becomes a home interaction target again.")
		await screenshot("09_home_after_school",false,false)
	# A second public load branches from the same saved morning to test leaving
	# early without manufacturing a new day, needs, arrival or reward state.
	await _public_load();await press("School")
	_check_away("early-return branch")
	await press("Come home early")
	await press("▶")
	await wait_until(func()->bool:return not app.sim.is_away(),"early return walks home",15)
	await press("Ⅱ")
	check(app.sim.education.attended==0,"Coming home early before the school day ends grants no full-day attendance.")
	check(app.player.visible and app.sim.get_away_state().is_empty(),"Early return clears the away session only after reaching home.")
	await screenshot("10_early_return_home",false,false)

func _away_snapshot() -> Dictionary:
	var state:Dictionary=app.sim.get_away_state()
	if state.get("exit_position") is Vector3:state.exit_position=vec(state.exit_position)
	return state
