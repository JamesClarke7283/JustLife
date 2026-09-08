extends "res://tests/test_sanitation_levels.gd"
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://sanitation_pending_expected.json"))
	app.load_game(str(expected.slot))
	check(app.sim.bladder_grace==10.0 and app.household.sanitation.puddles.is_empty() and app.household.speed==0,"Fresh physical load preserves the capped pending accident and exact pause.")
	var saved:Dictionary=expected.data.journeys.members.player.motion
	check(app.traversal.safety("player") and str(route().phase)=="transit" and int(route().identity)==int(saved.identity) and int(route().ticket)==int(saved.ticket) and float(route().distance)==float(saved.distance),"Fresh canceled stair load restores exact decoded safety progress and FIFO identity.")
	var before:Dictionary=facts()
	for index:int in 20:app._process(.05)
	check(facts()==before,"Twenty paused fresh frames cannot move, resolve or change the pending crossing.")
	app.household.set_speed(1)
	var deferred:bool=true
	for index:int in 1800:
		if not app.traversal.busy("player"):break
		app._process(.05);deferred=deferred and app.household.sanitation.puddles.is_empty()
	check(deferred and not app.traversal.busy("player") and app.world.point_level(app.player.position)==1,"Fresh resumed urgency waits for real supported upper clearance.")
	var at:Vector3=app.player.position;app._process(.05)
	check(app.household.sanitation.puddles.size()==1,"The fresh pending accident resolves exactly once after supported arrival.")
	if not app.household.sanitation.puddles.is_empty():
		var value:Dictionary=app.household.sanitation.puddles[0]
		check(Vector3(value.position[0],value.position[1],value.position[2])==at and int(value.level)==1,"Fresh resolution records the actual new landing, without a stale saved-tread position.")
	step(3.0);check(app.household.sanitation.puddles.size()==1,"Fresh continuation cannot repeat the same resolved pending event.")
	var file:=FileAccess.open("user://sanitation_pending.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  ",true,true));file.close()
	print("Sanitation pending: %d checks, %d failures."%[checks,failures.size()])
	app.queue_free();await frames(5);await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
