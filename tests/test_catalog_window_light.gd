extends SceneTree
## Purchased windows cut real wall triangles, preserving navigation. The optional
## rendered control measures the same floor pixel with and without its window.
var world:Node3D
var checks:int=0
var failures:Array[String]=[]
var capture:bool=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames()->void:
	for i:int in 4:await process_frame
func hit(from:Vector3,to:Vector3)->bool:
	for wall:Node3D in world.construction.wall_nodes.values():
		for mesh:MeshInstance3D in wall.find_children("*","MeshInstance3D",true,false):
			var triangles:PackedVector3Array=mesh.mesh.get_faces()
			for i:int in range(0,triangles.size(),3):
				if Geometry3D.segment_intersects_triangle(from,to,mesh.to_global(triangles[i]),mesh.to_global(triangles[i+1]),mesh.to_global(triangles[i+2]))!=null:return true
	return false
func snapshot(horizontal:bool,pattern:String="")->Dictionary:
	return {"kind":"__construction","walls":[{"id":"test_wall","x":0.,"z":0.,"w":8. if horizontal else .14,"d":.14 if horizontal else 8.,"height":2.6,"cut":false,"color":"eae7d7","pattern":pattern}],"floors":[{"id":"test_floor","x":0.,"z":0.,"w":8.,"d":8.,"color":"cfa97e"}]}
func picture(label:String)->Image:
	await frames();await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var output:String=OS.get_environment("JUSTLIFE_DATA_DIR").path_join("captures")
	DirAccess.make_dir_recursive_absolute(output);image.save_png(output.path_join(label+".png"))
	return image
func brightness(image:Image,at:Vector2)->float:
	var value:float=0.
	for x:int in range(-4,5):
		for y:int in range(-4,5):value+=image.get_pixel(int(at.x)+x,int(at.y)+y).get_luminance()
	return value/81.
func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():quit(2);return
	capture=OS.get_cmdline_user_args().has("--capture")
	world=load("res://scripts/world.gd").new();root.add_child(world);await frames()
	world.create_home([]);world.set_process(false);world.set_cutaway(false)
	var angles:Array=[] if OS.get_cmdline_user_args().has("--light-only") else [0.,90.,180.,270.]
	for angle:float in angles:
		world.construction.restore(snapshot(int(angle)%180==0));await frames()
		var normal:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3.BACK
		for style:String in ["a","b","c","d","e"]:
			var at:Vector3=Vector3(0,.16,0)+normal*.6
			var snapped:Dictionary=world.wall_snap("house_window",at)
			world.begin_placement("house_window",style);world.update_ghost(at)
			var bounds:Array[Vector3]=[];world._gather_visual_bounds(world.ghost,Transform3D.IDENTITY,bounds)
			var lowest:float=INF
			for point:Vector3 in bounds:lowest=minf(lowest,point.y)
			check(lowest>.8,"Window ghost is raised to the pane height")
			world.clear_placement()
			world.add_item({"id":"bought_window","kind":"house_window","x":snapped.position.x,"z":snapped.position.z,"rotation":snapped.angle,"style":style})
			var item:Dictionary=world.items.filter(func(entry:Dictionary)->bool:return str(entry.id)=="bought_window")[0]
			check(item.node.visible,"Purchased window is supported at "+str(angle)+style)
			var center:Vector3=Vector3(0,1.78,0)+Basis(Vector3.UP,deg_to_rad(angle))*Vector3(.4,.1,0)
			check(not hit(center-normal*.4,center+normal*.4),"Purchased pane cuts actual wall triangles")
			check(hit(Vector3(0,.6,0)-normal*.4,Vector3(0,.6,0)+normal*.4),"Sill wall stays solid")
			check(world.construction.point_blocked(Vector2.ZERO),"Window remains nonwalkable")
			var glass:MeshInstance3D=item.node.find_children("Glass*","MeshInstance3D",true,false)[0]
			check(glass.mesh is QuadMesh and glass.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and glass.material_override.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"Glass passes daylight without opaque shadows")
			world.set_cutaway(true);check(not item.node.visible,"Lowered walls hide window")
			world.set_cutaway(false);check(item.node.visible,"Raised walls restore window")
			world.remove_item("bought_window")
			check(hit(center-normal*.4,center+normal*.4),"Selling window restores its wall immediately")
			await frames()
			print("WINDOW_CASE ",angle," ",style)
	world.construction.restore(snapshot(true,"patterned"));await frames()
	world.add_item({"id":"light_window","kind":"house_window","x":0.,"z":-.13,"rotation":180.,"style":"e"})
	check(not hit(Vector3(.4,1.86,-.4),Vector3(.4,1.86,.4)),"Paint bands also leave the pane open")
	for pattern:String in ["stars","clouds"]:
		world.construction.restore(snapshot(true,pattern));await frames()
		check(not hit(Vector3(.4,1.2,-.4),Vector3(.4,1.2,.4)),"Nursery "+pattern+" leaves the lower pane open")
	world.construction.restore(snapshot(true));await frames()
	var saved:Array=world.serialize_items()
	var loaded:Dictionary=world.load_home(saved)
	check(bool(loaded.ok),"Purchased window and structure reload: "+str(loaded.get("error","")))
	world.set_cutaway(false);await frames()
	check(not hit(Vector3(.4,1.86,-.4),Vector3(.4,1.86,.4)),"Saved purchased window rebuilds its aperture")
	if capture:
		world.sun.rotation_degrees=Vector3(-45,0,0);world.sun.light_energy=1.2
		world.sun.light_angular_distance=0.;world.environment.ambient_light_energy=.03
		world.camera.position=Vector3(3,6,-7);world.camera.look_at(Vector3(0,.7,-.5));world.camera.size=8
		var pixel:Vector2=world.camera.unproject_position(Vector3(.4,.17,-1.6))
		var lit:Image=await picture("window-daylight")
		pixel*=Vector2(lit.get_size())/root.get_visible_rect().size
		world.remove_item("light_window")
		var dark:Image=await picture("window-removed-control")
		var delta:float=brightness(lit,pixel)-brightness(dark,pixel)
		print("DAYLIGHT_LUMINANCE_DELTA ",delta)
		check(delta>.08,"Real directional sunlight illuminates the floor through the window")
	world.queue_free();await frames()
	print("CATALOG_WINDOW_LIGHT ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
