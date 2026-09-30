extends "res://tests/test_home_visit.gd"
## Real controller regression: setup may seed needs, but every recovery follows
## the ordinary visitor route, arrival, timed activity and resource ledger.
var completed: Array[String]=[]
func frames_until(predicate: Callable, limit: int=6000) -> bool:
	for i: int in limit:
		if predicate.call():return true
		app._process(.05)
		if i%8==0:await process_frame
	return predicate.call()
func first(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}
func guest():return app.residents.home_visit.activity
func visit():return app.residents.home_visit
func run_action(id: String,target: String) -> bool:
	guest().cancel("")
	var before: int=int(guest().data.completed)
	if not guest().request(id,target,true):return false
	app.household.set_speed(8)
	var done: bool=await frames_until(func():return int(guest().data.completed)>before or not visit().active(),3000)
	app.household.set_speed(0)
	return done and visit().active() and str(guest().data.get("last_completed",""))==id
func fridge_shot() -> void:
	var folder: String=OS.get_environment("GUEST_EVIDENCE_DIR")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	var at: Vector3=first("fridge").node.global_position
	app.world.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	app.world.camera.global_position=at+Vector3(2.3,2.2,2.0)
	app.world.camera.look_at(at+Vector3(0,.9,.35))
	app.ui.visible=false
	await process_frame;RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(folder+"/visitor-fridge-paused-load.png")==OK,"Rendered the actual open fridge and visitor hand after paused load")
	app.ui.visible=true
func _run() -> void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup()
	app.household.groceries.stock=12
	var invited: bool=visit().invite("maya")
	check(invited,"Public friend invitation starts a visit")
	if not invited:
		print("INVITE_DIAGNOSTIC ",app.notice_text," requirement=",visit().requirement("maya")," door=",visit().front_door())
		await _finish();return
	app.household.set_speed(8)
	check(await frames_until(func():return _phase()=="waiting"),"Visitor physically reaches the front door")
	var welcomed: bool=visit().welcome("player")
	check(welcomed,"Public Welcome starts the coordinated entrance")
	if not welcomed:
		print("ENTRANCE_DIAGNOSTIC ",app.notice_text," door=",visit().front_door()," guest=",app.world.actors.maya.position," host=",app.world.actors.player.position)
		await _finish();return
	app.household.set_speed(8)
	check(await frames_until(func():return _phase()=="inside"),"Visitor is inside after the physical greeting")
	if _phase()!="inside":await _finish();return
	app.household.set_speed(0)
	check(visit().ask_to_stay_over(),"Stay Over accepts and seeks a real bed")
	check(str(guest().current_action().get("id",""))=="sleep" or bool(guest().data.bed_requested),"Overnight request owns a sleep route or waits for a free bed")
	guest().cancel("");guest().data.bed_requested=false
	guest().data.needs.bladder=12.0
	guest().data.next_at=guest().now()
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().current_action().get("id",""))=="toilet",100),"Urgent bladder autonomously selects the real toilet")
	var at_start: float=float(guest().data.needs.bladder)
	check(str(guest().current_action().phase)=="approach" and at_start<15,"Selecting the toilet does not grant bladder recovery")
	check(await frames_until(func():return str(guest().data.get("last_completed",""))=="toilet",3000),"Visitor walks through bathroom doors and completes toilet use")
	app.household.set_speed(0)
	check(float(guest().data.needs.bladder)>90,"Bladder recovers only after actual toilet use")
	var sink: Dictionary=guest().current_action()
	check(str(sink.get("id",""))=="wash_hands","Toilet completion queues bathroom hand washing")
	guest().cancel("")
	var fridge: Dictionary=first("fridge")
	var stock: int=app.household.groceries.stock
	guest().data.needs.hunger=20.0
	check(guest().request("snack",str(fridge.id),true),"Visitor accepts a real fridge snack request")
	app.household.set_speed(3)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active" and float(guest().current_action().get("elapsed",0))>=1.2,2400),"Visitor physically reaches the fridge and opens its lower door")
	app.household.set_speed(0)
	var hinge: Node3D=fridge.node.find_child("VisitorFridgeDoor",true,false)
	check(is_instance_valid(hinge) and hinge.rotation.y>.9,"Authored fridge door, handle and finish swing visibly open")
	var lower_door: Node3D=null
	for mesh: MeshInstance3D in fridge.node.find_children("*","MeshInstance3D",true,false):
		if str(mesh.name).begins_with("TintFresh"):lower_door=mesh
	check(is_instance_valid(lower_door) and lower_door.get_parent()==hinge,"The actual imported fresh-food door shares the hinge with its finish")
	var hand_target: Vector3=app.world.actors.maya._activity_anchor.get("care_target",Vector3.INF)
	var hand_local: Vector3=app.world.actors.maya._model.to_local(hand_target)
	check(hand_target.is_finite() and hand_local.z>0 and Vector2(hand_local.x,hand_local.z).length()<.8,"Fridge handle stays reachable in front of the visitor")
	var palm: Vector3=app.world.actors.maya._joints.Forearm_R.to_global(app.world.actors.maya._palm_offset("R"))
	check(palm.distance_to(hand_target)<.2,"Visitor hand reaches the actual open fridge handle")
	check(float(guest().data.needs.hunger)<20,"Reaching for the fridge handle does not feed the visitor")
	var opened: float=hinge.rotation.y if is_instance_valid(hinge) else 0.0
	check(app.save_game("","Guest opening fridge"),"Public save accepts an active visitor opening the fridge")
	var fridge_slot: String=app.active_save_id
	var fridge_epoch: int=app.load_epoch
	app.load_game(fridge_slot)
	fridge=app._find_item(str(fridge.id));hinge=fridge.node.find_child("VisitorFridgeDoor",true,false)
	check(app.load_epoch==fridge_epoch+1 and is_instance_valid(hinge) and is_equal_approx(hinge.rotation.y,opened),"Public load reconstructs the exact fridge hinge angle from saved snack time")
	hand_target=app.world.actors.maya._activity_anchor.get("care_target",Vector3.INF)
	palm=app.world.actors.maya._joints.Forearm_R.to_global(app.world.actors.maya._palm_offset("R"))
	check(palm.distance_to(hand_target)<.2,"Paused load reconstructs the visitor hand at the real fridge handle")
	await fridge_shot()
	app._process(.3)
	check(is_instance_valid(hinge) and is_equal_approx(hinge.rotation.y,opened),"Paused visitor fridge opening remains unchanged")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().data.get("last_completed",""))=="snack",2000),"Visitor physically gets and eats a fridge snack")
	app.household.set_speed(0)
	check(is_instance_valid(hinge) and is_zero_approx(hinge.rotation.y),"Completing the snack closes the real fridge door")
	check(app.household.groceries.stock==stock-1 and float(guest().data.needs.hunger)>45,"Visitor snack consumes one actual grocery and restores hunger")
	check(await run_action("shower",str(first("shower").id)),"Visitor physically reaches and uses the shower")
	var sofa: Dictionary=first("sofa")
	guest().cancel("")
	while not app.household.member_sim("player").action_queue.is_empty():app.household.member_sim("player").cancel_action()
	app.queue_interaction(sofa,"relax")
	app.household.set_speed(8)
	check(await frames_until(func():return str(app.household.member_sim("player").get_current_action().get("phase",""))=="active",2000),"Host physically sits at the sofa")
	app.household.set_speed(0)
	guest().cancel("")
	check(guest().come_join("player"),"Come Join Me creates a real visitor route to the host's sofa")
	check(str(guest().current_action().get("seat_slot",""))!=str(app.household.member_sim("player").get_current_action().get("seat_slot","")),"Visitor reserves a different sofa seat from the host")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active",2000),"Visitor reaches the adjacent sofa seat")
	app.household.set_speed(0)
	var before: Dictionary=guest().snapshot()
	check(app.save_game("","Visitor seated"),"Active visitor seat and needs pass public save validation")
	var slot: String=app.active_save_id
	var epoch: int=app.load_epoch
	app.load_game(slot)
	check(app.load_epoch==epoch+1,"Public load restores the active visitor household")
	check(_same_value(before,guest().snapshot()),"Visitor activity progress and needs survive load exactly")
	var frozen: Dictionary=guest().snapshot()
	app._process(.25)
	check(_same_value(frozen,guest().snapshot()),"Paused update neither moves nor advances visitor needs")
	check(guest().interrupt_for_social() and not guest().active(),"Direct social request releases the visitor's activity reservation")
	await _finish()
