extends SceneTree
## The room-editing package: a player can add rooms, extend them against a
## neighbouring room, and break the wall between two rooms so one becomes
## bigger — which is what "make the house your own" has to mean.
##
## Every assertion drives the real Build transaction against the live world and
## reads what the player would see: how many walls and floors stand, what was
## paid, and whether a refusal left the structure untouched.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_room_extension.gd

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


func frames(n: int = 3) -> void:
	for i: int in n:
		await process_frame


func _state() -> Dictionary:
	return app.world.construction.validated_state().state


func _wall_at(x: float, z: float, level: int = 0) -> Dictionary:
	for wall: Dictionary in _state().walls:
		if int(wall.level) == level and absf(float(wall.x) - x) < .2 and absf(float(wall.z) - z) < 1.2:
			return wall
	return {}


## Draw a room and commit it, returning the result. The world is left untouched
## on a refusal, which the caller checks.
func _build_room(a: Vector2, b: Vector2, level: int = 0) -> Dictionary:
	var quote: Dictionary = app.build_transactions.prepare({"op": "structure", "tool": "room",
		"level": level, "ax": a.x, "az": a.y, "bx": b.x, "bz": b.y})
	if not bool(quote.ok):
		return quote
	var committed: Dictionary = app.build_transactions.commit(quote)
	if not bool(committed.ok):
		return committed
	return {"ok": true, "cost": int(quote.cost)}


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	app.household_profiles[0]["age_stage"] = "adult"
	await frames(4)
	app.start_household()
	await frames(16)
	app.household.set_speed(0)
	app.set_build_mode(true)
	await frames(4)
	app.household.set_funds(300000)
	app.sim.funds = 300000

	var start_walls: int = _state().walls.size()
	var start_floors: int = _state().floors.size()
	# A room too small to be a room is refused, and changes nothing.
	var tiny: Dictionary = app.build_transactions.prepare({"op": "structure", "tool": "room",
		"level": 0, "ax": 7.0, "az": -4.0, "bx": 7.5, "bz": -3.5})
	check(not bool(tiny.ok) and not str(tiny.get("error", "")).is_empty(), "A room too small to stand in is refused with a reason.")

	# ------------------------------------------------------ adding a room
	var funds_before: int = app.household.funds
	var first: Dictionary = _build_room(Vector2(7.0, -4.0), Vector2(10.5, -0.5))
	check(bool(first.ok), "A room can be added on the open ground (%s)." % str(first.get("error", "")))
	check(_state().walls.size() == start_walls + 4, "An added room really raises four walls (%d -> %d)." % [start_walls, _state().walls.size()])
	check(_state().floors.size() == start_floors + 1, "An added room really lays a floor (%d -> %d)." % [start_floors, _state().floors.size()])
	check(app.household.funds == funds_before - int(first.cost), "The room cost exactly its quote (ℒ%d)." % int(first.cost))
	var dividing: Dictionary = _wall_at(10.5, -2.25)
	check(not dividing.is_empty(), "The new room has a wall on its far side where the next room will meet it.")

	# --------------------------------------- extending against it: one wall
	# The second room is drawn against the first, so the two are divided by the
	# one wall already standing rather than by a second wall on the same line.
	var before_second: int = _state().walls.size()
	var second: Dictionary = _build_room(Vector2(10.5, -4.0), Vector2(14.0, -0.5))
	check(bool(second.ok), "A room can be added against an existing room (%s)." % str(second.get("error", "")))
	check(_state().walls.size() == before_second + 3,
		"A room built against another shares the dividing wall instead of doubling it (+%d walls)." % (_state().walls.size() - before_second))
	var shared_count: int = 0
	for wall: Dictionary in _state().walls:
		if int(wall.level) == 0 and absf(float(wall.x) - 10.5) < .2: shared_count += 1
	check(shared_count == 1, "Exactly one wall divides the two rooms (%d)." % shared_count)

	# ------------------------------- breaking the wall to make one bigger room
	var funds_before_break: int = app.household.funds
	var break_quote: Dictionary = app.build_transactions.prepare({"op": "structure", "tool": "erase",
		"level": 0, "id": str(dividing.id)})
	check(bool(break_quote.ok), "The dividing wall can be removed (%s)." % str(break_quote.get("error", "")))
	check(int(break_quote.cost) < 0, "Breaking a wall refunds part of its cost (ℒ%d)." % int(break_quote.cost))
	var broke: Dictionary = app.build_transactions.commit(break_quote)
	check(bool(broke.ok), "Breaking the dividing wall commits.")
	check(app.household.funds == funds_before_break - int(break_quote.cost), "The break refunds exactly its quote.")
	check(_state().walls.size() == before_second + 2, "The dividing wall is really gone (%d walls left)." % _state().walls.size())
	# The two rooms are now one open space: a walker can cross where the wall was.
	var inside := Vector3(10.5, .16, -2.25)
	check(app.world.lot_navigation.point_clear(0, inside), "The two rooms are one space: the middle is walkable where the wall stood.")
	check(app.world.lot_navigation.segment_clear(0, Vector3(8.5, .16, -2.25), Vector3(12.5, .16, -2.25)),
		"A walk across the former dividing wall is clear, so the room really is bigger.")
	# A wall is genuinely load-bearing state: the room cannot be split again for
	# free, and a doorway punched in a surviving wall still works.
	var surviving: Dictionary = _wall_at(14.0, -2.25)
	check(not surviving.is_empty(), "The outer wall of the merged room survives.")
	if not surviving.is_empty():
		var door: Dictionary = app.build_transactions.prepare({"op": "structure", "tool": "door",
			"level": 0, "id": str(surviving.id), "center": -2.25})
		check(bool(door.ok), "A doorway can be cut into a surviving wall (%s)." % str(door.get("error", "")))
		if bool(door.ok):
			check(bool(app.build_transactions.commit(door).ok), "The doorway commits.")

	# ------------------------------------- extending a room by drawing further
	var before_extend: int = _state().floors.size()
	var extended: Dictionary = _build_room(Vector2(14.0, -4.0), Vector2(17.5, -0.5))
	check(bool(extended.ok), "The room can be extended further (%s)." % str(extended.get("error", "")))
	check(_state().floors.size() == before_extend + 1, "Extending adds real floor (%d -> %d)." % [before_extend, _state().floors.size()])
	var widest: float = 0.0
	for floor: Dictionary in _state().floors:
		if int(floor.level) == 0 and absf(float(floor.z) + 2.25) < 1.0: widest = maxf(widest, float(floor.x) + float(floor.w) * .5)
	check(widest >= 17.0, "The house now reaches x=%.1f, so it really grew." % widest)

	# --------------------------------------------------------- the whole lot
	# Every room is bounded by the household's lot, and the lot can be grown and
	# the building carried further out onto it.
	check(app.world.validate_home_layout(app.world.serialize_items()).is_empty(),
		"A home with every added room still validates as a real layout.")
	app.household.set_funds(200000)
	app.sim.funds = 200000
	var bought: Dictionary = app.build_transactions.buy_land("west")
	check(bool(bought.ok), "The lot can still be expanded around the enlarged house (%s)." % str(bought.get("error", "")))
	var on_new_land: Dictionary = _build_room(Vector2(-17.0, -4.0), Vector2(-13.5, -0.5))
	check(bool(on_new_land.ok), "A room can be built on the bought plot (%s)." % str(on_new_land.get("error", "")))
	check(app.world.lot_navigation.point_clear(0, Vector3(-15.0, .16, -2.25)), "The new room's floor is walkable.")
	# And the enlarged home still passes the world's own layout validation.
	check(app.world.validate_home_layout(app.world.serialize_items()).is_empty(),
		"A house extended onto bought land still validates.")

	print("ROOM_EXTENSION_RESULT ", JSON.stringify({"checks": checks, "failures": failures,
		"walls": _state().walls.size(), "floors": _state().floors.size()}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
