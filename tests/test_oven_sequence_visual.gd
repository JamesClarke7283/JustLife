extends SceneTree
var app:Node
var a:LifeActor
var checks:int=0
var failures:Array[String]=[]
var samples:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func capture(name:String)->void:
	for i:int in range(3):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://oven_sequence/"+name+".png")
func segment_box(start:Vector3,finish:Vector3,box:AABB)->bool:
	var direction:Vector3=finish-start
	var enter:float=0.0;var leave:float=1.0
	for axis:int in range(3):
		if absf(direction[axis])<.000001:
			if start[axis]<box.position[axis] or start[axis]>box.end[axis]:return false
		else:
			var lo:float=(box.position[axis]-start[axis])/direction[axis]
			var hi:float=(box.end[axis]-start[axis])/direction[axis]
			enter=maxf(enter,minf(lo,hi));leave=minf(leave,maxf(lo,hi))
			if enter>leave:return false
	return true
func point_box_distance_squared(point:Vector3,box:AABB)->float:
	return point.distance_squared_to(point.max(box.position).min(box.end))
func segment_box_distance_squared(start:Vector3,finish:Vector3,box:AABB)->float:
	if segment_box(start,finish,box):return 0.0
	# Distance to a convex box is convex along a line. Minimize the actual
	# squared Euclidean distance; growing an AABB gives false corner hits.
	var lo:float=0.0;var hi:float=1.0
	for iteration:int in range(36):
		var left:float=(2*lo+hi)/3;var right:float=(lo+2*hi)/3
		if point_box_distance_squared(start.lerp(finish,left),box)<point_box_distance_squared(start.lerp(finish,right),box):hi=right
		else:lo=left
	return point_box_distance_squared(start.lerp(finish,(lo+hi)*.5),box)
func padded_segment_hits(start:Vector3,finish:Vector3,radius:float,meshes:Array[Node])->Array[String]:
	var hits:Array[String]=[]
	for mesh:MeshInstance3D in meshes:
		var scale:Vector3=mesh.global_basis.get_scale().abs()
		var local_radius:float=radius/minf(scale.x,minf(scale.y,scale.z))
		if segment_box_distance_squared(mesh.to_local(start),mesh.to_local(finish),mesh.get_aabb())<local_radius*local_radius:hits.append(str(mesh.name))
	return hits
func volume_clearance(oven:Node3D,metric:Dictionary,phase:String)->void:
	var door:Node3D=oven.find_child("OvenDoor",true,false)
	var door_meshes:Array[Node]=door.find_children("*","MeshInstance3D",true,false)
	metric.door_limb_hits={}
	for side:String in a._leg_rest:
		var rest:Dictionary=a._leg_rest[side]
		var hip:Vector3=a._joints["Leg_"+side].global_position
		var knee:Vector3=a._joints["Shin_"+side].global_position
		var ankle:Vector3=a._joints["Shin_"+side].to_global(rest.lower)
		var thigh_hits:Array[String]=padded_segment_hits(hip,knee,.085*a.visual.scale.x,door_meshes)
		var shin_hits:Array[String]=padded_segment_hits(knee,ankle,.060*a.visual.scale.x,door_meshes)
		metric.door_limb_hits[side]={"thigh":thigh_hits,"shin":shin_hits}
		check(thigh_hits.is_empty() and shin_hits.is_empty(),phase+" "+side+" padded thigh/shin segments clear every real door mesh")
	var front_limit:float=-INF
	for mesh:MeshInstance3D in oven.find_children("*","MeshInstance3D",true,false):
		if str(mesh.name).begins_with("Control panel") or str(mesh.name).begins_with("Cooktop") or str(mesh.name).begins_with("Dial"):
			for corner:int in range(8):front_limit=maxf(front_limit,oven.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(corner))).z)
	var head_front:float=INF
	for mesh:MeshInstance3D in a._joints.Head.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree():continue
		for corner:int in range(8):head_front=minf(head_front,oven.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(corner))).z)
	metric.head_control_gap=head_front-front_limit
	check(head_front-front_limit>.025,phase+" all visible head/hair bounds clear the control/cooktop front by25mm")
	var hip_center:Vector3=(a._joints.Leg_L.global_position+a._joints.Leg_R.global_position)*.5
	var shoulders:Vector3=(a._joints.Arm_L.global_position+a._joints.Arm_R.global_position)*.5
	var tray_meshes:Array[Node]=a._baking_tray.find_children("*","MeshInstance3D",true,false)
	metric.body={"hips":str(hip_center),"shoulders":str(shoulders),"radius":.13*a.visual.scale.x,"tray":str(a._baking_tray.global_position)}
	var torso_hits:Array[String]=padded_segment_hits(hip_center,shoulders,.13*a.visual.scale.x,tray_meshes)
	metric.tray_torso_hits=torso_hits
	check(torso_hits.is_empty(),phase+" tray clears padded hip-to-shoulder torso segment")
	var head_hits:Array[String]=[]
	for head_mesh:MeshInstance3D in a._joints.Head.find_children("*","MeshInstance3D",true,false):
		if not head_mesh.is_visible_in_tree():continue
		for tray_mesh:MeshInstance3D in tray_meshes:
			var local_tray:AABB=head_mesh.global_transform.affine_inverse()*tray_mesh.global_transform*tray_mesh.get_aabb()
			if local_tray.intersects(head_mesh.get_aabb()):head_hits.append(str(head_mesh.name))
	metric.tray_head_hits=head_hits
	check(head_hits.is_empty(),phase+" every visible head/hair mesh bound clears dish and food bounds")
func run()->void:
	DirAccess.make_dir_recursive_absolute("user://oven_sequence")
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await process_frame;app.set_sound(false)
	var fixture_profile:Dictionary={"name":"Mara Vale","age_stage":"adult","frame":0,"hair":1,"outfit":0,"top_color":"7396a9","bottom_color":"e0d5bd","skin_color":"d9a17d"}
	var variants:Dictionary={"short_adult":{"height_scale":.93,"body_scale":.85},"broad_adult":{"frame":1,"height_scale":1.08,"body_scale":1.15},"short_teen":{"age_stage":"teen","height_scale":.93,"body_scale":.85},"broad_elder":{"age_stage":"elder","frame":1,"height_scale":1.08,"body_scale":1.15}}
	var arguments:PackedStringArray=OS.get_cmdline_user_args()
	var variant:String=arguments[0] if arguments.size()>0 else "default"
	var fixture_rotation:float=float(arguments[1]) if arguments.size()>1 else 0.0
	fixture_profile.merge(variants.get(variant,{}),true)
	app.household_profiles=[fixture_profile]
	app.start_household();app.set_process(false)
	app.setup_live([{"id":"stove","kind":"stove","x":0,"z":0,"rotation":fixture_rotation}]);app.ui.hide();app.overlay.hide()
	app.world.set_process(false);app.world.daylight(700)
	for wall:Node3D in app.world.construction.wall_nodes.values():wall.hide()
	for tree:Node3D in app.world.landscape_trees:tree.hide()
	for person:LifeActor in app.world.actors.values():person.hide();person.set_selected(false);person.voice_enabled=false
	a=app.world.actors.player;a.show()
	app.world.camera_target=Basis(Vector3.UP,deg_to_rad(fixture_rotation))*Vector3(0,.95,.53);app.world.camera.size=2.6;app.world.camera_angle=1.57+deg_to_rad(fixture_rotation);app.world.camera_elevation=.34;app.world.update_camera()
	var entry:Dictionary=app._find_item("stove");var oven:Node3D=entry.node
	var at:Vector3=app.world.oven_approach(entry)
	var anchor:Dictionary=app.world.activity_anchor(entry,"cook",a.get_body_landmarks().merged({"recipe":"harvest_bake","cooking_position":at}))
	a.position=at;a.rotation.y=anchor.yaw;a.set_activity_anchor(anchor.position,anchor.yaw,"standing","cook",anchor)
	var root_before:Transform3D=a.transform
	var pose_samples:Array[float]=[]
	for phase_entry:Array in LifeOvenSequence.PHASES:
		if str(phase_entry[0]) in ["open_load","pull_load","load","push_load","close_load","pull_unload","unload","push_unload","close_unload"]:
			pose_samples.append(lerpf(float(phase_entry[1]),float(phase_entry[2]),.80))
			if str(phase_entry[0]) in ["load","unload"]:pose_samples.append(lerpf(float(phase_entry[1]),float(phase_entry[2]),.999))
	if arguments.size()>2:pose_samples=[float(arguments[2])]
	for p:float in pose_samples:
		a.cooking_presentation={"recipe":"harvest_bake","progress":p,"oven":oven}
		for i:int in range(180):a.animate(1.0/60.0,1.0,false,"cook")
		var phase:String=LifeOvenSequence.phase(p)
		await capture(phase+"_%03d_side"%roundi(p*1000))
		app.world.camera_angle=.55+deg_to_rad(fixture_rotation);app.world.update_camera();await capture(phase+"_%03d_front"%roundi(p*1000));app.world.camera_angle=1.57+deg_to_rad(fixture_rotation);app.world.update_camera()
		var metric:Dictionary={"progress":p,"phase":phase,"tray":str(a._baking_tray.global_position),"hands":{},"ankles":{},"knees":{}}
		var expected:Dictionary={}
		if phase in ["load","unload"] and LifeOvenSequence.fraction(p,phase)>=.50:
			expected={"L":a._baking_tray.to_global(Vector3(-.2395,.046,0)),"R":a._baking_tray.to_global(Vector3(.2395,.046,0))}
		elif phase in ["pull_load","push_load","pull_unload","push_unload"] and LifeOvenSequence.fraction(p,phase)>=.50:
			expected.R=oven.find_child("OvenRackGrip",true,false).global_position
			if phase in ["pull_load","push_unload"]:expected.L=a._baking_tray.to_global(LifeOvenSequence.support_offset(p))
		elif phase in ["open_load","close_load","open_unload","close_unload"]:
			expected.R=oven.find_child("OvenHandleGrip",true,false).global_position
			if phase in ["open_load","close_unload"]:expected.L=a._baking_tray.to_global(LifeOvenSequence.support_offset(p))
		for side:String in expected:
			var palm:Vector3=a._joints["Forearm_"+side].to_global(a._grip_offset(side))
			var error:float=palm.distance_to(expected[side]);metric.hands[side]=error
			check(error<.025,phase+" "+side+" hand reaches actual handle/support within25mm")
		for side:String in a._leg_rest:
			var rest:Dictionary=a._leg_rest[side]
			var desired:Vector3=anchor.position+Basis(Vector3.UP,float(anchor.yaw))*(Vector3(rest.foot)*a.visual.scale)
			var actual:Vector3=a._joints["Shin_"+side].to_global(rest.lower)
			metric.ankles[side]=actual.distance_to(desired)
			var knee:Vector3=a._joints["Shin_"+side].global_position
			metric.knees[side]=str(knee)
			check(knee.y>at.y+.08,phase+" "+side+" knee stays above the floor")
			var shoe:Node3D=rest.shoe
			check(shoe.global_basis.y.normalized().dot(Vector3.UP)>.999,phase+" "+side+" shoe soles remain horizontal")
			var sole_min:float=INF
			for mesh:MeshInstance3D in shoe.find_children("Shoes_Sole*","MeshInstance3D",true,false):
				for corner:int in range(8):sole_min=minf(sole_min,(mesh.global_transform*mesh.get_aabb().get_endpoint(corner)).y)
			metric["sole_min_"+side]=sole_min
			check(sole_min>=at.y-.002 and sole_min<at.y+.015,phase+" "+side+" actual sole bounds retain floor support")
			check(actual.distance_to(desired)<.015,phase+" "+side+" ankle remains near its planted destination")
		volume_clearance(oven,metric,phase)
		check(a.transform==root_before,phase+" preserves actual navigation root")
		check(a._baking_tray.visible,phase+" has exactly its cooking tray visible")
		var paused_tray:Transform3D=a._baking_tray.global_transform
		var paused_hand:Transform3D=a._joints.Forearm_R.global_transform
		a.animate(.1,0,false,"cook")
		check(a._baking_tray.global_transform==paused_tray and a._joints.Forearm_R.global_transform==paused_hand,phase+" freezes at pause")
		samples.append(metric)
	var out:=FileAccess.open("user://oven_sequence/report.json",FileAccess.WRITE);out.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"variant":variant,"profile":fixture_profile,"rotation":fixture_rotation,"method":"Directed final imported actor, stove and tray; fixed progress poses, not public gameplay or continuous contact evidence."},"  "));out.close()
	print("OVEN_SEQUENCE ",checks," checks, ",failures.size()," failures")
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
