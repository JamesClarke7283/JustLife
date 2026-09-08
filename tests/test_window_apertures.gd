extends SceneTree
## Actual wall-triangle/material controls and matched-camera scene captures.
var world:Node3D
var checks:int=0
var failures:Array=[]
var receipt:Dictionary={}
var output_dir:String="user://qa/window_apertures"
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);print("FAIL: ",label)
func wall_hit(from:Vector3,to:Vector3)->bool:
	for wall:Node3D in world.construction.wall_nodes.values():
		for mesh:Node in wall.get_children():
			if not mesh is MeshInstance3D:continue
			var faces:PackedVector3Array=mesh.mesh.get_faces()
			for i:int in range(0,faces.size(),3):
				if Geometry3D.segment_intersects_triangle(from,to,mesh.to_global(faces[i]),mesh.to_global(faces[i+1]),mesh.to_global(faces[i+2]))!=null:return true
	return false
func windows()->Array:
	var out:Array=[]
	for node:Node in world.house.get_children():
		if node.has_meta("window_aperture"):out.append(node)
	return out
func sample_apertures(label:String)->void:
	for n:Node3D in windows():
		var side:bool=absf(n.rotation_degrees.y)>45
		for dx:float in [-.67,-.31,.31,.67]:
			for dy:float in [-.49,.29,.49]:
				var at:Vector3=n.position+(Vector3(0,dy,dx) if side else Vector3(dx,dy,0))
				var axis:Vector3=Vector3.RIGHT if side else Vector3.BACK
				check(not wall_hit(at-axis*.4,at+axis*.4),label+" wall has a true through aperture at "+str(at))
func capture(name:String,at:Vector3,target:Vector3,size:float)->void:
	if not "--capture" in OS.get_cmdline_user_args():return
	world.camera.position=at;world.camera.look_at(target);world.camera.size=size
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(output_dir.path_join(name+".png"))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world=load("res://scripts/world.gd").new();root.add_child(world);await process_frame
	world.create_home(LifeCatalog.starter_layout());world.set_process(false);world.set_cutaway(false);await process_frame
	check(windows().size()==5,"The starter home retains all five framed windows.")
	var snapshot:Dictionary=world.construction.snapshot().duplicate(true)
	for n:Node3D in windows():
		var glass:MeshInstance3D=n.get_child(0)
		check(glass.mesh is QuadMesh and glass.material_override.cull_mode==BaseMaterial3D.CULL_DISABLED,"Glass is a single two-sided pane rather than stacked transparent box faces.")
		check(glass.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Glass does not cast an opaque shadow over the interior.")
		check(glass.material_override!=world.material("9ac0c1"),"Glass does not share and mutate an opaque object material.")
		check(glass.material_override.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and glass.material_override.albedo_color.a<.3,"Window glass uses transparent alpha rather than opaque paint.")
	check(world.material("9ac0c1").transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Existing objects using the glass tint keep opaque material semantics.")
	sample_apertures("Initial")
	check(wall_hit(Vector3(-2.7,1.8,-4.7),Vector3(-2.7,1.8,-5.4)),"Wall between adjacent windows retains real opaque faces.")
	check(wall_hit(Vector3(-4.25,.7,-4.7),Vector3(-4.25,.7,-5.4)),"Wall below the window remains solid.")
	check(wall_hit(Vector3(-4.25,2.65,-4.7),Vector3(-4.25,2.65,-5.4)),"Wall lintel remains solid.")
	check(world.construction.point_blocked(Vector2(-4.25,-5.04)),"The visual aperture remains nonwalkable in logical navigation.")
	check(world.navigation.is_point_solid(Vector2i(-17,-20)),"The actual navigation grid still blocks a cell below the window.")
	await capture("01_inside",Vector3(-.7,2.45,.7),Vector3(-3,1.6,-5),7.8)
	await capture("02_outside",Vector3(-3.3,2.5,-9),Vector3(-2.8,1.5,-3),7.7)
	await capture("03_side",Vector3(-9.5,2.6,1),Vector3(-4,1.5,0),7.7)
	world.construction.refresh_decorations()
	check(world.construction.snapshot()==snapshot,"Rebuilding aperture meshes leaves the original structural records unchanged.")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(snapshot,"",true,true))
	world.construction.restore(saved);world.construction.refresh_decorations();await process_frame
	sample_apertures("JSON restored")
	check(world.construction.snapshot()==saved,"Window restore preserves the exact decoded saved structural records.")
	var modified:Dictionary=snapshot.duplicate(true)
	for entry:Dictionary in modified.walls:
		if float(entry.w)>10:entry.cut=true
	world.construction.restore(modified);world.set_cutaway(true);await process_frame
	var hidden:int=0
	for n:Node3D in windows():
		if is_zero_approx(n.rotation_degrees.y):hidden+=int(not n.visible)
	check(hidden==3,"Cutaway hides unsupported full-height back windows.")
	world.set_cutaway(false);await process_frame
	check(windows().all(func(n:Node3D)->bool:return n.visible),"Raising walls restores complete window frames.")
	var shortened:Dictionary=snapshot.duplicate(true)
	for entry:Dictionary in shortened.walls:
		if float(entry.w)>10:entry.w=1.0;entry.x=-4.25
	world.construction.restore(shortened);world.construction.refresh_decorations();await process_frame
	check(windows().filter(func(n:Node3D)->bool:return is_zero_approx(n.rotation_degrees.y) and n.visible).is_empty(),"A narrowed wall cannot retain a partly unsupported window or clipped hole.")
	check(wall_hit(Vector3(-4.25,1.8,-4.7),Vector3(-4.25,1.8,-5.4)),"User-edited short wall stays solid when no full frame fits.")
	world.construction.restore(snapshot);world.construction.refresh_decorations();await process_frame
	check(windows().all(func(n:Node3D)->bool:return n.visible),"Restoring the original wall shape restores windows.")
	var shifted:Dictionary=snapshot.duplicate(true)
	for entry:Dictionary in shifted.walls:
		if float(entry.w)>10:entry.z-=.03
	world.construction.restore(shifted);await process_frame
	check(windows().filter(func(n:Node3D)->bool:return is_zero_approx(n.rotation_degrees.y) and n.visible).is_empty(),"A nearby parallel wall on another plane cannot support these windows.")
	check(wall_hit(Vector3(-4.25,1.8,-4.7),Vector3(-4.25,1.8,-5.4)),"Misaligned supporting wall keeps solid geometry.")
	world.construction.restore(snapshot);await process_frame
	world.construction.begin("door")
	var door:Dictionary=world.construction.click(Vector3(-4.25,.16,-5.04))
	check(bool(door.get("valid",false)),"Actual door tool accepts a split through the first back window.")
	world.construction.commit(door);world.construction.cancel();await process_frame
	check(not windows()[0].visible,"Splitting the wall through a window removes its unsupported decoration.")
	check(windows()[1].visible and windows()[2].visible,"Other windows remain when their whole frames still fit a split wall.")
	check(not world.construction.point_blocked(Vector2(-4.25,-5.04)),"An intentional door opening remains walkable, unlike a glazed window.")
	world.construction.restore(snapshot);await process_frame
	var remove_id:String=""
	for entry:Dictionary in snapshot.walls:
		if float(entry.w)>10:remove_id=str(entry.id)
	world.construction.remove_wall(remove_id);await process_frame
	check(windows().filter(func(n:Node3D)->bool:return is_zero_approx(n.rotation_degrees.y) and n.visible).is_empty(),"Erasing a supporting wall immediately hides all attached back windows.")
	world.create_public_venue("library",[]);world.set_cutaway(false);await process_frame
	check(windows().size()==3,"Community buildings use the same supported transparent window construction.")
	sample_apertures("Library")
	receipt={"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"scope":"Actual generated wall triangles, logical obstruction, material, JSON construction restore, cutaway and changed wall shape. Static matched views; no walking or named-save claim."}
	var f=FileAccess.open(output_dir.path_join("result.json"),FileAccess.WRITE);f.store_string(JSON.stringify(receipt,"\t"));f.close()
	print("WINDOW CHECKS ",checks," FAILURES ",failures.size());world.free();quit(1 if failures.size() else 0)
