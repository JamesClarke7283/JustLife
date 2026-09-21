extends SceneTree
## A caller waiting on the doorstep must survive the household's own save.
##
## The doorstep is a Vector3 in memory. `snapshot()` packed the bell's position
## and rotation but not its doorstep, while the save validator demands an Array,
## so the game refused its own save with "Save contains an invalid doorstep
## position" for as long as a neighbour stood at the door. The pack is asserted
## through the production ring, the validator, and a real restore.

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


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame; await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	var visit = app.residents.home_visit
	check(visit != null, "The household owns a home-visit service.")

	# A neighbour really reaches the front path and rings, through the production
	# entry point rather than a hand-built record.
	var maya: LifeActor = app.world.actors.get("maya")
	if is_instance_valid(maya):
		maya.position = Vector3(0, .16, 7.2)
		app.world.set_actor_away("maya", false, false)
		var where: Dictionary = app.residents.locations.get("home", {}).get("maya", {})
		if not where.is_empty(): where.phase = "visiting"
	check(visit.consider_ring(), "A neighbour on the front path rings the doorbell.")
	check(visit.ringing(), "The doorbell really records the caller.")
	check(visit.bell.get("doorstep") is Vector3,
		"The live doorstep is a Vector3 in memory (%s)." % str(typeof(visit.bell.get("doorstep"))))

	# The saved record must carry a packed doorstep, which is what the validator
	# reads: an Array of three numbers, not the live Vector3.
	var saved: Dictionary = visit.snapshot()
	var bell: Dictionary = saved.get("doorbell", {})
	check(not bell.is_empty(), "The snapshot carries the doorbell record.")
	check(bell.get("doorstep") is Array,
		"The snapshot packs the doorstep as an Array (%s)." % str(typeof(bell.get("doorstep"))))
	check(bell.get("position") is Array,
		"The snapshot packs the caller's position as an Array (%s)." % str(typeof(bell.get("position"))))
	# And that packed record is exactly what the save validator accepts.
	check(LifeHomeVisit._validate_bell(saved.doorbell, int(saved.next_bell_serial) + 1,
		{"member_state": {"day": app.household.day, "minutes": app.household.minutes},
		 "residents": {"locations": {"home": {"maya": {}}}}}).is_empty(),
		"The packed doorbell passes the save validator.")

	# A real restore returns the same ground point rather than a lost caller.
	var live_doorstep: Vector3 = visit.bell.doorstep
	visit.restore(saved)
	check(visit.ringing() and visit.bell.get("doorstep") is Vector3 and visit.bell.doorstep == live_doorstep,
		"The restored caller waits on the same ground point (%s)." % str(visit.bell.get("doorstep")))

	# A ringing bell is its own record with no visit yet. The household's own
	# snapshot must still carry it, or the caller is forgotten across a save.
	var household_snap: Dictionary = app.residents.snapshot()
	check(household_snap.has("home_visit"),
		"The household snapshot carries a ringing doorbell with no active visit.")
	check((household_snap.get("home_visit", {}) as Dictionary).has("doorbell"),
		"That record really holds the caller on the doorstep.")

	app.queue_free()
	await process_frame
	print("DOORSTEP_SAVE %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
