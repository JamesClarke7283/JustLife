extends SceneTree
## Routes on the real lot, table driven: every legal parking pose on a grid and the
## named reference placements (yard cars facing every way, a four-bay garage with
## every bay taken, a garage that opens away from the street, a fenced frontage
## with a gate, a parked delivery van, large cars). Each plan is swept with the
## exact body against the world's own walls, furnishings, fences, hedges and gate
## posts, independently of the planner.
const Path = preload("res://scripts/vehicle_path.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Road = preload("res://scripts/road.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var times: Array[float] = []
var tally: Dictionary = {}

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

## Every rectangle that is in the car's way, plus every gate's two posts.
func obstacles(scene: Dictionary, home: Vector3 = Vector3.INF, car_scale: float = 1.0) -> Array:
	var out: Array = (scene.solid as Array).duplicate()
	# planting the car was parked in is driven out of, so it is not held against it
	for rect: Rect2 in scene.soft:
		if home.is_finite() and overlaps(home.x, home.y, home.z, .91 * car_scale, 2.1 * car_scale, rect): continue
		out.append(rect)
	for gate: Dictionary in scene.gates:
		for sign: float in [-1.0, 1.0]:
			var post: Vector2 = gate.c + gate.along * sign * (float(gate.span) * .5 - .1)
			out.append(Rect2(post - Vector2(.1, .1), Vector2(.2, .2)))
	return out

func swept_clear(path: Dictionary, car_scale: float, rects: Array) -> bool:
	var length: float = Path.length_of(path)
	var s: float = 0.0
	while s <= length + .05:
		var pose: Vector3 = Path.pose_at_distance(path, minf(s, length))
		var reach: float = 2.3 * car_scale
		for rect: Rect2 in rects:
			if rect.end.x < pose.x - reach or rect.position.x > pose.x + reach or rect.end.y < pose.y - reach or rect.position.y > pose.y + reach: continue
			if overlaps(pose.x, pose.y, pose.z, .91 * car_scale, 2.1 * car_scale, rect): return false
		s += .25
	return true

## Put one car on the lot and plan both ways with the world's own scene.
func trial(label: String, id: String, home: Vector3, car_scale: float = 1.0, expect_clean: bool = true) -> Dictionary:
	var scene: Dictionary = Planner.scene_from_world(app.world, id)
	var rects: Array = obstacles(scene, home, car_scale)
	var started: int = Time.get_ticks_usec()
	var leave: Dictionary = Planner.plan_departure(scene, home, car_scale)
	var middle: int = Time.get_ticks_usec()
	var back: Dictionary = Planner.plan_arrival(scene, home, car_scale)
	var finished: int = Time.get_ticks_usec()
	times.append(float(middle - started) / 1000.0)
	times.append(float(finished - middle) / 1000.0)
	if bool(leave.ok):
		var path: Dictionary = leave.path
		check(Path.path_error(path) == "", "%s: the departure validates" % label)
		var end: Vector3 = Path.end_pose(path)
		var sign: float = Road.lane_sign_for_yaw(end.z)
		check(not is_zero_approx(sign) and gap(end.z, Road.lane_yaw(sign)) < deg_to_rad(1.0) and absf(end.y - Planner._lane_z(sign, car_scale)) < .05, "%s: it ends square in the lane matching its heading" % label)
		check(sign * end.x >= Road.EXIT_X - .6, "%s: it ends out of the view" % label)
		check(Path.turning(path) < 20.0 and (str(leave.kind) == "forward") == (int(leave.cusps) == 0), "%s: forward means no cusp, reverse means one" % label)
		check(swept_clear(path, car_scale, rects), "%s: the departure's swept body touches nothing" % label)
	if bool(back.ok):
		var path: Dictionary = back.path
		check(Path.path_error(path) == "", "%s: the arrival validates" % label)
		var end: Vector3 = Path.end_pose(path)
		check(Vector2(end.x - home.x, end.y - home.y).length() < .01 and gap(end.z, home.z) < deg_to_rad(.5), "%s: the arrival ends on the parked pose" % label)
		check(swept_clear(path, car_scale, rects), "%s: the arrival's swept body touches nothing" % label)
	var key: String = "%s/%s" % [str(leave.get("kind", "none")), str(back.get("kind", "none"))]
	tally[key] = int(tally.get(key, 0)) + 1
	return {"leave": leave, "back": back}

func place(id: String, kind: String, x: float, z: float, rotation: float, extra: Dictionary = {}) -> void:
	var entry: Dictionary = {"id": id, "kind": kind, "x": x, "z": z, "rotation": rotation}
	entry.merge(extra, true)
	app.world.add_item(entry)

func clear_extras(ids: Array) -> void:
	for id: String in ids:
		if not app._find_item(id).is_empty(): app.world.remove_item(id)

func fresh() -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for frame: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Router", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	for frame: int in 4: await process_frame
	app.set_process(false)

func run() -> void:
	await fresh()
	check(app.world.validate_home_layout(LifeCatalog.starter_layout(7)) == "", "The Large Estate preset (garage inside the lot) validates")

	# ---- a grid of legal parking poses over the yard, four ways
	var legal: int = 0
	var refused: int = 0
	var lacking: PackedStringArray = PackedStringArray()
	var worst_ms: float = 0.0
	for x: float in range(-16, 17, 4):
		for z: float in [-10.0, -6.0, -2.0, 2.0, 6.0]:
			for yaw: float in [0.0, 90.0, 180.0, 270.0]:
				if not app.world.can_place("car", Vector3(x, .16, z), yaw): continue
				legal += 1
				place("grid_car", "car", x, z, yaw)
				var result: Dictionary = trial("grid (%d,%d) yaw %d" % [int(x), int(z), int(yaw)], "grid_car", Vector3(x, z, deg_to_rad(yaw)))
				if not bool(result.leave.ok) or not bool(result.back.ok):
					refused += 1
					lacking.append("(%d,%d,%d)" % [int(x), int(z), int(yaw)])
				clear_extras(["grid_car"])
	print("GRID legal=%d with a missing route=%d tally=%s" % [legal, refused, str(tally)])
	print("GRID_NO_ROUTE ", ", ".join(lacking))
	check(legal >= 60, "The grid covers many legal poses (%d)" % legal)
	check(float(refused) / float(maxi(legal, 1)) < .55, "Most legal poses have a route both ways (%d of %d lack one)" % [refused, legal])

	# ---- the reference placements, with their expected results
	var reference: Array = [
		{"label": "A east-facing (-9,6)", "at": Vector3(-9, 6, 90), "leave": "reverse", "back": "forward_in"},
		{"label": "B south-facing (-12,3)", "at": Vector3(-12, 3, 0), "leave": "forward", "back": "reverse_in"},
		{"label": "C north-facing (-12,4)", "at": Vector3(-12, 4, 180), "leave": "reverse", "back": "forward_in"},
		{"label": "D west-facing (-9,7)", "at": Vector3(-9, 7, 270), "leave": "forward", "back": "any"},
		{"label": "E east-facing east yard (12,6)", "at": Vector3(12, 6, 90), "leave": "forward", "back": "any"},
		{"label": "F south-facing east yard (11,2)", "at": Vector3(11, 2, 0), "leave": "forward", "back": "reverse_in"},
	]
	for row: Dictionary in reference:
		var at: Vector3 = row.at
		place("ref_car", "car", at.x, at.y, at.z)
		var result: Dictionary = trial(str(row.label), "ref_car", Vector3(at.x, at.y, deg_to_rad(at.z)))
		var came: String = str(result.back.get("kind", "none"))
		check(str(result.leave.get("kind", "none")) == str(row.leave) and (came == str(row.back) or (str(row.back) == "any" and came in ["forward_in", "reverse_in"])), "%s leaves %s and comes home %s (got %s / %s)" % [row.label, row.leave, row.back, str(result.leave.get("kind", "none")), came])
		clear_extras(["ref_car"])
	# the back garden: a car facing the open west yard drives round the house; one
	# directly behind it has no one-turn way to the road, so no route (the legacy run decides)
	place("back_car", "car", -11, -9, 270)
	var garden: Dictionary = trial("back garden west-facing", "back_car", Vector3(-11, -9, deg_to_rad(270)))
	print("BACK-GARDEN west-facing ", garden.leave.get("kind", "refused"), " / ", garden.back.get("kind", "refused"))
	clear_extras(["back_car"])
	place("back_car", "car", 0, -9, 0)
	var behind: Dictionary = trial("directly behind the house", "back_car", Vector3(0, -9, 0))
	check(not bool(behind.leave.ok) and not bool(behind.back.ok), "A car directly behind the house has no planned route")
	clear_extras(["back_car"])

	# ---- larger cars: a route or a clean refusal, never a clipped one
	for size: String in ["medium", "large"]:
		var car_scale: float = LifeCatalogVariants.size_scale(size)
		var routed: int = 0
		for at: Vector3 in [Vector3(-12, 3, 0), Vector3(12, 2, 0), Vector3(-12, 3, 180), Vector3(11, -2, 90)]:
			place("big_car", "car", at.x, at.y, at.z, {"size": size})
			var item: Dictionary = app._find_item("big_car")
			var grown: float = LifeCatalogVariants.size_scale(str(item.get("variant", {}).get("size", "")))
			if grown != car_scale: check(false, "The %s car item carries its size (%s)" % [size, str(item.get("variant", {}))])
			var result: Dictionary = trial("%s car at %s" % [size, str(at)], "big_car", Vector3(at.x, at.y, deg_to_rad(at.z)), car_scale)
			if bool(result.leave.ok): routed += 1
			clear_extras(["big_car"])
		print("LARGE ", size, " routed ", routed)

	# ---- a four-bay garage on the street side, every bay taken
	place("garage", "car_garage", -11.2, 6.1, 0)
	var bay_ids: Array = []
	for index: int in 4:
		var bay_x: float = -11.2 + [-3.2, -1.1, 1.1, 3.2][index]
		place("bay_car_%d" % index, "car", bay_x, 6.45, 0)
		bay_ids.append("bay_car_%d" % index)
	app.world.rebuild_navigation()
	for index: int in 4:
		var node: Node3D = app._find_item(str(bay_ids[index])).node
		var result: Dictionary = trial("garage bay %d" % index, str(bay_ids[index]), Vector3(node.position.x, node.position.z, node.rotation.y))
		check(bool(result.leave.ok) and str(result.leave.kind) == "forward", "Bay %d drives forward out of the garage onto the road" % index)
		check(bool(result.back.ok) and str(result.back.kind) == "reverse_in", "Bay %d is backed into" % index)
	clear_extras(bay_ids + ["garage"])

	# ---- a garage that opens away from the street
	place("far_garage", "car_garage", -11.2, 5.9, 180)
	place("far_car", "car", -11.2 - 1.1, 5.55, 180)
	app.world.rebuild_navigation()
	var node: Node3D = app._find_item("far_car").node
	var opposite: Dictionary = trial("bay of a garage opening away from the street", "far_car", Vector3(node.position.x, node.position.z, node.rotation.y))
	print("AWAY-GARAGE ", opposite.leave.get("kind", "refused"), " / ", opposite.back.get("kind", "refused"))
	check(opposite.leave.has("ok") and opposite.back.has("ok"), "A garage facing away is planned or cleanly refused both ways")
	clear_extras(["far_car", "far_garage"])

	# ---- a fenced frontage with a drive gate: the car goes out through the gate
	place("fence_west", "fence", -15.75, 8.4, 0, {"style": "01", "size": "L450H120"})
	place("fence_east", "fence", 3.75, 8.4, 0, {"style": "01", "size": "L2850H120"})
	place("drive_gate", "garden_gate_drive", -12.0, 8.4, 0)
	app.world.rebuild_navigation()
	check(not app._find_item("fence_west").is_empty() and not app._find_item("drive_gate").is_empty(), "The fenced frontage and its gate stand")
	for at: Vector3 in [Vector3(-12, 3, 0), Vector3(-11.2, 3, 0)]:
		place("fenced_car", "car", at.x, at.y, at.z)
		var result: Dictionary = trial("fenced frontage car at %s" % str(at), "fenced_car", Vector3(at.x, at.y, deg_to_rad(at.z)))
		check(bool(result.leave.ok) and bool(result.back.ok), "A fenced yard's car leaves and returns through the gate at %s" % str(at))
		if bool(result.leave.ok):
			for pose: Vector3 in Path.sample(result.leave.path, .1).poses:
				if absf(pose.y - 8.4) < .06:
					check(pose.x > -13.5 + .9 and pose.x < -10.5 - .9 and absf(cos(pose.z)) >= Planner.GATE_ALIGN - .01, "It crosses the fence line only inside the gate, square to it (x %.2f heading %.0f)" % [pose.x, rad_to_deg(pose.z)])
		clear_extras(["fenced_car"])
	place("fenced_car", "car", -3.0, 2.0, 0)
	var shut: Dictionary = trial("a car far from the gate", "fenced_car", Vector3(-3, 2, 0))
	check(not bool(shut.leave.ok) or swept_clear(shut.leave.path, 1.0, obstacles(Planner.scene_from_world(app.world, "fenced_car"), Vector3(-3, 2, 0))), "A car the gate cannot serve is refused or kept clear of the fence")
	clear_extras(["fenced_car", "fence_west", "fence_east", "drive_gate"])

	# ---- the delivery van parked at the kerb is driven around
	app.world.show_delivery_van()
	place("van_car", "car", -13, 6.9, 0)
	var van_scene: Dictionary = Planner.scene_from_world(app.world, "van_car")
	check((van_scene.street as Array).size() >= 1, "The parked delivery van is in the street scene")
	var van_result: Dictionary = trial("with the delivery van parked", "van_car", Vector3(-13, 6.9, 0))
	var van_rect: Rect2 = (van_scene.street as Array)[0]
	check(bool(van_result.leave.ok) and swept_clear(van_result.leave.path, 1.0, [van_rect]), "The departure drives round the delivery van")
	check(bool(van_result.back.ok) and swept_clear(van_result.back.path, 1.0, [van_rect]), "The arrival drives round the delivery van")
	app.world.hide_delivery_van()
	clear_extras(["van_car"])

	times.sort()
	var median: float = times[times.size() / 2]
	print("ROUTE_TIMES median %.1f ms worst %.1f ms over %d plans" % [median, times[times.size() - 1], times.size()])
	check(median < 150.0 and times[times.size() - 1] < 900.0, "Real-lot plans cost milliseconds (median %.1f, worst %.1f ms)" % [median, times[times.size() - 1]])
	print("VEHICLE_ROUTES %d checks, %d failures; plans %s" % [checks, failures.size(), str(tally)])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
