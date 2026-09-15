extends SceneTree
## Prove a social action really changes a relationship: run one through the
## interaction panel and read the friendship value before and after.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_social_outcome.gd

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

func button(text: String) -> Button:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).disabled and str((node as Button).text) == text:
			return node
	return null

## Press the named action in the open interaction panel and wait for it to run.
func run_action(label_prefix: String) -> bool:
	var chosen: Button = null
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).disabled and str((node as Button).text).begins_with(label_prefix):
			chosen = node
			break
	if chosen == null: return false
	chosen.pressed.emit()
	await frames(6)
	app.household.set_speed(3)
	var deadline: int = Time.get_ticks_msec() + 150000
	while not app.sim.action_queue.is_empty() and Time.get_ticks_msec() < deadline:
		await frames(10)
	app.household.set_speed(0)
	await frames(6)
	return true

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.add_creator_member()
	await frames(6)
	app.start_household(); await frames(16)
	app.household.set_speed(0)
	check(app.household.members.size() > 1, "The household has a second member to befriend")

	var other_id: String = ""
	for member: Dictionary in app.household.members:
		if str(member.id) != str(app.household.selected_id()):
			other_id = str(member.id)
			break
	check(not other_id.is_empty(), "A housemate to talk to exists")
	var rel: Dictionary = app.sim.relationships.get(other_id, {})
	check(not rel.is_empty(), "The selected Lifelet has a relationship record for the housemate")
	if rel.is_empty(): return

	# A friendly chat must be offered, and must be runnable. Both Lifelets are
	# placed within sight of each other and the panel is opened by a genuine
	# pointer press on the actor, so the world supplies the click payload itself.
	var friendship_before: int = int(rel.friendship)
	var actor: Node3D = app.world.actors[other_id]
	var me: Node3D = app.world.actors[str(app.household.selected_id())]
	me.position = actor.position + Vector3(0.9, 0, 0)
	app.sim.needs["social"] = 40.0
	await frames(8)
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
	await frames(5)
	check(app.overlay_open, "The housemate panel opened from a real click")
	var labels: Array[String] = []
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).disabled:
			labels.append(str((node as Button).text))
	print("social actions offered: ", labels)
	check(labels.size() >= 3, "The housemate offers social actions (%d)" % labels.size())

	var ran: bool = await run_action("Have a friendly chat")
	if not ran:
		ran = await run_action("Chat")
	check(ran, "A friendly chat was queued and completed")

	var friendship_after: int = int(app.sim.relationships[other_id].friendship)
	print("friendship %d -> %d" % [friendship_before, friendship_after])
	check(friendship_after > friendship_before,
		"Completing a friendly chat raised friendship (%d -> %d)" % [friendship_before, friendship_after])
	# And the change must reach the relationship panel the HUD shows.
	app.show_relationships()
	await frames(4)
	var shown: bool = false
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		if node is Label and str((node as Label).text).contains("Friendship %d" % friendship_after):
			shown = true
	check(shown, "The People panel shows the new friendship value (%d)" % friendship_after)
	app.close_overlay()

	print("SOCIAL_OUTCOME_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
