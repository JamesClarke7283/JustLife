extends SceneTree
## A housemate leaving for work must not interrupt another member's bed slot.
## Controlled starting clock/needs; all walking, work departure and sleep
## progress below use ordinary controller frames and unchanged action durations.
var app:Node
var checks:int=0
var failures:int=0
const DT:float=.1
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func frames(n:int=2)->void:
	for i:int in n:await process_frame
func step_many(n:int)->void:
	for i:int in n:
		app._process(DT)
		if i%20==0:await process_frame
func reach_active(member_id:String)->bool:
	for i:int in 500:
		app._process(DT)
		if i%20==0:await process_frame
		if str(app.household.member_sim(member_id).get_current_action().get("phase",""))=="active":return true
	return false
func snapshot(action:Dictionary)->Dictionary:
	return {"slot":str(action.get("seat_slot","")),"target":action.get("target_position",Vector3.INF),"phase":str(action.get("phase","")),"paid":bool(action.get("paid",false)),"elapsed":float(action.get("elapsed",0.0)),"body":app.world.actors.player.position}
func stable(action:Dictionary,before:Dictionary)->bool:
	return is_same(app.household.member_sim("player").get_current_action(),action) and str(action.get("seat_slot",""))==before.slot and Vector3(action.target_position)==before.target and str(action.phase)==before.phase and bool(action.paid)==before.paid and float(action.elapsed)==before.elapsed and app.world.actors.player.position==before.body
func finish()->void:
	app.queue_free();await frames(3)
	print("ACTIVE_SEAT_REFRESH %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():push_error("Use an isolated absolute JUSTLIFE_DATA_DIR");quit(2);return
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	app.household_profiles=[{"name":"Resting owner","age_stage":"adult","traits":[],"hair":0},{"name":"Working companion","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();await frames();app.household.set_speed(0)
	app.household.minutes=540.0
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false;member.sim.minutes=540.0
		for need:String in LifeSim.NEED_NAMES:member.sim.needs[need]=100.0
		while not member.sim.action_queue.is_empty():member.sim.cancel_action()
	app.household.member_sim("player").needs.energy=10.0
	var bed:Dictionary=app.world.closest_item("bed",Vector3.ZERO)
	var pet_choice:int=0
	for index:int in LifePets.candidate_count():
		if str(LifePets.candidate(1,index).species)=="dog":pet_choice=index;break
	var prepared:Dictionary=app.household.prepare_pet(LifePets.candidate(1,pet_choice))
	var adopted:Dictionary=app.household.commit_pet(prepared.get("request",{}),Vector3(-8,.16,4.3))
	check(bool(adopted.get("ok",false)),"The household adopts a real dog for the queued follow-up")
	if not bool(adopted.get("ok",false)):await finish();return
	var pet_id:String=str(adopted.pet.id)
	app.spawn_pet(pet_id,adopted.pet,Vector3(-8,.16,4.3),Vector3(-8,.16,4.3))
	app.queue_interaction(bed,"sleep");app.household.set_speed(8)
	check(await reach_active("player"),"The player physically reaches a bed half and starts ordinary sleep")
	var sleep:Dictionary=app.household.member_sim("player").get_current_action()
	if str(sleep.get("phase",""))!="active":await finish();return
	await step_many(10)
	var before:Dictionary=snapshot(sleep)
	check(not str(sleep.get("seat_slot","")).is_empty() and Vector3(sleep.target_position).distance_to(app.world.approach(bed))>.1,"The active sleeper owns a distinct bed-half endpoint")
	app._queue_pet_action(pet_id,"pet_teach_trick")
	var follow_up:Dictionary=app.sim.action_queue[-1]
	check(app.sim.action_queue.size()==2 and str(follow_up.get("id",""))=="pet_teach_trick","A real trick lesson queues behind the active sleep")
	# The public work action reaches the exit, changes away presence, and calls
	# _refresh_sim_targets(false) inside the controller's normal frame loop.
	app.select_household_member(1);app._go_to_work();app.select_household_member(0)
	check(str(app.household.member_sim("housemate_1").get_current_action().get("id",""))=="career_day","The housemate queues an ordinary work departure")
	for i:int in 500:
		app._process(DT)
		if i%20==0:await process_frame
		if bool(app.world.actors.housemate_1.get_meta("away",false)):break
	check(app.household.member_sim("housemate_1").is_away() and bool(app.world.actors.housemate_1.get_meta("away",false)),"The housemate physically leaves and triggers the away-target refresh")
	check(is_same(app.household.member_sim("player").get_current_action(),sleep) and str(sleep.phase)=="active" and str(sleep.seat_slot)==before.slot and Vector3(sleep.target_position)==before.target and bool(sleep.paid)==before.paid and float(sleep.elapsed)>float(before.elapsed) and app.world.actors.player.position==before.body,"Work departure preserves the active sleeper's exact slot, endpoint, body and advancing progress")
	check(app.sim.action_queue.size()==2 and is_same(app.sim.action_queue[1],follow_up) and str(follow_up.phase)=="queued" and not bool(follow_up.paid),"The accepted pet follow-up retains its identity, order and unpaid queued state")
	app.household.set_speed(0);before=snapshot(sleep)
	app._refresh_sim_targets(false)
	check(stable(sleep,before),"A standalone refresh preserves phase, payment and progress without requiring a later replan")
	app._refresh_sim_targets(true)
	check(stable(sleep,before),"A harmless replan also keeps the settled sleeper's exact slot")
	if str(sleep.phase)!="active":await finish();return
	app.household.set_speed(8)
	for i:int in 600:
		app._process(DT)
		if i%20==0:await process_frame
		if not is_same(app.household.member_sim("player").get_current_action(),sleep):break
	check(is_same(app.sim.get_current_action(),follow_up) and float(sleep.elapsed)>=float(sleep.duration),"Sleep completes its remaining normal duration and starts its accepted follow-up")
	await step_many(20)
	check(str(app.world.actors.player._activity_anchor.get("kind",""))!="bed" and app.household.member_sim("player").needs.energy>80.0,"The sleeper exits the bed pose normally with restored energy")
	for i:int in 500:
		app._process(DT)
		if i%20==0:await process_frame
		if app.sim.action_queue.is_empty():break
	check(app.sim.action_queue.is_empty() and float(follow_up.elapsed)>=float(follow_up.duration),"The queued trick lesson reaches the dog and completes after sleep")
	# Explicitly assigned beds enter from the side, not the ordinary foot slot.
	app.household.set_speed(0)
	check(bool(app.household.assign_bed_side("player",str(bed.id),"right").ok),"The player can reserve the right-hand bedside")
	app.queue_interaction(bed,"sleep");app.household.set_speed(8)
	check(await reach_active("player"),"The assigned sleeper reaches the actual right bedside")
	app.household.set_speed(0);var assigned:Dictionary=app.sim.get_current_action();before=snapshot(assigned)
	app._refresh_sim_targets(false)
	check(stable(assigned,before) and str(assigned.get("seat_slot",""))=="right" and Vector3(assigned.target_position)==app.world.bed_side_approach(bed,"right"),"Refreshing an assigned bed preserves its side approach rather than moving it to the foot")
	app.cancel_current_action()
	var sofa:Dictionary=app.world.closest_item("sofa",Vector3.ZERO)
	app.queue_interaction(sofa,"watch");app.household.set_speed(8)
	check(await reach_active("player"),"The player physically occupies a sofa cushion")
	app.household.set_speed(0);var seated:Dictionary=app.sim.get_current_action();before=snapshot(seated)
	app._refresh_sim_targets(false)
	check(stable(seated,before) and not str(seated.get("seat_slot","")).is_empty(),"An active sofa cushion keeps its exact endpoint and phase on a target refresh")
	# Geometry is still authoritative: the refresh must not blindly retain a
	# position after its furnishing really moved, or a removed target's action.
	sofa.node.position+=Vector3(0,0,1.5);app.world.rebuild_navigation()
	app._refresh_sim_targets(false)
	check(str(seated.phase)=="approach" and Vector3(seated.target_position)!=before.target and Vector3(seated.target_position)==app.world.slot_approach(sofa,str(seated.seat_slot)),"A genuinely moved seat still invalidates the old active position")
	app.world.remove_item(str(sofa.id));app._refresh_sim_targets(false)
	check(app.sim.action_queue.is_empty(),"Removing the furnishing still cancels its now-invalid activity")
	await finish()
