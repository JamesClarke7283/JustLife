extends "res://tests/test_home_visit.gd"
var shots: Dictionary = {}
func advance(count: int = 1) -> void:
	for n: int in count: app._process(.1)
func pair_active() -> bool:
	for member: Dictionary in app.household.members:
		var action: Dictionary = member.sim.get_current_action()
		if not LifeTVGroup.owns(action) or str(action.phase)!="active": return false
	return true
func until_pair(limit: int = 1500) -> bool:
	for n: int in limit:
		if pair_active(): return true
		advance()
	return pair_active()
func cancel_all() -> void:
	for member: Dictionary in app.household.members:
		while not member.sim.action_queue.is_empty(): member.sim.cancel_action()
	advance()
func capture(label: String, at: Vector3) -> void:
	var output: String = OS.get_environment("TV_EVIDENCE_DIR")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	app.world.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	app.world.camera.fov=51
	app.world.camera.global_position=at+Vector3(4,3.3,5.5) if label in ["sofa_together","visitor_tv"] else at+Vector3(-4.5,3.7,-5.5)
	app.world.camera.look_at(at+Vector3(0,.65,0))
	app.ui.visible=false
	await process_frame
	RenderingServer.force_draw(false,0.0)
	check(root.get_texture().get_image().save_png(output+"/"+label+".png")==OK,"Rendered "+label)
	app.ui.visible=true
func first_item(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind)==kind: return item
	return {}
func finish_tv() -> void:
	print("TV_GROUP_RESULT ",checks," checks / ",failures.size()," failures ",failures)
	app.queue_free();await process_frame;quit(1 if not failures.is_empty() else 0)
func capture_showcase() -> void:
	var tv:Dictionary=first_item("tv")
	check(app.tv_group.request(app.sim,str(tv.id),true) and until_pair(),"Capture household physically seated together")
	advance(65)
	await capture("sofa_together",app._find_item(str(app.sim.get_current_action().target_id)).node.position)
	cancel_all()
	check(app.world.can_place("outdoor_tv",Vector3(-11,.16,5),180),"Capture outdoor screen fits owned garden")
	app.world.add_item({"id":"capture_tv","kind":"outdoor_tv","x":-11.0,"z":5.0,"rotation":180.0})
	for kind:String in ["pool","hot_tub"]:
		var z:float=2.0 if kind=="pool" else -2.0
		check(app.world.can_place(kind,Vector3(-11,.16,z),0),"Capture "+kind+" fits clear ground")
		app.world.add_item({"id":"capture_"+kind,"kind":kind,"x":-11.0,"z":z,"rotation":0.0})
		app._refresh_sim_targets()
		var furnishing:Dictionary=app._find_item("capture_"+kind)
		app.queue_interaction(furnishing,"watch_water_tv")
		check(until_pair(),"Capture both viewers physically reach "+kind)
		advance(65)
		await capture(kind+"_tv",furnishing.node.position)
		cancel_all()
	await finish_tv()
func _run() -> void:
	app=MainScene.instantiate();root.add_child(app);await process_frame
	_setup();app.world.set_process(false);app.set_sound(true)
	if "--capture-showcase" in OS.get_cmdline_user_args():await capture_showcase();return
	var a: LifeSim=app.household.members[0].sim
	var b: LifeSim=app.household.members[1].sim
	var aid: String=str(app.household.members[0].id)
	var bid: String=str(app.household.members[1].id)
	var tv: Dictionary=first_item("tv")
	check(not tv.is_empty(),"Starter home supplies a real television")
	check(app.tv_group.request(a,str(tv.id),true),"Watch TV Together queues two physical viewers")
	check(LifeTVGroup.owns(a.get_current_action()) and LifeTVGroup.owns(b.get_current_action()),"Both queued actions retain the same actual television")
	var both: bool=until_pair()
	check(both,"Both viewers physically reach their allocated seats")
	if both:
		advance(75)
		for n:int in 50:
			if not app.world.actors[aid].speech_presentation().is_empty() or not app.world.actors[bid].speech_presentation().is_empty():break
			advance()
		var first: Dictionary=a.get_current_action()
		var second: Dictionary=b.get_current_action()
		check(first.target_id==second.target_id and first.seat_slot!=second.seat_slot,"Viewers occupy distinct adjacent cushions on the same sofa")
		check(app.tv_group.screens.get(str(first.tv.id),[]).any(func(entry:Dictionary)->bool:return entry.material is ShaderMaterial),"An animated programme renders on the actual television screen")
		check(first.tv.session==second.tv.session and first.tv.show==second.tv.show and first.tv.clock==second.tv.clock,"Both viewers watch one synchronized programme")
		var body_a: LifeActor=app.world.actors[aid]
		var body_b: LifeActor=app.world.actors[bid]
		check(body_a._sit_amount>.95 and body_b._sit_amount>.95,"Both bodies use the seated morph and supported hips")
		check(not body_a.speech_presentation().is_empty() or not body_b.speech_presentation().is_empty(),"Shared viewing presents topic speech bubbles")
		check(body_a._voice.playing or body_b._voice.playing or body_a._voice_cooldown>0 or body_b._voice_cooldown>0,"Topic conversation triggers ambient vocal chatter")
		var invalid:Dictionary=first.duplicate(true)
		invalid.tv.clock=NAN
		check(not LifeTVGroup.save_error(invalid).is_empty(),"Corrupt programme clocks are rejected")
		check(float(first.changes.social)>0 and float(second.changes.social)>0,"Social effects require physically present company")
		await capture("sofa_together",app._find_item(str(first.target_id)).node.position)
		app.household.set_speed(0)
		var facts: Dictionary=first.tv.duplicate(true)
		var pose: Transform3D=body_a.visual.global_transform
		advance(10)
		check(first.tv==facts and body_a.visual.global_transform==pose,"Pause freezes shared show, chatter clock and seated pose")
		check(app.save_game("","TV together checkpoint"),"Full save accepts a live shared viewing session")
		var slot: String=app.active_save_id
		var epoch: int=app.load_epoch
		app.load_game(slot)
		check(app.load_epoch==epoch+1,"Full load reconstructs the TV session and normal journeys")
		a=app.household.member_sim(aid);b=app.household.member_sim(bid)
		check(app.world.actors[aid]._sit_amount>.95 and app.world.actors[bid]._sit_amount>.95,"Paused full load reconstructs both seated bodies")
		check(a.get_current_action().tv==facts and b.get_current_action().tv==facts,"Load preserves exact programme and conversation clocks")
		advance(10)
		check(app.tv_group.screens.has(str(facts.id)) and a.get_current_action().tv==facts and b.get_current_action().tv==facts,"Paused frames after load preserve the visible programme and its clocks")
		app.household.set_speed(1)
		b.cancel_action();advance(2)
		check(float(a.get_current_action().changes.get("social",0))==0,"Canceling the companion removes solo social rewards")
		var choices: Array=[];app.tv_group.menu({"id":aid,"kind":"neighbor"},choices)
		app.select_household_member(1)
		choices=[];app.tv_group.menu({"id":aid,"kind":"neighbor"},choices)
		check(choices.any(func(choice: Dictionary)->bool:return str(choice.id)=="join_tv"),"Clicking a watching Lifelet offers Join")
		check(app.tv_group.join(b,aid) and until_pair(),"Join physically reseats the second viewer beside the first")
	cancel_all();check(app.tv_group.screens.is_empty(),"Last viewer leaving restores the television screen material")
	var isolated:=LifeSim.new();isolated.new_household({"name":"Probe","age_stage":"adult"})
	check(not isolated.queue_action("watch_together","fake",Vector3.ZERO),"Standalone Watch Together cannot award unearned social effects")
	isolated.free()
	if "--household-only" in OS.get_cmdline_user_args():await finish_tv();return
	# Place actual outdoor assets on reachable garden ground.
	check(app.world.can_place("outdoor_tv",Vector3(-11,.16,5),180),"Outdoor television is placed inside clear, owned garden ground")
	check(app.world.can_place("pool",Vector3(-11,.16,2),0),"Pool fits clear garden ground with no structure overlap")
	app.world.add_item({"id":"test_outdoor_tv","kind":"outdoor_tv","x":-11.0,"z":5.0,"rotation":180.0})
	app.world.add_item({"id":"test_pool_tv","kind":"pool","x":-11.0,"z":2.0,"rotation":0.0})
	app._refresh_sim_targets();app.select_household_member(0)
	var pool: Dictionary=app._find_item("test_pool_tv")
	app.queue_interaction(pool,"watch_water_tv")
	check(LifeTVGroup.owns(a.get_current_action()) and LifeTVGroup.owns(b.get_current_action()),"Pool TV requests retain water actions for both viewers")
	both=until_pair()
	check(both,"Two water viewers pass through the house and reach distinct pool approaches")
	if both:
		advance(60)
		var first: Dictionary=a.get_current_action();var second: Dictionary=b.get_current_action()
		check(first.swim_lane!=second.swim_lane and Vector3(first.target_position).distance_to(second.target_position)>.5,"Water lane reservations and walking endpoints are distinct")
		check(str(first.id)=="enjoy_outdoors" and a.wetness>0 and b.wetness>0,"Outdoor TV preserves simultaneous in-water activity and wetness")
		var anchor_a: Dictionary=app.tv_group.anchor(first,app.world.actors[aid]);var anchor_b: Dictionary=app.tv_group.anchor(second,app.world.actors[bid])
		check(anchor_a.position.distance_to(anchor_b.position)>.5 and bool(anchor_a.tv_water),"Relaxed bodies are supported at separate points inside the pool")
		await capture("pool_tv",pool.node.position)
	cancel_all()
	app.queue_interaction(pool,"enjoy_outdoors")
	check(app.tv_group.request(a,"test_outdoor_tv",false) and a.action_queue.size()==1 and str(a.get_current_action().id)=="enjoy_outdoors" and a.get_current_action().has("swim_lane"),"Adding TV to an existing pool visit preserves its activity and assigns its water place")
	cancel_all()
	check(app.world.can_place("hot_tub",Vector3(-11,.16,-2),0),"Hot tub fits clear garden ground")
	app.world.add_item({"id":"test_hot_tub_tv","kind":"hot_tub","x":-11.0,"z":-2.0,"rotation":0.0})
	app._refresh_sim_targets();app.select_household_member(0)
	var tub: Dictionary=app._find_item("test_hot_tub_tv")
	app.queue_interaction(tub,"watch_water_tv")
	both=until_pair();check(both,"Two hot-tub viewers reach separate rim approaches")
	if both:
		advance(55);await capture("hot_tub_tv",tub.node.position)
		check(a.get_current_action().tv.show==b.get_current_action().tv.show,"Hot-tub viewers share the outdoor programme")
	cancel_all()
	check(app.residents.home_visit.invite("maya"),"Invite a real visitor for TV qualification")
	for n: int in 2500:
		if _phase()=="waiting":break
		if n%500==0:print("TV GUEST ARRIVAL ",n," ",_phase())
		advance()
	app.residents.home_visit.welcome(aid)
	for n: int in 3500:
		if _phase()=="inside":break
		if n%500==0:print("TV GUEST WELCOME ",n," ",_phase())
		advance()
	check(_phase()=="inside","Visitor physically enters and completes the coordinated greeting")
	if _phase()=="inside":
		cancel_all();app.residents.home_visit.activity.cancel("")
		app.select_household_member(0)
		check(app.tv_group.request(a,str(tv.id),false),"Host turns on the television for a visitor")
		var joined: bool=false
		for n: int in 1800:
			advance()
			var guest: Dictionary=app.residents.home_visit.activity.current_action()
			if LifeTVGroup.owns(guest) and str(guest.phase)=="active" and str(a.get_current_action().get("phase",""))=="active":joined=true;break
		check(joined,"Visitor autonomously walks over and joins the host's actual programme")
		if joined:
			advance(60)
			var guest: Dictionary=app.residents.home_visit.activity.current_action()
			check(guest.tv.session==a.get_current_action().tv.session and guest.seat_slot!=a.get_current_action().seat_slot,"Guest shares programme while reserving a different cushion")
			await capture("visitor_tv",app._find_item(str(guest.target_id)).node.position)
			app.household.set_speed(0)
			var guest_tv:Dictionary=guest.tv.duplicate(true)
			var saved_guest:bool=app.save_game("","Guest TV checkpoint")
			print("GUEST TV SAVE ",saved_guest," ",app.notice_label.text)
			check(saved_guest,"Full save accepts visitor and host watching together")
			var saved_epoch:int=app.load_epoch
			if saved_guest:app.load_game(app.active_save_id)
			print("GUEST TV LOAD ",app.notice_label.text)
			check(app.load_epoch==saved_epoch+1 and app.residents.home_visit.activity.current_action().get("tv",{})==guest_tv,"Full load restores the guest's shared programme and reserved seat")
			check(app.world.actors[aid]._sit_amount>.95 and app.residents.home_visit.activity.body()._sit_amount>.95,"Paused guest load reconstructs both supported seated bodies")
			app.household.set_speed(1)
			app.residents.home_visit.goodbye();advance(5)
			check(not app.residents.home_visit.activity.active(),"Guest departure releases TV seating and conversation ownership")
	cancel_all()
	await finish_tv()
