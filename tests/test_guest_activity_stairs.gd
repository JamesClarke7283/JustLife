extends "res://tests/test_guest_activity.gd"
const Building=preload("res://scripts/building_state.gd")
func stair_house() -> Dictionary:
	var state: Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["west","east"]}]
	for level: int in [0,1]:
		for side: int in [-1,1]:state.walls.append({"id":("upper_" if level else "")+("west" if side<0 else "east"),"level":level,"x":side*4.0,"z":0.0,"w":.14,"d":10.0,"height":2.6,"cut":true,"material":"eae7d7"})
		state.walls.append({"id":"north_"+str(level),"level":level,"x":0.0,"z":-5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
		for side: int in [-1,1]:state.walls.append({"id":"south_"+str(level)+"_"+str(side),"level":level,"x":side*2.375,"z":5.0,"w":3.25,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	var quote: Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
	check(bool(quote.ok),"Two-floor visitor fixture has real supported stairs")
	return quote.get("after",state)
func _run() -> void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false);_setup()
	var layout: Array=[{"id":"guest_bed","kind":"bed","x":-2.25,"z":3.0,"rotation":0.0,"level":1},{"id":"guest_bath","kind":"bathtub","x":2.5,"z":3.0,"rotation":0.0,"level":1},stair_house()]
	app.loading_game=true;app.setup_live(layout);app.loading_game=false;app.set_process(false)
	for member: Dictionary in app.household.members:
		while not member.sim.action_queue.is_empty():member.sim.cancel_action()
	app.household.set_speed(0)
	var invited: bool=visit().invite("maya")
	check(invited,"Friend is invited to the two-storey home")
	if not invited:
		print("INVITE_DIAGNOSTIC ",app.notice_text," requirement=",visit().requirement("maya")," door=",visit().front_door())
		await _finish();return
	app.household.set_speed(8)
	check(await frames_until(func():return _phase()=="waiting"),"Friend reaches the real exterior door")
	check(visit().welcome("player"),"Host welcomes the upstairs-home visitor")
	app.household.set_speed(8)
	check(await frames_until(func():return _phase()=="inside"),"Coordinated physical entrance finishes before upstairs activity")
	if _phase()!="inside":await _finish();return
	app.household.set_speed(0)
	check(visit().ask_to_stay_over(),"Stay Over finds the actual spare upstairs bed")
	check(str(guest().current_action().get("id",""))=="sleep" and guest().current_action().target_position.y>3,"Spare-bed plan targets the upper-floor mattress approach")
	check(not bool(guest().data.bed_requested),"Accepted spare-bed plan consumes the overnight request once")
	app.household.set_speed(3)
	check(await frames_until(func():return str(app.traversal.routes.get("maya",{}).get("phase",""))=="transit" and float(app.traversal.routes.get("maya",{}).get("distance",0))>.6,1800),"Visitor physically enters the shared authored staircase gait")
	if str(app.traversal.routes.get("maya",{}).get("phase",""))!="transit":await _finish();return
	app.household.set_speed(0)
	var crossing: Dictionary=guest().snapshot()
	var at: Vector3=app.world.actors.maya.position
	check(at.y>.16 and at.y<3.16 and app.world.actors.maya.stair_pose_valid,"Visitor crossing has supported shoe contact between floors")
	check(app.household.members.size()==2,"Stair travel does not make the visitor a playable household member")
	var saved_crossing: bool=app.save_game("","Visitor on stairs")
	check(saved_crossing,"Public save validates the guest crossing and shared stair ownership")
	if not saved_crossing:print("STAIR_SAVE_NOTICE ",app.notice_text);await _finish();return
	var slot: String=app.active_save_id
	var bad: Dictionary=LifeSaveLibrary.read_slot(slot).data.duplicate(true)
	var bad_visit: Dictionary=LifeHomeVisit.saved_visit(bad).value.visit
	bad_visit.activity.journey.members.maya.motion.distance+=.5
	check(not LifeHomeVisit.validate_saved(bad).is_empty(),"Changed stair progress without matching physical contact is rejected")
	var epoch: int=app.load_epoch
	app.load_game(slot)
	check(app.load_epoch==epoch+1,"Public load restores the visitor's stair crossing")
	check(_same_value(crossing,guest().snapshot()) and app.world.actors.maya.position.distance_to(at)<.00001,"Load retains exact visitor route identity, FIFO ticket and stair distance")
	app._process(.2)
	check(_same_value(crossing,guest().snapshot()),"Paused guest crossing remains exact without advancing the household")
	check(app.world.actors.maya.stair_pose_valid and not app.world.actors.maya.stair_presentation.is_empty(),"Paused load reconstructs the visitor's real stair pose")
	app.queue_interaction({"id":"maya","kind":"neighbor","label":"Maya Chen","node":app.world.actors.maya,"size":Vector2(.5,.5)},"joke")
	check(str(app.sim.get_current_action().get("id",""))=="joke" and app.traversal.safety("maya") and app.world.actors.maya.position==at,"Public social command waits without moving or discarding a guest on the stairs")
	app.household.set_speed(8)
	check(await frames_until(func():return str(app.sim.get_current_action().get("id",""))=="joke" and str(app.sim.get_current_action().get("phase",""))=="active",2400),"Queued social action survives until the guest lands and both Lifelets physically meet")
	check(not app.traversal.busy("maya") and app.world.actors.maya.position.y>3,"Visitor clears the protected upper landing before conversation starts")
	var speaker: Vector3=app.world.actors.player.position
	var footprint:=Rect2(Vector2(speaker.x,speaker.z)-Vector2(.3,.3),Vector2(.6,.6))
	check(app.world.construction.building_state.stairs.all(func(stair: Dictionary)->bool:return not footprint.intersects(Building.landing_rect(stair,true))),"The real upstairs conversation leaves the stair landing clear for later travel")
	check(await frames_until(func():return app.sim.get_current_action().is_empty(),1200),"The actual upstairs conversation completes")
	app.household.set_speed(0)
	check(guest().request("sleep","guest_bed",true),"After talking the visitor can resume their spare-bed request")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active",2400),"Restored visitor clears the landing and physically reaches the spare bed")
	app.household.set_speed(0)
	check(app.world.actors.maya.position.y>3 and str(app.world.actors.maya._activity_anchor.get("kind",""))=="bed","Visitor lies on the actual upper mattress")
	guest().cancel("")
	check(await run_action("bath","guest_bath"),"Visitor walks on the upper floor and completes a real bath")
	guest().cancel("")
	# Select the deterministic upper-centre roaming candidate: the old planner
	# parked here on the top landing after skipping the stair opening itself.
	guest().data.serial=4
	check(guest()._roam(),"Visitor chooses an actual autonomous roaming route upstairs")
	var roam_at: Vector3=guest().current_action().get("target_position",Vector3.INF)
	var roam_footprint:=Rect2(Vector2(roam_at.x,roam_at.z)-Vector2(.3,.3),Vector2(.6,.6))
	check(roam_at.y>3 and not app.traversal._aside_blocks_doorway(roam_at) and app.world.construction.building_state.stairs.all(func(stair: Dictionary)->bool:return not roam_footprint.intersects(Building.landing_rect(stair,true))),"Autonomous roaming keeps supported stair landings and doorways clear")
	var roam_done: int=int(guest().data.completed)
	app.household.set_speed(8)
	check(await frames_until(func():return int(guest().data.completed)>roam_done,1200),"Visitor physically reaches the clear upper-floor roaming destination")
	app.household.set_speed(0)
	guest().cancel("")
	check(app.save_game("","Visitor upstairs idle"),"An idle visitor's supported upper-floor anchor saves")
	var idle_slot: String=app.active_save_id
	epoch=app.load_epoch
	app.load_game(idle_slot)
	check(app.load_epoch==epoch+1 and app.world.actors.maya.position.y>3 and not guest().active(),"Idle upstairs load really adopts the upper-floor visitor without dropping or teleporting them")
	check(guest().request("sleep","guest_bed",true),"Visitor can seek the upstairs bed again")
	app.household.set_speed(8)
	check(await frames_until(func():return str(guest().current_action().get("phase",""))=="active",1000),"Second bed request physically arrives")
	visit().goodbye()
	check(_phase()=="leaving" and bool(guest().data.get("returning",false)),"Goodbye schedules a physical downstairs return")
	var descended: bool=false
	for frame: int in 3000:
		if _phase()=="absent":break
		app._process(.05)
		descended=descended or (app.world.actors.maya.position.y>.16 and app.world.actors.maya.position.y<3.16)
		if frame%8==0:await process_frame
	check(descended and _phase()=="absent","Visitor walks downstairs and out through the door before leaving")
	if _phase()!="absent":print("DEPARTURE_DIAGNOSTIC guest=",app.world.actors.maya.position," host=",app.world.actors.player.position," route=",app.traversal.routes.get("maya",{})," locks=",app.traversal.stairs)
	check(app.traversal.stairs.values().all(func(lock: Dictionary)->bool:return str(lock.owner).is_empty() and lock.queue.is_empty()),"Departing guest releases all shared stair locks and FIFO tickets")
	await _finish()
