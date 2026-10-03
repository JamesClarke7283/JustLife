extends SceneTree
## The school bus drives in from off the lot, then a child walks out and boards.
## Neighbourhood children and a pet keep walking past the home.

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _initialize() -> void:
	var lot: Rect2 = LifeLand.rect(LifeLand.fresh())
	var bus := LifeSchoolBus.new()
	LifeSchoolBus.active = bus
	bus.consider(true, 470.0, 1)
	check(bus.phase == "approaching" and bus.off_lot(lot), "The bus starts off the lot, not already parked (%s)." % str(bus.position))
	var early := LifeSim.new()
	early.new_household({"name": "Kit", "age_stage": "child", "traits": []})
	early.autonomy = false
	var before: Dictionary = early._commute_choice("school_day", [])
	check(str(before.get("id", "")) != "board_school_bus", "Children do not board until the bus has reached the curb.")
	early.free()
	var guard: int = 0
	while bus.phase == "approaching" and guard < 40:
		bus.tick(1.0)
		guard += 1
	check(bus.waiting() and bus.position.distance_to(LifeSchoolBus.CURB) < 0.2, "The bus drives up to the curb (phase %s)." % bus.phase)
	check(lot.has_point(Vector2(bus.position.x, bus.position.z)), "The curb stop is outside the house, on the lot frontage.")
	var child := LifeSim.new()
	child.new_household({"name": "Kit", "age_stage": "child", "traits": []})
	child.autonomy = false
	child.register_targets([{"id": "exit", "kind": "lot_exit", "position": Vector3(0, .16, 8)}])
	var ride: Dictionary = child._commute_choice("school_day", [])
	check(str(ride.get("id")) == "board_school_bus" and str(ride.get("target_id")) == "school_bus_stop",
		"Boarding does not need a bus already placed on the lot (%s)." % str(ride.get("target_id")))
	check(child.queue_action("board_school_bus", "school_bus_stop", ride.position), "The child queues the walk out to the bus.")
	check(str(child.get_current_action().phase) == "approach" and Vector3(child.get_current_action().target_position).distance_to(bus.door_position()) < 0.2,
		"The child walks to the curb-side bus door, clear of the vehicle body.")
	child.begin_current_action()
	child.tick((float(child.get_current_action().duration) + 0.5) / LifeSim.GAME_MINUTES_PER_SECOND)
	check(bus.phase == "departing" and bus.boarded == 1, "Boarding sends the bus on its way.")
	var away: int = 0
	while bus.phase == "departing" and away < 40:
		bus.tick(1.0)
		away += 1
	check(bus.phase == "gone", "The morning bus leaves the street during the school day.")
	# ---- the morning run is made once: a bus that has left does not come back for the same pupil
	bus.consider(true, 510.0, 1, 1, 1)
	check(bus.phase == "gone", "The morning bus does not come back for a second go the same day.")
	# ---- and with nobody at school there is nothing to bring home
	bus.consider(true, 895.0, 0, 1, 0)
	check(bus.phase == "gone", "With nobody at school the bus makes no afternoon run.")
	bus.consider(true, 895.0, 0, 1, 1)
	check(bus.phase == "returning", "The bus comes back at the end of the school day.")
	var homeward: int = 0
	while bus.phase == "returning" and homeward < 20:
		bus.consider(true, 892.0, 0, 1, 1)
		bus.tick(1.0)
		homeward += 1
	check(bus.phase == "dropping" and bus.position.distance_to(LifeSchoolBus.CURB) < 0.2, "The afternoon bus stops at the same curb to drop the children.")
	for _wait in 30:
		bus.consider(true, 900.0, 0, 1, 1)
		bus.tick(1.0)
	check(bus.phase == "dropping", "The doors stay open while a pupil is still to step off.")
	check(bus.disembark("kit") == "off" and bus.disembark("rae") == "wait", "Pupils step off one at a time.")
	bus.tick(LifeSchoolBus.STEP_OFF_GAP + 0.1)
	check(bus.disembark("rae") == "off" and bus.dropped == 2, "The next pupil steps off after a short gap.")
	for _wait in 14:
		bus.consider(true, 905.0, 0, 1, 0)
		bus.tick(1.0)
	check(bus.phase == "leaving" or bus.phase == "gone", "After the last pupil is off the bus drives away again.")
	var gone: int = 0
	while bus.phase == "leaving" and gone < 60:
		bus.consider(true, 910.0, 0, 1, 0)
		bus.tick(1.0)
		gone += 1
	check(bus.phase == "gone", "The afternoon bus leaves the street.")
	for minute in range(895, 920):
		bus.consider(true, float(minute), 0, 1, 1)
	check(bus.phase == "gone", "The afternoon run is made once a day, however many are still about.")
	bus.consider(true, 450.0, 1, 2)
	check(bus.phase == "approaching" and bus.run_day == 2, "The next school day starts a new morning run.")
	bus.reset()
	check(bus.phase == "gone" and bus.run_day == 0 and bus.drop_day == 0 and bus.aboard.is_empty(), "A new household or a loaded game starts with a bare street.")

	# ---- a bus nobody boards still leaves, and not before it has waited
	var idle := LifeSchoolBus.new()
	idle.consider(true, 470.0, 1, 3)
	while idle.phase == "approaching":
		idle.tick(1.0)
	check(idle.waiting(), "An empty-handed bus waits at the curb.")
	idle.consider(true, 539.0, 1, 3)
	check(idle.waiting(), "It waits for the end of boarding time.")
	idle.consider(true, 540.0, 1, 3, 0, 1)
	check(idle.waiting(), "It holds a little longer for a pupil already walking to the door.")
	idle.consider(true, 559.0, 1, 3, 0, 1)
	check(idle.waiting(), "It holds for that pupil until 09:20.")
	idle.consider(true, 560.0, 1, 3, 0, 1)
	check(idle.phase == "departing", "It never holds past 09:20.")
	var empty_run := LifeSchoolBus.new()
	empty_run.consider(true, 470.0, 1, 3)
	while empty_run.phase == "approaching":
		empty_run.tick(1.0)
	empty_run.consider(true, 500.0, 0, 3, 1)
	check(empty_run.phase == "departing", "It leaves at once when nobody is left at home to go.")
	var weekend := LifeSchoolBus.new()
	weekend.consider(false, 470.0, 1, 6)
	weekend.consider(false, 895.0, 0, 6, 1)
	check(weekend.phase == "gone", "There is no bus at the weekend.")
	var stale := LifeSchoolBus.new()
	stale.consider(true, 470.0, 1, 3)
	while stale.phase == "approaching":
		stale.tick(1.0)
	stale.consider(true, 100.0, 1, 4)
	check(stale.phase == "departing", "A waiting bus left over from an earlier day drives off.")
	var street := LifeStreetLife.new()
	for _step in 40:
		street.tick(1.0)
	var child_passes: int = 0
	var pet_passes: int = 0
	for passer: Dictionary in street.passers:
		if str(passer.kind) == "child":
			child_passes += int(passer.passed_home)
		if str(passer.kind) == "pet":
			pet_passes += int(passer.passed_home)
		check(int(passer.trips) >= 1, "%s turns around and keeps walking (%d trips)." % [str(passer.id), int(passer.trips)])
	check(child_passes >= 2 and pet_passes >= 2, "Children and a pet pass the front of the home more than once (%d, %d)." % [child_passes, pet_passes])
	LifeSchoolBus.clear_active()
	child.free()
	print("BUS_AND_STREET %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
