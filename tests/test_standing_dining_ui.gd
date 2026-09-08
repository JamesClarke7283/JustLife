extends "res://tests/test_meal_placement_ui.gd"
## Public cooking/dining and build controls, real frame routes and clock.
## Only fixture intervention is disabling autonomy for four created adults.
var standing_log:Dictionary={"snapshots":[],"commands":[],"save":{}}

func _run()->void:
	screenshot_dir="res://art/standing_dining";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	setdown_observer=load("res://tests/food_setdown_observer.gd").new();setdown_observer.app=app;app.add_child(setdown_observer)
	app.household.member_action_finished.connect(func(id:String,a:Dictionary):member_completed.append(id+":"+str(a.id));observation.events.append({"id":id,"action":a.id,"plate":a.get("meal_plate",""),"day":app.household.day,"minutes":app.household.minutes}))
	if resume_only:await _resume_standing()
	else:await _first_standing()
	standing_log.setdown=setdown_observer.data
	var file:=FileAccess.open(screenshot_dir.path_join("standing_resume.json" if resume_only else "standing_first.json"),FileAccess.WRITE);file.store_string(JSON.stringify(standing_log,"  "));file.close()
	_write_report();app.queue_free();await frames(4)
	print("STANDING_PUBLIC assertions=%d failures=%d resume=%s"%[assertions,failures.size(),resume_only]);quit(0 if failures.is_empty() else 1)

func _first_standing()->void:
	await _enter_new_game()
	for i:int in range(4):
		if i>0:await press("+ Add Lifelet")
		var edit:LineEdit=app.find_children("*","LineEdit",true,false)[0];edit.text=FAMILY_NAMES[i];edit.text_changed.emit(edit.text);await _age("Adult")
	await press_member(FAMILY_NAMES[0]);await press("Find my home",true);await press("Start living",true);await press("Ⅱ")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	await press("Build & buy")
	for value:Dictionary in app.world.items.duplicate():
		if str(value.kind)!="chair":continue
		app.world.object_clicked.emit(value,app.world.camera.unproject_position(value.node.position));await frames(3);await press("Sell",true)
	await press("Live");await press("Ⅱ")
	var batch:String=await _request_batch()
	await press_member(FAMILY_NAMES[3]);await _object_action(first_item("sofa"),"Take a nap")
	await press("▶")
	if not await wait_until(func()->bool:return _active("housemate_3","nap"),"fourth adult walks to an actual nap before dinner",30):return
	await press("Ⅱ");await _request_diners(batch)
	await press("▶")
	if not await wait_until(func()->bool:return _standing_ids().size()>=2 and not _partial_standing_id().is_empty(),"at least two diners walk to separate standing places beside an ongoing nap",60):return
	await press("Ⅱ");await frames(3)
	check(_active("housemate_3","nap"),"The fourth adult remains in an actual nap while standing diners eat.")
	_assert_standing("standing beside existing nap");_record("before_build")
	await screenshot("01_standing_beside_nap",false,false)
	var chosen:String="";var lamp:Dictionary=first_item("lamp")
	for id:String in _standing_ids():
		if app.world.can_place("lamp",app.household.member_sim(id).get_current_action().target_position,lamp.node.rotation_degrees.y):chosen=id;break
	check(not chosen.is_empty(),"A real standing endpoint permits the planned lamp obstruction through Build.")
	if chosen.is_empty():return
	await press_member(str(app.household.member_sim(chosen).character.name))
	var action:Dictionary=app.sim.get_current_action();var plate_id:String=str(action.meal_plate)
	var old_target:Vector3=action.target_position;var progress:float=float(app.household.meals.portion(plate_id).progress)
	await press("Build & buy");await _move_furnishing(str(lamp.id),old_target)
	check(app.sim.get_current_action().phase=="approach" and str(app.sim.get_current_action().meal_plate)==plate_id,"Building over the standing place reroutes its same paid partial plate.")
	check(float(app.household.meals.portion(plate_id).progress)==progress and bool(app.sim.get_current_action().paid),"Paused build changes neither food progress nor payment.")
	_record("lamp_obstruction_pending_route")
	await screenshot("02_build_obstruction_paused",false,false)
	await press("Live");await press("▶")
	if not await wait_until(func()->bool:return _active(chosen,"eat_meal") and str(app.household.member_sim(chosen).get_current_action().get("meal_plate",""))==plate_id,"obstructed diner physically reaches another clear place",30):return
	await press("Ⅱ");await frames(3)
	check(app.sim.get_current_action().target_position.distance_to(old_target)>.3,"The obstructed diner reaches a different exact standing endpoint.")
	_assert_standing("after build reroute");_record("after_build_reroute")
	await screenshot("03_after_build_reroute",false,false)
	progress=float(app.household.meals.portion(plate_id).progress)
	await press("Cancel action");await frames(3)
	var plate:Dictionary=app.household.meals.portion(plate_id)
	check(str(plate.owner).is_empty() and float(plate.progress)==progress,"Public cancellation retains precisely the existing unfinished portion.")
	_assert_placements("canceled standing plate")
	await screenshot("04_canceled_plate",false,false)
	await _object_action(app._find_item(plate_id),"Take a serving")
	await _object_action(first_item("bookshelf"),"Read a book")
	check(app.sim.action_queue.size()==2 and str(app.sim.action_queue[1].id)=="read" and not bool(app.sim.action_queue[1].autonomous),"The player queues reading after the same resumed portion.")
	await press("▶")
	if not await wait_until(func()->bool:return _active(chosen,"eat_meal") and str(app.household.member_sim(chosen).get_current_action().get("meal_plate",""))==plate_id,"canceled partial food is collected and reached again",30):return
	await press("Ⅱ");await frames(3)
	_assert_standing("before paused named save");_record("before_save")
	await screenshot("05_paused_partial_save",false,false)
	expected={"batch":batch,"partial":plate_id,"person":chosen,"food":app.household.meals.get_state(),"members":[]}
	for member:Dictionary in app.household.members:
		expected.members.append({"id":member.id,"position":vec(app.world.actors[str(member.id)].position),"queue":member.sim._json_safe(member.sim.action_queue)})
	check(float(app.household.meals.portion(plate_id).progress)>0 and float(app.household.meals.portion(plate_id).progress)<1,"The named save contains real paid partial nourishment.")
	await _public_save("Standing dinner — exact places and partial plate")
	var out:=FileAccess.open("user://standing_dining_expected.json",FileAccess.WRITE);out.store_string(JSON.stringify(expected));out.close()
	standing_log.save=expected

func _resume_standing()->void:
	expected=JSON.parse_string(FileAccess.get_file_as_string("user://standing_dining_expected.json"))
	await _public_load();await frames(3)
	check(app.sim.speed==0,"Fresh process preserves the deliberate pause.")
	check(_food_restored(expected.food),"Fresh restart retains exact serving IDs, owners, nutrition and food positions with carrier reconstruction.")
	for member:Dictionary in expected.members:
		var sim:LifeSim=app.household.member_sim(str(member.id))
		check(equivalent(vec(app.world.actors[str(member.id)].position),member.position),"Paused restore preserves actual actor location: "+str(member.id))
		check(_same_queue(sim.action_queue,member.queue),"Paused restore preserves destinations, payment, elapsed food and later player instructions: "+str(member.id))
	_record("paused_fresh_restart");await screenshot("06_paused_fresh_restart",false,false)
	await press("▶")
	if not await wait_until(func()->bool:return _active(str(expected.person),"eat_meal"),"saved diner resumes at its exact reserved place",30):return
	await press("Ⅱ");await frames(3);_assert_standing("after saved arrival")
	await screenshot("07_resumed_standing",false,false)
	await press("▶▶▶")
	if not await wait_until(func()->bool:return _batch_done(str(expected.batch)),"all four real servings finish, including the adult’s queued meal after their nap",120):return
	if not await wait_until(func()->bool:return app.household.members.all(func(member:Dictionary)->bool:return member.sim.action_queue.is_empty()),"explicit later reading completes without being replaced",90):return
	await _wait_for_idle_space("standing final dinner")
	await press("Ⅱ");await frames(3)
	_assert_placements("finished standing dinner");_record("all_finished")
	check(app.household.meals.portions.size()==4 and int(app.household.meals.batch(str(expected.batch)).served)==4,"Cancel, build and restart never claim an extra serving.")
	check(observation.events.any(func(event:Dictionary)->bool:return str(event.id)==str(expected.person) and str(event.action)=="read"),"The selected diner completes the later explicit reading instruction.")
	await screenshot("08_finished_and_separated",false,false)

func _object_action(value:Dictionary,label:String)->void:
	check(not value.is_empty(),"Public interaction target exists: "+label)
	if value.is_empty():return
	app.world.object_clicked.emit(value,app.world.camera.unproject_position(value.node.position));await frames(3);await press(label,true)
	standing_log.commands.append({"person":app.bound_member_id,"target":value.id,"action":label,"day":app.household.day,"minutes":app.household.minutes})

func _move_furnishing(id:String,at:Vector3)->void:
	var value:Dictionary=app._find_item(id)
	await _object_action(value,"Move furnishing")
	var screen:Vector2=app.world.camera.unproject_position(at);await mouse_move(screen)
	check(app.world.ghost_valid,"Actual mouse preview accepts the temporary standing-place obstruction.")
	if not app.world.ghost_valid:return
	await mouse_click(screen);await frames(3)
	check(app.pending_move.is_empty() and app._find_item(id).node.position.distance_to(at)<.03,"Actual mouse placement commits the lamp at the reserved point.")

func _active(id:String,action_id:String)->bool:
	var action:Dictionary=app.household.member_sim(id).get_current_action()
	return str(action.get("id",""))==action_id and str(action.get("phase",""))=="active"

func _standing_ids()->Array[String]:
	var result:Array[String]=[]
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if bool(action.get("meal_standing",false)) and str(action.phase)=="active":result.append(str(member.id))
	return result

func _assert_standing(label:String)->void:
	for id:String in _standing_ids():
		var action:Dictionary=app.household.member_sim(id).get_current_action();var at:Vector3=app.world.actors[id].position
		check(at.distance_to(action.target_position)<.02,label+": eating starts only at the exact reserved endpoint: "+id)
		check(app.meal_flow.standing_geometry_clear(at),label+": standing body clears real furnishings and walls: "+id)
		for other:Dictionary in app.household.members:
			if str(other.id)==id or str(other.sim.get_current_action().get("phase",""))!="active":continue
			var gap:float=Vector2(at.x-app.world.actors[str(other.id)].position.x,at.z-app.world.actors[str(other.id)].position.z).length()
			var minimum:float=1.14 if str(other.sim.get_current_action().get("id","")) in ["nap","sleep"] else .84
			check(gap>=minimum,label+": active diner remains separate from active "+str(other.id))

func _record(label:String)->void:
	var members:Array=[]
	for member:Dictionary in app.household.members:
		members.append({"id":member.id,"position":vec(app.world.actors[str(member.id)].position),"queue":member.sim._json_safe(member.sim.action_queue),"motion":member.sim._json_safe(app.motion_states[str(member.id)])})
	standing_log.snapshots.append({"label":label,"day":app.household.day,"minutes":app.household.minutes,"members":members,"food":app.household.meals.get_state()})

func _same_queue(actual:Array,saved:Array)->bool:
	var normalized:Array=JSON.parse_string(JSON.stringify(app.sim._json_safe(actual)))
	if normalized.size()!=saved.size():return false
	for i:int in range(saved.size()):
		if i==0 and str(normalized[i].phase)=="approach" and str(saved[i].phase) in ["active","approach"]:normalized[i].phase=saved[i].phase
		if not saved[i].has("started_day") and normalized[i].get("started_day")==app.household.day:normalized[i].erase("started_day")
	return equivalent(normalized,saved)
