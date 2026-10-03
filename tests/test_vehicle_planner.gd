extends SceneTree
## The route planner on streets made of rectangles: leaving forward or, only when it
## must, in reverse; coming home to the exact parked pose; gates crossed only
## through their gap; large cars; a van at the kerb; four-bay garages; cars that
## queue for each other. Collisions are measured here independently of the
## planner, by sweeping the exact body along the path.
const Path = preload("res://scripts/vehicle_path.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Road = preload("res://scripts/road.gd")
var checks: int = 0
var failures: Array[String] = []
var times: Array[float] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
		print("FAIL ", message)

func gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))

func house() -> Array:
	return [Rect2(-6.12, -5.12, 12.24, .16), Rect2(-6.12, 4.96, 12.24, .16), Rect2(-6.12, -5.12, .16, 10.24), Rect2(5.96, -5.12, .16, 10.24)]

func lot() -> Rect2:
	return Rect2(-18, -12, 36, 21)

## Independent exact test: does a yawed body overlap an axis-aligned rectangle?
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

func swept_clear(path: Dictionary, car_scale: float, rects: Array) -> bool:
	var length: float = Path.length_of(path)
	var s: float = 0.0
	while s <= length + .05:
		var pose: Vector3 = Path.pose_at_distance(path, minf(s, length))
		for rect: Rect2 in rects:
			if overlaps(pose.x, pose.y, pose.z, .91 * car_scale, 2.1 * car_scale, rect): return false
		s += .1
	return true

func max_curvature(path: Dictionary) -> float:
	var worst: float = 0.0
	for seg: Array in path.segs: worst = maxf(worst, absf(float(seg[0])))
	return worst

func plan_timed(call: Callable) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var plan: Dictionary = call.call()
	times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	return plan

## Everything a departure must satisfy; returns the plan.
func check_departure(label: String, scene: Dictionary, rects: Array, home: Vector3, car_scale: float = 1.0) -> Dictionary:
	var plan: Dictionary = plan_timed(func() -> Dictionary: return Planner.plan_departure(scene, home, car_scale))
	if not bool(plan.ok): return plan
	var path: Dictionary = plan.path
	check(Path.path_error(path) == "", "%s: the departure is a valid saved route (%s)" % [label, Path.path_error(path)])
	var start: Vector3 = Path.start_pose(path)
	check(Vector2(start.x - home.x, start.y - home.y).length() < 1e-3 and gap(start.z, home.z) < 1e-3, "%s: it starts on the parked pose" % label)
	var end: Vector3 = Path.end_pose(path)
	var sign: float = Road.lane_sign_for_yaw(end.z)
	check(not is_zero_approx(sign), "%s: it ends heading along the street" % label)
	check(gap(end.z, Road.lane_yaw(sign)) < deg_to_rad(1.0), "%s: it ends square to the lane (yaw %.1f)" % [label, rad_to_deg(end.z)])
	check(absf(end.y - Planner._lane_z(sign, car_scale)) < .05, "%s: it ends in the lane that matches its heading (z %.2f, %s)" % [label, end.y, "near" if sign > 0 else "far"])
	check(sign * end.x >= Road.EXIT_X - .6, "%s: it leaves the view along the lane (x %.1f)" % [label, end.x])
	check(max_curvature(path) <= 1.0 / (Planner.TURN_RADIUS * car_scale) + 1e-6, "%s: no turn is tighter than the car can make" % label)
	var gears: Array = []
	for seg: Array in path.segs: gears.append(int(seg[2]))
	if str(plan.kind) == "forward": check(not gears.has(-1) and int(plan.cusps) == 0, "%s: a forward departure never reverses" % label)
	else: check(gears[0] == -1 and int(plan.cusps) == 1, "%s: a reverse departure has exactly one cusp (%d)" % [label, int(plan.cusps)])
	check(swept_clear(path, car_scale, rects), "%s: the swept body touches nothing" % label)
	# it crosses the lot's front edge inside the lot's width
	var crossing: float = INF
	var samples: Dictionary = Path.sample(path, .2)
	for pose: Vector3 in samples.poses:
		if pose.y >= 9.0: crossing = pose.x; break
	check(absf(crossing) <= 18.0 + 4.0, "%s: it crosses the frontage within the public strip by the lot (x %.1f)" % [label, crossing])
	return plan

func check_arrival(label: String, scene: Dictionary, rects: Array, home: Vector3, car_scale: float = 1.0) -> Dictionary:
	var plan: Dictionary = plan_timed(func() -> Dictionary: return Planner.plan_arrival(scene, home, car_scale))
	if not bool(plan.ok): return plan
	var path: Dictionary = plan.path
	check(Path.path_error(path) == "", "%s: the arrival is a valid saved route" % label)
	var end: Vector3 = Path.end_pose(path)
	check(Vector2(end.x - home.x, end.y - home.y).length() < .01, "%s: it ends on the parking spot within a centimetre (%.4f m)" % [label, Vector2(end.x - home.x, end.y - home.y).length()])
	check(gap(end.z, home.z) < deg_to_rad(.5), "%s: it ends facing exactly as parked (%.3f deg)" % [label, rad_to_deg(gap(end.z, home.z))])
	var start: Vector3 = Path.start_pose(path)
	var sign: float = Road.lane_sign_for_yaw(start.z)
	check(not is_zero_approx(sign) and absf(start.y - Planner._lane_z(sign, car_scale)) < .05, "%s: it comes along the lane that matches its heading (z %.2f)" % [label, start.y])
	check(absf(start.x + sign * Road.EXIT_X) < 1.0 or absf(start.x) >= Road.EXIT_X - 8.0, "%s: it starts at the edge of the view" % label)
	check(int(path.segs[0][2]) == 1 and absf(float(path.segs[0][0])) < 1e-9, "%s: it begins as a straight run along the lane" % label)
	var cusps: int = Path.cusps(path)
	if str(plan.kind) == "forward_in": check(cusps == 0, "%s: coming in forward has no cusp" % label)
	else: check(cusps == 1, "%s: reversing in has exactly one cusp" % label)
	check(swept_clear(path, car_scale, rects), "%s: the swept body touches nothing" % label)
	return plan

func run() -> void:
	var rects: Array = house()
	var scene: Dictionary = Planner.make_scene(lot(), rects)
	var around: Array = (scene.solid as Array) + (scene.soft as Array)  # the walls and the lot's hedged edges
	var table: Array = [
		{"label": "east-facing yard car (A)", "home": Vector3(-9, 6, PI * .5)},
		{"label": "south-facing yard car (B)", "home": Vector3(-12, 3, 0)},
		{"label": "north-facing yard car (C)", "home": Vector3(-12, 4, PI)},
		{"label": "west-facing yard car (D)", "home": Vector3(-9, 7, -PI * .5)},
		{"label": "east-facing east yard car (E)", "home": Vector3(12, 6, PI * .5)},
		{"label": "south-facing east yard car (F)", "home": Vector3(11, 2, 0)},
		{"label": "front-yard car parallel to the street", "home": Vector3(-2.5, 7.6, PI * .5)},
		{"label": "front-corner car facing the street", "home": Vector3(-13, 6.9, 0)},
		{"label": "beside the house, facing it", "home": Vector3(10, 2, -PI * .5)},
		{"label": "beside the house, street-facing", "home": Vector3(10, 0, 0)},
		{"label": "back garden, west-facing", "home": Vector3(-11, -9, -PI * .5)},
		{"label": "behind the house, facing it", "home": Vector3(0, -9, 0)},
	]
	var kinds: Dictionary = {}
	for row: Dictionary in table:
		var home: Vector3 = row.home
		var leave: Dictionary = check_departure(str(row.label), scene, around, home)
		var back: Dictionary = check_arrival(str(row.label), scene, around, home)
		kinds[str(row.label)] = [str(leave.get("kind", "none")), str(back.get("kind", "none"))]
	print("PLANS ", kinds)
	check(kinds["south-facing yard car (B)"][0] == "forward" and kinds["south-facing yard car (B)"][1] == "reverse_in", "A street-facing car leaves forward and backs in")
	check(kinds["east-facing yard car (A)"][0] == "forward" and kinds["east-facing yard car (A)"][1] == "forward_in", "A car parallel to the street leaves and comes home forward")
	check(kinds["north-facing yard car (C)"][0] == "reverse" and kinds["north-facing yard car (C)"][1] == "forward_in", "A car facing away from the street backs out and drives in forward")
	check(kinds["beside the house, facing it"][0] == "reverse" and kinds["beside the house, facing it"][1] == "forward_in", "A car facing the house wall backs out and drives in forward")
	check(kinds["front-corner car facing the street"][0] == "forward" and kinds["front-corner car facing the street"][1] == "reverse_in", "A front-corner car facing the street leaves forward and backs in")
	for label: String in kinds:
		if label.begins_with("behind the house"): check(kinds[label][0] == "none" and kinds[label][1] == "none", "A car directly behind the house, facing it, is cleanly refused: it has no one-turn way to the road")
		else: check(kinds[label][0] != "none" and kinds[label][1] != "none", "%s has both a departure and an arrival" % label)

	# ---- a mirror pair: the arrival retraces the departure's geometry
	var home := Vector3(-12, 3, 0)
	var leaving: Dictionary = Planner.plan_departure(scene, home)
	var from_departure: Dictionary = Planner.arrival_from_departure(leaving.path)
	var end: Vector3 = Path.end_pose(from_departure)
	check(Path.path_error(from_departure) == "" and Vector2(end.x - home.x, end.y - home.y).length() < .01 and gap(end.z, home.z) < deg_to_rad(.5), "A departure played backwards is a valid arrival on the same spot")

	# ---- determinism and speed
	var first: String = JSON.stringify(Planner.plan_departure(scene, home).path)
	var second: String = JSON.stringify(Planner.plan_departure(Planner.make_scene(lot(), rects), home).path)
	check(first == second, "The same street and car always give the same route")
	times.sort()
	var median: float = times[times.size() / 2]
	check(median < 120.0 and times[times.size() - 1] < 600.0, "Plans cost milliseconds (median %.1f ms, worst %.1f ms over %d plans)" % [median, times[times.size() - 1], times.size()])

	# ---- larger cars: a route or a clean refusal, never a clipped one
	for car_scale: float in [1.45, 2.0]:
		for row: Dictionary in table.slice(0, 6):
			var leave: Dictionary = check_departure("x%s %s" % [str(car_scale), str(row.label)], scene, around, row.home, car_scale)
			var back: Dictionary = check_arrival("x%s %s" % [str(car_scale), str(row.label)], scene, around, row.home, car_scale)
			if not bool(leave.get("ok", false)): check(leave.has("error"), "A refused large departure says why")
			if not bool(back.get("ok", false)): check(back.has("error"), "A refused large arrival says why")
	var medium: Dictionary = Planner.plan_departure(scene, Vector3(-12, 3, 0), 1.45)
	check(bool(medium.ok), "A medium car in the west yard still finds its way out")

	# ---- a house wall in the only way out: a clean refusal
	var boxed: Dictionary = Planner.make_scene(lot(), rects + [Rect2(-18, 2.0, 36.0, .2), Rect2(-18, 7.2, 36.0, .2)])
	var refused: Dictionary = Planner.plan_departure(boxed, Vector3(-12, 5, 0))
	check(not bool(refused.ok) and str(refused.get("error", "")) != "", "A car walled in on every side is cleanly refused")

	# ---- a car cannot leave through the hedge, whichever way it faces
	for yaw: float in [0.0, PI * .5, PI, -PI * .5]:
		var plan: Dictionary = Planner.plan_departure(scene, Vector3(-15.8, 0.0, yaw))
		if bool(plan.ok):
			var worst_x: float = 0.0
			for pose: Vector3 in Path.sample(plan.path, .2).poses:
				if pose.y < 7.4: worst_x = maxf(worst_x, absf(pose.x))
			check(worst_x <= 18.0 - Planner.SIDE_CLEARANCE + .0001, "A car at the west hedge (yaw %d) never crosses it (reach %.2f)" % [roundi(rad_to_deg(yaw)), worst_x])

	# ---- the delivery van at the kerb is driven around, and the car still gets out
	var van: Rect2 = Planner.oriented_box_rect(Vector3(0, 0, Road.VAN_Z), PI * .5, .91, 2.1)
	var with_van: Dictionary = Planner.make_scene(lot(), rects, [], [van])
	var driven: Dictionary = check_departure("with the van parked", with_van, around + [van], Vector3(-13, 6.9, 0))
	check(bool(driven.ok), "A car leaves past the delivery van")
	check(swept_clear(driven.path, 1.0, [van]), "The route never touches the van")
	var arrived: Dictionary = check_arrival("with the van parked", with_van, around + [van], Vector3(-13, 6.9, 0))
	check(bool(arrived.ok) and swept_clear(arrived.path, 1.0, [van]), "A car comes home past the delivery van")

	# ---- gates: crossed through the gap, square to the leaf
	var fence: Array = [Rect2(-18, 8.34, 4.5, .12), Rect2(-10.5, 8.34, 28.5, .12)]
	var gate: Dictionary = Planner.gate(Vector2(-12, 8.4), 0.0, 3.0)
	var gated: Dictionary = Planner.make_scene(lot(), rects + fence, [gate])
	var gated_rects: Array = around + fence
	for row: Dictionary in [{"label": "in line with the gate", "home": Vector3(-12, 3, 0)}, {"label": "beside the gate's line", "home": Vector3(-11.2, 3, 0)}, {"label": "offset behind the gate", "home": Vector3(-9.5, 2, 0)}]:
		var out: Dictionary = check_departure("fenced yard, " + str(row.label), gated, gated_rects, row.home)
		check(bool(out.ok), "A fenced yard's car leaves by the gate (%s)" % row.label)
		if bool(out.ok):
			var at_gate: float = 0.0
			for pose: Vector3 in Path.sample(out.path, .1).poses:
				if absf(pose.y - 8.4) < .06:
					at_gate = pose.x
					check(absf(cos(pose.z)) >= Planner.GATE_ALIGN - .01, "It crosses the gate line square to the leaf (heading %.0f deg)" % rad_to_deg(pose.z))
			check(at_gate >= -13.5 + 1.0 and at_gate <= -10.5 - 1.0, "It crosses the fence line inside the gate's gap (x %.2f)" % at_gate)
		var inward: Dictionary = check_arrival("fenced yard, " + str(row.label), gated, gated_rects, row.home)
		check(bool(inward.ok), "A fenced yard's car comes home through the gate (%s)" % row.label)
	var shut_in: Dictionary = Planner.plan_departure(gated, Vector3(-9, 6, PI * .5))
	check(not bool(shut_in.ok) or swept_clear(shut_in.path, 1.0, gated_rects), "A car the gate cannot serve is refused or kept clear of the fence")
	var closed_fence: Array = [Rect2(-18, 8.34, 36.0, .12)]
	var no_gate: Dictionary = Planner.plan_departure(Planner.make_scene(lot(), rects + closed_fence), Vector3(-12, 3, 0))
	check(not bool(no_gate.ok), "With the frontage fenced shut and no gate, the car has no way out")

	# ---- a four-bay garage on the street side: every bay, every neighbour parked
	var garage_walls: Array = [Rect2(-15.74, 3.265, 9.08, .12), Rect2(-15.74, 3.205, .12, 5.79), Rect2(-6.74, 3.205, .12, 5.79), Rect2(-11.26, 3.205, .12, 5.79)]
	var bays: Array = [Vector3(-14.4, 6.45, 0), Vector3(-12.3, 6.45, 0), Vector3(-10.1, 6.45, 0), Vector3(-8.0, 6.45, 0)]
	for index: int in 4:
		var neighbours: Array = []
		for other: int in 4:
			if other != index: neighbours.append(Planner.oriented_box_rect(Vector3(bays[other].x, 0, bays[other].y), 0.0, .91, 2.1))
		var garage_scene: Dictionary = Planner.make_scene(lot(), rects + garage_walls + neighbours)
		var obstacles: Array = around + garage_walls + neighbours
		var leave: Dictionary = check_departure("bay %d of a street-facing garage" % index, garage_scene, obstacles, bays[index])
		check(bool(leave.ok) and str(leave.kind) == "forward", "Bay %d drives forward out of the garage onto the road" % index)
		var back: Dictionary = check_arrival("bay %d of a street-facing garage" % index, garage_scene, obstacles, bays[index])
		check(bool(back.ok) and str(back.kind) == "reverse_in", "Bay %d is backed into" % index)
	# a garage that opens away from the street, flush with the front: reversing or refusal
	var away_garage: Array = [Rect2(-15.74, 8.86, 9.08, .12), Rect2(-15.74, 3.2, .12, 5.79), Rect2(-6.74, 3.2, .12, 5.79), Rect2(-11.26, 3.2, .12, 5.79)]
	var away_scene: Dictionary = Planner.make_scene(lot(), rects + away_garage)
	var away: Dictionary = Planner.plan_departure(away_scene, Vector3(-12.3, 5.75, PI))
	check(not bool(away.ok) or swept_clear(away.path, 1.0, around + away_garage), "A garage opening away from the street is refused or cleanly planned (%s)" % str(away.get("kind", "refused")))

	# ---- queueing: cars that would meet wait, the rest do not
	# each car's plan treats the other, parked, as an obstacle, as in the game
	var west_rect: Rect2 = Planner.oriented_box_rect(Vector3(-12, 0, 3), 0.0, .91, 2.1)
	var yard_rect: Rect2 = Planner.oriented_box_rect(Vector3(-14.5, 0, 7.5), PI * .5, .91, 2.1)
	var west: Dictionary = Planner.plan_departure(Planner.make_scene(lot(), rects + [yard_rect]), Vector3(-12, 3, 0))
	var yard: Dictionary = Planner.plan_departure(Planner.make_scene(lot(), rects + [west_rect]), Vector3(-14.5, 7.5, PI * .5))
	if not bool(west.ok) or not bool(yard.ok):
		check(false, "The queueing fixtures both have routes")
		print("VEHICLE_PLANNER %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	var meeting: Array = [{"path": west.path, "time": 0.0, "scale": 1.0, "stays": false}]
	var wait: float = Planner.hold_seconds(yard.path, 1.0, meeting)
	var poses_a: PackedVector3Array = Planner.poses_of(west.path, 0.0, .05)
	var poses_b: PackedVector3Array = Planner.poses_of(yard.path, 0.0, .05)
	var together: int = Planner.overlap_count(poses_a, false, 1.0, poses_b, false, 1.0, 0)
	var after_wait: int = Planner.overlap_count(poses_a, false, 1.0, poses_b, false, 1.0, roundi(wait / .05))
	check(wait > 0.0 and together > 0, "Two cars whose routes cross would overlap if they left together (%d moments), so the second waits %.2f s" % [together, wait])
	check(after_wait == 0, "After the wait their swept bodies never overlap (%d moments)" % after_wait)
	var apart: Dictionary = Planner.plan_departure(scene, Vector3(12, 6, PI * .5))
	check(Planner.hold_seconds(apart.path, 1.0, meeting) == 0.0, "Cars whose routes never meet do not wait")
	var returning: Dictionary = Planner.plan_arrival(Planner.make_scene(lot(), rects + [yard_rect]), Vector3(-12, 3, 0))
	var coming_and_going: float = Planner.hold_seconds(returning.path, 1.0, [{"path": yard.path, "time": 0.0, "scale": 1.0, "stays": false}], true)
	var poses_r: PackedVector3Array = Planner.poses_of(returning.path, 0.0, .05)
	var poses_y: PackedVector3Array = Planner.poses_of(yard.path, 0.0, .05)
	check(Planner.overlap_count(poses_y, false, 1.0, poses_r, true, 1.0, roundi(coming_and_going / .05)) == 0, "A car arriving while another leaves never overlaps it (waited %.2f s)" % coming_and_going)
	var capped: float = Planner.hold_seconds(west.path, 1.0, [{"path": west.path, "time": 0.0, "scale": 1.0, "stays": true}], false, 3.0)
	check(capped <= 3.0, "A wait is capped at the limit it is given")

	print("VEHICLE_PLANNER %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

