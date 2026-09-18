extends SceneTree
## Headless bounds check for the panels this branch added.
##
## The full UI-overlap oracle needs a real display (a headless window is square,
## and the design scales to fill its height, so every screen reports as off-canvas
## — including the untouched main menu). This checks the same property for the
## panels that are actually new here: every control they build must sit inside the
## authored 1440x900 design space, so nothing is clipped or unreachable.

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


func _descend(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is Control and (child as Control).visible and not (child as Control).is_queued_for_deletion():
			into.append(child)
			_descend(child, into)


## Every visible control inside the authored design space. Scroll containers are
## excluded, because their children are deliberately laid out past their own box.
func _bounds(screen: String) -> void:
	var layer: Control = app.overlay
	var all: Array[Control] = []
	_descend(layer, all)
	var escaped: int = 0
	for control: Control in all:
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if control is ScrollContainer:
			continue
		var parent: Node = control.get_parent()
		var in_scroll: bool = false
		while parent != null:
			if parent is ScrollContainer:
				in_scroll = true
				break
			parent = parent.get_parent()
		if in_scroll:
			continue
		var rect: Rect2 = Rect2(control.position, control.size)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		# A full-design-space ColorRect is the panel's own dim backdrop, which is
		# meant to cover the screen; it is not a control a player has to reach.
		if control is ColorRect and rect.size.x >= 1439.0 and rect.size.y >= 899.0:
			continue
		if rect.position.x < -2.0 or rect.position.y < -2.0 or rect.end.x > 1442.0 or rect.end.y > 902.0:
			escaped += 1
			if escaped <= 3:
				print("    escapes: ", control.name, " ", rect)
	check(escaped == 0, "%s: every control sits inside the 1440x900 design space (%d escaped)." % [screen, escaped])


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.selected_lot = 0
	app.start_household()
	await frames(3)
	app.household.set_speed(0)

	# The phone, which gained a Home insurance row.
	app.adoption_flow.show_phone()
	await frames(3)
	_bounds("phone")
	var insurance: Button = app.find_child("PhoneInsurance", true, false)
	check(insurance != null, "The phone shows a Home insurance row.")
	if insurance != null:
		var rect: Rect2 = Rect2(insurance.position, insurance.size)
		check(rect.end.y <= 902.0 and rect.position.y >= -2.0, "The insurance row sits inside the phone panel.")
	app.close_overlay()
	await frames(2)

	# The wardrobe panel, in all three of its tabs.
	var mirror: Dictionary = app.world.closest_item("mirror", Vector3.ZERO)
	for tab: String in ["clothes", "makeup", "jewelry"]:
		app.show_wardrobe_panel(str(mirror.id), tab)
		await frames(3)
		_bounds("wardrobe/" + tab)
	app.close_overlay()
	await frames(2)

	# The dish's own invitation panel.
	var dining: Dictionary = app.world.closest_item("dining", Vector3.ZERO)
	var food: LifeMeals = app.household.meals
	var now: float = app.meal_flow.now()
	var batch: Dictionary = food.create_batch("garden_skillet", str(app.household.selected_id()), 2, app.current_venue, now)
	food.set_batch_location(str(batch.id), "surface", str(dining.id), dining.node.global_position, now)
	app.meal_flow.sync_world(true)
	app.show_food_offers(str(batch.id))
	await frames(3)
	_bounds("food_offers")
	app.close_overlay()
	await frames(2)

	# The career picker, which now carries eight tracks.
	app.show_careers()
	await frames(3)
	_bounds("careers")
	var last_row: Button = app.find_child("Career_botany", true, false)
	check(last_row != null, "The career picker still shows its last track.")
	if last_row != null:
		check(last_row.position.y + last_row.size.y <= 902.0, "The last career row fits inside the picker card.")
	app.close_overlay()
	await frames(2)

	print("PANEL_BOUNDS %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
