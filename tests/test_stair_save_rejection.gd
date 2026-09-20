extends "res://tests/test_stair_save.gd"

func _rejected(data:Dictionary,label:String)->void:
	var old_member:LifeSim=app.household.selected()
	var old_state:Dictionary=app.household.get_state(app.world.serialize_items())
	var result:Dictionary=app.household.restore_state(data)
	check(not bool(result.ok),label+" is rejected at direct household ingress: "+str(result.get("error","")))
	check(is_same(app.household.selected(),old_member) and app.household.get_state(app.world.serialize_items())==old_state,label+" leaves the old live household unchanged.")
	var library:Dictionary=LifeSaveLibrary._validate_household(data)
	check(not bool(library.ok),label+" is rejected by the named-save validation boundary.")

func _run()->void:
	app=load("res://tests/rejecting_load_controller.gd").new();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup();app.on_ground_clicked(Vector3(2,3.16,4));check(_until_transit("player"),"Existing household is moving before rejected load.")
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://regression/stair_save/fresh_cancel_later_expected.json"))
	var data:Dictionary=expected.household
	for kind:String in ["missing_phase","unknown_phase","queued_front","unpaid_active","wrong_wait_id","string_wait","fractional_negative_wait","missing_shared_day","missing_selected"]:
		var bad:Dictionary=data.duplicate(true)
		var action:Dictionary=bad.members[0].state.action_queue[0]
		var saved:Dictionary=bad.members[0].state.character.world_state
		match kind:
			"missing_phase":action.erase("phase")
			"unknown_phase":action.phase="completed"
			"queued_front":action.phase="queued"
			"unpaid_active":saved.resource_action_active=true
			"wrong_wait_id":saved.waiting_action_id="cook"
			"string_wait":saved.resource_wait_started="-1"
			"fractional_negative_wait":saved.resource_wait_started=-.25
			"missing_shared_day":bad.erase("day")
			"missing_selected":bad.erase("selected_index")
		_rejected(bad,kind)
	var old_world:LifeWorld=app.world;var old_person:LifeSim=app.sim;var old_actor:LifeActor=app.player
	var facts:Dictionary=_saved_facts();var before:Dictionary=app.household.get_state(app.world.serialize_items())
	var child_count:int=app.get_child_count()
	app.load_game(expected.slot)
	check(is_same(app.world,old_world) and is_same(app.sim,old_person) and is_same(app.player,old_actor),"A staged reconstruction failure preserves actual old world, simulator and actor node identities.")
	check(app.household.get_state(app.world.serialize_items())==before and _saved_facts()==facts,"Failed staged load preserves current actions, funds, clock, positions and crossing locks.")
	check(app.get_child_count()==child_count,"Rejected staging frees its isolated viewport and candidate nodes.")
	check(app.notice_label.text.contains("Controlled reconstruction rejection"),"Public loader reports reconstruction rejection, without welcoming a partially loaded household.")
	# Checked actual reconstruction must expose an impossible contact schedule.
	app.household.journeys=app.traversal.snapshot()
	var route:Dictionary=_route("player");var leg:Dictionary=route.legs[int(route.cursor)]
	for gait_stage:Dictionary in leg.schedule.stages:
		gait_stage.before.L+=Vector3(0,10,0);gait_stage.after.L+=Vector3(0,10,0)
	var painted:Dictionary=app.traversal.reconstruct()
	check(not bool(painted.ok) and not app.player.stair_pose_valid,"Actual zero-time pose failure returns a failed reconstruction result.")
	var report:Dictionary={"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute("user://regression/stair_save")
	var file:=FileAccess.open("user://regression/stair_save/rejections_01.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("STAIR_SAVE_REJECTIONS checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
