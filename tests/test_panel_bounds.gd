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


## How many descendants carry a name starting with this prefix, whether or not
## they are visible (scroll children are laid out past their box but still real).
func _count_named(node: Node, prefix: String) -> int:
	var total: int = 1 if node.name.begins_with(prefix) else 0
	for child: Node in node.get_children():
		total += _count_named(child, prefix)
	return total


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
	var invitees: Array = app.meal_flow.food_invitees()
	app.show_food_offers(str(batch.id))
	await frames(3)
	_bounds("food_offers")
	# The panel used to abort part-way through building its rows (an invalid
	# property assignment on a plain Control), so the player saw an empty card
	# with no one to offer a serving to. Every invitee must get a real row and a
	# pressable button.
	check(invitees.size() > 0, "The fixture has someone to offer food to (%d)." % invitees.size())
	check(_count_named(app.overlay, "FoodOffer_") == invitees.size(),
		"Every invited Lifelet gets a row (%d of %d)." % [_count_named(app.overlay, "FoodOffer_"), invitees.size()])
	check(_count_named(app.overlay, "FoodOfferButton_") == invitees.size(),
		"Every row has an offer button (%d of %d)." % [_count_named(app.overlay, "FoodOfferButton_"), invitees.size()])
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
	# The tracks live in a scroll region, so a longer roster still reaches every
	# track instead of running rows past the card where they cannot be chosen.
	var careers_list: ScrollContainer = app.overlay.find_child("CareerList", true, false)
	check(careers_list != null, "The career picker keeps its tracks in a scroll region.")
	if careers_list != null:
		check(Rect2(careers_list.position, careers_list.size).end.y <= 902.0,
			"The career picker's scroll region sits inside the 1440x900 design space.")
		var tracks: int = 0
		for track_id: String in LifeSim.CAREER_TRACKS:
			if app.overlay.find_child("CareerRow_" + track_id, true, false) != null:
				tracks += 1
		check(tracks == LifeSim.CAREER_TRACKS.size(), "Every authored career track gets a row (%d of %d)." % [tracks, LifeSim.CAREER_TRACKS.size()])
		# The last track must be reachable by scrolling, not merely present: at
		# the bottom of the region it is inside the region's own box.
		var bottom: VScrollBar = careers_list.get_v_scroll_bar()
		careers_list.scroll_vertical = 100000
		await frames(2)
		check(careers_list.scroll_vertical == int(bottom.max_value - bottom.page),
			"The career picker scrolls to its own bottom (%.0f of %.0f)." % [careers_list.scroll_vertical, bottom.max_value - bottom.page])
		var tail: Button = app.find_child("Career_technical", true, false)
		if tail != null:
			var region: Rect2 = Rect2(careers_list.position, careers_list.size)
			var tail_rect: Rect2 = Rect2(tail.position, tail.size)
			check(tail_rect.end.y <= region.end.y + 1.0,
				"The last career track sits inside the scrolled region at its bottom (ends at %.0f, region ends %.0f)." % [tail_rect.end.y, region.end.y])
	app.close_overlay()
	await frames(2)

	# The cookbook, which grows with the recipe list. Absolute rows ran the last
	# dishes past the card and off the canvas once a seventh recipe was authored,
	# so the list must live in a scroll region inside the card.
	var stove: Dictionary = app.world.closest_item("stove", Vector3.ZERO)
	if not stove.is_empty():
		app.meal_flow.show_recipes(str(stove.id))
		await frames(3)
		var list: ScrollContainer = app.overlay.find_child("RecipeList", true, false)
		check(list != null, "The cookbook keeps its dishes in a scroll region.")
		if list != null:
			check(Rect2(list.position, list.size).end.y <= 902.0,
				"The cookbook's scroll region sits inside the 1440x900 design space.")
		var rows: int = 0
		for recipe: String in LifeMeals.RECIPES:
			if app.overlay.find_child("RecipeRow_" + recipe, true, false) != null:
				rows += 1
		check(rows == LifeMeals.RECIPES.size(), "Every authored recipe gets a row (%d of %d)." % [rows, LifeMeals.RECIPES.size()])
		app.close_overlay()
		await frames(2)

	# The creator's four tabs share the right-hand card, whose last 38 px sit
	# against the canvas edge; a wider pitch clipped the Style tab off-screen.
	app.show_creator()
	await frames(4)
	var tabs_seen: int = 0
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and str((node as Button).text) in ["Look", "Face", "Wardrobe", "Style"]:
			tabs_seen += 1
			var r: Rect2 = Rect2((node as Button).position, (node as Button).size)
			check(r.end.x <= 1442.0 and r.position.x >= -2.0,
				"The creator's %s tab sits inside the canvas (ends at %.0f)." % [str((node as Button).text), r.end.x])
	check(tabs_seen == 4, "The creator shows all four tabs (%d)." % tabs_seen)

	print("PANEL_BOUNDS %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
