extends "res://tests/test_guest_meal.gd"
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var file:=FileAccess.open("user://guest_meal_slots.json",FileAccess.READ)
	if file==null:check(false,"Producer slots exist");await _finish();return
	var ids:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	_load(str(ids.pickup));await process_frame;app.meal_flow.sync_world(false)
	var visit:LifeHomeVisit=app.residents.home_visit;var meal:LifeGuestMeal=visit.meal
	var source:String=str(meal.state.source)
	app.world.actors.player.position=meal.state.target
	check(visit._route(meal.body().position,meal.state.target,"maya").is_empty(),"Actual household body blocks the offered pickup destination")
	app.queue_interaction(app._find_item(source),"discard_meal");app.household.set_speed(1)
	for index:int in 300:
		if app.household.meals.batch(source).is_empty():break
		_step()
	check(app.household.meals.batch(source).is_empty(),"Household physically collects and finishes discarding the offered source")
	check(_meal_phase()!="pickup" and app.household.meals.portions.is_empty(),"Completed source mutation leaves no stale pickup or invented guest portion")
	check(app.save_game("","Discarded guest offer"),"Same-turn named save remains valid after ordinary source removal")
	_load(str(ids.pickup));await process_frame;app.meal_flow.sync_world(false)
	visit=app.residents.home_visit;meal=visit.meal;source=str(meal.state.source)
	app.world.actors.player.position=meal.state.target
	check(app.household.meals.discard_batch(source),"Controlled source disappearance prunes the unclaimed batch")
	app.household.set_speed(1);meal.tick(.05)
	check(_meal_phase()!="pickup" and app.household.meals.portions.is_empty(),"Guest tick reconciles a missing source before attempting the blocked walk")
	if await _save_phase("source_removed"):
		var output:=FileAccess.open("user://guest_meal_source_slot.json",FileAccess.WRITE);output.store_string(JSON.stringify({"source_removed":app.active_save_id},"",true,true));output.close()
	_load(str(ids.eating));await process_frame;app.meal_flow.sync_world(false)
	visit=app.residents.home_visit;meal=visit.meal
	var at:Vector3=Vector3.INF
	for x:int in range(-9,10):
		for z:int in range(-7,8):
			var candidate:=Vector3(x*.5,.16,z*.5)
			if app.world.can_place("dining",candidate,0):at=candidate;break
		if at.is_finite():break
	check(at.is_finite(),"Actual house has a valid placement for a second dining table")
	if at.is_finite():
		app.world.add_item({"id":"integrity_table","kind":"dining","x":at.x,"z":at.z,"rotation":0.0,"level":0})
		var second:Dictionary=app._find_item("integrity_table")
		var slot:Vector3=app.meal_flow._surface_slot(second,LifeMeals.PLATE_HALF_SIZE,str(meal.state.plate))
		check(slot.is_finite(),"Second real table supports an unoccupied plate setting")
		var before:Dictionary=app.household.meals.get_state()
		var serving:Dictionary=meal.plate();serving.host=str(second.id);serving.offset=[slot.x,slot.y,slot.z]
		var position:Vector3=second.node.to_global(slot);serving.position=[position.x,position.y,position.z]
		var mismatch:Dictionary=app.household.get_state(app.world.serialize_items())
		var validator:=LifeHousehold.new();root.add_child(validator)
		check(bool(validator.restore_state(mismatch).ok),"Controlled wrong-table save otherwise has valid food custody and supported layout")
		validator.free()
		var untouched:Dictionary=_record();var result:Dictionary=app._prepare_loaded_world(mismatch)
		check(not bool(result.ok),"Physical preflight rejects guest plate placed on the other valid table")
		if bool(result.ok):result.viewport.free();result.candidate.free()
		check(_same_value(_record(),untouched),"Wrong-table preflight rejects without repairing or mutating the current state")
		app.household.meals.restore(before)
	await _finish()
