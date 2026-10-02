extends SceneTree
## A child really goes to their own desk and works at it: they walk to a clear
## spot at arm's length, lean over it, hold a book or a crayon and keep their hands
## on its top, for homework, logic, drawing and colouring alike.
const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

func child_index() -> int:
	for index: int in range(app.household.members.size()):
		if str(app.household.members[index].sim.character.age_stage) == "child": return index
	return -1

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames()
	app.set_process(false); app.household.set_speed(0)
	# A child's desk in open floor of the starter home, with room on every side.
	var spot: Vector3 = Vector3.INF
	var z: float = 3.0
	while z > -3.5 and not spot.is_finite():
		var x: float = -2.0
		while x < 2.5 and not spot.is_finite():
			var at := Vector3(x, .16, z)
			var roomy: bool = app.world.can_place("child_desk", at, 180.0)
			for dx: float in [-1.0, 0.0, 1.0]:
				for dz: float in [-1.0, 0.0, 1.0]:
					roomy = roomy and app.world.lot_navigation.point_clear(0, at + Vector3(dx * .8, 0, dz * .6))
			if roomy: spot = at
			x += .5
		z -= .5
	check(spot.is_finite(), "There is open floor for a child's desk")
	if not spot.is_finite(): quit(1); return
	app.world.add_item({"id": "kids_desk", "kind": "child_desk", "x": spot.x, "z": spot.z, "rotation": 180.0})
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	var desk: Dictionary = app._find_item("kids_desk")
	check(not desk.is_empty(), "The home has a child's desk")
	if desk.is_empty(): quit(1); return
	var kit: int = child_index()
	check(kit >= 0, "The household has a child")
	app.select_household_member(kit)
	await frames()
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		member.sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 80.0
	app.household.minutes = 600.0

	for action_id: String in ["child_draw", "child_colour", "child_desk_study", "homework"]:
		app.sim.action_queue.clear()
		app.queue_interaction(desk, action_id)
		check(not app.sim.get_current_action().is_empty() and str(app.sim.get_current_action().id) == action_id, "%s queues from a click on the desk" % action_id)
		app.household.set_speed(1)
		var active: bool = false
		for frame: int in 3000:
			app._process(DT)
			if str(app.sim.get_current_action().get("phase", "")) == "active" and frame > 5: active = true; break
		check(active, "%s: the child reaches the desk and starts" % action_id)
		if not active: continue
		for frame: int in 20: app._process(DT)
		var body: LifeActor = app.player
		var anchor: Dictionary = body._activity_anchor
		check(str(anchor.get("kind", "")) == "standing" and anchor.has("hand_center"), "%s: the child is anchored at the desk with hands on its top" % action_id)
		var top: Vector3 = anchor.get("hand_center", Vector3.INF)
		var centre: Vector3 = desk.node.global_position
		check(Vector2(body.global_position.x - centre.x, body.global_position.z - centre.z).length() < 1.0, "%s: they stand within arm's length of the desk (%.2f m)" % [action_id, Vector2(body.global_position.x - centre.x, body.global_position.z - centre.z).length()])
		check(absf(top.y - (centre.y + float(desk.height))) < .1, "%s: the hands are at the desk top" % action_id)
		var near: float = INF
		for side: String in ["L", "R"]:
			var palm: Vector3 = body._joints["Forearm_" + side].to_global(body._palm_offset(side))
			near = minf(near, palm.distance_to(top))
		check(near < .35, "%s: a hand is on the desk (%.2f m from its top)" % [action_id, near])
		if action_id == "child_desk_study" or action_id == "homework":
			check(body._book.visible, "%s: they hold a book" % action_id)
		elif action_id in ["child_draw", "child_colour"]:
			check(body._brush.visible, "%s: they hold a crayon" % action_id)
		app.household.set_speed(8)
		var finished: bool = false
		for frame: int in 6000:
			app._process(DT)
			if app.sim.get_current_action().is_empty(): finished = true; break
		app.household.set_speed(0)
		check(finished, "%s runs to the end" % action_id)

	print("CHILD_DESK_ACTOR %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
