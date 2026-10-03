extends SceneTree
## The street's numbers live in LifeRoad; the ground drawing and the lanes cars
## drive must agree with them, and every older street constant must still lie
## where it always did (the kerb spot, the delivery van, the walkers' lanes).
const Road = preload("res://scripts/road.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
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

func box_at(centre_z: float, size_x: float) -> MeshInstance3D:
	for node: Node in app.world.ground_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh is BoxMesh and absf(mesh.position.z - centre_z) < .001 and absf((mesh.mesh as BoxMesh).size.x - size_x) < .001 and absf(mesh.position.x) < .001: return mesh
	return null

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Road", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false)

	# ---- the drawn ground reads the constants
	var sidewalk: MeshInstance3D = box_at(Road.SIDEWALK_Z, Road.SIDEWALK_LENGTH)
	var road: MeshInstance3D = box_at(Road.ROAD_CENTER_Z, Road.ROAD_LENGTH)
	check(sidewalk != null, "The sidewalk is drawn at the constant's centre and length")
	check(road != null, "The road is drawn at the constant's centre and length")
	if sidewalk != null:
		var size: Vector3 = (sidewalk.mesh as BoxMesh).size
		check(absf(size.z - Road.SIDEWALK_WIDTH) < 1e-4, "The sidewalk is as wide as the constant")
		check(absf(sidewalk.position.z - Road.SIDEWALK_WIDTH * .5 - 7.875) < 1e-4 and absf(sidewalk.position.z + Road.SIDEWALK_WIDTH * .5 - 9.125) < 1e-4, "The sidewalk still covers z 7.875 to 9.125")
	if road != null:
		var size: Vector3 = (road.mesh as BoxMesh).size
		check(absf(size.z - Road.ROAD_WIDTH) < 1e-4, "The road is as wide as the constant")
		check(absf(road.position.z - size.z * .5 - Road.ROAD_NEAR_EDGE) < 1e-4, "The road's kerb edge is where the constant puts it")
		check(absf(road.position.z + size.z * .5 - Road.ROAD_FAR_EDGE) < 1e-4, "The road's far edge is where the constant puts it")
	var dashes: int = 0
	for node: Node in app.world.ground_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh is BoxMesh and absf((mesh.mesh as BoxMesh).size.x - 2.0) < .001 and absf((mesh.mesh as BoxMesh).size.z - .08) < .001 and absf(mesh.position.z - Road.ROAD_CENTER_Z) < .001: dashes += 1
	check(dashes == 13, "The centre dashes run down the middle of the road (%d)" % dashes)

	# ---- the constants agree with one another
	check(absf(Road.ROAD_NEAR_EDGE + Road.ROAD_WIDTH - Road.ROAD_FAR_EDGE) < 1e-6, "Near edge plus width is the far edge")
	check(absf(Road.ROAD_NEAR_EDGE + Road.ROAD_WIDTH * .5 - Road.ROAD_CENTER_Z) < 1e-6, "The road's centre is halfway across")
	check(absf(Road.LANE_WIDTH * 2.0 - Road.ROAD_WIDTH) < 1e-6, "Two lanes fill the road")
	check(absf(Road.ROAD_NEAR_EDGE + Road.LANE_WIDTH * .5 - Road.LANE_NEAR_Z) < 1e-6 and absf(Road.ROAD_FAR_EDGE - Road.LANE_WIDTH * .5 - Road.LANE_FAR_Z) < 1e-6, "Each lane's centre is the middle of its half")
	check(Road.lane_z(1.0) == Road.LANE_NEAR_Z and Road.lane_z(-1.0) == Road.LANE_FAR_Z, "Eastbound drives the near lane, westbound the far one")
	check(is_equal_approx(Road.lane_yaw(1.0), PI * .5) and is_equal_approx(Road.lane_yaw(-1.0), -PI * .5), "Lane yaw faces along the street")

	# ---- the older street constants still hold
	var lot: Rect2 = LifeBuildingState.lot()
	check(lot.end.y == 9.0 and lot.position.x == -18.0 and lot.end.x == 18.0 and lot.position.y == -12.0, "The lot's bounds are untouched")
	check(lot.end.y <= 9.125 and lot.end.y >= 7.875 and Road.ROAD_NEAR_EDGE > 9.125, "The lot's front edge is on the sidewalk and the road starts beyond it")
	check(Road.on_road(Road.KERB_PARK_Z) and Road.KERB_PARK_Z == 10.25, "The kerb spot z is 10.25 and on the road")
	check(Road.KERB_PARK_Z - .91 >= Road.ROAD_NEAR_EDGE and Road.KERB_PARK_Z + .91 <= Road.ROAD_CENTER_Z, "A car at the kerb spot lies inside the near lane's half of the road")
	check(Road.VAN_Z == 10.6 and Road.VAN_Z + .91 <= Road.ROAD_CENTER_Z and Road.VAN_Z - .91 >= Road.ROAD_NEAR_EDGE, "The delivery van's z lies inside the near lane")
	app.world.show_delivery_van()
	check(is_instance_valid(app.world.delivery_van) and absf(app.world.delivery_van.position.z - Road.VAN_Z) < 1e-6, "The delivery van is parked at the constant z")
	app.world.hide_delivery_van()
	var kerb: Transform3D = app.residents._trip_car_transform({})
	check(absf(kerb.origin.z - Road.KERB_PARK_Z) < 1e-6 and absf(kerb.origin.x - Road.KERB_PARK_X) < 1e-6, "The shared car's kerb stand is the constant spot")
	var car := Node3D.new(); app.world.house.add_child(car)
	app.residents.car = car
	app.residents._park_venue_car()
	check(absf(app.residents.venue_car.position.z - Road.KERB_PARK_Z) < 1e-6, "A venue car parks at the constant kerb spot")
	app.residents._clear_venue_car()
	check(LifeStreetLife.LANE_EAST > 7.875 and LifeStreetLife.LANE_EAST < 9.125 and LifeStreetLife.LANE_WEST > 7.875 and LifeStreetLife.LANE_WEST < 9.125, "The walkers' lanes are on the sidewalk")
	check(LifeCrimeResponse.CURB.z >= Road.ROAD_NEAR_EDGE and LifeCrimeResponse.CURB.z <= Road.ROAD_CENTER_Z, "The police kerb stop is in the near half of the road")
	check(LifeSchoolBus.CURB.z < Road.ROAD_NEAR_EDGE, "The school bus still runs along the sidewalk line, off the tarmac")

	# ---- a lane keeps the body on the road for every car size
	for car_scale: float in [1.0, 1.45, 2.0]:
		var half: float = Planner.BODY_HALF_WIDTH * car_scale
		for sign: float in [1.0, -1.0]:
			var lane_z: float = Planner._lane_z(sign, car_scale)
			check(lane_z - half >= Road.ROAD_NEAR_EDGE - .2 and lane_z + half <= Road.ROAD_FAR_EDGE + .2, "A x%s car in the %s lane stays on the road (z %.2f)" % [str(car_scale), "near" if sign > 0 else "far", lane_z])
	check(Planner._lane_z(1.0, 1.0) == Road.LANE_NEAR_Z and Planner._lane_z(-1.0, 1.0) == Road.LANE_FAR_Z, "An ordinary car drives exactly the lane's centre line")
	check(Road.EXIT_X > 18.0 and Road.EXIT_X < Road.ROAD_LENGTH * .5, "Cars leave the view along the road before it ends")

	print("ROAD_GEOMETRY %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
