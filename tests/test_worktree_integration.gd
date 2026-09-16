extends SceneTree
## Controlled controller-level checks for the wardrobe, household bills and
## passing features merged from separate worktrees. No pointer/render claims.

var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func memorial_count(layout: Array, member_id: String) -> int:
	var count: int = 0
	for item: Dictionary in layout:
		if str(item.get("kind", "")) == "memorial" and str(item.get("for", "")) == member_id:
			count += 1
	return count

func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.set_process(false)
	app.household_profiles = [LifeCharacterIdentity.generate(8401, {"name":"Rowan Vale", "age_stage":"elder"})]
	app.creator_family_links = []
	app.selected_lot = 2
	app.start_household()
	app.household.set_speed(0)
	app.sim.autonomy = false
	app.sim.set_aging("normal", false)
	await process_frame

	# The two looks deliberately share every legacy clothing field. The live
	# controller must still swap category-specific meshes, including on Pause.
	var person: LifeSim = app.sim
	person.character.outfit_collection.formal = person.character.outfit_collection.everyday.duplicate(true)
	LifeCharacterIdentity.apply_category(person.character, "formal")
	check(str(app.player.profile.outfit_category) == "everyday", "The actor initially presents Everyday while the simulation changes its look.")
	app._process(0.01)
	check(str(app.player.profile.outfit_category) == "formal" and is_instance_valid(app.player._look_root), "A category-only change reaches the live actor and adds the Formal garment.")
	LifeCharacterIdentity.apply_category(person.character, "everyday")
	app._process(0.01)
	check(str(app.player.profile.outfit_category) == "everyday" and not is_instance_valid(app.player._look_root), "Returning to identical Everyday clothes removes the category garment.")

	# The live lot can change before its cached home layout is next saved.
	var home_value: int = 0
	for kind: String in ["fridge", "bed", "toilet", "shower", "stove", "wardrobe"]:
		home_value += int(LifeCatalog.ITEMS[kind].price)
	check(app.home_value() == home_value, "Home valuation reads the six furnishings on the fresh-canvas lot.")
	app.world.add_item({"id":"integration_piano", "kind":"piano", "x":-3.0, "z":2.0, "rotation":0.0})
	home_value += int(LifeCatalog.ITEMS.piano.price)
	check(app.home_value() == home_value, "A newly placed furnishing counts before the cached home layout refreshes.")
	app.home_layout = app.world.serialize_items()
	var saved_home: Array = app.home_layout.duplicate(true)

	# Use the ordinary arrival/setup path with a genuinely different lot; this
	# fixture does not claim to exercise driving or boarding.
	app.current_venue = "library"
	app.setup_live(LifeNeighborhood.layout("library"))
	check(app.home_value() == home_value and person.home_value() == home_value, "At the library, both controller and billing provider still value the household's home.")
	person.pending_bill.clear()
	person.last_bill_day = 0
	person._advance_bill_cycle()
	check(int(person.pending_bill.get("amount", -1)) == LifeSim.bill_amount_for(home_value), "A bill issued while away uses the saved home's furnishing value.")

	# Passing emits the real household signal into main while its actor exists.
	var actor_before: LifeActor = app.world.actors.player
	person.lifecycle.progress = 1.0
	var passing: Dictionary = app.household.pass_away("player")
	check(bool(passing.ok) and person.is_spirit(), "An elder can pass while the household visits another venue.")
	check(app.world.actors.player == actor_before and str(actor_before.profile.life_status) == "passed", "The passing signal refreshes the existing actor without replacing the member.")
	check(memorial_count(app.world.serialize_items(), "player") == 0, "Passing at the library does not place a household memorial on the public lot.")
	check(app.home_layout == saved_home, "Passing away from home preserves the saved home furnishings until return.")
	check(app.household.memorials.size() == 1, "The memorial record waits with the household.")

	app.current_venue = "home"
	app.setup_live(app.home_layout)
	check(memorial_count(app.world.serialize_items(), "player") == 1, "Arriving home places the pending remembrance stone.")
	check(memorial_count(app.home_layout, "player") == 1, "The home layout retains the stone's member identity.")
	var with_memorial: Array = app.world.serialize_items()
	app.setup_live(with_memorial)
	check(memorial_count(app.world.serialize_items(), "player") == 1, "Restoring the home does not duplicate an existing remembrance stone.")
	app.queue_free()
	await process_frame
	print("WORKTREE_INTEGRATION_RESULT %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
