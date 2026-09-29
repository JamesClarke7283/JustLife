extends RefCounted
class_name LifeEmbrace
## The hug as a shared, physical moment. The `hug` action walks the hugger to a
## conversational standing point beside the partner like any other social
## action; this controller does the rest. When the hug begins both bodies turn
## to face each other, the partner is held where they stand (a housemate stops
## walking, a neighbour is already held by the conversation), and both play the
## full-contact embrace: they step in until their chests meet, wrap their arms
## round each other's backs, hold, and step back. It is presentation over the
## ordinary action: the sim still owns duration, cost and friendship, so a
## cancelled, finished or saved hug simply lets go and nobody is left frozen.
##
## A hug that cannot be reached is bounded: an approach that has taken more than
## `APPROACH_LIMIT` game minutes is cancelled with a notice, so a hugger never
## stands in limbo.

const HOLD_RADIUS: float = 3.0
const APPROACH_LIMIT: float = 45.0
## Housemates who are lying down or washing cannot be hugged until they are up.
const BUSY_ACTIONS: Array[String] = ["sleep", "nap", "shower", "bath", "toilet"]

var app: Node
var _held: Dictionary = {}
var _posed: Dictionary = {}
var _embracing: Dictionary = {}
var _approach: Dictionary = {}


func _init(controller: Node) -> void:
	app = controller


## A housemate the hug is holding in place: `_advance_movement` skips them.
func holds(member_id: String) -> bool:
	return _held.has(member_id)


## A housemate who returns the hug and shows it: the controller animates them
## as hugging for as long as the hug lasts.
func posed(member_id: String) -> bool:
	return _posed.has(member_id)


func embracing(actor_id: String) -> bool:
	return _embracing.has(actor_id)


## Why this hug should not be offered right now, or "".
func refusal(partner_id: String) -> String:
	var sim: LifeSim = app.household.member_sim(partner_id)
	if not is_instance_valid(sim):
		return ""
	var first: String = str(sim.character.get("name", "Your housemate")).split(" ")[0]
	var doing: Dictionary = sim.get_current_action()
	if not doing.is_empty() and str(doing.get("id", "")) in BUSY_ACTIONS and str(doing.get("phase", "")) == "active":
		return "%s is busy. Wait until they are up for a hug." % first
	return ""


func tick(delta: float) -> void:
	if not is_instance_valid(app.world) or not is_instance_valid(app.household):
		return
	var game_minutes: float = delta * float(app.household.speed) * LifeSim.GAME_MINUTES_PER_SECOND
	var held: Dictionary = {}
	var posed_now: Dictionary = {}
	var embracing_now: Dictionary = {}
	var seen: Dictionary = {}
	for member: Dictionary in app.household.members:
		var id: String = str(member.id)
		var action: Dictionary = member.sim.get_current_action()
		if action.is_empty() or str(action.get("id", "")) != "hug" or member.sim.is_away():
			continue
		seen[id] = true
		var partner_id: String = str(action.get("target_id", ""))
		var hugger: LifeActor = app.world.actors.get(id)
		var partner: LifeActor = app.world.actors.get(partner_id)
		if not is_instance_valid(hugger) or not is_instance_valid(partner) or not hugger.visible or not partner.visible or bool(partner.get_meta("away", false)):
			continue
		var phase: String = str(action.get("phase", ""))
		if phase == "approach":
			_approach[id] = float(_approach.get(id, 0.0)) + game_minutes
			if float(_approach[id]) > APPROACH_LIMIT:
				_give_up(id, action, partner_id)
				continue
			# A housemate who is only standing around notices the hug coming and
			# waits, facing the hugger, instead of wandering off as they arrive.
			if hugger.position.distance_to(partner.position) <= HOLD_RADIUS and _idle(partner_id):
				held[partner_id] = id
				_face(partner, hugger, delta)
			continue
		_approach.erase(id)
		if phase != "active":
			continue
		var progress: float = clampf(float(action.get("elapsed", 0.0)) / maxf(1.0, float(action.get("duration", 1.0))), 0.0, 1.0)
		var mutual: bool = _partner_joins(partner_id, id)
		hugger.set_embrace(partner.position, mutual, progress, partner.get_display_height(), partner.embrace_depth(), partner)
		embracing_now[id] = true
		_face(hugger, partner, delta)
		if mutual:
			partner.set_embrace(hugger.position, true, progress, hugger.get_display_height(), hugger.embrace_depth(), hugger)
			embracing_now[partner_id] = true
			_face(partner, hugger, delta)
			if app.household.member_sim(partner_id) != null:
				held[partner_id] = id
				posed_now[partner_id] = true
	for id: String in _approach.keys():
		if not seen.has(id):
			_approach.erase(id)
	for id: String in _embracing.keys():
		if not embracing_now.has(id):
			var actor: LifeActor = app.world.actors.get(id)
			if is_instance_valid(actor):
				actor.clear_embrace()
	_held = held
	_posed = posed_now
	_embracing = embracing_now


## Whether the partner returns the hug with their own body: a housemate who is
## free to move, or a neighbour standing in the conversation. Somebody seated
## or lying down (anchored to furniture) is hugged without stepping in.
func _partner_joins(partner_id: String, hugger_id: String) -> bool:
	var partner: LifeActor = app.world.actors.get(partner_id)
	if not is_instance_valid(partner) or not partner.visible:
		return false
	if LifeResidents.PEOPLE.has(partner_id):
		return app.residents.present(partner_id) and not app.residents._speaker(partner_id).is_empty()
	var sim: LifeSim = app.household.member_sim(partner_id)
	if not is_instance_valid(sim) or sim.is_away() or partner.is_anchored() or app.traversal.busy(partner_id):
		return false
	var doing: Dictionary = sim.get_current_action()
	if not doing.is_empty() and str(doing.get("id", "")) == "hug" and str(doing.get("target_id", "")) != hugger_id:
		return false
	return true


func _idle(partner_id: String) -> bool:
	var sim: LifeSim = app.household.member_sim(partner_id)
	return is_instance_valid(sim) and not sim.is_away() and sim.get_current_action().is_empty() and not app.traversal.busy(partner_id)


func _face(body: Node3D, toward: Node3D, delta: float) -> void:
	var direction: Vector3 = toward.position - body.position
	direction.y = 0.0
	if direction.length() > .01:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(direction.x, direction.z), minf(delta * 6.0, 1.0))


func _give_up(hugger_id: String, action: Dictionary, partner_id: String) -> void:
	_approach.erase(hugger_id)
	var partner_sim: LifeSim = app.household.member_sim(partner_id)
	var partner_name: String = str(partner_sim.character.get("name", "them")) if is_instance_valid(partner_sim) else str(LifeResidents.PEOPLE.get(partner_id, {}).get("name", "them"))
	app.show_notice("%s could not get close enough for a hug." % partner_name.split(" ")[0])
	var stored: Dictionary = app.motion_states.get(hugger_id, {})
	app._cancel_blocked_action.call_deferred(int(stored.get("generation", 0)), action, hugger_id, app.load_epoch)
