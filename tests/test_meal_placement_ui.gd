extends "res://tests/test_meal_playthrough.gd"
var setdown_observer:Node
var observation:Dictionary={"events":[],"food":[],"commands":[],"autonomous_washes":0}
func _initialize()->void:
	var path:String=ProjectSettings.globalize_path("res://")
	if not path.trim_suffix("/").get_file().begins_with("justlife-playthrough-") or OS.get_environment("XDG_DATA_HOME")!=path.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR") != path.path_join("userdata/save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		push_error("Placement UI requires an isolated playthrough source and userdata.");quit(2);return
	resume_only="--resume-only" in OS.get_cmdline_user_args();_run.call_deferred()
func _run()->void:
	screenshot_dir="res://art/meal_placement";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	setdown_observer=load("res://tests/food_setdown_observer.gd").new();setdown_observer.app=app;app.add_child(setdown_observer)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):
		member_completed.append(id+":"+str(action.id));observation.events.append({"id":id,"action":action.id,"autonomous":bool(action.get("autonomous",false)),"day":app.household.day,"minutes":app.household.minutes})
		if str(action.id)=="clean_plate" and bool(action.get("autonomous",false)):observation.autonomous_washes+=1)
	if resume_only:
		expected=JSON.parse_string(FileAccess.get_file_as_string("user://meal_placement_expected.json"));observation=expected.observation
		setdown_observer.data=expected.observation.get("setdown",{"releases":[],"maximum_horizontal_metres":0.0})
		await _public_load()
		check(_food_restored(expected.food),"Fresh restart retains exact food identities, servings, owners, progress and placements; held standing food rebuilds its approach.")
		await screenshot("04_standing_restored",false,false)
		await press("▶▶▶")
		await wait_until(func()->bool:return _batch_done(str(expected.batch)),"remaining diners finish with real held food and floor set-down",120)
		await _wait_for_idle_space("standing dinner")
		await press("Ⅱ");await frames(4)
		_assert_placements("all standing diners finished")
		var floor_count:int=0
		for value:Dictionary in app.household.meals.portions:
			if str(value.storage)=="dirty" and str(value.host).is_empty():floor_count+=1
		check(floor_count>=4,"At least four real finished plates occupy distinct floor positions after support removal.")
		await screenshot("05_floor_plates",false,false)
		# Existing personal needs remain unchanged; ordinary autonomy must find
		# time for cleanup around real recovery and scheduled responsibilities.
		for member:Dictionary in app.household.members:member.sim.autonomy=true
		await press("▶▶▶")
		await wait_until(func()->bool:return int(observation.autonomous_washes)>=2,"safe Lifelets autonomously carry and wash at least two dirty plates",180)
		await press("Ⅱ");await frames(4);_assert_placements("after autonomous washing")
		check(int(observation.autonomous_washes)>=2,"Actual rendered sink work removes accumulated dirty plates.")
		await screenshot("06_autonomous_cleanup",false,false)
	else:
		await _enter_new_game()
		for i:int in range(4):
			if i>0:await press("+ Add Lifelet")
			var edit:LineEdit=app.find_children("*","LineEdit",true,false)[0];edit.text=FAMILY_NAMES[i];edit.text_changed.emit(edit.text);await _age("Adult")
		await press_member(FAMILY_NAMES[0]);await press("Find my home",true);await press("Start living",true);await press("Ⅱ")
		for member:Dictionary in app.household.members:member.sim.autonomy=false
		var first:String=await _request_batch()
		await _request_diners(first);await press("▶▶▶")
		await wait_until(func()->bool:return _batch_done(first),"four diners independently consume the first actual batch",120)
		await _wait_for_idle_space("first dinner")
		await press("Ⅱ");await frames(4);_assert_placements("crowded table after first dinner")
		check(app.household.meals.portions.size()==4,"Four pickups conserve the initial four servings.")
		await screenshot("01_crowded_table_clear_positions",false,false)
		await press("Build & buy")
		for value:Dictionary in app.world.items.duplicate():
			if str(value.kind) not in ["chair","dining","counter"]:continue
			app.world.object_clicked.emit(value,app.world.camera.unproject_position(value.node.position));await frames(3);await press("Sell",true)
		await press("Live");await press("Ⅱ");await frames(4);_assert_placements("supported food after public furnishing sale")
		var second:String=await _request_batch()
		await _request_diners(second);await press("▶▶▶")
		await wait_until(func()->bool:return _partial_standing_id()!="","a real standing diner reaches partial food progress",90)
		await press("Ⅱ")
		var person:String=_partial_standing_id();check(not person.is_empty(),"Standing partial meal is observed without injecting arrival or recovery.")
		if not person.is_empty():
			await press_member(str(app.household.member_sim(person).character.name));await screenshot("02_standing_partial",false,false)
			await press("Cancel action");await frames(4);_assert_placements("public cancellation of standing diner")
			await screenshot("03_canceled_plate_supported",false,false)
			# Publicly resume exactly the abandoned partial portion.
			var abandoned:Dictionary={}
			for value:Dictionary in app.household.meals.portions:
				if str(value.batch)==second and float(value.progress)>0 and float(value.progress)<1 and str(value.owner).is_empty():abandoned=value;break
			check(not abandoned.is_empty(),"Cancel leaves its actual unfinished plate available.")
			if not abandoned.is_empty():
				var view:Dictionary=app._find_item(str(abandoned.id));app.world.object_clicked.emit(view,app.world.camera.unproject_position(view.node.position));await frames(3);await press("Take a serving",true)
		await press("▶▶▶")
		await wait_until(func()->bool:return _partial_standing_id()!="","standing meal resumes with actual retained progress",90)
		await press("Ⅱ");await frames(4)
		observation.setdown=setdown_observer.data
		expected={"food":app.household.meals.get_state(),"batch":second,"observation":observation}
		await _public_save("Standing supper — placements and partial food")
		var file:=FileAccess.open("user://meal_placement_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected));file.close()
	observation.setdown=setdown_observer.data
	var file:=FileAccess.open(screenshot_dir.path_join("placement_resume.json" if resume_only else "placement_first.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(observation,"  "));file.close()
	_write_report();app.queue_free();await frames(3);print("MEAL_PLACEMENT_UI assertions=%d failures=%d resume=%s"%[assertions,failures.size(),resume_only]);quit(0 if failures.is_empty() else 1)

func _request_batch()->String:
	await press_member(FAMILY_NAMES[0])
	var previous:int=app.household.meals.batches.size()
	var stove:Dictionary=first_item("stove");app.world.object_clicked.emit(stove,app.world.camera.unproject_position(stove.node.position));await frames(3);await press("Cook a fresh meal",true);await press("Cook garden skillet");await press("▶▶▶")
	await wait_until(func()->bool:return app.household.meals.batches.size()>previous and str(app.household.meals.batches.back().storage)=="surface","real cooking creates and places its new batch",90)
	await press("Ⅱ");await frames(4)
	var id:String=str(app.household.meals.batches.back().id);observation.commands.append({"command":"Cook a fresh meal","batch":id,"day":app.household.day,"minutes":app.household.minutes});return id

func _request_diners(batch:String)->void:
	for member:Dictionary in app.household.members:
		if member.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="eat_meal"):continue
		await press_member(str(member.sim.character.name));var view:Dictionary=app._find_item(batch)
		app.world.object_clicked.emit(view,app.world.camera.unproject_position(view.node.position));await frames(3);await press("Take a serving",true)
		observation.commands.append({"command":"Take a serving","batch":batch,"id":member.id})

func _batch_done(id:String)->bool:
	var batch:Dictionary=app.household.meals.batch(id)
	if batch.is_empty() or int(batch.remaining)!=0:return false
	return app.household.meals.portions.filter(func(p:Dictionary)->bool:return str(p.batch)==id).all(func(p:Dictionary)->bool:return float(p.progress)==1 and str(p.owner).is_empty())

func _partial_standing_id()->String:
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if str(action.get("id",""))!="eat_meal" or str(action.get("phase",""))!="active" or not str(action.get("meal_seat","")).is_empty():continue
		var plate:Dictionary=app.household.meals.portion(str(action.get("meal_plate","")))
		if not plate.is_empty() and float(plate.progress)>.08 and float(plate.progress)<.8:return str(member.id)
	return ""

func _assert_placements(label:String)->void:
	var food:Dictionary=app.household.meals.get_state();var ids:Array=[]
	for member:Dictionary in app.household.members:ids.append(str(member.id))
	check(LifeMeals.validate(food,ids,app.meal_flow.now()).is_empty(),label+": serving and owner ledger remains valid.")
	for value:Dictionary in food.portions+food.batches:
		if not str(value.owner).is_empty() or str(value.storage)=="fridge" or (not value.has("batch") and int(value.remaining)==0):continue
		var at:=Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))
		var host:Dictionary=app._find_item(str(value.host))
		if host.is_empty():
			check(absf(at.y-app.meal_flow._floor_support(at,app.meal_flow._footprint(value)))<.003,label+": unhosted ceramic rests on measured floor: "+str(value.id))
		else:
			check(app.meal_flow._surface_clear(host,host.node.to_local(at),app.meal_flow._footprint(value),str(value.id)),label+": tabletop ceramic has a wholly supported unoccupied footprint: "+str(value.id))
	observation.food.append({"label":label,"food":food,"day":app.household.day,"minutes":app.household.minutes})

func _food_restored(saved:Dictionary)->bool:
	var actual:Dictionary=app.household.meals.get_state();var normalized:Dictionary=saved.duplicate(true)
	for portion:Dictionary in normalized.portions:
		var restored:Dictionary=app.household.meals.portion(str(portion.id))
		if str(portion.storage)!="table" or not str(portion.host).is_empty() or str(portion.owner).is_empty() or str(restored.get("storage",""))!="carried":continue
		var owner:Node=app.household.member_sim(str(portion.owner))
		var action:Dictionary=owner.get_current_action()
		if str(action.get("meal_plate",""))==str(portion.id) and str(action.get("phase",""))=="approach":portion.storage="carried"
	return equivalent(actual,normalized)

func _wait_for_idle_space(label:String) -> void:
	await wait_until(func()->bool:return _idle_space_clear(),label+": idle Lifelets walk into separate positions",12)
	var samples:Array=[]
	for member:Dictionary in app.household.members:
		var motion:Dictionary=app.motion_states[str(member.id)]
		samples.append({"id":member.id,"position":vec(app.world.actors[str(member.id)].position),"queue":member.sim.action_queue.duplicate(true),"walking":bool(motion.walk),"path_index":motion.index,"path_size":motion.path.size()})
	observation.get_or_add("body_spacing",[]).append({"label":label,"members":samples})
	check(_idle_space_clear(),label+": all completed diners have settled at least0.65m apart without queued activities.")

func _idle_space_clear() -> bool:
	for i:int in range(app.household.members.size()):
		var member:Dictionary=app.household.members[i]
		var motion:Dictionary=app.motion_states[str(member.id)]
		if not member.sim.action_queue.is_empty() or bool(motion.walk) or int(motion.index)<motion.path.size():return false
		for j:int in range(i+1,app.household.members.size()):
			var a:Vector3=app.world.actors[str(member.id)].position;var b:Vector3=app.world.actors[str(app.household.members[j].id)].position
			if Vector2(a.x-b.x,a.z-b.z).length()<.65:return false
	return true
