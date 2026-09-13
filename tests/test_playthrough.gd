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
var member_completed: Array[String] = []
var autonomous_completed: Array[String] = []
var evidence: Array = []
var previous_position: Vector3
var has_previous: bool = false
var max_step: float = 0.0
var motion_excess: float = 0.0
var motion_samples: Array = []
var pointer_observations: Array = []
var observing_motion: bool = false
var screenshot_dir: String = "res://art/playthrough"
var resume_only: bool = false
var track_household_completions: bool = false
var observed_household_ids: Array[int] = []

class MotionObserver extends Node:
	var harness: SceneTree
	func _process(delta: float) -> void:
		harness.observe_motion(delta)

func _initialize() -> void:
	var project_path: String = ProjectSettings.globalize_path("res://")
	if not project_path.trim_suffix("/").get_file().begins_with("justlife-playthrough-") or OS.get_environment("XDG_DATA_HOME")!=project_path.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR") != project_path.path_join("userdata/save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		push_error("Refusing to run outside an isolated playthrough copy with private userdata.")
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
	var motion_observer := MotionObserver.new()
	motion_observer.harness = self
	app.add_child(motion_observer)
	await frames(4)
	track_household_completions = true
	_observe_household_completions()
	app.set_sound(false)
	if resume_only:
		await _resume_verification()
	else:
		await _enter_new_game()
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

func _observe_household_completions() -> void:
	if not track_household_completions:return
	var household: Node = app.get("household")
	if not is_instance_valid(household):return
	var identity: int = household.get_instance_id()
	if identity in observed_household_ids:return
	observed_household_ids.append(identity)
	household.notice.connect(func(message: String) -> void: notices.append(message))
	household.member_action_finished.connect(func(member_id: String, action: Dictionary) -> void:
		completed.append(str(action.id))
		member_completed.append(member_id + ":" + str(action.id))
		if bool(action.get("autonomous", false)):autonomous_completed.append(member_id + ":" + str(action.id)))

func frames(count: int = 2) -> void:
	for i: int in range(count):
		await process_frame

func _enter_new_game() -> void:
	# Older frozen checkpoints opened directly into the creator.
	if app.mode == "menu":
		await press("New game")
		check(app.mode == "creator", "Main menu New game opens household creation.")

func _public_save(title: String) -> void:
	await press("PauseMenu")
	await press("Save this life")
	if is_instance_valid(button_matching("Save as new")):
		var name_field: LineEdit = app.menus.name_input
		name_field.text = title
		name_field.text_changed.emit(title)
		await press("Save as new")
		var library: Script = load("res://scripts/save_library.gd")
		check(not str(app.active_save_id).is_empty() and bool(library.read_slot(app.active_save_id).ok), "Public named-save flow writes a readable household slot.")
		check(app.active_save_name == title, "Saved slot retains its chosen name.")
	else:
		check(FileAccess.file_exists(load("res://scripts/save_library.gd").LEGACY_PATH), "Public save button writes an isolated household file.")

func _public_load() -> void:
	if is_instance_valid(button_matching("Continue your life", true)) and app.mode == "menu":
		await press("Saved lives")
		await press("Load selected life", true)
	elif is_instance_valid(button_matching("Continue saved life")):
		await press("Continue saved life")
	else:
		await press("PauseMenu")
		await press("Load a saved life")
		await press("Load selected life", true)
	if is_instance_valid(button_matching("Continue without saving")):
		await press("Continue without saving")
	# V2 loading atomically installs a new household node. Reconnect only this
	# general-flow observer; inherited specialized harnesses retain their own hooks.
	_observe_household_completions()

func observe_motion(delta: float) -> void:
	if not observing_motion or not is_instance_valid(app.player):
		has_previous = false
		return
	var at: Vector3 = app.player.position
	if has_previous:
		var step: float = at.distance_to(previous_position)
		var elapsed: float = delta
		max_step = maxf(max_step, step)
		# Child processing follows the main controller in the same frame. Use
		# that frame's engine delta, including renderer stalls, at max speed.
		motion_excess = maxf(motion_excess, step - 1.6 * 8.0 * elapsed)
		if step > 0.4:
			motion_samples.append({"step": step, "engine_delta": elapsed, "action": app.sim.get_current_action().duplicate(true)})
	previous_position = at
	has_previous = true

func button_matching(label_text: String, prefix: bool = false) -> Button:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and not node.disabled:
			var matches:bool=str(node.text).begins_with(label_text) if prefix else str(node.text)==label_text
			if matches or (not prefix and str(node.name)==label_text):
				return node
	return null

func press(label_text: String, prefix: bool = false) -> bool:
	var button: Button = button_matching(label_text, prefix)
	check(is_instance_valid(button), "Visible enabled button: " + label_text)
	if not is_instance_valid(button):
		var visible: Array[String] = []
		for node: Node in app.find_children("*", "Button", true, false):
			if node.is_visible_in_tree():visible.append(str(node.text))
		print("MISSING_BUTTON_VISIBLE ", JSON.stringify(visible))
		await screenshot("missing_button_%d" % assertions)
		return false
	# Emits the same signal connected by production UI code; mouse hit-testing is
	# separately exercised for furnishing placement.
	button.pressed.emit()
	await frames(3)
	return true

func press_member(person_name: String) -> bool:
	# The visible initials may change; the full identity tooltip is stable public UI.
	for node: Node in app.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and not node.disabled and str(node.tooltip_text).begins_with(person_name):
			check(true, "Visible household control for " + person_name)
			node.pressed.emit()
			await frames(3)
			return true
	check(false, "Visible household control for " + person_name)
	return false

func wait_until(predicate: Callable, description: String, timeout_seconds: float = 35.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await frames(1)
	check(false, "Timed out: " + description)
	return false

func screenshot(label_text: String, focus: bool = false, pause_for_capture: bool = true) -> void:
	var saved_speed: int = app.sim.speed
	if pause_for_capture:app.sim.set_speed(0)
	var camera_target: Vector3 = app.world.camera_target
	var camera_size: float = app.world.camera.size
	var camera_transform: Transform3D = app.world.camera.transform
	if focus and is_instance_valid(app.player):
		app.world.camera_target = app.player.position + Vector3(0, 0, -0.7)
		app.world.camera.size = 8.5
		app.world.update_camera()
	await frames(3)
	# Allow the periodic HUD refresh to reflect the capture state.
	await create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	var path: String = screenshot_dir.path_join(label_text + ".png")
	var error: int = root.get_texture().get_image().save_png(path)
	check(error == OK, "Rendered screenshot " + label_text)
	var state: Dictionary = {"name": label_text, "screenshot": path, "mode": app.mode, "state": app.sim.get_state()}
	if app.mode == "creator":
		state["creator_profile"] = app.profile.duplicate(true)
		state["creator_household"] = app.household_profiles.duplicate(true)
	if is_instance_valid(app.player):
		state["player_position"] = vec(app.player.position)
	evidence.append(state)
	app.world.camera_target = camera_target
	app.world.camera.size = camera_size
	# Creator tabs place the camera directly; the live orbit helper would destroy
	# their framing even when this capture did not request a focus change.
	app.world.camera.transform = camera_transform
	if pause_for_capture:app.sim.set_speed(saved_speed)

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
	var opened:bool=await press(str(definition.label), true)
	if opened and action_id=="cook":return await press("Cook garden skillet")
	return opened

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
	await press("Male")
	await press("Curls")
	await press("Creative")
	await press("Bookworm")
	if app.preview.has_method("set_face_feature"):
		await _creator_face([0.85, 0.65, 0.80, 0.90], true, "Rowan")
	await press("Wardrobe")
	if is_instance_valid(button_matching("Jacket")):await press("Jacket")
	await press("Coastal")
	var aspiration: OptionButton
	var aspiration_controls: int = 0
	for node: Node in app.find_children("*", "OptionButton", true, false):
		if not node.is_visible_in_tree():continue
		var labels: Array[String] = []
		for index: int in node.item_count:labels.append(node.get_item_text(index))
		if labels == ["Maker", "Connected", "Successful", "Balanced"]:
			aspiration = node;aspiration_controls += 1
	check(aspiration_controls == 1 and is_instance_valid(aspiration), "Creator exposes one semantic aspiration control distinct from age.")
	if is_instance_valid(aspiration):
		for index: int in aspiration.item_count:
			if aspiration.get_item_text(index) == "Connected":
				aspiration.select(index)
				aspiration.item_selected.emit(index)
				break
	await frames(3)
	check(app.profile.name == "Rowan Playtest" and app.profile.frame == 1 and app.profile.hair == 2, "Name/body/hair button choices update profile.")
	check(app.profile.traits.has("Bookworm") and not app.profile.traits.has("Creative"), "Personality buttons change selected traits.")
	check(app.profile.aspiration == "Connected" and app.profile.top_color == "efeadb", "Aspiration and wardrobe signals update profile.")
	await screenshot("01_creator_changed")
	if is_instance_valid(app.get("household")):
		await press("+ Add Lifelet")
		var second_name: LineEdit = app.find_children("*", "LineEdit", true, false)[0]
		second_name.text = "Ellis Playtest"
		second_name.text_changed.emit(second_name.text)
		await press("Look")
		await press("Female")
		await press("Bob")
		if app.preview.has_method("set_face_feature"):
			await _creator_face([0.15, 0.10, 0.25, 0.20], false, "Ellis")
		await press("Wardrobe")
		if is_instance_valid(button_matching("Cardigan")):await press("Cardigan")
		await press("Earthy")
		check(app.household_profiles.size() == 2 and app.profile.name == "Ellis Playtest" and app.profile.hair == 1 and app.profile.frame == 0, "Second Lifelet has a distinct name/body/hair profile.")
		await screenshot("01b_second_lifelet")
		await press_member("Rowan Playtest")
		check(app.profile.name == "Rowan Playtest" and app.profile.hair == 2 and app.profile.top_color == "efeadb", "Creator household chip restores the first distinct profile.")
	await press("Find my home", true)
	check(app.mode == "lots", "Creator continues into home selection.")
	await press("Sage House")
	check(app.selected_lot == 1, "Second home selection persists.")
	await screenshot("02_home_choice")
	await press("Start living", true)
	check(app.mode == "live", "Move-in enters live mode.")
	app.sim.autonomy = false
	if is_instance_valid(app.get("household")):
		for member: Dictionary in app.household.members:member.sim.autonomy = false
		check(app.household.members.size() == 2, "Two created Lifelets move into the same household.")
	app.sim.set_speed(0)
	check(app.sim.character.name == "Rowan Playtest" and app.sim.character.hair == 2 and app.sim.character.aspiration == "Connected", "Created identity persists into live simulation.")
	_check_live_outfits("move-in")
	await screenshot("03_home_live")

func _check_live_outfits(context: String) -> void:
	var diagnostics: Array = []
	for member: Dictionary in app.household.members:
		var actor: Node3D = app.world.actors[member.id]
		var choice: int = int(member.sim.character.get("outfit", 0))
		var expected_prefix: String = ["Outfit_Casual", "Outfit_Jacket", "Outfit_Cardigan"][choice]
		var selected_visible: int = 0
		var unexpected_visible: Array[String] = []
		var meshes: Array = []
		for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
			if not str(node.name).begins_with("Outfit_"):continue
			meshes.append({"path":str(actor.get_path_to(node)),"visible":node.visible,"visible_in_tree":node.is_visible_in_tree()})
			if node.is_visible_in_tree():
				if str(node.name).begins_with(expected_prefix):selected_visible += 1
				else:unexpected_visible.append(str(node.name))
		var identity_counts: Dictionary = {}
		for key: String in actor.get("_identity_shapes"):identity_counts[key] = actor.get("_identity_shapes")[key].size()
		diagnostics.append({"member":member.id,"outfit":choice,"model_scene":actor.get("_model").scene_file_path,"identity_shape_counts":identity_counts,"actor_profile":actor.profile.duplicate(true),"selected_visible_meshes":selected_visible,"unexpected_visible_meshes":unexpected_visible,"meshes":meshes})
		check(selected_visible > 0 and unexpected_visible.is_empty(), context + ": only selected outfit geometry is visible for " + str(member.sim.character.name))
	var file := FileAccess.open(screenshot_dir.path_join(context.replace(" ", "_") + "_outfit_diagnostics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(diagnostics, "  "));file.close()

func _creator_face(values: Array, exercise_reset: bool, person: String) -> void:
	await press("Face")
	var labels: Array[String] = ["Cheek fullness", "Jaw definition", "Nose width", "Eye spacing"]
	var keys: Array[String] = ["face_round", "jaw_strong", "nose_wide", "eye_spacing"]
	if exercise_reset:
		for label_text: String in labels:
			for node: Node in app.find_children("*", "HSlider", true, false):
				if node.tooltip_text == label_text:node.value = 1.0
		await frames(3)
		await screenshot("00_face_all_maximum")
		await press("Reset face")
		var reset: bool = true
		for key: String in keys:reset = reset and is_zero_approx(float(app.profile.get(key, -1)))
		check(reset, "Reset face restores all four identity features to neutral.")
		await screenshot("00_face_reset")
	for i: int in range(keys.size()):
		var found: HSlider
		for node: Node in app.find_children("*", "HSlider", true, false):
			if node.tooltip_text == labels[i]:found = node
		check(is_instance_valid(found), "Visible face slider: " + labels[i])
		if not is_instance_valid(found):continue
		found.value = float(values[i])
		await frames(2)
		check(is_equal_approx(float(app.profile.get(keys[i], -1)), float(values[i])), person + ": face slider changes the character profile: " + keys[i])
		var entries: Array = app.preview.get("_identity_shapes").get(keys[i], [])
		var applied: bool = not entries.is_empty()
		for entry: Dictionary in entries:
			applied = applied and is_equal_approx(entry.mesh.get_blend_shape_value(entry.index), float(values[i]))
		check(applied, person + ": imported preview geometry receives the chosen face deformation: " + keys[i])
	await screenshot("00_face_custom_" + person.to_lower())

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
	await press(app.sim.get_action_definition("friendly").label)
	check(app.sim.action_queue.size() == 3, "Three UI-selected actions remain queued.")
	if is_instance_valid(app.get("household")):
		observing_motion = false
		var first_sim: Node = app.sim
		var first_route: PackedVector3Array = app.path.duplicate()
		await press_member("Ellis Playtest")
		check(app.sim != first_sim and app.sim.character.name == "Ellis Playtest", "Household chip switches controlled Lifelet.")
		await queue_via_menu("bookshelf", "read")
		check(first_sim.action_queue.size() == 3 and app.sim.action_queue.size() == 1, "Two Lifelets keep separate pending action queues.")
		await press_member("Rowan Playtest")
		check(app.sim == first_sim and app.path == first_route, "Switching back preserves the first Lifelet's route and queue.")
		has_previous = false
		observing_motion = true
	await frames(15)
	check(app.player.position.distance_to(before_position) < 0.001 and app.sim.minutes == before_minutes and app.sim.needs == before_needs, "Paused queue does not move actor, advance clock, or change needs.")
	check(app.sim.funds == before_funds, "Ingredients are not charged during paused approach.")
	await screenshot("04_three_action_queue")
	await press("▶▶▶")
	check(app.sim.speed == 8, "Fastest HUD speed selects simulation rate 8.")
	if await wait_until(func() -> bool: return active_is("cook", 0.08), "walk to stove and actively cook"):
		check(app.player.position.distance_to(before_position) > 0.5, "Cooking begins after real routed movement.")
		check(app.sim.funds == before_funds - 12, "Cooking charges ingredients exactly when activity starts.")
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
	if is_instance_valid(app.get("household")):
		check(member_completed.has("player:cook") and member_completed.has("housemate_1:read"), "Two Lifelets finish separate activities through concurrent real processing.")
		var other: Node = app.household.member_sim("housemate_1")
		check(float(other.skills.logic.xp) > 0 and float(app.sim.skills.logic.xp) == 0, "Reading skill gains stay with the Lifelet who read.")
		check(app.sim.funds == other.funds and app.household.funds == app.sim.funds, "Both Lifelets share one consistent household wallet.")
		await press_member("Ellis Playtest")
		await screenshot("08c_second_lifelet_after_reading", true)
		await press_member("Rowan Playtest")

func mouse_move(screen: Vector2) -> void:
	var before: Vector2 = root.get_mouse_position()
	# Coordinate-space trap, measured in tests/probe_pointer_map.gd:
	# `Viewport.get_mouse_position()` and every `unproject_position` call site
	# report CANVAS coordinates under the `canvas_items` stretch mode, while
	# `Input.warp_mouse` takes WINDOW pixels. The two differ by exactly
	# canvas_size / window_size (measured uniform to 1e-6 across four probes),
	# so an unconverted warp lands short by that factor — on the recorded
	# hardware 1.466x, which is the ~450 px miss this harness used to report.
	# The synthetic motion event is fed as if it came from the OS, so it takes
	# the same window-space point.
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	var canvas_size: Vector2 = root.get_visible_rect().size
	var window_point: Vector2 = screen * window_size / canvas_size
	Input.warp_mouse(window_point)
	var event := InputEventMouseMotion.new()
	event.position = window_point
	event.global_position = window_point
	Input.parse_input_event(event)
	await frames(4)
	var actual: Vector2 = root.get_mouse_position()
	var sample: Dictionary = {"ticks_ms":Time.get_ticks_msec(),"requested":[screen.x,screen.y],"window_point":[window_point.x,window_point.y],"before":[before.x,before.y],"actual":[actual.x,actual.y],"distance":actual.distance_to(screen),"window_focused":app.get_window().has_focus(),"window_position":[app.get_window().position.x,app.get_window().position.y],"window_size":[app.get_window().size.x,app.get_window().size.y],"canvas_size":[canvas_size.x,canvas_size.y],"viewport_size":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"ghost_position":vec(app.world.ghost.position) if is_instance_valid(app.world.ghost) else [],"ghost_valid":app.world.ghost_valid,"placement_kind":app.world.placement_kind,"construction_tool":app.world.construction.tool}
	pointer_observations.append(sample)
	print("POINTER_OBSERVATION ",JSON.stringify(sample))
	check(actual.distance_to(screen) < 2.0, "Viewport pointer reaches requested preview coordinates.")

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
	await _construction_flow()
	await press("Live")
	check(app.sim.speed == 0, "Leaving build preserves the prior pause state.")

func _construction_flow() -> void:
	await press("Structure")
	await press("Room")
	var camera_target: Vector3 = app.world.camera_target
	var camera_size: float = app.world.camera.size
	app.world.camera_target = Vector3(-3.5, 0.0, 6.25)
	app.world.camera.size = 8.5
	app.world.update_camera()
	await frames(3)
	var first: Vector3 = Vector3(-4.5, 0.16, 5.5)
	var last: Vector3 = Vector3(-2.5, 0.16, 7.0)
	var funds_before: int = app.sim.funds
	var canonical_before: Dictionary = app.build_transactions.current()
	check(bool(canonical_before.ok), "Current home has valid canonical building geometry before room purchase.")
	if not bool(canonical_before.ok):return
	var walls_before: int = canonical_before.state.walls.size()
	var floors_before: int = canonical_before.state.floors.size()
	await mouse_move(app.world.camera.unproject_position(first))
	await mouse_click(app.world.camera.unproject_position(first))
	check(app.world.construction.anchored, "First room corner sets a mouse-driven anchor.")
	await mouse_move(app.world.camera.unproject_position(last))
	check(app.world.construction.valid, "Detached room has a valid construction preview.")
	await mouse_click(app.world.camera.unproject_position(last))
	var canonical_after: Dictionary = app.build_transactions.current()
	check(bool(canonical_after.ok) and canonical_after.state.walls.size() == walls_before + 4 and canonical_after.state.floors.size() == floors_before + 1, "Second corner adds four room walls and one floor to the canonical home.")
	var existing_preserved: bool = bool(canonical_after.ok)
	if existing_preserved:
		for group: String in ["walls", "floors"]:
			for original: Dictionary in canonical_before.state[group]:
				existing_preserved = existing_preserved and canonical_after.state[group].has(original)
	check(existing_preserved, "Room purchase retains all preexisting canonical walls and starter-floor geometry.")
	check(app.sim.funds == funds_before - 421, "A 2 by 1.5 metre room charges the expected geometry cost.")
	await screenshot("09b_room_constructed")
	await press("Door")
	var doorway: Vector3 = Vector3(-3.5, 0.16, 7.0)
	var before_door: int = app.sim.funds
	await mouse_move(app.world.camera.unproject_position(doorway))
	check(app.world.construction.valid, "An eligible room wall previews a doorway.")
	await mouse_click(app.world.camera.unproject_position(doorway))
	check(app.world.construction.records.size() == walls_before + 5 and app.sim.funds == before_door - 90, "Door replaces its wall with two sides and charges once.")
	await screenshot("09c_door_constructed")
	await press("Room")
	var before_invalid: int = app.sim.funds
	var layout_before: Array = app.world.serialize_items()
	await mouse_move(app.world.camera.unproject_position(first))
	await mouse_click(app.world.camera.unproject_position(first))
	await mouse_move(app.world.camera.unproject_position(last))
	check(not app.world.construction.valid, "A duplicated room previews invalid.")
	await mouse_click(app.world.camera.unproject_position(last))
	check(app.sim.funds == before_invalid and equivalent(app.world.serialize_items(), layout_before), "Invalid construction preserves funds and layout.")
	app.cancel_placement()
	await press("Walnut")
	check(app.floor_color == "896953", "Floor finish selection updates saved floor state.")
	app.world.camera_target = camera_target
	app.world.camera.size = camera_size
	app.world.update_camera()
	await frames(3)

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
	# The persistence checkpoint uses a nonzero-cost action, so restart proves
	# that the ingredient payment is not repeated, rather than testing free sleep.
	await press("Cancel action")
	await press("Cancel action")
	check(app.sim.action_queue.is_empty(), "Cancel sleep and pending reading before the paid persistence checkpoint.")
	await queue_via_menu("stove", "cook")
	await queue_via_menu("bookshelf", "read")
	app.sim.set_speed(8)
	if not await wait_until(func() -> bool: return active_is("cook", 0.16), "walk to the paid cooking checkpoint"):
		return
	app.sim.set_speed(0)
	await screenshot("11b_paid_cooking_before_save", true)
	var expected: Dictionary = {"state": app.sim.get_state(), "player": vec(app.player.position), "world": app.world.serialize_items(), "lot": app.selected_lot, "floor": app.floor_color}
	if is_instance_valid(app.get("household")):
		expected["selected_index"] = app.household.selected_index
		expected["members"] = []
		for member: Dictionary in app.household.members:
			expected.members.append({"id": member.id, "state": member.sim.get_state(), "position": vec(app.world.actors[member.id].position)})
	await _public_save("Rowan and Ellis — home checkpoint")
	var file := FileAccess.open("user://playthrough_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected))
	file.close()
	# Change only state after saving, then exercise public load signal.
	app.sim.funds += 777
	app.sim.character["name"] = "Unsaved change"
	app.sim.cancel_action(1)
	if not app.has_method("show_main_menu"):await press("PauseMenu")
	await _public_load()
	await _compare_saved(expected, "same-process")
	await screenshot("12_loaded_same_process")

func _resume_verification() -> void:
	check(FileAccess.file_exists("user://playthrough_expected.json"), "Expected state exists from the prior process.")
	if not FileAccess.file_exists("user://playthrough_expected.json"):
		return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://playthrough_expected.json"))
	await _public_load()
	await _compare_saved(expected, "fresh-process")
	await screenshot("13_loaded_fresh_process")
	app.sim.set_speed(8)
	var saved_action: Dictionary = expected.state.action_queue[0]
	var resume_progress: float = minf(0.95, float(saved_action.progress) + 0.02)
	await wait_until(func() -> bool: return active_is(str(saved_action.id), resume_progress), "resume the saved paid action after routing")
	check(int(saved_action.cost) > 0 and bool(saved_action.paid), "Persistence checkpoint contains a charged nonzero-cost action.")
	check(app.sim.funds == int(expected.state.funds), "Resuming an already paid activity does not charge it again.")
	await screenshot("14_resumed_paid_activity", true)
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "finish the restored paid action and following reading")
	if is_instance_valid(app.get("household")):
		for member: Dictionary in app.household.members:member.sim.autonomy = true
		var next_day: int = int(expected.state.day) + 1
		await wait_until(func() -> bool: return app.sim.day >= next_day or app.sim.minutes >= 1320, "autonomous household reaches the late evening", 180)
		await screenshot("15_autonomous_evening")
		await wait_until(func() -> bool: return app.sim.day >= next_day and app.sim.minutes >= 480, "autonomous household reaches the following morning", 180)
		check(app.sim.day >= next_day and app.household.day == app.sim.day, "Both simulation and household cross into the next day.")
		var needs_valid: bool = true
		var all_acted: bool = true
		for member: Dictionary in app.household.members:
			var acted: bool = false
			for entry: String in autonomous_completed:
				if entry.begins_with(str(member.id) + ":"):acted = true
			all_acted = all_acted and acted
			for value: Variant in member.sim.needs.values():needs_valid = needs_valid and float(value) >= 0 and float(value) <= 100
		check(needs_valid, "Autonomous day progression keeps all household needs within bounds.")
		check(all_acted, "Both Lifelets finish autonomous activities during the overnight run.")
		await screenshot("16_next_morning")

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
	if expected.has("members"):
		check(app.household.members.size() == expected.members.size() and app.household.selected_index == int(expected.selected_index), label_text + ": household membership and selection restored.")
		for member: Dictionary in expected.members:
			var restored: Node = app.household.member_sim(member.id)
			check(is_instance_valid(restored), label_text + ": member identity restored: " + str(member.id))
			if not is_instance_valid(restored):continue
			var profile_matches: bool = true
			for key: String in ["name", "frame", "hair", "top_color", "bottom_color", "traits", "aspiration", "outfit", "eye_color", "body_scale", "height_scale", "face_round", "jaw_strong", "nose_wide", "eye_spacing"]:
				if member.state.character.has(key):
					profile_matches = profile_matches and restored.character.has(key) and equivalent(restored.character.get(key), member.state.character[key])
			check(profile_matches and equivalent(restored.needs, member.state.needs), label_text + ": member appearance and independent needs restored: " + str(member.id))
			check(equivalent(restored.skills, member.state.skills) and equivalent(restored.relationships, member.state.relationships), label_text + ": member skills and relationships restored: " + str(member.id))
			var position: Array = member.position
			check(app.world.actors[member.id].position.distance_to(Vector3(position[0], position[1], position[2])) < 0.01, label_text + ": member actual position restored: " + str(member.id))

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
	var result: Dictionary = {"assertions": assertions, "failures": failures, "resume_only": resume_only, "completed": completed, "member_completed": member_completed, "autonomous_completed": autonomous_completed, "max_observed_movement_step": max_step, "max_motion_excess": motion_excess, "motion_samples": motion_samples, "pointer_observations": pointer_observations, "notices": notices, "evidence": evidence, "method": "Actual renderer and real frame processing; UI button signals, actual mouse placement; no simulated arrival or direct time advancement."}
	var file := FileAccess.open(screenshot_dir.path_join("resume_results.json" if resume_only else "playthrough_results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
