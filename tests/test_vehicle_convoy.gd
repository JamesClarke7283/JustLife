extends SceneTree
## Cars that would meet take turns. Two adults whose routes cross, and three adults
## with cars side by side, leave at the same game minute: the swept bodies never
## overlap, the follower waits parked with a caption, the wait is on the saved record,
## a save in the middle of it keeps it, and the cars come home together, or while
## another is leaving, onto their own spots without touching.
const Path = preload("res://scripts/vehicle_path.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Drive = preload("res://scripts/vehicle_drive.gd")
const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []
var overlap_frames: int = 0
var min_gap_seen: float = INF

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
		print("FAIL ", message)

func gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))

func members() -> Array:
	return app.household.members

func commute_of(index: int) -> Dictionary:
	return members()[index].sim.get_current_action().get("commute", {})

func phase_of(index: int) -> String:
	return str(commute_of(index).get("phase", ""))

func fresh(adults: int, cars: Array, garage: bool = false) -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = []
	for index: int in adults: app.household_profiles.append({"name": "Adult %d" % index, "age_stage": "adult", "traits": []})
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false); app.household.set_speed(1)
	for member: Dictionary in members():
		member.sim.autonomy = false; member.sim.minutes = 540.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 100.0
	app.household.minutes = 540.0
	if garage: app.world.add_item({"id": "garage", "kind": "car_garage", "x": -11.2, "z": 6.1, "rotation": 0})
	for index: int in cars.size():
		var car: Dictionary = cars[index]
		app.world.add_item({"id": "car%d" % index, "kind": "car", "x": float(car.x), "z": float(car.z), "rotation": float(car.rotation)})
	var migrated: Dictionary = LifeBuildingState.migrate(app.world.construction.snapshot())
	app.world.construction.restore(migrated.state)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	overlap_frames = 0; min_gap_seen = INF

func queue_all(at_doors: bool) -> void:
	for index: int in members().size():
		app._bind_member(str(members()[index].id))
		var node: Node3D = app._find_item("car%d" % index).node
		check(app.sim.queue_action("drive_to_work", "car%d" % index, node.position), "Adult %d queues the drive to work" % index)
		if at_doors:
			var stand: Vector3 = node.global_transform * Vector3(1.42, 0, -.092)
			app.world.actors[str(members()[index].id)].position = Vector3(stand.x, .16, stand.z)

## Count the frames in which two cars on the road or at their spots overlap.
func watch() -> void:
	var cars: Array = []
	for id: String in app.work_commute.views:
		var view: Dictionary = app.work_commute.views[id]
		if view.car.visible: cars.append(view.car)
	for i: int in cars.size():
		for j: int in range(i + 1, cars.size()):
			var a: Node3D = cars[i]
			var b: Node3D = cars[j]
			if Planner.boxes_overlap(a.global_position.x, a.global_position.z, a.rotation.y, .91, 2.1, b.global_position.x, b.global_position.z, b.rotation.y, .91, 2.1): overlap_frames += 1

func all_in(phase: String) -> bool:
	for index: int in members().size():
		if phase_of(index) != phase: return false
	return true

func run() -> void:
	# ---- two adults whose routes cross, both at their doors
	await fresh(2, [{"x": -12.0, "z": 3.0, "rotation": 0}, {"x": -14.5, "z": 7.5, "rotation": 90}])
	var homes: Array = []
	for index: int in 2: homes.append(app._find_item("car%d" % index).node.global_transform)
	queue_all(true)
	var started: Array = [-1, -1]
	var caption_seen: bool = false
	var parked_while_waiting: bool = true
	var holds: Array = [0.0, 0.0]
	var saved: bool = false
	var reload_hold: float = -1.0
	var reload_parked: bool = false
	var order: Array[int] = []
	for frame: int in 4000:
		app._process(DT)
		watch()
		for index: int in 2:
			var state: Dictionary = commute_of(index)
			if phase_of(index) == "depart":
				if started[index] < 0: started[index] = frame; order.append(index)
				holds[index] = float(state.get("depart_hold", 0.0))
				var waiting: bool = float(state.time) < holds[index]
				if waiting:
					var view: Dictionary = app.work_commute.views[str(members()[index].id)]
					parked_while_waiting = parked_while_waiting and view.car.global_position.distance_to(homes[index].origin) < .001
					if app.work_commute.caption(members()[index].sim.get_current_action()) == Drive.WAITING: caption_seen = true
					if not saved and float(state.time) > .5:
						saved = true
						check(app.save_game("", "Convoy hold"), "A save in the middle of a wait is written")
						var read: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
						check(read.ok, "The save in the middle of a wait validates: " + str(read.get("error", "")))
						var prepared: Dictionary = app._prepare_loaded_world(read.data)
						check(prepared.ok, "...and rebuilds physically: " + str(prepared.get("error", "")))
						if prepared.ok:
							var candidate: Node = prepared.candidate
							candidate.household.set_speed(0)
							for i: int in candidate.household.members.size():
								candidate._bind_member(str(candidate.household.members[i].id))
								candidate.work_commute.tick(0.0)
							var twin: Dictionary = candidate.household.members[index].sim.get_current_action().get("commute", {})
							reload_hold = float(twin.get("depart_hold", -1.0))
							var reborn: Dictionary = candidate.work_commute.views.get(str(candidate.household.members[index].id), {})
							reload_parked = not reborn.is_empty() and reborn.car.global_position.distance_to(homes[index].origin) < .001
							prepared.viewport.free(); candidate.free()
		if all_in("away"): break
	check(all_in("away"), "Both adults drive off to work")
	check(started[0] >= 0 and started[1] >= 0 and absi(started[0] - started[1]) <= 1, "Both drivers finish boarding in the same moment (frames %s)" % str(started))
	check(holds.has(0.0) and (holds[0] > 0.0 or holds[1] > 0.0), "Exactly the follower waits (holds %s)" % str(holds))
	check(order[0] == 0 and float(holds[0]) == 0.0 and float(holds[1]) > 0.0, "The first to finish boarding goes first and the second waits (order %s, holds %s)" % [str(order), str(holds)])
	check(caption_seen, "The waiting driver's caption says '%s'" % Drive.WAITING)
	check(parked_while_waiting, "The follower stays parked, exactly on its spot, while it waits")
	check(overlap_frames == 0, "The two cars' bodies never overlap on the way out (%d frames)" % overlap_frames)
	check(reload_hold >= 0.0 and absf(reload_hold - float(holds[1])) < 1e-6 and reload_parked, "A save in the middle of the wait keeps it and the car parked (%.2f s)" % reload_hold)
	# ---- ... and home again at the same minute
	while app.household.minutes < 1020.0:
		app.household.tick(minf(30.0, 1020.0 - app.household.minutes) / LifeSim.GAME_MINUTES_PER_SECOND)
	var returned: Array = [false, false]
	var return_holds: Array = [0.0, 0.0]
	var exact: Array = [false, false]
	overlap_frames = 0
	for frame: int in 5000:
		app._process(DT)
		watch()
		for index: int in 2:
			var state: Dictionary = commute_of(index)
			if phase_of(index) == "return": return_holds[index] = maxf(float(return_holds[index]), float(state.get("return_hold", 0.0)))
			if phase_of(index) == "exit":
				returned[index] = true
				var view: Dictionary = app.work_commute.views[str(members()[index].id)]
				exact[index] = view.car.global_position.distance_to(homes[index].origin) < .01 and gap(view.car.rotation.y, homes[index].basis.get_euler().y) < deg_to_rad(.5)
		if not members()[0].sim.is_away() and not members()[1].sim.is_away(): break
	check(returned[0] and returned[1], "Both cars come home")
	check(exact[0] and exact[1], "Each car is exactly on its own parked pose before its driver gets out")
	check(overlap_frames == 0, "The cars' bodies never overlap on the way home (%d frames, holds %s)" % [overlap_frames, str(return_holds)])

	# ---- a car arriving while another leaves
	await fresh(2, [{"x": -12.0, "z": 3.0, "rotation": 0}, {"x": -14.5, "z": 7.5, "rotation": 90}])
	homes.clear()
	for index: int in 2: homes.append(app._find_item("car%d" % index).node.global_transform)
	app._bind_member(str(members()[0].id))
	check(app.sim.queue_action("drive_to_work", "car0", app._find_item("car0").node.position), "The first adult leaves for work")
	for frame: int in 4000:
		app._process(DT)
		if phase_of(0) == "away": break
	while app.household.minutes < 700.0:
		app.household.tick(minf(30.0, 700.0 - app.household.minutes) / LifeSim.GAME_MINUTES_PER_SECOND)
	app._bind_member(str(members()[1].id))
	var node: Node3D = app._find_item("car1").node
	check(app.sim.queue_action("drive_to_work", "car1", node.position), "The second adult leaves while the first is at work")
	var stand: Vector3 = node.global_transform * Vector3(1.42, 0, -.092)
	app.world.actors[str(members()[1].id)].position = Vector3(stand.x, .16, stand.z)
	var told: bool = false
	var arriving_hold: float = 0.0
	var both_moving_frames: int = 0
	overlap_frames = 0
	var finished_exact: bool = false
	for frame: int in 4000:
		app._process(DT)
		watch()
		if not told and phase_of(1) == "depart":
			told = true
			members()[0].sim.away_state.return_minutes = float(members()[0].sim.minutes) - 1.0
		if phase_of(0) == "return":
			arriving_hold = maxf(arriving_hold, float(commute_of(0).get("return_hold", 0.0)))
			if phase_of(1) == "depart": both_moving_frames += 1
		if phase_of(0) == "exit":
			var view: Dictionary = app.work_commute.views[str(members()[0].id)]
			finished_exact = view.car.global_position.distance_to(homes[0].origin) < .01 and gap(view.car.rotation.y, homes[0].basis.get_euler().y) < deg_to_rad(.5)
		if phase_of(1) == "away" and phase_of(0) in ["exit", "back", ""] and not members()[0].sim.is_away(): break
		if phase_of(1) == "away" and phase_of(0) == "exit": break
	check(told and both_moving_frames > 0, "One car arrives while the other leaves (%d frames of both)" % both_moving_frames)
	check(overlap_frames == 0, "...and their bodies never overlap (%d frames, the arrival waited %.2f s)" % [overlap_frames, arriving_hold])
	check(finished_exact, "The arriving car still ends exactly on its spot")

	# ---- three adults whose cars stand side by side facing the street, at the same minute
	# (a garage bay's doors are boxed in by the next bay, so a driver cannot walk to it:
	# the planner's bay routes are covered by test_vehicle_planner and test_vehicle_routes)
	var row_x: Array = [-15.5, -11.9, -8.3]
	await fresh(3, [{"x": row_x[0], "z": 3.0, "rotation": 0}, {"x": row_x[1], "z": 3.0, "rotation": 0}, {"x": row_x[2], "z": 3.0, "rotation": 0}])
	homes.clear()
	for index: int in 3: homes.append(app._find_item("car%d" % index).node.global_transform)
	queue_all(true)
	var synced: bool = false
	var bay_holds: Array = [0.0, 0.0, 0.0]
	var departed: Array = [false, false, false]
	var drove: Array = [0, 0, 0]
	var forward_all: bool = true
	for frame: int in 6000:
		app._process(DT)
		watch()
		if not synced and all_in("board"):
			# the three boarding beats run in step, so all three cars are ready at once
			synced = true
			for index: int in 3: commute_of(index).time = 3.19
		for index: int in 3:
			if phase_of(index) == "depart":
				departed[index] = true
				bay_holds[index] = float(commute_of(index).get("depart_hold", 0.0))
				forward_all = forward_all and float(commute_of(index).get("drive_sign", 0.0)) == 1.0
				drove[index] += 1
		if all_in("away"): break
	check(synced and all_in("away"), "Three adults board together and drive off")
	check(departed[0] and departed[1] and departed[2], "All three cars leave")
	check(forward_all, "Every car in the row drives forward out")
	check(overlap_frames == 0, "Three cars side by side never overlap (%d frames, holds %s)" % [overlap_frames, str(bay_holds)])
	print("GARAGE holds ", bay_holds)
	while app.household.minutes < 1020.0:
		app.household.tick(minf(30.0, 1020.0 - app.household.minutes) / LifeSim.GAME_MINUTES_PER_SECOND)
	overlap_frames = 0
	var exits: Array = [false, false, false]
	var home_exact: Array = [false, false, false]
	for frame: int in 8000:
		app._process(DT)
		watch()
		for index: int in 3:
			if phase_of(index) == "exit" and not exits[index]:
				exits[index] = true
				var view: Dictionary = app.work_commute.views[str(members()[index].id)]
				home_exact[index] = view.car.global_position.distance_to(homes[index].origin) < .01 and gap(view.car.rotation.y, homes[index].basis.get_euler().y) < deg_to_rad(.5)
		var home_now: bool = true
		for member: Dictionary in members(): home_now = home_now and not member.sim.is_away()
		if home_now: break
	check(exits[0] and exits[1] and exits[2], "All three cars come home")
	check(home_exact[0] and home_exact[1] and home_exact[2], "Each car is on its own spot when its driver gets out")
	check(overlap_frames == 0, "Three cars backing in side by side never overlap (%d frames)" % overlap_frames)

	print("VEHICLE_CONVOY %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
