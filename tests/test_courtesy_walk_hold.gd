extends "res://tests/test_courtesy_walk_observation.gd"
## Separately authorized directed public walk; no original235 recovery claim.
var test_mode:String=OS.get_environment("WALK_TEST_MODE")
var phase_wanted:String=OS.get_environment("WALK_PHASE")
var loaded_slot:String=OS.get_environment("WALK_SLOT")
var saved_destination:Vector3=Vector3.INF
const PUBLIC_DESTINATION=Vector3(-3,.16,-1)
var walk_identity:int=-1
var step_count:int=0
var prior_identity:int=27

func _initialize()->void:
	var base:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not base.get_file().begins_with("justlife-playthrough-beneficiaries") or OS.get_environment("JUSTLIFE_DATA_DIR")!=OS.get_environment("WALK_RUN_ROOT").path_join("save_data") or OS.get_environment("WALK_CANDIDATE_TOKEN").is_empty() or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Nominated candidate and private walk test roots required");quit(2);return
	root.gui_disable_input=true;node_added.connect(exclude_input);run.call_deferred()

func write_json(name:String,value:Variant)->void:
	var f:=FileAccess.open(OS.get_environment("WALK_RUN_ROOT").path_join("evidence").path_join(name),FileAccess.WRITE)
	f.store_string(JSON.stringify(wire(value),"  ",true,true));f.close()

# Exact existing scalar comparison/projections from the reviewed stair study.
# No float tolerance, rounding, blanket serialization or calendar advancement.
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


func _project_queue(queue:Array)->Array:
	# The loader rebuilds each stored action from the live definition table (with
	# the recipe's own definition for a cook) and then adopts the saved progress,
	# so a definition-derived field (`label`, `changes`, `cost`, `description`,
	# `skill`, `xp`) reflects today's code rather than the text that was saved —
	# which is what lets a retuned activity load. The saved duration, elapsed,
	# identity and ownership are what a fresh load must preserve.
	var result:Array=queue.duplicate(true)
	for action:Dictionary in result:
		action.progress=clampf(float(action.elapsed)/float(action.duration),0.0,1.0)
		var definition:Dictionary=app.sim._actions.get(str(action.get("id","")),{})
		if definition.is_empty():continue
		var rebuilt:Dictionary=definition.duplicate(true)
		if str(action.get("id",""))=="cook":rebuilt=LifeMeals.cooking_definition(rebuilt,str(action.get("recipe","garden_skillet")))
		for key:String in ["label","changes","cost","description","skill","xp"]:
			if rebuilt.has(key):action[key]=rebuilt[key]
	return result


func _decoded_integer_fields(decoded:Dictionary,fields:Array,scope:String)->Dictionary:
	var result:Dictionary=decoded.duplicate(true)
	var invalid:Array[String]=[]
	for key:String in fields:
		var value:Variant=decoded.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)):
			invalid.append(scope+"."+key)
	check(invalid.is_empty(),"Specified decoded identity fields are finite integral values: "+scope+str(invalid))
	if not invalid.is_empty():return result
	for key:String in fields:result[key]=int(decoded[key])
	return result

func _now()->float:return float(app.household.day-1)*1440.0+app.household.minutes

func authoritative_facts()->Dictionary:
	# Same named authoritative scope as the accepted stair phase study, plus
	# sanitation/all visible bodies. Full semantic snapshots accompany saves.
	return {"clock":[app.household.day,app.household.minutes,app.household.speed],"speeds":speeds(),"funds":app.household.funds,"people":app.household.members.map(func(m:Dictionary):return {"id":m.id,"position":app.world.actors[m.id].position,"yaw":app.world.actors[m.id].rotation.y,"queue":m.sim.action_queue.duplicate(true),"needs":m.sim.needs.duplicate(true),"career":m.sim.career.duplicate(true),"education":m.sim.education.duplicate(true)}),"actors":semantic().actors,"journeys":app.traversal.snapshot(),"food":app.household.meals.get_state(),"sanitation":app.household.sanitation.get_state(),"visitor":app.residents.home_visit.state.duplicate(true),"stair_locks":app.traversal.stairs.duplicate(true)}

func press_speed(text:String)->void:
	var found:Button
	for n:Node in app.find_children("*","Button",true,false):
		if n.text==text and n.is_visible_in_tree():found=n;break
	check(is_instance_valid(found),"Existing public speed control found: "+text)
	if is_instance_valid(found):found.pressed.emit()
	freeze(app);input_guard.grab_focus()
	report.speed_observations.append(speeds())

func adopted_pause()->void:
	var before:Dictionary=authoritative_facts();var expected:Dictionary=before.duplicate(true)
	# An explicit speed-only expected delta, not a comparison normalization.
	expected.clock[2]=0;expected.speeds.household=0;expected.speeds.selected=0;expected.speeds.bound=0
	for id:String in expected.speeds.members:expected.speeds.members[id].speed=0
	press_speed("Ⅱ");await ordinary_step()
	var after:Dictionary=authoritative_facts()
	check(after==expected,"Public pause adoption changes only the explicitly requested speed fields")
	report.pause_boundary={"before":wire(before),"expected_speed_only":wire(expected),"after":wire(after)}
	check(app.household.speed==0 and app.sim.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Pause adopted in direct selected, aggregate and all member clocks")

func compare_loaded(disk:Dictionary)->void:
	check(app.household.funds==int(disk.funds) and app.household.day==int(disk.day) and app.household.minutes==float(disk.minutes),"Fresh named load preserves exact decoded wallet and clock")
	var expected_journeys:Dictionary=_project_journeys(disk.journeys)
	if test_mode=="produce":
		check(disk.journeys.version==1 and LifeJourneyState.VERSION==2,"Genuine first-crowd legacy reader1 and current writer2 are explicit")
		expected_journeys.version=LifeJourneyState.VERSION
		report.legacy_writer_boundary={"raw_version":disk.journeys.version,"expected_writer_version":LifeJourneyState.VERSION,"expected_complete_journeys":expected_journeys}
	check(_same(expected_journeys,app.traversal.snapshot()),"Complete journeys match exact typed projection and only declared legacy writer version delta")
	for saved:Dictionary in disk.members:
		var sim:LifeSim=app.household.member_sim(str(saved.id))
		check(_same(_project_queue(saved.state.action_queue),sim.action_queue),"Complete fresh queue/paid/duration/target and elapsed-derived progress: "+str(saved.id))
		check(sim.needs==saved.state.needs,"Exact fresh needs: "+str(saved.id))
		# A career's level and salary are whole numbers the game stores as ints,
		# so JSON hands them back as floats. They are compared through the same
		# named integer projection the education and food identities use.
		check(sim.career==_decoded_integer_fields(saved.state.career,["level","salary"],str(saved.id)+".career"),"Exact fresh career with its existing integer level and salary identities: "+str(saved.id))
		check(sim.education==_decoded_integer_fields(saved.state.education,["attended","enrolled_day","first_class_day","homework","last_attendance_day","last_day","last_homework_day","last_prepared_homework_day","missed","prepared","version"],str(saved.id)+".education"),"Exact education with existing nominated integer identities: "+str(saved.id))
	check(app.household.meals.get_state()==_decoded_integer_fields(disk.meals,["version","serial"],"food"),"Exact fresh food with only existing version/serial integer identities")

func walk_fact()->Dictionary:
	var t=app.traversal;var donor:String=t.courtesy.owner(t)
	if donor.is_empty():return {}
	var fact:Dictionary=t.routes[donor].courtesy
	if str(fact.get("beneficiary_kind",""))!="walk" or str(fact.get("beneficiary_id",""))!=MORGAN or int(fact.get("beneficiary_identity",-1))!=walk_identity:return {}
	return {"donor":donor,"fact":fact.duplicate(true),"route":t.routes[donor].duplicate(true)}

func record_step()->Dictionary:
	return {"step":step_count,"speeds":speeds(),"journeys":app.traversal.snapshot(),"routes":app.traversal.routes.duplicate(true),"motions":app.motion_states.duplicate(true),"bodies":body_facts(),"actors":semantic().actors,"queues":app.household.members.map(func(m:Dictionary):return {"id":m.id,"queue":m.sim.action_queue.duplicate(true)}),"courtesy_trace":app.traversal.courtesy.trace.duplicate(true)}

func run()->void:
	phase=test_mode+"_"+phase_wanted
	check(test_mode in ["natural","produce","fresh"],"Nominated test mode is explicit")
	if test_mode!="natural":check(phase_wanted in ["retreat","hold"],"Observed phase is explicitly named")
	input_guard=LineEdit.new();input_guard.name="DiagnosticPolledInputGuard";input_guard.position=Vector2(-10000,-10000);root.add_child(input_guard)
	app=MainScene.instantiate();root.add_child(app);current_scene=app;freeze(app);await frames(3)
	var read:Dictionary=LifeSaveLibrary.read_slot(loaded_slot);check(bool(read.get("ok",false)),"Actual input slot passes production named read")
	if not bool(read.get("ok",false)):await finish();return
	app.load_game(loaded_slot);freeze(app);input_guard.grab_focus();await frames(3)
	check(app.active_save_id==loaded_slot and app.mode=="live","Production named load adopts exact input slot")
	check(app.household.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Actual input loads paused without a helper-induced pause")
	report.loaded_read=wire(read);compare_loaded(read.data)
	check(app.traversal.routes.has(MORGAN),"Actual saved Morgan route is present")
	if not app.traversal.routes.has(MORGAN):await finish();return
	var route:Dictionary=app.traversal.routes[MORGAN];saved_destination=route.destination
	if test_mode=="produce":
		var action:Dictionary=app.household.member_sim(MORGAN).get_current_action()
		prior_identity=int(route.identity)
		check(prior_identity==27 and saved_destination==PUBLIC_DESTINATION and str(action.get("id",""))=="eat_meal" and str(action.get("phase",""))=="approach" and action.target_position==PUBLIC_DESTINATION,"Genuine first-crowd unstarted explicit meal route27 supplies the exact public destination")
	else:
		walk_identity=int(route.identity)
		check(walk_identity!=27 and saved_destination==PUBLIC_DESTINATION and app.household.member_sim(MORGAN).action_queue.is_empty() and bool(app.motion_states[MORGAN].walk),"Actual new public walk identity/destination survives fresh load")
	if test_mode=="fresh":check(not app.traversal.courtesy._eligible(app.traversal,MORGAN) and app.traversal.courtesy._beneficiary_kind(app.traversal,MORGAN)=="walk","Fresh Morgan is a separate walk beneficiary; unchanged donor gate rejects it")
	var initial:Dictionary=semantic()
	for i:int in 10:await ordinary_step()
	check(initial==semantic(),"Ten ordinary paused calls preserve complete typed observed state")
	if test_mode=="produce" and failures.is_empty():issue_public_walk()
	report.initial=wire(record_step())
	for m:Dictionary in app.household.members:
		m.sim.changed.connect(changed_signal.bind(str(m.id)));m.sim.action_started.connect(action_event.bind(str(m.id),"started"));m.sim.action_finished.connect(action_event.bind(str(m.id),"finished"))
	if test_mode=="fresh":
		var restored:Dictionary=walk_fact()
		check(not restored.is_empty() and str(restored.fact.phase)==phase_wanted and restored.fact.version==2,"Actual fresh phase keeps scalar version2 and walk ownership")
		if restored.is_empty():await finish();return
		var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LifeSaveLibrary._slot_path(loaded_slot)))
		report.codec={"raw_fact":wire(raw.data.journeys.members[str(restored.donor)].motion.courtesy),"restored_fact":wire(restored.fact),"raw_version_type":typeof(raw.data.journeys.members[str(restored.donor)].motion.courtesy.version)}
	if failures.is_empty():await exercise()
	await finish()

func issue_public_walk()->void:
	var before:Dictionary=authoritative_facts();var semantic_before:Dictionary=semantic()
	check(app.household.selected_id()=="housemate_1" and app.household_chips.has(MORGAN),"Original selected Ellis and public Morgan household chip present")
	if not app.household_chips.has(MORGAN):return
	app.household_chips[MORGAN].pressed.emit();freeze(app);input_guard.grab_focus()
	check(app.household.selected_id()==MORGAN and str(app.sim.get_current_action().get("id",""))=="eat_meal","Public household selection binds Morgan with original explicit meal")
	check(readonly_known_corridor(),"Known original complete-occupancy corridor admits the fixed measured donor retreat")
	if not failures.is_empty():return
	app.cancel_action_button.pressed.emit();freeze(app);input_guard.grab_focus()
	check(app.sim.action_queue.is_empty() and not app.traversal.routes.has(MORGAN),"Actual public Cancel removes current meal and retires its route before new intent")
	app.world.ground_clicked.emit(PUBLIC_DESTINATION);freeze(app);input_guard.grab_focus()
	var requested:Dictionary=app.traversal.routes.get(MORGAN,{})
	check(not requested.is_empty(),"Actual connected public ground command creates a route")
	if requested.is_empty():return
	walk_identity=int(requested.identity);saved_destination=requested.destination
	check(walk_identity!=27 and saved_destination==PUBLIC_DESTINATION and app.walk_only and app.walk_destination==PUBLIC_DESTINATION and app.sim.action_queue.is_empty(),"Public request creates distinct real walk identity and selected live intent")
	var selected_request:Dictionary=semantic()
	app.household_chips["housemate_1"].pressed.emit();freeze(app);input_guard.grab_focus()
	check(app.household.selected_id()=="housemate_1" and bool(app.motion_states[MORGAN].walk) and app.motion_states[MORGAN].destination==PUBLIC_DESTINATION,"Public Ellis reselection stores the new Morgan walk intent normally")
	var after:Dictionary=authoritative_facts()
	for key:String in ["clock","speeds","funds","actors","food","sanitation","visitor","stair_locks"]:
		check(before[key]==after[key],"Public command changes no observed "+key)
	var expected_people:Array=before.people.duplicate(true)
	for person:Dictionary in expected_people:
		if person.id==MORGAN:person.queue=[]
	check(expected_people==after.people,"Only Morgan public-cancelled queue differs in complete people facts")
	for id:String in before.journeys.members:
		if id!=MORGAN:check(before.journeys.members[id]==after.journeys.members[id],"Public command preserves non-Morgan authoritative journey: "+id)
	check(app.traversal.courtesy._beneficiary_kind(app.traversal,MORGAN)=="walk","Actual new public request is independently eligible as walk beneficiary")
	report.public_command={"method":"Existing Morgan Button, existing Cancel action Button, connected world.ground_clicked to exact prior meal target, existing Ellis Button; only explicitly cancelled Morgan queue/new walk intent change.","destination":PUBLIC_DESTINATION,"original_identity":prior_identity,"actual_new_identity":walk_identity,"before":semantic_before,"after_selected_request":selected_request,"after":semantic(),"authoritative_before":before,"authoritative_after":after}

func readonly_known_corridor()->bool:
	var t=app.traversal;var c=t.courtesy;var before:Dictionary=semantic()
	var from:Vector3=app.world.actors[MORGAN].position;var donor:String="housemate_1";var anchor:=Vector3(-.75,.16,2.5)
	var level:int=app.world.point_level(from)
	var start:Dictionary=LifeLotNavigation.floor_location(level,from);var target:Dictionary=LifeLotNavigation.floor_location(level,PUBLIC_DESTINATION)
	var static_route:Dictionary=app.world.lot_navigation.route(start,target)
	var current_occupied:Array[Vector3]=c._hypothetical(t,MORGAN,MORGAN,from)
	var original_route:Dictionary=app.world.lot_navigation.route_avoiding(start,target,current_occupied,LifeTraversal.ROUTE_CLEARANCE)
	var occupied:Array[Vector3]=c._hypothetical(t,MORGAN,donor,anchor)
	var opened:Dictionary=app.world.lot_navigation.route_avoiding(start,target,occupied,LifeTraversal.ROUTE_CLEARANCE)
	var eligible:bool=c._eligible(t,donor);var anchor_clear:bool=c._anchor_clear(t,donor,anchor);var sweep:bool=c._sweep(t,donor,app.world.actors[donor].position,anchor)
	check(before==semantic(),"One fixed known-corridor geometry query leaves all original state exact")
	report.known_corridor={"before":before,"after":semantic(),"original_occupied":current_occupied,"static_route":static_route,"original_route":original_route,"donor":donor,"anchor":anchor,"eligible":eligible,"anchor_clear":anchor_clear,"sweep_clear":sweep,"hypothetical_occupied":occupied,"opened_route":opened,"commands_so_far":"Morgan selected; no Cancel or ground request, zero advancing ticks"}
	return bool(static_route.ok) and not bool(original_route.ok) and eligible and anchor_clear and sweep and bool(opened.ok) and opened.segments.all(func(leg:Dictionary):return str(leg.kind)=="floor")

func exercise()->void:
	var t=app.traversal;var original_queues:Dictionary={};var original_actions:Dictionary={};var original_routes:Dictionary={};var original_positions:Dictionary={}
	for m:Dictionary in app.household.members:
		original_queues[m.id]=m.sim.action_queue.duplicate(true);original_actions[m.id]=m.sim.get_current_action()
		original_positions[m.id]=app.world.actors[m.id].position
		if t.routes.has(m.id):original_routes[m.id]=t.routes[m.id].duplicate(true)
	var selected:Dictionary=walk_fact();var seen_hold:bool=not selected.is_empty() and str(selected.fact.phase)=="hold"
	var reached:bool=false;var retired:bool=false;var resumed:bool=false;var identity_changed:bool=false;var donor_changed:bool=false
	var unsupported:int=0;var overlaps:int=0;var steps:Array=[];var start:float=_now()
	var released_at_step:int=-1;var release_evidence:Dictionary={};var resumption_evidence:Dictionary={}
	var expiry:float=float(selected.fact.expires_at) if not selected.is_empty() else start+60.0
	press_speed("▶▶▶" if test_mode=="natural" else "▶")
	var cap:int=100 if test_mode=="natural" else 200
	for i:int in cap:
		if _now()>=expiry:break
		var donor_before:Dictionary={}
		if not selected.is_empty():
			var id:String=str(selected.donor)
			donor_before={"position":app.world.actors[id].position,"route":t.routes.get(id,{}).duplicate(true),"step":step_count}
		await ordinary_step();step_count+=1
		var current:Dictionary=walk_fact();var checkpoint_now:bool=false
		if not current.is_empty():
			if selected.is_empty():selected=current;expiry=float(current.fact.expires_at)
			var id:String=str(current.donor)
			if str(current.fact.phase)=="hold":seen_hold=true
			if not t.courtesy._eligible(t,id) or not is_same(original_actions[id],app.household.member_sim(id).get_current_action()) or app.household.member_sim(id).action_queue!=original_queues[id] or current.route.destination!=original_routes[id].destination or int(current.route.identity)!=int(original_routes[id].identity):donor_changed=true
			checkpoint_now=test_mode=="produce" and str(current.fact.phase)==phase_wanted and app.world.actors[id].position!=original_positions[id]
		if t.routes.has(MORGAN) and int(t.routes[MORGAN].identity)==walk_identity:
			if t.routes[MORGAN].destination!=saved_destination or not bool(app.motion_states[MORGAN].walk) or not app.household.member_sim(MORGAN).action_queue.is_empty():identity_changed=true
		else:retired=true
		if app.world.actors[MORGAN].position==saved_destination:reached=true
		if retired and reached and not selected.is_empty() and t.courtesy.owner(t).is_empty():
			var id:String=str(selected.donor)
			if released_at_step<0:
				released_at_step=step_count;release_evidence=record_step()
			elif step_count>released_at_step and not donor_before.is_empty():
				var before_route:Dictionary=donor_before.route
				resumed=not before_route.is_empty() and not before_route.has("courtesy") and str(before_route.phase)=="route" and int(before_route.identity)==int(original_routes[id].identity) and before_route.destination==original_routes[id].destination and app.world.actors[id].position!=donor_before.position and is_same(original_actions[id],app.household.member_sim(id).get_current_action()) and app.household.member_sim(id).action_queue==original_queues[id]
				if resumed:resumption_evidence={"before":donor_before,"after":record_step(),"donor":id,"release_step":released_at_step}
		var bodies:Dictionary=body_facts()
		for pair:Dictionary in bodies.nearby_pairs:
			if bool(pair.below_gap):overlaps+=1
		for member:Dictionary in bodies.member_support:
			if member.visible and not member.static_point_clear and not member.stair_busy:unsupported+=1
		steps.append(wire(record_step()))
		if checkpoint_now:
			check(not identity_changed and not donor_changed and overlaps==0 and unsupported==0,"Observed phase reached with exact owned intent/instruction and safe sampled bodies")
			report.observed_phase=wire(record_step());report.selected=wire(selected)
			report.producer_steps={"start":start,"end":_now(),"observed_game_minutes":_now()-start,"samples":steps}
			if failures.is_empty():await save_observed_phase(current)
			return
		if resumed:break
	report.continuation={"start":start,"end":_now(),"observed_game_minutes":_now()-start,"steps":step_count,"samples":steps,"selected":wire(selected),"seen_hold":seen_hold,"physically_reached_requested_destination":reached,"retired":retired,"donor_resumed_same_instruction":resumed,"identity_changed":identity_changed,"donor_changed":donor_changed,"overlaps":overlaps,"unsupported":unsupported,"release_evidence":wire(release_evidence),"actual_later_movement":wire(resumption_evidence)}
	check(test_mode!="produce","Requested phase must be reached naturally before a producer may succeed")
	check(not selected.is_empty() and selected.fact.version==2 and str(selected.fact.beneficiary_kind)=="walk","Natural selection uses exact scalar version2 and separate walk kind")
	check(not identity_changed and not donor_changed,"Walk destination/intent and original donor instruction survive owned motion")
	check(reached and retired and resumed,"Morgan physically reaches requested destination, retires its actual new identity, and donor resumes unchanged instruction")
	check(overlaps==0 and unsupported==0,"Sampled motion introduces no body-gap or floor-support violation")
	check(app.active_save_id==loaded_slot,"Natural/fresh continuation uses no save to induce recovery")
	report.final=wire(record_step())

func save_observed_phase(current:Dictionary)->void:
	await adopted_pause()
	var paused:Dictionary=walk_fact()
	check(not paused.is_empty() and str(paused.fact.phase)==phase_wanted,"Public pause retains the naturally observed phase")
	if paused.is_empty():return
	var before:Dictionary=authoritative_facts();var full_before:Dictionary=semantic()
	var id:String="crowd_public_walk_actual_"+phase_wanted;var ok:bool=app.save_game(id,"Actual Morgan walk — "+phase_wanted);freeze(app)
	var read:Dictionary=LifeSaveLibrary.read_slot(id)
	check(ok and bool(read.get("ok",false)),"Production named save/read validates the actual walk phase")
	check(before==authoritative_facts(),"Named phase save preserves exact authoritative body/queue/needs/resources/journey/clock scope")
	report.phase_save={"slot":id,"observed":wire(current),"read":wire(read),"authoritative_before":wire(before),"authoritative_after":wire(authoritative_facts()),"full_semantic_before":wire(full_before),"full_semantic_after":wire(semantic())}
	if not bool(read.get("ok",false)):return
	var fact:Dictionary=read.data.journeys.members[str(paused.donor)].motion.courtesy
	check(fact.version==2 and str(fact.beneficiary_kind)=="walk" and str(fact.phase)==phase_wanted and int(fact.beneficiary_identity)==walk_identity,"Actual disk scalar version/kind/phase/identity survive named codec")
	var destination:String=OS.get_environment("WALK_RUN_ROOT").path_join("evidence/actual_checkpoint.json")
	check(DirAccess.copy_absolute(LifeSaveLibrary._slot_path(id),destination)==OK,"Archive copies only the actual generated named slot bytes")
	write_json("checkpoint.json",{"slot":id,"phase":phase_wanted,"actual_file":destination,"source_token":OS.get_environment("WALK_CANDIDATE_TOKEN"),"walk_identity":walk_identity,"destination":saved_destination})
