extends "res://tests/test_recipe_playthrough.gd"
## Three real rendered processes. Only pre-play fixture writes are adult Cooking
## XP and autonomy=false; no actor placement, need, clock, progress or arrivals.
var oven_stage:int=1
var verify_only:bool=false
var oven_trace:Array=[]
var oven_events:Array=[]
var observe_oven:bool=false
var starting_position:Vector3
var trace_frame:int=0
var wallet_events:Array=[]
var last_wallet:int=-1

class OvenObserver extends Node:
	var harness:SceneTree
	func _process(delta:float)->void:harness._observe_oven(delta)

func _run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument=="--oven-verify-only":verify_only=true
		if argument.begins_with("--oven-stage="):oven_stage=int(argument.trim_prefix("--oven-stage="))
	screenshot_dir="res://art/oven_playthrough";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	var observer:=OvenObserver.new();observer.harness=self;app.add_child(observer)
	app.household.member_action_finished.connect(func(person:String,action:Dictionary):
		member_completed.append(person+":"+str(action.id));oven_events.append({"person":person,"id":str(action.id),"recipe":str(action.get("recipe","")),"day":app.household.day,"minutes":app.household.minutes}))
	if oven_stage==1:await _start_bake()
	else:
		var expected_path:String="user://oven_stage_%d_expected.json"%(oven_stage-1)
		check(FileAccess.file_exists(expected_path),"Previous process wrote its named-save expectation.")
		if FileAccess.file_exists(expected_path):
			expected=JSON.parse_string(FileAccess.get_file_as_string(expected_path));oven_events=expected.events.duplicate(true)
			wallet_events=expected.wallet_events.duplicate(true);last_wallet=int(expected.funds)
			await _load_oven_save();await frames(5)
			await _verify_paused_restore()
			if failures.is_empty() and not verify_only:
				observe_oven=true;observing_motion=true
				if oven_stage==2:await _save_inside()
				elif oven_stage==3:await _finish_bake()
	_write_oven_report();observe_oven=false;observing_motion=false;app.queue_free();await frames(4)
	print("OVEN_PUBLIC stage=%d assertions=%d failures=%d"%[oven_stage,assertions,failures.size()]);quit(0 if failures.is_empty() else 1)

func _start_bake()->void:
	await _enter_new_game();await _age("Adult")
	await press("Find my home",true);await press("Start living",true);await press("Ⅱ")
	app.sim.autonomy=false
	app.sim._gain_skill("cooking",450.0) # Declared unlock fixture, not natural skill-progression evidence.
	check(int(app.sim.skills.cooking.level)==4,"Explicit fixture XP unlocks Cooking level4 before any cooking.")
	check(app.player.has_method("reconstruct_cooking_pose"),"The frozen actor exposes zero-time paused cooking reconstruction.")
	if not failures.is_empty():return
	expected={"funds_before":app.household.funds,"wants_before":app.sim.wants.duplicate(true)}
	last_wallet=app.household.funds
	check(not bool(app.sim.wants.filter(func(w:Dictionary)->bool:return str(w.id)=="first_meal")[0].complete),"The first-meal reward is genuinely unearned before the cook.")
	starting_position=app.player.position
	await open_cookbook();await press("Cook harvest vegetable bake")
	check(app.sim.get_current_action().get("recipe")=="harvest_bake" and not bool(app.sim.get_current_action().get("paid",true)),"Public recipe choice queues an unpaid harvest bake.")
	check(app.household.funds==int(expected.funds_before),"Recipe selection does not charge before physical arrival.")
	await queue_via_menu("bookshelf","read")
	check(app.sim.action_queue.size()==2 and str(app.sim.action_queue[1].id)=="read" and not bool(app.sim.action_queue[1].autonomous),"A later explicit reading instruction is queued through its public furniture menu.")
	observe_oven=true;observing_motion=true
	await press("▶")
	if not await wait_until(func()->bool:return active_is("cook"),"real physical approach to the oven",45):return
	var current:Dictionary=app.sim.get_current_action()
	check(app.player.position.distance_to(starting_position)>.5 and app.player.position.distance_to(current.target_position)<.02,"The cook moved through real frames and reached the exact oven endpoint.")
	check(app.household.funds==int(expected.funds_before)-24 and bool(current.paid),"Actual arrival charges the one ℒ24 ingredient payment.")
	if not await wait_until(_mid_load,"actual dish insertion midway between held and rack transforms",90):return
	await press("Ⅱ");await frames(3)
	check(_phase()=="load" and _transfer_fraction()>.1 and _transfer_fraction()<.9,"The first pause captures a transfer, rather than a fully held or interior dish.")
	_assert_preparation("mid-transfer")
	await _save_checkpoint("Oven — loading in progress",1)

func _load_oven_save()->void:
	await press("Saved lives")
	var chosen:Button=null
	for candidate:Node in app.find_children("*","Button",true,false):
		if str(candidate.get_meta("save_id",""))==str(expected.save_id):chosen=candidate;break
	check(is_instance_valid(chosen) and chosen.is_visible_in_tree() and not chosen.disabled,"The saved-life picker exposes the exact named checkpoint row.")
	if not is_instance_valid(chosen):return
	chosen.pressed.emit();await frames(3)
	await press("Load selected life",true)

func _phase()->String:
	var current:Dictionary=app.sim.get_current_action()
	return LifeOvenSequence.phase(float(current.progress)) if str(current.get("id",""))=="cook" else ""

func _transfer_fraction()->float:
	var oven:Dictionary=first_item("stove")
	if oven.is_empty():return -1
	var rack:Node3D=oven.node.find_child("OvenRack",true,false)
	if not is_instance_valid(rack):return -1
	# Query the production interpolation on a one-metre reference span. This
	# observes the current paid progress; it never writes simulation or pose.
	var held:=Transform3D(Basis.IDENTITY,rack.global_position+Vector3(0,0,1))
	return 1.0-LifeOvenSequence.tray(oven.node,float(app.sim.get_current_action().get("progress",0)),held).origin.distance_to(rack.global_position)

func _mid_load()->bool:
	return active_is("cook") and _phase()=="load" and _transfer_fraction()>=.3 and _transfer_fraction()<=.7

func _save_inside()->void:
	await press("▶")
	if not await wait_until(func()->bool:return active_is("cook") and _phase()=="bake","closed oven with the dish actually inside",100):return
	await press("Ⅱ");await frames(3)
	check(_phase()=="bake" and LifeOvenSequence.inside(float(app.sim.get_current_action().progress)),"The second pause captures the oven's closed interior baking phase.")
	_assert_preparation("closed inside")
	await _save_checkpoint("Oven — baking inside",2)

func _assert_preparation(label:String)->void:
	var action:Dictionary=app.sim.get_current_action();var oven:Dictionary=app._find_item(str(action.target_id))
	var inside:bool=LifeOvenSequence.inside(float(action.progress))
	check(app.sim.speed==0 and bool(action.paid) and str(action.recipe)=="harvest_bake",label+": paused paid recipe is unchanged.")
	check(app.household.funds==int(expected.funds_before)-24 and app.household.meals.batches.is_empty(),label+": exactly one ingredient charge and no prematurely edible batch.")
	check(app.sim.action_queue.size()==2 and str(app.sim.action_queue[1].id)=="read",label+": the later reading queue survives.")
	check(is_instance_valid(oven.node.find_child("OvenDoor",true,false)) and absf(oven.node.find_child("OvenDoor",true,false).rotation.x-PI*.5*LifeOvenSequence.door_open(float(action.progress)))<.002,label+": actual door matches the persisted cooking phase.")
	check(app.world.oven_food_views.size()==(1 if inside else 0),label+": exactly one world interior dish exists only in its owning phase.")
	check(app.player._baking_tray.visible!=inside,label+": the transfer tray and world interior dish never display together.")
	if inside:
		var rack:Node3D=oven.node.find_child("OvenRack",true,false)
		check(app.world.oven_food_views[str(action.target_id)].global_position.distance_to(rack.global_position)<.005,label+": interior dish rests at the authored rack.")

func _snapshot()->Dictionary:
	var action:Dictionary=app.sim.get_current_action()
	var oven:Dictionary=app._find_item(str(action.get("target_id","")))
	var door:Node3D=oven.node.find_child("OvenDoor",true,false) if not oven.is_empty() else null
	var current_world:Node3D=app.world.oven_food_views.get(str(action.get("target_id","")))
	return {"day":app.household.day,"minutes":app.household.minutes,"speed":app.sim.speed,"funds":app.household.funds,"action":app.sim._json_safe(action),"queue":app.sim._json_safe(app.sim.action_queue),"actor_position":vec(app.player.position),"actor_rotation":app.player.rotation.y,"model_position":vec(app.player._model.global_position),"tray_position":vec(app.player._baking_tray.global_position),"tray_visible":app.player._baking_tray.visible,"door_angle":door.rotation.x if is_instance_valid(door) else 0,"interior_position":vec(current_world.global_position) if is_instance_valid(current_world) else [],"interior_count":app.world.oven_food_views.size(),"food":app.household.meals.get_state(),"phase":_phase(),"transfer_fraction":_transfer_fraction(),"events":oven_events.duplicate(true),"wallet_events":wallet_events.duplicate(true),"wants":app.sim.wants.duplicate(true)}

func _save_checkpoint(title:String,index:int)->void:
	var before:Dictionary=_snapshot()
	await screenshot("%02d_before_save"%(index*2-1),true,false)
	await _public_save(title);await frames(3)
	check(app.sim.speed==0 and is_equal_approx(float(app.sim.get_current_action().elapsed),float(before.action.elapsed)),"Public save keeps pause and exact paid preparation time.")
	check(app.player.position.distance_to(Vector3(before.actor_position[0],before.actor_position[1],before.actor_position[2]))<.002,"Saving does not move the cook.")
	var state:Dictionary=_snapshot();state.funds_before=expected.funds_before;state.wants_before=expected.wants_before.duplicate(true);state.save_id=app.active_save_id;state.stage=index
	var file:=FileAccess.open("user://oven_stage_%d_expected.json"%index,FileAccess.WRITE);file.store_string(JSON.stringify(state,"  "));file.close()
	expected=state

func _verify_paused_restore()->void:
	check(app.active_save_id==str(expected.save_id),"The new process publicly loads the exact preceding named slot.")
	check(app.sim.speed==0 and is_equal_approx(float(app.sim.get_current_action().elapsed),float(expected.action.elapsed)),"Fresh-process load preserves pause and paid cooking time before any play.")
	check(app.household.day==int(expected.day) and is_equal_approx(app.household.minutes,float(expected.minutes)),"Paused reconstruction advances no game time.")
	check(app.player.position.distance_to(Vector3(expected.actor_position[0],expected.actor_position[1],expected.actor_position[2]))<.002,"Fresh process preserves the saved cook position.")
	check(app.sim.get_current_action().target_position.distance_to(Vector3(expected.action.target_position[0],expected.action.target_position[1],expected.action.target_position[2]))<.002,"Fresh process preserves the canonical oven route.")
	check(JSON.parse_string(JSON.stringify(app.household.meals.get_state()))==expected.food,"Fresh process retains the exact existing food ledger.")
	_assert_preparation("fresh stage%d"%oven_stage)
	check(app.action_label.text=="Preparing harvest vegetable bake","The paused restored preparation has the same readable activity title as before saving.")
	if bool(expected.tray_visible):
		check(app.player._baking_tray.global_position.distance_to(Vector3(expected.tray_position[0],expected.tray_position[1],expected.tray_position[2]))<.015,"Paused mid-transfer tray reconstructs within15mm of its saved physical position.")
	check(app.player._model.global_position.distance_to(Vector3(expected.model_position[0],expected.model_position[1],expected.model_position[2]))<.015,"Paused body pose reconstructs without a displaced model root.")
	await screenshot("%02d_fresh_process"%((oven_stage-1)*2),true,false)

func _finish_bake()->void:
	await press("▶")
	if not await wait_until(func()->bool:return active_is("cook") and _phase()=="unload" and _transfer_fraction()>.2 and _transfer_fraction()<.8,"actual extraction from the oven",100):return
	await press("Ⅱ");await frames(3);_assert_preparation("unloading")
	await screenshot("05_actual_unload",true,false)
	await press("▶")
	if not await wait_until(func()->bool:return not find_batch("harvest_bake").is_empty() and str(find_batch("harvest_bake").storage)=="surface","finished cooking and physical serving at a table",120):return
	await press("Ⅱ");await frames(3)
	var batch:Dictionary=find_batch("harvest_bake")
	check(app.household.meals.batches.size()==1 and int(batch.initial)==8 and int(batch.remaining)+int(batch.served)==8,"One completed bake creates exactly eight conserved servings.")
	_assert_completed_wallet("After serving")
	check(app.world.oven_food_views.is_empty() and not app.player._baking_tray.visible,"Serving leaves neither an oven duplicate nor a preparation tray.")
	check(oven_events.filter(func(event:Dictionary)->bool:return str(event.id)=="cook").size()==1 and oven_events.filter(func(event:Dictionary)->bool:return str(event.id)=="serve_meal").size()==1,"Cooking and serving each complete exactly once across all three processes.")
	await screenshot("06_eight_servings",false,false)
	await press("▶▶▶")
	if not await wait_until(func()->bool:return "player:read" in member_completed,"the queued later instruction completes after serving and any chosen portion",120):return
	await press("Ⅱ");await frames(3)
	check(app.household.meals.batches.size()==1,"The later activity introduces no second bake.")
	_assert_completed_wallet("After reading")
	await screenshot("07_later_instruction_finished",false,false)

func _assert_completed_wallet(label:String)->void:
	var earned:Array=[]
	for want:Dictionary in app.sim.wants:
		var before:Array=expected.wants_before.filter(func(w:Dictionary)->bool:return str(w.id)==str(want.id))
		if bool(want.complete) and not before.is_empty() and not bool(before[0].complete):earned.append(want)
	check(earned.size()==1 and str(earned[0].id)=="first_meal" and int(earned[0].reward)==60,label+": the actual first-meal wish earned its one ℒ60 reward.")
	check(wallet_events.filter(func(event:Dictionary)->bool:return int(event.delta)<0).map(func(event:Dictionary)->int:return int(event.delta))==[-24],label+": all observed debits contain exactly one ℒ24 ingredient charge across both restarts.")
	check(wallet_events.filter(func(event:Dictionary)->bool:return int(event.delta)>0).map(func(event:Dictionary)->int:return int(event.delta))==[60],label+": all observed credits contain exactly the one ℒ60 first-meal reward.")
	check(app.household.funds==int(expected.funds_before)-24+60,label+": the wallet accounts for ingredients and the independently verified earned reward.")

func _observe_oven(delta:float)->void:
	if not observe_oven or not is_instance_valid(app.player):return
	if last_wallet!=app.household.funds:
		wallet_events.append({"delta":app.household.funds-last_wallet,"funds":app.household.funds,"day":app.household.day,"minutes":app.household.minutes,"wants":app.sim.wants.duplicate(true)})
		last_wallet=app.household.funds
	observe_motion(delta);trace_frame+=1
	if trace_frame%3!=0:return
	oven_trace.append(_snapshot())

func _write_oven_report()->void:
	var result:Dictionary={"stage":oven_stage,"assertions":assertions,"failures":failures,"events":oven_events,"evidence":evidence,"trace":oven_trace,"max_motion_excess":motion_excess,"wallet_events":wallet_events,"method":"Actual rendered frames, public UI signals, three fresh processes. Only initial fixture writes: autonomy=false and Cooking XP450; no need/clock/progress/arrival injection."}
	var file:=FileAccess.open(screenshot_dir.path_join("stage_%d_results.json"%oven_stage),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
