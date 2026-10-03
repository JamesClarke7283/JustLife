extends SceneTree
## A gate in a car's way swings open for it and shuts behind it: for the drive to
## work and for a trip with the household.
const GateFlow=preload("res://scripts/gate_flow.gd")
const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func fresh() -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Driver", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false); app.household.set_speed(1)
	app.sim.autonomy = false; app.household.minutes = 540.0; app.sim.minutes = 540.0
	for need: String in LifeSim.NEED_NAMES: app.sim.needs[need] = 100.0
	# The frontage is fenced along z 8.4 with a driveway gate in it. The car stands
	# in line with the gate facing the street, so its planned route leaves through
	# the gate (and comes home back through it): a car crosses a fence line only
	# through a gate. The gate no longer has to stand across a straight line.
	app.world.add_item({"id": "gate_car", "kind": "car", "x": -12.0, "z": 3.0, "rotation": 0})
	app.world.add_item({"id": "fence_west", "kind": "fence", "x": -15.75, "z": 8.4, "rotation": 0, "style": "01", "size": "L450H120"})
	app.world.add_item({"id": "fence_east", "kind": "fence", "x": 3.75, "z": 8.4, "rotation": 0, "style": "01", "size": "L2850H120"})
	app.world.add_item({"id": "drive_gate", "kind": "garden_gate_drive", "x": -12.0, "z": 8.4, "rotation": 0.0})
	app.world.rebuild_navigation(); app._refresh_sim_targets()

func gate(id: String = "drive_gate") -> Node3D:
	return app._find_item(id).node

func car_node() -> Node3D:
	for node: Node in app.get_tree().get_nodes_in_group(GateFlow.DRIVING_GROUP):
		return node as Node3D
	return null

## Follow a drive: the gate's openness whenever a car is on the move, and whether
## it was open as the car's nose reached it.
func follow(frames: int, running: Callable) -> Dictionary:
	var watched: Node3D = gate("drive_gate")
	var out: Dictionary = {"closed_at_start": GateFlow.openness(watched) == 0.0, "open_at_nose": -1.0, "max": 0.0, "driving_frames": 0}
	for frame: int in frames:
		running.call()
		var car: Node3D = car_node()
		if car != null:
			out.driving_frames += 1
			var local: Vector3 = watched.to_local(car.global_position)
			if out.open_at_nose < 0.0 and absf(local.z) < 2.2: out.open_at_nose = GateFlow.openness(watched)
		out.max = maxf(float(out.max), GateFlow.openness(watched))
		if car == null and out.driving_frames > 0 and GateFlow.openness(watched) == 0.0: break
	return out

func run() -> void:
	# ---- the drive to work
	await fresh()
	check(GateFlow.openness(gate("drive_gate")) == 0.0, "The gate starts shut")
	check(not app._find_item("drive_gate").is_empty() and not app._find_item("fence_west").is_empty(), "A driveway gate stands in the fenced frontage")
	app._go_to_work()
	var crossings: Array[float] = []
	var seen: Dictionary = follow(2400, func() -> void:
		app._process(DT)
		var mover: Node3D = car_node()
		if mover != null and absf(mover.global_position.z - 8.4) < .08: crossings.append(mover.global_position.x))
	check(seen.closed_at_start, "The gate is shut before the car moves")
	check(int(seen.driving_frames) > 30, "The car really drives (%d frames)" % int(seen.driving_frames))
	check(float(seen.max) > .99, "The gate swings fully open for the car")
	check(float(seen.open_at_nose) > .9, "The gate is already open when the car's nose reaches it (%.2f)" % float(seen.open_at_nose))
	check(not crossings.is_empty() and crossings.all(func(x: float) -> bool: return x > -13.5 and x < -10.5), "The car crosses the fence line only inside the gate (%s)" % str(crossings))
	for frame: int in 200: app._process(DT)
	check(GateFlow.openness(gate("drive_gate")) == 0.0, "The gate has shut behind the car")
	check(car_node() == null, "A car that has gone leaves the gate alone")

	# ---- and the same car coming home
	while app.sim.minutes < 1020.0:
		app.household.tick(minf(30.0, 1020.0 - app.sim.minutes) / LifeSim.GAME_MINUTES_PER_SECOND)
	var homeward: Dictionary = {"max": 0.0, "driving": 0}
	for frame: int in 3000:
		app._process(DT)
		if car_node() != null:
			homeward.driving += 1
			homeward.max = maxf(float(homeward.max), GateFlow.openness(gate("drive_gate")))
		if not app.sim.is_away(): break
	check(int(homeward.driving) > 30 and float(homeward.max) > .99, "The gate opens for the car driving home")
	for frame: int in 200: app._process(DT)
	check(GateFlow.openness(gate("drive_gate")) == 0.0, "The gate shuts once the car is home")

	# ---- a trip with the household
	await fresh()
	app.household.set_speed(0)
	check(app.residents.begin_trip("library"), "The household sets off on a trip")
	var trip_open: float = 0.0
	var trip_frames: int = 0
	for frame: int in 4000:
		app._process(DT)
		if app.mode != "travel": break
		if str(app.residents.trip.get("phase", "")) == "departure":
			trip_frames += 1
			trip_open = maxf(trip_open, GateFlow.openness(gate()))
	check(trip_frames > 20, "The trip's car drives off the lot (%d frames)" % trip_frames)
	check(trip_open > .99, "The gate swings open for the household's car (%.2f)" % trip_open)

	print("GATE_VEHICLES %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
