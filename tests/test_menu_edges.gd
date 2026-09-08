extends "res://tests/test_playthrough.gd"
## Independent actual-renderer edge cases for named saves and explicit deletion.
## Fixture files and deletion are confined by the inherited /tmp isolation guard.

var library: Script
var slot_ids: Array[String] = []
var long_title: String = "The extraordinary Juniper Bay household and its next chapter".left(60)

func _run() -> void:
	screenshot_dir = "res://art/menu_edges"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	library = load("res://scripts/save_library.gd")
	await frames(4)
	app.set_sound(false)
	check(app.mode == "menu" and library.list_saves().is_empty(), "Menu edge run starts with an empty isolated library.")
	await screenshot("01_empty_main_menu")
	await _enter_new_game()
	for i: int in range(8):
		if i > 0:await press("+ Add Lifelet")
		var edit: LineEdit = app.find_children("*", "LineEdit", true, false)[0]
		edit.text = "Alexandria " + str(i + 1) + " Autumn Meadow-Rivers"
		edit.text_changed.emit(edit.text)
	await press("Find my home", true)
	await press("Willow Cottage")
	await press("Start living", true)
	app.household.set_speed(0)
	for member: Dictionary in app.household.members:member.sim.autonomy = false
	var labels: Dictionary = {}
	for node: Node in app.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and str(node.tooltip_text).begins_with("Alexandria"):
			labels[str(node.text)] = true
	check(labels.size() == 8, "Eight household chips remain distinguishable when first/last initials are identical.")
	await queue_via_menu("bookshelf", "read")
	if await wait_until(func() -> bool: return app.queue_box.get_child_count() > 0, "queued activity appears in the HUD", 3):
		var queue_button: Button = app.queue_box.get_child(0)
		var style: StyleBox = queue_button.get_theme_stylebox("normal")
		check(style is StyleBoxFlat and style.bg_color.a > 0.95 and style.bg_color.get_luminance() > 0.60, "Queue card resolves an opaque light theme background in the actual scene tree.")
		var visible_cancel: bool = false
		for node: Node in queue_button.find_children("*", "Label", true, false):
			if node.text == "×":visible_cancel = queue_button.get_global_rect().encloses(node.get_global_rect())
		check(visible_cancel, "Queue cancel mark stays within the visible card.")
		await screenshot("01b_paused_queue_theme")
	await press("Cancel action")
	await press("☰")
	await press("Save this life")
	app.menus.name_input.text = "   "
	await press("Save as new")
	check(library.list_saves().is_empty() and app.overlay_open, "Whitespace-only save name is refused without creating a file or closing the picker.")
	app.menus.name_input.text = long_title
	await press("Save as new")
	slot_ids.append(str(app.active_save_id))
	check(library.read_slot(slot_ids[0]).ok, "Long title and eight long Lifelet names create a readable save.")
	for i: int in range(4):
		await _public_save("Juniper chapter " + str(i + 2))
		slot_ids.append(str(app.active_save_id))
	check(library.list_saves().size() == 5, "Five separately named saves coexist.")
	await press("☰")
	await press("Load a saved life")
	await _select_slot(slot_ids[0])
	_check_long_copy("saved-life picker", "Alexandria")
	await screenshot("02_five_saves_eight_long_names")
	root.size = Vector2i(1120, 700)
	await frames(6)
	await screenshot("03_small_window_save_picker")
	root.size = Vector2i(1440, 900)
	await frames(6)
	await press("Delete save…")
	check(library.read_slot(slot_ids[0]).ok and library.list_saves().size() == 5, "Opening delete confirmation changes no saved files.")
	var keep: Button = button_matching("Keep save")
	check(keep == root.gui_get_focus_owner(), "Delete confirmation gives keyboard focus to Keep save.")
	_check_long_copy("delete confirmation", "“" + long_title)
	await screenshot("04_long_household_delete_confirmation")
	await press("Keep save")
	check(library.read_slot(slot_ids[0]).ok and library.list_saves().size() == 5, "Keep save preserves every slot.")
	await press("Delete save…")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await frames(4)
	check(library.read_slot(slot_ids[0]).ok and library.list_saves().size() == 5, "Escape from confirmation does not delete a save.")
	if not app.overlay_open:
		await press("☰")
		await press("Load a saved life")
		await _select_slot(slot_ids[0])
	else:
		await press("Keep save")
	await press("Delete save…")
	var identity_before: String = str(app.household.selected_id())
	var profile_before: Dictionary = app.sim.character.duplicate(true)
	var remaining_before: Dictionary = library.read_slot(slot_ids[4]).data.duplicate(true)
	await press("Delete permanently")
	check(not library.read_slot(slot_ids[0]).ok and library.list_saves().size() == 4, "Explicit deletion removes exactly the selected long-title save.")
	check(equivalent(library.read_slot(slot_ids[4]).data, remaining_before), "Deleting another save preserves the active saved household state.")
	check(str(app.household.selected_id()) == identity_before and equivalent(app.sim.character, profile_before) and app.household.members.size() == 8, "Deletion keeps the currently playing eight-Lifelet household intact.")
	await screenshot("05_after_exact_deletion")
	await press("Close")
	# A corrupt local fixture checks the public recovery UI, not filesystem trust.
	var bad_file := FileAccess.open(library.SAVE_DIR.path_join("unreadable_fixture.json"), FileAccess.WRITE)
	bad_file.store_string("{broken test fixture");bad_file.close()
	await press("☰")
	await press("Load a saved life")
	await _select_slot("unreadable_fixture")
	var can_load: bool = is_instance_valid(button_matching("Load selected life", true))
	check(not can_load, "Unreadable save cannot be loaded through the picker.")
	await screenshot("06_unreadable_save_recovery")
	await press("Delete save…")
	await press("Delete permanently")
	check(not FileAccess.file_exists(library.SAVE_DIR.path_join("unreadable_fixture.json")) and library.list_saves().size() == 4, "Confirmed cleanup removes only the unreadable fixture.")
	_write_report()
	app.queue_free()
	await frames(3)
	print("MENU_EDGES_RESULT assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _select_slot(id: String) -> void:
	var found: Button
	for node: Node in app.find_children("*", "Button", true, false):
		if str(node.get_meta("save_id", "")) == id and node.is_visible_in_tree():found = node
	check(is_instance_valid(found), "Selectable save row: " + id)
	if not is_instance_valid(found):return
	for node: Node in app.overlay.find_children("*", "ScrollContainer", true, false):
		if node.is_ancestor_of(found):node.ensure_control_visible(found)
	await frames(2)
	found.pressed.emit()
	await frames(4)
	for node: Node in app.find_children("*", "Button", true, false):
		if str(node.get_meta("save_id", "")) != id or not node.is_visible_in_tree():continue
		var ancestor: Node = node.get_parent()
		while is_instance_valid(ancestor) and not ancestor is ScrollContainer:ancestor = ancestor.get_parent()
		if ancestor is ScrollContainer:
			check(ancestor.get_global_rect().encloses(node.get_global_rect()), "Rebuilt picker keeps the selected save row in view.")

func _check_long_copy(context: String, prefix: String) -> void:
	var target: Label
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		if str(node.text).begins_with(prefix):target = node
	check(is_instance_valid(target), context + ": household identity is shown.")
	if not is_instance_valid(target):return
	check(target.get_visible_line_count() == target.get_line_count(), context + ": all identity lines fit their visible area.")
	# A bounded, scrollable member list is valid: assess its actually visible area.
	var visible_rect: Rect2 = target.get_global_rect()
	var ancestor: Node = target.get_parent()
	while is_instance_valid(ancestor):
		if ancestor is Control and ancestor.clip_contents:
			visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	var no_overlap: bool = true
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node.is_visible_in_tree():no_overlap = no_overlap and not visible_rect.intersects(node.get_global_rect())
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		if str(node.text).begins_with("This permanently"):
			no_overlap = no_overlap and not visible_rect.intersects(node.get_global_rect())
	check(no_overlap, context + ": identity copy does not overlap actions or deletion warning.")
