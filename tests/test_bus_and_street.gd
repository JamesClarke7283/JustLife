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
	check(str(child.get_current_action().phase) == "approach" and Vector3(child.get_current_action().target_position).distance_to(LifeSchoolBus.CURB) < 0.2,
		"The child walks out to the curb where the bus is waiting.")
	child.begin_current_action()
	child.tick((float(child.get_current_action().duration) + 0.5) / LifeSim.GAME_MINUTES_PER_SECOND)
	check(bus.phase == "departing" and bus.boarded == 1, "Boarding sends the bus on its way.")
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
