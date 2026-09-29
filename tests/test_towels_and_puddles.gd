extends SceneTree
## Towels, racks and the drying sequence, in the running game.
##
## The catalogue offers a loose beach towel (3 styles, 10 colours, ℒ5) and a
## garden towel rack (small, medium, large: ℒ30, ℒ35, ℒ40, holding 1, 2 and 4
## towels). A Lifelet coming out of the pool goes to a rack, takes a towel and wraps
## up in it, sits to finish drying, and hangs the towel back. A Lifelet who sits on
## a soft seat damp for too long leaves a puddle that has to be mopped.
##
##   JUSTLIFE_DATA_DIR=/tmp/x XDG_DATA_HOME=/tmp/y godot --headless --audio-driver Dummy --path . --script res://tests/test_towels_and_puddles.gd

const DT: float = 1.0 / 20.0

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("This test needs an isolated JUSTLIFE_DATA_DIR.")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	_catalogue()
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_funds(20000)
	app.household.set_speed(3)
	# What happens next is the swim's own doing, not the morning commute's.
	for member: Dictionary in app.household.members: member.sim.autonomy = false
	_racks()
	await _buying()
	await _drying_sequence()
	await _loose_towel()
	await _puddle()
	print("TOWELS_AND_PUDDLES %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: print("  FAILED: ", failure)
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)


func _catalogue() -> void:
	var towel: Dictionary = LifeCatalog.get_item("beach_towel")
	var rack: Dictionary = LifeCatalog.get_item("towel_rack")
	check(int(towel.price) == 5 and LifeCatalogVariants.styles(towel).size() == 3 and LifeCatalogVariants.colors(towel).size() == 10, "The beach towel is ℒ5 in 3 styles and 10 colours.")
	for size: String in ["small", "medium", "large"]:
		var price: int = int({"small": 30, "medium": 35, "large": 40}[size])
		var holds: int = int({"small": 1, "medium": 2, "large": 4}[size])
		check(LifeCatalogVariants.price(rack, size) == price, "The %s garden towel rack costs ℒ%d." % [size, price])
		check(LifeCatalogVariants.holds(rack, size) == holds, "The %s rack holds %d towel%s." % [size, holds, "" if holds == 1 else "s"])
	check(LifeCatalogVariants.colors(rack).size() == 10, "The rack comes in 10 colours.")
	for style: String in LifeCatalogVariants.styles(towel):
		var path: String = LifeCatalogVariants.model_path("beach_towel", style)
		check(ResourceLoader.exists(path), "Towel style %s has its authored model." % style)
		if ResourceLoader.exists(path):
			var scene: Node3D = load(path).instantiate()
			var tints: int = 0
			for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
				if LifeCatalogVariants.is_tint(mesh.name): tints += 1
			check(tints == 1, "Towel style %s authors one recolourable surface." % style)
			scene.free()
	check(ResourceLoader.exists("res://assets/models/towel_rack.glb"), "The rack has its authored model.")
	check(LifeCatalog.passable("beach_towel") and not LifeCatalog.passable("towel_rack"), "A towel on the ground never blocks a route; a rack is solid.")
	check(LifeCatalog.get_item("beach_towel").category == "Pool" and LifeCatalog.get_item("towel_rack").category == "Pool", "Both are sold in the Pool tab.")


func _place(kind: String, spots: Array, extra: Dictionary = {}) -> Dictionary:
	for spot: Vector2 in spots:
		var at := Vector3(spot.x, LifeBuildingState.level_y(0), spot.y)
		var style: String = str(extra.get("style", ""))
		var size: String = str(extra.get("size", ""))
		if app.world.can_place(kind, at, 0.0, style, size):
			var id: String = str(extra.get("id", "t_%s" % kind))
			var entry: Dictionary = {"id": id, "kind": kind, "x": at.x, "z": at.z, "rotation": 0}
			entry.merge(extra, true)
			app.world.add_item(entry)
			return app._find_item(id)
	return {}


func _racks() -> void:
	var spots: Array = [Vector2(-11, 7), Vector2(-8, 8), Vector2(11, 7), Vector2(8, 8), Vector2(-13, -6), Vector2(13, -6)]
	var expect: Dictionary = {"small": 1, "medium": 2, "large": 4}
	for size: String in ["small", "medium", "large"]:
		var rack: Dictionary = _place("towel_rack", spots, {"id": "rack_%s" % size, "size": size})
		check(not rack.is_empty(), "A %s rack can stand in the garden." % size)
		if rack.is_empty(): continue
		check(int(rack.towels) == int(expect[size]), "A new %s rack starts fully stocked with %d." % [size, int(expect[size])])
		var hung: Node = rack.node.get_node_or_null("RackTowels")
		check(hung != null and hung.get_child_count() == int(expect[size]), "The %s rack shows %d towel%s hanging (%d)." % [size, int(expect[size]), "" if int(expect[size]) == 1 else "s", hung.get_child_count() if hung != null else -1])
		check(app.world.change_rack_towels(str(rack.id), -1) and int(rack.towels) == int(expect[size]) - 1, "Taking a towel leaves the rack one short.")
		check((rack.node.get_node("RackTowels") as Node).get_child_count() == int(expect[size]) - 1, "…and one fewer hanging.")
		check(app.world.change_rack_towels(str(rack.id), 1) and int(rack.towels) == int(expect[size]), "Hanging it back restores the stock.")
		check(not app.world.change_rack_towels(str(rack.id), 1), "A full rack takes no more.")
		var saved: bool = false
		for record: Dictionary in app.world.serialize_items():
			if str(record.get("id", "")) == str(rack.id): saved = int(record.get("towels", -1)) == int(expect[size])
		check(saved, "A rack's towels are written to the layout.")
	check(app.world.validate_home_layout(app.world.serialize_items()).is_empty(), "The layout with racks passes validation.")
	app.world.remove_item("rack_small")
	app.world.remove_item("rack_medium")
	app.world.remove_item("rack_large")


func _buying() -> void:
	app.set_build_mode(true)
	await frames(2)
	for row: Array in [["beach_towel", "b", "", "6f8fa8", 5], ["towel_rack", "", "medium", "4a4f55", 35]]:
		var kind: String = str(row[0])
		var data: Dictionary = LifeCatalog.get_item(kind)
		var funds: int = app.sim.funds
		var items: int = app.world.items.size()
		app.world.placement_color = str(row[3])
		var placed: bool = false
		for spot: Vector2 in [Vector2(-9, 6), Vector2(9, 6), Vector2(-9, -6), Vector2(9, -6), Vector2(-12, 2), Vector2(12, 2)]:
			var at := Vector3(spot.x, LifeBuildingState.level_y(0), spot.y)
			if app.world.can_place(kind, at, 0.0, str(row[1]), str(row[2])):
				app.world.begin_placement(kind, str(row[1]), str(row[2]), str(row[3]))
				app.on_placement(kind, at, 0.0, str(row[1]), str(row[2]))
				app.world.clear_placement()
				placed = true
				break
		check(placed and app.world.items.size() == items + 1, "A %s is bought through the ordinary placement path." % kind)
		check(funds - app.sim.funds == int(row[4]), "…for exactly ℒ%d (%d)." % [int(row[4]), funds - app.sim.funds])
		var bought: Dictionary = {}
		for entry: Dictionary in app.world.items:
			if str(entry.kind) == kind: bought = entry
		check(not bought.is_empty() and str(bought.variant.get("color", "")) == str(row[3]), "The colour chosen is the colour bought.")
		if not bought.is_empty(): app.world.remove_item(str(bought.id))
	app.set_build_mode(false)
	await frames(2)


func _in_water(pool: Dictionary, at: Vector3) -> bool:
	for panel: Rect2 in app.world.item_panels(pool):
		if panel.grow(-.05).has_point(Vector2(at.x, at.z)): return true
	return false


func _drying_sequence() -> void:
	var pool: Dictionary = _place("pool", [Vector2(-12, 4), Vector2(12, 4), Vector2(-12, -8), Vector2(12, -8), Vector2(-13, 0)])
	check(not pool.is_empty(), "A pool fits in the garden.")
	var centre: Vector3 = pool.node.global_position
	var rack: Dictionary = _place("towel_rack", [Vector2(centre.x + 3.6, centre.z - 2.4), Vector2(centre.x - 3.6, centre.z - 2.4), Vector2(centre.x + 3.6, centre.z + 3.0), Vector2(centre.x - 3.6, centre.z + 3.0), Vector2(centre.x, centre.z - 3.4)], {"id": "rack_pool", "size": "medium"})
	var seat: Dictionary = _place("bench", [Vector2(centre.x - 3.6, centre.z + 3.4), Vector2(centre.x + 3.6, centre.z + 3.4), Vector2(centre.x, centre.z + 3.8), Vector2(centre.x + 5.0, centre.z), Vector2(centre.x - 5.0, centre.z)])
	check(not rack.is_empty() and not seat.is_empty(), "A rack and a garden seat stand near the pool.")
	if rack.is_empty() or seat.is_empty(): return
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	await frames(2)
	var id: String = app.household.selected_id()
	var person: LifeActor = app.world.actors[id]
	var sim: LifeSim = app.sim
	sim.action_queue.clear()
	sim.wetness = 0.0
	# A real swim, then everything after it happens on its own.
	check(sim.queue_action(LifeOutdoorActs.ACTION_ID, str(pool.id), app.world.approach(pool)), "The Lifelet goes for a swim.")
	var seen: Dictionary = {}
	var took_at: float = -1.0
	var wrapped_seen: bool = false
	var held_seen: bool = false
	var stocked_before: int = int(rack.towels)
	var minimum_stock: int = stocked_before
	var seated_seen: bool = false
	var sat_anchor: String = ""
	var dripped: bool = false
	var wet_on_exit: float = 0.0
	for frame: int in range(9000):
		app._process(DT)
		var action: Dictionary = sim.get_current_action()
		var current: String = str(action.get("id", "")) + "/" + str(action.get("phase", "")) if not action.is_empty() else ""
		seen[current] = true
		if current == "enjoy_outdoors/active": wet_on_exit = sim.wetness
		if person._drips.emitting: dripped = true
		minimum_stock = mini(minimum_stock, int(rack.towels))
		if person._towel_wrap.visible: wrapped_seen = true
		if person._towel_carry.visible: held_seen = true
		if current == "dry_sit/active":
			seated_seen = true
			sat_anchor = str(person._activity_anchor.get("kind", ""))
		if frame > 200 and sim.action_queue.is_empty() and sim.towel.is_empty() and sim.wetness <= 0.0: break
	check(seen.has("enjoy_outdoors/active"), "They swim.")
	check(wet_on_exit >= 1.0, "In the water they are soaked.")
	check(dripped, "Water drips off them when they get out.")
	check(seen.has("dry_off/approach"), "Coming out, they walk to the towel rack.")
	check(seen.has("dry_off/active"), "They take a towel and dry off.")
	check(minimum_stock == stocked_before - 1, "One towel came off the rack while it was in use (%d -> %d)." % [stocked_before, minimum_stock])
	check(held_seen, "The towel is shown in their hands as they take it…")
	check(wrapped_seen, "…and then wrapped round them.")
	check(seen.has("dry_sit/approach"), "Wrapped in the towel, they go to sit down.")
	check(seated_seen and sat_anchor == "seat", "They sit on the seat to finish drying (%s)." % sat_anchor)
	check(sim.wetness <= 0.0, "They end dry.")
	check(sim.towel.is_empty() and int(rack.towels) == stocked_before, "The towel is hung back on the rack (%d)." % int(rack.towels))
	check(str(sim.character.outfit_category) == "everyday", "Dry, they are back in everyday clothes (%s)." % str(sim.character.outfit_category))
	check(app.household.sanitation.puddles.is_empty(), "A towelled Lifelet leaves no puddle.")
	check(not person._towel_wrap.visible, "The towel is gone from their body.")


func _puddle() -> void:
	var id: String = app.household.selected_id()
	var person: LifeActor = app.world.actors[id]
	var sim: LifeSim = app.sim
	sim.action_queue.clear()
	sim.towel = {}
	var seat: Dictionary = {}
	for entry: Dictionary in app.world.items:
		if str(entry.kind) == "bench": seat = entry
	check(not seat.is_empty(), "There is a seat to sit on.")
	if seat.is_empty(): return
	# Soaking wet, no towel, straight onto the seat: it takes a while, then the puddle.
	sim.wetness = 1.0
	check(sim.queue_action("relax", str(seat.id), app.world.approach(seat)), "A wet Lifelet sits down without drying off.")
	var made: bool = false
	for frame: int in range(4000):
		app._process(DT)
		if not app.household.sanitation.puddles.is_empty():
			made = true
			break
	check(made, "Sitting damp for too long leaves a puddle.")
	if not made: return
	var puddle: Dictionary = app.household.sanitation.puddles[0]
	check(str(puddle.get("kind", "")) == "water", "It is a puddle of water (%s)." % str(puddle.get("kind", "")))
	check(app.household.sanitation.validate(app.household.sanitation.get_state(), app.household.members.map(func(member: Dictionary) -> String: return str(member.id)), [], 1e9).is_empty(), "A water puddle passes the save validator.")
	sim.action_queue.clear()
	await frames(2)
	app._process(DT)
	var puddle_item: Dictionary = app._find_item(str(puddle.id))
	check(not puddle_item.is_empty() and str(puddle_item.label) == "Water puddle", "The puddle is on the floor, named as water.")
	check(str(sim.get_actions_for("puddle", str(puddle.id))[0].id) == "mop_puddle", "It can be mopped.")
	check(sim.queue_action("mop_puddle", str(puddle.id), app.world.approach(puddle_item)), "Somebody is sent to mop it.")
	for frame: int in range(3000):
		app._process(DT)
		if app.household.sanitation.puddles.is_empty(): break
	check(app.household.sanitation.puddles.is_empty(), "Mopping cleans it up.")


## A loose beach towel on the ground works the same way: the Lifelet picks it up, wraps
## up in it, and it is put back where it lay when they are dry.
func _loose_towel() -> void:
	var rack: Dictionary = app._find_item("rack_pool")
	if not rack.is_empty(): app.world.remove_item("rack_pool")
	var pool: Dictionary = app._find_item("t_pool")
	var centre: Vector3 = pool.node.global_position
	var towel: Dictionary = _place("beach_towel", [Vector2(centre.x + 3.6, centre.z - 2.4), Vector2(centre.x - 3.6, centre.z - 2.4), Vector2(centre.x + 3.6, centre.z + 3.0), Vector2(centre.x - 3.6, centre.z + 3.0), Vector2(centre.x, centre.z - 3.4)], {"id": "loose_towel", "style": "b", "color": "d9a0a0"})
	check(not towel.is_empty(), "A beach towel lies on the ground by the pool.")
	if towel.is_empty(): return
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	await frames(2)
	var id: String = app.household.selected_id()
	var person: LifeActor = app.world.actors[id]
	var sim: LifeSim = app.sim
	sim.action_queue.clear()
	sim.towel = {}
	sim.wetness = 1.0
	check(bool(sim.get_action_availability(LifeWetness.DRY_OFF_ID, "loose_towel").available), "A wet Lifelet may dry off with the loose towel.")
	check(sim.queue_action(LifeWetness.DRY_OFF_ID, "loose_towel", app.world.approach(towel)), "They are sent to it.")
	var picked_up: bool = false
	var wrapped: bool = false
	for frame: int in range(3000):
		app._process(DT)
		if bool(towel.get("carried", false)):
			picked_up = true
			check(not towel.node.visible or picked_up, "The towel leaves the ground while it is in use.")
		if person._towel_wrap.visible: wrapped = true
		if frame > 60 and sim.action_queue.is_empty() and sim.towel.is_empty() and sim.wetness <= 0.0: break
	check(picked_up and wrapped, "They pick the towel up and wrap it round themselves.")
	check(not bool(towel.get("carried", false)) and towel.node.visible, "When they are dry it is back on the ground where it lay.")
	check(sim.wetness <= 0.0 and sim.towel.is_empty(), "They end dry with no towel still held.")
	app.world.remove_item("loose_towel")
