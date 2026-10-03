extends "res://tests/test_school_day.gd"
## Retirement and the pension, one Lifelet at a time. An elder may retire after
## fourteen calendar days in the stage (counted even with aging off, scaled by the
## lifespan). One who holds a job is told and chooses; one who has never been paid
## for a shift retires on their own. A retired Lifelet is no longer asked to work,
## builds no missed shifts, and is paid 1,000 every seven days, first on the seventh
## day after retiring and never twice across a save. The record is validated when a
## save loads, older saves are dated from the stage history or progress, and
## Change Age to a younger stage gives the job back.
func targets() -> Array:
	var result: Array = super.targets()
	result.append({"id": "car", "kind": "car", "position": Vector3(9, .16, 3)})
	return result

func check(value: bool, detail: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", detail)
	if not value: failures.append(detail)

## An elder on day 1 with aging off and no autonomy, so only the calendar moves.
func elder(lifespan: String = "normal", clock: float = 600.0, calendar_day: int = 1) -> LifeSim:
	var sim: LifeSim = setup("elder", clock, calendar_day)
	sim.set_aging(lifespan, false)
	sim.autonomy = false
	return sim

## An elder who has been paid for one real shift on day 1, so they hold a job.
func worker(lifespan: String = "normal") -> LifeSim:
	var sim: LifeSim = elder(lifespan, 540.0, 1)
	sim.queue_action("career_day", "lot_exit")
	sim.begin_current_action()
	advance(sim, 481.0)
	sim._tick_away(1.0)
	sim.complete_away_return()
	sim.complete_away_return()
	return sim

## Let the calendar run to `to_day` at `at_minutes`, an hour at a time, keeping the
## Lifelet fed and rested so nothing but the calendar moves.
func run_to(sim: LifeSim, to_day: int, at_minutes: float = 0.5) -> void:
	var target: float = float(to_day) * 1440.0 + at_minutes
	while float(sim.day) * 1440.0 + sim.minutes < target - 0.0001:
		for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 100.0
		sim._step(minf(60.0, target - (float(sim.day) * 1440.0 + sim.minutes)))

## Record every milestone a sim sends.
func listen(sim: LifeSim) -> Array:
	var heard: Array = []
	sim.milestone.connect(func(kind: String, data: Dictionary): heard.append({"kind": kind, "data": data}))
	return heard

func count(heard: Array, kind: String) -> int:
	return heard.filter(func(entry: Dictionary) -> bool: return str(entry.kind) == kind).size()

func loads(state: Dictionary) -> bool: return elder().restore_state(state).ok

func run() -> void:
	_numbers()
	_eligibility_and_notice()
	_choice_and_refusals()
	_pension()
	_automatic()
	_adversarial_saves()
	_migration_and_anchor()
	_end_of_life_and_change_age()
	check(observer_errors.is_empty(), "Every callback saw a serializable, committed state: " + str(observer_errors.slice(0, 3)))
	for sim: LifeSim in owned: sim.free()
	print("RETIREMENT %d checks, %d failures; %d callback snapshots" % [checks, failures.size(), observer_count])
	quit(0 if failures.is_empty() else 1)

func _numbers() -> void:
	check(LifeRetirement.needed_days("normal") == 14 and LifeRetirement.needed_days("short") == 7 and LifeRetirement.needed_days("long") == 56, "Fourteen days as an elder at the normal pace, seven on a short life, fifty-six on a long one")
	check(LifeRetirement.PENSION_AMOUNT == 1000 and LifeRetirement.PENSION_PERIOD_DAYS == 7, "The pension is 1,000 every seven days whatever the lifespan")
	var life: Dictionary = {"progress": 0.0, "lifespan": "normal", "auto_age": false, "history": [], "stage_day": 1}
	var record: Dictionary = LifeRetirement.fresh()
	check(not LifeRetirement.eligible(record, "elder", life, 14, false) and LifeRetirement.eligible(record, "elder", life, 15, false), "Day 14 is thirteen days as an elder and day 15 is fourteen")
	check(not LifeRetirement.eligible(record, "adult", life, 99, false) and not LifeRetirement.eligible(record, "elder", life, 99, true), "Only a living elder can be eligible")
	life["lifespan"] = "short"
	check(not LifeRetirement.eligible(record, "elder", life, 7, false) and LifeRetirement.eligible(record, "elder", life, 8, false), "On a short life seven days are enough")
	life["lifespan"] = "long"
	check(not LifeRetirement.eligible(record, "elder", life, 56, false) and LifeRetirement.eligible(record, "elder", life, 57, false), "On a long life it takes fifty-six")
	life["lifespan"] = "normal"
	check(LifeRetirement.days_until_eligible(life, 1) == 14 and LifeRetirement.days_until_eligible(life, 10) == 5 and LifeRetirement.days_until_eligible(life, 40) == 0, "The countdown reads 14, 5 and 0")
	# The reasons come in a fixed order, so a player always sees the first thing in the way.
	var ready: Dictionary = {"stage": "elder", "life": life, "day": 20}
	check(LifeRetirement.retire_error(record, "elder", life, 20, true, true, true, "career_day").begins_with("A spirit"), "A spirit first")
	check(LifeRetirement.retire_error(record, "adult", life, 20, false, true, true, "career_day") == "Retirement is for elders.", "Then not an elder")
	check(LifeRetirement.retire_error(LifeRetirement.retire(record, 20), "elder", life, 21, false, false, false, "") == "Already retired.", "Then already retired")
	check(LifeRetirement.retire_error(record, "elder", life, 5, false, true, true, "career_day").contains("14 days") and LifeRetirement.retire_error(record, "elder", life, 5, false, true, true, "").contains("10 to go"), "Then too early, saying how long is left")
	check(LifeRetirement.retire_error(record, "elder", life, 20, false, true, true, "career_day") == "Serve the sentence before retiring.", "Then a sentence")
	check(LifeRetirement.retire_error(record, "elder", life, 20, false, true, false, "career_day").contains("after coming home"), "Then being away")
	check(LifeRetirement.retire_error(record, "elder", life, 20, false, false, false, "career_day").contains("current shift"), "Then a shift in progress")
	check(LifeRetirement.retire_error(record, "elder", life, 20, false, false, false, "read").is_empty(), "Otherwise nothing is in the way")
	check(LifeRetirement.amount_text(1000) == "ℒ1,000" and LifeRetirement.amount_text(2000) == "ℒ2,000" and LifeRetirement.amount_text(0) == "ℒ0", "Amounts are written with their thousands comma")

func _eligibility_and_notice() -> void:
	var sim: LifeSim = worker()
	observe(sim)
	var heard: Array = listen(sim)
	check(sim.has_job() and int(sim.career.worked_day) == 1, "A paid shift means a job to give up")
	check(sim.retirement_status().state == "waiting" and str(sim.retirement_status().text) == "Can retire in 14 days", "Day one reads like waiting: %s" % str(sim.retirement_status().text))
	check(sim.retirement_error().contains("14 days") and not sim.retirement_eligible(), "On day 1 it is too early: " + sim.retirement_error())
	run_to(sim, 2, 600.0)
	check(sim._autonomy_duty_id() == "career_day", "Until they retire an elder is still asked to work")
	run_to(sim, 14, 0.5)
	check(not sim.retirement_eligible() and count(heard, "retirement_eligible") == 0 and not bool(sim.retirement.eligible_noticed), "Thirteen days in, nothing has happened")
	run_to(sim, 15, 0.5)
	check(sim.retirement_eligible() and count(heard, "retirement_eligible") == 1 and bool(sim.retirement.eligible_noticed), "Day 15: eligible, told once")
	var note: Dictionary = heard.filter(func(entry: Dictionary) -> bool: return entry.kind == "retirement_eligible")[0].data
	check(str(note.text).contains("can now retire") and str(note.text).contains("Career details") and str(note.name) == "School Lifelet", "The notice says they can retire and where to do it: " + str(note.text))
	check(sim.retirement_status().state == "eligible" and not is_retired_now(sim) and sim.retirement_error().is_empty(), "Eligible and free to choose")
	check(loads(snapshot(sim)), "The eligible state loads from a save")
	var copy: LifeSim = elder()
	copy.restore_state(snapshot(sim))
	var copy_heard: Array = listen(copy)
	run_to(copy, 18, 600.0)
	check(count(copy_heard, "retirement_eligible") == 0 and not is_retired_now(copy), "A reload does not tell them again, and does not retire them")
	run_to(sim, 17, 0.5)
	check(count(heard, "retirement_eligible") == 1 and not is_retired_now(sim), "Across days 15 to 17 there is exactly one notice and they keep their job")
	run_to(sim, 22, 600.0)
	check(sim.queue_action("career_day", "lot_exit") and sim._autonomy_duty_id() == "career_day", "An eligible elder who has not retired still goes to work (day 22, 10:00)")
	sim.cancel_action()

func is_retired_now(sim: LifeSim) -> bool: return sim.is_retired() and bool(sim.retirement.retired)

func _choice_and_refusals() -> void:
	var sim: LifeSim = worker()
	observe(sim)
	var heard: Array = listen(sim)
	run_to(sim, 15, 600.0)
	var missed_before: int = int(sim.career.schedule.missed)
	check(missed_before > 0, "Skipped weekdays so far counted as missed shifts (%d), the baseline" % missed_before)
	# A shift in progress holds retiring back; a plan behind it is dropped.
	check(sim.queue_action("job", "desk"), "A home shift is queued")
	var held: Dictionary = sim.retire()
	check(not bool(held.ok) and str(held.error).contains("current shift") and not sim.is_retired(), "Retiring in the middle of a shift is refused: " + str(held.get("error", "")))
	sim.cancel_action()
	check(sim.queue_action("read", "shelf") and sim.queue_action("career_day", "lot_exit"), "A book, then a trip to work, are queued")
	var funds_before: int = sim.funds
	var result: Dictionary = sim.retire()
	check(bool(result.ok) and int(result.retired_day) == 15 and int(result.next_pension_day) == 22, "Retiring on day 15 puts the first pension on day 22: " + str(result))
	check(sim.is_retired() and int(sim.retirement.retired_day) == 15 and int(sim.retirement.next_pension_day) == 22 and int(sim.retirement.pension_paid) == 0 and bool(sim.retirement.eligible_noticed), "The record says so, with nothing paid yet")
	check(sim.action_queue.filter(func(action: Dictionary) -> bool: return str(action.id) == "career_day").is_empty() and sim.action_queue.size() == 1, "The planned trip to work was dropped and the book stayed")
	check(sim.funds == funds_before, "Retiring pays nothing the same day")
	check(count(heard, "retired") == 1, "One 'retired' milestone")
	var milestone: Dictionary = heard.filter(func(entry: Dictionary) -> bool: return entry.kind == "retired")[0].data
	check(str(milestone.text) == "No longer required to work · ℒ1,000 pension every 7 days" and int(milestone.next_pension_day) == 22, "...carrying the line under the banner: " + str(milestone.text))
	check(sim.moodlets.any(func(entry: Dictionary) -> bool: return str(entry.label) == "Happily retired") and sim.memories.any(func(entry: Dictionary) -> bool: return str(entry.label) == "Retired"), "A moodlet and a memory mark the day")
	check(not bool(sim.retire().ok) and str(sim.retire().error) == "Already retired.", "Retiring twice is refused")
	check(sim.retirement_status().state == "retired" and str(sim.retirement_status().text).contains("next on day 22"), "The status line reads: " + str(sim.retirement_status().text))
	sim.cancel_action()
	# No more work, in every shape it comes in.
	run_to(sim, 16, 600.0)
	check(sim._autonomy_duty_id().is_empty() and sim._autonomy_preparation_duty_id().is_empty(), "At 10:00 on a weekday nobody sends a retiree to work")
	var career_day: Dictionary = sim.get_action_availability("career_day", "lot_exit")
	check(not bool(career_day.available) and str(career_day.reason) == LifeRetirement.RETIRED_REASON and not sim.queue_action("career_day", "lot_exit"), "Going to work is refused with the reason: " + str(career_day.reason))
	var drive: Dictionary = sim.get_action_availability("drive_to_work", "car")
	check(not bool(drive.available) and str(drive.reason) == LifeRetirement.RETIRED_REASON and not sim.queue_action("drive_to_work", "car"), "Driving to work is refused too")
	var home_shift: Dictionary = sim.get_action_availability("job", "desk")
	check(not bool(home_shift.available) and str(home_shift.reason) == LifeRetirement.RETIRED_REASON and not sim.queue_action("job", "desk"), "So is a shift from home")
	var freelance: Dictionary = sim.get_action_availability("work", "desk")
	check(bool(freelance.available), "Freelance work at the desk is a hobby and stays open: " + str(freelance.reason))
	var lot_exit: Array = sim.get_actions_for("lot_exit").map(func(entry: Dictionary) -> String: return str(entry.id))
	check(not lot_exit.has("career_day") and lot_exit.has("morning_run"), "The way to work is gone from the neighbourhood exit: " + str(lot_exit))
	check(not sim.career_entry_error("barista").is_empty() and sim.career_entry_error("barista") == "Retired Lifelets live on their pension.", "Find a job is closed: " + sim.career_entry_error("barista"))
	var peer: LifeSim = worker()
	check(peer.career_entry_error("barista").is_empty() and peer.get_actions_for("lot_exit").any(func(entry: Dictionary) -> bool: return str(entry.id) == "career_day"), "An elder who has not retired keeps both")
	run_to(sim, 29, 0.5)
	check(int(sim.career.schedule.missed) == missed_before and loads(snapshot(sim)), "Two weeks of retired weekdays add no missed shift (%d) and the save loads" % int(sim.career.schedule.missed))
	# A shift under way blocks it until they are home.
	var away: LifeSim = worker()
	run_to(away, 16, 600.0)
	away.queue_action("career_day", "lot_exit")
	away.begin_current_action()
	check(away.is_away() and not bool(away.retire().ok) and str(away.retire().error).contains("after coming home"), "At work, they can retire once home: " + str(away.retire().get("error", "")))

func _pension() -> void:
	var sim: LifeSim = worker()
	observe(sim)
	var heard: Array = listen(sim)
	run_to(sim, 15, 0.5)
	check(bool(sim.retire().ok), "Retired on day 15")
	var before: int = sim.funds
	run_to(sim, 21, 1439.0)
	check(sim.funds == before and int(sim.retirement.pension_paid) == 0, "Nothing arrives before the seventh day")
	run_to(sim, 22, 0.5)
	check(sim.funds == before + 1000 and int(sim.retirement.pension_paid) == 1000 and int(sim.retirement.next_pension_day) == 29, "Day 22: exactly 1,000 and the next one set for day 29")
	check(count(heard, "pension") == 1, "One pension milestone")
	var first: Dictionary = heard.filter(func(entry: Dictionary) -> bool: return entry.kind == "pension")[0].data
	check(int(first.amount) == 1000 and str(first.text).contains("Pension day") and str(first.text).contains("ℒ1,000") and str(first.text).contains("day 29"), "...naming the amount and the next day: " + str(first.text))
	var at_pay: Dictionary = snapshot(sim)
	check(loads(at_pay), "The state right after a payment loads")
	run_to(sim, 22, 1439.0)
	check(sim.funds == before + 1000, "Nothing more is paid later on the same day")
	var restarted: LifeSim = elder()
	check(restarted.restore_state(at_pay).ok and int(restarted.retirement.pension_paid) == 1000 and int(restarted.retirement.next_pension_day) == 29, "A restart on payday keeps the record")
	var restarted_funds: int = restarted.funds
	run_to(restarted, 28, 1439.0)
	check(restarted.funds == restarted_funds and int(restarted.retirement.pension_paid) == 1000, "...and is not paid for day 22 a second time")
	run_to(sim, 25, 600.0)
	var mid: Dictionary = snapshot(sim)
	var twin: LifeSim = elder()
	check(twin.restore_state(mid).ok and twin.retirement == sim.retirement, "A save in the middle of a period restores the same record")
	run_to(sim, 29, 0.5)
	run_to(twin, 29, 0.5)
	check(sim.funds == before + 2000 and twin.funds == sim.funds and int(twin.retirement.pension_paid) == 2000, "Day 29 pays once in both: +2,000 in all")
	run_to(sim, 36, 0.5)
	run_to(twin, 36, 0.5)
	check(sim.funds == before + 3000 and twin.funds == sim.funds and int(sim.retirement.next_pension_day) == 43, "And day 36: +3,000 and the next on day 43")
	check(count(heard, "pension") == 3, "Three payments, three milestones")
	# A long absence from the calendar catches up without paying a period twice.
	var behind: LifeSim = elder()
	behind.restore_state(mid)
	behind.day = 60
	behind.career.schedule = LifeCareerSchedule.fresh(60)
	var paid_before: int = behind.funds
	behind._advance_retirement()
	check(behind.funds - paid_before == 5000 and int(behind.retirement.next_pension_day) == 64 and int(behind.retirement.pension_paid) == 6000, "A record that fell behind is paid up once (5 periods) and moves on: %d" % (behind.funds - paid_before))

func _automatic() -> void:
	var sim: LifeSim = elder()
	observe(sim)
	var heard: Array = listen(sim)
	check(not sim.has_job(), "An elder who has never been paid for a shift has no job to give up")
	run_to(sim, 14, 0.5)
	check(not sim.is_retired() and count(heard, "retired") == 0, "Not on day 14")
	run_to(sim, 15, 0.5)
	check(sim.is_retired() and int(sim.retirement.retired_day) == 15 and count(heard, "retired") == 1 and count(heard, "retirement_eligible") == 0, "On day 15 they retire by themselves, with the banner and no 'can retire' notice")
	var data: Dictionary = heard.filter(func(entry: Dictionary) -> bool: return entry.kind == "retired")[0].data
	check(str(data.name) == "School Lifelet" and str(data.text).contains("No longer required to work"), "The same words as when they choose")
	check(int(sim.retirement.next_pension_day) == 22 and loads(snapshot(sim)), "Their first pension is on day 22 and the save loads")
	var before: int = sim.funds
	run_to(sim, 22, 0.5)
	check(sim.funds == before + 1000, "It arrives")
	# On a short life they have to wait only seven days.
	var brief: LifeSim = elder("short")
	var brief_heard: Array = listen(brief)
	run_to(brief, 8, 0.5)
	check(brief.is_retired() and int(brief.retirement.retired_day) == 8 and count(brief_heard, "retired") == 1, "A short life retires on day 8")
	# An aging Lifelet reaches it through the birthday history.
	var grown: LifeSim = setup("adult", 600.0, 9)
	grown.set_aging("normal", false)
	grown.autonomy = false
	grown.celebrate_birthday(false)
	check(grown.character.age_stage == "elder" and LifeRetirement.days_as_elder(grown.lifecycle, 9) == 0 and grown.retirement == LifeRetirement.fresh(), "A birthday into elder day 9 starts the count at zero with a fresh record")
	check(not LifeRetirement.eligible(grown.retirement, "elder", grown.lifecycle, 22, false) and LifeRetirement.eligible(grown.retirement, "elder", grown.lifecycle, 23, false), "...so day 23 is the first they can retire")
	var grown_heard: Array = listen(grown)
	run_to(grown, 24, 0.5)
	check(grown.is_retired() and int(grown.retirement.retired_day) == 23 and count(grown_heard, "retired") == 1, "A jobless elder who grew into it retires on day 23")

func _adversarial_saves() -> void:
	var sim: LifeSim = worker()
	run_to(sim, 15, 0.5)
	sim.retire()
	run_to(sim, 25, 600.0)
	var base: Dictionary = snapshot(sim)
	check(loads(base) and loads(snapshot(sim)), "The retired save loads (control)")
	var control: Dictionary = base.duplicate(true)
	control.erase("retirement")
	check(loads(control), "A save with no retirement at all is an older save and loads")
	control["retirement"] = null
	check(loads(control), "...and so does a null record")
	var cases: Dictionary = {}
	var m: Dictionary
	m = base.duplicate(true); m.character.age_stage = "adult"; cases["retired but an adult"] = m
	m = base.duplicate(true); m.retirement.retired_day = 0; cases["retired on day 0"] = m
	m = base.duplicate(true); m.retirement.retired_day = 26; cases["retired in the future"] = m
	m = base.duplicate(true); m.lifecycle.stage_day = 20; m.retirement.retired_day = 12; m.retirement.next_pension_day = 19; m.retirement.pension_paid = 0; cases["retired before becoming an elder"] = m
	m = base.duplicate(true); m.retirement.next_pension_day = 30; cases["pension day off the weekly cycle"] = m
	m = base.duplicate(true); m.retirement.next_pension_day = 15; cases["next pension before the first"] = m
	m = base.duplicate(true); m.retirement.next_pension_day = 155; m.retirement.pension_paid = 19000; cases["pension day far ahead"] = m
	m = base.duplicate(true); m.retirement.pension_paid = 2000; cases["more paid than the days allow"] = m
	m = base.duplicate(true); m.retirement.pension_paid = 500; cases["a part payment"] = m
	m = base.duplicate(true); m.retirement["bonus"] = 1; cases["an unknown key"] = m
	m = base.duplicate(true); m.retirement.erase("pension_paid"); cases["a missing key"] = m
	m = base.duplicate(true); m.retirement.version = 2; cases["version 2"] = m
	m = base.duplicate(true); m.retirement.retired_day = 15.5; cases["a fractional day"] = m
	m = base.duplicate(true); m.retirement.eligible_noticed = false; cases["retired but never told"] = m
	m = base.duplicate(true); m.retirement.retired = "yes"; cases["retired as a word"] = m
	m = base.duplicate(true); m.retirement = "retired"; cases["a word for a record"] = m
	m = base.duplicate(true); m.retirement = []; cases["a list for a record"] = m
	var unretired: Dictionary = LifeRetirement.fresh()
	unretired.pension_paid = 1000
	m = base.duplicate(true); m.retirement = unretired; cases["a pension without retiring"] = m
	unretired = LifeRetirement.fresh()
	unretired.retired_day = 15
	m = base.duplicate(true); m.retirement = unretired; cases["a retirement day without retiring"] = m
	var adult: LifeSim = setup("adult", 600.0, 1)
	var adult_state: Dictionary = snapshot(adult)
	adult_state.retirement = {"version": 1, "eligible_noticed": true, "retired": false, "retired_day": 0, "next_pension_day": 0, "pension_paid": 0}
	cases["an adult told they can retire"] = adult_state
	for name: String in cases:
		var receiver: LifeSim = elder()
		var prior: Dictionary = receiver.get_state()
		var result: Dictionary = receiver.restore_state(cases[name])
		check(not bool(result.ok) and receiver.get_state() == prior, "Refused and untouched: %s (%s)" % [name, str(result.get("error", ""))])
	# Work and retirement together are refused, wherever the work is.
	var record: Dictionary = {"version": 1, "eligible_noticed": true, "retired": true, "retired_day": 1, "next_pension_day": 8, "pension_paid": 0}
	var planner: LifeSim = elder()
	var shifter: LifeSim = elder("normal", 540.0, 1)
	planner.queue_action("career_day", "lot_exit")
	var planned: Dictionary = snapshot(planner)
	var no_plans: Dictionary = snapshot(elder("normal", 540.0, 1))
	no_plans.retirement = record
	check(loads(no_plans), "A retired record on day 1 with nothing planned loads (control)")
	planned.retirement = record
	check(not loads(planned), "A retired Lifelet with a queued trip to work is refused")
	var home: LifeSim = elder("normal", 600.0, 1)
	home.queue_action("job", "desk")
	var home_state: Dictionary = snapshot(home)
	home_state.retirement = record
	check(not loads(home_state), "...and one with a queued home shift")
	shifter.queue_action("career_day", "lot_exit")
	shifter.begin_current_action()
	advance(shifter, 30.0)
	var shift_state: Dictionary = snapshot(shifter)
	check(shift_state.away_state.activity == "career" and loads(snapshot(shifter)), "A Lifelet mid-shift saves and loads (control)")
	shift_state.retirement = record
	check(not loads(shift_state), "A retired Lifelet who is away at work is refused")

func _migration_and_anchor() -> void:
	# An older save has no retirement record: the elder is dated from the birthday history.
	var aged: LifeSim = setup("adult", 600.0, 3)
	aged.set_aging("normal", false)
	aged.autonomy = false
	aged.celebrate_birthday(false)
	run_to(aged, 20, 0.5)
	var older: Dictionary = snapshot(aged)
	older.erase("retirement")
	var from_history: LifeSim = elder()
	check(from_history.restore_state(older).ok, "An older elder save with no retirement loads")
	check(LifeRetirement.days_as_elder(from_history.lifecycle, 20) == 17 and from_history.retirement == LifeRetirement.fresh() and from_history.retirement_eligible(), "Day 3 to day 20 is 17 days as an elder, so they may retire at once")
	var heard: Array = listen(from_history)
	from_history.career.worked_day = 0
	run_to(from_history, 21, 0.5)
	check(from_history.is_retired() and int(from_history.retirement.retired_day) == 21 and count(heard, "retired") == 1, "Never paid for a shift, they retire at the next midnight")
	# A Lifelet created part-way through the stage is dated from the progress.
	var halfway: LifeSim = elder("normal", 600.0, 20)
	halfway.lifecycle.progress = 0.5
	var created: Dictionary = snapshot(halfway)
	check(int(created.lifecycle.stage_day) == 6, "Created half-way through the stage on day 20, they started on day 6: %s" % str(created.lifecycle.get("stage_day")))
	created.lifecycle.erase("stage_day")
	created.erase("retirement")
	var from_progress: LifeSim = elder("normal", 600.0, 20)
	check(from_progress.restore_state(created).ok and int(from_progress.lifecycle.stage_day) == 6 and from_progress.retirement_eligible(), "With no stage day recorded the progress dates it the same way")
	# The same state, a short life: the half is seven days.
	var brisk: LifeSim = elder("short", 600.0, 20)
	brisk.lifecycle.progress = 0.5
	check(LifeRetirement.days_as_elder(brisk.lifecycle, 20) == 7 and LifeRetirement.needed_days("short") == 7 and LifeRetirement.eligible(LifeRetirement.fresh(), "elder", brisk.lifecycle, 20, false), "Half-way through a short elder stage is seven days, enough on a short life")
	# A change of lifespan after being told does not break the save.
	var told: LifeSim = worker()
	run_to(told, 15, 0.5)
	told.set_aging("long", false)
	check(bool(told.retirement.eligible_noticed) and not told.retirement_eligible() and loads(snapshot(told)), "Stretching the lifespan after the notice closes the door again, and the save still loads")

func _end_of_life_and_change_age() -> void:
	var sim: LifeSim = worker()
	run_to(sim, 15, 0.5)
	sim.retire()
	run_to(sim, 22, 0.5)
	var funds_at_death: int = sim.funds
	sim.lifecycle.progress = 1.0
	check(sim.pass_on("old_age") and sim.is_spirit(), "A retiree who reaches the end passes on")
	run_to(sim, 40, 0.5)
	check(sim.funds == funds_at_death and int(sim.retirement.pension_paid) == 1000, "A spirit is paid no further pension")
	check(loads(snapshot(sim)), "The spirit's save still loads")
	var kept: LifeSim = worker()
	run_to(kept, 15, 0.5)
	kept.retire()
	kept.lifecycle.progress = 1.0
	kept.pending_passing_cause = "old_age"
	check(kept.cancel_pending_passing("elder") and kept.is_retired(), "Extending the same stage keeps them retired")
	kept.lifecycle.progress = 1.0
	kept.pending_passing_cause = "old_age"
	check(kept.cancel_pending_passing("adult") and not kept.is_retired() and kept.retirement == LifeRetirement.fresh() and kept.character.age_stage == "adult", "Change Age to a younger stage clears retirement")
	check(loads(snapshot(kept)), "...and the save loads")
	run_to(kept, 17, 600.0)
	check(kept.get_action_availability("career_day", "lot_exit").reason != LifeRetirement.RETIRED_REASON and kept._autonomy_duty_id() == "career_day", "...so they are asked to work again")
	var again: LifeSim = worker()
	run_to(again, 15, 0.5)
	again.retire()
	again.pending_passing_cause = "old_age"
	again.lifecycle.progress = 1.0
	check(again.cancel_pending_passing("teen") and not again.is_retired() and loads(snapshot(again)), "Change Age to a teen clears it too")
	var young: LifeSim = setup("adult", 600.0, 4)
	young.set_aging("normal", false)
	young.pending_passing_cause = "old_age"
	check(young.cancel_pending_passing("elder") and young.retirement == LifeRetirement.fresh() and LifeRetirement.days_as_elder(young.lifecycle, 4) == 0, "Change Age to elder starts the elder days at that day")
