extends Node
class_name LifeWaterFlow
## The swim, its toys and its towels: everything that follows from getting into the
## water that needs the world rather than the simulation alone.
##
##   * a pool toy is fetched from where it lies, carried to the pool's edge, taken
##     into the water and ridden there (`toy_stage` on the queued action:
##     fetch -> pickup -> carry -> enter -> swim);
##   * a wet Lifelet fetches a towel from a rack or the floor, wraps up in it, and
##     hands it back when dry (`LifeSim.towel`);
##   * a seat sat on damp for too long leaves a puddle of water for somebody to mop.
##
## The wetness itself, the outfit change and the drying clock live in `LifeSim`
## and `LifeWetness`; this file is the part that touches nodes.

const ActorMotion = preload("res://scripts/actor_motion.gd")

const PICKUP_SECONDS: float = 1.4
const ENTER_SECONDS: float = 1.6
## While a towel is being taken it is held out before it is wrapped round.
const TOWEL_HELD_SECONDS: float = 1.2
const TOYS: Array[String] = ["pool_ring", "pool_noodle"]

var app: Node
## member id -> {"toy": furnishing id, "stage": "pickup" | "carry" | "enter", "t": seconds,
##               "rest": Vector3, "target": Vector3, "yaw": float, "shift": Vector3}
var stages: Dictionary = {}
## toy furnishing id -> member id holding it
var holders: Dictionary = {}


## Forget every fetch and towel in flight, for a world that has just been replaced.
func reset() -> void:
	stages.clear()
	holders.clear()


func item(id: String) -> Dictionary:
	return app._find_item(id)


func member_id(sim: LifeSim) -> String:
	for member: Dictionary in app.household.members:
		if member.sim == sim: return str(member.id)
	return ""


func actor(id: String) -> LifeActor:
	return app.world.actors.get(id)


static func is_toy(kind: String) -> bool:
	return kind in TOYS


func toy_action(action: Dictionary) -> bool:
	if str(action.get("id", "")) != LifeOutdoorActs.ACTION_ID: return false
	var target: Dictionary = item(str(action.get("target_id", "")))
	return not target.is_empty() and is_toy(str(target.kind))


# ----------------------------------------------------------------- towels

## Why a towel cannot be taken from this furnishing right now, or "".
func towel_error(_sim: LifeSim, target_id: String) -> String:
	var source: Dictionary = item(target_id)
	if source.is_empty(): return "That towel is no longer here."
	match str(source.kind):
		"towel_rack":
			if int(source.get("towels", 0)) <= 0: return "This rack has no towels left. Somebody is using them."
		"beach_towel":
			if bool(source.get("carried", false)): return "Somebody is already using this towel."
		_:
			return "Choose a towel or a towel rack."
	return ""


## Take the towel as the Lifelet reaches it: one off a rack, or the loose towel
## itself. The sim then holds it until it is dry.
func _take_towel(sim: LifeSim, action: Dictionary) -> bool:
	var target_id: String = str(action.get("target_id", ""))
	var problem: String = towel_error(sim, target_id)
	if problem.is_empty() and not sim.towel.is_empty(): problem = "Already wrapped in a towel."
	if not problem.is_empty():
		_stop(sim, problem)
		return false
	var source: Dictionary = item(target_id)
	var variant: Dictionary = source.get("variant", {})
	var color: String = str(variant.get("color", "e9e2d2"))
	if str(source.kind) == "towel_rack":
		color = app.world.rack_towel_color(source, int(source.get("towels", 1)) - 1)
		app.world.change_rack_towels(target_id, -1)
	else:
		source["carried"] = true
		if is_instance_valid(source.get("node")): source.node.visible = false
	sim.towel = {"source": target_id, "kind": str(source.kind), "color": color}
	app._refresh_sim_targets()
	return true


## Hang a dried Lifelet's towel back where it was fetched from.
func _return_towel(record: Dictionary) -> void:
	var source: Dictionary = item(str(record.get("source", "")))
	if source.is_empty(): return
	if str(source.kind) == "towel_rack":
		app.world.change_rack_towels(str(source.id), 1)
	else:
		source["carried"] = false
		if is_instance_valid(source.get("node")): source.node.visible = true
	app._refresh_sim_targets()


# -------------------------------------------------------------------- toys

## The pool this toy is used in: the nearest one, however far the toy lies from it.
func _pool_for(toy: Dictionary) -> Dictionary:
	return app.world.closest_item("pool", toy.node.global_position, 60.0)


## Why this Lifelet cannot take this toy into the water, or "".
func toy_error(sim: LifeSim, toy_id: String) -> String:
	var toy: Dictionary = item(toy_id)
	if toy.is_empty() or not is_toy(str(toy.kind)): return "Choose a rubber ring or a pool noodle."
	var holder: String = str(holders.get(toy_id, ""))
	if not holder.is_empty() and holder != member_id(sim): return "Somebody else is using this."
	var availability: Dictionary = sim.get_action_availability(LifeOutdoorActs.ACTION_ID, toy_id)
	if not bool(availability.available): return str(availability.reason)
	if _pool_for(toy).is_empty(): return "Buy a pool first. This belongs in one."
	return ""


## The owned pool toys, for the Lifelet's "Use pool toy" panel.
func toy_options(person: String) -> Array:
	var sim: LifeSim = app.household.member_sim(person)
	var out: Array = []
	if sim == null: return out
	var count: Dictionary = {}
	for entry: Dictionary in app.world.items:
		var kind: String = str(entry.get("kind", ""))
		if not is_toy(kind): continue
		count[kind] = int(count.get(kind, 0)) + 1
		var reason: String = toy_error(sim, str(entry.id))
		var variant: Dictionary = entry.get("variant", {})
		out.append({"id": str(entry.id), "kind": kind, "label": "%s %d" % [str(entry.label), int(count[kind])], "color": str(variant.get("color", "")),
			"available": reason.is_empty(), "reason": reason})
	return out


## Send this Lifelet to fetch a toy and swim with it.
func queue_toy(person: String, toy_id: String) -> Dictionary:
	var sim: LifeSim = app.household.member_sim(person)
	if sim == null: return {"ok": false, "error": "That Lifelet is not part of this household."}
	var reason: String = toy_error(sim, toy_id)
	if not reason.is_empty(): return {"ok": false, "error": reason}
	var toy: Dictionary = item(toy_id)
	if not sim.queue_action(LifeOutdoorActs.ACTION_ID, toy_id, app.world.approach(toy)):
		return {"ok": false, "error": "Could not queue that swim."}
	return {"ok": true}


## Called as the action starts, before the route is made, to point it at whatever
## the current stage is walking to.
func resolve(sim: LifeSim, action: Dictionary) -> void:
	if not toy_action(action): return
	var toy: Dictionary = item(str(action.target_id))
	var person: String = member_id(sim)
	if not action.has("toy_stage") or (str(action.toy_stage) != "fetch" and not stages.has(person)):
		# A new or restored swim always begins by fetching the toy.
		action["toy_stage"] = "fetch"
		action["target_position"] = app.world.approach(toy)
		return
	if str(action.toy_stage) == "carry":
		var pool: Dictionary = _pool_for(toy)
		if not pool.is_empty(): action["target_position"] = app.world.approach(pool)


func before_begin(sim: LifeSim, action: Dictionary) -> bool:
	var id: String = str(action.get("id", ""))
	if id == LifeWetness.DRY_OFF_ID:
		return _take_towel(sim, action)
	if not toy_action(action): return true
	var person: String = member_id(sim)
	var toy: Dictionary = item(str(action.target_id))
	if toy.is_empty():
		_stop(sim, "That pool toy is no longer here.")
		return false
	match str(action.get("toy_stage", "fetch")):
		"fetch":
			var holder: String = str(holders.get(str(toy.id), ""))
			if not holder.is_empty() and holder != person:
				_stop(sim, "Somebody else has taken that toy.")
				return false
			if _pool_for(toy).is_empty():
				_stop(sim, "Buy a pool first. This belongs in one.")
				return false
			holders[str(toy.id)] = person
			toy["carried"] = true
			toy["rest"] = {"x": toy.node.position.x, "y": toy.node.position.y, "z": toy.node.position.z, "rotation": toy.node.rotation_degrees.y}
			app.world.rebuild_navigation()
			stages[person] = {"toy": str(toy.id), "stage": "pickup", "t": 0.0, "rest": toy.node.global_position, "rest_basis": toy.node.global_basis.orthonormalized()}
			action["toy_stage"] = "pickup"
			return false
		"carry":
			# At the water's edge: step in with the toy.
			var state: Dictionary = stages.get(person, {})
			if state.is_empty():
				action["toy_stage"] = "fetch"
				return false
			var entry: Dictionary = _water_entry(toy, sim, action)
			state["stage"] = "enter"
			state["t"] = 0.0
			state["target"] = entry.target
			state["yaw"] = entry.yaw
			state["shift"] = entry.shift
			action["toy_stage"] = "enter"
			return false
		"swim":
			return true
	return false


## Where the toy first settles on the water, and how far the body has to move out
## to it. Mirrors where `ActorMotion` starts the ride so the hand-over is seamless.
func _water_entry(toy: Dictionary, sim: LifeSim, action: Dictionary) -> Dictionary:
	var lane: int = clampi(int(action.get("swim_lane", 0)), 0, LifeOutdoorActs.MAX_JOIN - 1)
	var anchor: Dictionary = app.world.outdoor_water_anchor(toy, {"swim_lane": lane})
	var body: LifeActor = actor(member_id(sim))
	if anchor.is_empty() or not is_instance_valid(body):
		return {"target": toy.node.global_position, "yaw": 0.0, "shift": Vector3.ZERO}
	var from: Vector3 = anchor.swim_from
	var to: Vector3 = anchor.swim_to
	var target: Vector3 = from
	var yaw: float = float(anchor.yaw)
	if str(toy.kind) == "pool_noodle":
		var axis: Vector3 = to - from
		var along: Vector3 = axis.normalized() if axis.length() > .001 else Vector3.RIGHT
		var half_length: float = maxf(.3, axis.length() * .5 - .25)
		target = (from + to) * .5 + along * half_length
		var across := Vector3(along.z, 0, -along.x)
		yaw = atan2(across.x, across.z)
	target.y = from.y + (ActorMotion.NOODLE_TOP - .08 - ActorMotion.NOODLE_AXIS_HEIGHT if str(toy.kind) == "pool_noodle" else .07)
	var shift: Vector3 = target - body.global_position
	shift.y = 0.0
	return {"target": target, "yaw": yaw, "shift": shift}


func canceled(sim: LifeSim, action: Dictionary) -> void:
	if toy_action(action): _release_toy(member_id(sim))


func finished(person: String, action: Dictionary) -> void:
	if toy_action(action): _release_toy(person)


## Put the toy down at the water's edge, clear of whoever brought it, and stop
## presenting the fetch.
func _release_toy(person: String) -> void:
	stages.erase(person)
	var body: LifeActor = actor(person)
	if is_instance_valid(body): body.water_presentation = {}
	for toy_id: String in holders.keys():
		if str(holders[toy_id]) != person: continue
		holders.erase(toy_id)
		var toy: Dictionary = item(toy_id)
		if toy.is_empty() or not is_instance_valid(toy.get("node")): continue
		toy["carried"] = false
		var rest: Dictionary = toy.get("rest", {})
		toy.erase("rest")
		var spot: Vector3 = _drop_spot(toy, body, rest)
		toy.node.global_position = Vector3(spot.x, float(rest.get("y", toy.node.position.y)), spot.z)
		toy.node.rotation_degrees.y = float(rest.get("rotation", toy.node.rotation_degrees.y))
		toy["x"] = toy.node.position.x
		toy["z"] = toy.node.position.z
		app.world.rebuild_navigation()
		app._refresh_sim_targets()


## A clear spot on the deck beside the water's edge, off to one side of the
## swimmer; the toy's own resting place when no such spot can be found.
func _drop_spot(toy: Dictionary, body: LifeActor, rest: Dictionary) -> Vector3:
	var home := Vector3(float(rest.get("x", toy.node.position.x)), 0.0, float(rest.get("z", toy.node.position.z)))
	var pool: Dictionary = _pool_for(toy)
	if pool.is_empty() or not is_instance_valid(body): return home
	var edge: Vector3 = app.world.approach(pool)
	var level: int = app.world.item_level(pool)
	var toward: Vector3 = pool.node.global_position - edge
	toward.y = 0.0
	var side: Vector3 = Vector3(toward.z, 0, -toward.x).normalized() if toward.length() > .01 else Vector3.RIGHT
	for distance: float in [1.0, 1.4, 1.8]:
		for sign: float in [1.0, -1.0]:
			var wanted: Vector3 = edge + side * sign * distance
			var at: Vector3 = app.world.nearest_clear_point(wanted, level, 1) if not app.world.construction.building_state.is_empty() else wanted
			if at.is_finite() and Vector2(at.x - wanted.x, at.z - wanted.z).length() < .3 and at.distance_to(body.global_position) > .8:
				return at
	return home


# -------------------------------------------------------------- each frame

## Called for each household member in turn while they are the bound member: move
## a fetch along, place a toy that is being carried or ridden, and show how wet
## and how towelled the body is.
func advance(person: String, delta: float) -> void:
	var sim: LifeSim = app.household.member_sim(person)
	var body: LifeActor = actor(person)
	if sim == null or not is_instance_valid(body): return
	_advance_stage(person, sim, body, delta * clampf(float(sim.speed), 0.0, 3.0))
	_place_ridden_toy(sim, body)
	_present_wet(sim, body)
	_consume_requests(sim)


func _advance_stage(person: String, sim: LifeSim, body: LifeActor, clock: float) -> void:
	var state: Dictionary = stages.get(person, {})
	if state.is_empty():
		body.water_presentation = {}
		return
	var action: Dictionary = sim.get_current_action()
	if action.is_empty() or not toy_action(action) or str(action.target_id) != str(state.toy):
		# The swim was dropped from under the fetch: put the toy down.
		_release_toy(person)
		return
	var toy: Dictionary = item(str(state.toy))
	if toy.is_empty():
		_release_toy(person)
		return
	state["t"] = float(state.t) + clock
	var presentation: Dictionary = {"stage": str(state.stage), "toy": str(toy.kind), "t": float(state.t), "toy_position": state.get("rest", toy.node.global_position), "toy_basis": state.get("rest_basis", Basis.IDENTITY)}
	if str(state.stage) == "enter":
		presentation["toy_target"] = state.target
		presentation["toy_yaw"] = float(state.yaw)
		presentation["shift"] = state.shift
	body.water_presentation = presentation
	# Face what is being reached for: the toy on the ground, then the water.
	var looking_at: Vector3 = Vector3.INF
	if str(state.stage) == "pickup": looking_at = state.get("rest", Vector3.INF) as Vector3
	elif str(state.stage) == "enter": looking_at = state.get("target", Vector3.INF) as Vector3
	if looking_at.is_finite():
		var toward: Vector3 = looking_at - body.global_position
		if Vector2(toward.x, toward.z).length() > .3:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(toward.x, toward.z), minf(clock * 9.0, 1.0))
	if body.toy_world_valid and is_instance_valid(toy.get("node")):
		toy.node.global_transform = body.toy_world_transform
	match str(state.stage):
		"pickup":
			if float(state.t) >= PICKUP_SECONDS:
				state["stage"] = "carry"
				state["t"] = 0.0
				action["toy_stage"] = "carry"
				sim._emit_action_started(action)
		"enter":
			if float(state.t) >= ENTER_SECONDS:
				stages.erase(person)
				body.water_presentation = {}
				action["toy_stage"] = "swim"
				app.household.begin_action(person)


## The toy floats where the swimmer's pose puts it, once the ride has begun.
func _place_ridden_toy(sim: LifeSim, body: LifeActor) -> void:
	var action: Dictionary = sim.get_current_action()
	if action.is_empty() or str(action.get("phase", "")) != "active" or not toy_action(action): return
	var toy: Dictionary = item(str(action.target_id))
	var anchor: Dictionary = body._activity_anchor
	if toy.is_empty() or not is_instance_valid(toy.get("node")) or not anchor.get("toy_transform") is Transform3D: return
	toy.node.global_transform = anchor.toy_transform as Transform3D


func _present_wet(sim: LifeSim, body: LifeActor) -> void:
	body.set_wetness(sim.wetness)
	var mode: String = ""
	var color: Color = Color("e9e2d2")
	if not sim.towel.is_empty():
		mode = "wrapped"
		color = Color.from_string(str(sim.towel.get("color", "e9e2d2")), color)
		var action: Dictionary = sim.get_current_action()
		if str(action.get("id", "")) == LifeWetness.DRY_OFF_ID and str(action.get("phase", "")) == "active" and body._action_time < TOWEL_HELD_SECONDS:
			mode = "carried"
	# The actor remembers what it is showing, so a rebuilt model is dressed again.
	if body._towel_mode != mode or (mode != "" and body._towel_color != color):
		body.set_towel(mode, color)


## Hand back dried towels, and leave a puddle where a damp seat was sat on too long.
func _consume_requests(sim: LifeSim) -> void:
	if not sim.towel_returns.is_empty():
		var records: Array = sim.towel_returns.duplicate()
		sim.towel_returns.clear()
		for record: Variant in records:
			if record is Dictionary: _return_towel(record)
	if not sim.wet_seat_request.is_empty():
		sim.wet_seat_request = ""
		if app.sanitation_flow.spill(sim):
			app.show_notice("%s has left a puddle on the seat. Somebody needs to mop it up." % str(sim.character.name).split(" ")[0])


func _stop(sim: LifeSim, message: String) -> void:
	sim._emit_notice(message)
	sim.cancel_action()
