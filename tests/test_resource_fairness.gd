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
	root.add_child(app)
	# The real service set, so availability, routing and meal rules answer the way
	# they do in play rather than from a half-built controller.
	app.setup_services()
	app.world.name="World"
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
	_test_wait_positions(app)
	app.household.queue_free();app.world.queue_free();app.free();await process_frame
	print("RESOURCE_FAIRNESS %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _test_wait_positions(app:Node) -> void:
	app.world.navigation.region=Rect2i(-24,-24,49,49)
	app.world.navigation.cell_size=Vector2(.25,.25)
	app.world.navigation.update()
	var target:Vector3=Vector3(0,.16,1.5)
	for i:int in range(8):
		var member:Dictionary=app.household.members[i]
		while not member.sim.action_queue.is_empty():member.sim.cancel_action()
		member.sim.queue_action("sleep","bed",target)
		var actor:=LifeActor.new()
		actor.position=target
		app.world.actors[str(member.id)]=actor
		var motion:Dictionary=app._empty_motion()
		motion.waiting=i>0;motion.wait_started=480.0+i
		app.motion_states[str(member.id)]=motion
	app.household.members[0].sim.begin_current_action()
	var positions:Array[Vector3]=[]
	for i:int in range(1,8):
		app._bind_member(str(app.household.members[i].id))
		app._route_to_wait_position(app.sim.get_current_action())
		check(app.wait_destination.is_finite() and app.wait_destination.distance_to(target)>=.8,"A waiting Lifelet has a clear position outside the active object approach.")
		for other:Vector3 in positions:check(app.wait_destination.distance_to(other)>=.8,"Seven waiting Lifelets reserve distinct body-width positions.")
		positions.append(app.wait_destination)
		app._advance_path(10.0)
		app._store_motion()
		check(app.player.position.distance_to(app.wait_destination)<.01,"The waiting position is reached through the normal movement path.")
		check(app.sim.get_current_action().phase=="approach","Walking aside does not start an unavailable activity.")
	# Restore actual saved wait fields while the later Lifelet is selected.
	for member:Dictionary in app.household.members:
		member.sim.character.world_state={"resource_wait_started":app.motion_states[str(member.id)].wait_started,"resource_action_active":member.sim.get_current_action().phase=="active","waiting_action_id":"sleep","waiting_target_id":"bed"}
		member.sim.get_current_action().phase="approach"
		app.motion_states[str(member.id)]=app._empty_motion()
	app.household.minutes=500.0
	app.household.select(7)
	app._restore_resource_waits()
	check(app.motion_states.housemate_1.waiting and app.motion_states.housemate_1.wait_started==481.0,"Fresh restoration reinstates an arrived wait reservation before any movement.")
	check(app.motion_states.player.resume_active,"Fresh restoration preserves the existing active owner's reservation.")
	app.household.members[0].sim.character.world_state.erase("resource_action_active")
	app.household.members[0].sim.character.world_state.resource_wait_started=-1.0
	app.motion_states.player=app._empty_motion()
	app._restore_resource_waits()
	check(app.motion_states.player.resume_active,"Older saves infer the unfinished occupant from paid progress without new metadata.")
	app._bind_member("housemate_1")
	check(not app._activity_available(app.sim.get_current_action()),"Saved waiters cannot overtake an existing occupant during restored approach.")
	app._bind_member("player")
	check(not app._activity_available({"target_id":"bed"}),"Saved ownership cannot give a fresh request priority over existing waiters.")
	app._advance_movement(.01);app._store_motion()
	check(app.sim.get_current_action().phase=="active" and not app.resume_activity,"The saved occupant resumes at the object before arrived waiting requests.")
	app.household.members[0].sim.cancel_action()
	app._bind_member("housemate_1")
	app._advance_movement(.01)
	app._store_motion()
	check(app.waiting_for_target and app.sim.get_current_action().phase=="approach","The oldest waiter walks back instead of teleporting into an active pose.")
	app._bind_member("housemate_7")
	check(not app._activity_available(app.sim.get_current_action()),"The oldest waiter retains priority while returning from their distinct position.")
	app._bind_member("housemate_1")
	app._advance_movement(10.0);app._advance_movement(.01)
	check(app.sim.get_current_action().phase=="active" and app.player.position.distance_to(target)<.01,"An admitted waiter starts only after physically reaching the activity.")
	app._clear_motion();app.sim.cancel_action();app._store_motion()
	check(not app.motion_states.housemate_1.waiting and not app.motion_states.housemate_1.wait_destination.is_finite(),"Cancellation releases the waiting position and resource reservation.")
	app.world.house=Node3D.new();app.world.add_child(app.world.house)
	app.world.items.clear()
	app._refresh_sim_targets()
	for member:Dictionary in app.household.members:
		var motion:Dictionary=app.motion_states[str(member.id)]
		check(member.sim.action_queue.is_empty() and not motion.waiting and not motion.wait_destination.is_finite(),"Removing the contested object releases every pending queue position.")
	for actor:LifeActor in app.world.actors.values():actor.free()
	app.world.actors.clear()
