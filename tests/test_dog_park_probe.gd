extends SceneTree
## Dog park lot type plus public park café and restrooms away from home.
var checks: int = 0
var failures: Array = []
var app: Node


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	# Static venue policy first — no world required.
	check(LifeVenues.has("dog_park"), "Dog park is a travelable venue")
	check(LifeVenues.validate("dog_park").is_empty(), "Dog park layout validates (%s)" % LifeVenues.validate("dog_park"))
	var dog_kinds: Array = []
	for entry: Dictionary in LifeVenues.layout("dog_park"):
		dog_kinds.append(str(entry.kind))
	check(dog_kinds.has("kennel") and dog_kinds.has("pet_bowl"), "Dog park has kennels and bowls")
	check(dog_kinds.has("pet_bed_dog") and dog_kinds.has("pet_toy_dog"), "Dog park has beds and toys for visiting dogs")
	var dog_offers: Array = LifeVenues.offers("dog_park")
	check(dog_offers.size() >= 3, "Dog park offers socialization services")
	check(dog_offers.any(func(o: Dictionary) -> bool: return str(o.id) == "dog_social"), "Dog park offers Let the dogs socialise")

	# Public park: café kiosk furnishings and restrooms.
	var park_kinds: Array = []
	for entry: Dictionary in LifeNeighborhood.layout("park"):
		park_kinds.append(str(entry.kind))
	check(park_kinds.has("toilet") and park_kinds.has("sink"), "Public park has restrooms")
	check(park_kinds.has("counter") and park_kinds.has("fridge"), "Public park has a café kiosk")
	var park_offers: Array = LifeNeighborhood.offers("park")
	check(park_offers.any(func(o: Dictionary) -> bool: return str(o.id).begins_with("park_cafe")), "Park café services are offered")
	check(LifeNeighborhood.offers("cafe").size() >= 1, "Neighbourhood offers still resolve café venue services")

	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)

	# Lay out the park and use café + toilet the way a visitor would.
	app.current_venue = "park"
	app.loading_game = true
	app.setup_live(LifeNeighborhood.layout("park"))
	app.loading_game = false
	await frames(4)
	var has_toilet: bool = false
	var has_counter: bool = false
	for item: Dictionary in app.world.items:
		if str(item.kind) == "toilet": has_toilet = true
		if str(item.kind) == "counter": has_counter = true
	check(has_toilet and has_counter, "Park world places restroom and café counter")
	var toilet: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "toilet": toilet = item; break
	check(not toilet.is_empty(), "Toilet is clickable at the park")
	var toilet_actions: Array = app.sim.get_actions_for("toilet", str(toilet.id))
	check(toilet_actions.any(func(a: Dictionary) -> bool: return str(a.id) == "toilet" and bool(a.available)), "Bladder can be handled at the park toilet")

	app.sim.needs.hunger = 20.0
	app._use_venue_service("park", "park_cafe_lunch")
	check(float(app.sim.needs.hunger) >= 50.0, "Park café lunch raises hunger away from home")

	# Dog park world and socialization credit.
	app.current_venue = "dog_park"
	app.loading_game = true
	app.setup_live(LifeVenues.layout("dog_park"))
	app.loading_game = false
	await frames(4)
	check(app.world.items.any(func(i: Dictionary) -> bool: return str(i.kind) == "kennel"), "Dog park world places kennels")
	var pets: Dictionary = app.household.pets
	if not pets.has("pets") or not pets.pets is Array:
		pets["pets"] = []
	pets.pets.append({
		"id": "pet_dog_park", "species": "dog", "name": "Rusty", "sex": "male",
		"coat_color": "8b5a2b", "mark_color": "3b2a1a",
		"care": LifePetCare.fresh(), "tricks": [],
	})
	app.household.pets = pets
	var before_fun: float = float(app.household.pet_care("pet_dog_park").needs.fun)
	app.sim.needs.social = 40.0
	app._use_venue_service("dog_park", "dog_social")
	check(float(app.sim.needs.social) > 50.0, "Dog park socialising lifts the Lifelet")
	check(float(app.household.pet_care("pet_dog_park").needs.fun) > before_fun, "Dog park socialising lifts the dog")

	_finish()


func _finish() -> void:
	var out := FileAccess.open("res://evidence/dog_park_probe.txt", FileAccess.WRITE)
	if out:
		out.store_string("checks=%d failures=%d\n" % [checks, failures.size()])
		for line: String in failures:
			out.store_string("FAIL: %s\n" % line)
		out.close()
	print("DOG_PARK_PROBE assertions=%d failures=%d" % [checks, failures.size()])
	for line: String in failures:
		print("FAIL: ", line)
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
