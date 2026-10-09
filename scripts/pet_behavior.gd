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
const STAIR_TIMEOUT: float = 25.0     # on stairs, keep waiting for a supported landing
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
		{"id": "pet_drink", "label": "Drink from Water Bowl"},
		{"id": "pet_go_bed", "label": "Go to Cat Bed" if cat else "Go to Dog Bed"},
		{"id": "pet_cat_tree" if cat else "pet_go_dog_house", "label": "Command to Play on Cat Tree" if cat else "Go to Dog House"},
		{"id": "pet_play_toys", "label": "Play with Toys"},
	]
	if cat: result.append({"id": "pet_litter", "label": "Use Litter Tray"})
	result.append({"id": "relieve_outside", "label": "Go to the Toilet Outside"})
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
	if action == "pet_free": _interrupt_care(id)
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
	if action == "pet_free":
		_interrupt_care(id)
		_finish(id, actor, {})
		actor.traversing_stairs = false
		idle_minutes[id] = 0.0
		return {"ok": true, "message": "%s is free to look after themselves." % actor.display_name}
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
	# A canceled care route on stairs retains its checked landing segment.
	# Carry the new command to that landing instead of replanning in mid-air.
	var retained: Dictionary = app.pet_errands.get(id, {})
	if str(retained.get("phase", "")) == "walking" and app.world.point_level(actor.position) < 0:
		retained["pending_command"] = {"action": action, "ground": ground}
		return {"ok": true, "message": "%s will follow that command at the stair landing." % actor.display_name}
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
	for visit: LifeHomeVisit in (app.residents.visits() if app.residents != null else []):
		if visit.active() and (visit.activity.holds_pet(id) or str(visit.activity.data.get("pending_pet",{}).get("target",""))==id):visit.activity.cancel("")
	var care: RefCounted = app.care_motion()
	for member_id: String in care.sessions.keys():
		if str(care.sessions[member_id].pet) == id: care._release(member_id)
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		for index: int in range(sim.action_queue.size() - 1, -1, -1):
			var action: Dictionary = sim.action_queue[index]
			if str(action.get("target_id", "")) == id and (str(action.get("id", "")) in LifePetCare.interaction_ids() or str(action.get("id", "")) == "bathe_pet"): sim.cancel_action(index)

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
	if action == "relieve_outside": return ""
	if action.get_slice(":", 0) == "pet_litter":
		if _species(id) != "cat": return "Only cats use a litter tray."
		var tray: Dictionary = _item(action.get_slice(":", 1)) if action.contains(":") else _target(id, "relieve")
		if tray.is_empty() or str(tray.kind) != "litter_tray": return "Place a clean litter tray first."
		if app.household_flow.litter_full(str(tray.id)): return "Clean this litter tray first."
		return ""
	if action == "pet_cat_tree" and _species(id) != "cat": return "Only cats use a cat tree."
	if action == "pet_go_dog_house" and _species(id) != "dog": return "Only dogs use a dog house."
	if action.begins_with("pet_trick:"):
		var trick: String = action.trim_prefix("pet_trick:").get_slice("@", 0)
		if not trick in LifePetCare.known_tricks(app.household.pet_care(id)): return "Train Clever Tricks to learn this trick first."
		if trick == "fetch" and _target(id, "pet_play_toys").is_empty(): return "Place a dog toy to fetch first."
		return ""
	if action in ["pet_stop_squeaking", "pet_stop_playing", "pet_move", "wander", "relieve"]: return ""
	if action not in ["pet_eat", "pet_drink", "pet_go_bed", "pet_go_dog_house", "pet_cat_tree", "pet_play_toys"]: return "Unknown pet command."
	if _target(id, action).is_empty():
		return {"pet_eat": "Place a food bowl first.", "pet_drink": "Place a water bowl first.", "pet_go_bed": "Place a %s bed first." % _species(id), "pet_go_dog_house": "Place a dog house outdoors first.", "pet_cat_tree": "Place a cat tree first.", "pet_play_toys": "Buy a toy or a toy box for this pet first."}.get(action, "Place the pet furnishing first.")
	return ""

func _target(id: String, action: String) -> Dictionary:
	var actor: LifePetActor = app.pet_actors.get(id)
	if not is_instance_valid(actor): return {}
	var kind: String = {"pet_eat": "pet_bowl", "pet_drink": "pet_bowl", "pet_go_bed": "pet_bed_" + _species(id), "pet_go_dog_house": "kennel", "pet_cat_tree": "cat_tree", "relieve": "litter_tray"}.get(action, "")
	var best: Dictionary = {}
	var distance: float = INF
	for item: Dictionary in app.world.items:
		if not is_instance_valid(item.get("node")): continue
		if action == "pet_play_toys":
			if str(item.kind) != "pet_toy_" + _species(id) or bool(item.get("carried", false)): continue
			if toy_claims.has(str(item.id)) and str(toy_claims[str(item.id)]) != id: continue
			# A housemate on their way to tidy it away, or a toy whose box is gone, is not for playing.
			if not app.toy_flow.claimed_by(str(item.id)).is_empty(): continue
			if not str(item.get("box_id", "")).is_empty() and _item(str(item.box_id)).is_empty(): continue
		elif str(item.kind) != kind: continue
		if action == "relieve":
			if app.household_flow.litter_full(str(item.id)): continue
			if not _approach(id, item, action, actor.position).is_finite(): continue
		# The kennel itself makes its cell solid. Test the underlying lot/floor,
		# rather than outdoor_cell(), which is intended for empty walking cells.
		if action == "pet_go_dog_house" and (app.world.item_level(item) != 0 or app.world.construction.floor_contains(Vector2(item.node.position.x, item.node.position.z), 0)): continue
		var care: Dictionary = app.household.pet_care(id)
		var logic: int = LifePetCare.level(care, "logic")
		var access: Dictionary = _item(str(item.box_id)) if action == "pet_play_toys" and not str(item.get("box_id", "")).is_empty() else item
		if logic >= 5 and (access.is_empty() or not _approach(id, access, action, actor.position).is_finite()): continue
		var gap: float = actor.position.distance_squared_to(item.node.position)
		# A nearby inaccessible bowl must not strand a pet when another bowl
		# is reachable. Keep the blocked one only to explain a failed route.
		if action in ["pet_eat", "pet_drink"] and not _approach(id, item, action, actor.position).is_finite(): gap += 1000000.0
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
		if app.care_motion().holds(id) or (app.residents != null and app.residents.guest_holds_pet(id)):
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
	if route_failure.is_empty() or action not in ["pet_eat", "pet_drink", "pet_go_bed", "pet_go_dog_house", "pet_cat_tree"]: return
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
var _recover_after: Dictionary = {}

func recover_overlap(id: String, actor: LifePetActor) -> bool:
	var errand: Dictionary = app.pet_errands.get(id, {})
	if bool(errand.get("inside", false)) or actor.traversing_stairs or app.care_motion().holds(id): return false
	var level: int = app.world.point_level(actor.position)
	if level < 0 or (app.world.lot_navigation.point_clear(level, actor.position) and app.world.lot_navigation.pet_wall_pose_clear(actor.position, actor.rotation.y, actor.wall_hull())): return false
	# One that could not be helped a moment ago is not searched for again every tick.
	if float(_recover_after.get(id, 0.0)) > float(Time.get_ticks_msec()): return false
	# A pet may stand deep inside a large pool's hull, well over two metres from any
	# clear floor: search outward a ring at a time, and only as far as it takes.
	var safe: Dictionary = app._pet_safe_floor_pose(actor, actor.position)
	if safe.is_empty():
		_recover_after[id] = float(Time.get_ticks_msec()) + 3000.0
		return false
	actor.position = safe.position
	actor.rotation.y = float(safe.yaw)
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
	if float(needs.get("thirst", 80.0)) < URGENT and not _target(id, "pet_drink").is_empty(): return "pet_drink"
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
	var explicit_tray: String = action.get_slice(":", 1) if action.begins_with("pet_litter:") else ""
	var outside: bool = action == "relieve_outside"
	if action.get_slice(":", 0) == "pet_litter" or outside: action = "relieve"
	var target: Dictionary = _item(explicit_tray) if not explicit_tray.is_empty() else _target(id, action)
	var access: Dictionary = target
	if action == "pet_play_toys" and not str(target.get("box_id", "")).is_empty(): access = _item(str(target.box_id))
	var at: Vector3 = ground
	if action == "wander": at = _wander_spot(id, actor.position)
	elif action == "relieve" and (outside or _species(id) == "dog" or target.is_empty()):
		target = {}; access = {}; at = app._pet_outdoor_spot("bladder")
	elif action != "pet_move":
		if target.is_empty() or access.is_empty(): return false
		at = _approach(id, access, action, actor.position)
		# Every side of the furnishing is walled off: the goal is the piece itself,
		# and the item to name is whatever rings it, never the piece.
		if not at.is_finite() and is_instance_valid(access.get("node")):
			route_failure = {"from": actor.position, "to": Vector3(access.node.position.x, LifeBuildingState.level_y(app.world.item_level(access)), access.node.position.z), "ignore": [str(access.get("id", ""))]}
	if not at.is_finite(): return false
	var target_yaw: float = NAN
	if action in ["pet_eat", "pet_drink"] and not target.is_empty():
		var cup: Vector3 = bowl_point(target, action == "pet_drink")
		target_yaw = atan2(cup.x - at.x, cup.z - at.z)
	var route: Dictionary = _route(id, actor.position, at, target_yaw)
	if not bool(route.get("ok", false)):
		route_failure = {"from": actor.position, "to": at, "ignore": [str(access.get("id", ""))]}
		return false
	var path: PackedVector3Array = route.points
	var labels: Dictionary = {"pet_eat": "Walking to the food bowl", "pet_drink": "Walking to the water bowl", "pet_go_bed": "Going to bed", "pet_go_dog_house": "Going to the dog house", "pet_cat_tree": "Going to the cat tree", "pet_play_toys": "Fetching a toy", "pet_move": "Moving to your chosen spot", "wander": "Exploring the home", "relieve": "Taking a toilet break"}
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
	if action in ["pet_eat", "pet_drink"]: return bowl_approach(id, item, from, action == "pet_drink")
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

## Authored cup centres on the twin food/water tray.
func bowl_point(item: Dictionary, water: bool = false) -> Vector3:
	return (item.node as Node3D).to_global(Vector3(.105 if water else -.095, .108, 0))

## Put the animal's muzzle over the chosen cup from supported clear floor.
## Prefer the side away from a feeding Lifelet, with a full route around walls.
func bowl_approach(id: String, item: Dictionary, from: Vector3, water: bool = false, person: Vector3 = Vector3.INF) -> Vector3:
	var cup: Vector3 = bowl_point(item, water)
	var node: Node3D = item.node
	var reaches: Array[float] = [.35, .40]
	if _species(id) == "dog": reaches = [.48, .55]
	var candidates: Array[Vector3] = []
	for reach: float in reaches:
		for offset: Vector3 in [Vector3(0, 0, reach), Vector3(0, 0, -reach), Vector3(reach, 0, 0), Vector3(-reach, 0, 0)]:
			var at: Vector3 = cup + node.basis * offset
			at.y = LifeBuildingState.level_y(app.world.item_level(item))
			if person.is_finite() and at.distance_to(person) < LifeTraversal.BODY_GAP + .04: continue
			if not app.world.lot_navigation.point_clear(app.world.item_level(item), at): continue
			if not app.world.sight_line_clear(at, Vector3(cup.x, at.y, cup.z)): continue
			candidates.append(at)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(from) < b.distance_squared_to(from))
	for at: Vector3 in candidates:
		var facing: float = atan2(cup.x - at.x, cup.z - at.z)
		if bool(_route(id, from, at, facing).get("ok", false)): return at
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

func _route(id: String, from: Vector3, to: Vector3, target_yaw: float = NAN) -> Dictionary:
	var occupied: Array[Vector3] = []
	for other: String in app.world.actors:
		var body: Node3D = app.world.actors[other]
		if is_instance_valid(body) and body.visible: occupied.append(body.position)
	for other: String in app.pet_actors:
		var body: Node3D = app.pet_actors[other]
		if other != id and is_instance_valid(body) and body.visible: occupied.append(body.position)
	for poles: Array in agility_obstacles.values():
		for pole: Vector3 in poles: occupied.append(pole)
	var actor: LifePetActor = app.pet_actors[id]
	return app.world.lot_navigation.pet_route_avoiding(LifeLotNavigation.floor_location(app.world.point_level(from), from), LifeLotNavigation.floor_location(app.world.point_level(to), to), occupied, LifeTraversal.ROUTE_CLEARANCE, actor.wall_hull(), actor.rotation.y, target_yaw)

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
			actor.set_behavior("rest", elapsed, action == "pet_go_bed")
			errand.label = "Resting in the dog house" if action == "pet_go_dog_house" else "Sleeping in bed"
			needs.energy = minf(100.0, float(needs.energy) + LifePets.SLEEP_PER_HOUR * minutes / 60.0)
			if elapsed >= REST_MINUTES or (not bool(errand.commanded) and elapsed >= 25.0 and float(needs.energy) >= 85.0): _finish(id, actor, {})
		"pet_eat", "pet_drink":
			actor.set_behavior("drink" if action == "pet_drink" else "eat", elapsed)
			errand.label = "Drinking from the water bowl" if action == "pet_drink" else "Eating from the bowl"
			var need: String = "thirst" if action == "pet_drink" else "hunger"
			needs[need] = minf(100.0, float(needs.get(need, 80.0)) + minutes * 5.5)
			if elapsed >= 12.0: _finish(id, actor, {})
		"pet_cat_tree":
			_tree(id, actor, errand, target, elapsed, minutes, needs)
		"pet_play_toys":
			_play(id, actor, errand, target, elapsed, minutes, needs)
		"relieve":
			actor.set_behavior("toilet_dog" if _species(id) == "dog" else "toilet_cat", elapsed)
			errand.label = "Using the litter tray" if not target.is_empty() else "Taking a toilet break outside"
			if elapsed >= 3.0:
				needs.bladder = 95.0
				if not target.is_empty(): app.household_flow.use_litter(str(target.id))
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
		var segments: Array = errand.get("segments", [])
		var segment: Dictionary = segments[int(errand.index) - 1] if int(errand.index) > 0 and int(errand.index) <= segments.size() else {}
		if bool(segment.get("turn", false)):
			var turn: Dictionary = turn_step(actor, segment, budget / WALK_SPEED)
			if not bool(turn.ok):
				errand.blocked = float(errand.blocked) + seconds
				return moved
			budget -= float(turn.seconds) * WALK_SPEED
			if bool(turn.finished): errand.index = int(errand.index) + 1
			else: return moved
			continue
		var point: Vector3 = path[int(errand.index)]
		var gap: float = actor.position.distance_to(point)
		if gap <= .00001:
			errand.index = int(errand.index) + 1
			continue
		var step: float = minf(gap, minf(budget, .10))
		var next: Vector3 = actor.position.move_toward(point, step)
		var stair: bool = str(segment.get("kind", "floor")) == "stair"
		actor.traversing_stairs = stair
		var yaw: float = float(segment.get("yaw_to", atan2(point.x - actor.position.x, point.z - actor.position.z)))
		var blocked: bool = not _stair_clear(actor, next, segment, yaw) if stair else app._pet_step_blocked(actor, next, yaw)
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
		if app.world.construction.doors.before_pet_step(actor,next,seconds):return moved
		if gap > .001: actor.rotation.y = yaw
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
			var toward: Vector3 = (bowl_point(target, str(errand.action) == "pet_drink") if str(errand.action) in ["pet_eat", "pet_drink"] else target.node.position) - actor.position
			if toward.length() > .01:
				var yaw: float = atan2(toward.x, toward.z)
				if app.world.lot_navigation.pet_wall_step_clear(actor.position, actor.position, actor.rotation.y, yaw, actor.wall_hull()): actor.rotation.y = yaw
		if str(errand.action) in ["pet_go_bed", "pet_go_dog_house", "relieve"] and not target.is_empty():
			errand.phase = "entering"
			errand.inside = true
			var node: Node3D = target.node
			errand.inner = node.position + node.basis * (Vector3(0, .10, .02) if str(errand.action) == "pet_go_dog_house" else Vector3(0, .10, 0))
			if str(errand.action) == "relieve": errand.inner = node.position + Vector3(0, .04, 0)
			# Cushioned beds support the compact sleeping body above the hollow.
			if str(errand.kind) == "pet_bed_cat": errand.inner = node.position + node.basis * Vector3(0, .15, -.025)
			if str(errand.kind) == "pet_bed_dog": errand.inner = node.position + node.basis * Vector3(0, .178, -.05)
	return moved

func _stair_clear(actor: LifePetActor, next: Vector3, segment: Dictionary, proposed_yaw: float = NAN) -> bool:
	# Only graph-authored stair edges permit intermediate heights. Arbitrary
	# vertical goals still fail exact-floor endpoint validation in _route().
	var stair_id: String = str(segment.get("stair_id", ""))
	if stair_id.is_empty() or not app.world.lot_navigation.stair_connected(stair_id): return false
	var from: Vector3 = segment.from
	var to: Vector3 = segment.to
	var line: Vector3 = to - from
	var part: float = clampf((next - from).dot(line) / maxf(line.length_squared(), .000001), 0.0, 1.0)
	if next.distance_to(from.lerp(to, part)) > .001: return false
	var yaw: float = actor.rotation.y if not is_finite(proposed_yaw) else proposed_yaw
	return app._pet_path_clear(actor, actor.position, next) and app.world.lot_navigation.pet_wall_step_clear(actor.position, next, actor.rotation.y, yaw, actor.wall_hull())

func turn_step(actor: LifePetActor, segment: Dictionary, seconds: float) -> Dictionary:
	var target: float = float(segment.get("yaw_to", actor.rotation.y))
	var angle: float = absf(wrapf(target - actor.rotation.y, -PI, PI))
	var step: float = minf(angle, maxf(0.0, seconds) * 3.5)
	var yaw: float = rotate_toward(actor.rotation.y, target, step)
	if not app.world.lot_navigation.pet_wall_step_clear(actor.position, actor.position, actor.rotation.y, yaw, actor.wall_hull()): return {"ok": false, "finished": false, "seconds": 0.0}
	actor.rotation.y = yaw
	actor.traversing_stairs = false
	return {"ok": true, "finished": angle <= step + .00001, "seconds": step / 3.5}

func _access_step(id: String, actor: LifePetActor, errand: Dictionary, seconds: float) -> bool:
	var leaving: bool = str(errand.phase) == "exiting"
	var destination: Vector3 = errand.entry if leaving else errand.inner
	var next: Vector3 = actor.position.move_toward(destination, seconds * .65)
	var target: Dictionary = _item(str(errand.access))
	var direction: Vector3 = destination - actor.position
	var yaw: float = atan2(direction.x, direction.z) if direction.length() > .01 else actor.rotation.y
	if not _access_clear(actor, actor.position, next, target, yaw):
		# Held at the bed's or the kennel's edge by a body or a furnishing set down
		# in the way: wait a little, then leave the errand rather than for good.
		errand.blocked = float(errand.get("blocked", 0.0)) + seconds
		if float(errand.blocked) >= ACCESS_TIMEOUT: _release_access(id, actor, errand, leaving)
		return false
	errand.blocked = 0.0
	if direction.length() > .01: actor.rotation.y = yaw
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
			if not target.is_empty() and app.world.lot_navigation.pet_wall_step_clear(actor.position, actor.position, actor.rotation.y, target.node.rotation.y, actor.wall_hull()): actor.rotation.y = target.node.rotation.y
	return true

## A blocked entry backs out along its checked access leg. A blocked exit
## waits for that same way back to clear before a queued command can follow.
func _release_access(id: String, actor: LifePetActor, errand: Dictionary, leaving: bool) -> void:
	if leaving:
		# A body or a new wall can block the exit too. Retain the checked route
		# rather than snapping through that obstruction to a different floor tile.
		errand.blocked = 0.0
		errand.label = "Waiting for a clear way back to the floor"
		return
	# A blocked entry may already have lifted the pet into the furnishing.
	# Walk back along the same checked access leg before dropping the errand;
	# erasing it here would strand the pet at an unsupported intermediate height.
	errand.phase = "exiting"
	errand.label = "Waiting for space beside the furnishing"
	errand.walking = true
	errand.pending = {}
	errand.blocked = 0.0

## Leave an errand that cannot go on. A commanded one says which item is in the
## way. A pet on stairs retains its supported flight until the way clears.
func _give_up(id: String, actor: LifePetActor, errand: Dictionary, level: int) -> void:
	var goal: Vector3 = Vector3(errand.at)
	var commanded: bool = bool(errand.get("commanded", false))
	if level < 0:
		errand.blocked = 0.0
		errand.label = "Waiting for a clear stair landing"
		return
	_finish(id, actor, {})
	if commanded:
		app.show_blocked_notice(_named_blocker(actor.position, goal, "There is no clear route to that spot. Leave space around the furnishing.", [str(errand.get("access", ""))], false))

func _access_clear(actor: LifePetActor, from: Vector3, to: Vector3, target: Dictionary, proposed_yaw: float = NAN) -> bool:
	# Only the chosen usable furnishing is exempt during its short access
	# segment. Walls, other furnishings, floors and other bodies still block.
	var level: int = app.world.item_level(target) if not target.is_empty() else actor.floor_level
	var samples: int = maxi(1, ceili(from.distance_to(to) / .08))
	for index: int in range(samples + 1):
		var at: Vector3 = from.lerp(to, float(index) / float(samples))
		var flat := Vector2(at.x, at.z)
		var body_box := Rect2(flat - Vector2.ONE * LifeLotNavigation.RADIUS, Vector2.ONE * LifeLotNavigation.RADIUS * 2.0)
		if not app.world.grounds(flat, level) or app.world.construction.rect_blocked(body_box, level, LifeLotNavigation.WALL_RADIUS - LifeLotNavigation.RADIUS): return false
		for item: Dictionary in app.world.items:
			if str(item.id) == str(target.get("id", "")) or app.world.item_level(item) != level or LifeCatalog.passable(str(item.kind)): continue
			for panel: Rect2 in app.world.item_panels(item):
				if panel.intersects(body_box): return false
	var yaw: float = actor.rotation.y if not is_finite(proposed_yaw) else proposed_yaw
	return app._pet_path_clear(actor, from, to) and app.world.lot_navigation.pet_wall_step_clear(from, to, actor.rotation.y, yaw, actor.wall_hull())

func _tree(id: String, actor: LifePetActor, errand: Dictionary, target: Dictionary, elapsed: float, minutes: float, needs: Dictionary) -> void:
	var node: Node3D = target.node
	var top: Vector3 = node.position + node.basis * Vector3(0, 1.25, -.11)
	var entry: Vector3 = errand.entry
	var destination: Vector3 = entry
	if elapsed >= 8.0 and elapsed < 12.0: destination = entry.lerp(top, smoothstep(8.0, 12.0, elapsed))
	elif elapsed >= 12.0 and elapsed < 26.0: destination = top
	elif elapsed >= 26.0 and elapsed < 30.0: destination = top.lerp(entry, smoothstep(26.0, 30.0, elapsed))
	if not app.world.lot_navigation.pet_wall_step_clear(actor.position, destination, actor.rotation.y, node.rotation.y, actor.wall_hull()):
		errand.elapsed = maxf(0.0, elapsed - minutes)
		errand.label = "Waiting for space around the cat tree"
		return
	actor.rotation.y = node.rotation.y
	actor.position = destination
	if elapsed < 8.0:
		actor.set_behavior("scratch", elapsed)
		errand.label = "Scratching the cat tree"
	elif elapsed < 12.0:
		errand.inside = true
		actor.set_behavior("climb", elapsed)
		errand.label = "Climbing the cat tree"
	elif elapsed < 26.0:
		actor.set_behavior("tree_play", elapsed)
		errand.label = "Playing on the cat tree"
	elif elapsed < 30.0:
		actor.set_behavior("climb", elapsed)
		errand.label = "Climbing down"
	else:
		errand.inside = false
		_finish(id, actor, {})
	needs.fun = minf(100.0, float(needs.fun) + minutes * 1.5)
	LifePetCare.gain_xp(app.household.pet_care(id), "agility", minutes * .3)

func _play(id: String, actor: LifePetActor, errand: Dictionary, toy: Dictionary, elapsed: float, minutes: float, needs: Dictionary) -> void:
	if not str(toy.get("box_id", "")).is_empty():
		actor.set_behavior("retrieve", elapsed)
		errand.label = "Pulling a toy out of the toy box"
		if elapsed < 3.0: return
		var at: Vector3 = actor.position + actor.basis.z * .23
		at.y = LifeBuildingState.level_y(app.world.item_level(toy))
		app.toy_flow.unnest(toy, at)
		errand.toy_origin = at
	if not errand.has("toy_origin"): errand.toy_origin = toy.node.position
	actor.set_behavior("toy_play", elapsed)
	errand.label = "Playing with a toy on the floor"
	# The toy moves on the floor as the pet bats it; the persistent position
	# stays at the retrieval point and is restored when the activity ends.
	var origin: Vector3 = errand.toy_origin
	toy.node.position = origin + actor.basis.x * sin(elapsed * 1.8) * .12
	toy.node.rotation.y = wrapf(toy.node.rotation.y + minutes * 1.7, -PI, PI)
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
				var dropped: Vector3 = actor.position + actor.basis.z * .25
				toy.x = dropped.x; toy.z = dropped.z; toy.level = actor.floor_level
			if bool(toy.get("carried", false)):
				toy.erase("carried"); toy.erase("rest")
				toy.node.rotation = Vector3(0.0, toy.node.rotation.y, 0.0)
				if str(toy.get("box_id", "")).is_empty(): app.world.set_item_pickable(toy, true)
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
		if target.is_empty() or str(target.kind) != "pet_toy_" + _species(id) or bool(target.get("carried", false)): return false
		if toy_claims.has(str(target.id)) and str(toy_claims[str(target.id)]) != id: return false
		if not app.toy_flow.claimed_by(str(target.id)).is_empty(): return false
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
		# Carried in the mouth, a toy is saved at the pose it was lifted from, so a save
		# made now neither floats it in the air nor leaves it on the dog.
		var lifted_from: Dictionary = _item(str(toy.get("box_id", "")))
		var rest_at: Vector3 = lifted_from.node.position if not lifted_from.is_empty() else toy.node.position
		toy.erase("box_id")
		toy.node.visible = true
		toy["carried"] = true
		toy["rest"] = {"x": rest_at.x, "y": LifeBuildingState.level_y(app.world.item_level(toy)), "z": rest_at.z, "rotation": toy.node.rotation_degrees.y}
		app.world.set_item_pickable(toy, false)
		errand.carrying = true; errand.phase = "walking"; errand.walking = true
		errand.path = route.points; errand.segments = route.segments; errand.index = 0; errand.at = errand.origin
		toy.node.position = actor.mouth_point()
		return false
	if trick == "fetch" and bool(errand.get("carrying", false)):
		var toy: Dictionary = _item(str(errand.target))
		if not toy.is_empty():
			var drop: Vector3 = actor.position + actor.basis.z * .25
			drop.y = LifeBuildingState.level_y(actor.floor_level)
			toy.erase("carried"); toy.erase("rest")
			toy["level"] = actor.floor_level
			toy.x = drop.x; toy.z = drop.z; toy.node.position = drop
			toy.node.rotation = Vector3(0.0, toy.node.rotation.y, 0.0)
			app.world.set_item_pickable(toy, true)
		# The toy is on the floor where it was dropped: let go of it before finishing,
		# so the release does not move it back under the dog.
		errand.carrying = false
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
		app.world._assign_layers(props, LifeWorld.view_layer(actor.floor_level))
		agility_props[id] = props
		return points
	return []

func _release_course(id: String) -> void:
	agility_obstacles.erase(id)
	var props: Node3D = agility_props.get(id)
	if is_instance_valid(props): props.queue_free()
	agility_props.erase(id)
