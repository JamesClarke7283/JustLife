extends SceneTree
## Styles, colours and sizes: the catalogue's own variant system.
##
## Run headless:
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_garden_catalogue.gd
##
## The checks drive the real surfaces: a furnishing is bought through the ordinary
## placement path, the picker builds inside the design space, and the choice is
## read back off the placed body and out of the saved layout record.

var app: Node
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


## Every visible descendant, so a control nested inside the panel's own layout is
## measured the way a player would reach it.
func _descend(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is Control and (child as Control).visible and not (child as Control).is_queued_for_deletion():
			into.append(child)
			_descend(child, into)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)

	_variant_policy()
	_art_exists()
	_pricing_and_seats()
	await _placement()
	await _picker()
	await _seat_capacity()

	print("GARDEN_CATALOGUE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)


## The three axes, their defaults and the stored record.
func _variant_policy() -> void:
	var pool: Dictionary = LifeCatalog.get_item("pool")
	check(LifeCatalogVariants.styles(pool).size() == 3, "A pool offers three styles (%d)." % LifeCatalogVariants.styles(pool).size())
	check(LifeCatalogVariants.colors(pool).size() == 10, "A pool offers ten colours (%d)." % LifeCatalogVariants.colors(pool).size())
	check(LifeCatalogVariants.sizes(pool).size() == 3, "A pool offers three sizes (%d)." % LifeCatalogVariants.sizes(pool).size())
	check(LifeCatalogVariants.has_variants(pool), "A pool is a variant family.")
	# An entry with one axis and no others still behaves.
	var box: Dictionary = LifeCatalog.get_item("post_box")
	check(LifeCatalogVariants.sizes(box).is_empty(), "A post box has one size.")
	check(LifeCatalogVariants.model_path("post_box", "") == "res://assets/models/post_box.glb",
		"An unstyled kind resolves to its own file (%s)." % LifeCatalogVariants.model_path("post_box", ""))
	check(LifeCatalogVariants.model_path("pool", "roman").ends_with("pool_roman.glb"),
		"A styled kind resolves to its own styled file (%s)." % LifeCatalogVariants.model_path("pool", "roman"))
	# A style, colour or size outside what the entry offers falls back rather than
	# producing a broken record.
	check(LifeCatalogVariants.style_or_default("nonsense", pool) == "classic",
		"An unknown style falls back to the family's first (%s)." % LifeCatalogVariants.style_or_default("nonsense", pool))
	check(LifeCatalogVariants.size_or_default("nonsense", pool) == "small",
		"An unknown size falls back to the family's first (%s)." % LifeCatalogVariants.size_or_default("nonsense", pool))
	check(LifeCatalogVariants.size_or_default("small", box).is_empty(), "A one-size kind reports no size at all.")
	check(not LifeCatalogVariants.color_offered("123456", pool), "A colour outside the palette is refused.")
	check(LifeCatalogVariants.color_or_default("", box) == "4a6b5c",
		"An unnamed colour falls back to the family's authored colour (%s)." % LifeCatalogVariants.color_or_default("", box))
	# Only the axes an entry offers are stored.
	var record: Dictionary = LifeCatalogVariants.record(pool, "roman", "6f8fa8", "large")
	check(record.size() == 3, "A full family stores all three axes (%d)." % record.size())
	var box_record: Dictionary = LifeCatalogVariants.record(box, "", "6f8fa8", "")
	check(box_record.size() == 1 and box_record.has("color"),
		"A colour-only kind stores only its colour (%s)." % str(box_record.keys()))
	check(LifeCatalogVariants.default_record(pool) == {"style": "classic", "color": "7fb8c6", "size": "small"},
		"A family's default record is its first choice of each axis (%s)." % str(LifeCatalogVariants.default_record(pool)))


## Every choice a family offers must have the artwork it names, so a style is a
## real silhouette rather than a fallback.
func _art_exists() -> void:
	var missing: Array[String] = []
	var checked: int = 0
	for kind: String in LifeCatalog.ITEMS:
		# A memorial is built from code rather than authored art, which the
		# catalogue entry and the world both know.
		if kind == "memorial": continue
		var data: Dictionary = LifeCatalog.ITEMS[kind]
		for path: String in LifeCatalogVariants.model_paths(kind, data):
			checked += 1
			if not ResourceLoader.exists(path): missing.append(path)
	check(missing.is_empty(), "Every style a catalogue entry offers has its authored model (%d checked, %d missing: %s)."
		% [checked, missing.size(), ", ".join(PackedStringArray(missing.slice(0, 6)))])
	# A colour-variant model must carry the surface the colour actually paints.
	var tinted: Array[String] = []
	var no_tint: Array[String] = []
	for kind: String in LifeCatalog.ITEMS:
		var data: Dictionary = LifeCatalog.ITEMS[kind]
		if LifeCatalogVariants.colors(data).size() <= 1: continue
		tinted.append(kind)
		var path: String = LifeCatalogVariants.model_path(kind, LifeCatalogVariants.style_or_default("", data))
		if not ResourceLoader.exists(path):
			no_tint.append(kind)
			continue
		var scene: Node = (load(path) as PackedScene).instantiate()
		var found: int = 0
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			if LifeCatalogVariants.is_tint(node.name): found += 1
		scene.free()
		if found == 0: no_tint.append(kind)
	check(tinted.size() >= 40, "Most of the new catalogue offers colours (%d kinds)." % tinted.size())
	check(no_tint.is_empty(), "Every colour-variant model authors the surface its colour paints (%d missing: %s)."
		% [no_tint.size(), ", ".join(PackedStringArray(no_tint.slice(0, 6)))])


## The three price shapes and the per-size seat count.
func _pricing_and_seats() -> void:
	var pool: Dictionary = LifeCatalog.get_item("pool")
	check(LifeCatalogVariants.price(pool, "small") == 400 and LifeCatalogVariants.price(pool, "medium") == 600
		and LifeCatalogVariants.price(pool, "large") == 800,
		"A pool's three sizes cost what they advertise (%d/%d/%d)." % [
			LifeCatalogVariants.price(pool, "small"), LifeCatalogVariants.price(pool, "medium"), LifeCatalogVariants.price(pool, "large")])
	# A fence is sold by the square metre of face it presents.
	var fence: Dictionary = LifeCatalog.get_item("fence")
	var small: int = LifeCatalogVariants.price(fence, "small")
	var large: int = LifeCatalogVariants.price(fence, "large")
	check(large > small, "A larger fence run costs more (%d -> %d)." % [small, large])
	check(is_equal_approx(LifeCatalogVariants.face_area(fence, "small") * 10.0, float(small)),
		"A fence is priced at its own rate per square metre (%.2f m² -> %d)." % [LifeCatalogVariants.face_area(fence, "small"), small])
	# A one-price kind keeps its price at every size it offers.
	var box: Dictionary = LifeCatalog.get_item("post_box")
	check(LifeCatalogVariants.price(box, "") == int(box.price), "A one-price kind costs its stated price.")
	# Seats are the catalogue's own claim, per size.
	var table: Dictionary = LifeCatalog.get_item("garden_table")
	check(LifeCatalogVariants.seats(table, "small") == 4 and LifeCatalogVariants.seats(table, "medium") == 8
		and LifeCatalogVariants.seats(table, "large") == 10,
		"A garden table seats what it advertises (%d/%d/%d)." % [
			LifeCatalogVariants.seats(table, "small"), LifeCatalogVariants.seats(table, "medium"), LifeCatalogVariants.seats(table, "large")])


## A chosen style, colour and size survive the ordinary purchase and the save.
func _placement() -> void:
	app.set_build_mode(true)
	await frames(4)
	app.on_placement("hot_tub", Vector3(8.0, 0.16, 5.0), 0.0, "oval", "small")
	await frames(4)
	var placed: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "hot_tub": placed = item
	check(not placed.is_empty(), "A styled and coloured furnishing places through the ordinary path.")
	if placed.is_empty():
		return
	check(str(placed.get("variant", {}).get("style", "")) == "oval",
		"The placed body remembers the style that was chosen (%s)." % str(placed.get("variant", {}).get("style", "")))
	check(Color(app.world.item_colour(placed)).to_html(false) == LifeCatalogVariants.colors(LifeCatalog.get_item("hot_tub"))[0],
		"The placed body reports the colour that was chosen (%s)." % app.world.item_colour(placed).to_html(false))
	# The colour really reaches the model's Tint surface.
	var painted: int = 0
	for node: Node in placed.node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		if mesh.name == LifeCatalogVariants.TINT_SURFACE and mesh.material_override is StandardMaterial3D:
			painted += 1
	check(painted == 1, "The chosen colour paints the model's own Tint surface (%d painted)." % painted)
	# And the choice rides the saved layout.
	var saved: Dictionary = {}
	for entry: Dictionary in app.world.serialize_items():
		if str(entry.get("kind", "")) == "hot_tub": saved = entry
	check(str(saved.get("style", "")) == "oval" and not str(saved.get("color", "")).is_empty(),
		"The saved layout record carries the choice (%s)." % str(saved))
	# A hot tub is one size, so its record carries no size key at all — an absent
	# key and a `small` choice must not be two different objects.
	check(not saved.has("size"), "A one-size family stores no size key at all.")
	# A sized family really changes the footprint, the price and the record. A
	# small pool is the authored size and is the one the starter garden leaves
	# room for, so it is what the fixture places.
	var spot: Vector3 = _free_spot("pool", "classic", "small")
	check(spot.is_finite(), "The garden has room for the family's own smallest pool.")
	if spot.is_finite():
		app.on_placement("pool", spot, 0.0, "classic", "small")
		await frames(4)
		var pool: Dictionary = {}
		var pool_saved: Dictionary = {}
		for item: Dictionary in app.world.items:
			if str(item.kind) == "pool": pool = item
		for entry: Dictionary in app.world.serialize_items():
			if str(entry.get("kind", "")) == "pool": pool_saved = entry
		check(not pool.is_empty(), "A sized pool places through the ordinary path.")
		if not pool.is_empty():
			var authored: Vector2 = LifeCatalog.ITEMS.pool.size
			check(is_equal_approx(pool.size.x, authored.x),
				"A small pool is the authored size (%.2f against %.2f)." % [pool.size.x, authored.x])
			check(str(pool_saved.get("size", "")) == "small",
				"A sized family stores the size the player chose (%s)." % str(pool_saved.get("size", "<none>")))
			check(not str(pool_saved.get("color", "")).is_empty(),
				"A family with a colour stores it (%s)." % str(pool_saved.get("color", "<none>")))
	# A larger size really occupies more ground than a smaller one, measured
	# from the family's own scaled footprint rather than from a placement.
	var pool_data: Dictionary = LifeCatalog.get_item("pool")
	check(LifeCatalogVariants.footprint(pool_data, "large").x > LifeCatalogVariants.footprint(pool_data, "small").x * 1.9,
		"A large pool occupies a much larger footprint than a small one (%.1f against %.1f)."
		% [LifeCatalogVariants.footprint(pool_data, "large").x, LifeCatalogVariants.footprint(pool_data, "small").x])
	app.set_build_mode(false)
	await frames(3)


## The picker builds inside the design space, offers every choice, and settles on
## the size the player pressed.
func _picker() -> void:
	app.set_build_mode(true)
	await frames(3)
	app.pick_furnishing("tree_garden")
	await frames(6)
	var panel: Control = app.overlay
	var list: Control = panel.find_child("VariantPreview", true, false)
	check(list != null, "The picker shows a live preview of the family.")
	var styles: int = panel.find_children("VariantStyle_*", "Button", true, false).size()
	var sizes: int = panel.find_children("VariantSize_*", "Button", true, false).size()
	var colors: int = panel.find_children("VariantColor_*", "Button", true, false).size()
	check(styles == LifeCatalogVariants.styles(LifeCatalog.get_item("tree_garden")).size(),
		"The picker offers every style (%d of 10)." % styles)
	check(sizes == 3, "The picker offers every size (%d)." % sizes)
	check(colors == 10, "The picker offers every colour (%d)." % colors)
	check(panel.find_child("VariantConfirm", true, false) != null, "The picker offers a way to place it.")
	# Nothing the picker draws may escape the design space. The panel's own
	# full-screen backdrop is meant to cover the canvas, so it is not a control a
	# player has to reach — the same exclusion the bounds suite makes.
	var escaped: int = 0
	var all: Array[Control] = []
	_descend(panel, all)
	for control: Control in all:
		var rect: Rect2 = Rect2(control.position, control.size)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0: continue
		# A full-canvas backdrop is the panel's own dim scrim or dismiss layer,
		# meant to cover the screen; it is not a control a player has to reach.
		if rect.size.x >= 1439.0 and rect.size.y >= 899.0: continue
		if rect.position.x < -2.0 or rect.position.y < -2.0 or rect.end.x > 1442.0 or rect.end.y > 902.0:
			escaped += 1
			if escaped <= 3: print("    escaped: ", control.name, " ", rect)
	check(escaped == 0, "The picker fits the 1440x900 design space (%d escaped)." % escaped)
	# Pressing a size settles on it, and the price follows.
	var large: Button = panel.find_child("VariantSize_large", true, false)
	check(large != null and large.text.contains("1000"),
		"A large tree states its own price (%s)." % (large.text if large != null else "<missing>"))
	app.close_overlay()
	await frames(3)
	app.set_build_mode(false)
	await frames(3)


## A spot on the lot where this exact style and size may legally stand, found by
## asking the world's own placement rule rather than guessing coordinates.
func _free_spot(kind: String, style: String, size: String) -> Vector3:
	var x: float = -11.5
	while x <= 11.5:
		var z: float = -8.5
		while z <= 8.5:
			if app.world.can_place(kind, Vector3(x, 0.16, z), 0.0, style, size):
				return Vector3(x, 0.16, z)
			z += 0.5
		x += 0.5
	return Vector3.INF


## A furnishing really seats the number the catalogue advertises.
func _seat_capacity() -> void:
	var table_data: Dictionary = LifeCatalog.get_item("garden_table")
	var entry: Dictionary = {"id": "table_1", "kind": "garden_table", "x": 8.0, "z": -5.0, "rotation": 0, "size": "large"}
	entry.merge(LifeCatalogVariants.record(table_data, "", "d7ae7e", "large"), true)
	app.world.add_item(entry)
	await frames(3)
	var placed: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "garden_table": placed = item
	check(not placed.is_empty(), "A large garden table places.")
	if placed.is_empty():
		return
	check(app.world.seat_capacity(placed) == 10,
		"A large garden table really holds ten places (%d)." % app.world.seat_capacity(placed))
	check(app.world.seat_slots(placed).size() == 10,
		"It names ten distinct places (%d)." % app.world.seat_slots(placed).size())
	var offsets: Array = []
	for slot: String in app.world.seat_slots(placed):
		offsets.append(app.world.seat_slot_offset(placed, slot))
	var distinct: bool = true
	for i: int in offsets.size():
		for j: int in range(i + 1, offsets.size()):
			if (offsets[i] as Vector3).distance_to(offsets[j] as Vector3) < 0.01: distinct = false
	check(distinct, "Its places are distinct positions rather than one spot repeated.")
	# An ordinary chair still seats one, and a bed still keeps its named halves.
	var chair: Dictionary = app.world.closest_item("chair", Vector3.ZERO)
	check(chair.is_empty() or app.world.seat_capacity(chair) == 1,
		"An ordinary chair seats exactly one (%d)." % (0 if chair.is_empty() else app.world.seat_capacity(chair)))
	var bed: Dictionary = app.world.closest_item("bed", Vector3.ZERO)
	check(bed.is_empty() or app.world.seat_slots(bed) == ["left", "right"],
		"A bed still keeps its named halves (%s)." % str(app.world.seat_slots(bed)))
