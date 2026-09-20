extends "res://tests/test_school_day.gd"
## Focused independent review of school timing, recovery and saved late grades.

func run() -> void:
	_partial_care_matrix()
	_late_grade_archives()
	_invalid_late_records()
	_expiring_queued_departure()
	_dual_critical_paid_cooking()
	_school_preparation_boundaries()
	_enrollment_cutoff()
	for sim: LifeSim in owned: sim.free()
	print("SCHOOL_POLICY_ADVERSARIAL %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _partial_care_matrix() -> void:
	for departure: float in [480.0, 540.0, 540.125, 590.310576140835, 659.375, 719.123456789123, 720.0]:
		var uninterrupted: LifeSim = setup("teen", departure)
		uninterrupted.character.traits = ["Outgoing", "Active", "Neat"]
		for need: String in LifeSim.NEED_NAMES: uninterrupted.needs[need] = 63.0
		check(uninterrupted.queue_action("school_day", "lot_exit"), "School can be directed at valid departure %s." % departure)
		uninterrupted.begin_current_action()
		advance(uninterrupted, 37.375)
		var resumed: LifeSim = setup("teen")
		var restored: Dictionary = resumed.restore_state(snapshot(uninterrupted))
		check(restored.ok, "Partial care restores at departure %s: %s" % [departure, restored])
		if not restored.ok: continue
		for remaining: float in [21.625, 900.0 - departure - 59.0]:
			advance(uninterrupted, remaining)
			advance(resumed, remaining)
			for need: String in LifeSim.NEED_NAMES:
				check(is_equal_approx(float(uninterrupted.needs[need]), float(resumed.needs[need])), "Restored proportional %s care equals uninterrupted care at %s, clock %s." % [need, departure, uninterrupted.minutes])
		var same_learning: bool = snapshot(uninterrupted).education == snapshot(resumed).education
		for skill: String in uninterrupted.skills:
			same_learning = same_learning and int(uninterrupted.skills[skill].level) == int(resumed.skills[skill].level) and is_equal_approx(float(uninterrupted.skills[skill].xp), float(resumed.skills[skill].xp))
		check(same_learning, "Late attendance and learning match after resume at %s." % departure)
		check(resumed.away_state.completed and resumed.education.attended == 1, "One completed attendance after partial-care resume at %s." % departure)
		check(setup("teen").restore_state(snapshot(resumed)).ok, "Fractional late return is JSON-loadable at %s." % departure)

func _late_grade_archives() -> void:
	for departure: float in [540.125, 590.123456, 659.375, 719.999]:
		var sim: LifeSim = setup("teen", departure)
		sim.queue_action("school_day", "lot_exit")
		sim.begin_current_action()
		advance(sim, 899.0 - departure)
		sim.set_aging("normal", true)
		sim.lifecycle.progress = 1.0 - 1.0 / (LifeLifecycle.duration("teen", "normal") * 1440.0)
		advance(sim, 1.0)
		check(sim.character.age_stage == "young_adult" and sim.away_state.completed and sim.education.records.size() == 1, "Fractional late arrival still closes school before exact-bell birthday at %s." % departure)
		var record: Dictionary = sim.education.records[0]
		check(record.attended == 1 and is_equal_approx(float(record.late_minutes), departure - 540.0), "Birthday archive retains exact fractional late time at %s." % departure)
		var saved: Dictionary = snapshot(sim)
		var loaded: Dictionary = setup("young_adult").restore_state(saved)
		check(loaded.ok, "Fractional late grade survives JSON birthday archive at %s: %s; archived score %s recomputed %s." % [departure, loaded, saved.education.records[0].score, LifeEducation.score(saved.education.records[0])])

func _invalid_late_records() -> void:
	var sim: LifeSim = setup("teen", 660.0)
	sim.queue_action("school_day", "lot_exit")
	sim.begin_current_action()
	advance(sim, 240.0)
	var returning: Dictionary = snapshot(sim)
	check(setup("teen").restore_state(returning).ok, "Late returning state is valid before malformed-record adversaries.")
	for corrupt: Variant in [-0.001, true, "120", INF, NAN, 180.001]:
		var bad: Dictionary = returning.duplicate(true)
		bad.education.late_minutes = corrupt
		var receiver: LifeSim = setup("teen")
		var previous: Dictionary = receiver.get_state()
		check(not receiver.restore_state(bad).ok and receiver.get_state() == previous, "Invalid current late-time type/range rejects atomically: %s." % corrupt)
	var erased: Dictionary = returning.duplicate(true)
	erased.education.late_minutes = 0.0
	check(not setup("teen").restore_state(erased).ok, "Completed away metadata cannot contradict the late time earned on that same return.")
	sim.celebrate_birthday()
	var archived: Dictionary = snapshot(sim)
	for corrupt: Variant in [-0.001, true, "120", INF, NAN, 180.001]:
		var bad: Dictionary = archived.duplicate(true)
		bad.education.records[0].late_minutes = corrupt
		var receiver: LifeSim = setup("young_adult")
		var previous: Dictionary = receiver.get_state()
		check(not receiver.restore_state(bad).ok and receiver.get_state() == previous, "Invalid archived late-time type/range rejects atomically: %s." % corrupt)
	var punctual: LifeSim = setup("teen", 480.0)
	punctual.queue_action("school_day", "lot_exit")
	punctual.begin_current_action()
	advance(punctual, 420.0)
	punctual.complete_away_return()
	punctual.celebrate_birthday()
	var legacy: Dictionary = snapshot(punctual)
	legacy.education.erase("late_minutes")
	legacy.education.records[0].erase("late_minutes")
	check(setup("young_adult").restore_state(legacy).ok, "Existing punctual saves and archived grades remain compatible without late_minutes.")

func _expiring_queued_departure() -> void:
	var sim: LifeSim = setup("child", 700.0)
	sim.autonomy = false
	check(sim.queue_action("read", "shelf"), "Player can begin an ordinary activity before departure cutoff.")
	sim.begin_current_action()
	check(sim.queue_action("school_day", "lot_exit"), "School may be queued while its departure window is still open.")
	check(setup().restore_state(snapshot(sim)).ok, "A still-valid queued departure saves while waiting behind a player action.")
	advance(sim, 21.0)
	check(not sim.is_away() and sim.education.attended == 0 and sim.action_queue.size() == 1 and sim.get_current_action().id == "read", "Queued departure expires after cutoff while preserving the player's ongoing action.")
	check(setup().restore_state(snapshot(sim)).ok, "Expired departure leaves a coherent reloadable player action.")
	sim.begin_current_action()
	check(not sim.is_away(), "A delayed arrival callback cannot revive an expired departure.")

func _dual_critical_paid_cooking() -> void:
	var sim: LifeSim = setup("adult", 0.0)
	sim.needs.hunger = 0.0
	sim.needs.energy = 0.0
	sim.needs.bladder = 0.0
	check(sim.queue_action("cook", "fridge"), "An adult may cook with multiple critical needs.")
	sim.get_current_action().autonomous = true
	sim.begin_current_action()
	var paid_funds: int = sim.funds
	advance(sim, 20.0)
	check(sim.get_current_action().id == "cook" and sim.get_current_action().elapsed == 20.0 and sim.funds == paid_funds, "Critical competing needs do not cancel and repurchase an unfinished paid cooking.")
	var resumed: LifeSim = setup("adult", 0.0)
	check(resumed.restore_state(snapshot(sim)).ok, "Partly cooked recovery with critical competing needs saves.")
	resumed.begin_current_action()
	advance(sim, 25.0)
	advance(resumed, 25.0)
	check(sim.action_queue.is_empty() and resumed.action_queue.is_empty() and sim.funds == paid_funds and resumed.funds == paid_funds, "Paid cooking resumes and finishes without a second purchase or interruption.")
	check(sim.needs.hunger == 0.0 and resumed.needs.hunger == 0.0, "Paid cooking preserves empty hunger through save/resume; eating is still required.")
	sim._choose_autonomous_action()
	check(sim.get_current_action().id == "snack", "After committed cooking, a snack addresses the still-most-urgent hunger need.")

func _school_preparation_boundaries() -> void:
	for need: String in ["hygiene", "fun", "social"]:
		var sim: LifeSim = setup("child", 590.0)
		sim.needs[need] = 30.0
		check(sim._autonomy_projection_need("school_day").is_empty(), "Moderate %s deficit must not block otherwise physically safe school departure." % need)
		check(str(sim._autonomous_choice().get("id", "")) == "school_day", "Comfortable physical needs still choose school with %s at 30." % need)
	for need: String in ["hunger", "energy", "bladder"]:
		var sim: LifeSim = setup("child", 590.0)
		sim.needs[need] = 5.0
		check(str(sim._autonomous_choice().get("id", "")) != "school_day", "Critical current %s takes priority over school." % need)
		check(sim.queue_action("school_day", "lot_exit"), "A valid direct school instruction can approach before its urgent-need arrival recheck.")
		sim.begin_current_action()
		check(not sim.is_away() and sim.action_queue.is_empty(), "The departure arrival recheck refuses school while %s is critically low." % need)

func _enrollment_cutoff() -> void:
	# The class-start cutoff is the same 14:00 (840) the attendance window allows,
	# so a birthday at the last legal class start still reaches that day's lesson
	# and only a later one defers to the next school day.
	for time: float in [720.0,720.001,780.0,840.0,840.001,900.0]:
		var pupil: LifeSim = setup("child",time)
		pupil.celebrate_birthday()
		check(pupil.education.first_class_day==(1 if time<=840.0 else 2), "New term begins on an attendable campus day at %s." % time)
		check(setup("teen").restore_state(snapshot(pupil)).ok, "Noon enrollment rollover remains saveable at %s." % time)
