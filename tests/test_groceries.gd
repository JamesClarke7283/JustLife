extends SceneTree
## The grocery package: the kitchen is restocked by ordering a delivery from the
## computer, and a delivery arrives by van — so the fridge stops selling food and
## a household that forgot to shop really has to wait.
##
## Every assertion drives the real computer panel, the real household order and
## the real household clock, and reads what a player would see: what is in the
## kitchen, what the van brought, and what the fridge refuses.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_groceries.gd

const LifeGroceries = preload("res://scripts/groceries.gd")

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


func _press(text: String) -> bool:
	for button: Node in app.find_children("*", "Button", true, false):
		if button.text == text and button.is_visible_in_tree() and not button.disabled:
			button.pressed.emit()
			return true
	return false


func _run() -> void:
	# ---------------------------------------------------------------- policy
	check(LifeGroceries.validate(LifeGroceries.fresh()).is_empty(), "A fresh kitchen is valid.")
	check(LifeGroceries.stock(LifeGroceries.fresh()) == 0, "A fresh kitchen is empty.")
	check(LifeGroceries.baskets().size() >= 3, "The shop delivers more than one basket (%d)." % LifeGroceries.baskets().size())
	check(LifeGroceries.basket("large").meals > LifeGroceries.basket("small").meals, "The big shop is bigger than the small one.")
	check(not LifeGroceries.can_cook(LifeGroceries.fresh()), "An empty kitchen cannot cook.")
	check(not LifeGroceries.validate({"version": 1, "stock": 9999}).is_empty(), "An impossible amount of food is refused.")
	check(not LifeGroceries.validate({"version": 1, "order": {"basket": "ghost"}}).is_empty(), "A delivery of an unknown basket is refused.")

	# Ordering, arriving and running out, as pure policy.
	var kitchen: Dictionary = LifeGroceries.fresh()
	var order: Dictionary = LifeGroceries.order(kitchen, "weekly", 500, 2, 600.0)
	check(bool(order.ok), "A basket can be ordered with enough money (%s)." % str(order.get("error", "")))
	check(int(order.funds) == 500 - LifeGroceries.BASKET_PRICE, "The order costs exactly its price.")
	check(LifeGroceries.has_order(order.state), "The kitchen now has a delivery on its way.")
	check(not LifeGroceries.can_cook(order.state), "The kitchen is still empty until the van arrives.")
	check(not LifeGroceries.arrival_due(order.state, 2, 600.0), "The van has not arrived the moment it was ordered.")
	check(LifeGroceries.arrival_due(order.state, 2, 600.0 + LifeGroceries.DELIVERY_MINUTES), "The van arrives when its time comes.")
	var collected: Dictionary = LifeGroceries.collect(order.state)
	check(bool(collected.ok) and int(collected.meals) == LifeGroceries.BASKET_MEALS, "The van really brings the basket (%d meals)." % int(collected.get("meals", 0)))
	check(LifeGroceries.can_cook(collected.state), "The kitchen can cook once the shopping is in.")
	check(not LifeGroceries.has_order(collected.state), "Taking the delivery in clears it.")
	# An order placed in the evening comes the next day.
	var evening: Dictionary = LifeGroceries.order(LifeGroceries.fresh(), "small", 500, 3, float(LifeGroceries.LAST_ORDER_MINUTE))
	check(bool(evening.ok) and int(evening.day) == 4, "An evening order arrives the next day (day %d)." % int(evening.get("day", 0)))
	# A second order while one is on its way is refused.
	check(not bool(LifeGroceries.order(order.state, "small", 500, 2, 600.0).ok), "A second delivery cannot be ordered while one is on its way.")
	# An unaffordable order is refused.
	check(not bool(LifeGroceries.order(LifeGroceries.fresh(), "large", 5, 1, 600.0).ok), "An unaffordable shop is refused.")
	# Eating down the stock.
	var running: Dictionary = collected.state
	for i: int in LifeGroceries.BASKET_MEALS:
		var taken: Dictionary = LifeGroceries.take_meal(running)
		if bool(taken.ok): running = taken.state
	check(not LifeGroceries.can_cook(running), "The kitchen runs out when everything is eaten.")
	check(not bool(LifeGroceries.take_meal(running).ok), "Taking a meal from an empty kitchen is refused.")

	# ------------------------------------------------------------- the live game
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

	check(LifeGroceries.stock(app.household.groceries) == 0, "A new household's kitchen starts empty.")
	# The fridge no longer sells a meal: the cook and snack actions are refused
	# with a reason that names the computer.
	var cook: Dictionary = app.sim.get_action_availability("cook", "")
	check(not bool(cook.available), "Cooking is refused while the kitchen is empty.")
	check(str(cook.reason).to_lower().contains("kitchen") and str(cook.reason).to_lower().contains("computer"),
		"The refusal names the kitchen and where to order from (%s)." % str(cook.reason))
	var snack: Dictionary = app.sim.get_action_availability("snack", "")
	check(not bool(snack.available), "A snack is refused while the kitchen is empty.")
	check(app.household.cooking_availability(app.sim, "").contains("computer"), "The household's own kitchen answer names the computer.")

	# ------------------------------------------------- the computer's own panel
	app.household.set_funds(20000)
	app.sim.funds = 20000
	app.show_grocery_order()
	await frames(4)
	check(app.overlay_open, "The grocery panel opens.")
	var rows: int = 0
	for basket_id: String in LifeGroceries.baskets():
		if app.overlay.find_child("Grocery_" + basket_id, true, false) != null: rows += 1
	check(rows == LifeGroceries.baskets().size(), "Every basket gets a row (%d of %d)." % [rows, LifeGroceries.baskets().size()])
	var funds_before: int = app.household.funds
	check(_press("The weekly shop · ℒ%s" % _commas(LifeGroceries.BASKET_PRICE)), "The weekly shop can be ordered from the panel.")
	await frames(4)
	check(LifeGroceries.has_order(app.household.groceries), "The household now has a delivery on its way.")
	check(app.household.funds == funds_before - LifeGroceries.BASKET_PRICE, "The purse paid exactly its price (ℒ%d)." % LifeGroceries.BASKET_PRICE)
	check(int(app.household.groceries.order.meals) == LifeGroceries.BASKET_MEALS, "The delivery holds the basket's meals.")
	# The van is really standing outside while the order is on its way.
	await frames(3)
	check(is_instance_valid(app.world.delivery_van), "The delivery van is standing outside while the order is on its way.")
	if is_instance_valid(app.world.delivery_van):
		var leaves: int = 0
		for node: Node in app.world.delivery_van.get_children():
			if node.has_meta("delivery_leaf"): leaves += 1
		check(leaves >= LifeGroceries.VAN_SIGN_LEAVES, "The van carries its organic sign (%d leaves)." % leaves)
	app.close_overlay()
	await frames(2)

	# ----------------------------------------------- the delivery really arrives
	# Run the household clock past the delivery time and the kitchen fills itself.
	for i: int in 400:
		app.household.set_speed(1)
		app.household.tick(1.0)
		if not LifeGroceries.has_order(app.household.groceries):
			break
	check(not LifeGroceries.has_order(app.household.groceries), "The delivery arrived on the household's own clock.")
	check(LifeGroceries.stock(app.household.groceries) == LifeGroceries.BASKET_MEALS,
		"The kitchen holds the whole basket (%d meals)." % LifeGroceries.stock(app.household.groceries))
	check(app.household.kitchen().contains("kitchen"), "The kitchen describes what it holds (%s)." % app.household.kitchen())
	app.household.set_speed(0)
	await frames(3)
	check(not is_instance_valid(app.world.delivery_van), "The van leaves once the shopping is carried in.")

	# Cooking now draws from the kitchen rather than the purse.
	var stock_before: int = LifeGroceries.stock(app.household.groceries)
	var cook_now: Dictionary = app.sim.get_action_availability("cook", "")
	check(bool(cook_now.available), "Cooking is available with a stocked kitchen.")
	var funds_pre_cook: int = app.sim.funds
	var drawn: Dictionary = app.household.take_meal_for(app.sim, "cook")
	check(bool(drawn.ok), "A meal can be drawn from the kitchen for a recipe.")
	check(LifeGroceries.stock(app.household.groceries) == stock_before - 1, "Drawing a meal really lowers the stock (%d -> %d)." % [stock_before, LifeGroceries.stock(app.household.groceries)])
	check(app.sim.funds == funds_pre_cook, "Drawing a meal from the kitchen takes no money.")

	# ------------------------------------------------------------- saving
	check(app.save_game("grocery_probe", "Grocery probe"), "The household saves with its kitchen.")
	var slot: Dictionary = LifeSaveLibrary.read_slot("grocery_probe")
	check(bool(slot.get("ok", false)), "The written slot reads back (%s)." % str(slot.get("error", "")))
	var saved: Dictionary = (slot.get("data", {}) as Dictionary).get("groceries", {})
	check(LifeGroceries.stock(saved) == LifeGroceries.stock(app.household.groceries), "The kitchen rides the save (%d)." % LifeGroceries.stock(saved))
	var damaged: Dictionary = app.household.get_state()
	damaged.groceries = {"version": 1, "stock": 9999}
	var fresh: LifeHousehold = LifeHousehold.new()
	check(not bool(fresh.restore_state(damaged).ok), "A corrupt kitchen is refused.")
	fresh.free()
	LifeSaveLibrary.delete_slot("grocery_probe")

	print("GROCERIES_RESULT ", JSON.stringify({"checks": checks, "failures": failures,
		"stock": LifeGroceries.stock(app.household.groceries)}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)


func _commas(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out
