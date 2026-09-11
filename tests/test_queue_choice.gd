extends "res://tests/test_autonomy_policy.gd"
## An equivalent free resource must beat an occupied one that already has a
## queue: the week audits showed a second fridge relieving nothing while one
## member kept waiting at the original.

func run() -> void:
	var home: LifeHousehold = home_setup(["adult","adult","adult","adult"])
	var a: Dictionary = home.members[0]
	var b: Dictionary = home.members[1]
	var c: Dictionary = home.members[2]
	var d: Dictionary = home.members[3]
	for member: Dictionary in [a,b,c,d]:comfortable(member.sim)
	d.sim.needs.hunger=40.0
	var all: Array = targets()
	all.append({"id":"fridge2","kind":"fridge","position":Vector3(9,.16,6)})
	home.register_targets(all)
	# A is eating at the original fridge and B is already heading there; the
	# outsider sees both, the eaters see only each other.
	a.sim.action_queue=[{"id":"snack","target_id":"fridge","phase":"active","duration":30.0,"elapsed":5.0}]
	b.sim.action_queue=[{"id":"snack","target_id":"fridge","phase":"approach","duration":10.0,"elapsed":0.0}]
	check(c.sim._autonomy_target_load("fridge")==45.0 and c.sim._autonomy_target_load("fridge2")==0.0,
		"An outsider counts the current user plus the waiter on the busy fridge only.")
	check(a.sim._autonomy_target_load("fridge")==20.0,
		"The current user is not counted against themselves.")
	var choice: Dictionary=d.sim._autonomy_need_choice("hunger")
	check(str(choice.get("target_id"))=="fridge2",
		"A hungry Lifelet takes the free second fridge instead of queueing (%s)." % str(choice))
	# A user plus two waiters read as loaded for the pre-duty fitting bar, so a
	# brief break is not projected onto a full sofa when the day is due.
	a.sim.action_queue=[{"id":"watch","target_id":"sofa","phase":"active","duration":60.0,"elapsed":50.0}]
	b.sim.action_queue=[{"id":"watch","target_id":"sofa","phase":"approach","duration":60.0,"elapsed":0.0}]
	c.sim.action_queue=[{"id":"watch","target_id":"sofa","phase":"queued","duration":60.0,"elapsed":0.0}]
	check(d.sim._autonomy_target_load("sofa")>45.0,
		"A sofa with a user and two waiters reads as loaded for the fitting check.")
	# With every resource free the established preference is unchanged.
	for member: Dictionary in [a,b,c]:member.sim.action_queue=[]
	var calm: Dictionary=d.sim._autonomy_need_choice("hunger")
	check(str(calm.get("target_id"))=="fridge",
		"Free resources keep the established preference (%s)." % str(calm))
	for node: Node in owned:node.free()
	print("QUEUE_CHOICE %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
