extends "res://tests/test_lifecycle_playthrough.gd"
## Critic-owned public age creation, grounded school actions and saved history.
## Real renderer/frames; no direct time jumps, arrival callbacks or age mutation.
const CHILD_NAME: String = "Robin Reed"
const ADULT_NAME: String = "Morgan Reed"

func _run() -> void:
	screenshot_dir = "res://art/school_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene = app
	await frames(4)
	app.set_sound(false)
	app.household.notice.connect(func(message: String):notices.append(message))
	app.household.member_action_finished.connect(func(member_id: String,action: Dictionary):member_completed.append(member_id + ":" + str(action.id)))
	if resume_only:
		await _restart_school()
	else:
		await _create_school_household()
		await _school_activities()
		await _school_birthday()
		await _save_school()
	_write_report()
	app.queue_free();await frames(3)
	print("SCHOOL_UI_RESULT assertions=%d failures=%d resume=%s" % [assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _choose_age(label_text: String) -> void:
	var control: OptionButton = app.find_child("CreatorAge",true,false)
	check(is_instance_valid(control) and control.is_visible_in_tree(),"Creator exposes the visible age selector.")
	if not is_instance_valid(control):return
	var index: int = -1
	for i: int in range(control.item_count):
		if control.get_item_text(i) == label_text:index = i
	check(index >= 0,"Creator supports " + label_text + " with an available age model.")
	if index < 0:return
	control.select(index);control.item_selected.emit(index)
	await frames(8)

func _set_name(value: String) -> void:
	var edit: LineEdit = app.find_children("*","LineEdit",true,false)[0]
	edit.text = value;edit.text_changed.emit(value)

func _create_school_household() -> void:
	await _enter_new_game()
	_set_name(CHILD_NAME)
	await _choose_age("Child")
	check(app.profile.age_stage == "child" and app.preview.profile.age_stage == "child","Child selection updates draft and rendered creator preview.")
	check(str(app.preview._model.scene_file_path).contains("child") and app.preview.get_display_height() < 1.4,"Child preview uses the authored child asset and stature.")
	await screenshot("01_child_creator")
	await press("Face")
	await screenshot("02_child_face")
	await press("+ Add Lifelet")
	_set_name(ADULT_NAME)
	await _choose_age("Adult")
	check(app.profile.age_stage == "adult" and app.preview.get_display_height() > 1.6,"Adult household member has adult age and stature.")
	await screenshot("03_adult_creator")
	await press_member(CHILD_NAME)
	await press("Find my home",true)
	await press("Willow Cottage")
	await press("Start living",true)
	await press("Ⅱ")
	for member: Dictionary in app.household.members:member.sim.autonomy = false
	check(app.household.members.size() == 2 and app.sim.character.age_stage == "child","Child and adult enter the home with the child selected.")
	check(app.household.members[1].sim.character.age_stage == "adult","The second household member retains adult age.")
	check(str(app.player._model.scene_file_path).contains("child"),"Live child actor loads the authored age-specific model.")
	await press("School")
	check(_visible_text_contains("Willow School"),"School HUD presents the child's actual school.")
	await press("School record",true)
	check(_visible_text_contains("0 classes attended") and _visible_text_contains("Grade C"),"Initial school record shows the starting grade and zero completed classes.")
	await screenshot("04_initial_school_record")
	await press("Back to life")

func _school_activities() -> void:
	var initial_funds: int = app.sim.funds
	var initial_position: Vector3 = app.player.position
	var initial_logic: float = app.sim.skills.logic.xp
	await press("Homework")
	check(not app.sim.action_queue.is_empty() and app.sim.get_current_action().id == "homework","School HUD Homework queues a real furniture action.")
	check(app.sim.education.homework == 0 and app.sim.funds == initial_funds,"Queued homework grants no assignment, learning or money before arrival.")
	await press("▶")
	if await wait_until(func()->bool:return active_is("homework",.2),"normal-speed child approach and homework",45):
		check(app.player.position.distance_to(initial_position) > .5,"Child reaches homework through actual routed movement.")
		check(app.sim.education.homework == 0,"Partial homework does not award a completed assignment.")
		await _school_pose("05_child_homework")
	await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"actual homework completion",20)
	await press("Ⅱ")
	check(member_completed.has("player:homework") and app.sim.education.homework == 1,"Actual homework completion records exactly one assignment.")
	check(app.sim.skills.logic.xp > initial_logic and LifeEducation.summary(app.sim.education).homework_ready,"Homework grants learning and prepares the next class.")
	var school_before: Dictionary = app.sim.education.duplicate(true)
	var needs_before: Dictionary = app.sim.needs.duplicate(true)
	var logic_before: float = app.sim.skills.logic.xp
	await press("School record",true)
	await press("Online classes")
	check(app.sim.get_current_action().id == "school","School HUD Online classes queues its real activity.")
	await press("▶")
	if await wait_until(func()->bool:return active_is("school",.15),"normal-speed child class begins",40):
		check(app.sim.education.attended == 0,"Partial class does not grant attendance.")
		await _school_pose("06_child_online_class")
		await press("Ⅱ")
		var paused_elapsed: float = app.sim.get_current_action().elapsed
		var paused_transform: Transform3D = app.player.visual.transform
		await create_timer(.4).timeout
		check(is_equal_approx(app.sim.get_current_action().elapsed,paused_elapsed) and app.player.visual.transform.is_equal_approx(paused_transform),"Pause freezes both class progress and the child activity pose.")
		await screenshot("07_school_paused",false,false)
		await press("▶")
	await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"actual three-hour school completion",40)
	await press("Ⅱ")
	check(member_completed.has("player:school") and app.sim.education.attended == int(school_before.attended)+1,"A complete class records attendance through normal frame processing.")
	check(app.sim.education.prepared == 1 and not LifeEducation.summary(app.sim.education).homework_ready,"Class consumes the prepared homework once.")
	check(app.sim.skills.logic.xp >= logic_before+10 and app.sim.needs.energy < needs_before.energy,"Prepared class grants increased logic learning and costs energy.")
	check(app.sim.funds == initial_funds,"Homework and classes do not invent wages or fees.")
	await press("School record",true)
	check((_visible_text_contains("1 class attended") or _visible_text_contains("1 classes attended")) and (_visible_text_contains("1 assignment") or _visible_text_contains("1 assignments")),"Public record presents the completed class and assignment.")
	await screenshot("08_completed_school_record")
	await press("Back to life")

func _school_pose(label_text: String) -> void:
	var old_transform: Transform3D = app.world.camera.transform
	var old_size: float = app.world.camera.size
	var at: Vector3 = app.player.position + Vector3(0,.78,0)
	app.world.camera.size = 3.4
	app.world.camera.position = at + Vector3(3.4,1.9,3.7)
	app.world.camera.look_at(at,Vector3.UP)
	await screenshot(label_text,false,false)
	evidence.append({"capture":label_text,"activity":app.sim.get_current_action().duplicate(true),"actor_profile":app.player.profile.duplicate(true),"model":app.player._model.scene_file_path,"activity_anchor":str(app.player._activity_anchor),"sit_amount":app.player._sit_amount})
	app.world.camera.transform = old_transform;app.world.camera.size = old_size

func _school_birthday() -> void:
	var funds_before: int = app.sim.funds
	await press("My Lifelet")
	await press("Celebrate a birthday")
	check(_visible_text_contains("become a teen"),"Child birthday dialog names the next stage with correct wording.")
	await screenshot("09_child_birthday_choice")
	await press("Celebrate · ℒ30")
	await press("▶")
	await wait_until(func()->bool:return active_is("birthday",.15),"actual child birthday begins",40)
	await screenshot("10_child_birthday_active",true,false)
	await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"actual child birthday completion",20)
	await press("Ⅱ");await frames(10)
	check(app.sim.character.age_stage == "teen" and app.player.profile.age_stage == "teen","Completed child birthday updates simulation and live actor to teen.")
	check(str(app.player._model.scene_file_path).contains("teen") and app.player.get_display_height() > 1.4,"Birthday replaces the child model with the authored teen model.")
	check(app.sim.funds == funds_before-30 and app.sim.lifecycle.history.size() == 1,"Birthday costs exactly30 and records exactly one transition.")
	check(app.sim.education.records.size() == 1 and app.sim.education.records[0].stage == "child" and app.sim.education.records[0].attended == 1,"Birthday archives actual primary attendance and learning history.")
	check(app.sim.education.records[0].outcome == "unfinished","One class is not misrepresented as completed primary schooling.")
	await press("School")
	check(_visible_text_contains("Morrow Secondary"),"Teen HUD presents secondary school after birthday.")
	await press("My Lifelet")
	await press("School history")
	check(_visible_text_contains("Willow School") and _visible_text_contains("Coursework incomplete"),"Public school history accurately explains the partial childhood record.")
	await screenshot("11_school_history")
	await press("Back to life")
	await screenshot("12_teen_after_birthday",true)

func _save_school() -> void:
	var expected: Dictionary = {"state":app.sim.get_state(),"player":vec(app.player.position),"world":app.world.serialize_items(),"lot":app.selected_lot,"floor":app.floor_color,"selected_index":app.household.selected_index,"members":[]}
	for member: Dictionary in app.household.members:expected.members.append({"id":member.id,"state":member.sim.get_state(),"position":vec(app.world.actors[member.id].position)})
	await _public_save("Robin — first school day and birthday")
	var file := FileAccess.open("user://school_expected.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(expected));file.close()

func _restart_school() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://school_expected.json"))
	await _public_load()
	await _compare_saved(expected,"school restart")
	for i: int in range(app.household.members.size()):
		check(equivalent(app.household.members[i].sim.education,expected.members[i].state.education),"Fresh restart restores the exact schooling counters, archived records and dates.")
		check(equivalent(app.household.members[i].sim.lifecycle,expected.members[i].state.lifecycle),"Fresh restart restores the exact birthday history and progress.")
	check(app.sim.character.age_stage == "teen" and str(app.player._model.scene_file_path).contains("teen"),"Restored teen age loads the correct rendered model.")
	await press("School")
	await press("School record",true)
	check(_visible_text_contains("Morrow Secondary") and _visible_text_contains("0 classes attended"),"Fresh teen school record begins secondary counters without discarding primary history.")
	await screenshot("13_secondary_record_after_restart")
	await press("Back to life")
	await press("My Lifelet")
	await press("School history")
	check(_visible_text_contains("Willow School") and _visible_text_contains("Coursework incomplete"),"Archived primary outcome remains visible after fresh restart.")
	await screenshot("14_school_history_after_restart")
	await press("Back to life")
