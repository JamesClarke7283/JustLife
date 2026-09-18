extends SceneTree
## Plates on a table, and the food left out on one, through real pointer clicks.
##
## These were all unreachable in play: a furnishing's collision box runs from the
## floor to its authored height, and the dining table's box (1.16 m) is taller
## than its own tabletop (0.847 m). A plate set down on the table therefore lay
## inside the table's box, so every click ray reached the table first and no plate
## could ever be selected — it could not be taken, cleared or put in the fridge.
## The world now resolves food and spills on their own PICK_SURFACE bit before
## the furniture ray. Each assertion below is a real dispatched mouse press, so a
## regression that re-occludes the plate fails here.

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


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func settle(n: int = 3) -> void:
	# A pick body joins the physics space on the next physics tick, not the next
	# process frame, so every click here waits for real ticks first.
	for i: int in n:
		await physics_frame


func _pick_body(node: Node) -> StaticBody3D:
	for found: Node in node.find_children("*", "StaticBody3D", true, false):
		if found is StaticBody3D and (found as StaticBody3D).has_meta("item_id"):
			return found
	return null


func _box(item: Dictionary) -> AABB:
	var body: StaticBody3D = _pick_body(item.node)
	var shape: CollisionShape3D = body.get_child(0) as CollisionShape3D
	return AABB(item.node.global_position + shape.position - (shape.shape as BoxShape3D).size * 0.5, (shape.shape as BoxShape3D).size)


func _overlay_buttons() -> Array[String]:
	var out: Array[String] = []
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node is Button and (node as Button).is_visible_in_tree():
			out.append(str((node as Button).text))
	return out


func _has(buttons: Array[String], text: String) -> bool:
	for label: String in buttons:
		if label.contains(text):
			return true
	return false


## Aim at a pick box's top face and press, exactly as a player does.
func _click_top(box: AABB) -> void:
	app.world.update_camera()
	var aim := Vector3(box.get_center().x, box.position.y + .012, box.get_center().z)
	var point: Vector2 = app.world.camera.unproject_position(aim)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	down.global_position = point
	app.get_viewport().push_input(down, true)
	await frames(3)


func _click_at(world_point: Vector3) -> void:
	app.world.update_camera()
	var point: Vector2 = app.world.camera.unproject_position(world_point)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	down.global_position = point
	app.get_viewport().push_input(down, true)
	await frames(3)


## Put a fresh dish on the table and take one serving off it, leaving the plate
## sitting out in its own clear slot, exactly as a meal leaves the table.
func _leave_plate_on_table(dining: Dictionary, recipe: String) -> Dictionary:
	var food: LifeMeals = app.household.meals
	var now: float = app.meal_flow.now()
	var member: Dictionary = app.household.members[0]
	var batch: Dictionary = food.create_batch(recipe, str(member.id), 2, app.current_venue, now)
	food.set_batch_location(str(batch.id), "surface", str(dining.id), dining.node.global_position, now)
	var plate: Dictionary = food.claim(str(batch.id), str(member.id), now)
	# The slot search skips the carried plate, so this lands clear of the platter.
	var slot: Vector3 = app.meal_flow._surface_slot(dining, LifeMeals.PLATE_HALF_SIZE, str(plate.id))
	food.put_portion(str(plate.id), str(dining.id), "", dining.node.global_position, false, slot)
	app.meal_flow.sync_world(true)
	return {"batch": batch, "plate": plate}


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.selected_lot = 0
	# Two Lifelets, so one can be asked whether they want a serving.
	app.household_profiles = [{"name": "Mara Vale"}, {"name": "Rowan Vale"}]
	app.start_household()
	await frames(2)
	app.set_process(false)
	app.world.set_process(false)
	app.world.set_process_unhandled_input(false)
	app.household.set_speed(0)
	app.world.camera_angle = .62
	app.world.camera_elevation = .82
	app.world.camera_target = Vector3(0, 0, .25)
	app.world.camera.size = 16.0

	var dining: Dictionary = app.world.closest_item("dining", Vector3.ZERO)
	var fridge: Dictionary = app.world.closest_item("fridge", Vector3.ZERO)
	var bin: Dictionary = app.world.closest_item("rubbish_bin", Vector3.ZERO)
	check(not dining.is_empty() and not fridge.is_empty() and not bin.is_empty(),
		"The starter home has a table, a fridge and a bin.")

	# A spent plate, exactly as a finished meal leaves it on the table.
	var eaten: Dictionary = _leave_plate_on_table(dining, "garden_skillet")
	app.household.meals.finish_portion(str(eaten.plate.id))
	app.meal_flow.sync_world(true)
	await settle()

	var plate_item: Dictionary = app._find_item(str(eaten.plate.id))
	check(not plate_item.is_empty(), "The spent plate exists in the world.")
	var plate_box: AABB = _box(plate_item)
	var table_box: AABB = _box(dining)
	# The defect itself: the plate rests inside the table's own pick box.
	check(table_box.has_point(plate_box.get_center()),
		"The spent plate still rests inside the table's pick box (the occluding case).")

	await _click_top(plate_box)
	var plate_buttons: Array[String] = _overlay_buttons()
	check(_has(plate_buttons, "Wash this plate"), "Clicking a spent plate on the table opens the plate's own menu.")
	check(_has(plate_buttons, "Put away leftovers"), "A plate on the table offers being put away in the fridge.")
	check(_has(plate_buttons, "Throw it in the bin"), "A plate on the table offers the bin.")
	app.close_overlay()
	await frames(2)

	# The table itself is still reachable and still offers clearing it.
	var table_center: Vector3 = table_box.get_center()
	await _click_at(Vector3(table_center.x + .55, .95, table_center.z + .3))
	var table_buttons: Array[String] = _overlay_buttons()
	check(_has(table_buttons, "Clear the table"), "Clicking the table still opens the table's own menu.")
	app.close_overlay()
	await frames(2)

	var clear_entry: Dictionary = {}
	for action: Dictionary in app.sim.get_actions_for("dining", str(dining.id)):
		if str(action.id) == "clear_table":
			clear_entry = action
	check(not clear_entry.is_empty() and bool(clear_entry.get("available", false)),
		"Clear the table is available while a spent plate sits on it.")

	# Clearing it really gathers and washes the plate — the reported defect was
	# that the plate could not be reached at all, so this now follows the click.
	app.queue_interaction(dining, "clear_table")
	app.household.set_speed(1)
	for frame: int in 6000:
		app._process(0.05)
		await frames(1)
		if app.household.meals.portion(str(eaten.plate.id)).is_empty() or app.sim.action_queue.is_empty():
			break
	check(app.household.meals.portion(str(eaten.plate.id)).is_empty(), "Clear the table really gathers and washes the spent plate.")

	# An uneaten serving left out can be eaten, stored or binned, and offered.
	var fresh: Dictionary = _leave_plate_on_table(dining, "herb_pasta")
	await settle()
	var fresh_item: Dictionary = app._find_item(str(fresh.plate.id))
	await _click_top(_box(fresh_item))
	var fresh_buttons: Array[String] = _overlay_buttons()
	check(_has(fresh_buttons, "Take a serving"), "An uneaten serving on the table can still be eaten.")
	check(_has(fresh_buttons, "Put away leftovers"), "An uneaten serving can be put away in the fridge.")
	check(_has(fresh_buttons, "Throw it in the bin"), "A still-fresh serving can be thrown in the bin on purpose.")
	check(_has(fresh_buttons, "Ask who wants food"), "A serving offers asking who wants food.")
	app.close_overlay()
	await frames(2)

	# Asking a household Lifelet really queues a serving for them.
	app.household.select(1)
	app._bind_member(app.household.selected_id())
	app.household.members[1].sim.needs.hunger = 40.0
	var answer: String = app.meal_flow.ask_to_share(str(app.household.members[1].id), str(fresh.batch.id))
	check(not app.household.members[1].sim.action_queue.is_empty(), "Asking a hungry Lifelet queues a serving for them.")
	check(answer.contains("yes"), "A hungry Lifelet answers yes.")
	app.household.members[1].sim.cancel_action()
	app.household.members[1].sim.needs.hunger = 99.0
	var refusal: String = app.meal_flow.ask_to_share(str(app.household.members[1].id), str(fresh.batch.id))
	check(app.household.members[1].sim.action_queue.is_empty(), "A full Lifelet is not signed up for a meal.")
	check(refusal.contains("not hungry"), "A full Lifelet says they are not hungry.")

	# The fridge gathers what is left out.
	await _click_top(_box(fridge))
	var fridge_buttons: Array[String] = _overlay_buttons()
	check(_has(fridge_buttons, "Put away the food left out"), "The fridge offers putting the food left out away.")
	app.close_overlay()
	await frames(2)

	app.household.members[1].sim.needs.hunger = 90.0
	app.household.select(0)
	app._bind_member(app.household.selected_id())
	app.queue_interaction(fridge, "put_in_fridge")
	app.household.set_speed(1)
	for frame: int in 6000:
		app._process(0.05)
		await frames(1)
		if str(fresh.batch.storage) == "fridge" or app.sim.action_queue.is_empty():
			break
	check(str(fresh.batch.storage) == "fridge" and str(fresh.batch.host) == str(fridge.id),
		"The uneaten serving ends up back in its dish in the fridge.")
	check(int(fresh.batch.remaining) == 4 and int(fresh.batch.served) == 0,
		"The uneaten serving returns to its dish's remaining count.")

	print("PLATE_REACH %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
