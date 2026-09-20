extends "res://tests/test_stair_save_process.gd"
var food_expected:Dictionary={}

func _food_setup()->void:
	_setup()
	var layout:Array=[
		{"id":"ground_stove","kind":"stove","x":-2.0,"z":-2.0,"rotation":0.0},
		{"id":"ground_sink","kind":"sink","x":2.0,"z":-3.0,"rotation":0.0},
		{"id":"upper_table","kind":"dining","x":2.0,"z":0.0,"rotation":0.0,"level":1},
		{"id":"upper_chair","kind":"chair","x":2.0,"z":-1.0,"rotation":0.0,"level":1},
		{"id":"ground_shelf","kind":"bookshelf","x":-3.25,"z":0.0,"rotation":0.0},
		{"id":"upper_shelf","kind":"bookshelf","x":-3.25,"z":3.75,"rotation":0.0,"level":1},fixture()]
	var valid:String=app.world.validate_home_layout(layout)
	check(valid.is_empty(),"Complete meal fixture passes actual world layout validation: "+valid)
	app.loading_game=true;app.setup_live(layout);app.loading_game=false
	app.player.position=Vector3(-2,.16,-4)
	# A recipe's ingredients come out of the kitchen rather than the purse, so the
	# fixture stocks it through the household's own order before it cooks.
	app.household.set_funds(app.household.funds+200)
	app.household.order_groceries("weekly")
	app.household.collect_groceries()
	app.sim.needs.hunger=100.0;app._store_motion();app._refresh_sim_targets()

func _food_record(id:String)->Dictionary:
	var portion:Dictionary=app.household.meals.portion(id)
	return portion if not portion.is_empty() else app.household.meals.batch(id)

func _food_position(value:Dictionary)->Vector3:
	return Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))

func _food_produce()->void:
	_food_setup()
	if not failures.is_empty():return
	var initial_funds:int=app.household.funds
	app.meal_flow.queue_recipe("ground_stove","garden_skillet")
	var carried:bool=false
	for frame:int in 2200:
		_step()
		if str(app.sim.get_current_action().get("id",""))=="serve_meal" and str(_route("player").get("phase",""))=="transit" and float(_route("player").distance)>.6:carried=true;break
	check(carried,"Actual paid cooking creates a serving batch and carries it onto the upstairs route.")
	if not carried:
		print("FOOD_DIAGNOSTIC ",JSON.stringify(LifeSaveLibrary._json_safe({"queue":app.sim.action_queue,"route":_route("player"),"ledger":app.household.meals.get_state(),"position":app.player.position}),"",true,true));return
	# Cooking takes a meal out of the kitchen rather than charging the purse, so
	# what the fixture proves is that one meal was drawn and the dish really holds
	# four unclaimed servings.
	check(app.household.funds==initial_funds and app.household.meals.batches.size()==1 and app.household.meals.portions.is_empty(),"Actual garden skillet draws one meal from the kitchen and creates exactly four unclaimed servings.")
	var batch:Dictionary=app.household.meals.batches[0]
	check(int(batch.remaining)==4,"Cooked serving dish retains all four servings during transit.")
	var held_id:String=str(batch.id)
	if case_name.begins_with("partial"):
		var served:bool=false
		for frame:int in 2200:
			_step()
			if str(batch.storage)=="surface" and app.sim.action_queue.is_empty():served=true;break
		check(served and str(batch.host)=="upper_table","The actual cook completes upstairs service at the real dining table.")
		if not served:return
		app.queue_interaction(app._find_item(str(batch.id)),"eat_meal")
		var ate:bool=false
		for frame:int in 1500:
			_step()
			var action:Dictionary=app.sim.get_current_action()
			if str(action.get("id",""))=="eat_meal" and str(action.get("phase",""))=="active" and float(action.elapsed)>=8.0:ate=true;break
		check(ate,"Lifelet actually sits and eats part of one serving before cancellation.")
		if not ate:
			print("EAT_DIAGNOSTIC ",JSON.stringify(LifeSaveLibrary._json_safe({"queue":app.sim.action_queue,"route":_route("player"),"ledger":app.household.meals.get_state(),"position":app.player.position}),"",true,true));return
		held_id=str(app.sim.get_current_action().meal_plate)
		var plate:Dictionary=app.household.meals.portion(held_id)
		food_expected.eaten_progress=float(plate.progress)
		app.cancel_current_action();app.meal_flow.sync_world()
		check(str(plate.owner).is_empty() and str(plate.host)=="upper_table" and float(plate.progress)>0 and float(plate.progress)<1,"Canceling seated eating retains the exact unfinished serving on its upper table.")
		app.queue_interaction(app._find_item(held_id),"clean_plate")
		check(_until_transit("player") and int(_route("player").legs[int(_route("player").cursor)].direction)==-1,"Actual unfinished-plate pickup descends toward the ground-floor sink.")
		if str(_route("player").get("phase",""))!="transit":return
	if case_name.ends_with("later"):
		app.queue_interaction(app._find_item("upper_shelf" if case_name.begins_with("partial") else "ground_shelf"),"read")
	var ledger_before:Dictionary=app.household.meals.get_state()
	var identity:int=int(_route("player").identity)
	app.cancel_current_action()
	check(app.traversal.safety("player") and int(_route("player").identity)==identity and str(_route("player").custody)==held_id,"Canceling actual food transit retains its stair identity and dish custody.")
	check(_equal(app.household.meals.get_state(),ledger_before),"Stair cancellation does not alter food identity, paid servings, partial progress or ownership.")
	if case_name.ends_with("later"):
		check(app.sim.action_queue.size()==1 and str(app.sim.get_current_action().phase)=="approach" and float(app.sim.get_current_action().elapsed)==0,"Later reading remains unstarted while the carried dish exits safely.")
	else:check(app.sim.action_queue.is_empty(),"Empty canceled queue still keeps the actual carried dish until a supported landing.")
	app.household.set_speed(0);app.overlay_open=true
	food_expected.merge({"facts":_saved_facts(),"ledger":app.household.meals.get_state(),"food_id":held_id,"funds":app.household.funds,"minutes":app.household.minutes,"queue":app.sim.get_state().action_queue,"landing_level":0 if case_name.begins_with("partial") else 1},true)
	check(app.save_game("","Food custody "+case_name),"Actual main saves a named paused crossing with the carried cooked food.")
	food_expected.slot=app.active_save_id
	var read:Dictionary=LifeSaveLibrary.read_slot(str(food_expected.slot))
	check(bool(read.ok),"Saved food crossing passes detached layout, action, journey and custody validation: "+str(read.get("error","valid")))
	DirAccess.make_dir_recursive_absolute("user://regression/stair_save")
	var file:=FileAccess.open("user://regression/stair_save/food_"+case_name+"_expected.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(LifeSaveLibrary._json_safe(food_expected),"  ",true,true));file.close()

func _food_consume()->void:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://regression/stair_save/food_"+case_name+"_expected.json"))
	check(data is Dictionary,"Fresh process has the actual producer's saved-food expectation.")
	if not data is Dictionary:return
	food_expected=data
	var read:Dictionary=LifeSaveLibrary.read_slot(str(food_expected.slot))
	check(bool(read.ok),"Fresh process validates the real previously written named food slot.")
	if not bool(read.ok):return
	app.load_game(str(food_expected.slot))
	check(_equal(_saved_facts(),food_expected.facts),"Fresh main restores exact stair position, schedule distance, identity and custody.")
	check(_equal(app.household.meals.get_state(),food_expected.ledger) and _equal(app.sim.get_state().action_queue,food_expected.queue),"Fresh reconstruction preserves the entire food ledger and pending queue unchanged.")
	check(app.household.funds==int(food_expected.funds) and app.household.minutes==float(food_expected.minutes) and app.household.speed==0,"Fresh food load preserves wallet, exact clock and pause.")
	check(app.player.stair_pose_valid and not app.player.stair_presentation.is_empty() and str(app.household.meals.carried_by("player").get("id",""))==str(food_expected.food_id),"Fresh paused Lifelet reconstructs an actual valid stair pose while owning the same dish.")
	_step(20)
	check(_equal(_saved_facts(),food_expected.facts) and _equal(app.household.meals.get_state(),food_expected.ledger) and _equal(app.sim.get_state().action_queue,food_expected.queue),"Twenty paused frames neither move nor consume, refund, release or start later work.")
	app.household.set_speed(1)
	var premature:bool=false
	for frame:int in 2200:
		_step()
		if not app.traversal.safety("player"):break
		var current:Dictionary=app.sim.get_current_action()
		if not current.is_empty() and (str(current.phase)!="approach" or float(current.elapsed)!=0):premature=true
	check(not premature,"Later work never starts or progresses before the original stair clearance completes.")
	var held:Dictionary=_food_record(str(food_expected.food_id))
	check(not app.traversal.safety("player") and app.world.point_level(app.player.position)==int(food_expected.landing_level),"Canceled food trip reaches its original clear landing before releasing ownership.")
	check(not held.is_empty() and str(held.owner).is_empty() and str(held.storage)=="surface" and app.meal_flow._food_level(held)==int(food_expected.landing_level),"Exactly the original dish is set down on the reached floor and loses its carry owner.")
	if held.is_empty():return
	var at:Vector3=_food_position(held)
	if str(held.host).is_empty():
		check(absf(at.y-app.meal_flow._floor_support(at,app.meal_flow._footprint(held)))<.00001,"Loose set-down rests its complete original ceramic footprint on the real floor.")
		check(Vector2(at.x-app.player.position.x,at.z-app.player.position.z).length()>=.45,"Floor set-down leaves physical space for the Lifelet's feet.")
	check(app.household.funds==int(food_expected.funds) and app.household.meals.batches.size()==food_expected.ledger.batches.size() and app.household.meals.portions.size()==food_expected.ledger.portions.size(),"Clearance grants no refund, duplicate batch or extra serving.")
	for before:Dictionary in food_expected.ledger.batches:
		check(int(app.household.meals.batch(str(before.id)).remaining)==int(before.remaining),"Clearance preserves paid batch serving count "+str(before.id))
	for before:Dictionary in food_expected.ledger.portions:
		check(float(app.household.meals.portion(str(before.id)).progress)==float(before.progress),"Clearance preserves exact actual eaten fraction "+str(before.id))
	if case_name.ends_with("later"):
		var began:bool=false
		for frame:int in 2400:
			_step()
			if str(app.sim.get_current_action().get("phase",""))=="active":began=true;break
		check(began and str(app.sim.get_current_action().get("id",""))=="read" and app.world.point_level(app.player.position)==1-int(food_expected.landing_level),"The saved later read traverses back to its actual shelf and only then begins.")
	else:check(app.sim.action_queue.is_empty() and app.traversal.routes.is_empty(),"Empty cancellation ends idle after set-down and stair release.")
	check(app.traversal.stairs.values().all(func(lock:Dictionary)->bool:return str(lock.owner).is_empty() and lock.queue.is_empty()),"Finished food cancellation releases all staircase reservations.")

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	if stage_name=="produce":_food_produce()
	else:_food_consume()
	var report:Dictionary={"checks":checks,"failures":failures,"case":case_name,"stage":stage_name,"process_id":OS.get_process_id(),"scope":"Actual main paid cooking/serving/eating/pickup and stair cancellation through public controller APIs, saved disk state and separate-process reload. Manual 50ms frames; no pointer UI or rendered contact claim."}
	var file:=FileAccess.open("user://regression/stair_save/food_"+case_name+"_"+stage_name+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("STAIR_FOOD_PROCESS %s %s checks=%d failures=%d"%[case_name,stage_name,checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
