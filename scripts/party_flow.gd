extends Node
class_name LifePartyFlow
## Hosting a party, as the player sees it.
##
## From People, "Host a party..." opens a card: who is it for, which friends are
## asked, who brings a dish, how many hours, and whether there is music. Sending
## it writes the party record into the household (scripts/party_plan.gd describes
## it and checks it on a load) and sets each friend going, a few minutes apart. A
## friend who brings a dish spends twenty minutes making it first, arrives holding
## it, and sets it on the party table as shared servings (the meal ledger's
## `brought_by`). Friends arrive as party visits (scripts/residents.gd), walk
## straight in with no host greeting, and each goes home when the party ends.
##
## While the party is on the friends choose party things for themselves: a bite
## from the platter or a dish, a dance at the stereo. When the party is for
## someone whose birthday is waiting, the family's cake waits for the guests, who
## then stand round the table and sing with the family. The party music is the
## party loop (scripts/party_music.gd), from the stereo when there is one. A
## decorated home lifts the guests' fun and the household's mood.
##
## Everything that has to survive a save lives in the household's party record
## and the residents' party visits. This service keeps only what is on the screen
## (the card, the dishes in friends' hands, the music), so after a load it finds
## the party again and puts all of that back.

const PartyFood = preload("res://scripts/party_food.gd")
const CARD_AT: Vector2 = Vector2(370, 96)
const CARD_SIZE: Vector2 = Vector2(700, 772)
const STATUS_AT: Vector2 = Vector2(1038, 206)
const STATUS_SIZE: Vector2 = Vector2(374, 118)
## Real seconds between the party's own checks, and between status card updates.
const STEP_EVERY: float = .25
const STATUS_EVERY: float = .5
## Real seconds before a guest who could not set down a dish is asked again.
const BRING_EVERY: float = 1.5
## How far from the table a singing guest may stand.
const SING_DISTANCE: float = 2.6

var app: Node
## The load this service has seen, so a new load forgets what was on the screen.
var epoch: int = 0
## The planner card's choices: invited and potluck (id to bool), celebrant, hours, music.
var planner: Dictionary = {}
## What the player was last told about the party, oldest first.
var notices: Array[String] = []
## The dish each friend is holding as they arrive (guest id to node).
var dishes: Dictionary = {}
var status_card: Control
var status_text: Label
var status_music: Button
var status_end: Button
var _ui: Dictionary = {}
var _clock: float = 0.0
var _status_clock: float = 0.0
var _retry: Dictionary = {}
var _bring_at: Dictionary = {}
var _holding: Dictionary = {}
var _singers: Dictionary = {}
var _cues: Dictionary = {}
var _cheered: Dictionary = {}
var _was_on: bool = false
var _stereo: Vector3 = Vector3.INF
var _stereo_clock: float = 0.0


func _init(owner: Node = null) -> void:
	app = owner
	if is_instance_valid(owner): epoch = int(owner.load_epoch)


## ---- The party and where it stands

## Whether a party has been sent and is not over.
func active() -> bool:
	return is_instance_valid(app) and is_instance_valid(app.household) and not app.household.party.is_empty()

## The party record, or {}.
func party() -> Dictionary:
	return app.household.party

## The absolute game minute, on the same clock as every visit.
func now() -> float:
	return float(app.household.day - 1) * 1440.0 + float(app.household.minutes)

## The first name of a member or a neighbor.
func _first(id: String) -> String:
	var sim: LifeSim = app.household.member_sim(id)
	if sim != null: return str(sim.character.name).split(" ")[0]
	return str(LifeResidentCatalogue.PEOPLE.get(id, {}).get("name", id)).split(" ")[0]

func _tell(message: String) -> void:
	notices.append(message)
	while notices.size() > 16: notices.pop_front()
	app.show_notice(message)

## Whether the family's cake is held back for this person's guests.
func ritual_waits(member_id: String) -> bool:
	return active() and LifePartyPlan.ritual_waits(party(), member_id, now())


## ---- Every frame

## Called every frame by the controller.
func tick(delta: float) -> void:
	if not is_instance_valid(app) or not is_instance_valid(app.household): return
	_sync_epoch()
	if str(app.mode) == "creator":
		clear()
		return
	if not active():
		if _was_on: _stand_down()
		_status_clear()
		return
	if str(app.mode) != "live" or bool(app.loading_game) or str(app.current_venue) != "home": return
	_was_on = true
	_clock -= delta
	if _clock <= 0.0:
		_clock = STEP_EVERY
		_advance()
	if not active(): return
	_present(delta)
	_status_clock -= delta
	if _status_clock <= 0.0:
		_status_clock = STATUS_EVERY
		refresh_status()

## Throw away everything on the screen: the dishes, the poses, the music, the card.
func clear() -> void:
	_stand_down()
	_status_clear()
	_retry.clear()
	_bring_at.clear()

## A new game or a load starts a new epoch and the old screen is forgotten.
func _sync_epoch() -> void:
	if int(app.load_epoch) == epoch: return
	epoch = int(app.load_epoch)
	clear()
	planner.clear()

## Take away what the party put on the screen: held dishes, party poses, music.
func _stand_down() -> void:
	for id: Variant in dishes.keys(): _drop_dish(str(id))
	for id: Variant in _singers.keys(): _free_singer(str(id))
	_singers.clear()
	_cues.clear()
	_cheered.clear()
	_holding.clear()
	if is_instance_valid(app.party_music) and (app.party_music.wants_loop or app.party_music.loop_at.is_finite()): app.party_music.set_party_loop(false)
	_was_on = false

## The party step: who has set off, who has arrived, who has gone, and when it is over.
func _advance() -> void:
	var household: LifeHousehold = app.household
	var record: Dictionary = household.party
	var at: float = now()
	var residents: LifeResidents = app.residents
	var ending: bool = str(record.phase) == "ending"
	for entry: Dictionary in record.guests:
		var id: String = str(entry.id)
		var visit: LifeHomeVisit = residents.visit_for(id)
		var here: bool = visit.owns(id)
		match str(entry.status):
			"preparing":
				if ending or at >= float(record.ends_at): _give_up(entry, "%s could not make it to the party." % _first(id))
				elif at >= float(entry.depart_at): _send_guest(entry, at)
			"walking":
				if not here: entry.status = "left"
				elif str(visit.state.phase) == "inside": _arrived(entry)
			"inside":
				if not here: entry.status = "left"
	var found: Dictionary = LifePartyPlan.counts(record)
	if str(record.phase) == "inviting" and int(found.inside) > 0: _begin_party()
	if str(record.phase) != "ending" and at >= float(record.ends_at): _begin_ending()
	if not LifePartyPlan.guests_remaining(record):
		_finish()
		return
	_serve_dishes()
	_gather_guests()

## A friend sets off for the party. A try that cannot start yet is repeated a few
## minutes later, and a friend who cannot get in at all stays away.
func _send_guest(entry: Dictionary, at: float) -> void:
	var id: String = str(entry.id)
	var tries: Dictionary = _retry.get(id, {"tries": 0, "at": 0.0})
	if float(tries.at) > at: return
	var record: Dictionary = app.household.party
	var reason: String = app.residents.home_visit.party_requirement(id)
	var notice: String = " is on the way to your party%s." % (" with a dish" if not str(entry.potluck).is_empty() else "")
	if reason.is_empty() and app.residents.invite_to_party(id, int(record.serial), float(record.ends_at), notice):
		entry.status = "walking"
		_retry.erase(id)
		return
	tries.tries = int(tries.tries) + 1
	tries.at = at + LifePartyPlan.INVITE_RETRY
	tries["reason"] = reason
	_retry[id] = tries
	if int(tries.tries) >= LifePartyPlan.INVITE_TRIES: _give_up(entry, "%s could not come to the party.%s" % [_first(id), " " + str(tries.reason) if not str(tries.reason).is_empty() else ""])

func _give_up(entry: Dictionary, message: String) -> void:
	entry.status = "left"
	_retry.erase(str(entry.id))
	_tell(message)

## A guest is through the door: they came, and a decorated home gives them a lift.
func _arrived(entry: Dictionary) -> void:
	entry.status = "inside"
	entry["came"] = true
	var lift: int = LifePartyPlan.decor_fun(app.world.festive_count(0))
	if lift > 0:
		var visit: LifeHomeVisit = app.residents.visit_for(str(entry.id))
		visit.activity.ensure()
		visit.activity.data.needs.fun = minf(100.0, float(visit.activity.data.needs.fun) + float(lift))

## The first guest is inside: the party has begun.
func _begin_party() -> void:
	var record: Dictionary = app.household.party
	record.phase = "active"
	_tell("The party has begun!")
	if app.world.festive_count(0) > 0:
		for member: Dictionary in app.household.members:
			if member.sim.is_spirit() or member.sim.is_away(): continue
			member.sim.add_moodlet(LifePartyPlan.MOODLET_FESTIVE, "Happy", "The home is dressed up for a party.", 240.0, 2)

## The time is up (or the host called it): guests who are still on their way go home
## and the rest leave at their end time.
func _begin_ending() -> void:
	var record: Dictionary = app.household.party
	record.phase = "ending"
	_tell("The party is winding down.")
	for entry: Dictionary in record.guests:
		var visit: LifeHomeVisit = app.residents.visit_for(str(entry.id))
		if str(entry.status) == "preparing": entry.status = "left"
		elif visit.owns(str(entry.id)) and str(visit.state.phase) in ["arriving", "waiting", "entering"]: visit.goodbye("The party is over. Your guest is heading home.")

## The host calls the party off early. Guests say goodbye a couple of minutes apart.
func end_party() -> bool:
	if not active() or str(party().phase) == "ending": return false
	var record: Dictionary = app.household.party
	var at: float = now()
	var gap: float = 0.0
	record.phase = "ending"
	_tell("The party is winding down.")
	for entry: Dictionary in record.guests:
		var id: String = str(entry.id)
		var visit: LifeHomeVisit = app.residents.visit_for(id)
		if str(entry.status) == "preparing":
			entry.status = "left"
		elif visit.owns(id) and str(visit.state.phase) == "inside":
			visit.state.party_until = minf(float(visit.state.party_until), at + gap)
			gap += LifePartyPlan.GOODBYE_GAP
		elif visit.owns(id):
			visit.goodbye("The party is over. Your guest is heading home.")
	record.ends_at = maxf(float(record.started_at) + 1.0, minf(float(record.ends_at), at + maxf(0.0, gap - LifePartyPlan.GOODBYE_GAP)))
	# No guest's stay may run past the party's own end, even one already heading out.
	for entry: Dictionary in record.guests:
		var visit: LifeHomeVisit = app.residents.visit_for(str(entry.id))
		if visit.owns(str(entry.id)) and visit.state.has("party_until"): visit.state.party_until = minf(float(visit.state.party_until), float(record.ends_at))
	refresh_status()
	return true

## The last guest has gone. Friends grow closer, the household is pleased if it was
## a real party, and the party is forgotten.
func _finish() -> void:
	var household: LifeHousehold = app.household
	var record: Dictionary = household.party
	var came: Array = []
	for entry: Dictionary in record.guests:
		if bool(entry.get("came", false)): came.append(entry)
	var host: LifeSim = household.member_sim(str(record.host_id))
	var celebrant: LifeSim = household.member_sim(str(record.celebrant_id)) if not str(record.celebrant_id).is_empty() else null
	for entry: Dictionary in came:
		var eaten: bool = false
		if not str(entry.batch).is_empty():
			var batch: Dictionary = household.meals.batch(str(entry.batch))
			# A dish that is no longer in the ledger was eaten up and cleared away.
			eaten = batch.is_empty() or int(batch.remaining) < int(batch.initial)
		var gain: float = LifePartyPlan.friendship_gain(eaten)
		# The host is often the celebrant too, and is only thanked once.
		for sim: LifeSim in [host] if celebrant == host else [host, celebrant]:
			if sim != null: _befriend(sim, str(entry.id), gain)
	if host != null and not came.is_empty(): host.remember("Hosted a party", "%d %s came to the party." % [came.size(), "friend" if came.size() == 1 else "friends"])
	if came.size() >= 2:
		for member: Dictionary in household.members:
			if not member.sim.is_spirit() and not member.sim.is_away(): member.sim.add_moodlet(LifePartyPlan.MOODLET_GREAT, "Happy", "A lively party with good friends.", 360.0, 3)
	if came.is_empty(): _tell("The party is over. Nobody could come this time.")
	else: _tell("The party is over. %d %s came and everyone is closer for it." % [came.size(), "friend" if came.size() == 1 else "friends"])
	household.party = {}
	_stand_down()
	_status_clear()

## A friend grows closer to one member by this much.
func _befriend(sim: LifeSim, guest_id: String, amount: float) -> void:
	if not sim.relationships.has(guest_id): return
	var link: Dictionary = sim.relationships[guest_id]
	link["friendship"] = minf(100.0, float(link.get("friendship", 0.0)) + amount)
	sim._update_relationship_status(link)
	sim._emit_changed()


## ---- Dishes

## The table the party sits at: a dining table in a cloth if there is one, else
## any table with room for a dish. Only the ground floor counts, since guests
## stay downstairs.
func party_table() -> Dictionary:
	var best: Dictionary = {}
	var best_rank: int = 1000
	for host: Dictionary in app.world.items:
		var kind: String = str(host.kind)
		if kind not in LifeBirthdayFlow.TABLE_KINDS or not is_instance_valid(host.get("node")) or app.world.item_level(host) != 0: continue
		if not app.meal_flow._surface_slot(host, LifeMeals.PLATTER_HALF_SIZE).is_finite(): continue
		var rank: int = LifeBirthdayFlow.TABLE_KINDS.find(kind) - (10 if not app.world.item_cloth(host).is_empty() else 0)
		if rank < best_rank:
			best = host
			best_rank = rank
	return best

## Friends who are inside with a dish still in their hands set it down.
func _serve_dishes() -> void:
	var record: Dictionary = app.household.party
	for entry: Dictionary in record.guests:
		var id: String = str(entry.id)
		if str(entry.potluck).is_empty() or bool(entry.brought) or str(entry.status) != "inside": continue
		var visit: LifeHomeVisit = app.residents.visit_for(id)
		if not visit.owns(id) or str(visit.state.phase) != "inside" or visit.meal.active(): continue
		var current: Dictionary = visit.activity.current_action()
		if str(current.get("id", "")) in [LifePartyPlan.BRING, LifeBirthdayRitual.SINGER_ACTION]: continue
		if float(_bring_at.get(id, 0.0)) > Time.get_ticks_msec() / 1000.0: continue
		_bring_at[id] = Time.get_ticks_msec() / 1000.0 + BRING_EVERY
		var table: Dictionary = party_table()
		if table.is_empty():
			entry.brought = true
			_tell("There is no table with room for %s's %s." % [_first(id), LifePartyPlan.potluck_label(id)])
			continue
		var spot: Vector3 = _stand_by(table, visit)
		if not spot.is_finite(): continue
		var plan: Dictionary = {"id": LifePartyPlan.BRING, "label": "Set down a dish", "target_id": str(table.id), "target_kind": str(table.kind), "target_position": spot, "duration": 2.0, "changes": {"social": 6.0}, "animation": "", "face": _pack((table.node as Node3D).global_position)}
		visit.activity.request_plan(plan, true)

## The guest has set the dish down: it is on the table as shared servings.
func dish_set_down(guest_id: String, action: Dictionary) -> void:
	var record: Dictionary = app.household.party
	var entry: Dictionary = LifePartyPlan.guest_entry(record, guest_id)
	if entry.is_empty() or bool(entry.brought) or str(entry.potluck).is_empty(): return
	entry.brought = true
	var table_id: String = str(action.get("target_id", ""))
	var batch: Dictionary = app.meal_flow.place_potluck(guest_id, table_id, str(record.host_id), str(entry.potluck))
	if batch.is_empty() and not party_table().is_empty():
		var other: Dictionary = party_table()
		batch = app.meal_flow.place_potluck(guest_id, str(other.id), str(record.host_id), str(entry.potluck))
	if batch.is_empty():
		_tell("There was no room on the table for %s's %s." % [_first(guest_id), LifePartyPlan.potluck_label(guest_id)])
		return
	entry.batch = str(batch.id)
	app.meal_flow.sync_due = true

## A guest finished a bite from the platter.
func platter_taken(action: Dictionary) -> void:
	PartyFood.finished(app, action)

## A place to stand by a table that this guest can walk to, nearest first, or INF.
func _stand_by(table: Dictionary, visit: LifeHomeVisit) -> Vector3:
	var world: LifeWorld = app.world
	var node: Node3D = table.node
	var half: Vector2 = LifeMeals.SURFACE_HALF_SIZE.get(str(table.kind), Vector2(.5, .4))
	var body: LifeActor = world.actors.get(str(visit.state.guest))
	var level: int = world.item_level(table)
	var found: Array[Vector3] = []
	for turn: int in 8:
		var angle: float = float(turn) * PI * .25
		var wish: Vector3 = node.to_global(Vector3(sin(angle) * (half.x + .75), 0.0, cos(angle) * (half.y + .75)))
		var at: Vector3 = world.nearest_clear_point(wish, level, 1)
		if at.is_finite() and Vector2(at.x - node.global_position.x, at.z - node.global_position.z).length() <= maxf(half.x, half.y) + 1.4: found.append(at)
	if is_instance_valid(body): found.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(body.position) < b.distance_squared_to(body.position))
	for at: Vector3 in found:
		if not app.traversal._free(str(visit.state.guest), at): continue
		if visit.activity._route_to(at).is_empty(): continue
		return at
	return Vector3.INF

func _pack(at: Vector3) -> Array:
	return [at.x, at.y, at.z]

func _unpack(value: Variant) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value is Array and value.size() == 3 else Vector3.INF


## ---- Guests choosing party things for themselves

## A party guest who is free chooses something for the party: a bite from a dish or
## the platter when they are not full, or a dance at the stereo. Two choices in
## three are left to the party, the third to the guest's ordinary choices, so a
## guest still chats, sits and pets the dog. Returns whether a choice was made.
func guest_choose(act: LifeGuestActivity) -> bool:
	if not active() or str(party().phase) == "ending": return false
	var visit: LifeHomeVisit = act.visit
	if not visit.state.has("party") or str(visit.state.phase) != "inside": return false
	var turn: int = int(act.data.get("pick", 0))
	if turn % 3 == 0: return false
	var hungry: bool = float(act.data.needs.hunger) < 80.0
	var order: Array[String] = ["dance", "eat"]
	if (hungry and turn % 2 == 0) or not bool(party().music): order = ["eat", "dance"]
	for kind: String in order:
		if kind == "eat" and hungry and _try_eat(act): return true
		if kind == "dance" and bool(party().music) and _try_dance(act): return true
	return false

## A shared dish first (a friend's, the freshest), then the platter.
func _try_eat(act: LifeGuestActivity) -> bool:
	var household: LifeHousehold = app.household
	var dishes_found: Array = []
	for batch: Dictionary in household.meals.batches:
		if str(batch.storage) == "surface" and str(batch.owner).is_empty() and int(batch.remaining) > 0 and str(batch.venue) == "home": dishes_found.append(batch)
	dishes_found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("brought_by", "")) > str(b.get("brought_by", "")))
	for batch: Dictionary in dishes_found:
		if act.visit.meal.offer(str(batch.id)): return true
	for item: Dictionary in app.world.items:
		if str(item.kind) != "party_food" or app.world.item_level(item) != 0 or int(item.get("servings", 0)) <= 0: continue
		var spot: Vector3 = app.world.approach(item)
		if not spot.is_finite() or not app.traversal._free(act.person(), spot) or act._route_to(spot).is_empty(): continue
		var plan: Dictionary = {"id": PartyFood.EAT, "label": "Grab some party food", "target_id": str(item.id), "target_kind": "party_food", "target_position": spot, "duration": 15.0, "changes": {"hunger": 26.0, "fun": 8.0}, "animation": "snack"}
		if act.request_plan(plan, false): return true
	return false

## A dance at the stereo, on a place round it that nobody else has.
func _try_dance(act: LifeGuestActivity) -> bool:
	var stereo: Dictionary = _stereo_item()
	if stereo.is_empty(): return false
	var world: LifeWorld = app.world
	var node: Node3D = stereo.node
	var level: int = world.item_level(stereo)
	var taken: Array[Vector3] = []
	for visit: LifeHomeVisit in app.residents.visits():
		if visit.active() and visit != act.visit and str(visit.activity.current_action().get("id", "")) == LifePartyPlan.DANCE: taken.append(Vector3(visit.activity.current_action().target_position))
	# Rings round the stereo, near first. Each guest starts the ring at a different angle,
	# so several guests do not all crowd the same side.
	var start: int = absi(hash(act.person())) % 8
	for radius: float in [1.0, 1.4, 1.8]:
		for turn: int in 8:
			var angle: float = TAU * float((turn + start) % 8) / 8.0
			var wish: Vector3 = node.to_global(Vector3(sin(angle) * radius, 0.0, cos(angle) * radius))
			var at: Vector3 = world.nearest_clear_point(wish, level, 1)
			if not at.is_finite() or at.distance_to(node.global_position) > radius + .5 or not world._clear_coaching_space(at) or not app.traversal._free(act.person(), at): continue
			var crowded: bool = false
			for other: Vector3 in taken:
				if other.distance_to(at) < LifeDancePlan.MIN_SPACING + .1: crowded = true
			if crowded or act._route_to(at).is_empty(): continue
			var plan: Dictionary = {"id": LifePartyPlan.DANCE, "label": "Dance", "target_id": str(stereo.id), "target_kind": "stereo", "target_position": at, "duration": 30.0, "changes": {"fun": 28.0, "social": 8.0, "energy": -6.0}, "face": _pack(node.global_position)}
			if act.request_plan(plan, false): return true
	return false

## The ground-floor stereo, or {}.
func _stereo_item() -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == "stereo" and is_instance_valid(item.get("node")) and app.world.item_level(item) == 0: return item
	return {}


## ---- The cake, with guests

## When the party is for someone whose cake is on, the guests inside stand round
## the table and sing with the family.
func _gather_guests() -> void:
	var record: Dictionary = app.household.party
	var celebrant: String = str(record.celebrant_id)
	if celebrant.is_empty(): return
	var session: Dictionary = app.household.birthday_session_for(celebrant)
	if session.is_empty(): return
	var sid: String = str(session.id)
	var taken: Array[Vector3] = []
	for id: Variant in _singers.keys():
		if str(_singers[id].session) == sid: taken.append(_singers[id].spot)
	for entry: Dictionary in record.guests:
		var id: String = str(entry.id)
		if str(entry.status) != "inside" or (_singers.has(id) and str(_singers[id].session) == sid): continue
		# A friend still holding a dish sets it down first; they join the song after that if it is still on.
		if not str(entry.potluck).is_empty() and not bool(entry.brought): continue
		var visit: LifeHomeVisit = app.residents.visit_for(id)
		if not visit.owns(id) or str(visit.state.phase) != "inside" or visit.meal.active(): continue
		var spot: Vector3 = _singer_spot(session, visit, taken)
		if not spot.is_finite(): continue
		var face: Vector3 = _unpack(session.cake_position)
		var plan: Dictionary = {"id": LifeBirthdayRitual.SINGER_ACTION, "label": "Sing happy birthday", "target_id": str(session.table_id), "target_position": spot, "duration": LifeBirthdayRitual.DURATION, "changes": {"fun": 12.0, "social": 12.0}, "face": _pack(face)}
		if visit.activity.request_plan(plan, true):
			_singers[id] = {"session": sid, "spot": spot}
			taken.append(spot)

## A place round the cake for a guest: on the ring round the table (or round a held
## cake), clear, apart from everyone else and within reach.
func _singer_spot(session: Dictionary, visit: LifeHomeVisit, taken: Array[Vector3]) -> Vector3:
	var world: LifeWorld = app.world
	var wishes: Array[Vector3] = []
	var centre: Vector3 = Vector3.ZERO
	var level: int = 0
	var host: Dictionary = app._find_item(str(session.table_id)) if not str(session.table_id).is_empty() else {}
	if not host.is_empty() and is_instance_valid(host.get("node")) and LifeMeals.SURFACE_HALF_SIZE.has(str(host.kind)):
		level = world.item_level(host)
		centre = (host.node as Node3D).global_position
		for slot: Vector3 in LifeBirthdayRitual.ring_slots(LifeMeals.SURFACE_HALF_SIZE[str(host.kind)]): wishes.append((host.node as Node3D).to_global(slot))
	else:
		var here: Variant = session.positions.get(str(session.celebrant_id))
		if not here is Array: return Vector3.INF
		centre = _unpack(here)
		level = world.point_level(centre)
		for offset: Vector3 in LifeBirthdayRitual.held_offsets(8): wishes.append(centre + offset * 1.5)
	var body: LifeActor = world.actors.get(str(visit.state.guest))
	if is_instance_valid(body): wishes.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(body.position) < b.distance_squared_to(body.position))
	var spots: Array[Vector3] = taken.duplicate()
	for value: Variant in session.positions.values(): spots.append(_unpack(value))
	for wish: Vector3 in wishes:
		var at: Vector3 = world.nearest_clear_point(wish, level)
		if not at.is_finite() or Vector2(at.x - centre.x, at.z - centre.z).length() > SING_DISTANCE or not world._clear_coaching_space(at): continue
		var crowded: bool = false
		for other: Vector3 in spots:
			if other.distance_to(at) < LifeBirthdayRitual.MIN_SPACING + .05: crowded = true
		if crowded or not app.traversal._free(str(visit.state.guest), at) or visit.activity._route_to(at).is_empty(): continue
		return at
	return Vector3.INF


## ---- What is on the screen

func _present(_delta: float) -> void:
	_present_dishes()
	_present_singers()
	present_music()

## A friend bringing a dish holds it, in both hands, from the door until the table.
func _present_dishes() -> void:
	var record: Dictionary = app.household.party
	var live: Dictionary = {}
	for entry: Dictionary in record.guests:
		var id: String = str(entry.id)
		if str(entry.potluck).is_empty() or bool(entry.brought) or str(entry.status) not in ["walking", "inside"]: continue
		var visit: LifeHomeVisit = app.residents.visit_for(id)
		var body: LifeActor = app.world.actors.get(id)
		if not visit.owns(id) or str(visit.state.phase) == "leaving" or not is_instance_valid(body) or not body.visible: continue
		live[id] = true
		body.meal_presentation = {"carrying": true, "platter": true, "grips": app.meal_flow.carry_grips_for_recipe(str(entry.potluck))}
		var dish: Node3D = dishes.get(id) as Node3D
		if not is_instance_valid(dish):
			dish = _build_dish(str(entry.potluck), id)
			if dish == null: continue
			dishes[id] = dish
		dish.global_transform = body.meal_carry_transform()
		_holding[id] = true
	for id: Variant in dishes.keys():
		if not live.has(id): _drop_dish(str(id))

func _build_dish(recipe: String, guest_id: String) -> Node3D:
	var path: String = LifeMeals.model_path(recipe, false)
	if not ResourceLoader.exists(path) or not is_instance_valid(app.world.house): return null
	var dish: Node3D = (load(path) as PackedScene).instantiate()
	dish.name = "PotluckDish_" + guest_id
	app.world.house.add_child(dish)
	app.world._assign_layers(dish, LifeWorld.actor_layer(0))
	return dish

func _drop_dish(id: String) -> void:
	if dishes.has(id) and is_instance_valid(dishes[id]): dishes[id].queue_free()
	dishes.erase(id)
	if _holding.has(id):
		_holding.erase(id)
		var body: LifeActor = app.world.actors.get(id) if is_instance_valid(app.world) else null
		if is_instance_valid(body): body.meal_presentation = {}

## Guests round the cake take the poses and the song's own clock from the family.
func _present_singers() -> void:
	var household: LifeHousehold = app.household
	for id: Variant in _singers.keys():
		var guest_id: String = str(id)
		var info: Dictionary = _singers[id]
		var session: Dictionary = _session_by_id(str(info.session))
		var visit: LifeHomeVisit = app.residents.visit_for(guest_id)
		var current: Dictionary = visit.activity.current_action() if visit.owns(guest_id) else {}
		var singing: bool = str(current.get("id", "")) == LifeBirthdayRitual.SINGER_ACTION
		# The song is over, or the guest was drawn away from it: they stand down.
		if session.is_empty() or not singing:
			if session.is_empty() and singing: visit.activity.cancel("")
			_free_singer(guest_id)
			_singers.erase(id)
			continue
		var owner: LifeSim = household.member_sim(str(session.celebrant_id))
		var front: Dictionary = owner.get_current_action() if owner != null else {}
		var elapsed: float = float(front.get("elapsed", 0.0)) if str(front.get("cooperation_id", "")) == str(session.id) else 0.0
		var body: LifeActor = app.world.actors.get(guest_id)
		if not is_instance_valid(body): continue
		body.celebration_presentation = {"role": LifeBirthdayRitual.ROLE_SINGER, "ritual_phase": LifeBirthdayRitual.phase_at(elapsed), "elapsed": elapsed, "held_cake": false, "cake_point": _unpack(session.cake_position), "session_id": str(session.id)}
		_sing(guest_id, str(session.id), elapsed, str(session.celebrant_id))

## Bubbles for the song and a cheer at the end, said by each guest in turn.
func _sing(guest_id: String, sid: String, elapsed: float, celebrant_id: String) -> void:
	var body: LifeActor = app.world.actors.get(guest_id)
	if not is_instance_valid(body): return
	if elapsed >= 1.0 and elapsed < LifeBirthdayRitual.SING_END:
		var cue: int = int((elapsed + float(absi(hash(guest_id)) % 4)) / 5.0)
		var key: String = sid + ":" + guest_id
		if int(_cues.get(key, -1)) != cue:
			_cues[key] = cue
			body.speech(str(LifeBirthdayRitual.SING_BUBBLES[(cue + absi(hash(guest_id))) % LifeBirthdayRitual.SING_BUBBLES.size()]))
	if elapsed >= LifeBirthdayRitual.CHEER_START and not _cheered.has(sid + ":" + guest_id):
		_cheered[sid + ":" + guest_id] = true
		body.speech(str(LifeBirthdayRitual.CHEERS[absi(hash(guest_id)) % LifeBirthdayRitual.CHEERS.size()]).replace("%s", _first(celebrant_id)))

func _free_singer(guest_id: String) -> void:
	var body: LifeActor = app.world.actors.get(guest_id) if is_instance_valid(app.world) else null
	if is_instance_valid(body): body.celebration_presentation = {}

func _session_by_id(sid: String) -> Dictionary:
	for session: Dictionary in app.household.birthday_sessions():
		if str(session.id) == sid: return session
	return {}

## The party loop plays while the party is on, from the stereo when there is one.
## (Called every frame; a test may call it directly.)
## Turning the music off on the card, or Music or Sound off in the menu, silences it.
func present_music() -> void:
	var record: Dictionary = app.household.party
	var wanted: bool = str(record.phase) == "active" and bool(record.music)
	var music: LifePartyMusic = app.party_music
	if not is_instance_valid(music): return
	if not wanted:
		if music.wants_loop: music.set_party_loop(false)
		return
	_stereo_clock -= get_process_delta_time()
	if _stereo_clock <= 0.0 or not music.wants_loop:
		_stereo_clock = 1.0
		var stereo: Dictionary = _stereo_item()
		_stereo = (stereo.node as Node3D).global_position + Vector3(0, 1.0, 0) if not stereo.is_empty() else Vector3.INF
	if not music.wants_loop or music.loop_at.is_finite() != _stereo.is_finite() or (_stereo.is_finite() and music.loop_at.distance_to(_stereo) > .05): music.set_party_loop(true, _stereo)

## Turn the party music on or off from the status card.
func set_music(enabled: bool) -> void:
	if not active(): return
	party().music = enabled
	present_music()
	refresh_status()


## ---- The planner card

## The neighbors, in the order the card lists them.
func neighbors() -> Array:
	var ids: Array = []
	for id: String in LifeResidentCatalogue.IDS:
		if not app.residents.moved_in(id): ids.append(id)
	return ids

## Why this neighbor cannot be asked, or "".
func guest_reason(id: String) -> String:
	var residents: LifeResidents = app.residents
	var visiting: bool = false
	for visit: LifeHomeVisit in residents.visits():
		if visit.owns(id) or visit.owns_bell(id): visiting = true
	var why: String = LifePartyPlan.guest_error(id, {"moved_in": residents.moved_in(id), "visiting": visiting, "friendly": residents.can_visit(id)})
	if why.is_empty(): why = residents.home_visit.party_requirement(id)
	return why

## Why a party cannot be hosted right now, or "".
func host_reason() -> String:
	if active(): return "A party is already on."
	if str(app.mode) != "live" or str(app.current_venue) != "home": return "Host a party while you are at home in Live mode."
	if app.driving_lesson.running(): return "Wait for the driving lesson to finish before hosting a party."
	if not LifePartyPlan.window_open(float(app.household.minutes)): return "It is too late for a party tonight." if float(app.household.minutes) > LifePartyPlan.WINDOW_CLOSE else "It is too early for a party."
	var any: bool = false
	for id: String in neighbors():
		if guest_reason(id).is_empty(): any = true
	return "" if any else "No neighbor can come right now. Reach 20 friendship with a neighbor first."

## The member whose waiting birthday is the freshest, or "".
func default_celebrant() -> String:
	var best: String = ""
	var best_day: int = -1
	for entry: Dictionary in app.household.pending_birthdays():
		if app.household.member_sim(str(entry.member_id)) != null and int(entry.day) >= best_day:
			best = str(entry.member_id)
			best_day = int(entry.day)
	return best

## Open the planner card. `celebrant` names whose party it is; by default it is a
## member with a recent birthday, or no one in particular.
func show_planner(celebrant: String = "") -> void:
	var why: String = host_reason()
	if not why.is_empty():
		app.show_notice(why)
		return
	app.close_overlay()
	app.overlay_open = true
	app.dismiss_layer()
	planner = {"invited": {}, "potluck": {}, "celebrant": celebrant if app.household.member_sim(celebrant) != null else default_celebrant(), "hours": LifePartyPlan.MAX_HOURS, "music": true}
	_build_card()

func _build_card() -> void:
	var P: Variant = app.P
	_ui.clear()
	var at: Vector2 = CARD_AT
	var card: Panel = app.card(at, CARD_SIZE, P.WHITE, 24, app.overlay)
	card.name = "PartyPlanner"
	app.small_caps("Host a party", at + Vector2(32, 24), Vector2(400, 22), app.overlay)
	app.text_label("Invite your friends over", at + Vector2(30, 46), Vector2(640, 48), 32, P.INK, true, app.overlay)
	app.paragraph("Up to four neighbors who are friends of yours can come. The party runs for up to five game hours, and the guests go home when it ends.", at + Vector2(32, 100), Vector2(636, 46), 15, P.MUTED, app.overlay)
	app.small_caps("Whose party is it?", at + Vector2(32, 154), Vector2(400, 22), app.overlay)
	var chooser: OptionButton = OptionButton.new()
	chooser.name = "PartyCelebrant"
	chooser.add_item("No one in particular")
	chooser.set_item_metadata(0, "")
	var members: Array = []
	for member: Dictionary in app.household.members: members.append(member)
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_wait: bool = not app.household.birthday_entry(str(a.id)).is_empty()
		var b_wait: bool = not app.household.birthday_entry(str(b.id)).is_empty()
		return a_wait and not b_wait)
	var chosen: int = 0
	for member: Dictionary in members:
		var label: String = str(member.sim.character.name)
		if not app.household.birthday_entry(str(member.id)).is_empty(): label += "  ·  birthday"
		chooser.add_item(label)
		chooser.set_item_metadata(chooser.item_count - 1, str(member.id))
		if str(member.id) == str(planner.celebrant): chosen = chooser.item_count - 1
	chooser.select(chosen)
	chooser.item_selected.connect(func(index: int) -> void:
		planner.celebrant = str(chooser.get_item_metadata(index))
		_refresh_card())
	app.rect(chooser, at + Vector2(32, 180), Vector2(636, 42), app.overlay)
	app.small_caps("Who to ask", at + Vector2(32, 232), Vector2(400, 22), app.overlay)
	var ids: Array = neighbors()
	for index: int in ids.size():
		_neighbor_row(str(ids[index]), at + Vector2(32, 256 + 62 * index))
	var base: float = 256.0 + 62.0 * float(ids.size()) + 8.0
	app.small_caps("How long", at + Vector2(32, base), Vector2(200, 22), app.overlay)
	var less: Button = app.button("−", at + Vector2(32, base + 26), Vector2(46, 40), func() -> void: _set_hours(int(planner.hours) - 1), false, app.overlay)
	less.name = "PartyHoursLess"
	var hours: Label = app.text_label("", at + Vector2(86, base + 26), Vector2(150, 40), 20, P.INK, false, app.overlay)
	hours.name = "PartyHours"
	hours.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var more: Button = app.button("+", at + Vector2(244, base + 26), Vector2(46, 40), func() -> void: _set_hours(int(planner.hours) + 1), false, app.overlay)
	more.name = "PartyHoursMore"
	var music: CheckButton = CheckButton.new()
	music.name = "PartyMusic"
	music.text = "Lively party music"
	music.button_pressed = bool(planner.music)
	music.toggled.connect(func(on: bool) -> void: planner.music = on)
	app.rect(music, at + Vector2(340, base + 26), Vector2(330, 40), app.overlay)
	var decor: Label = app.paragraph("", at + Vector2(32, base + 80), Vector2(636, 40), 14, P.MUTED, app.overlay)
	decor.name = "PartyDecor"
	var summary: Label = app.paragraph("", at + Vector2(32, base + 124), Vector2(636, 40), 15, P.INK, app.overlay)
	summary.name = "PartySummary"
	var send: Button = app.button("Send invitations", at + Vector2(32, CARD_SIZE.y - 70), Vector2(300, 48), func() -> void: send(), true, app.overlay)
	send.name = "PartySend"
	var cancel: Button = app.button("Cancel", at + Vector2(348, CARD_SIZE.y - 70), Vector2(320, 48), app.close_overlay, false, app.overlay)
	cancel.name = "PartyCancel"
	_ui = {"hours": hours, "less": less, "more": more, "decor": decor, "summary": summary, "send": send}
	_refresh_card()

func _neighbor_row(id: String, at: Vector2) -> void:
	var P: Variant = app.P
	var why: String = guest_reason(id)
	var row: Panel = app.card(at, Vector2(636, 56), Color("f3f4ed"), 12, app.overlay)
	row.name = "PartyRow_" + id
	var friendship: int = 0
	for member: Dictionary in app.household.members: friendship = maxi(friendship, int(float(member.sim.relationships.get(id, {}).get("friendship", 0))))
	app.text_label(str(LifeResidentCatalogue.PEOPLE[id].name), at + Vector2(14, 5), Vector2(210, 26), 18, P.INK, false, app.overlay)
	var shown: String = "Friendship %d" % friendship
	if not why.is_empty(): shown = "Friendship %d · needs 20" % friendship if friendship < 20 else why
	var detail: Label = app.text_label(shown, at + Vector2(14, 30), Vector2(212, 22), 12, P.MUTED, false, app.overlay)
	detail.clip_text = true
	detail.tooltip_text = why
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	var invite: CheckBox = CheckBox.new()
	invite.name = "PartyInvite_" + id
	invite.text = "Invite"
	invite.disabled = not why.is_empty()
	invite.tooltip_text = why
	app.rect(invite, at + Vector2(232, 13), Vector2(100, 32), app.overlay)
	var dish: CheckBox = CheckBox.new()
	dish.name = "PartyPotluck_" + id
	dish.text = "Brings %s" % LifePartyPlan.potluck_label(id)
	dish.disabled = true
	dish.tooltip_text = "They make it at home first and set it on the party table to share."
	app.rect(dish, at + Vector2(338, 13), Vector2(290, 32), app.overlay)
	invite.toggled.connect(func(on: bool) -> void:
		planner.invited[id] = on
		if not on:
			planner.potluck[id] = false
			dish.set_pressed_no_signal(false)
		dish.disabled = not on
		_refresh_card())
	dish.toggled.connect(func(on: bool) -> void:
		planner.potluck[id] = on
		_refresh_card())

func _set_hours(hours: int) -> void:
	planner.hours = LifePartyPlan.clamp_hours(hours)
	_refresh_card()

## Update what the card says about the choices made so far.
func _refresh_card() -> void:
	if _ui.is_empty() or not is_instance_valid(_ui.get("send")): return
	var hours: int = LifePartyPlan.clamp_hours(planner.hours)
	(_ui.hours as Label).text = "%d %s" % [hours, "hour" if hours == 1 else "hours"]
	(_ui.less as Button).disabled = hours <= LifePartyPlan.MIN_HOURS
	(_ui.more as Button).disabled = hours >= LifePartyPlan.MAX_HOURS
	var score: int = app.world.festive_count(0)
	(_ui.decor as Label).text = "Your home has %d festive %s. Guests arrive in better spirits, and so does the household." % [score, "touch" if score == 1 else "touches"] if score > 0 else "No decorations yet. Balloons and streamers from the Party tab of Build & buy, and a festive cloth on a dining table, make a party feel like one."
	var chosen: Array = invited_ids()
	var why: String = _send_reason(chosen)
	if chosen.is_empty(): why = "Tick the friends you would like to ask."
	var summary: String = ""
	if why.is_empty():
		var names: Array[String] = []
		for id: String in chosen: names.append(_first(id))
		var dishes_count: int = 0
		for id: String in chosen:
			if bool(planner.potluck.get(id, false)): dishes_count += 1
		summary = "%s will come. %s" % [", ".join(names), "%d %s bringing a dish." % [dishes_count, "friend is" if dishes_count == 1 else "friends are"] if dishes_count > 0 else "Nobody is bringing a dish."]
	else:
		summary = why
	(_ui.summary as Label).text = summary
	(_ui.send as Button).disabled = not why.is_empty()

## The neighbors ticked on the card, in card order.
func invited_ids() -> Array:
	var chosen: Array = []
	for id: String in neighbors():
		if bool(planner.get("invited", {}).get(id, false)): chosen.append(id)
	return chosen

func _send_reason(chosen: Array) -> String:
	var errors: Dictionary = {}
	for id: Variant in chosen: errors[str(id)] = guest_reason(str(id))
	return LifePartyPlan.send_error({"party_on": active(), "at_home": str(app.mode) == "live" and str(app.current_venue) == "home", "minutes": float(app.household.minutes), "guests": chosen, "errors": errors})

## Send the invitations: write the party record and start the friends going.
func send() -> Dictionary:
	if planner.is_empty(): return {"ok": false, "error": "Open the party card first."}
	var chosen: Array = invited_ids()
	var why: String = _send_reason(chosen)
	if not why.is_empty():
		app.show_notice(why)
		return {"ok": false, "error": why}
	var household: LifeHousehold = app.household
	var invited: Array = []
	for id: Variant in chosen: invited.append({"id": str(id), "potluck": bool(planner.potluck.get(str(id), false))})
	var serial: int = household.party_serial + 1
	var celebrant: String = str(planner.get("celebrant", ""))
	household.party_serial = serial
	household.party = LifePartyPlan.build(serial, household.selected_id(), celebrant, now(), int(planner.hours), bool(planner.music), invited)
	# A birthday that is waiting for its cake is now part of the party.
	var waiting: Dictionary = household.birthday_entry(celebrant) if not celebrant.is_empty() else {}
	if not waiting.is_empty(): waiting["party_serial"] = serial
	_was_on = true
	_retry.clear()
	var names: Array[String] = []
	for entry: Dictionary in household.party.guests:
		names.append(_first(str(entry.id)))
		if not str(entry.potluck).is_empty(): _tell("%s is making %s to bring." % [_first(str(entry.id)), LifePartyPlan.potluck_label(str(entry.id))])
	_tell("Invitations are out. %s %s on the way." % [_join(names), "is" if names.size() == 1 else "are"])
	app.close_overlay()
	planner.clear()
	_clock = 0.0
	_advance()
	refresh_status()
	return {"ok": true, "serial": serial}

func _join(names: Array[String]) -> String:
	if names.size() <= 1: return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]


## ---- The party card on the screen

func _status_clear() -> void:
	if is_instance_valid(status_card): status_card.queue_free()
	status_card = null

## The line the party card shows.
func status_line() -> String:
	var record: Dictionary = party()
	var found: Dictionary = LifePartyPlan.counts(record)
	var ends: String = LifePartyPlan.clock_text(float(record.ends_at))
	var coming: int = int(found.preparing) + int(found.walking)
	var expected: int = 0
	for entry: Dictionary in record.guests:
		if str(entry.status) != "left" or bool(entry.get("came", false)): expected += 1
	match str(record.phase):
		"inviting": return "Party · waiting for %d %s · ends %s" % [coming, "friend" if coming == 1 else "friends", ends]
		"ending": return "Party · winding down · %d here" % int(found.inside)
	return "Party · %d of %d guests here · ends %s" % [int(found.inside), expected, ends]

## Keep the party card up to date, making it if it is missing. Returns whether a
## party card is showing (the ordinary guest card then stays away).
func refresh_status() -> bool:
	if not active() or str(app.mode) != "live":
		_status_clear()
		return false
	if not is_instance_valid(status_card):
		var P: Variant = app.P
		status_card = app.card(STATUS_AT, STATUS_SIZE, P.WHITE, 16)
		status_card.name = "PartyStatus"
		status_text = app.text_label("", Vector2(14, 6), Vector2(346, 34), 15, P.INK, true, status_card)
		status_text.name = "PartyStatusText"
		status_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_end = app.button("End the party", Vector2(14, 44), Vector2(166, 36), func() -> void: end_party(), true, status_card)
		status_end.name = "PartyEnd"
		status_music = app.button("", Vector2(192, 44), Vector2(168, 36), func() -> void: set_music(not bool(party().music)), false, status_card)
		status_music.name = "PartyMusicToggle"
		var hint: Label = app.text_label("", Vector2(14, 86), Vector2(346, 24), 13, P.MUTED, false, status_card)
		hint.name = "PartyStatusHint"
	var record: Dictionary = party()
	status_text.text = status_line()
	status_music.text = "Music on" if bool(record.music) else "Music off"
	status_end.disabled = str(record.phase) == "ending"
	var dishes_total: int = 0
	var dishes_set: int = 0
	for entry: Dictionary in record.guests:
		if str(entry.potluck).is_empty(): continue
		dishes_total += 1
		if not str(entry.batch).is_empty(): dishes_set += 1
	var score: int = app.world.festive_count(0)
	var hint_text: String = "%d festive %s" % [score, "touch" if score == 1 else "touches"]
	if dishes_total > 0: hint_text += " · dishes %d of %d on the table" % [dishes_set, dishes_total]
	(status_card.get_node("PartyStatusHint") as Label).text = hint_text
	return true
