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
const DRY_ACTIONS: Array[String] = [LifeWetness.DRY_OFF_ID, LifeWetness.DRY_SIT_ID]
const CARE_ACTIONS: Array[String] = ["pet_pet", "pet_tummy_rub", "pet_tug", "pet_feed", "pet_walk", "pet_teach_trick", "pet_train_social", "pet_train_logic"]
const CAR_ACTIONS: Array[String] = ["car_open_door", "car_get_in", "car_buckle", "car_close_door", "car_seated"]
const SWIM_SPEED: float = .55
const SWIM_TURN: float = .9
const STROKE_PERIOD: float = 1.6
const PADDLE_SPEED: float = .48
const PADDLE_PERIOD: float = 1.25
## The height of the top of the floating noodle above the water's surface.
const NOODLE_TOP: float = .12
## The authored noodle lies along x with its origin at one end: its middle is this
## far along the model's own -x, and its tube's axis is this high above the origin.
const NOODLE_CENTRE: float = .60
const NOODLE_AXIS_HEIGHT: float = .086

static func handles(action_id: String) -> bool:
	return action_id == LifeOutdoorActs.ACTION_ID or action_id in CARE_ACTIONS or action_id in CAR_ACTIONS or action_id in DRY_ACTIONS

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
			if kind == "pool_ring": return _ring(actor, pose, t)
			if kind == "pool_noodle": return _paddle(actor, pose, t)
			if kind in POOL_KINDS and str(anchor.get("kind", "")) == "swim": return _swim(actor, pose, t)
		LifeWetness.DRY_OFF_ID: return _rub_down(actor, pose, t)
		LifeWetness.DRY_SIT_ID: return _sit_in_towel(actor, pose, t)
		"pet_pet": return _stroke_pet(actor, pose, ct, anchor)
		"pet_tummy_rub": return _tummy_rub(actor, pose, ct, anchor)
		"pet_tug": return _tug(actor, pose, ct, anchor)
		"pet_feed": return _pour_kibble(actor, pose, ct, anchor)
		"pet_walk": return _walk_dog(actor, pose, ct, t, anchor)
		"pet_teach_trick", "pet_train_social", "pet_train_logic": return _signal_trick(actor, pose, ct)
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

## Sitting in the middle of the rubber ring, reclined against its far side while
## it floats and drifts: the hips sit in the opening, the legs are stretched out
## over the front of the ring, the hands trail in the water either side and now
## and then give a lazy scull.
static func _ring(actor, pose: Dictionary, t: float) -> Dictionary:
	var anchor: Dictionary = actor._activity_anchor
	var from: Variant = _world(anchor, "swim_from")
	var to: Variant = _world(anchor, "swim_to")
	if from == null or to == null: return {}
	var clock: float = actor._action_time
	var drift: float = .5 - .5 * cos(clock * .10)
	var centre: Vector3 = Vector3(from).lerp(to, drift)
	var yaw: float = float(anchor.get("yaw", 0.0)) + .32 * sin(clock * .17)
	var bob: float = .014 * sin(clock * 1.25)
	# The anchor is the hips, which settle just under the surface inside the hole.
	anchor["position"] = centre + Vector3(0, -.035 + bob, 0)
	anchor["yaw"] = yaw
	actor._seated_pose(pose)
	var scull: float = sin(clock * 1.6)
	pose["Leg_L"] = Vector3(-1.34, 0, .17)
	pose["Leg_R"] = Vector3(-1.34, 0, -.17)
	pose["Shin_L"] = Vector3(.34 + .07 * sin(clock * 1.9), 0, 0)
	pose["Shin_R"] = Vector3(.34 + .07 * sin(clock * 1.9 + 1.1), 0, 0)
	pose["Arm_L"] = Vector3(-.12 + .10 * scull, 0, -.92)
	pose["Arm_R"] = Vector3(-.12 - .10 * scull, 0, .92)
	pose["Forearm_L"] = Vector3(-.30, 0, 0)
	pose["Forearm_R"] = Vector3(-.30, 0, 0)
	pose["Head"] = Vector3(-.26 + .04 * sin(clock * .5), .12 * sin(clock * .23), 0)
	# The ring floats level on the water with the seated body in its opening.
	anchor["toy_transform"] = Transform3D(Basis(Vector3.UP, yaw), Vector3(centre.x, float(from.y) + .07 + bob, centre.z))
	return {"lean": Vector3(-.60, 0, .04 * sin(clock * .7)), "seated": true}

## Chest-down across the noodle with it under the midsection, kicking with the
## legs and paddling forward with alternate hands, the head up, round and round
## the pool at a wander.
static func _paddle(actor, pose: Dictionary, t: float) -> Dictionary:
	var anchor: Dictionary = actor._activity_anchor
	var from: Variant = _world(anchor, "swim_from")
	var to: Variant = _world(anchor, "swim_to")
	if from == null or to == null: return {}
	var clock: float = actor._action_time
	var centre: Vector3 = (Vector3(from) + Vector3(to)) * .5
	var axis: Vector3 = Vector3(to) - Vector3(from)
	var half_length: float = maxf(.3, axis.length() * .5 - .25)
	var along: Vector3 = axis.normalized() if axis.length() > .001 else Vector3.RIGHT
	var across: Vector3 = Vector3(along.z, 0, -along.x)
	var half_width: float = clampf(float(anchor.get("swim_span", .6)) * .55, .18, 1.6)
	var lane: float = float(anchor.get("swim_lane_offset", 0.0))
	var omega: float = PADDLE_SPEED / maxf(.35, (half_length + half_width) * .5)
	var angle: float = clock * omega
	var at: Vector3 = centre + along * half_length * cos(angle) + across * (half_width * sin(angle) + lane * .0)
	var heading: Vector3 = -along * half_length * sin(angle) + across * half_width * cos(angle)
	var yaw: float = atan2(heading.x, heading.z)
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var body: float = actor._authored_height * actor._height * actor._proportion
	var water_y: float = float(from.y)
	# The anchor is the feet, and the body is tipped a little head-up, so the feet
	# sit lower than the belly. Set them so the belly, a body's-length along at the
	# waist, rests on top of the noodle, whose top is a hand's width above the water.
	var tilt: float = .16
	var belly_along: float = body * .58
	anchor["position"] = Vector3(at.x, water_y + NOODLE_TOP + .10 - sin(tilt) * belly_along, at.z) - forward * belly_along * cos(tilt)
	anchor["yaw"] = yaw
	var stroke: float = fmod(clock / PADDLE_PERIOD, 1.0)
	_paddle_arm(pose, "L", stroke)
	_paddle_arm(pose, "R", fmod(stroke + .5, 1.0))
	var kick: float = sin(clock * 10.5)
	pose["Leg_L"] = Vector3(.26 * kick, 0, .03)
	pose["Leg_R"] = Vector3(-.26 * kick, 0, -.03)
	pose["Shin_L"] = Vector3(.20 + .16 * sin(clock * 10.5 + 1.0), 0, 0)
	pose["Shin_R"] = Vector3(.20 - .16 * sin(clock * 10.5 + 1.0), 0, 0)
	pose["Head"] = Vector3(-.95 + .05 * sin(clock * 1.1), .10 * sin(clock * .6), 0)
	# The noodle lies across the body's middle, at right angles to it.
	var toy_basis := Basis(Vector3.UP, yaw)
	anchor["toy_transform"] = Transform3D(toy_basis, Vector3(at.x, water_y + NOODLE_TOP - .08 - NOODLE_AXIS_HEIGHT, at.z) + toy_basis.x * NOODLE_CENTRE)
	return {"lean": Vector3(PI * .5 - tilt, 0, .05 * sin(stroke * TAU))}

## One paddling hand: reach forward and down into the water, pull back beside the body.
static func _paddle_arm(pose: Dictionary, side: String, p: float) -> void:
	var out: float = -1.0 if side == "L" else 1.0
	var reach: float = 0.5 - 0.5 * cos(p * TAU)
	pose["Arm_" + side] = Vector3(-2.55 + .95 * reach, 0, out * (.18 + .14 * reach))
	pose["Forearm_" + side] = Vector3(-.15 - .55 * reach, 0, 0)

## Standing wrapped in the towel and rubbing down: the hands go over the opposite
## shoulder, then the upper arms, then the chest, while the head tips to the side.
static func _rub_down(actor, pose: Dictionary, t: float) -> Dictionary:
	var clock: float = actor._action_time
	var rub: float = sin(clock * 6.5)
	var phase: float = fmod(clock / 2.4, 3.0)
	var shoulder: float = 1.0 if phase < 1.0 else 0.0
	pose["Arm_R"] = Vector3(-.95 + .22 * rub * shoulder - .30 * (1.0 - shoulder), 0, -.10 + .30 * (1.0 - shoulder))
	pose["Forearm_R"] = Vector3(-1.75 + .30 * rub, 0, 0)
	pose["Arm_L"] = Vector3(-.85 - .20 * rub * (1.0 - shoulder) - .15 * shoulder, 0, .15)
	pose["Forearm_L"] = Vector3(-1.55 - .25 * rub * (1.0 - shoulder), 0, 0)
	pose["Head"] = Vector3(.10, .14 * sin(clock * 1.3), .10 * sin(clock * .9))
	return {"lean": Vector3(.08 + .03 * rub, 0, 0)}

## Settled in a seat in the towel, holding its edges closed at the chest.
static func _sit_in_towel(actor, pose: Dictionary, t: float) -> Dictionary:
	actor._seated_pose(pose)
	pose["Arm_L"] = Vector3(-.62, 0, -.32)
	pose["Arm_R"] = Vector3(-.62, 0, .32)
	pose["Forearm_L"] = Vector3(-1.35, 0, 0)
	pose["Forearm_R"] = Vector3(-1.35, 0, 0)
	pose["Head"] = Vector3(.05 * sin(t * 1.1), .12 * sin(t * .4), 0)
	return {"seated": true}

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
