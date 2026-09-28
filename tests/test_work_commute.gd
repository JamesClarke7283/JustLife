extends SceneTree
const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func verify_snapshot(phase: String) -> void:
	if "--versioned" not in OS.get_cmdline_user_args(): return
	print("COMMUTE_SNAPSHOT ", phase)
	var wrote: bool = app.save_game("", "Commute " + phase)
	check(wrote, "Versioned household saves during " + phase + ": " + str(LifeSaveLibrary._validate_household(app.household.get_state(app.world.serialize_items())).get("error", "")))
	var read: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
	check(read.ok, "Saved " + phase + " passes household validation: " + str(read.get("error", "")))
	if not read.ok: return
	var prepared: Dictionary = app._prepare_loaded_world(read.data)
	check(prepared.ok, "Physical " + phase + " reconstruction succeeds: " + str(prepared.get("error", "")))
	if prepared.ok:
		var candidate: Node = prepared.candidate
		candidate.household.set_speed(0)
		candidate.work_commute.tick(0.0)
		check(str(candidate.sim.get_current_action().commute.phase) == phase, "Paused load preserves " + phase)
		prepared.viewport.free(); candidate.free()

func capture(label: String, target: Vector3) -> void:
	if "--visual" not in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute("res://art/goal_commute")
	if label == "03_back_entrance": app.world.camera_angle += PI
	app.world.camera_target = target
	app.world.camera.size = 10.0
	app.world.update_camera()
	app.refresh_hud()
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art/goal_commute/" + label + ".png")

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Commuter", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false); app.household.set_speed(1)
	app.sim.autonomy = false; app.household.minutes = 540.0; app.sim.minutes = 540.0
	for need: String in LifeSim.NEED_NAMES: app.sim.needs[need] = 100.0
	app.world.add_item({"id": "commute_car", "kind": "car", "x": -9.0, "z": 6.0, "rotation": 90})
	if "--versioned" in OS.get_cmdline_user_args() or "--canonical" in OS.get_cmdline_user_args():
		var migrated: Dictionary = LifeBuildingState.migrate(app.world.construction.snapshot())
		check(migrated.ok, "Commute fixture migrates to versioned construction.")
		app.world.construction.restore(migrated.state)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	var parked: Node3D = app._find_item("commute_car").node
	var home: Vector3 = parked.global_position
	var plan = preload("res://scripts/work_commute.gd")
	var front_bay := Transform3D(Basis.IDENTITY, Vector3(-8, 0, 8.3))
	check(plan.drive_direction(app.world, front_bay, "commute_car") == 1.0, "North-facing car leaves along its clear forward driveway.")
	front_bay = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 8.3))
	check(plan.drive_direction(app.world, front_bay, "commute_car") == -1.0, "A car facing the house reverses out rather than crossing the house.")
	app._go_to_work()
	check(str(app.sim.get_current_action().get("id", "")) == "drive_to_work", "Go to work selects the owned car.")
	var snapshots: Array[String] = []
	var phases: Array[String] = []
	var beats: Array[String] = []
	var walk_start: Vector3 = app.player.position
	var crossed_rear: bool = false
	for frame: int in 4000:
		app._process(DT)
		var action: Dictionary = app.sim.get_current_action()
		var phase: String = str(action.get("commute", {}).get("phase", ""))
		if not phase.is_empty() and not phases.has(phase):
			phases.append(phase)
			verify_snapshot(phase)
		if phase == "board":
			var view: Dictionary = app.work_commute.views[app.bound_member_id]
			var beat: String = str(view.entry.current().get("part", ""))
			if not beats.has(beat): beats.append(beat)
			if beat == "in" and not snapshots.has("board_image"):
				snapshots.append("board_image"); await capture("01_boarding", home + Vector3(0, .7, 0))
			check(view.car.global_position.distance_to(home) < .001, "Car remains parked throughout boarding.")
		if phase == "depart" and float(action.commute.time) > 1.0 and not snapshots.has("depart"):
			snapshots.append("depart")
			var before: Vector3 = app.work_commute.views[app.bound_member_id].car.global_position
			check(app.save_game("", "Departure regression"), "A partially driven departure saves with its phase.")
			app.household.set_speed(0)
			app.work_commute.tick(0.0)
			check(app.work_commute.views[app.bound_member_id].car.global_position.distance_to(before) < .5, "Pausing departure keeps the car along its saved route.")
			app.household.set_speed(1)
		if phase == "away": break
	check(app.player.position.distance_to(walk_start) > 1.0, "The worker physically walks to the car.")
	check(phases == ["walk", "board", "depart", "away"], "Morning phases run in order: " + str(phases))
	check(beats == ["approach", "open", "in", "close"], "Door opens, worker enters, door closes before departure: " + str(beats))
	check(app.save_game("", "Commute regression"), "The complete live household saves while its worker is away.")
	check(app.sim.is_away() and not app.player.visible, "Departure starts a real work absence and hides the cabin occupant.")
	var live_action: Dictionary = app.sim.get_current_action()
	var funds_before: int = app.sim.funds
	app.mode = "build"
	for operation: String in ["move_item", "store_item", "sell_item"]:
		app.call(operation, app._find_item("commute_car"))
		check(app._find_item("commute_car").get("node") == parked and is_same(app.sim.get_current_action(), live_action), "Build " + operation + " preserves the active car and workday.")
	check(app.pending_move.is_empty() and app.sim.funds == funds_before, "Rejected commute car edits neither start placement nor change funds.")
	app.mode = "live"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(app.sim._json_safe(app.sim.get_state())))
	var resumed: LifeSim = LifeSim.new(); resumed.new_household({"name": "Test", "age_stage": "adult"})
	check(resumed.restore_state(saved).ok and resumed.get_current_action().has("commute"), "A saved workday retains its car return.")
	for invalid: String in ["orphan_away", "early_return", "unknown_vehicle", "missing_direction", "fractional_direction"]:
		var damaged: Dictionary = saved.duplicate(true)
		match invalid:
			"orphan_away": damaged.action_queue[0].id = "drive_to_work"; damaged.away_state = {}
			"early_return": damaged.action_queue[0].commute.phase = "exit"
			"unknown_vehicle": damaged.action_queue[0].commute.vehicle = ""
			"missing_direction": damaged.action_queue[0].commute.erase("drive_sign")
			"fractional_direction": damaged.action_queue[0].commute.drive_sign = .001
		check(not resumed.restore_state(damaged).ok, "Malformed commute rejects: " + invalid)
	resumed.free()
	# Advance only the household clock through actual work; the controller then
	# sees the ordinary earned returning state and performs the visible arrival.
	while app.sim.minutes < 1020.0:
		app.household.tick(minf(30.0, 1020.0 - app.sim.minutes) / LifeSim.GAME_MINUTES_PER_SECOND)
	for frame: int in 5000:
		app._process(DT)
		var action: Dictionary = app.sim.get_current_action()
		var phase: String = str(action.get("commute", {}).get("phase", ""))
		if not phase.is_empty() and not phases.has(phase):
			phases.append(phase)
			verify_snapshot(phase)
		if phase == "exit":
			if not snapshots.has("return_image") and float(action.commute.time) > 1.7:
				snapshots.append("return_image"); await capture("02_parked_exit", home + Vector3(0, .7, 0))
			var view: Dictionary = app.work_commute.views[app.bound_member_id]
			check(view.car.global_position.distance_to(home) < .001, "The car parks before the driver gets out.")
		if phase == "back" and app.player.position.z < -5.5:
			crossed_rear = true
			if not snapshots.has("back_image") and int(action.commute.leg) >= 2:
				snapshots.append("back_image"); await capture("03_back_entrance", Vector3(3.55, .5, -4.4))
		if not app.sim.is_away(): break
	check(phases == ["walk", "board", "depart", "away", "return", "exit", "back"], "Evening phases drive, park, exit, close and walk: " + str(phases))
	check(crossed_rear and not app.sim.is_away() and app.player.position.z < -3.0, "Return walks around the house and through its rear entrance; final body=%s commute=%s path=%s" % [app.player.position, app.sim.get_current_action().get("commute", {}), app.path])
	check(parked.visible and app.work_commute.views.is_empty(), "The parked car is restored after the worker comes inside.")
	check(app.sim.needs.energy >= 79.95, "Energy remains at least 80 at home arrival.")
	print("WORK_COMMUTE %d checks, %d failures; phases=%s beats=%s" % [checks, failures.size(), str(phases), str(beats)])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
