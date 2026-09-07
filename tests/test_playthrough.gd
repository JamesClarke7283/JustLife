extends SceneTree
## Independent rendered integration check. Run only in /tmp/justlife-playthrough-*,
## with no addons/autoload and a separate XDG_DATA_HOME; see run_playthrough.py.
## Drives public UI signals and actual app frame processing. Never teleports the
## actor or calls begin_current_action/tick to pretend arrival/completion.
## A second --resume-only invocation verifies persistence across process restart.

var app: Node
var assertions: int = 0
var failures: Array[String] = []
var notices: Array[String] = []
var completed: Array[String] = []
var evidence: Array = []
var previous_position: Vector3
var has_previous: bool = false
var max_step: float = 0.0
var last_motion_usec: int = 0
var motion_excess: float = 0.0
var motion_samples: Array = []
var observing_motion: bool = false
var screenshot_dir: String = "res://art/playthrough"
var resume_only: bool = false

func _initialize() -> void:
	var project_path: String = ProjectSettings.globalize_path("res://")
	if not project_path.begins_with("/tmp/justlife-playthrough-") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		push_error("Refusing to run outside the isolated /tmp playthrough copy.")
		quit(2)
		return
	resume_only = "--resume-only" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(condition: bool, detail: String) -> void:
	assertions += 1
	print("CHECK ", "PASS " if condition else "FAIL ", detail)
	if not condition:
		failures.append(detail)
		push_error(detail)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.sim.notice.connect(func(message: String) -> void: notices.append(message))
	app.sim.action_finished.connect(func(action: Dictionary) -> void: completed.append(str(action.id)))
	app.set_sound(false)
	if resume_only:
		await _resume_verification()
	else:
		await _creator_flow()
		await _queue_and_activity_flow()
		await _full_queue_flow()
		await _build_flow()
		await _seating_and_save_flow()
	_write_report()
	app.queue_free()
	await frames(3)
	print("PLAYTHROUGH_RESULT assertions=%d failures=%d resume=%s" % [assertions, failures.size(), str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func frames(count: int = 2) -> void:
	for i: int in range(count):
		await process_frame
		observe_motion()

func observe_motion() -> void:
	if not observing_motion or not is_instance_valid(app.player):
		has_previous = false
		return
	var at: Vector3 = app.player.position
	var now: int = Time.get_ticks_usec()
	if has_previous and last_motion_usec > 0:
		var step: float = at.distance_to(previous_position)
		var elapsed: float = float(now - last_motion_usec) / 1000000.0
		max_step = maxf(max_step, step)
		# Actual render stalls can span several movement frames. Compare travel
		# against the maximum supported speed, not a fixed metres/frame bound.
		motion_excess = maxf(motion_excess, step - 1.6 * sqrt(8.0) * elapsed)
		if step > 0.4:
			motion_samples.append({"step": step, "wall_seconds": elapsed, "action": app.sim.get_current_action()})
	previous_position = at
	last_motion_usec = now
	has_previous = true

func button_matching(label_text: String, prefix: bool = false) -> Button:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and not node.disabled:
			if str(node.text).begins_with(label_text) if prefix else str(node.text) == label_text:
				return node
	return null

func press(label_text: String, prefix: bool = false) -> bool:
	var button: Button = button_matching(label_text, prefix)
	check(is_instance_valid(button), "Visible enabled button: " + label_text)
	if not is_instance_valid(button):
		return false
	# Emits the same signal connected by production UI code; mouse hit-testing is
	# separately exercised for furnishing placement.
	button.pressed.emit()
	await frames(3)
	return true

func wait_until(predicate: Callable, description: String, timeout_seconds: float = 35.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await frames(1)
	check(false, "Timed out: " + description)
	return false

func screenshot(label_text: String, focus: bool = false) -> void:
	var saved_speed: int = app.sim.speed
	app.sim.set_speed(0)
	var camera_target: Vector3 = app.world.camera_target
	var camera_size: float = app.world.camera.size
	if focus and is_instance_valid(app.player):
		app.world.camera_target = app.player.position + Vector3(0, 0, -0.7)
		app.world.camera.size = 8.5
		app.world.update_camera()
	await frames(3)
	await RenderingServer.frame_post_draw
	var path: String = screenshot_dir.path_join(label_text + ".png")
	var error: int = root.get_texture().get_image().save_png(path)
	check(error == OK, "Rendered screenshot " + label_text)
	var state: Dictionary = {"name": label_text, "screenshot": path, "mode": app.mode, "state": app.sim.get_state()}
	if is_instance_valid(app.player):
		state["player_position"] = vec(app.player.position)
	evidence.append(state)
	app.world.camera_target = camera_target
	app.world.camera.size = camera_size
	app.world.update_camera()
	app.sim.set_speed(saved_speed)

func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func first_item(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind:
			return item
	return {}

func queue_via_menu(kind: String, action_id: String) -> bool:
	var item: Dictionary = first_item(kind)
	check(not item.is_empty(), "Available interactive furnishing: " + kind)
	if item.is_empty():
		return false
	var screen: Vector2 = app.world.camera.unproject_position(item.node.position + Vector3(0, 0.6, 0))
	app.world.object_clicked.emit(item, screen)
	await frames(2)
	var definition: Dictionary = app.sim.get_action_definition(action_id)
	return await press(str(definition.label), true)

func active_is(action_id: String, minimum_progress: float = 0.0) -> bool:
	var action: Dictionary = app.sim.get_current_action()
	return not action.is_empty() and str(action.id) == action_id and str(action.phase) == "active" and float(action.progress) >= minimum_progress

func _creator_flow() -> void:
	check(app.mode == "creator", "New process opens character creator.")
	var edits: Array[Node] = app.find_children("*", "LineEdit", true, false)
	check(not edits.is_empty(), "Creator exposes a name field.")
	if not edits.is_empty():
		var edit: LineEdit = edits[0]
		edit.text = "Rowan Playtest"
		edit.text_changed.emit(edit.text)
	await press("Broad")
	await press("Curls")
	await press("Creative")
	await press("Bookworm")
	await press("Wardrobe")
	await press("Coastal")
	var aspirations: Array[Node] = app.find_children("*", "OptionButton", true, false)
	check(not aspirations.is_empty(), "Creator exposes aspiration selection.")
	if not aspirations.is_empty():
		var choice: OptionButton = aspirations[0]
		choice.select(1)
		choice.item_selected.emit(1)
	await frames(3)
	check(app.profile.name == "Rowan Playtest" and app.profile.frame == 1 and app.profile.hair == 2, "Name/body/hair button choices update profile.")
	check(app.profile.traits.has("Bookworm") and not app.profile.traits.has("Creative"), "Personality buttons change selected traits.")
	check(app.profile.aspiration == "Connected" and app.profile.top_color == "efeadb", "Aspiration and wardrobe signals update profile.")
	await screenshot("01_creator_changed")
	await press("Find my home", true)
	check(app.mode == "lots", "Creator continues into home selection.")
	await press("Sage House")
	check(app.selected_lot == 1, "Second home selection persists.")
	await screenshot("02_home_choice")
	await press("Start living", true)
	check(app.mode == "live", "Move-in enters live mode.")
	app.sim.autonomy = false
	app.sim.set_speed(0)
	check(app.sim.character.name == "Rowan Playtest" and app.sim.character.hair == 2 and app.sim.character.aspiration == "Connected", "Created identity persists into live simulation.")
	await screenshot("03_home_live")

func _queue_and_activity_flow() -> void:
	observing_motion = true
	previous_position = app.player.position
	has_previous = true
	var before_position: Vector3 = app.player.position
	var before_minutes: float = app.sim.minutes
	var before_needs: Dictionary = app.sim.needs.duplicate(true)
	var before_funds: int = app.sim.funds
	await queue_via_menu("stove", "cook")
	await queue_via_menu("shower", "shower")
	await press("People")
	await press("Maya Chen")
	await press("Friendly introduction")
	check(app.sim.action_queue.size() == 3, "Three UI-selected actions remain queued.")
	await frames(15)
	check(app.player.position.distance_to(before_position) < 0.001 and app.sim.minutes == before_minutes and app.sim.needs == before_needs, "Paused queue does not move actor, advance clock, or change needs.")
	check(app.sim.funds == before_funds, "Ingredients are not charged during paused approach.")
	await screenshot("04_three_action_queue")
	await press("▶▶▶")
	check(app.sim.speed == 8, "Fastest HUD speed selects simulation rate 8.")
	if await wait_until(func() -> bool: return active_is("cook", 0.08), "walk to stove and actively cook"):
		check(app.player.position.distance_to(before_position) > 0.5, "Cooking begins after real routed movement.")
		check(app.sim.funds == before_funds - 25, "Cooking charges ingredients exactly when activity starts.")
		check(float(app.sim.needs.hunger) > float(before_needs.hunger) - 20.0, "Cooking starts recovering hunger without instant completion.")
		await screenshot("05_cooking", true)
	if await wait_until(func() -> bool: return active_is("shower", 0.12), "finish meal and walk to shower"):
		check(completed.has("cook"), "Cooking completed before shower activity.")
		await screenshot("06_showering", true)
	if await wait_until(func() -> bool: return active_is("friendly", 0.08), "walk from shower to neighbor"):
		check(completed.has("shower"), "Shower completed before social activity.")
		await screenshot("07_social", true)
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "finish queued social action")
	app.sim.set_speed(0)
	check(completed.has("cook") and completed.has("shower") and completed.has("friendly"), "All queued activities complete through actual processing.")
	check(float(app.sim.needs.hygiene) > float(before_needs.hygiene), "Showering produces a lasting hygiene improvement.")
	check(float(app.sim.relationships.maya.friendship) > 12.0, "Conversation changes the persistent friendship.")
	check(float(app.sim.skills.cooking.xp) > 0.0 or int(app.sim.skills.cooking.level) > 1, "Cooking creates persistent skill progress.")
	check(motion_excess < 0.2, "Observed movement stays within maximum walk speed plus 0.2 m tolerance; excess=" + str(motion_excess))
	await screenshot("08_after_daily_actions")
	await press("Ⅱ")
	var pause_position: Vector3 = app.player.position
	var pause_time: float = app.sim.minutes
	await frames(15)
	check(app.sim.speed == 0 and app.sim.minutes == pause_time and app.player.position.distance_to(pause_position) < 0.001, "Pause button freezes completed action state.")
	observing_motion = false

func mouse_move(screen: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = screen
	event.global_position = screen
	Input.parse_input_event(event)
	await frames(4)

func _full_queue_flow() -> void:
	app.sim.set_speed(0)
	for i: int in range(8):
		app.focus_neighbor("maya")
		await frames(2)
		await press("Have a heartfelt talk")
	check(app.sim.action_queue.size() == 8, "Eight long-label activities can be queued.")
	await screenshot("08b_full_queue")
	var reachable: bool = true
	for node: Node in app.queue_box.get_children():
		if node is Button:
			var bounds: Rect2 = node.get_global_rect()
			var scroll_parent: Node = node.get_parent()
			while scroll_parent != null and not scroll_parent is ScrollContainer:
				scroll_parent = scroll_parent.get_parent()
			if scroll_parent == null and (bounds.end.x > 1440 or bounds.position.x < 0):
				reachable = false
	check(reachable, "Every full-queue cancellation remains visible or scrollable.")
	while not app.sim.action_queue.is_empty():
		var buttons: Array[Node] = app.queue_box.get_children()
		if buttons.is_empty():
			check(false, "Queued activity has no visible cancellation control.")
			break
		buttons[buttons.size()-1].pressed.emit()
		await frames(2)
	check(app.sim.action_queue.is_empty(), "Cancel controls remove every queued action without advancing time.")

func mouse_click(screen: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	Input.parse_input_event(event)
	await frames(4)

func _build_flow() -> void:
	await press("Build & buy")
	check(app.mode == "build" and app.sim.speed == 0, "Build mode owns a paused simulation.")
	var funds_before: int = app.sim.funds
	var count_before: int = app.world.items.size()
	# Catalog card buttons use an accessible tooltip rather than text.
	await press("Decor")
	var plant_card: Button
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and str(node.tooltip_text).begins_with("A breath of green"):
			plant_card = node
	check(is_instance_valid(plant_card), "Catalog exposes plant card with price tooltip.")
	if not is_instance_valid(plant_card):
		return
	plant_card.pressed.emit()
	await frames(3)
	check(app.world.placement_kind == "plant", "Catalog card starts a plant preview.")
	var free_position: Vector3 = Vector3.ZERO
	var free_found: bool = false
	for x: float in [-4.5, -3.0, -1.5, 0.0, 2.0, 4.0]:
		for z: float in [-3.0, -1.5, 0.0, 1.5, 3.0]:
			var candidate: Vector3 = Vector3(x, 0.16, z)
			var screen: Vector2 = app.world.camera.unproject_position(candidate)
			if app.world.can_place("plant", candidate, 0) and screen.y > 230 and screen.y < 590 and screen.x > 310 and screen.x < 1250:
				free_position = candidate
				free_found = true
				break
		if free_found:
			break
	check(free_found, "Find a valid visible plant location using placement rules.")
	if free_found:
		var screen: Vector2 = app.world.camera.unproject_position(free_position)
		await mouse_move(screen)
		check(app.world.ghost_valid, "Mouse-driven ghost recognizes valid placement.")
		await mouse_click(screen)
		check(app.world.items.size() == count_before + 1 and app.sim.funds == funds_before - 45, "Valid mouse placement adds exactly one item and charges its price.")
		await screenshot("09_furnishing_placed")
		var funds_placed: int = app.sim.funds
		var count_placed: int = app.world.items.size()
		await mouse_move(screen)
		check(not app.world.ghost_valid, "Preview rejects placing another solid item in same footprint.")
		await mouse_click(screen)
		check(app.world.items.size() == count_placed and app.sim.funds == funds_placed, "Invalid placement changes neither money nor layout.")
	app.cancel_placement()
	await press("Live")
	check(app.sim.speed == 0, "Leaving build preserves the prior pause state.")

func _seating_and_save_flow() -> void:
	await queue_via_menu("sofa", "relax")
	app.sim.set_speed(8)
	if await wait_until(func() -> bool: return active_is("relax", 0.15), "route to sofa and relax"):
		await screenshot("10_seated_relax", true)
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "finish sofa activity")
	app.sim.set_speed(0)
	await queue_via_menu("bed", "sleep")
	await queue_via_menu("bookshelf", "read")
	app.sim.set_speed(8)
	if not await wait_until(func() -> bool: return active_is("sleep", 0.12), "route to bed and sleep"):
		return
	app.sim.set_speed(0)
	await screenshot("11_sleeping_before_save", true)
	var expected: Dictionary = {"state": app.sim.get_state(), "player": vec(app.player.position), "world": app.world.serialize_items(), "lot": app.selected_lot, "floor": app.floor_color}
	await press("☰")
	await press("Save this life")
	check(FileAccess.file_exists("user://justlife_save.json"), "Public save button writes an isolated household file.")
	var file := FileAccess.open("user://playthrough_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected))
	file.close()
	# Change only state after saving, then exercise public load signal.
	app.sim.funds += 777
	app.sim.character["name"] = "Unsaved change"
	app.sim.cancel_action(1)
	await press("☰")
	await press("Continue saved life")
	await _compare_saved(expected, "same-process")
	await screenshot("12_loaded_same_process")

func _resume_verification() -> void:
	check(FileAccess.file_exists("user://playthrough_expected.json"), "Expected state exists from the prior process.")
	if not FileAccess.file_exists("user://playthrough_expected.json"):
		return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://playthrough_expected.json"))
	await press("Continue saved life")
	await _compare_saved(expected, "fresh-process")
	await screenshot("13_loaded_fresh_process")
	app.sim.set_speed(8)
	await wait_until(func() -> bool: return active_is("sleep", 0.13), "resume saved sleep after routing")
	check(app.sim.funds == int(expected.state.funds), "Resuming an already paid activity does not charge it again.")
	await screenshot("14_resumed_sleep", true)

func _compare_saved(expected: Dictionary, label_text: String) -> void:
	var state: Dictionary = expected.state
	check(app.mode == "live" and app.sim.character.name == state.character.name and app.sim.character.hair == state.character.hair and app.sim.character.top_color == state.character.top_color, label_text + ": appearance/name restored.")
	check(app.sim.funds == int(state.funds) and app.sim.day == int(state.day) and absf(app.sim.minutes - float(state.minutes)) < 0.001, label_text + ": funds/day/time restored.")
	var needs_equal: bool = true
	for key: String in state.needs:
		needs_equal = needs_equal and absf(float(app.sim.needs[key]) - float(state.needs[key])) < 0.001
	check(needs_equal, label_text + ": all six need values restored.")
	var at: Array = expected.player
	check(app.player.position.distance_to(Vector3(at[0], at[1], at[2])) < 0.01, label_text + ": actual actor location restored.")
	check(app.selected_lot == int(expected.lot) and app.floor_color == expected.floor, label_text + ": lot and floor restored.")
	var world_match: bool = equivalent(app.world.serialize_items(), expected.world)
	check(world_match, label_text + ": furniture identities/positions and construction restored.")
	check(app.sim.action_queue.size() == state.action_queue.size(), label_text + ": queue length restored.")
	if app.sim.action_queue.size() == state.action_queue.size():
		for i: int in range(state.action_queue.size()):
			var actual: Dictionary = app.sim.action_queue[i]
			var stored: Dictionary = state.action_queue[i]
			check(actual.id == stored.id and actual.target_id == stored.target_id and absf(float(actual.elapsed) - float(stored.elapsed)) < 0.001 and actual.paid == stored.paid, label_text + ": queued activity %d identity/progress/payment restored." % i)
	check(app.sim.speed == 0, label_text + ": saved pause remains paused.")

func equivalent(actual: Variant, expected: Variant) -> bool:
	# JSON round-trips numbers as floats; compare numeric values, not formatting.
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size():
			return false
		for key: Variant in expected:
			if not actual.has(key) or not equivalent(actual[key], expected[key]):
				return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			return false
		for i: int in range(expected.size()):
			if not equivalent(actual[i], expected[i]):
				return false
		return true
	if (actual is float or actual is int) and (expected is float or expected is int):
		return absf(float(actual) - float(expected)) < 0.001
	return actual == expected

func _write_report() -> void:
	var result: Dictionary = {"assertions": assertions, "failures": failures, "resume_only": resume_only, "completed": completed, "max_observed_movement_step": max_step, "max_motion_excess": motion_excess, "motion_samples": motion_samples, "notices": notices, "evidence": evidence, "method": "Actual renderer and real frame processing; UI button signals, actual mouse placement; no simulated arrival or direct time advancement."}
	var file := FileAccess.open(screenshot_dir.path_join("resume_results.json" if resume_only else "playthrough_results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
