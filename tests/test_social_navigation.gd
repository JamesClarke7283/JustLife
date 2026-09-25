extends "res://tests/test_public_twofloor.gd"
## Headless social admission and moved-target regression. Run with
## tests/run_social_navigation.py in its guarded private snapshot only.
## Controlled body fixtures isolate collision/queue behavior; actual route
## movement, activity time and friendship rewards use ordinary app steps.
const NAMES=["Rowan Vale","Ellis Vale","Morgan Vale","Casey Vale"]
const AGES=["Adult","Adult","Teen","Child"]
var audit:Dictionary={"events":[],"members":{}}
var phase:String="setup"
var event_file:FileAccess
var phase_tag:String=""
var control_completions:Array=[]
var control_saves:Array=[]

func _run()->void:
	phase_tag="controls_fresh" if resume_only else "controls"
	root.size=Vector2i(1440,900);screenshot_dir="res://evidence";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	event_file=FileAccess.open(screenshot_dir.path_join(phase_tag+"_events.jsonl"),FileAccess.WRITE)
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	if resume_only:
		await _fresh_controls();await _finish();return
	await _create_composed()
	if not failures.is_empty():await _finish();return
	phase="controlled_social_fixtures"
	_event("fixture_scope",{"description":"Controlled target/body placement and autonomy off isolate admission/invalidation. Initiator arrival, activity progress and rewards use ordinary .05 app steps with one process frame yielded every step. These are component/integration controls, not natural progression or the three-day review."})
	app.household.member_action_finished.connect(func(id:String,a:Dictionary):control_completions.append({"id":id,"action":a.duplicate(true),"at":_now()}))
	if "--legacy-only" in OS.get_cmdline_user_args():await _legacy_control();await _finish();return
	await _curb_control()
	if "--curb-only" in OS.get_cmdline_user_args():await _finish();return
	await _moved_control()
	await _blocked_control()
	await _stairs_control()
	await _target_stairs_control()
	await _legacy_control()
	check(not LifeSim.SOCIAL_ACTIONS.has("homework") and not LifeSim.SOCIAL_ACTIONS.has("help_homework"),"Cooperative homework IDs are excluded from social reconciliation.")
	var f:=FileAccess.open("user://social_controls_expected.json",FileAccess.WRITE);f.store_string(JSON.stringify(LifeSaveLibrary._json_safe({"saves":control_saves}),"  ",true,true));f.close()
	audit["control_completions"]=control_completions;audit["control_saves"]=control_saves
	await _finish()

func _reset_control(points:Dictionary)->void:
	await press("Ⅱ")
	for member:Dictionary in app.household.members:
		await _select(str(member.id));member.sim.autonomy=false
		while not member.sim.action_queue.is_empty():app.cancel_current_action()
		app._clear_motion();app._store_motion()
	check(app.traversal.stairs.values().all(func(lock:Dictionary):return str(lock.owner).is_empty()),"Fixture starts without a live stair owner.")
	for id:String in app.world.actors:
		if id in ["maya","leo"]:
			app.world.set_actor_away(id,true,true)
			app.residents.locations[app.current_venue][id].phase="home";app.residents.locations[app.current_venue][id].wait=999999.0
	var defaults:Dictionary={"player":Vector3(-5,.16,6),"housemate_1":Vector3(3,.16,6),"housemate_2":Vector3(5,.16,6),"housemate_3":Vector3(7,.16,6)}
	defaults.merge(points,true)
	for id:String in defaults:
		app.world.actors[id].position=defaults[id];app.world.set_actor_away(id,false,false)
		if id in ["maya","leo"]:
			app.residents.locations[app.current_venue][id].position=vec(defaults[id]);app.residents.locations[app.current_venue][id].phase="walking" if app.current_venue=="home" else "visiting";app.residents.locations[app.current_venue][id].wait=999999.0
	if app.current_venue=="home":
		var restored:=LifeResidents.new(app);restored.restore(app.residents.snapshot())
		check(restored.locations.home==app.residents.snapshot().locations.home,"Controlled home resident facts use the supported saved lifecycle exactly.")
	await _select("player");app._refresh_sim_targets(false)

func _chat(id:String)->void:
	await _open_item({"id":id,"kind":"neighbor","label":str(app.world.actors[id].get_meta("display_name")),"node":app.world.actors[id],"size":Vector2(.6,.6)})
	await press("Have a friendly chat")

func _steps(count:int)->void:
	for i:int in range(count):app._process(.05);await frames(1)

func _until(condition:Callable,limit:int,label_text:String)->bool:
	await press("▶▶▶")
	for i:int in range(limit):
		if condition.call():await press("Ⅱ");return true
		await _steps(1)
	await press("Ⅱ");check(false,label_text);return false

func _saved_control(label_text:String)->void:
	await press("Ⅱ");await _public_save(label_text)
	var read:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	if not bool(read.ok):_event("control_save_failure",{"label":label_text,"notice":app.notice_label.text});return
	control_saves.append({"name":label_text,"slot":app.active_save_id,"data":read.data,"friendship":app.sim.relationships.duplicate(true),"funds":app.household.funds})

func _curb_control()->void:
	# Day 1 parks the weekly van at (-4.6, 8.5). Its solid band is about
	# x -5.9..-3.3, z 7.6..9, so the old pair stood inside the van and every
	# approach was refused before a route existed. This pair is the same
	# sidewalk, east of that band.
	await _reset_control({"player":Vector3(-2.0,.16,8.25),"leo":Vector3(-1.25,.16,8.65)})
	var before:float=app.sim.relationships.leo.friendship
	await _chat("leo")
	await _open_item(first_item("bookshelf"));await press("Read a book")
	var action:Dictionary=app.sim.get_current_action();var destination:Vector3=action.target_position
	check(destination.distance_to(app.world.actors.leo.position)>=LifeTraversal.ROUTE_CLEARANCE,"Curb conversation admits an endpoint outside target body clearance.")
	app._refresh_sim_targets(false)
	check(action.target_position==destination and app.traversal.routes.get("player",{}).get("destination")==destination,"Non-replanning refresh preserves admitted action/route destination exactly.")
	await _saved_control("Social control — curb approach")
	var completed_before:int=control_completions.size()
	var finished:bool=await _until(func():return control_completions.slice(completed_before).any(func(e:Dictionary):return e.id=="player" and str(e.action.id)=="friendly"),90,"Curb social reaches and completes through routed movement.")
	check(finished and float(app.sim.relationships.leo.friendship)>before,"Only actual completed curb conversation earns friendship.")
	check(app.sim.action_queue.any(func(a:Dictionary):return a.id=="read") or control_completions.slice(completed_before).any(func(e:Dictionary):return e.id=="player" and str(e.action.id)=="read"),"The explicit later reading survives the social route.")

func _moved_control()->void:
	await _reset_control({"player":Vector3(-5.5,.16,6),"housemate_1":Vector3(-4,.16,6)})
	await _chat("housemate_1")
	var active:bool=await _until(func():return app.sim.get_current_action().get("phase")=="active",40,"Household conversation physically begins.")
	if not active:return
	await press("▶▶▶");await _steps(2);await press("Ⅱ")
	var action:Dictionary=app.sim.get_current_action();var elapsed_before:float=action.elapsed;var friendship_before:float=app.sim.relationships.housemate_1.friendship
	check(bool(action.paid) and elapsed_before>0 and elapsed_before<float(action.duration),"Moved-target fixture has genuine partial paid social progress.")
	await _saved_control("Social control — partial household chat")
	var position_before:Vector3=app.player.position
	app.world.actors.housemate_1.position=Vector3(0,.16,6)
	app._refresh_sim_targets(false)
	check(action.phase=="approach" and float(action.elapsed)==elapsed_before and bool(action.paid),"Target movement re-admits the paid action without granting or resetting progress.")
	check(app.player.position==position_before and app.traversal.routes.get("player",{}).get("destination")==action.target_position,"Retargeting changes the owned route atomically without moving the initiator.")
	await press("Build & buy")
	check(app.sim.get_current_action().target_position==action.target_position and app.traversal.routes.player.destination==action.target_position,"Build entry retains exact social action/journey identity before another simulation step.")
	await press("Live");await _saved_control("Social control — moved household approach")
	await press("▶▶▶");await _steps(1);await press("Ⅱ")
	check(float(action.elapsed)==elapsed_before and float(app.sim.relationships.housemate_1.friendship)==friendship_before,"Moving toward the new household endpoint earns no stale social progress or reward.")
	var finished:bool=await _until(func():return not app.sim.action_queue.has(action),90,"Moved household conversation re-arrives and completes.")
	check(finished and float(app.sim.relationships.housemate_1.friendship)>friendship_before,"Re-admitted household conversation earns one real completion.")

func _blocked_control()->void:
	var center:=Vector3(-4,.16,6)
	await _reset_control({"player":Vector3(-7,.16,6),"housemate_1":center,"housemate_2":center+Vector3(.65,0,.65),"housemate_3":center+Vector3(-.65,0,.65),"maya":center+Vector3(.65,0,-.65),"leo":center+Vector3(-.65,0,-.65)})
	var before:float=app.sim.relationships.housemate_1.friendship
	await _chat("housemate_1")
	await _open_item(first_item("bookshelf"));await press("Read a book")
	await frames(2)
	check(not app.sim.action_queue.any(func(a:Dictionary):return a.id=="friendly"),"No-space admission refuses the conversation without weakening body clearance.")
	check(float(app.sim.relationships.housemate_1.friendship)==before,"Refused conversation earns no friendship.")
	# Remove the controlled blockers after refusal; the later public reading
	# instruction must retain its own original resource, then route normally.
	app.world.set_actor_away("maya",true,true);app.world.set_actor_away("leo",true,true)
	for id:String in ["housemate_1","housemate_2","housemate_3"]:app.world.actors[id].position=Vector3(3+2*["housemate_1","housemate_2","housemate_3"].find(id),.16,6)
	var completed_before:int=control_completions.size()
	var finished:bool=await _until(func():return control_completions.slice(completed_before).any(func(e:Dictionary):return e.id=="player" and str(e.action.id)=="read"),180,"Explicit reading proceeds after refused conversation.")
	check(finished,"Refusal preserves subsequent explicit queue work.")

func _stairs_control()->void:
	await _reset_control({"player":Vector3(-1.5,.16,-3.5),"housemate_1":Vector3(0,3.16,1)})
	await _chat("housemate_1")
	var entered:bool=await _until(func():return app.traversal.busy("player") and app.traversal.routes.player.phase=="transit",150,"Initiator physically enters the existing stair while approaching upstairs household target.")
	if not entered:return
	var action:Dictionary=app.sim.get_current_action();var destination:Vector3=action.target_position;var identity:int=app.traversal.routes.player.identity;var at:Vector3=app.player.position;var score:float=app.sim.relationships.housemate_1.friendship
	app.world.actors.housemate_1.position=Vector3(0,.16,6)
	app._refresh_sim_targets(false)
	check(app.traversal.busy("player") and int(app.traversal.routes.player.identity)==identity and action.target_position==destination and app.player.position==at,"Moved target cannot steal or retarget the initiating actor's protected stair crossing.")
	var paid_before:float=action.elapsed
	var cleared:bool=await _until(func():return not app.traversal.busy("player"),80,"Protected ascent physically clears its original landing.")
	check(cleared and float(action.elapsed)==paid_before and float(app.sim.relationships.housemate_1.friendship)==score,"Clearing the old stair destination grants no social time or friendship.")
	await press("▶▶▶");await _steps(1);await press("Ⅱ")
	check(action.phase=="approach" and app.world.point_level(action.target_position)==0 and app.traversal.routes.get("player",{}).get("destination")==action.target_position,"After protected clearance, moved-floor target receives a new matching route.")
	var finished:bool=await _until(func():return not app.sim.action_queue.has(action),220,"Initiator descends and actually completes the relocated conversation.")
	check(finished and float(app.sim.relationships.housemate_1.friendship)>score,"Only actual re-arrival after the protected crossing earns social reward.")

func _target_stairs_control()->void:
	await _reset_control({"player":Vector3(-5,.16,6),"housemate_1":Vector3(-1.5,.16,-3.5)})
	await _select("housemate_1")
	var upper:Dictionary={}
	for item:Dictionary in app.world.items:
		if str(item.kind)=="bed" and app.world.item_level(item)==1:upper=item;break
	await _open_item(upper);await press("Take a nap")
	var entered:bool=await _until(func():return app.traversal.busy("housemate_1") and app.traversal.routes.housemate_1.phase=="transit",150,"Target physically enters a protected stair crossing.")
	if not entered:return
	var identity:int=app.traversal.routes.housemate_1.identity;var at:Vector3=app.world.actors.housemate_1.position
	await _select("player");var score:float=app.sim.relationships.housemate_1.friendship
	await _chat("housemate_1")
	check(not app.sim.action_queue.any(func(a:Dictionary):return a.id=="friendly"),"Target in transit explicitly refuses the current conversation.")
	check(app.notice_label.text.contains("using the stairs"),"Target-transit refusal explains when the other Lifelet can be approached.")
	check(app.traversal.busy("housemate_1") and int(app.traversal.routes.housemate_1.identity)==identity and app.world.actors.housemate_1.position==at,"Refusal leaves the target's protected physical crossing untouched.")
	check(float(app.sim.relationships.housemate_1.friendship)==score,"Target-transit refusal earns no social reward.")
	await _open_item(first_item("bookshelf"));await press("Read a book")
	var before:int=control_completions.size()
	var finished:bool=await _until(func():return control_completions.slice(before).any(func(e:Dictionary):return e.id=="player" and str(e.action.id)=="read"),200,"Later explicit reading proceeds after target-transit refusal.")
	check(finished,"Target-transit policy preserves the later queue rather than claiming retained conversation.")

func _legacy_control()->void:
	await _reset_control({})
	var canonical:bool=not app.world.construction.building_state.is_empty()
	var previous_occupied:Array[Vector3]=app.traversal._occupied("player") if canonical else []
	var corrected_occupied:Array[Vector3]=[]
	if canonical:corrected_occupied=app.traversal._occupied("player")
	check(var_to_bytes(previous_occupied)==var_to_bytes(corrected_occupied),"Typed-empty-array correction preserves canonical occupied-body bytes exactly.")
	await press("Explore");await press(str(LifeNeighborhood.PLACES.park.name));await press("Travel here",true)
	for i:int in range(600):
		if app.mode=="live" and app.current_venue=="park":break
		await _steps(1)
	var arrived:bool=app.mode=="live" and app.current_venue=="park"
	check(arrived,"Ordinary public car trip reaches the legacy park venue.")
	if not arrived:return
	check(app.world.construction.building_state.is_empty(),"Legacy social control uses the unversioned venue navigation path.")
	await _reset_control({"player":Vector3(-2,.16,5.5),"maya":Vector3(-2,.16,7)})
	var score:float=app.sim.relationships.maya.friendship
	await _chat("maya")
	var admitted:Dictionary=app.sim.get_current_action()
	var destination:Vector3=admitted.target_position
	var cell:=Vector2i(roundi(destination.x*4),roundi(destination.z*4))
	check(app.world.navigation.region.has_point(cell) and not app.world.navigation.is_point_solid(cell),"Legacy social endpoint is supported by the actual grid.")
	check(destination.distance_to(app.world.actors.maya.position)>=LifeTraversal.ROUTE_CLEARANCE and not app.path.is_empty() and app.path[-1]==destination,"Legacy endpoint remains body-clear and matches the real route exactly.")
	_event("legacy_admission",{"destination":vec(destination),"target":vec(app.world.actors.maya.position),"body_distance":destination.distance_to(app.world.actors.maya.position),"route_end":vec(app.path[-1]) if not app.path.is_empty() else []})
	var before:int=control_completions.size()
	var finished:bool=await _until(func():return control_completions.slice(before).any(func(e:Dictionary):return e.id=="player" and str(e.action.id)=="friendly"),90,"Legacy venue conversation reaches and completes normally.")
	check(finished and float(app.sim.relationships.maya.friendship)>score,"Noncanonical social fallback retains actual conversation and reward flow.")

func _fresh_controls()->void:
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://social_controls_expected.json"))
	check(not expected.is_empty(),"Fresh controls read their producer receipt.")
	if expected.is_empty():return
	for stored:Dictionary in expected.saves:
		if app.mode=="menu":await press("Saved lives")
		else:await press("PauseMenu");await press("Load a saved life")
		var chosen:Button
		for n:Node in app.find_children("*","Button",true,false):
			if n.is_visible_in_tree() and str(n.get_meta("save_id",""))==str(stored.slot):chosen=n;break
		check(is_instance_valid(chosen),"Public picker contains exact saved social control: "+str(stored.name))
		if not is_instance_valid(chosen):continue
		chosen.pressed.emit();await frames(2);await press("Load selected life",true)
		if is_instance_valid(button_matching("Continue without saving")):await press("Continue without saving")
		var loaded:bool=app.active_save_id==str(stored.slot) and app.mode=="live" and app.household.speed==0
		_event("fresh_load_result",{"slot":stored.slot,"active":app.active_save_id,"mode":app.mode,"speed":app.household.speed,"notice":app.notice_label.text,"visible_labels":app.find_children("*","Label",true,false).filter(func(n:Node):return n.is_visible_in_tree()).map(func(n:Node):return n.text)})
		check(loaded,"Fresh public load retains paused social checkpoint.")
		if not loaded:return
		var decoded:Dictionary=LifeSaveLibrary.read_slot(str(stored.slot)).data
		for record:Dictionary in decoded.members:
			var sim:LifeSim=app.household.member_sim(str(record.id));check(sim.action_queue.size()==record.state.action_queue.size(),"Fresh full queue size: "+str(record.id))
			for i:int in range(mini(sim.action_queue.size(),record.state.action_queue.size())):
				var a:Dictionary=sim.action_queue[i];var b:Dictionary=record.state.action_queue[i];var p:Array=b.target_position
				check(a.target_position==Vector3(p[0],p[1],p[2]) and a.id==b.id and a.target_id==b.target_id and a.phase==b.phase and float(a.elapsed)==float(b.elapsed) and a.paid==b.paid,"Fresh typed target and exact decoded action/progress/paid state: "+str(record.id))
		var before:Dictionary=app.household.get_state(app.world.serialize_items());var route:Dictionary=app.traversal.snapshot()
		await _steps(10)
		check(app.household.get_state(app.world.serialize_items())==before and app.traversal.snapshot()==route,"Ordinary paused frames preserve physical route, queues, clock, funds and needs.")
		app._refresh_sim_targets(false)
		check(app.traversal.snapshot()==route,"Non-replanning refresh preserves restored social journey before resumed time.")
		var action:Dictionary=app.sim.get_current_action();var social_id:String=str(action.get("target_id",""));var score:float=app.sim.relationships[social_id].friendship
		var ended:Array=[]
		app.household.member_action_finished.connect(func(id:String,a:Dictionary):
			if id=="player" and str(a.id)=="friendly" and str(a.target_id)==social_id:ended.append(a.duplicate(true)))
		var finished:bool=await _until(func():return ended.size()>0,160,"Fresh social checkpoint resumes to an actual completion.")
		check(finished and ended.size()==1 and float(app.sim.relationships[social_id].friendship)>score,"Fresh resumed conversation earns exactly one completed social result.")
		var earned:float=app.sim.relationships[social_id].friendship
		await press("▶▶▶");await _steps(10);await press("Ⅱ")
		check(ended.size()==1 and float(app.sim.relationships[social_id].friendship)==earned,"Later frames do not duplicate the restored conversation reward.")

func screenshot(label_text:String,_focus:bool=false,_pause:bool=true)->void:
	# This headless composition has no rendering or native pointer claim.
	_event("capture_requested",{"label":label_text,"headless":true})


func mouse_move(screen:Vector2)->void:
	# Never use the inherited native Input.warp_mouse helper.
	var e:=InputEventMouseMotion.new();e.position=screen;e.global_position=screen
	Input.parse_input_event(e);await frames(2)


func _create_composed()->void:
	await _enter_new_game()
	for index:int in range(4):
		if index>0:await press("+ Add Lifelet")
		await press("Male" if index%2==0 else "Female")
		var field:LineEdit=app.find_children("*","LineEdit",true,false)[0]
		field.text=NAMES[index];field.text_changed.emit(field.text)
		var age:OptionButton=app.find_child("CreatorAge",true,false)
		var found:bool=false
		for i:int in range(age.item_count):
			if age.get_item_text(i)==AGES[index]:age.select(i);age.item_selected.emit(i);found=true;break
		check(found,"Public creator age option: "+AGES[index])
		await frames(2)
		await press(["Curls","Bob","Crop","Bob"][index])
	await press_member(NAMES[0]);await press("Find my home",true);await press("Willow Cottage");await press("Start living",true);await press("Ⅱ")
	check(app.household.members.size()==4 and app.household.funds==6250 and app.household.day==1 and app.household.minutes==480,"Ordinary public move-in starts four Lifelets at Day 1 08:00 with ℒ6250.")
	for i:int in range(4):
		var sim:LifeSim=app.household.members[i].sim
		check(sim.character.name==NAMES[i] and sim.character.age_stage==AGES[i].to_lower() and sim.autonomy,"Public member identity, age and default autonomy: "+NAMES[i])
		print("CREATED ",JSON.stringify(sim.get_state()))
	await press("Build & buy");await press("Structure");await press("Upper");await press("Floor")
	var funds_before:int=app.household.funds
	await _ground_click(Vector3(-6,3.16,-3));await _ground_click(Vector3(6,3.16,3))
	check(app.household.funds==funds_before-864,"Supported partial upper floor charges its actual ℒ864 area quote.")
	if not failures.is_empty():return
	await press("Ground");await press("Stairs");await _ground_click(Vector3(-1.5,.16,-2.5))
	check(app.world.construction.snapshot().stairs.size()==1 and app.household.funds==4736,"Public stair click installs a paid supported stair and opening for ℒ650.")
	if not failures.is_empty():return
	await press("Upper")
	await _buy_control("bed","Comfort",Vector3(-4.25,3.16,-1.0))
	check(app.household.funds==3896,"Honest two-storey furnishing budget retains ℒ3896 before earned income and cooking.")
	check(Building.validate(app.world.construction.snapshot()).is_empty(),"Publicly purchased architecture validates.")
	await press("Live")
	audit["fixture"]={"lot":"Willow Cottage","starting_funds":6250,"remaining_funds":app.household.funds,"world":app.world.serialize_items(),"members":app.household.members.map(func(m:Dictionary):return {"id":m.id,"name":m.sim.character.name,"age":m.sim.character.age_stage}),"controls":"Menu/button signals; structural viewport click events; furnishing catalog buttons and production placement_requested signal. No native pointer/preview proof. app automatic processing disabled; ordinary manual _process(.05) at public speed 8."}
	for m:Dictionary in app.household.members:
		audit.members[m.id]={"minimum_needs":m.sim.needs.duplicate(true),"critical_minutes":{},"waiting_minutes":0.0,"idle_minutes":0.0,"max_stationary_approach":0.0,"stationary_minutes":0.0,"last_position":[],"last_signature":""}
		for need:String in LifeSim.NEED_NAMES:audit.members[m.id].critical_minutes[need]=0.0
	_event("setup",audit.fixture)


func _buy_control(kind:String,category:String,point:Vector3)->void:
	await press(category)
	var label_text:String=str(LifeCatalog.ITEMS[kind].label)
	var card_button:Button
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and str(node.tooltip_text).begins_with(label_text+" ·"):card_button=node;break
	check(is_instance_valid(card_button),"Public catalog card: "+label_text)
	if not is_instance_valid(card_button):return
	card_button.pressed.emit();await frames(2)
	check(app.world.can_place(kind,point,0),"Production furnishing placement validates: "+label_text)
	var before:int=app.household.funds
	app.world.placement_requested.emit(kind,point,0.0);await frames(2)
	check(app.household.funds==before-int(LifeCatalog.ITEMS[kind].price),"Production Build placement handler charges catalog cost: "+label_text)
	_event("purchase",{"kind":kind,"position":vec(point),"cost":before-app.household.funds,"funds":app.household.funds,"control":"catalog button + placement_requested signal; no pointer preview claim"})
	var cancel:=InputEventKey.new();cancel.keycode=KEY_ESCAPE;cancel.pressed=true;Input.parse_input_event(cancel);await frames(2)


func _event(kind:String,data:Dictionary)->void:
	var row:Dictionary={"kind":kind,"phase":phase,"at":_now() if is_instance_valid(app) and is_instance_valid(app.household) else 0.0,"data":data.duplicate(true)}
	audit.events.append(row)
	if event_file:event_file.store_line(JSON.stringify(LifeSaveLibrary._json_safe(row),"",true,true));event_file.flush()


func _now()->float:
	return float(app.household.day-1)*1440.0+app.household.minutes


func _select(id:String)->void:
	await press_member(str(app.household.member_sim(id).character.name))


func _open_item(item:Dictionary)->void:
	app.world.object_clicked.emit(item,Vector2(850,360));await frames(2)


func _finish()->void:
	audit["assertions"]=assertions;audit["failures"]=failures;audit["receipts"]=receipts
	audit["at"]=_now();audit["phase"]=phase_tag
	if event_file:event_file.close()
	var ambience:WeakRef=weakref(app.ambience_player.stream)
	var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free();await frames(2)
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Private app ambience releases before process exit.")
	audit["assertions"]=assertions;audit["failures"]=failures
	var f:=FileAccess.open(screenshot_dir.path_join(phase_tag+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(LifeSaveLibrary._json_safe(audit),"  ",true,true));f.close()
	print("SOCIAL_NAV_RESULT assertions=%d failures=%d phase=%s"%[assertions,failures.size(),phase_tag])
	quit(0 if failures.is_empty() else 1)
