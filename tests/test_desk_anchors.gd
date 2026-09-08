extends SceneTree
var checks:int=0
var failures:int=0

func check(value:bool,detail:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(detail)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world:LifeWorld=LifeWorld.new()
	root.add_child(world)
	var desk:Node3D=Node3D.new();world.add_child(desk)
	var chair:Node3D=Node3D.new();world.add_child(chair)
	var item:Dictionary={"node":desk,"kind":"desk","size":Vector2(1.65,.77)}
	world.items.assign([item,{"node":chair,"kind":"chair","size":Vector2(.57,.59)}])
	for angle:float in [0.0,PI*.5,PI,PI*1.5]:
		desk.position=Vector3(3,.16,2);desk.rotation.y=angle
		chair.position=desk.to_global(Vector3(0,0,.88));chair.rotation.y=angle+PI
		var furniture_before:Array=[desk.transform,chair.transform]
		var base:Dictionary=world.activity_anchor(item,"school")
		var child:Dictionary=world.activity_anchor(item,"school",{"age_stage":"child","height":1.18})
		var local_hip:Vector3=chair.to_local(child.position)
		check(absf(local_hip.x)<.51*.5 and absf(local_hip.z-.02)<.53*.5 and is_equal_approx(local_hip.y,.70),"The child hip anchor must stay on the booster surface at rotation %s."%angle)
		var booster:Node3D=chair.get_node("LifeletDeskBooster")
		check(booster.visible and is_equal_approx(booster.position.y,.52),"A visible booster must rest on the real chair, underneath the raised support point.")
		var model_top:float=-INF
		for mesh:MeshInstance3D in booster.find_children("*","MeshInstance3D",true,false):
			var bounds:AABB=mesh.get_aabb()
			for corner:int in range(8):model_top=maxf(model_top,mesh.to_global(bounds.get_endpoint(corner)).y)
		check(absf(model_top-child.position.y)<.001,"The imported Blender cushion's actual top must meet the supplied hip support height.")
		var base_distance:float=Vector2(base.position.x,base.position.z).distance_to(Vector2(base.hand_center.x,base.hand_center.z))
		var child_distance:float=Vector2(child.position.x,child.position.z).distance_to(Vector2(child.hand_center.x,child.hand_center.z))
		check(child_distance<base_distance-.20,"The child support point must materially shorten keyboard reach in every rotated layout.")
		check(child.hand_center.is_equal_approx(desk.to_global(Vector3(0,.915,.105))),"The keyboard target must remain attached to the desk, independent of the sitter.")
		check(child.yaw==base.yaw and child.kind=="seat","Seated orientation and support kind remain tied to the desk.")
		for stage:String in ["teen","young_adult","adult","elder"]:
			check(world.activity_anchor(item,"school",{"age_stage":stage}).position.is_equal_approx(base.position),stage+" retains the center seat support point.")
		check(furniture_before==[desk.transform,chair.transform],"Selecting an age-aware anchor cannot move furniture.")
		world.begin_activity_frame(true)
		check(booster.visible,"Pause preserves the support prop with the frozen seated pose, including a canceled queue.")
		world.begin_activity_frame()
		check(not booster.visible,"The temporary booster is hidden when no child desk activity uses it.")
	world.items.assign([item])
	var standing:Dictionary=world.activity_anchor(item,"school",{"age_stage":"child"})
	check(standing.kind=="standing" and standing.has("hand_center"),"Removing the chair must leave a standing desk anchor instead of a floating seat.")
	world.queue_free();await process_frame
	print("DESK_ANCHORS %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
