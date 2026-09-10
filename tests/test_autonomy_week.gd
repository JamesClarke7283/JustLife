extends "res://tests/test_genealogy_playthrough.gd"
## Sustained rendered observation. No needs/time/action completion mutation.
## The provided one-bed/one-bath cottage is deliberately left as advertised.
var audit: Dictionary = {"samples":[],"completions":[],"notices":[],"daily":[],"members":{},"frame_ms":[]}
var sample_time: float = -1.0
var next_capture: float = 0.0
var sample_positions: Dictionary = {}
var still_minutes: Dictionary = {}
var last_actions: Dictionary = {}
var audit_enabled: bool = false
var audit_start: float = 480.0

func _genealogy_ages()->Array[String]:
	return ["Elder","Adult","Adult","Adult","Child","Teen","Young adult","Child"]

func _run()->void:
	screenshot_dir="res://art/autonomy_week"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):
		member_completed.append(id+":"+str(action.id))
		if audit_enabled:audit.completions.append({"id":id,"day":app.household.day,"minutes":app.household.minutes,"action":action.id,"target":action.target_id,"autonomous":bool(action.get("autonomous",false))}))
	app.household.notice.connect(func(message:String):
		notices.append(message)
		if audit_enabled:audit.notices.append({"at":_now(),"message":message}))
	if resume_only:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://autonomy_expected.json"))
		audit=expected.audit
		await _public_load();await _compare_saved(expected,"midweek fresh-process")
		for id:String in expected.get("resource_waits",{}):
			var saved_wait:Dictionary=expected.resource_waits[id]
			if not bool(saved_wait.waiting):continue
			var restored_wait:Dictionary=app.motion_states[id]
			check(bool(restored_wait.waiting) and is_equal_approx(float(restored_wait.wait_started),float(saved_wait.started)),"Midweek fresh load preserves arrived resource priority before movement: "+id)
		check(equivalent(app.household.family_graph,expected.family_graph),"Midweek fresh load preserves exact directed family graph.")
		for member:Dictionary in expected.members:
			var restored:Node=app.household.member_sim(member.id)
			check(equivalent(restored.education,member.state.education),"Midweek load preserves school attendance and absence records.")
			check(restored.action_queue.size()==member.state.action_queue.size(),"Midweek load preserves every autonomous queue length.")
			if restored.action_queue.size()==member.state.action_queue.size():
				for i:int in range(restored.action_queue.size()):
					var actual:Dictionary=restored.action_queue[i];var stored:Dictionary=member.state.action_queue[i]
					check(actual.id==stored.id and actual.target_id==stored.target_id and actual.paid==stored.paid and is_equal_approx(actual.elapsed,stored.elapsed),"Midweek queue keeps activity, target, paid state and elapsed progress.")
		await _run_days(audit_start+7*1440)
		await _final_review()
	else:
		await _create_genealogy()
		for member:Dictionary in app.household.members:member.sim.autonomy=true
		check(app.household.members.size()==8,"Seven-day audit begins with eight family members.")
		var stages:Array=[]
		for member:Dictionary in app.household.members:
			stages.append(member.sim.character.age_stage)
			audit.members[str(member.id)]={"name":member.sim.character.name,"stage":member.sim.character.age_stage,"minimum_needs":member.sim.needs.duplicate(true),"critical_minutes":{},"waiting_minutes":0.0,"idle_minutes":0.0,"max_stationary_approach_minutes":0.0}
			for need:String in LifeSim.NEED_NAMES:audit.members[str(member.id)].critical_minutes[need]=0.0
		check(stages.has("elder") and stages.has("adult") and stages.has("young_adult") and stages.has("teen") and stages.has("child"),"Audit includes all five selectable age stages.")
		audit["fixture"]={"source":"isolated development candidate; see source_snapshot.json","lot":"Willow Cottage","beds":1,"bathrooms":1,"desk":1,"funds":app.sim.funds,"note":"Default small furnished home; no extra resources or money granted by harness."}
		await _run_days(audit_start+3*1440)
		await _save_midweek()
	var file:=FileAccess.open(screenshot_dir.path_join("audit_resume.json" if resume_only else "audit_first.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "));file.close()
	_write_report();app.queue_free();await frames(3)
	print("AUTONOMY_WEEK_RESULT assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _now()->float:
	return float(app.household.day-1)*1440.0+app.household.minutes

func _run_days(target:float)->void:
	for member:Dictionary in app.household.members:member.sim.autonomy=true
	sample_time=_now();next_capture=(floorf((_now()-audit_start)/1440)+1)*1440+audit_start
	audit_enabled=true
	await press("▶▶▶")
	var end_wall:int=Time.get_ticks_msec()+300000
	while _now()<target and Time.get_ticks_msec()<end_wall:
		await process_frame
		audit.frame_ms.append(root.get_process_delta_time()*1000.0)
		if _now()-sample_time>=15.0:_sample()
		if _now()>=next_capture:
			await press("Ⅱ");_sample()
			await _daily_capture()
			next_capture+=1440.0
			if _now()<target:await press("▶▶▶")
	await press("Ⅱ");_sample()
	audit_enabled=false
	check(_now()>=target,"Actual rendered clock reaches the requested sustained-play checkpoint.")

func _sample()->void:
	var at:float=_now();var step:float=maxf(0,at-sample_time);sample_time=at
	var record:Dictionary={"at":at,"day":app.household.day,"minutes":app.household.minutes,"funds":app.sim.funds,"members":[],"standoffs":app.traversal.standoff_count,"make_ways":app.traversal.make_way_count,"squeezes":app.traversal.squeeze_count}
	for member:Dictionary in app.household.members:
		var id:String=str(member.id);var sim:Node=member.sim;var action:Dictionary=sim.get_current_action()
		var motion:Dictionary=app.motion_states.get(id,{})
		var position:Vector3=app.world.actors[id].position
		var waiting:bool=bool(motion.get("waiting",false))
		var signature:String=str(action.get("id",""))+":"+str(action.get("target_id",""))+":"+str(action.get("phase",""))
		var stats:Dictionary=audit.members[id]
		for need:String in LifeSim.NEED_NAMES:
			stats.minimum_needs[need]=minf(stats.minimum_needs[need],sim.needs[need])
			if float(sim.needs[need])<10.0:stats.critical_minutes[need]+=step
		if waiting:stats.waiting_minutes+=step
		if action.is_empty():stats.idle_minutes+=step
		if not waiting and str(action.get("phase",""))=="approach" and last_actions.get(id,"")==signature and sample_positions.has(id) and position.distance_to(sample_positions[id])<.01:
			still_minutes[id]=float(still_minutes.get(id,0))+step
		else:still_minutes[id]=0.0
		stats.max_stationary_approach_minutes=maxf(stats.max_stationary_approach_minutes,float(still_minutes[id]))
		sample_positions[id]=position;last_actions[id]=signature
		var wait_position:Vector3=motion.get("wait_destination",Vector3.INF)
		record.members.append({"id":id,"needs":sim.needs.duplicate(true),"action":action.duplicate(true),"away_state":sim.get_away_state(),"actor_visible":app.world.actors[id].visible,"waiting":waiting,"wait_started":motion.get("wait_started",-1.0),"idle_minutes":sim._idle_minutes,"queue":sim.action_queue.size(),"route_failures":app.route_failures.get(id,{}).duplicate(true),"route":({"phase":str(app.traversal.routes[id].get("phase","")),"point":int(app.traversal.routes[id].get("point",-1)),"points":app.traversal.routes[id].get("points",PackedVector3Array()).size(),"standoff":app.traversal.routes[id].has("standoff"),"make_way":bool(app.traversal.routes[id].get("make_way",false)),"destination":app.traversal.routes[id].get("destination",Vector3.INF)} if app.traversal.routes.has(id) else {}),"wait_destination":vec(wait_position) if wait_position.is_finite() else [],"path_size":motion.get("path",[]).size(),"path_index":motion.get("index",0),"position":vec(position),"mood":sim.get_mood()})
	audit.samples.append(record)

func _daily_capture()->void:
	var day:int=app.household.day
	var worst_id:String="";var lowest:float=INF
	var daily:Dictionary={"day":day,"minutes":app.household.minutes,"funds":app.sim.funds,"members":[]}
	for member:Dictionary in app.household.members:
		var sum:float=0
		for value:float in member.sim.needs.values():sum+=value
		if sum<lowest:lowest=sum;worst_id=str(member.id)
		daily.members.append({"id":member.id,"state":member.sim.get_state(),"position":vec(app.world.actors[member.id].position)})
	audit.daily.append(daily)
	await press_member(str(app.household.member_sim(worst_id).character.name))
	await screenshot("day_%02d_lowest_needs"%day,false,false)
	if day in [4,8]:
		await press_member(FAMILY_NAMES[3]);await press("School");await press("School record",true)
		await screenshot("day_%02d_school"%day,false,false);await press("Back to life")

func _save_midweek()->void:
	var expected:Dictionary={"state":app.sim.get_state(),"player":vec(app.player.position),"world":app.world.serialize_items(),"lot":app.selected_lot,"floor":app.floor_color,"selected_index":app.household.selected_index,"family_graph":app.household.family_graph.duplicate(true),"members":[],"audit":audit}
	expected["resource_waits"]={}
	for member:Dictionary in app.household.members:
		var motion:Dictionary=app.motion_states.get(str(member.id),app._empty_motion())
		expected.resource_waits[str(member.id)]={"waiting":motion.waiting,"started":motion.wait_started}
	for member:Dictionary in app.household.members:expected.members.append({"id":member.id,"state":member.sim.get_state(),"position":vec(app.world.actors[member.id].position)})
	await _public_save("Reed family — autonomous week halfway")
	var file:=FileAccess.open("user://autonomy_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected));file.close()
	await screenshot("midweek_named_save",false,false)

func _final_review()->void:
	for member:Dictionary in app.household.members:
		var count:int=0
		var last_finish:float=audit_start
		var longest_gap:float=0.0
		for event:Dictionary in audit.completions:
			if event.id==member.id:
				count+=1
				var finish:float=float(event.day-1)*1440.0+float(event.minutes)
				longest_gap=maxf(longest_gap,finish-last_finish)
				last_finish=maxf(last_finish,finish)
		longest_gap=maxf(longest_gap,_now()-last_finish)
		check(count>0,"Each member completes at least one autonomous activity over the week: "+str(member.sim.character.name))
		check(_now()-last_finish<1440.0,"No member is starved of all completed actions for a full game day: "+str(member.sim.character.name))
		check(longest_gap<1440.0,"Every observed game day includes a useful completed action: "+str(member.sim.character.name))
		check(float(audit.members[str(member.id)].max_stationary_approach_minutes)<120,"No non-waiting route remains stationary for two game hours: "+str(member.sim.character.name))
	for member:Dictionary in app.household.members:
		var simulation:LifeSim=member.sim
		var counts:Dictionary={"school":0,"school_day":0,"homework":0,"job":0,"career_day":0}
		var dates:Dictionary={"school":[],"school_day":[],"homework":[],"job":[],"career_day":[]}
		for event:Dictionary in audit.completions:
			if event.id!=member.id or str(event.action) not in counts:continue
			counts[str(event.action)]+=1
			check(not dates[str(event.action)].has(int(event.day)),"Autonomy grants each daily responsibility at most once: "+str(member.id)+" "+str(event.action))
			dates[str(event.action)].append(int(event.day))
		if str(simulation.character.age_stage) in LifeEducation.SCHOOL_STAGES:
			check(int(simulation.education.attended)==5 and int(counts.school_day)==5,"Each healthy pupil completes all five off-lot school days without home computer attendance: "+str(simulation.character.name))
			check(int(simulation.education.homework)>0,"Each pupil actually completes homework during the observed school week: "+str(simulation.character.name))
			check(int(simulation.education.attended)+int(simulation.education.missed)==5,"School attendance and missed days account for all five elapsed weekdays.")
		else:check(int(counts.career_day)==5 and int(simulation.career.schedule.attended)==5,"Each healthy employed adult completes all five ordinary off-lot weekday shifts: "+str(simulation.character.name))
	check(app.household.funds>0,"The healthy starter household retains funds instead of repeatedly paying for abandoned recovery actions.")
	for member:Dictionary in app.household.members:
		check(member.sim.needs.values().all(func(value:float):return value>0.0),"No member ends the week with a completely depleted need: "+str(member.sim.character.name))
	check(audit.samples.all(func(sample:Dictionary):return sample.members.all(func(member:Dictionary):return not member.needs.values().all(func(value:float):return value==0.0))),"No sampled member collapses to all six needs at zero.")
	audit["final_household"]=app.household.get_state(app.world.serialize_items())
	var partners:Dictionary={}
	for event:Dictionary in audit.completions:
		if str(event.action) in ["friendly","joke","deep_talk"]:partners[str(event.target)]=true
	check(partners.size()>=4,"Completed social interactions reach at least four distinct partners.")
	await press("Stories",true);await screenshot("day_08_unattended_stories",false,false);await press("Back to life")
	await press("My Lifelet");await press("Family tree");await screenshot("day_08_family_tree",false,false);await press("Back to life")
