extends SceneTree
## Vehicle departure tracks the car's forward axis without side-to-side slide,
## and an arrived outing leaves a parked car at the venue to drive again.
const DT: float = 1.0 / 30.0

var checks: int = 0
var failures: Array = []
var app: Node


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)

	# A car parked facing north (yaw 0): driving must advance along +Z, not slide on X.
	var car := Node3D.new()
	app.world.house.add_child(car)
	car.position = Vector3(3, 0, 8)
	car.rotation.y = 0.0
	app.residents.car = car
	app.residents.trip = {"phase": "departure", "time": 0.0, "destination": "cafe", "resume": 0, "party": [], "drive_from": [3.0, 0.0, 8.0], "drive_yaw": 0.0}
	var zs: Array[float] = []
	var xs: Array[float] = []
	for i: int in 30:
		app.residents.tick_trip(DT)
		zs.append(car.global_position.z)
		xs.append(car.global_position.x)
	var z_travel: float = zs[-1] - zs[0]
	var x_drift: float = 0.0
	for x: float in xs:
		x_drift = maxf(x_drift, absf(x - 3.0))
	check(z_travel > 1.5, "Departure advances along the car's forward axis (Δz=%.2f)" % z_travel)
	check(x_drift < 0.08, "Departure does not slide side-to-side (max |Δx|=%.3f)" % x_drift)
	# Abort the half-finished trip so arrival logic can be checked cleanly.
	if is_instance_valid(app.residents.car):
		app.residents.car.queue_free()
	app.residents.car = null
	app.residents.trip.clear()
	app.mode = "live"
	app.world.live_enabled = true

	# Park at a venue after arrival: the body stays and is clickable.
	app.current_venue = "cafe"
	app.residents.trip_vehicle = {"kind": "car", "style": "", "color": "", "size": "", "paint": ""}
	app.residents.car = app.residents._make_car()
	app.world.house.add_child(app.residents.car)
	app.residents.car.position = Vector3(0, 0, 10.25)
	app.residents.car.rotation.y = PI * 0.5
	app.residents._park_venue_car()
	check(is_instance_valid(app.residents.venue_car), "Arrival parks the trip car at the venue")
	check(app.world.pick_extras.has(LifeResidents.VENUE_CAR_ID), "Parked venue car is clickable")
	var pick: Dictionary = app.world.pick_extras[LifeResidents.VENUE_CAR_ID]
	check(str(pick.get("kind", "")) == "car" and bool(pick.get("venue_trip", false)), "Click payload offers Drive… on the parked car")
	check(LifeOutdoorActs.leisure_actions("car").has("drive_car"), "A parked car still offers Drive…")

	# Taking the parked car for the next leg reuses the same body.
	var before: Node3D = app.residents.venue_car
	var again: Node3D = app.residents._spawn_trip_car({}, before.global_transform)
	check(again == before and app.residents.venue_car == null, "The next trip reuses the parked venue car")

	_finish()


func _finish() -> void:
	var out := FileAccess.open("res://evidence/vehicle_drive_probe.txt", FileAccess.WRITE)
	if out:
		out.store_string("checks=%d failures=%d\n" % [checks, failures.size()])
		for line: String in failures:
			out.store_string("FAIL: %s\n" % line)
		out.close()
	print("VEHICLE_DRIVE_PROBE assertions=%d failures=%d" % [checks, failures.size()])
	for line: String in failures:
		print("FAIL: ", line)
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
