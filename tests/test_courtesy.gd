extends "res://tests/test_public_twofloor.gd"
## Headless regression from an earned, public-creator/Build household checkpoint.
## The two courtesy participants keep real actions and serving custody. Natural
## continuations use one yielded frame after every ordinary .05 controller step.
## Named component fixtures are separate from that natural movement evidence.
var audit:Dictionary={"steps":[],"saves":[],"completions":[]}
var phase_tag:String="natural"
var baseline:bool=false

func _run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--courtesy-phase="):phase_tag=argument.trim_prefix("--courtesy-phase=")
	match phase_tag:
		"natural","natural_no_save":await _run_natural()
		"fresh":await _run_fresh()
		"controls":await _run_controls()
		"waiter_producer":await _run_waiter(true)
		"waiter_fresh":await _run_waiter(false)
		_:push_error("Unknown courtesy regression phase.");quit(2)


func _run_natural()->void:
	baseline="--baseline" in OS.get_cmdline_user_args()
	root.size=Vector2i(1440,900);screenshot_dir="res://evidence";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false)
	await frames(4);app.set_sound(false)
	var initial:Dictionary=LifeSaveLibrary.read_slot("life_1788942682044_57282849")
	print("INITIAL_SLOT ",JSON.stringify(initial if not bool(initial.ok) else {"ok":true}))
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LifeSaveLibrary._slot_path("life_1788942682044_57282849")))
	var j:Dictionary=raw.data.journeys
	print("FORMAT_DIAG ",JSON.stringify({"version":j.version,"type":typeof(j.version),"list":j.version in [1,LifeJourneyState.VERSION],"equal":j.version==1,"identity":LifeJourneyState.number(j.next_identity,1,1e9,true),"ticket":LifeJourneyState.number(j.next_ticket,1,1e9,true),"members":j.members is Dictionary,"writer":LifeJourneyState.VERSION}))
	await press("Saved lives")
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and str(node.get_meta("save_id",""))=="life_1788942682044_57282849":node.pressed.emit();await frames(2);break
	await press("Load selected life",true)
	check(app.mode=="live" and app.active_save_id=="life_1788942682044_57282849" and app.household.speed==0,"Actual named first-crowd v1 checkpoint freshly loads paused.")
	if not failures.is_empty():await _finish();return
	var starting:Dictionary=app.traversal.snapshot();var queues:Dictionary={}
	var food_before:Dictionary=app.household.meals.get_state()
	for member:Dictionary in app.household.members:queues[member.id]=member.sim.action_queue.duplicate(true)
	app.household.member_action_finished.connect(func(id:String,a:Dictionary):audit.completions.append({"id":id,"action":a.duplicate(true),"at":_now()}))
	check(not app.residents.home_visit.active(),"Natural crowd checkpoint has no active guest.")
	await press("▶")
	var retreat:bool=false;var held:bool=false;var pickup:bool=false
	for step:int in range(400):
		var started:int=Time.get_ticks_usec();app._process(.05);var elapsed:int=Time.get_ticks_usec()-started
		await frames(1)
		var record:Dictionary=_record();record["step"]=step;record["cpu_us"]=elapsed;audit.steps.append(record)
		if not baseline:
			var owner_id:String=app.traversal.courtesy.owner(app.traversal)
			if not owner_id.is_empty():
				var route:Dictionary=app.traversal.routes[owner_id];var fact:Dictionary=route.courtesy
				if not retreat and fact.phase=="retreat" and app.world.actors[owner_id].position.distance_to(route.courtesy_start)>.01:
					retreat=true
					var peer_id:String="housemate_2"
					var priority:PackedVector3Array=route.courtesy_priority
					check(owner_id=="housemate_1" and str(fact.beneficiary_id)==peer_id and str(fact.get("beneficiary_kind",""))=="action" and int(fact.beneficiary_identity)==int(starting.members[peer_id].motion.identity) and priority.size()>1 and priority[0]==LifeJourneyState.vector(starting.members[peer_id].position) and priority[-1]==LifeJourneyState.vector(starting.members[peer_id].motion.destination),"Natural Ellis retreat preserves Morgan's original pickup route and complete priority endpoints.")
					check(app.household.member_sim(owner_id).action_queue==queues[owner_id] and route.destination==LifeJourneyState.vector(starting.members[owner_id].motion.destination) and route.identity==starting.members[owner_id].motion.identity,"Natural retreat keeps the complete original donor queue, destination and identity.")
					await _save_phase("retreat");await press("▶")
				if not held and fact.phase=="hold":
					check(app.world.actors[owner_id].position==fact.anchor,"Natural donor physically reaches the selected anchor before holding.")
					held=true;await _save_phase("hold");await press("▶")
			var meal:Dictionary=app.household.member_sim("housemate_2").get_current_action()
			if str(meal.get("id",""))=="eat_meal" and str(meal.get("meal_stage",""))!="pickup":pickup=true
			if held and pickup and step>=100:break
		elif step>=100:break
	await press("Ⅱ")
	if baseline:
		check(app.world.actors.housemate_2.position==LifeJourneyState.vector(starting.members.housemate_2.position),"Matched baseline remains physically blocked over 101 ordinary steps.")
	else:
		check(retreat and held,"Natural continuation physically reaches retreat and hold phases.")
		var food_after:Dictionary=app.household.meals.get_state()
		check(int(food_after.serial)==int(food_before.serial)+1 and food_after.portions.size()==food_before.portions.size()+1 and float(food_after.batches[0].remaining)==float(food_before.batches[0].remaining)-1 and float(food_after.batches[0].served)==float(food_before.batches[0].served)+1 and food_after.portions[-1].owner=="housemate_2" and food_after.portions[-1].storage=="carried","Natural physical pickup issues exactly one serving and transfers custody to Morgan.")
		check(pickup,"Morgan physically reaches the real meal source and takes exactly one portion after courtesy.")
		check(app.traversal.courtesy.trace.any(func(e:Dictionary):return e.get("released","")=="housemate_1" and e.get("reason","")=="beneficiary_retired"),"The donor's hold releases when the beneficiary's original route retires.")
		audit["selection"]=app.traversal.courtesy.trace.duplicate(true)
		check(audit.selection.all(func(e:Dictionary):return int(e.get("queries",0))<=24) and _unique_selection_times(audit.selection),"Every advancing-step selection obeys its 24-query ceiling.")
		if failures.is_empty():await _save_phase("recovered")
	audit["final"]=_record();await _finish()

func _run_fresh()->void:
	root.size=Vector2i(1440,900);screenshot_dir="res://evidence";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var produced:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("natural.json")))
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false)
	await frames(4);app.set_sound(false)
	var saves:Array=produced.get("saves",[])
	check(saves.any(func(s:Dictionary):return s.phase=="retreat") and saves.any(func(s:Dictionary):return s.phase=="hold"),"Fresh process finds both real saved courtesy phases.")
	for entry:Dictionary in saves:
		if str(entry.phase) not in ["retreat","hold"]:continue
		await _load_slot(str(entry.slot))
		check(app.mode=="live" and app.active_save_id==str(entry.slot) and app.household.speed==0,"Fresh public load reconstructs paused "+str(entry.phase)+" ownership.")
		if app.active_save_id!=str(entry.slot):continue
		var disk:Dictionary=LifeSaveLibrary.read_slot(str(entry.slot)).data
		var motion:Dictionary=app.traversal.snapshot()
		print("FRESH_MISMATCH ",entry.phase," ",JSON.stringify(_differences(disk.journeys,motion)))
		if not audit.has("initials"):audit.initials=[]
		audit.initials.append({"phase":entry.phase,"disk":disk.journeys,"actual":motion})
		check(_same(_project_journeys(disk.journeys),motion),"Fresh "+str(entry.phase)+" journey facts match decoded disk with exact typed actor/vector projection; scalar deadline is unchanged.")
		for saved:Dictionary in disk.members:
			var id:String=str(saved.id);var sim:LifeSim=app.household.member_sim(id)
			check(_same(saved.state.action_queue,sim.action_queue),"Fresh exact full queue/progress/paid/target projection: "+id)
			check(app.world.actors[id].position==LifeJourneyState.vector(disk.journeys.members[id].position),"Fresh exact typed body: "+id)
		check(_same(disk.meals,app.household.meals.get_state()),"Fresh custody ledger equals authoritative decoded disk.")
		var before:Dictionary=_record()
		for i:int in range(10):app._process(.05);await frames(1)
		check(_record()==before,"Ten ordinary paused "+str(entry.phase)+" steps preserve all body/action/custody/deadline facts.")
		var owner_id:String=app.traversal.courtesy.owner(app.traversal)
		check(owner_id=="housemate_1" and app.traversal.routes[owner_id].courtesy_priority.size()>1,"Fresh priority corridor derives from saved current beneficiary body under donor-at-anchor.")
		var picked:bool=false;var minimum:float=INF;var household_minimum:float=INF;var pedestrian_minimum:float=INF
		await press("▶")
		for i:int in range(200):
			if _now()>=float(disk.journeys.members[owner_id].motion.courtesy.expires_at):break
			app._process(.05);await frames(1)
			var row:Dictionary=_record();row["fresh_phase"]=entry.phase;audit.steps.append(row)
			var pair_detail:Dictionary=_clearance_pairs();row["clearance"]=pair_detail
			minimum=minf(minimum,float(pair_detail.all_minimum))
			household_minimum=minf(household_minimum,float(pair_detail.household_minimum))
			pedestrian_minimum=minf(pedestrian_minimum,float(pair_detail.pedestrian_minimum))
			var meal:Dictionary=app.household.member_sim("housemate_2").get_current_action()
			if meal.get("id")=="eat_meal" and str(meal.get("meal_stage",""))!="pickup":picked=true;break
		await press("Ⅱ")
		check(picked,"Fresh "+str(entry.phase)+" continuation reaches real meal pickup through ordinary movement.")
		if not audit.has("clearance_summary"):audit.clearance_summary=[]
		audit.clearance_summary.append({"phase":entry.phase,"all":minimum,"household_vs_all":household_minimum,"pedestrian_only":pedestrian_minimum})
		check(household_minimum>=LifeTraversal.BODY_GAP-.000001,"Fresh "+str(entry.phase)+" household-versus-every-visible-actor clearance remains .72 m.")
		check(minimum>=LifeTraversal.BODY_GAP-.000001,"Fresh "+str(entry.phase)+" continuation preserves actual .72 m body clearance.")
		check(app.traversal.courtesy.trace.any(func(e:Dictionary):return e.get("released","")=="housemate_1" and e.get("reason","")=="beneficiary_retired"),"Fresh "+str(entry.phase)+" releases on actual beneficiary route retirement, not expiry.")
	await _finish()

func _run_controls()->void:
	root.size=Vector2i(1440,900);screenshot_dir="res://evidence";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var produced:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("natural.json")))
	var saves:Array=produced.get("saves",[]);var hold:Dictionary={}
	for entry:Dictionary in saves:
		if entry.phase=="hold":hold=entry;break
	check(not hold.is_empty(),"Controller controls use a real named hold from the natural route.")
	if hold.is_empty():quit(1);return
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false)
	await frames(4);app.set_sound(false)
	audit["scope"]="Controller mutation/validation fixtures. The producer and separate fresh process cover actual player flow. Corruption/resource/expiry inputs below are deliberate component-boundary controls, not natural progression."
	await _controller_load(str(hold.slot))
	var before:Dictionary=_record();var original:Dictionary=app.household.member_sim("housemate_1").get_current_action()
	var helper=app.traversal.courtesy
	var pedestrian:LifeActor=app.world.actors.leo;var old_position:Vector3=pedestrian.position;var old_visible:bool=pedestrian.visible
	pedestrian.visible=true;pedestrian.position=Vector3(14,.16,8.5)
	var far_key:Array=helper._positions(app.traversal)
	pedestrian.position=Vector3(14.25,.16,8.5)
	check(helper._positions(app.traversal)==far_key,"A distant passerby's movement does not invalidate the local negative-selection fingerprint.")
	pedestrian.position=Vector3(-1,.16,3)
	check(helper._positions(app.traversal)!=far_key,"A newly relevant nearby body invalidates the selection fingerprint.")
	pedestrian.position=old_position;pedestrian.visible=old_visible
	var corridor:PackedVector3Array=app.traversal.routes.housemate_1.courtesy_priority
	var reserved:Vector3=corridor[corridor.size()/2]
	check(not helper.point_allowed(app.traversal,"housemate_3",reserved) and not app.traversal._free("housemate_3",reserved),"An ordinary new wait/exit reservation cannot be granted through the beneficiary corridor.")

	app._refresh_sim_targets(false);app._refresh_sim_targets(true)
	check(_same_replan_facts(before,_record(),true) and is_same(original,app.household.member_sim("housemate_1").get_current_action()),"Both refresh modes retain exact courtesy and instruction facts; only other ordinary route IDs renew and food geometry projects to typed vectors.")
	var generation:int=app.world.lot_navigation.generation
	app.world.rebuild_navigation()
	var request:Dictionary=app.traversal.request("housemate_1",original.target_position)
	check(bool(request.ok) and app.world.lot_navigation.generation>generation and app.traversal.courtesy.generation_current(app.traversal),"Successful navigation rebuild regenerates courtesy geometry and retains ownership.")
	check(_same_replan_facts(before,_record(),true),"Navigation rebuild preserves bodies, targets, participant identities, queues, custody and deadline.")
	var invalid:Dictionary=app.world.construction.snapshot().duplicate(true);invalid.floors[0].level=8
	generation=app.world.lot_navigation.generation
	var failed_before:Dictionary=_record()
	var rejected:Dictionary=app.world.lot_navigation.rebuild(invalid,[])
	check(not bool(rejected.ok) and app.world.lot_navigation.generation==generation and _record()==failed_before,"Failed navigation rebuild retains the previous graph and all courtesy facts.")
	await _build_control()
	await _controller_load(str(hold.slot))
	await _resource_and_integrity(hold.data)
	await _expiry_control()
	await _controller_load(str(hold.slot))
	var donor_queue:Array=app.household.member_sim("housemate_1").action_queue.duplicate(true)
	var food:Dictionary=app.household.meals.get_state()
	app._bind_member("housemate_2");app.cancel_current_action();app._store_motion()
	check(app.traversal.courtesy.owner(app.traversal).is_empty() and app.household.member_sim("housemate_1").action_queue==donor_queue,"Cancelling the beneficiary releases only courtesy and preserves the donor's whole instruction queue.")
	check(app.household.meals.get_state()==food,"Cancelling an unclaimed pickup invents or discards no serving.")
	check(app.save_game("","Courtesy control — cancelled beneficiary"),"Immediate named save after beneficiary cancellation validates.")
	await _controller_load(str(hold.slot))
	app._bind_member("housemate_1")
	original=app.sim.get_current_action();var identity:int=app.traversal.routes.housemate_1.identity
	var target:Dictionary=app._find_item(str(original.target_id))
	app.cancel_current_action();app.queue_interaction(target,"paint");app._store_motion()
	check(app.traversal.courtesy.owner(app.traversal).is_empty() and not is_same(original,app.sim.get_current_action()) and int(app.traversal.routes.housemate_1.identity)!=identity,"Cancelling and requeueing the same target creates a new instruction, with no inherited courtesy ownership.")
	check(app.save_game("","Courtesy control — requeued target"),"Immediate same-target requeue save validates.")
	await _finish()

func _run_waiter(producer:bool)->void:
	root.size=Vector2i(1440,900);screenshot_dir="res://evidence";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false)
	await frames(4);app.set_sound(false)
	var slot:String="courtesy_arrived_waiter" if producer else "courtesy_arrived_resaved"
	if producer:
		var produced:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("natural.json")))
		var raw:Dictionary={}
		for entry:Dictionary in produced.saves:
			if entry.phase=="hold":raw=entry.data.duplicate(true);break
		check(not raw.is_empty(),"Arrived-waiter boundary derives from the natural hold checkpoint.")
		if raw.is_empty():await _finish();return
		# A declared component fixture: retire only Casey's already supported
		# approach as an arrived resource wait at the saved body. No actor,
		# action/paid/progress, needs, clock, funds or custody is edited.
		raw.journeys.members.housemate_3.motion={}
		for member:Dictionary in raw.members:
			if member.id=="housemate_3":member.state.character.world_state.resource_wait_started=float(raw.day-1)*1440.0+raw.minutes
		var result:Dictionary=LifeSaveLibrary.save_slot(slot,"Component fixture — arrived waiter with courtesy",raw)
		check(bool(result.ok),"Strict named writer accepts the supported arrived-waiter fixture: "+str(result.get("error","")))
		if not bool(result.ok):await _finish();return
	app.load_game(slot);app.set_process(false);await frames(3)
	check(app.active_save_id==slot and app.household.speed==0,"A fresh controller reconstructs the named arrived-waiter fixture paused.")
	if app.active_save_id!=slot:await _finish();return
	var disk:Dictionary=LifeSaveLibrary.read_slot(slot).data
	var body:Vector3=LifeJourneyState.vector(disk.journeys.members.housemate_3.position)
	var motion:Dictionary=app.motion_states.housemate_3
	check(motion.waiting and motion.wait_destination==body and not app.traversal.active("housemate_3") and motion.path.is_empty(),"Arrived resource waiter retains its exact saved body reservation and empty movement route.")
	check(app.traversal.courtesy._resource_waits(app.traversal,"",true)==app.traversal.courtesy._resource_waits(app.traversal,""),"Detached and runtime waiting reservations agree exactly after the same paused load.")
	check(app.traversal.courtesy.owner(app.traversal)=="housemate_1","Arrived waiter reconstruction preserves the valid donor hold.")
	check(_same(_project_journeys(disk.journeys),app.traversal.snapshot()),"The complete saved journey projection, including empty arrived-wait motion, is unchanged.")
	for member:Dictionary in disk.members:
		check(_same(member.state.action_queue,app.household.member_sim(str(member.id)).action_queue),"Arrived-wait restore preserves exact queue/paid/progress: "+str(member.id))
	check(_same(disk.meals,app.household.meals.get_state()),"Arrived-wait restore preserves exact decoded serving custody.")
	var before:Dictionary=_record()
	for i:int in range(10):app._process(.05);await frames(1)
	check(before==_record() and app.motion_states.housemate_3.wait_destination==body and not app.traversal.active("housemate_3"),"Ten ordinary paused frames retain arrived waiting and courtesy facts.")
	if producer:
		check(app.save_game("courtesy_arrived_resaved","Component fixture — arrived waiter resaved"),"Immediate production save preserves the reconstructed arrived wait.")
		var resaved:Dictionary=LifeSaveLibrary.read_slot("courtesy_arrived_resaved")
		check(bool(resaved.ok) and resaved.data.journeys.members.housemate_3.motion.is_empty(),"Rewritten arrived waiter remains explicitly motionless on disk.")
	else:
		app._bind_member("housemate_3");var action:Dictionary=app.sim.get_current_action();var available:bool=app._activity_available(action)
		check(available,"Fixture's unowned easel is available for ordinary resumed admission.")
		app.household.set_speed(1);app._advance_movement(.05);app._store_motion();app.household.set_speed(0)
		check(app.traversal.active("housemate_3") and app.traversal.routes.housemate_3.destination==action.target_position and app.motion_states.housemate_3.wait_destination==action.target_position,"Ordinary resumed admission chooses the real activity route instead of a stale restored route.")
		check(action.phase=="approach" and not bool(action.paid),"Resumed movement cannot begin/pay the action before physical arrival.")
	audit["final"]=_record();await _finish()

func screenshot(_label:String,_focus:bool=false,_pause:bool=true)->void:pass

func mouse_move(screen:Vector2)->void:
	var e:=InputEventMouseMotion.new();e.position=screen;e.global_position=screen
	Input.parse_input_event(e);await frames(2)

func _load_slot(slot:String)->void:
	if app.mode=="menu":await press("Saved lives")
	else:await press("PauseMenu");await press("Load a saved life")
	var row:Button
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and str(node.get_meta("save_id",""))==slot:row=node;break
	check(is_instance_valid(row),"Public picker contains expected saved row "+slot)
	if not is_instance_valid(row):return
	row.pressed.emit();await frames(3);await press("Load selected life",true)
	if is_instance_valid(button_matching("Continue without saving")):await press("Continue without saving")

func _same(disk:Variant,current:Variant)->bool:
	if current is Vector3:return disk is Array and disk.size()==3 and current==LifeJourneyState.vector(disk)
	if disk is Dictionary:
		if not current is Dictionary or disk.size()!=current.size():return false
		for key:Variant in disk:
			if not current.has(key) or not _same(disk[key],current[key]):return false
		return true
	if disk is Array:
		if not current is Array or disk.size()!=current.size():return false
		for i:int in disk.size():
			if not _same(disk[i],current[i]):return false
		return true
	return disk==current

func _minimum_gap()->float:
	var ids:Array=app.world.actors.keys();var value:float=INF
	for i:int in ids.size():
		var a:LifeActor=app.world.actors[ids[i]]
		if not a.visible:continue
		for j:int in range(i+1,ids.size()):
			var b:LifeActor=app.world.actors[ids[j]]
			if b.visible and absf(a.position.y-b.position.y)<.1:value=minf(value,a.position.distance_to(b.position))
	return value

func _now()->float:return float(app.household.day-1)*1440.0+app.household.minutes

func _record()->Dictionary:
	var people:Dictionary={}
	for member:Dictionary in app.household.members:
		var id:String=str(member.id)
		people[id]={"position":app.world.actors[id].position,"queue":member.sim.action_queue.duplicate(true),"needs":member.sim.needs.duplicate(true)}
	return {"at":_now(),"people":people,"journeys":app.traversal.snapshot(),"food":app.household.meals.get_state()}

func _json(value:Variant)->Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is PackedVector3Array:
		var result:Array=[]
		for point:Vector3 in value:result.append(_json(point))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[key]=_json(value[key])
		return result
	if value is Array:return value.map(_json)
	return value

func _unique_selection_times(rows:Array)->bool:
	var times:Array=[]
	for row:Dictionary in rows:
		if not row.has("queries"):continue
		if row.at in times:return false
		times.append(row.at)
	return true

func _differences(a:Variant,b:Variant,path:String="journeys")->Array:
	var result:Array=[]
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if b.has(key):result.append_array(_differences(a[key],b[key],path+"."+str(key)))
			else:result.append({"path":path+"."+str(key),"missing":true})
		for key:Variant in b:
			if not a.has(key):result.append({"path":path+"."+str(key),"extra":true})
	elif a is Array and b is Array and a.size()==b.size():
		for i:int in a.size():result.append_array(_differences(a[i],b[i],path+"["+str(i)+"]"))
	elif not _same(a,b):result.append({"path":path,"disk":a,"actual":b})
	return result

func _project_journeys(data:Dictionary)->Dictionary:
	var projected:Dictionary=data.duplicate(true)
	for record:Dictionary in projected.members.values():
		record.position=LifeJourneyState.packed(LifeJourneyState.vector(record.position))
		record.yaw=float(PackedFloat32Array([record.yaw])[0])
		var motion:Dictionary=record.motion
		if motion.is_empty():continue
		for key:String in ["destination","wait","clear"]:
			if not motion[key].is_empty():motion[key]=LifeJourneyState.packed(LifeJourneyState.vector(motion[key]))
		if motion.has("courtesy"):motion.courtesy.anchor=LifeJourneyState.packed(LifeJourneyState.vector(motion.courtesy.anchor))
	return projected

func _save_phase(label:String)->void:
	if label in ["retreat","hold"] and "--no-phase-saves" in OS.get_cmdline_user_args():return
	await press("Ⅱ")
	var before:Dictionary=_record();await _public_save("Natural courtesy — "+label)
	var loaded:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(app.active_save_name=="Natural courtesy — "+label and bool(loaded.ok),"Named courtesy "+label+" save validates: "+app.notice_label.text)
	if bool(loaded.ok):audit.saves.append({"phase":label,"slot":app.active_save_id,"data":loaded.data})
	var after:Dictionary=_record()
	check(before.people==after.people and before.food==after.food and before.at==after.at and before.journeys==after.journeys,"Saving "+label+" does not mutate paused bodies, queues, custody or movement facts.")
	for i:int in range(5):app._process(.05);await frames(1)
	check(_record()==after,"Ordinary paused steps preserve the saved "+label+" exactly.")

func _controller_load(slot:String)->void:
	app.load_game(slot);app.set_process(false);await frames(3)
	check(app.active_save_id==slot and app.household.speed==0 and app.traversal.courtesy.owner(app.traversal)=="housemate_1","Production named-load controller restores the paused hold fixture.")

func _build_control()->void:
	var before:Dictionary=_record();var funds:int=app.household.funds
	await press("Build & buy");await press("Ground")
	var plant:Dictionary=first_item("plant")
	app.show_build_object(plant,Vector2(760,350));await press("Move furnishing")
	check(not app.pending_move.is_empty(),"Public Build Move begins a real existing-plant placement.")
	app.cancel_placement();await frames(2)
	await press("Live")
	check(app.household.funds==funds and _same_replan_facts(before,_record(),true),"Cancelling the Build move and returning Live preserves paused courtesy, queues, bodies, custody and funds.")
	await press("Build & buy");await press("Ground")
	plant=app._find_item(str(plant.id));app.show_build_object(plant,Vector2(760,350));await press("Move furnishing")
	# The point must be one the production rules really accept, since the reach
	# rule refuses a spot that would seal the way to a furnishing — the old
	# hardcoded (4,-3) now blocks the rainfall shower and is correctly refused.
	# It must also be genuinely unrelated to the courtesy under test: moving the
	# plant across a participant's own route legitimately rebuilds the corridor
	# and retires the courtesy, which is a different assertion from this one.
	var participants:Array=[app.world.actors[str(app.household.selected_id())].position]
	for member:Dictionary in app.household.members:participants.append(app.world.actors[str(member.id)].position)
	# The courtesy's own holding anchor is the other place a move must miss: the
	# corridor runs donor-to-anchor, so a plant dropped on it is related by
	# definition and a different assertion from this one.
	var held:String=app.traversal.courtesy.owner(app.traversal)
	if not held.is_empty() and app.traversal.routes.has(held):
		var fact:Variant=app.traversal.routes[held].get("courtesy",{})
		if fact is Dictionary and (fact as Dictionary).has("anchor"):participants.append(Vector3((fact as Dictionary).anchor))
	var point:=Vector3(4,.16,-3)
	for candidate:Vector3 in [Vector3(4,.16,-3),Vector3(4.5,.16,3),Vector3(-4.5,.16,3),Vector3(5,.16,-1),Vector3(-5,.16,3.5),Vector3(0,.16,-3.5),Vector3(-5,.16,-1)]:
		var proposed:Array=app.world.serialize_items()
		proposed.append({"id":str(plant.id),"kind":"plant","x":candidate.x,"z":candidate.z,"rotation":0.0})
		if not app.world.can_place("plant",candidate,0) or not app.build_transactions.furnishing_error(proposed).is_empty():continue
		var related:bool=false
		for at:Vector3 in participants:
			if at.distance_to(candidate)<3.0:related=true
		if related:continue
		point=candidate;break
	check(app.world.can_place("plant",point,0) and app.build_transactions.furnishing_error(_moved_layout(plant,point)).is_empty(),
		"Controlled public Build placement is a supported open furnished-floor point (%s)." % str(point))
	app.world.placement_requested.emit("plant",point,0.0);await frames(2)
	check(app.pending_move.is_empty() and app._find_item(str(plant.id)).node.position==point,"Production placement commits the moved plant.")
	await press("Live")
	check(app.household.funds==funds and app.traversal.courtesy.owner(app.traversal)=="housemate_1" and app.traversal.courtesy.generation_current(app.traversal),"Successful unrelated Build move preserves the owner and rebuilds the corridor without charge.")
	var after:Dictionary=_record()
	check(_same_replan_facts(before,after,true),"Build rebuild preserves exact actor/action/paid/custody/deadline facts.")

func _resource_and_integrity(disk:Dictionary)->void:
	var motion:Dictionary=app.motion_states.housemate_3.duplicate(true)
	var anchor:Vector3=app.traversal.routes.housemate_1.courtesy.anchor
	app.motion_states.housemate_3.waiting=true;app.motion_states.housemate_3.wait_started=_now();app.motion_states.housemate_3.wait_destination=anchor
	check(not app.traversal.courtesy._eligible(app.traversal,"housemate_3"),"An earlier resource waiter cannot be selected as a donor or beneficiary.")
	check(not app.traversal.courtesy._anchor_clear(app.traversal,"housemate_1",anchor),"An earlier ordinary resource wait reserves its chosen endpoint before its actor arrives.")
	check(app.traversal.courtesy._hypothetical(app.traversal,"housemate_2","housemate_1",anchor).has(anchor),"Hypothetical beneficiary routing includes the earlier resource-wait endpoint.")
	app.motion_states.housemate_3=motion
	var raw:Dictionary=disk.duplicate(true)
	for member:Dictionary in raw.members:
		if member.id=="housemate_3":member.state.character.world_state.resource_wait_started=float(raw.day-1)*1440+raw.minutes
	raw.journeys.members.housemate_3.motion.destination=LifeJourneyState.packed(anchor)
	var rejected:Dictionary=LifeSaveLibrary._validate_household(raw)
	check(not bool(rejected.ok) and str(rejected.error).contains("resource waiting place"),"Detached saved-layout validation rejects courtesy stealing a previous resource-wait destination.")
	var mutations:Array=["legacy_with_courtesy","future_version","unknown_field","bad_phase","expired","foreign_peer","retired_peer","two_owners","unsupported_anchor","hold_position"]
	audit["rejections"]=[]
	for label:String in mutations:
		raw=disk.duplicate(true);var fact:Dictionary=raw.journeys.members.housemate_1.motion.courtesy
		match label:
			"legacy_with_courtesy":raw.journeys.version=1
			"future_version":raw.journeys.version=3
			"unknown_field":fact.extra=true
			"bad_phase":fact.phase="walking"
			"expired":fact.expires_at=float(raw.day-1)*1440+raw.minutes
			"foreign_peer":fact.beneficiary_id="maya"
			"retired_peer":fact.beneficiary_identity=raw.journeys.members.player.motion.identity
			"two_owners":raw.journeys.members.housemate_3.motion.courtesy=fact.duplicate(true)
			"unsupported_anchor":fact.anchor=[90,.16,90]
			"hold_position":fact.anchor[2]+=.1
		rejected=LifeSaveLibrary._validate_household(raw)
		check(not bool(rejected.ok),"Malformed present courtesy is explicitly rejected: "+label)
		audit.rejections.append({"case":label,"result":rejected})
	check(bool(LifeSaveLibrary.read_slot("life_1788942682044_57282849").ok),"The original courtesy-absent v1 journey remains loadable.")

func _expiry_control()->void:
	var before:Dictionary=_record();var owner_id:String="housemate_1"
	# Deliberately place just this bounded ownership fact at its boundary. No
	# household clock, needs, action progress, funds or actor position is changed.
	app.traversal.routes[owner_id].courtesy.expires_at=_now()
	check(app.save_game("","Courtesy control — expired hold"),"Pre-save mutation hook safely releases an expired hold before its read-only snapshot.")
	var after:Dictionary=_record()
	check(app.traversal.courtesy.owner(app.traversal).is_empty() and before.people==after.people and before.food==after.food and before.at==after.at,"Expiry release preserves exact queues/paid/needs/positions/custody and clock.")
	check(app.traversal.courtesy.trace.any(func(e:Dictionary):return e.get("released","")==owner_id and e.get("reason","")=="expired"),"Expiry is reported distinctly from successful beneficiary retirement.")
	check(before.journeys.members[owner_id].motion.destination==after.journeys.members[owner_id].motion.destination and before.journeys.members[owner_id].motion.identity==after.journeys.members[owner_id].motion.identity,"Expiry retains the donor's authoritative original destination and journey identity.")

## The live layout with this plant moved to `point`, exactly as a commit proposes.
func _moved_layout(plant:Dictionary,point:Vector3)->Array:
	var layout:Array=app.world.serialize_items()
	for entry:Dictionary in layout:
		if str(entry.get("id",""))==str(plant.id):
			entry["x"]=point.x;entry["z"]=point.z
	return layout

func _same_replan_facts(before:Dictionary,after:Dictionary,ordinary_replan:bool)->bool:
	# Explicit Build/target reconciliation projects ledger geometry to Vector3.
	# The authoritative amounts/progress/custody and every instruction scalar
	# remain exact. Ordinary nonparticipant routes can get new route IDs;
	# the two courtesy participants must keep their existing ownership IDs.
	var expected:Dictionary=before.duplicate(true);var actual:Dictionary=after.duplicate(true)
	for record:Dictionary in [expected,actual]:
		for collection:String in ["batches","portions"]:
			for item:Dictionary in record.food[collection]:
				item.position=LifeJourneyState.packed(LifeJourneyState.vector(item.position))
	if ordinary_replan:
		if int(actual.journeys.next_identity)<int(expected.journeys.next_identity):return false
		expected.journeys.next_identity=actual.journeys.next_identity
		for id:String in ["player","housemate_3"]:
			if int(actual.journeys.members[id].motion.identity)<int(expected.journeys.members[id].motion.identity):return false
			expected.journeys.members[id].motion.identity=actual.journeys.members[id].motion.identity
	# A fixture older than the seat model carries a bed action with no place of its
	# own. The first refresh gives it one — the same kind of one-time upgrade the
	# route identities above describe — and it is stable from then on (recorded
	# deltas show no remaining difference after it). A save that already holds a
	# place must keep exactly the place and endpoint it had, which is asserted
	# directly, so only the absent-to-present direction is projected here.
	for record:Dictionary in [expected,actual]:
		for member_id:String in record.people:
			for entry:Dictionary in record.people[member_id].queue:
				if entry.has("seat_slot") and not entry.get("seat_slot","") is String:return false
	for member_id:String in expected.people:
		var wanted_queue:Array=expected.people[member_id].queue
		var got_queue:Array=actual.people[member_id].queue
		for index:int in range(mini(wanted_queue.size(),got_queue.size())):
			var wanted:Dictionary=wanted_queue[index]
			var got:Dictionary=got_queue[index]
			if str(wanted.get("id",""))!=str(got.get("id","")):continue
			# A fixture that named no place at all may be given one; a save that
			# named a place keeps that exact place and its own endpoint.
			if not wanted.has("seat_slot") and got.has("seat_slot") and not str(got.get("seat_slot","")).is_empty():
				wanted["seat_slot"]=got["seat_slot"]
				wanted["target_position"]=got["target_position"]
				# The route the sleeper is walking is the same one-time upgrade:
				# its destination is the new place's endpoint rather than the
				# furnishing's centre, and it moves only on that first refresh.
				var before_motion:Dictionary=(expected.journeys.get("members",{}) as Dictionary).get(member_id,{}).get("motion",{})
				var after_motion:Dictionary=(actual.journeys.get("members",{}) as Dictionary).get(member_id,{}).get("motion",{})
				if not before_motion.is_empty() and after_motion.has("destination"):
					before_motion["destination"]=after_motion["destination"]
	if not audit.has("reconciliation_deltas"):audit.reconciliation_deltas=[]
	audit.reconciliation_deltas.append({"raw":_differences(_json(before),_json(after)),"remaining":_differences(_json(expected),_json(actual))})
	return expected==actual

func _finish()->void:
	audit["assertions"]=assertions;audit["failures"]=failures
	var f:=FileAccess.open(screenshot_dir.path_join(phase_tag+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(_json(audit),"  ",true,true));f.close()
	var ambience:WeakRef=weakref(app.ambience_player.stream);var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free();await frames(2)
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Private app ambience releases before process exit.")
	print("COURTESY_RESULT assertions=%d failures=%d"%[assertions,failures.size()]);quit(0 if failures.is_empty() else 1)

func _clearance_pairs()->Dictionary:
	var result:Dictionary={"all_minimum":INF,"household_minimum":INF,"pedestrian_minimum":INF,"pairs":[]}
	var ids:Array=app.world.actors.keys();var members:Array=[]
	for member:Dictionary in app.household.members:members.append(str(member.id))
	for i:int in ids.size():
		var a:LifeActor=app.world.actors[ids[i]]
		if not a.visible:continue
		for j:int in range(i+1,ids.size()):
			var b:LifeActor=app.world.actors[ids[j]]
			if not b.visible or absf(a.position.y-b.position.y)>=.1:continue
			var distance:float=a.position.distance_to(b.position)
			var household_pair:bool=ids[i] in members or ids[j] in members
			result.all_minimum=minf(float(result.all_minimum),distance)
			var key:String="household_minimum" if household_pair else "pedestrian_minimum"
			result[key]=minf(float(result[key]),distance)
			result.pairs.append({"a":ids[i],"b":ids[j],"a_position":a.position,"b_position":b.position,"gap":distance,"household":household_pair})
	return result
