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
	await press_member(FAMILY_NAMES[1]);await press("Cancel action")
	check(app.household.members[0].sim.action_queue.is_empty() and app.household.members[1].sim.action_queue.is_empty(),"Canceling from the helper ends both activities.")
	check(app.household.members[0].sim.education.homework==0 and app.sim.skills.parenting==baseline.parenting,"Partial cancellation awards neither homework nor Parenting XP.")
	await press_member(FAMILY_NAMES[0])
	check(app.sim.relationships.housemate_1.friendship==baseline.friendship,"Partial cancellation grants no cooperative friendship reward.")

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
	await screenshot("05_parenting_progress")
	await press_member(FAMILY_NAMES[0])
	var desk:Dictionary=first_item("desk")
	app.world.object_clicked.emit(desk,app.world.camera.unproject_position(desk.node.position+Vector3(0,.6,0)));await frames(3)
	var found:bool=false
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and node.text=="Do homework together…":found=node.disabled and not node.tooltip_text.is_empty()
	check(found,"A completed daily assignment disables another shared session with a reason.")
	app.close_overlay()

func _pair_view(label_text:String) -> void:
	var before:Transform3D=app.world.camera.transform
	var size:float=app.world.camera.size
	var target:Vector3=app.world.camera_target
	var desk:Dictionary=first_item("desk")
	app.world.camera_target=desk.node.position+Vector3(0,.6,-.35);app.world.camera.size=6.3;app.world.update_camera()
	await screenshot(label_text,false,false)
	app.world.camera.transform=before;app.world.camera.size=size;app.world.camera_target=target
