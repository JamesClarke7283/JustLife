extends "res://tests/test_stair_controller.gd"
## Actual main Build callbacks/50ms movement; food creation is explicit ledger
## setup, not paid cooking. No pointer UI or rendered contact claim.
var details:Array=[]
func frozen()->Dictionary:
	return {"layout":app.world.serialize_items(),"money":app.household.funds,"sim_money":app.sim.funds,"context":app.build_protection_context(),"history":app.build_undo.duplicate(true),"minutes":app.household.minutes}
func owner(waiter:bool=false)->bool:
	_setup(2 if waiter else 1)
	app.on_ground_clicked(Vector3(2,3.16,4));check(_until_transit("player"),"actual owner reaches stair transit")
	if waiter:
		app.select_household_member(1);app.on_ground_clicked(Vector3(-2,.16,-4))
		for frame:int in 800:
			_step()
			if str(_route("housemate_1").get("phase",""))=="waiting" and int(_route("housemate_1").ticket)>0:break
		check(str(_route("housemate_1").get("phase",""))=="waiting","opposite Lifelet really arrives at FIFO")
	app.set_build_mode(true);app.world.set_view_level(1)
	return str(_route("player").get("phase",""))=="transit"
func buy_protected(waiter:bool)->void:
	if not owner(waiter):return
	var at:Vector3=_route("housemate_1").wait if waiter else _route("player").clear
	check(app.world.can_place("plant",at,0),"geometry-only plant candidate is a valid layout fixture")
	var before:Dictionary=frozen();app.on_placement("plant",at,0)
	check(frozen()==before,"purchase rejects arrived waiter" if waiter else "purchase rejects owned stair clear point")
	details.append({"case":"purchase_waiter" if waiter else "purchase_clear","at":at,"before":before,"after":frozen()})
func move_into_clear()->void:
	_setup();app.world.add_item({"id":"movable","kind":"plant","x":-3.0,"z":3.0,"level":1});app._refresh_sim_targets(false)
	app.on_ground_clicked(Vector3(2,3.16,4));check(_until_transit("player"),"move case has actual stair owner")
	app.set_build_mode(true);app.world.set_view_level(1);app.move_item(app._find_item("movable"))
	check(not app.pending_move.is_empty(),"unrelated furnishing can enter move preview")
	var before:Dictionary=frozen();var pending:Dictionary=app.pending_move.duplicate(true);var at:Vector3=_route("player").clear
	app.on_placement("plant",at,0)
	check(frozen()==before and app.pending_move==pending,"move confirmation rejects occupied clear route without dropping pending original")
	details.append({"case":"move_clear","before":before,"after":frozen(),"pending":app.pending_move.duplicate(true)})
func carried_target(selling:bool)->void:
	_setup();app.loading_game=true;app.setup_live([{"id":"destination_table","kind":"dining","x":2.0,"z":0.0,"level":1},fixture()]);app.loading_game=false
	app.player.position=Vector3(-2,.16,-4);app.sim.needs.hunger=100;app._store_motion()
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet","player",2,"home",app.meal_flow.now());app.meal_flow.sync_world();app._refresh_sim_targets(false)
	check(app.sim.queue_action("serve_meal",str(batch.id)),"actual serving action accepts explicit API-created batch")
	check(_until_transit("player"),"real serving action enters stairs toward original table")
	app.set_build_mode(true);app.world.set_view_level(1)
	# Safe furnishing edits must preserve the real meal, original target and
	# paused route; only its proven navigation generation may be refreshed.
	var carried_before:Dictionary=equivalent_motion()
	var original_table:Dictionary=app.world.serialize_items().filter(func(entry:Dictionary)->bool:return str(entry.get("id",""))=="destination_table")[0]
	var original_queue:Array=app.sim.action_queue.duplicate(true)
	var money:int=app.household.funds;var clock:float=app.household.minutes
	app.on_placement("plant",Vector3(-3,3.16,-3),0)
	check(app.build_undo.size()==1 and app.household.funds==money-45,"unrelated furniture purchase remains usable during actual food transit")
	app.undo_build()
	check(app.build_undo.is_empty() and app.household.funds==money and app.household.members.all(func(m:Dictionary)->bool:return m.sim.funds==money),"unrelated furnishing undo restores every shared wallet during meal transit")
	var final_table:Dictionary=app.world.serialize_items().filter(func(entry:Dictionary)->bool:return str(entry.get("id",""))=="destination_table")[0]
	check(final_table==original_table and equivalent_motion()==carried_before and app.sim.action_queue==original_queue and app.household.minutes==clock,"safe edit and undo preserve original table, carried meal ownership/progress, queue and clock")
	var before:Dictionary=frozen()
	if selling:app.sell_item(app._find_item("destination_table"))
	else:app.move_item(app._find_item("destination_table"))
	check(frozen()==before and app.pending_move.is_empty(),"sell preserves busy carried-food destination" if selling else "move preserves busy carried-food destination")
	if not selling and not app.pending_move.is_empty():
		app.on_placement("dining",Vector3(-2,3.16,0),0);app.set_build_mode(false);app.household.set_speed(1)
		var started:bool=false;var distance:float=-1.0
		for frame:int in 2200:
			_step()
			if str(app.sim.get_current_action().get("id",""))=="serve_meal" and str(app.sim.get_current_action().get("phase",""))=="active":
				started=true;distance=app.player.position.distance_to(app.world.approach(app._find_item("destination_table")));break
		details.append({"case":"moved_food_target_continuation","started":started,"actor_to_actual_destination":distance,"queue":app.sim.action_queue.duplicate(true),"actor":app.player.position,"food":batch.duplicate(true)})
	details.append({"case":"sell_carried_target" if selling else "move_carried_target","before":before,"after":frozen()})
func undo_food()->void:
	_setup();app.set_build_mode(true);app.world.set_view_level(0)
	app.on_placement("plant",Vector3(2,.16,2),0)
	var plant:Dictionary=app.world.items[-1];var id:String=str(plant.id)
	app.move_item(plant);app.on_placement("plant",Vector3(3,.16,2),0)
	check(app.build_undo.size()==2,"real purchase and move create furnishing history")
	var batch:Dictionary=app.household.meals.create_batch("herb_pasta","player",2,"home",app.meal_flow.now())
	check(app.household.meals.set_batch_location(str(batch.id),"surface","",Vector3(2,.162,2),app.meal_flow.now()),"explicit loose-food ledger occupies the old furnishing footprint")
	app.meal_flow.sync_world()
	var before:Dictionary=frozen();app.undo_build()
	check(frozen()==before,"furnishing undo rejects occupied loose-food footprint without moving food or refunding")
	details.append({"case":"undo_food","item":id,"before":before,"after":frozen()})
func equivalent_motion()->Dictionary:
	var context:Dictionary=app.build_protection_context()
	for route:Dictionary in context.routes.values():route.erase("generation")
	return context
func unrelated_history()->void:
	if not owner(true):return
	var before:Dictionary=equivalent_motion();var money:int=app.household.funds;var clock:float=app.household.minutes
	var original:=Vector3(-3,3.16,-3)
	app.on_placement("plant",original,0)
	check(app.build_undo.size()==1 and app.household.funds==money-45 and app.household.members.all(func(m:Dictionary)->bool:return m.sim.funds==money-45),"unrelated purchase charges every household member immediately")
	check(equivalent_motion()==before,"unrelated purchase preserves owner/waiter facts except generation")
	var plant:Dictionary={}
	for item:Dictionary in app.world.items:
		if str(item.kind)=="plant":plant=item;break
	check(not plant.is_empty(),"unrelated purchase creates a real furnishing")
	if plant.is_empty():return
	var id:String=str(plant.id)
	app.move_item(plant);app.on_placement("plant",Vector3(-3,3.16,-2),0)
	check(app.pending_move.is_empty() and app.build_undo.size()==2 and app._find_item(id).node.position.distance_to(Vector3(-3,3.16,-2))<.001,"unrelated move retains real furnishing identity")
	check(equivalent_motion()==before,"unrelated move preserves current stair ownership and FIFO")
	app.sell_item(app._find_item(id))
	check(app.build_undo.size()==3 and app._find_item(id).is_empty() and app.household.funds==money-14 and app.household.members.all(func(m:Dictionary)->bool:return m.sim.funds==money-14),"unrelated sale credits every member immediately")
	for index:int in 3:app.undo_build()
	check(app.build_undo.is_empty() and app._find_item(id).is_empty() and app.household.funds==money and app.household.members.all(func(m:Dictionary)->bool:return m.sim.funds==money),"actual three-step furnishing undo restores exact shared wallet")
	check(equivalent_motion()==before and app.household.minutes==clock,"complete unrelated furnishing history preserves routes, food and clock")
	app.set_build_mode(false);app.household.set_speed(1)
	for frame:int in 2400:
		_step()
		if app.traversal.routes.is_empty():break
	check(app.traversal.routes.is_empty() and app.world.actors.player.position.distance_to(Vector3(2,3.16,4))<.001 and app.world.actors.housemate_1.position.distance_to(Vector3(-2,.16,-4))<.001,"both real walkers finish original opposite destinations after furnishing edits")
	details.append({"case":"unrelated_history","before":before,"after":equivalent_motion()})
func partial_table()->void:
	_setup();app.loading_game=true;app.setup_live([{"id":"dining_target","kind":"dining","x":2.0,"z":0.0,"level":1},{"id":"diner_chair","kind":"chair","x":2.0,"z":-1.0,"level":1},fixture()]);app.loading_game=false
	app.player.position=Vector3(-2,.16,-4);app._store_motion()
	var ledger:LifeMeals=app.household.meals
	var batch:Dictionary=ledger.create_batch("garden_skillet","player",2,"home",app.meal_flow.now())
	check(ledger.set_batch_location(str(batch.id),"surface","",Vector3(-2,.162,-2.5),app.meal_flow.now()),"API partial control places original batch")
	var plate:Dictionary=ledger.claim(str(batch.id),"player",app.meal_flow.now())
	check(not plate.is_empty() and ledger.eat(str(plate.id),"player",8.1,app.meal_flow.now())>0,"API partial control retains actual ledger eating fraction")
	ledger.release_member("player",Vector3(-2,.162,-3))
	app.meal_flow.sync_world();app._refresh_sim_targets(false)
	app.queue_interaction(app._find_item(str(plate.id)),"eat_meal")
	check(_until_transit("player"),"real partial-plate pickup enters upstairs dining trip")
	check(str(app.sim.get_current_action().get("meal_plate",""))==str(plate.id) and str(app.sim.get_current_action().get("meal_seat",""))=="diner_chair","actual partial diner reserves its real chair and same plate")
	app.set_build_mode(true);app.world.set_view_level(1)
	var before:Dictionary=frozen();app.move_item(app._find_item("dining_target"))
	check(frozen()==before and app.pending_move.is_empty(),"moving the reserved chair's table cannot bypass partial-plate destination protection")
	details.append({"case":"partial_table","before":before,"after":frozen()})
func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	buy_protected(false);buy_protected(true);move_into_clear();carried_target(false);carried_target(true);undo_food();unrelated_history();partial_table()
	var file:=FileAccess.open("user://furnishing_protection.json",FileAccess.WRITE);file.store_string(JSON.stringify(LifeSaveLibrary._json_safe({"checks":checks,"failures":failures,"details":details}),"  ",true,true));file.close()
	print("FURNISHING_PROTECTION checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
