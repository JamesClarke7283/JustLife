extends "res://tests/test_autonomy_policy.gd"
## Two consecutive routing failures for the same social target put that
## neighbour on a chooser cooldown, so a member whose route to one neighbour
## keeps failing falls back to the other company instead of stalling.
## Review 7's week B: 62 route failures, fourteen awake hours, Fun 9.1.

func run()->void:
	var home: LifeHousehold = home_setup(["adult","adult"])
	var walker: Dictionary = home.members[0]
	var neighbour_a: Dictionary = home.members[1]
	var maya: LifeSim = neighbour_a.sim
	walker.sim.needs.social=8.0
	# The normal company pool: two neighbours with relationships.
	var pool: Array = targets()
	pool.append({"id":"maya","kind":"neighbor","position":Vector3(0,.16,6)})
	pool.append({"id":"leo","kind":"neighbor","position":Vector3(3,.16,6)})
	home.register_targets(pool)
	walker.sim.relationships["maya"]={"name":"Maya","friendship":60,"romance":0,"status":"Friend"}
	walker.sim.relationships["leo"]={"name":"Leo","friendship":60,"romance":0,"status":"Friend"}
	# Two consecutive blocked approaches to Maya: the controller applies the
	# cooldown exactly as _cancel_blocked_action does.
	walker.sim.cool_social_target("maya",walker.sim._autonomy_now()+180.0)
	var choice:Dictionary=walker.sim._autonomy_social_choice()
	check(str(choice.get("target_id"))=="leo","With Maya on cooldown the chooser picks Leo ('"+str(choice.get("target_id","<none>"))+"').")
	# A fresh Lifelet without the cooldown still considers Maya.
	neighbour_a.sim.social_cooldowns.clear()
	var fresh:Dictionary=neighbour_a.sim._autonomy_social_choice()
	check(str(fresh.get("target_id"))=="maya" or str(fresh.get("target_id"))=="leo",
		"Without a cooldown both neighbours remain choosable ('"+str(fresh.get("target_id","<none>"))+"').")
	# The cooldown lapses: after three hours Maya is choosable again.
	walker.sim.cool_social_target("maya",walker.sim._autonomy_now()-1.0)
	var lapsed:Dictionary=walker.sim._autonomy_social_choice(["leo"])
	check(str(lapsed.get("target_id"))=="maya","A lapsed cooldown returns the neighbour to the pool ('"+str(lapsed.get("target_id","<none>"))+"').")
	for node:Node in owned:node.free()
	print("SOCIAL_COOLDOWN %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
