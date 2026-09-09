extends "res://tests/test_courtesy_clear_phases.gd"

func _run()->void:
	phase_tag="clear_cancel";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	audit={"events":[],"mode":mode_tag,"scope":"Actual public protected-beneficiary Cancel action at real saved hold, public named save and separate fresh continuation; no changed bodies/needs/clock or rescue."}
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	if mode_tag=="producer":
		var entries:Array=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("phase_slots.json")))
		var slot:String=str(entries.filter(func(e:Dictionary):return e.phase=="hold")[0].slot)
		await _load_exact(slot);await press_member("Rowan Vale")
		var route:Dictionary=app.traversal.routes.player.duplicate(true);var lock:Dictionary=app.traversal.stairs.stairs_2.duplicate(true)
		var donor:Dictionary=app.traversal.routes.housemate_3.courtesy.duplicate(true);var body:Vector3=app.world.actors.player.position
		var donor_queue:Array=app.household.member_sim("housemate_3").action_queue.duplicate(true)
		await press("Cancel action")
		app.traversal.courtesy.reconcile(app.traversal)
		check(app.household.member_sim("player").action_queue.is_empty() and app.traversal.routes.player.safety,"Public cancellation removes the action and retains the protected safety exit.")
		var same:bool=true
		for key:String in ["identity","ticket","destination","phase","stair_id","exit","clear","custody"]:
			if app.traversal.routes.player.get(key,"")!=route.get(key,""):same=false
		check(same and app.traversal.stairs.stairs_2==lock and app.world.actors.player.position==body,"Cancellation keeps the exact held lock/ticket/body/clear route and custody.")
		check(app.traversal.courtesy.owner(app.traversal)=="housemate_3" and app.traversal.routes.housemate_3.courtesy==donor and app.household.member_sim("housemate_3").action_queue==donor_queue,"The ordinary donor retains exact hold/queue while the same protected physical exit survives cancellation.")
		var facts:Dictionary=_physical_facts()
		for i:int in range(10):app._process(.05);await frames(1)
		check(_physical_facts()==facts,"Ten paused frames preserve canceled safety exit and donor hold without early lock release.")
		await _public_save("Landing clearance — canceled protected action")
		check(_physical_facts()==facts,"Public canceled-exit save preserves complete typed paused physical/custody/queue facts.")
		audit["slot"]=app.active_save_id;audit["saved"]=LifeSaveLibrary.read_slot(app.active_save_id);audit["facts"]=facts
		var file:=FileAccess.open(screenshot_dir.path_join("cancel_slot.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"slot":app.active_save_id}));file.close()
		DirAccess.copy_absolute(LifeSaveLibrary._slot_path(app.active_save_id),ProjectSettings.globalize_path(screenshot_dir.path_join("actual_cancel.json")))
	else:
		var entry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("cancel_slot.json")))
		await _load_exact(str(entry.slot))
		var disk:Dictionary=LifeSaveLibrary.read_slot(str(entry.slot)).data
		check(_same(_project_journeys(disk.journeys),app.traversal.snapshot()),"Fresh canceled-exit journeys match exact decoded facts with explicit typed vector/yaw projection.")
		check(app.household.member_sim("player").action_queue.is_empty() and app.traversal.routes.player.safety and app.traversal.courtesy.owner(app.traversal)=="housemate_3" and app.traversal.stairs.stairs_2.owner=="player","Fresh canceled beneficiary keeps safety route, held staircase and donor.")
		var initial:Dictionary=_physical_facts()
		for i:int in range(10):app._process(.05);await frames(1)
		check(_physical_facts()==initial and app.household.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Fresh canceled safety exit remains exactly paused.")
		audit["continuation"]=await _resume_one("canceled safety exit")
		check(not app.traversal.busy("player") and str(app.traversal.stairs.stairs_2.owner)!="player","Canceled beneficiary physically clears before releasing stair ownership.")
	await _finish()
