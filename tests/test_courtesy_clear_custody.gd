extends "res://tests/test_courtesy_clear_phases.gd"

func _run()->void:
	phase_tag="clear_custody";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	audit={"events":[],"mode":mode_tag,"scope":"Explicit custody component: production ledger claims one serving from the naturally earned existing meal, then registers it on the real canceled safety route. This is not a physical pickup claim. Public save/fresh and subsequent protected motion/setdown are real; no needs/clock/progress injection."}
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	if mode_tag=="producer":await _custody_produce()
	else:await _custody_fresh()
	await _finish()

func _custody_produce()->void:
	var entries:Array=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("phase_slots.json")))
	await _load_exact(str(entries.filter(func(e:Dictionary):return e.phase=="hold")[0].slot));await press_member("Rowan Vale")
	await press("Cancel action")
	var food=app.household.meals;var before:Dictionary=food.get_state()
	var portion:Dictionary=food.claim("meal_1","player",_now())
	check(not portion.is_empty(),"Production ledger issues one fresh serving from the checkpoint's existing earned meal.")
	if portion.is_empty():return
	app.traversal.routes.player.custody=str(portion.id);app.meal_flow.sync_world(true)
	check(int(food.batch("meal_1").remaining)==int(before.batches[0].remaining)-1 and int(food.batch("meal_1").served)==int(before.batches[0].served)+1 and food.portions.size()==before.portions.size()+1,"Declared custody component transfers exactly one existing serving without changing progress or inventing a batch.")
	var t:LifeTraversal=app.traversal;var helper=t.courtesy;var id:String=str(portion.id)
	check(helper._stair_clear(t,"player") and helper._still_owned(t,"housemate_3"),"A safety-clear beneficiary with matching real carried custody retains the donor.")
	for fault:String in ["missing","foreign","venue","unsafe"]:
		match fault:
			"missing":t.routes.player.custody="plate_missing"
			"foreign":portion.owner="housemate_2"
			"venue":portion.venue="library"
			"unsafe":t.routes.player.safety=false
		check(not helper._stair_clear(t,"player"),"Protected custody classifier refuses "+fault+" ownership.")
		t.routes.player.custody=id;portion.owner="player";portion.venue="home";t.routes.player.safety=true
	var facts:Dictionary=_physical_facts()
	for i:int in range(10):app._process(.05);await frames(1)
	check(_physical_facts()==facts,"Ten paused custody steps preserve the real serving/progress/owner and both protected/courtesy facts.")
	await _public_save("Component — landing with real held portion")
	check(_physical_facts()==facts,"Named custody save preserves all typed physical/food/queue/clock and protected facts.")
	audit["slot"]=app.active_save_id;audit["plate"]=id;audit["facts"]=facts;audit["before_claim"]=before
	var file:=FileAccess.open(screenshot_dir.path_join("custody_slot.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"slot":app.active_save_id,"plate":id}));file.close()
	DirAccess.copy_absolute(LifeSaveLibrary._slot_path(app.active_save_id),ProjectSettings.globalize_path(screenshot_dir.path_join("actual_custody.json")))

func _custody_fresh()->void:
	var entry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("custody_slot.json")))
	await _load_exact(str(entry.slot));var disk:Dictionary=LifeSaveLibrary.read_slot(str(entry.slot)).data
	var food=app.household.meals;var before:Dictionary=food.get_state();var plate:Dictionary=food.portion(str(entry.plate))
	var batch:Dictionary=food.batch(str(plate.batch));var host_id:String=str(batch.host)
	var host:Dictionary=app._find_item(host_id);var host_transform:Transform3D=host.node.global_transform
	var layout_before:Dictionary=app.world.construction.snapshot().duplicate(true)
	check(_same(_project_journeys(disk.journeys),app.traversal.snapshot()) and before==_decoded_integer_fields(disk.meals,["version","serial"],"food"),"Fresh real custody and authoritative journey data match decoded saved facts with only declared scalar/typed projections.")
	check(app.traversal.courtesy._stair_clear(app.traversal,"player") and app.traversal.routes.player.custody==entry.plate and plate.owner=="player" and plate.storage=="carried","Fresh held portion belongs uniquely to the canceled protected stair walk.")
	var paused:Dictionary=_physical_facts()
	for i:int in range(10):app._process(.05);await frames(1)
	check(_physical_facts()==paused,"Fresh paused custody advances no food/action/clock or protected ownership.")
	audit["continuation"]=await _resume_one("real held custody")
	check(str(plate.owner).is_empty() and str(plate.storage)=="surface" and float(plate.progress)==0,"Physical clear sets the exact unfinished portion down once before retiring the staircase.")
	var projected:Array=before.batches.duplicate(true)
	var projected_count:int=0
	for saved:Dictionary in projected:
		if str(saved.id)!=str(plate.batch):continue
		var offset:Vector3=Vector3(float(saved.offset[0]),float(saved.offset[1]),float(saved.offset[2]))
		saved.position=LifeJourneyState.packed(host.node.to_global(offset));projected_count+=1
	check(projected_count==1 and str(batch.storage)=="surface" and str(batch.host)==host_id and host.node.global_transform==host_transform and app.world.construction.snapshot()==layout_before,"Only the same actual hosted surface batch receives its existing unchanged host-transform position projection.")
	check(food.batches==projected and food.portions.size()==before.portions.size() and food.serial==before.serial,"Complete batch dictionaries remain exact with only that code-derived hosted position; portion count/serial and all serving amounts remain exact.")
	audit["batch_position_projection"]={"formula":"meal_flow.sync_world: host.node.to_global(Vector3(offset[0],offset[1],offset[2]))","expected_batches":projected,"unchanged_host":host_id,"host_origin":host_transform.origin,"host_basis":[host_transform.basis.x,host_transform.basis.y,host_transform.basis.z]}
	check(not app.traversal.busy("player") and app.traversal.stairs.stairs_2.owner!="player","Custody is released through actual safe setdown before the lock retires.")
	audit["food_before"]=before;audit["food_after"]=food.get_state()
