extends SceneTree
var app:Node
var checks:int=0
var failures:Array[String]=[]
var celebration_audio_started:bool=false
func _initialize()->void:
	if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():printerr("Use an isolated save directory.");quit(2);return
	run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func observe_celebration(child:Node)->void:
	if child.get_script()!=preload("res://scripts/wedding_celebration.gd"):return
	# Observe playback when it starts: rendering a busy house can take longer
	# than the short fanfare before the next test frame gets to inspect it.
	child.ready.connect(func():
		var players:Array=child.find_children("*","AudioStreamPlayer",true,false)
		celebration_audio_started=players.size()==1 and players[0].playing and players[0].stream.get_length()>1.5
		print("CELEBRATION_AUDIO_STARTED ",celebration_audio_started))
func drive(until:Callable,limit:int,label:String)->bool:
	for index:int in limit:
		app._process(.1)
		if index%20==0:await process_frame
		if until.call():return true
	print("TIMEOUT ",label," action=",app.sim.get_current_action()," visit=",app.residents.home_visit.state)
	return false
func perform(id:String,target:String="maya")->bool:
	app.household.set_speed(8)
	var body:LifeActor=app.world.actors.get(target)
	if not is_instance_valid(body):return false
	app.queue_interaction({"id":target,"kind":"neighbor","label":"Maya","node":body,"size":Vector2(.6,.6)},id)
	if app.sim.action_queue.is_empty():return false
	return await drive(func():return app.sim.action_queue.is_empty(),2600,id)
func capture(label:String)->void:
	var folder:String=OS.get_environment("RELATIONSHIP_EVIDENCE_DIR")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	app.world.set_cutaway(true)
	app.world.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	app.world.camera.global_position=app.player.position+Vector3(3,3,4)
	app.world.camera.look_at(app.player.position+Vector3(0,.8,0))
	await process_frame
	RenderingServer.force_draw(false,0.0)
	check(root.get_texture().get_image().save_png(folder+"/"+label+".png")==OK,"Rendered "+label)
func run()->void:
	root.size=Vector2i(960,600)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	app.child_entered_tree.connect(observe_celebration)
	await process_frame
	app.set_process(false);app.set_sound(false)
	app.household_profiles=[{"name":"Robin Vale","age_stage":"adult","gender":"female","traits":[]}]
	app.start_household();app.world.set_process(false)
	app.sim.autonomy=false;app.sim.set_aging("normal",false)
	for key:String in app.sim.needs:app.sim.needs[key]=90.0
	app.sim.relationships.maya.friendship=35.0
	app.household.set_speed(8)
	check(app.residents.home_visit.invite("maya"),"Friend is invited through the real home-visit API")
	var arrived:bool=await drive(func():return str(app.residents.home_visit.state.get("phase",""))=="waiting",3000,"arrival")
	check(arrived,"Visitor reaches the front door")
	if not arrived:finish();return
	var welcomed:bool=app.residents.home_visit.welcome("player")
	check(welcomed,"Host can welcome visitor")
	if not welcomed:finish();return
	var entered:bool=await drive(func():return str(app.residents.home_visit.state.get("phase",""))=="inside",3000,"welcome")
	check(entered,"Visitor enters and completes hallway greeting")
	if not entered:finish();return
	for index:int in 3:
		check(await perform("flirt"),"Actual flirt conversation completes")
		check(int(app.sim.relationships.maya.successful_flirts)==index+1,"Only completed real flirts increment progression")
	check(await perform("ask_partner"),"Actual partnership conversation completes")
	check(app.sim.romantic_partner=="maya","Invited friend becomes partner")
	check(await perform("go_on_date"),"First physical home date completes")
	check(int(app.sim.relationships.maya.completed_dates)==1,"First home date credits once")
	app.household.set_speed(8)
	check(app.relationship_flow.start_date("player","maya"),"Second dedicated home date starts")
	check(await drive(func():return str(app.sim.get_current_action().get("phase",""))=="active" and float(app.sim.get_current_action().get("elapsed",0))>15,1500,"date approach"),"Partner is physically approached before date progress")
	var guest:LifeActor=app.world.actors.maya
	check(app.player.position.distance_to(guest.position)<1.8,"Date partners stand together")
	await capture("date")
	app.household.set_speed(0)
	var elapsed:float=float(app.sim.get_current_action().get("elapsed",0))
	for index:int in 10:app._process(.1)
	check(is_equal_approx(float(app.sim.get_current_action().get("elapsed",0)),elapsed),"Date progress pauses with the game")
	check(app.save_game("","Dating regression"),"Physical date saves")
	var slot:String=app.active_save_id
	var epoch:int=app.load_epoch
	app.load_game(slot)
	await process_frame
	check(app.load_epoch==epoch+1,"Mid-date save actually reloads: "+app.notice_label.text)
	check(int(app.sim.relationships.maya.completed_dates)==1,"Loading mid-date does not grant completion")
	app.household.set_speed(8)
	check(await drive(func():return app.sim.action_queue.is_empty(),2500,"restored date"),"Restored physical date completes")
	check(int(app.sim.relationships.maya.completed_dates)==2,"Restored date increments once")
	app.set_sound(true)
	check(await perform("commit"),"Marriage proposal conversation completes")
	await process_frame;await process_frame
	check(app.household.members.size()==2,"Incoming spouse becomes a real household member")
	if app.household.members.size()==2:
		var spouse_id:String=str(app.household.resident_members.get("maya",""))
		check(not spouse_id.is_empty() and app.world.actors.has(spouse_id) and not app.world.actors.has("maya"),"Resident body becomes exactly one playable spouse body")
		check(str(app.household.member_sim(spouse_id).character.name)=="Maya Vale","Incoming wife adopts resident wife's surname")
		check(app.household_profiles.size()==2 and str(app.household_profiles[1].name)=="Maya Vale","Character profiles include the incoming spouse")
		var celebration:Node=null
		for child:Node in app.get_children():
			if child.get_script()==preload("res://scripts/wedding_celebration.gd"):celebration=child;break
		check(is_instance_valid(celebration) and celebration.pieces.size()==100,"Completed marriage spawns falling streamers")
		check(celebration_audio_started,"Marriage starts its celebration sound")
		if is_instance_valid(celebration):
			celebration._process(.8)
		await capture("married")
		app.select_household_member(1)
		check(app.bound_member_id==spouse_id and app.sim==app.household.member_sim(spouse_id),"Player can control the incoming spouse")
		check(app.save_game(slot,"Dating regression"),"Merged physical household saves")
		epoch=app.load_epoch
		app.load_game(slot);await process_frame
		check(app.load_epoch==epoch+1,"Merged household actually reloads: "+app.notice_label.text)
		check(app.household.members.size()==2 and not app.residents.present("maya") and not app.world.actors.has("maya"),"Reload does not recreate the retired neighbor")
		app.sim.autonomy=false
		app.cancel_current_action()
		check(await perform("friendly","player"),"Incoming spouse can perform a player-directed conversation")
	finish()
func finish()->void:
	print("DATING_MARRIAGE %d checks, %d failures" % [checks,failures.size()])
	app.queue_free();await process_frame
	quit(1 if not failures.is_empty() else 0)
