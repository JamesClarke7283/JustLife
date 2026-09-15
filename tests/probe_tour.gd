extends SceneTree
## Rendered tour of every player-facing screen, for independent visual review.
##
##   godot --audio-driver Dummy --path <private project> --script res://tests/probe_tour.gd
##
## Output goes to user://tour. It only opens screens through the game's own
## public callables and Button signals; it never fabricates state for a capture.

const OUT := "user://tour"
var app: Node
var checks: int = 0
var failures: Array[String] = []
var shots: Array[String] = []

## A run that pushes an engine error must not report a clean pass. Godot's own
## logger interface is the only reliable signal, so the harness installs one and
## counts every error it is handed for the whole run.
class ErrorCounter:
	extends Logger
	var errors: int = 0
	func _log_error(function: String, file: String, line: int, code: String, message: String, _rationale: bool, _editor: int, backtrace: Array[ScriptBacktrace]) -> void:
		errors += 1
		print("TOUR_ENGINE_ERROR ", file, ":", line, " ", message, " ", str(backtrace))

var error_counter: ErrorCounter

func _initialize() -> void:
	error_counter = ErrorCounter.new()
	OS.add_logger(error_counter)
	_run.call_deferred()

func _finish() -> void:
	if error_counter.errors > 0:
		check(false, "The run logged %d engine error(s)" % error_counter.errors)
	print("TOUR_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "shots": shots, "engine_errors": error_counter.errors}))
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures.append(why)
		push_error(why)

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func shot(label: String) -> void:
	for index: int in 3: await process_frame
	await RenderingServer.frame_post_draw
	var file: String = OUT.path_join(label + ".png")
	var error: Error = root.get_texture().get_image().save_png(file)
	check(error == OK, "Captured " + label)
	shots.append(label)
	print("TOUR_SHOT ", ProjectSettings.globalize_path(file))

func press(label_text: String) -> bool:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.text) == label_text:
			node.pressed.emit()
			await frames(2)
			return true
	return false

func has_button(label_text: String) -> bool:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.text) == label_text:
			return true
	return false

func visible_buttons() -> Array[String]:
	var out: Array[String] = []
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and not node.disabled:
			out.append(str(node.text))
	return out

func furnishing_of(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.get("kind", "")) == kind:
			return item
	return {}

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(6)
	app.set_sound(false)

	# --- Main menu and the save library -------------------------------------
	await shot("01_main_menu")
	await press("Saved lives")
	await shot("02_save_picker")

	# --- Character creation: every tab ---------------------------------------
	await press("Close")
	await press("New game")
	check(app.mode == "creator", "New game opens the creator")
	await shot("03_creator_look")
	var tabs: Array[String] = ["Face", "Wardrobe", "Look"]
	for tab: String in tabs:
		await press(tab)
		await shot("04_creator_" + tab.to_lower())

	# A second Lifelet, so Connections and the household strip are real.
	await press("+ Add Lifelet")
	await frames(2)
	await shot("05_creator_two_members")
	await press("Connections")
	await shot("06_creator_connections")
	await press("Back to creating")
	await press("Surprise me")
	await frames(2)
	await shot("07_creator_surprised")

	# --- Choosing a home -----------------------------------------------------
	await press("Find my home  →")
	check(app.mode == "lots", "Creator leads to choosing a home")
	await shot("08_lot_selection")

	# --- Live ----------------------------------------------------------------
	await press("Start living  →")
	check(app.mode == "live", "Household starts living")
	app.household.set_speed(0)
	await frames(8)
	await shot("09_live_hud")
	app.world.camera.size = 9.0
	app.world.update_camera()
	await shot("10_live_close")
	app.world.camera.size = 24.0
	app.world.camera_angle = 2.4
	app.world.update_camera()
	await shot("11_live_wide")
	app.world.camera.size = 16.0
	app.world.camera_angle = .62
	app.world.update_camera()

	# Object and housemate interaction menus. The housemate panel is opened by a
	# genuine pointer press on the actor, because a synthetic dictionary would
	# not exercise the world's own ray-cast or the label it supplies.
	var sofa: Dictionary = furnishing_of("sofa")
	if sofa.is_empty(): sofa = app.world.items[0] if not app.world.items.is_empty() else {}
	if not sofa.is_empty():
		app.on_object_clicked(sofa, Vector2(700, 450))
		await shot("12_object_interactions")
		app.close_overlay()
	if app.household.members.size() > 1:
		var other: String = ""
		for member: Dictionary in app.household.members:
			if str(member.id) != str(app.household.selected_id()):
				other = str(member.id)
				break
		check(not other.is_empty(), "A non-selected housemate exists to click")
		if not other.is_empty():
			var actor: Node3D = app.world.actors[other]
			var point: Vector2 = app.world.camera.unproject_position(actor.position + Vector3(0, 1.0, 0))
			var vp: Viewport = app.get_viewport()
			var motion := InputEventMouseMotion.new()
			motion.position = point; motion.global_position = point; motion.relative = Vector2(1, 1)
			vp.push_input(motion, true)
			await frames(2)
			for pressed: bool in [true, false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				click.position = point; click.global_position = point
				vp.push_input(click, true)
				await frames(2)
			await frames(4)
			check(app.overlay_open, "Clicking a housemate opens their interaction panel")
			var drawn: int = 0
			for node: Node in app.overlay.find_children("*", "Button", true, false):
				if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).flat:
					drawn += 1
			check(drawn >= 1, "The housemate panel offers at least one action (got %d)" % drawn)
			await shot("13_housemate_interactions")
			app.close_overlay()

	# --- The HUD's own panels ------------------------------------------------
	for panel: Dictionary in [
		{"label": "My Lifelet", "shot": "14_person"},
		{"label": "Stories", "shot": "15_stories"},
		{"label": "Explore", "shot": "16_explore"},
	]:
		if await press(str(panel["label"])):
			await shot(str(panel["shot"]))
			app.close_overlay()

	# The household strip opens a member's card; the skills/career panel is part
	# of the live HUD rather than an overlay.
	app.panel_tab = "People"
	app.draw_live()
	await frames(2)
	await shot("17_hud_people_tab")
	if await press("All relationships →"):
		await shot("17b_relationships")
		app.close_overlay()

	for opener: Dictionary in [
		{"call": func(): app.show_careers(), "shot": "18_careers"},
		{"call": func(): app.show_wishes(), "shot": "19_wishes"},
		{"call": func(): app.show_rewards(), "shot": "20_rewards"},
		{"call": func(): app.show_family_tree(), "shot": "21_family_tree"},
		{"call": func(): app.show_school_record(), "shot": "22_school_record"},
		{"call": func(): app.show_career_record(), "shot": "23_career_record"},
		{"call": func(): app.show_life_settings(), "shot": "24_life_settings"},
		{"call": func(): app.show_menu(), "shot": "25_pause_menu"},
		{"call": func(): app.show_help(), "shot": "26_help"},
	]:
		opener["call"].call()
		await shot(str(opener["shot"]))
		app.close_overlay()

	# --- Phone, calendar, adoption and the pet shop ---------------------------
	app.adoption_flow.show_phone()
	await shot("27_phone")
	app.adoption_flow.calendar.show_calendar()
	await shot("28_calendar")
	app.adoption_flow.show_phone()
	await press("Adopt a child")
	await shot("29_adoption_candidates")
	if has_button("Meet " + str(_first_candidate_name())):
		await press("Meet " + str(_first_candidate_name()))
		await shot("30_adoption_review")
	app.adoption_flow.show_phone()
	await press("Juniper Pet Shop")
	await shot("31_pet_shop")
	app.pet_shop.show_species()
	await shot("32_pet_picker")
	app.close_overlay()

	# --- Build and buy, every tool page --------------------------------------
	await press("Build & buy")
	check(app.mode == "build", "Build mode opens")
	await shot("33_build_catalog")
	for category: String in ["Kitchen", "Bathroom", "Activities", "Decor", "Structure"]:
		if await press(category):
			await shot("34_build_" + category.to_lower())
	app.show_storage()
	await shot("35_storage")
	app.close_overlay()
	await press("Live")

	print("TOUR_SHOTS ", JSON.stringify(shots))
	_finish()
	app.queue_free()
	await frames(3)

func _first_candidate_name() -> String:
	var adoption: Script = load("res://scripts/adoption.gd")
	var candidate: Dictionary = adoption.candidate(int(app.household.adoptions.next_serial), 0)
	return str(candidate.name).split(" ")[0]
