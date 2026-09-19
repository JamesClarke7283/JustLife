extends "res://tests/test_career_day.gd"
## Independent review: source c5b10c5a39ce5790; career_schedule 489fac5f2f06c224.
## Production is immutable during the parallel rendered career week.

func run() -> void:
	_birthdays_and_promotions()
	_career_changes()
	_office_remote_reward()
	_queue_and_urgent_edges()
	_invalid_schedule()
	_invalid_away()
	check(observer_count > 40 and observer_errors.is_empty(), "All observed career boundary callbacks expose loadable state: " + str(observer_errors))
	for sim: LifeSim in owned: sim.free()
	print("CAREER_POLICY_ADVERSARIAL %d checks, %d failures; %d callback snapshots" % [checks, failures.size(), observer_count])
	quit(0 if failures.is_empty() else 1)

func worker(stage: String = "adult", clock: float = 600.0, date: int = 1) -> LifeSim:
	var sim: LifeSim = setup(stage, clock, date)
	sim.career.schedule = LifeCareerSchedule.fresh(date)
	return sim

func _birthdays_and_promotions() -> void:
	for stage: String in ["young_adult", "adult"]:
		for at_bell: bool in [false, true]:
			var sim: LifeSim = worker(stage, 659.375)
			observe(sim)
			sim.queue_action("career_day", "lot_exit")
			sim.begin_current_action()
			advance(sim, (1019.0 if at_bell else 800.0) - sim.minutes)
			var before: int = sim.funds
			if at_bell:
				sim.set_aging("normal", true)
				sim.lifecycle.progress = 1.0 - 1.0 / (LifeLifecycle.duration(stage, "normal") * 1440.0)
				advance(sim, 1.0)
			else:
				check(sim.celebrate_birthday(), "Early career birthday advances " + stage)
			check(sim.character.age_stage == LifeLifecycle.next_stage(stage) and sim.away_state.phase == "returning", "Birthday produces a real return in the next eligible adult stage.")
			check(bool(sim.away_state.completed) == at_bell, "Only the exact work bell earns attendance at a birthday.")
			check((sim.funds > before) == at_bell and int(sim.career.schedule.attended) == (1 if at_bell else 0), "Birthday reward matches actual completion, without an early salary.")
			var resumed: LifeSim = worker()
			check(resumed.restore_state(snapshot(sim)).ok and resumed.complete_away_return(), "Birthday return loads and physically completes.")
			var paid: int = resumed.funds
			check(not resumed.complete_away_return() and resumed.funds == paid, "Repeated birthday return cannot award another payment.")
	var promoted: LifeSim = worker("adult", 540.0)
	promoted.career.performance = 99.0
	observe(promoted)
	promoted.queue_action("career_day", "lot_exit")
	promoted.begin_current_action()
	var before: int = promoted.funds
	advance(promoted, 480.0)
	var start_pay: int = LifeCareers.base_pay(LifeCareers.DEFAULT_JOB, 1)
	check(promoted.career.level == 2 and promoted.funds == before + start_pay + 200, "Off-lot completion pays the captured salary and one promotion bonus.")
	check(promoted.away_state.salary == start_pay and promoted.career.salary == LifeCareers.pay(LifeCareers.DEFAULT_JOB, 2), "Paid return keeps pre-promotion shift salary distinct from new salary.")
	check(worker().restore_state(snapshot(promoted)).ok, "A promotion during the completion callback remains loadable.")

	# At the top of the ladder there is no promotion left to spend performance on,
	# so it must not accumulate past what a save may hold. It used to: a Lifelet
	# who reached rung ten and kept working banked performance for ever, and once
	# it passed the validator's ceiling the household could no longer be saved at
	# all. Ninety days of ordinary work reproduced it (1023.8) — the save was
	# refused with "Save contains an invalid career".
	var topped: LifeSim = worker("adult", 540.0)
	topped.career.level = LifeCareers.MAX_LEVEL
	topped.career.title = LifeCareers.title_at(str(topped.career.track), LifeCareers.MAX_LEVEL)
	topped.career.performance = 99.0
	observe(topped)
	topped.queue_action("job", "desk")
	check(not topped.action_queue.is_empty(), "A top-rung Lifelet can still queue a home shift.")
	topped.begin_current_action()
	advance(topped, 361.0)
	# There is no promotion left at the top of the ladder, so nothing spends the
	# earned performance. It must stop at the promotion threshold rather than
	# climbing for ever: unbounded, it passed the validator's ceiling and the
	# household could no longer be saved at all. Ninety days of ordinary work
	# produced 1023.8 and the save was refused with "Save contains an invalid
	# career".
	check(int(topped.career.level) == LifeCareers.MAX_LEVEL, "A top-rung Lifelet stays at the top of the ladder.")
	check(float(topped.career.performance) <= 100.0,
		"Performance at the top of the ladder stops at the promotion threshold (%.1f)." % float(topped.career.performance))
	check(worker().restore_state(snapshot(topped)).ok,
		"A maxed career that kept working is still saveable.")

func _career_changes() -> void:
	var sim: LifeSim = worker()
	sim.queue_action("career_day", "lot_exit")
	check(not sim.choose_career("technology"), "A queued office shift prevents changing its career identity.")
	sim.begin_current_action()
	var old: Dictionary = sim.career.duplicate(true)
	check(not sim.choose_career("technology") and sim.career == old, "Being away prevents changing salary or track.")
	sim.request_return_home()
	check(not sim.choose_career("technology"), "Returning workers retain their original track until actual home arrival.")
	sim.complete_away_return()
	# The office asks for Logic 3, which is the point of a career being harder to
	# move into; the skill is earned here so the move itself is what is proven.
	sim.skills.logic.level = 3
	check(sim.choose_career("technology") and sim.career.track == "technology", "Changing career is valid once the worker arrives home.")
	sim.skills.gardening.level = 1
	check(sim.choose_career("gardener") and sim.career.track == "gardener" and int(sim.career.salary) == LifeCareers.pay("gardener", 1), "The gardening ladder is selectable with its own salary.")
	check(str(sim.career.title) == LifeCareers.title_at("gardener", 1) and sim.career.level == 1, "The gardening ladder starts at its first rank.")
	check(worker().restore_state(snapshot(sim)).ok, "An early return followed by a career change is loadable.")
	for adulthood: bool in [false, true]:
		var late: LifeSim = worker("teen" if adulthood else "adult", 780.0)
		late.skills.logic.level = 3
		observe(late)
		check(late.celebrate_birthday() if adulthood else late.choose_career("technology"), "Afternoon adulthood or career start succeeds.")
		check(late.career.schedule.first_day == 2 and not late.queue_action("career_day", "lot_exit") and not late.queue_action("job", "desk"), "Afternoon new workers cannot begin office or remote duties before their first day.")
		late.autonomy = false
		advance(late, 1440.0 - late.minutes)
		check(late.career.schedule.missed == 0 and late.career.schedule.last_day == 2, "Afternoon enrollment does not incur an impossible first-day absence.")
		check(worker().restore_state(snapshot(late)).ok, "First working day after afternoon enrollment is loadable.")

func _office_remote_reward() -> void:
	var start_pay: int = LifeCareers.base_pay(LifeCareers.DEFAULT_JOB, 1)
	var remote: LifeSim = worker("adult", 540.0)
	remote.autonomy = false
	observe(remote)
	check(remote.queue_action("job", "desk"), "An explicit remote shift remains available.")
	remote.begin_current_action()
	check(not remote.queue_action("career_day", "lot_exit"), "Office departure cannot overlap active remote work.")
	var before: int = remote.funds
	advance(remote, float(remote.get_current_action().duration))
	check(remote.career.schedule.attended == 1 and remote.funds == before + start_pay, "Remote completion updates the shared once-per-day payment marker.")
	remote.minutes = 700.0
	check(not remote.queue_action("career_day", "lot_exit") and not remote.queue_action("job", "desk"), "Same-day office and remote repeats are both refused.")
	var office: LifeSim = worker("adult", 540.0)
	office.autonomy = false
	observe(office)
	office.queue_action("career_day", "lot_exit")
	office.begin_current_action()
	check(office.queue_action("job", "desk"), "A later explicit remote instruction can wait behind an away day.")
	before = office.funds
	advance(office, 480.0)
	office.complete_away_return()
	office.begin_current_action()
	check(office.action_queue.is_empty() and office.funds == before + start_pay and office.career.schedule.attended == 1, "Queued remote instruction rechecks earned office pay on arrival and cannot duplicate it.")
	office.skills.logic.level = 3
	check(office.choose_career("technology") and not office.queue_action("job", "desk"), "A same-day career change cannot reset the shared paid marker.")

func _queue_and_urgent_edges() -> void:
	var sim: LifeSim = worker()
	sim._choose_autonomous_action()
	check(sim.get_current_action().id == "career_day", "Safe adults automatically approach an ordinary workplace.")
	check(sim.queue_action("read", "shelf") and sim.get_current_action().id == "read" and sim.action_queue.size() == 1, "Explicit leisure replaces an unpaid autonomous office approach.")
	var delayed: LifeSim = worker("adult", 710.0)
	delayed.autonomy = false
	delayed.queue_action("read", "shelf")
	delayed.begin_current_action()
	delayed.queue_action("career_day", "lot_exit")
	advance(delayed, 11.0)
	check(delayed.action_queue.size() == 1 and delayed.get_current_action().id == "read" and not delayed.is_away(), "A queued office approach expires after noon without canceling current player work.")
	for need: String in ["hunger", "energy", "bladder"]:
		var urgent: LifeSim = worker()
		urgent.queue_action("career_day", "lot_exit")
		urgent.needs[need] = 1.0
		urgent.begin_current_action()
		check(not urgent.is_away() and urgent.action_queue.is_empty(), "Actual office departure refuses newly critical " + need)
	for need: String in ["fun", "hygiene", "social"]:
		var moderate: LifeSim = worker()
		moderate.needs[need] = 30.0
		check(str(moderate._autonomous_choice().get("id", "")) == "career_day", "Moderate " + need + " does not skip a physically safe workday.")

func _invalid_schedule() -> void:
	var base: Dictionary = snapshot(worker())
	for key: String in ["version", "first_day", "last_day", "attended", "missed", "last_attendance_day", "late_minutes"]:
		for bad_value: Variant in [true, "1", -1.0, INF]:
			var bad: Dictionary = base.duplicate(true)
			bad.career.schedule[key] = bad_value
			var receiver: LifeSim = worker()
			var stable: Dictionary = receiver.get_state()
			check(not receiver.restore_state(bad).ok and receiver.get_state() == stable, "Malformed schedule rejects atomically: %s=%s" % [key, bad_value])
	for key: String in ["attended", "missed"]:
		var oversized: Dictionary = base.duplicate(true)
		oversized.career.schedule[key] = 1e30
		if key == "attended":
			oversized.career.schedule.last_attendance_day = 1
			oversized.career.worked_day = 1
		var receiver: LifeSim = worker()
		var stable: Dictionary = receiver.get_state()
		check(not bool(receiver.restore_state(oversized).get("ok", false)) and receiver.get_state() == stable, "Finite but overflowing career counter rejects atomically: " + key)
	var today: Dictionary = base.duplicate(true)
	today.career.schedule.missed = 1
	check(not worker().restore_state(today).ok, "An unelapsed first day cannot already count as a missed shift.")
	var weekend: LifeSim = worker("adult", 600.0, 7)
	weekend.career.schedule = LifeCareerSchedule.fresh(7, 1)
	var bad: Dictionary = snapshot(weekend)
	bad.career.schedule.missed = 6
	check(not worker().restore_state(bad).ok, "Six missed shifts cannot fit the five weekdays before a first-week Sunday.")

func _invalid_away() -> void:
	var sim: LifeSim = worker("adult", 650.123456789)
	sim.queue_action("career_day", "lot_exit")
	sim.begin_current_action()
	advance(sim, 31.625)
	var base: Dictionary = snapshot(sim)
	check(worker().restore_state(base).ok, "Arbitrary fractional away clock is valid before corruption.")
	var legacy: Dictionary = base.duplicate(true)
	legacy.character.erase("life_stage")
	var compatible: LifeSim = worker()
	check(compatible.restore_state(legacy).ok and compatible.character.life_stage == "adult" and compatible.is_away(), "Explicit adult age still normalizes a legacy profile without life_stage while away.")
	var child: Dictionary = snapshot(worker("child"))
	child.character.erase("life_stage")
	var child_receiver: LifeSim = worker()
	var child_before: Dictionary = child_receiver.get_state()
	var child_result: Dictionary = child_receiver.restore_state(child)
	check((child_receiver.character.age_stage == "child" and child_receiver.character.life_stage == "minor") if bool(child_result.get("ok", false)) else child_receiver.get_state() == child_before, "A child profile without legacy eligibility must restore as minor or reject atomically, never become adult.")
	for mutation: String in ["version_bool", "salary_fraction", "position_bool", "orphan", "other_activity", "false_paid", "wrong_duration", "wrong_elapsed", "future_end", "future_enrollment", "legacy_paid_day", "departure_dictionary", "departure_array", "worked_dictionary", "worked_array", "day_dictionary", "day_array"]:
		var bad: Dictionary = base.duplicate(true)
		match mutation:
			"version_bool": bad.away_state.version = true
			"salary_fraction": bad.away_state.salary = 180.5
			"position_bool": bad.away_state.exit_position = [true, 0, 0]
			"orphan": bad.action_queue.clear()
			"other_activity": bad.away_state.activity = "school"
			"false_paid": bad.action_queue[0].paid = false
			"wrong_duration": bad.action_queue[0].duration += .1
			"wrong_elapsed": bad.action_queue[0].elapsed += 1.0
			"future_end": bad.away_state.ended_at = 1020.0
			"future_enrollment": bad.career.schedule.first_day = 2
			"legacy_paid_day":
				bad.character.erase("life_stage")
				bad.career.worked_day = 1
			"departure_dictionary": bad.away_state.departure_day = {}
			"departure_array": bad.away_state.departure_day = []
			"worked_dictionary": bad.career.worked_day = {}
			"worked_array": bad.career.worked_day = []
			"day_dictionary": bad.day = {}
			"day_array": bad.day = []
		var receiver: LifeSim = worker()
		var stable: Dictionary = receiver.get_state()
		var caller: Dictionary = bad.duplicate(true)
		var result: Dictionary = receiver.restore_state(bad)
		check(not bool(result.get("ok", false)) and receiver.get_state() == stable and bad == caller, "Malformed away career rejects atomically without changing caller data: " + mutation)
