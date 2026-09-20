extends RefCounted
class_name LifeGroceries
## The household's weekly shop, ordered online and delivered.
##
## A household used to feed itself straight from the fridge: a snack or a recipe
## was charged for at the moment of cooking, with no store and no delivery. The
## brief asks for the opposite — the fridge stops selling food, and the kitchen
## is restocked by ordering a delivery from the computer, which arrives by van.
##
## A delivery is bought as an order, held as a pending record, and collected when
## its van reaches the door. Until it arrives the kitchen is genuinely empty, so
## a household that forgot to order eats out, visits the shopping centre, or
## waits for the van.
##
## Pure policy — no Nodes, no clock, no wallet. The household owns the order.

## What one delivery holds, and what it costs. A weekly shop is a real basket:
## enough for a household's meals for several days, priced below buying each
## meal separately, which is the point of doing one big order.
const BASKET_MEALS: int = 12
const BASKET_PRICE: int = 68

## The bigger basket, for a household that would rather shop less often.
const LARGE_BASKET_MEALS: int = 24
const LARGE_BASKET_PRICE: int = 120

## The one-person basket.
const SMALL_BASKET_MEALS: int = 6
const SMALL_BASKET_PRICE: int = 38

## What the fridge holds at most, so a household cannot bank an unbounded pantry.
const FRIDGE_CAPACITY: int = 36

## How many game minutes a delivery takes to arrive. Ordered in the morning it
## arrives the same afternoon; ordered in the evening it comes the next day, so
## a household cannot shop and cook in the same minute.
const DELIVERY_MINUTES: int = 180

## The delivery window: an order placed after this hour arrives the next day.
const LAST_ORDER_MINUTE: int = 1080

## The van's own identity, so the world can tell a grocery delivery from any
## other visitor. It carries an organic sign: three leaves on a cream panel.
const VAN_LABEL: String = "Organic delivery van"
const VAN_SIGN_LEAVES: int = 3

## Every basket a household may order, in the order the computer should show
## them. `size` is what it fills the fridge by, `price` what it costs.
const BASKETS: Dictionary = {
	"small": {"label": "A small order", "meals": SMALL_BASKET_MEALS, "price": SMALL_BASKET_PRICE,
		"description": "Six meals' worth of groceries. Enough for one Lifelet for a couple of days, and the cheapest way to keep the kitchen stocked."},
	"weekly": {"label": "The weekly shop", "meals": BASKET_MEALS, "price": BASKET_PRICE,
		"description": "Twelve meals' worth of groceries: a full week's shop for a small household, delivered in one van."},
	"large": {"label": "The big shop", "meals": LARGE_BASKET_MEALS, "price": LARGE_BASKET_PRICE,
		"description": "Twenty-four meals' worth of groceries. For a full house, or a household that would rather shop less often."},
}

const ORDER: Array[String] = ["small", "weekly", "large"]


## A household's grocery record: what is in the fridge, and the delivery that is
## on its way.
static func fresh() -> Dictionary:
	return {"version": 1, "stock": 0, "order": {}}


static func baskets() -> Array[String]:
	return ORDER.duplicate()


static func basket(basket_id: String) -> Dictionary:
	return (BASKETS.get(basket_id, {}) as Dictionary).duplicate(true)


static func has_basket(basket_id: String) -> bool:
	return BASKETS.has(basket_id)


## What is in the fridge now, in meals.
static func stock(state: Dictionary) -> int:
	return maxi(0, int(state.get("stock", 0)))


## Whether a delivery is already on its way.
static func pending(state: Dictionary) -> Dictionary:
	return (state.get("order", {}) as Dictionary).duplicate(true)


static func has_order(state: Dictionary) -> bool:
	return not pending(state).is_empty()


## Why this basket cannot be ordered, as the player-readable reason. Empty means
## it may go ahead. The computer panel and the order read this one answer.
static func order_error(state: Dictionary, basket_id: String, funds: int) -> String:
	if not has_basket(basket_id):
		return "That is not something the shop delivers."
	if has_order(state):
		return "A delivery is already on its way. It arrives on day %d." % int(pending(state).get("day", 0))
	var price: int = int(basket(basket_id).price)
	if funds < price:
		return "That shop costs ℒ%d and the household needs ℒ%d more." % [price, price - funds]
	return ""


## Order a delivery. The purse pays, and the van is given its own arrival day and
## minute: ordered after the last slot, it comes tomorrow.
static func order(state: Dictionary, basket_id: String, funds: int, day: int, minutes: float) -> Dictionary:
	var reason: String = order_error(state, basket_id, funds)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var price: int = int(basket(basket_id).price)
	var meals: int = int(basket(basket_id).meals)
	var arrive_day: int = day
	var arrive_minutes: int = int(minutes) + DELIVERY_MINUTES
	if int(minutes) >= LAST_ORDER_MINUTE:
		arrive_day = day + 1
		arrive_minutes = int(minutes) + DELIVERY_MINUTES - 1440
	var after: Dictionary = state.duplicate(true)
	after["order"] = {
		"basket": basket_id, "meals": meals, "price": price,
		"day": arrive_day, "minutes": arrive_minutes, "placed_day": day,
	}
	return {"ok": true, "state": after, "cost": price, "funds": funds - price,
		"meals": meals, "day": arrive_day, "minutes": arrive_minutes}


## Whether the van has arrived by this moment.
static func arrival_due(state: Dictionary, day: int, minutes: float) -> bool:
	if not has_order(state):
		return false
	var record: Dictionary = pending(state)
	if day > int(record.get("day", 0)):
		return true
	if day < int(record.get("day", 0)):
		return false
	return minutes >= float(record.get("minutes", 0))


## Take the delivery in: the order empties into the fridge, capped at what the
## fridge holds, and the pending record is cleared. Returns what was actually
## put away, so the notice can say if anything had to be left with the driver.
static func collect(state: Dictionary) -> Dictionary:
	if not has_order(state):
		return {"ok": false, "error": "No delivery is waiting."}
	var record: Dictionary = pending(state)
	var room: int = FRIDGE_CAPACITY - stock(state)
	var stored: int = mini(int(record.get("meals", 0)), maxi(0, room))
	var after: Dictionary = state.duplicate(true)
	after["stock"] = stock(state) + stored
	after["order"] = {}
	return {"ok": true, "state": after, "meals": stored,
		"basket": str(record.get("basket", "")), "left": maxi(0, int(record.get("meals", 0)) - stored)}


## Take a meal out of the fridge to cook or eat. Returns the new state, or a
## refusal when the kitchen is empty.
static func take_meal(state: Dictionary) -> Dictionary:
	if stock(state) <= 0:
		return {"ok": false, "error": "The kitchen is empty. Order a delivery from the computer, or from the fridge."}
	var after: Dictionary = state.duplicate(true)
	after["stock"] = stock(state) - 1
	return {"ok": true, "state": after, "remaining": int(after.stock)}


## Whether the kitchen has anything to cook with.
static func can_cook(state: Dictionary) -> bool:
	return stock(state) > 0


## What the kitchen holds, as the player reads it.
static func describe(state: Dictionary) -> String:
	var held: int = stock(state)
	var on_way: Dictionary = pending(state)
	var text: String = "The kitchen is empty." if held == 0 else ("%d %s in the kitchen." % [held, "meal" if held == 1 else "meals"])
	if not on_way.is_empty():
		text += " A delivery of %d meals arrives on day %d." % [int(on_way.get("meals", 0)), int(on_way.get("day", 0))]
	return text


## Whether the kitchen is low enough to be worth shopping for. A household whose
## fridge is already full is refused an order it does not need, so neither the
## computer nor the fridge offers a delivery nobody wants.
const WELL_STOCKED_MEALS: int = 6

## The largest basket the purse can afford, or "" when none is affordable. A
## household shopping from the kitchen buys as much as it can rather than the
## smallest order, which is what makes one big shop worth doing.
static func best_basket_for(state: Dictionary, funds: int) -> String:
	for basket_id: String in ["large", "weekly", "small"]:
		if order_error(state, basket_id, funds).is_empty():
			return basket_id
	return ""


## Whether the fridge is stocked enough that a shop would be wasted.
static func needs_restock(state: Dictionary) -> bool:
	return stock(state) < WELL_STOCKED_MEALS


## Validate a saved grocery record, so a corrupt one cannot mint free food or
## strand a household with a delivery that never arrives.
static func validate(value: Variant) -> String:
	if value == null:
		return ""
	if not value is Dictionary:
		return "Save contains an invalid grocery record."
	var state: Dictionary = value
	if int(state.get("version", 0)) != 1:
		return "The saved grocery record uses an unsupported version."
	var held: Variant = state.get("stock", 0)
	if not (held is int or held is float) or not is_finite(float(held)) or float(held) != floorf(float(held)) or int(held) < 0 or int(held) > FRIDGE_CAPACITY:
		return "Save contains an impossible amount of food in the kitchen."
	var order: Variant = state.get("order", {})
	if not order is Dictionary:
		return "Save contains an invalid delivery."
	if not order.is_empty():
		if not has_basket(str(order.get("basket", ""))):
			return "Save contains a delivery of an unknown basket."
		var meals: Variant = order.get("meals", 0)
		if not (meals is int or meals is float) or float(meals) != floorf(float(meals)) or int(meals) < 0 or int(meals) > LARGE_BASKET_MEALS:
			return "Save contains a delivery of an impossible size."
		if not (order.get("day") is int or order.get("day") is float) or int(order.get("day", 0)) < 1:
			return "Save contains a delivery with an impossible day."
		if int(order.get("minutes", -1)) < 0 or int(order.get("minutes", 0)) > 1439:
			return "Save contains a delivery at an impossible time."
	if state.size() > 3:
		return "Save contains an unknown grocery field."
	return ""


## Normalise a saved record, so a save from before groceries simply has an empty
## kitchen and no delivery on its way.
static func from_save(value: Variant) -> Dictionary:
	if not value is Dictionary or not validate(value).is_empty():
		return fresh()
	var state: Dictionary = fresh()
	state["stock"] = stock(value)
	state["order"] = (value.get("order", {}) as Dictionary).duplicate(true)
	return state
