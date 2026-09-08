extends SceneTree
## Regression for late-index household members starving at a shared bed.
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,detail:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(detail)
func run() -> void:
	var app:Node=load("res://scripts/main.gd").new()
	app.world=LifeWorld.new();root.add_child(app.world)
	app.household=LifeHousehold.new();root.add_child(app.household)
	app.household.new_household([{}, {}, {}, {}, {}, {}, {}, {}])
	var bed:Node3D=Node3D.new();app.world.add_child(bed)
	app.world.items.append({"id":"bed","kind":"bed","node":bed,"size":Vector2(2,2)})
	for i:int in range(8):
		var member:Dictionary=app.household.members[i]
		member.sim.autonomy=false
		member.sim.queue_action("sleep","bed",Vector3(0,.16,1.5))
		var state:Dictionary=app._empty_motion()
		state.waiting=true;state.wait_started=480.0+float(7-i)
		app.motion_states[member.id]=state
	app.bound_member_id="player";app.wait_started=487.0
	check(not app._activity_available(app.household.members[0].sim.get_current_action()),"The first-index Lifelet cannot take a bed from an older waiter.")
	app.bound_member_id="housemate_7";app.wait_started=480.0
	check(app._activity_available(app.household.members[7].sim.get_current_action()),"The oldest waiter can begin despite being last in the household array.")
	app.household.members[7].sim.begin_current_action()
	app.bound_member_id="housemate_6";app.wait_started=481.0
	check(not app._activity_available(app.household.members[6].sim.get_current_action()),"The active occupant still holds the bed.")
	app.household.members[7].sim.cancel_action()
	check(app._activity_available(app.household.members[6].sim.get_current_action()),"Releasing the bed admits the next oldest waiter.")
	check(app._activity_available({"target_id":"unrelated"}),"Waiting for a bed does not lock unrelated objects.")
	app.household.members[7].sim.queue_action("sleep","bed",Vector3(0,.16,1.5))
	app.motion_states.housemate_7.wait_started=490.0
	app.bound_member_id="housemate_7";app.wait_started=490.0
	check(not app._activity_available(app.household.members[7].sim.get_current_action()),"An immediate repeat request goes behind existing waiters.")
	for i:int in range(8):app.motion_states[app.household.members[i].id].wait_started=500.0
	app.bound_member_id="housemate_1";app.wait_started=500.0
	check(app._activity_available(app.household.members[1].sim.get_current_action()),"Simultaneous arrivals have a deterministic first waiter.")
	app.bound_member_id="housemate_2";app.wait_started=500.0
	check(not app._activity_available(app.household.members[2].sim.get_current_action()),"A tied second waiter does not also acquire the same object.")
	for i:int in range(8):
		app.household.members[i].sim.cancel_action()
	check(app._activity_available({"target_id":"bed"}),"Canceled queues cannot leave stale resource reservations.")
	var learner:LifeSim=app.household.members[0].sim
	var helper:LifeSim=app.household.members[1].sim
	learner.queue_action("sleep","bed",Vector3(0,.16,1.5))
	helper.queue_action("sleep","bed",Vector3(1.5,.16,1.5))
	learner.get_current_action()["cooperation_id"]="pair_regression"
	helper.get_current_action()["cooperation_id"]="pair_regression"
	app.bound_member_id="player";app.wait_started=-1.0
	check(app._activity_available(learner.get_current_action()),"Members of the same coordinated session share one reservation.")
	app.bound_member_id="housemate_2"
	check(not app._activity_available({"target_id":"bed"}),"An assembling pair holds its object against an unrelated arrival.")
	learner.get_current_action().erase("cooperation_id");helper.get_current_action().erase("cooperation_id")
	app.household.queue_free();app.world.queue_free();app.free();await process_frame
	print("RESOURCE_FAIRNESS %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
