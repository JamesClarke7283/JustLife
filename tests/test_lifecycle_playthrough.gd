extends "res://tests/test_family_playthrough.gd"
## Independent public settings, birthday, named restart and garden inspection.

func _run() -> void:
	screenshot_dir = "res://art/lifecycle_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.set_sound(false)
	app.household.member_action_finished.connect(func(member_id: String, action: Dictionary) -> void:member_completed.append(member_id + ":" + str(action.id)))
	if resume_only:
		await _restart_lifecycle()
	else:
		await _create_household()
		await _settings_flow()
		await _birthday_flow()
		await _ordered_people("07_ordered_people")
		await _garden_view()
		await _save_lifecycle()
	_write_report()
	app.queue_free()
	await frames(3)
	print("LIFECYCLE_UI_RESULT assertions=%d failures=%d resume=%s" % [assertions, failures.size(), str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _create_household() -> void:
	await _enter_new_game()
	for i: int in range(3):
		if i > 0:await press("+ Add Lifelet")
		var edit: LineEdit = app.find_children("*", "LineEdit", true, false)[0]
		edit.text = PEOPLE[i]
		edit.text_changed.emit(edit.text)
	await press_member(PEOPLE[0])
	await press("Connections")
	await _connection(1, 2)
	await _connection(2, 1)
	await press("Back to creating")
	await press("Find my home", true)
	await press("Willow Cottage")
	await press("Start living", true)
	app.household.set_speed(0)
	for member: Dictionary in app.household.members:member.sim.autonomy = false
	check(app.sim.character.age_stage == "young_adult", "Default creator enters live as a young adult.")
	check(app.sim.relationship_order().slice(0, 2) == ["housemate_1", "housemate_2"], "Partner and sibling precede unrelated acquaintances.")

func _open_settings() -> void:
	await press("PauseMenu")
	await press("Life settings")
	check(app.sim.speed == 0, "Life settings pause the live household.")

func _settings_controls() -> Array:
	var pace: OptionButton = app.find_child("LifespanSetting", true, false)
	var automatic: CheckButton = app.find_child("AutomaticAgingSetting", true, false)
	check(is_instance_valid(pace) and pace.is_visible_in_tree() and is_instance_valid(automatic) and automatic.is_visible_in_tree(), "Life settings expose both visible controls.")
	return [pace, automatic]

func _edit_settings(pace_index: int, automatic_enabled: bool) -> void:
	var controls: Array = _settings_controls()
	controls[0].select(pace_index)
	controls[0].item_selected.emit(pace_index)
	controls[1].button_pressed = automatic_enabled
	await frames(3)

func _check_settings(lifespan: String, automatic_enabled: bool, context: String) -> void:
	for member: Dictionary in app.household.members:
		check(member.sim.lifecycle.lifespan == lifespan and member.sim.lifecycle.auto_age == automatic_enabled, context + ": settings apply to " + str(member.sim.character.name))

func _settings_flow() -> void:
	await press("▶")
	await create_timer(.45).timeout
	await _open_settings()
	var controls: Array = _settings_controls()
	check(controls[0].item_count == 3 and controls[0].get_item_text(0) == "Short" and controls[0].get_item_text(1) == "Normal" and controls[0].get_item_text(2) == "Long", "The lifespan selector exposes Short, Normal and Long.")
	check(controls[0].selected == 1 and controls[1].button_pressed, "Initial settings display normal pace with automatic birthdays.")
	await _edit_settings(2, false)
	await screenshot("01_settings_before_cancel", false, false)
	await press("Cancel")
	_check_settings("normal", true, "Cancel preserves current household settings")
	check(app.sim.speed == 1, "Cancel restores the speed from before the settings menu.")
	await _open_settings()
	await _edit_settings(0, false)
	await press("Apply")
	_check_settings("short", false, "Apply short pace")
	check(app.sim.speed == 1, "Apply restores the prior live speed.")
	await press("Ⅱ")
	var progress: Array = []
	for member: Dictionary in app.household.members:progress.append(member.sim.lifecycle.progress)
	await press("▶")
	var initial_minutes: float = app.sim.minutes
	await create_timer(.55).timeout
	await press("Ⅱ")
	check(app.sim.minutes > initial_minutes, "Time advances with automatic birthdays disabled.")
	for i: int in range(app.household.members.size()):check(is_equal_approx(app.household.members[i].sim.lifecycle.progress, progress[i]), "Disabled automatic birthdays preserve member age progress while time runs.")
	await _open_settings()
	await _edit_settings(2, false)
	await screenshot("02_settings_applied_long", false, false)
	await press("Apply")
	_check_settings("long", false, "Apply long pace")
	for i: int in range(app.household.members.size()):check(is_equal_approx(app.household.members[i].sim.lifecycle.progress, progress[i]), "Changing pace preserves existing fractional age.")
	check(app.sim.speed == 0, "Settings opened from pause return to pause.")

func _birthday_flow() -> void:
	var old_profile: Dictionary = app.sim.character.duplicate(true)
	var old_skills: Dictionary = app.sim.skills.duplicate(true)
	var old_relationships: Dictionary = app.sim.relationships.duplicate(true)
	var old_funds: int = app.sim.funds
	await press("My Lifelet")
	check(_visible_text_contains("Young adult · aging paused"), "Personal panel describes the current age and paused aging.")
	await screenshot("03_person_before_birthday")
	await press("Celebrate a birthday")
	await screenshot("04_birthday_choice")
	await press("Keep this age")
	check(app.sim.character == old_profile and app.sim.funds == old_funds and app.sim.action_queue.is_empty(), "Keep this age preserves profile, funds and queue.")
	await press("My Lifelet")
	await press("Celebrate a birthday")
	var before_position: Vector3 = app.player.position
	await press("Celebrate · ℒ30")
	check(not app.sim.action_queue.is_empty() and app.sim.get_current_action().id == "birthday", "Confirming the birthday queues its real activity.")
	check(app.sim.character.age_stage == "young_adult" and app.sim.funds == old_funds, "Paused birthday is not an instant age change or charge.")
	await press("▶")
	if await wait_until(func() -> bool: return active_is("birthday", .15), "real birthday approach and activity", 40):
		check(app.player.position.distance_to(before_position) > .5, "The birthday starts after actual routed movement.")
		check(app.sim.funds == old_funds - 30, "The active birthday costs exactly 30.")
		check(app.sim.character.age_stage == "young_adult", "Age remains unchanged until the birthday finishes.")
		await screenshot("05_birthday_in_progress", true, false)
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "normal-speed birthday completion", 20)
	await frames(5)
	await press("Ⅱ")
	check(member_completed.has("player:birthday"), "Birthday completion comes from actual frame processing.")
	check(app.sim.character.age_stage == "adult" and app.player.profile.age_stage == "adult" and app.age_label.text == "Adult", "Completion refreshes simulation age, rendered actor profile and HUD.")
	check(app.sim.lifecycle.history.size() == 1 and app.sim.lifecycle.history[0].from == "young_adult" and app.sim.lifecycle.history[0].to == "adult", "Birthday records exactly one adjacent-stage transition.")
	check(equivalent(app.sim.skills, old_skills) and equivalent(app.sim.relationships, old_relationships) and app.sim.character.traits == old_profile.traits, "Birthday retains traits, learned skills and relationships.")
	check(app.household.members[1].sim.character.age_stage == "young_adult" and app.household.members[2].sim.character.age_stage == "young_adult", "The birthday advances only its participating Lifelet.")
	await press("My Lifelet")
	check(_visible_text_contains("Adult · aging paused"), "The personal panel updates to adult after completion.")
	await screenshot("06_person_after_birthday")
	await press("Back to life")

func _visible_text_contains(fragment: String) -> bool:
	for label: Label in app.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text.contains(fragment):return true
	return false

func _ordered_people(capture_name: String) -> void:
	await press("People")
	var preview_names: Array = []
	for node: Button in app.ui.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.get_global_rect().position.y > 770 and node.text in ["Bea Brook", "Cy Cedar", "Maya Chen", "Leo Morgan"]:preview_names.append(node.text)
	check(preview_names == ["Bea Brook", "Cy Cedar"], "People preview shows the partner and sibling first.")
	await press("All relationships", true)
	var rows: Array = []
	for node: Button in app.overlay.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.text in ["Bea Brook", "Cy Cedar", "Maya Chen", "Leo Morgan"]:rows.append({"name":node.text,"y":node.get_global_rect().position.y})
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return a.y < b.y)
	check(rows.size() == 4 and rows[0].name == "Bea Brook" and rows[1].name == "Cy Cedar", "Full relationship list uses the same partner/sibling priority.")
	await screenshot(capture_name)
	await press("Back to life")

func _garden_view() -> void:
	var plants: Array[Node] = app.world.house.find_children("*", "MultiMeshInstance3D", true, false)
	plants = plants.filter(func(node: Node) -> bool:return bool(node.get_meta("garden_decoration", false)))
	check(plants.size() == 24, "The two front flower beds contain grounded plant clumps.")
	if plants.is_empty():return
	var old_transform: Transform3D = app.world.camera.transform
	var old_size: float = app.world.camera.size
	var at: Vector3 = Vector3(-3.5, -.03, 6.8)
	app.world.camera.size = 2.2
	app.world.camera.position = at + Vector3(1.5, 1.4, 2.1)
	app.world.camera.look_at(at, Vector3.UP)
	await screenshot("08_grounded_flower_bed")
	app.world.camera.transform = old_transform
	app.world.camera.size = old_size

func _save_lifecycle() -> void:
	var expected: Dictionary = {"state":app.sim.get_state(),"player":vec(app.player.position),"world":app.world.serialize_items(),"lot":app.selected_lot,"floor":app.floor_color,"selected_index":app.household.selected_index,"members":[],"relationship_order":app.sim.relationship_order()}
	for member: Dictionary in app.household.members:expected.members.append({"id":member.id,"state":member.sim.get_state(),"position":vec(app.world.actors[member.id].position)})
	await _public_save("Ari — a birthday at our own pace")
	var file := FileAccess.open("user://lifecycle_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected));file.close()

func _restart_lifecycle() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://lifecycle_expected.json"))
	await _public_load()
	await _compare_saved(expected, "lifecycle restart")
	for i: int in range(app.household.members.size()):
		check(equivalent(app.household.members[i].sim.lifecycle, expected.members[i].state.lifecycle) and app.household.members[i].sim.character.age_stage == expected.members[i].state.character.age_stage, "Fresh restart restores member age, progress, settings and birthday history.")
	check(app.sim.relationship_order() == expected.relationship_order, "Relationship order survives named-save serialization and restart.")
	await _ordered_people("09_ordered_people_after_restart")
	await _open_settings()
	var controls: Array = _settings_controls()
	check(controls[0].selected == 2 and not controls[1].button_pressed, "Restored public settings display long pace with automatic birthdays off.")
	await screenshot("10_settings_after_restart", false, false)
	await press("Cancel")
	await press("My Lifelet")
	check(_visible_text_contains("Adult · aging paused"), "Loaded adult age is presented correctly.")
	await screenshot("11_person_after_restart")
	await press("Back to life")
