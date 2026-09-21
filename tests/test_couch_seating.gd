extends SceneTree
## A couch is shared seating: three Lifelets sit on one three-seater at three
## places, two on a loveseat, and a further Lifelet waits for a free cushion
## instead of stacking on an occupied one. Headless, through the household's own
## selection, interaction queue and resource arbitration.

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _find(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: return item
	return {}


func _queue(item: Dictionary, action_id: String, index: int) -> void:
	app.select_household_member(index)
	app.queue_interaction({"id": str(item.id), "kind": str(item.kind), "node": item.node, "size": item.size}, action_id)


func _seat_of(index: int) -> String:
	return str(app.household.members[index].sim.get_current_action().get("seat_slot", "<none>"))


## A Lifelet really using the place: the household's own begin_action, which is
## what arriving movement calls once the walk finishes.
func _occupy(index: int) -> void:
	app.household.begin_action(str(app.household.members[index].id))


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame; await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	var household = app.household
	while household.members.size() < 4:
		household.add_member({"name": "Extra", "age_stage": "adult", "gender": "Male"})
	for member: Dictionary in household.members:
		member.sim.autonomy = false
		if not app.world.actors.has(str(member.id)):
			app.spawn_actor(str(member.id), member.sim.character.duplicate(true), Vector3(6.5, .16, 6.5))
	for index: int in range(4):
		household.members[index].sim.character.name = "Person%d" % index

	var sofa: Dictionary = _find("sofa")
	check(not sofa.is_empty(), "The starter home has a sofa to share.")
	if sofa.is_empty():
		quit(1); return

	# A loveseat is bought through the ordinary Build & buy placement path. The
	# starter home's living room is furnished, so the first spot that really
	# accepts the placement is used rather than one assumed to be clear.
	app.set_build_mode(true)
	await process_frame
	# The starter home's living room is fully furnished, so the whole lot is
	# scanned for a spot the placement check, the home-layout transaction and the
	# purchase itself all accept.
	var placed_at: Vector3 = Vector3.INF
	var tried: int = 0
	for z: float in [6.4, 5.6, 4.8, -3.0, 3.4, 2.6, 0.4, -2.2, -4.6]:
		for x: float in [0.6, 2.6, -0.6, 3.4, -2.6, 1.6, -1.6, 4.2, -4.2, 5.0, -5.0]:
			var at := Vector3(x, 0.16, z)
			if not app.world.can_place("loveseat", at, 180.0): continue
			tried += 1
			app.on_placement("loveseat", at, 180.0)
			await process_frame
			if not _find("loveseat").is_empty():
				placed_at = at
				break
		if placed_at.is_finite(): break
	await process_frame
	app.set_build_mode(false)
	await process_frame
	var loveseat: Dictionary = _find("loveseat")
	check(not loveseat.is_empty(), "A loveseat is bought through the public purchase path at %s (%d clear spots tried)." % [str(placed_at), tried])

	check(app.world.seat_capacity(sofa) == 3, "A three-seater really holds three places (%d)." % app.world.seat_capacity(sofa))
	if not loveseat.is_empty():
		check(app.world.seat_capacity(loveseat) == 2, "A loveseat really holds two places (%d)." % app.world.seat_capacity(loveseat))

	# Three housemates take the three sofa places at three distinct positions.
	var seen: Array = []
	for index: int in range(3):
		_queue(sofa, "relax", index)
		for i: int in range(10): await process_frame
		var action: Dictionary = household.members[index].sim.get_current_action()
		check(not action.is_empty() and str(action.get("target_id", "")) == str(sofa.id),
			"Person%d queues a seat on the sofa (target %s)." % [index, str(action.get("target_id", "<none>"))])
		var slot: String = str(action.get("seat_slot", ""))
		check(not slot.is_empty(), "Person%d claims a place of their own (%s)." % [index, slot])
		seen.append(slot)
		_occupy(index)
		for i: int in range(3): await process_frame
	check(seen.size() == 3 and seen[0] != seen[1] and seen[1] != seen[2] and seen[0] != seen[2],
		"Three Lifelets hold three different sofa places (%s)." % str(seen))

	# The three seated bodies really occupy three separate points, not one cushion.
	var anchors: Array = []
	for slot: String in seen:
		anchors.append(Vector3(app.world.activity_anchor(sofa, "relax", {"seat_slot": slot}).position))
	var apart: bool = true
	for i: int in anchors.size():
		for j: int in range(i + 1, anchors.size()):
			if (anchors[i] as Vector3).distance_to(anchors[j] as Vector3) < .5: apart = false
	check(anchors.size() == 3 and apart, "They really sit apart rather than stacked on one cushion (%s)." % str(anchors))
	# The places follow the model's own cushions rather than an invented spread.
	check(float((app.world.seat_slot_offset(sofa, "seat_0") as Vector3).x) < -0.4
		and absf(float((app.world.seat_slot_offset(sofa, "seat_1") as Vector3).x)) < 0.01
		and float((app.world.seat_slot_offset(sofa, "seat_2") as Vector3).x) > 0.4,
		"The places sit on the sofa's three authored cushions (%s)." % str(seen.map(func(s: String) -> String: return str(app.world.seat_slot_offset(sofa, s)))))

	# A fourth Lifelet is refused the full couch rather than seated on an edge.
	_queue(sofa, "relax", 3)
	for i: int in range(10): await process_frame
	var fourth: Dictionary = household.members[3].sim.get_current_action()
	check(not fourth.is_empty() and str(fourth.get("target_id", "")) == str(sofa.id),
		"The fourth Lifelet queues for the couch (target %s)." % str(fourth.get("target_id", "<none>")))
	check(str(fourth.get("seat_slot", "")) == "",
		"A full couch hands the fourth no place at all (%s)." % _seat_of(3))
	check(not app._activity_available_for_member(fourth, str(household.members[3].id)),
		"The fourth is refused admission while all three cushions are taken.")
	# Freeing one cushion admits the fourth onto it.
	household.members[0].sim.cancel_action(0)
	for i: int in range(6): await process_frame
	app._resolve_activity_target(fourth)
	check(app._activity_available_for_member(fourth, str(household.members[3].id)),
		"Freeing one cushion admits the waiting Lifelet.")
	check(seen.has(str(fourth.get("seat_slot", ""))),
		"The fourth takes a place of their own (%s)." % str(fourth.get("seat_slot", "")))

	# The loveseat holds exactly two, on its own two authored cushions. Two
	# members who hold no other seat are used, so freeing a sofa place later
	# cannot disturb the loveseat's own two occupants.
	if not loveseat.is_empty():
		household.members[2].sim.cancel_action(0)
		household.members[3].sim.cancel_action(0)
		for i: int in range(4): await process_frame
		var loveseat_seats: Array = []
		for index: int in [2, 3]:
			_queue(loveseat, "relax", index)
			for i: int in range(10): await process_frame
			loveseat_seats.append(_seat_of(index))
			_occupy(index)
			for i: int in range(3): await process_frame
		check(loveseat_seats[0] != loveseat_seats[1] and loveseat_seats[0] != "" and loveseat_seats[1] != "",
			"Two Lifelets share the loveseat on separate places (%s)." % str(loveseat_seats))
		var loveseat_anchors: Array = []
		for slot: String in loveseat_seats:
			loveseat_anchors.append(Vector3(app.world.activity_anchor(loveseat, "relax", {"seat_slot": slot}).position))
		check(loveseat_anchors.size() == 2 and (loveseat_anchors[0] as Vector3).distance_to(loveseat_anchors[1] as Vector3) > .5,
			"The two loveseat places are separate cushions (%s)." % str(loveseat_anchors))
		# A third Lifelet is refused the full loveseat, using a member who holds
		# no seat of their own so the queue really starts empty.
		household.members[0].sim.cancel_action(0)
		for i: int in range(4): await process_frame
		_queue(loveseat, "relax", 0)
		for i: int in range(10): await process_frame
		var third: Dictionary = household.members[0].sim.get_current_action()
		check(str(third.get("target_id", "")) == str(loveseat.id),
			"A third Lifelet queues at the loveseat (target %s)." % str(third.get("target_id", "<none>")))
		check(str(third.get("seat_slot", "")) == "",
			"A full loveseat hands the third no place at all (%s)." % str(third.get("seat_slot", "<none>")))
		check(not app._activity_available_for_member(third, str(household.members[0].id)),
			"A full loveseat refuses a third person.")

	# The waiter at a full couch must really sit down once a cushion frees. It
	# holds no place of its own while waiting and claims every place so it
	# conflicts, so the admission path has to re-claim a freed cushion for it or
	# it would test against its own claim forever and never sit.
	await _waiter_takes_freed_cushion(sofa)

	app.queue_free()
	await process_frame
	print("COUCH_SEATING %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## One Lifelet waits at the full couch, somebody stands up, and the waiter is
## followed through the ordinary movement loop until it is seated on that cushion.
func _waiter_takes_freed_cushion(sofa: Dictionary) -> void:
	var household = app.household
	for index: int in range(household.members.size()):
		household.members[index].sim.cancel_action(0)
	for i: int in range(6): await process_frame
	var waiter: int = household.members.size() - 1
	# Fill all three places through the public queue and settle each body exactly
	# on its own cushion, so the seats are genuinely held.
	for index: int in range(3): _queue(sofa, "relax", index)
	for i: int in range(12): await process_frame
	for index: int in range(3):
		var action: Dictionary = household.members[index].sim.get_current_action()
		if str(action.get("id", "")) != "relax": continue
		var actor: LifeActor = app.world.actors.get(str(household.members[index].id))
		if is_instance_valid(actor): actor.position = Vector3(action.get("target_position", actor.position))
		app.household.begin_action(str(household.members[index].id))
	for i: int in range(4): await process_frame
	var held: int = 0
	for index: int in range(3):
		var a: Dictionary = household.members[index].sim.get_current_action()
		if str(a.get("id", "")) == "relax" and str(a.get("phase", "")) == "active": held += 1
	check(held == 3, "All three couch places are held before the waiter queues (%d)." % held)

	_queue(sofa, "relax", waiter)
	for i: int in range(10): await process_frame
	var queued: Dictionary = household.members[waiter].sim.get_current_action()
	check(str(queued.get("target_id", "")) == str(sofa.id) and str(queued.get("seat_slot", "")) == "",
		"The waiter queues at the full couch holding no place (target %s, place %s)." % [str(queued.get("target_id", "<none>")), str(queued.get("seat_slot", "<none>"))])

	# Stand the first occupant up, then run the real loop until the waiter sits.
	household.members[0].sim.cancel_action(0)
	household.set_speed(1)
	var seated: Dictionary = {}
	for i: int in range(900):
		await process_frame
		var now: Dictionary = household.members[waiter].sim.get_current_action()
		if str(now.get("id", "")) == "relax" and str(now.get("phase", "")) == "active":
			seated = now
			break
	check(not seated.is_empty(),
		"The waiter is really seated once a cushion frees (phase %s)." % str(household.members[waiter].sim.get_current_action().get("phase", "<none>")))
	if seated.is_empty():
		return
	var slot: String = str(seated.get("seat_slot", ""))
	check(not slot.is_empty() and slot != "seat_1" and slot != "seat_2",
		"The waiter took the cushion that actually freed (%s)." % slot)
	# It stands on that cushion's own place rather than at the couch's centre:
	# compare its horizontal offset from the cushion against the offset the
	# cushion's own anchor defines for a body at the same floor height.
	var waiter_actor: LifeActor = app.world.actors.get(str(household.members[waiter].id))
	if is_instance_valid(waiter_actor):
		var waiter_gap: float = _floor_gap(sofa, slot, waiter_actor)
		var centre_gap: float = _floor_gap(sofa, "seat_1", waiter_actor)
		check(waiter_gap < INF and waiter_gap < centre_gap,
			"The waiter stands on its own cushion rather than the couch's centre (%.2f m from its place vs %.2f m from the middle)." % [waiter_gap, centre_gap])


## How far a seated body is from its cushion's floor point, horizontally.
func _floor_gap(sofa: Dictionary, slot: String, actor: LifeActor) -> float:
	if slot.is_empty() or not is_instance_valid(actor): return INF
	var anchor: Vector3 = Vector3(app.world.activity_anchor(sofa, "relax", {"seat_slot": slot}).position)
	return Vector3(anchor.x, actor.position.y, anchor.z).distance_to(actor.position)
