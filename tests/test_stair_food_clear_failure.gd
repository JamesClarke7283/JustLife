extends "res://tests/test_stair_food_custody.gd"

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	food_expected=JSON.parse_string(FileAccess.get_file_as_string("user://regression/stair_save/food_partial_later_expected.json"))
	app.load_game(str(food_expected.slot))
	check(_equal(_saved_facts(),food_expected.facts),"Failure control loads the actual partially eaten plate's canceled descending save.")
	# Inject only the placement service's explicit failure result. The real
	# original actor, ledger, controller and loaded crossing remain in place.
	var original:LifeMealFlow=app.meal_flow
	var gate:LifeMealFlow=preload("res://tests/blocked_food_setdown.gd").new()
	gate.app=app;gate.views=original.views;gate.revision=original.revision;gate.sync_due=original.sync_due;gate._carry_grips_cache=original._carry_grips_cache
	app.add_child(gate);app.meal_flow=gate
	for member:Dictionary in app.household.members:member.sim.meal_service=gate
	original.queue_free();await process_frame
	app.household.set_speed(1)
	for frame:int in 2200:
		_step()
		if gate.denied>0:break
	check(gate.denied>0,"The actual safe exit reaches and attempts its guarded set-down callback.")
	var route:Dictionary=_route("player")
	check(str(route.get("phase",""))=="clear" and app.player.position.distance_to(route.clear)<.00001 and str(route.get("custody",""))==str(food_expected.food_id),"Failed set-down holds the actor at the actual clear landing with the same custody.")
	check(_equal(app.household.meals.get_state(),food_expected.ledger),"A refused placement leaves the entire live partial-plate ledger unchanged.")
	var facts:Dictionary=_saved_facts()
	_step(20)
	check(_equal(_saved_facts(),facts) and _equal(app.household.meals.get_state(),food_expected.ledger),"Repeated placement refusal retains exact physical ownership, position and food progress.")
	check(str(app.sim.get_current_action().phase)=="approach" and float(app.sim.get_current_action().elapsed)==0 and app.household.funds==int(food_expected.funds),"A blocked set-down cannot start later reading or refund ingredients.")
	app.household.set_speed(0);app.overlay_open=true
	check(app.save_game("","Blocked food landing"),"Actual main can save the paused clear landing with its still-owned partial dish.")
	var clear_slot:String=app.active_save_id
	var read:Dictionary=LifeSaveLibrary.read_slot(clear_slot)
	check(bool(read.ok),"Detached validator accepts legitimate clear-phase custody: "+str(read.get("error","valid")))
	app.load_game(clear_slot)
	check(_equal(_saved_facts(),facts) and _equal(app.household.meals.get_state(),food_expected.ledger),"Actual staged load restores the blocked landing and food exactly.")
	_step(20)
	check(_equal(_saved_facts(),facts),"Restored clear-phase custody remains stationary while paused.")
	# Loading installs the ordinary real placement service again. The same
	# supported scene can now succeed and release exactly once.
	app.household.set_speed(1);_step()
	var plate:Dictionary=app.household.meals.portion(str(food_expected.food_id))
	check(not app.traversal.safety("player") and str(plate.owner).is_empty() and float(plate.progress)==float(food_expected.eaten_progress),"Real set-down succeeds after refusal ends and preserves the actual eaten fraction.")
	check(app.traversal.stairs.values().all(func(lock:Dictionary)->bool:return str(lock.owner).is_empty()),"Successful retry releases the previous owner's stair reservation.")
	var report:Dictionary={"checks":checks,"failures":failures,"process_id":OS.get_process_id(),"slot":clear_slot,"scope":"Actual loaded cooking/eating history and main stair exit with an explicitly injected false placement callback; real clear-phase save/load and normal-placement retry. Does not claim a naturally overcrowded landing."}
	var file:=FileAccess.open("user://regression/stair_save/food_clear_failure.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("FOOD_CLEAR_FAILURE ",JSON.stringify(report))
	app.queue_free();await process_frame;await process_frame;await create_timer(.3).timeout
	quit(0 if failures.is_empty() else 1)
