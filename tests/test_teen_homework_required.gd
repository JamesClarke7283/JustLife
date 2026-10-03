extends SceneTree
## A teenager must hand in homework on every school day they attend: a missed
## assignment is counted and costs grade points, a moodlet and a notice; the
## autonomy puts it ahead of moderate boredom; from 20:00 it goes ahead of the
## player's plans (but never ahead of leaving for school or work, a driving lesson
## or the birthday ritual); it can be put off half an hour at a time; and a pupil
## who comes home from school goes straight to a desk. Children are let off.
const DT: float = .05
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func press(label: String) -> void:
	for control: Node in app.find_children("*", "Button", true, false):
		if control.text == label and control.is_visible_in_tree() and not control.disabled:
			control.pressed.emit(); return
	check(false, "Missing usable button: " + label)
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

func attended(stage: String, day: int = 1) -> Dictionary:
	var state: Dictionary = LifeEducation.fresh(stage, day)
	var done: Dictionary = LifeEducation.complete(state, stage, day, 500.0, "school")
	return done.state if bool(done.ok) else state

func round_trip(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state))

func make(stage: String, minutes: float, targets: Array = []) -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	sim.new_household({"name": "Teo", "age_stage": stage, "traits": []})
	sim.household_bills_enabled = false; sim.set_aging("normal", false); sim.wants.clear()
	sim.day = 1; sim.minutes = minutes
	sim.education = attended(stage, 1)
	for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 85.0
	sim.register_targets(targets if not targets.is_empty() else [
		{"id": "sd", "kind": "study_desk", "position": Vector3(1, .16, 1), "study_seat": "c1"},
		{"id": "ea", "kind": "easel", "position": Vector3(4, .16, 1)},
		{"id": "tv", "kind": "tv", "position": Vector3(6, .16, 1)}])
	return sim

func minutes_of(sim: LifeSim, amount: float) -> void:
	sim.tick(amount / LifeSim.GAME_MINUTES_PER_SECOND)

func run() -> void:
	# ---- (a) the count, on attended days only
	var teen: Dictionary = LifeEducation.advance(attended("teen"), "teen", 2)
	check(bool(teen.ok) and int(teen.state.missed_homework) == 1, "A teen who attended and handed nothing in is one assignment behind")
	check(is_equal_approx(LifeEducation.score(teen.state), LifeEducation.score(attended("teen")) - 3.0), "It costs three grade points")
	check(str(teen.notices).contains(LifeEducation.MISSED_HOMEWORK_NOTICE), "The day's notices say so (%s)" % str(teen.notices))
	var child: Dictionary = LifeEducation.advance(attended("child"), "child", 2)
	check(bool(child.ok) and int(child.state.get("missed_homework", 0)) == 0, "A child doing the same loses nothing")
	var absent: Dictionary = LifeEducation.advance(LifeEducation.fresh("teen", 1), "teen", 2)
	check(int(absent.state.missed) == 1 and int(absent.state.missed_homework) == 0, "A teen who stayed away counts as absent, not as behind on homework")
	var early: Dictionary = LifeEducation.complete(LifeEducation.fresh("teen", 1), "teen", 1, 460.0, "homework")
	var early_class: Dictionary = LifeEducation.complete(early.state, "teen", 1, 500.0, "school")
	check(int(LifeEducation.advance(early_class.state, "teen", 2).state.missed_homework) == 0, "Homework done before class counts")
	var friday: Dictionary = LifeEducation.advance(attended("teen", 5), "teen", 8)
	check(bool(friday.ok) and int(friday.state.missed_homework) == 1, "A Friday miss is counted once across the weekend")
	check(int(LifeEducation.advance(attended("teen"), "teen", 1).state.get("missed_homework", 0)) == 0, "Nothing is owed before the day is over")
	var finished: Dictionary = LifeEducation.complete(attended("teen"), "teen", 1, 1000.0, "homework")
	check(int(LifeEducation.advance(finished.state, "teen", 2).state.missed_homework) == 0, "Handed in on the day: nothing missed")
	var leaving: Dictionary = LifeEducation.advance(attended("teen"), "young_adult", 2)
	check(bool(leaving.ok) and int(leaving.state.records[0].missed_homework) == 1, "A miss on the last teenage day still goes into the school record")
	check(bool(LifeEducation.summary(teen.state).homework_required) and int(LifeEducation.summary(teen.state).missed_homework) == 1, "The summary tells the HUD and the record")
	check(not bool(LifeEducation.summary(child.state).homework_required), "Homework is not required of a child")
	var actions: Array = LifeEducation.actions(attended("teen"), "teen", 1, 1000.0)
	check(str(actions[1].description).contains("Required every school day"), "The Do homework entry says it is required for a teen")

	# ---- (b) saves
	var good: Dictionary = round_trip(teen.state)
	check(LifeEducation.validate(good, "teen", 2).is_empty(), "A state with a missed assignment survives JSON")
	var legacy: Dictionary = round_trip(attended("teen"))
	legacy.erase("missed_homework")
	check(LifeEducation.validate(legacy, "teen", 1).is_empty() and int(LifeEducation.advance(legacy, "teen", 1).state.missed_homework) == 0, "An older state without the counter validates and reads as zero")
	for bad: Variant in [-1, 1.5, "1", 2]:
		var tampered: Dictionary = round_trip(teen.state)
		tampered.missed_homework = bad
		check(not LifeEducation.validate(tampered, "teen", 2).is_empty(), "A missed_homework of %s is refused" % str(bad))
	var kid: Dictionary = round_trip(attended("child"))
	kid.missed_homework = 1
	check(not LifeEducation.validate(kid, "child", 1).is_empty(), "A child cannot carry missed homework")
	var grown: Dictionary = round_trip(LifeEducation.fresh("adult", 3))
	grown.missed_homework = 1
	check(not LifeEducation.validate(grown, "adult", 3).is_empty(), "An adult cannot carry missed homework")
	var record_state: Dictionary = round_trip(leaving.state)
	check(LifeEducation.validate(record_state, "young_adult", 2).is_empty(), "A school record with a miss validates")
	record_state.records[0].score = float(record_state.records[0].score) + 3.0
	check(not LifeEducation.validate(record_state, "young_adult", 2).is_empty(), "An archived grade that leaves out the penalty is refused")
	var old_record: Dictionary = round_trip(LifeEducation.advance(attended("teen"), "young_adult", 2).state)
	old_record.records[0].erase("missed_homework")
	old_record.records[0].score = float(old_record.records[0].score) + 3.0
	check(LifeEducation.validate(old_record, "young_adult", 2).is_empty(), "An older archived record without the counter keeps its own score")

	# ---- (c) autonomy: homework before moderate boredom, for a teenager
	for fun: float in [18.0, 26.0]:
		var teen_sim: LifeSim = make("teen", 960.0)
		teen_sim.autonomy = true; teen_sim.needs.fun = fun
		minutes_of(teen_sim, 2.0)
		check(str(teen_sim.get_current_action().get("id", "")) == "homework", "A teen with fun at %d goes to homework first (%s)" % [int(fun), str(teen_sim.get_current_action().get("id", ""))])
		var kid_sim: LifeSim = make("child", 960.0)
		kid_sim.autonomy = true; kid_sim.needs.fun = fun
		minutes_of(kid_sim, 2.0)
		check(str(kid_sim.get_current_action().get("id", "")) != "homework", "A child with fun at %d keeps the play-first choice (%s)" % [int(fun), str(kid_sim.get_current_action().get("id", ""))])
	var hungry: LifeSim = make("teen", 960.0, [{"id": "sd", "kind": "study_desk", "position": Vector3(1, .16, 1), "study_seat": "c1"}, {"id": "fr", "kind": "fridge", "position": Vector3(3, .16, 1)}])
	hungry.autonomy = true; hungry.needs.hunger = 8.0
	minutes_of(hungry, 2.0)
	check(str(hungry.get_current_action().get("id", "")) != "homework", "A critical need is still seen to before homework (%s)" % str(hungry.get_current_action().get("id", "")))

	# ---- (d) the 20:00 curfew
	var plan_sim: LifeSim = make("teen", 1200.0)
	var told: Array[String] = []
	plan_sim.notice.connect(func(message: String) -> void: told.append(message))
	plan_sim.autonomy = true
	check(plan_sim.queue_action("watch", "tv", Vector3(6, .16, 1)), "The player queues a television session at 20:00")
	check(plan_sim.homework_mandatory(), "The homework is required")
	minutes_of(plan_sim, 1.0)
	check(plan_sim.action_queue.size() == 2 and str(plan_sim.action_queue[0].id) == "homework" and str(plan_sim.action_queue[1].id) == "watch", "One step puts homework in front and the television behind it (%s)" % str(plan_sim.action_queue.map(func(a: Dictionary) -> String: return str(a.id))))
	check(bool(plan_sim.action_queue[0].get("autonomous", false)) and str(plan_sim.action_queue[0].target_id) == "sd", "It is an automatic action at the study desk")
	check(told.any(func(m: String) -> bool: return m.contains("puts other plans aside")), "The player is told (%s)" % str(told))
	var before: Array = plan_sim.action_queue.duplicate(true)
	minutes_of(plan_sim, 1.0)
	check(plan_sim.action_queue.size() == 2 and plan_sim.action_queue[0].id == before[0].id, "It happens once")
	# the cases it leaves alone
	var calm: Dictionary = {}
	for label: String in ["autonomy off", "weekend", "child", "homework done", "before 20:00", "after 23:00", "snoozed"]:
		var stage: String = "child" if label == "child" else "teen"
		var other: LifeSim = make(stage, 1200.0)
		other.autonomy = label != "autonomy off"
		if label == "weekend": other.day = 6; other.education = attended("teen", 6)
		if label == "homework done": other.education = LifeEducation.complete(other.education, "teen", 1, 1000.0, "homework").state
		if label == "before 20:00": other.minutes = 1100.0
		if label == "after 23:00": other.minutes = 1390.0
		if label == "snoozed": other.defer_autonomous_responsibility("homework")
		other.queue_action("watch", "tv", Vector3(6, .16, 1))
		other._enforce_mandatory_homework()
		calm[label] = str(other.action_queue[0].id) == "watch" and other.action_queue.size() == 1
		check(bool(calm[label]), "Nothing is put ahead of the player's plan: %s" % label)
	# the fronts it must yield to
	check(plan_sim.homework_enforcement_blocked("driving_lesson") and plan_sim.homework_enforcement_blocked("sing_birthday") and plan_sim.homework_enforcement_blocked("blow_candles") and plan_sim.homework_enforcement_blocked("birthday"), "Driving lesson and the birthday ritual yield homework")
	check(plan_sim.homework_enforcement_blocked("school_day") and plan_sim.homework_enforcement_blocked("career_day") and plan_sim.homework_enforcement_blocked("drive_to_work") and plan_sim.homework_enforcement_blocked("board_school_bus") and plan_sim.homework_enforcement_blocked("job"), "Leaving for school or work yields too")
	check(not plan_sim.homework_enforcement_blocked("watch") and plan_sim.homework_enforcement_blocked("anything", {"cooperation_id": "x"}), "Ordinary plans do not yield, a shared session does")
	for yielded: String in LifeSim.HOMEWORK_YIELDS:
		var holder: LifeSim = make("teen", 1200.0)
		holder.autonomy = true
		holder.action_queue.append({"id": yielded, "phase": "approach", "duration": 60.0, "elapsed": 0.0, "autonomous": false, "target_id": "sd"})
		holder._enforce_mandatory_homework()
		check(str(holder.action_queue[0].id) == yielded and holder.action_queue.size() == 1, "A front %s is not pushed aside" % yielded)
	var sharing: LifeSim = make("teen", 1200.0)
	sharing.autonomy = true
	sharing.action_queue.append({"id": "watch", "phase": "approach", "duration": 60.0, "elapsed": 0.0, "autonomous": false, "cooperation_id": "tv_1"})
	sharing._enforce_mandatory_homework()
	check(str(sharing.action_queue[0].id) == "watch" and sharing.action_queue.size() == 1, "A front shared with someone is not pushed aside")
	var nowhere: LifeSim = make("teen", 1200.0, [{"id": "tv", "kind": "tv", "position": Vector3(6, .16, 1)}])
	var warnings: Array[String] = []
	nowhere.notice.connect(func(message: String) -> void: warnings.append(message))
	nowhere.autonomy = true
	nowhere.queue_action("watch", "tv", Vector3(6, .16, 1))
	nowhere._enforce_mandatory_homework(); nowhere._enforce_mandatory_homework()
	check(str(nowhere.action_queue[0].id) == "watch" and warnings.size() == 1 and warnings[0].contains("nowhere to do it"), "With nowhere to do it the teen's plans stay and the player is told once (%s)" % str(warnings))

	# ---- (e) the half-hour snooze
	var snooze: LifeSim = make("teen", 1000.0)
	var snoozed: Array[String] = []
	snooze.notice.connect(func(message: String) -> void: snoozed.append(message))
	snooze.defer_autonomous_responsibility("homework")
	check(is_equal_approx(float(snooze.autonomy_state.deferred.homework) - snooze._autonomy_now(), 30.0), "A teenager can put homework off for 30 minutes, not 120")
	check(snoozed.size() == 1 and snoozed[0].contains("half an hour"), "And is told the limit (%s)" % str(snoozed))
	check(snooze._autonomy_duty_id().is_empty(), "While it is put off there is no due duty")
	minutes_of(snooze, 31.0)
	check(snooze._autonomy_duty_id() == "homework", "Half an hour later it is due again")
	var child_snooze: LifeSim = make("child", 1000.0)
	child_snooze.defer_autonomous_responsibility("homework")
	check(is_equal_approx(float(child_snooze.autonomy_state.deferred.homework) - child_snooze._autonomy_now(), 120.0), "A child still gets the usual two hours")

	# ---- (f) the day it was missed: moodlet, notice, HUD and record
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Teo Vale", "age_stage": "teen", "traits": []}]
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find("willow"))
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	app.select_household_member(1)
	var live: LifeSim = app.household.member_sim(str(app.household.members[1].id))
	live.autonomy = false
	live.day = 1; live.minutes = 1000.0
	live.education = attended("teen", 1)
	live.wants.clear()
	press("School"); await frames(2)
	app.refresh_hud(); await frames(2)
	var details: String = str(app.career_labels.details.text)
	check(details.contains("Homework due by 23:00") and not details.contains("missed"), "The HUD says homework is due (%s)" % details)
	var lines: Array[String] = []
	live.notice.connect(func(message: String) -> void: lines.append(message))
	# cancelling a required homework puts it off half an hour
	var station: Dictionary = live.homework_station()
	check(not station.is_empty() and live.queue_action("homework", str(station.target_id), station.position), "Homework is queued at the home's best place")
	live.action_queue[0]["autonomous"] = true
	app.cancel_current_action(0)
	check(is_equal_approx(float(live.autonomy_state.deferred.homework) - live._autonomy_now(), 30.0), "Cancelling it from the screen puts it off 30 minutes, not two hours")
	# midnight with nothing handed in
	live.minutes = 1438.0
	live.set_speed(1)
	minutes_of(live, 4.0)
	live.set_speed(0)
	check(int(live.education.get("missed_homework", 0)) == 1, "At midnight the missed assignment is counted")
	check(lines.any(func(m: String) -> bool: return m.begins_with("Teo Vale") and m.contains("not handed in")), "A notice names the teenager (%s)" % str(lines))
	check(live.moodlets.any(func(m: Dictionary) -> bool: return str(m.label) == "Behind on homework" and str(m.emotion) == "Tense"), "A tense moodlet follows")
	app.refresh_hud(); await frames(2)
	check(str(app.career_labels.details.text).contains("1 missed"), "The HUD counts it (%s)" % str(app.career_labels.details.text))
	app.show_school_record(); await frames(2)
	check(app.find_children("*", "Label", true, false).any(func(label: Node) -> bool: return label.text.contains("1 not handed in") and label.is_visible_in_tree()), "The school record shows the count")
	app.close_overlay(); await frames(2)

	# ---- (g) getting home from school: straight to a desk
	await school_run()

	print("TEEN_HOMEWORK_REQUIRED ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	if is_instance_valid(app): app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

## Monday from 07:30 with the pupils' autonomy on only until they have left for
## school: a teenager who comes home goes to a desk anyway, a child with autonomy
## off does not.
func school_run() -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}, {"name": "Teo Vale", "age_stage": "teen", "traits": []}]
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find("willow"))
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	for member: Dictionary in app.household.members:
		member.sim.minutes = 450.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
		member.sim.autonomy = str(member.sim.character.age_stage) != "adult"
	app.household.minutes = 450.0
	var kit: LifeSim = null
	var teo: LifeSim = null
	for member: Dictionary in app.household.members:
		if str(member.sim.character.age_stage) == "child": kit = member.sim
		if str(member.sim.character.age_stage) == "teen": teo = member.sim
	var returned: Dictionary = {}
	var started: Dictionary = {}
	app.household.set_speed(8)
	for frame: int in 40000:
		app._process(DT)
		var now: float = float(app.household.minutes)
		if now >= 1190.0: break
		for pupil: LifeSim in [kit, teo]:
			var key: String = str(pupil.character.age_stage)
			if pupil.is_away(): pupil.autonomy = false
			elif not returned.has(key) and now > 700.0:
				returned[key] = now
			var action: Dictionary = pupil.get_current_action()
			if returned.has(key) and not started.has(key) and str(action.get("id", "")) == "homework": started[key] = now
	check(returned.has("teen") and returned.has("child"), "Both pupils came home (%s)" % str(returned))
	check(started.has("teen") and float(started.teen) - float(returned.teen) < 40.0, "The teenager started homework as soon as they were indoors, with autonomy off (%s)" % str([returned, started]))
	check(int(teo.education.homework) == 1, "And finished it")
	check(not started.has("child") and int(kit.education.homework) == 0, "A child with autonomy off is left to the player")
