extends "res://tests/test_home_visit.gd"
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var slot:String=str(JSON.parse_string(FileAccess.get_file_as_string("user://home_visit_departure_slot.json")).slot)
	var raw:Dictionary=LifeSaveLibrary.read_slot(slot).data
	var expected:Dictionary=LifeHomeVisit.saved_visit(raw).value
	_load(slot);await process_frame
	check(_same_value(app.residents.home_visit.snapshot(),expected) and _phase()=="leaving","Fresh process restores Goodbye during paid Welcome with exact visit and departure owner")
	var friendship:float=app.sim.relationships.maya.friendship
	var paid:Dictionary=app.sim.get_current_action()
	check(str(paid.id)=="friendly" and bool(paid.paid) and not paid.has("home_visit_token"),"The restored real paid friendly action retains departure ownership without a stale Welcome token")
	var before:Dictionary=_facts();_step(4)
	check(_facts()==before,"Paused restored Goodbye keeps exact route, action and clocks")
	app.household.set_speed(1)
	check(_until("absent"),"Fresh paid-Welcome Goodbye completes the conversation and physical exit")
	check(app.sim.relationships.maya.friendship==friendship+12,"Only the one restored real conversation grants friendship")
	check(app.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"The unrelated reading queue survives fresh departure")
	await _finish()
