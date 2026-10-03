extends RefCounted
## How a Lifelet looks doing each household chore, on the actor's own joint rig and arm
## solver. The controller hands the pose a station (where the work is: an aim point, the
## way along the surface, the way out of it, how high it reaches) through the activity
## anchor, plus the chore's progress. Everything else follows from those facts:
##
##   * the tool is placed from the contact (its working end on the surface) and the hands
##     are solved to its grips, so a hand never leaves the handle it holds;
##   * the body leans from the hips and steps toward the work just far enough for both
##     hands to reach, with the ankles kept planted;
##   * the large movement (which lane, which cushion, which pass) is a function of the
##     task's progress and the small movement (the stroke) of the pose's own clock, so a
##     paused or reloaded task shows exactly where it was.
##
## `apply` runs before the body is placed and decides lean and reach; `reach` runs after
## it and solves the arms. The mop on a patch of floor reuses the existing mopping pose.

const Props = preload("res://scripts/chore_props.gd")
const Defs = preload("res://scripts/chore_defs.gd")

const ACTIONS: Array[String] = ["chore_vacuum", "chore_vacuum_curtains", "chore_dust", "chore_wipe_sink", "chore_scrub_toilet", "chore_fluff", "chore_sweep_entry", "chore_wipe_door", "chore_wash_window"]
## How tightly the fingers close on what is held, per hand.
const CURL: Dictionary = {
	"chore_vacuum": {"L": .55, "R": .70}, "chore_vacuum_curtains": {"L": .30, "R": .65}, "chore_dust": {"L": .15, "R": .65},
	"chore_wipe_sink": {"L": .20, "R": .50}, "chore_scrub_toilet": {"L": .15, "R": .75}, "chore_fluff": {"L": .25, "R": .25},
	"chore_sweep_entry": {"L": .70, "R": .70}, "chore_wipe_door": {"L": .40, "R": .35},
	"chore_wash_window": {"L": .45, "R": .65},
}
const UP: Vector3 = Vector3.UP
const ELBOW_R: Vector3 = Vector3(.55, -.65, -.20)
const ELBOW_L: Vector3 = Vector3(-.55, -.65, -.20)


static func handles(action_id: String) -> bool:
	return action_id in ACTIONS


static func grips(action_id: String) -> Dictionary:
	return CURL.get(action_id, {"L": 0.0, "R": 0.0})


# ----------------------------------------------------------------- entry points

## Before the body is placed: build the plan for this frame, choose how far to lean and
## step, and report that to the actor. {} when there is no station to work at yet.
static func apply(actor, pose: Dictionary, action_id: String, _t: float) -> Dictionary:
	var anchor: Dictionary = actor._activity_anchor
	if not anchor.has("chore_aim") or not anchor.has("chore_u") or not anchor.has("chore_n"):
		anchor.erase("chore_plan")
		return {}
	var c: Dictionary = _context(actor, anchor)
	var plan: Dictionary
	match action_id:
		"chore_vacuum": plan = _vacuum(c)
		"chore_vacuum_curtains": plan = _curtains(c)
		"chore_dust": plan = _dust(c)
		"chore_wipe_sink": plan = _sink(c)
		"chore_scrub_toilet": plan = _toilet(c)
		"chore_fluff": plan = _fluff(c)
		"chore_sweep_entry": plan = _sweep(c)
		"chore_wipe_door": plan = _door(c)
		"chore_wash_window": plan = _window(c)
		_: return {}
	var lift: float = float(plan.get("lift", 0.0)) * float(c.e)
	var base: Vector3 = c.stand
	anchor["position"] = base + UP * lift
	var body: Dictionary = _fit(actor, anchor, plan, c)
	_pull_in(actor, anchor, plan, body)
	plan["body"] = body
	anchor["chore_plan"] = plan
	if plan.has("stool_at"): plan.tools["stool"] = Transform3D(Basis.IDENTITY, plan.stool_at)
	return {"lean": Vector3(float(body.lean), 0, 0), "chore_body": body}


## After the body is placed: solve both arms to the plan's grips and turn the head to
## the work. The tools were placed by `apply` and are presented by the actor.
static func reach(actor, pose: Dictionary) -> void:
	var plan: Dictionary = actor._activity_anchor.get("chore_plan", {})
	if plan.is_empty(): return
	for side: String in ["R", "L"]:
		var hand: Variant = plan.hands.get(side)
		if hand == null: continue
		var target: Vector3 = hand.world if hand.has("world") else actor._model.to_global(hand.local)
		actor._reach_hand(pose, side, actor._model.to_local(target), hand.elbow, hand.get("axis", Vector3.ZERO))
	if plan.has("look") and actor._joints.has("Head"):
		var direction: Vector3 = actor._model.to_local(plan.look) - actor._model.to_local(actor._joints.Head.global_position)
		var flat: float = Vector2(direction.x, direction.z).length()
		pose["Head"] = Vector3(clampf(-atan2(direction.y, maxf(.01, flat)), -.35, .65), clampf(atan2(direction.x, direction.z), -.7, .7), 0.0) * float(plan.get("look_weight", .85))


## The body's origin for the planned lean: the hips stay where they are told and the
## feet are brought back to the anchor by the leg solver. Same formula as the actor's own.
static func body_origin(actor, anchor: Dictionary, body: Dictionary) -> Vector3:
	var yaw: float = float(anchor.yaw)
	var upright: Basis = Basis(UP, yaw)
	var orientation: Basis = upright * Basis.from_euler(Vector3(float(body.lean), 0, 0))
	var hips: Vector3 = Vector3(0, actor._hip_height * actor._height, 0)
	var shift: Vector3 = Vector3(float(body.get("side", 0.0)), -float(body.get("drop", 0.0)) * actor._height * actor._proportion, float(body.get("forward", 0.0)))
	return Vector3(anchor.position) + upright * (hips + shift) - orientation * hips


# --------------------------------------------------------------------- context

static func _context(actor, anchor: Dictionary) -> Dictionary:
	var yaw: float = float(anchor.get("yaw", 0.0))
	var stand: Vector3 = anchor.get("chore_stand", anchor.get("position", actor.global_position))
	var entry: float = 1.0 if actor._reconstructing_sanitation else smoothstep(0.0, .45, actor._action_time)
	var half: Variant = anchor.get("chore_half", Vector2(.5, .5))
	var heights: Variant = anchor.get("chore_y", Vector2(0, 1))
	return {"actor": actor, "anchor": anchor, "clock": actor._action_time, "p": clampf(float(anchor.get("chore_progress", 0.0)), 0.0, 1.0), "e": entry,
		"stand": stand, "y0": stand.y, "yaw": yaw, "f": Vector3(sin(yaw), 0, cos(yaw)), "r": Vector3(cos(yaw), 0, -sin(yaw)),
		"aim": anchor.chore_aim, "u": anchor.chore_u, "n": anchor.chore_n, "half": half as Vector2, "yr": heights as Vector2,
		"top": float(anchor.get("chore_top", (heights as Vector2).y)), "aid": str(anchor.get("chore_aid", "")), "ts": clampf(actor._proportion, .72, 1.10),
		"nodes": anchor.get("chore_nodes", []), "mode": str(anchor.get("chore_mode", "")), "reach_top": float(Defs.REACH_TOP.get(actor._model_age, 1.9))}


static func _basis(dir: Vector3, side: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	var x: Vector3 = side - y * side.dot(y)
	if x.length() < .001: x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


static func _tool(contact: Vector3, dir: Vector3, side: Vector3, scale: float) -> Transform3D:
	return Transform3D(_basis(dir, side).scaled(Vector3.ONE * scale), contact)


## The tool as carried to the work, easing into the working pose as the task begins.
static func _eased(c: Dictionary, work: Transform3D, held_dir: Vector3 = UP, high: float = .62) -> Transform3D:
	var at: Vector3 = Vector3(c.stand) + Vector3(c.f) * (.20 * float(c.ts)) + Vector3(c.r) * (.26 * float(c.ts)) + UP * (high * float(c.ts))
	var carried: Transform3D = _tool(at, held_dir, c.r, float(c.ts))
	return carried.interpolate_with(work, float(c.e))


static func _hand(world: Vector3, elbow: Vector3, axis: Vector3 = Vector3.ZERO, free: bool = false) -> Dictionary:
	return {"world": world, "elbow": elbow, "axis": axis, "free": free}


## A hand resting on the hip (model space), the other half of a one-handed job.
static func _rest_hand(actor, side: String) -> Dictionary:
	var x: float = .21 if side == "R" else -.21
	return {"local": Vector3(x, actor._hip_height + .06, .04 * actor._proportion), "elbow": ELBOW_R if side == "R" else ELBOW_L}


static func _grip(tool: String, side: String, at: Transform3D) -> Vector3:
	return Props.grip_point(tool, side, at, 1.0)


static func _triangle(x: float) -> float:
	var s: float = fposmod(x, 1.0)
	return s * 2.0 if s < .5 else 2.0 - s * 2.0


static func _canister(c: Dictionary, back: float, side: float) -> Transform3D:
	var at: Vector3 = Vector3(c.stand) - Vector3(c.f) * (back * float(c.ts)) + Vector3(c.r) * (side * float(c.ts))
	at.y = c.y0
	return Transform3D(Basis(UP, float(c.yaw) + .35).scaled(Vector3.ONE * float(c.ts)), at)


# ----------------------------------------------------------------- body fitting

## Choose how far the body leans and steps toward the work so both hands reach their
## grips: the smallest effort that does, found by bisection, so it varies smoothly.
static func _fit(actor, anchor: Dictionary, plan: Dictionary, c: Dictionary) -> Dictionary:
	var lean: Vector2 = plan.get("lean", Vector2(.12, .45))
	var forward: Vector2 = plan.get("forward", Vector2(0.0, .18))
	var drop: Vector2 = plan.get("drop", Vector2.ZERO)
	var side: float = float(plan.get("side", _lateral(plan, c)))
	var ease_in: float = float(c.e)
	var low: float = 0.0
	var high: float = 1.0
	var make: Callable = func(effort: float) -> Dictionary:
		var step: float = lerpf(forward.x, forward.y, effort)
		return {"lean": lerpf(lean.x, lean.y, effort) * ease_in, "forward": step * ease_in, "drop": (lerpf(drop.x, drop.y, effort) + step * .45) * ease_in, "side": side * ease_in}
	var chosen: Dictionary
	if _excess(actor, anchor, plan, make.call(0.0)) <= 0.0:
		chosen = make.call(0.0)
	elif _excess(actor, anchor, plan, make.call(1.0)) > 0.0:
		chosen = make.call(1.0)
	else:
		for step: int in range(7):
			var mid: float = (low + high) * .5
			if _excess(actor, anchor, plan, make.call(mid)) > 0.0: low = mid
			else: high = mid
		chosen = make.call(high)
	# Bend the knees enough that both ankles can stay where the feet were planted.
	for round: int in range(3):
		var short: float = _legs_short(actor, anchor, chosen)
		if short <= 0.0: break
		chosen["drop"] = float(chosen.drop) + short * 1.3 / maxf(.5, actor._height * actor._proportion)
	return chosen


## How far to let the hips drift sideways toward where the hands are working: weight
## shifted onto one leg, so a pane or a table is worked a little off-centre.
static func _lateral(plan: Dictionary, c: Dictionary) -> float:
	var sum: float = 0.0
	var count: int = 0
	for side: String in plan.hands:
		var hand: Dictionary = plan.hands[side]
		if not hand.has("world"): continue
		sum += (Vector3(hand.world) - Vector3(c.stand)).dot(Vector3(c.r))
		count += 1
	return clampf(sum / float(maxi(1, count)) * .6, -.22, .22)


## What cannot be reached even leaning as far as the work allows is brought in: the whole
## tool slides toward the shoulder until both hands can hold it. The blade may then stand a
## few centimetres off the surface, which reads far better than a hand left in mid-air.
static func _pull_in(actor, anchor: Dictionary, plan: Dictionary, body: Dictionary) -> void:
	var origin: Vector3 = body_origin(actor, anchor, body)
	var orientation: Basis = Basis(UP, float(anchor.yaw)) * Basis.from_euler(Vector3(float(body.lean), 0, 0))
	var model_pose: Transform3D = Transform3D(orientation * Basis.IDENTITY.scaled(actor.visual.scale), origin) * actor._model.transform
	var inverse: Transform3D = model_pose.affine_inverse()
	for round: int in range(4):
		var worst: float = 0.0
		var shift: Vector3 = Vector3.ZERO
		for side: String in ["R", "L"]:
			var hand: Variant = plan.hands.get(side)
			if hand == null or not hand.has("world") or not actor._arm_rest.has(side): continue
			var rest: Dictionary = actor._arm_rest[side]
			var arm_space: Transform3D = rest.space
			var target: Vector3 = hand.world
			var shoulder: Vector3 = model_pose * (arm_space * Vector3(rest.local_shoulder))
			var local_target: Vector3 = arm_space.affine_inverse() * (inverse * target)
			var model_distance: float = (local_target - Vector3(rest.local_shoulder)).length()
			var arm_length: float = Vector3(rest.upper).length() + actor._grip_offset(side).length() - .010
			var excess: float = model_distance - arm_length * .96
			if excess > .002 and model_distance > .0001 and bool(hand.get("free", false)):
				# A hand with a job of its own (steadying, pressing) is brought in by itself.
				hand["world"] = target + (shoulder - target).normalized() * excess * (shoulder.distance_to(target) / model_distance)
			elif excess > worst and model_distance > .0001:
				worst = excess
				shift = (shoulder - target).normalized() * excess * (shoulder.distance_to(target) / model_distance)
		if worst <= .002: return
		_translate(plan, shift)
	plan["pulled"] = true


static func _translate(plan: Dictionary, shift: Vector3) -> void:
	for key: String in plan.tools:
		var value: Variant = plan.tools[key]
		if key in ["canister", "stool"]: continue
		if value is Transform3D:
			plan.tools[key] = Transform3D(value.basis, value.origin + shift)
		elif key == "hose":
			var ends: Array = value
			plan.tools[key] = [Vector3(ends[0]) + shift, ends[1], ends[2]]
		elif key == "mist":
			plan.tools[key] = (value as Array).map(func(point: Vector3) -> Vector3: return point + shift)
	for side: String in plan.hands:
		if plan.hands[side].has("world"): plan.hands[side]["world"] = Vector3(plan.hands[side].world) + shift
	if plan.has("look"): plan["look"] = Vector3(plan.look) + shift


## How far the planted ankles lie beyond what the legs can span from the placed hips.
static func _legs_short(actor, anchor: Dictionary, body: Dictionary) -> float:
	var origin: Vector3 = body_origin(actor, anchor, body)
	var orientation: Basis = Basis(UP, float(anchor.yaw)) * Basis.from_euler(Vector3(float(body.lean), 0, 0))
	var model_pose: Transform3D = Transform3D(orientation * Basis.IDENTITY.scaled(actor.visual.scale), origin) * actor._model.transform
	var inverse: Transform3D = model_pose.affine_inverse()
	var upright: Basis = Basis(UP, float(anchor.yaw))
	var worst: float = 0.0
	for side: String in actor._leg_rest:
		var rest: Dictionary = actor._leg_rest[side]
		var target: Vector3 = Vector3(anchor.position) + upright * (Vector3(rest.foot) * actor.visual.scale)
		var local: Vector3 = Transform3D(rest.space).affine_inverse() * (inverse * target)
		var reach: float = (local - Vector3(rest.hip)).length()
		var limit: float = Vector3(rest.upper).length() + Vector3(rest.lower).length() - .005
		worst = maxf(worst, reach - limit * .985)
	return worst


## How far the hands' grips lie beyond comfortable reach for this body placement.
static func _excess(actor, anchor: Dictionary, plan: Dictionary, body: Dictionary) -> float:
	var origin: Vector3 = body_origin(actor, anchor, body)
	var orientation: Basis = Basis(UP, float(anchor.yaw)) * Basis.from_euler(Vector3(float(body.lean), 0, 0))
	var model_pose: Transform3D = Transform3D(orientation * Basis.IDENTITY.scaled(actor.visual.scale), origin) * actor._model.transform
	var inverse: Transform3D = model_pose.affine_inverse()
	var worst: float = 0.0
	for side: String in ["R", "L"]:
		var hand: Variant = plan.hands.get(side)
		if hand == null or not actor._arm_rest.has(side): continue
		var rest: Dictionary = actor._arm_rest[side]
		var target: Vector3 = hand.world if hand.has("world") else model_pose * hand.local
		var arm_space: Transform3D = rest.space
		var local_target: Vector3 = arm_space.affine_inverse() * (inverse * target)
		var arm_length: float = Vector3(rest.upper).length() + actor._grip_offset(side).length() - .010
		worst = maxf(worst, (local_target - Vector3(rest.local_shoulder)).length() - arm_length * .96)
	return worst


# --------------------------------------------------------------------- chores

static func _vacuum(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var stroke: float = .5 - .5 * cos(float(c.clock) * TAU / 1.9)
	var drift: float = sin(float(c.p) * TAU * 1.5)
	var head: Vector3 = Vector3(c.stand) + Vector3(c.f) * ((.40 + .46 * stroke) * ts) + Vector3(c.r) * (.30 * drift * ts)
	head.y = float(c.y0) + .005
	var top: Vector3 = Vector3(c.stand) + Vector3(c.f) * (.16 * ts) + Vector3(c.r) * (.10 * ts) + UP * (.97 * ts)
	var work: Transform3D = _tool(head, top - head, c.r, ts)
	var tool: Transform3D = _eased(c, work, UP, .0)
	var canister: Transform3D = _canister(c, .95, .50)
	var tools: Dictionary = {"hoover": tool, "canister": canister, "hose": [tool * (Vector3(0, .90, -.012) * 1.0), canister * Vector3(0, .17, .17), .20]}
	return {"tools": tools, "lean": Vector2(.12, .50), "forward": Vector2(0, .24), "drop": Vector2(.02, .04), "look": head,
		"hands": {"R": _hand(_grip("hoover", "R", tool), ELBOW_R), "L": _hand(_grip("hoover", "L", tool), ELBOW_L)}}


static func _curtains(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var hi: float = minf(float(c.yr.y), float(c.top))
	var lo: float = maxf(float(c.yr.x), .80)
	var width: float = maxf(.2, float(c.half.x) - .14)
	var passes: float = float(c.p) * 5.0
	var k: int = mini(int(passes), 4)
	var s: float = passes - float(k)
	var across: float = s if k % 2 == 0 else 1.0 - s
	var y_rel: float = lerpf(hi, lo, float(c.p))
	var contact: Vector3 = Vector3(c.aim) + Vector3(c.u) * lerpf(-width, width, across) + Vector3(c.n) * .06
	contact.y = float(c.y0) + y_rel
	var dir: Vector3 = (Vector3(c.n) * .8 + UP * .45).normalized()
	var work: Transform3D = _tool(contact, dir, c.u, ts)
	var tool: Transform3D = _eased(c, work, UP, .5)
	var canister: Transform3D = _canister(c, .70, .55)
	var hold: Vector3 = _grip("nozzle", "L", tool)
	var lift: float = 0.0
	var comfortable: float = float(c.reach_top) - Defs.COMFORT
	if str(c.aid) == "stool": lift = Defs.STOOL_HEIGHT * smoothstep(comfortable - .14, comfortable + .02, y_rel)
	var plan: Dictionary = {"tools": {"nozzle": tool, "canister": canister, "hose": [tool * (Vector3(0, .26, 0)), canister * Vector3(0, .17, .17), .22]}, "lean": Vector2(.08, .60), "forward": Vector2(0, .24), "drop": Vector2(0, .30), "look": contact,
		"hands": {"R": _hand(_grip("nozzle", "R", tool), ELBOW_R), "L": _hand(hold, ELBOW_L)}, "lift": lift}
	if lift > .005 or str(c.aid) == "stool": plan["stool_at"] = Vector3(c.stand)
	_sway(c, float(c.p) * TAU * 2.5)
	return plan


## The curtain moves a little as the nozzle pulls at it: a shear that leans the top toward the cleaner.
static func _sway(c: Dictionary, phase: float) -> void:
	for node: Variant in c.nodes:
		if node is Node3D and is_instance_valid(node) and str(node.name) == "Tint":
			if not node.has_meta("chore_rest"): node.set_meta("chore_rest", node.transform)
			var rest: Transform3D = node.get_meta("chore_rest")
			var lean: float = .022 * sin(phase)
			var shear: Basis = Basis(Vector3(1, 0, 0), Vector3(0, 1, lean), Vector3(0, 0, 1))
			node.transform = Transform3D(rest.basis * shear, rest.origin)


static func _dust(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var clock: float = c.clock
	var contact: Vector3
	var width: float = minf(.40, maxf(.12, float(c.half.x) - .06))
	if str(c.mode) == "face":
		var lane: float = lerpf(-.7, .7, _triangle(float(c.p) * 3.0)) * width
		var low: float = float(c.yr.x)
		var high: float = minf(minf(float(c.yr.y), float(c.top)), float(c.reach_top) - .22)
		contact = Vector3(c.aim) + Vector3(c.n) * (float(c.half.y) + .03) + Vector3(c.u) * lane
		contact.y = float(c.y0) + lerpf(low, high, .5 + .5 * sin(clock * 2.4))
	else:
		var along: float = sin(clock * 1.9) * width
		var depth: float = .10 + .10 * (.5 + .5 * sin(clock * 2.9 + 1.0))
		contact = Vector3(c.aim) + Vector3(c.n) * (float(c.half.y) - depth) + Vector3(c.u) * along
		contact.y = Vector3(c.aim).y + .012
	var dir: Vector3 = (Vector3(c.n) * .45 + UP * .85).normalized()
	var work: Transform3D = _tool(contact, dir, c.u, ts)
	var tool: Transform3D = _eased(c, work, UP, .42)
	return {"tools": {"duster": tool}, "lean": Vector2(.12, .40), "forward": Vector2(0, .16), "look": contact,
		"hands": {"R": _hand(_grip("duster", "R", tool), ELBOW_R), "L": _rest_hand(c.actor, "L")}}


static func _sink(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var around: float = float(c.clock) * TAU * 1.1
	var circle: Vector3 = Vector3(c.u) * (cos(around) * .09) + Vector3(c.n) * (sin(around) * .07)
	var rinse: float = smoothstep(.86, .92, float(c.p))
	var contact: Vector3 = Vector3(c.aim) + circle
	var tap: Vector3 = Vector3(c.aim) + Vector3(c.n) * -.10 + UP * .17
	contact = contact.lerp(tap, rinse)
	var work: Transform3D = _tool(contact, UP + Vector3(c.n) * .12, c.u, ts)
	var tool: Transform3D = _eased(c, work, UP, .5)
	var counter: Vector3 = Vector3(c.aim) + Vector3(c.u) * -.30 + Vector3(c.n) * .24
	counter.y = float(c.y0) + .965
	return {"tools": {"sponge": tool}, "lean": Vector2(.28, .55), "forward": Vector2(0, .10), "look": contact, "look_weight": .95,
		"hands": {"R": _hand(_grip("sponge", "R", tool), ELBOW_R), "L": _hand(counter, ELBOW_L)}}


static func _toilet(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var around: float = float(c.clock) * TAU * 1.3
	var contact: Vector3 = Vector3(c.aim) + Vector3(c.u) * (cos(around) * .065) + Vector3(c.n) * (sin(around) * .045)
	contact.y -= .03 + .02 * sin(around * 2.0)
	var dir: Vector3 = (Vector3(c.n) * .55 + UP * .85).normalized()
	var work: Transform3D = _tool(contact, dir, c.u, ts)
	var tool: Transform3D = _eased(c, work, UP, .45)
	return {"tools": {"brush": tool}, "lean": Vector2(.50, .72), "forward": Vector2(0, .10), "drop": Vector2(.18, .30), "look": contact, "look_weight": .95,
		"hands": {"R": _hand(_grip("brush", "R", tool), ELBOW_R), "L": _rest_hand(c.actor, "L")}}


## The cushion a task is on, its resting transform remembered the first time it is touched.
static func _cushion_rest(node: Node3D) -> Dictionary:
	if not node.has_meta("chore_rest"): node.set_meta("chore_rest", node.transform)
	var rest: Transform3D = node.get_meta("chore_rest")
	var size: Vector3 = Vector3(.50, .16, .46)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null: size = (node as MeshInstance3D).mesh.get_aabb().size * node.scale
	var parent: Node3D = node.get_parent() as Node3D
	var centre: Vector3 = parent.global_transform * rest.origin
	return {"rest": rest, "centre": centre, "size": Vector3(maxf(.18, size.x), maxf(.06, size.y), maxf(.18, size.z)), "parent": parent}


static func _fluff(c: Dictionary) -> Dictionary:
	var nodes: Array = []
	for node: Variant in c.nodes:
		if node is Node3D and is_instance_valid(node): nodes.append(node)
	var count: int = maxi(1, nodes.size())
	var q: float = float(c.p) * float(count)
	var index: int = mini(int(q), count - 1)
	var s: float = clampf(q - float(index), 0.0, 1.0)
	var lift: float = .15 * smoothstep(.22, .46, s) * (1.0 - smoothstep(.80, .94, s))
	var pull: float = .22 * smoothstep(.22, .46, s) * (1.0 - smoothstep(.80, .94, s))
	var shake: float = .03 * sin(s * TAU * 5.0) * smoothstep(.46, .56, s) * (1.0 - smoothstep(.74, .84, s))
	var press: float = smoothstep(.10, .20, s) * (1.0 - smoothstep(.20, .28, s)) + smoothstep(.84, .90, s) * (1.0 - smoothstep(.90, .97, s))
	var reachout: float = smoothstep(.0, .2, s)
	var centre: Vector3 = Vector3(c.aim)
	var size: Vector3 = Vector3(.5, .16, .46)
	var toward: Vector3 = c.n
	if not nodes.is_empty():
		_release(nodes, index)
		var info: Dictionary = _cushion_rest(nodes[index])
		centre = info.centre; size = info.size
		var node: Node3D = nodes[index]
		var parent: Node3D = info.parent
		var rest: Transform3D = info.rest
		var moved: Vector3 = UP * (lift + shake) + toward * pull
		var wobble: float = .05 * sin(s * TAU * 5.0) * smoothstep(.46, .56, s) * (1.0 - smoothstep(.74, .84, s))
		var squash: Vector3 = Vector3(1.0 + .05 * press, 1.0 - .13 * press, 1.0 + .05 * press)
		node.transform = Transform3D(rest.basis * Basis.from_euler(Vector3(0, 0, wobble)) * Basis.from_scale(squash), rest.origin + parent.global_basis.inverse() * (moved - UP * (size.y * .5 * .13 * press)))
		centre += moved
	var top: Vector3 = centre + UP * (size.y * .5 - size.y * .06 * press)
	var u: Vector3 = c.u
	var side: float = minf(size.x, size.z) * .40
	var ready: Vector3 = Vector3(c.stand) + Vector3(c.f) * (.32 * float(c.ts)) + UP * (.95 * float(c.ts))
	var near: Vector3 = toward * (size.z * .22)
	var right_hand: Vector3 = ready.lerp(top + near + u * side, reachout)
	var left_hand: Vector3 = ready.lerp(top + near - u * side, reachout)
	return {"tools": {}, "lean": Vector2(.28, .80), "forward": Vector2(0, .26), "drop": Vector2(0, .12), "look": centre, "look_weight": .9,
		"hands": {"R": _hand(right_hand, ELBOW_R, Vector3.ZERO, true), "L": _hand(left_hand, ELBOW_L, Vector3.ZERO, true)}}


## Put every cushion except the one in hand back as it was.
static func _release(nodes: Array, keep: int) -> void:
	for index: int in nodes.size():
		var node: Node3D = nodes[index]
		if index != keep and node.has_meta("chore_rest"): node.transform = node.get_meta("chore_rest")


static func _sweep(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var around: float = float(c.clock) * TAU / 1.4
	var lateral: float = sin(around) * .40
	var flick: float = .06 + .12 * (.5 + .5 * cos(around - .6))
	var head: Vector3 = Vector3(c.stand) + Vector3(c.f) * ((.42 + flick) * ts) + Vector3(c.r) * (lateral * ts)
	head.y = float(c.y0) + .004
	var dir: Vector3 = (-Vector3(c.f) * .36 + UP * .93).normalized()
	var work: Transform3D = _tool(head, dir, c.r, ts)
	var tool: Transform3D = _eased(c, work, UP, .0)
	return {"tools": {"broom": tool}, "lean": Vector2(.14, .46), "forward": Vector2(0, .22), "drop": Vector2(.02, .04), "look": head,
		"hands": {"R": _hand(_grip("broom", "R", tool), ELBOW_R), "L": _hand(_grip("broom", "L", tool), ELBOW_L)}}


## A pane of glass or a door: where the work lands at progress `p` and the height reached.
static func _surface(c: Dictionary, x: float, y_rel: float, off: float) -> Vector3:
	var point: Vector3 = Vector3(c.aim) + Vector3(c.u) * x + Vector3(c.n) * off
	point.y = float(c.y0) + y_rel
	return point


static func _door(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var p: float = c.p
	var clock: float = c.clock
	var half: float = c.half.x
	var low: float = maxf(float(c.yr.x), .72)
	var high: float = minf(float(c.yr.y), float(c.top))
	var spray_phase: float = 1.0 - smoothstep(.09, .13, p)
	var contact: Vector3
	if p < .5:
		var around: float = clock * TAU * 1.0
		var centre_x: float = lerpf(0.0, half * .55, _triangle(p * 3.0)) * (1.0 if p < .3 else -1.0)
		contact = _surface(c, centre_x + cos(around) * .14, 1.02 + sin(around) * .14, .04)
	else:
		var q: float = (p - .5) * 2.0 * 4.0
		var lane: int = mini(int(q), 3)
		var x: float = lerpf(-half + .15, half - .15, (float(lane) + .5) / 4.0)
		var s: float = q - float(lane)
		contact = _surface(c, x, lerpf(low + .1, high, _triangle(s)), .04)
	var cloth: Transform3D = _tool(contact, Vector3(c.n) + UP * .12, c.u, ts)
	var tool: Transform3D = _eased(c, cloth, UP, .55)
	var tools: Dictionary = {"cloth": tool}
	var hands: Dictionary = {"R": _hand(_grip("cloth", "R", tool), ELBOW_R, Vector3.ZERO)}
	var look: Vector3 = contact
	if spray_phase > .02:
		var target: Vector3 = _surface(c, 0.0, 1.05, .0)
		var nozzle: Vector3 = target + Vector3(c.n) * .30 + UP * -.02 - Vector3(c.u) * .12
		var basis: Basis = Basis.looking_at(Vector3(c.n), UP).scaled(Vector3.ONE * ts)
		var bottle: Transform3D = Transform3D(basis, nozzle - basis * Vector3(0, .222, .075))
		tools["spray"] = bottle
		hands["L"] = _hand(_grip("spray", "L", bottle), ELBOW_L)
		tools["mist"] = _mist(nozzle, target, clock)
		look = target
	else:
		hands["L"] = _rest_hand(c.actor, "L")
	return {"tools": tools, "lean": Vector2(.12, .45), "forward": Vector2(0, .18), "drop": Vector2(0, .18), "look": look, "hands": hands}


static func _mist(from: Vector3, to: Vector3, clock: float) -> Array:
	var points: Array = []
	for index: int in range(Props.MIST_BITS):
		var s: float = fposmod(clock * 2.4 + float(index) / float(Props.MIST_BITS), 1.0)
		points.append(from.lerp(to, s) + Vector3(sin(float(index) * 5.1) * .03 * s, cos(float(index) * 3.7) * .03 * s, 0.0))
	return points


static func _window(c: Dictionary) -> Dictionary:
	var ts: float = c.ts
	var p: float = c.p
	var clock: float = c.clock
	var half: float = c.half.x
	var low: float = float(c.yr.x)
	var high: float = float(c.yr.y)
	var pole: bool = str(c.aid) == "pole"
	var contact: Vector3
	var spray_phase: float = 1.0 - smoothstep(.12, .16, p)
	var edge_phase: float = smoothstep(.84, .88, p)
	var q: float = clampf((p - .14) / .72, 0.0, 1.0) * 3.0
	var lane: int = mini(int(q), 2)
	var s: float = q - float(lane)
	var x: float = lerpf(-half + .10, half - .10, (float(lane) + .5) / 3.0)
	var stroke_y: float = lerpf(high, low, s * s * (3.0 - 2.0 * s) * .15 + s * .85)
	contact = _surface(c, x, stroke_y, .035)
	var comfortable: float = float(c.reach_top) - Defs.COMFORT
	var tools: Dictionary = {}
	var hands: Dictionary = {}
	var tool_key: String = "pole_squeegee" if pole else "squeegee"
	var dir: Vector3 = (Vector3(c.n) * .78 + UP * .55).normalized()
	var pole_hands: Dictionary = {}
	if pole:
		# The pole is held where it is comfortable, at chest height just in front of the body,
		# and runs from there to the glass: down to the hands for the top of the pane.
		var rel: float = contact.y - float(c.y0)
		var chest: float = lerpf(1.05, 1.50, smoothstep(1.2, 2.05, rel)) * float(ts)
		var near: Vector3 = Vector3(c.stand) + Vector3(c.f) * (.28 * float(ts)) + Vector3(c.r) * clampf((contact - Vector3(c.stand)).dot(Vector3(c.r)) * .45, -.2, .2)
		near.y = float(c.y0) + chest
		dir = (near - contact).normalized()
		pole_hands = {"R": near, "L": near + dir * (.36 * float(ts))}
	var look: Vector3 = contact
	if edge_phase > .02:
		# Edges and the frame with a cloth.
		var e: float = clampf((p - .86) / .14, 0.0, 1.0) * 4.0
		var side: int = mini(int(e), 3)
		var f: float = e - float(side)
		var corners: Array = [Vector2(-half + .16, low + .05), Vector2(half - .16, low + .05), Vector2(half - .16, high - .1), Vector2(-half + .16, high - .1)]
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var edge: Vector2 = a.lerp(b, f)
		var wipe: Vector3 = _surface(c, edge.x, edge.y, .04)
		contact = contact.lerp(wipe, edge_phase)
		var cloth: Transform3D = _tool(contact, Vector3(c.n) + UP * .12, c.u, ts)
		tools["cloth"] = _eased(c, cloth, UP, .55)
		hands["R"] = _hand(_grip("cloth", "R", tools["cloth"]), ELBOW_R)
		look = contact
	else:
		var work: Transform3D = _tool(contact, dir, c.u, ts)
		var tool: Transform3D = _eased(c, work, UP, .55)
		tools[tool_key] = tool
		if pole:
			hands["R"] = _hand(pole_hands.R, ELBOW_R)
			hands["L"] = _hand(pole_hands.L, ELBOW_L)
		else:
			hands["R"] = _hand(_grip(tool_key, "R", tool), ELBOW_R)
	if spray_phase > .02:
		var target: Vector3 = _surface(c, 0.0, (low + high) * .5, .0)
		var nozzle: Vector3 = target + Vector3(c.n) * .34 - Vector3(c.u) * .10 + UP * -.04
		var basis: Basis = Basis.looking_at(Vector3(c.n), UP).scaled(Vector3.ONE * ts)
		var bottle: Transform3D = Transform3D(basis, nozzle - basis * Vector3(0, .222, .075))
		tools["spray"] = bottle
		if not pole: hands["L"] = _hand(_grip("spray", "L", bottle), ELBOW_L)
		tools["mist"] = _mist(nozzle, target, clock)
		look = target
	elif not hands.has("L"):
		hands["L"] = _rest_hand(c.actor, "L")
	var lift: float = 0.0
	if str(c.aid) == "stool": lift = Defs.STOOL_HEIGHT * smoothstep(comfortable - .14, comfortable + .02, contact.y - float(c.y0))
	var plan: Dictionary = {"tools": tools, "lean": Vector2(.10, .52), "forward": Vector2(0, .24), "drop": Vector2(0, .12), "look": look, "hands": hands, "lift": lift}
	if str(c.aid) == "stool": plan["stool_at"] = Vector3(c.stand)
	return plan
