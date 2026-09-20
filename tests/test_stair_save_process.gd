extends "res://tests/test_stair_save.gd"
var case_name:String=OS.get_environment("STAIR_SAVE_CASE")
var stage_name:String=OS.get_environment("STAIR_SAVE_STAGE")
var expected:Dictionary={}

func _equal(a:Variant,b:Variant)->bool:
	return JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(a),"",true,true))==JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(b),"",true,true))

func _produce()->void:
	if case_name.begins_with("walk"):
		_setup(2)
		var first:String="player" if case_name=="walk_up" else "housemate_1"
		var second:String="housemate_1" if first=="player" else "player"
		app.select_household_member(0 if first=="player" else 1)
		app.on_ground_clicked(Vector3(2,3.16,4) if first=="player" else Vector3(-2,.16,-4))
		check(_until_transit(first),"First directed Lifelet actually enters the requested ascent/descent.")
		app.select_household_member(0 if second=="player" else 1)
		app.on_ground_clicked(Vector3(2,3.16,4) if second=="player" else Vector3(-2,.16,-4))
		var arrived:bool=false
		for frame:int in 800:
			_step()
			if str(_route(second).get("phase",""))=="waiting" and int(_route(second).ticket)>0 and str(_route(first).get("phase",""))=="transit":arrived=true;break
		check(arrived,"Opposing Lifelet reaches the real FIFO while the first remains on stairs.")
		expected.owner=first;expected.waiter=second
	else:
		_setup()
		app.queue_interaction(app._find_item("upper_shelf"),"read")
		if case_name=="cancel_later":app.queue_interaction(app._find_item("ground_shelf"),"read")
		check(_until_transit("player"),"Public read instruction reaches real stair transit before cancellation.")
		app.cancel_current_action()
		check(app.traversal.safety("player"),"Canceling public action leaves a movement-only safe crossing.")
		expected.owner="player";expected.waiter=""
	app.household.set_speed(0);app.overlay_open=true
	expected.facts=_saved_facts();expected.funds=app.household.funds;expected.minutes=app.household.minutes
	check(app.save_game("","Fresh "+case_name),"Public named save writes the paused journey.")
	expected.slot=app.active_save_id
	var read:Dictionary=LifeSaveLibrary.read_slot(expected.slot)
	check(bool(read.ok),"Written slot passes detached public validation: "+str(read.get("error","valid")))
	if bool(read.ok):expected.household=read.data
	DirAccess.make_dir_recursive_absolute("user://regression/stair_save")
	var file:=FileAccess.open("user://regression/stair_save/fresh_"+case_name+"_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected,"  ",true,true));file.close()

func _consume()->void:
	expected=JSON.parse_string(FileAccess.get_file_as_string("user://regression/stair_save/fresh_"+case_name+"_expected.json"))
	var raw:Dictionary=LifeSaveLibrary.read_slot(expected.slot)
	check(bool(raw.ok),"Fresh process reads and validates the existing named slot.")
	if not bool(raw.ok):return
	app.load_game(expected.slot)
	check(_equal(_saved_facts(),expected.facts),"Fresh main restores exact positions, yaw, progress, intent, identities and tickets.")
	check(app.household.funds==int(expected.funds) and app.household.minutes==float(expected.minutes) and app.household.speed==0,"Fresh load keeps wallet, clock and chosen pause.")
	for index:int in app.household.members.size():
		if not _equal(app.household.members[index].sim.get_state().action_queue,expected.household.members[index].state.action_queue):
			print("ACTUAL_QUEUE ",JSON.stringify(app.household.members[index].sim.get_state().action_queue,"",true,true))
			print("EXPECTED_QUEUE ",JSON.stringify(expected.household.members[index].state.action_queue,"",true,true))
		check(_equal(app.household.members[index].sim.get_state().action_queue,expected.household.members[index].state.action_queue),"Fresh load does not begin, discard or change the saved action queue for member "+str(index))
	var owner:LifeActor=app.world.actors[expected.owner]
	check(owner.stair_pose_valid and not owner.stair_presentation.is_empty(),"Fresh paused owner has the reconstructed real stair contact pose.")
	_step(20)
	check(_equal(_saved_facts(),expected.facts),"Twenty paused frames preserve every reconstructed journey fact.")
	app.household.set_speed(1)
	var admissions:Array[String]=[expected.owner]
	var cleared_floor:int=-1
	var saw_next:bool=false
	for frame:int in 2600:
		_step()
		for lock:Dictionary in app.traversal.stairs.values():
			if not str(lock.owner).is_empty() and str(lock.owner)!=admissions[-1]:admissions.append(str(lock.owner))
		if case_name.begins_with("cancel") and not app.traversal.safety("player") and cleared_floor<0:cleared_floor=app.world.point_level(app.world.actors.player.position)
		if case_name=="cancel_later" and str(app.household.member_sim("player").get_current_action().get("phase",""))=="active":saw_next=true;break
		if frame>10 and app.traversal.routes.is_empty():break
	if case_name.begins_with("walk"):
		check(admissions==[str(expected.owner),str(expected.waiter)],"Freshly restored FIFO admits the waiter only after the original owner clears.")
		check(app.world.actors.player.position.distance_to(Vector3(2,3.16,4))<.001 and app.world.actors.housemate_1.position.distance_to(Vector3(-2,.16,-4))<.001,"Both fresh-process opposing walks finish at their intended floors.")
	else:
		check(cleared_floor==1,"Canceled crossing clears the originally reserved upper landing before any later instruction.")
		if case_name=="cancel_later":check(saw_next and app.world.point_level(app.player.position)==0,"Saved later read waits for clearance, descends, and begins at the actual ground shelf.")
		else:check(app.sim.action_queue.is_empty() and app.world.point_level(app.player.position)==1,"Empty canceled queue ends idle on supported upper floor.")
	check(app.traversal.stairs.values().all(func(lock:Dictionary)->bool:return str(lock.owner).is_empty() and lock.queue.is_empty()),"Completed fresh-process crossing releases all stair ownership and queue places.")

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	if stage_name=="produce":_produce()
	else:_consume()
	var report:Dictionary={"checks":checks,"failures":failures,"case":case_name,"stage":stage_name,"process_id":OS.get_process_id()}
	var file:=FileAccess.open("user://regression/stair_save/fresh_"+case_name+"_"+stage_name+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("STAIR_SAVE_PROCESS %s %s checks=%d failures=%d"%[case_name,stage_name,checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
