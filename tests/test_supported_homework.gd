extends SceneTree

var checks: int = 0
var failures: int = 0
var observer_failures: Array[String] = []
var observer_count: int = 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func targets() -> Array:
	return [{"id":"desk","kind":"desk","position":Vector3(0,.16,0)},{"id":"desk2","kind":"computer","position":Vector3(3,.16,0)},{"id":"player","kind":"neighbor","position":Vector3(1,.16,0)},{"id":"housemate_1","kind":"neighbor","position":Vector3(-1,.16,0)},{"id":"housemate_2","kind":"neighbor","position":Vector3(-2,.16,0)}]

func make_home() -> LifeHousehold:
	var home: LifeHousehold = LifeHousehold.new();root.add_child(home)
	home.new_household([{"name":"Rowan","age_stage":"child","traits":[]},{"name":"Ellis","age_stage":"adult","traits":[]},{"name":"Morgan","age_stage":"elder","traits":[]}])
	home.configure_family([{"a":"housemate_1","b":"player","role":"parent"},{"a":"housemate_2","b":"housemate_1","role":"parent"}])
	for member: Dictionary in home.members:
		member.sim.autonomy=false
		member.sim.wants.clear()
	home.register_targets(targets())
	return home

func queue_pair(home: LifeHousehold, helper: String = "housemate_1") -> Dictionary:
	return home.queue_supported_homework("player",helper,"desk",Vector3(0,.16,0),Vector3(.75,.16,0))

func roundtrip(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(state)))

func observe(home: LifeHousehold) -> void:
	for member: Dictionary in home.members:
		member.sim.changed.connect(func(): observe_state(home,"changed"))
		member.sim.action_started.connect(func(_action: Dictionary): observe_state(home,"started"))
		member.sim.action_finished.connect(func(_action: Dictionary): observe_state(home,"finished"))
		member.sim.notice.connect(func(_message: String): observe_state(home,"notice"))
		member.sim.age_changed.connect(func(_a: String,_b: String): observe_state(home,"age"))

func observe_state(home: LifeHousehold, event: String) -> void:
	observer_count+=1
	var validator: LifeHousehold=LifeHousehold.new()
	var result: Dictionary=validator.restore_state(roundtrip(home.get_state()))
	if not result.ok: observer_failures.append(event+": "+str(result.error))
	validator.free()

func run() -> void:
	var home: LifeHousehold=make_home()
	var learner: LifeSim=home.member_sim("player")
	var helper: LifeSim=home.member_sim("housemate_1")
	observe(home)
	check(home.homework_helpers("player","desk").size()==2 and home.homework_helpers("player","desk")[0].available,"Both trusted adult household members appear as caregivers.")
	var initial: Dictionary=home.get_state()
	check(not helper.queue_action("help_homework","desk") and home.get_state()==initial,"A standalone helper action cannot create an orphan queue.")
	var queued: Dictionary=queue_pair(home)
	check(queued.ok and home.cooperations.size()==1,"Pair creation creates one linked session.")
	check(learner.action_queue[0].id=="homework" and helper.action_queue[0].id=="help_homework","The learner owns homework and the helper has a passive action.")
	check(learner.action_queue[0].cooperation_id==helper.action_queue[0].cooperation_id and learner.action_queue[0].target_id==helper.action_queue[0].target_id,"The pair shares a token and desk, with separate approach positions.")
	check(not queue_pair(home,"housemate_2").ok,"A second caregiver cannot reserve the same learner.")
	home.begin_action("player")
	check(home.cooperative_presentation("player").ready and not home.cooperative_presentation("housemate_1").ready,"The learner can wait seated for the caregiver.")
	home.tick(6.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(float(learner.action_queue[0].elapsed)==0 and learner.education.homework==0 and helper.skills.parenting.xp==0,"Waiting advances needs/time but awards no assignment progress or effects.")
	home.begin_action("housemate_1")
	check(home.cooperative_presentation("player").phase=="active" and learner.action_queue[0].phase=="active" and helper.action_queue[0].phase=="active","Both arrivals start the shared activity.")
	home.tick(12.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(is_equal_approx(float(learner.action_queue[0].elapsed),12.0) and learner.action_queue[0].elapsed==helper.action_queue[0].elapsed,"The learner clock advances once and helper progress mirrors it.")
	var snapshot: Dictionary=roundtrip(home.get_state())
	home.set_speed(0)
	var paused: Dictionary=home.get_state()
	home.tick(30)
	check(home.get_state()==paused,"Pause freezes both clocks, waits and effects exactly.")
	home.set_speed(1)
	var before_logic: float=learner.skills.logic.xp
	var before_friend: float=learner.relationships.housemate_1.friendship
	var before_funds: int=home.funds
	home.tick(33.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(home.cooperations.is_empty() and learner.action_queue.is_empty() and helper.action_queue.is_empty(),"Successful completion clears both actions and the reservation.")
	check(learner.education.homework==1 and learner.education.last_homework_day==1 and learner.education.attended==0,"The ordinary assignment completes once without inventing school attendance.")
	check(is_equal_approx(float(learner.skills.logic.xp)-before_logic,10.0) and helper.skills.parenting.xp==20.0,"Completion grants base Logic6 plus supported4 and Parenting20.")
	check(learner.relationships.housemate_1.friendship==before_friend+6 and helper.relationships.player.friendship==before_friend+6,"Friendship improves reciprocally by six.")
	check(home.funds==before_funds and LifeEducation.score(learner.education)==61.0,"Cooperation grants no money or extra grade points beyond normal homework.")
	check(learner.memories.any(func(entry:Dictionary)->bool:return entry.label=="Learning together") and helper.memories.any(func(entry:Dictionary)->bool:return entry.label=="Learning together"),"Both participants remember the shared assignment.")
	var finished: Dictionary=home.get_state()
	home.finish_cooperative_homework(str(queued.session_id))
	check(home.get_state()==finished and not queue_pair(home).ok,"Repeated completion and same-day replay cannot duplicate rewards.")
	check(observer_count>15 and observer_failures.is_empty(),"Every observed start/change/finish/notice sees a complete loadable household: "+str(observer_failures))
	_restore_cases(snapshot)
	_cancel_cases()
	_eligibility_cases()
	home.queue_free();await process_frame
	print("SUPPORTED HOMEWORK: %d checks, %d failures; %d observed callbacks" % [checks,failures,observer_count])
	quit(1 if failures>0 else 0)

func _restore_cases(snapshot: Dictionary) -> void:
	var home: LifeHousehold=make_home()
	var original: Dictionary=snapshot.duplicate(true)
	check(home.restore_state(snapshot).ok and snapshot==original,"An active session restores without mutating caller data.")
	var view: Dictionary=home.cooperative_presentation("player")
	check(view.phase=="assembling" and not view.ready and is_equal_approx(float(view.elapsed),12.0),"Restore keeps learning progress but requires both arrivals again.")
	check(home.member_sim("housemate_1").action_queue[0].target_position.is_equal_approx(Vector3(.75,.16,0)),"The caregiver's distinct standing route survives JSON.")
	var standalone: LifeSim=LifeSim.new()
	check(not standalone.restore_state(snapshot.members[1].state).ok,"A paired helper cannot be loaded alone.")
	standalone.free()
	home.register_targets(targets());home.begin_action("housemate_1");home.begin_action("player");home.tick(33.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(home.selected().education.homework==1 and home.member_sim("housemate_1").skills.parenting.xp==20.0,"Reapproach finishes only the remaining work, with effects once.")
	var stable: Dictionary=home.get_state()
	for mutation: String in ["orphan","missing_pair","duplicate","wrong_member","underage","low_trust","different_clock","wrong_position","late","bad_ready","bad_token","delayed_action","bad_skill"]:
		var broken: Dictionary=snapshot.duplicate(true)
		match mutation:
			"orphan":broken.cooperations.clear()
			"missing_pair":broken.members[1].state.action_queue.clear()
			"duplicate":broken.cooperations.append(broken.cooperations[0].duplicate(true))
			"wrong_member":broken.cooperations[0].helper_id="missing"
			"underage":broken.members[1].state.character.life_stage="minor"
			"low_trust":broken.members[1].state.relationships.player.friendship=19.0
			"different_clock":broken.members[1].state.action_queue[0].elapsed=11.0
			"wrong_position":broken.cooperations[0].helper_position=[99,0,0]
			"late":broken.cooperations[0].waited=60.0
			"bad_ready":broken.cooperations[0].ready=["player","player"]
			"bad_token":broken.cooperations[0].id="homework_02"
			"delayed_action":broken.members[1].state.action_queue.push_front(broken.members[1].state.action_queue[0].duplicate(true))
			"bad_skill":broken.members[1].state.skills.parenting.level=true
		var copy: Dictionary=broken.duplicate(true)
		check(not home.restore_state(broken).ok and home.get_state()==stable and broken==copy,"Malformed paired save rejected atomically: "+mutation)
	var old: Dictionary=stable.duplicate(true)
	old.erase("cooperations");old.erase("cooperation_serial");old.erase("cooperation_version")
	for entry: Dictionary in old.members:entry.state.skills.erase("parenting")
	check(home.restore_state(old).ok and home.member_sim("housemate_1").skills.parenting=={"level":1,"xp":0.0},"Older saves gain neutral Parenting skill and no sessions.")
	home.queue_free()

func _cancel_cases() -> void:
	for cause: String in ["learner","helper","timeout","midnight","birthday","furniture","presence"]:
		var home: LifeHousehold=make_home();observe(home);queue_pair(home)
		var learner: LifeSim=home.selected();var helper: LifeSim=home.member_sim("housemate_1")
		if cause not in ["timeout","midnight"]:
			home.begin_action("player");home.begin_action("housemate_1");home.tick(3.0/LifeSim.GAME_MINUTES_PER_SECOND)
		match cause:
			"learner":learner.cancel_action()
			"helper":helper.cancel_action()
			"timeout":home.tick(60.0/LifeSim.GAME_MINUTES_PER_SECOND)
			"midnight":
				home.day=1;home.minutes=1439.0
				for member: Dictionary in home.members:member.sim.minutes=1439.0
				home.tick(1.2/LifeSim.GAME_MINUTES_PER_SECOND)
			"birthday":learner.celebrate_birthday()
			"furniture":home.register_targets(targets().filter(func(target:Dictionary)->bool:return str(target.id)!="desk"))
			"presence":home.register_targets(targets().filter(func(target:Dictionary)->bool:return str(target.id)!="housemate_1"))
		check(home.cooperations.is_empty() and learner.action_queue.is_empty() and helper.action_queue.is_empty(),"Both linked plans release after "+cause)
		check(learner.education.homework==0 and helper.skills.parenting.xp==0,"Interrupted homework cannot grant effects: "+cause)
		home.queue_free()
	check(observer_failures.is_empty(),"All cancellation/birthday callback snapshots remain valid: "+str(observer_failures))

func _eligibility_cases() -> void:
	var home: LifeHousehold=make_home()
	var stable: Dictionary=home.get_state()
	check(not home.queue_supported_homework("player","player","desk").ok and not home.queue_supported_homework("player","maya","desk").ok,"Self and outside-household help are refused.")
	check(not home.queue_supported_homework("housemate_1","player","desk").ok and home.get_state()==stable,"Reversed age roles are refused without changing state.")
	home.member_sim("housemate_1").relationships.player.friendship=19
	check(not queue_pair(home).ok,"Unilateral low friendship blocks help.")
	home.member_sim("housemate_1").relationships.player.friendship=55
	home.member_sim("housemate_1").queue_action("read","desk2")
	check(not queue_pair(home).ok,"A caregiver with other plans is not silently interrupted.")
	home.queue_free()
