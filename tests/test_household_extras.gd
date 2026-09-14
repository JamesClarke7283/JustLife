extends SceneTree
## The household extras (bin, skill books, instruments) and their persistence.
##
## No pointer or rendering proof: bin fill, book purchase/refusal and the
## extras round-trip are asserted from the real service and household state.

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


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	app.set_process(false)

	var flow: LifeHouseholdFlow = app.household_flow
	var bin: Dictionary = app.world.closest_item("rubbish_bin", Vector3.ZERO)
	var shelf: Dictionary = app.world.closest_item("bookshelf", Vector3.ZERO)
	check(not bin.is_empty(), "The starter home has a rubbish bin.")
	check(not shelf.is_empty(), "The starter home has a bookshelf.")

	# The bin fills from household rubbish and empties only when full.
	check(not flow.bin_is_full(str(bin.id)), "A new bin starts empty.")
	flow.add_rubbish(3)
	check(not flow.bin_is_full(str(bin.id)), "A partly filled bin is not yet full.")
	flow.add_rubbish(1)
	check(flow.bin_is_full(str(bin.id)), "The bin reads full once its units are reached.")
	check(flow.empty_bin(str(bin.id)) and not flow.bin_is_full(str(bin.id)), "Emptying a full bin clears it.")
	check(not flow.empty_bin(str(bin.id)), "A not-full bin cannot be emptied again.")
	var bin_menu: Array = app.sim.get_actions_for("rubbish_bin", str(bin.id)).map(func(a: Dictionary) -> String: return str(a.id))
	check(bin_menu.has("empty_bin"), "The bin offers its own empty_bin action.")

	# A skill book is bought for a shelf, teaches its subject and refuses abuse.
	var bought: Dictionary = flow.buy_book(str(shelf.id), "cooking")
	check(bool(bought.ok), "A cooking book can be bought for the shelf.")
	check(flow.books_on(str(shelf.id)).size() == 1, "The bought book sits on its shelf.")
	var study: Array = app.sim.get_actions_for("bookshelf", str(shelf.id)).map(func(a: Dictionary) -> String: return str(a.id))
	check(study.has("study_book") and study.has("buy_book"), "The shelf offers study_book and buy_book.")
	check(not bool(flow.buy_book(str(shelf.id), "astrology").ok), "An unknown subject is refused.")
	var tv: Dictionary = app.world.closest_item("tv", Vector3.ZERO)
	check(not bool(flow.buy_book(str(tv.id), "cooking").ok), "A non-shelf target is refused a book.")

	# Instruments share one practice action and are real catalogue furnishings.
	check(not LifeCatalog.INSTRUMENTS.is_empty(), "Instruments are declared in the catalogue.")
	for kind: String in LifeCatalog.INSTRUMENTS:
		check(LifeCatalog.ITEMS.has(kind), "The catalogue sells the %s." % kind)
	var practice: Dictionary = app.sim.get_action_definition("practice_instrument")
	check(not practice.is_empty() and str(practice.skill) == "music", "Practising an instrument builds Music.")

	# The extras ride the household state and survive a save/load round trip.
	var layout: Array = app.world.serialize_items()
	var snapshot: Dictionary = app.household.get_state(layout)
	check(int(snapshot.get("extras", {}).get("books", []).size()) == 1, "The household state carries the bought book.")
	flow.add_rubbish(2)
	var with_fill: Dictionary = app.household.get_state(layout)
	check(int(with_fill.extras.fill.get(str(bin.id), -1)) == 2, "The household state carries the bin fill.")

	# Stored records are validated against the real layout, not trusted blindly.
	var bad_shelf: Dictionary = {"serial": 9, "books": [{"id": "book_9", "skill": "cooking", "shelf": "missing_shelf"}], "fill": {}}
	check(not LifeHouseholdFlow.validate(bad_shelf, with_fill.world).is_empty(), "A book on a missing shelf is rejected.")
	var bad_fill: Dictionary = {"serial": 9, "books": [], "fill": {str(bin.id): 99}}
	check(not LifeHouseholdFlow.validate(bad_fill, with_fill.world).is_empty(), "An impossible saved bin fill is rejected.")
	var good: Dictionary = {"serial": 3, "books": [{"id": "book_1", "skill": "music", "shelf": str(shelf.id)}], "fill": {}}
	check(LifeHouseholdFlow.validate(good, with_fill.world).is_empty(), "A well-formed extras record validates.")
	flow.restore(good)
	check(flow.books_on(str(shelf.id)).size() == 1 and str(flow.books_on(str(shelf.id))[0].skill) == "music", "A restored extras record replaces the shelf's books.")

	# A real save and load keeps the books and the bin fill, not just the shape.
	flow.restore({"serial":0, "books":[], "fill":{}})
	flow.buy_book(str(shelf.id), "gardening")
	flow.add_rubbish(2)
	check(app.save_game("Extras Round Trip"), "The household saves through the public path.")
	await process_frame
	var slot: String = app.active_save_id
	flow.restore({"serial":0, "books":[], "fill":{}})
	app.load_game(slot)
	await process_frame
	check(flow.books_on(str(shelf.id)).size() == 1 and str(flow.books_on(str(shelf.id))[0].skill) == "gardening",
		"A fresh load restores the shelf's book and its subject.")
	check(int(flow.get_state().fill.get(str(bin.id), -1)) == 2, "A fresh load restores the bin fill.")

	_storage_unit(flow)
	_spoilage_and_bin()
	_pregnancy_meter()
	_wall_sightlines()

	app.queue_free()
	await process_frame
	print("HOUSEHOLD_EXTRAS %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## Furniture storage: a placed furnishing leaves the world, is counted against
## the 30-item cap, and can be taken back out or sold.
func _storage_unit(flow: LifeHouseholdFlow) -> void:
	var chair: Dictionary = app.world.closest_item("chair", Vector3.ZERO)
	check(not chair.is_empty(), "The starter home has a chair to store.")
	var entry: Dictionary = {"id":str(chair.id), "kind":str(chair.kind), "x":chair.node.position.x, "z":chair.node.position.z, "rotation":chair.node.rotation_degrees.y, "level":app.world.item_level(chair)}
	var placed: Dictionary = flow.store_furnishing(entry)
	check(bool(placed.ok), "A placed furnishing can be filed away into storage.")
	check(flow.storage_count() == 1, "The stored furnishing is counted.")
	var withdrawn: Dictionary = flow.withdraw_furnishing(str(chair.id))
	check(bool(withdrawn.ok) and str(withdrawn.record.kind) == "chair", "A stored furnishing can be taken back out.")
	check(flow.storage_count() == 0, "Withdrawing removes it from storage.")
	flow.store_furnishing(entry)
	var sold: Dictionary = flow.sell_stored(str(chair.id))
	check(bool(sold.ok) and int(sold.credit) == int(LifeCatalog.ITEMS.chair.price * .7), "A stored furnishing sells for its usual value.")
	check(flow.storage_count() == 0, "Selling removes it from storage.")
	# The cap is exactly the advertised number and the next item is refused.
	for i:int in range(LifeHouseholdFlow.MAX_STORAGE):
		flow.store_furnishing({"id":"cap_%d" % i, "kind":"chair", "x":0.0, "z":0.0, "rotation":0.0, "level":0})
	check(flow.storage_count() == LifeHouseholdFlow.MAX_STORAGE, "Storage holds exactly 30 items.")
	check(not bool(flow.store_furnishing({"id":"cap_over", "kind":"chair", "x":0.0, "z":0.0, "rotation":0.0, "level":0}).ok), "A 31st item is refused.")
	# A stored record must name a real catalogue item at a valid level.
	check(not LifeHouseholdFlow.validate({"serial":0, "books":[], "fill":{}, "storage":[{"id":"x","kind":"not_a_kind","x":0.0,"z":0.0,"rotation":0.0,"level":0}]}, app.world.serialize_items()).is_empty(), "A stored record for an unknown furnishing is rejected.")
	check(LifeHouseholdFlow.validate({"serial":0, "books":[], "fill":{}, "storage":[{"id":"x","kind":"chair","x":1.0,"z":1.0,"rotation":0.0,"level":0}]}, app.world.serialize_items()).is_empty(), "A well-formed stored record validates.")
	flow.storage.clear()


## Fresh food keeps for one game day and turns green once spoiled; spoiled food
## can be thrown in the bin instead of the sink.
func _spoilage_and_bin() -> void:
	var meals: LifeMeals = app.household.meals
	var now: float = app.meal_flow.now()
	var batch: Dictionary = meals.create_batch("garden_skillet", str(app.household.selected_id()), 1, "home", now)
	check(not batch.is_empty(), "The ledger creates a batch for the spoilage check.")
	check(absf(float(batch.expires) - (now + LifeMeals.FRESH_MINUTES)) < 0.001, "A fresh dish keeps for exactly one game day.")
	var table: Dictionary = app.world.closest_item("dining", Vector3.ZERO)
	if not table.is_empty():
		var slot: Vector3 = app.meal_flow._surface_slot(table, LifeMeals.PLATTER_HALF_SIZE, str(batch.id))
		meals.set_batch_location(str(batch.id), "surface", str(table.id), table.node.to_global(slot), now)
		batch.offset = [slot.x, slot.y, slot.z]
		var menu: Array = app.sim.get_actions_for("meal", str(batch.id)).map(func(a: Dictionary) -> String: return str(a.id))
		check(not menu.has("bin_meal") or app.sim.get_actions_for("meal", str(batch.id)).filter(func(a: Dictionary) -> bool: return str(a.id) == "bin_meal")[0].available == false, "Fresh food is not offered to the bin.")
		batch.expires = now - 1.0
		var spoiled: Array = app.sim.get_actions_for("meal", str(batch.id)).filter(func(a: Dictionary) -> bool: return str(a.id) == "bin_meal")
		check(spoiled.size() == 1 and bool(spoiled[0].available), "Spoiled food offers Throw it in the bin.")
	meals.discard_batch(str(batch.id))


## The household reports a 0..1 pregnancy progress while a mother is expecting.
func _pregnancy_meter() -> void:
	check(app.household.pregnancy_progress() < 0.0, "An idle household reports no pregnancy progress.")
	check(app.household.pregnancy_mother_id().is_empty(), "An idle household names no expecting mother.")
	var mother: LifeSim = app.household.selected()
	var father: LifeSim = app.household.members[1].sim if app.household.members.size() > 1 else mother
	if father == mother: return
	app.household.pregnancy = LifeBabyPlan.conceive(mother, str(app.household.members[0].id), father, str(app.household.members[1].id), app.household.day, app.household.minutes, 1)
	check(app.household.pregnancy_progress() >= 0.0 and app.household.pregnancy_progress() <= 0.01, "A fresh pregnancy starts near zero progress.")
	app.household.minutes += LifeBabyPlan.PREGNANCY_MINUTES * 0.5
	check(float(app.household.pregnancy_progress()) > 0.4 and float(app.household.pregnancy_progress()) < 0.6, "Halfway through the term reads about half.")
	check(app.household.pregnancy_mother_id() == str(app.household.members[0].id), "The expecting mother is reported by id.")
	app.household.pregnancy = LifeBabyPlan.fresh()


## A wall between two same-floor points blocks the line of sight, and an open
## doorway between them does not.
func _wall_sightlines() -> void:
	check(app.world.sight_line_clear(Vector3(0, .16, 0), Vector3(0, .16, 2)), "An open stretch of floor has a clear sightline.")
	check(not app.world.sight_line_clear(Vector3(0, .16, -4.5), Vector3(0, .16, -6.5)), "The back wall blocks a sightline through it.")
	# Across the room's interior partition (a wall at x=1.0 spanning z=-5.02..-1.42).
	check(not app.world.sight_line_clear(Vector3(.2, .16, -2.0), Vector3(1.8, .16, -2.0)), "The interior partition blocks a sightline through it.")
	check(app.world.sight_line_clear(Vector3(.2, .16, -2.0), Vector3(.2, .16, -3.0)), "Two points on the same side of a partition can see each other.")
	check(app.world.sight_line_clear(Vector3(-3.0, .16, -1.0), Vector3(-3.0, .16, 1.0)), "An open room interior keeps its sightlines.")
