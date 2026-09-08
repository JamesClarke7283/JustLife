extends SceneTree
var checks:int=0
var failures:Array[String]=[]
var app:Node
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func capture(name:String)->void:
	for i:int in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://oven_art/"+name+".png")
func run()->void:
	DirAccess.make_dir_recursive_absolute("user://oven_art")
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await process_frame;app.set_sound(false);app.start_household();app.set_process(false)
	app.setup_live([{"id":"stove","kind":"stove","x":0,"z":0,"rotation":0}]);app.ui.hide();app.overlay.hide()
	for person:Node3D in app.world.actors.values():person.hide()
	app.world.set_process(false);app.world.daylight(700)
	for tree:Node3D in app.world.landscape_trees:tree.hide()
	for wall:Node3D in app.world.construction.wall_nodes.values():wall.hide()
	app.world.camera_target=Vector3(0,.60,.08);app.world.camera.size=1.8;app.world.camera_angle=1.02;app.world.camera_elevation=.23;app.world.update_camera()
	var oven:Node3D=app._find_item("stove").node
	var door:Node3D=oven.find_child("OvenDoor",true,false)
	var rack:Node3D=oven.find_child("OvenRack",true,false)
	var grip:Node3D=oven.find_child("OvenHandleGrip",true,false)
	var carrier:Node3D=oven.find_child("OvenRackCarrier",true,false)
	var rack_grip:Node3D=oven.find_child("OvenRackGrip",true,false)
	check(is_instance_valid(door) and is_instance_valid(rack) and is_instance_valid(grip) and is_instance_valid(carrier) and is_instance_valid(rack_grip),"Imported oven has a real door pivot, rack and handle anchor")
	if failures.size():quit(1);return
	check(grip.get_parent()==door,"Handle reference moves with the actual door")
	await capture("01_closed")
	var tray:Node3D=load("res://assets/models/meal_harvest_bake_serving.glb").instantiate();oven.add_child(tray);tray.position=oven.to_local(rack.global_position)
	var min_at:=Vector3(INF,INF,INF);var max_at:=Vector3(-INF,-INF,-INF)
	for mesh:MeshInstance3D in tray.find_children("*","MeshInstance3D",true,false):
		for i:int in range(8):
			var at:Vector3=oven.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(i)))
			min_at=min_at.min(at);max_at=max_at.max(at)
	var inner_panel:MeshInstance3D=door.find_child("Door inner enamel*",true,false)
	var inner_bounds:AABB=oven.global_transform.affine_inverse()*inner_panel.global_transform*inner_panel.get_aabb()
	check(min_at.x>=-.402 and max_at.x<=.402 and min_at.z>=-.2775 and max_at.z<inner_bounds.position.z-.005,"Complete serving dish and both handles fit behind actual closed inner panel")
	var rack_top:float=-INF;var rack_front:float=-INF
	for mesh:MeshInstance3D in carrier.find_children("*","MeshInstance3D",true,false):
		for corner:int in range(8):
			var point:Vector3=oven.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
			rack_top=maxf(rack_top,point.y);rack_front=maxf(rack_front,point.z)
	check(rack_front<inner_bounds.position.z-.003,"Complete retracted rack/grip clears actual closed door panel")
	check(min_at.y>=rack_top-.001 and min_at.y-rack_top<.003,"Dish underside rests within3mm of actual rack support height")
	check(rack.get_parent()==carrier and rack_grip.get_parent()==carrier,"Rack load and grip anchors belong to physical sliding mesh carrier")
	check(min_at.y>=.564 and max_at.y<=.747,"Tray underside rests above rack and food clears cavity ceiling")
	door.rotation.x=PI/2
	var minimum:float=INF
	for mesh:MeshInstance3D in door.find_children("*","MeshInstance3D",true,false):
		for i:int in range(8):minimum=minf(minimum,mesh.to_global(mesh.get_aabb().get_endpoint(i)).y)
	check(minimum>oven.global_position.y+.02,"Open door and handle stay above the visible cottage floor")
	check(absf(oven.to_local(grip.global_position).y-.345)<.01,"Handle follows the lower-edge hinge arc")
	await capture("02_open_loaded")
	carrier.position.z=.22;tray.global_position=rack.global_position
	check(absf(oven.to_local(rack.global_position).z-.39)<.001,"Full22cm extended carrier moves the real dish anchor")
	await capture("03_extended_loaded")
	tray.hide();await capture("04_open_cavity")
	var report:Dictionary={"checks":checks,"failures":failures,"tray_min":str(min_at),"tray_max":str(max_at),"open_door_minimum_y":minimum,"method":"Actual imported oven/tray in Godot; directed static geometry, no character or gameplay claim."}
	var out:=FileAccess.open("user://oven_art/report.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print("OVEN_ART ",JSON.stringify(report));app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
