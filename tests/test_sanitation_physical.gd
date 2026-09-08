extends "res://tests/test_sanitation_levels.gd"
## Draft: actual named V2 save, dry reconstruction and fresh cleanup continuation.
var target_id:String=""
var expected_slot:String=""
func save_named(title:String)->Dictionary:
	check(app.save_game("",title),"Named physical sanitation save succeeds: "+title)
	var read:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(read.ok) and int(read.data.household_version)==2,"The actual named save validates as a physical V2 household.")
	expected_slot=app.active_save_id
	return read.data
func restored_cleanup(expected:Dictionary)->void:
	var current:Dictionary=app.sim.get_current_action()
	var saved:Dictionary=expected.members[int(expected.selected_index)].state.action_queue[0]
	check(app.household.sanitation.puddles==expected.sanitation.puddles,"Restored physical save retains exact decoded puddle data.")
	check(str(current.get("id",""))=="mop_puddle" and str(current.target_id)==target_id and current.phase==saved.phase and float(current.elapsed)==float(saved.elapsed),"Saved upper cleanup retains its exact decoded target, phase and progress.")
	var view:Dictionary=app._find_item(target_id)
	check(not view.is_empty() and view.node.get_parent()==app.world.house and not view.node.is_queued_for_deletion(),"The candidate's current house owns a synchronous clickable upper puddle before any Live tick.")
	check(app.sanitation_flow.app==app and app.sim.sanitation_service==app.sanitation_flow,"The committed household uses the committed sanitation service.")
	var palms:Dictionary={}
	for side:String in ["L","R"]:palms[side]=app.player._joints["Forearm_"+side].to_global(app.player._grip_offset(side))
	app.player.reconstruct_sanitation_pose("mop_puddle")
	check(["L","R"].all(func(side:String)->bool:return app.player._joints["Forearm_"+side].to_global(app.player._grip_offset(side)).distance_to(palms[side])<.00001),"The first restored mop pose is already stable in its installed body space; repeating zero-time reconstruction cannot move either hand.")
func complete_cleanup()->void:
	var completions:Array=[]
	app.household.member_action_finished.connect(func(_member:String,action:Dictionary):
		if str(action.id)=="mop_puddle" and str(action.target_id)==target_id:completions.append(str(action.target_id)))
	app.household.set_speed(1)
	check(until(func()->bool:return app.household.sanitation.find(target_id).is_empty(),400.0),"The saved cleaner completes through the actual upper-floor movement/action controller.")
	check(completions==[target_id] and app._find_item(target_id).is_empty(),"The upper accident and picking geometry are removed by exactly one completion.")
	check(not app.sim.queue_action("mop_puddle",target_id),"A stale upper-floor cleanup cannot complete twice.")
func rejected_physical(data:Dictionary)->void:
	for kind:String in ["wrong_floor","missing_venue_layout","hole"]:
		var bad:Dictionary=data.duplicate(true)
		var value:Dictionary=bad.sanitation.puddles[0]
		match kind:
			"wrong_floor":value.floor_y=.16;value.position[1]=.16
			"missing_venue_layout":
				value.venue="maya_home"
				bad.members[int(bad.selected_index)].state.character.world_state.venue_layouts.erase("maya_home")
			"hole":value.position[0]=0.0;value.position[2]=0.0
		var before:Dictionary=facts()
		var before_world:Node=app.world;var before_flow:Node=app.sanitation_flow;var before_household:Node=app.household
		var count:int=app.get_child_count()
		var slot_data:Dictionary=LifeSaveLibrary.read_slot(expected_slot).data
		var checked:Dictionary=app._prepare_loaded_world(bad)
		check(not bool(checked.ok),"Invalid sanitation support is rejected before physical adoption: "+kind)
		if bool(checked.ok):checked.viewport.free();checked.candidate.free()
		check(app.world==before_world and app.sanitation_flow==before_flow and app.household==before_household and app.get_child_count()==count,"Rejected "+kind+" keeps actual old world/household/service identities and frees staging nodes.")
		check(facts()==before and LifeSaveLibrary.read_slot(expected_slot).data==slot_data,"Rejected "+kind+" leaves poses, clocks, routes, ledger and the named saved data unchanged.")
func produce()->void:
	setup_levels();walk_to(Vector3(2,3.16,3.5))
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=10.0;app._process(.05)
	check(app.household.sanitation.puddles.size()==1,"An actual upper-floor accident exists before the physical save tests.")
	if app.household.sanitation.puddles.is_empty():return
	target_id=str(app.household.sanitation.puddles[0].id)
	reset_needs();walk_to(Vector3(-2,.16,-3.5))
	app.queue_interaction(app._find_item(target_id),"mop_puddle")
	check(until_transit(),"The cleaner climbs the real stairs to reach the retained upper puddle.")
	check(str(app.sim.get_current_action().phase)=="approach","Cross-storey cleanup gives no effect during stair approach.")
	check_read_only("Cleanup in stair approach")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active",400.0),"Mop activation follows supported upstairs arrival.")
	step(2.0);app.household.set_speed(0)
	var expected:Dictionary=save_named("Upper floor - mop in progress")
	check_read_only("Paused active upper mop")
	var old_flow:Node=app.sanitation_flow;var old_world:Node=app.world
	app.load_game(expected_slot)
	check(app.world!=old_world and app.sanitation_flow!=old_flow,"Same-process V2 load atomically adopts its own sanitation service and physical world.")
	restored_cleanup(expected);await frames(3)
	rejected_physical(expected)
	var file:=FileAccess.open("user://sanitation_physical_expected.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"slot":expected_slot,"target":target_id,"data":expected},"  ",true,true));file.close()
	complete_cleanup()
func consume()->void:
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://sanitation_physical_expected.json"))
	target_id=str(expected.target);expected_slot=str(expected.slot)
	app.load_game(expected_slot)
	restored_cleanup(expected.data);await frames(3)
	complete_cleanup()
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	if "--resume" in OS.get_cmdline_user_args():await consume()
	else:await produce()
	var file:=FileAccess.open("user://sanitation_physical_"+("resume" if "--resume" in OS.get_cmdline_user_args() else "first")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  ",true,true));file.close()
	print("Sanitation physical: %d checks, %d failures."%[checks,failures.size()])
	app.queue_free();await frames(5);await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
