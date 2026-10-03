extends SceneTree
## The small neighbours of the car routes: the car that brings a mother and baby home
## now eases along its lane onto the kerb instead of sliding sideways 2.16 m, the
## Large Estate preset's garage stands inside the lot and its bays have a way out,
## and the police car turns at the station without its heading snapping.
const Path = preload("res://scripts/vehicle_path.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Road = preload("res://scripts/road.gd")
const Crime = preload("res://scripts/crime_response.gd")
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

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Mother", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false)

	# ---- the birth car: along the lane, eased onto the kerb, no sideways slide
	app._begin_birth_arrival_cinematic([])
	var car: Node3D = app.birth_arrival.car
	check(car.position.is_equal_approx(Vector3(-Road.EXIT_X, 0, Road.LANE_NEAR_Z)) and gap(car.rotation.y, PI * .5) < 1e-4, "The birth car starts out of sight in the near lane, facing along it")
	var last: Vector3 = car.global_position
	var sideways: float = 0.0
	var along: float = 0.0
	var worst_yaw: float = 0.0
	var last_yaw: float = car.rotation.y
	var steer: float = 0.0
	var frames: int = 0
	for frame: int in 800:
		app._tick_birth_arrival(DT)
		if str(app.birth_arrival.get("phase", "")) != "drive": break
		var step: Vector3 = car.global_position - last
		var heading := Vector3(sin(car.rotation.y), 0, cos(car.rotation.y))
		sideways = maxf(sideways, absf(step.dot(Vector3(heading.z, 0, -heading.x))))
		along += step.dot(heading)
		worst_yaw = maxf(worst_yaw, gap(car.rotation.y, last_yaw))
		last = car.global_position; last_yaw = car.rotation.y
		frames += 1
		var rig: Dictionary = app.birth_arrival.drive.rig
		if bool(rig.ok):
			for wheel: Dictionary in rig.wheels:
				if bool(wheel.front) and not bool(wheel.hub):
					var delta: Basis = (wheel.node as Node3D).transform.basis * (wheel.rest as Transform3D).basis.inverse()
					steer = maxf(steer, absf(atan2(-(delta * Vector3(1, 0, 0)).z, (delta * Vector3(1, 0, 0)).x)))
	check(str(app.birth_arrival.get("phase", "")) == "exit", "The birth car reaches the kerb and the exit begins")
	check(frames > 60 and frames < 12 * 30, "The drive is a real drive of a few seconds (%d frames)" % frames)
	check(sideways < .02, "It never slides sideways: at most %.4f m a frame across its heading (the old slide was 2.16 m in all)" % sideways)
	check(along > 20.0, "It really drives in along its heading (%.1f m)" % along)
	check(car.global_position.distance_to(Vector3(Road.KERB_PARK_X, 0, Road.KERB_PARK_Z)) < .01 and gap(car.rotation.y, PI * .5) < deg_to_rad(.5), "It stops exactly on the kerb spot")
	check(rad_to_deg(worst_yaw) < 1.5, "Its heading never jumps (%.2f deg a frame)" % rad_to_deg(worst_yaw))
	check(rad_to_deg(steer) > .5, "Its front wheels steer into the kerb (%.2f deg)" % rad_to_deg(steer))
	app._end_birth_arrival_cinematic()

	# ---- the Large Estate preset
	check(app.world.validate_home_layout(LifeCatalog.starter_layout(7)) == "", "starter_layout(7), the Large Estate, validates")
	var garage: Dictionary = {}
	for entry: Variant in LifeCatalog.starter_layout(7):
		if entry is Dictionary and str(entry.get("kind", "")) == "car_garage": garage = entry
	check(not garage.is_empty() and LifeBuildingState.lot().encloses(app.world.furnishing_rect(garage)), "Its garage stands wholly inside the lot")
	check(not garage.is_empty() and int(garage.rotation) == 0, "...and opens towards the street")
	app.world.create_home(LifeCatalog.starter_layout(7))
	await process_frame
	for index: int in 4:
		var bay_x: float = float(garage.x) + [-3.2, -1.1, 1.1, 3.2][index]
		app.world.add_item({"id": "estate_car_%d" % index, "kind": "car", "x": bay_x, "z": float(garage.z) + .35, "rotation": 0})
	var routed: int = 0
	for index: int in 4:
		var node: Node3D = app._find_item("estate_car_%d" % index).node
		var plan: Dictionary = Planner.plan_departure(Planner.scene_from_world(app.world, "estate_car_%d" % index), Vector3(node.position.x, node.position.z, node.rotation.y))
		if bool(plan.ok): routed += 1
	check(routed == 4, "All four bays of the Large Estate garage have a forward way out (%d)" % routed)

	# ---- the police car's heading never snaps at the station
	var world := LifeWorld.new(); root.add_child(world)
	var home := LifeHousehold.new(); root.add_child(home)
	home.new_household([{"name": "Parent", "age_stage": "adult"}, {"name": "Child", "age_stage": "child"}])
	await process_frame
	world.create_home(LifeCatalog.starter_layout(0))
	await process_frame
	var crime: Node = Crime.new(); world.add_child(crime); crime.setup(world, home); crime.set_sound(false)
	crime.consider_night(3, .0099)
	for frame: int in 3000:
		crime.tick(.1, .3)
		if crime.phase == "escaped": break
	check(crime.phase == "escaped" and bool(crime.call_police("housemate_1").ok), "The burglar escapes and police are called")
	for frame: int in 3000:
		crime.tick(.1, .3)
		if crime.phase == "departing": break
	check(crime.phase == "departing", "The patrol is ready to drive to the station")
	var previous: float = crime.police_car.rotation.y
	var worst: float = 0.0
	var turned: float = 0.0
	var start_yaw: float = previous
	for frame: int in 900:
		crime.tick(DT, .3)
		if crime.phase != "departing": break
		worst = maxf(worst, gap(crime.police_car.rotation.y, previous))
		turned = maxf(turned, gap(crime.police_car.rotation.y, start_yaw))
		previous = crime.police_car.rotation.y
	check(crime.phase != "departing", "The patrol reaches the station")
	check(rad_to_deg(turned) > 60.0, "The patrol turns into the station yard (%.0f degrees)" % rad_to_deg(turned))
	check(rad_to_deg(worst) < 5.0, "...without its heading ever snapping: at most %.2f degrees in a frame" % rad_to_deg(worst))

	print("VEHICLE_EXTRAS %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
