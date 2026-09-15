extends SceneTree
## Click a household member the way the player does — a real mouse press on the
## actor's own collider — and prove the interaction panel is populated.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_housemate_panel.gd

var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

## The world reports no screen position for a synthetic click, so the actor is
## projected through the live camera exactly as the pointer ray would be.
func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	app._begin_new_game()
	app.add_creator_member()
	await frames(4)
	app.start_household()
	await frames(14)
	app.household.set_speed(0)
	check(app.household.members.size() > 1, "The household has more than one member")

	var selected: String = str(app.household.selected_id())
	var other: String = ""
	for member: Dictionary in app.household.members:
		if str(member.id) != selected:
			other = str(member.id)
			break
	check(not other.is_empty(), "A non-selected housemate exists")

	var actor: Node3D = app.world.actors[other]
	var camera: Camera3D = app.world.camera
	var point: Vector2 = camera.unproject_position(actor.position + Vector3(0, 1.0, 0))
	print("click point for ", other, " = ", point)

	# Dispatch a genuine left click through the viewport so the world's own
	# ray-cast decides, rather than calling the handler directly.
	var vp: Viewport = app.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point; motion.relative = Vector2(1, 1)
	vp.push_input(motion, true)
	await frames(2)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = point
		click.global_position = point
		vp.push_input(click, true)
		await frames(2)
	await frames(4)

	check(app.overlay_open, "The click opened an overlay panel")
	# Count the drawn content inside the overlay: a blank card would have none.
	var buttons: int = 0
	var labels: int = 0
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).flat:
			buttons += 1
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		if node is Label and (node as Label).is_visible_in_tree() and not str((node as Label).text).strip_edges().is_empty():
			labels += 1
	print("overlay buttons=", buttons, " labels=", labels)
	# The panel is a title label plus an action list; the section caption and the
	# action rows are drawn as buttons and labels inside a scroll column, so the
	# real signal is a title and a populated action list.
	var titled: bool = labels >= 2
	check(titled, "The panel draws its title and section caption (got %d labels)" % labels)
	check(buttons >= 3, "The panel offers several actions (got %d buttons)" % buttons)
	var action_buttons: int = 0
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).flat and str((node as Button).text).length() > 3:
			action_buttons += 1
	check(action_buttons >= 3, "The panel lists real social actions (got %d)" % action_buttons)

	print("HOUSEMATE_PANEL_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
