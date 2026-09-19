extends SceneTree
## The venue package: the town's working places — the shop, the café, the salon,
## the gym, the filling station, the school, the university and the prison — are
## real destinations the household can travel to and use.
##
## Every assertion drives the real map panel, the real trip machinery and the
## real world builder, and reads what a player would see: a place listed and
## described, a lot built and walkable, and a save that resumes there.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_venues.gd

const LifeVenues = preload("res://scripts/venues.gd")

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


func _finish_trip() -> void:
	for i: int in 600:
		if app.residents.trip.is_empty() and app.mode == "live":
			return
		app.residents.tick_trip(0.05)
		await process_frame


func _run() -> void:
	# ---------------------------------------------------------------- policy
	check(LifeVenues.ids().size() == 8, "Eight working venues are offered (%d)." % LifeVenues.ids().size())
	for place: String in LifeVenues.ids():
		check(LifeVenues.validate(place).is_empty(), "The %s venue is valid (%s)." % [place, LifeVenues.validate(place)])
		check(not LifeVenues.layout(place).is_empty(), "The %s has a real layout." % place)
		check(not LifeVenues.offers(place).is_empty(), "The %s offers real services." % place)
		for service: Dictionary in LifeVenues.offers(place):
			check(not str(service.label).is_empty() and not str(service.description).is_empty(),
				"%s's %s service is described." % [place, str(service.id)])
	# The brief's own venues are all present, with the services it named.
	for required: String in ["petrol_station", "shopping_centre", "hairdresser", "cafe", "gymnasium", "school", "university", "prison"]:
		check(LifeVenues.has(required), "The %s is in the town." % required)
	var fuel_services: Array = LifeVenues.offers("petrol_station")
	var fuel_text: String = ""
	for service: Dictionary in fuel_services:
		fuel_text += str(service.id) + " " + str(service.label) + " " + str(service.description) + " "
	check(fuel_text.to_lower().contains("petrol"), "The filling station really offers petrol.")
	check(fuel_text.to_lower().contains("electric"), "The filling station really offers electric charging.")
	check(LifeVenues.offers("shopping_centre").size() >= 3, "The shopping centre offers a weekly shop and more.")
	check(LifeVenues.PLACES.size() == 8, "Only the new venues are in this table; the originals stay in LifeNeighborhood.")
	# Every place the town can reach, originals and venues alike.
	check(LifeNeighborhood.travel_ids().size() == 16, "The town now has sixteen places (%d)." % LifeNeighborhood.travel_ids().size())
	check(LifeNeighborhood.has("cafe") and LifeNeighborhood.has("library"), "Both a new venue and an original place resolve.")
	check(LifeNeighborhood.is_venue("prison") and not LifeNeighborhood.is_venue("library"), "A working venue is distinguished from the original places.")

	# The charger and the electric car the brief asks for are real catalogue items.
	check(LifeCatalog.ITEMS.has("electric_charger"), "A wall charger is sold in the catalogue.")
	check(LifeCatalog.ITEMS.has("car_electric"), "An electric car is sold in the catalogue.")
	check(bool(LifeCatalog.ITEMS.electric_charger.get("wall_mounted", false)), "The charger must be mounted on a wall.")
	check(LifeCatalog.ITEMS.electric_charger.get("charges", "") == "car_electric", "The charger names what it charges.")
	# The wall rule is read from the entry, so a furnishing that declares itself
	# wall-mounted is refused free-standing without a second edit anywhere.
	check(LifeCatalog.wall_mounted("electric_charger"), "The charger really counts as wall-mounted.")
	check(LifeCatalog.wall_mounted("painting") and not LifeCatalog.wall_mounted("plant"),
		"The authored wall decor still counts, and an ordinary furnishing still does not.")

	# ------------------------------------------------------------- the town
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
	app.set_game_speed(0)

	app.show_neighborhood("cafe")
	await frames(4)
	check(app.overlay_open, "The map opens.")
	var rows: int = 0
	for id: String in LifeNeighborhood.travel_ids():
		if id == "home": continue
		if app.overlay.find_child("Place_" + id, true, false) != null: rows += 1
	check(rows == 15, "Every place other than home has a row in the list (%d of 15)." % rows)
	check(app.overlay.find_child("Place_cafe", true, false) != null, "The café is reachable from the list.")
	check(app.overlay.find_child("Place_prison", true, false) != null, "The prison is reachable from the list.")
	check(_press("Travel here  →"), "A venue can be travelled to.")
	await _finish_trip()
	await frames(4)
	check(app.current_venue == "cafe", "The household arrived at the café (%s)." % app.current_venue)
	check(app.world.items.size() >= 10, "The café was really built with its furnishings (%d)." % app.world.items.size())

	# The charger the brief asks for must go on a wall, and nowhere else. The
	# live game is asked the same question the player's click asks.
	check(not app.world.can_place("electric_charger", Vector3(-9.0, .16, 0.0), 0.0),
		"A wall charger is refused free-standing in the open garden.")
	check(app.world.can_place("plant", Vector3(-9.0, .16, 0.0), 0.0),
		"That same open spot really is free, so it is the charger's own rule refusing it.")
	var charger_spot: Dictionary = app.world.wall_snap("electric_charger", Vector3(-5.8, .16, 2.0), 1.0)
	check(not charger_spot.is_empty(), "A clear stretch of wall offers a place for the charger.")
	if not charger_spot.is_empty():
		check(app.world.can_place("electric_charger", charger_spot.position, float(charger_spot.angle)),
			"The charger really fits against that wall.")
		check(app.world.wall_behind("electric_charger", charger_spot.position, float(charger_spot.angle)),
			"The place the charger takes really is against a wall.")

	# The venue is a place, not a home: it cannot be built on or edited as one.
	app.set_build_mode(true)
	await frames(2)
	check(app.mode == "live", "A public venue cannot be edited as the household's own home.")

	# --------------------------------------------------- the other venues
	for venue: String in ["shopping_centre", "gymnasium", "petrol_station", "hairdresser", "school", "university", "prison"]:
		app.travel_to(venue)
		await _finish_trip()
		await frames(3)
		check(app.current_venue == venue, "The household can travel to the %s (%s)." % [venue, app.current_venue])
		check(app.world.items.size() >= 8, "The %s was really built with its furnishings (%d)." % [venue, app.world.items.size()])
		# The lot is walkable: the household can stand and move there.
		check(app.world.lot_navigation.point_clear(0, app.player.position),
			"The household stands on walkable ground at the %s." % venue)

	# The prison is where an incarcerated family member can be visited, so a
	# Lifelet serving a sentence at home can still be travelled to and seen.
	check(app.current_venue == "prison", "The prison is a real destination the household can reach.")

	# -------------------------------------------------- saving a venue visit
	app.home_layout = LifeCatalog.starter_layout(0)
	check(app.save_game("venue_probe", "Venue probe"), "The household saves while at the prison.")
	var slot: Dictionary = LifeSaveLibrary.read_slot("venue_probe")
	check(bool(slot.get("ok", false)), "The written slot reads back (%s)." % str(slot.get("error", "")))
	var members: Array = (slot.get("data", {}) as Dictionary).get("members", [])
	var saved_character: Dictionary = (members[0] as Dictionary).get("state", {}).get("character", {})
	var world_state: Dictionary = saved_character.get("world_state", {})
	check(str(world_state.get("venue", "")) == "prison", "The saved world records the prison as the venue (%s)." % str(world_state.get("venue", "")))
	# A fresh household accepts that save, so a venue visit resumes.
	var fresh: Object = load("res://scripts/life_sim.gd").new()
	root.add_child(fresh)
	fresh.new_household({"name": "Visitor", "age_stage": "adult", "traits": []})
	check(bool(fresh.restore_state((members[0] as Dictionary).get("state", {})).ok), "A save at a venue is valid.")
	fresh.free()
	# A save naming a place that does not exist is refused.
	var damaged: Dictionary = app.sim.get_state()
	damaged.character.world_state["venue"] = "moon"
	check(not bool(app.sim.restore_state(damaged).ok), "A save at an unknown venue is refused.")
	LifeSaveLibrary.delete_slot("venue_probe")

	print("VENUES_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "places": LifeNeighborhood.travel_ids().size()}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
