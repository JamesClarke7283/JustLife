extends SceneTree
## A worker who drives home always gets out and goes indoors, even when the spot
## beside the car is taken or the house has no rear entrance.
const DT: float = 1.0 / 30.0
## The matrix of houses runs on coarser frames so that it finishes in minutes.
var dt: float = DT
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func fresh(plug_rear: bool = false, lot: int = 0, family: bool = false, car: Dictionary = {}) -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Commuter", "age_stage": "adult", "traits": []}]
	if family:
		app.household_profiles.append({"name": "Partner", "age_stage": "adult", "traits": []})
		app.household_profiles.append({"name": "Child", "age_stage": "child", "traits": []})
		app.household_profiles.append({"name": "Baby", "age_stage": "baby", "traits": []})
	app.selected_lot = lot; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false); app.household.set_speed(1)
	app.sim.autonomy = false; app.household.minutes = 540.0; app.sim.minutes = 540.0
	for need: String in LifeSim.NEED_NAMES: app.sim.needs[need] = 100.0
	app.world.add_item({"id": "commute_car", "kind": "car", "x": float(car.get("x", -9.0)), "z": float(car.get("z", 6.0)), "rotation": float(car.get("rotation", 90.0))})
	var snapshot: Dictionary = app.world.construction.snapshot()
	if plug_rear:
		# Close the doorway in the rear wall: the house keeps only its front door.
		snapshot.walls.append({"x": 3.55, "z": -5.04, "w": 1.2, "d": .16, "height": 2.6, "color": "eae7d7", "cut": false, "id": "plug_rear"})
	var migrated: Dictionary = LifeBuildingState.migrate(snapshot)
	check(migrated.ok, "The commute fixture migrates to versioned construction.")
	app.world.construction.restore(migrated.state)
	app.world.rebuild_navigation(); app._refresh_sim_targets()

## Morning: out to the car and away. Evening: back, up to the exit phase.
func work_day() -> bool:
	app._go_to_work()
	for frame: int in 4000:
		app._process(dt)
		if str(app.sim.get_current_action().get("commute", {}).get("phase", "")) == "away": break
	if not app.sim.is_away(): return false
	while app.sim.minutes < 1020.0:
		app.household.tick(minf(30.0, 1020.0 - app.sim.minutes) / LifeSim.GAME_MINUTES_PER_SECOND)
	return true

func phase_of() -> String:
	return str(app.sim.get_current_action().get("commute", {}).get("phase", ""))

## Run the evening until the worker is home or the budget is spent; returns the
## simulated seconds it took (budget when it never finished).
func come_home(on_phase: Callable = Callable()) -> float:
	var seen: Dictionary = {}
	for frame: int in 6000:
		app._process(dt)
		var phase: String = phase_of()
		if not phase.is_empty() and not seen.has(phase):
			seen[phase] = true
			if on_phase.is_valid(): on_phase.call(phase)
		if not app.sim.is_away(): return float(frame) * dt
	return 6000.0 * dt

func run() -> void:
	# ---- the ordinary evening still ends indoors
	await fresh()
	check(await work_day(), "The worker drives off to work")
	var took: float = come_home()
	check(not app.sim.is_away(), "The worker is home again (%s, %.0fs)" % [phase_of(), took])
	check(app.player.visible and not app.player.has_meta("commute_inside"), "They are standing outside the car, visible")
	check(app.work_commute.views.is_empty() and app._find_item("commute_car").node.visible, "The parked car is restored")

	# ---- the spot beside the car is blocked by a neighbouring object
	await fresh()
	check(await work_day(), "The worker drives off again")
	var blocked: Dictionary = {"placed": false}
	took = come_home(func(phase: String) -> void:
		if phase != "exit": return
		var view: Dictionary = app.work_commute.views[app.bound_member_id]
		var stand: Vector3 = view.entry.stand_point("front")
		app.world.add_item({"id": "stand_blocker", "kind": "dining", "x": snappedf(stand.x, .25), "z": snappedf(stand.z, .25), "rotation": 0.0})
		blocked.placed = true
		blocked.stand = stand)
	check(blocked.placed, "A table now stands where the driver gets out")
	check(not app.sim.is_away(), "The worker still gets home when the exit spot is blocked (%s)" % phase_of())
	check(took < 80.0, "They come home promptly instead of standing at the car (%.0fs)" % took)
	check(app.world.lot_navigation.point_clear(0, Vector3(app.player.position.x, .16, app.player.position.z)) or app.player.position.z < 7.0, "They are not left inside the furniture")

	# ---- a house with no rear entrance is entered by the front door
	await fresh(true)
	check(preload("res://scripts/work_commute.gd").back_route(app.world, Vector3(-8, .16, 6)).is_empty(), "The rear wall has no gap, so no rear route exists")
	var front: PackedVector3Array = app.work_commute.front_route()
	check(front.size() == 2 and front[0].distance_to(front[1]) > 1.5, "A front-door route out and in exists (%s)" % str(front))
	check(await work_day(), "The worker drives off from a house with one door")
	took = come_home()
	check(not app.sim.is_away(), "The worker comes home through the front door (%s, %.0fs)" % [phase_of(), took])
	check(took < 80.0, "They do not stand beside the car waiting for a rear entrance (%.0fs)" % took)

	# ---- and a walk that can never finish is given up, not left standing
	await fresh()
	check(await work_day(), "The worker drives off a third time")
	var stuck: bool = false
	for frame: int in 6000:
		app._process(dt)
		if phase_of() == "back":
			var state: Dictionary = app.sim.get_current_action().commute
			state.time = float(app.work_commute.BACK_LIMIT) + 1.0
			stuck = true
			break
	check(stuck, "The walk home is reached")
	for frame: int in 200:
		app._process(dt)
		if not app.sim.is_away(): break
	check(not app.sim.is_away(), "A walk past its time limit puts the worker home")

	dt = .1
	# ---- every starter house, with and without a family, gets its worker indoors:
	# several have furniture just inside the rear door, where the walk used to end.
	for family: bool in [false, true]:
		await fresh(false, 0, family)
		var homes: int = LifeProperties.starters_for(app.household_profiles).size()
		for lot: int in range(homes):
			await fresh(false, lot, family)
			var worked: bool = await work_day()
			var seconds: float = come_home() if worked else -1.0
			check(worked and not app.sim.is_away(), "Starter %d%s: the worker drives home and is indoors again (%s, %.0fs)" % [lot, " with a family" if family else "", phase_of(), seconds])
			check(seconds < 70.0, "Starter %d%s: it takes under a minute and a bit (%.0fs)" % [lot, " with a family" if family else "", seconds])

	# ---- and a car parked where the old route would have run through it
	for placement: Dictionary in [{"x": 7.0, "z": 7.0, "rotation": 90.0}, {"x": -7.0, "z": -8.0, "rotation": 0.0}, {"x": 9.0, "z": -7.0, "rotation": 270.0}]:
		await fresh(false, 0, false, placement)
		var worked: bool = await work_day()
		var seconds: float = come_home() if worked else -1.0
		check(worked and not app.sim.is_away(), "A car at %s,%s: the worker is home again (%s, %.0fs)" % [str(placement.x), str(placement.z), phase_of(), seconds])

	print("COMMUTE_RETURN %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
