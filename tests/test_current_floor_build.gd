extends "res://tests/test_current_floor_phases.gd"

func _reload_hold()->void:
	await _public_load()
	check(app.active_save_id==str(contract.slot) and app.household.speed==0 and app.traversal.courtesy.owner(app.traversal)==DONOR,"Independent control publicly reloads the same actual paused v3 hold.")

func _mutations()->void:
	var before:Dictionary=_facts();audit["layout_before"]=before
	var generation:int=app.world.lot_navigation.generation
	var protection:Dictionary=app.build_protection_context();var structure:Dictionary=app.world.construction.validated_state().state
	await press("Build & buy");await press("Ground")
	var plant:Dictionary=first_item("plant");var original:Vector3=plant.node.position
	app.show_build_object(plant,Vector2(760,350));await press("Move furnishing")
	check(not app.pending_move.is_empty(),"Actual unrelated plant lift changes the physical layout.")
	var destination:Vector3=Vector3.INF;var candidates:Array=[]
	for offset:Vector3 in [Vector3(.5,0,0),Vector3(-.5,0,0),Vector3(0,0,.5),Vector3(0,0,-.5),Vector3(1,0,0),Vector3(-1,0,0)]:
		var point:Vector3=original+offset;var allowed:bool=app.world.can_place(str(plant.kind),point,app.world.placement_angle)
		candidates.append({"point":point,"supported":allowed})
		if allowed:destination=point;break
	audit["layout_candidates"]=candidates
	check(destination.is_finite(),"A bounded read-only placement query finds an actual supported different plant position.")
	if destination.is_finite():app.world.placement_requested.emit(str(plant.kind),destination,app.world.placement_angle);await frames(2)
	check(app.pending_move.is_empty() and app._find_item(str(plant.id)).node.position==destination,"The public placement signal commits the real unrelated layout change.")
	await press("Live")
	var after:Dictionary=_facts();audit["layout_after"]=after;audit["layout_trace"]=app.traversal.courtesy.trace.duplicate(true)
	var acknowledged:Array=LifeBuildProtection.unchanged_routes(protection,structure,structure,app.world.lot_navigation)
	audit["unaffected_navigation"]={"before":generation,"after":app.world.lot_navigation.generation,"acknowledged":acknowledged,"route_generation":app.traversal.routes[DONOR].generation,"courtesy_generation":app.traversal.routes[DONOR].get("courtesy_generation",-1)}
	check(app.world.lot_navigation.generation!=generation and acknowledged.has(DONOR) and app.traversal.courtesy.owner(app.traversal)==DONOR and after.journeys.members[DONOR].motion.courtesy==before.journeys.members[DONOR].motion.courtesy,"An actual navigation change preserves the exact hold only after existing full-route certification and corridor rebuild.")
	check(after.waits[PEER]==before.waits[PEER],"The unchanged furnishing retains Rowan's exact ordinary FIFO through the certified navigation refresh.")
	check(after.people[DONOR].action_queue==before.people[DONOR].action_queue and after.people[PEER].action_queue==before.people[PEER].action_queue and after.bodies==before.bodies and after.at==before.at and after.funds==before.funds,"Real unrelated Build preserves both complete queues, all bodies, clock and funds.")
	check(app.traversal.routes[DONOR].destination==initial.routes[DONOR].destination and app.traversal.routes[DONOR].legs.any(func(leg:Dictionary)->bool:return str(leg.kind)=="stair" and str(leg.stair_id)=="stairs_2"),"Normal post-edit rebuilding retains Morgan's full upstairs goal and actual future staircase.")
	await _reload_hold();await _affected_route_move()
	for id:String in [DONOR,PEER]:
		await _reload_hold();await _select(id)
		before=_facts();var previous:Dictionary=app.household.member_sim(id).get_current_action();var other:String=PEER if id==DONOR else DONOR
		var generation_before:int=app.route_generation
		await press("Cancel action")
		after=_facts();audit["cancel_"+id]={"before":before,"after":after,"trace":app.traversal.courtesy.trace.duplicate(true)}
		check(not is_same(app.household.member_sim(id).get_current_action(),previous) and app.traversal.courtesy.owner(app.traversal).is_empty(),"Public cancellation retires only the selected original instruction and releases v3: "+id)
		check(app.route_generation>generation_before and after.people[other].action_queue==before.people[other].action_queue and after.bodies==before.bodies and after.at==before.at and after.funds==before.funds,"Cancellation keeps generation invalidation, the other queue and physical facts exact: "+id)
	await _reload_hold();before=_facts();var later:Dictionary=app.household.member_sim(PEER).action_queue[1];await press("Build & buy");await press("Ground")
	var target:Dictionary=app._find_item("item_14");app.show_build_object(target,Vector2(760,350));await press("Sell  +ℒ",true)
	after=_facts();audit["target_sell"]={"before":before,"after":after,"trace":app.traversal.courtesy.trace.duplicate(true)}
	check(app._find_item("item_14").is_empty() and app.traversal.courtesy.owner(app.traversal).is_empty(),"Actual public sale removes the resource and retires v3 ownership.")
	var expected_next:Array=before.people[PEER].action_queue.slice(1).duplicate(true)
	check(expected_next.size()==1 and str(expected_next[0].id)=="cook" and str(expected_next[0].phase)=="queued" and is_same(app.household.member_sim(PEER).get_current_action(),later),"Target removal synchronously starts the same actual previously queued explicit Cook object.")
	expected_next[0].phase="approach";audit["target_sell"]["expected_next"]=expected_next
	check(not bool(after.waits[PEER].waiting) and float(after.waits[PEER].wait_started)<0.0 and after.people[PEER].action_queue==expected_next,"Removed resource loses its stale FIFO; only the observed queued-to-approach transition changes the complete later Cook fields.")
	check(after.people[DONOR].action_queue==before.people[DONOR].action_queue and after.bodies==before.bodies and after.at==before.at,"Target sale preserves Morgan's original Sleep instruction, bodies and clock.")

func _affected_route_move()->void:
	var before:Dictionary=_facts();var protection:Dictionary=app.build_protection_context()
	var structure:Dictionary=app.world.construction.validated_state().state;var generation:int=app.world.lot_navigation.generation
	await press("Build & buy");await press("Ground")
	var plant:Dictionary=first_item("nightstand");app.show_build_object(plant,Vector2(760,350));await press("Move furnishing")
	check(not app.pending_move.is_empty(),"Affected-route control lifts a real unrelated nightstand through Build.")
	var destination:Vector3=Vector3.INF;var candidates:Array=[]
	var queries:int=0;var inspected:int=0;var seen:Dictionary={}
	for base:Vector3 in protection.routes[DONOR].points:
		for offset:Vector3 in [Vector3.ZERO,Vector3(.25,0,0),Vector3(-.25,0,0),Vector3(0,0,.25),Vector3(0,0,-.25)]:
			var point:Vector3=base+offset
			if seen.has(point):continue
			seen[point]=true;inspected+=1
			if inspected>128 or queries>=24:break
			if not app.world.can_place(str(plant.kind),point,app.world.placement_angle):continue
			queries+=1
			var entry:Dictionary={"id":str(plant.id),"kind":str(plant.kind),"x":point.x,"z":point.z,"rotation":app.world.placement_angle}
			var proposed:Array=app.world.serialize_items();proposed.append(entry)
			var error:String=app.build_transactions.furnishing_error(proposed);var certified:Array=[]
			if error.is_empty():
				var candidate:LifeLotNavigation=LifeLotNavigation.new();var rebuilt:Dictionary=candidate.rebuild(structure,app.build_transactions._layout_obstacles(proposed))
				if bool(rebuilt.ok):certified=LifeBuildProtection.unchanged_routes(protection,structure,structure,candidate)
				else:error=str(rebuilt.error)
			candidates.append({"point":point,"transaction_error":error,"certified":certified})
			if error.is_empty() and not certified.has(DONOR):destination=point;break
		if destination.is_finite() or inspected>128 or queries>=24:break
	audit["affected_queries"]={"inspected":inspected,"full_transaction_queries":queries,"candidates":candidates}
	check(destination.is_finite(),"Bounded full transaction and route checks find a legal affected-path placement.")
	if destination.is_finite():app.world.placement_requested.emit(str(plant.kind),destination,app.world.placement_angle);await frames(2)
	check(app.pending_move.is_empty() and app._find_item(str(plant.id)).node.position==destination,"Actual public placement commits an obstacle on the prior floor route.")
	audit["affected_before_return"]={"pending_move":app.pending_move.duplicate(true),"notice":app.notice_label.text if is_instance_valid(app.notice_label) else "","actual_position":app._find_item(str(plant.id)).get("node").position if not app._find_item(str(plant.id)).is_empty() else Vector3.INF}
	await press("Live")
	var after:Dictionary=_facts();var acknowledged:Array=LifeBuildProtection.unchanged_routes(protection,structure,structure,app.world.lot_navigation)
	audit["affected_layout"]={"before":before,"after":after,"candidates":candidates,"navigation_before":generation,"navigation_after":app.world.lot_navigation.generation,"acknowledged":acknowledged,"trace":app.traversal.courtesy.trace.duplicate(true)}
	check(app.world.lot_navigation.generation!=generation and not acknowledged.has(DONOR),"The actual edit fails certification of Morgan's original complete route.")
	check(app.traversal.courtesy.owner(app.traversal).is_empty(),"An uncertified changed route retires v3 without resurrecting old ownership.")
	check(after.waits[PEER]==before.waits[PEER] and after.people[PEER].action_queue==before.people[PEER].action_queue,"The unchanged bookcase retains Rowan's original FIFO and full queue after affected-route release.")
	check(after.people[DONOR].action_queue==before.people[DONOR].action_queue and after.bodies==before.bodies and after.at==before.at and after.funds==before.funds,"Actual affected-route edit leaves the original Sleep instruction, bodies, clock and funds exact.")

func _unchanged_build()->void:
	var before:Dictionary=_facts();audit["before_build"]=before
	var donor_queue:Array=app.household.member_sim(DONOR).action_queue.duplicate(true)
	var peer_queue:Array=app.household.member_sim(PEER).action_queue.duplicate(true)
	var owner_fact:Dictionary=app.traversal.routes[DONOR].courtesy.duplicate(true)
	var donor_signature:Array=app.traversal.courtesy._floor_signature(app.traversal,DONOR)
	for label:String in ["Build & buy","Live"]:
		await press(label)
		var now:Dictionary=_facts();audit[label]=now
		check(app.household.speed==0 and now.at==before.at and now.funds==before.funds and now.bodies==before.bodies,"Paused "+label+" preserves clock, funds and every physical body.")
		check(app.household.member_sim(DONOR).action_queue==donor_queue and app.household.member_sim(PEER).action_queue==peer_queue,"Paused "+label+" preserves both complete queues and paid/progress facts.")
		check(now.waits[PEER]==before.waits[PEER],"Paused "+label+" retains Rowan's exact FIFO reservation.")
		check(app.traversal.courtesy.owner(app.traversal)==DONOR and app.traversal.routes[DONOR].get("courtesy",{})==owner_fact,"Paused "+label+" retains the exact existing v3 hold.")
		check(app.traversal.courtesy._floor_signature(app.traversal,DONOR)==donor_signature and int(app.traversal.routes.get(PEER,{}).get("identity",-1))==218,"Paused "+label+" retains both participant journeys and Morgan's complete future legs.")
	audit["trace"]=app.traversal.courtesy.trace.duplicate(true)

func _run_composed()->void:
	if test_phase=="build":await _unchanged_build()
	else:await _mutations()
