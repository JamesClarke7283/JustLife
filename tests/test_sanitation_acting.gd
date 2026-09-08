extends SceneTree
## Actual queue/event capture; source and save roots must be private.
var app:Node
var checks:int=0
var failures:Array=[]
var samples:Array=[]
var captures:bool=false
var phase:String="baseline"
var ownership:Array=[]
func _initialize()->void:
	var path:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not path.get_file().begins_with("sanitation-acting-") or OS.get_environment("XDG_DATA_HOME")!=path.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=path.path_join("save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Acting checks require a private source and both data guards.");quit(2);return
	captures="--capture" in OS.get_cmdline_user_args()
	if "--after" in OS.get_cmdline_user_args():phase="after"
	run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);print("FAIL: ",label)
func frames(count:int=2)->void:
	for i:int in count:await process_frame
func step(seconds:float)->void:
	var remaining:float=seconds
	while remaining>.000001:
		var part:float=minf(.025,remaining);app._process(part);remaining-=part
func until(done:Callable,seconds:float=100.0)->bool:
	for i:int in int(seconds/.025):
		if done.call():return true
		step(.025)
	return bool(done.call())
func first(kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}
func pose_snapshot(actor:LifeActor)->Dictionary:
	var result:Dictionary={"root":actor.transform,"visual":actor.visual.transform,"joints":{},"feet":{},"hands":{}}
	for name:String in actor._joints:result.joints[name]=actor._joints[name].transform
	for side:String in actor._leg_rest:result.feet[side]=actor._leg_rest[side].shoe.global_transform
	for side:String in actor._arm_rest:result.hands[side]=actor._joints["Forearm_"+side].to_global(actor._palm_offset(side))
	return result
func sample(label:String)->void:
	var actor:LifeActor=app.player
	var record:Dictionary={"label":label,"profile":actor.profile,"action":app.sim.get_current_action().duplicate(true),"pose":pose_snapshot(actor),"anchor":actor._activity_anchor.duplicate(true),"time":actor._action_time}
	var max_foot_error:float=0.0
	if not actor._activity_anchor.is_empty():
		for side:String in actor._leg_rest:
			var expected:Vector3=actor._activity_anchor.position+Basis(Vector3.UP,float(actor._activity_anchor.yaw))*(Vector3(actor._leg_rest[side].foot)*actor.visual.scale)
			max_foot_error=maxf(max_foot_error,expected.distance_to(actor._leg_rest[side].shoe.global_position))
	record.foot_error=max_foot_error;samples.append(record)
	if phase=="after" and label.contains("pot_"):check(max_foot_error<.012,label+" retains neutral floor contacts within 12mm.")
	if captures:
		await frames(3);await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("user://acting/"+phase+"_"+label+".png")
func run()->void:
	seed(875193)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://acting"))
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	for config:Dictionary in [{"name":"Alex Rivera","frame":0},{"name":"Jamie Rowan","frame":1},{"name":"River Young","frame":0,"age_stage":"child"},{"name":"Morgan Woods","frame":1,"age_stage":"elder"}]:
		app.household_profiles=[config];app.start_household();await frames(3)
		for member:Dictionary in app.household.members:
			member.sim.autonomy=false
			for key:String in member.sim.needs:member.sim.needs[key]=80.0
		app.household.set_speed(1)
		var label:String=str(config.get("age_stage","adult"))+"_"+str(config.frame)
		var plant:Dictionary=first("plant")
		app.sim.needs.bladder=10.0;app.queue_interaction(plant,"plant_wee")
		check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),label+" reaches the actual pot through navigation.")
		app.world.camera_target=(app.player.position+plant.node.position)*.5+Vector3(0,.55,0);app.world.camera.size=4.4;app.world.camera_angle=2.55;app.world.update_camera()
		step(.22);await sample(label+"_pot_look")
		step(.38);await sample(label+"_pot_brace")
		app.world.camera_angle=1.7;app.world.update_camera();await sample(label+"_pot_side")
		app.world.camera_angle=2.55;app.world.update_camera()
		var frozen:Dictionary=pose_snapshot(app.player)
		app.household.set_speed(0);step(.5)
		check(pose_snapshot(app.player)==frozen,label+" pot pose freezes exactly while paused.")
		app.household.set_speed(1);step(.55);await sample(label+"_pot_release")
		app.queue_interaction(first("bookshelf"),"read")
		app.cancel_current_action()
		check(app.sim.action_queue.size()==1 and str(app.sim.get_current_action().id)=="read",label+" cancellation preserves the later read instruction.")
		app.cancel_current_action();app.on_ground_clicked(Vector3(-2,.16,2))
		check(until(func()->bool:return not app.walk_only),label+" walks to open floor before the accident.")
		step(.4)
		app.world.camera_target=app.player.position+Vector3(0,.55,0);app.world.camera.size=4.4;app.world.camera_angle=2.55;app.world.update_camera()
		app.sim.needs.bladder=0.0;app.sim.bladder_grace=9.99;step(.025)
		check(app.household.sanitation.puddles.size()==1,label+" receives an actual model accident callback.")
		var at:Vector3=app.player.position
		step(.2);await sample(label+"_accident_start")
		step(.70);await sample(label+"_accident_react")
		frozen=pose_snapshot(app.player);app.household.set_speed(0);step(.5)
		check(pose_snapshot(app.player)==frozen,label+" accident pose freezes exactly while paused.")
		app.household.set_speed(1);step(.80);await sample(label+"_accident_settle")
		check(app.player.position==at and app.sim.action_queue.is_empty(),label+" reaction does not move the actor root or create an action.")
	if phase=="after":await ownership_controls()
	var result:Dictionary={"ownership":ownership,"checks":checks,"failures":failures,"samples":samples,"phase":phase}
	var file:=FileAccess.open("user://acting/"+phase+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t",true,true));file.close()
	print("Acting: ",checks," checks, ",failures.size()," failures.")
	app.queue_free();await frames(4);await create_timer(.15,true,false,true).timeout;quit(0 if failures.is_empty() else 1)

func trigger_accident()->void:
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=9.99;step(.025)
func ownership_controls()->void:
	app.household_profiles=[{"name":"Casey Wells","frame":1}];app.start_household();await frames(3)
	app.household.set_speed(1);app.sim.autonomy=false
	for key:String in app.sim.needs:app.sim.needs[key]=80.0
	app.queue_interaction(first("stove"),"cook")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),"Ownership control uses an actual paid cooking action.")
	step(.4)
	var cooking:Dictionary=app.sim.get_current_action();var paid:int=app.household.funds
	app.queue_interaction(first("bookshelf"),"read");trigger_accident()
	check(app.player._accident_time<0 and not app.player._accident_visible,"Accident during paid cooking immediately discards the free-hand gesture.")
	check(is_same(app.sim.get_current_action(),cooking) and bool(cooking.paid) and app.household.funds==paid,"Cooking retains its exact paid action and ingredient charge.")
	check(app.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"Cooking accident keeps its later read instruction.")
	ownership.append({"stage":"paid_cook","pose":pose_snapshot(app.player),"recipe":app.player.cooking_presentation.duplicate(true)})
	check(until(func()->bool:return not app.household.meals.carried_by("player").is_empty()),"Ownership control reaches a real held serving dish.")
	var dish:Dictionary=app.household.meals.carried_by("player");var dish_id:String=dish.id
	trigger_accident()
	check(app.player._accident_time<0 and not app.player._accident_visible,"Accident with actual carried food cannot pose either busy hand.")
	check(str(app.household.meals.carried_by("player").get("id",""))==dish_id,"Accident preserves exact held-dish identity and owner.")
	ownership.append({"stage":"actual_carried_dish","pose":pose_snapshot(app.player),"dish":dish.duplicate(true)})
	check(until(func()->bool:return app.household.meals.carried_by("player").is_empty()),"Original food route places the held dish safely.")
	check(str(app.household.meals.batch(dish_id).storage)=="surface" and app.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"Food and later instruction survive the entire cooking and serving flow.")
	while not app.sim.action_queue.is_empty():app.cancel_current_action()
	app.on_ground_clicked(Vector3(0,.16,8.5));step(.05)
	var before:Vector3=app.player.position;trigger_accident()
	check(app.walk_only and app.player.position.distance_to(before)>0 and app.player._accident_time<0 and not app.player._accident_visible,"Accident while actually walking retains movement and discards the gesture.")
	check(until(func()->bool:return not app.walk_only),"The original walking route reaches its destination.")
	step(.4);check(app.player._accident_time<0 and not app.player._accident_visible,"An accident suppressed during movement never replays after arrival.")
	trigger_accident();step(.3)
	check(app.player._accident_visible,"An actual idle accident receives the short visible reaction.")
	app.on_ground_clicked(Vector3(1.8,.16,8.5));step(.05)
	check(not app.player._accident_visible and app.player._accident_time<0,"A new walking command interrupts the presentation immediately.")
	check(until(func()->bool:return not app.walk_only),"Interrupting an idle reaction preserves the new movement destination.")
	var puddle:Dictionary=app.household.sanitation.puddles[0]
	app.queue_interaction(app._find_item(puddle.id),"mop_puddle")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),"Ownership control reaches an actual cleanup action.")
	step(.4);var cleanup:Dictionary=app.sim.get_current_action();trigger_accident()
	check(is_same(app.sim.get_current_action(),cleanup) and app.player._mop.visible and not app.player._accident_visible,"A cleanup accident keeps the original mop and active instruction.")
	step(.3)
	var worst:float=0.0
	for side:String in ["L","R"]:
		var grip:Vector3=Vector3(0,.96,-.287) if side=="L" else Vector3(0,.68,-.198)
		var hand:Vector3=app.player._joints["Forearm_"+side].to_global(app.player._grip_offset(side))
		worst=maxf(worst,hand.distance_to(app.player._mop.to_global(grip)))
	# Diagnostic only: the released mop lower-hand reach is a known baseline gap.
	ownership.append({"stage":"actual_mop","pose":pose_snapshot(app.player),"contact_error":worst})
