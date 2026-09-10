extends SceneTree
## Adversarial component checks for autonomous responsibilities and social memory.
## Arrival is supplied by the controller callback; this is not a navigation test.

var checks: int = 0
var failures: Array[String] = []
var owned: Array[Node] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures.append(detail)
		push_error(detail)

func targets() -> Array:
	return [
		{"id":"lot_exit","kind":"lot_exit","position":Vector3(0,.16,8.5)},		{"id":"desk","kind":"desk","position":Vector3(0,.16,0)},
		{"id":"desk2","kind":"computer","position":Vector3(3,.16,0)},
		{"id":"shelf","kind":"bookshelf","position":Vector3(6,.16,0)},
		{"id":"fridge","kind":"fridge","position":Vector3(9,.16,0)},
		{"id":"bed","kind":"bed","position":Vector3(0,.16,3)},
		{"id":"shower","kind":"shower","position":Vector3(3,.16,3)},
		{"id":"toilet","kind":"toilet","position":Vector3(6,.16,3)},
		{"id":"sofa","kind":"sofa","position":Vector3(9,.16,3)},
		{"id":"maya","kind":"neighbor","position":Vector3(0,.16,6)},
		{"id":"leo","kind":"neighbor","position":Vector3(3,.16,6)}]

func comfortable(sim: LifeSim) -> void:
	for need: String in LifeSim.NEED_NAMES:
		sim.needs[need] = 100.0

func setup(stage: String = "adult", clock: float = 480.0, calendar_day: int = 1) -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	owned.append(sim)
	sim.new_household({"name":"Policy Lifelet","age_stage":stage,"traits":[]})
	sim.set_aging("normal",false)
	sim.household_bills_enabled = false
	sim.day = calendar_day
	sim.career.schedule=LifeCareerSchedule.fresh(calendar_day)
	sim.minutes = clock
	sim.education = LifeEducation.fresh(stage,calendar_day)
	sim.wants.clear()
	sim.register_targets(targets())
	comfortable(sim)
	return sim

func home_setup(stages: Array) -> LifeHousehold:
	var home: LifeHousehold = LifeHousehold.new()
	owned.append(home)
	var profiles: Array = []
	for index: int in range(stages.size()):
		profiles.append({"name":"Member %d" % index,"age_stage":stages[index],"traits":[]})
	home.new_household(profiles)
	var all_targets: Array = targets()
	for member: Dictionary in home.members:
		all_targets.append({"id":member.id,"kind":"neighbor","position":Vector3(0,.16,9)})
	home.register_targets(all_targets)
	for member: Dictionary in home.members:
		member.sim.set_aging("normal",false)
		member.sim.household_bills_enabled = false
		comfortable(member.sim)
	return home

func advance(sim: LifeSim, amount: float) -> void:
	while amount > .000001:
		var step: float = minf(amount,60.0)
		sim.tick(step / LifeSim.GAME_MINUTES_PER_SECOND)
		amount -= step

func complete_front(sim: LifeSim) -> void:
	if sim.action_queue.is_empty():
		check(false,"The expected action exists before its arrival callback.")
		return
	sim.begin_current_action()
	var remaining: float = float(sim.get_current_action().duration) - float(sim.get_current_action().elapsed)
	advance(sim,remaining)
	if sim.is_away() and sim.away_state.phase == "returning": sim.complete_away_return()

func json_state(sim: LifeSim) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sim._json_safe(sim.get_state())))

func current_id(sim: LifeSim) -> String:
	return str(sim.get_current_action().get("id",""))

func run() -> void:
	_calendar_boundaries()
	_daily_rewards()
	_needs_before_duties()
	_early_preparation()
	_moderate_departure_needs()
	_queue_ownership()
	_active_interruption()
	_arrival_and_resume()
	_desk_contention()
	_cohort_fairness()
	_social_choices()
	_persistence()
	for node: Node in owned:
		node.free()
	print("AUTONOMY_POLICY %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _calendar_boundaries() -> void:
	for stage: String in ["child","teen"]:
		var pupil: LifeSim = setup(stage,479.999)
		check(pupil._autonomy_duty_id() != "school_day",stage+": classes never begin before the opening time.")
		pupil.minutes = 480.0
		check(pupil._autonomy_duty_id() == "school_day",stage+": weekday class becomes due at 08:00.")
		check(str(pupil._autonomous_choice().get("id","")) == "school_day",stage+": a comfortable pupil selects its due class.")
		pupil.minutes = 720.0
		check(pupil._autonomy_duty_id() == "school_day",stage+": an uncompleted class remains selectable at the final valid start minute.")
		pupil.minutes = 720.001
		check(pupil._autonomy_duty_id() != "school_day",stage+": no new class is selected after its deadline.")
		pupil.minutes = 1320.0
		check(pupil._autonomy_duty_id() == "homework",stage+": an overdue assignment remains due at the autonomous 22:00 cutoff.")
		pupil.minutes = 1320.001
		check(pupil._autonomy_duty_id().is_empty(),stage+": expired class and assignment windows do not schedule impossible work.")
		for weekend: int in [6,7]:
			var rested: LifeSim = setup(stage,600.0,weekend)
			check(rested._autonomy_duty_id().is_empty(),stage+": weekend has no compulsory school or homework.")
			check(str(rested._autonomous_choice().get("id","")) not in ["school","school_day","homework"],stage+": weekend choice respects the education calendar.")
	var unknown: LifeSim = setup("unknown",600.0)
	check(unknown._autonomy_duty_id().is_empty(),"An unspecified age cannot autonomously enter school or an adult career.")
	for stage: String in ["young_adult","adult","elder"]:
		var worker: LifeSim = setup(stage,600.0)
		check(worker._autonomy_duty_id() == "career_day",stage+": an eligible comfortable adult has a weekday career responsibility.")
		worker.minutes = 539.999
		check(worker._autonomy_duty_id().is_empty(),stage+": autonomous work respects its weekday opening time.")
		worker.minutes = 540.0
		check(worker._autonomy_duty_id() == "career_day",stage+": the first work slot opens exactly at 09:00.")
		worker.minutes = 720.0
		check(worker._autonomy_duty_id() == "career_day",stage+": an overdue workplace departure remains due until noon.")
		worker.minutes = 720.001
		check(worker._autonomy_duty_id().is_empty(),stage+": autonomy does not depart after the workplace cutoff.")
		for weekend: int in [6,7]:
			var rested: LifeSim = setup(stage,600.0,weekend)
			check(rested._autonomy_duty_id().is_empty(),stage+": autonomous shifts leave weekends free.")

func _daily_rewards() -> void:
	var pupil: LifeSim = setup("teen")
	pupil._choose_autonomous_action()
	check(current_id(pupil) == "school_day" and bool(pupil.get_current_action().get("autonomous",false)),"An idle pupil queues its class with autonomous ownership.")
	complete_front(pupil)
	check(pupil.education.attended == 1 and pupil.education.last_attendance_day == 1,"A completed autonomous class awards one attended day.")
	check(pupil._autonomy_duty_id() != "school_day" and not pupil.queue_action("school","desk2"),"Neither autonomy nor a second desk can award another class that day.")
	comfortable(pupil)
	pupil.minutes = 1080.0
	pupil._choose_autonomous_action()
	check(current_id(pupil) == "homework","The uncompleted weekday assignment becomes a responsibility after class.")
	complete_front(pupil)
	check(pupil.education.homework == 1 and pupil.education.last_homework_day == 1,"Autonomous homework awards one assignment.")
	check(pupil._autonomy_duty_id().is_empty() and not pupil.queue_action("homework","shelf"),"Completing both school responsibilities leaves no duplicate daily duty.")
	var restored_pupil: LifeSim = setup("teen")
	check(restored_pupil.restore_state(json_state(pupil)).ok,"Completed autonomous schoolwork produces a loadable JSON save.")
	check(restored_pupil._autonomy_duty_id().is_empty(),"Loading a finished school day does not repeat its rewards.")
	var worker: LifeSim = setup("adult",600.0)
	worker._choose_autonomous_action()
	check(current_id(worker) == "career_day","A comfortable idle adult queues a career shift.")
	var before_funds: int = worker.funds
	var advertised_salary: int = roundi(float(worker.career.salary)*(1020.0-worker.minutes)/480.0)
	complete_front(worker)
	check(worker.career.worked_day == 1 and worker.funds == before_funds+advertised_salary,"The autonomous shift pays its advertised salary exactly once.")
	check(worker._autonomy_duty_id().is_empty() and not worker.queue_action("job","desk2"),"Completed daily work cannot be selected or paid again.")
	var restored_worker: LifeSim = setup()
	check(restored_worker.restore_state(json_state(worker)).ok and restored_worker._autonomy_duty_id().is_empty(),"JSON restoration preserves the paid shift marker.")

func _needs_before_duties() -> void:
	for stage: String in ["teen","adult"]:
		for need: String in ["hunger","energy","hygiene","bladder"]:
			var sim: LifeSim = setup(stage,600.0)
			sim.needs[need] = 1.0
			var choice: Dictionary = sim._autonomous_choice()
			var expected: Dictionary = {"hunger":["snack","cook"],"energy":["sleep","nap"],"hygiene":["shower"],"bladder":["toilet"]}
			check(str(choice.get("id","")) in expected[need],stage+": critical "+need+" takes priority over a long responsibility.")
		var preparing: LifeSim = setup(stage,480.0 if stage == "teen" else 600.0)
		var duty: String = "school_day" if stage == "teen" else "career_day"
		preparing.needs.energy = 35.0
		check(preparing._autonomy_projection_need(duty) == "energy",stage+": workload projection sees exhaustion before accepting the duty.")
		check(str(preparing._autonomous_choice().get("id","")) in ["sleep","nap"],stage+": projected exhaustion results in actual preparation.")
	var no_recovery: LifeSim = setup("adult",600.0)
	no_recovery.needs.energy = 1.0
	no_recovery.register_targets([{"id":"desk","kind":"desk","position":Vector3.ZERO}])
	check(str(no_recovery._autonomous_choice().get("id","")) != "career_day","Missing recovery furniture does not make an unsafe long shift acceptable.")

func _queue_ownership() -> void:
	var sim: LifeSim = setup("adult",600.0)
	check(sim.queue_action("read","shelf") and sim.queue_action("water","plant"),"The player can explicitly queue unrelated plans while a job is due.")
	var before: Array = sim.action_queue.duplicate(true)
	sim._choose_autonomous_action()
	check(sim.action_queue == before,"Calling the autonomy chooser cannot append or relabel a player's existing queue.")
	sim.begin_current_action()
	sim.needs.hunger = 1.0
	before = sim.action_queue.duplicate(true)
	sim._reconsider_active_autonomy()
	check(sim.action_queue == before,"Urgent need reconsideration preserves both active and pending player instructions.")
	var later: LifeSim = setup("adult",600.0)
	later._choose_autonomous_action()
	later.begin_current_action()
	later.queue_action("read","shelf")
	later.needs.bladder = 1.0
	before = later.action_queue.duplicate(true)
	later._reconsider_active_autonomy()
	check(later.action_queue == before,"An autonomous front action does not reorder a later explicit instruction during urgency reconsideration.")
	var disabled: LifeSim = setup("teen",600.0)
	disabled.autonomy = false
	disabled._choose_autonomous_action()
	check(disabled.action_queue.is_empty(),"The direct chooser respects the user's autonomy toggle.")

func _active_interruption() -> void:
	var sim: LifeSim = setup("adult",600.0)
	sim.queue_action("job","desk");sim.get_current_action().autonomous=true
	sim.begin_current_action();advance(sim,10.0)
	check(current_id(sim)=="job" and sim.get_current_action().phase=="active","An explicitly selected home shift still uses its real desk activity.")
	var before_funds:int=sim.funds
	sim.needs.bladder=1.0;sim._reconsider_active_autonomy()
	check(current_id(sim)!="job","An urgent bathroom need can interrupt an autonomous home shift.")
	check(sim.career.worked_day==0 and sim.funds==before_funds,"Interrupted home work awards no shift salary.")
	if sim.action_queue.is_empty():sim._choose_autonomous_action()
	check(current_id(sim)=="toilet","Interrupted home work gives way to useful recovery.")
	var leisure: LifeSim = setup("teen",479.0)
	leisure.queue_action("read","shelf")
	leisure.get_current_action()["autonomous"] = true
	leisure.begin_current_action()
	leisure.minutes = 480.0
	leisure._reconsider_active_autonomy()
	check(current_id(leisure) != "read","Optional autonomous leisure gives way when a safe class becomes due.")
	if leisure.action_queue.is_empty():leisure._choose_autonomous_action()
	check(current_id(leisure) == "school_day","Reconsidered leisure yields a real class request.")
	var paired: LifeHousehold = home_setup(["child","adult"])
	var learner: LifeSim = paired.selected()
	var helper: LifeSim = paired.member_sim("housemate_1")
	learner.relationships.housemate_1.friendship = 50.0
	helper.relationships.player.friendship = 50.0
	check(paired.queue_supported_homework("player","housemate_1","desk").ok,"A trusted explicit homework pair is available to test ownership.")
	paired.begin_action("player")
	paired.begin_action("housemate_1")
	learner.needs.hunger = 1.0
	helper.needs.bladder = 1.0
	var learner_before: Array = learner.action_queue.duplicate(true)
	var helper_before: Array = helper.action_queue.duplicate(true)
	learner._reconsider_active_autonomy()
	helper._reconsider_active_autonomy()
	check(learner.action_queue == learner_before and helper.action_queue == helper_before and paired.cooperations.size() == 1,"Autonomy leaves both halves of an explicit coordinated assignment intact.")

func _desk_contention() -> void:
	var home: LifeHousehold = home_setup(["adult","adult"])
	var first: LifeSim = home.member_sim("player")
	var second: LifeSim = home.member_sim("housemate_1")
	first.minutes = 600.0
	second.minutes = 600.0
	first.queue_action("study","desk")
	first.begin_current_action()
	var choice: Dictionary = second._autonomous_choice()
	check(str(choice.get("id","")) == "career_day" and str(choice.get("target_id","")) == "lot_exit","A due worker leaves for the workplace while the household desks stay available.")
	choice = second._autonomous_choice(["lot_exit"])
	check(str(choice.get("target_id","")) != "lot_exit","Explicit exclusions remain effective during responsibility target selection.")
	var learner: LifeSim = setup("child",600.0)
	learner.register_targets([{"id":"shelf","kind":"bookshelf","position":Vector3.ZERO}])
	check(str(learner._autonomous_choice().get("id","")) not in ["school","school_day"],"A bookshelf cannot masquerade as a classroom desk.")

func _arrival_and_resume() -> void:
	for stage: String in ["teen","adult"]:
		var waiting: LifeSim = setup(stage,480.0 if stage == "teen" else 600.0)
		waiting._choose_autonomous_action()
		var duty: String = current_id(waiting)
		check(duty in ["school_day","career_day"] and waiting.get_current_action().phase == "approach",stage+": responsibility reserves a destination before its arrival.")
		waiting.needs.energy = 1.0
		var before_funds: int = waiting.funds
		waiting.begin_current_action()
		check(current_id(waiting) != duty,stage+": arrival reassesses needs that deteriorated while waiting for furniture.")
		check(waiting.funds == before_funds and waiting.education.attended == 0 and waiting.career.worked_day == 0,stage+": rejecting an unsafe arrival grants no class or shift completion.")
	var late: LifeSim = setup("adult",710.0)
	late._choose_autonomous_action()
	late.minutes = 720.001
	late.begin_current_action()
	check(late.action_queue.is_empty() and late.career.worked_day == 0,"An autonomous shift that arrives after its last start slot is canceled without payment.")
	var explicit: LifeSim = setup("adult",1000.0)
	explicit.queue_action("job","desk")
	explicit.begin_current_action()
	check(current_id(explicit) == "job" and explicit.get_current_action().phase == "active","Autonomous arrival scheduling does not silently impose new hours on an explicit player shift.")
	var paid: LifeSim = setup("adult",710.0)
	paid._choose_autonomous_action()
	paid.begin_current_action()
	advance(paid,20.0)
	var snapshot: Dictionary = json_state(paid)
	var resumed: LifeSim = setup()
	check(resumed.restore_state(snapshot).ok,"A paid autonomous shift saves after the last start slot with partial progress.")
	resumed.begin_current_action()
	check(current_id(resumed) == "career_day" and resumed.get_current_action().phase == "active" and resumed.get_current_action().elapsed == 20.0,"A restored paid shift resumes its existing work after hours without restarting the whole duty.")
	var initial_funds: int = resumed.funds
	var salary: int = roundi(float(resumed.career.salary)*310.0/480.0)
	advance(resumed,290.0)
	check(resumed.career.worked_day == 1 and resumed.funds == initial_funds+salary,"The resumed shift awards one salary after only its remaining duration.")
	var paused: LifeSim = setup("adult",600.0)
	paused._choose_autonomous_action()
	paused.begin_current_action()
	paused.needs.bladder = 1.0
	paused.set_speed(0)
	var frozen: Dictionary = paused.get_state()
	paused.tick(30.0)
	check(paused.get_state() == frozen,"Paused simulation freezes duty progress, social memory, and urgent replanning together.")

func _cohort_fairness() -> void:
	var pupils: LifeHousehold = home_setup(["child","teen"])
	var first: LifeSim = pupils.member_sim("player")
	var second: LifeSim = pupils.member_sim("housemate_1")
	check(first._autonomy_duty_id() == "school_day" and second._autonomy_duty_id() == "school_day","Every pupil can leave for campus at 08:00 without waiting for another household member's desk slot.")
	second.minutes = 500.0
	check(second._autonomy_duty_id() == "school_day","A pupil delayed within the departure window can still go to school.")
	first.education = LifeEducation.complete(first.education,"child",1,660.0,"school").state
	first.education = LifeEducation.advance(first.education,"child",3).state
	second.education = LifeEducation.advance(second.education,"teen",3).state
	first.day = 3
	second.day = 3
	first.minutes = 480.0
	second.minutes = 480.0
	check(second._autonomy_duty_id() == "school_day" and first._autonomy_duty_id() == "school_day","Past absence never locks a pupil out behind classmates when the new departure window opens.")
	var workers: LifeHousehold = home_setup(["adult","adult"])
	first = workers.member_sim("player")
	second = workers.member_sim("housemate_1")
	first.day = 4
	second.day = 4
	first.minutes = 540.0
	second.minutes = 540.0
	first.career.worked_day = 3
	second.career.worked_day = 1
	check(second._autonomy_duty_id() == "career_day" and first._autonomy_duty_id()=="career_day","All eligible workers can depart at 09:00 without sharing a computer slot.")
	var mixed: LifeHousehold = home_setup(["adult","adult","child","adult","teen","adult"])
	var earlier: LifeSim = mixed.member_sim("housemate_2")
	var later: LifeSim = mixed.member_sim("housemate_4")
	check(earlier._autonomy_duty_id() == "school_day" and later._autonomy_duty_id() == "school_day","Pupils separated by adults in the roster can both depart at the school start.")
	for member: Dictionary in mixed.members:
		member.sim.day = 2
		member.sim.minutes = 480.0
		member.sim.education = LifeEducation.fresh(str(member.sim.character.age_stage),2)
	check(later._autonomy_duty_id() == "school_day" and earlier._autonomy_duty_id() == "school_day","The next weekday keeps both non-contiguous pupils eligible instead of selecting an array-order winner.")
	var worker: LifeSim = mixed.member_sim("player")
	worker.minutes = 600.0
	check(worker._autonomy_duty_id()=="career_day","Adult workplace departure runs alongside pupil school departure.")
	for member: Dictionary in mixed.members:
		member.sim.minutes = 650.0
	check(mixed.members.any(func(member: Dictionary) -> bool:return str(member.sim.character.life_stage) == "adult" and member.sim._autonomy_duty_id() == "career_day"),"Every adult can depart during the family morning without excluding another worker.")

func _social_choices() -> void:
	var sim: LifeSim = setup("adult",600.0,6)
	sim.needs.social = 5.0
	var first: Dictionary = sim._autonomous_choice()
	check(str(first.get("id","")) in ["friendly","joke","deep_talk"],"An autonomous social need selects a consensual ordinary conversation.")
	sim._choose_autonomous_action()
	complete_front(sim)
	var first_target: String = str(first.get("target_id",""))
	check(sim.autonomy_state.contacts.has(first_target),"A completed conversation records contact with the actual relationship.")
	comfortable(sim)
	sim.needs.social = 5.0
	var next: Dictionary = sim._autonomous_choice()
	check(str(next.get("target_id","")) != first_target,"The next social need reaches another available acquaintance instead of repeating the first roster entry.")
	var close: LifeSim = setup("adult",600.0,6)
	close.register_targets([{"id":"maya","kind":"neighbor","position":Vector3.ZERO}])
	close.relationships.maya.friendship = 80.0
	close.needs.social = 5.0
	var actions: Array[String] = []
	for index: int in range(4):
		close._choose_autonomous_action()
		actions.append(current_id(close))
		complete_front(close)
		comfortable(close)
		close.needs.social = 5.0
	check("deep_talk" in actions,"A strong relationship permits a heartfelt conversation within recurring autonomous contact.")
	var distinct: Array[String] = []
	for id: String in actions:
		if id not in distinct:distinct.append(id)
	check(distinct.size() >= 2,"Even a single available friend receives varied conversation rather than identical repeated greetings.")
	check(actions.all(func(id: String) -> bool:return id in ["friendly","joke","deep_talk"]),"Autonomous social variety does not initiate arguments, romance, commitment, or breakups.")
	var stranger: LifeSim = setup("child",600.0,6)
	stranger.register_targets([{"id":"leo","kind":"neighbor","position":Vector3.ZERO}])
	stranger.relationships.leo.friendship = 0.0
	stranger.needs.social = 5.0
	check(str(stranger._autonomous_choice().get("id","")) in ["friendly","joke"],"A child builds an unfamiliar relationship before choosing a heartfelt conversation.")
	var alias: LifeSim = setup("adult",600.0,6)
	alias.queue_action("friendly","neighbor_maya")
	complete_front(alias)
	check(alias.autonomy_state.contacts.has("maya") and not alias.autonomy_state.contacts.has("neighbor_maya"),"Completed alias-target conversations normalize memory to the relationship identity.")
	var count: int = int(alias.autonomy_state.contacts.maya.count)
	alias.queue_action("joke","maya")
	alias.begin_current_action()
	advance(alias,5.0)
	alias.cancel_action()
	check(int(alias.autonomy_state.contacts.maya.count) == count and alias.autonomy_state.contacts.maya.action == "friendly","An interrupted social activity cannot fabricate a completed contact or advance conversation variety.")
	var occupied: LifeHousehold = home_setup(["adult","adult"])
	var speaker: LifeSim = occupied.selected()
	var partner: LifeSim = occupied.member_sim("housemate_1")
	for member: Dictionary in occupied.members:
		member.sim.day = 6
		member.sim.minutes = 600.0
	partner.queue_action("sleep","bed")
	partner.begin_current_action()
	speaker.needs.social = 5.0
	speaker.relationships.housemate_1.friendship = 90.0
	check(str(speaker._autonomous_choice().get("target_id","")) != "housemate_1","An attractive friendship does not interrupt another Lifelet's sleep for optional conversation.")

func _persistence() -> void:
	var sim: LifeSim = setup("adult",540.0)
	sim.queue_action("friendly","maya")
	complete_front(sim)
	sim.defer_autonomous_responsibility("career_day",120.0)
	check(sim._autonomy_duty_id().is_empty(),"Canceling a responsibility can defer its autonomous restart.")
	var saved: Dictionary = json_state(sim)
	check(saved.has("autonomy_state") and saved.autonomy_state.version == 1,"Policy memory is an explicit versioned part of the save.")
	var restored: LifeSim = setup()
	check(restored.restore_state(saved).ok,"Contact memory and a deferred duty survive real JSON serialization.")
	check(restored.autonomy_state == saved.autonomy_state and restored._autonomy_duty_id().is_empty(),"JSON restoration preserves the contact/defer policy rather than resetting its choices.")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("autonomy_state")
	check(restored.restore_state(legacy).ok and restored.autonomy_state.contacts.is_empty() and restored.autonomy_state.deferred.is_empty(),"Older saves without policy memory restore with neutral defaults.")
	check(restored.restore_state(saved).ok,"The valid policy snapshot can be loaded again after legacy migration.")
	var before: Dictionary = restored.get_state()
	for mutation: String in ["wrong_type","future_version","boolean_version","fractional_version","bad_contacts","future_contact","near_future_contact","negative_contact","boolean_contact","missing_relationship","non_social_action","negative_count","zero_count","fractional_count","boolean_count","excessive_count","bad_deferred","unknown_duty","negative_defer","boolean_defer","excessive_defer","infinite_defer"]:
		var broken: Dictionary = saved.duplicate(true)
		match mutation:
			"wrong_type":broken.autonomy_state = []
			"future_version":broken.autonomy_state.version = 2
			"boolean_version":broken.autonomy_state.version = true
			"fractional_version":broken.autonomy_state.version = 1.5
			"bad_contacts":broken.autonomy_state.contacts = []
			"future_contact":broken.autonomy_state.contacts.maya.at = 1000000000.0
			"near_future_contact":broken.autonomy_state.contacts.maya.at = (float(saved.day)-1.0)*1440.0+float(saved.minutes)+.001
			"negative_contact":broken.autonomy_state.contacts.maya.at = -1.0
			"boolean_contact":broken.autonomy_state.contacts.maya.at = true
			"missing_relationship":broken.autonomy_state.contacts["missing_person"] = broken.autonomy_state.contacts.maya.duplicate(true)
			"non_social_action":broken.autonomy_state.contacts.maya.action = "job"
			"negative_count":broken.autonomy_state.contacts.maya.count = -1
			"zero_count":broken.autonomy_state.contacts.maya.count = 0
			"fractional_count":broken.autonomy_state.contacts.maya.count = 1.5
			"boolean_count":broken.autonomy_state.contacts.maya.count = true
			"excessive_count":broken.autonomy_state.contacts.maya.count = 1000001
			"bad_deferred":broken.autonomy_state.deferred = []
			"unknown_duty":broken.autonomy_state.deferred.birthday = 1.0
			"negative_defer":broken.autonomy_state.deferred.job = -1.0
			"boolean_defer":broken.autonomy_state.deferred.job = true
			"excessive_defer":broken.autonomy_state.deferred.job = (float(saved.day)-1.0)*1440.0+float(saved.minutes)+1440.001
			"infinite_defer":broken.autonomy_state.deferred.job = INF
		var input_before: Dictionary = broken.duplicate(true)
		var result: Dictionary = restored.restore_state(broken)
		check(not result.ok and restored.get_state() == before and broken == input_before,"Malformed policy save is rejected without changing live or caller state: "+mutation)
	comfortable(sim)
	sim.minutes += 119.9
	check(sim._autonomy_duty_id().is_empty(),"A deferred job is not requeued one fraction before the cooldown ends.")
	sim.minutes += .1
	check(sim._autonomy_duty_id() == "career_day","A deferred job becomes available when its cooldown expires within the work window.")

func _early_preparation() -> void:
	var worker:LifeSim=setup("adult",390.0)
	worker.needs.energy=55.0
	check(worker._autonomy_duty_id().is_empty(),"Preparing for a shift does not make it start before09:00.")
	check(worker._autonomy_preparation_duty_id()=="career_day","A scheduled weekday shift supports preparation up to three hours ahead.")
	check(str(worker._autonomous_choice().get("id",""))=="nap","Projected duty exhaustion triggers preparation even above the normal52 need threshold.")
	comfortable(worker)
	check(worker._autonomous_choice().is_empty(),"A comfortable worker does not begin a future duty early.")

func _moderate_departure_needs() -> void:
	for stage:String in ["teen","adult"]:
		for need:String in ["hygiene","fun","social"]:
			# Moderate boredom takes a fitting break while arrival can still be on
			# time; the clock here is past the last fitting pastime, so all three
			# needs yield to the open duty.
			var sim:LifeSim=setup(stage,520.0 if stage=="teen" else 570.0)
			var duty:String="school_day" if stage=="teen" else "career_day"
			sim.needs[need]=17.0
			check(str(sim._autonomous_choice().get("id",""))==duty,"Moderate "+need+" yields to physically safe "+duty+".")
			sim.queue_action("read","shelf");sim.get_current_action().autonomous=true
			sim._reconsider_active_autonomy()
			check(current_id(sim)==duty,"An optional approach yields to "+duty+" before waiting for furniture.")
			sim.cancel_action();sim.needs[need]=11.0
			check(str(sim._autonomous_choice().get("id",""))!=duty,"Truly critical "+need+" still recovers before "+duty+".")
