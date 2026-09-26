extends SceneTree
## School movement endpoints are explicit controller callbacks. These components
## prove away clocks/state/rewards; the rendered suite proves real navigation.

var checks: int = 0
var failures: Array[String] = []
var owned: Array[LifeSim] = []
var observer_errors: Array[String] = []
var observer_count: int = 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures.append(detail)
		push_error(detail)

func targets() -> Array:
	return [{"id":"lot_exit","kind":"lot_exit","position":Vector3(0,.16,8.5)},
		{"id":"desk","kind":"desk","position":Vector3.ZERO},
		{"id":"shelf","kind":"bookshelf","position":Vector3(2,.16,0)},
		{"id":"bed","kind":"bed","position":Vector3(4,.16,0)},
		{"id":"fridge","kind":"fridge","position":Vector3(6,.16,0)},
		{"id":"toilet","kind":"toilet","position":Vector3(8,.16,0)}]

func setup(stage: String = "child", clock: float = 480.0, calendar_day: int = 1) -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	owned.append(sim)
	sim.new_household({"name":"School Lifelet","age_stage":stage,"traits":[]})
	sim.set_aging("normal",false)
	sim.household_bills_enabled = false
	sim.wants.clear()
	sim.day = calendar_day
	sim.career.schedule=LifeCareerSchedule.fresh(calendar_day)
	sim.minutes = clock
	sim.education = LifeEducation.fresh(stage,calendar_day)
	sim.register_targets(targets())
	for need: String in LifeSim.NEED_NAMES:sim.needs[need] = 100.0
	return sim

func advance(sim: LifeSim, amount: float) -> void:
	while amount > .000001:
		var step: float = minf(60.0,amount)
		sim.tick(step/LifeSim.GAME_MINUTES_PER_SECOND)
		amount -= step

func snapshot(sim: LifeSim) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sim._json_safe(sim.get_state())))

func observe(sim: LifeSim) -> void:
	sim.away_changed.connect(func(_state: Dictionary):audit_callback(sim,"away"))
	sim.changed.connect(func():audit_callback(sim,"changed"))
	sim.notice.connect(func(_message: String):audit_callback(sim,"notice"))
	sim.action_started.connect(func(_action: Dictionary):audit_callback(sim,"started"))
	sim.action_finished.connect(func(_action: Dictionary):audit_callback(sim,"finished"))
	sim.age_changed.connect(func(_before: String,_after: String):audit_callback(sim,"age"))

func audit_callback(sim: LifeSim, event: String) -> void:
	observer_count += 1
	var validator: LifeSim = LifeSim.new()
	var result: Dictionary = validator.restore_state(snapshot(sim))
	if not result.ok: observer_errors.append(event+": "+str(result.error))
	validator.free()

func run() -> void:
	_departure_boundaries()
	_full_day()
	_save_resume()
	_early_return()
	_explicit_and_urgent()
	_optional_online()
	_late_route_and_birthday()
	_recovery_and_bell_regressions()
	_early_return_is_a_player_choice()
	_empty_away_queue_can_come_home()
	_school_lunch_prevents_starvation()
	_corrupt_saves()
	check(observer_count > 40 and observer_errors.is_empty(),"Every observed school callback exposes a complete loadable state: "+str(observer_errors))
	for sim: LifeSim in owned:sim.free()
	print("SCHOOL_DAY %d checks, %d failures; %d callback snapshots" % [checks,failures.size(),observer_count])
	quit(0 if failures.is_empty() else 1)

func _departure_boundaries() -> void:
	for stage: String in ["child","teen"]:
		var sim: LifeSim = setup(stage,479.999)
		check(not sim.school_departure_reason().is_empty() and not sim.queue_action("school_day","lot_exit"),stage+": departure is closed before 08:00.")
		sim.minutes = 480.0
		check(sim.school_departure_reason().is_empty() and sim._autonomy_duty_id() == "school_day",stage+": school departure becomes due at 08:00.")
		check(str(sim._autonomous_choice().get("id","")) == "school_day",stage+": school autonomy selects the neighborhood exit instead of a computer class.")
		sim.minutes = 720.0
		check(sim.school_departure_reason().is_empty(),stage+": the final 12:00 late departure minute is valid.")
		sim.minutes = 720.001
		check(not sim.school_departure_reason().is_empty() and sim._autonomy_duty_id() != "school_day",stage+": a missed departure cannot begin after 12:00.")
		for weekend: int in [6,7]:
			var rested: LifeSim = setup(stage,480.0,weekend)
			check(not rested.queue_action("school_day","lot_exit") and rested._autonomy_duty_id().is_empty(),stage+": no weekend departure.")
	for stage: String in ["young_adult","adult","elder","unknown"]:
		check(not setup(stage).queue_action("school_day","lot_exit"),stage+": adult or unknown profiles cannot attend child school.")
	var missing: LifeSim = setup()
	check(not missing.queue_action("school_day") and not missing.queue_action("school_day","desk"),"A real exit is required; furniture or an empty target cannot create a departure.")
	missing.register_targets(targets().filter(func(target:Dictionary)->bool:return str(target.id) != "lot_exit"))
	check(str(missing._autonomous_choice().get("id","")) not in ["school_day","school"],"A missing exit never silently substitutes home computer schooling.")
	var early: LifeSim = setup("teen",360.0)
	early.needs.energy = 55.0
	check(early._autonomy_duty_id().is_empty() and str(early._autonomous_choice().get("id","")) == "nap","An upcoming long school day triggers preparation at 06:00 without leaving early.")
	early._choose_autonomous_action()
	check(str(early.get_current_action().get("id","")) == "nap" and not early.is_away(),"Early preparation queues a real local nap rather than a premature departure.")

func _full_day() -> void:
	var sim: LifeSim = setup()
	observe(sim)
	var finishes: Array = []
	sim.action_finished.connect(func(action:Dictionary):finishes.append(action.duplicate(true)))
	sim._choose_autonomous_action()
	check(sim.get_current_action().id == "school_day" and sim.get_current_action().phase == "approach" and not sim.is_away(),"Choosing school begins a physical approach while the Lifelet remains at home.")
	advance(sim,10.0)
	check(not sim.is_away() and sim.education.attended == 0,"Time spent walking to the exit grants no away state or attendance.")
	sim.get_current_action().target_position = Vector3(-1.6,.16,8.5)
	sim.begin_current_action()
	check(sim.is_away() and sim.away_state.phase == "away" and sim.get_current_action().phase == "active","The actual exit-arrival callback starts the away school day.")
	var original_career: Dictionary = sim.career.duplicate(true)
	check(not sim.choose_career("technology") and sim.career == original_career and not sim.queue_action("job","desk"),"Being away does not bypass a pupil's career and adult-work eligibility.")
	check(sim.away_state.exit_position == Vector3(-1.6,.16,8.5) and sim.away_state.departure_minutes == 490.0 and sim.get_current_action().duration == 410.0,"The actual individual exit and calendar remaining duration are preserved.")
	var start: Dictionary = snapshot(sim)
	sim.begin_current_action()
	check(snapshot(sim) == start,"A repeated exit-arrival callback cannot restart an away day.")
	check(not sim.queue_action("school_day","lot_exit") and not sim.complete_away_return(),"A second departure and a premature home-arrival callback are refused.")
	sim.queue_action("read","shelf")
	var directed: Dictionary = sim.action_queue[1].duplicate(true)
	advance(sim,409.0)
	check(sim.minutes == 899.0 and sim.away_state.phase == "away" and sim.education.attended == 0,"School remains away with no attendance reward just before 15:00.")
	advance(sim,1.0)
	check(sim.away_state.phase == "returning" and sim.away_state.completed and sim.education.attended == 1 and sim.education.last_attendance_day == 1,"At 15:00 one attended day is earned before the walk home.")
	check(sim.action_queue[1] == directed and finishes.is_empty(),"Later player plans and the school completion callback wait until actual home arrival.")
	# The away day meets meals, bathroom use and washroom care, and its lunch
	# break carries the compensating Fun that offsets the base decay (the same
	# compensation career_day uses). Learning still costs energy.
	check(sim.needs.hunger > 65.0 and sim.needs.bladder > 65.0 and sim.needs.hygiene > 65.0 and sim.needs.energy < 85.0 and sim.needs.fun > 65.0,"School provides meal, bathroom and washroom care while learning still costs energy and fun.")
	var attendance: Dictionary = sim.education.duplicate(true)
	var logic: Dictionary = sim.skills.logic.duplicate(true)
	advance(sim,15.0)
	check(sim.education == attendance and sim.skills.logic == logic,"Walking home cannot farm another attendance reward or further lesson experience.")
	check(sim.request_return_home() and sim.away_state.completed and sim.education == attendance,"Cancel after the bell preserves attendance already earned.")
	check(sim.complete_away_return() and not sim.is_away() and sim.get_current_action().id == "read" and sim.get_current_action().phase == "approach","Real home arrival clears away state and only then starts the queued player route.")
	check(finishes.size() == 1 and finishes[0].id == "school_day" and finishes[0].attendance_earned,"The completed school-day action emits its final callback exactly once.")
	check(not sim.complete_away_return() and finishes.size() == 1 and sim.education == attendance,"Repeated home-arrival callbacks cannot duplicate completion.")

func _save_resume() -> void:
	var sim: LifeSim = setup("teen",500.0)
	sim.queue_action("school_day","lot_exit",Vector3(1.6,.16,8.5))
	sim.begin_current_action()
	advance(sim,90.0)
	var saved: Dictionary = snapshot(sim)
	var restored: LifeSim = setup("teen")
	check(restored.restore_state(saved).ok,"A genuinely away school day survives real JSON serialization.")
	check(restored.is_away() and restored.away_state.phase == "away" and restored.get_current_action().phase == "active" and restored.get_current_action().elapsed == 90.0,"Loading an away pupil preserves its clock instead of asking it to leave home again.")
	check(restored.away_state.exit_position == Vector3(1.6,.16,8.5),"JSON load preserves the individual return position.")
	advance(restored,310.0)
	advance(sim,310.0)
	var same_needs:bool=true
	for need:String in LifeSim.NEED_NAMES:same_needs=same_needs and is_equal_approx(float(sim.needs[need]),float(restored.needs[need]))
	check(same_needs,"Saving while away preserves exactly the remaining school care and fatigue, matching uninterrupted simulation.")
	check(restored.away_state.phase == "returning" and restored.education.attended == 1,"A resumed pupil completes only the remaining school-day time.")
	var returning: Dictionary = snapshot(restored)
	var at_gate: LifeSim = setup("teen")
	check(at_gate.restore_state(returning).ok and at_gate.away_state.completed and at_gate.education.attended == 1,"A save made on the return walk restores its awarded attendance.")
	advance(at_gate,20.0)
	check(at_gate.complete_away_return() and at_gate.education.attended == 1,"Restoring a return walk never repeats school attendance on arrival.")
	var old: Dictionary = snapshot(at_gate)
	old.erase("away_state")
	check(setup("teen").restore_state(old).ok,"Older home saves without away-state metadata remain supported.")

func _early_return() -> void:
	var sim: LifeSim = setup()
	observe(sim)
	sim.queue_action("school_day","lot_exit")
	sim.begin_current_action()
	sim.queue_action("read","shelf")
	advance(sim,60.0)
	sim.cancel_action()
	check(sim.is_away() and sim.away_state.phase == "returning" and not sim.away_state.completed,"Canceling an away activity requests a real early return instead of teleporting home.")
	check(sim.action_queue.size() == 2 and sim.action_queue[0].id == "school_day" and sim.action_queue[1].id == "read","An early return keeps the later explicit queue behind its travel lifecycle.")
	check(sim.education.attended == 0 and sim.skills.logic.xp == 0.0,"An early school exit grants no class attendance or learning reward.")
	var restored: LifeSim = setup()
	check(restored.restore_state(snapshot(sim)).ok and not restored.away_state.completed,"A canceled school's return path can be saved and resumed.")
	check(restored.complete_away_return() and restored.get_current_action().id == "read" and restored.education.attended == 0,"Early home arrival resumes the directed plan without inventing attendance.")
	restored.autonomy = false
	advance(restored,1440.0-restored.minutes+1.0)
	check(restored.education.attended == 0 and restored.education.missed == 1,"The ordinary calendar records one absence after an unfinished school day.")

func _explicit_and_urgent() -> void:
	var sim: LifeSim = setup()
	sim.queue_action("read","shelf")
	var before: Array = sim.action_queue.duplicate(true)
	sim._choose_autonomous_action()
	check(sim.action_queue == before and not sim.is_away(),"Existing player instructions prevent autonomous departure.")
	var walking: LifeSim = setup()
	walking._choose_autonomous_action()
	check(walking.queue_action("read","shelf") and walking.action_queue.size() == 1 and walking.get_current_action().id == "read","A valid player instruction takes over an autonomous departure before the exit.")
	var invalid: LifeSim = setup()
	invalid._choose_autonomous_action()
	before = invalid.action_queue.duplicate(true)
	check(not invalid.queue_action("missing_action") and invalid.action_queue == before,"An invalid instruction cannot cancel the pending school departure.")
	var exhausted: LifeSim = setup()
	exhausted._choose_autonomous_action()
	exhausted.needs.energy = 1.0
	exhausted.begin_current_action()
	check(not exhausted.is_away() and exhausted.action_queue.is_empty() and exhausted.education.attended == 0,"Critical needs acquired while walking prevent school departure at the exit.")
	var paused: LifeSim = setup()
	paused.queue_action("school_day","lot_exit")
	paused.begin_current_action()
	paused.set_speed(0)
	var frozen: Dictionary = paused.get_state()
	paused.tick(60.0)
	check(paused.get_state() == frozen,"Pause freezes the away school clock and need consequences exactly.")

func _optional_online() -> void:
	var sim: LifeSim = setup()
	sim.autonomy = false
	check(sim.queue_action("school","desk"),"The player can still choose an optional online class at a computer.")
	sim.begin_current_action()
	advance(sim,180.0)
	check(not sim.is_away() and sim.education.attended == 1,"A manually selected online class retains its established local completion flow.")
	sim.minutes = 500.0
	check(not sim.queue_action("school_day","lot_exit"),"Home and campus schooling cannot award duplicate attendance on one day.")
	var override: LifeSim = setup()
	override._choose_autonomous_action()
	check(override.queue_action("school","desk") and override.action_queue.size() == 1 and override.get_current_action().id == "school","Explicit online learning can replace a pending automatic campus departure.")

func _late_route_and_birthday() -> void:
	var late: LifeSim = setup("child",720.0)
	late.queue_action("school_day","lot_exit")
	advance(late,1.0)
	check(late.action_queue.is_empty() and not late.is_away() and late.education.attended == 0,"A walk that misses the last departure slot expires without hiding the pupil.")
	var delayed: LifeSim = setup()
	delayed.queue_action("school_day","lot_exit")
	delayed.begin_current_action()
	advance(delayed,420.0)
	advance(delayed,541.0)
	check(delayed.day == 2 and delayed.education.attended == 1 and delayed.education.missed == 0,"A blocked home route crossing midnight retains the previous day's earned attendance.")
	check(setup().restore_state(snapshot(delayed)).ok,"The cross-midnight return state remains loadable.")
	var birthday: LifeSim = setup("teen")
	observe(birthday)
	birthday.queue_action("school_day","lot_exit")
	birthday.begin_current_action()
	advance(birthday,30.0)
	check(birthday.celebrate_birthday() and birthday.character.age_stage == "young_adult","A birthday can still advance a pupil's life stage during the school day.")
	check(birthday.away_state.phase == "returning" and not birthday.away_state.completed and birthday.education.records[0].attended == 0,"A school-age transition returns the Lifelet without awarding an incompatible class.")
	check(setup("young_adult").restore_state(snapshot(birthday)).ok and birthday.complete_away_return(),"The age-changed early return survives loading and arrival.")
	var after_bell: LifeSim = setup("teen")
	after_bell.queue_action("school_day","lot_exit")
	after_bell.begin_current_action()
	advance(after_bell,420.0)
	check(after_bell.celebrate_birthday() and after_bell.away_state.completed and after_bell.education.records[0].attended == 1,"A birthday on the return walk preserves the school day already earned.")
	check(setup("young_adult").restore_state(snapshot(after_bell)).ok and after_bell.complete_away_return(),"The completed school return remains loadable after its attendance moves into an archived term.")

func _empty_away_queue_can_come_home() -> void:
	var sim: LifeSim = setup("child", 600.0)
	sim.away_state = {"version":1,"activity":"school","phase":"away","departure_day":sim.day,
		"departure_minutes":480.0,"return_day":sim.day,"return_minutes":900.0,
		"exit_id":"lot_exit","exit_position":Vector3.ZERO,"age_stage":"baby","completed":false,"ended_at":0.0}
	sim.action_queue.clear()
	check(sim.request_return_home() and str(sim.away_state.phase) == "returning" and not sim.away_state.completed,
		"An away Lifelet whose action queue is already empty can still come home.")
	check(sim.complete_away_return() and not sim.is_away(),
		"Coming home with no queued action ends the trip instead of crashing.")


func _school_lunch_prevents_starvation() -> void:
	var sim: LifeSim = setup("child", 500.0)
	sim.queue_action("school_day", "lot_exit")
	sim.get_current_action().target_position = Vector3(-1.6, .16, 8.5)
	sim.begin_current_action()
	sim.needs.hunger = 0.0
	sim.starvation_minutes = 120.0
	advance(sim, 200.0)
	check(sim.is_away() and sim.needs.hunger >= 40.0 and sim.starvation_minutes == 0.0,
		"A school day includes a meal, so an empty stomach does not keep the starvation clock running.")


func _corrupt_saves() -> void:
	var sim: LifeSim = setup()
	sim.queue_action("school_day","lot_exit")
	sim.begin_current_action()
	advance(sim,60.0)
	var valid: Dictionary = snapshot(sim)
	var restored: LifeSim = setup()
	check(restored.restore_state(valid).ok,"The unmodified away snapshot is valid before corruption adversaries.")
	var stable: Dictionary = restored.get_state()
	for mutation: String in ["wrong_type","future_version","boolean_version","wrong_activity","wrong_phase","orphan","missing_away","duplicate","future_departure","weekend","wrong_return","wrong_stage","wrong_exit","wrong_position","nonfinite_position","false_paid","wrong_elapsed","wrong_duration","future_end","early_reward","past_bell","boolean_completed"]:
		var bad: Dictionary = valid.duplicate(true)
		match mutation:
			"wrong_type":bad.away_state = []
			"future_version":bad.away_state.version = 2
			"boolean_version":bad.away_state.version = true
			"wrong_activity":bad.away_state.activity = "job"
			"wrong_phase":bad.away_state.phase = "home"
			"orphan":bad.action_queue.clear()
			"missing_away":bad.away_state.clear()
			"duplicate":bad.action_queue.append(bad.action_queue[0].duplicate(true))
			"future_departure":bad.away_state.departure_minutes = 540.001
			"weekend":bad.away_state.departure_day = 6
			"wrong_return":bad.away_state.return_minutes = 901.0
			"wrong_stage":bad.away_state.age_stage = "adult"
			"wrong_exit":bad.away_state.exit_id = "desk"
			"wrong_position":bad.away_state.exit_position = [99,0,0]
			"nonfinite_position":bad.away_state.exit_position = [INF,0,0]
			"false_paid":bad.action_queue[0].paid = false
			"wrong_elapsed":bad.action_queue[0].elapsed = 61.0
			"wrong_duration":bad.action_queue[0].duration = 419.0
			"future_end":bad.away_state.ended_at = 541.0
			"early_reward":bad.away_state.completed = true
			"past_bell":bad.minutes = 900.0
			"boolean_completed":bad.away_state.completed = 1
		var caller: Dictionary = bad.duplicate(true)
		check(not restored.restore_state(bad).ok and restored.get_state() == stable and bad == caller,"Malformed away save is rejected atomically: "+mutation)

func _recovery_and_bell_regressions() -> void:
	var sim:LifeSim=setup("adult",0)
	sim.needs.hunger=0.0;sim.needs.energy=0.0;sim.needs.bladder=0.0
	sim.queue_action("snack","fridge");sim.get_current_action().autonomous=true
	sim.begin_current_action()
	var spent:int=sim.funds
	advance(sim,15.0)
	check(sim.action_queue.is_empty() and sim.funds==spent and sim.needs.hunger>30.0,"Three simultaneous critical needs cannot cancel and repurchase a paid snack before it finishes.")
	var same:LifeSim=setup("adult",0)
	same.needs.hunger=0.0;same.needs.hygiene=0.0
	same.queue_action("snack","fridge");same.get_current_action().autonomous=true;same.begin_current_action()
	var front:Dictionary=same.get_current_action()
	for i:int in range(10):same._reconsider_active_autonomy()
	check(same.get_current_action()==front and same.funds==2496,"Replanning never cancels a paid recovery merely to choose the same action again.")
	var walking:LifeSim=setup("child",479.0)
	walking.queue_action("read","shelf");walking.get_current_action().autonomous=true
	walking.minutes=480.0;walking._reconsider_active_autonomy()
	check(walking.get_current_action().id=="school_day","A safe due school day can replace optional leisure that is still walking to its target.")
	var late:LifeSim=setup("child",660.0)
	late.queue_action("school_day","lot_exit");late.begin_current_action();advance(late,240.0)
	check(late.education.attended==1 and is_equal_approx(float(late.education.late_minutes),120.0),"Late school attendance records the actual missed morning separately from a full absence.")
	var punctual:Dictionary=late.education.duplicate(true);punctual.late_minutes=0.0
	check(LifeEducation.score(late.education)<LifeEducation.score(punctual) and late.skills.logic.xp<6.0,"Late arrival reduces school performance and actual learning.")
	check(setup().restore_state(snapshot(late)).ok,"Late attendance and the returning session remain loadable.")
	var bell:LifeSim=setup("teen")
	bell.queue_action("school_day","lot_exit");bell.begin_current_action();advance(bell,419.0)
	observe(bell)
	bell.set_aging("normal",true)
	bell.lifecycle.progress=1.0-1.0/(LifeLifecycle.duration("teen","normal")*1440.0)
	advance(bell,1.0)
	check(bell.character.age_stage=="young_adult" and bell.away_state.completed and bell.education.records[0].attended==1,"An automatic birthday exactly at the school bell closes and archives the earned attendance first.")
	check(setup("young_adult").restore_state(snapshot(bell)).ok,"The exact-bell automatic birthday exposes a valid saved return state.")
	var commute:LifeSim=setup("child",590.0)
	commute.needs.hunger=30.0;commute.needs.energy=60.0
	check(commute._autonomy_projection_need("school_day")=="hunger","Departure preparation budgets the actual commute instead of assuming school meals begin at home.")
	var rest:LifeSim=setup("child",540.0)
	rest.needs.energy=50.0
	rest.queue_action("nap","bed");rest.get_current_action().autonomous=true;rest.begin_current_action()
	advance(rest,30.0)
	check(rest.get_current_action().id=="nap" and rest.get_current_action().elapsed==30.0,"A short preparation nap finishes useful recovery instead of being abandoned as soon as the optimistic departure threshold is crossed.")
	var malformed:Dictionary=snapshot(late);malformed.education.late_minutes=-1.0
	check(not setup().restore_state(malformed).ok,"Negative late-school time is rejected.")
	malformed=snapshot(late);malformed.education.late_minutes=INF
	check(not setup().restore_state(malformed).ok,"Nonfinite late-school time is rejected.")

func _early_return_is_a_player_choice() -> void:
	var sim:LifeSim=setup("child",490.0)
	sim.queue_action("school_day","lot_exit");sim.begin_current_action()
	sim.request_return_home();sim.complete_away_return()
	check(sim._autonomy_duty_id().is_empty(),"A player-requested early return does not immediately send the pupil back to school autonomously.")
	var restored:LifeSim=setup()
	check(restored.restore_state(snapshot(sim)).ok and restored._autonomy_duty_id().is_empty(),"The player's early-return decision persists for the rest of today's departure window.")
