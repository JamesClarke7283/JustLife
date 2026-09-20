extends SceneTree
## The weekly food truck, the coffee machine and temporary energy.
##
## Every assertion is made through the real UI/API: the catalogue row, the
## placement path, the click dispatch, the shop's own buttons, the shared clock
## and the public save/load. Nothing is called "because it exists"; each check
## reads a value a player would see.

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


func press(name: String) -> bool:
	var button: Button = app.overlay.get_node_or_null(name) as Button
	if button == null:
		return false
	button.pressed.emit()
	return true


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.selected_lot = 0
	app.start_household()
	await frames(3)
	app.set_process(false)
	app.household.set_speed(0)

	await _coffee_is_a_furnishing()
	await _coffee_action_grants_temporary_energy()
	_temporary_energy_has_its_own_decay_and_bar()
	_temporary_energy_round_trips()
	await _the_truck_arrives_on_the_clock()
	await _clicking_the_van_opens_the_shop()
	await _an_affordable_order_charges_once_and_delivers()
	await _an_unaffordable_order_is_refused_with_a_reason()
	# The save/load round trip runs last: a deliberate reload replaces the live
	# household, so it must not disturb the checks above.
	await _older_save_without_it_loads_with_none()

	app.queue_free()
	await frames(2)
	print("WEEKLY_SHOP %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------------------
# (a) The coffee machine is a catalogue furnishing that buys on the lot and
#     offers a coffee action which grants temporary energy.
# ---------------------------------------------------------------------------
func _coffee_is_a_furnishing() -> void:
	var item: Dictionary = LifeCatalog.ITEMS.get("coffee_machine", {})
	check(not item.is_empty(), "The coffee machine is a catalogue kind.")
	check(str(item.get("category", "")) == "Kitchen", "The coffee machine sits in the Kitchen category.")
	check(FileAccess.file_exists("res://assets/models/coffee_machine.glb"), "The coffee machine's model ships with the game.")

	# Buy it through the ordinary placement path, from the real build mode.
	var before: int = int(app.sim.funds)
	app.set_build_mode(true)
	app.begin_purchase("coffee_machine")
	check(str(app.world.placement_kind) == "coffee_machine", "The catalogue offers a coffee machine ghost to place.")
	var spot: Vector3 = Vector3(-2.4, 0.16, -2.0)
	app.on_placement("coffee_machine", spot, 0.0)
	await frames()
	app.set_build_mode(false)
	var placed: Dictionary = app.world.closest_item("coffee_machine", spot)
	check(not placed.is_empty(), "The coffee machine buys onto the lot.")
	check(before - int(app.sim.funds) == int(item.price), "The purchase charges the catalogue price once (%d)." % int(item.price))


func _coffee_action_grants_temporary_energy() -> void:
	var machine: Dictionary = app.world.closest_item("coffee_machine", Vector3.ZERO)
	var offered: Array = app.sim.get_actions_for("coffee_machine", str(machine.id))
	var ids: Array = offered.map(func(a: Dictionary) -> String: return str(a.id))
	check(ids.has("drink_coffee"), "The placed machine offers the drink_coffee action (got %s)." % str(ids))

	# The action's own declared changes must reach the temporary pool and not
	# the ordinary energy need.
	var definition: Dictionary = app.sim.get_action_definition("drink_coffee")
	check(float(definition.get("changes", {}).get("second_wind", 0.0)) > 0.0, "Drinking coffee declares a second-wind change.")
	check(not definition.get("changes", {}).has("energy"), "Drinking coffee does not declare a change to the Energy need.")

	app.sim.needs.energy = 40.0
	app.sim.second_wind = 0.0
	app.sim.speed = 1
	app.sim.queue_action("drink_coffee", str(machine.id), machine.node.global_position)
	var queued: Dictionary = app.sim.get_current_action()
	check(str(queued.get("id", "")) == "drink_coffee", "The coffee action can be queued on the machine.")
	# Run the action to completion on the shared clock.
	var guard: int = 0
	while not app.sim.get_current_action().is_empty() and guard < 4000:
		app.sim.tick(1.0)
		guard += 1
	check(app.sim.second_wind > 50.0, "Drinking the coffee grants temporary energy (%0.1f)." % app.sim.second_wind)
	check(app.sim.needs.energy <= 40.0, "The Energy need itself is not raised by the coffee (%0.1f)." % app.sim.needs.energy)


# ---------------------------------------------------------------------------
# (b) Temporary energy decays at its own rate and is drawn as its own darker
#     bar that reads the temporary pool, not the ordinary energy need.
# ---------------------------------------------------------------------------
func _temporary_energy_has_its_own_decay_and_bar() -> void:
	app.sim.speed = 1
	app.sim.second_wind = LifeSim.SECOND_WIND_MAX
	app.sim.needs.energy = 80.0
	var energy_before: float = app.sim.needs.energy
	# An hour on the shared clock, in minute steps, as the sim really ticks.
	for i: int in 60:
		app.sim.tick(1.0)
	var dropped: float = LifeSim.SECOND_WIND_MAX - app.sim.second_wind
	check(absf(dropped - LifeSim.SECOND_WIND_DECAY_PER_HOUR) < 0.5,
		"Temporary energy falls by its own %0.1f a game hour (fell %0.2f)." % [LifeSim.SECOND_WIND_DECAY_PER_HOUR, dropped])
	check(app.sim.needs.energy == energy_before,
		"While the second wind lasts the ordinary Energy need does not drain (%0.2f -> %0.2f)." % [energy_before, app.sim.needs.energy])

	# Let the pool run out and show the two meters are independent: the energy
	# need then resumes its own decay.
	app.sim.second_wind = 0.0
	app.sim.needs.energy = 80.0
	for i: int in 60:
		app.sim.tick(1.0)
	check(app.sim.needs.energy < 79.0, "Once the pool is empty the ordinary Energy need drains again (%0.2f)." % app.sim.needs.energy)

	# The bar exists, is darker than the Energy need's own fill, and reads the
	# temporary pool rather than the need.
	app.sim.second_wind = 42.0
	app.sim.needs.energy = 90.0
	app.refresh_hud()
	await frames()
	var bar: ProgressBar = app.find_child("SecondWindBar", true, false) as ProgressBar
	check(bar != null, "The HUD draws a SecondWindBar.")
	if bar == null:
		return
	check(absf(bar.value - 42.0) < 0.01, "The SecondWindBar reads the temporary pool (%0.2f), not the Energy need." % bar.value)
	var energy_bar: ProgressBar = app.need_bars.get("energy") as ProgressBar
	check(energy_bar != null and absf(energy_bar.value - 90.0) < 0.01, "The Energy need keeps its own separate bar (%.1f)." % energy_bar.value)
	var wind_fill: Color = (bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color
	var energy_fill: Color = (energy_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color
	check(wind_fill.get_luminance() < energy_fill.get_luminance(),
		"The second-wind bar is drawn darker than the Energy need (%.3f < %.3f)." % [wind_fill.get_luminance(), energy_fill.get_luminance()])
	var card: Panel = app.find_child("SecondWindCard", true, false) as Panel
	check(card != null and card.visible, "The second-wind card is shown while the pool is full.")
	app.sim.second_wind = 0.0
	app.refresh_hud()
	await frames()
	check(not card.visible, "The second-wind card hides itself when the pool is empty.")


# ---------------------------------------------------------------------------
# (c) Temporary energy survives serialize -> validate -> reload, and an older
#     save without it loads cleanly with none.
# ---------------------------------------------------------------------------
func _temporary_energy_round_trips() -> void:
	app.sim.second_wind = 63.5
	var state: Dictionary = app.sim.get_state()
	check(absf(float(state.get("second_wind", -1.0)) - 63.5) < 0.01, "A Lifelet's state carries the temporary pool (%s)." % str(state.get("second_wind")))
	var accepted: Dictionary = app.sim.restore_state(state)
	check(bool(accepted.get("ok", false)), "A well-formed second wind round-trips (error: %s)." % str(accepted.get("error", "")))
	var bad: Dictionary = state.duplicate(true)
	bad["second_wind"] = 400.0
	var rejected: Dictionary = app.sim.restore_state(bad)
	check(not bool(rejected.get("ok", true)), "An impossible second wind is rejected (%s)." % str(rejected.get("error", "")))


func _older_save_without_it_loads_with_none() -> void:
	# A genuine round trip through the public save path.
	app.sim.second_wind = 71.0
	app.household.set_speed(1)
	var saved: bool = app.save_game("Second Wind Round Trip")
	print("SAVE_NOTE ", str(app.notice_label.text) if is_instance_valid(app.notice_label) else "?")
	check(saved, "The household saves through the public path.")
	await frames(4)
	var slot: String = app.active_save_id
	check(not slot.is_empty(), "The save produced a slot id (%s)." % slot)
	app.sim.second_wind = 0.0
	app.load_game(slot)
	await frames(6)
	check(absf(app.sim.second_wind - 71.0) < 0.01, "A fresh load restores the temporary pool (%0.1f)." % app.sim.second_wind)

	# An older save has no `second_wind` key at all. Strip it the way a pre-pool
	# save would look and confirm the load path leaves the pool at none.
	var old: Dictionary = app.sim.get_state().duplicate(true)
	old.erase("second_wind")
	app.sim.second_wind = 88.0
	var loaded: Dictionary = app.sim.restore_state(old)
	check(bool(loaded.get("ok", false)), "An older save with no second wind still loads (error: %s)." % str(loaded.get("error", "")))
	check(app.sim.second_wind == 0.0, "An older save loads with no temporary energy (%0.1f)." % app.sim.second_wind)
	app.sim.second_wind = 71.0


# ---------------------------------------------------------------------------
# (d)/(e) The truck's arrival is driven by the shared game clock, its click
#     opens the shop, and the shop charges once and refuses with a reason.
# ---------------------------------------------------------------------------
func _the_truck_arrives_on_the_clock() -> void:
	app.household.set_speed(0)
	# Day 1 is a visit day; make it a non-visit day and let the clock run to the
	# next one. Nothing calls the truck by hand: the household advances the day
	# and the controller's own tick presents the van.
	app.household.day = 2
	app.household.minutes = 0.0
	app.world.pick_extras.erase("FoodTruckVan")
	if is_instance_valid(app.food_truck.van()):
		app.food_truck.remove_van()
	app._truck_parked = false
	check(not app.food_truck.present(), "No van is parked on a non-visit day (day %d)." % app.household.day)
	check(not app.food_truck.visiting(), "The truck's own schedule says day 2 is not a visit.")

	var visit: int = app.food_truck.next_visit_day()
	check(visit == 8, "The truck's next visit is a week out (day %d)." % visit)
	# Advance the shared clock to the middle of the visit day in one jump and
	# run the controller's own frame: the van must appear without a manual call.
	app.household.day = visit
	app.household.minutes = 10.0 * 60.0
	app.household.set_speed(1)
	app.set_process(true)
	await frames(6)
	check(app.food_truck.visiting(), "The shared clock reaches a visit day (day %d)." % app.household.day)
	check(app.food_truck.present(), "The van is parked by the clock alone, with no manual call.")
	check(app.food_truck.open(), "The van is open during its own opening hours.")
	check(app.world.pick_extras.has("FoodTruckVan"), "The van is a pick target in the world.")
	app.set_process(false)
	app.household.set_speed(0)


func _clicking_the_van_opens_the_shop() -> void:
	check(app.food_truck.present(), "The van is still parked for the click test.")
	# Click the world object exactly as the ray does: same payload, same dispatch.
	var info: Dictionary = app.world.pick_extras.get("FoodTruckVan", {})
	check(str(info.get("kind", "")) == "food_truck", "The van's pick payload declares the food_truck kind.")
	app.on_object_clicked(info, Vector2(720, 450))
	await frames(3)
	check(app.overlay.get_node_or_null("TruckOrder_coffee_machine") != null, "Clicking the van opens the truck's shop.")
	app.close_overlay()
	await frames(2)

	# The phone offers the same shop, so it is reachable without the van's pixel.
	app.adoption_flow.show_phone()
	await frames(3)
	var row: Button = app.overlay.get_node_or_null("PhoneFoodTruck") as Button
	check(row != null, "The phone lists the weekly food truck.")
	check(row != null and not row.disabled, "The phone's food-truck row is enabled while the van is open.")
	if row != null:
		row.pressed.emit()
		await frames(3)
		check(app.overlay.get_node_or_null("TruckOrder_coffee_machine") != null, "The phone row opens the same shop as the van.")
	app.close_overlay()
	await frames(2)


func _an_affordable_order_charges_once_and_delivers() -> void:
	app.household.set_funds(5000)
	var before: int = int(app.household.funds)
	var price: int = int(LifeCatalog.ITEMS.garden_bed.price)
	check(app.food_truck.order_error("garden_bed").is_empty(), "An affordable line has no refusal (%s)." % app.food_truck.order_error("garden_bed"))

	# Order through the shop's own button.
	app.food_truck.show_shop()
	await frames(3)
	var ordered: bool = press("TruckOrder_garden_bed")
	check(ordered, "The shop offers a Garden bed button.")
	await frames(3)
	check(int(app.household.funds) == before - price, "The order charges the wallet exactly once (ℒ%d -> ℒ%d)." % [before, app.household.funds])
	check(app.mode == "build" and str(app.world.placement_kind) == "garden_bed", "The order hands the delivery to the ordinary placement.")

	# Placing the delivery must not charge a second time.
	var after_charge: int = int(app.household.funds)
	app.on_placement("garden_bed", Vector3(2.6, 0.16, -2.4), 0.0)
	await frames(2)
	var placed: Dictionary = app.world.closest_item("garden_bed", Vector3(2.6, 0.16, -2.4))
	check(not placed.is_empty(), "The delivery places as a real furnishing the household owns.")
	check(int(app.household.funds) == after_charge, "Placing the delivery does not charge again (ℒ%d)." % app.household.funds)
	app.set_build_mode(false)
	await frames(2)


func _an_unaffordable_order_is_refused_with_a_reason() -> void:
	app.household.set_funds(10)
	var before: int = int(app.household.funds)
	app.food_truck.show_shop()
	await frames(3)
	var row: Button = app.overlay.get_node_or_null("TruckOrder_garden_bed") as Button
	check(row != null and row.disabled, "A line the household cannot afford is disabled in the shop.")
	check(row != null and not str(row.tooltip_text).is_empty(), "The disabled line carries a readable refusal (%s)." % (str(row.tooltip_text) if row != null else ""))
	# And the truck itself refuses the order with a reason when asked directly.
	var result: Dictionary = app.food_truck.place_order("garden_bed")
	check(not bool(result.get("ok", true)), "The truck refuses an unaffordable order.")
	check("costs" in str(result.get("error", "")), "The refusal names the price (%s)." % str(result.get("error", "")))
	check(int(app.household.funds) == before, "A refused order changes nothing in the purse (ℒ%d)." % app.household.funds)
	app.close_overlay()
	await frames(2)
	app.household.set_funds(2500)
