extends "res://tests/test_family_ui.gd"
## Public creation, phone adoption and real arrival; private initial autonomy-off
## keeps the paid preservation checkpoint stable. Overnight autonomy then runs
## normally to prove the adopted pupil joins the following school day.
var expected:Dictionary={}
var oven_fixture:bool=false
var oven_evidence:Array=[]
var school_return_diagnostic:Dictionary={}
const FAMILY:Array[String]=["Morgan Linden","Jamie Linden","Taylor Linden"]
func _run() -> void:
	oven_fixture="--adoption-oven" in OS.get_cmdline_user_args()
	screenshot_dir="res://art/adoption_playthrough";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):member_completed.append(id+":"+str(action.id)))
	app.household.notice.connect(func(message:String):notices.append(message))
	if resume_only:
		expected=JSON.parse_string(FileAccess.get_file_as_string("user://adoption_expected.json"))
		oven_fixture=bool(expected.get("oven_fixture",false))
		await _public_load();await _resume_adoption()
	else:
		await _setup_family()
		if "--adoption-ui-only" in OS.get_cmdline_user_args():await _small_public_review()
		else:await _adopt()
	_write_report();app.queue_free();await frames(4)
	print("ADOPTION_PUBLIC assertions=%d failures=%d resume=%s" % [assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)
func _setup_family() -> void:
	await _enter_new_game()
	for index:int in range(3):
		if index>0:await press("+ Add Lifelet")
		var edit:LineEdit=app.find_children("*","LineEdit",true,false)[0]
		edit.text=FAMILY[index];edit.text_changed.emit(edit.text)
		await _age("Child" if index==2 else "Adult")
	await press_member(FAMILY[0]);await press("Connections")
	var connection:OptionButton
	for node:Node in app.find_children("*","OptionButton",true,false):
		if node.is_visible_in_tree() and int(node.get_meta("connection_member",-1))==2:connection=node
	check(is_instance_valid(connection),"Public creator exposes Taylor's parent connection.")
	if is_instance_valid(connection):connection.select(4);connection.item_selected.emit(4);await frames(3)
	await press("Back to creating")
	await press_member(FAMILY[0]);await press("Find my home",true);await press("Start living",true);await press("Ⅱ")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	if oven_fixture:app.sim._gain_skill("cooking",450.0) # Explicit pre-play unlock fixture for the integrated oven scenario.
	var stove:Dictionary=first_item("stove")
	app.world.object_clicked.emit(stove,app.world.camera.unproject_position(stove.node.position));await frames(3)
	await press("Cook a fresh meal",true);await press("Cook harvest vegetable bake" if oven_fixture else "Cook garden skillet")
	await queue_via_menu("bookshelf","read");await press("▶" if oven_fixture else "▶▶▶")
	if not await wait_until(func()->bool:return active_is("cook",.26 if oven_fixture else .12),"actual paid partial cook before adoption",40):return
	await press("Ⅱ")
	check(bool(app.sim.get_current_action().paid) and float(app.sim.get_current_action().elapsed)>0,"Existing guardian physically prepares a paid partial meal before the phone opens.")
func _second_guardian() -> void:
	var selector:OptionButton=app.find_child("AdoptionSecondGuardian",true,false)
	check(is_instance_valid(selector),"Review exposes an explicit optional second guardian.")
	if not is_instance_valid(selector):return
	for index:int in range(selector.item_count):
		if str(selector.get_item_metadata(index))=="housemate_1":selector.select(index);selector.item_selected.emit(index);await frames(3);return
	check(false,"Second adult guardian is selectable.")
func _adopt() -> void:
	var parent:LifeSim=app.sim
	var paid:Dictionary=parent.action_queue[0];var later:Dictionary=parent.action_queue[1]
	var before:Dictionary=app.household.get_state(app.world.serialize_items())
	var oven_before:Dictionary=_oven_snapshot()
	if oven_fixture:
		check(str(oven_before.phase)=="load" and bool(oven_before.tray_visible),"The integrated adoption begins during actual oven loading, with the dish still owned by the guardian.")
		await screenshot("00_guardian_loading_oven",true,false)
	await press("Phone");await screenshot("01_phone_service",false,false)
	await press("Adopt a child");await screenshot("02_original_candidates",false,false);await _small_adoption_panel("02b_candidates_960")
	await press("Meet Wren");await _second_guardian();await screenshot("03_review_two_guardians",false,false);await _small_adoption_panel("03b_review_960")
	check(app.sim.speed==0,"Adoption review preserves the existing paused state.")
	await press("Cancel adoption")
	check(app.household.get_state(app.world.serialize_items())==before,"Canceling the review changes no household state or money.")
	if oven_fixture:_assert_oven_same(oven_before,"Canceled phone review")
	await press("Meet Wren");await _second_guardian()
	await press("Confirm adoption · §1,000")
	check(app.household.members.size()==4,"Public confirmation appends one child.")
	if app.household.members.size()!=4:return
	var child:LifeSim=app.household.member_sim("housemate_3")
	child.autonomy=false # Same declared checkpoint fixture as the existing members; normal autonomy resumes overnight.
	check(str(child.character.name)=="Wren Avery" and str(child.character.age_stage)=="child","The child matches the named school-age candidate reviewed publicly.")
	check(app.household.funds==int(before.funds)-1000,"The final confirmation charges the displayed fee exactly once.")
	check(is_same(parent.get_current_action(),paid) and is_same(parent.action_queue[1],later) and float(paid.elapsed)==float(before.members[0].state.action_queue[0].elapsed),"Confirmation retains the exact paid cook, its progress and the later player instruction.")
	check(app.household.family_relationship("player","housemate_3")=="child" and app.household.family_relationship("housemate_3","housemate_1")=="parent" and app.household.family_relationship("housemate_3","housemate_2")=="siblings","Both guardians and the sibling have canonical family links.")
	check(app.household.adoptions.events.size()==1,"One persisted adoption event records the confirmed family change.")
	if oven_fixture:_assert_oven_same(oven_before,"Confirmed child append")
	await press("My Lifelet");await press("Family tree");await screenshot("04_family_tree",false,false);await press("Back to life")
	await press_member("Wren Avery")
	check(not child.get_action_availability("school_day","lot_exit").available,"The newly arrived child has no school commitment on the settling-in day.")
	var spawn:Vector3=app.player.position
	await press("▶")
	if not await wait_until(func()->bool:return app.player.position.distance_to(spawn)>.3,"actual street-to-home arrival movement",15):return
	await press("Ⅱ")
	check(str(child.get_current_action().get("id",""))=="arrive_home","The first save occurs mid-route, before physical arrival completes.")
	check(app.player.position.distance_to(spawn)<1.2,"The arrival checkpoint observes a short actual walk rather than an injected endpoint.")
	await screenshot("05_paused_arrival",true,false)
	var position:Vector3=app.player.position;var clock:float=child.minutes
	await frames(12)
	check(app.player.position==position and child.minutes==clock,"Pause freezes the arriving child's position and school clock.")
	expected={"child":"housemate_3","position":vec(position),"funds":app.household.funds,"day":child.day,"minutes":child.minutes,"appearance":child.character.duplicate(true),"arrival":child.get_current_action().duplicate(true),"education":child.education.duplicate(true),"family_graph":app.household.family_graph.duplicate(true),"adoptions":app.household.adoptions.duplicate(true),"parent_elapsed":parent.get_current_action().elapsed,"parent_later":"read","wish_rewards":_wish_rewards()}
	expected.oven_fixture=oven_fixture
	if oven_fixture:expected.oven_pose=_oven_snapshot()
	await _public_save("A new beginning — Wren on the way home")
	var file:=FileAccess.open("user://adoption_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(app.household.json_safe(expected),"  "));file.close()
	await screenshot("06_named_arrival_checkpoint",false,false)
func _resume_adoption() -> void:
	check(app.household.members.size()==4 and app.household.selected_id()==str(expected.child),"Fresh named load preserves household count and selected arriving child.")
	var child:LifeSim=app.sim
	check(app.sim.speed==0 and app.sim.day==int(expected.day) and absf(app.sim.minutes-float(expected.minutes))<.001,"Fresh process restores the paused arrival clock.")
	check(app.player.position.distance_to(Vector3(expected.position[0],expected.position[1],expected.position[2]))<.001,"Fresh process restores the actual mid-route child position.")
	check(app.household.funds==int(expected.funds) and app.household.adoptions.events.size()==1,"Named restart neither recharges adoption nor repeats membership.")
	check(equivalent(child.education,expected.education) and equivalent(app.household.family_graph,expected.family_graph) and equivalent(app.household.adoptions,expected.adoptions),"School enrollment, genealogy and transaction receipt survive process restart.")
	for field:String in ["name","age_stage","hair","frame","skin_color","hair_color","top_color","traits","aspiration"]:check(child.character[field]==expected.appearance[field],"Restart preserves the reviewed appearance/personality field "+field+".")
	var parent:LifeSim=app.household.member_sim("player")
	check(absf(float(parent.get_current_action().elapsed)-float(expected.parent_elapsed))<.001 and bool(parent.get_current_action().paid) and parent.action_queue[1].id=="read","Fresh restart retains the existing paid cook and later read.")
	if oven_fixture:_assert_oven_same(expected.oven_pose,"Fresh process with arriving child selected")
	await screenshot("07_fresh_process_arrival",true,false)
	await press_member(FAMILY[1]);await queue_via_menu("bookshelf","read")
	check(app.sim.action_queue.any(func(action:Dictionary)->bool:return str(action.id)=="read"),"Another household member remains controllable while the child is arriving.")
	await press_member("Wren Avery");await press("▶")
	if not await wait_until(func()->bool:return member_completed.has("housemate_3:arrive_home"),"resumed physical arrival",15):return
	await press("Ⅱ")
	check(app.household.members.size()==4 and app.household.funds==int(expected.funds),"Actual resumed arrival completes without another charge or child.")
	check(member_completed.count("housemate_3:arrive_home")==1 and not child.action_queue.any(func(action:Dictionary)->bool:return str(action.id)=="arrive_home"),"Exactly one arrival completes through actual frame movement.")
	await screenshot("08_wren_home",true,false)
	await queue_via_menu("bookshelf","read");await press("▶▶▶")
	if not await wait_until(func()->bool:return member_completed.has("housemate_3:read") and member_completed.has("player:read"),"new child and existing guardian finish their independent reading",60):return
	await press("Ⅱ")
	check(app.household.funds==int(expected.funds)+_wish_rewards()-int(expected.wish_rewards),"Finishing the old paid recipe applies earned wish rewards without repeating ingredients or adoption fees.")
	await press("My Lifelet");await press("Family tree");await screenshot("09_new_child_family_view",false,false);await press("Back to life")
	# Ordinary autonomy from this point: no direct time, needs, action, or location edits.
	for member:Dictionary in app.household.members:member.sim.autonomy=true
	await press("▶▶▶")
	if not await wait_until(func()->bool:return child.day>=int(expected.day)+1 and child.is_away(),"adopted pupil's first actual weekday school departure",85):return
	await press("Ⅱ")
	check(child.day==int(expected.day)+1 and str(child.get_away_state().get("activity",""))=="school","The adopted child joins school on the next due day.")
	check(int(child.education.missed)==0,"There is no phantom absence before enrollment becomes due.")
	await screenshot("10_first_school_day",false,false)
	await press("▶▶▶")
	if not await _wait_school_return(child,60):return
	await press("Ⅱ")
	check(int(child.education.last_attendance_day)==int(expected.day)+1 and int(child.education.attended)==1,"The first completed school day records attendance once.")
	var homework_before:int=int(child.education.homework)
	await queue_via_menu("desk","homework");await press("▶▶▶")
	if not await wait_until(func()->bool:return int(child.education.homework)>homework_before and int(child.education.last_homework_day)==child.day,"new current-day public homework for the adopted pupil",45):return
	await press("Ⅱ");await screenshot("11_school_and_homework",false,false)
	await _public_save("Wren's first school day")
	var final_state:Dictionary=app.household.get_state(app.world.serialize_items())
	var file:=FileAccess.open("user://adoption_final.json",FileAccess.WRITE);file.store_string(JSON.stringify(app.household.json_safe(final_state),"  "));file.close()

func _wish_rewards() -> int:
	var total:int=0
	for member:Dictionary in app.household.members:
		for want:Dictionary in member.sim.wants:
			if bool(want.complete):total+=int(want.reward)
	return total

func _wait_school_return(child:LifeSim,timeout_seconds:float) -> bool:
	# Same wall-clock deadline and predicate as wait_until; observation never ticks
	# the simulation, changes speed, synchronizes wallets, or relaxes the gate.
	var started:int=Time.get_ticks_msec()
	var deadline:int=started+int(timeout_seconds*1000)
	var next_sample:int=started+1000
	var observed_delta:float=0.0
	var observed_frames:int=0
	school_return_diagnostic={"description":"first actual school return","timeout_seconds":timeout_seconds,"engine":{"time_scale":Engine.time_scale,"physics_ticks_per_second":Engine.physics_ticks_per_second,"max_physics_steps_per_frame":Engine.max_physics_steps_per_frame,"max_fps":Engine.max_fps},"delta_method":"Read app.get_process_delta_time once per awaited process_frame; frame-boundary observation may be one frame offset from the app callback. This is engine process delta, not wall time or measured rendering performance.","samples":[]}
	school_return_diagnostic.samples.append(_school_return_sample(child,started,observed_delta,observed_frames))
	while Time.get_ticks_msec()<deadline:
		if int(child.education.attended)==1 and not child.is_away():
			_finish_school_return_diagnostic(child,started,observed_delta,observed_frames,"passed")
			return true
		await frames(1)
		observed_frames+=1
		observed_delta+=app.get_process_delta_time()
		if Time.get_ticks_msec()>=next_sample:
			school_return_diagnostic.samples.append(_school_return_sample(child,started,observed_delta,observed_frames))
			next_sample=Time.get_ticks_msec()+1000
	_finish_school_return_diagnostic(child,started,observed_delta,observed_frames,"timeout")
	check(false,"Timed out: first actual school return")
	return false

func _school_return_sample(child:LifeSim,started:int,observed_delta:float,observed_frames:int) -> Dictionary:
	var member_id:String=str(expected.child)
	var actor:Node3D=app.world.actors.get(member_id)
	return {"wall_seconds":float(Time.get_ticks_msec()-started)/1000.0,"observed_engine_delta_seconds":observed_delta,"observed_process_frames":observed_frames,"child":{"day":child.day,"minutes":child.minutes,"speed":child.speed,"away":child.get_away_state(),"education":child.education.duplicate(true),"queue":child.action_queue.duplicate(true),"needs":child.needs.duplicate(true)},"household":{"day":app.household.day,"minutes":app.household.minutes,"speed":app.household.speed,"selected_id":app.household.selected_id()},"app":{"bound_id":app.bound_member_id,"mode":app.mode,"overlay_open":app.overlay_open,"overlay_pauses_sim":app.overlay_pauses_sim,"tree_paused":paused,"processing":app.is_processing()},"actor":{"position":vec(actor.position),"visible":actor.visible} if is_instance_valid(actor) else {},"motion":_read_motion(member_id),"notice_count":notices.size(),"completed_count":member_completed.size()}

func _read_motion(member_id:String) -> Dictionary:
	# The bound member's live route fields can be newer than motion_states.
	var motion:Dictionary=app.motion_states.get(member_id,{}).duplicate(true)
	if app.bound_member_id==member_id:
		motion={"path":app.path,"index":app.path_index,"pending":app.pending_action.duplicate(true),"waiting":app.waiting_for_target,"wait_started":app.wait_started,"wait_review":app.wait_review,"resume_active":app.resume_activity,"generation":app.route_generation}
	motion["path"]=Array(motion.get("path",PackedVector3Array()))
	return motion

func _finish_school_return_diagnostic(child:LifeSim,started:int,observed_delta:float,observed_frames:int,outcome:String) -> void:
	school_return_diagnostic["outcome"]=outcome
	school_return_diagnostic["terminal"]=_school_return_sample(child,started,observed_delta,observed_frames)
	var file:=FileAccess.open(screenshot_dir.path_join("school_return_diagnostic.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(app.household.json_safe(school_return_diagnostic),"  "));file.close()

func _write_report() -> void:
	# This is an observed state receipt, not a save operation. In particular,
	# household.get_state would synchronize selected speed/funds before reading.
	var observed_household:Dictionary={"selected_index":app.household.selected_index,"funds":app.household.funds,"day":app.household.day,"minutes":app.household.minutes,"speed":app.household.speed,"members":[],"family_graph":app.household.family_graph.duplicate(true),"adoptions":app.household.adoptions.duplicate(true),"meals":app.household.meals.get_state()}
	var diagnostic:Dictionary={"method":"Read-only observed state; no household synchronization or simulation writes.","household":observed_household,"bound":app.bound_member_id,"mode":app.mode,"overlay_open":app.overlay_open,"overlay_pauses_sim":app.overlay_pauses_sim,"motions":{},"positions":{},"school_return":school_return_diagnostic,"oven_fixture":oven_fixture,"oven_evidence":oven_evidence}
	for member:Dictionary in app.household.members:
		var id:String=str(member.id)
		observed_household.members.append({"id":id,"state":member.sim.get_state()})
		diagnostic.positions[id]=vec(app.world.actors[id].position)
		diagnostic.motions[id]=_read_motion(id)
	var file:=FileAccess.open(screenshot_dir.path_join("resume_terminal.json" if resume_only else "first_terminal.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(app.household.json_safe(diagnostic),"  "));file.close()
	super._write_report()

func _small_adoption_panel(name:String)->void:
	var previous:Vector2i=root.size
	root.size=Vector2i(960,600);await frames(8)
	check(root.size==Vector2i(960,600) and DisplayServer.window_get_size()==Vector2i(960,600),"Both root Window and native client area are actually 960×600.")
	for id:String in ["AdoptionCandidate_0","AdoptionCandidate_1","AdoptionCandidate_2","AdoptionSecondGuardian","AdoptionConfirm"]:
		var control:Control=app.find_child(id,true,false)
		if is_instance_valid(control) and control.is_visible_in_tree():check(root.get_visible_rect().encloses(control.get_global_rect()),"Small-window adoption control stays within the viewport: "+id)
	await screenshot(name,false,false)
	var captured:Image=Image.load_from_file(screenshot_dir.path_join(name+".png"))
	check(captured.get_size()==Vector2i(960,600),"Saved adoption screenshot contains actual 960×600 rendered pixels.")
	root.size=previous;await frames(8)

func _small_public_review()->void:
	var before:Dictionary=app.household.get_state(app.world.serialize_items())
	var oven_before:Dictionary=_oven_snapshot()
	root.size=Vector2i(960,600);await frames(8)
	await press("Phone");await press("Adopt a child")
	await _small_adoption_panel("candidates_actual_960")
	await press("Meet Wren");await _second_guardian()
	await _small_adoption_panel("review_actual_960")
	await press("Cancel adoption")
	check(app.household.get_state(app.world.serialize_items())==before,"Small-window public cancel preserves the full household and funds.")
	if oven_fixture:_assert_oven_same(oven_before,"Small-window canceled review")
	await press("Back to phone");await press("Back to life")
	check(not app.overlay_open and app.sim.speed==0,"Small-window phone closes back to the paused live household.")
	root.size=Vector2i(1440,900);await frames(8)

func _matrix_data(value:Transform3D)->Array:
	return [vec(value.origin),vec(value.basis.x),vec(value.basis.y),vec(value.basis.z)]

func _matrix_error(current:Array,saved:Array)->float:
	if current.size()!=4 or saved.size()!=4:return INF
	var worst:float=0
	for index:int in range(4):
		var a:Vector3=Vector3(current[index][0],current[index][1],current[index][2])
		var b:Vector3=Vector3(saved[index][0],saved[index][1],saved[index][2])
		worst=maxf(worst,a.distance_to(b))
	return worst

func _oven_snapshot()->Dictionary:
	if not oven_fixture:return {}
	var person:LifeActor=app.world.actors.player
	var action:Dictionary=app.household.member_sim("player").get_current_action()
	var oven:Dictionary=app._find_item(str(action.target_id))
	var interior:Node3D=app.world.oven_food_views.get(str(action.target_id))
	var joints:Dictionary={}
	for name:String in LifeActor.JOINT_NAMES:joints[name]=_matrix_data(person._joints[name].global_transform)
	return {"recipe":str(action.get("recipe","")),"elapsed":float(action.elapsed),"phase":LifeOvenSequence.phase(float(action.progress)),"body":_matrix_data(person._model.global_transform),"tray":_matrix_data(person._baking_tray.global_transform),"tray_visible":person._baking_tray.visible,"door":oven.node.find_child("OvenDoor",true,false).rotation.x,"interior":_matrix_data(interior.global_transform) if is_instance_valid(interior) else [],"interior_count":app.world.oven_food_views.size(),"joints":joints}

func _assert_oven_same(saved:Dictionary,label:String)->void:
	var current:Dictionary=_oven_snapshot()
	check(str(current.recipe)=="harvest_bake" and is_equal_approx(float(current.elapsed),float(saved.elapsed)),label+": the original paid bake and elapsed time survive.")
	check(_matrix_error(current.body,saved.body)<.001 and _matrix_error(current.tray,saved.tray)<.001,label+": the guardian body and dish retain their full physical transforms.")
	check(current.tray_visible==saved.tray_visible and current.interior_count==saved.interior_count and is_equal_approx(float(current.door),float(saved.door)),label+": door state and exclusive interior/held ownership survive.")
	if int(current.interior_count)>0:check(_matrix_error(current.interior,saved.interior)<.001,label+": the interior dish retains its actual rack transform.")
	var worst:float=0
	for name:String in current.joints:worst=maxf(worst,_matrix_error(current.joints[name],saved.joints[name]))
	check(worst<.003,label+": all articulated guardian joints retain the paid phase pose.")
	oven_evidence.append({"label":label,"saved":saved,"observed":current,"maximum_joint_transform_error":worst})
