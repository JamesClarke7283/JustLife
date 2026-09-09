extends SceneTree
## Critic-owned component adversaries. Uses actual simulation ticks; arrival is
## an explicit controller callback. This is not a renderer or navigation test.
const Sim = preload("res://scripts/life_sim.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var owned: Array[LifeSim] = []

func _initialize() -> void:
	if not ProjectSettings.globalize_path("res://").begins_with("/tmp/justlife-education-review-"):
		push_error("Refusing to test outside the isolated education snapshot.");quit(2);return
	call_deferred("run")

func check(value: bool, detail: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", detail)
	if not value:failures.append(detail);push_error(detail)

func setup(stage: String = "teen", clock_minutes: float = 480.0) -> LifeSim:
	var sim: LifeSim = Sim.new()
	owned.append(sim)
	sim.new_household({"name":"Boundary Learner","age_stage":stage,"traits":[]})
	sim.autonomy = false
	sim.household_bills_enabled = false
	sim.set_aging("normal", false)
	sim.minutes = clock_minutes
	sim.register_targets(targets())
	return sim

func targets() -> Array:
	return [{"id":"desk","kind":"desk","position":Vector3.ZERO},{"id":"desk2","kind":"computer","position":Vector3(1,0,0)},{"id":"shelf","kind":"bookshelf","position":Vector3.ONE},{"id":"fridge","kind":"fridge","position":Vector3(2,0,0)}]

func advance_minutes(sim: LifeSim, amount: float) -> void:
	while amount > .000001:
		var step: float = minf(amount,minf(300.0,60.0*LifeSim.GAME_MINUTES_PER_SECOND))
		sim.tick(step / LifeSim.GAME_MINUTES_PER_SECOND)
		amount -= step

func json_state(sim: LifeSim) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sim._json_safe(sim.get_state())))

func restore_result(sim: LifeSim) -> Dictionary:
	var copy: LifeSim = setup()
	var result: Dictionary = copy.restore_state(json_state(sim))
	return {"result":result,"sim":copy}

func run() -> void:
	_auto_birthdays()
	_birthday_completion_callbacks()
	_birthday_race()
	_birthday_signal_atomicity()
	_calendar_boundaries()
	_mutable_targets()
	_resume_deadline()
	_absences_and_grades()
	_invalid_restore_atomicity()
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations}
	var file := FileAccess.open("res://adversarial_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	for sim: LifeSim in owned:sim.free()
	print("EDUCATION_ADVERSARIAL checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _auto_birthdays() -> void:
	for stage: String in ["child","teen"]:
		var sim: LifeSim = setup(stage)
		check(sim.queue_action("school","desk") and sim.queue_action("homework","shelf") and sim.queue_action("read","shelf"),stage + ": school, homework and unrelated reading queue.")
		sim.begin_current_action()
		advance_minutes(sim,30)
		sim.set_aging("normal",true)
		sim.lifecycle.progress = 1.0 - .5 / (LifeLifecycle.duration(stage,"normal") * 1440.0)
		advance_minutes(sim,1)
		check(sim.character.age_stage == LifeLifecycle.next_stage(stage),stage + ": actual tick crosses automatic birthday boundary.")
		check(sim.action_queue.size() == 1 and sim.action_queue[0].id == "read",stage + ": birthday removes active and queued schoolwork while keeping unrelated reading.")
		check(sim.education.records.size() == 1 and sim.education.records[0].attended == 0 and sim.skills.logic.xp == 0.0,stage + ": unfinished class grants no attendance or learning on birthday.")
		var restored: Dictionary = restore_result(sim)
		check(restored.result.ok,stage + ": state saved immediately after automatic birthday remains loadable.")
		check(restored.sim.character.age_stage == sim.character.age_stage and restored.sim.education == sim.education,stage + ": restored age and archived school term agree.")
		sim.begin_current_action();advance_minutes(sim,60)
		check(sim.action_queue.is_empty(),stage + ": unrelated reading proceeds after school cancellation.")

func _birthday_completion_callbacks() -> void:
	var sim: LifeSim = setup()
	var starts: Array[String] = []
	sim.action_started.connect(func(action: Dictionary):starts.append(str(action.id)))
	check(sim.queue_action("birthday","fridge") and sim.queue_action("school","desk") and sim.queue_action("homework","shelf") and sim.queue_action("read","shelf"),"Birthday can precede pending lessons and an unrelated action.")
	sim.begin_current_action();advance_minutes(sim,45)
	check(sim.character.age_stage == "young_adult" and sim.action_queue.size() == 1 and sim.action_queue[0].id == "read","Completed birthday removes queued school activities while retaining reading.")
	check(starts.count("read") == 1,"Birthday completion emits the next reading start exactly once.")
	observations.append({"case":"birthday_callback_order","starts":starts,"queue":sim._json_safe(sim.action_queue)})
	check(restore_result(sim).result.ok,"State after queued birthday completion remains loadable.")

func _calendar_boundaries() -> void:
	var sim: LifeSim = setup("teen",840.0)
	check(sim.queue_action("school","desk"),"A class can start at the exact 14:00 deadline.")
	sim.begin_current_action();advance_minutes(sim,180)
	check(sim.education.attended == 1 and sim.minutes == 1020.0,"A full class starting at 14:00 finishes successfully at 17:00.")
	check(restore_result(sim).result.ok,"A just-completed deadline class produces a valid save.")
	var late: LifeSim = setup("teen",840.001)
	check(not late.queue_action("school","desk"),"Even a slightly late class start is refused.")
	var duplicate: LifeSim = setup()
	duplicate.queue_action("read","shelf")
	check(duplicate.queue_action("school","desk") and not duplicate.queue_action("school","desk2"),"A queued class reservation cannot be duplicated at another desk.")
	duplicate.minutes = 1439.0
	advance_minutes(duplicate,2)
	check(duplicate.action_queue.size() == 1 and duplicate.action_queue[0].id == "read", "Midnight clears pending school reservations and keeps unrelated actions.")
	check(duplicate.education.missed == 1 and duplicate.education.attended == 0 and restore_result(duplicate).result.ok,"An uncompleted weekday class records one absence and remains loadable.")
	var homework: LifeSim = setup("teen",1380.0)
	check(homework.queue_action("homework","shelf"),"Homework starts at the exact 23:00 deadline.")
	homework.begin_current_action();advance_minutes(homework,30)
	var resume: Dictionary = restore_result(homework)
	check(resume.result.ok,"Part-completed late homework can be saved and restored.")
	# Restored paid actions re-approach their furniture before resuming. Let a
	# controller delay that arrival through midnight without forcing completion.
	advance_minutes(resume.sim,35)
	check(resume.sim.day == 2 and resume.sim.action_queue.is_empty() and resume.sim.education.homework == 0,"Midnight cancels delayed restored homework without granting the new day's assignment.")
	check(restore_result(resume.sim).result.ok,"State after delayed homework crosses midnight remains loadable.")

func _birthday_race() -> void:
	for phase: String in ["approach","active"]:
		var sim: LifeSim = setup()
		sim.queue_action("birthday","fridge")
		if phase == "active":sim.begin_current_action()
		sim.set_aging("normal",true)
		sim.lifecycle.progress = 1.0 - .5 / (LifeLifecycle.duration("teen","normal") * 1440.0)
		advance_minutes(sim,1)
		check(sim.character.age_stage == "young_adult",phase + ": natural age boundary occurs while a manual birthday is pending.")
		if phase == "approach":sim.begin_current_action()
		advance_minutes(sim,45)
		observations.append({"case":"automatic_manual_birthday_race","phase":phase,"age":sim.character.age_stage,"history":sim.lifecycle.history.duplicate(true)})
		check(sim.character.age_stage == "young_adult" and sim.lifecycle.history.size() == 1,phase + ": a birthday queued for teen-to-young-adult cannot silently advance another stage after that transition happened naturally.")
		check(restore_result(sim).result.ok,phase + ": concurrent birthday result remains loadable.")

func _mutable_targets() -> void:
	for new_kind: String in ["missing","fridge","computer"]:
		var sim: LifeSim = setup()
		check(sim.queue_action("school","desk"),new_kind + ": class queues before target change.")
		sim.begin_current_action();advance_minutes(sim,60)
		var modified: Array = targets().filter(func(item: Dictionary)->bool:return item.id != "desk")
		if new_kind != "missing":modified.append({"id":"desk","kind":new_kind,"position":Vector3(5,0,0)})
		sim.register_targets(modified)
		advance_minutes(sim,120)
		if new_kind == "computer":
			check(sim.education.attended == 1,"Replacing the target with compatible computer furniture preserves a valid class.")
		else:
			check(sim.education.attended == 0 and sim.skills.logic.xp == 0.0,new_kind + ": an active class cannot finish and award learning after its usable furniture disappears.")
		check(restore_result(sim).result.ok,new_kind + ": target-change outcome remains serializable.")

func _birthday_signal_atomicity() -> void:
	for mode: String in ["automatic", "manual"]:
		var sim: LifeSim = setup("child")
		sim.celebrate_birthday()
		check(sim.character.age_stage == "teen" and sim.lifecycle.history.size() == 1,mode + ": observer fixture contains an earlier child-to-teen birthday.")
		if mode == "manual":sim.queue_action("birthday","fridge")
		sim.queue_action("school","desk");sim.queue_action("homework","shelf");sim.queue_action("read","shelf")
		sim.begin_current_action()
		if mode == "automatic":
			sim.set_aging("normal",true)
			sim.lifecycle.progress = 1.0 - .5 / (LifeLifecycle.duration("teen","normal") * 1440.0)
		var signal_snapshots: Array = []
		var capture: Callable = func(signal_name: String):
			var snapshot: Dictionary = json_state(sim)
			var copy: LifeSim = Sim.new()
			copy.new_household({"name":"Observer restore","age_stage":"teen"})
			var result: Dictionary = copy.restore_state(snapshot)
			signal_snapshots.append({"signal":signal_name,"stage":sim.character.age_stage,"history":sim.lifecycle.history.duplicate(true),"restore":result})
			copy.free()
		sim.changed.connect(func():capture.call("changed"))
		sim.action_started.connect(func(_action: Dictionary):capture.call("action_started"))
		advance_minutes(sim,1 if mode == "automatic" else 45)
		var invalid: Array = signal_snapshots.filter(func(item: Dictionary)->bool:return not bool(item.restore.ok))
		check(sim.character.age_stage == "young_adult" and sim.lifecycle.history.size() == 2,mode + ": observer fixture completes the next age transition.")
		check(not signal_snapshots.is_empty() and invalid.is_empty(),mode + ": every changed/action_started observer sees a loadable, fully committed birthday state.")
		observations.append({"case":"birthday_signal_atomicity","mode":mode,"snapshots":signal_snapshots})

func _resume_deadline() -> void:
	var sim: LifeSim = setup("teen",840.0)
	sim.queue_action("school","desk");sim.begin_current_action();advance_minutes(sim,150)
	var resumed: Dictionary = restore_result(sim)
	check(resumed.result.ok,"A 16:30 partially completed class restores for furniture re-approach.")
	advance_minutes(resumed.sim,31)
	var round_trip: Dictionary = restore_result(resumed.sim)
	observations.append({"case":"restored_class_after_finish_deadline","restore":round_trip.result,"state":json_state(resumed.sim)})
	check(round_trip.result.ok,"A delayed restored class cannot make a later legitimate save unloadable after 17:00.")
	resumed.sim.begin_current_action()
	check(resumed.sim.action_queue.is_empty() and resumed.sim.education.attended == 0,"Late restored arrival cancels without awarding attendance.")
	check(restore_result(resumed.sim).result.ok,"Arrival cancellation recovers a valid state.")

func _absences_and_grades() -> void:
	var sim: LifeSim = setup("teen",0)
	advance_minutes(sim,7*1440.0)
	check(sim.day == 8 and sim.education.missed == 5,"A full missed week counts five weekdays and excludes both weekend days.")
	check(LifeEducation.score(sim.education) == 40.0 and LifeEducation.grade(sim.education) == "D","Five absences yield the documented grade consequences exactly once.")
	check(restore_result(sim).result.ok,"Missed-day counters remain valid after a week and JSON restart.")
	var initial: Dictionary = sim.education.duplicate(true)
	sim._advance_education();sim._advance_education()
	check(sim.education == initial,"Repeated calendar reconciliation does not duplicate absences.")
	var late_enrollment: LifeSim = setup("child",1080)
	late_enrollment.celebrate_birthday();advance_minutes(late_enrollment,360)
	observations.append({"case":"secondary_enrollment_after_school_deadline","state":late_enrollment.education.duplicate(true)})
	check(late_enrollment.education.missed == 0 and int(late_enrollment.education.get("first_class_day",0)) == 2,"A stage change after the class deadline does not punish the Lifelet for an impossible first school day.")
	check(restore_result(late_enrollment).result.ok,"A late-day stage transition and following midnight produce valid school records.")

func _invalid_restore_atomicity() -> void:
	var teen: LifeSim = setup()
	teen.queue_action("school","desk");teen.begin_current_action();advance_minutes(teen,30)
	var adult: LifeSim = setup("young_adult")
	var malformed: Dictionary = json_state(adult)
	malformed.action_queue = json_state(teen).action_queue
	var before: Dictionary = json_state(adult)
	check(not adult.restore_state(malformed).ok,"Adult school queue forgery is rejected.")
	check(json_state(adult) == before,"Rejected adult school queue leaves the existing live state untouched.")
