extends SceneTree
## The home telephone and the alarm keypad hang on a wall. Buying one must let it
## be placed against any stretch of wall a person can point at, on either floor,
## in every starter home, without a snap error or a refusal.
##
## The regression this guards: the ghost's point was lifted to the piece's hang
## height before `can_place` judged it, and a point that is not on a floor level
## belongs to no level, so every hung piece was refused and the notice blamed the
## wall ("Hang this against a wall.") even while the ghost sat against one.

const Building = preload("res://scripts/building_state.gd")

const KINDS: Array[String] = ["home_phone", "burglar_alarm"]

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
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	var starters: Array = LifeProperties.starters_for([{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}])
	for lot: int in range(starters.size()):
		app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
		app.selected_lot = lot
		app.start_household()
		await frames(6)
		app.household.set_speed(0)
		app.sim.funds = 20000
		app.set_build_mode(true)
		await frames(2)
		await sweep_walls(str(starters[lot]))
		app.set_build_mode(false)
		await frames(2)
	await purchase_through_the_public_path()
	await upper_floor()
	print("WALL_ELECTRONICS %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


## Every wall long enough to carry the piece must offer at least one accepted spot
## on some side, and no accepted spot may be a level-less point.
func sweep_walls(home: String) -> void:
	var world: LifeWorld = app.world
	for kind: String in KINDS:
		var size: Vector2 = LifeCatalog.get_item(kind).size
		var walls_tested: int = 0
		var walls_accepted: int = 0
		var levels: Array = []
		for entry: Dictionary in world.construction.records:
			var level: int = int(entry.get("level", 0))
			if not levels.has(level): levels.append(level)
			var w: float = float(entry.w)
			var d: float = float(entry.d)
			var along_x: bool = w >= d
			var length: float = w if along_x else d
			if length < size.x + .7 or float(entry.get("height", 2.6)) < 1.8: continue
			walls_tested += 1
			var floor_y: float = Building.level_y(level)
			var accepted: bool = false
			for fraction: float in [.5, .3, .7]:
				for side: float in [1.0, -1.0]:
					var centre := Vector3(float(entry.x), floor_y, float(entry.z))
					var probe: Vector3 = centre
					if along_x:
						probe.x += (fraction - .5) * length
						probe.z += side * (float(entry.d) * .5 + .4)
					else:
						probe.z += (fraction - .5) * length
						probe.x += side * (float(entry.w) * .5 + .4)
					var snap: Dictionary = world.wall_snap(kind, probe, 1.0)
					if snap.is_empty(): continue
					var p: Vector3 = snap.position
					check(world.point_level(p) == level, "%s: a %s snap point sits on floor level %d, not a height" % [home, kind, level])
					if world.can_place(kind, p, float(snap.angle)): accepted = true
			if accepted: walls_accepted += 1
			else: check(false, "%s: no side of %s wall %s (%.2f m) accepts a %s" % [home, "level %d" % level, str(entry.get("id", "?")), length, kind])
		check(walls_tested > 0, "%s: at least one wall is long enough for a %s" % [home, kind])
		print("  %s %s: %d of %d walls accept it (levels %s)" % [home, kind, walls_accepted, walls_tested, str(levels)])


func purchase_through_the_public_path() -> void:
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	app.sim.funds = 20000
	app.set_build_mode(true)
	await frames(2)
	var world: LifeWorld = app.world
	for kind: String in KINDS:
		# The longest ground-floor wall with the most room in front of it.
		var best: Dictionary = {}
		for entry: Dictionary in world.construction.records:
			if int(entry.get("level", 0)) != 0: continue
			var length: float = maxf(float(entry.w), float(entry.d))
			if best.is_empty() or length > maxf(float(best.w), float(best.d)): best = entry
		check(not best.is_empty(), "There is a ground-floor wall to hang a %s on" % kind)
		if best.is_empty(): continue
		var probe := Vector3(float(best.x), Building.level_y(0), float(best.z))
		var along_x: bool = float(best.w) >= float(best.d)
		var found: Dictionary = {}
		for side: float in [1.0, -1.0]:
			var candidate: Vector3 = probe
			if along_x: candidate.z += side * (float(best.d) * .5 + .4)
			else: candidate.x += side * (float(best.w) * .5 + .4)
			var snap: Dictionary = world.wall_snap(kind, candidate, 1.0)
			if not snap.is_empty() and world.can_place(kind, snap.position, float(snap.angle)):
				found = snap
				break
		check(not found.is_empty(), "A %s can be placed on the longest ground-floor wall" % kind)
		if found.is_empty(): continue
		# The ghost the player actually drags: pointing at a spot beside the wall
		# must show a valid, raised ghost whose judged point stays on the floor.
		world.begin_placement(kind)
		world.update_ghost(found.position)
		check(world.ghost_valid, "The dragged %s ghost is valid against the wall (not refused for its height)" % kind)
		check(absf(world.ghost_position.y - Building.level_y(0)) < .001, "The judged %s point stays at floor level" % kind)
		check(absf(world.ghost.position.y - Building.level_y(0) - float(LifeCatalog.get_item(kind).hang)) < .001, "The %s ghost is drawn at its hang height" % kind)
		world.clear_placement()
		# Furniture standing against the very same wall does not stop a piece that
		# hangs above it.
		var forward: Vector3 = Basis(Vector3.UP, deg_to_rad(float(found.angle))) * Vector3(0, 0, 1)
		var under: Vector3 = found.position + forward * .55
		world.add_item({"id": "probe_fridge", "kind": "fridge", "x": under.x, "z": under.z, "rotation": float(found.angle)})
		check(world.can_place(kind, found.position, float(found.angle)), "A %s still hangs above a fridge standing under it" % kind)
		world.remove_item("probe_fridge")
		world.begin_placement(kind)
		var funds_before: int = app.sim.funds
		var items_before: int = world.items.size()
		app.on_placement(kind, found.position, float(found.angle))
		world.clear_placement()
		await frames(2)
		check(world.items.size() == items_before + 1, "Buying a %s places exactly one item" % kind)
		check(app.sim.funds == funds_before - int(LifeCatalog.get_item(kind).price), "A %s costs exactly its price" % kind)
		var placed: Dictionary = {}
		for item: Dictionary in world.items:
			if str(item.kind) == kind: placed = item
		check(not placed.is_empty(), "The placed %s is in the world" % kind)
		if not placed.is_empty():
			var hang: float = float(LifeCatalog.get_item(kind).hang)
			check(absf(placed.node.position.y - Building.level_y(0) - hang) < .01, "The placed %s hangs %.2f m up its wall" % [kind, hang])
			check(not LifeCatalog.passable(kind) == false, "A %s never blocks the way for a walker" % kind)
		# It survives a save round trip through the layout.
		var layout: Array = world.serialize_items()
		var saved_hang: float = 0.0
		for record: Dictionary in layout:
			if str(record.get("kind", "")) == kind: saved_hang = float(record.get("hang", 0.0))
		check(absf(saved_hang - float(LifeCatalog.get_item(kind).hang)) < .01, "The saved %s keeps its hang" % kind)


## The same on an upper floor, whose walls stand three metres up: the point that
## is judged is the floor of the storey the ghost is drawn on.
func upper_floor() -> void:
	var state: Dictionary = Building.fresh()
	state.floors = [{"id": "ground", "level": 0, "x": 0.0, "z": 0.0, "w": 8.0, "d": 10.0, "material": "cfa97e"}, {"id": "upper", "level": 1, "x": 0.0, "z": 0.0, "w": 8.0, "d": 10.0, "material": "dcd6c6", "supports": ["north", "south"]}]
	for level: int in [0, 1]:
		for side: int in [-1, 1]:
			state.walls.append({"id": ("upper_" if level else "") + ("north" if side < 0 else "south"), "level": level, "x": 0.0, "z": side * 5.0, "w": 8.0, "d": .14, "height": 2.6, "cut": true, "material": "eae7d7"})
	var quote: Dictionary = Building.propose(state, {"op": "add", "collection": "stairs", "record": {"x": 0.0, "z": -2.0, "rotation": 0}}, 10000)
	if bool(quote.ok): state = quote.after
	var world: LifeWorld = LifeWorld.new()
	root.add_child(world)
	await frames(2)
	var loaded: Dictionary = world.load_home([state])
	check(bool(loaded.ok), "A two-storey shell loads for the upper-floor check (%s)." % str(loaded.get("error", "")))
	if not bool(loaded.ok):
		world.queue_free()
		return
	await frames(2)
	world.set_view_level(1)
	for kind: String in KINDS:
		var pointed := Vector3(1.5, Building.level_y(1), -4.3)
		world.begin_placement(kind)
		world.build_enabled = true
		world.update_ghost(pointed)
		check(world.ghost_valid, "A %s hangs on an upper-floor wall." % kind)
		check(world.point_level(world.ghost_position) == 1, "…judged on the upper floor.")
		check(absf(world.ghost.position.y - Building.level_y(1) - float(LifeCatalog.get_item(kind).hang)) < .001, "…drawn at its hang height above that floor.")
		world.clear_placement()
	world.queue_free()
	await frames(2)
