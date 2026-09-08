extends "res://tests/test_sanitation_levels.gd"
var support_facts:Array=[]
func edge_and_build()->void:
	setup_levels();walk_to(Vector3(3.8,3.16,3.5))
	var exact:Vector3=app.player.position
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=10.0;app._process(.05)
	check(app.household.sanitation.puddles.size()==1,"A narrow but supported upper standing point can have its pending accident.")
	if app.household.sanitation.puddles.is_empty():return
	var value:Dictionary=app.household.sanitation.puddles[0]
	check(Vector3(value.position[0],value.position[1],value.position[2])==exact and float(value.scale)<1.0,"The wet patch shrinks at the edge while preserving the actor's exact accident coordinates.")
	check(Building.footprint_supported(app.world.construction.building_state,1,LifeSanitation.bounds(value)),"The complete persisted wet-patch footprint fits on the real upper slab.")
	var id:String=str(value.id)
	reset_needs();walk_to(Vector3(-2,.16,-3.5));app.set_build_mode(true)
	for name:String in ["upper_plant","upper_shelf"]:app.sell_item(app._find_item(name))
	check(app._find_item("upper_plant").is_empty() and app._find_item("upper_shelf").is_empty(),"Actual Build selling clears upper furnishings before reviewing floor support.")
	var ledger:Dictionary=app.household.sanitation.get_state();var clock:float=app.household.minutes
	var detached:Dictionary=app.build_protection_context();detached.sanitation.puddles.clear()
	check(app.household.sanitation.get_state()==ledger,"Detached Build sanitation facts cannot mutate the live ledger.")
	var quote:Dictionary=app.build_transactions.prepare({"op":"structure","tool":"wall","level":0,"ax":5.0,"az":1.0,"bx":6.0,"bz":1.0},true)
	check(bool(quote.ok),"An unrelated ground wall remains available while the upper wet patch persists.")
	if bool(quote.ok):app.on_construction({"valid":true,"build_quote":quote});app.undo_build()
	check(app.household.sanitation.get_state()==ledger and app.household.minutes==clock,"Actual unrelated Build and Undo retain exact sanitation records and urgency time.")
	var removed_walls:int=0
	var upper_walls:Array=app.world.construction.building_state.walls.filter(func(wall:Dictionary)->bool:return int(wall.level)==1).duplicate(true)
	for wall:Dictionary in upper_walls:
		var wall_quote:Dictionary=app.build_transactions.prepare({"op":"remove","id":str(wall.id)},true)
		check(bool(wall_quote.ok),"The empty upper wall can be removed before reviewing its floor: "+str(wall_quote.get("error","valid")))
		if bool(wall_quote.ok):app.on_construction({"valid":true,"build_quote":wall_quote});removed_walls+=1
	var stair_id:String=str(app.world.construction.building_state.stairs[0].id)
	quote=app.build_transactions.prepare({"op":"remove","id":stair_id},true)
	check(bool(quote.ok),"An unoccupied staircase can be removed before separately reviewing upper-floor demolition.")
	if bool(quote.ok):
		app.on_construction({"valid":true,"build_quote":quote})
		var before:Dictionary=app.world.construction.snapshot();var funds:int=app.household.funds
		var remove:Dictionary=app.build_transactions.prepare({"op":"remove","id":"upper"},true)
		check(not bool(remove.ok) and str(remove.get("error","")).contains("Mop"),"Actual upper-floor demolition identifies the retained accident as its support blocker: "+str(remove.get("error","unexpected acceptance")))
		check(app.world.construction.snapshot()==before and app.household.funds==funds and app.household.sanitation.get_state()==ledger,"Rejected supporting-floor demolition changes neither geometry, money nor wet patch.")
		app.undo_build()
	for index:int in removed_walls:app.undo_build()
	app.set_build_mode(false);app.household.set_speed(1)
	app.queue_interaction(app._find_item(id),"mop_puddle")
	check(until(func()->bool:return app.household.sanitation.find(id).is_empty(),400.0),"After restoring the stair, the Lifelet physically climbs and cleans the narrow upper patch.")
	check(app._find_item(id).is_empty(),"Cleaning removes the edge picking geometry as well as its record.")
	support_facts.append({"edge":value.duplicate(true),"ledger_after":app.household.sanitation.get_state()})
func cooking_custody()->void:
	setup_levels();app.loading_game=true
	app.setup_live([{"id":"ground_stove","kind":"stove","x":-2.0,"z":-2.0,"rotation":0.0},{"id":"upper_table","kind":"dining","x":2.0,"z":0.0,"rotation":0.0,"level":1},{"id":"ground_shelf","kind":"bookshelf","x":-3.25,"z":0.0,"rotation":0.0},fixture()])
	app.loading_game=false;reset_needs();app.player.position=Vector3(-2,.16,-4);app.world.actors.housemate_1.position=Vector3(3,.16,3.5);app._store_motion();app._refresh_sim_targets(false)
	var funds:int=app.household.funds
	app.meal_flow.queue_recipe("ground_stove","garden_skillet")
	var cooking_paid:bool=false
	for frame:int in 2400:
		app._process(.05)
		if str(app.sim.get_current_action().get("id",""))=="serve_meal" and str(route().get("phase",""))=="transit" and float(route().distance)>.6:cooking_paid=true;break
	check(cooking_paid,"Actual paid cooking carries its original serving dish onto the real staircase.")
	if not cooking_paid:return
	var batch:Dictionary=app.household.meals.batches[0];var id:String=str(batch.id)
	check(app.household.funds==funds-25 and int(batch.remaining)==4,"The fixture paid exactly once for four genuine cooked servings.")
	app.queue_interaction(app._find_item("ground_shelf"),"read");app.cancel_current_action()
	var later:Dictionary=app.sim.get_current_action();var ledger:Dictionary=app.household.meals.get_state()
	var identity:int=int(route().identity);var ticket:int=int(route().ticket)
	check(app.traversal.safety("player") and str(route().custody)==id,"Actual cancel preserves stair safety and the original cooked dish custody.")
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=10.0
	var intact:bool=true;var deferred:bool=true
	for frame:int in 2000:
		if not app.traversal.busy("player"):break
		app._process(.05)
		deferred=deferred and app.household.sanitation.puddles.is_empty()
		if app.traversal.busy("player"):
			intact=intact and app.household.meals.get_state()==ledger and int(route().identity)==identity and int(route().ticket)==ticket and str(route().custody)==id and is_same(later,app.sim.get_current_action()) and str(later.phase)=="approach" and float(later.elapsed)==0.0
	check(deferred and intact,"Capped urgency preserves every cooked-food record, stair owner/ticket and unstarted later action until safe clearance.")
	check(not app.traversal.busy("player") and str(batch.owner).is_empty() and int(batch.remaining)==4,"The existing meal controller releases the same four-serving dish once at its supported upper landing.")
	app._process(.05)
	check(app.household.sanitation.puddles.size()==1 and int(app.household.sanitation.puddles[0].level)==1,"Only after genuine custody clearance does the upper landing receive one accident.")
	check(app.household.funds==funds-25 and app.household.meals.batches.size()==1 and app.household.meals.portions.is_empty(),"The accident grants no food, serving, refund or extra cooking charge.")
	check(until(func()->bool:return str(later.phase)=="active",400.0) and is_same(later,app.sim.get_current_action()) and app.world.point_level(app.player.position)==0,"The original later read descends naturally and starts at its intended ground-floor shelf.")
	support_facts.append({"paid_cooking":true,"sanitation":app.household.sanitation.get_state(),"food":app.household.meals.get_state()})
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	edge_and_build();cooking_custody()
	var file:=FileAccess.open("user://sanitation_support.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":support_facts},"  ",true,true));file.close()
	print("Sanitation support: %d checks, %d failures."%[checks,failures.size()])
	app.queue_free();await frames(5);await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
