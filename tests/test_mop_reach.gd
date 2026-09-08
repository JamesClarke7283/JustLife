extends "res://tests/test_sanitation_acting.gd"
var contact_samples:Array=[]
func _initialize()->void:
	var path:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not path.get_file().begins_with("sanitation-mop-") or OS.get_environment("XDG_DATA_HOME")!=path.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=path.path_join("save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Mop checks require private source and both data guards.");quit(2);return
	captures="--capture" in OS.get_cmdline_user_args();run.call_deferred()
func run()->void:
	seed(875193);app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	for config:Dictionary in [{"name":"Alex Rivera","frame":0},{"name":"Jamie Rowan","frame":1},{"name":"Small frame","frame":0,"body_scale":.85,"height_scale":.93},{"name":"Large frame","frame":1,"body_scale":1.15,"height_scale":1.08},{"name":"River Young","frame":0,"age_stage":"child"},{"name":"Quinn Young","frame":1,"age_stage":"child"},{"name":"Morgan Woods","frame":0,"age_stage":"elder"},{"name":"Jules Woods","frame":1,"age_stage":"elder"},{"name":"Small broad adult","frame":1,"body_scale":.85,"height_scale":.93},{"name":"Large narrow adult","frame":0,"body_scale":1.15,"height_scale":1.08},{"name":"Small child","frame":1,"age_stage":"child","body_scale":.85,"height_scale":.93},{"name":"Large child","frame":0,"age_stage":"child","body_scale":1.15,"height_scale":1.08},{"name":"Small elder","frame":1,"age_stage":"elder","body_scale":.85,"height_scale":.93},{"name":"Large elder","frame":0,"age_stage":"elder","body_scale":1.15,"height_scale":1.08}]:
		app.household_profiles=[config];app.start_household();await frames(3);app.sim.autonomy=false;app.household.set_speed(1)
		for key:String in app.sim.needs:app.sim.needs[key]=80.0
		app.on_ground_clicked(Vector3(-2,.16,2));check(until(func()->bool:return not app.walk_only),str(config.name)+" walks to the real accident site.")
		trigger_accident();step(.1)
		var puddle:Dictionary=app.household.sanitation.puddles[0]
		app.queue_interaction(app._find_item(puddle.id),"mop_puddle")
		check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),str(config.name)+" reaches the actual cleanup anchor.")
		var worst:float=0.0;var feet:float=0.0;var left:float=0.0;var right:float=0.0;var walking_frames:int=0;var held_frames:int=0
		for i:int in 240:
			if str(app.sim.get_current_action().get("id",""))!="mop_puddle":break
			if app.player._motion_action=="walk":
				walking_frames+=1;check(not app.player._mop.visible,"The final approach frame keeps the walking pose and hides the unheld mop.");step(1.0/60.0);continue
			held_frames+=1
			for side:String in ["L","R"]:
				var grip:Vector3=Vector3(0,.96,-.287) if side=="L" else Vector3(0,.68,-.198)
				var hand:Vector3=app.player._joints["Forearm_"+side].to_global(app.player._grip_offset(side))
				var error:float=hand.distance_to(app.player._mop.to_global(grip));worst=maxf(worst,error)
				if side=="L":left=maxf(left,error)
				else:right=maxf(right,error)
				var rest:Dictionary=app.player._leg_rest[side]
				var target:Vector3=app.player._activity_anchor.position+Basis(Vector3.UP,float(app.player._activity_anchor.yaw))*(Vector3(rest.foot)*app.player.visual.scale)
				feet=maxf(feet,target.distance_to(rest.shoe.global_position))
			if i==20 and captures:
				app.world.camera_target=app.player.position+Vector3(0,.45,0);app.world.camera.size=4.4;app.world.camera_angle=2.5;app.world.update_camera();await frames(3);await RenderingServer.frame_post_draw
				get_root().get_texture().get_image().save_png("user://mop_"+str(config.name).replace(" ","_")+".png")
			if i==35:
				app.household.set_speed(0);var frozen:Dictionary=pose_snapshot(app.player);step(.4);check(frozen==pose_snapshot(app.player),str(config.name)+" held midpoint freezes exactly.");app.household.set_speed(1)
			step(1.0/60.0)
		check(walking_frames<=1 and held_frames>50,str(config.name)+" visibly holds the mop immediately after the last approach frame.")
		check(worst<.025,str(config.name)+" holds both unchanged shaft contacts within 25mm throughout the actual cleanup.")
		check(feet<.012,str(config.name)+" keeps both original ankle contacts within 12mm.")
		contact_samples.append({"profile":app.player.profile,"hand_max":worst,"left_max":left,"right_max":right,"foot_max":feet,"walking_frames":walking_frames,"held_frames":held_frames});print(config.name," hands=",worst," L=",left," R=",right," feet=",feet)
		check(str(app.sim.get_current_action().get("id",""))!="mop_puddle" and app.household.sanitation.find(str(puddle.id)).is_empty() and not app.player._mop.visible,str(config.name)+" reaches actual cleanup completion and releases the mop after all held frames are measured.")
	var file:=FileAccess.open("user://mop_reach.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":contact_samples},"\t",true,true));file.close()
	print("Mop reach: ",checks," checks, ",failures.size()," failures.");app.queue_free();await frames(4);await create_timer(.15,true,false,true).timeout;quit(0 if failures.is_empty() else 1)
