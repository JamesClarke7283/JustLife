extends SceneTree
## Actual wall-triangle/material controls and matched-camera scene captures.
const Building=preload("res://scripts/building_state.gd")
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
		if not n.visible:continue
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
func v2_controls()->void:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	for level:int in [0,1]:
		for side:int in [-1,1]:
			state.walls.append({"id":("upper_" if level else "")+("north" if side<0 else "south"),"level":level,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":false,"material":"eae7d7"})
	var loaded:Dictionary=world.load_home([
		{"id":"ground_shelf","kind":"bookshelf","x":-1.25,"z":-3.5,"rotation":180.0,"level":0},
		{"id":"upper_shelf","kind":"bookshelf","x":-1.25,"z":-3.5,"rotation":180.0,"level":1},state]);await process_frame
	check(bool(loaded.ok),"A canonical two-floor home loads with unchanged support records.")
	if not bool(loaded.ok):return
	world.set_cutaway(false)
	var before:Dictionary=world.construction.snapshot().duplicate(true)
	var generation:int=world.lot_navigation.generation
	world.window_panel(Vector3(-1.25,1.78,-4.915),false)
	var lower:Node3D=world.house.get_child(world.house.get_child_count()-1)
	world.window_panel(Vector3(-1.25,4.78,-4.915),false)
	var upper:Node3D=world.house.get_child(world.house.get_child_count()-1)
	world.construction.refresh_decorations();await process_frame
	check(lower.visible and upper.visible,"Ground and upper windows each use their own full-height support.")
	check(windows().filter(func(n:Node3D)->bool:return n.visible).size()==2,"Unrelated original windows cannot attach to the nearby new wall plane.")
	check(lower.get_child(0).layers==world.VIEW_GROUND and upper.get_child(0).layers==world.VIEW_UPPER,"Window glass and frames inherit the floor's actual rendering layer.")
	sample_apertures("Two-floor")
	check(wall_hit(Vector3(-1.25,2.9,-4.7),Vector3(-1.25,2.9,-5.4)),"Bearing wall rim above the window still supports the upper slab.")
	check(not world.lot_navigation.point_clear(0,Vector3(-1.25,.16,-5)) and not world.lot_navigation.point_clear(1,Vector3(-1.25,3.16,-5)),"Both real navigation floors keep glazed wall cells blocked.")
	check(world.construction.snapshot()==before and world.lot_navigation.generation==generation,"Visual openings leave canonical support, floor and navigation generation exactly unchanged.")
	world.set_view_level(0)
	check((world.camera.cull_mask & upper.get_child(0).layers)==0 and (world.camera.cull_mask & lower.get_child(0).layers)!=0,"Ground camera excludes upper glass and frame layers.")
	world.set_view_level(1)
	check((world.camera.cull_mask & upper.get_child(0).layers)!=0,"Upper view includes the upper window without moving structural records.")
	await capture("04_two_floor_outside",Vector3(-2.5,5.5,-10),Vector3(-1.25,3,-4),9.0)
	var saved:Dictionary=JSON.parse_string(JSON.stringify(before,"",true,true))
	world.construction.restore(saved);await process_frame
	check(world.construction.last_error.is_empty() and world.construction.snapshot()==saved,"Canonical JSON restore retains the exact decoded geometry/support payload.")
	check(lower.visible and upper.visible,"Both floor apertures and frames recover after canonical restore.")
	var lowered:Dictionary=before.duplicate(true)
	for entry:Dictionary in lowered.walls:
		if int(entry.level)==1:entry.cut=true
	world.construction.restore(lowered);world.set_cutaway(true);await process_frame
	check(lower.visible and not upper.visible,"Upper cutaway hides only its unsupported window and leaves ground glass visible.")
	world.set_cutaway(false);await process_frame
	check(lower.visible and upper.visible,"Full walls restore the same window nodes on both floors.")
	check(wall_hit(Vector3(-2.7,4.8,-4.7),Vector3(-2.7,4.8,-5.4)),"Upper wall surrounding the opening remains opaque geometry.")

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
	var joined:Dictionary=snapshot.duplicate(true)
	var split:Array=[]
	for entry:Dictionary in joined.walls:
		if float(entry.w)<=10:split.append(entry);continue
		var left:Dictionary=entry.duplicate(true);left.id=str(entry.id)+"_left";left.x=-3.675;left.w=4.85
		var right:Dictionary=entry.duplicate(true);right.id=str(entry.id)+"_right";right.x=2.425;right.w=7.35
		split.append(left);split.append(right)
	joined.walls=split
	world.construction.restore(joined);await process_frame
	check(windows().all(func(n:Node3D)->bool:return n.visible),"Collinear joined segments retain a window crossing their closed joint.")
	sample_apertures("Collinear joined")
	check(not wall_hit(Vector3(-1.25,2.1,-4.7),Vector3(-1.25,2.1,-5.4)),"The wall joint does not leave an opaque stud through the aperture.")
	var gapped:Dictionary=joined.duplicate(true)
	for entry:Dictionary in gapped.walls:
		if str(entry.id).ends_with("_left"):entry.x-=.01;entry.w-=.02
		if str(entry.id).ends_with("_right"):entry.x+=.01;entry.w-=.02
	world.construction.restore(gapped);await process_frame
	check(not windows()[1].visible,"A real gap between wall segments hides the crossing window.")
	check(wall_hit(Vector3(-1.56,2.1,-4.7),Vector3(-1.56,2.1,-5.4)),"A gap-invalidated frame cannot leave a partial carved opening in either wall.")
	world.create_public_venue("library",[]);world.set_cutaway(false);await process_frame
	check(windows().size()==3,"Community buildings use the same supported transparent window construction.")
	sample_apertures("Library")
	await v2_controls()
	receipt={"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"scope":"Actual generated wall triangles, materials, obstruction, legacy and canonical two-floor JSON restore, real door split/removal, cutaway, support rim and camera layers. Static matched views; no walking or named-save claim."}
	var f=FileAccess.open(output_dir.path_join("result.json"),FileAccess.WRITE);f.store_string(JSON.stringify(receipt,"\t"));f.close()
	print("WINDOW CHECKS ",checks," FAILURES ",failures.size());world.free();quit(1 if failures.size() else 0)
