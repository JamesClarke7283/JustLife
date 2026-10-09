extends RefCounted
## Stages a pet-care beat between the Lifelet doing it and the animal receiving
## it: where the pet stands, which way both face, what the person's hand is
## reaching for (coat, tummy, rope, bowl, collar) and, for a walk, the loop the
## pair walks on the lead. The household still owns what the care achieves;
## this owns only what it looks like, on one clock both bodies share.

const CARE_ACTIONS: Array[String] = ["pet_pet", "pet_tummy_rub", "pet_play", "pet_tug", "pet_feed", "pet_walk", "pet_teach_trick", "pet_train", "pet_train_social", "pet_train_logic", "bathe_pet"]
## How far in front of the Lifelet each beat puts the animal.
const REACH: Dictionary = {"pet_pet": .62, "pet_tummy_rub": .62, "pet_play": .85, "pet_tug": 1.0, "pet_teach_trick": .85, "pet_train": .85, "pet_train_social": .85, "pet_train_logic": .85, "pet_walk": .55, "bathe_pet": .62}
const PET_STEP: float = 1.1

const Walk = preload("res://scripts/pet_walk.gd")
var walker: RefCounted
var app: Node
## member id -> {pet, action, time, origin, path, length}
var sessions: Dictionary = {}
## Exact queued instructions waiting for a pet to leave furniture or reach a
## stair landing. Keep these transient: a canceled instruction must not return.
var exit_waits: Dictionary = {}
var feeding_plans: Dictionary = {}


func _init(owner_app: Node = null) -> void:
	app = owner_app
	walker = Walk.new(app)


func prepare(member_id: String, action: Dictionary) -> bool:
	exit_waits.erase(member_id)
	if str(action.get("id", "")) not in CARE_ACTIONS: return true
	var pet_id: String = str(action.get("target_id", ""))
	if not app.pet_actors.has(pet_id): return true
	# A pet can start its own errand while this instruction waits behind another
	# Lifelet activity. Check again when it reaches the front of the queue.
	if not app._pet_errand(pet_id).is_empty():
		app.pet_behavior().command(pet_id, "pet_stop_playing")
		if not app._pet_errand(pet_id).is_empty():
			exit_waits[member_id] = {"pet": pet_id, "action": action}
			return false
	return true


func resume_waiters() -> void:
	for member_id: String in exit_waits.keys():
		var waiting: Dictionary = exit_waits[member_id]
		var member: LifeSim = app.household.member_sim(member_id)
		if member == null or not is_same(member.get_current_action(), waiting.action):
			exit_waits.erase(member_id)
			continue
		if not app._pet_errand(str(waiting.pet)).is_empty(): continue
		exit_waits.erase(member_id)
		app._member_action_started(member_id, waiting.action)


func holds(pet_id: String) -> bool:
	# A care request owns the animal during the approach too. Waiting until
	# the first active pose lets autonomy move it away from the queued target.
	for member: Dictionary in app.household.members:
		var current: Dictionary = member.sim.get_current_action()
		if str(current.get("target_id", "")) == pet_id and str(current.get("id", "")) in CARE_ACTIONS:
			var waiting: Dictionary = exit_waits.get(str(member.id), {})
			if is_same(waiting.get("action", {}), current): continue
			return true
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
		session = {"pet": pet_id, "action": action_id, "time": 0.0, "origin": body.global_position, "path": [], "length": 0.0, "bowl": _bowl_near(body.global_position), "feed_index": 0, "feed_replan": 0.0}
		if action_id == "pet_feed":
			var plan: Dictionary = feeding_plans.get(pet_id, {})
			if not plan.is_empty() and body.position.distance_to(plan.at) < .25: session.bowl = plan.bowl
		sessions[member_id] = session
	var speed: float = float(app.household.speed) if is_instance_valid(app.household) else 1.0
	if speed > 0.0: session.time = float(session.time) + delta * clampf(speed, 1.0, 3.0)
	var at: Vector3 = session.origin
	var toward: Vector3 = pet.global_position - at
	var details: Dictionary = {"kind": "standing", "care_time": float(session.time), "care_forward": pet.global_basis.z.normalized()}
	match action_id:
		"pet_pet", "bathe_pet": details["care_target"] = pet.back_point()
		"pet_tummy_rub": details["care_target"] = pet.belly_point()
		"pet_tug": details["care_target"] = pet.mouth_point()
		"pet_feed":
			var bowl: Vector3 = _bowl_point(session)
			details["care_target"] = bowl
			toward = bowl - at
		"pet_walk":
			at = body.global_position
			toward = body.global_basis.z
			details["care_collar"] = pet.collar_point()
			details["care_phase"] = walker.phase(member_id)
			details["care_time"] = float(walker.walks.get(member_id, {}).get("clock", 0.0))
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
			"pet_pet", "pet_tummy_rub", "bathe_pet":
				goal = person + dir * float(REACH[action_id]); facing = Vector3(-dir.z, 0, dir.x)
			"pet_play", "pet_tug", "pet_teach_trick", "pet_train", "pet_train_social", "pet_train_logic":
				goal = person + dir * float(REACH[action_id])
			"pet_feed":
				# Feeding owns a real pet route. A clear bowl on the other side of
				# a partition is never reached by a pose's straight-line shortcut.
				if _advance_feed(session, pet, person, delta): moving[str(session.pet)] = true
				if bool(session.get("feed_arrived", false)) and float(session.time) >= 4.8:
					var cup: Vector3 = _bowl_point(session)
					var look: Vector3 = cup - pet.global_position
					var yaw: float = atan2(look.x, look.z)
					if not app.world.lot_navigation.pet_wall_step_clear(pet.position, pet.position, pet.rotation.y, yaw, pet.wall_hull()):
						_cancel_feed(session, "Leave space around the bowl for the pet to eat.")
						continue
					pet.rotation.y = yaw
					pet.set_interaction(action_id, float(session.time), person)
				else:
					pet.clear_interaction()
				continue
			"pet_walk":
				# Positions belong to the checked walking controller, never the pose.
				pet.set_interaction(action_id, float(session.time), body.global_position)
				if bool(walker.walks.get(member_id, {}).get("pet_moving", false)): moving[str(session.pet)] = true
				continue
		goal.y = pet.global_position.y
		if goal.distance_to(pet.global_position) > .02 and _clear(goal):
			# Each step is checked too: a pet led toward a clear spot across a
			# solid piece holds where it is, and one already inside a solid may
			# step out of it.
			var step: Vector3 = pet.global_position.move_toward(goal, delta * PET_STEP * maxf(1.0, float(app.household.speed)))
			if _clear(step) and app.world.lot_navigation.segment_clear(app.world.point_level(step), pet.global_position, step) and app._pet_path_clear(pet, pet.global_position, step) and app.world.lot_navigation.pet_wall_step_clear(pet.global_position, step, pet.rotation.y, pet.rotation.y, pet.wall_hull()): pet.global_position = step
		if facing.length() > .01:
			var yaw: float = lerp_angle(pet.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 6.0))
			if app.world.lot_navigation.pet_wall_step_clear(pet.position, pet.position, pet.rotation.y, yaw, pet.wall_hull()): pet.rotation.y = yaw
		pet.set_interaction(action_id, float(session.time), body.global_position)
	return moving


func _drop(member_id: String) -> Dictionary:
	if sessions.has(member_id): _release(member_id)
	return {}


func _release(member_id: String) -> void:
	var session: Dictionary = sessions.get(member_id, {})
	walker.release(member_id)
	sessions.erase(member_id)
	if session.is_empty(): return
	feeding_plans.erase(str(session.pet))
	var pet: LifePetActor = app.pet_actors.get(str(session.pet))
	if is_instance_valid(pet):
		pet.clear_interaction()
		if str(session.action) == "pet_feed" and pet.traversing_stairs:
			# Finish the current checked flight on cancellation; ordinary pet
			# commands can then wait for this supported landing as usual.
			var segments: Array = session.get("feed_segments", [])
			var index: int = int(session.get("feed_index", 0)) - 1
			if index >= 0 and index < segments.size() and str(segments[index].kind) == "stair":
				# The navigation graph has one edge per stair tread. Retaining only
				# the current edge leaves the pet suspended on the next tread.
				var path := PackedVector3Array([pet.position])
				var remaining: Array[Dictionary] = []
				var stair_id: String = str(segments[index].stair_id)
				for leg: Dictionary in segments.slice(index):
					if str(leg.kind) != "stair" or str(leg.stair_id) != stair_id: break
					var retained: Dictionary = leg.duplicate()
					retained.from = path[-1]
					remaining.append(retained); path.append(retained.to)
					if _clear(retained.to): break
				var landing: Vector3 = path[-1]
				app.pet_errands[str(session.pet)] = {"action": "pet_move", "label": "Finishing the stair flight", "travel_label": "Finishing the stair flight", "kind": "outdoors", "target": "", "access": "", "at": landing, "entry": landing, "path": path, "segments": remaining, "index": 0, "phase": "walking", "walking": true, "elapsed": 0.0, "commanded": false, "inside": false, "blocked": 0.0}


func _clear(point: Vector3) -> bool:
	var level: int = app.world.point_level(point)
	return level >= 0 and app.world.lot_navigation.point_clear(level, point)


func _bowl_near(from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = 1.2 * 1.2
	for item: Dictionary in app.world.items:
		if str(item.kind) != "pet_bowl" or not is_instance_valid(item.get("node")): continue
		if app.world.item_level(item) != app.world.point_level(from): continue
		var cup: Vector3 = app.pet_behavior().bowl_point(item)
		var gap: float = cup.distance_squared_to(from)
		if gap >= distance or not app.world.sight_line_clear(from, Vector3(cup.x, from.y, cup.z)): continue
		best = item; distance = gap
	return best


## The exact authored food cup. A missing bowl has no pretend floor target.
func _bowl_point(session: Dictionary) -> Vector3:
	var bowl: Dictionary = session.get("bowl", {})
	if not bowl.is_empty() and is_instance_valid(bowl.get("node")):
		return app.pet_behavior().bowl_point(bowl)
	return Vector3.INF


## Lifelets finish their ordinary approach next to a reachable real bowl,
## close enough to kneel and pour. The bowl must also admit this pet.
func feeding_destination(pet_id: String, from: Vector3) -> Vector3:
	var pet: LifePetActor = app.pet_actors.get(pet_id)
	if not is_instance_valid(pet): return Vector3.INF
	var bowls: Array[Dictionary] = []
	for item: Dictionary in app.world.items:
		if str(item.kind) == "pet_bowl" and is_instance_valid(item.get("node")): bowls.append(item)
	bowls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.node.position.distance_squared_to(pet.position) < b.node.position.distance_squared_to(pet.position))
	for bowl: Dictionary in bowls:
		var cup: Vector3 = app.pet_behavior().bowl_point(bowl)
		for reach: float in [.60, .70, .80]:
			for offset: Vector3 in [Vector3(0, 0, reach), Vector3(0, 0, -reach), Vector3(reach, 0, 0), Vector3(-reach, 0, 0)]:
				var at: Vector3 = cup + bowl.node.basis * offset
				at.y = LifeBuildingState.level_y(app.world.item_level(bowl))
				if not _clear(at) or not app.world.sight_line_clear(at, Vector3(cup.x, at.y, cup.z)): continue
				var path: PackedVector3Array = app.world.path_to(from, at)
				if path.is_empty() or path[-1].distance_to(at) > .01: continue
				if not app.pet_behavior().bowl_approach(pet_id, bowl, pet.position, false, at).is_finite(): continue
				feeding_plans[pet_id] = {"at": at, "bowl": bowl}
				return at
	feeding_plans.erase(pet_id)
	return Vector3.INF

func _advance_feed(session: Dictionary, pet: LifePetActor, person: Vector3, delta: float) -> bool:
	var bowl: Dictionary = session.get("bowl", {})
	if bowl.is_empty() or not is_instance_valid(bowl.get("node")):
		_cancel_feed(session, "Place a food and water bowl before feeding this pet.")
		return false
	var seconds: float = delta * maxf(0.0, float(app.household.speed))
	if seconds <= 0.0: return false
	if bool(session.get("feed_arrived", false)): return false
	session.feed_replan = float(session.get("feed_replan", 0.0)) - seconds
	var path: PackedVector3Array = session.get("feed_path", PackedVector3Array())
	if path.is_empty() and float(session.feed_replan) <= 0.0:
		session.feed_replan = .5
		var at: Vector3 = app.pet_behavior().bowl_approach(str(session.pet), bowl, pet.position, false, person)
		if not at.is_finite(): return _feed_blocked(session, seconds)
		var cup: Vector3 = app.pet_behavior().bowl_point(bowl)
		var route: Dictionary = app.pet_behavior()._route(str(session.pet), pet.position, at, atan2(cup.x - at.x, cup.z - at.z))
		if not bool(route.get("ok", false)): return _feed_blocked(session, seconds)
		session["feed_path"] = route.points; session["feed_segments"] = route.segments
		session["feed_index"] = 0; session["feed_goal"] = at
		path = route.points
	if path.is_empty(): return _feed_blocked(session, seconds)
	var budget: float = seconds * LifePetBehavior.WALK_SPEED
	var moved: bool = false
	while int(session.feed_index) < path.size() and budget > .000001:
		var index: int = int(session.feed_index)
		var segments: Array = session.get("feed_segments", [])
		var segment: Dictionary = segments[index - 1] if index > 0 and index <= segments.size() else {}
		if bool(segment.get("turn", false)):
			var turn: Dictionary = app.pet_behavior().turn_step(pet, segment, budget / LifePetBehavior.WALK_SPEED)
			if not bool(turn.ok): _feed_blocked(session, seconds); return moved
			budget -= float(turn.seconds) * LifePetBehavior.WALK_SPEED
			if bool(turn.finished): session.feed_index = index + 1
			else: return moved
			continue
		var point: Vector3 = path[index]
		var gap: float = pet.position.distance_to(point)
		if gap < .00001: session.feed_index = index + 1; continue
		var step: float = minf(gap, minf(budget, .10))
		var next: Vector3 = pet.position.move_toward(point, step)
		var stair: bool = str(segment.get("kind", "floor")) == "stair"
		var yaw: float = float(segment.get("yaw_to", atan2(point.x - pet.position.x, point.z - pet.position.z)))
		var blocked: bool = not app.pet_behavior()._stair_clear(pet, next, segment, yaw) if stair else app._pet_step_blocked(pet, next, yaw)
		if blocked:
			if float(session.feed_replan) <= 0.0: session["feed_path"] = PackedVector3Array()
			_feed_blocked(session, seconds)
			return moved
		if app.world.construction.doors.before_pet_step(pet, next, seconds): return moved
		pet.traversing_stairs = stair
		pet.rotation.y = yaw
		pet.position = next
		var level: int = app.world.point_level(next)
		if level >= 0: pet.floor_level = level
		budget -= step; moved = true
		session["feed_blocked"] = 0.0
		if gap <= step + .00001: session.feed_index = index + 1
	if not path.is_empty() and int(session.feed_index) >= path.size():
		session["feed_arrived"] = true
		session["feed_arrived_at"] = float(session.time)
		pet.traversing_stairs = false
	return moved

func feeding_ready(member_id: String) -> bool:
	var session: Dictionary = sessions.get(member_id, {})
	# Fast-forward must still show the single fill through standing back up,
	# even when the pet was already beside its bowl when the action started.
	return not session.is_empty() and bool(session.get("feed_arrived", false)) and float(session.time) >= maxf(6.0, float(session.get("feed_arrived_at", 0.0)) + .8)

func _feed_blocked(session: Dictionary, seconds: float) -> bool:
	session["feed_blocked"] = float(session.get("feed_blocked", 0.0)) + seconds
	if float(session.feed_blocked) >= LifePetBehavior.BLOCKED_TIMEOUT:
		_cancel_feed(session, "The pet cannot reach the bowl. Clear a path before feeding them.")
	return false

func _cancel_feed(session: Dictionary, message: String) -> void:
	for member_id: String in sessions.keys():
		if not is_same(sessions[member_id], session): continue
		var member: LifeSim = app.household.member_sim(member_id)
		if member != null and str(member.get_current_action().get("id", "")) == "pet_feed": member.cancel_action()
		app.show_blocked_notice(message)
		break

func advance_walk(member_id: String, action: Dictionary, delta: float) -> bool:
	return walker.advance(member_id, action, delta)

func walk_ready(member_id: String) -> bool:
	return walker.ready(member_id)
