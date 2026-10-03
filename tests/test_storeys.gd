extends SceneTree
## Storeys and stairs: with everything put in storage, a staircase on the ground
## floor just works — it needs no floor or walls upstairs, it brings its own
## landing — and Add storey raises the house up to four storeys, the new floor,
## the outer walls and the roof going up each time. Stairs then join every storey,
## Lifelets route to the top, furniture stands on the highest floor, each floor is
## viewed on its own, and a save keeps the whole house.
##
##   JUSTLIFE_DATA_DIR=/tmp/x XDG_DATA_HOME=/tmp/y godot --headless --path . --audio-driver Dummy --script res://tests/test_storeys.gd

const Building = preload("res://scripts/building_state.gd")
const Navigation = preload("res://scripts/lot_navigation.gd")
const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)


func frames(n: int = 3) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("This test needs an isolated JUSTLIFE_DATA_DIR.")
		quit(2)
		return
	_run.call_deferred()


func _state() -> Dictionary:
	return app.world.construction.building_state


func _on_level(group: String, level: int) -> Array:
	return _state()[group].filter(func(record: Dictionary) -> bool: return int(record.get("level", -1)) == level)


## The first of these staircase spots the whole-house quote accepts, committed.
func _buy_stair(lower: int, spots: Array) -> Dictionary:
	for spot: Vector2 in spots:
		for rotation: int in [0, 180, 90, 270]:
			var quote: Dictionary = app.build_transactions.prepare({"op": "add", "collection": "stairs", "record": {"x": spot.x, "z": spot.y, "rotation": rotation, "lower": lower}})
			if not bool(quote.ok):
				continue
			var result: Dictionary = app.build_transactions.commit(quote)
			if not bool(result.ok):
				continue
			app.build_undo.append({"architecture": result.receipt, "level": app.world.view_level})
			app._refresh_sim_targets(false)
			for stair: Dictionary in _state().stairs:
				if int(stair.lower) == lower and is_equal_approx(float(stair.x), spot.x) and is_equal_approx(float(stair.z), spot.y):
					return {"stair": stair, "cost": int(result.cost)}
	return {}


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_funds(200000)
	app.set_build_mode(true)
	await frames(2)

	# ---- everything in storage, then stairs on the ground floor
	for item: Dictionary in app.world.items.duplicate():
		app.store_item(item)
	check(app.world.items.is_empty(), "Everything in the home is put in storage (%d left)" % app.world.items.size())
	app.set_build_level(0)
	check(app.world.view_level == 0 and not app.world.construction.has_upper_floor(), "Building on the ground floor, with no upper floor at all")
	app.begin_construction("stairs")
	var tool_valid: int = 0
	var tool_spots: int = 0
	var first_refusal: String = ""
	for x: float in [-4.0, -2.0, 2.0, 4.0]:
		for z: float in [-3.0, 1.0]:
			tool_spots += 1
			app.world.construction.update_preview(Vector3(x, .16, z))
			if bool(app.world.construction.proposal.get("valid", false)):
				tool_valid += 1
			elif first_refusal.is_empty():
				first_refusal = str(app.world.construction.proposal.get("error", ""))
	check(tool_valid >= tool_spots / 2, "The Stairs tool offers ground-floor stairs with no floor or walls upstairs (%d of %d spots; %s)" % [tool_valid, tool_spots, first_refusal])
	app.world.construction.cancel()
	var funds_before: int = app.household.funds
	var bought: Dictionary = _buy_stair(0, [Vector2(-4.0, -3.0), Vector2(-4.5, -3.0), Vector2(-3.5, -2.5), Vector2(2.0, -3.0), Vector2(4.0, -3.0)])
	check(not bought.is_empty(), "A ground-floor staircase is bought in the empty home")
	if bought.is_empty():
		_finish()
		return
	var stair: Dictionary = bought.stair
	var landing: Array = _state().floors.filter(func(floor: Dictionary) -> bool: return str(floor.get("landing_for", "")) == str(stair.id))
	check(landing.size() == 1 and int(landing[0].level) == 1 and Building.rect(landing[0]).encloses(Building.landing_rect(stair, true)), "It brings its own landing slab upstairs, round the opening, the landing and the rail")
	check(_on_level("walls", 1).is_empty(), "No upstairs walls were needed")
	var forged: Dictionary = _state().duplicate(true)
	for floor: Dictionary in forged.floors:
		if floor.get("landing_for") != null: floor.landing_for = "stairs_missing"
	check(not Building.validate(forged).is_empty(), "A landing that names no real staircase is refused, so it cannot float on its own")
	var stretched: Dictionary = _state().duplicate(true)
	for floor: Dictionary in stretched.floors:
		if floor.get("landing_for") != null: floor.w = float(floor.w) + 6.0
	check(not Building.validate(stretched).is_empty(), "Nor can a landing grow past the stairs' own opening, landing and rail")
	var on_landing: Dictionary = Building.propose(_state(), {"op": "add", "collection": "floors", "record": {"level": 2, "x": float(landing[0].x), "z": float(landing[0].z), "w": 1.0, "d": 1.0, "material": "cfa97e"}}, 100000)
	check(not bool(on_landing.ok), "A landing holds up no floor above it")
	var tagged: Dictionary = Building.propose(_state(), {"op": "add", "collection": "floors", "record": {"level": 1, "x": 8.0, "z": 8.0, "w": 2.0, "d": 2.0, "material": "cfa97e", "landing_for": str(stair.id)}}, 100000)
	check(not bool(tagged.ok), "A new floor cannot claim to be a staircase's landing")
	check(int(bought.cost) > 650 and app.household.funds == funds_before - int(bought.cost), "The landing is priced with the stairs (ℒ%d)" % int(bought.cost))
	check(app.world.lot_navigation.stair_connected(str(stair.id)), "Lifelets can really use it: the route graph joins the ground floor to the landing")
	var foot: Vector3 = app.world.nearest_clear_point(Building.stair_point(stair, -.9), 0, 6)
	var head: Vector3 = app.world.nearest_clear_point(Building.stair_point(stair, Building.STAIR_RUN + .5, Building.RISE), 1, 4)
	var climb: Dictionary = app.world.lot_navigation.route(Navigation.floor_location(0, foot), Navigation.floor_location(1, head))
	check(bool(climb.get("ok", false)) and climb.segments.any(func(segment: Dictionary) -> bool: return str(segment.kind) == "stair"), "A route climbs the stairs to the landing")

	# ---- removing that staircase takes its landing with it
	var remove: Dictionary = app.build_transactions.prepare({"op": "remove", "id": str(stair.id)})
	check(bool(remove.ok) and int(remove.cost) < -250 and remove.after.floors.filter(func(floor: Dictionary) -> bool: return int(floor.level) == 1).is_empty(), "Removing the stairs also removes and refunds their landing (ℒ%d)" % -int(remove.get("cost", 0)))
	if bool(remove.ok):
		app.build_transactions.commit(remove)
		app._refresh_sim_targets(false)
	check(_state().stairs.is_empty() and _on_level("floors", 1).is_empty(), "The home is back to one storey")

	# ---- storeys added up to four, the roof going up with them
	var storey_costs: Array = []
	for expected: int in [1, 2, 3]:
		var quote: Dictionary = app.build_transactions.prepare({"op": "add_storey"})
		check(bool(quote.ok) and int(quote.level) == expected, "Add storey quotes the %s (%s)" % [app.storey_name(expected), str(quote.get("error", ""))])
		if not bool(quote.ok):
			continue
		var paid: int = app.household.funds
		var result: Dictionary = app.build_transactions.commit(quote)
		check(bool(result.ok) and app.household.funds == paid - int(quote.cost), "The %s is built and paid for (ℒ%d)" % [app.storey_name(expected), int(quote.cost)])
		storey_costs.append(int(quote.cost))
		var floors: Array = _on_level("floors", expected)
		var walls: Array = _on_level("walls", expected)
		check(floors.size() >= 1 and Building.rect(floors[0]).encloses(Rect2(-6, -5, 12, 10)), "The %s has a floor over the whole house below" % app.storey_name(expected))
		var outer: int = 0
		for wall: Dictionary in walls:
			var r: Rect2 = Building.rect(wall)
			if absf(absf(r.get_center().x) - 6.04) < .05 or absf(absf(r.get_center().y) - 5.04) < .05:
				outer += 1
		check(outer == 4 and walls.size() == 4, "Its four outer walls go up on the lines of the walls below, whole, with no doorway holes (%d walls)" % walls.size())
		if expected == 1:
			var first_walls: Array = _on_level("walls", 1)
			var roof_quote: Dictionary = {}
			for first: Dictionary in first_walls:
				for second: Dictionary in first_walls:
					if str(first.id) == str(second.id) or not roof_quote.is_empty():
						continue
					var record: Dictionary = {"level": 1, "x": 0.0, "z": 0.0, "w": 12.08, "d": 10.08, "pitch": .5, "rotation": 0, "material": "57736a", "style": "gabled", "supports": [str(first.id), str(second.id)]}
					var trial: Dictionary = app.build_transactions.prepare({"op": "add", "collection": "roofs", "record": record})
					if bool(trial.ok):
						roof_quote = trial
			check(not roof_quote.is_empty(), "The first floor can carry a gable roof on its raised walls")
			if not roof_quote.is_empty():
				app.build_transactions.commit(roof_quote)
			app._refresh_sim_targets(false)
		var roofs: Array = _state().roofs
		check(roofs.size() == 1 and int(roofs[0].level) == expected, "The roof is on the %s" % app.storey_name(expected))
		check(roofs.size() == 1 and Building._perimeter_support_error(_state(), roofs[0], expected).is_empty(), "And it rests on the %s's new walls" % app.storey_name(expected))
		check(Building.validate(_state()).is_empty(), "The four-storey building stays valid: %s" % Building.validate(_state()))
	var fifth: Dictionary = app.build_transactions.prepare({"op": "add_storey"})
	check(not bool(fifth.ok) and str(fifth.get("error", "")).contains("four storeys"), "A fifth storey is refused: %s" % str(fifth.get("error", "")))
	check(Building.top_level(_state()) == 3, "The home has four storeys")

	# ---- stairs join every storey, and a Lifelet can route to the top
	var flights: Array = []
	for lower: int in [0, 1, 2]:
		app.set_build_level(lower)
		var spots: Array = [Vector2(-4.0, -3.0), Vector2(-4.5, -3.5)] if lower == 0 else ([Vector2(0.0, -3.5), Vector2(.5, -3.0)] if lower == 1 else [Vector2(4.0, -3.5), Vector2(3.5, -3.0)])
		var flight: Dictionary = _buy_stair(lower, spots)
		check(not flight.is_empty(), "Stairs climb from the %s to the %s" % [app.storey_name(lower), app.storey_name(lower + 1)])
		if not flight.is_empty():
			flights.append(flight.stair)
			check(app.world.lot_navigation.stair_connected(str(flight.stair.id)), "The flight from the %s is walkable" % app.storey_name(lower))
	var bottom: Vector3 = app.world.nearest_clear_point(Vector3(0, .16, 3.0), 0, 8)
	var top: Vector3 = app.world.nearest_clear_point(Vector3(0, Building.level_y(3), 3.0), 3, 8)
	var all_the_way: Dictionary = app.world.lot_navigation.route(Navigation.floor_location(0, bottom), Navigation.floor_location(3, top))
	var climbed: Dictionary = {}
	for segment: Dictionary in all_the_way.get("segments", []):
		if str(segment.kind) == "stair":
			climbed[str(segment.stair_id)] = true
	check(bool(all_the_way.get("ok", false)) and climbed.size() == 3, "A route climbs all three flights from the ground floor to the third floor")
	app.set_build_mode(false)
	await frames(2)
	app.sim.autonomy = false
	var actor: LifeActor = app.player
	app.household.set_speed(3)
	app.on_ground_clicked(top)
	check(app.walk_only and not app.path.is_empty(), "The Lifelet is sent walking to the top floor (%s)" % app.notice_text)
	var reached: bool = false
	for frame: int in 9000:
		app._process(DT)
		if frame % 10 == 0:
			await process_frame
		if app.world.point_level(actor.position) == 3 and actor.position.distance_to(top) < .3:
			reached = true
			break
	check(reached, "The Lifelet climbs the stairs all the way to the third floor (at level %d)" % app.world.point_level(actor.position))
	app.household.set_speed(0)
	check(app.sanitation_flow.accident(app.sim) and app.household.sanitation.puddles.any(func(puddle: Dictionary) -> bool: return int(puddle.level) == 3), "An accident up there leaves its puddle on the third floor")

	# ---- each floor is viewed on its own
	check(app.world.set_view_level(3), "The third floor can be viewed")
	var mask: int = app.world.camera.cull_mask
	check(mask & LifeWorld.VIEW_LEVELS[3] != 0 and mask & LifeWorld.VIEW_LEVELS[0] != 0 and mask & LifeWorld.VIEW_ACTOR_LEVELS[3] != 0 and mask & LifeWorld.VIEW_ACTOR_LEVELS[0] == 0, "Viewing the top shows every storey's structure and the Lifelets up there")
	check(app.world.set_view_level(1) and app.world.camera.cull_mask & LifeWorld.VIEW_LEVELS[3] == 0, "Viewing the first floor hides the storeys above it")
	var third_wall: Dictionary = _on_level("walls", 3)[0] if not _on_level("walls", 3).is_empty() else {}
	var wall_node: Node3D = app.world.construction.wall_nodes.get(str(third_wall.get("id", "")))
	var layered: bool = false
	if is_instance_valid(wall_node):
		for mesh: Node in wall_node.find_children("*", "VisualInstance3D", true, false):
			layered = (mesh as VisualInstance3D).layers == LifeWorld.VIEW_LEVELS[3]
			break
	check(layered, "A third-floor wall is drawn on the third floor's own layer")
	app.world.set_view_level(0)

	# ---- furniture on the top floor, and the storey stepper
	app.set_build_mode(true)
	await frames(2)
	app.set_build_level(3)
	check(app.world.view_level == 3, "Build mode steps up to the third floor")
	app.on_placement("plant", Vector3(-1.5, Building.level_y(3), 2.5), 0.0)
	var plant: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "plant":
			plant = item
	check(not plant.is_empty() and app.world.item_level(plant) == 3 and is_equal_approx(plant.node.global_position.y, Building.level_y(3)), "A plant placed upstairs stands on the third floor")
	app.draw_live()
	await frames(1)
	var up: Button = app.ui.find_child("BuildLevelUp", true, false)
	var down: Button = app.ui.find_child("BuildLevelDown", true, false)
	check(is_instance_valid(up) and up.disabled and is_instance_valid(down) and not down.disabled and down.text == "Down", "At the top the Up button is off and Down steps down a storey")
	app.show_add_storey()
	await frames(1)
	var confirm: Button = app.overlay.find_child("AddStoreyConfirm", true, false)
	check(is_instance_valid(confirm) and confirm.disabled and app.overlay.find_child("AddStoreyRefusal", true, false) != null, "The Add storey card says a fifth storey cannot be built")
	app.close_overlay()

	# ---- the whole house survives a save
	var facts: Dictionary = _state().duplicate(true)
	check(app.save_game("", "Four storeys"), "The four-storey home saves")
	var epoch: int = app.load_epoch
	app.load_game(app.active_save_id)
	await frames(3)
	check(app.load_epoch == epoch + 1, "And loads")
	var loaded: Dictionary = _state()
	check(loaded.floors.size() == facts.floors.size() and loaded.walls.size() == facts.walls.size() and loaded.stairs.size() == 3 and loaded.roofs.size() == 1 and int(loaded.roofs[0].level) == 3, "The loaded home keeps its storeys, walls, three flights and the roof on top")
	check(app.household.sanitation.puddles.any(func(puddle: Dictionary) -> bool: return int(puddle.level) == 3), "The third-floor puddle survives the save")
	var kept_plant: bool = false
	for item: Dictionary in app.world.items:
		if str(item.kind) == "plant" and app.world.item_level(item) == 3:
			kept_plant = true
	check(kept_plant, "The plant is still on the third floor")
	check(app.world.point_level(app.player.position) == 3, "The Lifelet is still upstairs")
	await _large_home()
	_finish()


## A fuller home: more furnishings than the old thirty-item storage unit held.
## All of it goes into storage, and stairs still just work on the ground floor.
func _large_home() -> void:
	app.queue_free()
	await process_frame
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Bo Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_funds(200000)
	app.set_build_mode(true)
	await frames(2)
	# Furnish it past thirty pieces, as a bigger home is (the large starters hold 33 to 53).
	for index: int in 14:
		app.world.add_item({"id": "extra_plant_%d" % index, "kind": "plant", "x": -9.0 + float(index % 7) * 1.5, "z": 7.0 + float(index / 7) * 1.2, "rotation": 0.0}, false)
	app.world.rebuild_navigation()
	app._refresh_sim_targets(false)
	var furnished: int = app.world.items.size()
	for item: Dictionary in app.world.items.duplicate():
		app.store_item(item)
	check(furnished > 30 and app.world.items.is_empty() and app.household_flow.storage_count() == furnished, "A home with %d furnishings is emptied into storage completely (%d stored)" % [furnished, app.household_flow.storage_count()])
	app.set_build_level(0)
	var stair: Dictionary = _buy_stair(0, [Vector2(-4.0, -3.0), Vector2(-2.0, -3.0), Vector2(2.0, -3.0), Vector2(4.0, -3.0), Vector2(-4.0, 1.0), Vector2(2.0, 1.0)])
	check(not stair.is_empty(), "And a ground-floor staircase goes straight in")


func _finish() -> void:
	print("STOREYS %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures:
		print("  FAILED: ", failure)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
