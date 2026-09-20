extends RefCounted
class_name LifeLand
## The household's land: the plot the house stands on, and the neighbours' plots
## it can buy and build on.
##
## The lot is a rectangle that grows outward one plot at a time, without limit.
## Everything that has to agree on how far the ground reaches — building
## validation, floor support, the navigation graph, the compatibility grid, the
## camera pan and the garden dressing — reads `LifeLand.rect()`, so buying a plot
## really moves the boundary for all of them at once rather than only drawing
## more grass.
##
## The street stays where it is. The lot grows west, east and north; the south
## edge is the frontage, and the sidewalk, doorstep and every walk to the lot
## exit are anchored to it.
##
## Pure policy — no Nodes, no clock, no wallet. The household owns the purchase.

## The plot a household starts with. The house sits at x -6..6, z -5..5, with
## the front sidewalk at z 8.5 and 9 m of garden behind it.
const BASE := Rect2(-18, -12, 36, 21)

## What one bought plot measures. A side plot is as deep as the lot and 12 m
## wide; a back plot is as wide as the lot and 10 m deep, so plots tile the
## ground rather than leaving gaps between them.
const PLOT_WIDTH: float = 12.0
const PLOT_DEPTH: float = 10.0

## The sides a plot can be bought on. The front is the street, so it is not one
## of them.
const SIDES: Array[String] = ["west", "east", "north"]

## What the first plot on a side costs, and what each further plot on the same
## side adds. Land gets dearer the further out it is, so expanding indefinitely
## is possible but never cheap.
const PLOT_PRICE_BASE: int = 6000
const PLOT_PRICE_STEP: int = 2500

## How many plots can be bought on one side. It exists only to keep the saved
## counters and the derived rectangle inside sane numbers; it is far beyond any
## household's means, so the lot is effectively unlimited.
const MAX_PLOTS_PER_SIDE: int = 400

## The most a lot may measure in either direction, so a corrupt save cannot ask
## for a navigation grid no machine can build.
const MAX_SPAN: float = 20000.0


static func fresh() -> Dictionary:
	return {"version": 1, "west": 0, "east": 0, "north": 0}


static func _count(state: Dictionary, side: String) -> int:
	return clampi(int(state.get(side, 0)), 0, MAX_PLOTS_PER_SIDE)


## The whole lot: the starting plot grown by every plot bought on each side.
static func rect(state: Dictionary = {}) -> Rect2:
	var west: int = _count(state, "west")
	var east: int = _count(state, "east")
	var north: int = _count(state, "north")
	var low := Vector2(BASE.position.x - PLOT_WIDTH * float(west), BASE.position.y - PLOT_DEPTH * float(north))
	var high := Vector2(BASE.end.x + PLOT_WIDTH * float(east), BASE.end.y)
	return Rect2(low, high - low)


## How many plots have been bought in total.
static func plots(state: Dictionary) -> int:
	return _count(state, "west") + _count(state, "east") + _count(state, "north")


## The rectangle one further plot on this side would cover, for the preview the
## player sees before paying.
static func next_plot(state: Dictionary, side: String) -> Rect2:
	if not SIDES.has(side):
		return Rect2()
	var grown: Dictionary = state.duplicate()
	grown[side] = _count(state, side) + 1
	var whole: Rect2 = rect(grown)
	var current: Rect2 = rect(state)
	# The strip the new plot adds is the difference between the two rectangles.
	var low := Vector2(minf(whole.position.x, current.position.x), minf(whole.position.y, current.position.y))
	var high := Vector2(maxf(whole.end.x, current.end.x), maxf(whole.end.y, current.end.y))
	return Rect2(low, high - low)


## What the next plot on this side costs. Each further plot on the same side is
## dearer than the last, so land is a real investment.
static func price(state: Dictionary, side: String) -> int:
	if not SIDES.has(side):
		return 0
	return PLOT_PRICE_BASE + PLOT_PRICE_STEP * _count(state, side)


## Why the next plot on this side cannot be bought, as the player-readable
## reason. Empty means the purchase may go ahead. The picker and the purchase
## read this one answer, so a greyed-out button and a refused call never differ.
static func purchase_error(state: Dictionary, side: String, funds: int) -> String:
	if not SIDES.has(side):
		return "That side of the lot faces the street and cannot be bought."
	if _count(state, side) >= MAX_PLOTS_PER_SIDE:
		return "This side of the lot cannot grow any further."
	var cost: int = price(state, side)
	if funds < cost:
		return "The next plot on that side costs ℒ%d and needs ℒ%d more." % [cost, cost - funds]
	if rect(state).size.x + PLOT_WIDTH > MAX_SPAN or rect(state).size.y + PLOT_DEPTH > MAX_SPAN:
		return "This lot cannot grow any further."
	return ""


## Every side the player may expand on, with its price and its own refusal. One
## list, so the picker and the purchase agree.
static func offers(state: Dictionary, funds: int) -> Array:
	var result: Array = []
	for side: String in SIDES:
		var reason: String = purchase_error(state, side, funds)
		result.append({
			"side": side,
			"label": side.capitalize(),
			"price": price(state, side),
			"plots": _count(state, side),
			"strip": next_plot(state, side),
			"available": reason.is_empty(),
			"reason": reason,
		})
	return result


## Buy the next plot on this side. The household purse pays, and the lot grows.
## Refused, with its reason, before anything is charged.
static func purchase(state: Dictionary, side: String, funds: int) -> Dictionary:
	var reason: String = purchase_error(state, side, funds)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var cost: int = price(state, side)
	var after: Dictionary = state.duplicate()
	after[side] = _count(state, side) + 1
	# A lot that could not actually grow is refused rather than charged for.
	if rect(after) == rect(state):
		return {"ok": false, "error": "That plot adds no new ground."}
	return {"ok": true, "state": after, "cost": cost, "funds": funds - cost, "side": side}


## Whether a point is inside the household's land.
static func encloses(state: Dictionary, bounds: Rect2) -> bool:
	return rect(state).encloses(bounds)


## Whether a point is inside the household's land.
static func has_point(state: Dictionary, point: Vector2) -> bool:
	return rect(state).has_point(point)


## Validate a saved land record. A corrupt one could otherwise ask for a lot no
## machine can build the navigation grid for.
static func validate(value: Variant) -> String:
	if value == null:
		return ""
	if not value is Dictionary:
		return "Save contains an invalid land record."
	var state: Dictionary = value
	if int(state.get("version", 0)) != 1:
		return "The saved land record uses an unsupported version."
	for side: String in SIDES:
		var count: Variant = state.get(side, 0)
		if not (count is int or count is float) or not is_finite(float(count)) or float(count) != floorf(float(count)) or int(count) < 0 or int(count) > MAX_PLOTS_PER_SIDE:
			return "Save contains an impossible plot count."
	if state.size() > 4:
		return "Save contains an unknown land field."
	var measured: Rect2 = rect(state)
	if measured.size.x > MAX_SPAN or measured.size.y > MAX_SPAN:
		return "Save contains a lot larger than the game can build."
	if not measured.encloses(BASE):
		return "Save contains a lot smaller than the starting plot."
	return ""


## Normalise a saved record, so a save that predates the land field simply owns
## the starting plot.
static func from_save(value: Variant) -> Dictionary:
	if not value is Dictionary or not validate(value).is_empty():
		return fresh()
	var state: Dictionary = fresh()
	for side: String in SIDES:
		state[side] = _count(value, side)
	return state


## A player-readable summary of how big the lot has become.
static func describe(state: Dictionary) -> String:
	var measured: Rect2 = rect(state)
	var bought: int = plots(state)
	if bought == 0:
		return "The starting plot, %.0f m by %.0f m." % [measured.size.x, measured.size.y]
	return "%d bought %s, %.0f m by %.0f m in all." % [bought, "plot" if bought == 1 else "plots", measured.size.x, measured.size.y]
