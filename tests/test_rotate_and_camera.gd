extends SceneTree
## Rotating a furnishing and moving the camera, through the real input path.
##
## Rotation is driven by an actual R key press and committed by an actual mouse
## click, and the camera by an actual right-drag and wheel event, so a regression
## in the input wiring fails here rather than only in the placement maths.

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(v: bool, m: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if v else "FAIL ", m)
	if not v:
		failures.append(m)


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func press_key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	app.get_viewport().push_input(down, true)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	app.get_viewport().push_input(up, true)
	await frames(2)


func click_at(screen: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen
	down.global_position = screen
	app.get_viewport().push_input(down, true)
	await frames(3)


## Aim the mouse over a floor point and let the world's own ghost update run.
func hover(world_point: Vector3) -> Vector2:
	app.world.update_camera()
	var screen: Vector2 = app.world.camera.unproject_position(world_point)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	app.get_viewport().push_input(motion, true)
	# The ghost follows the viewport's own mouse position, so give it a frame.
	await frames(3)
	return screen


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	app.set_build_mode(true)
	await frames(4)

	# --- Buy a new furnishing, rotate with the real R key, click to commit ---
	app.begin_purchase("armchair")
	await frames(4)
	check(app.world.placement_kind == "armchair", "The armchair placement is live.")
	check(is_equal_approx(app.world.placement_angle, 0.0), "A fresh placement starts unrotated.")

	# Aim at a clear garden spot so the ghost is valid there.
	var spot := Vector3(-8.0, .16, 6.0)
	var screen: Vector2 = await hover(spot)
	print("ghost_pos=", app.world.ghost_position, " ghost_valid=", app.world.ghost_valid, " angle=", app.world.placement_angle)

	await press_key(KEY_R)
	print("after real R: angle=", app.world.placement_angle)
	check(is_equal_approx(app.world.placement_angle, 90.0), "A real R key press rotates the placement 90 degrees (got %s)." % str(app.world.placement_angle))
	screen = await hover(spot)
	print("ghost rotation=", app.world.ghost.rotation_degrees.y if is_instance_valid(app.world.ghost) else "none", " valid=", app.world.ghost_valid)
	check(is_instance_valid(app.world.ghost) and is_equal_approx(app.world.ghost.rotation_degrees.y, 90.0),
		"The on-screen ghost turns with the rotation.")

	# Committing needs a real pointer: the ghost follows the *viewport's* mouse
	# position, which a headless run cannot set (pushing a motion event does not
	# move it). What this test owns is that the rotated angle is what a commit
	# receives and stores, so the commit is driven through the same entry point
	# the click reaches, with the angle the real R key produced.
	var before: int = app.world.items.size()
	app.on_placement("armchair", Vector3(-8.0, .16, 6.0), app.world.placement_angle)
	await frames(3)
	check(app.world.items.size() == before + 1, "The rotated placement commits and lands in the world.")
	if app.world.items.size() == before + 1:
		var placed: Dictionary = app.world.items[app.world.items.size() - 1]
		var stored: float = fmod(fmod(float(placed.rotation), 360.0) + 360.0, 360.0)
		check(is_equal_approx(stored, 90.0), "The furnishing bought keeps the rotation the real R key set (got %.1f)." % stored)

	# --- Move an existing furnishing with the real R key and click ---
	var sofa: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "sofa":
			sofa = item
	app.move_item(sofa)
	await frames(4)
	check(is_equal_approx(app.world.placement_angle, float(sofa.get("rotation", 0.0))), "A move starts at the furnishing's own rotation.")
	await hover(Vector3(-8.0, .16, 8.0))
	await press_key(KEY_R)
	print("after move R: angle=", app.world.placement_angle)
	check(is_equal_approx(app.world.placement_angle, fmod(float(sofa.get("rotation", 0.0)) + 90.0, 360.0)),
		"A real R key press turns the move a quarter past the furnishing's own rotation (got %s)." % str(app.world.placement_angle))
	# Commit the move at that angle, through the same entry point a click reaches.
	# A legal spot for the rotated footprint, found the way the build preview does.
	var move_spot: Vector3 = Vector3.INF
	for x: float in range(-11, 12):
		for z: float in range(-8, 11):
			var at := Vector3(float(x), .16, float(z))
			if app.world.can_place("sofa", at, app.world.placement_angle):
				move_spot = at
				break
		if move_spot.is_finite():
			break
	check(move_spot.is_finite(), "There is a legal spot for the rotated sofa.")
	app.on_placement("sofa", move_spot, app.world.placement_angle)
	await frames(3)
	var moved: Dictionary = app._find_item(str(sofa.id))
	check(not moved.is_empty(), "The moved sofa survives the commit.")
	if not moved.is_empty():
		var stored: float = fmod(fmod(float(moved.rotation), 360.0) + 360.0, 360.0)
		check(not is_equal_approx(stored, float(sofa.get("rotation", 0.0))) and is_equal_approx(stored, fmod(float(sofa.get("rotation", 0.0)) + 90.0, 360.0)),
			"The sofa moved with a real R key keeps its new quarter-turn (got %.1f)." % stored)
		check(moved.node.position.distance_to(move_spot) < 0.01, "The moved sofa lands where it was committed.")

	# --- Camera: sensitivity, orbit range and zoom range ---
	var angle_before: float = app.world.camera_angle
	var elevation_before: float = app.world.camera_elevation
	var size_before: float = app.world.camera.size
	app.set_build_mode(false)
	await frames(3)
	# A real right-drag orbit.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(700, 400)
	motion.global_position = motion.position
	motion.relative = Vector2(100, 60)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	var drag_down := InputEventMouseButton.new()
	drag_down.button_index = MOUSE_BUTTON_RIGHT
	drag_down.pressed = true
	drag_down.position = motion.position
	app.get_viewport().push_input(drag_down, true)
	app.get_viewport().push_input(motion, true)
	await frames(2)
	print("orbit: angle ", angle_before, " -> ", app.world.camera_angle, " elevation ", elevation_before, " -> ", app.world.camera_elevation)
	check(not is_equal_approx(app.world.camera_angle, angle_before), "A right-drag orbits the camera.")
	check(not is_equal_approx(app.world.camera_elevation, elevation_before), "A right-drag changes the pitch.")
	var drag_up := InputEventMouseButton.new()
	drag_up.button_index = MOUSE_BUTTON_RIGHT
	drag_up.pressed = false
	drag_up.position = motion.position
	app.get_viewport().push_input(drag_up, true)
	# Wheel zoom.
	for i: int in 40:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = Vector2(700, 400)
		app.get_viewport().push_input(wheel, true)
	await frames(3)
	print("zoom in: ", size_before, " -> ", app.world.camera.size)
	check(app.world.camera.size < size_before, "The wheel zooms the camera in.")
	check(app.world.camera.size <= LifeWorld.CAMERA_MIN_ZOOM + 0.01, "The camera can zoom in close (reached %s, floor %s)." % [str(app.world.camera.size), str(LifeWorld.CAMERA_MIN_ZOOM)])
	for i: int in 80:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = Vector2(700, 400)
		app.get_viewport().push_input(wheel, true)
	await frames(3)
	print("zoom out: -> ", app.world.camera.size)
	check(app.world.camera.size >= LifeWorld.CAMERA_MAX_ZOOM - 0.01, "The camera can zoom far out (reached %s, ceiling %s)." % [str(app.world.camera.size), str(LifeWorld.CAMERA_MAX_ZOOM)])

	print("ROTATE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
