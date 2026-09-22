extends "res://tests/test_activity_flow.gd"
## Save a naturally observed transient route delay, then load its actual named bytes.
func _run()->void:
	await _start_activity("produce")
	if test_phase=="fresh":await _fresh_observation()
	else:await _natural_owner()
	await _finish()
func _activity_observed_row(index:int)->bool:
	if index!=106:return false
	await _phase_observation()
	return true
func _speeds_direct()->Dictionary:
	var people:Dictionary={}
	for member:Dictionary in app.household.members:people[member.id]=member.sim.speed
	return {"aggregate":app.household.speed,"selected":app.sim.speed,"people":people,"bound":app.bound_member_id,"selected_id":app.household.selected_id(),"at":_now()}
func _query_state()->Dictionary:
	var people:Dictionary={};var bodies:Dictionary={}
	for member:Dictionary in app.household.members:people[member.id]=member.sim.get_state()
	for id:String in app.world.actors:
		var actor:LifeActor=app.world.actors[id]
		bodies[id]={"position":actor.position,"rotation":actor.rotation,"visible":actor.visible}
	var disabled:Array=[];var nav=app.world.lot_navigation
	for id:int in nav._graph.get_point_ids():
		if nav._graph.is_point_disabled(id):disabled.append(id)
	var c=app.traversal.courtesy
	return {"people":people,"bodies":bodies,"speeds":_speeds_direct(),"funds":app.household.funds,"motions":app.motion_states.duplicate(true),"routes":app.traversal.routes.duplicate(true),"stairs":app.traversal.stairs.duplicate(true),"journeys":app.traversal.snapshot(),"cached_journeys":app.household.journeys.duplicate(true),"food":app.household.meals.get_state(),"sanitation":app.household.sanitation.get_state(),"cooperations":app.household.cooperations.duplicate(true),"cooperation_serial":app.household.cooperation_serial,"family":app.household.family_graph.duplicate(true),"adoptions":app.household.adoptions.duplicate(true),"courtesy":{"blocked":c.blocked.duplicate(true),"attempted":c.attempted.duplicate(true),"rejected":c.rejected.duplicate(true),"trace":c.trace.duplicate(true),"queries":c.queries,"attempted_at":c.attempted_at},"navigation":{"generation":nav.generation,"disabled":disabled,"point_count":nav._graph.get_point_count(),"state":nav._state.duplicate(true)},"bound_intent":{"walk":app.walk_only,"destination":app.walk_destination,"path":app.path,"path_index":app.path_index,"waiting":app.waiting_for_target,"wait_started":app.wait_started,"resume_active":app.resume_activity},"residents":app.residents.snapshot(),"physical":app._physical_snapshot_context()}
func _phase_observation()->void:
	check(audit.steps.size()==107 and int(audit.steps[-1].step)==106,"Same public normal-speed prefix stops after original row106,107 advancing calls.")
	var route:Dictionary=app.traversal.routes.housemate_1
	check(int(route.identity)==95 and route.has("replan_observation") and route.replan_observation.age==.05,"Actual first Ellis Read route95 observation has age.05 without phase injection.")
	var observation:Dictionary=route.replan_observation.duplicate(true)
	var route_before:Dictionary=route.duplicate(true)
	audit.observed=_query_state();audit.speed_before_pause=_speeds_direct()
	var facts:Dictionary=_busy_record()
	await press("Ⅱ");_exclude_inputs();audit.speed_after_public_pause=_speeds_direct()
	app._process(.05);await frames(1);_exclude_inputs()
	audit.paused=_query_state();audit.speed_after_materialization=_speeds_direct()
	check(facts==_busy_record(),"Public Pause and one ordinary adoption preserve exact clock/body/needs/completequeue/journey/wait/food/fund facts.")
	check(app.household.speed==0 and app.household.members.all(func(m:Dictionary)->bool:return m.sim.speed==0),"Selected, aggregate and all member speeds are explicitly paused before save.")
	check(route.replan_observation==observation,"Paused materialization leaves the actual derived observation and age exact.")
	await _public_save("Finite route observation — actual Ellis Read");_exclude_inputs()
	var disk:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(disk.ok) and app.active_save_id!=EASEL_SLOT,"Public Save as new writes an actual readable observed-phase checkpoint.")
	check(facts==_busy_record(),"Actual named save preserves all recorded consequential facts exactly.")
	check(app.traversal.routes.housemate_1==route_before and route.replan_observation==observation,"Actual named save retains the live derived route and observation exactly.")
	if bool(disk.ok):
		audit.saves.append({"slot":app.active_save_id,"data":disk.data,"facts":_busy_record()})
		check(_same(_project_journeys(disk.data.journeys),app.traversal.snapshot()),"Saved physical journeys use existing field-specific typed vector/yaw projection exactly.")
		check(not JSON.stringify(disk.data).contains("replan_observation"),"Derived retry observation is omitted from the actual persisted schema.")
	audit.saved=_query_state();audit.final=_busy_record()
	check(_input_excluded(),"All four input modes and new nodes, GUI and native camera polling remain isolated.")
func _fresh_observation()->void:
	var slot:String=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):slot=arg.trim_prefix("--slot=")
	check(not slot.is_empty() and slot!=EASEL_SLOT,"Fresh phase uses the actual newly generated named slot.")
	if slot.is_empty():return
	var read:Dictionary=LifeSaveLibrary.read_slot(slot)
	if not await _load_busy(slot):return
	check(app.household.speed==0 and app.household.members.all(func(m:Dictionary)->bool:return m.sim.speed==0),"Fresh actual phase loads with every speed paused.")
	check(app.household.funds==int(read.data.funds) and app.household.day==int(read.data.day) and app.household.minutes==float(read.data.minutes),"Fresh wallet/calendar/clock exactly retain decoded named values.")
	for saved:Dictionary in read.data.members:
		var sim:LifeSim=app.household.member_sim(str(saved.id))
		check(sim.needs==saved.state.needs and _same(_decoded_career(saved.state.career),sim.career),"Fresh exact decoded needs including Fun, and career: "+str(saved.id))
	check(_same(read.data.meals,app.household.meals.get_state()) and _same(read.data.sanitation,app.household.sanitation.get_state()),"Fresh complete food/custody and sanitation retain exact decoded values.")
	check(app.traversal.routes.has("housemate_1") and int(app.traversal.routes.housemate_1.identity)==95,"Fresh reconstruction retains actual Ellis route95 identity.")
	var route:Dictionary=app.traversal.routes.housemate_1
	var sim:LifeSim=app.household.member_sim("housemate_1");var action:Dictionary=sim.get_current_action();var action_before:Dictionary=action.duplicate(true)
	check(action.id=="read" and action.phase=="approach" and not action.paid and action.elapsed==0.0,"Fresh actual read remains unpaid approach, not invented active progress.")
	check(app.traversal.routes.values().all(func(r:Dictionary)->bool:return not r.has("replan_observation")),"Fresh derived routes start without persisted retry ages by the explicit transient contract.")
	audit.initial=_busy_record();audit.fresh=_query_state();audit.loaded=read.data
	var origin:Vector3=app.world.actors.housemate_1.position;var destination:Vector3=route.destination
	var moved:bool=false;var minimum:float=INF;var native_excluded:bool=true;var completed:bool=false
	app.household.member_action_finished.connect(func(member_id:String,a:Dictionary):audit.completions.append({"id":member_id,"action":a.duplicate(true),"body":app.world.actors[member_id].position,"at":_now()}))
	await press("▶")
	for i:int in range(493):
		_exclude_inputs();native_excluded=native_excluded and _input_excluded();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();row.routes=app.traversal.routes.duplicate(true);audit.steps.append(row)
		minimum=minf(minimum,float(row.clearance.all_minimum))
		if i==59:audit.first60=row.duplicate(true)
		if not moved and app.world.actors.housemate_1.position.distance_to(origin)>.1:moved=true;audit.movement=row.duplicate(true)
		completed=audit.completions.any(func(e:Dictionary)->bool:return str(e.id)=="housemate_1")
		if moved and completed:break
	await press("Ⅱ");_exclude_inputs();app._process(.05);await frames(1)
	check(audit.steps.size()<=493,"Fresh continuation stays within the original remaining493-call horizon; no extension.")
	check(moved,"Fresh actual saved observation resumes ordinary physical Ellis movement without rescue.")
	check(completed,"Fresh unchanged autonomy physically completes an actual useful Ellis activity within the original remaining budget.")
	check(minimum>=LifeTraversal.BODY_GAP-.000001,"Resumed samples retain the existing physical clearance threshold.")
	check(native_excluded,"All ordinary continuation calls retain explicit native and Node input isolation.")
	audit.origin=origin;audit.original_destination=destination;audit.original_read=action_before;audit.original_action_retained_at_end=is_same(sim.get_current_action(),action);audit.minimum_clearance=minimum;audit.final=_busy_record();audit.final_state=_query_state()
