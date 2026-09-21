extends SceneTree
## The contract the courtesy controls' projection must keep: a save that already
## holds a bed place keeps exactly that place and its endpoint through a refresh,
## while a fixture older than the seat model may be given one exactly once.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_seat_stability.gd

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.household_profiles = [{"name": "Avery Stone", "age_stage": "young_adult", "traits": [], "hair": 0}]
	app.creator_family_links = []
	app.start_household(); await frames(10)
	app.household.set_speed(0)
	app.household.set_funds(900000)
	await frames(2)

	var bed: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "bed": bed = item
	check(not bed.is_empty(), "The starter home has a bed to sleep in.")

	# A queued sleep really holds a place of its own on the bed.
	app.queue_interaction(bed, "sleep")
	await frames(6)
	var action: Dictionary = app.sim.get_current_action()
	check(str(action.get("id", "")) == "sleep", "The bed really queues a sleep (%s)." % str(action.get("id", "")))
	check(action.has("seat_slot") and not str(action.get("seat_slot", "")).is_empty(),
		"A queued bed sleep really holds a place of its own (%s)." % str(action.get("seat_slot", "<none>")))
	var seat: String = str(action.get("seat_slot", ""))
	var target: Vector3 = action.target_position
	check(target.distance_to(bed.node.position) < 2.0,
		"The sleeper's endpoint is really beside the bed, not at its centre (%s)." % str(target))

	# Two refreshes, exactly as the courtesy controls perform them.
	app._refresh_sim_targets(false)
	await frames(3)
	app._refresh_sim_targets(true)
	await frames(3)
	var after: Dictionary = app.sim.get_current_action()
	check(str(after.get("seat_slot", "")) == seat,
		"A refresh keeps the sleeper's own place (%s -> %s)." % [seat, str(after.get("seat_slot", "<none>"))])
	check(Vector3(after.target_position).distance_to(target) < .01,
		"A refresh keeps the sleeper's own endpoint exactly (%s -> %s)." % [str(target), str(after.target_position)])

	# And a second refresh is still exact: the upgrade, if any, is one-time.
	app._refresh_sim_targets(true)
	await frames(3)
	var settled: Dictionary = app.sim.get_current_action()
	check(str(settled.get("seat_slot", "")) == seat and Vector3(settled.target_position).distance_to(target) < .01,
		"Repeated refreshes never move a settled sleeper (%s / %s)." % [str(settled.get("seat_slot", "")), str(settled.target_position)])

	app.queue_free(); await frames(3)
	print("SEAT_STABILITY_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
