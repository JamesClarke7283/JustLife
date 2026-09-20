extends "res://tests/test_stair_food_custody.gd"

func _leftover_produce()->void:
	food_expected=JSON.parse_string(FileAccess.get_file_as_string("user://regression/stair_save/food_partial_empty_expected.json"))
	app.load_game(str(food_expected.slot));app.household.set_speed(1)
	for frame:int in 2200:
		_step()
		if not app.traversal.safety("player"):break
	var plate:Dictionary=app.household.meals.portion(str(food_expected.food_id))
	check(str(plate.owner).is_empty() and float(plate.progress)==float(food_expected.eaten_progress),"Actual canceled cleanup leaves the real unfinished serving on the ground floor.")
	app.queue_interaction(app._find_item(str(plate.id)),"eat_meal")
	check(_until_transit("player"),"Actual leftover pickup routes the diner upstairs to the available chair.")
	var action:Dictionary=app.sim.get_current_action()
	check(str(action.get("id",""))=="eat_meal" and str(action.get("meal_stage",""))=="eat" and str(action.get("phase",""))=="approach" and action.get("paid")==false,"New eating instruction is still approaching after actual collection of the partial plate.")
	check(float(action.get("elapsed",0))==float(plate.progress)*LifeMeals.EATING_MINUTES and float(action.elapsed)>0,"Unstarted eating instruction inherits exact already-eaten serving progress through real callbacks.")
	app.household.set_speed(0);app.overlay_open=true
	food_expected.merge({"facts":_saved_facts(),"ledger":app.household.meals.get_state(),"queue":app.sim.get_state().action_queue,"funds":app.household.funds,"minutes":app.household.minutes},true)
	check(app.save_game("","Returning to leftovers"),"Public named save accepts legitimate carried partial-food progress while approaching the chair.")
	food_expected.slot=app.active_save_id
	var read:Dictionary=LifeSaveLibrary.read_slot(str(food_expected.slot))
	check(bool(read.ok),"Actual leftover stair save passes full detached validation: "+str(read.get("error","valid")))
	DirAccess.make_dir_recursive_absolute("user://regression/stair_save")
	var file:=FileAccess.open("user://regression/stair_save/leftover_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(LifeSaveLibrary._json_safe(food_expected),"  ",true,true));file.close()

func _leftover_consume()->void:
	food_expected=JSON.parse_string(FileAccess.get_file_as_string("user://regression/stair_save/leftover_expected.json"))
	var read:Dictionary=LifeSaveLibrary.read_slot(str(food_expected.slot))
	check(bool(read.ok),"Fresh process accepts the actual unpaid partial-plate approach save.")
	if not bool(read.ok):return
	app.load_game(str(food_expected.slot))
	check(_equal(_saved_facts(),food_expected.facts) and _equal(app.household.meals.get_state(),food_expected.ledger) and _equal(app.sim.get_state().action_queue,food_expected.queue),"Fresh staged load preserves exact resumed leftover, queue and physical crossing.")
	_step(20)
	check(_equal(_saved_facts(),food_expected.facts) and _equal(app.household.meals.get_state(),food_expected.ledger),"Paused leftover reconstruction consumes no food and makes no movement.")
	app.household.set_speed(1)
	var premature:bool=false;var began:bool=false
	for frame:int in 2200:
		_step()
		var plate:Dictionary=app.household.meals.portion(str(food_expected.food_id))
		var action:Dictionary=app.sim.get_current_action()
		if str(action.get("phase",""))=="active":began=true;break
		if float(plate.progress)!=float(food_expected.eaten_progress):premature=true
	check(began and not premature and app.world.point_level(app.player.position)==1 and str(app.sim.get_current_action().get("meal_seat",""))=="upper_chair","The leftover resumes eating only after reaching its real upstairs chair.")
	_step(10)
	var plate:Dictionary=app.household.meals.portion(str(food_expected.food_id))
	check(float(plate.progress)>float(food_expected.eaten_progress) and float(plate.progress)<1,"The original leftover continues consuming from its saved fraction.")
	check(app.household.funds==int(food_expected.funds) and app.household.meals.batches.size()==1 and app.household.meals.portions.size()==1 and int(app.household.meals.batches[0].remaining)==3,"Resuming leftovers neither charges again nor claims another serving.")

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	if stage_name=="produce":_leftover_produce()
	else:_leftover_consume()
	var report:Dictionary={"checks":checks,"failures":failures,"stage":stage_name,"process_id":OS.get_process_id(),"scope":"Actual cooked/eaten/canceled-cleanup history, normal leftover pickup and upstairs re-eating; separate main save/load processes, no injected progress or phases."}
	var file:=FileAccess.open("user://regression/stair_save/leftover_"+stage_name+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("STAIR_LEFTOVER %s checks=%d failures=%d"%[stage_name,checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.3).timeout;quit(0 if failures.is_empty() else 1)
