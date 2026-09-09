extends SceneTree
const Sim = preload("res://scripts/life_sim.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func setup(stage: String = "child") -> LifeSim:
	var sim: LifeSim = Sim.new()
	sim.new_household({"name":"School test","age_stage":stage,"traits":[]})
	sim.autonomy = false
	sim.set_aging("normal",false)
	sim.household_bills_enabled = false
	sim.register_targets([{"id":"desk","kind":"desk","position":Vector3.ZERO},{"id":"shelf","kind":"bookshelf","position":Vector3.ONE},{"id":"fridge","kind":"fridge","position":Vector3.ZERO}])
	return sim

func advance_minutes(sim: LifeSim, amount: float) -> void:
	var rate: float = LifeSim.GAME_MINUTES_PER_SECOND*float(sim.speed)
	assert(rate > 0.0)
	while amount > .0001:
		var step: float = minf(amount,minf(2400.0,60.0*rate))
		sim.tick(step/rate)
		amount -= step

func finish(sim: LifeSim, action: String, target: String = "desk") -> void:
	check(sim.queue_action(action,target),"Eligible %s must queue at suitable furniture." % action)
	sim.begin_current_action()
	check(not sim.get_current_action().is_empty() and sim.get_current_action().phase == "active","School action must become active after reaching furniture.")
	var duration: float = float(sim.get_current_action().duration)
	advance_minutes(sim,duration)
	check(sim.get_current_action().is_empty(),"School action must finish through real simulation ticks.")

func go_to_next_morning(sim: LifeSim) -> void:
	var remaining: float = 1440.0-float(sim.minutes)+480.0
	sim.set_speed(8)
	advance_minutes(sim,remaining)
	sim.set_speed(1)

func run() -> void:
	var sim: LifeSim = setup()
	check(sim.get_actions_for("desk","desk")[0].label == "Attend online classes","The menu must describe the actual desk activity accurately.")
	check(sim.get_actions_for("bookshelf","shelf").any(func(a: Dictionary)->bool: return a.id == "homework"),"Bookshelves must offer homework for children.")
	check(not sim.queue_action("school","shelf") and not sim.queue_action("homework","fridge") and not sim.queue_action("school"),"Wrong or missing school furniture must be rejected at queue time.")
	var wallet: int = sim.funds
	finish(sim,"homework","shelf")
	check(sim.education.homework == 1 and sim.skills.logic.xp == 6.0,"Finished homework must persist and award its exact learning once.")
	check(not sim.queue_action("homework","desk"),"The actual queue must reject repeated daily homework.")
	finish(sim,"school")
	check(sim.education.attended == 1 and sim.education.prepared == 1,"Finished online classes must consume the prepared assignment.")
	check(sim.skills.logic.xp == 16.0 and sim.skills.charisma.xp == 3.0 and sim.funds == wallet,"Actual class completion must award learning without wages or duplicate continuous effects.")
	check(not sim.queue_action("school","desk"),"Daily attendance cannot be repeated through the real queue.")
	var state: Dictionary = sim.get_state()
	var restored: LifeSim = setup()
	check(restored.restore_state(JSON.parse_string(JSON.stringify(sim._json_safe(state)))).ok and restored.education == sim.education,"Household school state must survive real JSON restore.")
	for i: int in range(2):
		go_to_next_morning(sim)
		check(sim.education.missed == 0,"New-day callbacks must not count an attended day as missed.")
		finish(sim,"school")
	check(sim.day == 3 and sim.education.attended == 3,"At least three actual game days must retain cumulative attendance.")
	var prior_needs: Dictionary = sim.needs.duplicate(true)
	check(sim.celebrate_birthday() and sim.character.age_stage == "teen" and sim.education.records.size() == 1,"Birthday integration must store primary completion and enroll the teen.")
	check(sim.education.records[0].outcome == "completed" and sim.education.attended == 0,"New school stages must start a new term while preserving earned results.")
	var record_count: int = sim.memories.size()
	sim._advance_education();sim._advance_education()
	check(sim.memories.size() == record_count,"Repeated schooling updates must not duplicate birthday report memories.")
	check(sim.needs == prior_needs,"Child school completion must not silently grant graduation effects.")
	var partial: LifeSim = setup("teen")
	check(partial.queue_action("school","desk"),"An online class can be queued for persistence testing.")
	check(not partial.queue_action("school","desk"),"Duplicate queued classes must fail before attendance is completed.")
	partial.begin_current_action();advance_minutes(partial,60.0)
	check(partial.get_current_action().elapsed == 60.0 and partial.skills.logic.xp == 0.0,"Partially completed lessons must not grant completion learning.")
	state = partial.get_state()
	var resumed: LifeSim = setup("teen")
	check(resumed.restore_state(JSON.parse_string(JSON.stringify(sim._json_safe(state)))).ok,"An active online class must survive JSON save and reload.")
	resumed.begin_current_action()
	check(resumed.get_current_action().started_minutes == 480.0,"Resuming a class must preserve its original start time.")
	advance_minutes(resumed,120.0)
	check(resumed.education.attended == 1 and resumed.skills.logic.xp == 6.0,"Resumed completion must award attendance and learning exactly once.")
	partial.cancel_action()
	check(partial.education.attended == 0 and partial.skills.logic.xp == 0.0,"Cancelling an unfinished class must not award attendance or learning.")
	var late: LifeSim = setup("teen")
	late.minutes = 839.0
	check(late.queue_action("school","desk"),"A class can queue before the daily deadline.")
	advance_minutes(late,6.0)
	late.begin_current_action()
	check(late.action_queue.is_empty() and late.education.attended == 0,"Arrival after the start deadline must cancel without effects.")
	var birthday: LifeSim = setup("teen")
	check(birthday.queue_action("school","desk") and birthday.queue_action("homework","shelf"),"Different school activities can share the ordinary queue.")
	birthday.begin_current_action()
	check(birthday.celebrate_birthday() and birthday.action_queue.is_empty(),"A transition out of school age must clear incompatible active and queued lessons.")
	check(birthday.education.records[0].outcome == "unfinished" and birthday.skills.logic.xp == 0.0,"A birthday cannot turn partial class progress into an earned diploma.")
	var adult: LifeSim = setup("adult")
	check(not adult.queue_action("school","desk") and not adult.queue_action("homework","shelf"),"Adults cannot invoke school actions through direct queue calls.")
	check(not adult.get_actions_for("desk","desk").any(func(a:Dictionary)->bool:return a.id == "school"),"Adult desk menus must retain their existing work activities.")
	var damaged: Dictionary = state.duplicate(true)
	damaged.action_queue[0].duration = 1.0
	check(not resumed.restore_state(damaged).ok,"Malformed saves cannot shorten a lesson duration.")
	damaged = state.duplicate(true);damaged.action_queue[0].target_kind = "fridge"
	check(not resumed.restore_state(damaged).ok,"Malformed saves cannot resume lessons at a refrigerator.")
	damaged = state.duplicate(true);damaged.action_queue[0].started_minutes = 530.0
	check(not resumed.restore_state(damaged).ok,"Saved lesson progress cannot exceed elapsed calendar time.")
	damaged = state.duplicate(true);damaged.action_queue.append(damaged.action_queue[0].duplicate(true))
	check(not resumed.restore_state(damaged).ok,"Malformed saves cannot contain duplicate daily class reservations.")
	damaged = adult.get_state();damaged.action_queue = state.action_queue.duplicate(true)
	check(not resumed.restore_state(damaged).ok,"Malformed adult saves cannot carry active child or teen lessons.")
	damaged = state.duplicate(true);damaged.education.prepared = 500
	check(not resumed.restore_state(damaged).ok,"Invalid school records must fail atomically before state restoration.")
	var changed_target: LifeSim = setup("teen")
	check(changed_target.queue_action("homework","shelf"),"Homework can initially route to a bookshelf.")
	changed_target.register_targets([{"id":"shelf","kind":"fridge","position":Vector3.ONE}])
	changed_target.begin_current_action()
	check(changed_target.action_queue.is_empty() and changed_target.education.homework == 0,"Arrival must reject furniture that changed to an unsuitable kind.")
	var completion_gate: LifeSim = setup("teen")
	completion_gate.queue_action("school","desk");completion_gate.begin_current_action()
	completion_gate.education = LifeEducation.complete(completion_gate.education,"teen",1,660,"school").state
	advance_minutes(completion_gate,180.0)
	check(completion_gate.education.attended == 1 and completion_gate.skills.logic.xp == 0.0,"Completion must recheck attendance and reject a duplicate without granting effects.")
	var graduation: LifeSim = setup("teen")
	for i: int in range(3):
		finish(graduation,"school")
		if i < 2: go_to_next_morning(graduation)
	var old_fun: float = graduation.needs.fun
	check(graduation.celebrate_birthday() and graduation.education.records[0].outcome == "graduated","Completed classes must produce an earned graduation on the actual birthday path.")
	check(graduation.needs.fun == minf(100.0,old_fun+8.0),"Graduation effects must apply once at the birthday boundary.")
	old_fun = graduation.needs.fun;graduation._advance_education();graduation._advance_education()
	check(graduation.needs.fun == old_fun,"Repeated education updates must not replay graduation benefits.")
	var legacy_sim: LifeSim = setup("teen")
	var legacy: Dictionary = legacy_sim.get_state();legacy.erase("education")
	check(restored.restore_state(legacy).ok and restored.education.attended == 0,"Older saves without schooling must migrate to an empty age-appropriate term.")
	for owned: LifeSim in [sim,restored,partial,resumed,late,birthday,adult,legacy_sim,changed_target,completion_gate,graduation]: owned.free()
	print("SCHOOL INTEGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
