extends "res://tests/test_playthrough.gd"
const MainScene=preload("res://scenes/main.tscn")
const Building=preload("res://scripts/building_state.gd")
var preflight:bool=false
var receipts:Array=[]
var crossed_stairs:bool=false
var travelled_from_upper:bool=false
var book_id:String=""

func _run()->void:
	preflight="--preflight" in OS.get_cmdline_user_args()
	root.size=Vector2i(1440,900)
	screenshot_dir="res://evidence"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	var observer:=MotionObserver.new();observer.harness=self;app.add_child(observer)
	if "--resume-only" in OS.get_cmdline_user_args():
		await _resume_public();await _finish();return
	await _enter_new_game()
	await press("Male")
	var name_field:LineEdit=app.find_children("*","LineEdit",true,false)[0]
	name_field.text="Rowan Vale";name_field.text_changed.emit(name_field.text)
	await press("Curls");await press("+ Add Lifelet");await press("Female");await press("Bob")
	name_field=app.find_children("*","LineEdit",true,false)[0]
	name_field.text="Ellis Vale";name_field.text_changed.emit(name_field.text)
	await press_member("Rowan Vale")
	check(app.household_profiles.size()==2 and app.household_profiles[0].frame==1 and app.household_profiles[1].frame==0,"Public creator retains two distinct male/female Lifelets.")
	await screenshot("01_creator")
	await press("Find my home",true);await press("A Fresh Canvas");await press("Start living",true)
	await press("Ⅱ")
	# Disable autonomy only to keep this finite interaction test deterministic.
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	check(app.mode=="live" and app.household.members.size()==2 and app.household.funds==4500,"Public move-in starts the essentials home with its advertised household funds.")
	await press("Build & buy");await press("Structure");await press("Upper")
	var before:Dictionary=app.world.construction.snapshot()
	await press("Floor")
	await _ground_click(Vector3(-6,3.16,-5))
	await _ground_click(Vector3(6,3.16,5))
	var state:Dictionary=app.world.construction.snapshot()
	check(state.floors.size()==before.floors.size()+1 and app.household.funds==3060,"Public floor clicks purchase a supported full upper floor for ℒ1440.")
	if state.floors.size()==before.floors.size():await _finish();return
	await screenshot("02_upper_floor")
	await press("Ground");await press("Stairs")
	await _ground_click(Vector3(-1.5,.16,-2.5))
	state=app.world.construction.snapshot()
	check(state.stairs.size()==1 and state.openings.size()==1 and app.household.funds==2410,"Public stair click buys the original stair, supported opening and guard for ℒ650.")
	check(app.world.construction.tool.is_empty() and app.world.construction.preview==null,"Successful stair purchase completes placement without an overlapping repeat-preview error.")
	check(Building.validate(state).is_empty(),"Publicly purchased architecture validates without fixture injection.")
	await screenshot("03_stairs")
	if not preflight and state.stairs.size()==1:await _upper_room_flow()
	await _finish()

func observe_motion(delta:float)->void:
	if not is_instance_valid(app) or not is_instance_valid(app.player):return
	if app.traversal.routes.has("player") and str(app.traversal.routes.player.get("phase",""))=="transit":
		crossed_stairs=true
		if app.mode=="travel":travelled_from_upper=true

func _upper_room_flow()->void:
	await press("Upper")
	await _purchase("Activities","Stories bookcase",Vector3(-4.0,3.16,-3.0))
	for item:Dictionary in app.world.items:
		if item.kind=="bookshelf" and app.world.item_level(item)==1:book_id=str(item.id)
	await _purchase("Decor","A breath of green",Vector3(3.0,3.16,2.0))
	check(not book_id.is_empty() and app.household.funds==2145,"Upper room furnishings retain the real floor and charge ℒ220 plus ℒ45.")
	await press("Live")
	var item:Dictionary=app._find_item(book_id)
	if item.is_empty():return
	app.world.camera.size=19.0;app.world.camera_target=Vector3(-1,3.16,0);app.world.update_camera();await frames(3)
	var screen:Vector2=app.world.camera.unproject_position(item.node.position+Vector3(0,.85,0))
	await mouse_move(screen);await mouse_click(screen);await press("Read a book")
	await press("▶▶▶")
	var reached:bool=await wait_until(func():return str(app.sim.get_current_action().get("id",""))=="read" and str(app.sim.get_current_action().get("phase",""))=="active","Actual stair ascent to the purchased upper bookcase",50)
	check(reached and crossed_stairs and app.world.point_level(app.player.position)==1,"Lifelet physically crosses the purchased stair and begins reading at the upper bookcase.")
	await press("Ⅱ");await screenshot("04_reading_upstairs")
	await _public_save("Two storey public home")
	var slot:String=app.active_save_id
	var saved:Dictionary=LifeSaveLibrary.read_slot(slot)
	check(bool(saved.ok),"Public upstairs save is readable before any travel.")
	var expectation:Dictionary={"slot":slot,"book_id":book_id,"funds":app.household.funds,"layout":app.world.serialize_items(),"structure":app.world.construction.snapshot(),"names":app.household.members.map(func(member:Dictionary):return str(member.sim.character.name))}
	var f:=FileAccess.open("user://twofloor_expected.json",FileAccess.WRITE);f.store_string(JSON.stringify(LifeSaveLibrary._json_safe(expectation),"  ",true,true));f.close()
	await _trip("library")
	check(travelled_from_upper,"Public departure descends the actual stairs from the upper activity before boarding.")
	await screenshot("05_library_arrival")
	await _trip("home")
	check(app.world.construction.snapshot()==expectation.structure and not app._find_item(book_id).is_empty(),"Actual round trip retains the exact original upper architecture and furnishing identity.")
	await screenshot("06_return_home")
	# Leave the saved upstairs reading checkpoint unchanged for another process.

func _purchase(category:String,label_text:String,point:Vector3)->void:
	await press(category)
	var card_button:Button
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and str(node.tooltip_text).begins_with(label_text+" ·"):card_button=node;break
	check(is_instance_valid(card_button),"Public catalog card is available: "+label_text)
	if not is_instance_valid(card_button):return
	card_button.pressed.emit();await frames(3)
	app.world.camera_target=Vector3(0,point.y,0);app.world.camera.size=22.0;app.world.update_camera();await frames(3)
	var screen:Vector2=app.world.camera.unproject_position(point)
	await mouse_move(screen)
	check(app.world.ghost_valid and app.world.ghost.position.distance_to(point)<.01,"Actual pointer preview supports the upper furnishing: "+label_text)
	await mouse_click(screen)
	var cancel:=InputEventKey.new();cancel.keycode=KEY_ESCAPE;cancel.pressed=true;Input.parse_input_event(cancel);await frames(3)

func _trip(place:String)->void:
	var time_before:float=app.household.day*1440+app.household.minutes
	var funds_before:int=app.household.funds
	await press("Explore");await press(str(LifeNeighborhood.PLACES[place].name));await press("Travel here",true)
	var arrived:bool=await wait_until(func():return app.mode=="live" and app.current_venue==place,"Actual car arrives at "+place,60)
	check(arrived and app.household.speed==0 and app.household.funds==funds_before,"Public car trip preserves paused speed and the shared wallet: "+place)
	check(absf(app.household.day*1440+app.household.minutes-time_before-15.0)<.0001,"Car charges exactly fifteen game minutes: "+place)

func _resume_public()->void:
	var f:=FileAccess.open("user://twofloor_expected.json",FileAccess.READ)
	check(f!=null,"Fresh process has the producer's untouched checkpoint receipt.")
	if f==null:return
	var expected:Dictionary=JSON.parse_string(f.get_as_text());f.close();book_id=str(expected.book_id)
	var saved:Dictionary=LifeSaveLibrary.read_slot(str(expected.slot)).data
	var saved_action:Dictionary=saved.members[int(saved.selected_index)].state.action_queue[0]
	await _public_load()
	check(app.mode=="live" and app.active_save_id==str(expected.slot),"Fresh public save-picker load adopts the actual named upstairs save.")
	check(app.household.speed==0 and app.household.speed==int(saved.speed),"Fresh load itself preserves the saved pause before the capture helper can pause anything.")
	var current:Dictionary=app.sim.get_current_action()
	check(str(current.get("target_id",""))==str(saved_action.target_id) and str(current.get("phase",""))==str(saved_action.phase) and float(current.get("elapsed",-1))==float(saved_action.elapsed),"Fresh load preserves the exact decoded reading target, phase and progress before any capture or resumed simulation.")
	check(app.world.point_level(app.player.position)==1 and app.world.view_level==1 and str(app.sim.get_current_action().get("id",""))=="read","Fresh load restores upper floor view, physical Lifelet and original reading instruction.")
	check(app.world.construction.snapshot()==expected.structure and app.household.funds==int(expected.funds),"Fresh load retains exact decoded building records and the charged household funds.")
	check(app.household.members.map(func(member:Dictionary):return str(member.sim.character.name))==expected.names,"Fresh load retains both publicly created Lifelets.")
	await screenshot("07_fresh_upstairs_load")
	await press("▶▶▶")
	var finished:bool=await wait_until(func():return app.sim.action_queue.is_empty(),"Saved upper reading resumes and naturally completes",50)
	check(finished and app.world.point_level(app.player.position)==1,"Restored reading completes through actual frames on its original upper floor.")
	await press("Ⅱ")
	await _trip("library")

func _ground_click(point:Vector3)->void:
	# Framing changes the view only; input still goes through the real viewport.
	app.world.camera_target=Vector3(0,point.y,0);app.world.camera.size=30.0;app.world.update_camera()
	await frames(3)
	var screen:Vector2=app.world.camera.unproject_position(point)
	check(screen.x>290 and screen.x<1220 and screen.y>125 and screen.y<620,"Build corner projects inside the unobstructed world viewport.")
	if not preflight:await mouse_move(screen)
	await mouse_click(screen)
	receipts.append({"viewport":root.get_visible_rect(),"camera":app.world.camera.global_transform,"ray_point":app.world.floor_point(screen),"point":[point.x,point.y,point.z],"screen":[screen.x,screen.y],"tool":app.world.construction.tool,"anchored":app.world.construction.anchored,"notice":app.notice_label.text if is_instance_valid(app.notice_label) else "","state":app.world.construction.snapshot(),"funds":app.household.funds})

func screenshot(label_text:String,focus:bool=false,pause_for_capture:bool=true)->void:
	if not preflight:await super.screenshot(label_text,focus,pause_for_capture)

func _finish()->void:
	var report:Dictionary={"assertions":assertions,"failures":failures,"receipts":receipts,"pointer_observations":pointer_observations,"preflight":preflight,"crossed_stairs":crossed_stairs,"travelled_from_upper":travelled_from_upper,"scope":"Actual menu/creator/Build button signals, viewport mouse events, physical activity and public save/travel. Headless preflight has no OS pointer or rendering proof. No architecture, actor, wallet, needs or time injection."}
	var output:String="twofloor_preflight" if preflight else ("twofloor_resume" if "--resume-only" in OS.get_cmdline_user_args() else "twofloor_public")
	var file:=FileAccess.open("res://evidence/"+output+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(LifeSaveLibrary._json_safe(report),"  ",true,true));file.close()
	app.queue_free();await frames(4);await create_timer(.15).timeout
	print("PUBLIC_TWOFLOOR checks=%d failures=%d preflight=%s"%[assertions,failures.size(),str(preflight)])
	quit(0 if failures.is_empty() else 1)
