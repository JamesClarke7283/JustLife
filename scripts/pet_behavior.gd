extends RefCounted
class_name LifePetBehavior
## Runtime pet actions. Saved care stays in the household; routes, furniture
## access and audio are transient, so older saves require no new fields.

const REST_MINUTES: float = 120.0
const PLAY_MINUTES: float = 30.0
const WALK_SPEED: float = 1.4
const URGENT: float = 35.0
var app: Node
var idle_minutes: Dictionary = {}
var turns: Dictionary = {}
var muted: Dictionary = {}
var toy_claims: Dictionary = {}
var introductions: Dictionary = {}
var agility_obstacles: Dictionary = {}
var agility_props: Dictionary = {}
## Pets that really stepped on the last tick. A pet held up by a wall or a body
## is not in this set, so it stands and looks around instead of trotting in place.
var moved_ids: Dictionary = {}
## Game minutes a pet waits before it looks for another autonomous errand after
## one could not start, so a pet with nowhere to go does not replan every frame.
var cooldown: Dictionary = {}
## Where the last failed route ran between, for the notice that names the item.
var route_failure: Dictionary = {}
## Game time of each pet's last "cannot reach" notice.
var notified: Dictionary = {}
const BLOCKED_TIMEOUT: float = 12.0   # scaled seconds a walking pet may be held before it gives the errand up
const STAIR_TIMEOUT: float = 25.0     # the same on a staircase, where it is put back on a landing
const ACCESS_TIMEOUT: float = 6.0     # scaled seconds a pet may wait to enter or leave a bed or a kennel
const RETRY_MINUTES: float = 3.0
const NOTICE_MINUTES: float = 90.0

func _init(owner_app: Node) -> void:
	app = owner_app

func state(id: String) -> Dictionary:
	var activity: Dictionary = app.pet_errands.get(id, {})
	return {
		"action": str(activity.get("action", "idle")),
		"phase": str(activity.get("phase", "idle")),
		"label": str(activity.get("label", "Exploring the home")),
		"elapsed_minutes": float(activity.get("elapsed", 0.0)),
		"squeaking": str(activity.get("action", "")) == "pet_play_toys" and not bool(muted.get(id, false)),
		"traits": ["Curious", "Playful", "Independent" if _species(id) == "cat" else "Sociable"],
	}

func commands(id: String) -> Array[Dictionary]:
	if app.household.pet_record(id).is_empty(): return []
	var cat: bool = _species(id) == "cat"
	var result: Array[Dictionary] = [
		{"id": "pet_eat", "label": "Feed the Cat" if cat else "Feed the Dog"},
		{"id": "pet_go_bed", "label": "Go to Cat Bed" if cat else "Go to Dog Bed"},
		{"id": "pet_cat_tree" if cat else "pet_go_dog_house", "label": "Command to Play on Cat Tree" if cat else "Go to Dog House"},
		{"id": "pet_play_toys", "label": "Play with Toys"},
	]
	var action: String = str(state(id).action)
	if action == "pet_play_toys" and not bool(muted.get(id, false)):
		result.append({"id": "pet_stop_squeaking", "label": "Stop Squeaking"})
	if action in ["pet_play_toys", "pet_cat_tree"]:
		result.append({"id": "pet_stop_playing", "label": "Stop Playing"})
	for entry: Dictionary in result:
		var reason: String = _availability(id, str(entry.id))
		entry["disabled"] = not reason.is_empty()
		entry["available"] = reason.is_empty()
		entry["unavailable_reason"] = reason
	return result

func command(id: String, action: String, ground: Vector3 = Vector3.INF) -> Dictionary:
	var actor: LifePetActor = app.pet_actors.get(id)
	if not is_instance_valid(actor): return _failure("That pet is not at home.")
	if action == "pet_move" and (not ground.is_finite() or not app.world.lot_navigation.point_clear(app.world.point_level(ground), ground)):
		return _failure(_named_blocker(actor.position, ground, "Choose a clear, supported spot on the ground or floor.", [], true))
	if action == "pet_move_out":
		ground = _clearance_spot(id)
		if not ground.is_finite(): return _failure("There is no clear space nearby. Leave a path around the dog.")
		action = "pet_move"
	var walking: Dictionary = app.pet_errands.get(id, {})
	if action != "pet_stop_squeaking" and str(walking.get("phase", "")) == "walking" and app.world.point_level(actor.position) < 0:
		walking["pending_command"] = {"action": action, "ground": ground}
		return {"ok": true, "message": "%s will follow that command at the stair landing." % actor.display_name}
	if action == "pet_stop_squeaking":
		muted[id] = true
		actor.stop_squeak()
		return {"ok": true, "message": "%s will play quietly." % actor.display_name}
	if action == "pet_stop_playing":
		_finish(id, actor, {})
		idle_minutes[id] = -35.0
		actor.stop_squeak()
		return {"ok": true, "message": "%s has stopped playing." % actor.display_name}
	var reason: String = _availability(id, action)
	if not reason.is_empty(): return _failure(reason)
	_interrupt_care(id)
	var old: Dictionary = app.pet_errands.get(id, {})
	if str(old.get("phase", "")) in ["entering", "using", "exiting"] and bool(old.get("inside", false)):
		_finish(id, actor, {"action": action, "ground": ground})
		return {"ok": true, "message": "%s is coming out first." % actor.display_name}
	_release_toy(id)
	_release_course(id)
	app.pet_errands.erase(id)
	app.pet_arrivals.erase(id)
	actor.clear_behavior()
	actor.clear_interaction()
	actor.stop_squeak()
	var ok: bool = _start(id, action, true, ground)
	if not ok: return _failure(_blocked_message("There is no clear route to that spot. Leave space around the furnishing."))
	idle_minutes[id] = 0.0
	return {"ok": true, "message": "%s: %s" % [actor.display_name, state(id).label]}

## Player movement owns the pet immediately, even during a Lifelet's feeding
## beat. Cancel that beat as well as its pose so it cannot reclaim the dog.
func _interrupt_care(id: String) -> void:
	app.pending_pet_care.erase(id)
	var care: RefCounted = app.care_motion()
	for member_id: String in care.sessions.keys():
		if str(care.sessions[member_id].pet) == id: care._release(member_id)
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		for index: int in range(sim.action_queue.size() - 1, -1, -1):
			var action: Dictionary = sim.action_queue[index]
			if str(action.get("target_id", "")) == id and str(action.get("id", "")) in LifePetCare.interaction_ids(): sim.cancel_action(index)

func _clearance_spot(id: String) -> Vector3:
	var actor: LifePetActor = app.pet_actors[id]
	var from: Vector3 = actor.position
	var old: Dictionary = app.pet_errands.get(id, {})
	if bool(old.get("inside", false)): from = old.get("entry", from)
	var nearest: Vector3 = from + actor.basis.z
	var distance: float = 3.0
	for item: Dictionary in app.world.items:
		if not is_instance_valid(item.get("node")) or app.world.item_level(item) != actor.floor_level: continue
		var gap: float = from.distance_to(item.node.position)
		if gap < distance: nearest = item.node.position; distance = gap
	distance = from.distance_to(nearest)
	var away: Vector3 = from - nearest; away.y = 0.0
	if away.length() < .01: away = -actor.basis.z
	away = away.normalized()
	for radius: float in [1.5, 2.0, 1.0, 2.5]:
		for angle: float in [0.0, .55, -.55, 1.1, -1.1, PI]:
			var at: Vector3 = from + away.rotated(Vector3.UP, angle) * radius
			if not app.world.lot_navigation.point_clear(actor.floor_level, at): continue
			if at.distance_to(nearest) < distance + .45: continue
			if bool(_route(id, from, at).get("ok", false)): return at
	return Vector3.INF

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "message": message}

func _species(id: String) -> String:
	return str(app.household.pet_record(id).get("species", "cat"))

func _availability(id: String, action: String) -> String:
	if action == "pet_cat_tree" and _species(id) != "cat": return "Only cats use a cat tree."
	if action == "pet_go_dog_house" and _species(id) != "dog": return "Only dogs use a dog house."
	if action.begins_with("pet_trick:"):
		var trick: String = action.trim_prefix("pet_trick:").get_slice("@", 0)
		if not trick in LifePetCare.known_tricks(app.household.pet_care(id)): return "Train Clever Tricks to learn this trick first."
		if trick == "fetch" and _target(id, "pet_play_toys").is_empty(): return "Place a dog toy to fetch first."
		return ""
	if action in ["pet_stop_squeaking", "pet_stop_playing", "pet_move", "wander", "relieve"]: return ""
	if action not in ["pet_eat", "pet_go_bed", "pet_go_dog_house", "pet_cat_tree", "pet_play_toys"]: return "Unknown pet command."
	if _target(id, action).is_empty():
		return {"pet_eat": "Place a food bowl first.", "pet_go_bed": "Place a %s bed first." % _species(id), "pet_go_dog_house": "Place a dog house outdoors first.", "pet_cat_tree": "Place a cat tree first.", "pet_play_toys": "Buy a toy or a toy box for this pet first."}.get(action, "Place the pet furnishing first.")
	return ""

func _target(id: String, action: String) -> Dictionary:
	var actor: LifePetActor = app.pet_actors.get(id)
	if not is_instance_valid(actor): return {}
	var kind: String = {"pet_eat": "pet_bowl", "pet_go_bed": "pet_bed_" + _species(id), "pet_go_dog_house": "kennel", "pet_cat_tree": "cat_tree", "relieve": "litter_tray"}.get(action, "")
	var best: Dictionary = {}
	var distance: float = INF
	for item: Dictionary in app.world.items:
		if not is_instance_valid(item.get("node")): continue
		if action == "pet_play_toys":
			if str(item.kind) != "pet_toy_" + _species(id) or bool(item.get("held", false)): continue
			if toy_claims.has(str(item.id)) and str(toy_claims[str(item.id)]) != id: continue
		elif str(item.kind) != kind: continue
		# The kennel itself makes its cell solid. Test the underlying lot/floor,
		# rather than outdoor_cell(), which is intended for empty walking cells.
		if action == "pet_go_dog_house" and (app.world.item_level(item) != 0 or app.world.construction.floor_contains(Vector2(item.node.position.x, item.node.position.z), 0)): continue
		var care: Dictionary = app.household.pet_care(id)
		var logic: int = LifePetCare.level(care, "logic")
		var access: Dictionary = _item(str(item.box_id)) if action == "pet_play_toys" and not str(item.get("box_id", "")).is_empty() else item
		if logic >= 5 and (access.is_empty() or not _approach(id, access, action, actor.position).is_finite()): continue
		var gap: float = actor.position.distance_squared_to(item.node.position)
		if logic >= 5 and str(item.id) in care.get("familiar_items", []): gap *= .75
		if gap < distance: best = item; distance = gap
	return best

func tick(delta: float, speed: float) -> bool:
	if delta <= 0.0 or speed <= 0.0: return false
	var minutes: float = delta * speed * LifeSim.GAME_MINUTES_PER_SECOND
	var moved: bool = false
	moved_ids.clear()
	for id: String in app.pet_actors.keys():
		var actor: LifePetActor = app.pet_actors.get(id)
		if not is_instance_valid(actor) or app.pet_arrivals.has(id): continue
		if app.care_motion().holds(id):
			actor.clear_behavior()
			actor.stop_squeak()
			continue
		var record: Dictionary = app.household.pet_record(id)
		if record.is_empty(): continue
		var care: Dictionary = app.household.pet_care(id)
		var needs: Dictionary = care.needs
		recover_overlap(id, actor)
		_react_to_company(id, actor, care, minutes)
		if _species(id) == "cat": needs.hygiene = minf(100.0, float(needs.hygiene) + minutes * 0.10)
		if (app.pet_errands.get(id, {}) as Dictionary).is_empty():
			idle_minutes[id] = float(idle_minutes.get(id, 0.0)) + minutes
			cooldown[id] = maxf(0.0, float(cooldown.get(id, 0.0)) - minutes)
			var action: String = _choose(id, needs) if float(cooldown.get(id, 0.0)) <= 0.0 else ""
			if not action.is_empty() and not _start(id, action, false): _could_not_start(id, action)
		if not (app.pet_errands.get(id, {}) as Dictionary).is_empty():
			if _advance(id, actor, needs, minutes, delta * speed):
				moved = true
				moved_ids[id] = true
	return moved

## An autonomous errand that found no way to start waits a few game minutes
## before the next try, and a pet whose urgent need is walled off says which item
## to move, at most once every ninety game minutes.
func _could_not_start(id: String, action: String) -> void:
	cooldown[id] = RETRY_MINUTES
	if route_failure.is_empty() or action not in ["pet_eat", "pet_go_bed", "pet_go_dog_house", "pet_cat_tree"]: return
	var now: float = float(app.household.day) * 1440.0 + float(app.household.minutes)
	if now - float(notified.get(id, -1000000.0)) < NOTICE_MINUTES: return
	var message: String = _blocked_message("")
	if message.begins_with("Please move"):
		notified[id] = now
		app.show_blocked_notice(message)

## The notice for the route that last failed: the placed item in the way, or
## `fallback` when no item is responsible. Read once, then forgotten.
func _blocked_message(fallback: String) -> String:
	var failure: Dictionary = route_failure
	route_failure = {}
	if failure.is_empty(): return fallback
	return _named_blocker(failure.from, failure.to, fallback, failure.get("ignore", []), false)

## Name the placed item between two spots. `items_only` keeps a wall or a
## staircase out of the answer for a spot that is itself refused, where the
## plain reason reads better.
func _named_blocker(from: Vector3, to: Vector3, fallback: String, ignore: Array, items_only: bool) -> String:
	var from_level: int = app.world.point_level(from)
	var to_level: int = app.world.point_level(to)
	if from_level < 0 or to_level < 0: return fallback
	var blocker: Dictionary = app.world.lot_navigation.blocker_between(from_level, from, to_level, to, ignore)
	if items_only and not LifeLotNavigation.is_item_source(blocker): return fallback
	return app.world.blocker_notice(blocker, fallback)

## A pet found inside a solid footprint (a furnishing set down over it, a step
## that slipped past a thin edge) is lifted to the nearest clear floor and its
## errand is dropped. Pets that are meant to be inside one - on a bed, in the
## kennel, up the cat tree - or that a Lifelet is caring for are left alone.
func recover_overlap(id: String, actor: LifePetActor) -> bool:
	var errand: Dictionary = app.pet_errands.get(id, {})
	if bool(errand.get("inside", false)) or actor.traversing_stairs or app.care_motion().holds(id): return false
	var level: int = app.world.point_level(actor.position)
	if level < 0 or app.world.lot_navigation.point_clear(level, actor.position): return false
	var clear: Vector3 = app.world.nearest_clear_point(actor.position, level, 8)
	if not clear.is_finite(): return false
	actor.position = clear
	actor.floor_level = level
	if not errand.is_empty(): _finish(id, actor, {})
	return true

## New guests and animals are a brief hesitation during autonomous activity;
## social practice shortens it and makes company a source of happiness.
func _react_to_company(id: String, actor: LifePetActor, care: Dictionary, minutes: float) -> void:
	var seen: Dictionary = introductions.get(id, {})
	var social: int = LifePetCare.level(care, "social")
	var company: Dictionary = app.world.actors.duplicate()
	company.merge(app.pet_actors)
	for other: String in company:
		if other == id: continue
		var body: Node3D = company[other]
		if not is_instance_valid(body) or not body.visible or absf(body.position.y - actor.position.y) > .3 or body.position.distance_to(actor.position) > 2.5: continue
		var errand: Dictionary = app.pet_errands.get(id, {})
		if not seen.has(other) and not errand.is_empty() and not bool(errand.commanded):
			errand["caution"] = maxf(float(errand.get("caution", 0.0)), float(10 - social) * .2)
		seen[other] = true
		if social > 1:
			care.needs.social = minf(100.0, float(care.needs.social) + minutes * float(social - 1) * .03)
			care.needs.fun = minf(100.0, float(care.needs.fun) + minutes * float(social - 1) * .02)
	introductions[id] = seen

func _choose(id: String, needs: Dictionary) -> String:
	if float(needs.hunger) < URGENT and not _target(id, "pet_eat").is_empty(): return "pet_eat"
	if float(needs.energy) < URGENT:
		if _species(id) == "dog" and int(turns.get(id, 0)) % 2 == 1 and not _target(id, "pet_go_dog_house").is_empty(): return "pet_go_dog_house"
		if not _target(id, "pet_go_bed").is_empty(): return "pet_go_bed"
		if _species(id) == "dog" and not _target(id, "pet_go_dog_house").is_empty(): return "pet_go_dog_house"
	if float(needs.bladder) < URGENT: return "relieve"
	if float(idle_minutes.get(id, 0.0)) < 8.0: return ""
	var cycle: int = int(turns.get(id, 0)) % 4
	if _species(id) == "cat" and (cycle == 1 or float(needs.fun) < URGENT) and not _target(id, "pet_cat_tree").is_empty(): return "pet_cat_tree"
	if _species(id) == "dog" and cycle == 1 and not _target(id, "pet_go_dog_house").is_empty(): return "pet_go_dog_house"
	if (cycle == 2 or float(needs.fun) < URGENT) and not _target(id, "pet_play_toys").is_empty(): return "pet_play_toys"
	if cycle == 3 and float(needs.energy) < 80.0 and not _target(id, "pet_go_bed").is_empty(): return "pet_go_bed"
	return "wander"

func _start(id: String, action: String, commanded: bool, ground: Vector3 = Vector3.INF) -> bool:
	route_failure = {}
	if action.begins_with("pet_trick:"): return _start_trick(id, action)
	var actor: LifePetActor = app.pet_actors.get(id)
	var level: int = app.world.point_level(actor.position)
	if level >= 0: actor.floor_level = level
	var target: Dictionary = _target(id, action)
	var access: Dictionary = target
	if action == "pet_play_toys" and not str(target.get("box_id", "")).is_empty(): access = _item(str(target.box_id))
	var at: Vector3 = ground
	if action == "wander": at = _wander_spot(id, actor.position)
	elif action == "relieve" and (_species(id) == "dog" or target.is_empty()):
		target = {}; access = {}; at = app._pet_outdoor_spot("bladder")
	elif action != "pet_move":
		if target.is_empty() or access.is_empty(): return false
		at = _approach(id, access, action, actor.position)
		# Every side of the furnishing is walled off: the goal is the piece itself,
		# and the item to name is whatever rings it, never the piece.
		if not at.is_finite() and is_instance_valid(access.get("node")):
			route_failure = {"from": actor.position, "to": Vector3(access.node.position.x, LifeBuildingState.level_y(app.world.item_level(access)), access.node.position.z), "ignore": [str(access.get("id", ""))]}
	if not at.is_finite(): return false
	var route: Dictionary = _route(id, actor.position, at)
	if not bool(route.get("ok", false)):
		route_failure = {"from": actor.position, "to": at, "ignore": [str(access.get("id", ""))]}
		return false
	var path: PackedVector3Array = route.points
	var labels: Dictionary = {"pet_eat": "Walking to the food bowl", "pet_go_bed": "Going to bed", "pet_go_dog_house": "Going to the dog house", "pet_cat_tree": "Going to the cat tree", "pet_play_toys": "Fetching a toy", "pet_move": "Moving to your chosen spot", "wander": "Exploring the home", "relieve": "Taking a toilet break"}
	app.pet_errands[id] = {"action": action, "label": labels.get(action, action), "travel_label": labels.get(action, action), "kind": str(target.get("kind", "outdoors")), "target": str(target.get("id", "")), "access": str(access.get("id", "")), "at": at, "entry": at, "path": path, "segments": route.segments, "index": 0, "phase": "walking", "walking": true, "elapsed": 0.0, "commanded": commanded, "inside": false, "squeak_at": 0.0, "blocked": 0.0}
	if not commanded and not target.is_empty():
		var care: Dictionary = app.household.pet_care(id)
		if not str(target.id) in care.get("familiar_items", []):
			app.pet_errands[id]["caution"] = float(10 - LifePetCare.level(care, "social")) * .2
	if action == "pet_play_toys": toy_claims[str(target.id)] = id
	idle_minutes[id] = 0.0
	turns[id] = int(turns.get(id, 0)) + 1
	actor.traversing_stairs = false
	actor.clear_behavior()
	return true

func _approach(id: String, item: Dictionary, action: String, from: Vector3) -> Vector3:
	var node: Node3D = item.node
	# A kennel has one doorway, a cat tree's wrapped post is behind its cubby.
	var offsets: Array[Vector3] = []
	if action == "pet_go_dog_house": offsets = [Vector3(0, 0, .92), Vector3(0, 0, 1.17)]
	elif action == "pet_cat_tree": offsets = [Vector3(0, 0, -.72), Vector3(.55, 0, -.55)]
	elif action == "pet_play_toys" and str(item.kind).begins_with("pet_toy_"):
		var reach: float = .32 if _species(id) == "cat" else .45
		offsets = [Vector3(reach, 0, 0), Vector3(-reach, 0, 0), Vector3(0, 0, reach), Vector3(0, 0, -reach)]
	else: offsets = [Vector3(.75, 0, 0), Vector3(-.75, 0, 0), Vector3(0, 0, .75), Vector3(0, 0, -.75), Vector3(.6, 0, .6), Vector3(-.6, 0, .6), Vector3(.6, 0, -.6), Vector3(-.6, 0, -.6), Vector3(.95, 0, 0), Vector3(0, 0, .95)]
	for offset: Vector3 in offsets:
		var at: Vector3 = node.position + node.basis * offset
		at.y = LifeBuildingState.level_y(app.world.item_level(item))
		if not app.world.lot_navigation.point_clear(app.world.item_level(item), at): continue
		if not bool(_route(id, from, at).get("ok", false)): continue
		return at
	return Vector3.INF

func _wander_spot(id: String, from: Vector3) -> Vector3:
	var cycle: int = int(turns.get(id, 0))
	var level: int = app.world.point_level(from)
	for attempt: int in range(12):
		var angle: float = float(abs(id.hash()) % 360) * PI / 180.0 + float(cycle + attempt) * 2.39996
		var radius: float = 1.25 + float(attempt % 4) * .65
		var at: Vector3 = from + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if not app.world.lot_navigation.point_clear(level, at): continue
		if bool(_route(id, from, at).get("ok", false)): return at
	return Vector3.INF

func _route(id: String, from: Vector3, to: Vector3) -> Dictionary:
	var occupied: Array[Vector3] = []
	for other: String in app.world.actors:
		var body: Node3D = app.world.actors[other]
		if is_instance_valid(body) and body.visible: occupied.append(body.position)
	for other: String in app.pet_actors:
		var body: Node3D = app.pet_actors[other]
		if other != id and is_instance_valid(body) and body.visible: occupied.append(body.position)
	for poles: Array in agility_obstacles.values():
		for pole: Vector3 in poles: occupied.append(pole)
	return app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(app.world.point_level(from), from), LifeLotNavigation.floor_location(app.world.point_level(to), to), occupied, LifeTraversal.ROUTE_CLEARANCE)

func _advance(id: String, actor: LifePetActor, needs: Dictionary, minutes: float, seconds: float) -> bool:
	var errand: Dictionary = app.pet_errands[id]
	var target: Dictionary = _item(str(errand.target))
	if not str(errand.target).is_empty() and target.is_empty() and str(errand.phase) != "exiting":
		_finish(id, actor, {})
		return false
	if str(errand.action) == "pet_perform_trick" and str(errand.phase) == "using":
		return _perform_trick(id, actor, errand, minutes)
	match str(errand.phase):
		"walking": return _walk(id, actor, errand, seconds)
		"entering", "exiting": return _access_step(id, actor, errand, seconds)
	# Time on furniture is measured in game minutes, including the kennel's
	# commanded two-hour stay; walking to it never uses up that stay.
	errand.elapsed = float(errand.elapsed) + minutes
	errand.walking = false
	var elapsed: float = float(errand.elapsed)
	var action: String = str(errand.action)
	match action:
		"pet_go_bed", "pet_go_dog_house":
			actor.set_behavior("rest", elapsed)
			errand.label = "Resting in the dog house" if action == "pet_go_dog_house" else "Sleeping in bed"
			needs.energy = minf(100.0, float(needs.energy) + LifePets.SLEEP_PER_HOUR * minutes / 60.0)
			if elapsed >= REST_MINUTES or (not bool(errand.commanded) and elapsed >= 25.0 and float(needs.energy) >= 85.0): _finish(id, actor, {})
		"pet_eat":
			actor.set_behavior("eat", elapsed)
			errand.label = "Eating from the bowl"
			needs.hunger = minf(100.0, float(needs.hunger) + minutes * 5.5)
			if elapsed >= 12.0: _finish(id, actor, {})
		"pet_cat_tree":
			_tree(id, actor, errand, target, elapsed, minutes, needs)
		"pet_play_toys":
			_play(id, actor, errand, target, elapsed, minutes, needs)
		"relieve":
			actor.set_behavior("sniff", elapsed)
			errand.label = "Using the litter tray" if not target.is_empty() else "Taking a toilet break outside"
			if elapsed >= 3.0:
				needs.bladder = 95.0
				_finish(id, actor, {})
		"pet_move", "wander":
			actor.set_behavior("sniff", elapsed)
			if elapsed >= (5.0 if action == "wander" else 12.0): _finish(id, actor, {})
	return false

func _walk(id: String, actor: LifePetActor, errand: Dictionary, seconds: float) -> bool:
	var path: PackedVector3Array = errand.path
	var care: Dictionary = app.household.pet_care(id)
	var social: int = LifePetCare.level(care, "social")
	var logic: int = LifePetCare.level(care, "logic")
	if not bool(errand.commanded) and float(errand.get("caution", 0.0)) > 0.0:
		errand.caution = maxf(0.0, float(errand.caution) - seconds)
		errand.label = "Getting used to an unfamiliar object"
		actor.set_behavior("sniff", float(errand.caution))
		return false
	if errand.has("travel_label"): errand.label = errand.travel_label
	var budget: float = seconds * WALK_SPEED * (1.0 + float(social - 1) * .025)
	var moved: bool = false
	while int(errand.index) < path.size() and budget > 0.0:
		var point: Vector3 = path[int(errand.index)]
		var gap: float = actor.position.distance_to(point)
		if gap <= .00001:
			errand.index = int(errand.index) + 1
			continue
		var step: float = minf(gap, minf(budget, .10))
		var next: Vector3 = actor.position.move_toward(point, step)
		var segments: Array = errand.get("segments", [])
		var segment: Dictionary = segments[int(errand.index) - 1] if int(errand.index) > 0 and int(errand.index) <= segments.size() else {}
		var stair: bool = str(segment.get("kind", "floor")) == "stair"
		actor.traversing_stairs = stair
		var blocked: bool = not _stair_clear(actor, next, segment) if stair else app._pet_step_blocked(actor, next)
		if blocked:
			errand.blocked = float(errand.blocked) + seconds
			errand.replan = float(errand.get("replan", 0.0)) - seconds
			var here: int = app.world.point_level(actor.position)
			# Replanning walks the whole graph, so a held pet tries again twice a
			# second rather than every frame.
			if float(errand.blocked) >= maxf(.2, 1.0 - float(logic - 1) * .09) and here >= 0 and float(errand.replan) <= 0.0:
				errand.replan = .5
				# A refusal by a wall or furnishing (not a body, which moves on) is
				# learned as a Lifelet learns it, so the detour avoids that edge.
				var next_level: int = app.world.point_level(next)
				if not stair and (next_level < 0 or not app.world.lot_navigation.point_clear(next_level, next)):
					app.world.lot_navigation.penalize_segment(here, actor.position, point)
				var detour: Dictionary = _route(id, actor.position, Vector3(errand.at))
				if not bool(detour.get("ok", false)) and logic >= 5 and not str(errand.target).is_empty():
					var furnishing: Dictionary = _item(str(errand.target))
					if not furnishing.is_empty():
						var alternative: Vector3 = _approach(id, furnishing, str(errand.action), actor.position)
						if alternative.is_finite():
							detour = _route(id, actor.position, alternative)
							errand.at = alternative; errand.entry = alternative
				if bool(detour.get("ok", false)): errand.path = detour.points; errand.segments = detour.segments; errand.index = 0
			if float(errand.blocked) > (BLOCKED_TIMEOUT if here >= 0 else STAIR_TIMEOUT): _give_up(id, actor, errand, here)
			return moved
		if gap > .001: actor.rotation.y = atan2(point.x - actor.position.x, point.z - actor.position.z)
		actor.position = next
		if bool(errand.get("carrying", false)):
			var toy: Dictionary = _item(str(errand.target))
			if not toy.is_empty(): toy.node.position = actor.mouth_point()
		errand.blocked = 0.0
		var level: int = app.world.point_level(next)
		if level >= 0: actor.floor_level = level
		budget -= step
		moved = moved or step > 0.0
		if gap <= step + .00001: errand.index = int(errand.index) + 1
		if level >= 0 and app.world.lot_navigation.point_clear(level, next) and errand.has("pending_command"):
			var pending: Dictionary = errand.pending_command
			app.pet_errands.erase(id)
			command(id, str(pending.action), pending.get("ground", Vector3.INF))
			return moved
	if int(errand.index) >= path.size():
		actor.traversing_stairs = false
		errand.walking = false
		errand.phase = "using"
		var target: Dictionary = _item(str(errand.target))
		if not target.is_empty():
			var familiar: Array = care.get("familiar_items", [])
			if not str(target.id) in familiar:
				familiar.append(str(target.id))
				if familiar.size() > 128: familiar.pop_front()
			care["familiar_items"] = familiar
			var toward: Vector3 = target.node.position - actor.position
			if toward.length() > .01: actor.rotation.y = atan2(toward.x, toward.z)
		if str(errand.action) in ["pet_go_bed", "pet_go_dog_house"] and not target.is_empty():
			errand.phase = "entering"
			errand.inside = true
			var node: Node3D = target.node
			errand.inner = node.position + node.basis * (Vector3(0, .10, .02) if str(errand.action) == "pet_go_dog_house" else Vector3(0, .10, 0))
			# A bed's cushion is higher on the dog model.
			if str(errand.kind) == "pet_bed_dog": errand.inner = Vector3(errand.inner) + Vector3(0, .03, 0)
	return moved

func _stair_clear(actor: LifePetActor, next: Vector3, segment: Dictionary) -> bool:
	# Only graph-authored stair edges permit intermediate heights. Arbitrary
	# vertical goals still fail exact-floor endpoint validation in _route().
	var stair_id: String = str(segment.get("stair_id", ""))
	if stair_id.is_empty() or not app.world.lot_navigation.stair_connected(stair_id): return false
	var from: Vector3 = segment.from
	var to: Vector3 = segment.to
	var line: Vector3 = to - from
	var part: float = clampf((next - from).dot(line) / maxf(line.length_squared(), .000001), 0.0, 1.0)
	if next.distance_to(from.lerp(to, part)) > .001: return false
	return app._pet_path_clear(actor, actor.position, next)

func _access_step(id: String, actor: LifePetActor, errand: Dictionary, seconds: float) -> bool:
	var leaving: bool = str(errand.phase) == "exiting"
	var destination: Vector3 = errand.entry if leaving else errand.inner
	var next: Vector3 = actor.position.move_toward(destination, seconds * .65)
	var target: Dictionary = _item(str(errand.access))
	if not _access_clear(actor, actor.position, next, target):
		# Held at the bed's or the kennel's edge by a body or a furnishing set down
		# in the way: wait a little, then leave the errand rather than for good.
		errand.blocked = float(errand.get("blocked", 0.0)) + seconds
		if float(errand.blocked) >= ACCESS_TIMEOUT: _release_access(id, actor, errand, leaving)
		return false
	errand.blocked = 0.0
	var direction: Vector3 = destination - actor.position
	if direction.length() > .01: actor.rotation.y = atan2(direction.x, direction.z)
	actor.position = next
	actor.clear_behavior()
	errand.walking = true
	if actor.position.distance_to(destination) <= .01:
		errand.walking = false
		if leaving:
			var pending: Dictionary = errand.get("pending", {})
			app.pet_errands.erase(id)
			if not pending.is_empty(): _start(id, str(pending.action), true, pending.get("ground", Vector3.INF))
		else:
			errand.phase = "using"
			errand.elapsed = 0.0
			if not target.is_empty(): actor.rotation.y = target.node.rotation.y
	return true

## A pet that has been held too long on its way onto or off a furnishing steps
## down to clear floor beside it and its errand ends; a queued command still
## follows. Entering abandons the bed or kennel instead.
func _release_access(id: String, actor: LifePetActor, errand: Dictionary, leaving: bool) -> void:
	var level: int = app.world.point_level(actor.position)
	if level < 0: level = actor.floor_level
	if leaving:
		var pending: Dictionary = errand.get("pending", {})
		var landing: Vector3 = errand.entry
		if not app.world.lot_navigation.point_clear(level, landing): landing = app.world.nearest_clear_point(landing, level, 8)
		if landing.is_finite(): actor.position = landing
		actor.clear_behavior()
		app.pet_errands.erase(id)
		if not pending.is_empty(): _start(id, str(pending.action), true, pending.get("ground", Vector3.INF))
		return
	errand.inside = false
	_finish(id, actor, {})

## Leave an errand that cannot go on. A commanded one says which item is in the
## way. On a staircase the pet is put back on the nearer landing first.
func _give_up(id: String, actor: LifePetActor, errand: Dictionary, level: int) -> void:
	var goal: Vector3 = Vector3(errand.at)
	var commanded: bool = bool(errand.get("commanded", false))
	if level < 0:
		var segments: Array = errand.get("segments", [])
		var index: int = clampi(int(errand.index) - 1, 0, maxi(0, segments.size() - 1))
		if not segments.is_empty():
			var leg: Dictionary = segments[index]
			var landing: Vector3 = leg.from if actor.position.distance_to(leg.from) <= actor.position.distance_to(leg.to) else leg.to
			actor.position = landing
			actor.traversing_stairs = false
			level = app.world.point_level(landing)
			if level >= 0: actor.floor_level = level
	_finish(id, actor, {})
	if commanded:
		app.show_blocked_notice(_named_blocker(actor.position, goal, "There is no clear route to that spot. Leave space around the furnishing.", [str(errand.get("access", ""))], false))

func _access_clear(actor: LifePetActor, from: Vector3, to: Vector3, target: Dictionary) -> bool:
	# Only the chosen usable furnishing is exempt during its short access
	# segment. Walls, other furnishings, floors and other bodies still block.
	var level: int = app.world.item_level(target) if not target.is_empty() else actor.floor_level
	var samples: int = maxi(1, ceili(from.distance_to(to) / .08))
	for index: int in range(samples + 1):
		var at: Vector3 = from.lerp(to, float(index) / float(samples))
		var flat := Vector2(at.x, at.z)
		if not app.world.grounds(flat, level) or app.world.construction.point_blocked(flat, level): return false
		for item: Dictionary in app.world.items:
			if str(item.id) == str(target.get("id", "")) or app.world.item_level(item) != level or LifeCatalog.passable(str(item.kind)): continue
			for panel: Rect2 in app.world.item_panels(item):
				if panel.has_point(flat): return false
	return app._pet_path_clear(actor, from, to)

func _tree(id: String, actor: LifePetActor, errand: Dictionary, target: Dictionary, elapsed: float, minutes: float, needs: Dictionary) -> void:
	var node: Node3D = target.node
	var top: Vector3 = node.position + node.basis * Vector3(0, 1.25, -.11)
	var entry: Vector3 = errand.entry
	actor.rotation.y = node.rotation.y
	if elapsed < 8.0:
		actor.set_behavior("scratch", elapsed)
		errand.label = "Scratching the cat tree"
	elif elapsed < 12.0:
		errand.inside = true
		actor.position = entry.lerp(top, smoothstep(8.0, 12.0, elapsed))
		actor.set_behavior("climb", elapsed)
		errand.label = "Climbing the cat tree"
	elif elapsed < 26.0:
		actor.position = top
		actor.set_behavior("tree_play", elapsed)
		errand.label = "Playing on the cat tree"
	elif elapsed < 30.0:
		actor.position = top.lerp(entry, smoothstep(26.0, 30.0, elapsed))
		actor.set_behavior("climb", elapsed)
		errand.label = "Climbing down"
	else:
		actor.position = entry
		errand.inside = false
		_finish(id, actor, {})
	needs.fun = minf(100.0, float(needs.fun) + minutes * 1.5)
	LifePetCare.gain_xp(app.household.pet_care(id), "agility", minutes * .3)

func _play(id: String, actor: LifePetActor, errand: Dictionary, toy: Dictionary, elapsed: float, minutes: float, needs: Dictionary) -> void:
	if not str(toy.get("box_id", "")).is_empty():
		actor.set_behavior("retrieve", elapsed)
		errand.label = "Pulling a toy out of the toy box"
		if elapsed < 3.0: return
		toy.erase("box_id")
		var at: Vector3 = actor.position + actor.basis.z * .23
		at.y = LifeBuildingState.level_y(app.world.item_level(toy))
		toy.x = at.x; toy.z = at.z
		toy.node.position = at
		toy.node.visible = true
		errand.toy_origin = at
	if not errand.has("toy_origin"): errand.toy_origin = toy.node.position
	actor.set_behavior("toy_play", elapsed)
	errand.label = "Playing with a toy on the floor"
	# The toy moves on the floor as the pet bats it; the persistent position
	# stays at the retrieval point and is restored when the activity ends.
	var origin: Vector3 = errand.toy_origin
	toy.node.position = origin + actor.basis.x * sin(elapsed * 1.8) * .12
	toy.node.rotation.y += minutes * 1.7
	needs.fun = minf(100.0, float(needs.fun) + minutes * 2.0)
	if elapsed >= float(errand.squeak_at):
		errand.squeak_at = elapsed + 3.2
		if not bool(muted.get(id, false)) and bool(app.sound_enabled): actor.squeak()
	if elapsed >= PLAY_MINUTES: _finish(id, actor, {})

func _finish(id: String, actor: LifePetActor, pending: Dictionary) -> void:
	var errand: Dictionary = app.pet_errands.get(id, {})
	_release_toy(id)
	_release_course(id)
	actor.clear_behavior()
	actor.stop_squeak()
	idle_minutes[id] = 0.0
	if bool(errand.get("inside", false)):
		errand.phase = "exiting"
		errand.label = "Coming back to the floor"
		errand.walking = true
		errand.pending = pending
	else:
		app.pet_errands.erase(id)
		if not pending.is_empty(): _start(id, str(pending.action), true, pending.get("ground", Vector3.INF))

func _release_toy(id: String) -> void:
	for toy_id: String in toy_claims.keys():
		if str(toy_claims[toy_id]) != id: continue
		var toy: Dictionary = _item(toy_id)
		if not toy.is_empty():
			var errand: Dictionary = app.pet_errands.get(id, {})
			var actor: LifePetActor = app.pet_actors.get(id)
			if bool(errand.get("carrying", false)) and is_instance_valid(actor):
				toy.x = actor.position.x; toy.z = actor.position.z; toy.level = actor.floor_level
			toy.node.position = Vector3(float(toy.x), LifeBuildingState.level_y(app.world.item_level(toy)), float(toy.z))
		toy_claims.erase(toy_id)

func _item(id: String) -> Dictionary:
	if id.is_empty(): return {}
	for item: Dictionary in app.world.items:
		if str(item.id) == id and is_instance_valid(item.get("node")): return item
	return {}

func _start_trick(id: String, command_id: String) -> bool:
	var actor: LifePetActor = app.pet_actors[id]
	var spec: String = command_id.trim_prefix("pet_trick:")
	var trick: String = spec.get_slice("@", 0)
	var target: Dictionary = {}
	var at: Vector3 = actor.position
	var course: Array[Vector3] = []
	if trick == "fetch":
		target = _item(spec.get_slice("@", 1)) if spec.contains("@") else _target(id, "pet_play_toys")
		if target.is_empty() or str(target.kind) != "pet_toy_" + _species(id) or bool(target.get("held", false)): return false
		if toy_claims.has(str(target.id)) and str(toy_claims[str(target.id)]) != id: return false
		var access: Dictionary = _item(str(target.box_id)) if not str(target.get("box_id", "")).is_empty() else target
		if access.is_empty(): return false
		at = _approach(id, access, "pet_play_toys", actor.position)
	elif trick == "weave":
		course = _plan_agility(id)
		if course.is_empty(): return false
		at = course[0]
	if not at.is_finite(): return false
	var route: Dictionary = _route(id, actor.position, at)
	if not bool(route.get("ok", false)):
		route_failure = {"from": actor.position, "to": at, "ignore": [str(target.get("id", ""))]}
		_release_course(id)
		return false
	app.pet_errands[id] = {"action": "pet_perform_trick", "trick": trick, "label": LifePetCare.trick_label(trick), "target": str(target.get("id", "")), "access": "", "kind": "trick", "at": at, "entry": at, "origin": actor.position, "path": route.points, "segments": route.segments, "index": 0, "phase": "walking", "walking": true, "elapsed": 0.0, "commanded": true, "inside": false, "blocked": 0.0, "lap": 0}
	app.pet_errands[id]["course"] = course
	if not target.is_empty(): toy_claims[str(target.id)] = id
	return true

func _perform_trick(id: String, actor: LifePetActor, errand: Dictionary, minutes: float) -> bool:
	errand.elapsed = float(errand.elapsed) + minutes
	var elapsed: float = float(errand.elapsed)
	var trick: String = str(errand.trick)
	if trick == "fetch" and not bool(errand.get("carrying", false)):
		var toy: Dictionary = _item(str(errand.target))
		if toy.is_empty(): _finish(id, actor, {}); return false
		var route: Dictionary = _route(id, actor.position, Vector3(errand.origin))
		if not bool(route.get("ok", false)): _finish(id, actor, {}); return false
		toy.erase("box_id")
		toy.node.visible = true
		errand.carrying = true; errand.phase = "walking"; errand.walking = true
		errand.path = route.points; errand.segments = route.segments; errand.index = 0; errand.at = errand.origin
		toy.node.position = actor.mouth_point()
		return false
	if trick == "fetch" and bool(errand.get("carrying", false)):
		var toy: Dictionary = _item(str(errand.target))
		if not toy.is_empty():
			var drop: Vector3 = actor.position + actor.basis.z * .25
			drop.y = LifeBuildingState.level_y(actor.floor_level)
			toy.x = drop.x; toy.z = drop.z; toy.node.position = drop
		_finish(id, actor, {})
		return false
	if trick == "weave":
		var course: Array = errand.get("course", [])
		var next: int = int(errand.lap) + 1
		if next < course.size():
			var at: Vector3 = course[next]
			var route: Dictionary = _route(id, actor.position, at)
			if bool(route.get("ok", false)):
				errand.lap = next; errand.phase = "walking"; errand.walking = true
				errand.path = route.points; errand.segments = route.segments; errand.index = 0; errand.at = at
				return false
		_finish(id, actor, {})
		return false
	var pose: String = trick
	if trick == "routine":
		var routine: Array[String] = ["sit", "lie", "paw", "roll", "high_five", "backflip", "dance", "play_dead"]
		pose = routine[mini(routine.size() - 1, int(elapsed / 3.0))]
	if pose == "speak" and not bool(errand.get("spoke", false)):
		errand["spoke"] = true
		if bool(app.sound_enabled): actor.bark()
	actor.set_behavior("trick_" + pose, fmod(elapsed, 3.0) if trick == "routine" else elapsed)
	var needs: Dictionary = app.household.pet_care(id).needs
	needs.fun = minf(100.0, float(needs.fun) + minutes * 1.5)
	if elapsed >= (24.0 if trick == "routine" else 6.0): _finish(id, actor, {})
	return false

## A visible five-pole slalom uses alternating waypoints, each validated on
## the floor graph with poles treated as occupied positions. No props are saved.
func _plan_agility(id: String) -> Array[Vector3]:
	var actor: LifePetActor = app.pet_actors[id]
	for angle: float in [0.0, PI * .5, PI, PI * 1.5]:
		var forward := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-forward.z, 0, forward.x)
		var poles: Array[Vector3] = []
		var points: Array[Vector3] = []
		var clear: bool = true
		for n: int in 5:
			var pole: Vector3 = actor.position + forward * (1.5 + float(n) * 1.5)
			var point: Vector3 = pole + side * (1.0 if n % 2 == 0 else -1.0)
			if not app.world.lot_navigation.point_clear(actor.floor_level, pole) or not app.world.lot_navigation.point_clear(actor.floor_level, point): clear = false; break
			poles.append(pole); points.append(point)
		if not clear: continue
		points.append(actor.position)
		agility_obstacles[id] = poles
		var previous: Vector3 = actor.position
		for point: Vector3 in points:
			if not bool(_route(id, previous, point).get("ok", false)): clear = false; break
			previous = point
		if not clear: agility_obstacles.erase(id); continue
		var props := Node3D.new();props.name = "DogAgilityCourse"
		app.world.house.add_child(props)
		for pole: Vector3 in poles:
			var mesh := MeshInstance3D.new()
			var cylinder := CylinderMesh.new();cylinder.top_radius = .065;cylinder.bottom_radius = .11;cylinder.height = .65
			var material := StandardMaterial3D.new();material.albedo_color = Color("efb447")
			mesh.mesh = cylinder;mesh.material_override = material
			props.add_child(mesh);mesh.position = pole + Vector3(0,.325,0)
		app.world._assign_layers(props, LifeWorld.VIEW_GROUND if actor.floor_level == 0 else LifeWorld.VIEW_UPPER)
		agility_props[id] = props
		return points
	return []

func _release_course(id: String) -> void:
	agility_obstacles.erase(id)
	var props: Node3D = agility_props.get(id)
	if is_instance_valid(props): props.queue_free()
	agility_props.erase(id)
