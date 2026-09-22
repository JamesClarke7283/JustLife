extends RefCounted
class_name LifeProperties
## The households a player owns: the houses they can live in, the insurance on
## each one, and what it costs to move between them.
##
## A household is not tied to one building. It can own several homes, live in one
## at a time, move mid-game, and hold a separate policy on each — because a
## second home is a real property with its own roof, its own burglar and its own
## premium, not a copy of the first.
##
## The *active* home is the one the world is currently built from. Everything
## else is a saved layout plus its own land and its own insurance, waiting to be
## moved into.
##
## `LifeCatalog.starter_layout` owns what each house type contains; this owns
## which houses exist, what they cost, and which one is lived in.
##
## Pure policy — no Nodes, no clock, no wallet.

## The house types a player may choose at the start, or buy later. `layout` names
## the starter layout in `LifeCatalog`; `price` is what the house itself costs to
## buy when moving into a second one.
const TYPES: Dictionary = {
	"willow": {
		"label": "Willow Cottage", "layout": 0, "price": 0,
		"tagline": "A furnished start, with room to grow.",
		"description": "A one-bed cottage, fully furnished, with a garden on three sides. The easiest place to begin and the simplest to extend.",
		"rooms": 4, "beds": 1, "baths": 1,
	},
	"sage": {
		"label": "Sage House", "layout": 1, "price": 0,
		"tagline": "A creative home for your next chapter.",
		"description": "A one-bed home laid out around a wide living room and a studio corner, with the bathroom and kitchen along the back wall.",
		"rooms": 4, "beds": 1, "baths": 1,
	},
	"canvas": {
		"label": "A Fresh Canvas", "layout": 2, "price": 0,
		"tagline": "The essentials. You bring the ideas.",
		"description": "An almost empty shell with a bed, a bathroom, a kitchen and a wardrobe. Cheaper up front and free to shape into whatever you want.",
		"rooms": 2, "beds": 1, "baths": 1,
	},
	"rowan": {
		"label": "Rowan Villa", "layout": 3, "price": 48000,
		"tagline": "Room for a growing household.",
		"description": "A larger furnished home with two separate bedrooms, a wide kitchen and a double-length garden. Bought when the household outgrows its first house.",
		"rooms": 6, "beds": 2, "baths": 1,
	},
	"juniper": {
		"label": "Juniper House", "layout": 4, "price": 96000,
		"tagline": "The largest house on the street.",
		"description": "Four bedrooms, two bathrooms, a formal dining room and a garden the full width of its plot. The most house the game sells.",
		"rooms": 9, "beds": 4, "baths": 2,
	},
}

## The order a picker should offer the types in: cheapest and simplest first.
const ORDER: Array[String] = ["willow", "sage", "canvas", "rowan", "juniper"]

## What moving into a house the household already owns costs, on top of the
## house's own price. A move is a real expense, so moving is a decision.
const MOVING_FEE: int = 1200

## Every policy a house may carry. It mirrors `LifeSim.INSURANCE_POLICIES` in
## spirit but is keyed per property, so two houses can be covered differently.
const POLICIES: Dictionary = {
	"home": {"label": "Home insurance", "premium": 600},
	"premium": {"label": "Premium home insurance", "premium": 900, "payout_multiple": 1.5},
	"baby": {"label": "Baby & Child Insurance", "premium": 500},
}

## The most houses one household may own, so a save cannot grow without bound.
const MAX_HOUSES: int = 8


static func fresh() -> Dictionary:
	return {"version": 1, "active": "", "houses": {}}


static func types() -> Array[String]:
	return ORDER.duplicate()


static func type_info(type_id: String) -> Dictionary:
	return TYPES.get(type_id, {}).duplicate(true)


static func has_type(type_id: String) -> bool:
	return TYPES.has(type_id)


static func label(type_id: String) -> String:
	return str(type_info(type_id).get("label", type_id.capitalize()))


## What one house type costs to buy outright, before any moving fee.
static func price(type_id: String) -> int:
	return int(type_info(type_id).get("price", 0))


## Whether a type is one a household may start in. The starter homes are the
## free ones; a bought house is something a household moves into later.
static func is_starter(type_id: String) -> bool:
	return has_type(type_id) and price(type_id) <= 0


## Every starter type, in the order the opening picker should show them.
static func starters() -> Array[String]:
	var result: Array[String] = []
	for type_id: String in ORDER:
		if is_starter(type_id): result.append(type_id)
	return result


## The house records a household owns. The first house is granted at the start
## and is never bought.
static func houses(state: Dictionary) -> Dictionary:
	return state.get("houses", {})


static func owns(state: Dictionary, house_id: String) -> bool:
	return houses(state).has(house_id)


static func count(state: Dictionary) -> int:
	return houses(state).size()


## The house currently lived in.
static func active(state: Dictionary) -> String:
	return str(state.get("active", ""))


## The record of one owned house, or an empty dictionary.
static func house(state: Dictionary, house_id: String) -> Dictionary:
	return (houses(state).get(house_id, {}) as Dictionary).duplicate(true)


## Grant a house to the household and make it the one lived in. Used for the
## house a household starts in.
static func grant(state: Dictionary, house_id: String, type_id: String, land: Dictionary = {}) -> Dictionary:
	if not has_type(type_id):
		return {"ok": false, "error": "That is not a kind of house this game sells."}
	if houses(state).has(house_id):
		return {"ok": false, "error": "This household already owns a house with that name."}
	if count(state) >= MAX_HOUSES:
		return {"ok": false, "error": "A household may own at most %d houses." % MAX_HOUSES}
	var after: Dictionary = state.duplicate(true)
	after["houses"][house_id] = {
		"id": house_id, "type": type_id, "land": land.duplicate(true),
		"policy": "", "layout": [], "name": label(type_id),
	}
	after["active"] = house_id
	return {"ok": true, "state": after}


## Why this house type cannot be bought and moved into, as the player-readable
## reason. Empty means the move may go ahead. The picker and the move read this
## one answer, so a greyed-out button and a refused call never differ.
static func move_error(state: Dictionary, type_id: String, funds: int, house_id: String = "") -> String:
	if not has_type(type_id):
		return "That is not a kind of house this game sells."
	var target_id: String = house_id if not house_id.is_empty() else type_id
	if active(state) == target_id and owns(state, target_id):
		return "The household already lives in this house."
	var cost: int = move_cost(state, type_id, house_id)
	if funds < cost:
		return "Buying this house and moving in costs ℒ%d and needs ℒ%d more." % [cost, cost - funds]
	if not owns(state, target_id) and count(state) >= MAX_HOUSES:
		return "A household may own at most %d houses." % MAX_HOUSES
	return ""


## What buying this house and moving in costs in total: the house's own price
## when the household does not own it yet, plus the moving fee.
static func move_cost(state: Dictionary, type_id: String, house_id: String = "") -> int:
	var target_id: String = house_id if not house_id.is_empty() else type_id
	var cost: int = MOVING_FEE
	if not owns(state, target_id):
		cost += price(type_id)
	return cost


## Buy a house (if not already owned) and move the household into it. The purse
## pays once, and the previously active house keeps its own land and policy for
## whenever the household moves back.
static func move_into(state: Dictionary, type_id: String, funds: int, house_id: String = "", land: Dictionary = {}) -> Dictionary:
	var reason: String = move_error(state, type_id, funds, house_id)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	if not has_type(type_id):
		return {"ok": false, "error": "That is not a kind of house this game sells."}
	var target_id: String = house_id if not house_id.is_empty() else type_id
	var cost: int = move_cost(state, type_id, house_id)
	var after: Dictionary = state.duplicate(true)
	if not owns(after, target_id):
		after["houses"][target_id] = {
			"id": target_id, "type": type_id, "land": land.duplicate(true),
			"policy": "", "layout": [], "name": label(type_id),
		}
	else:
		# An owned house is kept as it was left: its own land and its own policy.
		after["houses"][target_id]["type"] = type_id
	after["active"] = target_id
	return {"ok": true, "state": after, "cost": cost, "funds": funds - cost, "house_id": target_id, "type": type_id, "bought": not owns(state, target_id)}


## What moving out of a house and into one already owned costs. Cheaper than
## buying, because only the move is paid for.
static func moving_fee() -> int:
	return MOVING_FEE


## The policy in force on one house, or an empty dictionary.
static func policy(state: Dictionary, house_id: String) -> Dictionary:
	var held: String = str(house(state, house_id).get("policy", ""))
	if held.is_empty() or not POLICIES.has(held):
		return {}
	return {"id": held, "label": str(POLICIES[held].label), "premium": int(POLICIES[held].premium)}


## Buy the named policy on one house. Each house carries its own cover, so a
## second home is insured separately from the first. Baby & Child cover is an
## add-on kept on `baby_policy` so it can sit beside burglar cover.
static func buy_policy(state: Dictionary, house_id: String, policy_id: String, funds: int) -> Dictionary:
	if not owns(state, house_id):
		return {"ok": false, "error": "This household does not own that house."}
	if not POLICIES.has(policy_id):
		return {"ok": false, "error": "That is not a policy this game sells."}
	var premium: int = int(POLICIES[policy_id].premium)
	if funds < premium:
		return {"ok": false, "error": "That cover costs ℒ%d and needs ℒ%d more." % [premium, premium - funds]}
	var after: Dictionary = state.duplicate(true)
	if policy_id == "baby":
		if not str(house(state, house_id).get("baby_policy", "")).is_empty():
			return {"ok": false, "error": "Baby & Child Insurance is already in force on this home."}
		after["houses"][house_id]["baby_policy"] = "baby"
		return {"ok": true, "state": after, "cost": premium, "funds": funds - premium}
	var existing: Dictionary = policy(state, house_id)
	if not existing.is_empty():
		return {"ok": false, "error": "%s is already insured for ℒ%d a term. Cancel it first to change cover." % [str(house(state, house_id).get("name", "This house")), int(existing.premium)]}
	after["houses"][house_id]["policy"] = policy_id
	return {"ok": true, "state": after, "cost": premium, "funds": funds - premium}


static func cancel_policy(state: Dictionary, house_id: String) -> Dictionary:
	if not owns(state, house_id):
		return {"ok": false, "error": "This household does not own that house."}
	if policy(state, house_id).is_empty():
		return {"ok": false, "error": "This house is not insured."}
	var after: Dictionary = state.duplicate(true)
	after["houses"][house_id]["policy"] = ""
	return {"ok": true, "state": after}


## Every house the household owns, as the player reads them in the property
## list: which is lived in, its type, its insurance and its size of land.
static func offers(state: Dictionary, funds: int) -> Array:
	var result: Array = []
	var owned: Dictionary = houses(state)
	for house_id: String in ORDER:
		var type_id: String = house_id
		if not has_type(type_id): continue
		var info: Dictionary = type_info(type_id)
		var is_owned: bool = owned.has(type_id)
		var reason: String = move_error(state, type_id, funds)
		result.append({
			"id": type_id, "label": str(info.label), "tagline": str(info.tagline),
			"description": str(info.description), "price": price(type_id),
			"cost": move_cost(state, type_id),
			"rooms": int(info.rooms), "beds": int(info.beds), "baths": int(info.baths),
			"owned": is_owned, "current": active(state) == type_id,
			"policy": policy(state, type_id),
			"available": reason.is_empty(), "reason": reason,
		})
	for house_id: String in owned:
		if has_type(house_id): continue
		var record: Dictionary = owned[house_id]
		result.append({
			"id": house_id, "label": str(record.get("name", house_id)), "tagline": "",
			"description": "A home this household already owns.", "price": 0,
			"cost": MOVING_FEE, "rooms": 0, "beds": 0, "baths": 0,
			"owned": true, "current": active(state) == house_id,
			"policy": policy(state, house_id),
			"available": move_error(state, str(record.get("type", "")), funds, house_id).is_empty(),
			"reason": move_error(state, str(record.get("type", "")), funds, house_id),
		})
	return result


## Validate a saved property record. An unknown house or policy, or an active
## house the household does not own, would otherwise let a corrupt save mint a
## free home or a free payout.
static func validate(value: Variant) -> String:
	if value == null:
		return ""
	if not value is Dictionary:
		return "Save contains an invalid property record."
	var state: Dictionary = value
	if int(state.get("version", 0)) != 1:
		return "The saved property record uses an unsupported version."
	if not state.get("houses") is Dictionary:
		return "Save contains an invalid house list."
	if state.houses.size() > MAX_HOUSES:
		return "Save contains more houses than a household may own."
	for house_id: Variant in state.houses:
		if not house_id is String or str(house_id).is_empty() or str(house_id).length() > 100:
			return "Save contains an invalid house identity."
		var record: Variant = state.houses[house_id]
		if not record is Dictionary:
			return "Save contains an invalid house record."
		if not has_type(str(record.get("type", ""))):
			return "Save contains an unknown kind of house."
		var held: String = str(record.get("policy", ""))
		if not held.is_empty() and not POLICIES.has(held):
			return "Save contains an unknown policy on a house."
		if not record.get("land", {}) is Dictionary:
			return "Save contains invalid land on a house."
		if not record.get("layout", []) is Array:
			return "Save contains an invalid saved layout on a house."
	var active_id: String = str(state.get("active", ""))
	if not active_id.is_empty() and not state.houses.has(active_id):
		return "Save is living in a house the household does not own."
	if state.size() > 3:
		return "Save contains an unknown property field."
	return ""


## Normalise a saved record, so a save made before houses existed simply owns
## the house it was started in.
static func from_save(value: Variant) -> Dictionary:
	if not value is Dictionary or not validate(value).is_empty():
		return fresh()
	var state: Dictionary = fresh()
	state["active"] = str(value.get("active", ""))
	state["houses"] = (value.get("houses", {}) as Dictionary).duplicate(true)
	return state


## A player-readable summary of what the household owns.
static func describe(state: Dictionary) -> String:
	var owned: int = count(state)
	if owned == 0:
		return "No home owned."
	var lived: String = str(house(state, active(state)).get("name", "a home"))
	if owned == 1:
		return "Living in %s." % lived
	return "Living in %s, with %d other %s owned." % [lived, owned - 1, "house" if owned - 1 == 1 else "houses"]
