extends "res://tests/test_guest_meal.gd"
var finished_actions:Array=[]
func _item_kind(kind:String)->Dictionary:return app.world.closest_item(kind,Vector3.ZERO)
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var file:=FileAccess.open("user://guest_meal_slots.json",FileAccess.READ)
	if file==null:check(false,"Producer slots exist");await _finish();return
	var ids:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	_load(str(ids.pickup));await process_frame;app.meal_flow.sync_world(false)
	var source:String=str(app.residents.home_visit.meal.state.source)
	# Withdraw the unclaimed producer offer, then gather the household diner
	# nearby through the real ground-click route before calling everyone.
	app.residents.home_visit.meal.cancel("");app.household.set_speed(1)
	check(_meal_until("none"),"Unclaimed offer safely returns guest to the admitted visit")
	app.select_household_member(0)
	var near:Vector3=app.world.approach(app._find_item(source))+Vector3(1.5,0,.5)
	near=app.world.nearest_clear_point(near,0)
	app.on_ground_clicked(near)
	for index:int in 500:
		if app.world.actors.player.position.distance_to(near)<.02:break
		_step()
	check(app.world.actors.player.position.distance_to(near)<.02,"Household diner walks near the meal before the shared call")
	app.select_household_member(1)
	app.queue_interaction(_item_kind("stove"),"cook")
	app.household.set_speed(1)
	for index:int in 300:
		if str(app.sim.get_current_action().get("phase",""))=="active":break
		_step()
	var chef:LifeSim=app.sim;var cook:Dictionary=chef.get_current_action()
	check(str(cook.get("id",""))=="cook" and str(cook.get("phase",""))=="active" and bool(cook.get("paid",false)),"Other household member has a real active paid cooking instruction")
	app.queue_interaction(_item_kind("bookshelf"),"read")
	var later:Dictionary=chef.action_queue[-1];var funds:int=app.household.funds
	app.select_household_member(0);app.sim.needs.hunger=25
	var friend_before:float=float(app.sim.relationships.maya.friendship)
	var chef_queue:Array=chef.action_queue.duplicate(true)
	check(app.meal_flow.call_to_meal(source)==2,"One call adds the nearby household diner and welcomed guest while busy chef keeps plans")
	check(is_same(chef.get_current_action(),cook) and is_same(chef.action_queue[-1],later) and chef.action_queue==chef_queue and app.household.funds==funds,"Call preserves the exact paid chef instruction, later explicit reading and wallet")
	var simultaneous:bool=false
	for index:int in 500:
		var action:Dictionary=app.sim.get_current_action()
		if _meal_phase()=="eating" and str(action.get("id",""))=="eat_meal" and str(action.get("phase",""))=="active":simultaneous=true;break
		if index%30==0:events.append({"step":index,"meal":app.residents.home_visit.meal.state.duplicate(true),"action":action.duplicate(true),"food":app.household.meals.get_state(),"positions":app.residents.home_visit.snapshot(),"motion":app.motion_states.duplicate(true)})
		_step()
	check(simultaneous,"Guest and household Lifelet physically arrive at the same table together")
	if simultaneous:
		var plate_id:String=str(app.sim.get_current_action().meal_plate)
		var guest_plate:String=str(app.residents.home_visit.meal.state.plate)
		check(str(app.household.meals.portion(plate_id).host)==str(app.household.meals.portion(guest_plate).host),"Separate real reservations share one table without sharing a chair")
		_step(20)
		var own:Dictionary=app.household.meals.portion(plate_id);var guest:Dictionary=app.household.meals.portion(guest_plate)
		check(float(own.shared_minutes)>=5 and own.company.has("maya") and guest.company.has("player"),"Actual overlapping eating records guest company and shared minutes on both portions")
		check(app.household.members.size()==2 and app.household.member_sim("maya")==null,"Shared company creates no fake household member or guest needs")
		if not await _save_phase("company"):await _finish();return
		var saved:=FileAccess.open("user://guest_meal_company_slot.json",FileAccess.WRITE);saved.store_string(JSON.stringify({"company":app.active_save_id},"",true,true));saved.close()
		chef=app.household.member_sim("housemate_1")
		check(app.household.funds==funds and chef.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"Concurrent named restore preserves the chef's paid debit and later reading")
		app.household.set_speed(1)
		for index:int in 500:
			if float(app.household.meals.portion(plate_id).progress)==1:break
			_step()
		check(float(app.household.meals.portion(plate_id).progress)==1 and str(app.household.meals.portion(plate_id).owner).is_empty(),"Household diner completes and releases their own portion")
		check(float(app.sim.relationships.maya.friendship)==friend_before+4,"One actual shared household meal grants exactly one ordinary company relationship reward")
		var retained:float=float(app.sim.relationships.maya.friendship);_step(20)
		check(float(app.sim.relationships.maya.friendship)==retained,"Later guest completion does not grant a duplicate household reward")
		var queue:Array=chef.action_queue.duplicate(true);var ledger:Dictionary=app.household.meals.get_state();funds=app.household.funds
		app.residents.home_visit.goodbye()
		check(chef.action_queue==queue and app.household.meals.get_state()==ledger and app.household.funds==funds,"Goodbye leaves unrelated paid cooking and explicit queues untouched")
		check(_until("absent"),"Dinner guest follows the normal physical exit after company")
		app.select_household_member(0)
		app.queue_interaction(app._find_item(guest_plate),"clean_plate")
		check(str(app.sim.get_current_action().get("id",""))=="clean_plate","Guest's actual empty dish exposes ordinary household cleanup")
		for index:int in 600:
			if app.household.meals.portion(guest_plate).is_empty():break
			_step()
		check(app.household.meals.portion(guest_plate).is_empty() and int(app.household.meals.batch(source).served)==2,"Real sink routing and paid washing time remove only the guest's used dish")
	await _finish()
