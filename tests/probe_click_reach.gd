extends SceneTree
## Confirm that a control the layout oracle flags is genuinely unreachable by a
## real mouse click, using Godot's own input dispatch rather than geometry maths.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_click_reach.gd

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

## Dispatch a real press+release through the viewport's own input pipeline and
## report which probed Control actually received the press signal.
func clicked_control(point: Vector2, probe: Array[Control]) -> Control:
	var vp: Viewport = app.get_viewport()
	var seen: Array[Control] = []
	var hooks: Array[Callable] = []
	for control: Control in probe:
		if control is BaseButton:
			var button: BaseButton = control
			var hook: Callable = func() -> void: seen.append(button)
			hooks.append(hook)
			button.pressed.connect(hook)
		else:
			hooks.append(Callable())
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	down.global_position = point
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = point
	up.global_position = point
	# A motion event first, so hover state and button groups see the pointer.
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = Vector2(1, 1)
	vp.push_input(motion, true)
	await frames(2)
	vp.push_input(down, true)
	await frames(2)
	vp.push_input(up, true)
	await frames(3)
	var winner: Control = seen.front() if not seen.is_empty() else null
	for index: int in probe.size():
		if probe[index] is BaseButton:
			var button: BaseButton = probe[index]
			if not hooks[index].is_null() and button.pressed.is_connected(hooks[index]):
				button.pressed.disconnect(hooks[index])
	return winner

func button_named(text: String) -> Button:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and str(node.text) == text:
			return node
	return null

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)

	# --- Build mode: the Storage button against the catalogue strip ----------
	app.new_game(); await frames(4)
	app.start_household(); await frames(10)
	app.household.set_speed(0)
	app.set_build_mode(true); await frames(4)
	var storage: Button = button_named("Storage")
	check(storage != null, "Storage button exists in Build & buy")
	if storage != null:
		var center: Vector2 = storage.get_global_rect().get_center()
		var candidates: Array[Control] = []
		for node: Node in app.find_children("*", "Control", true, false):
			if node is Control and (node as Control).is_visible_in_tree():
				candidates.append(node)
		var hit: Control = await clicked_control(center, candidates)
		check(hit == storage, "A real click at the Storage button's centre reaches Storage (got %s)" % ("nothing" if hit == null else str(hit)))
		# The click opened the storage overlay; close it before the next probe.
		app.close_overlay()
		await frames(3)
		# The top-right corner is the point closest to the catalogue strip, and is
		# the first place a neighbouring container would swallow the button.
		var corner: Vector2 = Vector2(storage.get_global_rect().end.x - 4.0, storage.get_global_rect().position.y + 4.0)
		var hit_corner: Control = await clicked_control(corner, candidates)
		check(hit_corner == storage, "A real click near the Storage button's catalogue-side edge reaches Storage (got %s)" % ("nothing" if hit_corner == null else str(hit_corner)))
		app.close_overlay()
		await frames(3)
	app.set_build_mode(false); await frames(3)

	# --- Live HUD: Rewards against Cancel action -----------------------------
	var rewards: Button = button_named("Rewards")
	var cancel: Button = button_named("Cancel action")
	check(rewards != null and cancel != null, "Rewards and Cancel action both exist on the live HUD")
	if rewards != null and cancel != null:
		var overlap: Rect2 = rewards.get_global_rect().intersection(cancel.get_global_rect())
		print("GEOMETRY rewards=%s cancel=%s overlap=%s" % [str(rewards.get_global_rect()), str(cancel.get_global_rect()), str(overlap)])
		var candidates: Array[Control] = []
		for node: Node in app.find_children("*", "Control", true, false):
			if node is Control and (node as Control).is_visible_in_tree():
				candidates.append(node)
		var hit: Control = await clicked_control(rewards.get_global_rect().get_center(), candidates)
		check(hit == rewards, "A real click at the Rewards button's centre reaches Rewards (got %s)" % ("nothing" if hit == null else str(hit)))
		app.close_overlay()
		await frames(3)
		var hit_left: Control = await clicked_control(Vector2(rewards.get_global_rect().position.x + 2.0, rewards.get_global_rect().get_center().y), candidates)
		check(hit_left == rewards, "A real click at the Rewards button's left edge reaches Rewards (got %s)" % ("nothing" if hit_left == null else str(hit_left)))
		app.close_overlay()
		await frames(3)
		var hit_right: Control = await clicked_control(Vector2(rewards.get_global_rect().end.x - 2.0, rewards.get_global_rect().get_center().y), candidates)
		check(hit_right == rewards, "A real click at the Rewards button's right edge reaches Rewards (got %s)" % ("nothing" if hit_right == null else str(hit_right)))
		app.close_overlay()
		await frames(3)

	print("CLICK_REACH_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
