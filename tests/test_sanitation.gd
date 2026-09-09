extends SceneTree
# Load the actual scene before static save-library references in this test graph.
const MainScene=preload("res://scenes/main.tscn")
var app:Node
var checks:int=0
var failures:Array=[]
var captures:bool=false
var completed:Array=[]
var pot_slot:String=""
func _initialize()->void:
	var path:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not path.get_file().begins_with("justlife-sanitation-") or OS.get_environment("XDG_DATA_HOME")!=path.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=path.path_join("save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Sanitation checks require a private source, XDG_DATA_HOME and JUSTLIFE_DATA_DIR.");quit(2);return
	captures="--capture" in OS.get_cmdline_user_args()
	run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);print("FAIL: ",label)
func frames(count:int=2)->void:
	for i:int in count:await process_frame
func step(minutes:float)->void:
	var remaining:float=minutes
	while remaining>.000001:
		var part:float=minf(.05*LifeSim.GAME_MINUTES_PER_SECOND,remaining);app._process(part/LifeSim.GAME_MINUTES_PER_SECOND);remaining-=part
func until(done:Callable,limit:float=100.0)->bool:
	for i:int in int(limit/.3):
		if done.call():return true
		step(.3)
	return bool(done.call())
func finish_car_trip()->void:
	# Visual travel is paused; its controller owns the single arrival time charge.
	for frame:int in 1500:
		if app.mode!="travel":return
		app._process(.05)
		if frame%20==0:await process_frame
	check(app.mode!="travel","The actual car journey completes within the bounded travel window.")
func first(kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}
func reset_needs()->void:
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false
		for key:String in member.sim.needs:member.sim.needs[key]=80.0
		member.sim.bladder_grace=0.0
	app.household.set_speed(1)
func capture(label:String)->void:
	if not captures:return
	await frames(3);await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("user://"+label+".png")
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	if "--resume" in OS.get_cmdline_user_args():
		await resume();await finish();return
	app.household_profiles=[{"name":"Alex Rivera","frame":0},{"name":"Jamie Rowan","frame":1}]
	app.start_household();await frames(3);reset_needs()
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):completed.append(id+":"+str(action.id)))
	var plant:Dictionary=first("plant")
	check(not plant.is_empty(),"A real authored plant is present.")
	check(app.sim.get_actions_for("plant",plant.id).size()==1,"Ordinary bladder exposes plant tending only.")
	app.sim.needs.bladder=12.0
	check(app.sim.get_actions_for("plant",plant.id).any(func(a:Dictionary)->bool:return str(a.id)=="plant_wee" and a.available),"Emergency option appears at 12 bladder.")
	check(not app.sim.queue_action("plant_wee","missing",Vector3.ZERO),"A fabricated pot target is refused.")
	check(not app.sim.queue_action("plant_wee",first("toilet").id,Vector3.ZERO),"A non-pot target is refused.")
	var start:Vector3=app.player.position
	app.queue_interaction(plant,"plant_wee");step(1.0)
	check(app.player.position.distance_to(start)>.1 and app.sim.get_current_action().phase=="approach","Emergency use follows the actual walking controller.")
	check(float(app.sim.needs.bladder)<12.0,"Walking does not give premature bladder relief.")
	app.cancel_current_action()
	check(app.sim.get_current_action().is_empty() and app.household.sanitation.puddles.is_empty(),"Canceling the walk leaves no relief event or puddle.")
	# Moving/selling uses existing target refresh, preserving unrelated later instructions.
	app.sim.needs.bladder=12.0;app.queue_interaction(plant,"plant_wee")
	var original_position:Vector3=plant.node.position
	plant.node.position.x-=.5;app.world.rebuild_navigation();app._refresh_sim_targets()
	check(app.sim.get_current_action().target_position==app.world.approach(plant),"Moving a pot updates the emergency approach target.")
	var saved_plant:Dictionary={"id":plant.id,"kind":"plant","x":original_position.x,"z":original_position.z,"rotation":plant.node.rotation_degrees.y}
	app.world.remove_item(plant.id);app._refresh_sim_targets()
	check(app.sim.action_queue.is_empty(),"Selling a pot cancels its unreachable emergency use.")
	app.world.add_item(saved_plant);app._refresh_sim_targets();plant=app._find_item(saved_plant.id)
	app.sim.needs.bladder=12.0;app.queue_interaction(plant,"plant_wee");app.sim.needs.bladder=40.0
	check(until(func()->bool:return app.sim.action_queue.is_empty()),"Reaching a pot rechecks desperation and cancels a now-unneeded action.")
	check(float(app.sim.needs.bladder)<40.0,"Arrival rejection awards no continuous relief.")
	app.sim.needs.bladder=10.0;app.queue_interaction(plant,"plant_wee")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),"Lifelet reaches the pot before using it.")
	step(2.0);app.world.camera_target=(app.player.position+plant.node.position)*.5+Vector3(0,.6,0);app.world.camera.size=5.7;app.world.camera_angle=.65;app.world.update_camera();await capture("01_desperate_pot")
	check(float(app.sim.needs.bladder)>20.0,"Actual pot use continuously restores bladder.")
	check(app.save_game("","Emergency pot in progress"),"A partly relieved plant-use action can be saved.")
	pot_slot=app.active_save_id
	check(until(func()->bool:return app.sim.action_queue.is_empty()),"Pot use completes through the ordinary action queue.")
	check(float(app.sim.needs.bladder)>85.0 and completed.has("player:plant_wee"),"Completed emergency use grants its bounded relief once.")
	# Toilet relief wins against a nearly expired accident timer.
	reset_needs();var toilet:Dictionary=first("toilet");app.queue_interaction(toilet,"toilet")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),"The existing toilet remains reachable.")
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=9.8;step(.6)
	check(float(app.sim.needs.bladder)>0.0 and app.sim.bladder_grace==0.0 and app.household.sanitation.puddles.is_empty(),"Toilet relief already in progress resets grace before an accident.")
	app.cancel_current_action();reset_needs()
	# Move to open floor through the ordinary walk control before the accident.
	app.on_ground_clicked(Vector3(-2,.16,2));check(until(func()->bool:return not app.walk_only),"Lifelet walks to open floor.")
	app.sim.needs.bladder=0.0;step(9.0)
	check(app.household.sanitation.puddles.is_empty() and absf(app.sim.bladder_grace-9.0)<.00001,"An empty meter has a ten-minute grace period.")
	app.household.set_speed(0);step(20.0)
	check(absf(app.sim.bladder_grace-9.0)<.00001,"Pause cannot advance urgency.")
	app.household.set_speed(1);app.set_build_mode(true);step(20.0)
	check(absf(app.sim.bladder_grace-9.0)<.00001,"Build mode cannot advance urgency.")
	app.set_build_mode(false);app.show_menu();step(20.0)
	check(absf(app.sim.bladder_grace-9.0)<.00001,"A paused menu cannot advance urgency.")
	app.close_overlay();app.household.set_speed(1)
	var accident_position:Vector3=app.player.position
	step(1.01)
	check(app.household.sanitation.puddles.size()==1,"The grace deadline creates exactly one puddle.")
	var puddle:Dictionary=app.household.sanitation.puddles[0]
	check(str(puddle.member)=="player" and str(puddle.venue)=="home" and Vector3(puddle.position[0],puddle.position[1],puddle.position[2]).distance_to(accident_position)<.001,"Accident records the real actor position, member and location.")
	check(float(app.sim.needs.bladder)>74.0 and float(app.sim.needs.hygiene)<45.0 and app.sim.moodlets.any(func(m:Dictionary)->bool:return str(m.emotion)=="Embarrassed"),"Accident gives relief, hygiene loss and an embarrassed moodlet.")
	step(60.0)
	check(app.household.sanitation.puddles.size()==1,"Continuing a large interval does not spam the same zero crossing.")
	var puddle_item:Dictionary=app._find_item(puddle.id)
	check(not puddle_item.is_empty() and app.world.serialize_items().all(func(i:Dictionary)->bool:return str(i.get("kind",""))!="puddle"),"Puddle is an interactable dynamic object, not a purchasable furnishing.")
	var cell:Vector2i=app.world.nearest_free(puddle_item.node.position)
	app.world.rebuild_navigation()
	check(not app.world.navigation.is_point_solid(cell),"Puddle collision does not block walking or cleanup navigation.")
	app.world.camera_target=accident_position;app.world.camera.size=7.5;app.world.camera_angle=.8;app.world.update_camera()
	var mesh:MeshInstance3D=puddle_item.node.get_child(0)
	var colors:PackedColorArray=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(mesh.material_override.vertex_color_use_as_albedo and colors[0].a<.5 and colors[49].a==0.0,"The wet patch uses a translucent centre and a fully fading perimeter.")
	check(puddle_item.node.position.y>float(puddle.floor_y)+.0265,"A puddle above the actual woven rug surface remains visible.")
	await capture("02_accident_floor")
	if captures:
		var picked:Array=[]
		app.world.object_clicked.connect(func(item:Dictionary,_at:Vector2):picked.append(str(item.id)))
		for dx:float in [-.43,.43]:
			app.world.pick(app.world.camera.unproject_position(puddle_item.node.position+Vector3(dx,.015,0)))
			if picked.has(str(puddle.id)):break
		check(picked.has(str(puddle.id)),"Rendered camera ray picking reaches the actual puddle collision.")
		var mop_button:Button=null
		for node:Node in app.overlay.find_children("*","Button",true,false):
			if node.text=="Mop up accident":mop_button=node
		check(is_instance_valid(mop_button) and not mop_button.disabled,"Clicking the puddle opens an available mop action.")
		app.close_overlay()
	# A second member owns an independent urgency timer and puddle.
	var second:LifeSim=app.household.member_sim("housemate_1");second.needs.bladder=0.0;step(10.01)
	check(app.household.sanitation.puddles.size()==2 and str(app.household.sanitation.puddles[1].member)=="housemate_1","Each household member can independently have an accident.")
	if captures:
		var wood_puddle:Dictionary=app.household.sanitation.puddles[1]
		var wood_at:Vector3=Vector3(wood_puddle.position[0],wood_puddle.position[1],wood_puddle.position[2])
		app.select_household_member(1);app.on_ground_clicked(wood_at+Vector3(1.25,0,0))
		check(until(func()->bool:return not app.walk_only),"The second Lifelet walks away to reveal their wet patch on bare wood.")
		app.select_household_member(0);app.world.camera_target=wood_at+Vector3(0,.3,0);app.world.camera.size=5.7;app.world.camera_angle=2.4;app.world.update_camera()
		await capture("02b_bare_wood")
	# A pending car/hidden event waits for a real visible location.
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=9.0;app.mode="travel";app.household.tick(15.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(app.household.sanitation.puddles.size()==2 and app.sim.bladder_grace==10.0,"Trip time retains urgent need without a stale departure puddle.")
	app.mode="live";app.player.visible=false;app.household.tick(1.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(app.household.sanitation.puddles.size()==2,"A hidden actor cannot create a puddle at stale coordinates.")
	app.player.visible=true;step(.3)
	check(app.household.sanitation.puddles.size()==3,"Pending urgency resolves once the Lifelet is visibly present again.")
	# Actual cleanup cancellation and competition preserve the mess and later queues.
	reset_needs();app.queue_interaction(puddle_item,"mop_puddle")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),"The cleaner walks to the actual puddle before mopping.")
	step(2.0)
	for actor:LifeActor in app.world.actors.values():actor.clear_speech()
	app.world.camera_target=accident_position+Vector3(0,.3,0);app.world.camera.size=6.3;app.world.camera_angle=.8;app.world.update_camera()
	await capture("03_mopping")
	check(app.player._mop.visible,"Mopping presents the original authored mop at floor level.")
	app.household.set_speed(0);app._process(.1)
	check(app.player._mop.visible,"Pausing active mopping retains its held prop.")
	app.household.set_speed(1)
	check(not second.get_action_availability("mop_puddle",puddle.id).available,"An active cleaner exclusively owns the puddle.")
	app.household.set_speed(0);app.cancel_current_action();app._process(.1)
	check(not app.player._mop.visible,"Canceling paused mopping removes the abandoned prop.")
	app.household.set_speed(1)
	check(not app.household.sanitation.find(puddle.id).is_empty(),"Canceling partial mopping leaves the puddle.")
	var previous_completions:int=completed.count("player:mop_puddle")+completed.count("housemate_1:mop_puddle")
	app.queue_interaction(puddle_item,"mop_puddle")
	check(second.queue_action("mop_puddle",puddle.id,app.world.approach(puddle_item)),"A second cleaner can queue while the first is still approaching.")
	var shelf:Dictionary=first("bookshelf");second.queue_action("read",shelf.id,app.world.approach(shelf))
	check(until(func()->bool:return app.household.sanitation.find(puddle.id).is_empty()),"One of the competing cleaners completes through actual movement and action progress.")
	check(completed.count("player:mop_puddle")+completed.count("housemate_1:mop_puddle")==previous_completions+1,"Competing cleanup completes exactly once.")
	check(second.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"Canceling a duplicate cleanup preserves that Lifelet’s later read instruction.")
	check(app.household.sanitation.find(puddle.id).is_empty() and app._find_item(puddle.id).is_empty(),"Completed cleaning removes the ledger record and picking geometry.")
	check(not app.sim.queue_action("mop_puddle",puddle.id),"Cleaning an already removed puddle is refused.")
	# Keep a real in-progress clean in a named save for a fresh process.
	var retained:Dictionary=app.household.sanitation.puddles[0]
	app.queue_interaction(app._find_item(retained.id),"mop_puddle")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active"),"A retained puddle has real active cleanup before saving.")
	step(2.0);second.needs.bladder=0.0;second.bladder_grace=4.0
	var saved:Dictionary=app.household.sanitation.get_state()
	check(app.save_game("","Bladder and floor cleanup"),"Named save accepts puddles and active cleanup.")
	var expectation:Dictionary={"slot":app.active_save_id,"sanitation":LifeSaveLibrary.read_slot(app.active_save_id).data.sanitation,"pot_slot":pot_slot,"target":retained.id,"grace":second.bladder_grace,"elapsed":app.sim.get_current_action().elapsed}
	var f:=FileAccess.open("user://sanitation_expected.json",FileAccess.WRITE);f.store_string(JSON.stringify(expectation,"",true,true));f.close()
	app.load_game(app.active_save_id)
	check(not app._find_item(retained.id).is_empty() and app.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="mop_puddle"),"Same-process loading rebuilds puddle targets synchronously before resuming cleanup.")
	second=app.household.member_sim("housemate_1")
	var state:Dictionary=app.household.get_state(app.world.serialize_items())
	for change:String in ["timer","position","member","duplicate","action"]:
		var invalid:Dictionary=state.duplicate(true)
		match change:
			"timer":invalid.members[0].state.bladder_grace={"bad":true}
			"position":invalid.sanitation.puddles[0].position[1]=INF
			"member":invalid.sanitation.puddles[0].member="not_a_housemate"
			"duplicate":invalid.sanitation.puddles.append(invalid.sanitation.puddles[0].duplicate(true))
			"action":invalid.members[0].state.action_queue[0].duration=1.0
		var validator:LifeHousehold=LifeHousehold.new();var result:Dictionary=validator.restore_state(invalid);validator.free()
		check(not result.ok,"Malformed "+change+" is rejected before adopting a household.")
	var old:Dictionary=state.duplicate(true);old.erase("sanitation")
	for member:Dictionary in old.members:member.state.erase("bladder_grace");member.state.action_queue.clear()
	var legacy:LifeHousehold=LifeHousehold.new();var legacy_result:Dictionary=legacy.restore_state(old)
	check(legacy_result.ok and legacy.sanitation.puddles.is_empty() and legacy.selected().bladder_grace==0.0,"Older saves receive clean floors and zero urgency without migration loss.");legacy.free()
	await finish()
func resume()->void:
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://sanitation_expected.json"))
	app.load_game(expected.pot_slot);await frames(3)
	check(float(app.sim.needs.bladder)>12.0 and str(app.sim.get_current_action().get("id",""))=="plant_wee","A fresh load retains the already-started emergency use after partial relief.")
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):completed.append(id+":"+str(action.id)))
	check(until(func()->bool:return app.sim.action_queue.is_empty()) and completed.has("player:plant_wee"),"Already-started pot use resumes without incorrectly reapplying the initial desperation gate.")
	app.load_game(expected.slot);await frames(3)
	check(app.active_save_id==str(expected.slot) and app.has_active_game,"Fresh process opens the actual named save.")
	check(app.household.sanitation.puddles==expected.sanitation.puddles,"Fresh load preserves the exact decoded saved puddle identities, positions, owner and location.")
	check(app.household.sanitation.serial==int(expected.sanitation.serial),"The saved integer puddle serial restores exactly from JSON numeric data.")
	check(app.household.member_sim("housemate_1").bladder_grace==float(expected.grace),"Fresh load preserves another member’s remaining grace.")
	check(absf(float(app.sim.get_current_action().elapsed)-float(expected.elapsed))<.00000001,"Fresh load preserves actual partial cleanup progress.")
	check(not app._find_item(expected.target).is_empty(),"Fresh world reconstruction restores clickable puddle geometry.")
	reset_needs()
	check(until(func()->bool:return app.sim.action_queue.is_empty()),"Loaded cleaner physically resumes and completes the saved action.")
	check(app.household.sanitation.find(expected.target).is_empty(),"Restored cleanup removes its puddle exactly once.")
	var retained:Dictionary=app.household.sanitation.get_state()
	app.travel_to("park");await finish_car_trip();await frames(2)
	check(app.current_venue=="park" and first("puddle").is_empty(),"Home puddles are absent from another location.")
	app.travel_to("home");await finish_car_trip();await frames(2)
	check(app.household.sanitation.get_state()==retained and not first("puddle").is_empty(),"Returning home retains the remaining floor messes.")
	await capture("04_restored_floor")
	app.on_ground_clicked(Vector3(0,.16,8.5))
	check(until(func()->bool:return not app.walk_only),"The Lifelet reaches the real front sidewalk through normal navigation.")
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=0.0;step(10.01)
	var street:Dictionary=app.household.sanitation.puddles[-1]
	var street_node:Node3D=app._find_item(street.id).node
	var street_at:Vector3=Vector3(street.position[0],street.position[1],street.position[2])
	var surface_y:float=app.meal_flow._floor_height(street_at)-.002
	check(street_node.position.y<float(street.floor_y) and absf(street_node.position.y-(surface_y+.006))<.000001,"A real outdoor accident lies on the measured sidewalk rather than floating at the navigation datum.")
func finish()->void:
	var report:Dictionary={"checks":checks,"failures":failures}
	var path:String="user://sanitation_busy.json" if "--busy" in OS.get_cmdline_user_args() else ("user://sanitation_resume.json" if "--resume" in OS.get_cmdline_user_args() else "user://sanitation_first.json")
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("Sanitation: %d checks, %d failures." % [checks,failures.size()])
	app.queue_free();await frames(5)
	# The audio mixer releases stopped WAV playback on its own thread.
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)
