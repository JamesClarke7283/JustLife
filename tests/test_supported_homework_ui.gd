extends "res://tests/test_family_ui.gd"
## Actual rendered public UI, routed arrival, pair cancellation and JSON restart.
var baseline:Dictionary={}

func _run() -> void:
	screenshot_dir="res://art/supported_homework"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):member_completed.append(id+":"+str(action.id)))
	if resume_only:
		baseline=JSON.parse_string(FileAccess.get_file_as_string("user://supported_homework_expected.json"))
		await _public_load()
		await _resume_pair()
	else:
		await _make_family()
		await _cancel_partial_pair()
		await _save_partial_pair()
	_write_report();app.queue_free();await frames(3)
	print("SUPPORTED_HOMEWORK_UI assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _make_family() -> void:
	await _enter_new_game()
	for i:int in range(2):
		if i>0:await press("+ Add Lifelet")
		var edit:LineEdit=app.find_children("*","LineEdit",true,false)[0]
		edit.text=FAMILY_NAMES[i];edit.text_changed.emit(edit.text)
		await _age("Child" if i==0 else "Adult")
	await _link(1,0,4)
	await press_member(FAMILY_NAMES[0]);await press("Find my home",true);await press("Start living",true)
	await press("Ⅱ")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	check(app.household.family_relationship("player","housemate_1")=="parent","A child and parent enter through public creation.")
	baseline={"funds":app.sim.funds,"friendship":app.sim.relationships.housemate_1.friendship,"logic":app.sim.skills.logic.duplicate(true),"parenting":app.household.members[1].sim.skills.parenting.duplicate(true)}

func _open_helper_picker() -> void:
	var desk:Dictionary=first_item("desk")
	app.world.object_clicked.emit(desk,app.world.camera.unproject_position(desk.node.position+Vector3(0,.6,0)))
	await frames(3);await press("Do homework together…")
	var choose:Button=app.find_child("HomeworkHelper_housemate_1",true,false)
	check(is_instance_valid(choose) and not choose.disabled,"The trusted idle household parent is available in the helper picker.")
	check(app.sim.speed==0,"Choosing a homework helper pauses the household.")
	await screenshot("01_helper_picker",false,false)
	await press("Learn together")
	check(app.sim.get_current_action().id=="homework" and app.household.members[1].sim.get_current_action().id=="help_homework","Public choice gives learner and helper their coordinated actions.")
	check(app.sim.get_current_action().cooperation_id==app.household.members[1].sim.get_current_action().cooperation_id,"The pair shares one activity identity.")

func _cancel_partial_pair() -> void:
	await _open_helper_picker()
	await press("▶")
	if not await wait_until(func()->bool:return active_is("homework",.2),"both Lifelets route to the desk and begin together",45):return
	check(app.household.members[1].sim.get_current_action().phase=="active","Both Lifelets are active after actual arrival.")
	check(app.sim.education.homework==0,"Partial pair has not awarded an assignment.")
	await press("Ⅱ");await _pair_view("02_learning_together")
	var progress:float=app.sim.get_current_action().elapsed
	var adult_transform:Transform3D=app.world.actors.housemate_1.visual.transform
	var child_transform:Transform3D=app.world.actors.player.visual.transform
	await create_timer(.4).timeout
	check(is_equal_approx(app.sim.get_current_action().elapsed,progress) and adult_transform.is_equal_approx(app.world.actors.housemate_1.visual.transform) and child_transform.is_equal_approx(app.world.actors.player.visual.transform),"Pause freezes the shared progress and both poses.")
	await _coaching_cycle()
	await press_member(FAMILY_NAMES[1]);await press("Cancel action")
	check(app.household.members[0].sim.action_queue.is_empty() and app.household.members[1].sim.action_queue.is_empty(),"Canceling from the helper ends both activities.")
	check(app.household.members[0].sim.education.homework==0 and app.sim.skills.parenting==baseline.parenting,"Partial cancellation awards neither homework nor Parenting XP.")
	await press_member(FAMILY_NAMES[0])
	check(app.sim.relationships.housemate_1.friendship==baseline.friendship,"Partial cancellation grants no cooperative friendship reward.")
	check(app.action_context.text=="TODAY IS YOURS","Canceling clears the previous partner from the selected Lifelet's HUD.")

func _coaching_cycle() -> void:
	var camera_state:Dictionary={"target":app.world.camera_target,"size":app.world.camera.size,"angle":app.world.camera_angle,"elevation":app.world.camera_elevation}
	var desk:Dictionary=first_item("desk")
	app.world.camera_target=desk.node.position+Vector3(0,.8,-.35)
	app.world.camera.size=5.0;app.world.camera_angle=1.1;app.world.camera_elevation=.48;app.world.update_camera()
	check(app.action_context.text.contains(FAMILY_NAMES[1].to_upper()) and app.action_label.text=="Learning together","The active learner sees who is helping and that this is shared learning.")
	check(app.queue_box.get_child(0).tooltip_text.contains("both Lifelets"),"The shared queue explains that cancellation ends both participants' work.")
	await press_member(FAMILY_NAMES[1])
	check(app.action_context.text.contains(FAMILY_NAMES[0].to_upper()) and app.action_label.text=="Helping with homework","Selecting the helper reverses the partner context without losing shared progress.")
	var samples:Array=[]
	for i:int in range(5):
		await press("▶");await create_timer(.85).timeout;await press("Ⅱ")
		var actor:LifeActor=app.world.actors.housemate_1
		var learner_actor:LifeActor=app.world.actors.player
		var sample:Dictionary={"index":i,"action":app.sim.get_current_action().duplicate(true),"motion_action":actor._motion_action,"action_time":actor._action_time,"right_arm":vec(actor._joints.Arm_R.rotation),"right_forearm":vec(actor._joints.Forearm_R.rotation),"learner_head":vec(learner_actor._joints.Head.rotation),"learner_action_time":learner_actor._action_time,"bone_poses":{}}
		for entry:Dictionary in actor._rig_bones:
			var rotation:Quaternion=entry.skeleton.get_bone_pose_rotation(int(entry.index))
			sample.bone_poses[str(entry.name)]=[rotation.x,rotation.y,rotation.z,rotation.w]
		samples.append(sample)
		check(actor._motion_action=="help_homework","Actual rendered helper keeps its coaching motion while the assignment runs.")
		await screenshot("02_coaching_cycle_%02d"%i,false,false)
	var trace:=FileAccess.open(screenshot_dir+"/coaching_cycle.json",FileAccess.WRITE)
	trace.store_string(JSON.stringify(samples,"\t"));trace.close()
	app.world.camera_target=camera_state.target;app.world.camera.size=camera_state.size
	app.world.camera_angle=camera_state.angle;app.world.camera_elevation=camera_state.elevation;app.world.update_camera()

func _save_partial_pair() -> void:
	await _open_helper_picker();await press("▶")
	if not await wait_until(func()->bool:return active_is("homework",.25),"retry after cancellation begins through normal arrival",45):return
	await press("Ⅱ")
	baseline["elapsed"]=app.sim.get_current_action().elapsed
	baseline["session"]=app.sim.get_current_action().cooperation_id
	baseline["helper_position"]=vec(app.household.members[1].sim.get_current_action().target_position)
	await _public_save("Homework together — unfinished assignment")
	var file:=FileAccess.open("user://supported_homework_expected.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(baseline));file.close()
	check(app.household.members[0].sim.education.homework==0,"Saving an unfinished pair does not complete the assignment.")
	await screenshot("03_saved_partial_pair")

func _resume_pair() -> void:
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	var learner:LifeSim=app.household.members[0].sim
	var helper:LifeSim=app.household.members[1].sim
	check(learner.get_current_action().cooperation_id==baseline.session and helper.get_current_action().cooperation_id==baseline.session,"Fresh-process load preserves the shared activity identity.")
	check(is_equal_approx(learner.get_current_action().elapsed,float(baseline.elapsed)),"Fresh-process load preserves the learner's authoritative elapsed time.")
	var expected_point:Vector3=Vector3(float(baseline.helper_position[0]),float(baseline.helper_position[1]),float(baseline.helper_position[2]))
	check(helper.get_current_action().target_position.is_equal_approx(expected_point),"Fresh-process load preserves the caregiver's separate standing point.")
	check(learner.get_current_action().phase=="approach" and helper.get_current_action().phase=="approach","Both Lifelets re-establish arrival safely after loading.")
	await press("▶")
	if await wait_until(func()->bool:return active_is("homework",.3),"loaded pair reaches its restored desk and standing point",40):
		await press("Ⅱ");await _pair_view("04_resumed_pair");await press("▶")
	await wait_until(func()->bool:return learner.action_queue.is_empty() and helper.action_queue.is_empty(),"paired assignment completes once",25)
	await press("Ⅱ")
	check(learner.education.homework==1 and LifeEducation.summary(learner.education).homework_ready,"Cooperative completion records one prepared assignment.")
	check(helper.skills.parenting.level==1 and is_equal_approx(helper.skills.parenting.xp,20.0),"The caregiver earns exactly20 Parenting XP.")
	check(learner.relationships.housemate_1.friendship>=float(baseline.friendship)+6 and helper.relationships.player.friendship>=float(baseline.friendship)+6,"Completed shared work strengthens both relationship directions.")
	check(member_completed.count("player:homework")==1 and member_completed.count("housemate_1:help_homework")==1,"Both completion events happen exactly once after restart.")
	check(app.household.funds==int(baseline.funds),"Cooperative homework does not invent household money.")
	await press_member(FAMILY_NAMES[1]);await press("Skills")
	check(app.skill_labels.has("parenting"),"The adult's Parenting level is visible in the Skills panel.")
	check(app.skill_progress_labels.parenting.text=="40%" and is_equal_approx(app.skill_bars.parenting.value,40.0),"The caregiver sees the earned20XP as40percent progress toward level2.")
	await screenshot("05_parenting_progress")
	await press_member(FAMILY_NAMES[0])
	var desk:Dictionary=first_item("desk")
	app.world.object_clicked.emit(desk,app.world.camera.unproject_position(desk.node.position+Vector3(0,.6,0)));await frames(3)
	var found:bool=false
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and node.text=="Do homework together…":found=node.disabled and not node.tooltip_text.is_empty()
	check(found,"A completed daily assignment disables another shared session with a reason.")
	app.close_overlay()
	await _review_speech()

func _review_speech() -> void:
	await frames(3)
	var bubbles: Control = app.activity_bubbles
	check(bubbles.visible and bubbles.cards.size()==2,"Completed shared homework shows both speakers in the live overlay.")
	var remaining:float=app.player.speech_presentation().remaining
	await create_timer(.4).timeout
	check(is_equal_approx(app.player.speech_presentation().remaining,remaining),"Pause holds readable speech for inspection.")
	for zoom:float in [18.0,30.0,7.0]:
		if zoom==7.0:app.world.camera_target=(app.world.actors.player.position+app.world.actors.housemate_1.position)*.5+Vector3(0,.7,0)
		app.world.camera.size=zoom;app.world.update_camera();await frames(4)
		_check_bubble_layout("camera zoom %d"%zoom)
		await screenshot("06_speech_zoom_%d"%zoom,false,false)
	root.size=Vector2i(960,600);await frames(10)
	check(root.size==Vector2i(960,600) and DisplayServer.window_get_size()==Vector2i(960,600),"The rendered window actually resized to 960 by 600.")
	app.world.camera_target=Vector3.ZERO
	app.world.camera.size=18;app.world.update_camera();await frames(4)
	_check_bubble_layout("960 by 600 window")
	await screenshot("07_speech_small_window",false,false)
	await press("PauseMenu");await frames(3)
	check(not bubbles.visible,"Opening a modal hides in-world bubbles.")
	await press("Resume");await frames(3)
	check(bubbles.visible,"Closing the modal restores paused speech.")
	# Controlled presentation stress: these are existing actors at their real
	# positions. Supplying text tests wrapping/placement, not simulated activity.
	for actor:LifeActor in app.world.actors.values():
		actor.speech("Let's spend a little time together and make something to remember.")
	await frames(4);_check_bubble_layout("four simultaneous presentation messages",false)
	await screenshot("08_speech_four_actors",false,false)
	app.world.camera_target=Vector3(100,0,100);app.world.update_camera();await frames(3)
	check(bubbles.cards.is_empty(),"Speakers outside the camera do not leave detached captions behind.")
	for actor:LifeActor in app.world.actors.values():actor.clear_speech()
	app.world.camera_target=Vector3.ZERO;app.world.update_camera();await frames(3)
	check(bubbles.cards.is_empty(),"Clearing speech removes all presentation cards.")
	root.size=Vector2i(1440,900);await frames(3)

func _check_bubble_layout(context:String,require_homework_pair:bool=true) -> void:
	var shown:Array[Rect2]=[]
	var speakers:Array[String]=[]
	var bounds:Rect2=Rect2(Vector2(18,96),Vector2(app.get_viewport().get_visible_rect().size.x-36,594))
	for id:String in app.activity_bubbles.cards:
		var card:Panel=app.activity_bubbles.cards[id]
		if not card.is_visible_in_tree():continue
		var area:Rect2=card.get_global_rect()
		check(bounds.encloses(area),"Speech stays inside the live viewport: "+context+" / "+id)
		for prior:Rect2 in shown:check(not area.intersects(prior),"Simultaneous speech cards remain separate: "+context)
		shown.append(area)
		speakers.append(id)
		var text:Label=card.get_node("Words")
		var physical:float=text.get_theme_font_size("font_size")*app.get_viewport().get_screen_transform().get_scale().x
		check(physical>=15.5,"Speech text stays at least fifteen physical pixels: "+context+" / "+id)
		check(text.size.y>=text.get_minimum_size().y,"Speech wraps without vertical truncation: "+context+" / "+id)
		check(not app.world.actors[id]._speech.visible,"No duplicate tiny world label behind the overlay: "+id)
	if require_homework_pair:
		check("player" in speakers and "housemate_1" in speakers,"Both nearby homework speakers remain readable: "+context)
	else:
		check("player" in speakers and shown.size()>=2,"Crowded speech preserves the selected speaker and separate nearby conversation: "+context)

func _pair_view(label_text:String) -> void:
	var before:Transform3D=app.world.camera.transform
	var size:float=app.world.camera.size
	var target:Vector3=app.world.camera_target
	var desk:Dictionary=first_item("desk")
	app.world.camera_target=desk.node.position+Vector3(0,.6,-.35);app.world.camera.size=6.3;app.world.update_camera()
	await screenshot(label_text,false,false)
	app.world.camera.transform=before;app.world.camera.size=size;app.world.camera_target=target
