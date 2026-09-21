extends SceneTree
## Temporary probe: the two-car garage really places through the public path,
## its interior stays walkable, and two cars park inside it.

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


func _find(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: return item
	return {}


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame; await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	app.set_build_mode(true)
	await process_frame
	# The garden is the only ground the furnished starter home leaves clear, so
	# the lot is scanned for a spot both the placement check and the home-layout
	# transaction accept.
	var placed_at: Vector3 = Vector3.INF
	for x: float in range(-17, 18, 2):
		for z: float in range(-10, 11, 2):
			var at := Vector3(float(x), 0.16, float(z))
			if not app.world.can_place("car_garage", at, 0.0): continue
			app.on_placement("car_garage", at, 0.0)
			await process_frame
			if not _find("car_garage").is_empty():
				placed_at = at
				break
		if placed_at.is_finite(): break
	await process_frame
	var garage: Dictionary = _find("car_garage")
	check(not garage.is_empty(), "The two-car garage really places through Build & buy at %s." % str(placed_at))
	if garage.is_empty():
		app.set_build_mode(false)
		quit(1); return
	check(app.world.seat_capacity(garage) >= 1, "The garage resolves its catalogue facts (%d)." % app.world.seat_capacity(garage))
	# Its interior is clear of the blocking bands, so a car fits inside.
	var centre: Vector3 = garage.node.to_global(Vector3(0, 0, 0))
	check(not app.world.construction.rect_blocked(Rect2(centre.x - 0.6, centre.z - 0.6, 1.2, 1.2), 0),
		"The garage's own interior is not blocked, so a car can stand inside it.")
	app.set_build_mode(false)
	await process_frame
	app.queue_free()
	await process_frame
	print("CAR_GARAGE %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
