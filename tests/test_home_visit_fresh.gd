extends "res://tests/test_home_visit.gd"
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var file:=FileAccess.open("user://home_visit_slots.json",FileAccess.READ)
	if file==null:check(false,"Producer phase slots exist");await _finish();return
	var slots:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	var phases:Array=["greeting"] if "--greeting-only" in OS.get_cmdline_user_args() else slots.keys()
	for phase:String in phases:
		var raw:Dictionary=LifeSaveLibrary.read_slot(str(slots[phase])).data
		var expected:Dictionary=LifeHomeVisit.saved_visit(raw).value
		_load(str(slots[phase]));await process_frame
		check(_same_value(app.residents.home_visit.snapshot(),expected),"Fresh process restores exact decoded "+phase+" route, clocks and identity")
		check(app.household.speed==0,"Fresh "+phase+" load remains paused")
		var before:Dictionary=_facts();_step(4)
		check(_facts()==before,"Paused "+phase+" does not advance simulation or visit")
		app.household.set_speed(1)
		if phase in ["greeting","entering"]:
			check(_until("inside"),"Fresh "+phase+" resumes accepted welcome through indoor arrival")
		app.residents.home_visit.goodbye()
		check(_until("absent"),"Fresh "+phase+" completes one physical departure")
		check(not app.residents.present("maya"),"Fresh "+phase+" is absent only after exit")
	await _finish()
