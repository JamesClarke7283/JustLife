extends "res://tests/test_playthrough.gd"
## Run in a plugin-free justlife-playthrough-* copy with private data paths.
## Fixture creation is direct; an external XTest driver sends the OS pointer.
## Completion advances only through the application's ordinary engine frames.
var pointer_hits:Array[String]=[]
var finished_actions:Array[Dictionary]=[]
var pointer_steps:Array[Dictionary]=[]
var proof:Dictionary={}
var pointer_sequence:int=0
var observed_state_frames:int=0

class EngineErrors:
	extends Logger
	var errors:Array[Dictionary]=[]
	func _log_error(function:String,file:String,line:int,code:String,message:String,_notify:bool,_type:int,_backtrace:Array[ScriptBacktrace])->void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"message":message})

var engine_errors:EngineErrors

func clock_minutes()->float:
	return float(app.household.day-1)*1440.0+app.household.minutes

func observe_state(label:String)->void:
	if proof.is_empty():return
	observed_state_frames+=1
	var member:LifeSim=app.household.member_sim(str(proof.member))
	var dog:LifePetActor=app.pet_actors.get(str(proof.pet))
	var state:Dictionary={"label":label,"wall_msec":Time.get_ticks_msec(),"frame":observed_state_frames,"clock":clock_minutes(),"speed":app.household.speed,"action":member.get_current_action().duplicate(true),"person":vec(app.world.actors[str(proof.member)].position),"dog":vec(dog.position),"interaction":dog.interaction,"bond":LifePetCare.bond(app.household.pet_care(str(proof.pet)),str(proof.member))}
	var file:=FileAccess.open("res://evidence/action_trace.jsonl",FileAccess.READ_WRITE if FileAccess.file_exists("res://evidence/action_trace.jsonl") else FileAccess.WRITE)
	file.seek_end();file.store_line(JSON.stringify(LifeSaveLibrary._json_safe(state)));file.close()

func capture_pointer(name:String)->void:
	# One rendered frame, with no pause or extra timer consuming the watchdog.
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(screenshot_dir.path_join(name+".png"))==OK,"Rendered screenshot "+name)
	observe_state("capture_"+name)

func native_click(at:Vector2,label:String)->void:
	pointer_sequence+=1
	var scale:Vector2=Vector2(DisplayServer.window_get_size())/root.get_visible_rect().size
	var request:=FileAccess.open("res://evidence/pointer_request.json",FileAccess.WRITE)
	request.store_string(JSON.stringify({"sequence":pointer_sequence,"action":"click","x":roundi(at.x*scale.x),"y":roundi(at.y*scale.y)}));request.close()
	var began:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<15000:
		await process_frame
		observe_state("pointer_wait_"+label)
		if not FileAccess.file_exists("res://evidence/pointer_reply.json"):continue
		var reply:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/pointer_reply.json"))
		if not reply is Dictionary or int(reply.get("sequence",-1))!=pointer_sequence:continue
		check(bool(reply.get("ok",false)),"External OS pointer driver delivered "+label)
		await frames(4)
		pointer_steps.append({"label":label,"screen":[at.x,at.y],"actual_mouse":vec(Vector3(root.get_mouse_position().x,root.get_mouse_position().y,0)),"selected":app.household.selected_id(),"pet":app.selected_pet_id,"os":reply})
		return
	check(false,"External OS pointer driver replied to "+label)

func click_button(label:String)->bool:
	var button:Button=button_matching(label)
	check(button!=null,"Pointer can target visible enabled button: "+label)
	if button==null:return false
	await native_click(button.get_global_transform_with_canvas()*(button.size*.5),label)
	return true

func body_pixel(id:String,body:Node3D,heights:Array[float])->Vector2:
	# Find a visibly exposed part using the same read-only physics mask as a
	# world click. The real input below must still dispatch through the UI.
	for height:float in heights:
		var pixel:Vector2=app.world.camera.unproject_position(body.position+Vector3(0,height,0))
		var origin:Vector3=app.world.camera.project_ray_origin(pixel)
		var query:=PhysicsRayQueryParameters3D.create(origin,origin+app.world.camera.project_ray_normal(pixel)*150,app.world.PICK_GROUND)
		var hit:Dictionary=app.world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and str(hit.collider.get_meta("item_id",""))==id:return pixel
	return Vector2.INF

func _run()->void:
	if OS.get_environment("DISPLAY")==":0" or OS.get_environment("DISPLAY").is_empty():
		push_error("Native pointer qualification requires its own isolated display.");quit(2);return
	engine_errors=EngineErrors.new();OS.add_logger(engine_errors)
	# Cosmetic test-only quality keeps real-frame play practical on llvmpipe.
	root.msaa_3d=Viewport.MSAA_DISABLED;root.scaling_3d_scale=.35
	screenshot_dir="res://art/pet_pointer"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household_profiles=[{"name":"Avery","age_stage":"adult","traits":[],"hair":0},{"name":"River","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.selected_lot=0;app.start_household()
	app.world.sun.shadow_enabled=false
	app.household.set_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	await frames(4)
	var choice:int=-1
	for index:int in LifePets.candidate_count():
		if str(LifePets.candidate(1,index).species)=="dog":choice=index;break
	check(choice>=0,"Fixture has a dog candidate")
	if choice<0:await finish();return
	var draft:Dictionary=LifePets.candidate(1,choice);draft.name="Rex"
	var prepared:Dictionary=app.household.prepare_pet(draft)
	var at:Vector3=app.pet_home_spot()
	var adopted:Dictionary=app.household.commit_pet(prepared.get("request",{}),at)
	check(bool(adopted.get("ok",false)),"Fixture adopts a dog on clear home floor")
	if not bool(adopted.get("ok",false)):await finish();return
	var pet_id:String=str(adopted.pet.id)
	var dog:LifePetActor=app.spawn_pet(pet_id,adopted.pet,at,at)
	app.draw_live()
	app.world.object_clicked.connect(func(item:Dictionary,_screen:Vector2):pointer_hits.append(str(item.id)))
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):finished_actions.append({"member":id,"action":action.duplicate(true)}))
	await frames(4);await physics_frame
	var selected_id:String=str(app.household.members[1].id)
	var other_id:String=str(app.household.members[0].id)
	check(app.household.selected_id()==other_id,"The second Lifelet starts unselected")
	var person:LifeActor=app.world.actors[selected_id]
	var person_pixel:Vector2=body_pixel(selected_id,person,[1.25,.9,.5,.2])
	check(person_pixel.is_finite(),"The unselected Lifelet has a visible pickable body")
	if not person_pixel.is_finite():await finish();return
	await native_click(person_pixel,"Lifelet body")
	check(pointer_hits.has(selected_id),"Native body click reaches the Lifelet through world picking")
	if not await click_button("Control this Lifelet"):await finish();return
	check(app.household.selected_id()==selected_id and app.bound_member_id==selected_id,"Native control click selects the intended Lifelet")
	await physics_frame
	var dog_pixel:Vector2=body_pixel(pet_id,dog,[.22,.12,.32])
	check(dog_pixel.is_finite(),"The dog has a visible pickable body")
	if not dog_pixel.is_finite():await finish();return
	await native_click(dog_pixel,"Dog body")
	check(pointer_hits.has(pet_id) and app.selected_pet_id==pet_id,"Native dog click opens the correct pet card")
	await capture_pointer("selected_dog")
	var before:float=LifePetCare.bond(app.household.pet_care(pet_id),selected_id)
	var other_before:float=LifePetCare.bond(app.household.pet_care(pet_id),other_id)
	proof={"member":selected_id,"pet":pet_id,"bond_before":before,"other_bond_before":other_before,"person_before":vec(person.position),"pet_before":vec(dog.position)}
	if not await click_button("PetCare_pet_play"):await finish();return
	var sim:LifeSim=app.household.member_sim(selected_id)
	var queued:Dictionary=sim.get_current_action()
	check(str(queued.get("id",""))=="pet_play" and str(queued.get("target_id",""))==pet_id,"Native care click queues play for the selected Lifelet and dog")
	check(app.care_motion().holds(pet_id),"Queued play reserves the same dog")
	if str(queued.get("id",""))!="pet_play":await finish();return
	if not await click_button("▶▶▶"):await finish();return
	var active_seen:bool=false
	var start:int=Time.get_ticks_msec()
	var start_clock:float=clock_minutes()
	var observed_frames:int=0
	while Time.get_ticks_msec()-start<180000 and finished_actions.is_empty() and engine_errors.errors.is_empty():
		await process_frame;observed_frames+=1
		observe_state("completion_wait")
		if str(dog.interaction)=="pet_play" and not active_seen:
			active_seen=true;await capture_pointer("paired_play")
	observe_state("completion_check")
	check(active_seen,"Normal engine frames show the paired dog-play pose")
	var credited:bool=finished_actions.any(func(record:Dictionary)->bool:return record.member==selected_id and str(record.action.id)=="pet_play" and str(record.action.target_id)==pet_id)
	check(credited,"Normal engine frames complete the selected Lifelet's exact dog interaction")
	check(LifePetCare.bond(app.household.pet_care(pet_id),selected_id)>before,"Completed pointer-selected play improves that Lifelet's bond")
	check(is_equal_approx(LifePetCare.bond(app.household.pet_care(pet_id),other_id),other_before),"The unselected Lifelet receives no interaction credit")
	check(observed_frames>0 and clock_minutes()>start_clock,"The shared game clock advances through actual engine frames")
	proof.merge({"bond_after":LifePetCare.bond(app.household.pet_care(pet_id),selected_id),"other_bond_after":LifePetCare.bond(app.household.pet_care(pet_id),other_id),"person_after":vec(person.position),"pet_after":vec(dog.position),"observed_frames":observed_frames,"start_clock":start_clock,"end_clock":clock_minutes(),"last_action":sim.get_current_action().duplicate(true)})
	write_result()
	await click_button("Ⅱ")
	await capture_pointer("completed")
	await finish()

func write_result()->void:
	var output:=FileAccess.open("res://evidence/result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(LifeSaveLibrary._json_safe({"checks":assertions,"failures":failures,"pointer_steps":pointer_steps,"world_hits":pointer_hits,"finished_actions":finished_actions,"proof":proof,"engine_errors":engine_errors.errors}),"  "))
	output.close()

func finish()->void:
	check(engine_errors.errors.is_empty(),"The pointer chain and real-frame completion emit no engine errors")
	write_result()
	app.queue_free();await frames(3)
	print("PET_POINTER_RESULT checks=%d failures=%d"%[assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)
