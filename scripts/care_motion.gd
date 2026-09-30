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
		session = {"pet": pet_id, "action": action_id, "time": 0.0, "origin": body.global_position, "path": [], "length": 0.0, "bowl": _bowl_near(body.global_position)}
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
				# Positions belong to the checked walking controller, never the pose.
				pet.set_interaction(action_id, float(session.time), body.global_position)
				if bool(walker.walks.get(member_id, {}).get("pet_moving", false)): moving[str(session.pet)] = true
				continue
		goal.y = pet.global_position.y
		if goal.distance_to(pet.global_position) > .02 and (_clear(goal) or action_id == "pet_feed"):
			# Each step is checked too: a pet led toward a clear spot across a
			# solid piece holds where it is, and one already inside a solid may
			# step out of it.
			var step: Vector3 = pet.global_position.move_toward(goal, delta * PET_STEP * maxf(1.0, float(app.household.speed)))
			if _clear(step) or not _clear(pet.global_position) or action_id == "pet_feed": pet.global_position = step
		if facing.length() > .01:
			pet.rotation.y = lerp_angle(pet.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 6.0))
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


func advance_walk(member_id: String, action: Dictionary, delta: float) -> bool:
	return walker.advance(member_id, action, delta)

func walk_ready(member_id: String) -> bool:
	return walker.ready(member_id)
