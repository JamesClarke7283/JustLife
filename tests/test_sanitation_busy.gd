extends "res://tests/test_sanitation.gd"
## Cross-system accident controls use actual paid cooking and carried food.
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false);app.start_household();await frames(3);reset_needs()
	var stove:Dictionary=first("stove")
	app.queue_interaction(stove,"cook")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),"Cooking begins after the Lifelet actually reaches the stove.")
	step(2.0)
	var cooking:Dictionary=app.sim.get_current_action();var paid:int=app.household.funds
	app.queue_interaction(first("bookshelf"),"read")
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=9.0;step(1.01)
	check(app.household.sanitation.puddles.size()==1 and is_same(app.sim.get_current_action(),cooking) and bool(cooking.paid),"An accident preserves the actual paid cooking action and its progress.")
	check(app.household.funds==paid and app.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"The accident does not refund/recharge ingredients or erase later instructions.")
	check(until(func()->bool:return not app.household.meals.carried_by("player").is_empty()),"The completed cook picks up a real serving dish under meal custody.")
	var dish:Dictionary=app.household.meals.carried_by("player");var dish_id:String=dish.id
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=9.0;step(1.01)
	check(app.household.sanitation.puddles.size()==2 and str(app.household.meals.carried_by("player").get("id",""))==dish_id,"An accident during real carrying preserves the same dish and owner.")
	app.sim.needs.bladder=10.0
	var remaining:Dictionary=app.household.meals.get_state()
	check(not app.sim.queue_action("plant_wee",first("plant").id) and not app.sim.queue_action("mop_puddle",app.household.sanitation.puddles[0].id),"New pot-use and cleanup instructions refuse occupied food-carrying hands.")
	check(app.household.meals.get_state()==remaining and str(app.sim.get_current_action().id)=="serve_meal","Refusing sanitation leaves food responsibility and the serving action intact.")
	check(until(func()->bool:return app.household.meals.carried_by("player").is_empty()),"The original serving route safely places the held dish after the accident.")
	check(str(app.household.meals.batch(dish_id).storage)=="surface" and app.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"The same food reaches a real surface and the later read instruction remains.")
	await finish()
