extends SceneTree
## The drive to and from work as the player sees it: the car turns smoothly onto the
## lane that matches its heading, its wheels steer and roll, it never touches the
## house, the furniture or the hedge, the saved record rebuilds the same pose, an
## old record (no route) still plays the straight run, and the drive home ends
## exactly on the parked pose before the driver gets out.
const Path = preload("res://scripts/vehicle_path.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Road = preload("res://scripts/road.gd")
const Rig = preload("res://scripts/vehicle_rig.gd")
const Commute = preload("res://scripts/work_commute.gd")
const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
		print("FAIL ", message)

func gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))

func overlaps(x: float, z: float, yaw: float, hw: float, hl: float, rect: Rect2) -> bool:
	var forward := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(cos(yaw), -sin(yaw))
	var corners: Array[Vector2] = []
	for a: float in [-1.0, 1.0]:
		for b: float in [-1.0, 1.0]: corners.append(Vector2(x, z) + forward * hl * a + side * hw * b)
	var rect_corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for axis: Vector2 in [Vector2(1, 0), Vector2(0, 1), forward, side]:
		var low_a: float = INF; var high_a: float = -INF; var low_b: float = INF; var high_b: float = -INF
		for corner: Vector2 in corners:
			low_a = minf(low_a, corner.dot(axis)); high_a = maxf(high_a, corner.dot(axis))
		for corner: Vector2 in rect_corners:
			low_b = minf(low_b, corner.dot(axis)); high_b = maxf(high_b, corner.dot(axis))
		if high_a < low_b or high_b < low_a: return false
	return true

func fresh(x: float, z: float, rotation: float) -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Commuter", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false); app.household.set_speed(1)
	app.sim.autonomy = false; app.household.minutes = 540.0; app.sim.minutes = 540.0
	for need: String in LifeSim.NEED_NAMES: app.sim.needs[need] = 100.0
	app.world.add_item({"id": "commute_car", "kind": "car", "x": x, "z": z, "rotation": rotation})
	var migrated: Dictionary = LifeBuildingState.migrate(app.world.construction.snapshot())
	check(migrated.ok, "The fixture migrates to versioned construction")
	app.world.construction.restore(migrated.state)
	app.world.rebuild_navigation(); app._refresh_sim_targets()

func phase_of() -> String:
	return str(app.sim.get_current_action().get("commute", {}).get("phase", ""))

func state_of() -> Dictionary:
	return app.sim.get_current_action().get("commute", {})

func view() -> Dictionary:
	return app.work_commute.views.get(app.bound_member_id, {})

## The angle a front tyre is steered, read off the wheel node itself.
func steer_of(rig: Dictionary) -> float:
	for wheel: Dictionary in rig.wheels:
		if bool(wheel.front) and not bool(wheel.hub):
			var delta: Basis = (wheel.node as Node3D).transform.basis * (wheel.rest as Transform3D).basis.inverse()
			var axle: Vector3 = delta * Vector3(1, 0, 0)
			return atan2(-axle.z, axle.x)
	return 0.0

func run() -> void:
	await fresh(-12.0, 3.0, 0.0)
	var parked: Node3D = app._find_item("commute_car").node
	var home: Transform3D = parked.global_transform
	var scene: Dictionary = Planner.scene_from_world(app.world, "commute_car")
	var rects: Array = (scene.solid as Array) + (scene.soft as Array)
	app._go_to_work()
	check(str(app.sim.get_current_action().get("id", "")) == "drive_to_work", "Go to work selects the owned car")

	# ---- the way out
	var seen: Array[String] = []
	var yaw_before: float = INF
	var worst_yaw_step: float = 0.0
	var max_yaw_change: float = 0.0
	var max_steer: float = 0.0
	var rear_steer: float = 0.0
	var touched: int = 0
	var left_lot_sideways: int = 0
	var depart_frames: int = 0
	var first_pose: Vector3 = Vector3.ZERO
	var last_pose: Vector3 = Vector3.ZERO
	var saved_state: Dictionary = {}
	var saved_car: Vector3 = Vector3.ZERO
	var saved_steer: float = 0.0
	var board_ok: bool = true
	var cabin_ok: bool = true
	var vehicle: Dictionary = {"kind": "car", "x": home.origin.x, "z": home.origin.z, "rotation": 0, "hang": 0, "size": ""}
	for frame: int in 4000:
		app._process(DT)
		var phase: String = phase_of()
		if not phase.is_empty() and not seen.has(phase): seen.append(phase)
		if phase in ["board", "depart", "away", "return", "exit"] and not view().is_empty():
			cabin_ok = cabin_ok and Commute.cabin_position_matches(app.sim.get_current_action(), app.player.position, vehicle)
		if phase == "board" and not view().is_empty(): board_ok = board_ok and view().car.global_position.distance_to(home.origin) < .001
		if phase == "depart":
			var car: Node3D = view().car
			var pose := Vector3(car.global_position.x, car.global_position.z, car.rotation.y)
			if depart_frames == 0:
				first_pose = pose
				check(state_of().has("drive_path") and Path.path_error(state_of().drive_path) == "", "The commute keeps a valid planned route on the record")
				check(str(state_of().drive_sign) != "" and float(state_of().drive_sign) == 1.0, "A street-facing car drives forward (drive_sign +1)")
			else:
				worst_yaw_step = maxf(worst_yaw_step, gap(pose.z, yaw_before))
			max_yaw_change = maxf(max_yaw_change, gap(pose.z, first_pose.z))
			yaw_before = pose.z
			last_pose = pose
			depart_frames += 1
			for rect: Rect2 in rects:
				if overlaps(pose.x, pose.y, pose.z, .91, 2.1, rect): touched += 1; break
			if pose.y < 7.4 and absf(pose.x) > 18.0 - Planner.SIDE_CLEARANCE + .001: left_lot_sideways += 1
			var rig: Dictionary = view().wheels
			max_steer = maxf(max_steer, absf(steer_of(rig)))
			for wheel: Dictionary in rig.wheels:
				if not bool(wheel.front) and not bool(wheel.hub):
					var delta: Basis = (wheel.node as Node3D).transform.basis * (wheel.rest as Transform3D).basis.inverse()
					rear_steer = maxf(rear_steer, absf((delta * Vector3(1, 0, 0)).z))
			if saved_state.is_empty() and float(state_of().time) > 3.0:
				saved_state = state_of().duplicate(true)
				saved_car = Vector3(car.global_position.x, car.global_position.z, car.rotation.y)
				saved_steer = steer_of(rig)
				check(app.save_game("", "Departure drive"), "A save in the middle of the drive is written")
				var read: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
				check(read.ok, "The mid-drive save reads back and validates: " + str(read.get("error", "")))
				if read.ok:
					var prepared: Dictionary = app._prepare_loaded_world(read.data)
					check(prepared.ok, "The mid-drive save reconstructs physically: " + str(prepared.get("error", "")))
					if prepared.ok:
						var candidate: Node = prepared.candidate
						candidate.household.set_speed(0)
						candidate.work_commute.tick(0.0)
						var reborn: Dictionary = candidate.work_commute.views.get(candidate.bound_member_id, {})
						check(not reborn.is_empty(), "The loaded game rebuilds the driving car")
						if not reborn.is_empty():
							var twin: Node3D = reborn.car
							var saved_time: float = float(candidate.sim.get_current_action().commute.time)
							check(Vector2(twin.global_position.x - saved_car.x, twin.global_position.z - saved_car.y).length() < .001, "The reloaded car stands where it was saved (%.4f m apart)" % Vector2(twin.global_position.x - saved_car.x, twin.global_position.z - saved_car.y).length())
							check(gap(twin.rotation.y, saved_car.z) < deg_to_rad(.1), "...facing the same way")
							check(absf(steer_of(reborn.wheels) - saved_steer) < deg_to_rad(.5), "...with its front wheels at the same angle (%.2f vs %.2f deg)" % [rad_to_deg(steer_of(reborn.wheels)), rad_to_deg(saved_steer)])
							var expected: Dictionary = Path.state_at(candidate.sim.get_current_action().commute.drive_path, saved_time - float(candidate.sim.get_current_action().commute.get("depart_hold", 0.0)))
							check(absf(float(expected.x) - twin.global_position.x) < .001 and absf(float(expected.z) - twin.global_position.z) < .001, "The pose is the saved route at the saved time, recomputed")
						prepared.viewport.free(); candidate.free()
		if phase == "away": break
	check(seen == ["walk", "board", "depart", "away"], "Morning phases run in order: " + str(seen))
	check(board_ok, "The car stays parked while the driver boards")
	check(cabin_ok, "The hidden driver stays at the seat through board, depart, away (cabin check)")
	check(depart_frames > 100, "The drive is a real drive, not a hop (%d frames)" % depart_frames)
	check(rad_to_deg(max_yaw_change) > 60.0, "The car turns onto the road (%.0f degrees of heading change)" % rad_to_deg(max_yaw_change))
	check(rad_to_deg(worst_yaw_step) < 2.6, "Its heading never jumps: at most %.2f degrees in a frame (%.0f deg/s)" % [rad_to_deg(worst_yaw_step), rad_to_deg(worst_yaw_step) / DT])
	check(rad_to_deg(max_steer) > 12.0, "The front wheels visibly steer in the turn (%.0f degrees)" % rad_to_deg(max_steer))
	check(rear_steer < .02, "The rear wheels stay straight")
	check(touched == 0, "The car never touches a wall, a furnishing, a hedge or a tree on the way out (%d frames)" % touched)
	check(left_lot_sideways == 0, "It never leaves the lot through the side hedge")
	check(gap(last_pose.z, PI * .5) < deg_to_rad(2.0) and absf(last_pose.y - Road.LANE_NEAR_Z) < .08, "It ends heading east in the near lane (z %.2f yaw %.0f)" % [last_pose.y, rad_to_deg(last_pose.z)])
	check(last_pose.x >= Road.EXIT_X - .6, "...out of the view (x %.1f)" % last_pose.x)

	# ---- the record is validated
	var good: Dictionary = saved_state.duplicate(true)
	check(Commute.save_error(good, {}, {}) == "", "A saved mid-drive record is valid: " + Commute.save_error(good, {}, {}))
	for broken: String in ["nan", "gear", "huge", "long", "hold", "negative_hold", "late", "short_path"]:
		var bad: Dictionary = good.duplicate(true)
		match broken:
			"nan": bad.drive_path.segs[0][1] = NAN
			"gear": bad.drive_path.segs[0][2] = 3
			"huge": bad.drive_path.segs[0][1] = 9999.0
			"long":
				for more: int in 12: bad.drive_path.segs.append([0.0, 5.0, 1])
			"hold": bad["depart_hold"] = 9999.0
			"negative_hold": bad["depart_hold"] = -1.0
			"late": bad.time = 9999.0
			"short_path": bad.drive_path.segs = []
		check(Commute.save_error(bad, {}, {}) != "", "A malformed saved route is refused: " + broken)
	var held: Dictionary = good.duplicate(true)
	held["depart_hold"] = 5.0
	held.time = float(good.time) + 4.0
	check(Commute.save_error(held, {}, {}) == "", "A wait extends how long the phase may last")
	var old_record: Dictionary = {"vehicle": "commute_car", "phase": "depart", "time": 3.9, "leg": 0, "drive_sign": -1.0}
	check(Commute.save_error(old_record, {}, {}) == "", "An old record with no route is still valid")
	old_record.time = 4.5
	check(Commute.save_error(old_record, {}, {}) != "", "...and still ends with the old four seconds")

	# ---- the way home
	while app.sim.minutes < 1020.0:
		app.household.tick(minf(30.0, 1020.0 - app.sim.minutes) / LifeSim.GAME_MINUTES_PER_SECOND)
	var coming: Array[String] = []
	var home_yaw_before: float = INF
	var worst_home_yaw: float = 0.0
	var return_touched: int = 0
	var first_return: Vector3 = Vector3.INF
	var at_exit: Transform3D = Transform3D.IDENTITY
	var saw_return_path: bool = false
	var reverse_frames: int = 0
	for frame: int in 5000:
		app._process(DT)
		var phase: String = phase_of()
		if not phase.is_empty() and not coming.has(phase): coming.append(phase)
		if phase in ["return", "exit"] and not view().is_empty():
			cabin_ok = cabin_ok and Commute.cabin_position_matches(app.sim.get_current_action(), app.player.position, vehicle)
		if phase == "return" and not view().is_empty():
			var car: Node3D = view().car
			saw_return_path = saw_return_path or Path.path_error(state_of().get("return_path", {})) == ""
			var pose := Vector3(car.global_position.x, car.global_position.z, car.rotation.y)
			if not first_return.is_finite(): first_return = pose
			else: worst_home_yaw = maxf(worst_home_yaw, gap(pose.z, home_yaw_before))
			home_yaw_before = pose.z
			for rect: Rect2 in rects:
				if overlaps(pose.x, pose.y, pose.z, .91, 2.1, rect): return_touched += 1; break
			if int(Path.state_at(state_of().return_path, float(state_of().time)).gear) < 0: reverse_frames += 1
		if phase == "exit":
			at_exit = view().car.global_transform
			break
	check(coming.has("return") and coming.has("exit"), "The evening runs return then exit: " + str(coming))
	check(saw_return_path, "The return has its own planned route")
	check(first_return.is_finite() and absf(first_return.y - Road.LANE_NEAR_Z) < .08 and gap(first_return.z, PI * .5) < deg_to_rad(2.0) and first_return.x < -Road.EXIT_X + 1.0, "The car comes into view along the near lane from the west (%s)" % str(first_return))
	check(rad_to_deg(worst_home_yaw) < 2.6, "Its heading never jumps on the way home (%.2f deg per frame)" % rad_to_deg(worst_home_yaw))
	check(return_touched == 0, "It touches nothing on the way home (%d frames)" % return_touched)
	check(reverse_frames > 10, "A street-facing car backs in (%d frames in reverse)" % reverse_frames)
	check(at_exit.origin.distance_to(home.origin) < .01 and gap(at_exit.basis.get_euler().y, home.basis.get_euler().y) < deg_to_rad(.5), "The car is exactly on its parked pose before the driver gets out (%.4f m)" % at_exit.origin.distance_to(home.origin))
	check(cabin_ok, "The hidden driver stays at the seat through return and exit (cabin check)")
	for frame: int in 4000:
		app._process(DT)
		if not app.sim.is_away(): break
	check(not app.sim.is_away() and parked.visible and app.work_commute.views.is_empty(), "The worker is home and the parked car is restored")

	# ---- an old record, with no route, plays the old straight run exactly
	await fresh(-9.0, 6.0, 90.0)
	var old_home: Transform3D = app._find_item("commute_car").node.global_transform
	app._go_to_work()
	for frame: int in 4000:
		app._process(DT)
		if phase_of() == "depart": break
	var state: Dictionary = state_of()
	state.erase("drive_path"); state.erase("depart_hold")
	state["drive_sign"] = -1.0
	state.time = 1.7
	app.work_commute.tick(0.0)
	var expected_old: Vector3 = old_home.origin + old_home.basis.z.normalized() * -1.0 * 22.0 * smoothstep(0.0, 1.0, 1.7 / 4.0)
	var old_car: Node3D = view().car
	check(old_car.global_position.distance_to(expected_old) < 1e-4, "A record with no route reconstructs the old straight run exactly")
	check(gap(old_car.rotation.y, old_home.basis.get_euler().y) < 1e-4, "...and the car never turns on it")
	state.time = 3.99
	for frame: int in 3:
		app._process(DT)
	check(phase_of() in ["depart", "away"], "...which runs its own four seconds")

	print("COMMUTE_DRIVE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
