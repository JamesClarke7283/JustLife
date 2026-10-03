extends Node
class_name LifeToyFlow
## Toys on the floor and in their boxes: the one place that decides where a toy is.
##
## A toy (a pet's toy, or a child's or baby's) is in exactly one of three states:
##
##   * boxed   `box_id` names its container; the node is hidden and cannot be clicked;
##   * carried `carried` is true and `rest` is the floor pose it was lifted from (a
##             Lifelet's hand or a dog's mouth); a save writes the rest pose;
##   * floor   neither; it lies where its record says and can be picked up.
##
## `nest()` and `unnest()` are the only writers of the boxed state, each in one
## synchronous call, so a toy is never hidden without its box or in a box while
## visible. `reconcile()` mends anything a load, an undo or an edit left behind
## and `invariant_errors()` reports it, so tests can assert after every step.
##
## Tidying a toy away is a real flow on the Lifelet's queued `put_pet_toy` action
## (`toy_stage`: fetch -> pickup -> carry -> place -> done): they walk to the toy,
## stoop and lift it, carry it to a box that takes it and set it in. Taking one out
## (`take_pet_toy`: fetch -> draw -> done) is the same in reverse. Both are cleaned
## up on cancel, so a toy is never left in the air or hidden outside a box.

const PICKUP_SECONDS: float = 1.7
const PLACE_SECONDS: float = 1.3
const DRAW_SECONDS: float = 1.9

const TIDY_ID: String = "put_pet_toy"
const TAKE_ID: String = "take_pet_toy"
const PET_TOYS: Array[String] = ["pet_toy_cat", "pet_toy_dog"]
const KIDS_TOY: String = "kids_toy"
## What each container takes and how many it holds.
const CONTAINERS: Dictionary = {
	"cat_toy_box": {"accepts": ["pet_toy_cat"], "capacity": 6},
	"dog_toy_box": {"accepts": ["pet_toy_dog"], "capacity": 6},
	"toy_chest": {"accepts": ["kids_toy"], "capacity": 12},
	"toybox": {"accepts": ["kids_toy"], "capacity": 12},
}
## Play that leaves toys out, and how many a home may have lying about at once.
const PLAY_ACTIONS: Array[String] = ["play_toys", "play_dollhouse", "play_with_baby", "play_baby_mat"]
const MAX_LOOSE_KIDS_TOYS: int = 8
const BABY_STYLES: Array[String] = ["rattle", "duck", "ball"]
const KID_STYLES: Array[String] = ["block", "ball", "bear"]
const BABY_REASON: String = "Babies and toddlers can play with toys, but cannot put them away yet."

var app: Node
## member id -> {"kind": "put" | "take", "toy", "box", "target", "stage", "t", "rest", ...}
var stages: Dictionary = {}
var _reach_cache: Dictionary = {}
var _reach_generation: int = -1


## Forget every fetch in flight, for a world that has just been replaced.
func reset() -> void:
	stages.clear()


# --------------------------------------------------------------- vocabulary

static func is_toy(kind: String) -> bool:
	return kind in PET_TOYS or kind == KIDS_TOY


static func is_container(kind: String) -> bool:
	return CONTAINERS.has(kind)


static func capacity(kind: String) -> int:
	return int((CONTAINERS.get(kind, {}) as Dictionary).get("capacity", 0))


static func accepts(box_kind: String, toy_kind: String) -> bool:
	return toy_kind in ((CONTAINERS.get(box_kind, {}) as Dictionary).get("accepts", []) as Array)


## Mend a saved layout before it is built: a toy whose box is gone, does not take
## it, is on another floor or is over capacity is let out onto the floor rather than
## refusing the whole home, and the loose toys an older build left lying where they
## popped out of a box (`toy_<box>_<n>`, within 0.3 m of it) are put back in it.
## Works on a copy.
static func normalize_layout(layout: Array) -> Array:
	var result: Array = layout.duplicate(true)
	# Two records with one id (an older build could restock a box over a toy left out of
	# it) would refuse the whole home: the later toy is given an id of its own.
	var seen: Dictionary = {}
	for entry: Variant in result:
		if not entry is Dictionary or not is_toy(str(entry.get("kind", ""))): 
			if entry is Dictionary and entry.get("id") is String: seen[str(entry.id)] = true
			continue
		var id: String = str(entry.get("id", ""))
		if seen.has(id):
			var serial: int = 1
			while seen.has("%s_dup%d" % [id, serial]): serial += 1
			entry["id"] = "%s_dup%d" % [id, serial]
			id = str(entry.id)
		seen[id] = true
	var boxes: Dictionary = {}
	for entry: Variant in result:
		if entry is Dictionary and is_container(str(entry.get("kind", ""))) and str(entry.get("id", "")) != "":
			boxes[str(entry.id)] = entry
	if boxes.is_empty():
		for entry: Variant in result:
			if entry is Dictionary and is_toy(str(entry.get("kind", ""))) and entry.has("box_id"): entry.erase("box_id")
		return result
	var counts: Dictionary = {}
	# Records that already say where they are come first, so they keep their places.
	for pass_index: int in 2:
		for entry: Variant in result:
			if not entry is Dictionary or not is_toy(str(entry.get("kind", ""))): continue
			var box_id: String = str(entry.get("box_id", ""))
			if pass_index == 0 and box_id.is_empty(): continue
			if pass_index == 1:
				if not box_id.is_empty(): continue
				box_id = _legacy_box(entry, boxes)
				if box_id.is_empty(): continue
			var box: Dictionary = boxes.get(box_id, {})
			var fits: bool = not box.is_empty() and accepts(str(box.kind), str(entry.kind)) \
				and int(box.get("level", 0)) == int(entry.get("level", 0)) \
				and int(counts.get(box_id, 0)) < capacity(str(box.kind))
			if fits:
				counts[box_id] = int(counts.get(box_id, 0)) + 1
				entry["box_id"] = box_id
			else:
				entry.erase("box_id")
	return result


static func _legacy_box(toy: Dictionary, boxes: Dictionary) -> String:
	var id: String = str(toy.get("id", ""))
	for box_id: String in boxes:
		if not id.begins_with("toy_%s_" % box_id): continue
		var box: Dictionary = boxes[box_id]
		if Vector2(float(toy.get("x", 0.0)) - float(box.get("x", 0.0)), float(toy.get("z", 0.0)) - float(box.get("z", 0.0))).length() <= .3:
			return box_id
	return ""


# -------------------------------------------------------------------- access

func item(id: String) -> Dictionary:
	return app._find_item(id) if not id.is_empty() else {}


func member_id(sim: LifeSim) -> String:
	for member: Dictionary in app.household.members:
		if member.sim == sim: return str(member.id)
	return ""


func actor(id: String) -> LifeActor:
	return app.world.actors.get(id)


func is_boxed(toy: Dictionary) -> bool:
	return str(toy.get("box_id", "")) != ""


func is_carried(toy: Dictionary) -> bool:
	return bool(toy.get("carried", false))


func is_floor(toy: Dictionary) -> bool:
	return is_toy(str(toy.get("kind", ""))) and not is_boxed(toy) and not is_carried(toy)


func toys() -> Array:
	var out: Array = []
	for entry: Dictionary in app.world.items:
		if is_toy(str(entry.kind)) and is_instance_valid(entry.get("node")): out.append(entry)
	return out


func containers() -> Array:
	var out: Array = []
	for entry: Dictionary in app.world.items:
		if is_container(str(entry.kind)) and is_instance_valid(entry.get("node")): out.append(entry)
	return out


## The toys nested in a container.
func contents(box_id: String) -> Array:
	var out: Array = []
	for entry: Dictionary in app.world.items:
		if str(entry.get("box_id", "")) == box_id and is_toy(str(entry.kind)): out.append(entry)
	return out


## Toys lying on the floor, optionally of one kind.
func loose_toys(kind: String = "") -> Array:
	var out: Array = []
	for entry: Dictionary in toys():
		if is_floor(entry) and (kind.is_empty() or str(entry.kind) == kind): out.append(entry)
	return out


## The Lifelet whose queue holds a tidy of this toy, or "".
func claimed_by(toy_id: String) -> String:
	for member: Dictionary in app.household.members:
		for action: Dictionary in member.sim.action_queue:
			if str(action.get("id", "")) == TIDY_ID and str(action.get("target_id", "")) == toy_id: return str(member.id)
	return ""


func pet_claimed(toy_id: String) -> bool:
	return app.pet_behavior().toy_claims.has(toy_id)


func carried_by_pet(toy_id: String) -> bool:
	for errand: Variant in app.pet_errands.values():
		if errand is Dictionary and bool(errand.get("carrying", false)) and str(errand.get("target", "")) == toy_id: return true
	return false


## Places left in a container once what is on its way there is counted.
func free_slots(box: Dictionary) -> int:
	var pending: int = 0
	for member: Dictionary in app.household.members:
		for action: Dictionary in member.sim.action_queue:
			if str(action.get("id", "")) != TIDY_ID: continue
			var toy: Dictionary = item(str(action.get("target_id", "")))
			if toy.is_empty() or not accepts(str(box.kind), str(toy.kind)): continue
			if is_floor(toy) or is_carried(toy): pending += 1
	return capacity(str(box.kind)) - contents(str(box.id)).size() - pending


## Whether somebody can walk to a box from here. Remembered while the navigation is
## unchanged, since every tidy check asks.
func box_reachable(from: Vector3, box: Dictionary) -> bool:
	var generation: int = app.world.lot_navigation.generation
	if generation != _reach_generation:
		_reach_cache.clear()
		_reach_generation = generation
	var at: Vector3 = app.world.approach(box)
	if not at.is_finite() or not from.is_finite(): return false
	var key: String = "%s|%d,%d" % [str(box.id), roundi(from.x * 2.0), roundi(from.z * 2.0)]
	if not _reach_cache.has(key): _reach_cache[key] = not app.world.path_to(from, at).is_empty()
	return bool(_reach_cache[key])


## The nearest box on the toy's own floor that takes it and has room, or {}. A box
## that other tidies are already filling is chosen only when no other has room.
func container_for(toy: Dictionary, from: Vector3 = Vector3.INF, spent: Dictionary = {}) -> Dictionary:
	var level: int = app.world.item_level(toy)
	var origin: Vector3 = from if from.is_finite() else toy.node.global_position
	var own: int = 1 if (not claimed_by(str(toy.id)).is_empty() or is_carried(toy)) else 0
	var best: Dictionary = {}
	var best_key: Vector2 = Vector2(INF, INF)
	for box: Dictionary in containers():
		if not accepts(str(box.kind), str(toy.kind)) or app.world.item_level(box) != level: continue
		if contents(str(box.id)).size() >= capacity(str(box.kind)): continue
		if not box_reachable(origin, box): continue
		if not spent.is_empty() and free_slots(box) - int(spent.get(str(box.id), 0)) <= 0: continue
		var key := Vector2(0.0 if free_slots(box) + own > 0 else 1.0, box.node.global_position.distance_squared_to(origin))
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best = box
			best_key = key
	return best


# -------------------------------------------------------------- the two writers

## Why this toy cannot go into this box, or "".
func can_nest(toy: Dictionary, box: Dictionary) -> String:
	if toy.is_empty() or not is_toy(str(toy.get("kind", ""))): return "Choose a toy to put away."
	if box.is_empty() or not accepts(str(box.kind), str(toy.kind)): return "That toy does not go in this box."
	if app.world.item_level(box) != app.world.item_level(toy): return "That toy box is on another floor."
	var inside: int = contents(str(box.id)).size()
	if str(toy.get("box_id", "")) == str(box.id): inside -= 1
	if inside >= capacity(str(box.kind)): return "This toy box is full."
	return ""


## Put a toy into a box: the only place a toy becomes boxed. Atomic: the record, the
## node, the collider and the navigation change together, or nothing does.
func nest(toy: Dictionary, box: Dictionary) -> bool:
	if not can_nest(toy, box).is_empty(): return false
	var level: int = app.world.item_level(box)
	var index: int = contents(str(box.id)).size()
	var angle: float = float(index) * TAU / float(maxi(1, capacity(str(box.kind))))
	var at := Vector3(box.node.position.x + cos(angle) * .12, LifeBuildingState.level_y(level), box.node.position.z + sin(angle) * .12)
	toy["box_id"] = str(box.id)
	toy["level"] = level
	toy.erase("carried")
	toy.erase("rest")
	toy.node.position = at
	toy.node.rotation = Vector3(0.0, deg_to_rad(float(index * 30)), 0.0)
	toy.node.visible = false
	toy["x"] = at.x
	toy["z"] = at.z
	_relayer(toy, level)
	app.world.set_item_pickable(toy, false)
	return true


## Take a toy out onto the floor at `spot` (a clear place in front of its box when
## none is given): the inverse of `nest()`.
func unnest(toy: Dictionary, spot: Vector3 = Vector3.INF) -> bool:
	if toy.is_empty() or not is_instance_valid(toy.get("node")): return false
	var box: Dictionary = item(str(toy.get("box_id", "")))
	if not spot.is_finite(): spot = floor_spot(box if not box.is_empty() else toy)
	var level: int = app.world.item_level(box) if not box.is_empty() else app.world.item_level(toy)
	toy.erase("box_id")
	toy.erase("carried")
	toy.erase("rest")
	toy["level"] = level
	toy.node.position = Vector3(spot.x, LifeBuildingState.level_y(level), spot.z)
	toy.node.rotation = Vector3(0.0, toy.node.rotation.y, 0.0)
	toy.node.visible = true
	toy["x"] = toy.node.position.x
	toy["z"] = toy.node.position.z
	_relayer(toy, level)
	app.world.set_item_pickable(toy, true)
	return true


## A clear place on the floor in front of a furnishing for something to land.
func floor_spot(furnishing: Dictionary) -> Vector3:
	var world: Node = app.world
	var node: Node3D = furnishing.node
	var level: int = world.item_level(furnishing)
	var variant: Dictionary = furnishing.get("variant", {}) if furnishing.get("variant", {}) is Dictionary else {}
	var reach: float = world.front_extent(str(furnishing.kind), str(variant.get("size", "")), str(variant.get("style", "")))
	var offsets: Array[Vector3] = [Vector3(0, 0, reach + .3), Vector3(.4, 0, reach + .25), Vector3(-.4, 0, reach + .25), Vector3(.7, 0, reach), Vector3(-.7, 0, reach), Vector3(0, 0, reach + .6)]
	for offset: Vector3 in offsets:
		var wanted: Vector3 = node.to_global(offset)
		var at: Vector3 = world.nearest_clear_point(wanted, level, 1) if not world.construction.building_state.is_empty() else Vector3(wanted.x, LifeBuildingState.level_y(level), wanted.z)
		if not at.is_finite() or Vector2(at.x - wanted.x, at.z - wanted.z).length() > .2: continue
		if _toy_near(at, level): continue
		return at
	var fallback: Vector3 = node.to_global(Vector3(0, 0, reach + .3))
	fallback.y = LifeBuildingState.level_y(level)
	return fallback


func _toy_near(at: Vector3, level: int) -> bool:
	for entry: Dictionary in toys():
		if is_boxed(entry) or app.world.item_level(entry) != level: continue
		if Vector2(entry.node.position.x - at.x, entry.node.position.z - at.z).length() < .18: return true
	return false


## A toy is drawn and picked on the floor it lies on: keep its render layers (and
## its collider) in step with its level, whichever floor a box and its toys moved to.
func _relayer(toy: Dictionary, level: int) -> void:
	if is_instance_valid(toy.get("node")): app.world.assign_structure_layer(toy.node, level)


## Everything that changed because a toy moved between states.
func _changed() -> void:
	app.world.rebuild_navigation()
	app._refresh_sim_targets()


# ------------------------------------------------------------------- lifecycle

## A container is about to be sold, stolen or stored: its toys go with it.
## Returns the number of toys removed.
func take_contents_away(box_id: String) -> int:
	var count: int = 0
	for toy: Dictionary in contents(box_id):
		app.world.remove_item(str(toy.id))
		count += 1
	return count


## A container has moved: every toy in it moves too.
func container_moved(box: Dictionary) -> void:
	var toys_in: Array = contents(str(box.id))
	for index: int in range(toys_in.size()):
		var toy: Dictionary = toys_in[index]
		toy.erase("box_id")
		toy["box_id"] = str(box.id)
		var level: int = app.world.item_level(box)
		var angle: float = float(index) * TAU / float(maxi(1, capacity(str(box.kind))))
		toy.node.position = Vector3(box.node.position.x + cos(angle) * .12, LifeBuildingState.level_y(level), box.node.position.z + sin(angle) * .12)
		toy["level"] = level
		toy["x"] = toy.node.position.x
		toy["z"] = toy.node.position.z
		toy.node.visible = false
		_relayer(toy, level)
		app.world.set_item_pickable(toy, false)


## Mend whatever a load, an undo, or an edit left inconsistent. Returns the number
## of toys that had to be corrected.
func reconcile() -> int:
	var repairs: int = 0
	var counts: Dictionary = {}
	for toy: Dictionary in toys():
		if is_boxed(toy):
			var box: Dictionary = item(str(toy.box_id))
			var fits: bool = not box.is_empty() and accepts(str(box.kind), str(toy.kind)) and app.world.item_level(box) == app.world.item_level(toy) \
				and int(counts.get(str(box.id), 0)) < capacity(str(box.kind))
			if not fits:
				# A box that is gone, wrong or full cannot keep its toys hidden: let
				# them out where they are, onto clear floor.
				var spot: Vector3 = floor_spot(box) if not box.is_empty() and app.world.item_level(box) == app.world.item_level(toy) else _clear_near(toy.node.global_position, app.world.item_level(toy))
				unnest(toy, spot)
				repairs += 1
				continue
			counts[str(box.id)] = int(counts.get(str(box.id), 0)) + 1
			if is_carried(toy):
				toy.erase("carried"); toy.erase("rest"); repairs += 1
			if toy.node.visible or _pickable(toy):
				toy.node.visible = false
				app.world.set_item_pickable(toy, false)
				repairs += 1
		elif is_carried(toy):
			if not _someone_has(toy):
				_put_down(toy, Vector3.INF)
				repairs += 1
		elif not toy.node.visible:
			toy.node.visible = true
			app.world.set_item_pickable(toy, true)
			repairs += 1
	return repairs


func _someone_has(toy: Dictionary) -> bool:
	for state: Variant in stages.values():
		if state is Dictionary and str(state.get("toy", "")) == str(toy.id): return true
	return carried_by_pet(str(toy.id))


func _pickable(toy: Dictionary) -> bool:
	for body: Node in toy.node.find_children("*", "StaticBody3D", false, false):
		if (body as StaticBody3D).collision_layer != 0: return true
	return false


func _clear_near(point: Vector3, level: int) -> Vector3:
	if app.world.construction.building_state.is_empty(): return Vector3(point.x, LifeBuildingState.level_y(level), point.z)
	var at: Vector3 = app.world.nearest_clear_point(point, level)
	return at if at.is_finite() else Vector3(point.x, LifeBuildingState.level_y(level), point.z)


## What is wrong with the toys right now, as readable lines; empty when all is well.
func invariant_errors() -> Array[String]:
	var errors: Array[String] = []
	var counts: Dictionary = {}
	for toy: Dictionary in toys():
		var id: String = str(toy.id)
		var boxed: bool = is_boxed(toy)
		var carried: bool = is_carried(toy)
		if boxed and carried: errors.append("%s is both boxed and carried" % id)
		if boxed:
			var box: Dictionary = item(str(toy.box_id))
			if box.is_empty(): errors.append("%s is boxed in a box that is gone" % id)
			elif not accepts(str(box.kind), str(toy.kind)): errors.append("%s is boxed in a box that does not take it" % id)
			elif app.world.item_level(box) != app.world.item_level(toy): errors.append("%s is boxed across floors" % id)
			else: counts[str(box.id)] = int(counts.get(str(box.id), 0)) + 1
			if toy.node.visible: errors.append("%s is boxed but visible" % id)
			if _pickable(toy): errors.append("%s is boxed but can be clicked" % id)
		elif carried:
			if not toy.get("rest") is Dictionary or (toy.rest as Dictionary).is_empty(): errors.append("%s is carried with no rest pose" % id)
		else:
			if not toy.node.visible: errors.append("%s is on the floor but hidden" % id)
			if not _pickable(toy) and not toy.node.find_children("*", "StaticBody3D", false, false).is_empty(): errors.append("%s is on the floor but cannot be clicked" % id)
	for box_id: String in counts:
		var box_item: Dictionary = item(box_id)
		if not box_item.is_empty() and int(counts[box_id]) > capacity(str(box_item.kind)): errors.append("%s holds more than it can" % box_id)
	return errors


# --------------------------------------------------------------------- queueing

## Why this Lifelet cannot put this toy away right now, or "".
func tidy_error(sim: LifeSim, toy_id: String) -> String:
	var toy: Dictionary = item(toy_id)
	if toy.is_empty() or not is_toy(str(toy.kind)): return "Choose a toy to put away."
	if str(sim.character.age_stage) == "baby": return BABY_REASON
	var availability: Dictionary = sim.get_action_availability(TIDY_ID, toy_id)
	if not bool(availability.available): return str(availability.reason)
	if is_boxed(toy): return "That toy is already in its box."
	if is_carried(toy) or carried_by_pet(toy_id): return "Somebody is playing with that toy."
	if pet_claimed(toy_id): return "A pet is playing with that toy."
	var other: String = claimed_by(toy_id)
	if not other.is_empty() and other != member_id(sim): return "Somebody else is already putting that away."
	var any_box: bool = false
	var same_level: bool = false
	var has_room: bool = false
	for box: Dictionary in containers():
		if not accepts(str(box.kind), str(toy.kind)): continue
		any_box = true
		if app.world.item_level(box) != app.world.item_level(toy): continue
		same_level = true
		if free_slots(box) > 0 or (not other.is_empty() and other == member_id(sim) and contents(str(box.id)).size() < capacity(str(box.kind))):
			has_room = true
			if box_reachable(toy.node.global_position, box): return ""
	if not any_box: return "Place a matching toy box first."
	if not same_level: return "The toy box is on another floor."
	if has_room: return "The toy box cannot be reached."
	return "The toy box is full."


## Send this Lifelet to put one toy away.
func queue_tidy(person: String, toy_id: String) -> Dictionary:
	var sim: LifeSim = app.household.member_sim(person)
	if sim == null: return {"ok": false, "error": "That Lifelet is not part of this household."}
	var reason: String = tidy_error(sim, toy_id)
	if not reason.is_empty(): return {"ok": false, "error": reason}
	if claimed_by(toy_id) == person: return {"ok": false, "error": "That toy is already on their list.", "already": true}
	var toy: Dictionary = item(toy_id)
	var at: Vector3 = app.world.approach(toy)
	if not at.is_finite(): return {"ok": false, "error": "There is no clear route to that toy."}
	if not sim.queue_action(TIDY_ID, toy_id, at): return {"ok": false, "error": "Could not queue that."}
	return {"ok": true}


## Queue every loose toy of a kind (all kinds when empty), nearest first, up to a
## handful at a time, each one its own cancellable action.
func queue_tidy_all(person: String, kind: String = "", limit: int = 6) -> Dictionary:
	var sim: LifeSim = app.household.member_sim(person)
	var body: LifeActor = actor(person)
	if sim == null or not is_instance_valid(body): return {"ok": false, "error": "That Lifelet is not part of this household.", "queued": 0}
	var candidates: Array = loose_toys(kind)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.node.global_position.distance_squared_to(body.global_position) < b.node.global_position.distance_squared_to(body.global_position))
	var queued: int = 0
	var already: int = 0
	var reason: String = "There is nothing to tidy."
	for toy: Dictionary in candidates:
		if queued >= limit: break
		var answer: Dictionary = queue_tidy(person, str(toy.id))
		if bool(answer.ok): queued += 1
		elif bool(answer.get("already", false)): already += 1
		else: reason = str(answer.error)
	if queued == 0 and already > 0: reason = "Already tidying those."
	return {"ok": queued > 0, "error": "" if queued > 0 else reason, "queued": queued}


## A pick for an idle Lifelet: the nearest loose toy they could put away.
func autonomous_tidy_choice(sim: LifeSim, excluded: Array = []) -> Dictionary:
	if not sim.action_queue.is_empty() or sim.is_away(): return {}
	if not str(sim.character.age_stage) in ["child", "teen", "young_adult", "adult", "elder"]: return {}
	var body: LifeActor = actor(member_id(sim))
	if not is_instance_valid(body): return {}
	var candidates: Array = []
	for toy: Dictionary in loose_toys():
		if excluded.has(str(toy.id)) or not tidy_error(sim, str(toy.id)).is_empty(): continue
		var at: Vector3 = app.world.approach(toy)
		if not at.is_finite() or app.world.path_to(body.position, at).is_empty(): continue
		candidates.append({"id": TIDY_ID, "target_id": str(toy.id), "position": at})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.position.distance_squared_to(body.position) < b.position.distance_squared_to(body.position))
	return candidates[0] if not candidates.is_empty() else {}


## The household-cleaning contract: what tidying toys still has to do.
func chores(person: String) -> Array:
	var sim: LifeSim = app.household.member_sim(person)
	var out: Array = []
	if sim == null: return out
	for toy: Dictionary in loose_toys():
		var reason: String = tidy_error(sim, str(toy.id))
		out.append({"chore": "tidy_toys", "target_id": str(toy.id), "action": TIDY_ID, "position": app.world.approach(toy), "label": "Tidy %s" % str(toy.label).to_lower(), "available": reason.is_empty(), "reason": reason})
	return out


## Play leaves a few toys out: one to three, near where the Lifelet played, when the
## home has somewhere to put them away and not too many are already out.
func scatter_after_play(person: String, action: Dictionary) -> int:
	if str(action.get("id", "")) not in PLAY_ACTIONS: return 0
	var sim: LifeSim = app.household.member_sim(person)
	var body: LifeActor = actor(person)
	if sim == null or not is_instance_valid(body): return 0
	var level: int = maxi(0, app.world.point_level(body.position))
	# Only as many toys as the boxes can take, so nothing is left out that cannot be put away.
	var space: int = 0
	for box: Dictionary in containers():
		if accepts(str(box.kind), KIDS_TOY) and app.world.item_level(box) == level: space += maxi(0, capacity(str(box.kind)) - contents(str(box.id)).size())
	var loose: int = loose_toys(KIDS_TOY).size()
	var room: int = mini(mini(MAX_LOOSE_KIDS_TOYS - loose, space - loose), furnishing_room())
	if room <= 0: return 0
	var styles: Array[String] = BABY_STYLES if str(sim.character.age_stage) == "baby" else KID_STYLES
	var wanted: int = mini(room, 1 + int(floorf(sim.minutes)) % 3)
	var made: int = 0
	for attempt: int in 8:
		if made >= wanted: break
		var angle: float = float(attempt) * 2.4 + float(int(floorf(sim.minutes)) % 7)
		var distance: float = .6 + .12 * float(attempt % 4)
		var wished: Vector3 = body.global_position + Vector3(sin(angle) * distance, 0.0, cos(angle) * distance)
		var at: Vector3 = _clear_near(wished, level) if not app.world.construction.building_state.is_empty() else Vector3(wished.x, LifeBuildingState.level_y(level), wished.z)
		if not at.is_finite() or Vector2(at.x - wished.x, at.z - wished.z).length() > .3 or _toy_near(at, level): continue
		var record: Dictionary = {"id": _next_id("kids_toy_%s" % person), "kind": KIDS_TOY, "style": styles[(loose_toys(KIDS_TOY).size() + made) % styles.size()], "x": at.x, "z": at.z, "rotation": fmod(angle * 57.3, 360.0)}
		if level > 0: record["level"] = level
		app.world.add_item(record, false)
		if not item(str(record.id)).is_empty(): made += 1
	if made > 0: _changed()
	return made


func _next_id(prefix: String) -> String:
	var serial: int = 1
	while not item("%s_%d" % [prefix, serial]).is_empty(): serial += 1
	return "%s_%d" % [prefix, serial]


## How many more furnishings the home can hold before a layout is refused.
func furnishing_room() -> int:
	var used: int = 0
	for entry: Dictionary in app.world.items:
		if not bool(entry.get("transient_food", false)) and not bool(entry.get("transient_puddle", false)) and not bool(entry.get("derived", false)): used += 1
	return maxi(0, LifeWorld.MAX_FURNISHINGS - used - 4)


## Put toys into a box: a pet toy box comes with six of its own, and anything taken
## out of storage gets back the number it went in with (as many as the home has room
## for). They are made nested, each with an id nothing else has.
func stock(box: Dictionary, count: int = -1) -> int:
	var pet_kind: String = str(LifePets.TOY_BOX_TOYS.get(str(box.kind), ""))
	var toy_kind: String = pet_kind if not pet_kind.is_empty() else (KIDS_TOY if accepts(str(box.kind), KIDS_TOY) else "")
	if toy_kind.is_empty() or not LifeCatalog.ITEMS.has(toy_kind): return 0
	var level: int = app.world.item_level(box)
	var made: int = 0
	var total: int = mini(clampi(LifePets.TOYS_PER_BOX if count < 0 else count, 0, capacity(str(box.kind))), furnishing_room())
	var serial: int = 0
	for index: int in total:
		while not item("toy_%s_%d" % [str(box.id), serial]).is_empty(): serial += 1
		var angle: float = float(index) * TAU / float(maxi(1, capacity(str(box.kind))))
		var record: Dictionary = {"id": "toy_%s_%d" % [str(box.id), serial], "kind": toy_kind, "x": box.node.position.x + cos(angle) * .12, "z": box.node.position.z + sin(angle) * .12, "rotation": float(index * 30), "box_id": str(box.id)}
		if toy_kind == KIDS_TOY: record["style"] = KID_STYLES[index % KID_STYLES.size()]
		if level > 0: record["level"] = level
		app.world.add_item(record, false)
		if not item(str(record.id)).is_empty(): made += 1
		serial += 1
	app.world.rebuild_navigation()
	return made


# -------------------------------------------------------------------- the flow

func tidy_action(action: Dictionary) -> bool:
	return str(action.get("id", "")) == TIDY_ID


func take_action(action: Dictionary) -> bool:
	return str(action.get("id", "")) == TAKE_ID


func toy_action(action: Dictionary) -> bool:
	return tidy_action(action) or take_action(action)


## Past its fetch, a tidy walks to the box and sets the toy down, so the world
## refreshing its targets must not pull it back to where the toy once lay.
func keeps_own_target(action: Dictionary) -> bool:
	return toy_action(action) and str(action.get("toy_stage", "fetch")) != "fetch"


## A restored tidy or take begins again: a tidy from the walk to its toy (which a save
## wrote at its resting place), a take that was mid-draw as finished (the toy it drew
## already lies out). Nothing to do any more means the task is dropped, and a cleaning
## round carries on with its next task.
func restore(sim: LifeSim, action: Dictionary) -> bool:
	if not toy_action(action): return true
	var target: Dictionary = item(str(action.get("target_id", "")))
	var stage: String = str(action.get("toy_stage", "fetch"))
	if target.is_empty() or (tidy_action(action) and not is_floor(target)) or (take_action(action) and stage != "draw" and contents(str(target.id)).is_empty()):
		_drop_task(sim)
		return false
	action["phase"] = "approach"
	action["toy_stage"] = "done" if take_action(action) and stage in ["draw", "done"] else "fetch"
	action["target_position"] = app.world.approach(target)
	return true


## Called as the action starts, before the route is made, to point it at whatever
## the current stage is walking to.
func resolve(sim: LifeSim, action: Dictionary) -> void:
	if not toy_action(action): return
	if str(action.get("phase", "")) == "active": return
	var person: String = member_id(sim)
	var target: Dictionary = item(str(action.get("target_id", "")))
	if target.is_empty(): return
	if not action.has("toy_stage") or (str(action.toy_stage) not in ["fetch", "done"] and not stages.has(person)):
		action["toy_stage"] = "fetch"
		action["target_position"] = app.world.approach(target)
		return
	if tidy_action(action) and str(action.toy_stage) == "carry":
		var box: Dictionary = item(str((stages.get(person, {}) as Dictionary).get("box", "")))
		if not box.is_empty(): action["target_position"] = app.world.approach(box)


func before_begin(sim: LifeSim, action: Dictionary) -> bool:
	if tidy_action(action): return _begin_tidy(sim, action)
	if take_action(action): return _begin_take(sim, action)
	return true


func _begin_tidy(sim: LifeSim, action: Dictionary) -> bool:
	var person: String = member_id(sim)
	var toy: Dictionary = item(str(action.get("target_id", "")))
	if toy.is_empty():
		_stop(sim, "That toy is no longer here.")
		return false
	match str(action.get("toy_stage", "fetch")):
		"fetch":
			# Somebody (or a save and load) already put it away: nothing left to do.
			if is_boxed(toy):
				action["toy_stage"] = "done"
				return true
			var problem: String = tidy_error(sim, str(toy.id))
			if not problem.is_empty():
				_stop(sim, problem)
				return false
			var box: Dictionary = container_for(toy)
			if box.is_empty():
				_stop(sim, "The toy box is full.")
				return false
			toy["carried"] = true
			toy["rest"] = {"x": toy.node.position.x, "y": toy.node.position.y, "z": toy.node.position.z, "rotation": toy.node.rotation_degrees.y}
			app.world.set_item_pickable(toy, false)
			app.world.rebuild_navigation()
			stages[person] = {"kind": "put", "toy": str(toy.id), "target": str(toy.id), "box": str(box.id), "stage": "pickup", "t": 0.0, "rest": toy.node.global_position, "rest_basis": toy.node.global_basis.orthonormalized()}
			action["toy_stage"] = "pickup"
			return false
		"carry":
			var state: Dictionary = stages.get(person, {})
			if state.is_empty():
				action["toy_stage"] = "fetch"
				return false
			var destination: Dictionary = item(str(state.box))
			if not can_nest(toy, destination).is_empty():
				# The box it was bound for filled up or went away on the walk.
				destination = container_for(toy, app.world.actors[person].global_position)
				if destination.is_empty():
					_stop(sim, "The toy box is full.")
					return false
				state["box"] = str(destination.id)
			state["stage"] = "place"
			state["t"] = 0.0
			action["toy_stage"] = "place"
			return false
		"done":
			return true
	return false


func _begin_take(sim: LifeSim, action: Dictionary) -> bool:
	var person: String = member_id(sim)
	var box: Dictionary = item(str(action.get("target_id", "")))
	if box.is_empty() or not is_container(str(box.kind)):
		_stop(sim, "That toy box is no longer here.")
		return false
	match str(action.get("toy_stage", "fetch")):
		"fetch":
			if str(sim.character.age_stage) == "baby":
				_stop(sim, BABY_REASON)
				return false
			var inside: Array = contents(str(box.id))
			if inside.is_empty():
				_stop(sim, "Every toy from this box is already out.")
				return false
			var toy: Dictionary = inside.front()
			var spot: Vector3 = floor_spot(box)
			toy["carried"] = true
			toy.erase("box_id")
			toy["rest"] = {"x": spot.x, "y": spot.y, "z": spot.z, "rotation": toy.node.rotation_degrees.y}
			toy.node.position = Vector3(box.node.position.x, LifeBuildingState.level_y(app.world.item_level(box)), box.node.position.z)
			toy.node.visible = true
			app.world.set_item_pickable(toy, false)
			stages[person] = {"kind": "take", "toy": str(toy.id), "target": str(box.id), "box": str(box.id), "stage": "draw", "t": 0.0, "spot": spot}
			action["toy_stage"] = "draw"
			return false
		"done":
			return true
	return false


## Only the action that is really using a toy lets go of it.
func canceled(sim: LifeSim, action: Dictionary) -> void:
	var person: String = member_id(sim)
	if not toy_action(action): return
	var state: Dictionary = stages.get(person, {})
	if not state.is_empty() and str(state.get("target", "")) == str(action.get("target_id", "")): release(person, false)


func finished(person: String, action: Dictionary) -> void:
	if not toy_action(action): return
	var state: Dictionary = stages.get(person, {})
	if not state.is_empty() and str(state.get("target", "")) == str(action.get("target_id", "")): release(person, false)


## Put a toy that is still in somebody's hands back on the floor, and stop
## presenting the fetch. `refresh` is false when the caller is itself cancelling the
## action (the targets must not be refreshed under it).
func release(person: String, refresh: bool = true) -> void:
	var state: Dictionary = stages.get(person, {})
	var body: LifeActor = actor(person)
	stages.erase(person)
	if is_instance_valid(body): body.toy_presentation = {}
	if state.is_empty(): return
	var toy: Dictionary = item(str(state.toy))
	if toy.is_empty() or not is_instance_valid(toy.get("node")) or is_boxed(toy): return
	if not is_carried(toy):
		# The record was rebuilt under the fetch (an undo, a move put back, a load of
		# another world) and lost the flag: the stage still knows where it was lifted from.
		var at_rest: Vector3 = (state.get("rest", state.get("spot", toy.node.global_position))) as Vector3
		toy["carried"] = true
		toy["rest"] = {"x": at_rest.x, "y": LifeBuildingState.level_y(app.world.item_level(toy)), "z": at_rest.z, "rotation": toy.node.rotation_degrees.y}
	var spot: Vector3 = Vector3.INF
	if str(state.kind) == "take": spot = state.get("spot", Vector3.INF) as Vector3
	elif str(state.stage) in ["carry", "place"] and is_instance_valid(body):
		spot = _beside(body, app.world.item_level(toy))
	_put_down(toy, spot)
	if refresh: _changed()
	else: app.world.rebuild_navigation()


## Set a carried toy on the floor: at `spot` when given, otherwise where it was
## lifted from.
func _put_down(toy: Dictionary, spot: Vector3) -> void:
	var rest: Dictionary = toy.get("rest", {}) if toy.get("rest") is Dictionary else {}
	toy.erase("carried")
	toy.erase("rest")
	var level: int = app.world.item_level(toy)
	var at: Vector3 = spot if spot.is_finite() else Vector3(float(rest.get("x", toy.node.position.x)), 0.0, float(rest.get("z", toy.node.position.z)))
	toy.node.global_position = Vector3(at.x, LifeBuildingState.level_y(level), at.z)
	toy.node.rotation = Vector3(0.0, deg_to_rad(float(rest.get("rotation", toy.node.rotation_degrees.y))), 0.0)
	toy.node.visible = true
	toy["x"] = toy.node.position.x
	toy["z"] = toy.node.position.z
	_relayer(toy, level)
	app.world.set_item_pickable(toy, true)


## A clear floor spot just in front of a Lifelet.
func _beside(body: LifeActor, level: int) -> Vector3:
	var forward: Vector3 = body.global_basis.orthonormalized() * Vector3(0, 0, .5)
	return _clear_near(body.global_position + forward, level)


# -------------------------------------------------------------- each frame

## Called for each household member in turn while they are the bound member: move
## a fetch along and place the toy in their hands.
func advance(person: String, delta: float) -> void:
	var sim: LifeSim = app.household.member_sim(person)
	var body: LifeActor = actor(person)
	if sim == null or not is_instance_valid(body): return
	var state: Dictionary = stages.get(person, {})
	if state.is_empty():
		if not body.toy_presentation.is_empty(): body.toy_presentation = {}
		return
	var action: Dictionary = sim.get_current_action()
	if action.is_empty() or not toy_action(action) or str(action.get("target_id", "")) != str(state.target):
		release(person)
		return
	var toy: Dictionary = item(str(state.toy))
	var box: Dictionary = item(str(state.box))
	if toy.is_empty() or box.is_empty() or not is_instance_valid(toy.get("node")):
		release(person)
		return
	var clock: float = delta * clampf(float(sim.speed), 0.0, 3.0)
	state["t"] = float(state.t) + clock
	var stage: String = str(state.stage)
	var duration: float = {"pickup": PICKUP_SECONDS, "place": PLACE_SECONDS, "draw": DRAW_SECONDS}.get(stage, 0.0)
	var level_y: float = LifeBuildingState.level_y(app.world.item_level(box))
	var presentation: Dictionary = {"stage": stage, "t": float(state.t), "duration": duration, "toy": str(toy.kind), "node": toy.node, "box_point": _rim_point(box, body, level_y),
		"toy_position": state.get("rest", toy.node.global_position), "toy_basis": state.get("rest_basis", Basis.IDENTITY)}
	if stage == "draw":
		var spot: Vector3 = state.spot as Vector3
		presentation["toy_position"] = spot
		presentation["toy_basis"] = Basis(Vector3.UP, toy.node.rotation.y)
		presentation["floor_point"] = spot
		presentation["from_point"] = (presentation.box_point as Vector3) - Vector3(0, .09, 0)
	body.toy_presentation = presentation
	# Face what is being reached for.
	var looking_at: Vector3 = Vector3.INF
	if stage == "pickup": looking_at = state.get("rest", Vector3.INF) as Vector3
	elif stage in ["place", "draw"]: looking_at = box.node.global_position
	if looking_at.is_finite():
		var toward: Vector3 = looking_at - body.global_position
		if Vector2(toward.x, toward.z).length() > .03:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(toward.x, toward.z), minf(clock * 9.0, 1.0))
	if body.toy_world_valid:
		toy.node.global_transform = body.toy_world_transform
	match stage:
		"pickup":
			if float(state.t) >= PICKUP_SECONDS:
				state["stage"] = "carry"
				state["t"] = 0.0
				action["toy_stage"] = "carry"
				sim._emit_action_started(action)
		"place":
			if float(state.t) >= PLACE_SECONDS:
				stages.erase(person)
				body.toy_presentation = {}
				if not nest(toy, box):
					_put_down(toy, _beside(body, app.world.item_level(toy)))
				_changed()
				action["toy_stage"] = "done"
				_activate(person)
		"draw":
			if float(state.t) >= DRAW_SECONDS:
				stages.erase(person)
				body.toy_presentation = {}
				_put_down(toy, state.spot as Vector3)
				_changed()
				action["toy_stage"] = "done"
				_activate(person)


## Where the hand goes to set a toy into a box (or reaches into it): the part of the
## box's top nearest the person, a little in from its edge, so a big chest is reached
## across its near rim rather than at its middle.
func _rim_point(box: Dictionary, body: LifeActor, level_y: float) -> Vector3:
	var node: Node3D = box.node
	var size: Vector2 = box.size if box.get("size") is Vector2 else Vector2(.5, .5)
	var local: Vector3 = node.to_local(body.global_position)
	var inset: float = .10
	var near := Vector3(clampf(local.x, -maxf(0.0, size.x * .5 - inset), maxf(0.0, size.x * .5 - inset)), 0.0, clampf(local.z, -maxf(0.0, size.y * .5 - inset), maxf(0.0, size.y * .5 - inset)))
	var world_point: Vector3 = node.to_global(near)
	return Vector3(world_point.x, level_y + float(box.get("height", .6)) + .03, world_point.z)


## Start the closing moment of a tidy or a draw: the walk to the box is over, so its
## route must not outlive it (an active action cannot also be travelling).
func _activate(person: String) -> void:
	if app.traversal.active(person): app.traversal.cancel(person)
	app.path = PackedVector3Array()
	app.path_index = 0
	app.household.begin_action(person)


# ------------------------------------------------------------ legacy shims

## Put a toy straight into the nearest box that takes it, with no walk or animation:
## for a queued action that finishes without having run the flow.
func put_away_now(toy_id: String) -> bool:
	var toy: Dictionary = item(toy_id)
	if toy.is_empty() or is_boxed(toy): return false
	var box: Dictionary = container_for(toy)
	if box.is_empty() or not nest(toy, box): return false
	_changed()
	return true


func take_out_now(box_id: String) -> bool:
	var box: Dictionary = item(box_id)
	var inside: Array = contents(box_id)
	if box.is_empty() or inside.is_empty(): return false
	unnest(inside.front())
	_changed()
	return true


## Give up on this task. A toy that is one task of a cleaning round does not end the
## round: the next task takes its place.
func _drop_task(sim: LifeSim) -> void:
	var current: Dictionary = sim.get_current_action()
	if current.has("chore") and is_instance_valid(app.get("chore_flow")):
		var before: int = sim.action_queue.size()
		app.chore_flow.successor_behind(sim, 0)
		if sim.action_queue.size() == before: app.chore_flow.ended_early(sim, current)
	sim.cancel_action()


## Give up on this toy with a reason.
func _stop(sim: LifeSim, message: String) -> void:
	sim._emit_notice(message)
	_drop_task(sim)
