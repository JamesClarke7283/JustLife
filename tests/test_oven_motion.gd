extends "res://tests/test_oven_sequence_visual.gd"
var stage_samples:Array=[]
var frame_count:int=0
var max_hand_step:float=0.0
var tray_obstacles:Array[Node]=[]
var obstacle_hits:Dictionary={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):failures.append(label);push_error(label)
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
	app.world.camera_target=Basis(Vector3.UP,deg_to_rad(fixture_rotation))*Vector3(0,.95,.53);app.world.camera.size=2.6;app.world.camera_angle=.80+deg_to_rad(fixture_rotation);app.world.camera_elevation=.34;app.world.update_camera()
	var entry:Dictionary=app._find_item("stove");var oven:Node3D=entry.node
	for mesh:MeshInstance3D in oven.find_children("*","MeshInstance3D",true,false):
		if str(mesh.name).begins_with("Control panel") or str(mesh.name).begins_with("Cooktop") or str(mesh.name).begins_with("Dial") or str(mesh.name).begins_with("Enamel side"):tray_obstacles.append(mesh)
	tray_obstacles.append_array(oven.find_child("OvenDoor",true,false).find_children("*","MeshInstance3D",true,false))
	var at:Vector3=app.world.oven_approach(entry)
	var anchor:Dictionary=app.world.activity_anchor(entry,"cook",a.get_body_landmarks().merged({"recipe":"harvest_bake","cooking_position":at}))
	a.position=at;a.rotation.y=anchor.yaw;a.set_activity_anchor(anchor.position,anchor.yaw,"standing","cook",anchor)
	var root_before:Transform3D=a.transform
	var previous:Dictionary={};var previous_phase:String=""
	var analytic_box:AABB=AABB(Vector3(-1,-1,-1),Vector3.ONE*2)
	check(is_equal_approx(segment_box_distance_squared(Vector3(1.2,1.2,0),Vector3(1.2,1.2,.5),analytic_box),.08),"Capsule metric correctly excludes inflated-box corner false positives")
	check(is_zero_approx(segment_box_distance_squared(Vector3(0,0,0),Vector3(2,2,2),analytic_box)),"Capsule metric retains true box penetration, including rejected r5 knee case")
	for frame:int in range(701):
		var p:float=float(frame)/700.0
		a.cooking_presentation={"recipe":"harvest_bake","progress":p,"oven":oven}
		a.animate(1.0/60.0,1.0,false,"cook")
		var phase:String=LifeOvenSequence.phase(p);var part:float=LifeOvenSequence.fraction(p,phase)
		var metric:Dictionary={"progress":p,"phase":phase}
		var expected:Dictionary={}
		if phase in ["load","unload"] and part>=.50:
			expected={"L":a._baking_tray.to_global(Vector3(-.2395,.046,0)),"R":a._baking_tray.to_global(Vector3(.2395,.046,0))}
		elif phase in ["pull_load","push_load","pull_unload","push_unload"] and part>=.50:
			expected.R=oven.find_child("OvenRackGrip",true,false).global_position
		elif phase in ["open_load","open_unload"] or (phase in ["close_load","close_unload"] and part>=.50):
			expected.R=oven.find_child("OvenHandleGrip",true,false).global_position
		for side:String in ["L","R"]:
			var palm:Vector3=a._joints["Forearm_"+side].to_global(a._grip_offset(side))
			if expected.has(side):
				var error:float=palm.distance_to(expected[side])
				if error>=.025:stage_samples.append({"bad_contact":side,"phase":phase,"p":p,"error":error})
				check(error<.025,phase+" "+side+" contact stays within25mm while the held part moves")
			if previous.has(side):
				var step:float=palm.distance_to(previous[side]);max_hand_step=maxf(max_hand_step,step)
				if step>=.075:stage_samples.append({"bad_step":side,"phase":phase,"p":p,"step":step})
				check(step<.075,previous_phase+"->"+phase+" "+side+" palm moves less than75mm per normal-speed frame")
			previous[side]=palm
		var tray_hits:Array[String]=[]
		for mesh:MeshInstance3D in a._baking_tray.find_children("*","MeshInstance3D",true,false):
			for obstacle:MeshInstance3D in tray_obstacles:
				var box:AABB=obstacle.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
				if box.intersects(obstacle.get_aabb()):tray_hits.append(str(obstacle.name))
		if not tray_hits.is_empty():obstacle_hits[phase+"_%03d"%frame]=tray_hits
		check(tray_hits.is_empty(),phase+" full-size tray/food bounds clear controls/cooktop/sides and every moving door mesh")
		volume_clearance(oven,metric,phase)
		if not metric.tray_torso_hits.is_empty():stage_samples.append(metric)
		check(a.transform==root_before,phase+" keeps navigation root")
		check(absf(a._baking_tray.global_basis.y.dot(Vector3.UP)-1.0)<.0001,phase+" full-size tray stays level")
		for side:String in a._leg_rest:
			var rest:Dictionary=a._leg_rest[side]
			var target:Vector3=anchor.position+Basis(Vector3.UP,float(anchor.yaw))*(Vector3(rest.foot)*a.visual.scale)
			check(a._joints["Shin_"+side].to_global(rest.lower).distance_to(target)<.015,phase+" "+side+" ankle stays planted")
			check(rest.shoe.global_basis.y.normalized().dot(Vector3.UP)>.999,phase+" "+side+" sole stays level")
		if phase!=previous_phase:
			stage_samples.append(metric)
			await capture("motion_%03d_"%frame+phase)
		previous_phase=phase;frame_count+=1
		await process_frame
	var out:=FileAccess.open("user://oven_sequence/motion_report.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frame_count,"variant":variant,"profile":fixture_profile,"rotation":fixture_rotation,"max_hand_step":max_hand_step,"phase_samples":stage_samples,"obstacle_hits":obstacle_hits,"method":"Directed continuous persisted-progress trajectory, 701 normal-speed steps over70 game minutes. Real imported default adult/appliance/dish. Conservative mesh bounds and padded limb/torso proxies. No public or fresh-process gameplay claim."},"  "));out.close()
	print("OVEN_MOTION ",checks," checks, ",failures.size()," distinct failures; max_hand_step=",max_hand_step)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
