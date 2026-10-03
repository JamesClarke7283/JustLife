extends SceneTree
## The household's trips by car: the way out follows a planned route with the camera
## easing after the car, the fifteen minutes still span the drive however long it
## is, a venue arrival eases into the kerb without sliding, the way home from a
## venue ends on the household car's own parked pose with the party stepping out
## beside it, and a boxed-in car refuses the trip before anything changes.
const Path = preload("res://scripts/vehicle_path.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Drive = preload("res://scripts/vehicle_drive.gd")
const Road = preload("res://scripts/road.gd")
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

func clock_minutes() -> float:
	return (app.household.day - 1) * 1440.0 + app.household.minutes

func fresh(x: float, z: float, rotation: float, size: String = "") -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Driver", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false); app.household.set_speed(0)
	for member: Dictionary in app.household.members: member.sim.autonomy = false
	var entry: Dictionary = {"id": "trip_car", "kind": "car", "x": x, "z": z, "rotation": rotation}
	if not size.is_empty(): entry["size"] = size
	app.world.add_item(entry)
	app.world.rebuild_navigation(); app._refresh_sim_targets()

## Run the trip until the given phase starts; returns false if it never does.
func run_to(phase: String, limit: int = 4000) -> bool:
	for frame: int in limit:
		if str(app.residents.trip.get("phase", "")) == phase: return true
		app._process(DT)
		if app.mode != "travel" and app.residents.trip.is_empty(): return false
	return str(app.residents.trip.get("phase", "")) == phase

func run() -> void:
	await fresh(-12.0, 3.0, 0.0)
	var parked: Node3D = app._find_item("trip_car").node
	var home: Transform3D = parked.global_transform
	var scene: Dictionary = Planner.scene_from_world(app.world, "trip_car")
	var rects: Array = (scene.solid as Array) + (scene.soft as Array)
	var clock_before: float = clock_minutes()
	check(app.residents.begin_trip("library"), "The household sets off on a trip from its own car")
	var drive: Dictionary = app.residents.trip.get("drive", {})
	check(drive.has("path") and Path.path_error(drive.path) == "" and str(drive.kind) == "forward", "The trip carries a valid planned route (%s)" % str(drive.get("kind", "none")))
	var duration: float = Path.duration(drive.path)
	check(duration > 4.0 and duration < 14.0, "The planned drive takes a believable time (%.1f s)" % duration)
	check(Drive.trip_seconds(app.residents.trip, 6.0) == duration, "The trip's drive phase lasts as long as the route")
	check(run_to("departure"), "The party boards and the car sets off")
	# ---- the way out
	var frames: int = 0
	var worst_yaw: float = 0.0
	var max_turn: float = 0.0
	var touched: int = 0
	var previous_yaw: float = INF
	var first_yaw: float = 0.0
	var max_camera_step: float = 0.0
	var max_camera_gap: float = 0.0
	var previous_camera: Vector3 = app.world.camera_target
	var half_clock: float = -1.0
	var steer_seen: float = 0.0
	var rig_wheels: Dictionary = {}
	var lights_on: bool = false
	for frame: int in 3000:
		var phase: String = str(app.residents.trip.get("phase", ""))
		if phase != "departure": break
		app._process(DT)
		if str(app.residents.trip.get("phase", "")) != "departure": break
		var car: Node3D = app.residents.car
		var yaw: float = car.rotation.y
		if frames == 0: first_yaw = yaw
		else: worst_yaw = maxf(worst_yaw, gap(yaw, previous_yaw))
		max_turn = maxf(max_turn, gap(yaw, first_yaw))
		previous_yaw = yaw
		for rect: Rect2 in rects:
			if overlaps(car.global_position.x, car.global_position.z, yaw, .91, 2.1, rect): touched += 1; break
		var camera: Vector3 = app.world.camera_target
		max_camera_step = maxf(max_camera_step, camera.distance_to(previous_camera))
		previous_camera = camera
		max_camera_gap = maxf(max_camera_gap, Vector2(camera.x - car.global_position.x, camera.z - (car.global_position.z - 2.2)).length())
		if half_clock < 0.0 and float(app.residents.trip.time) >= duration * .5: half_clock = float(app.residents.trip.get("travel_sim", 0.0))
		if app.residents.trip.drive.has("rig"):
			rig_wheels = app.residents.trip.drive.rig
			for wheel: Dictionary in rig_wheels.wheels:
				if bool(wheel.front) and not bool(wheel.hub):
					var delta: Basis = (wheel.node as Node3D).transform.basis * (wheel.rest as Transform3D).basis.inverse()
					var axle: Vector3 = delta * Vector3(1, 0, 0)
					steer_seen = maxf(steer_seen, absf(atan2(-axle.z, axle.x)))
		frames += 1
	check(frames > 100, "The departure is a real drive (%d frames)" % frames)
	check(rad_to_deg(max_turn) > 60.0, "The car turns onto the road (%.0f degrees)" % rad_to_deg(max_turn))
	check(rad_to_deg(worst_yaw) < 2.6, "Its heading never jumps (%.2f degrees in a frame)" % rad_to_deg(worst_yaw))
	check(touched == 0, "The trip car never touches the house, a furnishing or a hedge (%d frames)" % touched)
	check(rad_to_deg(steer_seen) > 12.0, "The front wheels steer visibly (%.0f degrees)" % rad_to_deg(steer_seen))
	check(max_camera_step < .5, "The camera never jumps: at most %.2f m a frame" % max_camera_step)
	check(max_camera_gap < 3.0, "The camera stays within three metres of the car on screen (%.2f m)" % max_camera_gap)
	check(absf(half_clock - 7.5) < 1.2, "Half way through the drive half the quarter hour has passed (%.2f minutes)" % half_clock)
	check(app.residents.trip.get("phase", "") == "arrival" or app.mode == "travel", "The drive ends in the arrival at the library")
	# ---- the arrival at the venue: along the lane, eased onto the kerb, no sideways slide
	var arrival_frames: int = 0
	var sideways: float = 0.0
	var arrival_yaw_step: float = 0.0
	var last_pos: Vector3 = Vector3.INF
	var last_yaw: float = INF
	var arrival_camera_step: float = 0.0
	var last_cam: Vector3 = Vector3.INF
	var last_car: Vector3 = Vector3.ZERO
	var last_car_yaw: float = 0.0
	var arrival_start: Vector3 = Vector3.INF
	for frame: int in 3000:
		if str(app.residents.trip.get("phase", "")) != "arrival": app._process(DT); continue
		var car: Node3D = app.residents.car
		if not is_instance_valid(car): break
		if arrival_start == Vector3.INF: arrival_start = car.global_position
		if last_pos != Vector3.INF:
			var step: Vector3 = car.global_position - last_pos
			var heading := Vector3(sin(car.rotation.y), 0, cos(car.rotation.y))
			var side := Vector3(heading.z, 0, -heading.x)
			if step.length() > .02: sideways = maxf(sideways, absf(step.dot(side)))
			arrival_yaw_step = maxf(arrival_yaw_step, gap(car.rotation.y, last_yaw))
			arrival_camera_step = maxf(arrival_camera_step, app.world.camera_target.distance_to(last_cam))
		last_pos = car.global_position; last_yaw = car.rotation.y; last_cam = app.world.camera_target
		last_car = car.global_position; last_car_yaw = car.rotation.y
		arrival_frames += 1
		app._process(DT)
		if app.mode != "travel": break
	check(arrival_start.x < -Road.EXIT_X + 1.0 and absf(arrival_start.z - Road.LANE_NEAR_Z) < .05, "The car arrives along the near lane from the west (%s)" % str(arrival_start))
	check(arrival_frames > 60, "The arrival is a real drive (%d frames)" % arrival_frames)
	check(sideways < .02, "The car never slides sideways on the way in (%.3f m a frame across its heading)" % sideways)
	check(rad_to_deg(arrival_yaw_step) < 2.6, "Its heading never jumps on the way in")
	check(arrival_camera_step < .2, "The arrival camera pans without a jump (%.3f m a frame)" % arrival_camera_step)
	check(app.mode == "live" and app.current_venue == "library", "The party has arrived at the library")
	check(is_instance_valid(app.residents.venue_car) and app.residents.venue_car.position.distance_to(Vector3(Road.KERB_PARK_X, 0.0, Road.KERB_PARK_Z)) < .01 and gap(app.residents.venue_car.rotation.y, PI * .5) < deg_to_rad(.5), "The car is parked at the kerb spot, facing along the lane")
	check(app.world.camera_target.is_equal_approx(Vector3(0, 0, .25)), "The camera ends on the usual framing (no cut at the end)")
	check(clock_minutes() == clock_before + 15.0, "The drive advanced exactly fifteen minutes (%.9f)" % (clock_minutes() - clock_before))
	for member: Dictionary in app.household.members: member.sim.autonomy = false
	app.household.set_speed(0)

	# ---- home again from the venue: the kerb run out, the household car's own spot in
	var venue_clock: float = clock_minutes()
	check(app.residents.begin_trip("home"), "The party sets off home from the library")
	var leave: Dictionary = app.residents.trip.get("drive", {})
	check(str(leave.get("kind", "")) == "kerb" and Path.path_error(leave.path) == "", "Leaving a venue is a smooth run along the lane from the kerb")
	check(run_to("departure"), "The party boards the venue car")
	var kerb_end: Vector3 = Path.end_pose(leave.path)
	check(absf(kerb_end.y - Road.LANE_NEAR_Z) < .05 and gap(kerb_end.z, PI * .5) < deg_to_rad(1.0) and kerb_end.x >= Road.EXIT_X - .6, "It pulls out into the near lane and away (%s)" % str(kerb_end))
	var kerb_yaw_step: float = 0.0
	var prior: float = INF
	for frame: int in 3000:
		if str(app.residents.trip.get("phase", "")) != "departure": break
		app._process(DT)
		if is_instance_valid(app.residents.car) and str(app.residents.trip.get("phase", "")) == "departure":
			if prior != INF: kerb_yaw_step = maxf(kerb_yaw_step, gap(app.residents.car.rotation.y, prior))
			prior = app.residents.car.rotation.y
	check(rad_to_deg(kerb_yaw_step) < 2.6, "The kerb departure never jumps in heading")
	check(str(app.residents.trip.get("phase", "")) == "arrival" and app.current_venue == "home", "The drive ends back on the home lot")
	var homeward: Dictionary = app.residents.trip.get("drive", {})
	check(str(homeward.get("kind", "")) in ["forward_in", "reverse_in"] and homeward.has("parked_body"), "Home with the household car is a planned way onto its own spot (%s)" % str(homeward.get("kind", "none")))
	var owned: Node3D = app._find_item("trip_car").node
	var owned_pose: Transform3D = owned.global_transform
	check(not owned.visible, "The parked body is hidden while its twin drives in")
	var home_scene: Dictionary = Planner.scene_from_world(app.world, "trip_car")
	var home_touched: int = 0
	var last_trip_car: Transform3D = Transform3D.IDENTITY
	var home_camera_step: float = 0.0
	var home_cam: Vector3 = Vector3.INF
	for frame: int in 3000:
		if app.mode != "travel": break
		app._process(DT)
		if app.mode == "travel" and is_instance_valid(app.residents.car):
			var car: Node3D = app.residents.car
			last_trip_car = car.global_transform
			for rect: Rect2 in (home_scene.solid as Array) + (home_scene.soft as Array):
				if overlaps(car.global_position.x, car.global_position.z, car.rotation.y, .91, 2.1, rect): home_touched += 1; break
			if home_cam != Vector3.INF: home_camera_step = maxf(home_camera_step, app.world.camera_target.distance_to(home_cam))
			home_cam = app.world.camera_target
	check(app.mode == "live" and app.current_venue == "home", "The household is home")
	check(home_touched == 0, "The car touches nothing on its way onto the spot (%d frames)" % home_touched)
	check(last_trip_car.origin.distance_to(Vector3(owned_pose.origin.x, last_trip_car.origin.y, owned_pose.origin.z)) < .01 and gap(last_trip_car.basis.get_euler().y, owned_pose.basis.get_euler().y) < deg_to_rad(.5), "The trip car's last frame is exactly the parked pose (%.4f m)" % last_trip_car.origin.distance_to(Vector3(owned_pose.origin.x, last_trip_car.origin.y, owned_pose.origin.z)))
	check(owned.visible, "The household car's own body is shown again")
	check(app.residents.car == null, "The trip car is gone once parked")
	check(home_camera_step < .2, "The camera pans home without a jump (%.3f m a frame)" % home_camera_step)
	check(app.world.camera_target.is_equal_approx(Vector3(0, 0, .25)), "...and ends on the usual framing")
	var near_car: bool = true
	for member: Dictionary in app.household.members:
		var body: LifeActor = app.world.actors[member.id]
		near_car = near_car and body.visible and body.position.distance_to(owned_pose.origin) < 3.0
	check(near_car, "The party steps out beside the car, not at the old kerb spot")
	check(clock_minutes() == venue_clock + 15.0, "The drive home advanced exactly fifteen minutes")
	check(Drive.trip_seconds({}, 6.0) == 6.0 and Drive.trip_seconds({"drive": {}}, 2.2) == 2.2, "A trip with no route keeps the old time budget")

	# ---- a boxed-in car refuses the trip before anything changes
	await fresh(-12.0, 4.0, 0.0)
	for index: int in 4:
		var box: Array = [[-12.0, 1.7, 0.0, "L420H120"], [-12.0, 6.6, 0.0, "L420H120"], [-14.4, 4.0, 90.0, "L440H120"], [-9.6, 4.0, 90.0, "L440H120"]][index]
		app.world.add_item({"id": "box_%d" % index, "kind": "fence", "x": box[0], "z": box[1], "rotation": box[2], "style": "01", "size": box[3]})
	app.world.rebuild_navigation()
	var visible_before: bool = app._find_item("trip_car").node.visible
	var minutes_before: float = clock_minutes()
	check(not app.residents.begin_trip("library"), "A car boxed in by fences refuses the trip")
	check(app.mode == "live" and app.residents.trip.is_empty() and app.residents.car == null and app._find_item("trip_car").node.visible == visible_before and clock_minutes() == minutes_before, "...before any state is changed")
	check(str(app.notice_text).contains("Clear the driveway"), "...with the driveway notice: " + str(app.notice_text))

	# ---- a large car: a route or the same clean refusal
	await fresh(-12.0, 3.0, 0.0, "large")
	var big_ok: bool = app.residents.begin_trip("library")
	check(big_ok or str(app.notice_text).contains("Clear the driveway"), "A large car either has a route or is cleanly refused")
	if big_ok: check(app.mode == "travel" and app.residents.trip.has("drive") == (app.residents.trip.get("drive", {}).has("path")) or app.mode == "travel", "The large car's trip is under way")

	print("TRIP_DRIVE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
