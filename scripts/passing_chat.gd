extends RefCounted
class_name LifePassingChat
## Casual moments with the neighbours who walk past the home. Any Lifelet who
## can see the sidewalk (outside, or at a door or window with a clear line) may
## wave to, greet or chat with a passing child, teen, adult or elder, admire the
## dog on a lead, or say hello to and pat a dog trotting by. The rules (which
## moments, cooldowns, effects, autonomy) are `LifePassingPolicy`; this is the
## physical half:
##
##  * a passer who has been spoken to is held: they stop where they are, turn to
##    face the Lifelet and answer with a gesture, and are released the moment
##    the action ends however it ends (finished, cancelled, replaced, saved and
##    reloaded, or the Lifelet walks away), with a short timer in the street
##    itself as a backstop;
##  * the Lifelet walks to a clear spot a conversational metre from the passer
##    on the house side (a pat for a dog is closer), through the ordinary route
##    and queue machinery, so a passing moment persists through a save;
##  * a passer who has gone (or a Lifelet who cannot get there in time) cancels
##    the moment with a notice instead of leaving anybody standing in limbo.

## How far a hello carries along a clear line of sight, in metres.
const REACH: float = 18.0
const STAND_OFF: float = 0.95
const PET_STAND_OFF: float = 0.62
## Game minutes an approach may take before the moment is given up.
const APPROACH_LIMIT: float = 45.0

const LINES: Dictionary = {
	"wave_to_passer": ["Hi!", "Morning!"],
	"greet_passer": ["Hello there!", "Hi, how are you?"],
	"passing_chat": ["Lovely day, isn't it?", "Have you got a minute?"],
	"compliment_passer_dog": ["What a gorgeous dog!", "Aren't you handsome!"],
	"greet_passing_pet": ["Hello, you!", "Hello, good dog!"],
	"pet_passing_pet": ["Who's a good dog?", "Good dog!"],
}
const REPLIES: Dictionary = {
	"child": ["Hi! I'm going to play.", "Hello!"],
	"teen": ["Hey.", "Oh, hi!"],
	"adult": ["Hello, nice to see you.", "Morning! Lovely weather."],
	"elder": ["Well, hello there.", "Good to see a friendly face."],
}

var app: Node
var _waited: Dictionary = {}
var _dropped: Dictionary = {}
var _spoken: Dictionary = {}
var _replied: Dictionary = {}
## A loaded instruction was already admitted before saving. The old format
## did not save street positions; let it approach the reconstructed passer even
## if that new position is temporarily out of sight from the saved Lifelet.
var _restored: Dictionary = {}


func _init(controller: Node) -> void:
	app = controller


func owns(action: Dictionary) -> bool:
	return str(action.get("id", "")) in LifePassingPolicy.ALL


func restore_actions(had_street_snapshot: bool) -> void:
	_restored.clear()
	for member: Dictionary in app.household.members:
		var admitted: Array = []
		for action: Dictionary in member.sim.action_queue:
			if not owns(action): continue
			var passer: Dictionary = app.street_life.find(str(action.get("target_id", "")))
			if passer.is_empty() or not bool(passer.active): continue
			admitted.append(action)
			if is_same(action, member.sim.get_current_action()):
				app.street_life.hold(str(passer.id), str(member.id))
				if not had_street_snapshot and str(action.get("phase", "")) == "active": action.phase = "approach"
		if not admitted.is_empty(): _restored[str(member.id)] = admitted


func _restored_target(member_id: String, passer_id: String) -> bool:
	var member: LifeSim = app.household.member_sim(member_id)
	if member == null: return false
	for action: Dictionary in _restored.get(member_id, []):
		if str(action.get("target_id", "")) != passer_id: continue
		for queued: Dictionary in member.action_queue:
			if is_same(action, queued): return true
	return false


## The passers this Lifelet can hail right now: on the ground floor, within
## reach and with no wall between. These become the sim's `passer` targets, so
## an indoor Lifelet's menu shows the moments disabled with the reason.
func targets_for(member_id: String) -> Array:
	var result: Array = []
	var street: LifeStreetLife = app.street_life
	if street == null or app.current_venue != "home" or not is_instance_valid(app.world):
		return result
	var actor: LifeActor = app.world.actors.get(member_id)
	if not is_instance_valid(actor) or not actor.visible or bool(actor.get_meta("away", false)):
		return result
	if app.world.point_level(actor.position) != 0:
		return result
	for passer: Dictionary in street.visible_passers():
		var at: Vector3 = street.position_of(passer)
		var visible: bool = actor.position.distance_to(at) <= REACH and app.world.sight_line_clear(actor.position, at)
		if not visible and not _restored_target(member_id, str(passer.id)):
			continue
		# Retaining an admitted instruction does not admit a new request
		# through a wall. Policy still uses actual visibility for the menu.
		result.append({"id": str(passer.id), "kind": "passer", "position": at, "passer_kind": str(passer.kind), "name": str(passer.name), "walks_dog": walks_dog(str(passer.id)), "visible": visible})
	return result


func walks_dog(passer_id: String) -> bool:
	for other: Dictionary in app.street_life.passers:
		if str(other.get("follows", "")) == passer_id:
			return true
	return false


## The player's click on a menu entry: check it, find a place to stand, queue it.
func queue(item: Dictionary, action_id: String) -> void:
	var street: LifeStreetLife = app.street_life
	var passer: Dictionary = street.find(str(item.get("id", ""))) if street != null else {}
	if passer.is_empty() or not bool(passer.active):
		app.show_notice("They have already walked on.")
		return
	var sim: LifeSim = app.sim
	if sim.is_away():
		app.show_notice("This Lifelet will be available after coming home.")
		return
	var availability: Dictionary = sim.get_action_availability(action_id, str(passer.id))
	if not bool(availability.available):
		app.show_notice(str(availability.reason))
		return
	var stand: Vector3 = stand_point(passer, app.bound_member_id)
	if not stand.is_finite():
		app.show_notice("There is no clear place to stand beside them.")
		return
	if not sim.queue_action(action_id, str(passer.id), stand):
		return
	# Remember who it was for, so the notice can name them even after a save.
	for queued: Dictionary in sim.action_queue:
		if str(queued.get("id", "")) == action_id and str(queued.get("target_id", "")) == str(passer.id) and not queued.has("passer_name"):
			queued["passer_name"] = str(passer.name)
	app.refresh_hud()


## A clear spot on the house side of the passer, a conversational metre away (a
## pat for a dog is closer), reachable on foot. Candidates are tried nearest-route
## first; every one must be walkable, free of bodies and in sight of the passer.
func stand_point(passer: Dictionary, member_id: String) -> Vector3:
	var street: LifeStreetLife = app.street_life
	var actor: LifeActor = app.world.actors.get(member_id)
	if not is_instance_valid(actor):
		return Vector3.INF
	var at: Vector3 = street.position_of(passer)
	var off: float = PET_STAND_OFF if str(passer.kind) == "pet" else STAND_OFF
	var diagonal: float = off * 0.72
	var offsets: Array[Vector3] = [Vector3(0, 0, -off), Vector3(-diagonal, 0, -diagonal), Vector3(diagonal, 0, -diagonal), Vector3(-off, 0, 0), Vector3(off, 0, 0), Vector3(0, 0, off), Vector3(-diagonal, 0, diagonal), Vector3(diagonal, 0, diagonal)]
	var best: Vector3 = Vector3.INF
	var best_length: float = INF
	for offset: Vector3 in offsets:
		var point: Vector3 = at + offset
		point.x = snappedf(point.x, .25)
		point.z = snappedf(point.z, .25)
		point.y = LifeStreetLife.HEIGHT
		if not stand_clear(point, at, str(passer.kind) == "pet", member_id):
			continue
		var length: float = actor.position.distance_to(point)
		if actor.position.distance_to(point) > 1.0:
			var route: PackedVector3Array = app.traversal._floor_route(actor.position, point, member_id)
			if route.is_empty():
				continue
			length = 0.0
			for index: int in range(1, route.size()):
				length += route[index - 1].distance_to(route[index])
		if length < best_length:
			best_length = length
			best = point
	return best


func stand_clear(point: Vector3, passer_at: Vector3, pet: bool, member_id: String) -> bool:
	if not point.is_finite() or app.world.point_level(point) != 0:
		return false
	var distance: float = Vector2(point.x - passer_at.x, point.z - passer_at.z).length()
	if distance < (0.45 if pet else 0.75) or distance > (1.3 if pet else 1.7):
		return false
	if not app.world.lot_navigation.point_clear(0, point) or not app.world.sight_line_clear(point, passer_at):
		return false
	return app.traversal._free(member_id, point)


## The action began (or was restarted after a load, a replan or a route change)
## for the bound Lifelet: pick the spot, hold the passer, walk there.
func prepare(action: Dictionary) -> void:
	var street: LifeStreetLife = app.street_life
	var member_id: String = app.bound_member_id
	var passer: Dictionary = street.find(str(action.get("target_id", ""))) if street != null else {}
	if passer.is_empty() or not bool(passer.active):
		_fail(action, "They have already walked on.")
		return
	var at: Vector3 = street.position_of(passer)
	var stand: Vector3 = Vector3(action.get("target_position", Vector3.INF))
	if not (stand.is_finite() and stand_clear(stand, at, str(passer.kind) == "pet", member_id)):
		stand = stand_point(passer, member_id)
	if not stand.is_finite():
		_fail(action, "There is no clear place to stand beside them.")
		return
	street.hold(str(passer.id), member_id)
	app._clear_motion()
	action.target_position = stand
	app.pending_action = action
	if not app._set_route(stand):
		_fail(action, "The way is blocked. Try moving a furnishing.")
		return
	app.refresh_hud()


func _fail(action: Dictionary, message: String) -> void:
	# Only the selected Lifelet's refusals, or one the player asked for, reach the
	# notice card: a housemate's own passing moment failing is not the player's news.
	if app.bound_member_id == app.household.selected_id() or not bool(action.get("autonomous", false)):
		app.show_notice(message)
	app._cancel_blocked_action.call_deferred(app.route_generation, action, app.bound_member_id, app.load_epoch)


## Once a frame at home: keep every spoken-to passer held while somebody is on
## the way to or in a moment with them, animate the moment, give up on the ones
## that cannot happen, and release everyone else.
func tick(delta: float) -> void:
	var street: LifeStreetLife = app.street_life
	if street == null or not is_instance_valid(app.world):
		return
	var game_minutes: float = delta * float(app.household.speed) * LifeSim.GAME_MINUTES_PER_SECOND
	var engaged: Dictionary = {}
	var poses: Dictionary = {}
	for member: Dictionary in app.household.members:
		var id: String = str(member.id)
		var action: Dictionary = member.sim.get_current_action()
		if action.is_empty() or not owns(action):
			_waited.erase(id)
			_spoken.erase(id)
			continue
		var phase: String = str(action.get("phase", ""))
		if phase not in ["approach", "active"]:
			continue
		var passer: Dictionary = street.find(str(action.get("target_id", "")))
		if passer.is_empty() or not bool(passer.active):
			_drop(id, action, "They have already walked on.")
			continue
		if is_same(_dropped.get(id), action):
			continue
		for entry: Dictionary in street.party_of(str(passer.id)):
			engaged[str(entry.id)] = id
		street.hold(str(passer.id), id)
		if phase == "approach":
			_waited[id] = float(_waited.get(id, 0.0)) + game_minutes
			if float(_waited[id]) > APPROACH_LIMIT:
				_drop(id, action, "%s did not wait around." % str(passer.name))
				continue
			_retarget(id, action, passer)
		else:
			_waited.erase(id)
			_present(id, action, passer, poses, delta)
	for passer: Dictionary in street.passers:
		if str(passer.holder) != "" and not engaged.has(str(passer.id)):
			street.release(str(passer.id))
	if app.street_bodies != null:
		app.street_bodies.poses = poses


## The moment is under way: the Lifelet turns to the passer, the passer answers
## with a gesture, and each says a line once.
func _present(member_id: String, action: Dictionary, passer: Dictionary, poses: Dictionary, delta: float) -> void:
	var actor: LifeActor = app.world.actors.get(member_id)
	if not is_instance_valid(actor):
		return
	var at: Vector3 = app.street_life.position_of(passer)
	var toward: Vector3 = at - actor.position
	toward.y = 0.0
	if toward.length() > .05:
		actor.rotation.y = lerp_angle(actor.rotation.y, atan2(toward.x, toward.z), minf(delta * 6.0, 1.0))
	var id: String = str(action.id)
	var progress: float = clampf(float(action.get("elapsed", 0.0)) / maxf(1.0, float(action.get("duration", 1.0))), 0.0, 1.0)
	var pet: bool = str(passer.kind) == "pet"
	var body: Node3D = app.street_bodies.body_of(str(passer.id)) if app.street_bodies != null else null
	if not is_same(_spoken.get(member_id), action):
		_spoken[member_id] = action
		_replied.erase(member_id)
		var lines: Array = LINES.get(id, ["Hello!"])
		actor.speech(str(lines[abs(("%s|%s" % [member_id, passer.id]).hash()) % lines.size()]))
		if pet and body is LifePetActor and app.sound_enabled and id == "greet_passing_pet":
			(body as LifePetActor).bark()
	if not is_same(_replied.get(member_id), action) and progress >= .35:
		_replied[member_id] = action
		if body is LifeActor:
			var replies: Array = REPLIES.get(str(passer.kind), ["Hello!"])
			(body as LifeActor).speech(str(replies[abs(("%s|%s" % [passer.id, member_id]).hash()) % replies.size()]))
	if pet:
		if body is LifePetActor:
			if id == "pet_passing_pet":
				(body as LifePetActor).set_interaction("pet_pet", float(action.get("elapsed", 0.0)), actor.position)
			else:
				(body as LifePetActor).clear_interaction()
	else:
		# A wave is answered with a wave, everything else with the gestures of a
		# friendly chat.
		poses[str(passer.id)] = "wave_to_passer" if id == "wave_to_passer" else "friendly"


## A route that started before the passer stopped (or before a load) may end
## somewhere the passer no longer is: walk to the right spot instead.
func _retarget(member_id: String, action: Dictionary, passer: Dictionary) -> void:
	var at: Vector3 = app.street_life.position_of(passer)
	var stand: Vector3 = Vector3(action.get("target_position", Vector3.INF))
	if stand.is_finite() and Vector2(stand.x - at.x, stand.z - at.z).length() <= 2.0:
		return
	var prior: String = app.bound_member_id
	app._store_motion()
	app._bind_member(member_id)
	prepare(action)
	app._store_motion()
	app._bind_member(prior)


## Give up on a moment that can no longer happen: name why, and cancel it through
## the ordinary blocked-action route so the queue carries on.
func _drop(member_id: String, action: Dictionary, message: String) -> void:
	if is_same(_dropped.get(member_id), action):
		return
	_dropped[member_id] = action
	if member_id == app.household.selected_id() or not bool(action.get("autonomous", false)):
		app.show_notice(message)
	var stored: Dictionary = app.motion_states.get(member_id, {})
	app._cancel_blocked_action.call_deferred(int(stored.get("generation", 0)), action, member_id, app.load_epoch)
