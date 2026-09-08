extends "res://tests/test_playthrough.gd"
## Real-frame creator kinship, reciprocal relationship growth and restart flow.
const PEOPLE: Array[String] = ["Ari Atlas", "Bea Brook", "Cy Cedar", "Dee Dawn"]

func _run() -> void:
	screenshot_dir = "res://art/family_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.set_sound(false)
	app.household.notice.connect(func(message: String) -> void: notices.append(message))
	app.household.member_action_finished.connect(func(member_id: String, action: Dictionary) -> void:
		member_completed.append(member_id + ":" + str(action.id)))
	if resume_only:
		await _resume_family()
	else:
		await _create_connections()
		await _live_connections()
		await _save_family()
	_write_report()
	app.queue_free()
	await frames(3)
	print("FAMILY_RESULT assertions=%d failures=%d resume=%s" % [assertions, failures.size(), str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _connection(other_index: int, role_index: int) -> void:
	var option: OptionButton
	for node: Node in app.find_children("*", "OptionButton", true, false):
		if node.is_visible_in_tree() and int(node.get_meta("connection_member", -1)) == other_index:option = node
	check(is_instance_valid(option), "Visible connection selector for creator member " + str(other_index))
	if not is_instance_valid(option):return
	option.select(role_index)
	option.item_selected.emit(role_index)
	await frames(4)

func _create_connections() -> void:
	await _enter_new_game()
	for i: int in range(4):
		if i > 0:await press("+ Add Lifelet")
		var edit: LineEdit = app.find_children("*", "LineEdit", true, false)[0]
		edit.text = PEOPLE[i]
		edit.text_changed.emit(edit.text)
	await press_member(PEOPLE[0])
	await press("Connections")
	await _connection(1, 1)
	check(app.creator_connection(1) == "siblings", "Creator declares Ari and Bea siblings.")
	await screenshot("01_first_sibling_pair")
	await press("Back to creating")
	await press_member(PEOPLE[1])
	await press("Connections")
	await _connection(2, 1)
	await press("Back to creating")
	await press_member(PEOPLE[0])
	await press("Connections")
	check(app.creator_connection(2) == "siblings", "Ari sees Cy as a sibling through the existing sibling chain.")
	var prior: Array = app.creator_family_links.duplicate(true)
	await _connection(2, 2)
	check(equivalent(app.creator_family_links, prior) and app.creator_connection(2) == "siblings", "An incompatible partner declaration preserves the sibling family.")
	check(is_instance_valid(app.notice_label) and app.notice_label.text.to_lower().contains("sibling"), "Invalid family choice explains the sibling conflict in the UI.")
	await screenshot("02_incompatible_connection_explained")
	await press("Back to creating")
	await press_member(PEOPLE[2])
	await press("Connections")
	await _connection(3, 2)
	check(app.creator_connection(3) == "partners", "Unrelated Cy and Dee start as partners.")
	await screenshot("03_existing_partners")
	await press("Back to creating")
	await press_member(PEOPLE[0])
	await press("Connections")
	prior = app.creator_family_links.duplicate(true)
	await _connection(3, 2)
	check(equivalent(app.creator_family_links, prior), "A second simultaneous partnership is refused without altering the draft.")
	await press("Back to creating")
	await press_member(PEOPLE[1])
	await press("Remove")
	check(app.household_profiles.size() == 3, "Removing the middle draft sibling retains three Lifelets.")
	await press_member(PEOPLE[0])
	await press("Connections")
	check(app.creator_connection(1) == "siblings", "Removing Bea retains Ari and Cy's established sibling kinship.")
	await screenshot("04_sibling_link_after_removal")
	await press("Back to creating")
	await press_member(PEOPLE[2])
	await press("Connections")
	check(app.creator_connection(2) == "partners", "Remaining partner connection follows the remapped household identity.")
	await press("Back to creating")
	await press_member(PEOPLE[0])
	await press("Find my home", true)
	await press("Willow Cottage")
	await press("Start living", true)
	app.household.set_speed(0)
	for member: Dictionary in app.household.members:member.sim.autonomy = false
	check(app.household.members.size() == 3, "Configured family moves into the chosen home.")
	_check_kinship("move-in")
	await screenshot("05_family_at_home")

func _check_kinship(context: String) -> void:
	var ari: Node = app.household.member_sim("player")
	var cy: Node = app.household.member_sim("housemate_1")
	var dee: Node = app.household.member_sim("housemate_2")
	check(ari.relationships.housemate_1.family_role == "siblings" and cy.relationships.player.family_role == "siblings", context + ": sibling roles are reciprocal.")
	check(cy.romantic_partner == "housemate_2" and dee.romantic_partner == "housemate_1", context + ": the starting partnership is reciprocal.")
	check(not ari.get_action_availability("flirt", "housemate_1").available, context + ": sibling romantic actions are unavailable.")

func _open_social(target_id: String) -> void:
	var actor: Node3D = app.world.actors[target_id]
	var item: Dictionary = {"id":target_id,"kind":"neighbor","label":actor.get_meta("display_name"),"node":actor,"size":Vector2(0.6, 0.6)}
	app.world.object_clicked.emit(item, Vector2(890, 380))
	await frames(4)

func _disabled_social(action_id: String, reason_fragment: String) -> void:
	var label_text: String = str(app.sim.get_action_definition(action_id).label)
	var found: Button
	for node: Node in app.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.text == label_text:found = node
	check(is_instance_valid(found) and found.disabled and found.tooltip_text.to_lower().contains(reason_fragment), "Unavailable " + action_id + " is disabled with an explanatory tooltip.")

func _perform_social(target_id: String, action_id: String, capture_name: String) -> void:
	await _open_social(target_id)
	var before_position: Vector3 = app.player.position
	await press(str(app.sim.get_action_definition(action_id).label))
	app.household.set_speed(8)
	if await wait_until(func() -> bool: return active_is(action_id, 0.30), "route and perform " + action_id, 40):
		check(app.player.position.distance_to(app.world.actors[target_id].position) < 1.8, "Social action starts within conversational range of its actual target.")
		if action_id == "friendly":check(app.player.position.distance_to(before_position) > 0.20, "Initial sibling conversation follows actual routed movement.")
		await screenshot(capture_name, true)
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "complete social action " + action_id, 25)
	app.household.set_speed(0)
	check(member_completed.has(str(app.household.selected_id()) + ":" + action_id), "Selected member completes " + action_id + " through real frame processing.")

func _live_connections() -> void:
	await _open_social("housemate_1")
	_disabled_social("flirt", "siblings")
	await screenshot("06_sibling_social_menu")
	app.close_overlay()
	await _perform_social("housemate_1", "friendly", "07_sibling_conversation")
	var ari: Node = app.household.member_sim("player")
	var cy: Node = app.household.member_sim("housemate_1")
	check(float(ari.relationships.housemate_1.friendship) > 55 and is_equal_approx(float(ari.relationships.housemate_1.friendship), float(cy.relationships.player.friendship)), "Sibling conversation improves friendship reciprocally.")
	check(ari.relationships.housemate_1.status == "Sibling" and cy.relationships.player.status == "Sibling", "Friendship growth retains the family identity.")
	await press_member(PEOPLE[2])
	await _open_social("housemate_2")
	_disabled_social("commit", "65")
	await screenshot("08_partner_commitment_requirement")
	app.close_overlay()
	await _perform_social("housemate_2", "flirt", "09_partner_flirt")
	var dee: Node = app.household.member_sim("housemate_2")
	check(float(cy.relationships.housemate_2.friendship) >= 65 and float(cy.relationships.housemate_2.romance) >= 65, "Partner interaction reaches the displayed commitment thresholds.")
	check(is_equal_approx(float(cy.relationships.housemate_2.romance), float(dee.relationships.housemate_1.romance)), "Romance growth is reciprocal between the playable partners.")
	await _perform_social("housemate_2", "commit", "10_making_a_commitment")
	check(cy.relationships.housemate_2.bond == "committed" and dee.relationships.housemate_1.bond == "committed", "Completed commitment changes both partners' bond.")
	check(not cy.social_history.is_empty() and not dee.social_history.is_empty(), "Both partners retain consequential social history.")
	await press("People")
	await press("All relationships", true)
	await screenshot("11_relationships_after_commitment")
	app.close_overlay()

func _save_family() -> void:
	var expected: Dictionary = {"state":app.sim.get_state(),"player":vec(app.player.position),"world":app.world.serialize_items(),"lot":app.selected_lot,"floor":app.floor_color,"selected_index":app.household.selected_index,"family":app.household.get_family_links(),"members":[]}
	for member: Dictionary in app.household.members:
		expected.members.append({"id":member.id,"state":member.sim.get_state(),"position":vec(app.world.actors[member.id].position)})
	await _public_save("Ari, Cy and Dee — a shared future")
	var file := FileAccess.open("user://family_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected));file.close()
	await screenshot("12_saved_family")

func _resume_family() -> void:
	check(FileAccess.file_exists("user://family_expected.json"), "Family checkpoint exists from the prior process.")
	if not FileAccess.file_exists("user://family_expected.json"):return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://family_expected.json"))
	await _public_load()
	await _compare_saved(expected, "family fresh-process")
	_check_kinship("fresh-process")
	check(equivalent(app.household.get_family_links(), expected.family), "Declared family links survive a fresh named-save restart.")
	var cy: Node = app.household.member_sim("housemate_1")
	var dee: Node = app.household.member_sim("housemate_2")
	check(cy.relationships.housemate_2.bond == "committed" and dee.relationships.housemate_1.bond == "committed", "Earned reciprocal commitment survives restart.")
	await screenshot("13_resumed_family")
	await _perform_social("housemate_2", "break_up", "14_ending_the_partnership")
	check(cy.romantic_partner.is_empty() and dee.romantic_partner.is_empty(), "Completed breakup clears both active partner identities.")
	check(cy.relationships.housemate_2.bond == "separated" and dee.relationships.housemate_1.bond == "separated", "Breakup records both sides as former partners.")
	check(cy.relationships.player.family_role == "siblings", "Ending a partnership leaves unrelated sibling kinship intact.")
	await press("People")
	await press("All relationships", true)
	await screenshot("15_relationships_after_separation")
	app.close_overlay()
