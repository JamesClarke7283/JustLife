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

	app.queue_free()
	await process_frame
	print("HOUSEHOLD_EXTRAS %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
