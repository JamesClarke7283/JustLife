extends SceneTree
## Queue a real activity list and capture where the chips land, so the action
## queue is visible evidence rather than an empty strip.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_queue_visible.gd

const Building = preload("res://scripts/building_state.gd")
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

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://queue_visible"))
	root.get_texture().get_image().save_png("user://queue_visible/%s.png" % label)
	print("QUEUE_SHOT ", ProjectSettings.globalize_path("user://queue_visible/%s.png" % label))

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(14)
	app.household.set_speed(0)
	await frames(4)

	# Queue several real activities through the same public path the interaction
	# menus use, so the queue holds genuine entries rather than test stubs.
	var queued: Array[String] = []
	for item: Dictionary in app.world.items:
		var kind: String = str(item.get("kind", ""))
		if kind in ["bookshelf", "easel", "sofa", "tv", "stove", "fridge"]:
			var actions: Array = app.sim.get_actions_for(kind, str(item.id))
			for action: Dictionary in actions:
				if not bool(action.get("available", true)): continue
				if str(action.get("id", "")) in ["cook", "paint", "read", "relax", "watch_tv", "snack"]:
					if app.sim.queue_action(str(action.id), str(item.id), Vector3(float(item.x), Building.GROUND_Y, float(item.z))):
						queued.append("%s@%s" % [str(action.id), kind])
					break
			if queued.size() >= 4: break
	print("queued=", queued)
	check(queued.size() >= 2, "Several real activities were queued (%d)" % queued.size())
	check(app.sim.action_queue.size() >= 2, "The simulation holds the queued actions (%d)" % app.sim.action_queue.size())

	app.refresh_hud()
	await frames(6)
	var chips: int = 0
	if is_instance_valid(app.queue_box):
		for node: Node in app.queue_box.get_children():
			if node is Button and (node as Button).is_visible_in_tree(): chips += 1
	print("queue chips drawn=", chips, " box=", app.queue_box.get_global_rect() if is_instance_valid(app.queue_box) else "-")
	check(chips >= 2, "The HUD really draws a chip per queued action (%d)" % chips)
	# Two activities can share a label. Each chip must name its own target so the
	# player can tell which one a click will cancel.
	# Each chip draws its title and a separate cancel mark, so only the titles
	# are long enough to name a target.
	var titles: Array[String] = []
	for node: Node in app.queue_box.get_children():
		if not (node is Button): continue
		for child: Node in (node as Button).get_children():
			if child is Label and str((child as Label).text).length() > 2:
				titles.append(str((child as Label).text))
	print("queue titles=", titles)
	var named: int = 0
	for title: String in titles:
		if title.contains("·"): named += 1
	check(not titles.is_empty() and named == titles.size(), "Every chip names its target (%d/%d)" % [named, titles.size()])
	check(titles.size() == app.sim.action_queue.size(), "One title per queued action (%d/%d)" % [titles.size(), app.sim.action_queue.size()])

	# The chips must sit in a HUD card with its own background, not float as
	# bare text over the middle of the 3D scene.
	check(is_instance_valid(app.queue_card), "The queue has a card")
	if is_instance_valid(app.queue_card) and chips > 0:
		var card_rect: Rect2 = app.queue_card.get_global_rect()
		# The visible strip is the ScrollContainer; the HBox may be wider than it
		# and scroll, which is intended, so the scroll's own rect is what must sit
		# inside the card.
		var strip: Rect2 = app.queue_scroll.get_global_rect()
		print("queue_card=%s queue_strip=%s content=%s" % [str(card_rect), str(strip), str(app.queue_box.get_global_rect())])
		check(card_rect.encloses(strip.grow(2.0)), "The queue strip sits inside its card (%s in %s)" % [str(strip), str(card_rect)])
		check(app.queue_box.size.x > 0.0, "The queue content really has width (%.1f)" % app.queue_box.size.x)
		check(app.queue_card.visible, "The queue card is visible while actions are queued")
		# And the card must not sit on top of the goal card.
		var goal: Rect2 = Rect2(24, 104, 262, 157)
		var overlap: Rect2 = goal.intersection(card_rect)
		check(overlap.size.x <= 0.0 or overlap.size.y <= 0.0, "The queue card does not cover the goal card (overlap %s)" % str(overlap))
	await shot("01_queue_visible")

	# Cancelling a queued chip removes it.
	var before: int = chips
	var button: Button = null
	for node: Node in app.queue_box.get_children():
		if node is Button and (node as Button).is_visible_in_tree(): button = node; break
	if button != null:
		button.pressed.emit()
		await frames(6)
		var after: int = 0
		for node: Node in app.queue_box.get_children():
			if node is Button and (node as Button).is_visible_in_tree(): after += 1
		check(after < before, "Clicking a chip cancels that action (%d -> %d chips)" % [before, after])
		# With nothing queued the card must go away rather than linger empty.
		while app.sim.action_queue.size() > 0:
			app.sim.cancel_action(0)
			await frames(3)
		app.refresh_hud()
		await frames(6)
		check(is_instance_valid(app.queue_card) and not app.queue_card.visible,
			"The queue card hides once nothing is queued")

	print("QUEUE_VISIBLE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
