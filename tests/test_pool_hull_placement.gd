extends SceneTree
## A pool's coping reaches past the footprint the catalogue declares, and walkers
## and clicks meet that measured hull. Everything else judges the declared footprint,
## as it always has, so a pool bought where the placement rule allowed it never makes
## the home unbuildable, the save unloadable or a later purchase impossible, and the
## standing spot beside it is never inside it.
##
##   JUSTLIFE_DATA_DIR=/tmp/x XDG_DATA_HOME=/tmp/y godot --headless --audio-driver Dummy --path . --script res://tests/test_pool_hull_placement.gd

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
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_funds(50000)
	app.set_build_mode(true)
	await frames(2)
	_hull_versus_footprint()
	await _pool_beside_the_house()
	await _every_size_reachable()
	print("POOL_HULL_PLACEMENT %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: print("  FAILED: ", failure)
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)


func _hull_versus_footprint() -> void:
	var walking: Array = LifeCatalog.local_panels("pool", "small", "classic")
	var declared: Array = LifeCatalog.local_panels("pool", "small", "classic", false)
	check(float(walking[0].w) > float(declared[0].w) and float(walking[0].d) > float(declared[0].d), "A walker meets a pool's measured hull, which is bigger than its declared footprint (%.1f x %.1f against %.1f x %.1f)." % [float(walking[0].w), float(walking[0].d), float(declared[0].w), float(declared[0].d)])
	var entry: Dictionary = {"kind": "pool", "x": -12.0, "z": 0.0, "rotation": 0.0, "size": "large", "style": "classic"}
	var solid: Rect2 = app.world.furnishing_panels(entry)[0]
	var footprint: Rect2 = app.world.furnishing_panels(entry, false)[0]
	check(solid.size.x > footprint.size.x and solid.encloses(footprint), "The walking hull of a large pool encloses its declared footprint.")
	for kind: String in ["pool", "hot_tub", "pool_slide"]:
		var data: Dictionary = LifeCatalog.get_item(kind)
		var style: String = str(LifeCatalogVariants.styles(data)[0])
		var probe: Dictionary = {"kind": kind, "x": -10.0, "z": 2.0, "rotation": 0.0, "style": style, "size": "small"}
		var reach: float = app.world.front_extent(kind, "small", style)
		var spot: Vector3 = app.world.layout_approach(probe)
		var hull: Rect2 = app.world.furnishing_panels(probe)[0]
		check(not hull.has_point(Vector2(spot.x, spot.z)), "The standing spot in front of a %s lies outside its hull." % kind)
		check(reach >= float(data.size.y) * .5, "…measured from the piece's real front edge (%.2f m)." % reach)


## The first hazard: a small pool bought beside the west wall, where the declared
## footprint fits, must not make the home unbuildable or the save unloadable once the
## home has been converted for building.
func _pool_beside_the_house() -> void:
	var wall_x: float = 1e9
	for record: Dictionary in app.world.construction.records:
		if int(record.get("level", 0)) == 0 and float(record.d) > float(record.w): wall_x = minf(wall_x, float(record.x))
	var at := Vector3(-8.25, LifeBuildingState.level_y(0), 0.0)
	var placed: bool = false
	for x: float in [-8.25, -8.5, -8.75, -9.0, -9.5]:
		at.x = x
		if app.world.can_place("pool", at, 0.0, "classic", "small"):
			var funds: int = app.sim.funds
			app.world.begin_placement("pool", "classic", "small", "7fb8c6")
			app.on_placement("pool", at, 0.0, "classic", "small")
			app.world.clear_placement()
			placed = app.sim.funds < funds
			break
	check(placed, "A small pool is bought beside the house.")
	if not placed: return
	# Any structural preparation converts the home to a versioned building: the check
	# that used to fail with 'A furnishing intersects a wall or stair run.'
	app.set_build_level(0)
	await frames(2)
	var error: String = app.world.validate_home_layout(app.world.serialize_items())
	check(error.is_empty(), "The home with a pool beside it still validates once converted (%s)." % error)
	check(app.build_transactions.furnishing_error(app.world.serialize_items()).is_empty(), "Buying anything else afterwards is not refused because of the pool.")
	check(app.save_game("pool_hull_probe", "Pool hull probe"), "The home saves with the pool beside the wall.")
	var pool: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "pool": pool = item
	check(not pool.is_empty(), "The pool stands in the world.")
	if not pool.is_empty():
		var spot: Vector3 = app.world.approach(pool)
		var hull: Rect2 = app.world.item_panels(pool)[0]
		check(spot.is_finite() and not hull.has_point(Vector2(spot.x, spot.z)), "Its standing spot is clear of its hull.")
		app.world.remove_item(str(pool.id))
	await frames(1)


## The second: a medium or large pool used to be refused ('That would block the way to
## the swimming pool') because its own standing spot was measured from the small footprint.
func _every_size_reachable() -> void:
	for size: String in ["small", "medium", "large"]:
		for style: String in LifeCatalogVariants.styles(LifeCatalog.get_item("pool")):
			var bought: bool = false
			for spot: Vector2 in [Vector2(-12, 5), Vector2(12, 5), Vector2(-12, -6), Vector2(12, -6), Vector2(-13, 0), Vector2(13, 0), Vector2(0, -8)]:
				var at := Vector3(spot.x, LifeBuildingState.level_y(0), spot.y)
				if not app.world.can_place("pool", at, 0.0, style, size): continue
				var before: int = app.world.items.size()
				app.world.begin_placement("pool", style, size, "7fb8c6")
				app.on_placement("pool", at, 0.0, style, size)
				app.world.clear_placement()
				bought = app.world.items.size() == before + 1
				if bought:
					for item: Dictionary in app.world.items:
						if str(item.kind) == "pool": app.world.remove_item(str(item.id))
					break
			# A lot with no room for a big one refuses with room, not with the reach rule.
			if not bought:
				var refused: String = ""
				for spot: Vector2 in [Vector2(-12, 5)]:
					refused = app.build_transactions.furnishing_error(app.world.serialize_items() + [{"id": "probe_pool", "kind": "pool", "x": spot.x, "z": spot.y, "rotation": 0, "style": style, "size": size}])
				check(not refused.contains("block the way"), "A %s %s pool is never refused for blocking its own way (%s)." % [size, style, refused])
			else:
				check(true, "A %s %s pool can be bought and its way stays open." % [size, style])
