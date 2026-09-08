extends SceneTree
## Exact shared-homework stand/route validation at rotated desks.
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func run() -> void:
	var world:LifeWorld=LifeWorld.new();root.add_child(world)
	world.construction=LifeConstruction.new();world.add_child(world.construction);world.construction.initialize(world)
	var desk:Node3D=Node3D.new();world.add_child(desk)
	var chair:Node3D=Node3D.new();world.add_child(chair)
	var item:Dictionary={"id":"desk","node":desk,"kind":"desk","size":Vector2(1.65,.8)}
	var seat:Dictionary={"id":"chair","node":chair,"kind":"chair","size":Vector2(.57,.59)}
	world.items.assign([item,seat])
	for angle:float in [0.0,PI*.5,PI,PI*1.5]:
		desk.position=Vector3(1,.16,1);desk.rotation.y=angle
		chair.position=desk.to_global(Vector3(0,0,.88));chair.rotation.y=angle+PI
		world.rebuild_navigation()
		var before:Array=[desk.transform,chair.transform]
		var plan:Dictionary=world.supported_homework_plan(item,Vector3(-3,.16,-3),Vector3(3,.16,-3))
		check(plan.ok,"A rotated desk has a reachable cooperative plan: "+str(angle))
		if bool(plan.ok):
			check(plan.helper_position.distance_to(chair.position)>=.85,"Caregiver has body clearance from the learner at "+str(angle))
			check(world._clear_coaching_space(plan.helper_position),"Caregiver footprint clears furniture and walls at "+str(angle))
			var route:PackedVector3Array=world.path_to(Vector3(3,.16,-3),plan.helper_position)
			check(not route.is_empty() and route[-1].is_equal_approx(plan.helper_position),"Route reaches the exact stand point without nearest-free drift at "+str(angle))
		check(before==[desk.transform,chair.transform],"Planning leaves the authored desk and chair unchanged.")
	world.items.assign([item]);world.rebuild_navigation()
	check(not world.supported_homework_plan(item,Vector3.ZERO,Vector3.ZERO).ok,"An unsupported desk clearly rejects paired homework.")
	world.items.assign([item,seat])
	var blocker:Node3D=Node3D.new();world.add_child(blocker);blocker.position=desk.position
	world.items.append({"id":"blocker","kind":"bed","node":blocker,"size":Vector2(6,6)})
	world.rebuild_navigation()
	var blocked:Dictionary=world.supported_homework_plan(item,Vector3(-4,.16,-4),Vector3(4,.16,-4))
	check(not blocked.ok and not str(blocked.error).is_empty(),"Blocked coaching space fails with a player-facing reason instead of snapping elsewhere.")
	world.queue_free();await process_frame
	print("COACHING_SPACE %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
