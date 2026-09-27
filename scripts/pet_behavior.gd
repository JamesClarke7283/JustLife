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
		return _failure("Choose a clear, supported spot on the ground or floor.")
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
	if app.care_motion().holds(id): return _failure("Let this pet finish its time with the Lifelet first.")
	var old: Dictionary = app.pet_errands.get(id, {})
	if str(old.get("phase", "")) in ["entering", "using", "exiting"] and bool(old.get("inside", false)):
		_finish(id, actor, {"action": action, "ground": ground})
		return {"ok": true, "message": "%s is coming out first." % actor.display_name}
	_release_toy(id)
	app.pet_errands.erase(id)
	app.pet_arrivals.erase(id)
	actor.clear_behavior()
	var ok: bool = _start(id, action, true, ground)
	if not ok: return _failure("There is no clear route to that spot. Leave space around the furnishing.")
	idle_minutes[id] = 0.0
	return {"ok": true, "message": "%s: %s" % [actor.display_name, state(id).label]}

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "message": message}

func _species(id: String) -> String:
	return str(app.household.pet_record(id).get("species", "cat"))

func _availability(id: String, action: String) -> String:
	if action == "pet_cat_tree" and _species(id) != "cat": return "Only cats use a cat tree."
	if action == "pet_go_dog_house" and _species(id) != "dog": return "Only dogs use a dog house."
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
		var gap: float = actor.position.distance_squared_to(item.node.position)
		if gap < distance: best = item; distance = gap
	return best

func tick(delta: float, speed: float) -> bool:
	if delta <= 0.0 or speed <= 0.0: return false
	var minutes: float = delta * speed * LifeSim.GAME_MINUTES_PER_SECOND
	var moved: bool = false
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
		if _species(id) == "cat": needs.hygiene = minf(100.0, float(needs.hygiene) + minutes * 0.10)
		if (app.pet_errands.get(id, {}) as Dictionary).is_empty():
			idle_minutes[id] = float(idle_minutes.get(id, 0.0)) + minutes
			var action: String = _choose(id, needs)
			if not action.is_empty(): _start(id, action, false)
		if not (app.pet_errands.get(id, {}) as Dictionary).is_empty():
			moved = _advance(id, actor, needs, minutes, delta * speed) or moved
	return moved

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
	if not at.is_finite(): return false
	var route: Dictionary = _route(id, actor.position, at)
	if not bool(route.get("ok", false)): return false
	var path: PackedVector3Array = route.points
	var labels: Dictionary = {"pet_eat": "Walking to the food bowl", "pet_go_bed": "Going to bed", "pet_go_dog_house": "Going to the dog house", "pet_cat_tree": "Going to the cat tree", "pet_play_toys": "Fetching a toy", "pet_move": "Moving to your chosen spot", "wander": "Exploring the home", "relieve": "Taking a toilet break"}
	app.pet_errands[id] = {"action": action, "label": labels.get(action, action), "kind": str(target.get("kind", "outdoors")), "target": str(target.get("id", "")), "access": str(access.get("id", "")), "at": at, "entry": at, "path": path, "segments": route.segments, "index": 0, "phase": "walking", "walking": true, "elapsed": 0.0, "commanded": commanded, "inside": false, "squeak_at": 0.0, "blocked": 0.0}
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
	return app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(app.world.point_level(from), from), LifeLotNavigation.floor_location(app.world.point_level(to), to), occupied, LifeTraversal.ROUTE_CLEARANCE)

func _advance(id: String, actor: LifePetActor, needs: Dictionary, minutes: float, seconds: float) -> bool:
	var errand: Dictionary = app.pet_errands[id]
	var target: Dictionary = _item(str(errand.target))
	if not str(errand.target).is_empty() and target.is_empty() and str(errand.phase) != "exiting":
		_finish(id, actor, {})
		return false
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
	var budget: float = seconds * WALK_SPEED
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
			if float(errand.blocked) >= 1.0 and app.world.point_level(actor.position) >= 0:
				var detour: Dictionary = _route(id, actor.position, Vector3(errand.at))
				if bool(detour.get("ok", false)): errand.path = detour.points; errand.segments = detour.segments; errand.index = 0
			if float(errand.blocked) > 12.0 and app.world.point_level(actor.position) >= 0: _finish(id, actor, {})
			return moved
		if gap > .001: actor.rotation.y = atan2(point.x - actor.position.x, point.z - actor.position.z)
		actor.position = next
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
	if not _access_clear(actor, actor.position, next, target): return false
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
			toy.node.position = Vector3(float(toy.x), LifeBuildingState.level_y(app.world.item_level(toy)), float(toy.z))
		toy_claims.erase(toy_id)

func _item(id: String) -> Dictionary:
	if id.is_empty(): return {}
	for item: Dictionary in app.world.items:
		if str(item.id) == id and is_instance_valid(item.get("node")): return item
	return {}
