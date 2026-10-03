extends SceneTree
## The day a life stage began, and what hangs on it. Stage-age rules ("a teenager
## for twenty days") count calendar days from that day: from the birthday history,
## from the `stage_day` the sim writes, or from the stage progress for an older
## save. Change Age on the farewell dialog has to leave a save that loads, and a
## birthday during a hospital stay must not send the mother home.
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func make(stage: String, name: String = "Liz Vale") -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	root.add_child(sim)
	sim.new_household({"name": name, "age_stage": stage, "gender": "female"})
	return sim

## Let `days` whole days pass, an hour at a time, keeping the Lifelet fed and
## rested so nothing but the calendar moves.
func advance_days(sim: LifeSim, days: int) -> void: advance_hours(sim, days * 24)

func advance_hours(sim: LifeSim, hours: int) -> void:
	for step: int in hours:
		for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 85.0
		sim._step(60.0)

## Save a sim, send it through JSON like a file would, and load it into a new one.
func load_into_new(state: Variant) -> Dictionary:
	var fresh: LifeSim = make("adult", "Someone Else")
	var result: Dictionary = fresh.restore_state(JSON.parse_string(JSON.stringify(fresh._json_safe(state))))
	result["sim"] = fresh
	return result

func run() -> void:
	# ---- the plain numbers
	check(LifeLifecycle.NORMAL_DAYS.child == 20, "A child stage is twenty days at the normal pace")
	check(LifeLifecycle.duration("child", "normal") == 20.0 and LifeLifecycle.duration("child", "short") == 10.0 and LifeLifecycle.duration("child", "long") == 80.0, "The child's twenty days shrink and stretch with the lifespan")
	check(LifeLifecycle.scaled_days(20, "short") == 10.0 and LifeLifecycle.scaled_days(20, "normal") == 20.0 and LifeLifecycle.scaled_days(14, "long") == 56.0, "Age-tied days scale with the lifespan (short 10, long 56 for 14)")
	var wording: Dictionary = {"baby": "Kit is now a baby!", "child": "Kit is now a child!", "teen": "Kit is now a teenager!", "young_adult": "Kit is now a young adult!", "adult": "Kit is now an adult!", "elder": "Kit is now an elder!"}
	for stage: String in wording: check(LifeLifecycle.milestone_text("Kit", stage) == wording[stage], "Banner words for %s: %s" % [stage, LifeLifecycle.milestone_text("Kit", stage)])

	# ---- days_in_stage from each source
	var history_only: Dictionary = {"progress": 0.3, "lifespan": "normal", "auto_age": true, "history": [{"from": "child", "to": "teen", "day": 5}]}
	check(LifeLifecycle.days_in_stage(history_only, "teen", 25) == 20, "Days in a stage count from the last birthday that reached it (day 5 to day 25 is 20)")
	check(LifeLifecycle.days_in_stage(history_only, "teen", 5) == 0, "On the birthday itself it is day zero")
	var anchored: Dictionary = {"progress": 0.0, "lifespan": "normal", "auto_age": false, "history": [], "stage_day": 12}
	check(LifeLifecycle.days_in_stage(anchored, "elder", 40) == 28, "Without a history the recorded stage day is used, and aging being off does not matter")
	var both: Dictionary = {"progress": 0.0, "lifespan": "normal", "auto_age": true, "history": [{"from": "adult", "to": "elder", "day": 5}], "stage_day": 30}
	check(LifeLifecycle.days_in_stage(both, "elder", 33) == 3, "A stage day newer than the history (Change Age) wins")
	var old_save: Dictionary = {"progress": 0.5, "lifespan": "normal", "auto_age": true, "history": []}
	check(LifeLifecycle.days_in_stage(old_save, "elder", 99) == 14, "An older save with no history and no stage day is read from the progress (half of 28 is 14)")
	old_save["lifespan"] = "short"
	check(LifeLifecycle.days_in_stage(old_save, "elder", 99) == 7, "The progress reading follows the lifespan (half of 14 is 7)")
	var rounding: Dictionary = {"progress": 20.0 / 21.0, "lifespan": "normal", "auto_age": true, "history": []}
	check(LifeLifecycle.days_in_stage(rounding, "teen", 99) == 20, "Twenty-one twenty-firsts of a teen stage is twenty days, not nineteen")
	var other_stage: Dictionary = {"progress": 0.0, "lifespan": "normal", "auto_age": true, "history": [{"from": "teen", "to": "young_adult", "day": 9}]}
	check(LifeLifecycle.days_in_stage(other_stage, "adult", 30) == 0, "A history that ends in another stage says nothing about this one")

	# ---- a Lifelet is anchored the first time the sim runs, on the day it is then
	var born: LifeSim = make("teen")
	born.day = 40
	check(not born.lifecycle.has("stage_day"), "A sim has no stage day before it has a calendar")
	born.set_aging("normal", false)
	advance_days(born, 3)
	check(int(born.lifecycle.stage_day) == 40, "The first tick records the day the Lifelet was created at its stage (day %d)" % int(born.lifecycle.stage_day))
	check(born.day == 43 and LifeLifecycle.days_in_stage(born.lifecycle, "teen", born.day) == 3, "Calendar days keep counting with automatic birthdays off (day %d, %d days)" % [born.day, LifeLifecycle.days_in_stage(born.lifecycle, "teen", born.day)])
	check(float(born.lifecycle.progress) == 0.0, "...while the stage progress stays where it was")
	var saved_early: LifeSim = make("child")
	saved_early.day = 7
	check(int(saved_early.get_state().lifecycle.stage_day) == 7, "A save made before any tick still records the stage day")

	# ---- a birthday starts the stage today
	var kit: LifeSim = make("child", "Kit Vale")
	advance_days(kit, 4)
	check(kit.celebrate_birthday(false) and kit.last_birthday_source == "auto", "A birthday with no source is an automatic one")
	check(int(kit.lifecycle.stage_day) == kit.day and LifeLifecycle.days_in_stage(kit.lifecycle, "teen", kit.day + 20) == 20, "A birthday records the stage day (day %d), so twenty teen days end on day %d" % [kit.day, kit.day + 20])
	var kit_two: LifeSim = make("child", "Kit Vale")
	kit_two.celebrate_birthday(false, "cake")
	check(kit_two.last_birthday_source == "cake", "The paid birthday says it was a cake")

	# ---- a child grows into a teenager after twenty normal days (ten on a short life), not fourteen
	for pace: Array in [["normal", 20], ["short", 10]]:
		var growing: LifeSim = make("child", "Pip Vale")
		growing.set_aging(str(pace[0]), true)
		var grown_stages: Array[String] = []
		growing.age_changed.connect(func(_previous: String, current: String): grown_stages.append(current))
		advance_days(growing, int(pace[1]) - 1)
		advance_hours(growing, 23)
		check(str(growing.character.age_stage) == "child" and grown_stages.is_empty(), "A child is still a child an hour short of day %d on a %s life" % [int(pace[1]), str(pace[0])])
		advance_hours(growing, 1)
		check(str(growing.character.age_stage) == "teen" and grown_stages == ["teen"] and growing.last_birthday_source == "auto", "...and an automatic birthday makes them a teenager when day %d is done (%s)" % [int(pace[1]), str(grown_stages)])

	# ---- finishing the paid fridge birthday is the cake path
	var cake: LifeSim = make("child", "Kit Vale")
	var fridge_birthday: Dictionary = cake._actions["birthday"].duplicate(true)
	fridge_birthday["birthday_from_stage"] = "child"
	fridge_birthday["target_position"] = Vector3.ZERO
	cake.action_queue.push_back(fridge_birthday)
	var cake_milestones: Array = []
	cake.milestone.connect(func(kind: String, data: Dictionary): cake_milestones.append([kind, data.source]))
	cake._finish_front()
	check(str(cake.character.age_stage) == "teen" and cake.last_birthday_source == "cake" and cake_milestones == [["birthday", "cake"]], "Finishing the paid fridge birthday makes the child a teen as a cake birthday (%s)" % str(cake_milestones))

	# ---- old saves (no stage day) get one when they load
	var legacy: LifeSim = make("adult")
	advance_days(legacy, 8)
	legacy.celebrate_birthday(false)
	var birthday_day: int = legacy.day
	advance_days(legacy, 3)
	var legacy_state: Dictionary = JSON.parse_string(JSON.stringify(legacy._json_safe(legacy.get_state())))
	legacy_state.lifecycle.erase("stage_day")
	var legacy_result: Dictionary = load_into_new(legacy_state)
	check(bool(legacy_result.ok) and int(legacy_result.sim.lifecycle.stage_day) == birthday_day, "A save from before the stage day loads and takes it from the history (day %s, birthday on %d: %s)" % [str(legacy_result.sim.lifecycle.get("stage_day")), birthday_day, str(legacy_result.get("error", ""))])
	check(typeof(legacy_result.sim.lifecycle.get("stage_day")) == TYPE_INT, "The stage day comes back from JSON as a whole number")
	var elder: LifeSim = make("elder")
	elder.set_aging("normal", false)
	advance_days(elder, 20)
	elder.lifecycle.progress = 0.5
	var mid_state: Dictionary = JSON.parse_string(JSON.stringify(elder._json_safe(elder.get_state())))
	mid_state.lifecycle.erase("stage_day")
	var mid: Dictionary = load_into_new(mid_state)
	check(bool(mid.ok) and int(mid.sim.lifecycle.stage_day) == elder.day - 14, "A created elder halfway through the stage is dated by the progress: day %s of %d (%s)" % [str(mid.sim.lifecycle.get("stage_day")), elder.day, str(mid.get("error", ""))])

	# ---- hostile stage days are refused before anything is adopted
	var seasoned: LifeSim = make("adult")
	advance_days(seasoned, 29)
	var good: Dictionary = JSON.parse_string(JSON.stringify(seasoned._json_safe(seasoned.get_state())))
	check(bool(load_into_new(good).ok), "An untouched save of the same sim loads")
	for case: Array in [["a future stage day", good.day + 1], ["a negative stage day", -2], ["a fractional stage day", 3.5], ["a text stage day", "soon"], ["an enormous stage day", 5000000]]:
		var tampered: Dictionary = good.duplicate(true)
		tampered.lifecycle["stage_day"] = case[1]
		var refuse: LifeSim = make("adult")
		var before: String = JSON.stringify(refuse.get_state().lifecycle)
		var refused: Dictionary = refuse.restore_state(tampered)
		check(not bool(refused.ok) and JSON.stringify(refuse.get_state().lifecycle) == before, "%s is refused and changes nothing" % str(case[0]).capitalize())
	var stale: Dictionary = legacy_state.duplicate(true)
	stale.lifecycle["stage_day"] = birthday_day - 2
	check(not bool(load_into_new(stale).ok), "A stage day earlier than the birthday it should follow is refused")

	# ---- Change Age leaves a save that loads, from every stage to every stage
	var stages: Array = ["child", "teen", "young_adult", "adult", "elder"]
	var snapshots: Dictionary = {}
	var walker: LifeSim = make("child")
	for stage: String in stages:
		advance_days(walker, 3)
		snapshots[stage] = JSON.stringify(walker._json_safe(walker.get_state()))
		if stage != "elder": walker.celebrate_birthday(false)
	var bad: Array[String] = []
	var tried: int = 0
	for from_stage: String in stages:
		for to_stage: String in stages:
			var start: Dictionary = load_into_new(JSON.parse_string(snapshots[from_stage]))
			if not bool(start.ok):
				bad.append("%s start: %s" % [from_stage, str(start.error)])
				continue
			var aged: LifeSim = start.sim
			advance_days(aged, 2)
			aged.pending_passing_cause = "old_age"
			var changed: bool = aged.cancel_pending_passing(to_stage)
			var state_error: String = LifeLifecycle.validate(aged.character, aged.lifecycle)
			var restored: Dictionary = load_into_new(aged.get_state())
			tried += 1
			if not changed or not state_error.is_empty() or not bool(restored.ok) or str(restored.sim.character.age_stage) != to_stage:
				bad.append("%s>%s %s %s" % [from_stage, to_stage, state_error, str(restored.get("error", ""))])
	check(tried == 25 and bad.is_empty(), "Change Age from any stage to any stage keeps a loadable save (%d tried; %s)" % [tried, ", ".join(bad)])
	var grown: LifeSim = make("adult")
	advance_days(grown, 5)
	grown.celebrate_birthday(false)
	advance_days(grown, 4)
	grown.pending_passing_cause = "old_age"
	grown.cancel_pending_passing("adult")
	var back: Dictionary = load_into_new(grown.get_state())
	check(bool(back.ok), "The reported case loads: an adult who grew old, then was changed back to adult (%s)" % str(back.get("error", "")))
	check(int(grown.lifecycle.stage_day) == grown.day and LifeLifecycle.days_in_stage(grown.lifecycle, "adult", grown.day + 3) == 3, "Change Age starts the new stage today")
	var young_again: LifeSim = make("child")
	advance_days(young_again, 2)
	young_again.celebrate_birthday(false)
	advance_days(young_again, 3)
	young_again.pending_passing_cause = "hunger"
	young_again.cancel_pending_passing("child")
	check(LifeLifecycle.days_in_stage(young_again.lifecycle, "child", young_again.day + 5) == 5 and young_again.lifecycle.history.is_empty(), "Changing back to an earlier stage drops the birthdays that led past it and counts from today")
	var steady: LifeSim = make("adult")
	advance_days(steady, 2)
	steady.pending_passing_cause = "old_age"
	var steady_began: int = int(steady.lifecycle.get("stage_day"))
	advance_days(steady, 3)
	steady.pending_passing_cause = "old_age"
	check(steady.cancel_pending_passing("adult") and int(steady.lifecycle.get("stage_day")) == steady_began, "Extending life with the same age does not restart the stage: it began on day %d and still did" % steady_began)
	var milestones: Array = []
	steady.milestone.connect(func(kind: String, _data: Dictionary): milestones.append(kind))
	steady.pending_passing_cause = "old_age"
	steady.cancel_pending_passing("elder")
	check(milestones.is_empty() and steady.last_birthday_source.is_empty(), "Change Age is the player's own choice, so it sends no birthday milestone")

	# ---- a birthday during a hospital stay or a sentence does not cut it short
	for activity: String in ["hospital", "prison"]:
		var mum: LifeSim = make("young_adult", "Mum Vale")
		advance_days(mum, 1)
		mum.begin_hospital_stay(Vector3(0, 0, 9))
		if activity == "prison": mum.away_state = {"version": 1, "activity": "prison", "phase": "away", "departure_day": mum.day, "departure_minutes": mum.minutes, "return_day": mum.day + 2, "return_minutes": mum.minutes, "exit_id": "lot_exit", "exit_position": Vector3(0, 0, 9), "age_stage": "young_adult", "completed": false, "ended_at": 0.0}
		var notices: Array = []
		mum.notice.connect(func(text: String): notices.append(text))
		check(mum.celebrate_birthday(false) and str(mum.character.age_stage) == "adult", "The %s birthday happens" % activity)
		check(str(mum.away_state.phase) == "away" and str(mum.away_state.activity) == activity, "A birthday during a %s absence keeps it away (phase %s)" % [activity, str(mum.away_state.get("phase", ""))])
		check(not notices.any(func(text: String) -> bool: return text.contains("leaving school") or text.contains("coming home early")), "No 'leaving school early' notice for a %s absence" % activity)
		if activity == "hospital":
			var after: Dictionary = load_into_new(mum.get_state())
			check(bool(after.ok), "The save made after a hospital birthday loads (%s)" % str(after.get("error", "")))

	# ---- the wording of a call home follows the absence
	var worker: LifeSim = make("adult")
	for pair: Array in [["school", "leaving school early"], ["career", "leaving work early"], ["driving_lesson", "driving lesson early"], ["visit", "coming home early"]]:
		worker.away_state = {"version": 1, "activity": pair[0], "phase": "away", "departure_day": worker.day, "departure_minutes": 480.0, "return_day": worker.day, "return_minutes": 900.0, "exit_id": "lot_exit", "exit_position": Vector3.ZERO, "age_stage": "adult", "completed": false, "ended_at": 0.0}
		worker.action_queue.clear()
		var said: Array = []
		var listener: Callable = func(text: String): said.append(text)
		worker.notice.connect(listener)
		worker.request_return_home()
		worker.notice.disconnect(listener)
		check(said.any(func(text: String) -> bool: return text.contains(pair[1])), "Calling someone home from %s says '%s' (%s)" % [pair[0], pair[1], str(said)])

	print("Lifecycle anchor: %d checks, %d failures." % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
