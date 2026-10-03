extends Node
class_name LifeBirthdayFlow
## Gathering round the cake, as the player sees it.
##
## Every automatic birthday leaves a cake owed to the birthday person (the
## household keeps that note). This service starts the gathering when the home is
## calm: it picks a table (or a cake held in two hands), finds a clear spot round
## it for everyone who is free, and asks the household to send them there. While
## the family sings it shows the cake and its candles, gives everyone their pose
## and their bubbles, slows the game to Normal speed and plays the birthday tune
## through the party music owner. When the candles are out it sets a real layer
## cake out on the table for the household to share.
##
## Everything that has to survive a save lives in the household (the owed birthday
## and the gathering). This service keeps only what is on the screen, so after a
## load it simply finds the gathering again and rebuilds the cake and the tune.

const CAKE_MODEL: String = "res://assets/models/birthday_cake.glb"
## The authored cake is a hand-held 29 cm plate; on a table it is a little larger.
const CAKE_SCALE: float = 1.5
## A table's own top is a hair under a cloth, so a cake sits just above it.
const CLOTH_LIFT: float = .004
const START_EVERY: float = .25
## Tables that can hold the cake, best first.
const TABLE_KINDS: Array[String] = ["dining", "coffee_table", "counter", "corner_counter"]
## A resumed song is put back within this many seconds of where it should be.
const TUNE_DRIFT: float = 1.5

var app: Node
## The load this service has seen, so a new load forgets what was on the screen.
var epoch: int = 0
## The cake on the table for each gathering (session id to node).
var props: Dictionary = {}
## What the player was last told about gatherings, oldest first.
var notices: Array[String] = []
var _connected: Node = null
var _presented: Dictionary = {}
var _tune_key: String = ""
var _fired: Dictionary = {}
var _cues: Dictionary = {}
var _slowed: Dictionary = {}
## The speed the player had chosen before a song slowed the game, or 0.
var _resume_speed: int = 0
## Real-time seconds before a birthday that could not be laid out is tried again.
var _backoff: Dictionary = {}
var _retry: float = 0.0


func _init(owner: Node = null) -> void:
	app = owner
	if is_instance_valid(owner): epoch = int(owner.load_epoch)


## Called every frame by the controller.
func tick(delta: float) -> void:
	if not is_instance_valid(app) or not is_instance_valid(app.household): return
	_follow_household()
	_sync_epoch()
	if str(app.mode) == "creator":
		clear()
		return
	if str(app.mode) not in ["live", "build"] or bool(app.loading_game): return
	_present()
	_retry -= delta
	if _retry <= 0.0:
		_retry = START_EVERY
		try_start()

## Throw away everything on the screen: the cakes, the poses, the tune.
func clear() -> void:
	for id: Variant in props.keys():
		if is_instance_valid(props[id]): props[id].queue_free()
	props.clear()
	_release_actors({})
	if is_instance_valid(app) and is_instance_valid(app.party_music) and not _tune_key.is_empty(): app.party_music.stop_birthday_tune()
	_tune_key = ""
	_fired.clear()
	_cues.clear()
	_slowed.clear()
	_backoff.clear()
	_resume_speed = 0


## Start the oldest waiting birthday that can be held now. Returns whether a
## gathering began.
func try_start() -> bool:
	var household: LifeHousehold = app.household
	if household.pending_birthdays().is_empty() or not _can_start(): return false
	var now: float = float(household.day - 1) * 1440.0 + household.minutes
	for entry: Dictionary in household.pending_birthdays():
		var id: String = str(entry.member_id)
		if float(entry.get("hold_until", 0.0)) > now or not household.birthday_session_for(id).is_empty(): continue
		if float(_backoff.get(id, 0.0)) > Time.get_ticks_msec() / 1000.0: continue
		var plan: Dictionary = household.birthday_plan(id)
		if bool(plan.ok) and _start(id, plan): return true
	return false

## Whether the home is calm enough for a gathering: in the live house with the
## clock running, no menu open, and not away on a trip.
func _can_start() -> bool:
	if str(app.mode) != "live" or bool(app.loading_game) or str(app.current_venue) != "home": return false
	var household: LifeHousehold = app.household
	if household.restoring or int(household.speed) <= 0: return false
	if bool(app.overlay_open) and bool(app.overlay_pauses_sim): return false
	return is_instance_valid(app.world) and is_instance_valid(app.world.house)

func _start(celebrant_id: String, plan: Dictionary) -> bool:
	var household: LifeHousehold = app.household
	var world: LifeWorld = app.world
	var ids: Array = []
	var bodies: Dictionary = {}
	for member_id: Variant in plan.members:
		var body: Variant = world.actors.get(str(member_id))
		var here: bool = is_instance_valid(body) and (body as Node3D).visible and world.point_level((body as Node3D).position) >= 0
		if here:
			ids.append(str(member_id))
			bodies[str(member_id)] = body
		elif str(member_id) == celebrant_id:
			return false
	var layout: Dictionary = _table_layout(ids, bodies)
	if layout.is_empty() or layout.ids.size() < ids.size():
		# A cake in two hands makes room for everyone when the table cannot.
		var held: Dictionary = _held_layout(ids, bodies)
		if layout.is_empty() or (not held.is_empty() and held.ids.size() > layout.ids.size()): layout = held
	if layout.is_empty():
		# No cake can be set anywhere yet; look again in a few seconds, not every frame.
		_backoff[celebrant_id] = Time.get_ticks_msec() / 1000.0 + 3.0
		return false
	var result: Dictionary = household.queue_birthday_gathering(celebrant_id, layout.ids, layout.positions, str(layout.table_id), layout.cake)
	if not bool(result.ok):
		household._hold_birthday(celebrant_id)
		return false
	# One notice says it all: who is gathering, and who will miss the song.
	var first: String = str(household.member_sim(celebrant_id).character.name).split(" ")[0]
	var message: String = "Everyone gathers round the cake for %s!" % first
	for member: Dictionary in plan.skipped:
		message += " %s is busy and will miss the song." % str(member.name).split(" ")[0]
	for member_id: String in ids:
		if not layout.ids.has(member_id) and member_id != celebrant_id:
			message += " There is no room for %s round the cake." % str(household.member_sim(member_id).character.name).split(" ")[0]
	_tell(message)
	return true

## Tell the player, and keep what was said so a test can read every line.
func _tell(message: String) -> void:
	notices.append(message)
	while notices.size() > 12: notices.pop_front()
	app.show_notice(message)


## ---- Where the cake goes and who stands where

## The cake on the best table: its own spot on the top, and a clear, reachable spot
## round it for the birthday person and as many of the others as will fit. {} when
## there is no table the birthday person can walk to.
func _table_layout(ids: Array, bodies: Dictionary) -> Dictionary:
	var world: LifeWorld = app.world
	var celebrant_id: String = str(ids[0])
	var celebrant_body: Node3D = bodies[celebrant_id]
	var hosts: Array = []
	for host: Dictionary in world.items:
		if str(host.kind) in TABLE_KINDS and LifeMeals.SURFACE_HALF_SIZE.has(str(host.kind)) and is_instance_valid(host.get("node")): hosts.append(host)
	hosts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a: int = TABLE_KINDS.find(str(a.kind)) - (10 if not world.item_cloth(a).is_empty() else 0)
		var rank_b: int = TABLE_KINDS.find(str(b.kind)) - (10 if not world.item_cloth(b).is_empty() else 0)
		if rank_a != rank_b: return rank_a < rank_b
		return _away(a, celebrant_body) < _away(b, celebrant_body))
	var best: Dictionary = {}
	for host: Dictionary in hosts.slice(0, 6):
		var slot: Vector3 = app.meal_flow._surface_slot(host, LifeMeals.PLATTER_HALF_SIZE)
		if not slot.is_finite(): continue
		var layout: Dictionary = _spots_round(host, ids, bodies)
		if layout.is_empty(): continue
		layout["table_id"] = str(host.id)
		slot.y += CLOTH_LIFT if not world.item_cloth(host).is_empty() else 0.0
		layout["cake"] = (host.node as Node3D).to_global(slot)
		layout["slot"] = slot
		if layout.ids.size() == ids.size(): return layout
		if best.is_empty() or layout.ids.size() > best.ids.size(): best = layout
	return best

## How far a table is from the birthday person, counting another storey as far.
func _away(host: Dictionary, body: Node3D) -> float:
	var level_gap: float = absf(float(app.world.item_level(host) - app.world.point_level(body.position)))
	return (host.node as Node3D).global_position.distance_to(body.position) + level_gap * 20.0

## The clear standing spots round one table, and who stands on each.
func _spots_round(host: Dictionary, ids: Array, bodies: Dictionary) -> Dictionary:
	var world: LifeWorld = app.world
	var node: Node3D = host.node
	var half: Vector2 = LifeMeals.SURFACE_HALF_SIZE[str(host.kind)]
	var level: int = world.item_level(host)
	var slots: Array[Vector3] = LifeBirthdayRitual.ring_slots(half)
	var centre: Vector3 = node.global_position
	var found: Array = []
	for index: int in slots.size():
		var at: Vector3 = world.nearest_clear_point(node.to_global(slots[index]), level)
		if not at.is_finite() or Vector2(at.x - centre.x, at.z - centre.z).length() > LifeBirthdayRitual.MAX_SPOT_DISTANCE: continue
		if not world._clear_coaching_space(at): continue
		var crowded: bool = false
		for other: Dictionary in found:
			if (other.position as Vector3).distance_to(at) < LifeBirthdayRitual.MIN_SPACING + .05: crowded = true
		if not crowded: found.append({"index": index, "position": at})
	if found.is_empty(): return {}
	var celebrant_id: String = str(ids[0])
	var celebrant_body: Node3D = bodies[celebrant_id]
	# The birthday person takes a spot on a long side if they can walk to one.
	var order: Array = found.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var side_a: float = absf(slots[int(a.index)].x) / maxf(half.x, .01)
		var side_b: float = absf(slots[int(b.index)].x) / maxf(half.x, .01)
		var central_a: bool = side_a <= .6
		var central_b: bool = side_b <= .6
		if central_a != central_b: return central_a
		return (a.position as Vector3).distance_squared_to(celebrant_body.position) < (b.position as Vector3).distance_squared_to(celebrant_body.position))
	var first: Dictionary = {}
	for candidate: Dictionary in order:
		if not world.path_to(celebrant_body.position, candidate.position).is_empty():
			first = candidate
			break
	if first.is_empty(): return {}
	var positions: Dictionary = {celebrant_id: first.position}
	var members: Array = [celebrant_id]
	# The others take the spots in turn round the table, each the nearest free singer.
	var rest: Array = found.filter(func(entry: Dictionary) -> bool: return int(entry.index) != int(first.index))
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return fposmod(float(int(a.index) - int(first.index)), float(slots.size())) < fposmod(float(int(b.index) - int(first.index)), float(slots.size())))
	var waiting: Array = ids.slice(1)
	var wanted: int = waiting.size()
	var chosen: Array = []
	if rest.size() <= wanted: chosen = rest
	else:
		for step: int in wanted: chosen.append(rest[int(floor(float(step) * float(rest.size()) / float(maxi(1, wanted))))])
	for entry: Dictionary in chosen:
		var nearest: String = ""
		var nearest_distance: float = INF
		for member_id: Variant in waiting:
			var body: Node3D = bodies[str(member_id)]
			var gap: float = body.position.distance_squared_to(entry.position)
			if gap < nearest_distance and not world.path_to(body.position, entry.position).is_empty():
				nearest = str(member_id)
				nearest_distance = gap
		if nearest.is_empty(): continue
		positions[nearest] = entry.position
		members.append(nearest)
		waiting.erase(nearest)
	return {"ids": members, "positions": positions}

## The clear floor nearest a point that has room to stand on, or INF.
func _standing_spot_near(point: Vector3, level: int) -> Vector3:
	var world: LifeWorld = app.world
	var direct: Vector3 = world.nearest_clear_point(point, level)
	if direct.is_finite() and world._clear_coaching_space(direct): return direct
	var best: Vector3 = Vector3.INF
	var best_gap: float = INF
	for x: int in range(-8, 9):
		for z: int in range(-8, 9):
			var at: Vector3 = world.nearest_clear_point(point + Vector3(float(x) * .25, 0.0, float(z) * .25), level, 1)
			if not at.is_finite(): continue
			var gap: float = at.distance_squared_to(point)
			if gap < best_gap and world._clear_coaching_space(at):
				best = at
				best_gap = gap
	return best

## A cake held in two hands: the birthday person stands where they are and the
## others make a ring round them. Used when no table can take the cake.
func _held_layout(ids: Array, bodies: Dictionary) -> Dictionary:
	var world: LifeWorld = app.world
	var celebrant_id: String = str(ids[0])
	var body: Node3D = bodies[celebrant_id]
	var level: int = world.point_level(body.position)
	var here: Vector3 = _standing_spot_near(body.position, level)
	if not here.is_finite(): return {}
	var positions: Dictionary = {celebrant_id: here}
	var members: Array = [celebrant_id]
	var taken: Array[Vector3] = [here]
	var offsets: Array[Vector3] = LifeBirthdayRitual.held_offsets(ids.size() - 1)
	var waiting: Array = ids.slice(1)
	for offset: Vector3 in offsets:
		var at: Vector3 = world.nearest_clear_point(here + offset, level)
		if not at.is_finite() or not world._clear_coaching_space(at): continue
		var crowded: bool = false
		for other: Vector3 in taken:
			if other.distance_to(at) < LifeBirthdayRitual.MIN_SPACING + .05: crowded = true
		if crowded: continue
		var nearest: String = ""
		var nearest_distance: float = INF
		for member_id: Variant in waiting:
			var singer: Node3D = bodies[str(member_id)]
			var gap: float = singer.position.distance_squared_to(at)
			if gap < nearest_distance and not world.path_to(singer.position, at).is_empty():
				nearest = str(member_id)
				nearest_distance = gap
		if nearest.is_empty(): continue
		taken.append(at)
		positions[nearest] = at
		members.append(nearest)
		waiting.erase(nearest)
	return {"ids": members, "positions": positions, "table_id": "", "cake": here + Vector3(0, 1.0, 0), "slot": Vector3.ZERO}


## ---- What is on the screen while the family gathers

func _present() -> void:
	var household: LifeHousehold = app.household
	var world: LifeWorld = app.world
	var live: Dictionary = {}
	var seen: Dictionary = {}
	var tune_wanted: String = ""
	for session: Dictionary in household.birthday_sessions():
		var sid: String = str(session.id)
		seen[sid] = true
		var owner: LifeSim = household.member_sim(str(session.celebrant_id))
		if owner == null: continue
		var front: Dictionary = owner.get_current_action()
		var elapsed: float = float(front.get("elapsed", 0.0)) if str(front.get("cooperation_id", "")) == sid else 0.0
		var active: bool = str(session.phase) == "active"
		var cake: Array = session.cake_position
		var cake_point: Vector3 = Vector3(float(cake[0]), float(cake[1]), float(cake[2]))
		var phase: String = LifeBirthdayRitual.phase_at(elapsed)
		if not _fired.has(sid + ":seen"):
			_fired[sid + ":seen"] = true
			if elapsed >= LifeBirthdayRitual.BLOW_AT: _fired[sid + ":wish"] = true
			if elapsed >= LifeBirthdayRitual.CHEER_START: _fired[sid + ":cheer"] = true
		_show_cake(session, elapsed)
		# A gathering found after a load has no birthday signal to start the tune's making.
		if not active and not CelebrationAudio.is_built("birthday_tune"): CelebrationAudio.warm(["birthday_tune"])
		var ids: Array = session.members
		for member_id: Variant in ids:
			var actor: LifeActor = world.actors.get(str(member_id))
			if not is_instance_valid(actor): continue
			actor.celebration_presentation = {"role": LifeBirthdayRitual.ROLE_CELEBRANT if str(member_id) == str(session.celebrant_id) else LifeBirthdayRitual.ROLE_SINGER, "ritual_phase": phase, "elapsed": elapsed, "held_cake": bool(session.held), "cake_point": cake_point, "session_id": sid}
			live[str(member_id)] = true
		if active or elapsed > .01:
			tune_wanted = sid + ":" + str(epoch)
			if _tune_key != tune_wanted:
				_tune_key = tune_wanted
				app.party_music.play_birthday_tune(elapsed)
			elif active and app.party_music.tune_audible() and absf(app.party_music.tune_position() - elapsed) > TUNE_DRIFT and elapsed < CelebrationAudio.tune_seconds() - 1.0:
				# Turning Sound back on mid-song joins the tune where the family is.
				app.party_music.play_birthday_tune(elapsed)
		if active:
			_slow_down(sid)
			_speak(session, elapsed)
	_release_actors(live)
	_restore_speed(not seen.is_empty())
	if tune_wanted.is_empty() and not _tune_key.is_empty():
		_tune_key = ""
		app.party_music.stop_birthday_tune()
	for sid: Variant in props.keys():
		if not seen.has(str(sid)): _drop_cake(str(sid))

## The game runs at Normal speed for the song, so the tune and the poses keep time.
## The speed it was at is put back when the song is over.
func _slow_down(sid: String) -> void:
	if int(app.household.speed) > 1 and not (bool(app.overlay_open) and bool(app.overlay_pauses_sim)):
		if _resume_speed == 0: _resume_speed = int(app.household.speed)
		app.set_game_speed(1)
		if not _slowed.has(sid):
			_slowed[sid] = true
			_tell("Slowing down for the birthday song.")

## Once no song is going, the speed the player had chosen comes back, unless they
## have paused or changed it since.
func _restore_speed(singing: bool) -> void:
	if _resume_speed == 0 or singing: return
	if int(app.household.speed) == 1 and str(app.mode) == "live" and not (bool(app.overlay_open) and bool(app.overlay_pauses_sim)): app.set_game_speed(_resume_speed)
	_resume_speed = 0

## Bubbles for the singing, a wish for the candles and cheers at the end.
func _speak(session: Dictionary, elapsed: float) -> void:
	var household: LifeHousehold = app.household
	var sid: String = str(session.id)
	var celebrant_id: String = str(session.celebrant_id)
	var singers: Array = (session.members as Array).slice(1)
	var first: String = str(household.member_sim(celebrant_id).character.name).split(" ")[0]
	if elapsed >= 1.0 and elapsed < LifeBirthdayRitual.SING_END:
		for index: int in singers.size():
			# Each singer joins in a little after the one before, every five minutes.
			var cue: int = int((elapsed + float(index) * 1.3) / 5.0)
			var key: String = sid + ":sing:" + str(singers[index])
			if int(_cues.get(key, -1)) == cue: continue
			_cues[key] = cue
			_say(str(singers[index]), LifeBirthdayRitual.SING_BUBBLES[(cue + index) % LifeBirthdayRitual.SING_BUBBLES.size()])
	if elapsed >= LifeBirthdayRitual.BLOW_AT and not _fired.has(sid + ":wish"):
		_fired[sid + ":wish"] = true
		_say(celebrant_id, LifeBirthdayRitual.WISH_LINES[absi(hash(sid)) % LifeBirthdayRitual.WISH_LINES.size()])
	if elapsed >= LifeBirthdayRitual.CHEER_START and not _fired.has(sid + ":cheer"):
		_fired[sid + ":cheer"] = true
		for index: int in singers.size():
			_say(str(singers[index]), str(LifeBirthdayRitual.CHEERS[index % LifeBirthdayRitual.CHEERS.size()]).replace("%s", first))
		_say(celebrant_id, LifeBirthdayRitual.THANKS)

func _say(member_id: String, text: String) -> void:
	var actor: LifeActor = app.world.actors.get(member_id)
	if is_instance_valid(actor): actor.speech(text)

## Put the cake on its table (or take it away again when the candles are out).
func _show_cake(session: Dictionary, elapsed: float) -> void:
	var sid: String = str(session.id)
	if bool(session.held) or str(session.table_id).is_empty(): return
	var host: Dictionary = app._find_item(str(session.table_id))
	if host.is_empty() or not is_instance_valid(host.get("node")): return
	var cake: Node3D = props.get(sid)
	if not is_instance_valid(cake) or cake.get_parent() != host.node:
		if is_instance_valid(cake): cake.queue_free()
		cake = _build_cake(host, session)
		if cake == null: return
		props[sid] = cake
	for flame: Node in cake.find_children("Flame_*", "Node3D", true, false):
		(flame as Node3D).visible = LifeBirthdayRitual.candles_lit(elapsed)

func _build_cake(host: Dictionary, session: Dictionary) -> Node3D:
	if not ResourceLoader.exists(CAKE_MODEL): return null
	var scene: PackedScene = load(CAKE_MODEL)
	var cake: Node3D = scene.instantiate()
	# The table drops its own ornaments (the bowl of fruit) while this node stands on it.
	cake.name = LifeWorld.BIRTHDAY_CAKE_NODE
	cake.scale = Vector3.ONE * CAKE_SCALE
	var point: Array = session.cake_position
	cake.position = (host.node as Node3D).to_local(Vector3(float(point[0]), float(point[1]), float(point[2])))
	host.node.add_child(cake)
	app.world.assign_structure_layer(cake, app.world.item_level(host))
	app.world.sync_surface_decorations()
	return cake

func _drop_cake(sid: String) -> void:
	if props.has(sid) and is_instance_valid(props[sid]): props[sid].queue_free()
	props.erase(sid)
	# The table's own ornaments come back when nothing else stands on them.
	if is_instance_valid(app.world): app.world.sync_surface_decorations()
	for key: Variant in _fired.keys():
		if str(key).begins_with(sid + ":"): _fired.erase(key)
	for key: Variant in _cues.keys():
		if str(key).begins_with(sid + ":"): _cues.erase(key)
	_slowed.erase(sid)

## Everyone no longer in a gathering stands down.
func _release_actors(live: Dictionary) -> void:
	for member_id: Variant in _presented.keys():
		if live.has(member_id): continue
		var actor: LifeActor = app.world.actors.get(str(member_id)) if is_instance_valid(app) and is_instance_valid(app.world) else null
		if is_instance_valid(actor): actor.celebration_presentation = {}
		_presented.erase(member_id)
	for member_id: Variant in live.keys(): _presented[member_id] = true


## ---- When the candles are out

## A real cake is set out for the household to share: on the table it stood on, or
## else the nearest serving surface, or else in the fridge.
func _on_finished(celebrant_id: String, record: Dictionary) -> void:
	var sid: String = str(record.get("id", ""))
	_drop_cake(sid)
	if is_instance_valid(app.party_music): app.party_music.stop_birthday_tune()
	_tune_key = ""
	var batch: Dictionary = _set_out_cake(celebrant_id, record)
	if batch.is_empty(): return
	app.meal_flow.sync_due = true
	app.meal_flow.call_to_meal(str(batch.id))

func _set_out_cake(celebrant_id: String, record: Dictionary) -> Dictionary:
	var flow: LifeMealFlow = app.meal_flow
	var meals: LifeMeals = flow.food()
	var now: float = flow.now()
	var batch: Dictionary = {}
	var table: Dictionary = app._find_item(str(record.get("table_id", ""))) if not str(record.get("table_id", "")).is_empty() else {}
	var cake: Array = record.get("cake_position", [0.0, 0.0, 0.0])
	var from: Vector3 = Vector3(float(cake[0]), float(cake[1]), float(cake[2]))
	var body: Variant = app.world.actors.get(celebrant_id)
	if is_instance_valid(body): from = (body as Node3D).position
	var hosts: Array = [table] if not table.is_empty() else []
	# Failing that, the nearest other table (a stove top is no place for a birthday cake).
	var others: Array = app.world.items.filter(func(host: Dictionary) -> bool: return str(host.kind) in TABLE_KINDS and is_instance_valid(host.get("node")) and str(host.id) != str(table.get("id", "")) and app.world.item_level(host) == app.world.point_level(from))
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.node as Node3D).global_position.distance_squared_to(from) < (b.node as Node3D).global_position.distance_squared_to(from))
	hosts.append_array(others)
	for host: Dictionary in hosts:
		if not LifeMeals.SURFACE_HEIGHTS.has(str(host.kind)): continue
		var slot: Vector3 = flow._surface_slot(host, LifeMeals.PLATTER_HALF_SIZE)
		if not slot.is_finite(): continue
		batch = meals.place_batch("layer_cake", celebrant_id, 2, str(app.current_venue), now, str(host.id), (host.node as Node3D).to_global(slot), slot)
		if not batch.is_empty(): return batch
	var fridge: Dictionary = app.world.closest_item("fridge", from)
	if not fridge.is_empty():
		batch = meals.create_batch("layer_cake", celebrant_id, 2, str(app.current_venue), now)
		if not batch.is_empty():
			meals.set_batch_location(str(batch.id), "fridge", str(fridge.id), (fridge.node as Node3D).position, now)
			_tell("The birthday cake goes in the fridge for later.")
	return batch


## ---- Keeping up with the household and the loads

## The household is replaced by a load; connect to whichever one is current.
func _follow_household() -> void:
	var household: Node = app.household
	if household == _connected: return
	_connected = household
	household.birthday_ritual_finished.connect(_on_finished)
	household.member_milestone.connect(_on_milestone)

func _on_milestone(_member_id: String, kind: String, data: Dictionary) -> void:
	if kind != "birthday": return
	_retry = 0.0
	# The tune takes a moment to make: start on a worker thread now, so it is ready
	# by the time the family has gathered.
	if str(data.get("source", "")) == "auto": CelebrationAudio.warm(["birthday_tune"])

## A new game or a load starts a new epoch and the old screen is forgotten.
func _sync_epoch() -> void:
	if int(app.load_epoch) == epoch: return
	epoch = int(app.load_epoch)
	clear()
