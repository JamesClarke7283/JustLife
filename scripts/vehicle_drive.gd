extends RefCounted
class_name LifeVehicleDrive
## The meeting point between the pure route code and the running game: it plans a
## drive from the world's lot, keeps the plan on the saved commute, places a car
## (and its wheels) on it at any moment, and queues cars that would otherwise
## meet. The work commute and the household's trips both call into this file, so
## their own scripts only say when a drive begins and what time it is.
##
## Saved commute keys it owns: drive_path, return_path (a route each) and
## depart_hold, return_hold (seconds the car waits, parked or out of sight, for
## another car to clear the way). A commute without a path plays the old straight
## 22 m line exactly.

const Path = preload("res://scripts/vehicle_path.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Rig = preload("res://scripts/vehicle_rig.gd")
const Road = preload("res://scripts/road.gd")
const MAX_HOLD: float = 60.0
## The caption of a driver whose car waits its turn.
const WAITING: String = "Waiting for the car ahead"


## A transform's position and yaw as the planner's (x, z, yaw).
static func pose_of(transform: Transform3D) -> Vector3:
	var ahead: Vector3 = transform.basis.z
	return Vector3(transform.origin.x, transform.origin.z, atan2(ahead.x, ahead.z))


static func _key(phase: String) -> String:
	return "drive_path" if phase == "depart" else "return_path"


static func _hold_key(phase: String) -> String:
	return "depart_hold" if phase == "depart" else "return_hold"


## Cars of other members that sit at their own spot right now (they are hidden
## furnishings with a copy standing in): they are obstacles though invisible.
static func _present(commute: RefCounted, own_vehicle: String) -> Array:
	var ids: Array = []
	for other: String in commute.views:
		var view: Dictionary = commute.views[other]
		if str(view.vehicle) == own_vehicle: continue
		var phase: String = str(view.action.get("commute", {}).get("phase", ""))
		if phase in ["walk", "board", "exit", "back"]: ids.append(str(view.vehicle))
	return ids


static func scene_for(commute: RefCounted, view: Dictionary) -> Dictionary:
	return Planner.scene_from_world(commute.app.world, str(view.vehicle), _present(commute, str(view.vehicle)))

# ---------------------------------------------------------------- departures

## Plan the drive away and keep it on the commute. Returns the drive direction the
## commute records (+1 forward, -1 reversing first), or `legacy` when no route
## exists and the old straight run is still clear, or 0 when nothing is.
static func begin_departure(commute: RefCounted, view: Dictionary, state: Dictionary, home: Transform3D, legacy: float) -> float:
	for key: String in ["drive_path", "return_path", "depart_hold", "return_hold"]: state.erase(key)
	var plan: Dictionary = Planner.plan_departure(scene_for(commute, view), pose_of(home), float(view.scale))
	if bool(plan.ok):
		state["drive_path"] = plan.path
		return 1.0 if int(plan.path.segs[0][2]) > 0 else -1.0
	return legacy


## How long the car waits at its spot before it may move, so it never meets a car
## that is already driving. Recorded at the moment boarding finishes.
static func queue(commute: RefCounted, id: String, view: Dictionary, state: Dictionary, phase: String) -> void:
	state.erase(_hold_key(phase))
	var path: Variant = state.get(_key(phase))
	if not path is Dictionary: return
	var others: Array = []
	for other_id: String in commute.views:
		if other_id == id: continue
		var other_view: Dictionary = commute.views[other_id]
		var other_state: Dictionary = other_view.action.get("commute", {})
		var other_phase: String = str(other_state.get("phase", ""))
		if other_phase not in ["depart", "return"]: continue
		var other_path: Variant = other_state.get(_key(other_phase))
		if not other_path is Dictionary: continue
		others.append({"path": other_path, "time": float(other_state.get("time", 0.0)) - float(other_state.get(_hold_key(other_phase), 0.0)), "scale": float(other_view.scale), "stays": other_phase == "return"})
	if others.is_empty(): return
	var hold: float = Planner.hold_seconds(path, float(view.scale), others, phase == "return")
	if hold > 0.0: state[_hold_key(phase)] = hold


## The way home: along the road, off it and onto the spot exactly. A failed plan
## falls back to the departure route driven back, then to the old straight run.
static func begin_arrival(commute: RefCounted, id: String, view: Dictionary, state: Dictionary, home: Transform3D) -> void:
	state.erase("return_path"); state.erase("return_hold")
	var plan: Dictionary = Planner.plan_arrival(scene_for(commute, view), pose_of(home), float(view.scale))
	if bool(plan.ok): state["return_path"] = plan.path
	elif state.get("drive_path") is Dictionary:
		var back: Dictionary = Planner.arrival_from_departure(state.drive_path)
		if not back.is_empty(): state["return_path"] = back
	queue(commute, id, view, state, "return")

# ------------------------------------------------------------------ playing

## Seconds a phase takes: the path's own time plus any wait, or the old four.
static func seconds(state: Dictionary, phase: String) -> float:
	var path: Variant = state.get(_key(phase))
	if not path is Dictionary: return Path.LEGACY_SECONDS
	return float(state.get(_hold_key(phase), 0.0)) + Path.duration(path)


## Whether the car is still waiting for its turn (parked, or not yet in sight).
static func waiting(state: Dictionary, phase: String) -> bool:
	return phase in ["depart", "return"] and state.get(_key(phase)) is Dictionary and float(state.time) < float(state.get(_hold_key(phase), 0.0))


## Whether the car is out on the road moving: gates open for it only then.
static func moving(state: Dictionary, phase: String) -> bool:
	return phase in ["depart", "return"] and not waiting(state, phase)


## A car queuing to come home is out of sight until its turn.
static func hidden(state: Dictionary, phase: String) -> bool:
	return phase == "return" and waiting(state, phase)


## Put the car (and its wheels) where the saved route has it `time` seconds into
## the phase.
static func place(view: Dictionary, state: Dictionary, phase: String, time: float) -> void:
	var car: Node3D = view.car
	var home: Transform3D = view.home
	var path: Variant = state.get(_key(phase))
	if not path is Dictionary:
		car.global_position = Path.legacy_position(home, float(state.get("drive_sign", 1.0)), time, phase == "return")
		return
	var rig: Dictionary = view.get("wheels", {})
	var at: float = maxf(0.0, time - float(state.get(_hold_key(phase), 0.0)))
	var now: Dictionary = Path.state_at(path, at, float(rig.get("wheelbase", 0.0)) * home.basis.get_scale().x if bool(rig.get("ok", false)) else Path.WHEELBASE)
	car.global_transform = Transform3D(Basis(Vector3.UP, float(now.yaw)) * Basis.from_scale(home.basis.get_scale()), Vector3(float(now.x), home.origin.y, float(now.z)))
	Rig.apply(rig, float(now.steer), float(now.spin))
	Rig.lights(rig, bool(now.braking) or int(now.gear) < 0)


## Back at its spot, wheels straight and lights out.
static func park(view: Dictionary) -> void:
	var rig: Dictionary = view.get("wheels", {})
	if rig.is_empty(): return
	Rig.reset(rig)
	Rig.lights(rig, false)

# -------------------------------------------------------------- persistence

## "" when the saved drive keys are sound; each route must be well formed and each
## wait a small, finite number of seconds.
static func save_error(value: Dictionary) -> String:
	for key: String in ["drive_path", "return_path"]:
		if value.has(key) and not Path.path_error(value[key]).is_empty(): return "Invalid saved car route."
	for key: String in ["depart_hold", "return_hold"]:
		if value.has(key) and not LifeBuildingState.number(value[key], 0.0, MAX_HOLD): return "Invalid saved car wait."
	return ""


## How long a drive phase may last in a saved commute: its route's time and wait.
static func phase_limit(value: Dictionary, phase: String, legacy_limit: float) -> float:
	var path: Variant = value.get(_key(phase))
	if not path is Dictionary or phase not in ["depart", "return"]: return legacy_limit
	return float(value.get(_hold_key(phase), 0.0)) + Path.duration(path) + .5


# -------------------------------------------------------------------- trips
## The household's trips keep their route on the trip record under "drive":
## {path, scale, kind, y, rig, parked_body}. A trip with no "drive" (a hand-built
## one) still plays the old straight run in residents.gd.

## The kerb run of the shared car, a venue's parked car or the birth car: along the
## near lane to or from the kerb spot, with the little sideways shift eased by a
## curve rather than slid.
static func kerb_path(arriving: bool) -> Dictionary:
	var lane: float = Road.LANE_NEAR_Z
	var rho: float = Planner.TURN_RADIUS
	var path: Dictionary
	if arriving:
		path = Path.create(-Road.EXIT_X, lane, PI * .5)
		Path.add(path, 0.0, Road.EXIT_X - 8.0, 1)
		var shift: Dictionary = Path.dubins(-8.0, lane, PI * .5, Road.KERB_PARK_X, Road.KERB_PARK_Z, PI * .5, rho)
		Path.add_all(path, shift.segs)
		path["v0"] = Path.V_MAX
	else:
		path = Path.create(Road.KERB_PARK_X, Road.KERB_PARK_Z, PI * .5)
		var shift: Dictionary = Path.dubins(Road.KERB_PARK_X, Road.KERB_PARK_Z, PI * .5, 8.0, lane, PI * .5, rho)
		Path.add_all(path, shift.segs)
		Path.add(path, 0.0, Road.EXIT_X - 8.0, 1)
		path["v1"] = Path.V_MAX
	return path


## The plan for leaving: {ok, path, scale} for a route, {ok: true} for the old straight
## run, or {ok: false, error} when the car is boxed in.
static func trip_departure(app: Node, owned: Dictionary, car_at: Transform3D) -> Dictionary:
	if owned.is_empty(): return {"ok": true, "path": kerb_path(false), "scale": 1.0, "kind": "kerb"}
	var scale: float = LifeCatalogVariants.size_scale(str(owned.get("variant", {}).get("size", "")))
	var plan: Dictionary = Planner.plan_departure(Planner.scene_from_world(app.world, str(owned.id)), pose_of(car_at), scale)
	if bool(plan.ok): return {"ok": true, "path": plan.path, "scale": scale, "kind": plan.kind}
	if not is_zero_approx(app.work_commute.drive_direction(app.world, car_at, str(owned.id))): return {"ok": true}
	return {"ok": false, "error": "Clear the driveway so the car can reach the road."}


## How long the trip's drive phase lasts: the route's own time, or `fallback`.
static func trip_seconds(trip: Dictionary, fallback: float) -> float:
	var info: Variant = trip.get("drive")
	if not info is Dictionary or not (info as Dictionary).has("path"): return fallback
	return Path.duration(info.path)


## The slice of the quarter hour to step this frame. A planned drive paces the clock
## across its own length in sixty-fourths of a minute, so every slice and every sum
## is exact (the household clock then lands on the quarter hour exactly, however long
## the route is); a hand-built trip keeps the old proportional slice.
static func trip_slice(trip: Dictionary, travelled: float, delta: float, total_minutes: float, fallback: float) -> float:
	var seconds: float = trip_seconds(trip, fallback)
	if seconds == fallback and not (trip.get("drive") is Dictionary and (trip.drive as Dictionary).has("path")):
		return minf(total_minutes - travelled, delta / fallback * total_minutes)
	var target: float = floorf(clampf(float(trip.time) / seconds, 0.0, 1.0) * total_minutes * 64.0) / 64.0
	return clampf(target - travelled, 0.0, total_minutes - travelled)


## The party's arrival route at the new place: back onto the household car's own
## spot at home, otherwise the kerb. Puts the trip car at the start of it.
static func trip_arrival(residents: RefCounted, destination: String) -> void:
	var app: Node = residents.app
	var trip: Dictionary = residents.trip
	var car: Node3D = residents.car
	var info: Dictionary = {}
	if destination == "home":
		var owned: Dictionary = residents._find_owned_vehicle()
		if not owned.is_empty() and is_instance_valid(owned.get("node")):
			var scale: float = LifeCatalogVariants.size_scale(str(owned.get("variant", {}).get("size", "")))
			var plan: Dictionary = Planner.plan_arrival(Planner.scene_from_world(app.world, str(owned.id)), pose_of((owned.node as Node3D).global_transform), scale)
			if bool(plan.ok): info = {"path": plan.path, "scale": scale, "kind": plan.kind, "parked_body": owned.node}
	if info.is_empty(): info = {"path": kerb_path(true), "scale": 1.0, "kind": "kerb"}
	info["y"] = (info.parked_body as Node3D).global_position.y if info.has("parked_body") else car.global_position.y
	if info.has("parked_body"): (info.parked_body as Node3D).visible = false
	trip["drive"] = info
	trip["camera_from"] = Vector3(0, 0, 6.5)
	_pose_trip_car(residents, 0.0)


static func _pose_trip_car(residents: RefCounted, time: float) -> Dictionary:
	var info: Dictionary = residents.trip.drive
	var car: Node3D = residents.car
	if not info.has("rig"): info["rig"] = Rig.attach(car)
	if not info.has("y"): info["y"] = car.global_position.y
	var rig: Dictionary = info.rig
	var scale: float = float(info.get("scale", 1.0))
	var wheelbase: float = float(rig.get("wheelbase", 0.0)) * scale if bool(rig.get("ok", false)) else Path.WHEELBASE
	var now: Dictionary = Path.state_at(info.path, time, wheelbase)
	var node_scale: Vector3 = car.scale
	car.global_transform = Transform3D(Basis(Vector3.UP, float(now.yaw)) * Basis.from_scale(node_scale), Vector3(float(now.x), float(info.get("y", 0.0)), float(now.z)))
	Rig.apply(rig, float(now.steer), float(now.spin))
	Rig.lights(rig, bool(now.braking) or int(now.gear) < 0)
	return now


## One frame of a planned trip drive: the car and its wheels on the route, and the
## camera easing after it (leaving) or panning home (arriving) with no cut.
static func trip_place(residents: RefCounted, phase: String, delta: float) -> void:
	var trip: Dictionary = residents.trip
	if not is_instance_valid(residents.car): return
	var now: Dictionary = _pose_trip_car(residents, float(trip.time))
	var world: Node3D = residents.app.world
	if phase == "departure":
		var target := Vector3(float(now.x), 0.0, float(now.z) - 2.2)
		var follow: Vector3 = trip.get("cam", world.camera_target)
		follow = follow.lerp(target, 1.0 - exp(-4.0 * delta))
		trip["cam"] = follow
		world.camera_target = follow
	else:
		var span: float = maxf(.1, Path.duration(trip.drive.path))
		world.camera_target = (trip.get("camera_from", Vector3(0, 0, 6.5)) as Vector3).lerp(Vector3(0, 0, .25), smoothstep(0.0, 1.0, float(trip.time) / span))
	world.update_camera()


## The drive is over: the car exactly on the end of its route, wheels straight,
## and the household car's own body shown again where it was parked.
static func trip_finish(residents: RefCounted) -> void:
	var info: Variant = residents.trip.get("drive")
	if not info is Dictionary or not (info as Dictionary).has("path"): return
	if is_instance_valid(residents.car): _pose_trip_car(residents, Path.duration(info.path) + 1.0)
	if info.has("rig"):
		Rig.reset(info.rig)
		Rig.lights(info.rig, false)
	if info.has("parked_body") and is_instance_valid(info.parked_body): (info.parked_body as Node3D).visible = true
	info.erase("parked_body")


## Where a returning party member stands: beside the household car where it is
## parked at home, otherwise at the usual kerb places.
static func exit_spot(residents: RefCounted, index: int, id: String, taken: Array[Vector3]) -> Vector3:
	if str(residents.trip.get("destination", "")) == "home":
		var owned: Dictionary = residents._find_owned_vehicle()
		if not owned.is_empty() and is_instance_valid(owned.get("node")):
			var near: Vector3 = residents._boarding_point(index, id, taken, (owned.node as Node3D).global_transform)
			if near.is_finite(): return near
	return residents._curb(index, taken)


# -------------------------------------------------------------------- birth car
## The car that brings a mother and baby home drives the same kerb route as a venue
## arrival; main.gd keeps its time on the birth record.

static func birth_start(car: Node3D) -> Dictionary:
	return {"path": kerb_path(true), "rig": Rig.attach(car), "scale": 1.0}


## One frame of the birth drive; true once the car is parked at the kerb.
static func birth_drive(arrival: Dictionary, car: Node3D) -> bool:
	var info: Dictionary = arrival.drive
	var rig: Dictionary = info.rig
	var wheelbase: float = float(rig.get("wheelbase", 0.0)) if bool(rig.get("ok", false)) else Path.WHEELBASE
	var now: Dictionary = Path.state_at(info.path, float(arrival.time), wheelbase)
	car.global_transform = Transform3D(Basis(Vector3.UP, float(now.yaw)), Vector3(float(now.x), 0.0, float(now.z)))
	Rig.apply(rig, float(now.steer), float(now.spin))
	Rig.lights(rig, bool(now.braking))
	if bool(now.done):
		Rig.reset(rig)
		Rig.lights(rig, false)
		return true
	return false
