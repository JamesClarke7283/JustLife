extends Node
## Household cleaning: the service that knows how dirty the home is, plans a round of
## chores and walks a Lifelet through it one real queued action at a time.
##
##   * `LifeChores` (chores.gd, owned by the household extras) remembers when each zone
##     was last cleaned; `LifeChoreSites` (chore_sites.gd) says where each is done.
##   * A chore is an ordinary `LifeSim` action (`chore_vacuum`, ...). A round of them is
##     a chain: each queued action carries the tasks still to come in `action.chore`, and
##     finishing one pushes the next to the front of the queue. Cancelling the front
##     action therefore cancels the whole round, and a save keeps it for free.
##   * Stations are published as simulation targets (`world.chore_targets`) so queued
##     chores survive the controller's target refresh.
##
## It never touches needs or funds itself: every chore carries its own effects.

const Defs = preload("res://scripts/chore_defs.gd")
const Chores = preload("res://scripts/chores.gd")
const Sites = preload("res://scripts/chore_sites.gd")

const NOUNS: Dictionary = {"sofa": "sofa", "loveseat": "loveseat", "armchair": "armchair", "bookshelf": "bookcase", "shelf": "shelf", "desk": "desk", "study_desk": "study desk", "office_desk": "office desk", "dining": "dining table", "table": "coffee table", "coffee_table": "coffee table", "side_table": "side table", "nightstand": "bedside table", "dressing_table": "dressing table", "tv": "television", "fireplace": "fireplace", "piano": "piano"}
const VERBS: Dictionary = {"chore_vacuum": "Vacuum", "chore_vacuum_curtains": "Vacuum", "chore_dust": "Dust", "chore_mop": "Mop", "chore_wipe_sink": "Wipe", "chore_scrub_toilet": "Scrub", "chore_fluff": "Fluff", "chore_sweep_entry": "Sweep", "chore_wipe_door": "Wipe", "chore_wash_window": "Wash"}
const QUICK_CAP_MINUTES: float = 90.0
## A Lifelet covers about a metre a game minute on foot; a task is on average this far from the last.
const WALK_MINUTES_PER_METRE: float = 1.0
const AVERAGE_WALK_MINUTES: float = 6.0
const THRESHOLDS: Dictionary = {"quick": 50.0, "full": 20.0, "inside": 20.0, "outside": 20.0, "custom": 10.0}
const AUTO_COOLDOWN: float = 90.0
## A zone this clean needs no more attention in a round, whoever cleaned it.
const ALREADY_CLEAN: float = 5.0
const URGENT: String = "urgent"

var app: Node
## station id -> station (every one, including those with nowhere to stand)
var stations: Dictionary = {}
var list: Array = []
var _by_item: Dictionary = {}
var _signature: String = ""
var _hour_synced: int = -1
var _visuals: RefCounted
var _grubby_day: int = -1
var _house_id: String = ""
var _reach_memo: Dictionary = {}
var _reach_generation: int = -1


func vis() -> RefCounted:
	if _visuals == null: _visuals = preload("res://scripts/chore_visuals.gd").new()
	return _visuals


func reset() -> void:
	if _visuals != null: _visuals.clear()
	stations.clear(); list.clear(); _by_item.clear(); _signature = ""
	if is_instance_valid(app) and is_instance_valid(app.world): app.world.chore_targets = []


# ------------------------------------------------------------------ helpers

func chores() -> Chores:
	return app.household_flow.chores


func now() -> float:
	return Chores.minute_of(int(app.household.day), float(app.household.minutes))


func member_id(sim: LifeSim) -> String:
	for member: Dictionary in app.household.members:
		if member.sim == sim: return str(member.id)
	return ""


func first_name(sim: LifeSim) -> String:
	return str(sim.character.get("name", "Somebody")).split(" ")[0]


## How much faster dirt returns with more people and pets about the place.
func household_factor() -> float:
	var residents: int = app.household.members.size()
	var pets: int = app.household.pets.get("pets", []).size() if app.household.pets is Dictionary else 0
	return minf(1.6, 1.0 + .10 * float(maxi(0, residents - 1)) + .05 * float(pets))


func is_station(id: String) -> bool:
	return id.begins_with(Defs.STATION_PREFIX)


## The station a chore at `target_id` means: the station itself, or for a furnishing the
## part of it nearest `near` (the dirtiest part when no place is given).
func station_for(id: String, target_id: String, near: Vector3 = Vector3.INF) -> Dictionary:
	if stations.has(target_id): return stations[target_id]
	var best: Dictionary = {}
	var best_score: float = -INF
	for station_id: Variant in _by_item.get(id + "|" + target_id, []):
		var station: Dictionary = stations[station_id]
		var score: float = (1000.0 if bool(station.ok) else 0.0) + (-Vector3(station.position).distance_to(near) if near.is_finite() and bool(station.ok) else dirt_of(station))
		if score > best_score:
			best_score = score; best = station
	return best


# ----------------------------------------------------------------- stations

func _signature_now() -> String:
	var world: Node = app.world
	var records: int = world.construction.records.size() if is_instance_valid(world.construction) else 0
	var revision: int = int(world.construction.building_state.get("revision", 0)) if is_instance_valid(world.construction) else 0
	var doors: int = world.construction.doors.doors.size() if is_instance_valid(world.construction) and world.construction.doors != null else 0
	return "%s|%d|%d|%d|%d|%d|%d" % [app.current_venue, world.get_instance_id(), world.lot_navigation.generation, world.items.size(), records, revision, doors]


## Rebuild the stations when the home has changed, publish them as targets and make
## sure every zone has a cleaning stamp. Cheap when nothing moved.
func rebuild_stations(force: bool = false) -> bool:
	if not is_instance_valid(app) or not is_instance_valid(app.world) or not is_instance_valid(app.world.house): return false
	var signature: String = _signature_now()
	if not force and signature == _signature: return false
	_signature = signature
	list = Sites.build(app)
	stations.clear(); _by_item.clear()
	var targets: Array = []
	for station: Dictionary in list:
		stations[station.id] = station
		if not str(station.item_id).is_empty():
			var link: String = str(station.chore) + "|" + str(station.item_id)
			if not _by_item.has(link): _by_item[link] = []
			_by_item[link].append(station.id)
		if bool(station.ok): targets.append({"id": station.id, "kind": "chore_station", "position": station.position, "level": station.level})
	app.world.chore_targets = targets
	if str(app.current_venue) == "home" and is_instance_valid(app.household_flow):
		var book: Chores = chores()
		# Dirt is remembered by place; a different house has none of the last one's.
		var house_id: String = str(app.properties.get("active", "")) if app.properties is Dictionary else ""
		if not _house_id.is_empty() and house_id != _house_id: book.reset()
		_house_id = house_id
		var valid: Dictionary = {}
		var stamp: float = now()
		for station: Dictionary in list:
			valid[station.key] = true
			book.ensure(str(station.key), str(station.dirt), stamp)
		# A piece that is picked up (to be moved or put back) is off the list for a while: what
		# was last cleaned on it must still be there when it is placed again, so nothing is
		# forgotten until the move is over.
		if not list.is_empty() and app.pending_move.is_empty(): book.prune(valid)
		# Toy counts belong to boxes that still exist.
		for box: Variant in book.toys.keys():
			if app._find_item(str(box)).is_empty(): book.toys.erase(box)
	vis().sync(self)
	return true


# --------------------------------------------------------------------- dirt

func dirt_of(station: Dictionary) -> float:
	var factor: float = household_factor() if str(station.category) in ["floors", "entry"] or bool(station.wet) else 1.0
	return chores().dirt(str(station.key), str(station.dirt), now(), factor)


## {category: {"count", "dirt" (mean), "worst"}} over every zone that can be cleaned.
func category_summary() -> Dictionary:
	var out: Dictionary = {}
	for station: Dictionary in list:
		var category: String = str(station.category)
		var entry: Dictionary = out.get(category, {"count": 0, "sum": 0.0, "worst": 0.0, "stations": 0})
		var amount: float = dirt_of(station)
		entry.count = int(entry.count) + 1; entry.sum = float(entry.sum) + amount
		entry.worst = maxf(float(entry.worst), amount)
		if bool(station.ok): entry.stations = int(entry.stations) + 1
		out[category] = entry
	for category: String in out:
		out[category]["dirt"] = float(out[category].sum) / maxf(1.0, float(out[category].count))
	# Toys are real items lying on the floor, not a dirt zone: the row is how many are out.
	var loose: int = app.toy_flow.loose_toys().size() if is_instance_valid(app.toy_flow) else 0
	if loose > 0 or not app.toy_flow.containers().is_empty():
		out["toys"] = {"count": loose, "sum": 0.0, "worst": minf(100.0, float(loose) * 25.0), "stations": loose, "dirt": minf(100.0, float(loose) * 25.0)}
	return out


## Percent clean of the whole home, 100 when spotless.
func home_score() -> float:
	var summary: Dictionary = category_summary()
	var weight: float = 0.0
	var spoiled: float = 0.0
	for category: String in summary:
		var share: float = float(Defs.WEIGHTS.get(category, .02))
		weight += share; spoiled += share * float(summary[category].dirt)
	if weight <= 0.0: return 100.0
	return clampf(100.0 - spoiled / weight, 0.0, 100.0)


## The dirtiest few zones, for the tooltip and the panel header.
func worst(count: int = 3) -> Array:
	var best: Dictionary = {}
	for station: Dictionary in list:
		if not bool(station.ok): continue
		var amount: float = dirt_of(station)
		var name: String = str(station.label)
		for strip: String in [" (left)", " (right)"]: name = name.replace(strip, "")
		if amount >= Defs.GRUBBY and (not best.has(name) or amount > float(best[name].dirt)): best[name] = {"label": name, "dirt": amount, "category": station.category}
	var rows: Array = best.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dirt) > float(b.dirt))
	return rows.slice(0, count)


# ------------------------------------------------------------- availability

func _carrying(sim: LifeSim) -> bool:
	var meals: Variant = app.household.meals
	return meals != null and not meals.carried_by(member_id(sim)).is_empty()


func _claimed_by_other(sim: LifeSim, station: Dictionary, active_only: bool = false) -> bool:
	for member: Dictionary in app.household.members:
		if member.sim == sim: continue
		var action: Dictionary = member.sim.get_current_action()
		if action.is_empty(): continue
		if str(action.get("target_id", "")) == str(station.id) and str(action.get("phase", "")) in (["active"] if active_only else ["approach", "active"]): return true
		if not str(station.item_id).is_empty() and str(action.get("chore", {}).get("item", "")) == str(station.item_id) and str(action.get("phase", "")) == "active": return true
	return false


func _station_reason(sim: LifeSim, id: String, station: Dictionary, active_only: bool = false) -> String:
	var stage: String = str(sim.character.age_stage)
	var stage_reason: String = Defs.stage_error(stage, id)
	if not stage_reason.is_empty(): return stage_reason
	if not bool(station.ok): return str(station.refusal) if not str(station.refusal).is_empty() else "There is nowhere to stand to do that."
	if bool(station.outdoor) and not Defs.daylight(float(sim.minutes)): return "Wait for daylight to clean outdoors."
	if float(station.need_top) > 0.0:
		var reach: Dictionary = Defs.reach(stage, sim._actor_is_pregnant(), float(station.need_top), float(station.min_top), str(station.aids))
		if str(reach.aid) == "refused": return "Too high to reach safely." if stage != "child" else "Too small to reach that yet."
	if _claimed_by_other(sim, station, active_only): return "Somebody else is already cleaning this."
	return ""


## Why a chore cannot be done by this Lifelet at this target right now, or "". The
## target is a station or the furnishing the chore is done at.
func action_availability(sim: LifeSim, id: String, target_id: String) -> String:
	if sim.is_away(): return "This Lifelet is away from home."
	if str(app.current_venue) != "home": return "Chores are done at home."
	if _carrying(sim): return "Put down the food you are carrying first."
	if not Defs.is_chore(id): return ""
	var stage_reason: String = Defs.stage_error(str(sim.character.age_stage), id)
	if not stage_reason.is_empty(): return stage_reason
	var station: Dictionary = station_for(id, target_id, _body_position(sim))
	if station.is_empty() or str(station.chore) != id: return "There is nothing here to clean."
	return _station_reason(sim, id, station)


# ------------------------------------------------------------------ actions

func _label_for(id: String, station: Dictionary) -> String:
	var noun: String = str(station.label)
	if id in ["chore_dust", "chore_fluff"] and not str(station.item_id).is_empty():
		var item: Dictionary = app._find_item(str(station.item_id))
		var named: String = str(NOUNS.get(str(item.get("kind", "")), ""))
		if not named.is_empty(): noun = "the %s%s" % [named, " cushions" if id == "chore_fluff" else ""]
	return "%s %s" % [VERBS.get(id, "Clean"), noun]


func _units(id: String, station: Dictionary) -> float:
	match id:
		"chore_dust": return float(station.units)
		"chore_fluff": return float(station.units)
	return 0.0


## One chore action for this Lifelet, ready to queue: its own length, effects and label.
func build_action(sim: LifeSim, id: String, station: Dictionary, record: Dictionary = {}) -> Dictionary:
	var neat: bool = sim._has_trait("Neat")
	var stage: String = str(sim.character.age_stage)
	var minutes: float = Defs.duration(id, _units(id, station), stage, neat)
	var effects: Dictionary = Defs.changes(id, minutes, neat)
	var action: Dictionary = sim.get_action_definition(id)
	action["duration"] = minutes
	action["changes"] = effects
	action["label"] = _label_for(id, station)
	action["description"] = str(Defs.definition(id).get("description", ""))
	action.merge({"target_id": str(station.id), "target_position": station.position, "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false}, true)
	var reach: Dictionary = Defs.reach(stage, sim._actor_is_pregnant(), float(station.need_top), float(station.min_top), str(station.aids)) if float(station.need_top) > 0.0 else {"aid": ""}
	var chore: Dictionary = {"v": 1, "mode": "task", "plan": [], "index": 1, "total": 1, "label": action.label, "changes": effects, "key": str(station.key), "item": str(station.item_id), "face": "", "aid": str(reach.aid) if str(reach.aid) in ["stool", "pole"] else "", "from": 0.0}
	chore.merge(record, true)
	action["chore"] = chore
	return action


func _target_position(sim: LifeSim, target_id: String) -> Vector3:
	for target: Dictionary in sim._targets:
		if str(target.id) == target_id: return target.position
	var item: Dictionary = app._find_item(target_id)
	return app.world.approach(item) if not item.is_empty() else Vector3.INF


## The queued action for one plan entry ("action_id@target_id"), or {} if it no longer applies.
func _entry_action(sim: LifeSim, entry: String, record: Dictionary) -> Dictionary:
	var at: int = entry.find("@")
	var id: String = entry.substr(0, at)
	var target: String = entry.substr(at + 1)
	if Defs.is_chore(id):
		var station: Dictionary = stations.get(target, {})
		if station.is_empty() or str(station.chore) != id or not _station_reason(sim, id, station).is_empty(): return {}
		if _carrying(sim) or (str(record.get("mode", "task")) != "task" and dirt_of(station) < ALREADY_CLEAN): return {}
		return build_action(sim, id, station, record)
	var reason: Dictionary = sim.get_action_availability(id, target)
	if not bool(reason.available): return {}
	# A toy is tidied only while it is still lying about and somebody can still put it away:
	# another cleaner may have boxed it, or the box may have filled, since the round was planned.
	if id == "put_pet_toy":
		var toy: Dictionary = app._find_item(target)
		if toy.is_empty() or not app.toy_flow.is_floor(toy) or not app.toy_flow.tidy_error(sim, target).is_empty(): return {}
	var position: Vector3 = _target_position(sim, target)
	if not position.is_finite(): return {}
	var action: Dictionary = sim.get_action_definition(id)
	action.merge({"target_id": target, "target_position": position, "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false}, true)
	var chore: Dictionary = {"v": 1, "mode": "task", "plan": [], "index": 1, "total": 1, "label": str(action.label), "changes": action.changes.duplicate(true), "key": "", "item": "", "face": "", "aid": "", "from": 0.0}
	chore.merge(record, true)
	action["chore"] = chore
	return action


func _body_position(sim: LifeSim) -> Vector3:
	var body: Node3D = app.world.actors.get(member_id(sim))
	return body.position if is_instance_valid(body) else Vector3.INF


func _reachable(sim: LifeSim, position: Vector3) -> bool:
	var body: Node3D = app.world.actors.get(member_id(sim))
	if not is_instance_valid(body) or not position.is_finite(): return false
	var from: Vector3 = body.position
	if app.world.point_level(from) < 0: return true
	# The panel asks about every station for several presets at once: remember each answer
	# for as long as the walkable ground and the places asked about stay as they are.
	var generation: int = app.world.lot_navigation.generation
	if generation != _reach_generation:
		_reach_memo.clear()
		_reach_generation = generation
	var key: String = "%d,%d>%d,%d,%d" % [roundi(from.x * 4.0), roundi(from.z * 4.0), roundi(position.x * 4.0), roundi(position.z * 4.0), roundi(position.y * 4.0)]
	if not _reach_memo.has(key): _reach_memo[key] = not app.world.path_to(from, position).is_empty()
	return bool(_reach_memo[key])


## The chain's next task after `action`: the first listed entry that still applies and
## is free, else the first that applies. {} when none is left.
func _successor(sim: LifeSim, action: Dictionary) -> Dictionary:
	var record: Dictionary = action.get("chore", {})
	var plan: Array = record.get("plan", [])
	var fallback: int = -1
	var fallback_action: Dictionary = {}
	for index: int in plan.size():
		var carried: Dictionary = {"mode": str(record.mode), "from": float(record.get("from", 0.0)), "total": int(record.total), "index": int(record.index) + 1}
		var built: Dictionary = _entry_action(sim, str(plan[index]), carried)
		if built.is_empty() or not _reachable(sim, built.target_position): continue
		if app._activity_available_for_member(built, member_id(sim)): return _with_plan(built, plan, index)
		if fallback < 0:
			fallback = index; fallback_action = built
	if fallback >= 0: return _with_plan(fallback_action, plan, fallback)
	return {}


func _with_plan(built: Dictionary, plan: Array, chosen: int) -> Dictionary:
	var rest: Array = plan.duplicate()
	rest.remove_at(chosen)
	built.chore["plan"] = rest
	built["autonomous"] = false
	return built


## Why a round should stop between two tasks, or "": somebody else's order waits behind it,
## or the Lifelet is running short of what keeps them well.
func stop_reason(sim: LifeSim, next: Dictionary) -> String:
	for later: Dictionary in sim.action_queue:
		if not bool(later.get("autonomous", false)): return "%s has other things to do." % first_name(sim)
	for need: String in ["hunger", "energy", "bladder"]:
		if float(sim.needs[need]) < 20.0: return "%s stopped cleaning to take care of themselves." % first_name(sim)
	# A round the player asked for is theirs to weigh against school or work, as any queued
	# activity is; only a Lifelet's own need ends it.
	return ""


# ---------------------------------------------------------------- the round

## Every task a round would hold for this Lifelet: {"entries", "minutes", "count",
## "refused" (reason -> count), "night" (outdoor tasks waiting for daylight)}. `mode`
## is quick, full, inside, outside or custom; `categories` limits a custom round.
func make_plan(sim: LifeSim, mode: String, categories: Array = []) -> Dictionary:
	var result: Dictionary = {"entries": [], "minutes": 0.0, "count": 0, "refused": {}, "night": 0, "urgent": 0}
	if not is_instance_valid(app.world) or str(app.current_venue) != "home": return result
	var person: String = member_id(sim)
	var threshold: float = float(THRESHOLDS.get(mode, 20.0))
	var stamp: float = now()
	var dark: bool = not Defs.daylight(float(sim.minutes))
	var entries: Array = []
	var selected: Callable = func(category: String) -> bool: return categories.is_empty() or category in categories
	var body: Node3D = app.world.actors.get(person)
	var origin: Vector3 = body.position if is_instance_valid(body) else Vector3.ZERO
	# Spills, dishes, bins and strays are always first and always welcome.
	if mode != "outside" and selected.call(URGENT):
		for entry: Dictionary in _urgent(sim):
			entries.append(entry)
	# Toys lying about come next: each is a real tidy (walk, bend, lift, carry, set in the box).
	if mode != "outside" and selected.call("toys"):
		for entry: Dictionary in _toy_entries(sim, origin):
			entries.append(entry)
	var found: Array = []
	for station: Dictionary in list:
		var id: String = str(station.chore)
		if not selected.call(str(station.category)): continue
		if mode == "inside" and bool(station.outdoor): continue
		if mode == "outside" and not bool(station.outdoor): continue
		var amount: float = dirt_of(station)
		if amount < threshold: continue
		var reason: String = _station_reason(sim, id, station)
		if reason.begins_with("Wait for daylight"):
			result.night = int(result.night) + 1; continue
		if reason.is_empty() and _claimed(person, str(station.id), str(station.item_id)): reason = "Somebody else is already cleaning this."
		if not reason.is_empty():
			if reason != "Somebody else is already cleaning this." and str(station.category) != "floors": result.refused[reason] = int(result.refused.get(reason, 0)) + 1
			continue
		if not _reachable(sim, station.position): continue
		var neat: bool = sim._has_trait("Neat")
		var minutes: float = Defs.duration(id, _units(id, station), str(sim.character.age_stage), neat)
		found.append({"id": id, "target": str(station.id), "minutes": minutes, "dirt": amount, "category": station.category, "position": station.position, "label": _label_for(id, station), "outdoor": station.outdoor})
	if mode == "quick":
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dirt) > float(b.dirt))
		var spent: float = 0.0
		var kept: Array = []
		for entry: Dictionary in found:
			# Every task is the work and a walk to it: a typical walk is counted for the cap.
			var cost: float = float(entry.minutes) + AVERAGE_WALK_MINUTES
			if spent + cost > QUICK_CAP_MINUTES and not kept.is_empty(): continue
			spent += cost; kept.append(entry)
		found = kept
	entries.append_array(_ordered(found, origin))
	var minutes_total: float = 0.0
	var walking_from: Vector3 = origin
	for entry: Dictionary in entries:
		minutes_total += float(entry.minutes)
		# The walk to each task counts too, so the time shown is the time it takes.
		if Vector3(entry.position).is_finite():
			minutes_total += walking_from.distance_to(Vector3(entry.position)) * WALK_MINUTES_PER_METRE
			walking_from = Vector3(entry.position)
	result.entries = entries
	result.minutes = minutes_total
	result.count = entries.size()
	return result


## Whether another member is at this station or on their way to it. Plans hold no claims:
## each cleaner picks the first task nobody has reached and nobody has already done.
func _claimed(person: String, station_id: String, item_id: String) -> bool:
	for member: Dictionary in app.household.members:
		if str(member.id) == person: continue
		var action: Dictionary = member.sim.get_current_action()
		if str(action.get("target_id", "")) == station_id and str(action.get("phase", "")) in ["approach", "active"]: return true
	return false


## Spills, dishes, a full bin or tray and strays: the existing chores a round takes first.
func _urgent(sim: LifeSim) -> Array:
	var out: Array = []
	var puddles: Array = []
	for item: Dictionary in app.world.items:
		var kind: String = str(item.get("kind", ""))
		var id: String = str(item.get("id", ""))
		if kind == "puddle" and bool(sim.get_action_availability("mop_puddle", id).available): puddles.append(item)
		elif kind == "rubbish_bin" and bool(sim.get_action_availability("empty_bin", id).available): out.append({"id": "empty_bin", "target": id, "minutes": 8.0, "dirt": 100.0, "category": URGENT, "label": "Empty the bin", "outdoor": false, "position": app.world.approach(item)})
		elif kind == "litter_tray" and app.household_flow.litter_full(id) and bool(sim.get_action_availability("clean_litter_tray", id).available): out.append({"id": "clean_litter_tray", "target": id, "minutes": 12.0, "dirt": 100.0, "category": URGENT, "label": "Clean the litter tray", "outdoor": false, "position": app.world.approach(item)})
		elif kind in ["dining", "counter", "coffee_table", "table"] and app.household_flow.table_has_dirty(id) and bool(sim.get_action_availability("clear_table", id).available): out.append({"id": "clear_table", "target": id, "minutes": 10.0, "dirt": 100.0, "category": URGENT, "label": "Clear the table", "outdoor": false, "position": app.world.approach(item)})
	var ordered: Array = []
	for item: Dictionary in puddles:
		ordered.append({"id": "mop_puddle", "target": str(item.id), "minutes": 8.0, "dirt": 100.0, "category": URGENT, "label": "Mop up the accident", "outdoor": false, "position": app.world.approach(item)})
	ordered.append_array(out)
	return ordered


## One tidy for every toy lying on the floor that this Lifelet could put away, the nearest
## first. The tidy itself is `LifeToyFlow`'s: the Lifelet walks to the toy, bends down,
## lifts it, carries it to a box that takes it and sets it in.
func _toy_entries(sim: LifeSim, origin: Vector3) -> Array:
	var found: Array = []
	for toy: Dictionary in app.toy_flow.loose_toys():
		var id: String = str(toy.id)
		if not app.toy_flow.tidy_error(sim, id).is_empty(): continue
		var at: Vector3 = app.world.approach(toy)
		if not at.is_finite() or not _reachable(sim, at): continue
		found.append({"id": "put_pet_toy", "target": id, "minutes": 1.0, "dirt": 100.0, "category": "toys", "label": "Put the toy away", "outdoor": false, "position": at})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector3(a.position).distance_squared_to(origin) < Vector3(b.position).distance_squared_to(origin))
	# No more tidies than the boxes have room for: the rest would only fail one by one. Each
	# toy goes to the nearest box that still has room once the ones before it are counted.
	var spent: Dictionary = {}
	var kept: Array = []
	for entry: Dictionary in found:
		var toy: Dictionary = app._find_item(str(entry.target))
		var box: Dictionary = app.toy_flow.container_for(toy, Vector3.INF, spent)
		if box.is_empty(): continue
		spent[str(box.id)] = int(spent.get(str(box.id), 0)) + 1
		kept.append(entry)
	return kept


## Tasks in the order a person would do them: tidy, soft furnishings, dust, curtains,
## windows, floors (vacuum then mop), the kitchen sink, the bathroom, then outside; the
## ones in each stage by the shortest walk.
func _stage_of(entry: Dictionary) -> int:
	var id: String = str(entry.id)
	if bool(entry.outdoor): return 90 if id == "chore_sweep_entry" else (91 if id == "chore_wipe_door" else 92)
	match id:
		"chore_fluff": return 20
		"chore_dust": return 30
		"chore_vacuum_curtains": return 40
		"chore_wash_window": return 50
		"chore_vacuum": return 60
		"chore_mop": return 85 if _bathroom_entry(entry) else 70
		"chore_wipe_sink": return 82 if str(entry.category) == "bathroom" else 80
		"chore_scrub_toilet": return 84
	return 99


func _ordered(found: Array, origin: Vector3) -> Array:
	var out: Array = []
	var at: Vector3 = origin
	var stages: Array = []
	for entry: Dictionary in found:
		if not stages.has(_stage_of(entry)): stages.append(_stage_of(entry))
	stages.sort()
	for stage: int in stages:
		var group: Array = found.filter(func(entry: Dictionary) -> bool: return _stage_of(entry) == stage)
		while not group.is_empty():
			var best: int = 0
			for index: int in group.size():
				if Vector3(group[index].position).distance_to(at) < Vector3(group[best].position).distance_to(at): best = index
			at = group[best].position
			out.append(group[best]); group.remove_at(best)
	return out


func _bathroom_entry(entry: Dictionary) -> bool:
	var station: Dictionary = stations.get(str(entry.target), {})
	return bool(station.get("wet", false))


## Start a round for this Lifelet. {"ok", "error", "count", "minutes"}.
func start(person: String, mode: String, categories: Array = []) -> Dictionary:
	var sim: LifeSim = app.household.member_sim(person)
	if sim == null: return {"ok": false, "error": "That Lifelet is not part of this household."}
	var reason: String = start_error(sim)
	if not reason.is_empty(): return {"ok": false, "error": reason}
	var plan: Dictionary = make_plan(sim, mode, categories)
	if int(plan.count) == 0:
		var why: String = "Nothing needs cleaning right now."
		if int(plan.night) > 0: why = "Outdoor chores wait for daylight; nothing indoors needs cleaning."
		for text: Variant in plan.refused: why = str(text); break
		return {"ok": false, "error": why}
	# A Lifelet busy with something they chose themselves hands it over; one with
	# the player's own plans is left alone.
	for action: Dictionary in sim.action_queue:
		if not bool(action.get("autonomous", false)): return {"ok": false, "error": "Finish or cancel %s's current activity first." % first_name(sim)}
	while not sim.action_queue.is_empty(): sim.cancel_action()
	var entries: Array = plan.entries
	var names: Array = []
	for entry: Dictionary in entries: names.append("%s@%s" % [entry.id, entry.target])
	var capped: Array = names.slice(0, Defs.MAX_PLAN + 1)
	var first_entry: String = capped[0]
	capped.remove_at(0)
	var record: Dictionary = {"mode": mode if mode in ["quick", "full", "inside", "outside"] else "custom", "plan": capped, "index": 1, "total": capped.size() + 1, "from": snappedf(home_score(), .1)}
	var first: Dictionary = _entry_action(sim, first_entry, record)
	if first.is_empty(): return {"ok": false, "error": "The first task is no longer possible."}
	first.chore["plan"] = capped
	first.chore["total"] = capped.size() + 1
	if not sim.enqueue_prepared(first): return {"ok": false, "error": "Could not start cleaning."}
	return {"ok": true, "error": "", "count": capped.size() + 1, "minutes": float(plan.minutes)}


## Why this Lifelet cannot be sent to clean at all, or "".
func start_error(sim: LifeSim) -> String:
	if sim.is_away(): return "%s is away from home." % first_name(sim)
	if str(app.current_venue) != "home": return "Chores are done at home."
	if str(sim.character.age_stage) == "baby": return "A baby cannot do that yet."
	if sim.is_spirit(): return "A spirit has finished that chapter of life."
	if _carrying(sim): return "Put down the food you are carrying first."
	return ""


## What each tile of the Clean Home panel would do for this Lifelet.
func preview(sim: LifeSim, mode: String, categories: Array = []) -> Dictionary:
	var plan: Dictionary = make_plan(sim, mode, categories)
	return {"count": int(plan.count), "minutes": float(plan.minutes), "refused": plan.refused, "night": plan.night}


# ------------------------------------------------------------ service hooks

## `LifeSim.queue_action` for a chore: bind it to its station and queue it.
func request(sim: LifeSim, id: String, target_id: String, _position: Vector3) -> bool:
	var reason: String = action_availability(sim, id, target_id)
	if not reason.is_empty():
		sim._emit_notice(reason)
		return false
	var station: Dictionary = station_for(id, target_id, _body_position(sim))
	if station.is_empty(): return false
	return sim.enqueue_prepared(build_action(sim, id, station))


## Called as an approach ends and before the work begins. False means this chore was
## replaced or dropped and nothing should begin.
func before_begin(sim: LifeSim, action: Dictionary) -> bool:
	if not action.has("chore"): return true
	var id: String = str(action.id)
	var problem: String = ""
	if Defs.is_chore(id):
		var station: Dictionary = stations.get(str(action.target_id), {})
		problem = "That is no longer there to clean." if station.is_empty() or str(station.chore) != id else _station_reason(sim, id, station, true)
		if problem.is_empty() and str(action.chore.get("mode", "task")) != "task" and dirt_of(station) < ALREADY_CLEAN: problem = "That has already been cleaned."
	elif id in Defs.EXISTING:
		var availability: Dictionary = sim.get_action_availability(id, str(action.target_id))
		if not bool(availability.available): problem = str(availability.reason)
	if problem.is_empty(): return true
	sim._emit_notice(problem)
	var next: Dictionary = _successor(sim, action)
	if not next.is_empty(): sim.action_queue.insert(1, next)
	sim.cancel_action()
	return false


## A task has just finished: clean its zone and soil what the activity soiled. The
## round then moves on, unless somebody needs the Lifelet for something else.
func finished(sim: LifeSim, action: Dictionary) -> void:
	_soil(sim, action)
	if not action.has("chore"): return
	var id: String = str(action.id)
	var record: Dictionary = action.chore
	if Defs.is_chore(id):
		var station: Dictionary = stations.get(str(action.target_id), {})
		if not station.is_empty():
			clean_station(sim, station)
			if id == "chore_wash_window": vis().sparkle(self, station.aim, station.n, station.u)
	var next: Dictionary = _successor(sim, action)
	if next.is_empty():
		_round_over(sim, action, "")
		return
	var reason: String = stop_reason(sim, next)
	if not reason.is_empty():
		_round_over(sim, action, reason)
		return
	sim.push_chain_action(next)


func clean_station(_sim: LifeSim, station: Dictionary) -> void:
	chores().clean(str(station.key), str(station.dirt), now())


## Tell the player how the round went and leave the Lifelet a little pleased with it.
func _round_over(sim: LifeSim, action: Dictionary, reason: String) -> void:
	var record: Dictionary = action.chore
	var rounds: bool = str(record.get("mode", "task")) != "task" and int(record.get("total", 1)) > 1
	var score: float = home_score()
	if not reason.is_empty():
		sim._emit_notice(reason)
	elif rounds:
		var delta: int = int(round(score - float(record.get("from", score))))
		sim._emit_notice("%s finished cleaning. The home is %d%% clean%s." % [first_name(sim), int(round(score)), " (+%d%%)" % delta if delta > 0 else ""])
		sim.add_moodlet("A tidy home", "Happy", "Every room has had attention, and it feels lighter in here.", 240, 2)
	elif Defs.is_chore(str(action.id)) and str(record.get("mode", "task")) == "task":
		sim.add_moodlet("Tidied up", "Happy", "A little cleaning goes a long way.", 120, 1)


## A round whose last task could not be done (a toy with nowhere to go) still ends the
## way a round does, with its notice and its mood.
func ended_early(sim: LifeSim, action: Dictionary) -> void:
	if action.has("chore"): _round_over(sim, action, "")


## What an activity leaves behind it. Called for every finished action.
func _soil(sim: LifeSim, action: Dictionary) -> void:
	if not is_instance_valid(app.world) or str(app.current_venue) != "home" or list.is_empty(): return
	var id: String = str(action.get("id", ""))
	var target: String = str(action.get("target_id", ""))
	var book: Chores = chores()
	var item: Dictionary = app._find_item(target)
	match id:
		"toilet":
			book.soil("toilet:" + Sites._slug(target), 180.0)
			for station: Dictionary in list:
				if str(station.dirt) == "sink" and str(station.category) == "bathroom": book.soil(str(station.key), 60.0)
		"wash_hands", "brush_teeth":
			book.soil("sink:" + Sites._slug(target), 40.0)
		"cook", "snack":
			var origin: Vector3 = item.node.global_position if not item.is_empty() and is_instance_valid(item.get("node")) else Vector3.INF
			for station: Dictionary in list:
				if str(station.dirt) == "sink" and str(station.category) == "kitchen": book.soil(str(station.key), 120.0 if id == "cook" else 40.0)
				elif origin.is_finite() and str(station.dirt) in ["fvac", "fmop"] and Vector3(station.aim).distance_to(origin) < 2.5: book.soil(str(station.key), 90.0 if id == "cook" else 20.0)
		"shower", "bath":
			for station: Dictionary in list:
				if bool(station.wet) and str(station.dirt) == "wmop": book.soil(str(station.key), 45.0)
		"arrive_home", "career_day", "school_day", "visit", "morning_run", "jog":
			for station: Dictionary in list:
				if str(station.dirt) == "entry": book.soil(str(station.key), 120.0)
				elif str(station.dirt) in ["fvac", "fmop"] and _near_door(station, 2.5): book.soil(str(station.key), 60.0)
		"deep_clean":
			for station: Dictionary in list:
				if str(station.dirt) in ["sink", "dust"] and station.item_id == target: book.clean(str(station.key), str(station.dirt), now())


func _near_door(station: Dictionary, within: float) -> bool:
	for other: Dictionary in list:
		if str(other.dirt) == "entry" and Vector3(other.position).distance_to(station.aim) < within + 2.0 and Vector3(station.aim).distance_to(other.position) < within + 2.0: return true
	return false


## A queued chore was cancelled by the world rather than by the player: the round goes on.
func successor_behind(sim: LifeSim, index: int) -> void:
	if index < 0 or index >= sim.action_queue.size(): return
	var action: Dictionary = sim.action_queue[index]
	if not action.has("chore"): return
	var next: Dictionary = _successor(sim, action)
	if not next.is_empty(): sim.action_queue.insert(index + 1, next)


func canceled(_sim: LifeSim, _action: Dictionary) -> void:
	pass


## The extra furnishing a chore holds, so a sitter on a sofa blocks fluffing it.
func extra_resources(action: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var record: Variant = action.get("chore", null)
	if record is Dictionary and not str(record.get("item", "")).is_empty() and Defs.is_chore(str(action.get("id", ""))): out.append(str(record.item))
	return out


## The HUD's account of where the round stands, or "".
func status_text(action: Dictionary) -> String:
	var record: Variant = action.get("chore", null)
	if not record is Dictionary or str(record.get("mode", "task")) == "task" or int(record.get("total", 1)) <= 1: return ""
	return "CLEANING HOME — %d OF %d" % [int(record.index), int(record.total)]


## A spoken line for a finished task is kept for the end of the round.
func silent(action: Dictionary) -> bool:
	var record: Variant = action.get("chore", null)
	return record is Dictionary and str(record.get("mode", "task")) != "task" and not (record.get("plan", []) as Array).is_empty()


# ------------------------------------------------------------------- acting

## The activity anchor for the chore this member is doing: where the feet go, which way
## to face and the facts the pose needs about the work (chore_motion.gd). {} when the
## action has no station.
func anchor(person: String, action: Dictionary) -> Dictionary:
	var id: String = str(action.get("id", ""))
	var station: Dictionary = stations.get(str(action.get("target_id", "")), {})
	if station.is_empty() or str(station.chore) != id: return {}
	var sim: LifeSim = app.household.member_sim(person)
	var stage: String = str(sim.character.age_stage) if sim != null else "adult"
	var pregnant: bool = sim != null and sim._actor_is_pregnant()
	return anchor_for(stage, pregnant, id, station, float(action.get("progress", 0.0)), float(action.get("elapsed", 0.0)))


## The same anchor for a given body and progress, with no action needed.
func anchor_for(stage: String, pregnant: bool, id: String, station: Dictionary, progress: float, elapsed: float = 0.0) -> Dictionary:
	var details: Dictionary = {"position": station.anchor, "yaw": float(station.yaw), "kind": "standing", "chore_stand": station.anchor, "chore_aim": station.aim,
		"chore_u": station.u, "chore_n": station.n, "chore_half": station.half, "chore_y": Vector2(float(station.y_lo), float(station.y_hi)),
		"chore_top": float(station.y_hi), "chore_aid": "", "chore_progress": progress,
		"chore_mode": str(station.get("dust_mode", "")), "chore_item": str(station.item_id)}
	if float(station.need_top) > 0.0:
		var reach: Dictionary = Defs.reach(stage, pregnant, float(station.need_top), float(station.min_top), str(station.aids))
		details["chore_top"] = minf(float(reach.top), float(station.y_hi))
		details["chore_aid"] = str(reach.aid) if str(reach.aid) in ["stool", "pole"] else ""
	var item: Dictionary = app._find_item(str(station.item_id)) if not str(station.item_id).is_empty() else {}
	if id == "chore_fluff" and not item.is_empty(): details["chore_nodes"] = cushions_of(item.node, station)
	elif id == "chore_vacuum_curtains" and not item.is_empty():
		var tint: Node = item.node.find_child("Tint", true, false)
		if tint != null: details["chore_nodes"] = [tint]
	elif id == "chore_mop":
		var wobble: float = elapsed * 1.7
		details["mop_contact"] = Vector3(station.aim) + Vector3(station.u) * (.26 * sin(wobble)) + Vector3(station.n) * (-.05 * cos(wobble * .5))
	return details


## After a load, paint a chore in progress at zero time so a paused game shows the Lifelet
## mid-task, tool in hand, rather than standing at rest until the clock runs.
func reconstruct_actors() -> void:
	for member: Dictionary in app.household.members:
		var action: Dictionary = member.sim.get_current_action()
		if not Defs.is_chore(str(action.get("id", ""))) or not bool(action.get("paid", false)) or float(action.get("elapsed", 0.0)) <= 0.0: continue
		var actor: LifeActor = app.world.actors.get(str(member.id))
		var details: Dictionary = anchor(str(member.id), action)
		# A task under way is saved paid and part-done; it resumes where its Lifelet stands.
		if not is_instance_valid(actor) or details.is_empty() or actor.position.distance_to(Vector3(action.target_position)) > .15: continue
		actor.set_activity_anchor(details.position, details.yaw, "standing", str(action.id), details)
		actor.reconstruct_sanitation_pose(str(action.id))


## The cushions of one seat position (a column of a sofa), back cushions first, then
## the seat, then the scatter.
func cushions_of(node: Node3D, station: Dictionary = {}) -> Array:
	var found: Array = node.find_children("*ushion*", "Node3D", true, false)
	if station.has("column"):
		var kind: String = str(app._find_item(str(station.item_id)).get("kind", ""))
		var offsets: Array = LifeCatalog.get_item(kind).get("seat_offsets", [0.0])
		found = found.filter(func(entry: Node) -> bool:
			var local_x: float = node.to_local((entry as Node3D).global_position).x
			var nearest: float = float(offsets[0])
			for offset: Variant in offsets:
				if absf(local_x - float(offset)) < absf(local_x - nearest): nearest = float(offset)
			return is_equal_approx(nearest, float(station.column)))
	var ordered: Array = []
	for word: String in ["Back", "Seat"]:
		for entry: Node in found:
			if str(entry.name).begins_with(word): ordered.append(entry)
	for entry: Node in found:
		if not ordered.has(entry): ordered.append(entry)
	return ordered


# ----------------------------------------------------------------- autonomy

## One chore a Lifelet might do unprompted, or {}. Conservative: daytime, comfortable,
## after their own needs, duties and a long cooldown, and nobody else cleaning already.
func autonomous_choice(sim: LifeSim, excluded: Array = []) -> Dictionary:
	if not is_instance_valid(app) or str(app.current_venue) != "home" or app.mode != "live" or list.is_empty(): return {}
	var person: String = member_id(sim)
	if person.is_empty() or sim.is_away() or not sim.action_queue.is_empty(): return {}
	var stage: String = str(sim.character.age_stage)
	if stage == "baby" or sim.is_spirit() or _carrying(sim): return {}
	var minutes_of_day: float = float(sim.minutes)
	if minutes_of_day < Defs.AUTO_START or minutes_of_day > Defs.AUTO_END: return {}
	for need: String in Defs.NEED_NAMES:
		if float(sim.needs[need]) < 55.0: return {}
	if float(sim.needs.energy) < 50.0 or float(sim.needs.hunger) < 45.0: return {}
	var stamp: float = now()
	if stamp < float(chores().auto_next.get(person, 0.0)): return {}
	for member: Dictionary in app.household.members:
		if member.sim == sim: continue
		var other: Dictionary = member.sim.get_current_action()
		if bool(other.get("autonomous", false)) and other.has("chore"): return {}
		if Defs.is_chore(str(other.get("id", ""))) and bool(other.get("autonomous", false)): return {}
	var neat: bool = sim._has_trait("Neat")
	if home_score() >= (75.0 if neat else 55.0): return {}
	var body: Node3D = app.world.actors.get(person)
	var scored: Array = []
	for station: Dictionary in list:
		var id: String = str(station.chore)
		var amount: float = dirt_of(station)
		if amount < Defs.NEEDS_CLEANING or str(station.id) in excluded: continue
		if stage == "child": continue
		if bool(station.outdoor) and not (minutes_of_day >= 7.0 * 60.0 and minutes_of_day <= 17.5 * 60.0): continue
		if not _station_reason(sim, id, station).is_empty() or _claimed(person, str(station.id), str(station.item_id)): continue
		var walk: float = Vector3(station.position).distance_to(body.position) if is_instance_valid(body) else 0.0
		scored.append({"station": station, "score": amount - .4 * walk})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	# The best-scored place may be walled off: the next few are tried before giving up, so one
	# unreachable corner cannot stop a Lifelet cleaning anywhere.
	for index: int in mini(scored.size(), 8):
		var best: Dictionary = scored[index].station
		if not _reachable(sim, best.position): continue
		chores().auto_next[person] = stamp + AUTO_COOLDOWN
		return {"id": str(best.chore), "target_id": str(best.id), "position": best.position, "load": 0.0}
	return {}


# -------------------------------------------------------------------- world

## Called every frame by the controller; does its slower work about once a game hour.
func sync_world(delta: float = 0.0) -> void:
	if not is_instance_valid(app) or not is_instance_valid(app.world) or app.mode != "live": return
	rebuild_stations()
	if list.is_empty(): return
	vis().frame(self, delta)
	var hour: int = int(now() / 60.0)
	if hour == _hour_synced: return
	_hour_synced = hour
	vis().sync(self)
	if app.household.speed > 0 and home_score() < 40.0 and int(app.household.day) != _grubby_day:
		_grubby_day = int(app.household.day)
		for member: Dictionary in app.household.members:
			if not member.sim.is_away() and str(member.sim.character.age_stage) != "baby": member.sim.add_moodlet("A grubby home", "Tense", "Dust and dirt are winning, and it is hard to relax.", 240, 1)
