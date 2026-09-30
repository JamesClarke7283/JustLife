extends SceneTree
## Real pet commands, furnishing exit, target refreshes and public save/load.
## No need, clock, care duration or action progress is injected.
var app:Node
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Run with an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
	run.call_deferred()
func frames(count:int=2)->void:
	for i:int in count:await process_frame
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func step()->void:
	app._process(.1);await process_frame
func finish()->void:
	app.queue_free();await frames()
	print("PET_QUEUE_LIFECYCLE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await frames();app.set_sound(false)
	app.household_profiles=[{"name":"Avery","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();await frames(3)
	app.set_process(false);app.household.set_speed(0);app.sim.autonomy=false
	while not app.sim.action_queue.is_empty():app.sim.cancel_action()
	var choice:int=0
	for index:int in LifePets.candidate_count():
		if str(LifePets.candidate(1,index).species)=="dog":choice=index;break
	var draft:Dictionary=LifePets.candidate(1,choice);draft.name="Rex"
	var prepared:Dictionary=app.household.prepare_pet(draft)
	var spot:=Vector3(-8,.16,4.3)
	var bought:Dictionary=app.household.commit_pet(prepared.get("request",{}),spot)
	check(bool(bought.get("ok",false)),"The fixture adopts a real dog")
	if not bool(bought.get("ok",false)):await finish();return
	var pet_id:String=str(bought.pet.id)
	var member_id:String=app.household.selected_id()
	app.spawn_pet(pet_id,bought.pet,spot,spot)
	app.world.add_item({"id":"queue_save_bed","kind":"pet_bed_dog","x":-8.0,"z":2.5,"rotation":0.0})
	var command:Dictionary=app.pet_behavior().command(pet_id,"pet_go_bed")
	for i:int in 300:
		app._tick_pet_autonomy(.1,3.0)
		if str(app.pet_behavior().state(pet_id).phase)=="using":break
	check(bool(command.get("ok",false)) and str(app.pet_behavior().state(pet_id).phase)=="using","A public pet command puts the dog in its bed")
	app._queue_pet_action(pet_id,"pet_pet")
	var care:Dictionary=app.sim.get_current_action()
	check(str(care.get("id",""))=="pet_pet","Care requested during a bed exit enters the durable action queue immediately")
	check(app.care_motion().exit_waits.has(member_id),"The same queued instruction waits for the dog to reach clear floor")
	var saved:bool=app.save_game("pet_queue_lifecycle","Pet queue lifecycle")
	check(saved,"The household saves while its care instruction waits for the pet")
	if not saved:await finish();return
	app.load_game("pet_queue_lifecycle");await frames(3);app.set_process(false);app.household.set_speed(0);app.sim.autonomy=false
	care=app.sim.get_current_action()
	check(str(care.get("id",""))=="pet_pet" and str(care.get("target_id",""))==pet_id,"Public load restores the exact requested care and pet")
	if str(care.get("id",""))!="pet_pet":await finish();return
	var dog:LifePetActor=app.pet_actors[pet_id]
	check(Vector3(care.target_position).distance_to(dog.position)>=.6 and Vector3(care.target_position).distance_to(dog.position)<=1.3,"The restored approach resolves beside the rebuilt pet")
	app._refresh_sim_targets(false)
	check(is_same(care,app.sim.get_current_action()),"The target refresh used by work departures retains the current pet instruction")
	var before:float=LifePetCare.bond(app.household.pet_care(pet_id),member_id)
	var active_checked:bool=false
	app.household.set_speed(3)
	for i:int in 1000:
		await step()
		if not active_checked and str(care.get("phase",""))=="active":
			var at:Vector3=care.target_position
			app._refresh_sim_targets(false)
			check(is_same(care,app.sim.get_current_action()) and str(care.phase)=="active" and Vector3(care.target_position)==at,"Refreshing an active pet interaction preserves its admitted standing position")
			active_checked=true
		if app.sim.action_queue.is_empty():break
	check(active_checked and app.sim.action_queue.is_empty() and LifePetCare.bond(app.household.pet_care(pet_id),member_id)>before,"Reloaded care reaches the dog and completes with its bond effect")
	app.household.set_speed(0)
	app.pet_behavior().command(pet_id,"pet_stop_playing")
	app.queue_nearest("bookshelf","read")
	app._queue_pet_action(pet_id,"pet_pet")
	var queued:Dictionary=app.sim.action_queue[-1] if app.sim.action_queue.size()>1 else {}
	app._refresh_sim_targets(false)
	check(app.sim.action_queue.size()==2 and is_same(app.sim.action_queue[1],queued) and str(queued.get("id",""))=="pet_pet","Target refresh also retains care queued behind another activity")
	app.cancel_current_action(1)
	check(app.sim.action_queue.size()==1 and not app.care_motion().exit_waits.has(member_id),"Cancel removes the queued care without leaving a resumable side request")
	await finish()
