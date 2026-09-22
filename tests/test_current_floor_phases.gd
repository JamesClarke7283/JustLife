extends "res://tests/test_current_floor.gd"
var contract:Dictionary={}

func _facts()->Dictionary:
	var data:Dictionary=_state();var waits:Dictionary={}
	for id:String in data.motions:
		var motion:Dictionary=data.motions[id];waits[id]={}
		for key:String in ["waiting","wait_started","wait_review","wait_destination","resume_active","walk"]:waits[id][key]=motion[key]
	data.erase("routes");data.erase("motions");data.erase("blocked")
	data["waits"]=waits;data["journeys"]=app.traversal.snapshot();data["layout"]=app.world.serialize_items()
	return data

func _resume_composed()->void:
	test_phase=FileAccess.get_file_as_string("res://evidence/test_phase.txt").strip_edges()
	if test_phase.begins_with("produce"):
		await super._resume_composed();return
	contract=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/contract.json"))
	var decoded:Dictionary=LifeSaveLibrary.read_slot(str(contract.slot))
	check(bool(decoded.ok),"Actual v3 phase file passes strict detached save validation.")
	if not bool(decoded.ok):return
	audit["decoded"]=decoded.data
	await _public_load()
	check(app.active_save_id==str(contract.slot) and app.mode=="live","Public Load adopts the actual v3 phase file.")
	if app.active_save_id!=str(contract.slot):audit["notice"]=app.notice_label.text;return
	check(app.household.speed==0 and app.household.members.all(func(m:Dictionary)->bool:return m.sim.speed==0),"Fresh v3 load leaves every speed paused.")
	check(app.household.day==int(decoded.data.day) and app.household.minutes==float(decoded.data.minutes) and app.household.funds==int(decoded.data.funds),"Fresh phase clock and funds equal their exact decoded values.")
	for member:Dictionary in decoded.data.members:
		var id:String=str(member.id);var expected:Dictionary=member.state.duplicate(true)
		for action:Dictionary in expected.action_queue:
			if action.has("target_position"):
				var p:Array=action.target_position;action.target_position=Vector3(p[0],p[1],p[2])
			if action.has("progress") and float(action.get("duration",0.0))>0.0:action.progress=clampf(float(action.get("elapsed",0.0)),0.0,float(action.duration))/float(action.duration)
		check(_same(app.household.member_sim(id).get_state(),expected),"Complete member state matches decoded values and existing action-vector/progress reconstruction: "+id)
		var p:Array=decoded.data.journeys.members[id].position
		check(app.world.actors[id].position==Vector3(p[0],p[1],p[2]),"Exact saved typed body survives phase load: "+id)
	check(_same(app.household.meals.get_state(),decoded.data.meals),"Full saved food values survive phase load.")
	check(app.traversal.courtesy.staged_current_floor.is_empty() and app.traversal.courtesy.owner(app.traversal)==DONOR,"Expected saved owner publishes only after prepared validation completes.")
	var actual:Dictionary=app.traversal.routes[DONOR].courtesy;var expected_fact:Dictionary=decoded.data.journeys.members[DONOR].motion.courtesy.duplicate(true)
	expected_fact.anchor=LifeJourneyState.vector(expected_fact.anchor)
	check(_same(actual,expected_fact),"Phase, anchor, peer identity, kind and deadline retain exact saved facts.")
	check(int(app.traversal.routes[DONOR].identity)==219 and int(app.traversal.routes[PEER].identity)==218 and int(app.traversal.routes[DONOR].ticket)==0 and app.traversal.routes[DONOR].destination==Vector3(-4.25,3.16,.75) and app.traversal.routes[DONOR].wait==Vector3(-2.5,.16,-3.5),"Fresh donor retains original full upstairs intent and chosen unowned stair wait.")
	check(app.motion_states[PEER].waiting and float(app.motion_states[PEER].wait_started)==float(decoded.data.members[0].state.character.world_state.resource_wait_started),"Fresh Rowan retains the original saved FIFO reservation.")
	var before:Dictionary=_facts();audit["fresh_initial"]=before
	for i:int in range(10):app._process(.05);await frames(1)
	check(before==_facts(),"Ten paused phase calls preserve complete typed authoritative facts.")
	initial=_state();_connect_audit()

func _run_composed()->void:
	if test_phase.begins_with("produce"):await _produce_phase()
	else:await _continue_phase()

func _produce_phase()->void:
	var wanted:String="retreat" if test_phase.ends_with("retreat") else "hold"
	await press("▶")
	var seen:bool=false
	for step:int in range(200):
		app._process(.05);await frames(1)
		var row:Dictionary=_state();row["step"]=step;rows.append(row)
		if app.traversal.courtesy.owner(app.traversal)!=DONOR:continue
		var fact:Dictionary=app.traversal.routes[DONOR].courtesy
		if str(fact.phase)==wanted and app.world.actors[DONOR].position.distance_to(initial.bodies[DONOR].position)>.03:seen=true;break
	check(seen,"The actual ordinary continuation naturally reaches the requested moving-retreat or hold phase.")
	audit["rows"]=rows;audit["trace"]=app.traversal.courtesy.trace.duplicate(true)
	if not seen:return
	var before:Dictionary=_facts();audit["before_pause"]=before
	await press("Ⅱ");app._process(.05);await frames(1)
	var expected:Dictionary=before.duplicate(true);expected.speed=0
	for id:String in expected.people:expected.people[id].speed=0
	check(expected==_facts(),"Public Pause materializes only aggregate and individual speeds at the actual phase.")
	var paused:Dictionary=_facts();audit["paused"]=paused
	var physical:Dictionary=app._physical_snapshot_context()
	check(not physical.has("error"),"Pure physical capture supplies the exact public-save cache projection.")
	var expected_saved:Dictionary=paused.duplicate(true)
	for id:String in expected_saved.people:expected_saved.people[id].character.world_state=physical.members[id]
	# `save_game` writes the shared world fields (land, properties, the autosave
	# interval) into the saved member alongside the physical capture, so the
	# expectation carries the live values the save itself writes.
	var selected:String=str(app.household.selected_id())
	expected_saved.people[selected].character.world_state["land"]=LifeBuildingState.land.duplicate(true)
	expected_saved.people[selected].character.world_state["properties"]=app._properties_for_save()
	expected_saved.people[selected].character.world_state["autosave_minutes"]=app.autosave_minutes
	await _public_save("Vale household — current-floor "+wanted)
	var result:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	audit["after_save"]=_facts();audit["save_expected"]=expected_saved
	check(bool(result.ok) and app.active_save_id!=SLOT,"Public Save creates a readable distinct actual v3 phase slot.")
	check(expected_saved==_facts(),"Named Save changes only the exact existing physical world-cache projection; all other authoritative state remains typed-exact.")
	check(app.traversal.courtesy.owner(app.traversal)==DONOR and str(app.traversal.routes[DONOR].courtesy.phase)==wanted,"Save retains the actual courtesy phase rather than inducing recovery or discarding it.")
	audit["saved"]={"slot":app.active_save_id,"phase":wanted,"read":result,"notice":app.notice_label.text}

func _continue_phase()->void:
	var donor_action:Dictionary=app.household.member_sim(DONOR).get_current_action();var peer_action:Dictionary=app.household.member_sim(PEER).get_current_action()
	var donor_queue:Array=app.household.member_sim(DONOR).action_queue.duplicate(true);var later:Array=app.household.member_sim(PEER).action_queue.slice(1).duplicate(true)
	var signature:Array=app.traversal.courtesy._floor_signature(app.traversal,DONOR);var wait_stamp:float=app.motion_states[PEER].wait_started
	var deadline:float=app.traversal.routes[DONOR].courtesy.expires_at
	var ownership:bool=true;var waiting:bool=true;var admitted:bool=false;var resumed:bool=false;var release_body:Vector3=Vector3.INF
	var min_gap:float=INF;var min_pair:Array=[]
	await press("▶")
	for step:int in range(200):
		if _now()>=deadline:break
		app._process(.05);await frames(1)
		var row:Dictionary=_state();row["step"]=step;rows.append(row)
		if app.traversal.courtesy.owner(app.traversal)==DONOR:
			ownership=ownership and app.traversal.courtesy._floor_signature(app.traversal,DONOR)==signature and app.household.member_sim(DONOR).action_queue==donor_queue and is_same(app.household.member_sim(DONOR).get_current_action(),donor_action)
		elif not release_body.is_finite():release_body=app.world.actors[DONOR].position
		elif app.world.actors[DONOR].position.distance_to(release_body)>.03:resumed=is_same(app.household.member_sim(DONOR).get_current_action(),donor_action) and int(app.traversal.routes.get(DONOR,{}).get("identity",-1))==219 and app.traversal.routes[DONOR].destination==initial.routes[DONOR].destination and str(app.traversal.routes[DONOR].error).is_empty()
		if is_same(app.household.member_sim(PEER).get_current_action(),peer_action):
			if str(peer_action.phase)=="approach":waiting=waiting and bool(app.motion_states[PEER].waiting) and float(app.motion_states[PEER].wait_started)==wait_stamp and app.household.member_sim(PEER).action_queue.slice(1)==later and not bool(peer_action.paid) and float(peer_action.elapsed)==0.0
			elif str(peer_action.phase)=="active":admitted=app.world.actors[PEER].position==peer_action.target_position and float(peer_action.elapsed)==0.0 and app.household.member_sim(PEER).action_queue.slice(1)==later
		for member:Dictionary in app.household.members:
			var a:LifeActor=app.world.actors[member.id]
			if not a.visible:continue
			for id:String in app.world.actors:
				var b:LifeActor=app.world.actors[id]
				if id==member.id or not b.visible or absf(a.position.y-b.position.y)>.8:continue
				var gap:float=a.position.distance_to(b.position)
				if gap<min_gap:min_gap=gap;min_pair=[member.id,id,step,a.position,b.position]
		if admitted and resumed:break
	audit["rows"]=rows;audit["trace"]=app.traversal.courtesy.trace.duplicate(true);audit["final"]=_facts();audit["gap"]={"minimum":min_gap,"pair":min_pair};audit["deadline"]=deadline
	check(ownership,"Fresh courtesy preserves Morgan's full reconstructed future journey, unpaid queue and original action.")
	check(waiting,"Until actual arrival Rowan retains FIFO, unpaid approach and later explicit Cook.")
	check(admitted,"Fresh Rowan physically reaches the original bookcase and starts Read at elapsed0 with later Cook exact.")
	check(resumed,"Fresh Morgan physically resumes original route219 with no continuation error.")
	check(app.traversal.courtesy.trace.any(func(e:Dictionary)->bool:return str(e.get("released",""))==DONOR and str(e.get("reason",""))=="beneficiary_retired"),"Fresh beneficiary retirement, not expiry, releases the donor.")
	check(_now()<deadline and min_gap>=.72,"Physical recovery finishes within the original saved deadline with household-to-visible clearance intact.")
