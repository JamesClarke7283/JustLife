extends SceneTree
## The doorbell: nobody wanders in, and the household decides who does.
##
## A neighbor who reaches the front path rings the bell and waits on the
## doorstep, outside the house. The household can let them in — which starts an
## ordinary invited visit — or ask them to leave, at any time. Before this, a
## resident stepping back on after a routine window flipped to the "visiting"
## phase, whose waypoints sit inside the house, so people simply walked in.

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(v: bool, m: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if v else "FAIL ", m)
	if not v:
		failures.append(m)


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _inside_house(p: Vector3) -> bool:
	return absf(p.x) < 6.0 and absf(p.z) < 5.0


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.selected_lot = 0
	app.household_profiles = [{"name": "Mara Vale"}]
	app.start_household()
	await frames(2)
	app.household.set_speed(1)

	var visit: LifeHomeVisit = app.residents.home_visit
	var maya: LifeActor = app.world.actors["maya"]
	# Put Maya on the front path as a routine window closing does.
	maya.position = Vector3(0, .16, 7.2)
	app.world.set_actor_away("maya", false, false)
	app.residents.locations["home"]["maya"].phase = "visiting"
	check(visit.consider_ring(), "A neighbor on the front path rings the doorbell.")
	check(visit.ringing(), "The doorbell is ringing.")
	check(str(visit.bell.guest) == "maya", "The caller is recorded.")
	check(not _inside_house(maya.position), "The caller is still outside the house.")

	# They must wait outside while the household decides.
	for i: int in 60:
		app._process(0.05)
		await frames(1)
	check(not _inside_house(maya.position), "The caller waits outside instead of wandering in.")
	var door: Vector3 = visit._door()
	check(Vector2(maya.position.x, maya.position.z).distance_to(Vector2(door.x, door.z)) < 3.0, "The caller waits at the door.")

	# Turning them away sends them off.
	app.answer_doorbell("turn_away")
	check(not visit.ringing(), "Turning the caller away closes the doorbell.")
	check(not visit.active(), "A turned-away caller does not become a visit.")
	for i: int in 200:
		app._process(0.05)
		await frames(1)
	check(not _inside_house(maya.position), "A turned-away caller never enters the house.")

	# Ring again on a later day and let them in this time. A fresh arrival: they
	# are back on the path and present, exactly as the walk cycle leaves them.
	app.household.day = 2
	maya.position = Vector3(0, .16, 7.2)
	app.world.set_actor_away("maya", false, false)
	maya.visible = true
	app.residents.locations["home"]["maya"].phase = "visiting"
	print("  diag present=", app.residents.present("maya"), " ringing=", visit.ringing(), " active=", visit.active(), " trip=", not app.residents.trip.is_empty(), " pos=", maya.position, " phase=", app.residents.locations["home"]["maya"].phase, " speaker=", not app.residents._speaker("maya").is_empty(), " away_meta=", maya.get_meta("away", false), " visible=", maya.visible)
	check(visit.consider_ring(), "A neighbor can ring again afterwards.")
	app.answer_doorbell("let_in")
	check(visit.active(), "Letting them in starts an ordinary invited visit.")
	check(not visit.ringing(), "The doorstep record is spent once they are let in.")
	for i: int in 4000:
		app._process(0.1)
		await frames(1)
		if visit.active() and str(visit.state.phase) == "inside":
			break
		if not visit.active():
			break
	check(str(visit.state.get("phase", "")) == "inside", "A let-in caller really comes inside.")
	check(_inside_house(maya.position), "The let-in caller is inside the house.")

	# Ask them to leave at any time.
	visit.goodbye()
	check(str(visit.state.get("phase", "")) == "leaving", "Ask to leave works while they are inside.")
	for i: int in 6000:
		app._process(0.1)
		await frames(1)
		if not visit.active():
			break
	check(not visit.active(), "The guest really leaves when asked.")
	check(not _inside_house(maya.position), "The departed guest is out of the house.")

	print("BELL %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
