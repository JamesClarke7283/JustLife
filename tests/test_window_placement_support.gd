extends SceneTree
## Placement and the rendered frame share continuous wall support, even with
## the walls lowered. This fixture changes records without rebuilding navigation.
var world:LifeWorld
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func walls(spans:Array,angle:float,height:float=2.6)->Array:
	var records:Array=[]
	for span:Vector2 in spans:
		var along_x:bool=int(angle)%180==0
		records.append({"id":"wall_"+str(records.size()),"x":span.x if along_x else 0.,"z":0. if along_x else span.x,"w":span.y if along_x else .14,"d":.14 if along_x else span.y,"height":height,"level":0})
	return records
func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():quit(2);return
	world=LifeWorld.new();root.add_child(world);world.set_process(false)
	world.house=Node3D.new();world.add_child(world.house)
	world.furniture=Node3D.new();world.house.add_child(world.furniture)
	for angle:float in [0.,90.,180.,270.]:
		var normal:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3.BACK
		var at:Vector3=Vector3(0,.16,0)+normal*.13
		for cutaway:bool in [false,true]:
			world.cutaway=cutaway;world.construction.cutaway=cutaway
			world.construction.records=walls([Vector2(0,6)],angle)
			check(world.can_place("house_window",at,angle),"Long wall supports full window at "+str(angle)+" cutaway="+str(cutaway))
			world.construction.records=walls([Vector2(-1,2),Vector2(1,2)],angle)
			check(world.can_place("house_window",at,angle),"Joined walls support a frame across their seam")
			world.construction.records=walls([Vector2(0,.5)],angle)
			check(not world.can_place("house_window",at,angle),"Short stub rejects a frame wider than the wall")
			world.construction.records=walls([Vector2(-1.35,3.3),Vector2(1.8,2.4)],angle)
			check(not world.can_place("house_window",at,angle),"Gap under one side of the frame is rejected")
			world.construction.records=walls([Vector2(0,6)],angle,2.)
			check(not world.can_place("house_window",at,angle),"Low wall rejects a frame exceeding its height")
		world.construction.records=walls([Vector2(0,6)],angle)
		world.begin_placement("house_window","e");world.update_ghost(Vector3(0,.16,0)+normal*.6)
		check(world.ghost_valid,"Supported preview stays green with walls lowered")
		var points:Array[Vector3]=[];world._gather_visual_bounds(world.ghost,Transform3D.IDENTITY,points)
		var lowest:float=INF
		for point:Vector3 in points:lowest=minf(lowest,point.y)
		check(lowest>.8,"Window preview is raised above the floor")
		world.construction.records=walls([Vector2(0,.5)],angle)
		world.update_ghost(Vector3(0,.16,0)+normal*.6)
		check(not world.ghost_valid,"Unsupported short-wall preview is red")
		world.clear_placement()
	world.queue_free();await process_frame;await process_frame
	print("WINDOW_PLACEMENT_SUPPORT ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
