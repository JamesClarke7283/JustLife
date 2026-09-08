extends "res://tests/test_stair_controller.gd"
var slot:String=""

func _saved_facts()->Dictionary:
	app._store_motion()
	return app.traversal.snapshot()

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup(2)
	app.on_ground_clicked(Vector3(2,3.16,4))
	app.select_household_member(1);app.on_ground_clicked(Vector3(-2,.16,-4))
	var found:bool=false
	for frame:int in 1500:
		_step()
		var owners:int=0;var waiters:int=0
		for route:Dictionary in app.traversal.routes.values():
			if route.phase=="transit" and float(route.distance)>.6:owners+=1
			if route.phase=="waiting" and int(route.ticket)>0:waiters+=1
		if owners==1 and waiters==1:found=true;break
	check(found,"Actual main reaches opposite owner and arrived waiter before saving.")
	app.household.set_speed(0)
	# Headless verification deliberately does not claim a screenshot preview.
	app.overlay_open=true
	var before:Dictionary=_saved_facts()
	var paid:int=app.household.funds;var minute:float=app.household.minutes
	check(app.save_game("","Stair save integration"),"Public named save accepts the actual paused crossing and waiting queue.")
	slot=app.active_save_id
	var read:Dictionary=LifeSaveLibrary.read_slot(slot)
	print("READ_RESULT ",read.get("error","valid"))
	check(bool(read.ok),"Named slot passes detached household and complete-layout validation.")
	if bool(read.ok):
		check(read.data.household_version==2 and read.data.journeys==JSON.parse_string(JSON.stringify(before,"",true,true)),"Disk JSON preserves every exact journey fact, position and arrival ticket.")
		app.load_game(slot)
		var after:Dictionary=_saved_facts()
		check(after==before,"Actual main loader restores both Lifelets and physical journey facts without advancing time.")
		check(app.household.funds==paid and app.household.minutes==minute and app.household.speed==0,"Loading preserves the paused household clock and wallet.")
		_step(10)
		check(_saved_facts()==before,"Paused reconstructed stair controller remains exactly stationary.")
		app.household.set_speed(1)
		for frame:int in 2400:
			_step()
			if frame>10 and app.traversal.routes.is_empty():break
		check(app.world.actors.player.position.distance_to(Vector3(2,3.16,4))<.001 and app.world.actors.housemate_1.position.distance_to(Vector3(-2,.16,-4))<.001,"Both restored opposing journeys finish on the requested supported floors.")
		check(app.traversal.stairs.values().all(func(lock:Dictionary)->bool:return str(lock.owner).is_empty() and lock.queue.is_empty()),"Both restored crossings release their queue and exit reservations.")
	var report:Dictionary={"checks":checks,"failures":failures,"before":before,"slot":slot,"scope":"Actual main named save/load on one live process, pause and later crossing completion; no fresh-process or food custody claim."}
	var file:=FileAccess.open("user://regression/stair_save/save_03.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("STAIR_SAVE checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
