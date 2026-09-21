extends "res://tests/test_school_playthrough.gd"
## Public renderer flow: a couch is really shared seating. Three Lifelets each
## click the sofa and take their own cushion — not one seat and a queue — and the
## three of them are sitting on it at once, side by side.

const SITTERS: Array[String] = ["Morgan Reed", "Casey Vale", "Ellis Reed"]


func _run() -> void:
	screenshot_dir = "res://art/couch_seating"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene = app
	await frames(4)
	app.set_sound(false)
	if resume_only:
		await _restart_couch()
		_write_report();app.queue_free();await frames(3)
		print("COUCH_PLAYTHROUGH assertions=%d failures=%d resume=true" % [assertions, failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	await _enter_new_game()
	for i: int in range(3):
		if i > 0: await press("+ Add Lifelet")
		_set_name(SITTERS[i]);await _choose_age("Adult")
	await press_member(SITTERS[0])
	await press("Find my home", true);await press("A Fresh Canvas");await press("Start living", true)
	await press("Ⅱ")
	for member: Dictionary in app.household.members: member.sim.autonomy = false
	check(app.household.members.size() == 3, "Three adults move into the empty lot.")
	app.household.set_funds(app.sim.funds + 4000)

	# A three-seater is bought through the ordinary purchase path. The fresh lot
	# is bare, so the placement scan uses the lot's own clear ground.
	await press("Build & buy")
	var before: int = app.world.items.size()
	var placed_at: Vector3 = Vector3.INF
	for z: float in [0.0, 2.0, -2.0, 4.0, -4.0]:
		for x: float in [0.0, 2.0, -2.0, 4.0, -4.0]:
			var at := Vector3(x, 0.16, z)
			if not app.world.can_place("sofa", at, 0.0): continue
			app.on_placement("sofa", at, 0.0)
			await frames(2)
			if app.world.items.size() == before + 1:
				placed_at = at
				break
		if placed_at.is_finite(): break
	check(app.world.items.size() == before + 1, "A Sunday sofa is bought through the public purchase path at %s." % str(placed_at))
	await press("Live")
	var sofa: Dictionary = app.world.closest_item("sofa", placed_at if placed_at.is_finite() else Vector3.ZERO)
	check(not sofa.is_empty(), "The sofa resolves in the world.")
	if sofa.is_empty():
		_write_report();app.queue_free();await frames(3)
		print("COUCH_PLAYTHROUGH assertions=%d failures=%d" % [assertions, failures.size()]);quit(1);return
	check(app.world.seat_capacity(sofa) == 3, "The bought sofa really has three places (%d)." % app.world.seat_capacity(sofa))

	# Each Lifelet sits, and each takes a different cushion of the one sofa.
	var seats: Array[String] = []
	for i: int in range(3):
		await press_member(SITTERS[i])
		await _sit(sofa)
		await press("▶")
		await wait_until(func() -> bool: return active_is("relax"), SITTERS[i] + " sits down", 40)
		await press("Ⅱ")
		var action: Dictionary = app.sim.get_current_action()
		check(str(action.get("target_id", "")) == str(sofa.id),
			"%s is seated on the sofa (target %s)." % [SITTERS[i], str(action.get("target_id", "<none>"))])
		seats.append(str(action.get("seat_slot", "")))
		check(not app.waiting_for_target, "%s is sitting rather than queueing." % SITTERS[i])
	check(seats.size() == 3 and seats[0] != seats[1] and seats[1] != seats[2] and seats[0] != seats[2],
		"The three Lifelets hold three different cushions (%s)." % str(seats))
	# All three are on the sofa at the same moment, in separate places.
	var occupied: int = 0
	var places: Array[Vector3] = []
	for member: Dictionary in app.household.members:
		var action: Dictionary = member.sim.get_current_action()
		if str(action.get("id", "")) == "relax" and str(action.get("target_id", "")) == str(sofa.id):
			occupied += 1
			var actor: LifeActor = app.world.actors.get(str(member.id))
			if is_instance_valid(actor): places.append(app.world.activity_anchor(sofa, "relax", {"seat_slot": str(action.get("seat_slot", ""))}).position)
	check(occupied == 3, "Three Lifelets are sitting on the one sofa at once (%d)." % occupied)
	var apart: bool = true
	for i: int in places.size():
		for j: int in range(i + 1, places.size()):
			if (places[i] as Vector3).distance_to(places[j] as Vector3) < 0.5: apart = false
	check(places.size() == 3 and apart, "They sit apart on their own cushions rather than stacked (%s)." % str(places))
	await screenshot("01_three_on_the_sofa", false, false)
	await _save_couch()
	_write_report();app.queue_free();await frames(3)
	print("COUCH_PLAYTHROUGH assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


## Save the three seated Lifelets and the sofa they hold, so a fresh process can
## confirm the same three cushions come back rather than two people on one seat.
func _save_couch() -> void:
	var expected: Dictionary = {"world":app.world.serialize_items(),"members":[]}
	for member: Dictionary in app.household.members:
		var action: Dictionary = member.sim.get_current_action()
		expected.members.append({"id":member.id,"seat_slot":str(action.get("seat_slot", "")),"target_id":str(action.get("target_id", "")),"action":str(action.get("id", ""))})
	await _public_save("Couch — three sharing one sofa")
	var file := FileAccess.open("user://couch_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected));file.close()


func _restart_couch() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://couch_expected.json"))
	check(not expected.is_empty(), "The producer left a couch expectation for the fresh process.")
	if expected.is_empty():
		return
	await _public_load()
	await frames(4)
	var sofa: Dictionary = app.world.closest_item("sofa", Vector3(0.0, 0.16, 0.0))
	check(not sofa.is_empty(), "The sofa comes back in the loaded home.")
	if sofa.is_empty():
		return
	check(app.world.seat_capacity(sofa) == 3, "The reloaded sofa still holds three places (%d)." % app.world.seat_capacity(sofa))
	var slots: Array[String] = []
	for member: Dictionary in app.household.members:
		var action: Dictionary = member.sim.get_current_action()
		if str(action.get("id", "")) != "relax" or str(action.get("target_id", "")) != str(sofa.id): continue
		slots.append(str(action.get("seat_slot", "")))
	check(slots.size() == 3, "Three Lifelets come back seated on the one sofa (%d)." % slots.size())
	check(slots.size() == 3 and slots[0] != slots[1] and slots[1] != slots[2] and slots[0] != slots[2],
		"They come back on three different cushions (%s)." % str(slots))


## Click the sofa and choose to sit on it, through the real object menu.
func _sit(item: Dictionary) -> void:
	var screen: Vector2 = app.world.camera.unproject_position(item.node.position + Vector3(0, .6, 0))
	app.world.object_clicked.emit(item, screen)
	await frames(2)
	await press(str(app.sim.get_action_definition("relax").label), true)
	check(app.sim.get_current_action().get("id", "") == "relax", "Public object interaction queues sitting down.")
