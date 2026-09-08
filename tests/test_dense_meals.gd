extends "res://tests/test_autonomy_week.gd"
## Three rendered weekdays, default eight-person cottage, two dining chairs.
## Player requests one four-serving dinner daily; nobody is teleported, fed,
## given money, or advanced by direct tick. Existing autonomous queues remain.
var density: Dictionary={"commands":[],"food_samples":[],"offered":{},"dinners":{},"violations":[],"stage":"first"}
var setdown_observer:Node
var save_ready: bool=false
var next_density_capture: float=1920.0

func _initialize()->void:
	var path:String=ProjectSettings.globalize_path("res://")
	if not path.trim_suffix("/").get_file().begins_with("justlife-playthrough-") or OS.get_environment("XDG_DATA_HOME")!=path.path_join("userdata") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		push_error("Refusing dense meal fixture outside its isolated source and userdata.");quit(2);return
	resume_only="--resume-only" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _run()->void:
	screenshot_dir="res://art/dense_meals";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	setdown_observer=load("res://tests/food_setdown_observer.gd").new();setdown_observer.app=app;app.add_child(setdown_observer)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):
		member_completed.append(id+":"+str(action.id))
		if audit_enabled:audit.completions.append({"id":id,"day":app.household.day,"minutes":app.household.minutes,"action":action.id,"target":action.target_id,"autonomous":bool(action.get("autonomous",false))}))
	app.household.notice.connect(func(message:String):
		notices.append(message)
		if audit_enabled:audit.notices.append({"at":_now(),"message":message}))
	if resume_only:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://dense_meals_expected.json"))
		audit=expected.audit;density=expected.density;density.stage="resume"
		setdown_observer.data=density.get("setdown",{"releases":[],"maximum_horizontal_metres":0.0})
		await _public_load();await _compare_saved(expected,"dense dinner fresh-process")
		check(_food_restored(expected.food),"Food identities, counts, owners, freshness and partial progress survive named restart; standing carrier approach is rebuilt.")
		for member:Dictionary in expected.members:
			var actual:Node=app.household.member_sim(member.id)
			check(equivalent(actual.education,member.state.education),"Independent school record survives dense dinner restart: "+str(member.id))
			check(equivalent(actual.career,member.state.career),"Independent career record survives dense dinner restart: "+str(member.id))
			check(_queue_restored(actual.action_queue,member.state.action_queue),"Every pending action preserves identity, target, progress, payment and later instructions after reconstruction: "+str(member.id))
		await screenshot("02_restored_partial_dinner",false,false)
		await _observe(480.0+3*1440.0,false)
		await _density_review()
	else:
		await _create_genealogy()
		check(app.household.members.size()==8,"Dense meal fixture begins with eight household members.")
		for member:Dictionary in app.household.members:
			member.sim.autonomy=true
			audit.members[str(member.id)]={"name":member.sim.character.name,"stage":member.sim.character.age_stage,"minimum_needs":member.sim.needs.duplicate(true),"critical_minutes":{},"waiting_minutes":0.0,"idle_minutes":0.0,"max_stationary_approach_minutes":0.0}
			for need:String in LifeSim.NEED_NAMES:audit.members[str(member.id)].critical_minutes[need]=0.0
		audit.fixture={"source_manifest":"res://source_snapshot.json","lot":"Willow Cottage","members":8,"beds":1,"bathrooms":1,"desks":1,"dining_chairs":2,"funds":app.sim.funds,"method":"Three weekdays; public player-selected dinner at 18:00, one four-serving batch offered to eight Lifelets. Three explicit public serving requests after Call everyone, existing queues preserved. No added resources, money, need recovery, time advancement or arrival mutation."}
		await _observe(1440.0+22*60.0,true)
		check(save_ready,"A genuinely partially eaten second-day dinner supplies the persistence boundary.")
		await _density_save()
	_flush_audit()
	_write_report();app.queue_free();await frames(3)
	print("DENSE_MEALS_RESULT assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _observe(target:float,stop_at_partial:bool)->void:
	sample_time=_now();next_density_capture=(floorf((_now()-480.0)/1440.0)+1)*1440.0+480.0
	audit_enabled=true
	await press("▶▶▶")
	var deadline:int=Time.get_ticks_msec()+540000
	while _now()<target and Time.get_ticks_msec()<deadline:
		await process_frame
		audit.frame_ms.append(root.get_process_delta_time()*1000.0)
		if _now()-sample_time>=15.0:_sample()
		var day_key:String=str(app.household.day)
		if app.household.day<=3 and app.household.minutes>=1080 and not density.dinners.has(day_key):
			await press("Ⅱ");await _request_dinner(day_key);await press("▶▶▶")
		for value:Dictionary in app.household.meals.batches.duplicate():
			if str(value.storage)=="surface" and not density.offered.has(str(value.id)) and int(value.remaining)>0 and _now()<float(value.expires):
				await press("Ⅱ");await _offer_dinner(str(value.id));await press("▶▶▶")
		if stop_at_partial and app.household.day==2 and app.household.minutes>=1080 and app.household.meals.portions.any(func(p:Dictionary)->bool:return not str(p.owner).is_empty() and float(p.progress)>.08 and float(p.progress)<.9):
			save_ready=true;break
		if _now()>=next_density_capture:
			await press("Ⅱ");_sample();await _daily_capture();_flush_audit();next_density_capture+=1440.0
			if _now()<target:await press("▶▶▶")
	await press("Ⅱ");_sample();audit_enabled=false
	check(save_ready or _now()>=target,"Rendered clock reaches its requested checkpoint without synthetic clock changes.")

func _request_dinner(day_key:String)->void:
	density.dinners[day_key]={"requested_at":_now(),"queued":false}
	# Choose the first home adult whose public cook button is available. Do not
	# erase their existing action or insert a private action behind the UI.
	for member:Dictionary in app.household.members:
		if member.sim.is_away() or str(member.sim.character.age_stage) in ["child","teen"]:continue
		await press_member(str(member.sim.character.name))
		var stove:Dictionary=first_item("stove")
		app.world.object_clicked.emit(stove,app.world.camera.unproject_position(stove.node.position+Vector3(0,.6,0)))
		await frames(3)
		if is_instance_valid(button_matching("Cook a fresh meal",true)):
			var before:Array=JSON.parse_string(JSON.stringify(member.sim.action_queue))
			await press("Cook a fresh meal",true);await press("Cook garden skillet")
			density.commands.append({"at":_now(),"command":"Cook a fresh meal","member":member.id,"queue_before":before})
			density.dinners[day_key].queued=true;density.dinners[day_key].cook=member.id
			return
		app.close_overlay();await frames(2)
	check(false,"At least one home adult can queue the public dinner on day "+day_key)

func _offer_dinner(id:String)->void:
	density.offered[id]=_now()
	var dish:Dictionary=app._find_item(id)
	check(not dish.is_empty(),"Physically served batch has a public world interaction: "+id)
	if dish.is_empty():return
	app.world.object_clicked.emit(dish,app.world.camera.unproject_position(dish.node.position));await frames(3)
	await press("Call everyone to eat")
	density.commands.append({"at":_now(),"command":"Call everyone to eat","batch":id})
	var requested:int=0
	for member:Dictionary in app.household.members:
		if requested>=3:break
		if member.sim.is_away() or not app.household.meals.carried_by(str(member.id)).is_empty():continue
		if member.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="eat_meal"):continue
		await press_member(str(member.sim.character.name))
		dish=app._find_item(id)
		app.world.object_clicked.emit(dish,app.world.camera.unproject_position(dish.node.position));await frames(3)
		if is_instance_valid(button_matching("Take a serving",true)):
			await press("Take a serving",true);requested+=1
			density.commands.append({"at":_now(),"command":"Take a serving","member":member.id,"batch":id})
		else:app.close_overlay();await frames(2)
	_sample();await screenshot("day_%02d_offered_%s"%[app.household.day,id],false,false)

func _sample()->void:
	super._sample()
	var food:Dictionary=app.household.meals.get_state()
	var ids:Array=[];var members:Array=[];var eaters:Array=[]
	for member:Dictionary in app.household.members:
		ids.append(str(member.id));members.append({"id":member.id,"state":member.sim.get_state()})
		var action:Dictionary=member.sim.get_current_action()
		if str(action.get("id",""))=="eat_meal":eaters.append({"id":member.id,"action":action.duplicate(true)})
	var invalid:String=LifeMeals.validate(food,ids,_now())
	if invalid.is_empty():invalid=LifeMeals.validate_actions(food,members)
	if not invalid.is_empty() and not density.violations.has(invalid):
		density.violations.append(invalid);check(false,"Live meal invariants: "+invalid)
	var dirty:int=0;var spoiled:int=0;var active:int=0;var seated:int=0
	for portion:Dictionary in food.portions:
		if str(portion.storage)=="dirty":dirty+=1
		if float(portion.progress)<1 and _now()>=float(portion.expires):spoiled+=1
		if not str(portion.owner).is_empty():active+=1
		if str(portion.storage)=="table" and not str(portion.seat).is_empty():seated+=1
	for batch:Dictionary in food.batches:
		if int(batch.remaining)>0 and _now()>=float(batch.expires):spoiled+=1
	density.food_samples.append({"at":_now(),"food":food,"diners":eaters,"dirty":dirty,"spoiled":spoiled,"active_portions":active,"seated_portions":seated,"invariant_error":invalid})

func _density_save()->void:
	density.setdown=setdown_observer.data
	var expected:Dictionary={"state":app.sim.get_state(),"player":vec(app.player.position),"world":app.world.serialize_items(),"lot":app.selected_lot,"floor":app.floor_color,"selected_index":app.household.selected_index,"family_graph":app.household.family_graph.duplicate(true),"members":[],"audit":audit,"density":density,"food":app.household.meals.get_state()}
	for member:Dictionary in app.household.members:expected.members.append({"id":member.id,"state":member.sim.get_state(),"position":vec(app.world.actors[member.id].position)})
	await screenshot("01_partial_dinner_save",false,false)
	await _public_save("Reed family — dense dinner checkpoint")
	var file:=FileAccess.open("user://dense_meals_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected));file.close()

func _flush_audit()->void:
	density.setdown=setdown_observer.data
	var file:=FileAccess.open(screenshot_dir.path_join("audit_resume.json" if resume_only else "audit_first.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "));file.close()
	file=FileAccess.open(screenshot_dir.path_join("density_resume.json" if resume_only else "density_first.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(density,"  "));file.close()

func _density_review()->void:
	check(density.violations.is_empty(),"All sampled food ledgers preserve serving conservation and unique portion/seat ownership.")
	check(density.dinners.size()==3,"Three real daily dinner requests are recorded.")
	check(density.offered.size()>=3,"At least three cooked batches reach an actual surface and public offer.")
	check(density.food_samples.any(func(s:Dictionary)->bool:return int(s.active_portions)>=3),"Dining contention includes at least three simultaneous owned portions with only two dining chairs.")
	check(density.food_samples.any(func(s:Dictionary)->bool:return int(s.dirty)>=2),"Real completed meals leave at least two dirty plates in the household.")
	for member:Dictionary in app.household.members:
		var count:int=0;var last:float=480.0;var gap:float=0.0
		for event:Dictionary in audit.completions:
			if event.id==member.id:
				var at:float=float(event.day-1)*1440.0+float(event.minutes)
				count+=1;gap=maxf(gap,at-last);last=at
		gap=maxf(gap,_now()-last)
		check(count>0 and gap<1440,"Each member keeps completing useful actions without a full-day gap: "+str(member.sim.character.name))
		check(float(audit.members[str(member.id)].max_stationary_approach_minutes)<120,"No non-waiting route is stationary for two hours: "+str(member.sim.character.name))
		var sim:Node=member.sim
		if str(sim.character.age_stage) in LifeEducation.SCHOOL_STAGES:
			check(int(sim.education.attended)==3,"Pupil completes all three school days alongside household meals: "+str(sim.character.name))
			check(int(sim.education.attended)+int(sim.education.missed)==3,"Pupil record accounts for three elapsed weekdays: "+str(sim.character.name))
		else:check(int(sim.career.schedule.attended)==3,"Employed adult completes all three weekday shifts alongside meals: "+str(sim.character.name))
		check(sim.needs.values().all(func(v:float)->bool:return v>0),"No fully depleted need at the final checkpoint: "+str(sim.character.name))
	check(app.household.funds>0,"Shared funds remain positive after three days of real recovery and dinner charges.")
	audit.final_household=app.household.get_state(app.world.serialize_items())
	await _daily_capture()

func _food_restored(saved:Dictionary)->bool:
	var actual:Dictionary=app.household.meals.get_state();var normalized:Dictionary=saved.duplicate(true)
	for portion:Dictionary in normalized.portions:
		var restored:Dictionary=app.household.meals.portion(str(portion.id))
		if str(portion.storage)!="table" or not str(portion.host).is_empty() or str(portion.owner).is_empty() or str(restored.get("storage",""))!="carried":continue
		var owner:Node=app.household.member_sim(str(portion.owner));var action:Dictionary=owner.get_current_action()
		if str(action.get("meal_plate",""))==str(portion.id) and str(action.get("phase",""))=="approach":portion.storage="carried"
	return equivalent(actual,normalized)

func _queue_restored(actual:Array,saved:Array)->bool:
	if actual.size()!=saved.size():return false
	var normalized:Array=JSON.parse_string(JSON.stringify(actual))
	for i:int in range(normalized.size()):
		if str(saved[i].get("phase",""))=="active" and str(normalized[i].get("phase",""))=="approach":normalized[i].phase="active"
		if not saved[i].has("started_day"):normalized[i].erase("started_day")
	return equivalent(normalized,saved)
