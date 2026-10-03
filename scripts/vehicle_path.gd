extends RefCounted
class_name LifeVehiclePath
## A car's route as plain, saveable data, and the pure functions that play it.
##
## A path is {"v": 1, "start": [x, z, yaw], "segs": [[curvature, length, gear], ...]}
## with optional "v0" / "v1", the speeds at its two ends (zero means standing
## still). A car facing yaw looks along (sin yaw, cos yaw); a segment of
## curvature k turns the car left while k > 0 (yaw grows), gear +1 drives it
## forward and -1 reverses it. Integrating a segment is exact, so the pose at any
## distance is a pure function of the saved numbers, and the pose at any time is a
## pure function of the path and that time: nothing about a journey is stored but
## the segments.
##
## Dubins words (a straight and two arcs of the tightest turn the car can make)
## give the shortest drivable route between two poses; the planner picks among
## them, the profile below paces them (slow in the bends, standing still at a
## cusp where forward becomes reverse) and pose_at/state_at play them.

const VERSION: int = 1
## Spacing of the speed table, in metres.
const STEP: float = .1
const V_MAX: float = 8.5
const V_REVERSE: float = 2.2
const A_ACCEL: float = 3.0
const A_BRAKE: float = 3.6
## Sideways acceleration a bend may ask for: speed in a bend is sqrt(A_LATERAL / |k|).
const A_LATERAL: float = 3.0
const CUSP_DWELL: float = .4
## The yaw a car shows is the heading averaged over this stretch of road, so a
## bend begins and ends without a kink in how fast the car is turning.
const YAW_WINDOW: float = .9
const STEER_WINDOW: float = 2.0
const MAX_STEER: float = .62
const MAX_SEGMENTS: int = 10
const MAX_LENGTH: float = 320.0
const MAX_CURVATURE: float = 1.0
const WHEELBASE: float = 2.6
## What a path without a plan did: 22 m along the car's own axis in 4 s.
const LEGACY_SECONDS: float = 4.0
const LEGACY_DISTANCE: float = 22.0

static var _cache: Dictionary = {}

# ------------------------------------------------------------------ building

static func create(x: float, z: float, yaw: float) -> Dictionary:
	return {"v": VERSION, "start": [x, z, yaw], "segs": []}


## Add a segment; zero-length ones are dropped and a run of equal ones is merged.
static func add(path: Dictionary, curvature: float, length: float, gear: int) -> void:
	if length < 1e-4: return
	var segs: Array = path.segs
	if not segs.is_empty():
		var last: Array = segs[segs.size() - 1]
		if int(last[2]) == gear and absf(float(last[0]) - curvature) < 1e-9:
			last[1] = float(last[1]) + length
			return
	segs.append([curvature, length, gear])


static func add_all(path: Dictionary, segments: Array) -> void:
	for seg: Array in segments: add(path, float(seg[0]), float(seg[1]), int(seg[2]))


static func length_of(path: Dictionary) -> float:
	var total: float = 0.0
	for seg: Array in path.segs: total += float(seg[1])
	return total


## How far the car turns in all, in radians, whichever way it turns.
static func turning(path: Dictionary) -> float:
	var total: float = 0.0
	for seg: Array in path.segs: total += absf(float(seg[0])) * float(seg[1])
	return total


static func cusps(path: Dictionary) -> int:
	var count: int = 0
	var segs: Array = path.segs
	for index: int in range(1, segs.size()):
		if int(segs[index][2]) != int(segs[index - 1][2]): count += 1
	return count


## The same road driven the other way round: the segments backwards, every gear
## flipped, so a car that left in reverse comes home nose first.
static func reversed(path: Dictionary) -> Dictionary:
	var end: Vector3 = end_pose(path)
	var out: Dictionary = create(end.x, end.y, end.z)
	var segs: Array = path.segs
	for index: int in range(segs.size() - 1, -1, -1):
		var seg: Array = segs[index]
		out.segs.append([float(seg[0]), float(seg[1]), -int(seg[2])])
	if path.has("v1"): out["v0"] = float(path.v1)
	if path.has("v0"): out["v1"] = float(path.v0)
	return out


## Where a segment of curvature k, driven for `length` in `gear`, leaves a pose.
static func advance(pose: Vector3, curvature: float, length: float, gear: int) -> Vector3:
	var yaw: float = pose.z
	if absf(curvature) < 1e-9:
		return Vector3(pose.x + sin(yaw) * length * gear, pose.y + cos(yaw) * length * gear, yaw)
	var yaw1: float = yaw + gear * curvature * length
	return Vector3(pose.x + (cos(yaw) - cos(yaw1)) / curvature, pose.y + (sin(yaw1) - sin(yaw)) / curvature, yaw1)


## A pose as Vector3(x, z, yaw).
static func start_pose(path: Dictionary) -> Vector3:
	var start: Array = path.start
	return Vector3(float(start[0]), float(start[1]), float(start[2]))


static func end_pose(path: Dictionary) -> Vector3:
	var pose: Vector3 = start_pose(path)
	for seg: Array in path.segs: pose = advance(pose, float(seg[0]), float(seg[1]), int(seg[2]))
	return pose

# -------------------------------------------------------------------- Dubins

static func _mod2pi(angle: float) -> float:
	var wrapped: float = fposmod(angle, TAU)
	return 0.0 if wrapped > TAU - 1e-9 else wrapped


## The shortest forward (or, with gear -1, reverse) route between two poses for a
## car that cannot turn tighter than `rho`: {"word", "length", "segs"}, or {} when
## none exists. `allowed` lists the words to try, empty for all six.
static func dubins(x0: float, z0: float, yaw0: float, x1: float, z1: float, yaw1: float, rho: float, gear: int = 1, allowed: PackedStringArray = PackedStringArray()) -> Dictionary:
	var h0: float = yaw0 + (PI if gear < 0 else 0.0)
	var h1: float = yaw1 + (PI if gear < 0 else 0.0)
	# Planar frame: X = z, Y = x, heading = yaw, so a left turn is counter-clockwise.
	var dx: float = z1 - z0
	var dy: float = x1 - x0
	var distance: float = sqrt(dx * dx + dy * dy)
	var d: float = distance / rho
	var theta: float = _mod2pi(atan2(dy, dx)) if distance > 1e-9 else 0.0
	var alpha: float = _mod2pi(h0 - theta)
	var beta: float = _mod2pi(h1 - theta)
	var sa: float = sin(alpha); var ca: float = cos(alpha)
	var sb: float = sin(beta); var cb: float = cos(beta)
	var cab: float = cos(alpha - beta)
	var best: Dictionary = {}
	var best_total: float = INF
	for word: String in ["LSL", "RSR", "LSR", "RSL", "RLR", "LRL"]:
		if not allowed.is_empty() and not allowed.has(word): continue
		var t: float = 0.0; var p: float = 0.0; var q: float = 0.0
		var ok: bool = false
		match word:
			"LSL":
				var p_sq: float = 2.0 + d * d - 2.0 * cab + 2.0 * d * (sa - sb)
				if p_sq >= 0.0:
					var tmp: float = atan2(cb - ca, d + sa - sb)
					t = _mod2pi(-alpha + tmp); p = sqrt(p_sq); q = _mod2pi(beta - tmp); ok = true
			"RSR":
				var p_sq: float = 2.0 + d * d - 2.0 * cab + 2.0 * d * (sb - sa)
				if p_sq >= 0.0:
					var tmp: float = atan2(ca - cb, d - sa + sb)
					t = _mod2pi(alpha - tmp); p = sqrt(p_sq); q = _mod2pi(-beta + tmp); ok = true
			"LSR":
				var p_sq: float = -2.0 + d * d + 2.0 * cab + 2.0 * d * (sa + sb)
				if p_sq >= 0.0:
					p = sqrt(p_sq)
					var tmp: float = atan2(-ca - cb, d + sa + sb) - atan2(-2.0, p)
					t = _mod2pi(-alpha + tmp); q = _mod2pi(-beta + tmp); ok = true
			"RSL":
				var p_sq: float = -2.0 + d * d + 2.0 * cab - 2.0 * d * (sa + sb)
				if p_sq >= 0.0:
					p = sqrt(p_sq)
					var tmp: float = atan2(ca + cb, d - sa - sb) - atan2(2.0, p)
					t = _mod2pi(alpha - tmp); q = _mod2pi(beta - tmp); ok = true
			"RLR":
				var tmp: float = (6.0 - d * d + 2.0 * cab + 2.0 * d * (sa - sb)) / 8.0
				if absf(tmp) <= 1.0:
					p = _mod2pi(TAU - acos(tmp))
					t = _mod2pi(alpha - atan2(ca - cb, d - sa + sb) + p * .5)
					q = _mod2pi(alpha - beta - t + p); ok = true
			"LRL":
				var tmp: float = (6.0 - d * d + 2.0 * cab + 2.0 * d * (-sa + sb)) / 8.0
				if absf(tmp) <= 1.0:
					p = _mod2pi(TAU - acos(tmp))
					t = _mod2pi(-alpha - atan2(ca - cb, d + sa - sb) + p * .5)
					q = _mod2pi(beta - alpha - t + p); ok = true
		if not ok: continue
		var total: float = (t + p + q) * rho
		if total >= best_total: continue
		best_total = total
		best = {"word": word, "length": total, "lengths": [t * rho, p * rho, q * rho]}
	if best.is_empty(): return {}
	var word: String = str(best.word)
	var lengths: Array = best.lengths
	var segs: Array = []
	for index: int in range(3):
		var kind: String = word[index]
		var curvature: float = 0.0 if kind == "S" else (1.0 / rho if kind == "L" else -1.0 / rho)
		if gear < 0: curvature = -curvature
		if float(lengths[index]) > 1e-6: segs.append([curvature, float(lengths[index]), gear])
	best["segs"] = segs
	best.erase("lengths")
	return best

# ------------------------------------------------------------------- profile

## The tables a path is played from, built once per distinct path.
static func profile(path: Dictionary) -> Dictionary:
	var key: String = str(path.get("start", [])) + str(path.get("segs", [])) + str(path.get("v0", 0.0)) + "|" + str(path.get("v1", 0.0))
	if _cache.has(key): return _cache[key]
	if _cache.size() > 40: _cache.clear()
	var built: Dictionary = _build(path)
	_cache[key] = built
	return built


static func _build(path: Dictionary) -> Dictionary:
	var segs: Array = path.segs
	var starts: Array[Vector3] = []
	var s0: PackedFloat64Array = PackedFloat64Array()
	var pose: Vector3 = start_pose(path)
	var total: float = 0.0
	for seg: Array in segs:
		starts.append(pose)
		s0.append(total)
		total += float(seg[1])
		pose = advance(pose, float(seg[0]), float(seg[1]), int(seg[2]))
	s0.append(total)
	var count: int = maxi(1, ceili(total / STEP))
	var limit := PackedFloat64Array(); limit.resize(count + 1)
	var gears := PackedInt32Array(); gears.resize(count + 1)
	var seg_index: int = 0
	for index: int in range(count + 1):
		var s: float = minf(float(index) * STEP, total)
		while seg_index < segs.size() - 1 and s > s0[seg_index + 1] + 1e-9: seg_index += 1
		var k: float = 0.0
		var gear: int = 1
		if not segs.is_empty():
			k = absf(float(segs[seg_index][0])); gear = int(segs[seg_index][2])
		# The bend ahead matters as much as the one underfoot: look one sample on.
		if not segs.is_empty() and seg_index + 1 < segs.size() and s + STEP > s0[seg_index + 1]: k = maxf(k, absf(float(segs[seg_index + 1][0])))
		var cap: float = V_MAX if gear > 0 else V_REVERSE
		if k > 1e-6: cap = minf(cap, sqrt(A_LATERAL / k))
		limit[index] = cap
		gears[index] = gear
	# Standing still at every cusp, and at an end that is not a hand-over.
	var speed := PackedFloat64Array(); speed.resize(count + 1)
	for index: int in range(count + 1): speed[index] = limit[index]
	speed[0] = minf(speed[0], float(path.get("v0", 0.0)))
	speed[count] = minf(speed[count], float(path.get("v1", 0.0)))
	var cusp_index: Array[int] = []
	for index: int in range(1, count + 1):
		if gears[index] != gears[index - 1]:
			cusp_index.append(index)
			speed[index] = 0.0
	for index: int in range(1, count + 1):
		speed[index] = minf(speed[index], sqrt(speed[index - 1] * speed[index - 1] + 2.0 * A_ACCEL * STEP))
	for index: int in range(count - 1, -1, -1):
		speed[index] = minf(speed[index], sqrt(speed[index + 1] * speed[index + 1] + 2.0 * A_BRAKE * STEP))
	var times := PackedFloat64Array(); times.resize(count + 1)
	var roll := PackedFloat64Array(); roll.resize(count + 1)
	var distances := PackedFloat64Array(); distances.resize(count + 1)
	var clock: float = 0.0
	var rolled: float = 0.0
	for index: int in range(1, count + 1):
		var s_prev: float = minf(float(index - 1) * STEP, total)
		var s_now: float = minf(float(index) * STEP, total)
		var span: float = s_now - s_prev
		var average: float = maxf(.08, (speed[index - 1] + speed[index]) * .5)
		clock += span / average
		if cusp_index.has(index): clock += CUSP_DWELL
		times[index] = clock
		rolled += span * float(gears[index])
		roll[index] = rolled
		distances[index] = s_now
	return {"segs": segs.duplicate(true), "starts": starts, "s0": s0, "length": total, "count": count, "times": times, "roll": roll,
		"distance": distances, "speed": speed, "gears": gears, "duration": clock, "cusp_samples": cusp_index}


## Seconds the whole path takes to drive.
static func duration(path: Dictionary) -> float:
	return float(profile(path).duration)


static func _segment_at(prof: Dictionary, s: float) -> int:
	var s0: PackedFloat64Array = prof.s0
	var low: int = 0
	var high: int = (prof.segs as Array).size() - 1
	while low < high:
		var mid: int = (low + high + 1) >> 1
		if s0[mid] <= s: low = mid
		else: high = mid - 1
	return low


## The unfiltered pose (x, z, yaw) after driving s metres of the path.
static func pose_at_distance(path: Dictionary, s: float) -> Vector3:
	return _raw_pose(profile(path), path, s)


static func _raw_pose(prof: Dictionary, path: Dictionary, s: float) -> Vector3:
	var segs: Array = prof.segs
	if segs.is_empty(): return start_pose(path)
	s = clampf(s, 0.0, float(prof.length))
	var index: int = _segment_at(prof, s)
	var seg: Array = segs[index]
	var local: float = clampf(s - float(prof.s0[index]), 0.0, float(seg[1]))
	return advance(prof.starts[index], float(seg[0]), local, int(seg[2]))


## Signed curvature (in the path's own convention) at distance s.
static func curvature_at(prof: Dictionary, s: float) -> float:
	var segs: Array = prof.segs
	if segs.is_empty() or s < 0.0 or s > float(prof.length): return 0.0
	return float(segs[_segment_at(prof, s)][0])


## The curvature averaged over a stretch of road, exactly: what the steering
## wheel does while the road ahead and behind blur into one another.
static func _mean_curvature(prof: Dictionary, from: float, to: float) -> float:
	var segs: Array = prof.segs
	var s0: PackedFloat64Array = prof.s0
	var sum: float = 0.0
	for index: int in segs.size():
		var overlap: float = minf(to, s0[index + 1]) - maxf(from, s0[index])
		if overlap > 0.0: sum += overlap * float(segs[index][0])
	return sum / (to - from)


static func _gear_at(prof: Dictionary, s: float) -> int:
	var segs: Array = prof.segs
	if segs.is_empty(): return 1
	return int(segs[_segment_at(prof, clampf(s, 0.0, float(prof.length)))][2])


## Distance driven by time t (clamped to the ends of the journey).
static func distance_at(prof: Dictionary, t: float) -> float:
	var count: int = int(prof.count)
	var times: PackedFloat64Array = prof.times
	if t <= 0.0: return 0.0
	if t >= times[count]: return float(prof.length)
	var low: int = 0
	var high: int = count
	while high - low > 1:
		var mid: int = (low + high) >> 1
		if times[mid] <= t: low = mid
		else: high = mid
	var span: float = times[high] - times[low]
	var fraction: float = 0.0 if span <= 1e-9 else (t - times[low]) / span
	var distances: PackedFloat64Array = prof.distance
	return lerpf(distances[low], distances[high], fraction)


static func _roll_at(prof: Dictionary, s: float) -> float:
	var count: int = int(prof.count)
	var distances: PackedFloat64Array = prof.distance
	var roll: PackedFloat64Array = prof.roll
	if s <= 0.0: return 0.0
	if s >= distances[count]: return roll[count]
	var index: int = clampi(int(floor(s / STEP)), 0, count - 1)
	var span: float = distances[index + 1] - distances[index]
	var fraction: float = 0.0 if span <= 1e-9 else (s - distances[index]) / span
	return lerpf(roll[index], roll[index + 1], fraction)


## Everything a car needs to be drawn t seconds into a path: its pose, the front
## wheels' steering angle, how far a wheel has rolled (signed: negative backing
## up) and whether it is braking or about to turn.
static func state_at(path: Dictionary, t: float, wheelbase: float = WHEELBASE) -> Dictionary:
	var prof: Dictionary = profile(path)
	var length: float = float(prof.length)
	var s: float = distance_at(prof, t)
	var raw: Vector3 = _raw_pose(prof, path, s)
	# Heading averaged along the road, tapering to nothing at either end so the
	# parked pose is exact.
	var half: float = minf(YAW_WINDOW * .5, minf(s, length - s))
	var yaw: float = raw.z
	if half > 1e-4:
		var sum: float = 0.0
		for sample: int in range(7):
			sum += _raw_pose(prof, path, s - half + half / 3.0 * float(sample)).z
		yaw = sum / 7.0
	var steer: float = clampf(atan(_mean_curvature(prof, s - STEER_WINDOW * .5, s + STEER_WINDOW * .5) * wheelbase), -MAX_STEER, MAX_STEER) * smoothstep(0.0, 1.2, minf(s, length - s))
	var ahead: float = 0.0
	for sample: int in range(1, 5):
		ahead = maxf(ahead, absf(curvature_at(prof, s + 2.0 * float(sample))))
	var index: int = clampi(int(floor(s / STEP)), 0, int(prof.count) - 1)
	var speed: PackedFloat64Array = prof.speed
	var gear: int = _gear_at(prof, s)
	var moving: bool = t > 0.0 and t < float(prof.duration)
	return {"x": raw.x, "z": raw.y, "yaw": yaw, "s": s, "gear": gear, "steer": steer, "spin": _roll_at(prof, s),
		"braking": moving and speed[index + 1] < speed[index] - 1e-6, "turning": ahead > .05 or absf(steer) > .04,
		"speed": speed[index] if moving else 0.0, "done": t >= float(prof.duration)}


## The car's transform t seconds into the path, at height y and with its own
## scale kept.
static func transform_at(path: Dictionary, t: float, y: float, car_scale: Vector3 = Vector3.ONE) -> Transform3D:
	var state: Dictionary = state_at(path, t)
	return Transform3D(Basis(Vector3.UP, float(state.yaw)) * Basis.from_scale(car_scale), Vector3(float(state.x), y, float(state.z)))


## Poses (x, z, yaw) along a path every `step` metres of it, with the gear of the
## stretch each belongs to in `gears`: what the planner sweeps a car's body along.
static func sample(path: Dictionary, step: float = .35) -> Dictionary:
	# Geometry only (no pace table), so sweeping many candidate routes stays cheap.
	var segs: Array = path.segs
	var length: float = length_of(path)
	var poses: PackedVector3Array = PackedVector3Array()
	var gears: PackedInt32Array = PackedInt32Array()
	var count: int = maxi(1, ceili(length / step))
	var index_seg: int = 0
	var seg_pose: Vector3 = start_pose(path)
	var seg_from: float = 0.0
	for index: int in range(count + 1):
		var s: float = minf(float(index) * step, length)
		if segs.is_empty():
			poses.append(seg_pose); gears.append(1)
			continue
		while index_seg < segs.size() - 1 and s > seg_from + float(segs[index_seg][1]) + 1e-9:
			var done: Array = segs[index_seg]
			seg_pose = advance(seg_pose, float(done[0]), float(done[1]), int(done[2]))
			seg_from += float(done[1])
			index_seg += 1
		var seg: Array = segs[index_seg]
		poses.append(advance(seg_pose, float(seg[0]), clampf(s - seg_from, 0.0, float(seg[1])), int(seg[2])))
		gears.append(int(seg[2]))
	return {"poses": poses, "gears": gears}

# ------------------------------------------------------------------ the legacy

## Where the old straight run put the car: 22 m along its own axis, eased over
## four seconds. A saved journey with no path keeps playing exactly this.
static func legacy_position(home: Transform3D, direction: float, time: float, returning: bool) -> Vector3:
	var eased: float = smoothstep(0.0, 1.0, time / LEGACY_SECONDS)
	if returning: eased = 1.0 - eased
	return home.origin + home.basis.z.normalized() * direction * LEGACY_DISTANCE * eased

# ----------------------------------------------------------------- validation

## "" when a saved path is well formed, otherwise why not. Nothing here trusts a
## number: it must be finite and small enough to be a street.
static func path_error(value: Variant) -> String:
	if not value is Dictionary: return "Invalid saved route."
	var path: Dictionary = value
	if not (path.get("v") is int or path.get("v") is float) or int(path.v) != VERSION: return "Invalid saved route version."
	var start: Variant = path.get("start")
	if not start is Array or (start as Array).size() != 3: return "Invalid saved route start."
	for index: int in range(3):
		if not (start[index] is int or start[index] is float) or not is_finite(float(start[index])): return "Invalid saved route start."
		if absf(float(start[index])) > (1000.0 if index < 2 else 100.0): return "Invalid saved route start."
	var segs: Variant = path.get("segs")
	if not segs is Array or (segs as Array).is_empty() or (segs as Array).size() > MAX_SEGMENTS: return "Invalid saved route segments."
	var total: float = 0.0
	for seg: Variant in segs:
		if not seg is Array or (seg as Array).size() != 3: return "Invalid saved route segment."
		for index: int in range(3):
			if not (seg[index] is int or seg[index] is float) or not is_finite(float(seg[index])): return "Invalid saved route segment."
		if absf(float(seg[0])) > MAX_CURVATURE: return "Invalid saved route curvature."
		if float(seg[1]) <= 0.0 or float(seg[1]) > 200.0: return "Invalid saved route length."
		if float(seg[2]) != 1.0 and float(seg[2]) != -1.0: return "Invalid saved route gear."
		total += float(seg[1])
	if total > MAX_LENGTH: return "Saved route is too long."
	for key: String in ["v0", "v1"]:
		if path.has(key) and (not (path[key] is int or path[key] is float) or not is_finite(float(path[key])) or float(path[key]) < 0.0 or float(path[key]) > V_MAX): return "Invalid saved route speed."
	return ""
