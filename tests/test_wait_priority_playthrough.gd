extends "res://tests/test_genealogy_playthrough.gd"
## Public eight-member queue/save/restart check, isolated by run_playthrough.py.
## No clock jumps, need fills, forced arrivals or forced activity completions.
func _run() -> void:
	screenshot_dir="res://art/wait_priority"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	if resume_only:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://wait_priority_expected.json"))
		await _public_load()
		for id:String in expected.waiters:
			var motion:Dictionary=app.motion_states[id]
			check(bool(motion.waiting) and is_equal_approx(float(motion.wait_started),float(expected.waiters[id])),"Fresh public load preserves arrived queue timestamp: "+id)
		await press("▶");await frames(8);await press("Ⅱ")
		check(app.household.member_sim(expected.occupant).get_current_action().phase=="active","Fresh load resumes the existing bed occupant before waiting arrivals.")
		await screenshot("02_restored_waiters",false,false)
		await press_member(str(app.household.member_sim(expected.occupant).character.name))
		await press("Cancel action")
		await press("▶▶▶")
		await wait_until(func()->bool:return app.household.member_sim(expected.oldest).get_current_action().phase=="active","Oldest saved waiter receives the released bed",20)
		await press("Ⅱ")
		for id:String in expected.waiters:
			if id==expected.oldest:continue
			check(app.household.member_sim(id).get_current_action().phase=="approach","A later saved waiter does not overtake the oldest arrival: "+id)
		await press_member(str(app.household.member_sim(expected.oldest).character.name))
		await screenshot("03_oldest_admitted",false,false)
	else:
		await _create_genealogy()
		for person:String in FAMILY_NAMES:
			await press_member(person);await queue_via_menu("bed","sleep")
		await press("▶▶▶")
		await wait_until(_all_arrived,"One actual sleeper and seven settled waiting Lifelets",30)
		await press("Ⅱ")
		var expected:Dictionary={"waiters":{},"occupant":"","oldest":""}
		var earliest:float=INF
		var positions:Array[Vector3]=[]
		for member:Dictionary in app.household.members:
			var id:String=str(member.id);var motion:Dictionary=app.motion_states[id]
			if member.sim.get_current_action().phase=="active":expected.occupant=id
			else:
				expected.waiters[id]=motion.wait_started
				if float(motion.wait_started)<earliest or (is_equal_approx(float(motion.wait_started),earliest) and id<str(expected.oldest)):
					earliest=float(motion.wait_started);expected.oldest=id
				var position:Vector3=app.world.actors[id].position
				for other:Vector3 in positions:check(position.distance_to(other)>=.65,"Settled waiting bodies are visibly separate before saving.")
				positions.append(position)
		check(expected.waiters.size()==7 and not str(expected.occupant).is_empty(),"The saved controlled fixture contains seven actual waiters and one occupant.")
		await screenshot("01_seven_distinct_waiters",false,false)
		await _public_save("Reed family — arrived waiting order")
		var file:=FileAccess.open("user://wait_priority_expected.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(expected));file.close()
	_write_report();app.queue_free();await frames(3)
	print("WAIT_PRIORITY_RESULT assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _all_arrived() -> bool:
	var active:int=0;var waiting:int=0
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if action.is_empty():return false
		if action.phase=="active":active+=1
		var motion:Dictionary=app.motion_states[str(member.id)]
		if bool(motion.waiting) and int(motion.index)>=motion.path.size():waiting+=1
	return active==1 and waiting==7
