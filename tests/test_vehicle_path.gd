extends SceneTree
## The route maths a car is driven by, with no app and no scene: Dubins words
## integrate to the pose they promise, the pace table respects its limits, a pose
## is a pure function of the saved path and the time, and a malformed saved route
## is refused.
const Path = preload("res://scripts/vehicle_path.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
		print("FAIL ", message)

func angle_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))

func run() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 20260502
	# ---- every word reaches the pose it was asked for, forward and in reverse
	var worst_position: float = 0.0
	var worst_yaw: float = 0.0
	var solved: int = 0
	var words: Dictionary = {}
	for index: int in 600:
		var gear: int = 1 if index % 3 != 0 else -1
		var a := Vector3(rng.randf_range(-20, 20), rng.randf_range(-12, 14), rng.randf_range(-PI, PI))
		var b := Vector3(rng.randf_range(-20, 20), rng.randf_range(-12, 14), rng.randf_range(-PI, PI))
		var rho: float = rng.randf_range(2.0, 7.5)
		var found: Dictionary = Path.dubins(a.x, a.y, a.z, b.x, b.y, b.z, rho, gear)
		if found.is_empty(): continue
		solved += 1
		words[str(found.word)] = int(words.get(str(found.word), 0)) + 1
		var path: Dictionary = Path.create(a.x, a.y, a.z)
		Path.add_all(path, found.segs)
		var end: Vector3 = Path.end_pose(path)
		worst_position = maxf(worst_position, Vector2(end.x - b.x, end.y - b.y).length())
		worst_yaw = maxf(worst_yaw, angle_gap(end.z, b.z))
		check(absf(Path.length_of(path) - float(found.length)) < 1e-6, "Word length equals its segments (%s)" % str(found.word))
		if gear < 0:
			for seg: Array in path.segs: check(int(seg[2]) == -1, "A reverse word has only reverse segments")
	check(solved >= 590, "Almost every random pose pair has a word (%d of 600)" % solved)
	check(worst_position < 1e-3, "Every word ends on its goal position (worst %s m)" % str(worst_position))
	check(worst_yaw < 1e-3, "Every word ends on its goal heading (worst %s rad)" % str(worst_yaw))
	check(words.size() >= 5, "All the word families occur (%s)" % str(words))

	# ---- a route with a bend, a reverse stub and a cusp
	var path: Dictionary = Path.create(-9.0, 6.0, PI * .5)
	Path.add(path, 0.0, 3.0, 1)
	Path.add(path, -1.0 / 3.7, 5.8, 1)
	Path.add(path, 1.0 / 3.7, 5.8, 1)
	Path.add(path, 0.0, 14.0, 1)
	path["v1"] = Path.V_MAX
	check(Path.path_error(path) == "", "A built route validates: " + Path.path_error(path))
	var prof: Dictionary = Path.profile(path)
	var total_time: float = Path.duration(path)
	check(total_time > 4.0 and total_time < 14.0, "The drive takes a believable time (%.2f s)" % total_time)
	var start_state: Dictionary = Path.state_at(path, 0.0)
	check(Vector2(float(start_state.x) + 9.0, float(start_state.z) - 6.0).length() < 1e-5 and angle_gap(float(start_state.yaw), PI * .5) < 1e-5, "The route starts exactly on the parked pose")
	check(absf(float(start_state.steer)) < 1e-9, "The wheels start straight")
	var last: Dictionary = Path.state_at(path, total_time + 3.0)
	var end_pose: Vector3 = Path.end_pose(path)
	check(Vector2(float(last.x) - end_pose.x, float(last.z) - end_pose.y).length() < 1e-6, "Past its end the car stays at the end of the route")

	# ---- continuity: no jump in position, no instantaneous heading change, bounded yaw rate
	var dt: float = 1.0 / 60.0
	var previous: Dictionary = Path.state_at(path, 0.0)
	var max_step: float = 0.0
	var max_yaw_rate: float = 0.0
	var max_steer_rate: float = 0.0
	var max_speed: float = 0.0
	var steered: float = 0.0
	var time: float = dt
	while time < total_time + .2:
		var now: Dictionary = Path.state_at(path, time)
		max_step = maxf(max_step, Vector2(float(now.x) - float(previous.x), float(now.z) - float(previous.z)).length())
		max_yaw_rate = maxf(max_yaw_rate, angle_gap(float(now.yaw), float(previous.yaw)) / dt)
		max_steer_rate = maxf(max_steer_rate, absf(float(now.steer) - float(previous.steer)) / dt)
		max_speed = maxf(max_speed, Vector2(float(now.x) - float(previous.x), float(now.z) - float(previous.z)).length() / dt)
		steered = maxf(steered, absf(float(now.steer)))
		previous = now
		time += dt
	check(max_step < Path.V_MAX * dt * 1.15, "The car never jumps (largest step %.3f m per frame)" % max_step)
	check(max_speed <= Path.V_MAX + .3, "Speed never exceeds the limit (%.2f m/s)" % max_speed)
	check(rad_to_deg(max_yaw_rate) < 60.0, "The yaw rate is bounded (%.1f deg/s)" % rad_to_deg(max_yaw_rate))
	check(rad_to_deg(max_steer_rate) < 140.0, "The wheels turn smoothly (%.1f deg/s)" % rad_to_deg(max_steer_rate))
	check(rad_to_deg(steered) > 12.0, "The front wheels visibly steer in the bend (%.1f deg)" % rad_to_deg(steered))
	# the heading follows the tangent: compare with the unfiltered heading at the same distance
	var tangent_gap: float = 0.0
	time = 0.0
	while time < total_time:
		var now: Dictionary = Path.state_at(path, time)
		tangent_gap = maxf(tangent_gap, angle_gap(float(now.yaw), Path.pose_at_distance(path, float(now.s)).z))
		time += .05
	check(rad_to_deg(tangent_gap) < 7.0, "The shown heading follows the path tangent (%.1f deg)" % rad_to_deg(tangent_gap))

	# ---- pace: slow in the bends, standing still at a cusp and at a stop
	var speed: PackedFloat64Array = prof.speed
	var distances: PackedFloat64Array = prof.distance
	var bend_ok: bool = true
	for index: int in speed.size():
		var k: float = absf(Path.curvature_at(prof, distances[index]))
		if k > 1e-6 and speed[index] > sqrt(Path.A_LATERAL / k) + 1e-6: bend_ok = false
	check(bend_ok, "Speed in a bend never exceeds sqrt(A_LATERAL / |k|)")
	check(speed[0] == 0.0, "The car starts from rest")
	var reverse_path: Dictionary = Path.create(0.0, 0.0, 0.0)
	Path.add(reverse_path, 0.0, 4.0, -1)
	Path.add(reverse_path, 0.0, 6.0, 1)
	var reverse_prof: Dictionary = Path.profile(reverse_path)
	check((reverse_prof.cusp_samples as Array).size() == 1, "A reverse then forward route has one cusp")
	check(Path.cusps(reverse_path) == 1, "cusps() counts one")
	var cusp_speed: float = (reverse_prof.speed as PackedFloat64Array)[int(reverse_prof.cusp_samples[0])]
	check(cusp_speed == 0.0, "The car stands still at the cusp")
	var reverse_max: float = 0.0
	for index: int in range(0, int(4.0 / Path.STEP)): reverse_max = maxf(reverse_max, (reverse_prof.speed as PackedFloat64Array)[index])
	check(reverse_max <= Path.V_REVERSE + 1e-6, "Reversing is slow (%.2f m/s)" % reverse_max)
	var mid_reverse: Dictionary = Path.state_at(reverse_path, 1.2)
	check(int(mid_reverse.gear) == -1 and float(mid_reverse.spin) < -.1, "Reversing rolls the wheels backwards (spin %.2f)" % float(mid_reverse.spin))
	var forward_state: Dictionary = Path.state_at(path, total_time * .6)
	check(int(forward_state.gear) == 1 and float(forward_state.spin) > 1.0, "Driving forward rolls them forwards")

	# ---- a pure function of the saved numbers
	var copy: Dictionary = JSON.parse_string(JSON.stringify(path))
	Path._cache.clear()
	check(is_equal_approx(Path.duration(copy), total_time), "The duration survives a JSON round trip (%.6f vs %.6f)" % [Path.duration(copy), total_time])
	var a: Dictionary = Path.state_at(path, 3.3)
	var b: Dictionary = Path.state_at(copy, 3.3)
	check(absf(float(a.x) - float(b.x)) < 1e-9 and absf(float(a.z) - float(b.z)) < 1e-9 and absf(float(a.yaw) - float(b.yaw)) < 1e-9, "The pose at a time survives a JSON round trip")
	# reversed(reversed(p)) == p
	var twice: Dictionary = Path.reversed(Path.reversed(path))
	var identical: bool = Vector3(float(twice.start[0]), float(twice.start[1]), float(twice.start[2])).distance_to(Path.start_pose(path)) < 1e-6 and twice.segs.size() == path.segs.size()
	for index: int in twice.segs.size():
		for part: int in 3: identical = identical and absf(float(twice.segs[index][part]) - float(path.segs[index][part])) < 1e-9
	check(identical, "Reversing a route twice gives the route")
	var back: Dictionary = Path.reversed(path)
	var back_end: Vector3 = Path.end_pose(back)
	check(Vector2(back_end.x + 9.0, back_end.y - 6.0).length() < 1e-6 and angle_gap(back_end.z, PI * .5) < 1e-6, "The reversed route comes back to where the first began")
	check(int(back.segs[0][2]) == -1, "Driven the other way, a forward route is a reverse one")

	# ---- the old straight run, exactly
	var home := Transform3D(Basis(Vector3.UP, PI * .5), Vector3(-9, .16, 6))
	var legacy: Vector3 = Path.legacy_position(home, -1.0, 2.0, false)
	var expected: Vector3 = home.origin + home.basis.z.normalized() * -1.0 * 22.0 * smoothstep(0.0, 1.0, 2.0 / 4.0)
	check(legacy.distance_to(expected) < 1e-9, "The legacy run is the old formula")
	check(Path.legacy_position(home, 1.0, 9.0, true).distance_to(home.origin) < 1e-9, "The legacy return ends at home")

	# ---- a malformed saved route is refused
	var bad: Dictionary = path.duplicate(true)
	check(Path.path_error(bad) == "", "The intact route is accepted")
	for broken: String in ["nan_curve", "huge_length", "zero_length", "bad_gear", "too_many", "not_finite_start", "no_segs", "huge_total", "bad_speed", "bad_version", "wide_curve"]:
		bad = path.duplicate(true)
		match broken:
			"nan_curve": bad.segs[1][0] = NAN
			"huge_length": bad.segs[1][1] = 1.0e9
			"zero_length": bad.segs[1][1] = 0.0
			"bad_gear": bad.segs[1][2] = 0
			"too_many":
				for more: int in 12: bad.segs.append([0.0, 1.0, 1])
			"not_finite_start": bad.start[0] = INF
			"no_segs": bad.segs = []
			"huge_total":
				for more: int in 4: bad.segs.append([0.0, 190.0, 1])
				bad.segs = bad.segs.slice(0, 9)
			"bad_speed": bad["v1"] = 99.0
			"bad_version": bad["v"] = 2
			"wide_curve": bad.segs[1][0] = 5.0
		check(Path.path_error(bad) != "", "A malformed route is refused: " + broken)
	check(Path.path_error("nope") != "" and Path.path_error({}) != "" and Path.path_error({"v": 1, "start": [0, 0], "segs": []}) != "", "Non-routes are refused")

	print("VEHICLE_PATH %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
