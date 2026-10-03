extends SceneTree
## A pupil who takes the school bus has a real school day: it ends at 15:00 with
## attendance, the pupil comes home, homework is then due, and a save made during
## the day loads. Saves written before the fix (an absence with no school day on
## the queue) are mended on load.
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func pupil(stage: String = "child") -> LifeSim:
	var child := LifeSim.new()
	child.new_household({"name": "Kit", "age_stage": stage, "traits": []})
	child.autonomy = false; child.set_aging("normal", false); child.household_bills_enabled = false
	child.minutes = 490.0
	for need: String in LifeSim.NEED_NAMES: child.needs[need] = 80.0
	child.register_targets([{"id": "lot_exit", "kind": "lot_exit", "position": Vector3(0, .16, 8.5)}, {"id": "desk1", "kind": "desk", "position": Vector3(2, .16, 0)}])
	return child

func board(child: LifeSim, bus: LifeSchoolBus) -> void:
	child.queue_action("board_school_bus", "school_bus_stop", bus.door_position())
	child.begin_current_action()
	child.tick((float(child.get_current_action().duration) + .5) / LifeSim.GAME_MINUTES_PER_SECOND)

func run() -> void:
	var bus := LifeSchoolBus.new()
	LifeSchoolBus.active = bus
	bus.consider(true, 470.0, 1)
	var guard: int = 0
	while bus.phase == "approaching" and guard < 40:
		bus.tick(1.0); guard += 1
	var child: LifeSim = pupil()
	board(child, bus)
	check(child.is_away(), "Boarding the bus takes the pupil away")
	var front: Dictionary = child.get_current_action()
	check(str(front.get("id", "")) == "school_day" and str(front.get("phase", "")) == "active" and bool(front.get("paid", false)), "The school day is the action at the front of the queue, active and paid")
	check(str(front.get("target_kind", "")) == "lot_exit" and float(front.get("duration", 0.0)) > 300.0, "It runs to the end of the school day")

	# ---- a save made during the day loads, and the day still ends
	var saved: Dictionary = JSON.parse_string(JSON.stringify(child._json_safe(child.get_state())))
	var other := LifeSim.new()
	var restored: Dictionary = other.restore_state(saved)
	check(bool(restored.ok), "A save made while the pupil is on the bus day loads (%s)" % str(restored.get("error", "")))
	check(other.is_away() and str(other.get_current_action().get("id", "")) == "school_day", "The loaded pupil is still on their school day")

	# ---- the day ends at 15:00 with attendance, not at midnight
	var steps: int = 0
	while child.minutes < 960.0 and steps < 2000:
		child.tick(10.0); steps += 1
	check(str(child.get_away_state().get("phase", "")) == "returning", "At 16:00 the pupil is on the way home")
	check(int(child.education.attended) == 1 and int(child.education.last_attendance_day) == child.day, "Attendance is recorded for the day")
	check(child.complete_away_return() and not child.is_away(), "The pupil is home")
	child._idle_minutes = 0.0
	check(child._autonomy_duty_id() == "homework", "Homework is then due")

	# ---- the day they boarded the bus is not a missed day
	check(int(child.education.missed) == 0, "No school day was missed")

	# ---- a save written by the earlier build (away, no school day queued) is mended
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(pupil()._json_safe(pupil().get_state())))
	var away_pupil: LifeSim = pupil()
	board(away_pupil, bus)
	var broken: Dictionary = JSON.parse_string(JSON.stringify(away_pupil._json_safe(away_pupil.get_state())))
	broken.action_queue = []
	var mended := LifeSim.new()
	var mend_result: Dictionary = mended.restore_state(broken)
	check(bool(mend_result.ok), "A save with an absence and no school day loads (%s)" % str(mend_result.get("error", "")))
	check(mended.is_away() and not mended.action_queue.is_empty() and str(mended.get_current_action().get("id", "")) == "school_day", "The missing school day is rebuilt from the absence")
	steps = 0
	while mended.minutes < 960.0 and steps < 2000:
		mended.tick(10.0); steps += 1
	check(str(mended.get_away_state().get("phase", "")) == "returning" and int(mended.education.attended) == 1, "A mended pupil still comes home at 15:00 with attendance")

	# ---- an absence whose action went missing in a running game is rebuilt too
	var stranded: LifeSim = pupil()
	board(stranded, bus)
	stranded.action_queue.clear()
	stranded.tick(30.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	check(not stranded.action_queue.is_empty() and str(stranded.get_current_action().get("id", "")) == "school_day", "A running absence with no school day gets it back")

	# ---- the walk-to-the-exit path is unchanged
	var walker: LifeSim = pupil()
	check(walker.queue_action("school_day", "lot_exit", Vector3(0, .16, 8.5)), "A pupil can still be sent to the exit")
	walker.begin_current_action()
	check(walker.is_away() and str(walker.get_current_action().get("id", "")) == "school_day", "Leaving through the exit still starts the day")

	# ---- a pupil too hungry to go is turned back, not stranded on the bus
	var hungry: LifeSim = pupil()
	hungry.needs.hunger = 5.0
	board(hungry, bus)
	check(not hungry.is_away(), "A pupil with an empty stomach stays home")

	print("SCHOOL_BUS_DAY ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	LifeSchoolBus.active = null
	quit(0 if failures.is_empty() else 1)
