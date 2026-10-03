extends RefCounted
## The festive tablecloth: a setting on the gathering table rather than a thing of its own.
## The table's layout record carries `cloth` (a six-digit shade from the party colours), the
## world draws a thin drape over the top, and the player lays it for ℒ15 or takes it off
## from the table's card in Build mode and from its menu in Live mode. Every control here
## only asks the world to change that setting; the cloth never changes where food sits.

const P = preload("res://scripts/palette.gd")
const PartyProps = preload("res://scripts/party_props.gd")

const HOSTS: Array[String] = PartyProps.CLOTH_HOSTS
const PRICE: int = 15
const LAY: String = "lay_tablecloth"
const REMOVE: String = "remove_tablecloth"
const RECOLOUR: String = "change_tablecloth"
const IDS: Array[String] = [LAY, REMOVE, RECOLOUR]


static func hosts(kind: String) -> bool:
	return kind in HOSTS


static func lay_label() -> String:
	return "Lay a festive tablecloth · ℒ%d" % PRICE


## Why this change cannot be made to this table, or "" when it can.
static func error(app: Node, id: String, table_id: String) -> String:
	var table: Dictionary = app._find_item(table_id)
	if table.is_empty() or not hosts(str(table.get("kind", ""))):
		return "Choose a gathering table."
	var worn: bool = not str(app.world.item_cloth(table)).is_empty()
	if id == LAY:
		if worn: return "This table already has a cloth."
		if app.sim.funds < PRICE: return "Requires ℒ%d." % PRICE
	elif id in [REMOVE, RECOLOUR] and not worn:
		return "This table has no cloth."
	return ""


## Lay the cloth (ℒ15), take it off, or change its shade (both free). In Build mode the
## change is a step of Undo. Returns whether the table changed.
static func apply(app: Node, id: String, table_id: String, shade: String = "") -> bool:
	var problem: String = error(app, id, table_id)
	if problem.is_empty() and id != REMOVE and not shade.is_empty() and not LifeCatalog.PARTY_COLORS.has(shade):
		problem = "Choose one of the party colours."
	if not problem.is_empty():
		app.show_notice(problem)
		return false
	var table: Dictionary = app._find_item(table_id)
	var chosen: String = shade if not shade.is_empty() else str(LifeCatalog.PARTY_COLORS[0])
	if str(app.mode) == "build":
		app.build_undo.append(app._build_snapshot(PRICE if id == LAY else 0))
	if id == REMOVE:
		app.world.set_item_cloth(table, "")
		app.show_notice("The tablecloth is off the table.")
	else:
		app.world.set_item_cloth(table, chosen)
		if id == LAY:
			app.household.set_funds(app.sim.funds - PRICE)
			app.show_notice("A festive tablecloth is on the table. −ℒ%d" % PRICE)
		else:
			app.show_notice("A fresh colour for the tablecloth.")
	app.refresh_hud()
	return true


# ---------------------------------------------------------------- the live menu

## The menu entries for a gathering table: lay a cloth, or change and take off the one it wears.
static func menu_entries(app: Node, item: Dictionary) -> Array:
	var id: String = str(item.get("id", ""))
	var out: Array = []
	if str(app.world.item_cloth(app._find_item(id))).is_empty():
		var why: String = error(app, LAY, id)
		out.append({"id": LAY, "label": lay_label(), "cost": 0, "duration": 0, "available": why.is_empty(), "unavailable_reason": why,
			"description": "Dress the table for a party. Meals and food sit on it just as before."})
	else:
		out.append({"id": RECOLOUR, "label": "Change the tablecloth colour…", "cost": 0, "duration": 0, "available": true,
			"description": "Choose another of the party colours. It costs nothing."})
		out.append({"id": REMOVE, "label": "Take the tablecloth off", "cost": 0, "duration": 0, "available": true,
			"description": "Fold the cloth away."})
	return out


## What a menu entry does. A colour change opens its own picker; the others finish and close the menu.
static func choose(app: Node, id: String, table_id: String) -> void:
	if id == RECOLOUR:
		show_colours(app, table_id)
		return
	apply(app, id, table_id)
	app.close_overlay()


# ------------------------------------------------------------- the Build card

## How many buttons the table's Build card gains.
static func card_rows(app: Node, item: Dictionary) -> int:
	if not hosts(str(item.get("kind", ""))): return 0
	return 1 if str(app.world.item_cloth(app._find_item(str(item.get("id", ""))))).is_empty() else 2


## Add the cloth buttons to a table's Build card at `y` inside the card at `card_at`, and
## return where the next row starts.
static func card_buttons(app: Node, item: Dictionary, card_at: Vector2, y: float) -> float:
	if not hosts(str(item.get("kind", ""))): return y
	var id: String = str(item.get("id", ""))
	var live: Dictionary = app._find_item(id)
	if live.is_empty(): return y
	if str(app.world.item_cloth(live)).is_empty():
		var lay: Button = app.button(lay_label(), card_at + Vector2(16, y), Vector2(258, 40), func() -> void:
			apply(app, LAY, id)
			app.close_overlay(), false, app.overlay)
		lay.name = "TableClothLay"
		lay.disabled = not error(app, LAY, id).is_empty()
		lay.tooltip_text = error(app, LAY, id) if lay.disabled else "Dress this table for a party. Meals and food sit on it just as before."
		return y + 51.0
	var colour: Button = app.button("Change cloth colour…", card_at + Vector2(16, y), Vector2(258, 40), func() -> void: show_colours(app, id), false, app.overlay)
	colour.name = "TableClothColour"
	colour.tooltip_text = "Choose another of the party colours. It costs nothing."
	var off: Button = app.button("Take the tablecloth off", card_at + Vector2(16, y + 51.0), Vector2(258, 40), func() -> void:
		apply(app, REMOVE, id)
		app.close_overlay(), false, app.overlay)
	off.name = "TableClothRemove"
	off.tooltip_text = "Fold the cloth away."
	return y + 102.0


## The party colours as swatches. A press changes the cloth at once and the picker stays
## open, as the colour picker for other furnishings does.
static func show_colours(app: Node, table_id: String) -> void:
	var table: Dictionary = app._find_item(table_id)
	if table.is_empty() or not hosts(str(table.get("kind", ""))): return
	var current: String = str(app.world.item_cloth(table))
	if current.is_empty(): return
	app.close_overlay()
	app.overlay_open = true
	app.dismiss_layer()
	var at := Vector2(420, 180)
	app.card(at, Vector2(560, 420), P.WHITE, 20, app.overlay)
	app.small_caps("Tablecloth colour", at + Vector2(28, 22), Vector2(500, 22), app.overlay)
	app.text_label(str(table.get("label", "Gathering table")), at + Vector2(26, 52), Vector2(500, 36), 26, P.INK, true, app.overlay)
	app.paragraph("Pick a swatch. The cloth changes on the table at once.", at + Vector2(28, 96), Vector2(500, 40), 15, P.MUTED, app.overlay)
	var palette: Array[String] = LifeCatalog.PARTY_COLORS
	for index: int in palette.size():
		var hex: String = palette[index]
		var chosen: bool = hex == current
		var spot: Vector2 = at + Vector2(28.0 + float(index % 5) * 68.0, 150.0 + float(index / 5) * 68.0)
		var chip: Button = app.button("•" if chosen else "", spot, Vector2(56, 56), func() -> void:
			apply(app, RECOLOUR, table_id, hex)
			show_colours(app, table_id), false, app.overlay)
		chip.name = "TableClothColor_%d" % index
		chip.tooltip_text = "#" + hex.to_upper()
		chip.add_theme_stylebox_override("normal", P.panel(Color(hex), 16, P.TEAL if chosen else Color("dbe2d7"), 3 if chosen else 1))
		chip.add_theme_stylebox_override("hover", P.panel(Color(hex).lightened(.08), 16, P.TEAL, 3))
		if chosen: chip.add_theme_color_override("font_color", Color.WHITE)
		app.compact_button(chip)
		chip.size = Vector2(56, 56)
	app.button("Back", at + Vector2(28, 360), Vector2(200, 42), func() -> void: _back(app, table_id), false, app.overlay)


## Leave the picker: back to the table's card in Build mode, or out of the way in Live mode.
static func _back(app: Node, table_id: String) -> void:
	var table: Dictionary = app._find_item(table_id)
	if str(app.mode) == "build" and not table.is_empty():
		app.show_build_object(table, Vector2(850, 380))
	else:
		app.close_overlay()
