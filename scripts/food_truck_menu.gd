extends RefCounted
class_name LifeFoodTruckMenu
## The weekly food truck's shop, drawn in the ordinary phone card so ordering a
## delivery needs no second idiom. Every row is a real catalogue kind: the price
## shown is the catalogue price, the refusal is the truck's own reason, and a
## successful order opens the ordinary build placement for the article it
## delivered, exactly as the pet shop's accessories do.
##
## The panel is presentation only. The truck owns the schedule, the wallet
## charge and the delivery receipt; this file owns the card.

const P = preload("res://scripts/palette.gd")
const PANEL_POS: Vector2 = Vector2(265, 118)
const PANEL_SIZE: Vector2 = Vector2(910, 664)
const ROW_HEIGHT: float = 44.0
const ROW_GAP: float = 46.0


static func _panel(app: Node) -> void:
	app._begin_pause_overlay()
	app.menus.shade()
	app.card(PANEL_POS, PANEL_SIZE, P.WHITE, 24, app.overlay)
	app.small_caps("A van on the street", PANEL_POS + Vector2(35, 22), Vector2(780, 26), app.overlay)


static func show_shop(app: Node) -> void:
	var truck: LifeFoodTruck = app.food_truck
	_panel(app)
	var day: int = int(app.household.day)
	var minutes_shown: String = "%02d:%02d" % [int(app.household.minutes) / 60, int(app.household.minutes) % 60]
	app.text_label("The weekly food truck.", PANEL_POS + Vector2(33, 62), Vector2(805, 57), 38, P.INK, true, app.overlay)
	var reason: String = truck.availability()
	var parked: bool = truck.visiting()
	var subtitle: String = (
		"A delivery van is parked on the sidewalk, open %s–%s. It comes every %d days in time for day %d."
		% [LifeFoodTruck._clock(LifeFoodTruck.OPEN_MINUTES), LifeFoodTruck._clock(LifeFoodTruck.CLOSE_MINUTES), LifeFoodTruck.PERIOD_DAYS, truck.next_visit_day()]
	) if parked else (
		"There is no van today. The next one parks outside on day %d and sells the same menu." % truck.next_visit_day()
	)
	app.paragraph(subtitle, PANEL_POS + Vector2(37, 130), Vector2(822, 62), 18, P.MUTED, app.overlay)
	app.small_caps("Day %d · %s · household purse ℒ%s" % [day, minutes_shown, app.commas(int(app.household.funds))], PANEL_POS + Vector2(37, 198), Vector2(820, 23), app.overlay)
	app.card(PANEL_POS + Vector2(37, 228), Vector2(822, 320), P.PALE, 15, app.overlay)
	app.small_caps("Today's menu", PANEL_POS + Vector2(58, 240), Vector2(400, 23), app.overlay)
	var kinds: Array = LifeFoodTruck.GOODS.keys()
	kinds.sort()
	for index: int in range(kinds.size()):
		_menu_row(app, truck, str(kinds[index]), PANEL_POS + Vector2(37, 272 + float(index) * ROW_GAP), index)
	if reason.is_empty():
		app.paragraph("Choose a line and the order is charged once; you place the delivery in the ordinary way.", PANEL_POS + Vector2(37, 560), Vector2(822, 42), 15, P.MUTED, app.overlay)
	else:
		app.paragraph(reason, PANEL_POS + Vector2(37, 560), Vector2(822, 60), 16, P.TEAL, app.overlay)
	app.button("Back to life", PANEL_POS + Vector2(37, 608), Vector2(822, 40), app.close_overlay, false, app.overlay)


## One menu line. A delivered line shows its own refusal and is disabled, so a
## greyed-out row and a refused order can never disagree.
static func _menu_row(app: Node, truck: LifeFoodTruck, kind: String, at: Vector2, index: int) -> void:
	var data: Dictionary = LifeCatalog.ITEMS[kind]
	var note: String = str(LifeFoodTruck.GOODS[kind].get("note", ""))
	var refusal: String = truck.order_error(kind)
	var row: Button = app.button("%s  ·  ℒ%d" % [str(data.label), int(data.price)], at, Vector2(822, ROW_HEIGHT), func(): _order(app, kind), false, app.overlay)
	row.name = "TruckOrder_" + kind
	row.disabled = not refusal.is_empty()
	row.tooltip_text = refusal if not refusal.is_empty() else note
	app.paragraph(note, at + Vector2(6, ROW_HEIGHT), Vector2(822, 20), 12, P.MUTED, app.overlay)


## Place the order and then hand the delivery to the ordinary build placement.
## The shop closes first so the placement owns the cursor, exactly as a
## catalogue purchase does.
static func _order(app: Node, kind: String) -> void:
	var result: Dictionary = app.food_truck.place_order(kind)
	if not bool(result.get("ok", false)):
		app.show_notice(str(result.get("error", "The truck could not take that order.")))
		return
	# The purse was charged at the counter. The placement is told so it does not
	# charge again for the article the order already paid for.
	app.pending_delivery = {"kind":kind}
	app.close_overlay()
	app.refresh_hud()
	app.show_notice("%s delivered for ℒ%d. Find a spot for it." % [app.food_truck.order_label(kind), int(result.get("price", 0))])
	app.set_build_mode(true)
	app.begin_purchase(kind)
