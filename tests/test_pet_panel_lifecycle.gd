extends SceneTree

var app: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Use an isolated absolute JUSTLIFE_DATA_DIR.")
		quit(2)
		return
	_run.call_deferred()

func frames(count: int = 2) -> void:
	for index: int in count:
		await process_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Avery", "age_stage": "adult", "traits": [], "hair": 0}]
	app.creator_family_links = []
	app.start_household()
	await frames(3)
	app.household.set_speed(0)
	app.set_process(false)
	var choice := 0
	for index: int in LifePets.candidate_count():
		if str(LifePets.candidate(1, index).species) == "dog":
			choice = index
			break
	var draft: Dictionary = LifePets.candidate(1, choice)
	draft.name = "Rex"
	var prepared: Dictionary = app.household.prepare_pet(draft)
	var home: Vector3 = app.pet_home_spot()
	var committed: Dictionary = app.household.commit_pet(prepared.get("request", {}), home)
	check(bool(committed.get("ok", false)), "Dog joins the household")
	if not bool(committed.get("ok", false)):
		quit(1)
		return
	var pet_id: String = str(committed.pet.id)
	app.spawn_pet(pet_id, committed.pet, home, home)

	app.show_pet_card(pet_id, true)
	await frames(2)
	check(app.pet_panel_bars.size() == 6 and app.pet_panel_values.size() == 6, "Pet card owns six live need rows")
	var old_bar: Variant = app.pet_panel_bars.get("hunger")
	check(is_instance_valid(old_bar), "The first card's Hunger bar is live")

	# This is the day-84 failure: the pet remains selected while a furnishing
	# menu replaces its card, then the regular HUD refresh runs again.
	app.show_interactions({"kind": "dog_toy_box", "id": "test_box", "label": "Dog Toy Box"}, Vector2(350, 240))
	await frames(3)
	check(str(app.selected_pet_id) == pet_id, "Pet remains selected during the toy-box menu")
	check(app.overlay_open and app.overlay.get_node_or_null("PetNeedsPanel") == null, "Dog Toy Box menu replaces the pet card")
	check(not is_instance_valid(old_bar), "The old pet bar was actually freed")
	check(app.pet_panel_bars.is_empty() and app.pet_panel_values.is_empty(), "Overlay closure releases pet-bar references")
	app.refresh_hud()
	await frames(2)
	check(app.overlay_open and app.overlay.get_node_or_null("PetNeedsPanel") == null, "HUD refresh preserves the other menu")

	app.show_pet_card(pet_id, true)
	await frames(2)
	check(app.pet_panel_bars.size() == 6 and is_instance_valid(app.pet_panel_bars.get("hunger")), "Reopened pet card has fresh bars")
	app.household.pet_care(pet_id).needs.hunger = 23.0
	app._refresh_pet_panel()
	var fresh_bar: Variant = app.pet_panel_bars.get("hunger")
	check(is_instance_valid(fresh_bar) and is_equal_approx(fresh_bar.value, 23.0), "Fresh pet card still refreshes live needs")

	# A stale entry is also safe if a child control is freed independently.
	fresh_bar.queue_free()
	await frames(3)
	check(not is_instance_valid(fresh_bar), "Standalone stale bar setup reached the freed state")
	app._refresh_pet_panel()
	check(app.overlay.get_node_or_null("PetNeedsPanel") != null, "A stale row cannot break the active pet card")
	app.queue_free()
	await frames()
	print("PET_PANEL_LIFECYCLE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
