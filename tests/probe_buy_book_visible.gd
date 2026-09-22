extends SceneTree
## Reproduce the buy_book use-after-free: after a model rebuild, held-book
## refs must not receive `.visible` writes. Also buy a shelf book through the
## household service so refresh_props runs on live ShelfBook nodes.

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
	var actor: LifeActor = LifeActor.new()
	root.add_child(actor)
	await process_frame
	actor.configure({"name": "Taylor", "age_stage": "young_adult", "low_detail": true})
	await process_frame
	# A second configure frees the first model's HeldBook nodes. Stale refs in
	# `_books` used to make buy_book's pose crash on `.visible = true`.
	actor.configure({"name": "Taylor", "age_stage": "adult", "low_detail": true})
	await process_frame
	actor.animate(0.05, 1.0, false, "buy_book")
	await process_frame
	check(true, "buy_book pose after reconfigure does not crash on held-book visibility.")
	var live_books: int = 0
	for held: Node3D in actor.get("_books"):
		if is_instance_valid(held):
			live_books += 1
			check(held.visible, "A live held book is shown during buy_book.")
	check(live_books == 2, "Exactly two live held books remain after rebuild (got %d)." % live_books)
	actor.queue_free()
	await process_frame

	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	app.set_process(false)
	var flow: LifeHouseholdFlow = app.household_flow
	var shelf: Dictionary = app.world.closest_item("bookshelf", Vector3.ZERO)
	check(not shelf.is_empty(), "The starter home has a bookshelf.")
	if not shelf.is_empty():
		# Age-refresh the selected actor, then buy — the path players hit after
		# a birthday or wardrobe rebuild before shelving a skill book.
		var member_id: String = str(app.household.members[app.household.selected_index].id)
		app._refresh_aged_member(member_id)
		await process_frame
		var bought: Dictionary = flow.buy_book(str(shelf.id), "logic")
		check(bool(bought.ok), "A Logic book can be bought after an actor rebuild.")
		var actor2: LifeActor = app.world.actors.get(member_id) as LifeActor
		if is_instance_valid(actor2):
			actor2.animate(0.05, 1.0, false, "buy_book")
			await process_frame
			check(true, "buy_book pose on a live household actor after age refresh does not crash.")
	app.queue_free()
	await process_frame
	print("BUY_BOOK_VISIBLE %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
