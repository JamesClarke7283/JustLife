extends RefCounted
## The party food platter: eight servings that Lifelets take one at a time, refilled for a
## fee. The platter keeps its own count (`servings` on its layout record, shown as that
## many servings on the model) rather than drawing on the fridge, so a party table is
## stocked by buying and refilling the platter.
##
## This file holds the rules; the sim asks `reason` for availability and the app calls
## `finished` when an action ends. Dishes friends bring along are the meal ledger's
## business (LifeMeals.place_batch, LifeMealFlow.place_potluck), not this platter's.

const EAT: String = "eat_party_food"
const REFILL: String = "refill_party_food"
const IDS: Array[String] = [EAT, REFILL]
const REFILL_COST: int = 30


## How many servings a full platter holds.
static func capacity() -> int:
	return int(LifeCatalog.get_item("party_food").get("servings", 8))


## A saved or supplied count made safe: whole, finite and between none and `limit`.
## Anything that is not a number is a full platter, as a new one is.
static func clean(value: Variant, limit: int) -> int:
	if (value is int or value is float) and is_finite(float(value)):
		return clampi(int(value), 0, limit)
	return limit


## Why `id` cannot be done at a furnishing of this kind holding `servings`, or "" when
## it can. `funds` only matters to a refill, which is paid when it starts.
static func reason(id: String, kind: String, servings: int, funds: int) -> String:
	if kind != "party_food":
		return "Choose a party food platter."
	if id == EAT:
		return "The platter is empty. Refill it for ℒ%d." % REFILL_COST if servings <= 0 else ""
	if servings >= capacity():
		return "The platter is already full."
	if funds < REFILL_COST:
		return "Requires ℒ%d." % REFILL_COST
	return ""


## The platter's bookkeeping when an eat or refill finishes: one serving fewer, or a full
## platter again. The sims learn the new count on the next target refresh.
static func finished(app: Node, action: Dictionary) -> void:
	var id: String = str(action.get("id", ""))
	if not id in IDS:
		return
	var target: String = str(action.get("target_id", ""))
	var item: Dictionary = app._find_item(target)
	if item.is_empty() or str(item.get("kind", "")) != "party_food":
		return
	var left: int = capacity() if id == REFILL else maxi(0, int(item.get("servings", 0)) - 1)
	app.world.set_party_servings(target, left)
	if id == EAT and left == 0:
		app.show_notice("The party food platter is empty. Refill it for ℒ%d from its menu." % REFILL_COST)
	elif id == REFILL:
		app.show_notice("The party food platter is full again.")
	app.call_deferred("_refresh_sim_targets", false, false)
