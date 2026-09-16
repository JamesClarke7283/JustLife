extends "res://tests/test_stair_food_custody.gd"

func _food_setup()->void:
	super._food_setup()
	if not failures.is_empty():return
	app.set_build_mode(true)
	var funds:int=app.household.funds
	var quote:Dictionary=app.build_transactions.prepare({"op":"add","collection":"roofs","record":{"level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"pitch":.5,"rotation":90,"material":"57736a","supports":["upper_north","upper_south"]}},true)
	check(bool(quote.ok),"Actual upstairs roof previews against the meal home's bearing walls and furnishings: "+str(quote.get("error","valid")))
	if not bool(quote.ok):return
	app.on_construction({"valid":true,"build_quote":quote})
	check(app.world.construction.roof_nodes.size()==1 and app.household.funds==funds-1440 and app.household.members.all(func(member:Dictionary)->bool:return member.sim.funds==funds-1440),"Public Build callback installs the real upper roof and immediately charges the whole household exactly once.")
	check(app.build_undo.size()==1,"Purchased roof has one real Build history entry.")
	app.set_build_mode(false);app.household.set_speed(1)
	check(app.build_undo.is_empty(),"Leaving Build commits the roof and clears the completed session's Undo history.")

func _protected_build_after_cooking()->void:
	var before:Dictionary=app.build_protection_context();var before_facts:Dictionary=_saved_facts()
	var ledger:Dictionary=app.household.meals.get_state();var money:int=app.household.funds
	var building:Dictionary=app.world.construction.snapshot()
	var clock:float=app.household.minutes
	app.overlay_open=false;app.set_build_mode(true)
	check(app.build_undo.is_empty(),"Returning to Build starts a fresh Undo history while retaining the existing roof.")
	var route:Dictionary=_route("player");var clear:Vector3=route.clear
	var blocked:Dictionary=app.build_transactions.prepare({"op":"structure","tool":"wall","level":int(food_expected.landing_level),"ax":clear.x-.5,"az":clear.z,"bx":clear.x+.5,"bz":clear.z},true)
	check(not bool(blocked.ok),"Actual paid-food crossing prevents construction through its reserved landing.")
	check(app.build_protection_context()==before and _equal(_saved_facts(),before_facts) and app.household.funds==money,"Rejected occupied-landing preview leaves exact real food, route, geometry and wallet intact.")
	var quote:Dictionary=app.build_transactions.prepare({"op":"structure","tool":"wall","level":0,"ax":5.0,"az":1.0,"bx":6.0,"bz":1.0},true)
	check(bool(quote.ok),"An unrelated wall is still buildable while the original cooked dish completes a canceled trip: "+str(quote.get("error","valid")))
	if not bool(quote.ok):return
	app.on_construction({"valid":true,"build_quote":quote})
	check(app.build_undo.size()==1,"Unrelated wall purchase appends one entry to this Build session's history.")
	check(app.household.funds==money-int(quote.cost),"Unrelated wall purchase debits its exact quoted price once.")
	check(_equal(_saved_facts(),before_facts) and _equal(app.household.meals.get_state(),ledger) and app.household.minutes==clock,"Actual purchase preserves paid food progress, queued later work, stair identity and exact clock.")
	app.undo_build()
	check(app.build_undo.is_empty(),"Undo removes the new session's single wall entry.")
	check(app.household.funds==money and app.build_transactions._same_geometry(building,app.world.construction.snapshot()),"Undo refunds only the unrelated wall and retains the previously purchased roof.")
	check(_equal(_saved_facts(),before_facts) and _equal(app.household.meals.get_state(),ledger),"Undo leaves the original canceled food journey unchanged.")
	app.world.set_view_level(1)
	app.on_placement("plant",Vector3(-3,3.16,-3),0)
	check(app.build_undo.size()==1 and app.household.funds==money-45 and app.household.members.all(func(member:Dictionary)->bool:return member.sim.funds==money-45),"Unrelated real furnishing purchase charges every household member once during the actual paid-food crossing.")
	check(_equal(_saved_facts(),before_facts) and _equal(app.household.meals.get_state(),ledger) and app.household.minutes==clock,"Furnishing purchase preserves actual paid food, later reading, stair custody and clock.")
	app.undo_build()
	check(app.build_undo.is_empty() and app.household.funds==money and app.household.members.all(func(member:Dictionary)->bool:return member.sim.funds==money),"Furnishing undo restores the original shared wallet before saving the real roofed home.")
	check(_equal(_saved_facts(),before_facts) and _equal(app.household.meals.get_state(),ledger) and app.household.minutes==clock and app.build_transactions._same_geometry(building,app.world.construction.snapshot()),"Furnishing undo keeps the original roof, actual meal fraction, later queue and safe crossing.")
	app.set_build_mode(false);app.household.set_speed(0);app.overlay_open=true
	food_expected.building=app.world.construction.snapshot()
	food_expected.facts=_saved_facts()
	check(app.save_game("","Built home food "+case_name),"Public main saves the roofed home after real cooking, cancellation, Build and Undo.")
	food_expected.slot=app.active_save_id
	var saved:Dictionary=LifeSaveLibrary.read_slot(str(food_expected.slot))
	check(bool(saved.ok),"Roofed food/custody save passes the complete detached validator: "+str(saved.get("error","valid")))
	if bool(saved.ok):
		var stored:Dictionary={}
		for record:Dictionary in saved.data.world:
			if str(record.get("kind",""))=="__construction":stored=record
		check(_equal(stored,food_expected.building),"Named file retains the exact roof, structure revision and allocation state.")
	var file:=FileAccess.open("user://regression/stair_save/food_"+case_name+"_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(LifeSaveLibrary._json_safe(food_expected),"  ",true,true));file.close()

func _run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://regression/stair_save"))
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	if stage_name=="produce":
		_food_produce()
		if failures.is_empty():_protected_build_after_cooking()
	else:
		_food_consume()
		if not food_expected.is_empty():
			check(app.world.construction.roof_nodes.size()==1 and _equal(app.world.construction.snapshot(),food_expected.building),"Fresh real world retains the exact purchased roof and post-Undo structure after food continuation.")
	var report:Dictionary={"checks":checks,"failures":failures,"case":case_name,"stage":stage_name,"process_id":OS.get_process_id(),"scope":"Actual roof purchase, paid cooking/eating, food stair cancellation, protected Build edit and Undo, then separate-process full main save/load/continuation. Manual50ms frames and public controller callbacks, not pointer UI."}
	var file:=FileAccess.open("user://regression/stair_save/build_food_"+case_name+"_"+stage_name+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("BUILD_FOOD_SAVE %s %s checks=%d failures=%d"%[case_name,stage_name,checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.3).timeout;quit(0 if failures.is_empty() else 1)
