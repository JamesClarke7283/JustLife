extends "res://tests/test_activity_flow.gd"
## Genuine current-floor passage; run only through run_current_floor.py.
const SLOT="life_1788975081557_584989380"
const DONOR="housemate_2"
const PEER="player"
var initial:Dictionary={}
var rows:Array=[]
var phase:String="current_floor"
var wallet_last:Dictionary={}
var event_file:FileAccess

func _run()->void:
	audit={"events":[],"wallet":[],"steps":[],"saves":[],"completions":[]}
	await _start_activity("natural")
	event_file=FileAccess.open(screenshot_dir.path_join(phase_tag+"_events.jsonl"),FileAccess.WRITE)
	await _resume_composed()
	if failures.is_empty():await _run_composed()
	await _finish()

func _state()->Dictionary:
	var people:Dictionary={};var bodies:Dictionary={};var routes:Dictionary={}
	for member:Dictionary in app.household.members:
		people[member.id]=member.sim.get_state().duplicate(true)
		if app.traversal.routes.has(member.id):routes[member.id]=app.traversal.routes[member.id].duplicate(true)
	for id:String in app.world.actors:
		var actor:LifeActor=app.world.actors[id];bodies[id]={"position":actor.position,"rotation":actor.rotation,"visible":actor.visible}
	return {"at":_now(),"funds":app.household.funds,"speed":app.household.speed,"people":people,"bodies":bodies,"routes":routes,"stairs":app.traversal.stairs.duplicate(true),"motions":app.motion_states.duplicate(true),"food":app.household.meals.get_state(),"bound":app.bound_member_id,"selected":app.household.selected_id(),"blocked":app.traversal.courtesy.blocked.duplicate(true)}

func _same(a:Variant,b:Variant)->bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for k:Variant in a:
			if not b.has(k) or not _same(a[k],b[k]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i:int in range(a.size()):
			if not _same(a[i],b[i]):return false
		return true
	return a==b

func _resume_composed()->void:
	var decoded:Dictionary=LifeSaveLibrary.read_slot(SLOT)
	check(bool(decoded.ok),"The genuine4107 named save is readable by the unchanged save boundary.")
	if not bool(decoded.ok):return
	await _public_load()
	check(app.active_save_id==SLOT and app.mode=="live","The public picker loads the actual4107 slot.")
	check(app.household.speed==0 and app.household.members.all(func(m:Dictionary)->bool:return m.sim.speed==0),"Aggregate and every individual member load paused.")
	for saved:Dictionary in decoded.data.members:
		var id:String=str(saved.id);var sim:LifeSim=app.household.member_sim(id)
		check(sim.needs==saved.state.needs and sim.career==saved.state.career,"Exact decoded needs and career survive: "+id)
		var expected:Array=saved.state.action_queue.duplicate(true)
		for a:Dictionary in expected:
			if a.has("target_position"):
				var p:Array=a.target_position;a.target_position=Vector3(p[0],p[1],p[2])
			if a.has("progress") and float(a.get("duration",0.0))>0.0:a.progress=clampf(float(a.get("elapsed",0.0)),0.0,float(a.duration))/float(a.duration)
		check(_same(sim.action_queue,expected),"Full decoded queue retains payment and elapsed, with exact existing target-vector/progress reconstruction: "+id)
		var p:Array=decoded.data.journeys.members[id].position
		check(app.world.actors[id].position==Vector3(p[0],p[1],p[2]),"Exact typed saved body loads: "+id)
	var paused:Dictionary=_state();audit["before_paused_steps"]=paused
	for i:int in range(10):app._process(.05);await frames(1)
	audit["after_paused_steps"]=_state()
	var expected_paused:Dictionary=paused.duplicate(true)
	check(not paused.motions.housemate_3.has("traversal") and not paused.routes.has("housemate_3") and not app.traversal.routes.has("housemate_3") and app.motion_states.housemate_3.traversal=={},"Only Casey's absent derived route cache materializes as the existing empty traversal.")
	expected_paused.motions.housemate_3["traversal"]={}
	check(expected_paused==_state(),"Ten paused steps preserve all typed facts with only the recorded absent-to-empty route cache materialization.")
	initial=_state();audit["decoded"]=decoded.data;audit["initial"]=initial
	check(int(app.traversal.routes[DONOR].identity)==219 and int(app.traversal.routes[PEER].identity)==218,"Original donor219 and resource-return218 identities survive fresh reconstruction.")
	check(app.traversal.courtesy._current_floor_donor(app.traversal,DONOR),"Actual restored Morgan is an unpaid pre-stair current-floor donor with no ticket or custody.")
	check(app.traversal.courtesy._resource_return(app.traversal,PEER),"Actual restored Rowan retains FIFO while physically returning to its now-free furnishing.")
	_connect_audit()

func _natural_passage()->void:
	phase="local_passage"
	var original_donor:Dictionary=app.household.member_sim(DONOR).get_current_action()
	var original_peer:Dictionary=app.household.member_sim(PEER).get_current_action()
	var donor_queue:Array=app.household.member_sim(DONOR).action_queue.duplicate(true)
	var later:Array=app.household.member_sim(PEER).action_queue.slice(1).duplicate(true)
	var floor_signature:Array=app.traversal.courtesy._floor_signature(app.traversal,DONOR)
	var wait_stamp:float=float(app.motion_states[PEER].wait_started)
	var observed:bool=false;var retreated:bool=false;var admitted:bool=false;var resumed:bool=false
	var ownership_exact:bool=true;var waiting_exact:bool=true;var admission_exact:bool=true
	var release_body:Vector3=Vector3.INF;var min_gap:float=INF;var min_pair:Array=[]
	var initial_body:Vector3=app.world.actors[DONOR].position
	await press("▶")
	var deadline:int=Time.get_ticks_msec()+180000
	for step:int in range(200):
		if Time.get_ticks_msec()>=deadline:break
		app._process(.05);await frames(1)
		var row:Dictionary=_state();row["step"]=step;rows.append(row)
		var owner:String=app.traversal.courtesy.owner(app.traversal)
		if owner==DONOR:
			observed=true
			ownership_exact=ownership_exact and app.traversal.courtesy._floor_signature(app.traversal,DONOR)==floor_signature and app.household.member_sim(DONOR).action_queue==donor_queue and is_same(app.household.member_sim(DONOR).get_current_action(),original_donor)
			if app.world.actors[DONOR].position.distance_to(initial_body)>.1:retreated=true
		elif observed and not release_body.is_finite():release_body=app.world.actors[DONOR].position
		elif release_body.is_finite() and app.world.actors[DONOR].position.distance_to(release_body)>.03:
			resumed=is_same(app.household.member_sim(DONOR).get_current_action(),original_donor) and int(app.traversal.routes.get(DONOR,{}).get("identity",-1))==219 and app.traversal.routes[DONOR].destination==initial.routes[DONOR].destination
		var current:Dictionary=app.household.member_sim(PEER).get_current_action()
		if is_same(current,original_peer) and str(current.phase)=="approach":
			waiting_exact=waiting_exact and bool(app.motion_states[PEER].waiting) and float(app.motion_states[PEER].wait_started)==wait_stamp and app.household.member_sim(PEER).action_queue.slice(1)==later and not bool(current.paid) and float(current.elapsed)==0.0
		if is_same(current,original_peer) and str(current.phase)=="active":
			admitted=true
			admission_exact=admission_exact and app.world.actors[PEER].position==original_peer.target_position and app.household.member_sim(PEER).action_queue.slice(1)==later
		for member:Dictionary in app.household.members:
			var a:LifeActor=app.world.actors[member.id]
			if not a.visible:continue
			for id:String in app.world.actors:
				var b:LifeActor=app.world.actors[id]
				if id==member.id or not b.visible or absf(a.position.y-b.position.y)>.8:continue
				var gap:float=a.position.distance_to(b.position)
				if gap<min_gap:min_gap=gap;min_pair=[member.id,id,step,a.position,b.position]
		if observed and retreated and admitted and resumed:break
	audit["rows"]=rows;audit["trace"]=app.traversal.courtesy.trace.duplicate(true);audit["final"]=_state();audit["gap"]={"minimum":min_gap,"pair":min_pair}
	check(observed,"Ordinary advancing steps select the typed Morgan-to-Rowan passage.")
	check(retreated,"Morgan physically retreats under ordinary swept movement.")
	check(ownership_exact,"During courtesy Morgan retains the complete fresh-restored future legs, chosen wait, ticket, destination, queue and instruction.")
	check(waiting_exact,"Until actual Read admission Rowan retains the original FIFO stamp, unpaid approach and later explicit Cook.")
	check(admitted and admission_exact,"Rowan physically arrives at the original bookcase and starts the original Read with later explicit Cook exact.")
	check(resumed,"After passage Morgan physically resumes the original route219 and upstairs Sleep destination.")
	check(app.traversal.courtesy.trace.any(func(e:Dictionary)->bool:return str(e.get("released",""))==DONOR and str(e.get("reason",""))=="beneficiary_retired"),"Actual beneficiary retirement releases the donor; expiry is not accepted as recovery.")
	check(min_gap>=.72,"Every sampled household body retains .72 clearance against all visible actors.")

func _run_composed()->void:
	var original:Dictionary=app.household.member_sim(DONOR).get_current_action()
	var original_queue:Array=app.household.member_sim(DONOR).action_queue.duplicate(true)
	var goal:Vector3=original.target_position
	await _natural_passage()
	if not failures.is_empty():return
	# A separate bounded observation after the unchanged43-call passage gate.
	var continuation:Array=[];var seen_entry:bool=false;var seen_transit:bool=false;var seen_clear:bool=false;var released:bool=false;var arrived:bool=false
	var same_instruction:bool=true;var protected_valid:bool=true;var no_early_start:bool=true
	var min_gap:float=INF;var min_pair:Array=[];var began:float=_now();var wall_deadline:int=Time.get_ticks_msec()+180000
	for step:int in range(400):
		if Time.get_ticks_msec()>=wall_deadline:break
		app._process(.05);await frames(1)
		var state:Dictionary=_state();state["step"]=step;continuation.append(state)
		var current:Dictionary=app.household.member_sim(DONOR).get_current_action()
		if not is_same(current,original):same_instruction=false;break
		var route:Dictionary=app.traversal.routes.get(DONOR,{})
		if not route.is_empty():
			var phase_name:String=str(route.phase)
			if phase_name in ["entry","transit","clear"]:
				var lock:Dictionary=app.traversal.stairs.get(str(route.stair_id),{})
				protected_valid=protected_valid and int(route.identity)==219 and int(route.ticket)>0 and str(lock.get("owner",""))==DONOR and route.destination==goal and str(route.custody).is_empty() and not bool(route.safety)
				seen_entry=seen_entry or phase_name=="entry";seen_transit=seen_transit or phase_name=="transit";seen_clear=seen_clear or phase_name=="clear"
				if phase_name=="transit":protected_valid=protected_valid and app.world.actors[DONOR].stair_pose_valid
			elif seen_clear and int(route.identity)!=219:released=true
		if seen_clear and not app.traversal.stairs.values().any(func(lock:Dictionary)->bool:return str(lock.owner)==DONOR):released=true
		if str(current.phase)=="approach":no_early_start=no_early_start and not bool(current.paid) and float(current.elapsed)==0.0 and app.household.member_sim(DONOR).action_queue==original_queue
		elif str(current.phase)=="active":arrived=app.world.actors[DONOR].position==goal and bool(current.paid) and float(current.elapsed)==0.0
		for member:Dictionary in app.household.members:
			var a:LifeActor=app.world.actors[member.id]
			if not a.visible:continue
			for id:String in app.world.actors:
				var b:LifeActor=app.world.actors[id]
				if id==member.id or not b.visible or absf(a.position.y-b.position.y)>.8:continue
				var gap:float=a.position.distance_to(b.position)
				if gap<min_gap:min_gap=gap;min_pair=[member.id,id,step,a.position,b.position]
		if arrived:break
	audit["stair_continuation"]={"start_at":began,"end_at":_now(),"cap_calls":400,"rows":continuation,"entry":seen_entry,"transit":seen_transit,"clear":seen_clear,"released":released,"arrived":arrived,"gap":{"minimum":min_gap,"pair":min_pair},"final":_state()}
	check(same_instruction and no_early_start,"The original Sleep instruction and complete queue survive real approach without early payment or progress.")
	check(seen_entry and seen_transit and seen_clear and protected_valid,"Morgan naturally owns a real ticket and lock through entry, supported stair transit and clearance.")
	check(released,"The original protected crossing clears and retires its lock through ordinary movement.")
	check(arrived,"Morgan physically reaches the original upstairs Sleep anchor and begins that exact instruction at elapsed0.")
	check(min_gap>=.72,"The bounded continuation preserves household-versus-visible body clearance.")

func _event(kind:String,data:Dictionary)->void:
	var row:Dictionary={"kind":kind,"phase":phase,"at":_now() if is_instance_valid(app) and is_instance_valid(app.household) else 0.0,"data":data.duplicate(true)}
	audit.events.append(row)
	if event_file:event_file.store_line(JSON.stringify(_finite_diagnostic(LifeSaveLibrary._json_safe(row)),"",true,true));event_file.flush()

func _connect_audit()->void:
	app.household.member_action_started.connect(func(id:String,a:Dictionary):_wallet_observe("action_started",id);_event("action_started",{"id":id,"sim_at":_sim_now(id),"action":a}))
	app.household.member_action_finished.connect(func(id:String,a:Dictionary):_wallet_observe("action_finished",id);_event("action_finished",{"id":id,"sim_at":_sim_now(id),"action":a,"needs":app.household.member_sim(id).needs.duplicate(true)}))
	app.household.notice.connect(func(msg:String):_event("notice",{"message":msg}))
	for member:Dictionary in app.household.members:
		var id:String=str(member.id)
		member.sim.changed.connect(func():_wallet_observe("changed",id))
	wallet_last={"funds":app.household.funds}

func _sim_now(id:String)->float:
	var sim:LifeSim=app.household.member_sim(id)
	return float(sim.day-1)*1440.0+sim.minutes

func _wallet_observe(trigger:String,id:String="")->void:
	var value:int=app.household.funds if id.is_empty() else app.household.member_sim(id).funds
	if not wallet_last.has("funds"):wallet_last.funds=value;return
	if value!=int(wallet_last.funds):
		var row:Dictionary={"at":_now(),"sim_at":_sim_now(id) if not id.is_empty() else _now(),"before":wallet_last.funds,"after":value,"delta":value-int(wallet_last.funds),"trigger":trigger,"member":id,"action":app.household.member_sim(id).get_current_action().duplicate(true) if not id.is_empty() else {}}
		audit.wallet.append(row);wallet_last.funds=value;_event("wallet",row)

func _select(id:String)->void:
	await press_member(str(app.household.member_sim(id).character.name))

func _finite_diagnostic(value:Variant)->Variant:
	if value is float and not is_finite(value):
		return {"__diagnostic_nonfinite__":"nan" if is_nan(value) else ("positive_infinity" if value>0.0 else "negative_infinity")}
	if value is Array:
		var result:Array=[]
		for entry:Variant in value:result.append(_finite_diagnostic(entry))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[key]=_finite_diagnostic(value[key])
		return result
	return value

func _finish()->void:
	check(_input_excluded(),"All GUI, Node input and direct camera polling stay excluded before teardown.")
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
	var f:=FileAccess.open(screenshot_dir.path_join(phase_tag+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(_finite_diagnostic(LifeSaveLibrary._json_safe(audit)),"  ",true,true));f.close()
	print("CURRENT_FLOOR_RESULT assertions=%d failures=%d phase=%s"%[assertions,failures.size(),phase_tag])
	quit(0 if failures.is_empty() else 1)
