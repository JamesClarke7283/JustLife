extends "res://tests/test_guest_activity.gd"
func family_setup() -> bool:
	app.household_profiles=[{"name":"Avery Stone","age_stage":"adult","traits":[],"hair":0},{"name":"River Stone","age_stage":"adult","traits":[],"hair":0},{"name":"Robin Stone","age_stage":"child","traits":[],"hair":0},{"name":"Baby Stone","age_stage":"baby","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();app.set_process(false);app.set_sound(false)
	app.household.minutes=1080.0
	for member: Dictionary in app.household.members:
		member.sim.minutes=1080.0;member.sim.autonomy=false;member.sim.set_aging("normal",false);member.sim.household_bills_enabled=false;member.sim.wants.clear()
		for attempt: int in 16:
			if member.sim.action_queue.is_empty():break
			member.sim.cancel_action()
		if not member.sim.action_queue.is_empty():
			check(false,"Fixture could not cancel "+str(member.id)+": "+str(member.sim.action_queue))
			return false
		for need: String in LifeSim.NEED_NAMES:member.sim.needs[need]=85
	app.sim.relationships.maya.friendship=40
	app.household.groceries.stock=20
	app.household.set_speed(0)
	return true
func idle_family() -> bool:
	for member: Dictionary in app.household.members:
		for attempt: int in 16:
			if member.sim.action_queue.is_empty():break
			member.sim.cancel_action()
		if not member.sim.action_queue.is_empty():
			check(false,"Fixture could not cancel "+str(member.id)+": "+str(member.sim.action_queue))
			return false
	return true
func shot(label: String) -> void:
	var folder: String=OS.get_environment("GUEST_EVIDENCE_DIR")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	var at: Vector3=app.world.actors.maya.visual.global_position
	app.world.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	app.world.camera.global_position=at+Vector3(3,3,5)
	app.world.camera.look_at(at+Vector3(0,.6,0))
	app.ui.visible=false
	await process_frame;RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(folder+"/"+label+".png")==OK,"Rendered visitor "+label)
	app.ui.visible=true
func _run() -> void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	if not family_setup():await _finish();return
	var draft: Dictionary=LifePets.candidate(1,0);draft.name="Guest's friend"
	var prepared: Dictionary=app.household.prepare_pet(draft)
	var home: Vector3=app.pet_home_spot()
	var adopted: Dictionary=app.household.commit_pet(prepared.get("request",{}),home)
	check(bool(adopted.get("ok",false)),"Real pet is adopted for the visitor interaction")
	if not bool(adopted.get("ok",false)):await _finish();return
	var pet_id: String=str(adopted.pet.id)
	app.spawn_pet(pet_id,adopted.pet,home,home)
	app.world.add_item({"id":"guest_swing","kind":"outdoor_swing","x":6.5,"z":7.0,"rotation":0.0})
	app.world.add_item({"id":"guest_game","kind":"game_ring_toss","x":-6.5,"z":7.0,"rotation":0.0})
	app._refresh_sim_targets()
	var invited: bool=visit().invite("maya")
	check(invited,"Friend is invited to a home with adults, child, baby and pet")
	if not invited:
		print("INVITE_DIAGNOSTIC ",app.notice_text," requirement=",visit().requirement("maya")," door=",visit().front_door())
		var door: Dictionary=visit().front_door()
		var inside: Vector3=visit()._inside_point("maya",door.position-door.outward*1.7) if not door.is_empty() else Vector3.INF
		var exit: Vector3=visit()._curb_point("maya")
		print("INVITE_GEOMETRY inside=",inside," exit=",exit," strict=",visit()._route(inside,exit,"maya").size() if inside.is_finite() else -1," tolerant=",visit()._route(inside,exit,"maya",true).size() if inside.is_finite() else -1)
		for member: Dictionary in app.household.members:print("INVITE_MEMBER ",member.id," ",app.world.actors[str(member.id)].position," ",member.sim.action_queue)
		await _finish();return
	app.household.set_speed(8)
	check(await frames_until(func():return _phase()=="waiting"),"Family visitor reaches the front door")
	check(visit().welcome("player"),"Host welcomes the family visitor")
	app.household.set_speed(8)
	await frames_until(func():return _phase() in ["inside","absent","leaving"])
	check(_phase()=="inside","Family visitor completes the physical entrance")
	if _phase()!="inside":
		print("FAMILY_ENTRANCE_DIAGNOSTIC phase=",_phase()," notice=",app.notice_text," entrance=",visit().state.get("entrance",{})," host=",app.world.actors.player.position," guest=",app.world.actors.maya.position," queue=",app.sim.action_queue)
		await _finish();return
	var front: Dictionary=visit().front_door()
	check(float(app.world.construction.doors.doors[str(front.id)].progress)<.001,"Host closes the front door after household members physically yield")
	check(not app.traversal._aside_blocks_doorway(app.world.actors.housemate_3.position),"Yielding infant remains clear of the doorway after the welcome")
	app.household.set_speed(0);visit().ask_to_stay_over();guest().cancel("");guest().data.bed_requested=false
	if not idle_family():await _finish();return
	check(guest().request("snack",str(first("fridge").id),true),"Visitor can choose the working fridge before joining the family")
	app.household.set_speed(3)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active" and float(guest().current_action().get("elapsed",0))>=1.2,1800),"Visitor reaches the fridge handle and opens the actual door")
	await shot("fridge_open")
	app.household.set_speed(0);guest().cancel("")
	var hinge: Node3D=first("fridge").node.find_child("VisitorFridgeDoor",true,false)
	check(is_instance_valid(hinge) and is_zero_approx(hinge.rotation.y),"Canceling a visitor snack releases and closes the fridge door")
	var child: LifeSim=app.household.member_sim("housemate_2")
	child.needs.social=30;child.needs.fun=30
	check(await run_action("joke","housemate_2"),"Visitor physically approaches and plays with the child")
	check(child.needs.social>40 and child.needs.fun>30,"Child receives social and fun credit only after the shared activity")
	var baby: LifeSim=app.household.member_sim("housemate_3")
	baby.needs.social=30;baby.needs.fun=30
	check(await run_action("play_with_baby","housemate_3"),"Visitor physically approaches and plays with the infant")
	check(baby.needs.social>40 and baby.needs.fun>45,"Infant shared play restores social and fun needs")
	guest().cancel("")
	var bond: float=LifePetCare.bond(app.household.pet_care(pet_id),"maya")
	guest().show_choices()
	var play: Button=app.overlay.find_child("GuestActivity_pet_play_"+pet_id,true,false)
	check(is_instance_valid(play),"Visitor activity card exposes the actual pet Play button")
	if is_instance_valid(play):play.pressed.emit()
	check(guest().holds_pet(pet_id) or str(guest().data.get("pending_pet",{}).get("target",""))==pet_id,"Pet Play reserves the real pet or waits for its safe furnishing exit")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active",1800),"Visitor physically reaches the pet before play")
	await shot("pet_play")
	app.household.set_speed(0)
	check(not str(app.pet_actors[pet_id].interaction).is_empty(),"Paired visitor play actually animates the pet")
	check(bool(app.pet_behavior().command(pet_id,"pet_free").get("ok",false)),"Free Will accepts the public pet command during visitor play")
	check(not guest().holds_pet(pet_id) and not guest().active() and str(app.pet_actors[pet_id].interaction).is_empty(),"Free Will immediately releases visitor reservation and pet animation")
	check(is_equal_approx(LifePetCare.bond(app.household.pet_care(pet_id),"maya"),bond),"Interrupted visitor play earns no completion credit")
	check(guest().request("pet_play",pet_id,true),"Visitor can request pet play again after Free Will")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().data.get("last_completed",""))=="pet_play",1800),"Visitor completes a paired pet Play interaction")
	app.household.set_speed(0)
	check(LifePetCare.bond(app.household.pet_care(pet_id),"maya")>bond,"Completed visitor pet play credits the visitor's own bond")
	check(await run_action("pet_pet",pet_id),"Visitor also physically pets the same animal")
	guest().cancel("")
	if not idle_family():await _finish();return
	app.select_household_member(0)
	app.queue_interaction(app._find_item("guest_swing"),"enjoy_outdoors")
	app.household.set_speed(8)
	check(await frames_until(func():return str(app.sim.get_current_action().get("phase",""))=="active",1800),"Host physically sits on the garden swing")
	app.household.set_speed(0);guest().cancel("")
	check(guest().come_join("player"),"Come Join Me routes the visitor to the same garden swing")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active",1800),"Visitor arrives at their own garden swing seat")
	check(str(guest().current_action().get("seat_slot",""))!=str(app.sim.get_current_action().get("seat_slot","")),"Swing companions reserve distinct seats")
	await shot("garden_swing")
	app.household.set_speed(0);guest().cancel("")
	if not idle_family():await _finish();return
	app.queue_interaction(app._find_item("guest_game"),"play_garden_game")
	app.household.set_speed(8)
	check(await frames_until(func():return str(app.sim.get_current_action().get("phase",""))=="active",1800),"Host physically reaches a lawn game")
	app.household.set_speed(0);guest().cancel("")
	check(guest().come_join("player"),"Come Join Me reserves a separate side of the host's lawn game")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active",1800),"Visitor physically joins the lawn game")
	check(app.world.actors.maya.position.distance_to(app.world.actors.player.position)>=.8,"Lawn-game players retain separate body positions")
	await shot("lawn_game")
	app.household.set_speed(0);guest().cancel("")
	if not idle_family():await _finish();return
	guest().data.next_at=guest().now()+120;guest().data.needs.hunger=65
	app.sim.needs.hunger=30
	app.meal_flow.queue_recipe(str(first("stove").id),"garden_skillet")
	app.household.set_speed(8)
	check(await frames_until(func():return not app.household.meals.batches.is_empty(),2400),"Host physically cooks a complete meal while the visitor is present")
	if not app.household.meals.batches.is_empty():
		var batch: Dictionary=app.household.meals.batches[-1]
		check(int(batch.get("guest_extra",0))==1 and int(batch.initial)==5,"Cooking creates exactly one extra real serving for the visitor")
		check(await frames_until(func():return str(visit().meal.state.get("phase",""))=="eating",2600),"Serving automatically brings the visitor to a real plate and eating place")
		await shot("shared_meal")
		check(await frames_until(func():return not visit().meal.active(),2400),"Visitor finishes the automatically served meal")
		app.household.set_speed(0)
		check(float(guest().data.needs.hunger)>80,"Actual guest meal consumption restores hunger")
		check(app.save_game("","Visitor family and dinner"),"Public save validates extra serving accounting and guest needs")
		var slot: String=app.active_save_id;var epoch: int=app.load_epoch
		app.load_game(slot)
		check(app.load_epoch==epoch+1 and int(app.household.meals.batches[-1].initial)==5,"Full load preserves the extra serving and family visitor")
	await _finish()
