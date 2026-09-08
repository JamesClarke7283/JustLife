extends "res://tests/test_offlot_school_ui.gd"
## Real rendered departure, another member's home control, fresh-process away
## persistence, scheduled return/pay and player-directed early return.
func _run() -> void:
	screenshot_dir="res://art/offlot_career"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.notice.connect(func(message:String):notices.append(message))
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):member_completed.append(id+":"+str(action.id)))
	if resume_only:await _resume_work()
	else:
		await _create_school_household()
		await press_member(ADULT_NAME);await press("Career")
		await press("Career details")
		check(_visible_text_contains("09:00–17:00") and is_instance_valid(button_matching("Work from home")),"Career record explains the workplace schedule and distinct home alternative.")
		await screenshot("04_career_record",false,false);await press("Back to life")
		await press("▶▶▶")
		await wait_until(func()->bool:return app.sim.minutes>=540.0,"weekday09:00 workplace opens",15)
		await press("Ⅱ")
		var origin:Vector3=app.player.position
		await press("Go to work")
		check(str(app.sim.get_current_action().get("id",""))=="career_day" and not app.sim.is_away(),"Go to work queues the visible departure before marking anyone away.")
		await press("▶")
		await wait_until(func()->bool:return app.player.position.distance_to(origin)>.8,"adult actually walks toward the lot exit",20)
		check(app.player.visible and not app.sim.is_away(),"Worker remains visible while walking out.")
		await screenshot("05_walking_to_work",false,false)
		if await wait_until(func()->bool:return app.sim.is_away(),"worker reaches real sidewalk exit",45):
			await press("Ⅱ");_check_work_away("departure")
			check(app.player.position.distance_to(app.world.lot_exit_position(1))<.02,"Work begins only after actual exit arrival.")
			check(app.sim.career.worked_day==0,"Departing does not pay an unfinished shift.")
			await screenshot("06_at_work",false,false)
			await press_member(CHILD_NAME);await queue_via_menu("bookshelf","read");await press("▶")
			await wait_until(func()->bool:return active_is("read",.1),"child reads at home during adult absence",40)
			await press("Ⅱ")
			check(app.household.member_sim("housemate_1").is_away() and not app.world.actors.housemate_1.visible,"Controlling the child leaves work running without a phantom adult.")
			await screenshot("06b_child_at_home",false,false)
			await press_member(ADULT_NAME);await press("Career");_check_work_away("switching back")
			var expected:Dictionary={"away":_away_snapshot(),"career":app.sim.career.duplicate(true),"funds":app.household.funds,"position":vec(app.player.position),"day":app.sim.day,"minutes":app.sim.minutes}
			await _public_save("Morgan — away at work")
			var file:=FileAccess.open("user://offlot_career_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected));file.close()
	_write_report();app.queue_free();await frames(3)
	print("OFFLOT_CAREER_UI_RESULT assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _check_work_away(context:String) -> void:
	check(app.sim.is_away() and str(app.sim.get_away_state().phase)=="away" and str(app.sim.get_away_state().activity)=="career",context+": active work absence is identified.")
	check(not app.player.visible,context+": away worker has no home body.")
	var ids:Array=app.world.simulation_targets().map(func(target:Dictionary):return str(target.id))
	check(not ids.has("housemate_1") and ids.has("lot_exit"),context+": away worker is excluded from home interaction targets.")
	check(_visible_text_contains("At work") and _visible_text_contains("17:00"),context+": HUD identifies work and return time.")
	check(app.world.actors.player.visible,context+": the at-home child remains visible.")

func _resume_work() -> void:
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://offlot_career_expected.json"))
	await _public_load();await press("Career");_check_work_away("fresh restart")
	check(equivalent(_away_snapshot(),expected.away) and equivalent(app.sim.career,expected.career),"Fresh process preserves exact away work and unpaid career record.")
	check(app.household.funds==int(expected.funds),"Loading an away worker cannot pay a salary.")
	await screenshot("07_restored_work",false,false)
	await press("▶▶▶")
	if await wait_until(func()->bool:return str(app.sim.get_away_state().get("phase",""))=="returning","scheduled17:00 end of work",45):
		await press("Ⅱ")
		check(app.sim.day==int(expected.day) and app.sim.minutes>=1020 and app.sim.minutes<1023,"The workday ends at17:00 through real frame processing.")
		var salary:int=roundi(float(expected.away.salary)*(1020.0-float(expected.away.departure_minutes))/480.0)
		check(app.household.funds==int(expected.funds)+salary and app.sim.career.worked_day==app.sim.day,"The work bell grants exactly the time-proportional salary.")
		check(app.player.visible and app.sim.is_away(),"Worker reappears at the street and still needs to walk home.")
		await screenshot("08_returning_from_work",false,false)
		await press("▶");await wait_until(func()->bool:return not app.sim.is_away(),"worker walks into front garden",15);await press("Ⅱ")
		check(app.player.position.distance_to(app.world.lot_return_position(1))<.02,"Worker reaches the actual front garden rather than teleporting home.")
		check(member_completed.count("housemate_1:career_day")==1 and app.household.funds==int(expected.funds)+salary,"Return reports one completed workday without repeated pay.")
		await screenshot("09_home_from_work",false,false)
	await _public_load();await press("Career");_check_work_away("early-return branch")
	await press("Come home early");await press("▶");await wait_until(func()->bool:return not app.sim.is_away(),"worker walks home early",15);await press("Ⅱ")
	check(app.sim.career.worked_day==0 and app.household.funds==int(expected.funds),"Early return earns neither full-day attendance nor salary.")
	check(app.player.visible and app.sim.get_away_state().is_empty(),"Early return clears absence only after reaching the garden.")
	await screenshot("10_early_work_return",false,false)
