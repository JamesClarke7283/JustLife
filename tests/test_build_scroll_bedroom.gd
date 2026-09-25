extends SceneTree
## Build & Buy scrollbars and the child bedroom pack.
##
## Overflowing sections (the catalogue strip, a long style row, the structure
## tools) expose a scrollbar and can bring a clipped control into view. A section
## whose content already fits does not show one. Placing the child bedroom pack
## records a bed, bedside table, floor lamp, rug, painting, and a desk with the
## home computer and a chair.

var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int = 3) -> void:
	for _i: int in n:
		await process_frame


func _child_min(scroll: ScrollContainer) -> Vector2:
	if scroll == null or scroll.get_child_count() == 0:
		return Vector2.ZERO
	return (scroll.get_child(0) as Control).get_combined_minimum_size()


## A scrollbar is showing on an axis only when that axis really overflows.
func _assert_scroll(scroll: ScrollContainer, label: String) -> void:
	check(scroll != null, "%s exists." % label)
	if scroll == null:
		return
	var content: Vector2 = _child_min(scroll)
	var hbar: ScrollBar = scroll.get_h_scroll_bar()
	var vbar: ScrollBar = scroll.get_v_scroll_bar()
	var wider: bool = content.x > scroll.size.x + 1.0
	var taller: bool = content.y > scroll.size.y + 1.0
	# The horizontal bar consumes height, so a row can be taller than the
	# remaining page without being taller than the whole control.
	if hbar.visible:
		taller = content.y > hbar.position.y + 1.0
	if vbar.visible:
		wider = content.x > vbar.position.x + 1.0
	check(wider == hbar.visible, "%s horizontal scrollbar matches overflow (content %.0f, viewport %.0f, bar %s)." % [label, content.x, scroll.size.x, str(hbar.visible)])
	check(taller == vbar.visible, "%s vertical scrollbar matches overflow (content %.0f, viewport %.0f, bar %s)." % [label, content.y, scroll.size.y, str(vbar.visible)])


func _bring_into_view(scroll: ScrollContainer, control: Control, label: String) -> void:
	check(control != null, "%s control exists." % label)
	if scroll == null or control == null:
		return
	scroll.ensure_control_visible(control)
	await frames(2)
	var view: Rect2 = scroll.get_global_rect()
	var target: Rect2 = control.get_global_rect()
	var centre: Vector2 = target.get_center()
	check(view.has_point(centre), "%s scrolls into view (centre %s, view %s)." % [label, str(centre), str(view)])


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.selected_lot = 0
	app.start_household()
	await frames(8)
	app.household.set_speed(0)
	app.set_build_mode(true)
	await frames(4)

	var categories: ScrollContainer = app.find_child("CatalogCategories", true, false)
	_assert_scroll(categories, "Category list")
	var strip: ScrollContainer = app.find_child("CatalogStrip", true, false)
	_assert_scroll(strip, "Catalogue strip")
	check(_child_min(strip).x > strip.size.x + 1.0, "The catalogue strip is wider than its panel.")
	var bedroom_cell: Control = app.find_child("Catalog_child_bedroom_pack", true, false)
	await _bring_into_view(strip, bedroom_cell, "Child bedroom pack")

	app.catalog_category = "Structure"
	app.draw_live()
	await frames(3)
	var tools: ScrollContainer = app.find_child("StructureTools", true, false)
	_assert_scroll(tools, "Structure tools")
	check(_child_min(tools).y > tools.size.y + 1.0, "Structure tools are taller than the Build & Buy panel.")
	var gable: Control = app.find_child("RoofStyle_gabled", true, false)
	await _bring_into_view(tools, gable, "Gable roof style")

	app.close_overlay()
	app.pick_furnishing("shrub")
	await frames(3)
	var styles: ScrollContainer = app.overlay.find_child("VariantStyles", true, false)
	var sizes: ScrollContainer = app.overlay.find_child("VariantSizes", true, false)
	_assert_scroll(styles, "Shrub style row")
	_assert_scroll(sizes, "Shrub size row")
	check(_child_min(styles).x > styles.size.x + 1.0, "The shrub style row is wider than the panel.")
	check(_child_min(sizes).x <= sizes.size.x + 1.0, "The shrub size row fits, so it does not need a horizontal scrollbar.")
	var last_style: Control = app.overlay.find_child("VariantStyle_20", true, false)
	await _bring_into_view(styles, last_style, "Last shrub style")
	app.close_overlay()

	# The fitting colour row on a short family stays on the card without a bar.
	app.pick_furnishing("toy_chest")
	await frames(2)
	var colours: ScrollContainer = app.overlay.find_child("VariantColours", true, false)
	check(colours == null, "A colour row that fits the panel has no scrollbar.")
	var chip: Control = app.overlay.find_child("VariantColor_4", true, false)
	check(chip != null and chip.get_global_rect().end.y < 900.0, "The last toy-chest colour stays on the canvas.")
	app.close_overlay()
	await frames(2)

	var required: Array[String] = ["child_bed", "nightstand", "floor_lamp", "child_rug", "painting", "child_desk", "computer", "child_chair"]
	var layout_kinds: Array = LifeCatalog.room_pack_layout("child_bedroom_pack").map(func(row: Dictionary) -> String: return str(row.kind))
	for kind: String in required:
		check(layout_kinds.has(kind), "Child bedroom layout includes %s." % kind)
	app.household.set_funds(50000)
	app.catalog_category = "All"
	app.draw_live()
	await frames(2)
	if app.mode != "build":
		app.set_build_mode(true)
		await frames(2)
	var state: Dictionary = app.build_transactions.current().state
	var house := Rect2()
	for wall: Dictionary in state.walls:
		house = LifeBuildingState.rect(wall) if not house.has_area() else house.merge(LifeBuildingState.rect(wall))
	var before: Dictionary = {}
	for item: Dictionary in app.world.items:
		before[str(item.id)] = true
	var result: Dictionary = {}
	for offset: Vector2 in [Vector2(2.25 + .35, 0), Vector2(2.25 + .35, 2.0), Vector2(2.25 + .35, -2.0), Vector2(2.25 + .35, 3.0)]:
		var click := Vector3(house.end.x + offset.x, LifeBuildingState.level_y(0), house.get_center().y + offset.y)
		result = app._place_room_pack("child_bedroom_pack", click, 0.0)
		if not result.is_empty():
			break
	check(not result.is_empty(), "The child bedroom pack places.")
	var placed: Array[String] = []
	for item: Dictionary in app.world.items:
		if not before.has(str(item.id)):
			placed.append(str(item.kind))
	print("BEDROOM_PLACED ", placed, " skipped ", result.get("skipped", []))
	for kind: String in required:
		check(placed.has(kind), "Placed child bedroom includes %s." % kind)

	print("BUILD_SCROLL_BEDROOM %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
