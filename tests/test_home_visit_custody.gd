extends "res://tests/test_home_visit.gd"
func _item(kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}
var finished:Array[String]=[]
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false);_setup()
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):
		if id=="player":finished.append(str(action.id)))
	app.queue_interaction(_item("stove"),"cook")
	for index:int in 500:
		if str(app.sim.get_current_action().get("phase",""))=="active":break
		_step()
	var cook:Dictionary=app.sim.get_current_action()
	check(str(cook.get("id",""))=="cook" and str(cook.get("phase",""))=="active" and bool(cook.paid),"A real paid cooking action is active before invitation")
	app.queue_interaction(_item("bookshelf"),"read")
	var chef:LifeSim=app.sim
	var funds:int=app.household.funds
	var queue:Array=chef.action_queue.duplicate(true)
	var food:Dictionary=app.household.meals.get_state().duplicate(true)
	var motion:Dictionary=app.motion_states.duplicate(true)
	check(app.residents.home_visit.invite("leo"),"A second household friend can invite Leo during real paid cooking")
	check(is_same(chef.get_current_action(),cook) and chef.action_queue==queue and app.household.funds==funds and app.household.meals.get_state()==food and app.motion_states==motion,"Invitation preserves the paid action, later queue, wallet, food and existing motion")
	app.select_household_member(1)
	check(_until("waiting"),"Leo physically arrives while the other household Lifelet continues work")
	check(app.residents.home_visit.welcome(app.household.selected_id()),"Another household Lifelet can welcome the guest")
	check(_until("inside"),"Welcome succeeds alongside the first Lifelet's ordinary kitchen work")
	check(app.household.funds==funds,"Concurrent Welcome neither refunds nor charges cooking ingredients")
	check(chef.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read") or finished.has("read"),"The chef's later reading instruction remains or completes normally")
	var food_before:Dictionary=app.household.meals.get_state().duplicate(true)
	var queue_before:Array=chef.action_queue.duplicate(true)
	app.residents.home_visit.goodbye()
	check(chef.action_queue==queue_before and app.household.meals.get_state()==food_before and app.household.funds==funds,"Goodbye preserves the unrelated chef queue, food custody and wallet")
	check(_until("absent"),"Leo's physical departure completes during household work")
	await _finish()
