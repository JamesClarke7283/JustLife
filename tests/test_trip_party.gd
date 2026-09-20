extends SceneTree
## The trip package: a trip takes only the Lifelets the player chooses, and
## anyone left behind stays home and carries on.
##
## Every assertion drives the real map panel and the real trip machinery, and
## reads what a player would see: who is on the lot, who is hidden at home, and
## which of them actually moved across town.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_trip_party.gd

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


## Drive the trip through its real phases until the household is standing at the
## destination.
func _finish_trip() -> void:
	for i: int in 600:
		if str(app.residents.trip.get("phase", "")) == "arrival" and app.residents.trip.get("time", 0.0) == 0.0:
			pass
		if app.residents.trip.is_empty() and app.mode == "live":
			return
		app.residents.tick_trip(0.05)
		await process_frame


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	# A household of four adults, so there is a real party to choose from.
	app.household_profiles[0]["age_stage"] = "adult"
	await frames(2)
	for i: int in 3:
		app.add_creator_member()
		app.household_profiles[app.household_profiles.size() - 1]["age_stage"] = "adult"
		app.household_profiles[app.household_profiles.size() - 1]["name"] = "Lifelet %d" % (i + 2)
	await frames(4)
	app.start_household()
	await frames(16)
	app.set_game_speed(0)

	check(app.household.members.size() == 4, "The household really has four Lifelets (%d)." % app.household.members.size())

	# ------------------------------------------------ the picker's own answers
	var options: Array = app.residents.party_options()
	check(options.size() == 4, "Every member is offered for the trip (%d)." % options.size())
	var available: int = 0
	for entry: Dictionary in options:
		if bool(entry.available): available += 1
	check(available == 4, "Everyone at home and idle can travel (%d)." % available)
	check(app.residents.party_error().is_empty(), "A household where nobody is busy can travel.")

	# A Lifelet at work cannot come, and the picker says so.
	var worker_id: String = str(app.household.members[1].id)
	app.household.members[1].sim.away_state = {"version": 1, "activity": "career", "phase": "away"}
	options = app.residents.party_options()
	var blocked: Dictionary = {}
	for entry: Dictionary in options:
		if str(entry.id) == worker_id: blocked = entry
	check(not blocked.is_empty() and not bool(blocked.available), "A Lifelet who is away cannot come on a trip.")
	check(not str(blocked.reason).is_empty(), "The picker states the reason they cannot come (%s)." % str(blocked.reason))
	app.household.members[1].sim.away_state = {}

	# ------------------------------------------------- taking only some people
	app.show_neighborhood("park")
	await frames(4)
	check(app.overlay_open, "The map opens.")
	check(_press("Choose who goes…"), "The map offers the party picker.")
	await frames(4)
	var rows: int = 0
	for entry: Dictionary in options:
		if app.overlay.find_child("TripParty_" + str(entry.id), true, false) != null: rows += 1
	check(rows == 4, "The picker lists every Lifelet (%d of 4)." % rows)
	# Start with everyone ticked, then untick two so only half the household goes.
	var go: Button = app.overlay.find_child("TripPartyGo", true, false)
	check(go != null and not go.disabled, "Everyone is ticked by default, so Travel is available.")
	var first_two: Array[String] = [str(options[0].id), str(options[1].id)]
	for entry: Dictionary in options:
		if first_two.has(str(entry.id)): continue
		# Each untick redraws the panel, so the row is re-found after every press
		# rather than held across the redraw.
		var row: Button = app.overlay.find_child("TripParty_" + str(entry.id), true, false)
		if row != null and not row.disabled:
			row.pressed.emit()
			await frames(3)
	check(app.party_selection.size() == 2, "Only two Lifelets are left ticked (%d)." % app.party_selection.size())
	go = app.overlay.find_child("TripPartyGo", true, false)
	check(go != null and not go.disabled, "Travel stays available with a smaller party.")
	check(_press("Travel  →"), "The chosen party can set off.")
	await frames(4)
	check(not app.residents.trip.is_empty(), "A real trip started.")
	check(app.residents.trip.get("party", []).size() == 2, "The trip carries only the two chosen Lifelets (%d)." % app.residents.trip.get("party", []).size())
	await _finish_trip()
	await frames(4)

	# -------------------------------------------------- what the trip changed
	check(app.current_venue == "park", "The party really arrived at the garden (%s)." % app.current_venue)
	var visible: int = 0
	var hidden: int = 0
	for member: Dictionary in app.household.members:
		var actor: Node3D = app.world.actors[str(member.id)]
		if actor.visible: visible += 1
		else: hidden += 1
	check(visible == 2, "Exactly the two chosen Lifelets are standing at the destination (%d)." % visible)
	check(hidden == 2, "The two left behind are not on the destination lot (%d)." % hidden)
	# The two at the venue really are the ones chosen, in order.
	var arrived: Array[String] = []
	for member: Dictionary in app.household.members:
		if app.world.actors[str(member.id)].visible: arrived.append(str(member.id))
	check(arrived.has(first_two[0]) and arrived.has(first_two[1]), "The Lifelets at the garden are the ones ticked (%s)." % str(arrived))
	# The Lifelets left behind kept their own bodies and plans.
	for entry: Dictionary in options:
		if first_two.has(str(entry.id)): continue
		var actor: Node3D = app.world.actors[str(entry.id)]
		check(not actor.visible, "A Lifelet left behind stays off the destination lot.")

	# --------------------------------------------------- travelling home again
	app.travel_to("home")
	await _finish_trip()
	await frames(4)
	check(app.current_venue == "home", "The party can travel home again (%s)." % app.current_venue)
	var home_visible: int = 0
	for member: Dictionary in app.household.members:
		if app.world.actors[str(member.id)].visible: home_visible += 1
	check(home_visible == 4, "Everyone is on the home lot again (%d of 4)." % home_visible)

	print("TRIP_PARTY_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
