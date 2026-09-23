extends RefCounted
## Poses for garden water, pet care and getting into a car, on the actor's own
## joint rig and arm solver, so they blend exactly like every other activity.
##
## The controller that owns an activity passes its facts through the activity
## anchor: the water a swimmer laps, the pet's back, collar or mouth, the bowl,
## the car's door handle or seat. `care_time` is the controller's clock for that
## activity, so a pose and the pet or door it touches agree on the moment.

const POOL_KINDS: Array[String] = ["pool", "pool_slide", "pool_ladder", "pool_light", "pool_ring", "pool_noodle"]
const FLOAT_KINDS: Array[String] = ["pool_ring", "pool_noodle"]
const CARE_ACTIONS: Array[String] = ["pet_pet", "pet_tummy_rub", "pet_tug", "pet_feed", "pet_walk", "pet_teach_trick"]
const CAR_ACTIONS: Array[String] = ["car_open_door", "car_get_in", "car_buckle", "car_close_door", "car_seated"]
const SWIM_SPEED: float = .55
const SWIM_TURN: float = .9
const STROKE_PERIOD: float = 1.6

static func handles(action_id: String) -> bool:
	return action_id == LifeOutdoorActs.ACTION_ID or action_id in CARE_ACTIONS or action_id in CAR_ACTIONS

## Shape `pose` for this activity. Returns what the caller folds into the body:
## `lean` (Vector3), `drop` (metres the hips sink), `seated` (sit blend) and
## `props` (world transforms for the held bag, kibble, rope or leash).
static func apply(actor, pose: Dictionary, action_id: String, t: float) -> Dictionary:
	var anchor: Dictionary = actor._activity_anchor
	var ct: float = float(anchor.get("care_time", actor._action_time))
	match action_id:
		LifeOutdoorActs.ACTION_ID:
			var kind: String = str(anchor.get("outdoor_kind", ""))
			if kind == "hot_tub": return _soak(actor, pose, t)
			if kind in FLOAT_KINDS and str(anchor.get("kind", "")) == "swim": return _float(actor, pose, t)
			if kind in POOL_KINDS and str(anchor.get("kind", "")) == "swim": return _swim(actor, pose, t)
		"pet_pet": return _stroke_pet(actor, pose, ct, anchor)
		"pet_tummy_rub": return _tummy_rub(actor, pose, ct, anchor)
		"pet_tug": return _tug(actor, pose, ct, anchor)
		"pet_feed": return _pour_kibble(actor, pose, ct, anchor)
		"pet_walk": return _walk_dog(actor, pose, ct, t, anchor)
		"pet_teach_trick": return _signal_trick(actor, pose, ct)
		"car_open_door", "car_close_door": return _work_door(actor, pose, ct, anchor, action_id == "car_open_door")
		"car_get_in": return _get_in(actor, pose, ct, anchor)
		"car_buckle": return _buckle(actor, pose, ct, anchor)
		"car_seated": return _seated_passenger(actor, pose, t)
	return {}

static func _local(actor, world_point: Vector3) -> Vector3:
	return actor._model.to_local(world_point)

static func _world(anchor: Dictionary, key: String) -> Variant:
	var value: Variant = anchor.get(key)
	return value if value is Vector3 and value.is_finite() else null

## Down on the right knee, left knee on the floor: the reach a person uses to
## fuss a dog at floor level. Returns how far the hips sink.
static func _kneel(actor, pose: Dictionary, amount: float) -> float:
	pose["Leg_R"] = Vector3(-1.45 * amount, 0, -.05 * amount)
	pose["Shin_R"] = Vector3(1.45 * amount, 0, 0)
	pose["Leg_L"] = Vector3(.10 * amount, 0, .05 * amount)
	pose["Shin_L"] = Vector3(1.62 * amount, 0, 0)
	return .42 * actor._height * actor._proportion * amount

static func _stroke_pet(actor, pose: Dictionary, ct: float, anchor: Dictionary) -> Dictionary:
	var kneel: float = smoothstep(0.0, .7, ct)
	var drop: float = _kneel(actor, pose, kneel)
	var back: Variant = _world(anchor, "care_target")
	var forward: Vector3 = anchor.get("care_forward", Vector3.FORWARD)
	if back != null and kneel > .4:
		# Head to tail along the coat and lift off, over and over.
		var stroke: float = .5 - .5 * cos(ct * 2.4)
		var lift: float = .03 + .035 * maxf(0.0, sin(ct * 2.4 - PI * .5))
		var hand: Vector3 = back + forward * (.16 - .34 * stroke) + Vector3.UP * lift
		actor._reach_hand(pose, "R", _local(actor, hand), Vector3(.7, -.6, -.1))
	pose["Arm_L"] = Vector3(-.28, 0, .06); pose["Forearm_L"] = Vector3(-.55, 0, 0)
	pose["Head"] = Vector3(.34, .06 * sin(ct * .7), 0)
	return {"lean": Vector3(.22 * kneel, 0, 0), "drop": drop}

static func _tummy_rub(actor, pose: Dictionary, ct: float, anchor: Dictionary) -> Dictionary:
	var kneel: float = smoothstep(0.0, .7, ct)
	var drop: float = _kneel(actor, pose, kneel)
	var belly: Variant = _world(anchor, "care_target")
	var forward: Vector3 = anchor.get("care_forward", Vector3.FORWARD)
	if belly != null and kneel > .4:
		# Small circles on the upturned tummy, the other hand steadying the chest.
		var circle := Vector3(cos(ct * 5.0), 0, sin(ct * 5.0)) * .055
		actor._reach_hand(pose, "R", _local(actor, belly + circle + Vector3.UP * .02), Vector3(.7, -.6, -.1))
		actor._reach_hand(pose, "L", _local(actor, belly + forward * .14 + Vector3.UP * .03), Vector3(-.7, -.6, -.1))
	pose["Head"] = Vector3(.38, .08 * sin(ct * 1.3), .05 * sin(ct * .9))
	return {"lean": Vector3(.30 * kneel, 0, 0), "drop": drop}

static func _tug(actor, pose: Dictionary, ct: float, anchor: Dictionary) -> Dictionary:
	# Feet braced, leaning back against the dog's pull, which comes in waves.
	var pull: float = .5 + .5 * sin(ct * 3.2)
	var proportion: float = actor._proportion
	pose["Leg_L"] = Vector3(-.28, 0, .04); pose["Shin_L"] = Vector3(.12, 0, 0)
	pose["Leg_R"] = Vector3(.22, 0, -.04); pose["Shin_R"] = Vector3(.20, 0, 0)
	var grip := Vector3(0, actor._hip_height + .16 * proportion, (.40 - .07 * pull) * proportion)
	actor._reach_hand(pose, "R", grip + Vector3(.05, 0, 0) * proportion, Vector3(.7, -.6, -.1))
	actor._reach_hand(pose, "L", grip + Vector3(-.05, .01, -.03) * proportion, Vector3(-.7, -.6, -.1))
	pose["Head"] = Vector3(.10, .06 * sin(ct * 2.1), 0)
	var props: Dictionary = {}
	var mouth: Variant = _world(anchor, "care_target")
	if mouth != null: props["rope"] = [actor._model.to_global(grip), mouth]
	return {"lean": Vector3(-.10 - .09 * pull, 0, .02 * sin(ct * 1.7)), "props": props}

## Lift the kibble bag from the hip, tip it over the bowl until the food runs
## out, then set it upright again, on a six-second loop.
static func _pour_kibble(actor, pose: Dictionary, ct: float, anchor: Dictionary) -> Dictionary:
	var c: float = fmod(ct, 6.0)
	var lift: float = smoothstep(0.0, .9, c) * (1.0 - smoothstep(5.0, 5.8, c))
	var pour: float = smoothstep(1.0, 1.6, c) * (1.0 - smoothstep(4.2, 4.8, c))
	var proportion: float = actor._proportion
	var start := Vector3(.18, actor._hip_height + .05 * proportion, .22 * proportion)
	var bowl: Variant = _world(anchor, "care_target")
	var over: Vector3 = start + Vector3(-.08, -.10, .22) * proportion
	if bowl != null:
		over = _local(actor, bowl + Vector3.UP * .46 * proportion)
		over.x = clampf(over.x, -.05, .25)
	var hand: Vector3 = start.lerp(over, lift)
	actor._reach_hand(pose, "R", hand, Vector3(.7, -.6, -.1))
	actor._reach_hand(pose, "L", hand + Vector3(-.11, -.10, -.02) * proportion, Vector3(-.7, -.6, -.1))
	pose["Head"] = Vector3(.32 * lift, 0, 0)
	var tip: float = pour * 1.9
	var basis: Basis = actor._model.global_basis.orthonormalized() * Basis(Vector3.RIGHT, tip)
	var bag := Transform3D(basis.scaled(Vector3.ONE * proportion), actor._model.to_global(hand + Vector3(-.05, .06, .02) * proportion))
	var props: Dictionary = {"bag": bag}
	if pour > .55 and bowl != null:
		var mouth: Vector3 = bag * Vector3(0, .14, 0)
		var bits: Array = []
		for i: int in range(7):
			var s: float = fmod(ct * 1.7 + float(i) / 7.0, 1.0)
			var fall: Vector3 = mouth.lerp(bowl + Vector3.UP * .07, s)
			fall.y -= .08 * sin(s * PI)
			bits.append(fall)
		props["kibble"] = bits
	return {"lean": Vector3(.30 * lift, 0, 0), "props": props}

static func _walk_dog(actor, pose: Dictionary, ct: float, t: float, anchor: Dictionary) -> Dictionary:
	var phase: String = str(anchor.get("care_phase", "clip"))
	var collar: Variant = _world(anchor, "care_collar")
	var props: Dictionary = {}
	if phase == "clip":
		# Kneel, find the collar ring and clip the lead on with a small twist.
		var kneel: float = smoothstep(0.0, .6, ct)
		var drop: float = _kneel(actor, pose, kneel)
		if collar != null and kneel > .3:
			var twist: float = sin(clampf((ct - .9) / .8, 0.0, 1.0) * PI) * .03
			actor._reach_hand(pose, "R", _local(actor, collar + Vector3(twist, .02, 0)), Vector3(.7, -.6, -.1))
			if ct > 1.2: props["leash"] = [actor._model.to_global(actor._model.to_local(collar) + Vector3(0, .02, 0)), collar]
		pose["Head"] = Vector3(.36, 0, 0)
		return {"lean": Vector3(.26 * kneel, 0, 0), "drop": drop, "props": props}
	# Walking the lead: a real gait while the controller moves the pair along
	# their loop, the left hand holding the lead out toward the collar.
	var walking: bool = phase == "walk"
	var lean := Vector3.ZERO
	if walking:
		var cycle: float = t * 7.6
		var swing: float = sin(cycle)
		pose["Leg_L"] = Vector3(swing * .48, 0, 0); pose["Leg_R"] = Vector3(-swing * .48, 0, 0)
		pose["Shin_L"] = Vector3(maxf(0.0, -cos(cycle)) * .62, 0, 0); pose["Shin_R"] = Vector3(maxf(0.0, cos(cycle)) * .62, 0, 0)
		pose["Arm_R"] = Vector3(swing * .37, 0, .025); pose["Forearm_R"] = Vector3(-.16 - maxf(0.0, -swing) * .18, 0, 0)
		lean = Vector3(.025, .025 * swing, -.013 * swing)
	var proportion: float = actor._proportion
	var hand := Vector3(-.16 * proportion, actor._hip_height + .02 * proportion, .26 * proportion)
	actor._reach_hand(pose, "L", hand, Vector3(-.7, -.6, -.1))
	if collar != null: props["leash"] = [actor._model.to_global(hand), collar]
	pose["Head"] = Vector3(.06, .10 * sin(t * .6), 0)
	return {"lean": lean, "props": props}

static func _signal_trick(actor, pose: Dictionary, ct: float) -> Dictionary:
	# Raise the hand signal, hold it, then lower a treat to the dog's nose.
	var c: float = fmod(ct, 3.2)
	var cue: float = smoothstep(0.0, .4, c) * (1.0 - smoothstep(1.5, 1.9, c))
	var treat: float = smoothstep(1.8, 2.3, c) * (1.0 - smoothstep(2.9, 3.2, c))
	var proportion: float = actor._proportion
	var raised := Vector3(.20, actor._hip_height + .62 * proportion, .22 * proportion)
	var low := Vector3(.12, actor._hip_height - .10 * proportion, .42 * proportion)
	var rest := Vector3(.20, actor._hip_height + .05 * proportion, .12 * proportion)
	actor._reach_hand(pose, "R", rest.lerp(raised, cue).lerp(low, treat), Vector3(.7, -.6, -.1))
	pose["Head"] = Vector3(.22 + .15 * treat, 0, 0)
	return {"lean": Vector3(.25 * treat, 0, 0)}

## Front crawl along the pool: face down at the surface, one arm pulling under
## while the other recovers over the water, a flutter kick and a breath to the
## side each stroke. Laps turn at each end.
static func _swim(actor, pose: Dictionary, t: float) -> Dictionary:
	var anchor: Dictionary = actor._activity_anchor
	var from: Variant = _world(anchor, "swim_from")
	var to: Variant = _world(anchor, "swim_to")
	if from == null or to == null: return {}
	var length: float = maxf(.5, Vector3(from).distance_to(to))
	var leg: float = length / SWIM_SPEED
	var cycle: float = 2.0 * (leg + SWIM_TURN)
	var p: float = fmod(actor._action_time, cycle)
	var at: Vector3 = from
	var heading: Vector3 = Vector3(to) - Vector3(from)
	var turning: float = -1.0
	if p < leg:
		at = Vector3(from).lerp(to, p / leg)
	elif p < leg + SWIM_TURN:
		at = to; turning = (p - leg) / SWIM_TURN
	elif p < 2.0 * leg + SWIM_TURN:
		at = Vector3(to).lerp(from, (p - leg - SWIM_TURN) / leg); heading = -heading
	else:
		at = from; heading = -heading; turning = (p - 2.0 * leg - SWIM_TURN) / SWIM_TURN
	var yaw: float = atan2(heading.x, heading.z)
	if turning >= 0.0: yaw += PI * smoothstep(0.0, 1.0, turning)
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var body: float = actor._authored_height * actor._height * actor._proportion
	# The anchor is the feet: lie the body along the lap with the chest at `at`.
	anchor["position"] = at - forward * body * .62 - Vector3.UP * .10
	anchor["yaw"] = yaw
	var stroke: float = fmod(actor._action_time / STROKE_PERIOD, 1.0)
	if turning >= 0.0:
		pose["Arm_L"] = Vector3(-2.85, 0, -.08); pose["Arm_R"] = Vector3(-2.85, 0, .08)
		pose["Forearm_L"] = Vector3.ZERO; pose["Forearm_R"] = Vector3.ZERO
	else:
		_crawl_arm(pose, "L", stroke)
		_crawl_arm(pose, "R", fmod(stroke + .5, 1.0))
	var kick: float = sin(actor._action_time * 9.0)
	pose["Leg_L"] = Vector3(.22 * kick, 0, .03); pose["Leg_R"] = Vector3(-.22 * kick, 0, -.03)
	pose["Shin_L"] = Vector3(.16 + .12 * sin(actor._action_time * 9.0 + 1.0), 0, 0)
	pose["Shin_R"] = Vector3(.16 - .12 * sin(actor._action_time * 9.0 + 1.0), 0, 0)
	var right: float = fmod(stroke + .5, 1.0)
	var breath: float = sin(clampf((right - .55) / .45, 0.0, 1.0) * PI) if turning < 0.0 else 0.0
	pose["Head"] = Vector3(-.20, .95 * breath, .10 * breath)
	return {"lean": Vector3(PI * .5 - .10, 0, .10 * sin(stroke * TAU))}

static func _crawl_arm(pose: Dictionary, side: String, p: float) -> void:
	var out: float = -1.0 if side == "L" else 1.0
	if p < .55:
		var a: float = p / .55
		pose["Arm_" + side] = Vector3(-2.85 + 2.85 * a, 0, out * .06)
		pose["Forearm_" + side] = Vector3(-.35 * sin(a * PI), 0, 0)
	else:
		var q: float = (p - .55) / .45
		pose["Arm_" + side] = Vector3(-2.85 * q, 0, out * 1.05 * sin(q * PI))
		pose["Forearm_" + side] = Vector3(-1.25 * sin(q * PI), 0, 0)

## Upright in the water with the ring or noodle, treading and drifting slowly.
static func _float(actor, pose: Dictionary, t: float) -> Dictionary:
	var anchor: Dictionary = actor._activity_anchor
	var from: Variant = _world(anchor, "swim_from")
	var to: Variant = _world(anchor, "swim_to")
	if from == null or to == null: return {}
	var drift: float = .5 - .5 * cos(actor._action_time * .12)
	var at: Vector3 = Vector3(from).lerp(to, drift)
	anchor["position"] = at - Vector3.UP * (actor._hip_height * actor._height * 1.08)
	anchor["yaw"] = float(anchor.get("yaw", 0.0)) + .25 * sin(actor._action_time * .2)
	var scull: float = sin(actor._action_time * 2.6)
	pose["Arm_L"] = Vector3(-.35, .2 * scull, -.95); pose["Arm_R"] = Vector3(-.35, -.2 * scull, .95)
	pose["Forearm_L"] = Vector3(-.25, 0, 0); pose["Forearm_R"] = Vector3(-.25, 0, 0)
	var tread: float = sin(actor._action_time * 3.1)
	pose["Leg_L"] = Vector3(-.45 * tread - .2, 0, .05); pose["Leg_R"] = Vector3(.45 * tread - .2, 0, -.05)
	pose["Shin_L"] = Vector3(.6 + .3 * tread, 0, 0); pose["Shin_R"] = Vector3(.6 - .3 * tread, 0, 0)
	pose["Head"] = Vector3(-.08, .25 * sin(actor._action_time * .4), 0)
	return {"lean": Vector3(.04 * scull, 0, 0)}

## Settled on the tub's bench, arms along the rim and head tipped back.
static func _soak(actor, pose: Dictionary, t: float) -> Dictionary:
	actor._seated_pose(pose)
	pose["Arm_L"] = Vector3(-.18, 0, -1.10); pose["Arm_R"] = Vector3(-.18, 0, 1.10)
	pose["Forearm_L"] = Vector3(-.55, 0, 0); pose["Forearm_R"] = Vector3(-.55, 0, 0)
	pose["Leg_L"] = Vector3(-1.25, 0, .10); pose["Leg_R"] = Vector3(-1.25, 0, -.10)
	pose["Head"] = Vector3(-.24 + .04 * sin(t * .5), .08 * sin(t * .3), 0)
	return {"lean": Vector3(-.14, 0, 0), "seated": true}

static func _work_door(actor, pose: Dictionary, ct: float, anchor: Dictionary, opening: bool) -> Dictionary:
	var handle: Variant = _world(anchor, "care_target")
	if handle != null:
		actor._reach_hand(pose, "R", _local(actor, handle), Vector3(.7, -.6, -.1))
	pose["Head"] = Vector3(.12, -.10 if opening else .10, 0)
	pose["Leg_R"] = Vector3(-.12, 0, 0)
	return {"lean": Vector3(.06, 0, 0)}

## Turn, duck under the roof line and sit down into the seat as the controller
## carries the body in through the doorway.
static func _get_in(actor, pose: Dictionary, ct: float, anchor: Dictionary) -> Dictionary:
	var sit: float = clampf(float(anchor.get("care_progress", 0.0)), 0.0, 1.0)
	var settle: float = smoothstep(0.15, .85, sit)
	pose["Leg_L"] = Vector3(-PI * .5 * settle, 0, .03); pose["Leg_R"] = Vector3(-PI * .5 * smoothstep(0.0, .6, sit), 0, -.03)
	pose["Shin_L"] = Vector3(PI * .5 * settle, 0, 0); pose["Shin_R"] = Vector3(PI * .5 * smoothstep(0.0, .6, sit), 0, 0)
	var duck: float = sin(sit * PI)
	pose["Head"] = Vector3(.35 * duck, 0, 0)
	pose["Arm_R"] = Vector3(-.55 * duck, 0, .20); pose["Forearm_R"] = Vector3(-.6 * duck, 0, 0)
	return {"lean": Vector3(.35 * duck, 0, 0), "drop": .43 * actor._height * actor._proportion * settle, "seated": settle > .5}

## Lean in through the rear door and fasten the harness: both hands down at the
## buckle, working it until it clicks.
static func _buckle(actor, pose: Dictionary, ct: float, anchor: Dictionary) -> Dictionary:
	var lean_in: float = smoothstep(0.0, .5, ct)
	var buckle: Variant = _world(anchor, "care_target")
	if buckle != null and lean_in > .3:
		var work := Vector3(sin(ct * 9.0) * .025, 0, 0)
		actor._reach_hand(pose, "R", _local(actor, buckle + work), Vector3(.7, -.6, -.1))
		actor._reach_hand(pose, "L", _local(actor, buckle + Vector3(-.13, .12, 0)), Vector3(-.7, -.6, -.1))
	pose["Leg_R"] = Vector3(-.30 * lean_in, 0, 0); pose["Shin_R"] = Vector3(.25 * lean_in, 0, 0)
	pose["Head"] = Vector3(.30 * lean_in, 0, 0)
	return {"lean": Vector3(.55 * lean_in, 0, 0)}

static func _seated_passenger(actor, pose: Dictionary, t: float) -> Dictionary:
	actor._seated_pose(pose)
	pose["Head"] = Vector3(.05 * sin(t * 1.1), .12 * sin(t * .4), 0)
	return {"drop": .43 * actor._height * actor._proportion, "seated": true}
