extends SceneTree
## Build grid covers the whole owned lot; Grab wall push/pull resizes a room.
const Building = preload("res://scripts/building_state.gd")
const Land = preload("res://scripts/land.gd")
const Edits = preload("res://scripts/building_edits.gd")

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
	# Policy: south edge never grows — street/sidewalk stay put.
	var base: Rect2 = Land.rect(Land.fresh())
	var east: Dictionary = Land.fresh()
	east["east"] = 1
	var grown: Rect2 = Land.rect(east)
	check(is_equal_approx(grown.end.y, base.end.y), "Buying east land keeps the south/street edge fixed")
	check(grown.size.x > base.size.x + 1.0, "Buying east land widens the lot")
	check(not Land.SIDES.has("south"), "South/street side is not a purchasable plot")

	# Detached grab: push a room wall, stretch connectors, and grow the floor so
	# the new interior stays supported and walkable.
	var room: Dictionary = Building.fresh()
	room.walls = [
		{"id": "n", "level": 0, "x": 0.0, "z": -2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "s", "level": 0, "x": 0.0, "z": 2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "w", "level": 0, "x": -2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "e", "level": 0, "x": 2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
	]
	room.floors = [
		{"id": "f0", "level": 0, "x": 0.0, "z": 0.0, "w": 4.0, "d": 4.0, "material": "cfa97e"},
	]
	Building.set_land(Land.fresh())
	var grab: Dictionary = Edits.propose(room, {"op": "structure", "tool": "grab", "level": 0, "id": "s", "line": 3.0}, 5000)
	check(bool(grab.ok), "Grab wall quote succeeds (%s)" % str(grab.get("error", "")))
	if bool(grab.ok):
		var after: Dictionary = grab.after
		var south: Dictionary = Building.find(after, "s")
		check(is_equal_approx(float(south.z), 3.0), "Grabbed south wall moved to the new line")
		var west: Dictionary = Building.find(after, "w")
		var east_wall: Dictionary = Building.find(after, "e")
		check(is_equal_approx(float(west.d), 5.0) and is_equal_approx(float(east_wall.d), 5.0), "Connecting side walls stretch to the new south line")
		check(int(grab.cost) > 0, "Grab wall charges for the push")
		# Interior just inside the new south wall must sit on a floor slab.
		var interior := Vector2(0.0, 2.7)
		var covered: bool = false
		for floor: Dictionary in after.floors:
			if int(floor.level) != 0: continue
			if Building.rect(floor).has_point(interior):
				covered = true; break
		check(covered, "Floor covers the pushed wall's new interior at %s" % interior)
		var floor_after: Dictionary = Building.find(after, "f0")
		check(not floor_after.is_empty() and float(floor_after.d) >= 4.9, "Existing floor slab grew with the room (d=%s)" % str(floor_after.get("d", "?")))

	# Collinear doorway stubs ride with the grab so the opening stays intact.
	var doorway: Dictionary = Building.fresh()
	doorway.walls = [
		{"id": "n", "level": 0, "x": 0.0, "z": -2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "s_l", "level": 0, "x": -1.5, "z": 2.0, "w": 1.8, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "s_r", "level": 0, "x": 1.5, "z": 2.0, "w": 1.8, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "w", "level": 0, "x": -2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "e", "level": 0, "x": 2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
	]
	doorway.floors = [
		{"id": "f0", "level": 0, "x": 0.0, "z": 0.0, "w": 4.0, "d": 4.0, "material": "cfa97e"},
	]
	var door_grab: Dictionary = Edits.propose(doorway, {"op": "structure", "tool": "grab", "level": 0, "id": "s_l", "line": 3.0}, 5000)
	check(bool(door_grab.ok), "Grab on a doorway stub succeeds (%s)" % str(door_grab.get("error", "")))
	if bool(door_grab.ok):
		var left: Dictionary = Building.find(door_grab.after, "s_l")
		var right: Dictionary = Building.find(door_grab.after, "s_r")
		check(is_equal_approx(float(left.z), 3.0), "Grabbed doorway stub moved to the new line")
		check(is_equal_approx(float(right.z), 3.0), "Collinear doorway stub moved with the grab")

	# Roof footprint follows the outermost walls after a grab.
	Building.set_land(Land.fresh())
	var roofed: Dictionary = Building.fresh()
	roofed.walls = [
		{"id": "n", "level": 0, "x": 0.0, "z": -2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "s", "level": 0, "x": 0.0, "z": 2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "w", "level": 0, "x": -2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "e", "level": 0, "x": 2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
	]
	roofed.floors = [
		{"id": "f0", "level": 0, "x": 0.0, "z": 0.0, "w": 4.0, "d": 4.0, "material": "cfa97e"},
	]
	roofed.roofs = [
		{"id": "r0", "level": 0, "x": 0.0, "z": 0.0, "w": 4.0, "d": 4.0, "pitch": 0.5, "rotation": 0, "material": "57736a", "supports": ["w", "e"]},
	]
	var roof_grab: Dictionary = Edits.propose(roofed, {"op": "structure", "tool": "grab", "level": 0, "id": "s", "line": 3.0}, 5000)
	check(bool(roof_grab.ok), "Grab with a roof succeeds (%s)" % str(roof_grab.get("error", "")))
	if bool(roof_grab.ok):
		var roof: Dictionary = Building.find(roof_grab.after, "r0")
		check(not roof.is_empty() and float(roof.d) >= 4.7, "Roof depth grew with the outermost walls (d=%s)" % str(roof.get("d", "?")))
		check(absf(float(roof.z) - 0.5) < 0.2, "Roof centre shifted with the expanded footprint (z=%s)" % str(roof.get("z", "?")))

	# Empty shell (no floor yet): grab must add a slab over the new footprint.
	var shell: Dictionary = Building.fresh()
	shell.walls = [
		{"id": "n", "level": 0, "x": 0.0, "z": -2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "s", "level": 0, "x": 0.0, "z": 2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "w", "level": 0, "x": -2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "e", "level": 0, "x": 2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
	]
	var shell_grab: Dictionary = Edits.propose(shell, {"op": "structure", "tool": "grab", "level": 0, "id": "s", "line": 3.0}, 5000)
	check(bool(shell_grab.ok), "Grab on an empty shell succeeds (%s)" % str(shell_grab.get("error", "")))
	if bool(shell_grab.ok):
		var shell_interior := Vector2(0.0, 2.7)
		var shell_covered: bool = false
		for floor: Dictionary in shell_grab.after.floors:
			if int(floor.level) != 0: continue
			if Building.rect(floor).has_point(shell_interior):
				shell_covered = true; break
		check(shell_covered, "Grab adds a floor covering the new interior when none existed")
		check(shell_grab.after.floors.size() >= 1, "Empty-shell grab creates at least one floor slab")

	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)

	check(is_instance_valid(app.world.grid), "Build grid node exists after home create")
	var lot: Rect2 = Building.lot()
	check(lot.size.x >= 35.0 and lot.size.y >= 20.0, "Starter lot matches the owned land rectangle")
	# Grid lines span the lot: an eastmost vertical line sits near lot.end.x.
	var max_x: float = -999.0
	var max_z: float = -999.0
	var min_z: float = 999.0
	for child: Node in app.world.grid.get_children():
		if child is Node3D:
			max_x = maxf(max_x, (child as Node3D).position.x)
			max_z = maxf(max_z, (child as Node3D).position.z)
			min_z = minf(min_z, (child as Node3D).position.z)
	check(max_x >= lot.end.x - 1.0, "Build grid reaches the east lot edge")
	check(min_z <= lot.position.y + 1.0, "Build grid reaches the north lot edge")
	check(max_z <= lot.end.y + 0.6, "Build grid stops at the south lot edge (street stays clear)")

	# Buy an east plot: grid must rebuild to the wider lot; south bound unchanged.
	var before_south: float = lot.end.y
	app.sim.funds = 20000
	var purchase: Dictionary = app.build_transactions.buy_land("east")
	check(bool(purchase.ok), "East plot purchase succeeds (%s)" % str(purchase.get("error", "")))
	await frames(3)
	var wider: Rect2 = Building.lot()
	check(wider.size.x > lot.size.x + 10.0, "Owned lot widens after buying east")
	check(is_equal_approx(wider.end.y, before_south), "South edge still the sidewalk after plot buy")
	app.world.set_build(true)
	await frames(2)
	var wide_max_x: float = -999.0
	for child: Node in app.world.grid.get_children():
		if child is Node3D:
			wide_max_x = maxf(wide_max_x, (child as Node3D).position.x)
	check(wide_max_x >= wider.end.x - 1.0, "Rebuilt build grid covers the expanded lot")
	check(app.world.construction.snap(Vector3(wider.end.x - 1.0, 0.16, 0.0)).x > 8.0, "Construction snap uses the expanded lot, not the old ±8 m clamp")

	# Live grab through the construction quote path. Prefer an existing wall;
	# if the starter shell has none in building_state yet, place a short wall.
	var state: Dictionary = app.world.construction.building_state.duplicate(true)
	var wall_id: String = ""
	for wall: Dictionary in state.get("walls", []):
		if int(wall.get("level", 0)) != 0: continue
		if maxf(float(wall.w), float(wall.d)) >= 2.0:
			wall_id = str(wall.id); break
	if wall_id.is_empty():
		app.sim.funds = maxi(int(app.sim.funds), 5000)
		app.world.construction.quote_provider = app.build_transactions.prepare
		# Place in the newly bought east plot, clear of the starter furnishings.
		var place: Dictionary = app.build_transactions.prepare({
			"op": "structure", "tool": "wall", "level": 0,
			"ax": 20.0, "az": -2.0, "bx": 24.0, "bz": -2.0
		})
		check(bool(place.ok), "Seed wall for grab succeeds (%s)" % str(place.get("error", "")))
		if bool(place.ok):
			var placed: Dictionary = app.build_transactions.commit(place)
			check(bool(placed.ok), "Seed wall commits (%s)" % str(placed.get("error", "")))
			state = app.world.construction.building_state.duplicate(true)
			for wall: Dictionary in state.get("walls", []):
				if absf(float(wall.z) + 2.0) < 0.2 and float(wall.w) > 2.0:
					wall_id = str(wall.id); break
	check(not wall_id.is_empty(), "Home has a grab-able wall")
	if not wall_id.is_empty():
		var target: Dictionary = Building.find(app.world.construction.building_state, wall_id)
		var horizontal: bool = float(target.w) > float(target.d)
		var old_line: float = float(target.z) if horizontal else float(target.x)
		var new_line: float = old_line + (1.0 if old_line < 6.0 else -1.0)
		app.world.construction.quote_provider = app.build_transactions.prepare
		app.world.begin_construction("grab")
		app.world.construction.grab_id = wall_id
		app.world.construction.anchored = true
		var proposal: Dictionary = app.world.construction.make_proposal(Vector3(
			new_line if not horizontal else float(target.x),
			Building.level_y(0),
			new_line if horizontal else float(target.z)
		))
		check(bool(proposal.get("valid", false)), "Grab wall proposal is valid (%s)" % str(proposal.get("error", "")))
		if bool(proposal.get("valid", false)) and proposal.get("build_quote") is Dictionary:
			var committed: Dictionary = app.build_transactions.commit(proposal.build_quote)
			check(bool(committed.ok), "Grab wall commit succeeds (%s)" % str(committed.get("error", "")))
			var moved: Dictionary = Building.find(app.world.construction.building_state, wall_id)
			var moved_line: float = float(moved.z) if horizontal else float(moved.x)
			check(absf(moved_line - new_line) < 0.1, "Committed grab moves the live wall")

	# Live window rides with its host wall under Grab.
	app.sim.funds = maxi(int(app.sim.funds), 5000)
	var win_wall_quote: Dictionary = app.build_transactions.prepare({
		"op": "structure", "tool": "wall", "level": 0,
		"ax": 18.0, "az": 2.0, "bx": 26.0, "bz": 2.0
	})
	check(bool(win_wall_quote.ok), "Seed wall for window grab succeeds (%s)" % str(win_wall_quote.get("error", "")))
	if bool(win_wall_quote.ok):
		check(bool(app.build_transactions.commit(win_wall_quote).ok), "Seed wall for window grab commits")
		var win_snap: Dictionary = app.world.wall_snap("house_window", Vector3(22.0, 0.16, 2.2), 2.0)
		check(not win_snap.is_empty(), "Window snaps to the grab seed wall")
		if not win_snap.is_empty():
			app.set_build_mode(true)
			app.on_placement("house_window", win_snap.position, float(win_snap.angle), "a", "")
			await frames(2)
			var win_item: Dictionary = {}
			for item: Dictionary in app.world.items:
				if str(item.kind) == "house_window":
					win_item = item; break
			check(not win_item.is_empty(), "Window was placed for grab sync")
			var host_id: String = ""
			for wall: Dictionary in app.world.construction.building_state.get("walls", []):
				if int(wall.get("level", 0)) != 0: continue
				if absf(float(wall.z) - 2.0) < 0.15 and float(wall.w) > 2.0:
					host_id = str(wall.id); break
			check(not host_id.is_empty(), "Host wall for window grab found")
			if not host_id.is_empty() and not win_item.is_empty():
				var before_z: float = float(win_item.z)
				app.world.construction.quote_provider = app.build_transactions.prepare
				var win_grab: Dictionary = app.build_transactions.prepare({
					"op": "structure", "tool": "grab", "level": 0, "id": host_id, "line": 3.0
				})
				check(bool(win_grab.ok), "Grab quote with window succeeds (%s)" % str(win_grab.get("error", "")))
				if bool(win_grab.ok):
					check(bool(app.build_transactions.commit(win_grab).ok), "Grab with window commits")
					await frames(2)
					var after_win: Dictionary = {}
					for item: Dictionary in app.world.items:
						if str(item.id) == str(win_item.id):
							after_win = item; break
					check(not after_win.is_empty() and absf(float(after_win.z) - (before_z + 1.0)) < 0.2,
						"Window moved with its wall (z %s -> %s)" % [str(before_z), str(after_win.get("z", "?"))])

	print("BUILD_GRID_GRAB_PROBE %d/%d" % [checks - failures.size(), checks])
	for failure: String in failures:
		print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
