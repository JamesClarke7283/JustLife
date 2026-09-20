extends "res://tests/test_guest_meal.gd"
## Mirror the company setup, then ask why the shared call counts what it does.
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var file:=FileAccess.open("user://guest_meal_slots.json",FileAccess.READ)
	if file==null:print("PROBE no slots");return
	var ids:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	_load(str(ids.pickup));await process_frame;app.meal_flow.sync_world(false)
	var source:String=str(app.residents.home_visit.meal.state.source)
	print("PROBE source=",source," visit_phase=",app.residents.home_visit.state.get("phase",""))
	app.residents.home_visit.meal.cancel("");app.household.set_speed(1)
	print("PROBE after cancel meal=",app.residents.home_visit.meal.state)
	app.select_household_member(0)
	var near:Vector3=app.world.approach(app._find_item(source))+Vector3(1.5,0,.5)
	near=app.world.nearest_clear_point(near,0)
	app.on_ground_clicked(near)
	for index:int in 500:
		if app.world.actors.player.position.distance_to(near)<.02:break
		_step()
	app.select_household_member(1)
	app.queue_interaction(_item_kind("stove"),"cook")
	app.household.set_speed(1)
	for index:int in 300:
		if str(app.sim.get_current_action().get("phase",""))=="active":break
		_step()
	app.queue_interaction(_item_kind("bookshelf"),"read")
	app.select_household_member(0);app.sim.needs.hunger=25
	print("PROBE offerable=",app.meal_flow.offerable_food(source)," visit_active=",app.residents.home_visit.active())
	print("PROBE meal_active=",app.residents.home_visit.meal.active()," speaker=",app.residents._speaker(app.residents.home_visit.meal.person()))
	# What does the guest's own offer return, and why?
	var offered:bool=app.residents.home_visit.meal.offer(source)
	print("PROBE offer returned=",offered," meal_state=",app.residents.home_visit.meal.state)
	var count:int=app.meal_flow.call_to_meal(source)
	print("PROBE call_to_meal=",count)
	app.queue_free();await process_frame;quit(0)
