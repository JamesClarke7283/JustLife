extends SceneTree
## Pointing at a visible raised worktop aims at that surface, then commits a
## floor-level coordinate so placement and story validation agree.
var failures:int=0
var checks:int=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var world:=LifeWorld.new();root.add_child(world)
	world.create_home([]);world.set_process(false)
	world.add_item({"id":"counter","kind":"counter","x":-3.0,"z":-3.0,"rotation":0.0},false)
	world.add_item({"id":"table","kind":"dining","x":-3.0,"z":1.0,"rotation":90.0},false)
	world.begin_placement("coffee_machine")
	for target:Vector3 in [Vector3(-3,1.112,-3),Vector3(-3,1.007,1)]:
		var screen:Vector2=world.camera.unproject_position(target)
		var pointed:Vector3=world.placement_point(screen)
		check(Vector2(pointed.x-target.x,pointed.z-target.z).length()<.01,"Visible surface follows mouse ray")
		check(is_equal_approx(pointed.y,.16),"Surface ray preserves floor-level validation point")
		world.update_ghost(pointed)
		check(world.ghost_valid and absf(world.ghost.position.y-target.y)<.001,"Surface cursor creates a legal raised preview")
	var floor_target:=Vector3(-3,.16,3)
	check(world.placement_point(world.camera.unproject_position(floor_target)).distance_to(floor_target)<.01,"Open floor remains available from the mouse")
	world.queue_free();await process_frame
	print("KITCHEN_POINTER %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
