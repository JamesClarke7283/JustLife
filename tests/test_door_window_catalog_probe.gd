extends SceneTree
## Door and window catalogues: 5 styles × 10 colours, doorway relocate, wall slide.
const Building = preload("res://scripts/building_state.gd")
const Edits = preload("res://scripts/building_edits.gd")
const Variants = preload("res://scripts/catalog_variants.gd")
const Land = preload("res://scripts/land.gd")

var checks: int = 0
var failures: Array = []
var app: Node


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var door: Dictionary = LifeCatalog.get_item("house_door")
	var window: Dictionary = LifeCatalog.get_item("house_window")
	check(not door.is_empty() and not window.is_empty(), "Door and window catalogue entries exist")
	check(Variants.styles(door).size() == 5, "Door catalogue has 5 styles")
	check(Variants.colors(door).size() == 10, "Door catalogue has 10 colours")
	check(Variants.styles(window).size() == 5, "Window catalogue has 5 styles")
	check(Variants.colors(window).size() == 10, "Window catalogue has 10 colours")
	for style: String in Variants.styles(door):
		check(ResourceLoader.exists(Variants.model_path("house_door", style)), "Door style %s mesh exists" % style)
	for style: String in Variants.styles(window):
		check(ResourceLoader.exists(Variants.model_path("house_window", style)), "Window style %s mesh exists" % style)
	check(LifeCatalog.wall_mounted("house_door") and LifeCatalog.wall_mounted("house_window"), "Door and window are wall-mounted")
	check(LifeCatalog.passable("house_door") and LifeCatalog.passable("house_window"), "Door and window stay passable for navigation")

	# Relocate an existing doorway along its wall.
	# left spans -3.5..-0.56, right spans 0.56..3.5 → gap 1.12 m centred at 0.
	Building.set_land(Land.fresh())
	var room: Dictionary = Building.fresh()
	room.walls = [
		{"id": "left", "level": 0, "x": -2.03, "z": 1.0, "w": 2.94, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "right", "level": 0, "x": 2.03, "z": 1.0, "w": 2.94, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
	]
	var move: Dictionary = Edits.propose(room, {"op": "structure", "tool": "door", "level": 0, "id": "left", "center": 1.0}, 5000)
	check(bool(move.ok), "Doorway relocate quote succeeds (%s)" % str(move.get("error", "")))
	if bool(move.ok):
		check(int(move.cost) == 40, "Relocating an existing doorway is the cheaper move price")
		var stubs: Array = []
		for wall: Dictionary in move.after.walls:
			if int(wall.level) == 0 and float(wall.w) > float(wall.d) and absf(float(wall.z) - 1.0) < 0.1:
				stubs.append(wall)
		check(stubs.size() == 2, "Relocate still leaves two wall stubs around the opening")
		if stubs.size() == 2:
			stubs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) < float(b.x))
			var opening: float = (float(stubs[1].x) - float(stubs[1].w) * 0.5) - (float(stubs[0].x) + float(stubs[0].w) * 0.5)
			var opening_mid: float = (float(stubs[0].x) + float(stubs[0].w) * 0.5 + float(stubs[1].x) - float(stubs[1].w) * 0.5) * 0.5
			check(opening > 0.9 and opening < 1.3, "Relocated doorway keeps a walkable gap")
			check(absf(opening_mid - 1.0) < 0.15, "Relocated doorway centre follows the click")

	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	app.sim.funds = 20000
	app.set_build_mode(true)
	await frames(2)

	app.build_transactions.buy_land("east")
	await frames(2)
	var wall_quote: Dictionary = app.build_transactions.prepare({
		"op": "structure", "tool": "wall", "level": 0,
		"ax": 20.0, "az": 0.0, "bx": 28.0, "bz": 0.0
	})
	check(bool(wall_quote.ok), "Seed wall for openings succeeds (%s)" % str(wall_quote.get("error", "")))
	if bool(wall_quote.ok):
		check(bool(app.build_transactions.commit(wall_quote).ok), "Seed wall commits")

	var snap: Dictionary = app.world.wall_snap("house_window", Vector3(24.0, 0.16, 0.2), 2.0)
	check(not snap.is_empty(), "Window snaps along the seed wall")
	if not snap.is_empty():
		app.on_placement("house_window", snap.position, float(snap.angle), "c", "")
		await frames(2)
		var found_win: Dictionary = {}
		for item: Dictionary in app.world.items:
			if str(item.kind) == "house_window":
				found_win = item; break
		check(not found_win.is_empty(), "Window furnishing is placed")
		if not found_win.is_empty():
			check(str(found_win.variant.get("style", "")) == "c", "Placed window keeps its style")
			check(found_win.node.has_meta("window_aperture"), "Placed window exposes an aperture for curtains")
			var slid: Dictionary = app.world.wall_snap("house_window", Vector3(22.0, 0.16, float(snap.position.z)), 2.0)
			check(not slid.is_empty() and absf(slid.position.x - snap.position.x) > 0.5, "Window can move along the wall")

	var snap_door: Dictionary = app.world.wall_snap("house_door", Vector3(25.0, 0.16, 0.2), 2.0)
	check(not snap_door.is_empty(), "Door snaps along the seed wall")
	if not snap_door.is_empty():
		app.on_placement("house_door", snap_door.position, float(snap_door.angle), "b", "")
		await frames(2)
		var found_door: Dictionary = {}
		for item: Dictionary in app.world.items:
			if str(item.kind) == "house_door":
				found_door = item; break
		check(not found_door.is_empty(), "Door leaf is placed")
		if not found_door.is_empty():
			check(str(found_door.variant.get("style", "")) == "b", "Placed door keeps its style")
			var doorway_gaps := 0
			var walls: Array = app.world.construction.building_state.get("walls", [])
			for i in walls.size():
				for j in range(i + 1, walls.size()):
					var a: Dictionary = walls[i]
					var b: Dictionary = walls[j]
					if int(a.level) != 0 or int(b.level) != 0: continue
					if (float(a.w) > float(a.d)) != (float(b.w) > float(b.d)): continue
					var horizontal: bool = float(a.w) > float(a.d)
					if absf((float(a.z) if horizontal else float(a.x)) - (float(b.z) if horizontal else float(b.x))) > 0.1: continue
					var a_mid: float = float(a.x) if horizontal else float(a.z)
					var b_mid: float = float(b.x) if horizontal else float(b.z)
					var a_half: float = maxf(float(a.w), float(a.d)) * 0.5
					var b_half: float = maxf(float(b.w), float(b.d)) * 0.5
					var lo_a: float = a_mid - a_half
					var hi_a: float = a_mid + a_half
					var lo_b: float = b_mid - b_half
					var hi_b: float = b_mid + b_half
					if lo_a > lo_b:
						var t: float = lo_a; lo_a = lo_b; lo_b = t
						t = hi_a; hi_a = hi_b; hi_b = t
					var gap: float = lo_b - hi_a
					if gap > 0.9 and gap < 1.35:
						doorway_gaps += 1
			check(doorway_gaps >= 1, "Placing a door leaf cuts a doorway in the wall")

	print("DOOR_WINDOW_CATALOG_PROBE %d/%d" % [checks - failures.size(), checks])
	for failure: String in failures:
		print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
