extends RefCounted
## Stages a pet-care beat between the Lifelet doing it and the animal receiving
## it: where the pet stands, which way both face, what the person's hand is
## reaching for (coat, tummy, rope, bowl, collar) and, for a walk, the loop the
## pair walks on the lead. The household still owns what the care achieves;
## this owns only what it looks like, on one clock both bodies share.

const CARE_ACTIONS: Array[String] = ["pet_pet", "pet_tummy_rub", "pet_tug", "pet_feed", "pet_walk", "pet_teach_trick"]
## How far in front of the Lifelet each beat puts the animal.
const REACH: Dictionary = {"pet_pet": .62, "pet_tummy_rub": .62, "pet_tug": 1.0, "pet_teach_trick": .85, "pet_walk": .55}
const WALK_CLIP: float = .08
const WALK_LAPS: int = 2
const PET_STEP: float = 1.1

var app: Node
## member id -> {pet, action, time, origin, path, length}
var sessions: Dictionary = {}


func _init(owner_app: Node = null) -> void:
	app = owner_app


func holds(pet_id: String) -> bool:
	for session: Dictionary in sessions.values():
		if str(session.pet) == pet_id: return true
	return false


## The activity anchor for this member's pet-care beat, or {} when the current
## action is not one. Called every frame the action is active.
func anchor(member_id: String, action: Dictionary, action_id: String, delta: float) -> Dictionary:
	if action_id not in CARE_ACTIONS: return _drop(member_id)
	var pet_id: String = str(action.get("target_id", ""))
	var pet: LifePetActor = app.pet_actors.get(pet_id)
	var body: Node3D = app.world.actors.get(member_id)
	if not is_instance_valid(pet) or not is_instance_valid(body): return _drop(member_id)
	var session: Dictionary = sessions.get(member_id, {})
	if session.is_empty() or str(session.pet) != pet_id or str(session.action) != action_id:
		session = {"pet": pet_id, "action": action_id, "time": 0.0, "origin": body.global_position, "path": [], "length": 0.0, "bowl": _bowl_near(body.global_position)}
		sessions[member_id] = session
	var speed: float = float(app.household.speed) if is_instance_valid(app.household) else 1.0
	if speed > 0.0: session.time = float(session.time) + delta * clampf(speed, 1.0, 3.0)
	var at: Vector3 = session.origin
	var toward: Vector3 = pet.global_position - at
	var details: Dictionary = {"kind": "standing", "care_time": float(session.time), "care_forward": pet.global_basis.z.normalized()}
	match action_id:
		"pet_pet": details["care_target"] = pet.back_point()
		"pet_tummy_rub": details["care_target"] = pet.belly_point()
		"pet_tug": details["care_target"] = pet.mouth_point()
		"pet_feed":
			var bowl: Vector3 = _bowl_point(session)
			details["care_target"] = bowl
			toward = bowl - at
		"pet_walk":
			details["care_collar"] = pet.collar_point()
			var progress: float = float(action.get("progress", 0.0))
			if progress < WALK_CLIP:
				details["care_phase"] = "clip"
			else:
				if (session.path as Array).is_empty() and float(session.length) >= 0.0: _plan_walk(session, at, toward)
				if float(session.length) > 0.0:
					var s: float = fmod(clampf((progress - WALK_CLIP) / (1.0 - WALK_CLIP), 0.0, 1.0) * WALK_LAPS, 1.0) * float(session.length)
					var point: Dictionary = _along(session.path, s)
					at = point.position
					toward = point.tangent
					details["care_phase"] = "walk"
				else:
					details["care_phase"] = "hold"
	toward.y = 0.0
	details["position"] = at
	details["yaw"] = atan2(toward.x, toward.z) if toward.length() > .01 else body.global_rotation.y
	return details


## Pose each held pet toward the Lifelet caring for it. Returns the pets that are
## walking this frame, so their gait plays.
func present_pets(delta: float) -> Dictionary:
	var moving: Dictionary = {}
	for member_id: String in sessions.keys():
		var session: Dictionary = sessions[member_id]
		var member: LifeSim = app.household.member_sim(member_id) if is_instance_valid(app.household) else null
		var current: Dictionary = member.get_current_action() if member != null else {}
		if current.is_empty() or str(current.get("id", "")) != str(session.action) or str(current.get("phase", "")) != "active" or str(current.get("target_id", "")) != str(session.pet):
			_release(member_id)
			continue
		var pet: LifePetActor = app.pet_actors.get(str(session.pet))
		var body: Node3D = app.world.actors.get(member_id)
		if not is_instance_valid(pet) or not is_instance_valid(body): _release(member_id); continue
		var person: Vector3 = body.global_position
		var toward: Vector3 = pet.global_position - person; toward.y = 0.0
		if toward.length() < .05: toward = body.global_basis.z
		var dir: Vector3 = toward.normalized()
		var goal: Vector3 = pet.global_position
		var facing: Vector3 = -dir
		var action_id: String = str(session.action)
		match action_id:
			"pet_pet", "pet_tummy_rub":
				goal = person + dir * float(REACH[action_id]); facing = Vector3(-dir.z, 0, dir.x)
			"pet_tug", "pet_teach_trick":
				goal = person + dir * float(REACH[action_id])
			"pet_feed":
				# The far side of the bowl from the Lifelet, as close as clear
				# floor allows: the bowl's own footprint blocks the nearest cells.
				var bowl: Vector3 = _bowl_point(session)
				var side: Vector3 = bowl - person; side.y = 0.0
				var out: Vector3 = side.normalized() if side.length() > .05 else dir
				goal = bowl + out * .45
				for reach: float in [.32, .45, .6, .75]:
					var spot: Vector3 = bowl + out * reach
					spot.y = pet.global_position.y
					if _clear(spot): goal = spot; break
				facing = (bowl - goal).normalized()
			"pet_walk":
				if float(session.length) > 0.0 and float(current.get("progress", 0.0)) >= WALK_CLIP:
					var s: float = fmod(clampf((float(current.progress) - WALK_CLIP) / (1.0 - WALK_CLIP), 0.0, 1.0) * WALK_LAPS, 1.0) * float(session.length)
					# The dog trots a lead's length ahead of the walker.
					var point: Dictionary = _along(session.path, fmod(s + .8, float(session.length)))
					goal = point.position; facing = point.tangent
					moving[str(session.pet)] = true
				else:
					goal = person + dir * float(REACH.pet_walk); facing = Vector3(-dir.z, 0, dir.x)
		goal.y = pet.global_position.y
		if action_id == "pet_walk" and moving.has(str(session.pet)):
			pet.global_position = goal
		elif goal.distance_to(pet.global_position) > .02 and (_clear(goal) or action_id == "pet_feed"):
			pet.global_position = pet.global_position.move_toward(goal, delta * PET_STEP * maxf(1.0, float(app.household.speed)))
		if facing.length() > .01:
			pet.rotation.y = lerp_angle(pet.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 6.0))
		pet.set_interaction(action_id, float(session.time), body.global_position)
	return moving


func _drop(member_id: String) -> Dictionary:
	if sessions.has(member_id): _release(member_id)
	return {}


func _release(member_id: String) -> void:
	var session: Dictionary = sessions.get(member_id, {})
	sessions.erase(member_id)
	if session.is_empty(): return
	var pet: LifePetActor = app.pet_actors.get(str(session.pet))
	if is_instance_valid(pet): pet.clear_interaction()


func _clear(point: Vector3) -> bool:
	var level: int = app.world.point_level(point)
	return level >= 0 and app.world.lot_navigation.point_clear(level, point)


func _bowl_near(from: Vector3) -> Dictionary:
	return app.world.closest_item("pet_bowl", from, 2.6)


## The food side of the household's bowl, or a patch of floor in front of the
## Lifelet when there is no bowl.
func _bowl_point(session: Dictionary) -> Vector3:
	var bowl: Dictionary = session.get("bowl", {})
	if not bowl.is_empty() and is_instance_valid(bowl.get("node")):
		return (bowl.node as Node3D).to_global(Vector3(-.095, .09, 0))
	var body: Node3D = null
	for id: String in sessions:
		if sessions[id] == session: body = app.world.actors.get(id)
	var origin: Vector3 = session.origin
	return origin + (body.global_basis.z if is_instance_valid(body) else Vector3.FORWARD) * .5


## A loop that starts and ends where the Lifelet stands, on clear floor all the
## way round. Tries a few sizes and directions; none clear means they stand and
## hold the lead instead.
func _plan_walk(session: Dictionary, start: Vector3, toward: Vector3) -> void:
	var base: float = atan2(toward.x, toward.z) if toward.length() > .01 else 0.0
	for radius: float in [1.6, 1.25, .95]:
		for turn: int in range(8):
			var heading: float = base + float(turn) * TAU / 8.0
			var center: Vector3 = start + Vector3(sin(heading), 0, cos(heading)) * radius
			var points: Array = []
			var ok: bool = true
			for i: int in range(24):
				var a: float = heading + PI + float(i) * TAU / 24.0
				var point: Vector3 = center + Vector3(sin(a), 0, cos(a)) * radius
				point.y = start.y
				if not _clear(point) or app.world.point_level(point) != app.world.point_level(start): ok = false; break
				points.append(point)
			if ok:
				points.append(points[0])
				session.path = points
				session.length = TAU * radius
				return
	session.length = -1.0


static func _along(path: Array, distance: float) -> Dictionary:
	var left: float = distance
	for i: int in range(path.size() - 1):
		var a: Vector3 = path[i]; var b: Vector3 = path[i + 1]
		var step: float = a.distance_to(b)
		if left <= step or i == path.size() - 2:
			var at: Vector3 = a.lerp(b, clampf(left / maxf(step, .0001), 0.0, 1.0))
			return {"position": at, "tangent": (b - a).normalized()}
		left -= step
	return {"position": path[0] if not path.is_empty() else Vector3.ZERO, "tangent": Vector3.FORWARD}
