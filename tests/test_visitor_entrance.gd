extends "res://tests/test_home_visit.gd"
## Public invitation and welcome sequence, including physical door custody.
var stages:Array[String]=[]
var guest_touched:bool=false
var host_touched:bool=false
var crossed_open:bool=false
var entrance_door:Dictionary={}
var host_grip_error:float=0.0
var captures:Dictionary={}
func visit()->LifeHomeVisit:return app.residents.home_visit
func wait_until(predicate:Callable,limit:int=3000)->bool:
	for index:int in limit:
		if predicate.call():return true
		app._process(.05)
		var stage:String=str(visit().state.get("entrance",{}).get("stage",""))
		if not stage.is_empty() and not stages.has(stage):stages.append(stage)
		if visit().active():
			guest_touched=guest_touched or not app.world.actors.maya.door_presentation.is_empty()
			host_touched=host_touched or (stage=="closing" and not app.world.actors.player.door_presentation.is_empty())
			var host:LifeActor=app.world.actors.player
			if stage=="closing" and float(host.door_presentation.get("weight",0.0))>.98:
				var side:String=str(host.door_presentation.side)
				host_grip_error=maxf(host_grip_error,host._joints["Forearm_"+side].to_global(host._grip_offset(side)).distance_to(host.door_presentation.target))
				await capture("host-closing")
			if stage=="guest_enter" and float(app.world.actors.maya.door_presentation.get("weight",0.0))>.98:await capture("guest-handle")
			var door:Dictionary=entrance_door
			if not door.is_empty():
				var distance:float=(app.world.actors.maya.position-door.position).dot(door.outward)
				if absf(distance)<.1:crossed_open=crossed_open or float(app.world.construction.doors.doors[door.id].progress)>.98
		if index%8==0:await process_frame
	return predicate.call()
func capture(label:String)->void:
	if not "--capture" in OS.get_cmdline_user_args() or captures.has(label):return
	captures[label]=true
	app.world.set_process(false);app.world.set_cutaway(false)
	app.world.camera_target=entrance_door.position+Vector3(0,1.1,-.5)
	app.world.camera.size=4.4;app.world.camera_distance=3.2 if label=="guest-handle" else 2.6
	app.world.camera_angle=.38 if label=="guest-handle" else PI+.38;app.world.camera_elevation=.45;app.world.update_camera()
	for frame:int in 3:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://visitor-"+label+".png")==OK,"Rendered visitor "+label)

func save_reload(label:String)->void:
	if "--quick" in OS.get_cmdline_user_args():return
	app.household.set_speed(0)
	var before:Dictionary=visit().snapshot()
	check(app.save_game("",label),label+" saves through public validation")
	var epoch:int=app.load_epoch
	var slot:String=app.active_save_id
	app.load_game(slot);await process_frame
	check(app.load_epoch==epoch+1,label+" actually reloads")
	if not _same_value(before,visit().snapshot()):events.append({"label":label,"before":before,"after":visit().snapshot()})
	check(_same_value(before,visit().snapshot()),label+" preserves the complete paused visit")
	var frozen:Dictionary=visit().snapshot()
	app._process(.25)
	check(_same_value(frozen,visit().snapshot()),label+" remains frozen while paused")
	app.household.set_speed(1)
func check_moved_door()->void:
	var original:Dictionary=app.world.construction.snapshot()
	var changed:Dictionary=original.duplicate(true)
	for wall:Dictionary in changed.walls:
		if absf(float(wall.z)-5.04)>.01 or float(wall.w)<1.0:continue
		if float(wall.x)<0:wall.x=-4.05;wall.w=4.1
		else:wall.x=3.05;wall.w=6.1
	app.world.construction.restore(changed);app.world.rebuild_navigation()
	var moved:Dictionary=visit().front_door()
	check(not moved.is_empty() and absf(float(moved.position.x)+1.0)<.01,"Rebuilt exterior wall gap changes the actual front door")
	var doorstep:Vector3=visit()._doorstep_point("maya")
	check(doorstep.is_finite() and absf(doorstep.x+1.0)<.01,"Arrival follows the moved doorway instead of the starter coordinate")
	app.world.construction.restore(original);app.world.rebuild_navigation()

func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup()
	check_moved_door()
	var door:Dictionary=visit().front_door()
	entrance_door=door.duplicate()
	if "--capture" in OS.get_cmdline_user_args():
		app.world.set_process(false);app.world.construction.update_cutaway(false)
	check(not door.is_empty(),"Front door is derived from an actual exterior wall opening")
	if door.is_empty():await _finish();return
	var invited:bool=visit().invite("maya")
	check(invited,"Public friend invitation starts an arrival")
	if not invited:
		print("INVITATION_DEBUG notice=",app.notice_label.text," building_error=",app.world.construction.last_error," inside=",visit()._inside_point("maya",door.position-door.outward*1.7)," doorstep=",visit()._doorstep_point("maya")," door=",door)
		await _finish();return
	check((visit().state.welcome-door.position).dot(door.outward)>1.0,"Arrival standing point is outside the actual front door")
	check(visit().social_allowed("maya") and visit().prepare_social("maya"),"Moving arrival remains available for direct social commands")
	app._process(.25)
	await save_reload("Visitor arrival")
	check(await wait_until(func():return _phase()=="waiting"),"Guest physically walks to the front door")
	check(visit().welcome("player"),"Public Welcome queues the host entrance sequence")
	if visit().state.get("entrance",{}).is_empty():
		print("ENTRANCE_DEBUG ",door," host=",app.world.actors.player.position," guest=",app.world.actors.maya.position," notice=",app.notice_label.text)
		for offset:float in [1.0,-1.0,1.25,-1.25]:
			var side:=Vector3(door.outward.z,0,-door.outward.x)
			var wait:Vector3=visit()._grid(door.position-door.outward*.85+side*offset)
			var close:Vector3=visit()._grid(door.position-door.outward*.65+side*clampf(offset,-.25,.25))
			print("ENTRANCE_CANDIDATE ",wait," clear=",visit()._clear("player",wait)," close=",close," clear=",visit()._clear("player",close)," route=",app.world.route_to(app.world.actors.player.position,wait))
		await _finish();return
	check(not visit().welcome("player"),"A second Welcome cannot replace the entrance owner")
	check(str(visit().state.entrance.stage)=="host_approach","Host first approaches a clear indoor waiting point")
	await save_reload("Host approaching visitor")
	check(await wait_until(func():return str(visit().state.get("entrance",{}).get("stage",""))=="guest_enter"),"Host reaches the doorway before guest entry")
	check(str(app.household.member_sim("player").get_current_action().phase)=="approach","Greeting rewards wait until the guest has entered")
	check(visit().social_allowed("maya") and not visit().conversation_start_allowed("maya",{"id":"joke"}),"Entering guest stays clickable while a second social waits safely")
	var waiting_person:String=str(app.household.members[1].id)
	var waiting_position:Vector3=app.world.actors[waiting_person].position
	app.select_household_member(1)
	app.queue_interaction({"id":"maya","kind":"neighbor","node":app.world.actors.maya,"size":Vector2(.6,.6)},"joke")
	check(str(app.sim.get_current_action().get("id",""))=="joke","Clicking the entering visitor queues a direct social action")
	app.select_household_member(0)
	await save_reload("Guest crossing doorway")
	check(await wait_until(func():return str(visit().state.get("entrance",{}).get("stage",""))=="closing"),"Guest clears the doorway and the host approaches the handle")
	if str(visit().state.get("entrance",{}).get("stage",""))!="closing":
		events.append({"visit":visit().snapshot(),"host":str(app.world.actors.player.position),"queue":str(app.sim.action_queue),"notice":app.notice_label.text,"stages":stages});await _finish();return
	check(await wait_until(func():return float(app.world.construction.doors.passages.get("player",{}).get("clock",0.0))>=.20,20),"Host reaches the handle before moving the leaf")
	app._process(.10)
	var progress:float=float(app.world.construction.doors.doors[str(visit().state.entrance.door)].progress)
	check(progress>0.0 and progress<1.0,"Closing save is taken during the actual door swing")
	var grip_side:String=str(app.world.actors.player.door_presentation.side)
	var saved_grip:Vector3=app.world.actors.player._joints["Forearm_"+grip_side].to_global(app.world.actors.player._grip_offset(grip_side))
	await save_reload("Host closing front door")
	check(is_equal_approx(progress,float(app.world.construction.doors.doors[str(visit().state.entrance.door)].progress)),"Load preserves the partially open door leaf")
	var restored_host:LifeActor=app.world.actors.player
	check(saved_grip.distance_to(restored_host._joints["Forearm_"+grip_side].to_global(restored_host._grip_offset(grip_side)))<.01,"Paused load reconstructs the same hand position during the door swing")
	check(await wait_until(func():return str(visit().state.get("entrance",{}).get("stage",""))=="greeting"),"Host closes the door and starts the hallway greeting")
	check(float(app.world.construction.doors.doors[str(visit().state.entrance.door)].progress)<.001,"Greeting starts only after the door is closed")
	check(app.world.actors[waiting_person].position.distance_to(waiting_position)<.001,"Queued companion waits clear of the doorway during entry")
	check(str(app.household.member_sim(waiting_person).get_current_action().phase)=="approach","Queued companion cannot interrupt the host's greeting")
	check(app.world.actors.player.position.distance_to(app.world.actors.maya.position)<=1.8,"Host and guest are within real conversation distance")
	check(guest_touched and crossed_open,"Guest touches the handle and crosses an open door")
	check(host_touched,"Host visibly reaches for the door while closing behind the guest")
	check(host_grip_error<.05,"Host hand reaches the rendered handle within5cm; error="+str(host_grip_error))
	await capture("hallway-greeting")
	await save_reload("Hallway greeting")
	check(await wait_until(func():return _phase()=="inside"),"Completed hallway greeting admits the visitor")
	check(app.sim.relationships.maya.friendship==42,"Only the completed real greeting grants friendship")
	check(not app.world.construction.doors.passages.has("player"),"Completed entrance releases host door custody")
	check(await wait_until(func():return str(app.household.member_sim(waiting_person).get_current_action().get("phase",""))=="active"),"Queued direct social replans and starts after the welcome")
	app.household.member_sim(waiting_person).cancel_action()
	visit().goodbye();app.household.set_speed(8)
	check(await wait_until(func():return not visit().active()),"Visitor departs through physical navigation")
	app.household.set_speed(1)
	check(visit().invite("maya"),"Second invitation remains available after departure")
	check(await wait_until(func():return _phase()=="waiting"),"Second visitor arrival completes")
	check(visit().welcome("player"),"Second entrance starts normally")
	app.household.member_sim("player").cancel_action();visit().reconcile()
	check(visit().state.greeting.is_empty() and visit().state.entrance.is_empty(),"Cancel clears the pending entrance and host reservation")
	check(not app.world.construction.doors.passages.has("player"),"Cancel releases door presentation")
	await save_reload("Cancelled welcome")
	events.append({"stages":stages,"guest_touched":guest_touched,"host_touched":host_touched,"crossed_open":crossed_open})
	await _finish()
