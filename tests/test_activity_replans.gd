extends "res://tests/test_activity_flow.gd"
class CountedTraversal extends LifeTraversal:
	var queries:Array=[]
	func _floor_route(from:Vector3,to:Vector3,id:String="")->PackedVector3Array:
		var result:PackedVector3Array=super._floor_route(from,to,id)
		queries.append({"from":from,"to":to,"id":id,"points":result})
		return result
var original_traversal:LifeTraversal
var original_transforms:Dictionary={}
var original_queue:Array=[]
var original_motions:Dictionary={}
var original_bound:Dictionary={}
func _run()->void:
	await _start_activity("components")
	if await _load_busy(EASEL_SLOT):
		if test_phase=="components":await _components()
		elif test_phase=="live":await _live_controls()
		else:check(false,"Unknown control phase.")
	await _finish()
func _save_component_inputs()->void:
	original_traversal=app.traversal
	for id:String in app.world.actors:original_transforms[id]={"position":app.world.actors[id].position,"rotation":app.world.actors[id].rotation,"visible":app.world.actors[id].visible}
	original_queue=app.sim.action_queue.duplicate()
	original_motions=app.motion_states.duplicate()
	original_bound={"walk":app.walk_only,"waiting":app.waiting_for_target,"started":app.wait_started,"resume":app.resume_activity}
func _restore_component_inputs()->void:
	app.traversal=original_traversal
	for id:String in original_transforms:app.world.actors[id].position=original_transforms[id].position;app.world.actors[id].rotation=original_transforms[id].rotation;app.world.actors[id].visible=original_transforms[id].visible
	app.sim.action_queue.assign(original_queue)
	app.motion_states.assign(original_motions)
	app.walk_only=original_bound.walk;app.waiting_for_target=original_bound.waiting;app.wait_started=original_bound.started;app.resume_activity=original_bound.resume
func _component_route()->CountedTraversal:
	_restore_component_inputs()
	var t:=CountedTraversal.new(app);t.routes=original_traversal.routes.duplicate(true);t.stairs=original_traversal.stairs.duplicate(true);t.next_identity=original_traversal.next_identity;t.next_ticket=original_traversal.next_ticket;app.traversal=t
	var route:Dictionary=t.routes.housemate_1
	if not bool(route.prepared):t._prepare("housemate_1",route)
	while int(route.point)<route.points.size() and route.points[int(route.point)]==app.player.position:route.point+=1
	return t
func _components()->void:
	await _select_busy("housemate_1");_save_component_inputs();var before:Dictionary=_busy_record();var before_action:Dictionary=app.sim.get_current_action().duplicate(true)
	audit.scope="Declared movement-component controls temporarily change only stated obstruction/path inputs and restore original objects/transforms. Counter delegates every floor query to actual production navigation. No component is a natural gameplay/save fixture."
	var t:CountedTraversal=_component_route();var route:Dictionary=t.routes.housemate_1;var at:Vector3=app.player.position;var points:PackedVector3Array=route.points;var point:int=route.point
	var first:Dictionary=t._walk("housemate_1",route,.05)
	check(bool(first.blocked) and not first.moved and app.player.position==at and t.queries.is_empty(),"Actual blocked first step defers replacement without moving or issuing a floor query.")
	check(route.points==points and route.point==point and route.replan_observation.age==.05,"The first observation retains its exact existing polyline/cursor and actual blocked time.")
	# Remove only the observed body obstruction, then move through the unchanged
	# real supported step; no route replacement or expired delay is required.
	app.world.actors.housemate_2.visible=false
	var cleared:Dictionary=t._walk("housemate_1",route,.05)
	check(bool(cleared.moved) and app.player.position!=at and t.queries.is_empty() and not route.has("replan_observation"),"An original step clearing before the threshold moves immediately and clears its observation.")
	check(app.sim.get_current_action()==before_action,"Immediate movement does not begin/pay/change the activity.")
	audit.cleared={"before":at,"after":app.player.position,"result":cleared}
	# Same actual occupied endpoint, no second observed donor: all attempted
	# fallback queries are real and empty. They cannot restart the hold forever.
	t=_component_route();route=t.routes.housemate_1;at=app.player.position;points=route.points;point=route.point
	for i:int in range(5):t._walk("housemate_1",route,.05);t.courtesy.consider(t)
	check(t.queries.is_empty() and route.replan_observation.age==.25 and route.points==points and route.point==point,"Threshold-reaching collision leaves the original path for the end-of-household consideration opportunity.")
	t._walk("housemate_1",route,.05);var first_queries:int=t.queries.size();t._walk("housemate_1",route,.05);t._walk("housemate_1",route,.05)
	check(first_queries==1 and t.queries.size()==3 and t.queries.all(func(q:Dictionary)->bool:return q.points.is_empty()),"Single/no-donor empty-route fallback freshly queries every later unchanged blocked call instead of restarting its hold.")
	check(app.player.position==at and route.points==points and app.sim.get_current_action()==before_action and t.courtesy.owner(t).is_empty(),"No-anchor fallback preserves physical body, original path/action and absence of invented courtesy ownership.")
	audit.empty_fallback=t.queries.duplicate(true)
	# Partial physical progress reaches a close supported waypoint, then the
	# next segment hits the real Morgan body in this same call.
	t=_component_route();route=t.routes.housemate_1;at=app.player.position
	var goal:Vector3=route.points[-1];var next_index:int=0
	while next_index<route.points.size() and route.points[next_index]==at:next_index+=1
	var toward:Vector3=route.points[next_index];var middle:Vector3=at.move_toward(toward,.016)
	check(t._step_clear("housemate_1",at,middle),"The partial-time fixture's first short physical step is genuinely clear.")
	route.points=PackedVector3Array([at,middle,toward,goal]);route.point=0
	var expected:float=.05-at.distance_to(middle)/LifeTraversal.WALK_SPEED;var partial:Dictionary=t._walk("housemate_1",route,.05)
	check(bool(partial.moved) and bool(partial.blocked) and app.player.position==middle and route.replan_observation.age==expected and expected>0 and expected<.05,"Observation age counts exactly the remaining blocked time after actual partial movement.")
	audit.partial={"from":at,"middle":middle,"expected_remaining":expected,"actual":route.get("replan_observation",{}),"result":partial}
	# New requests and actual cancellation retire derived retry state while
	# preserving the caller's unchanged unpaid action and actual body.
	t=_component_route();route=t.routes.housemate_1;t._walk("housemate_1",route,.05);var old_id:int=route.identity
	var requested:Dictionary=t.request("housemate_1",route.destination);var replacement:Dictionary=t.routes.housemate_1
	check(bool(requested.ok) and int(replacement.identity)>old_id and not replacement.has("replan_observation") and not t.courtesy.blocked.has("housemate_1"),"Ordinary same-goal new route identity clears prior observation and blocked record.")
	t.cancel("housemate_1");var canceled_at:Vector3=app.player.position;var stopped:Dictionary=t.advance("housemate_1",.05,1)
	check(not t.routes.has("housemate_1") and not stopped.moving and app.player.position==canceled_at and app.sim.get_current_action()==before_action,"Actual route cancellation cannot continue the old observation or move/pay its activity.")
	# Observe real collision/fallback cadence at each supported simulation speed.
	audit.cadence=[]
	for speed:int in [1,3,8]:
		t=_component_route();route=t.routes.housemate_1;at=app.player.position;var elapsed:float=0;var calls_used:int=0
		while t.queries.is_empty() and calls_used<12:
			t.advance("housemate_1",.05,speed);elapsed+=.05*speed;calls_used+=1;t.courtesy.consider(t)
		check(t.queries.size()==1 and elapsed>=.25 and elapsed<=.25+.1*speed and app.player.position==at,"Speed%d reaches a finite real-query fallback with cadence-bounded threshold overshoot."%speed)
		audit.cadence.append({"speed":speed,"calls":calls_used,"movement_seconds":elapsed,"observation":route.get("replan_observation",{}),"queries":t.queries.duplicate(true)})
	_valid_detour()
	await _exclusion_controls()
	_restore_component_inputs();audit.component_before=before;audit.component_after=_busy_record();check(before==_busy_record() and app.sim.get_current_action()==before_action,"All movement components restore exact original household, body, food, needs, waits and authoritative journeys.")
func _valid_detour()->void:
	var found:bool=false;audit.detour_cases=[]
	for start:Vector3 in [Vector3(-1.25,.16,2.5),Vector3(-1.5,.16,2.5),Vector3(-2,.16,2.5),Vector3(-.5,.16,2.5),Vector3(.5,.16,2.5),Vector3(1,.16,2.5)]:
		var t:CountedTraversal=_component_route()
		if not t._free("housemate_1",start):continue
		app.player.position=start
		var action:Dictionary=app.sim._actions.read.duplicate(true)
		action.merge({"target_id":"item_14","target_position":Vector3(0,.16,-2),"phase":"approach","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":true})
		app.sim.action_queue[0]=action
		var built:Dictionary=t.request("housemate_1",action.target_position)
		if not bool(built.ok):continue
		var route:Dictionary=t.routes.housemate_1;t._prepare("housemate_1",route)
		for i:int in range(100):
			t._walk("housemate_1",route,.05)
			if route.has("replan_observation") or int(route.point)>=route.points.size():break
		if not route.has("replan_observation"):audit.detour_cases.append({"start":start,"observed":false});continue
		var at:Vector3=app.player.position;var direct:PackedVector3Array=t._floor_route(at,action.target_position,"housemate_1")
		audit.detour_cases.append({"start":start,"at":at,"observed":true,"complete_alternative":direct})
		if direct.is_empty():continue
		found=true;t.queries.clear();var original_points:PackedVector3Array=route.points;var original_action:Dictionary=action.duplicate(true)
		for i:int in range(10):
			t._walk("housemate_1",route,.05)
			if not t.queries.is_empty():break
		check(t.queries.size()==1 and not t.queries[0].points.is_empty() and route.points!=original_points and app.player.position==at,"A single observed caller falls back to a fresh real valid detour after its finite observation.")
		var moved:Dictionary=t._walk("housemate_1",route,.05)
		check(bool(moved.moved) and app.player.position!=at and action==original_action and not route.has("replan_observation"),"The re-queried detour actually moves on supported floor while retaining the unpaid instruction.")
		break
	check(found,"Bounded declared component placements supply an actual blocked path with a nonempty safe alternative.")
func _exclusion_controls()->void:
	var t:CountedTraversal=_component_route();var route:Dictionary=t.routes.housemate_1;var action:Dictionary=app.sim.get_current_action();var copy:Dictionary=action.duplicate(true)
	check(t._can_observe_replan("housemate_1",route),"Actual original floor approach qualifies for the narrow observation.")
	for phase:String in ["to_wait","waiting","entry","transit","clear"]:
		route.phase=phase;check(not t._can_observe_replan("housemate_1",route),"Stair/wait phase "+phase+" is excluded.")
	route.phase="route";route.ticket=1;check(not t._can_observe_replan("housemate_1",route),"An owned stair ticket is excluded.");route.ticket=0
	route.custody="component_custody";check(not t._can_observe_replan("housemate_1",route),"Explicit protected custody is excluded.");route.erase("custody")
	route.safety=true;check(not t._can_observe_replan("housemate_1",route),"Safety movement is excluded.");route.safety=false
	for key:String in ["cooperation_id","cooperation_role"]:
		action[key]="component";check(not t._can_observe_replan("housemate_1",route),"Cooperative "+key+" is excluded.");action.erase(key)
	app.waiting_for_target=true;check(not t._can_observe_replan("housemate_1",route),"Live bound resource-wait state is excluded even before cache storage.");app.waiting_for_target=false
	app.wait_started=_now();check(not t._can_observe_replan("housemate_1",route),"Live bound FIFO age is excluded.");app.wait_started=-1
	app.resume_activity=true;check(not t._can_observe_replan("housemate_1",route),"Live active-resume ownership is excluded.");app.resume_activity=false
	app.walk_only=true;check(not t._can_observe_replan("housemate_1",route),"Ordinary ground-walk intent is not widened into activity observation.");app.walk_only=false
	for role:String in ["donor","beneficiary"]:
		if role=="donor":route.courtesy={"beneficiary_id":"housemate_2"}
		else:t.routes.housemate_2={"courtesy":{"beneficiary_id":"housemate_1"}}
		check(not t._can_observe_replan("housemate_1",route),"Existing courtesy "+role+" keeps its own movement policy.")
		if role=="donor":route.erase("courtesy")
		else:t.routes.erase("housemate_2")
	# Real ledger-owned batch exercises carried_by without inventing a fake ID;
	# creation is a declared component input and ledger state is restored exactly.
	var food:Dictionary=app.household.meals.get_state();var batch:Dictionary=app.household.meals.create_batch("garden_skillet","housemate_1",1,app.current_venue,_now())
	check(not batch.is_empty() and not t._can_observe_replan("housemate_1",route),"A real food-ledger owner is excluded from retry observation.")
	app.household.meals.restore(food);check(app.household.meals.get_state()==food,"Declared food component restores complete original ledger exactly.")
	check(action==copy,"Exclusion controls leave the original full action unchanged.")
func _speeds()->Array:
	var result:Array=[app.household.speed]
	for member:Dictionary in app.household.members:result.append(member.sim.speed)
	return result
func _live_controls()->void:
	# Normal speed keeps Ellis inside the occupied-easel queue for this 107-call
	# prefix. Danger interrupts no longer abandon that paint approach for an
	# unrelated Read (e6fcfc3); the waiter stands at the FIFO point with the
	# approach route retired, so Pause/Build must freeze wait facts rather than
	# index a missing traversal route.
	await press("▶")
	for i:int in range(107):_exclude_inputs();app._process(.05);await frames(1)
	var sim:LifeSim=app.household.member_sim("housemate_1")
	var action:Dictionary=sim.get_current_action()
	var motion:Dictionary=app.motion_states.housemate_1
	check(str(action.id)=="paint" and str(action.phase)=="approach" and not bool(action.paid) and float(action.elapsed)==0.0 and bool(action.autonomous),"Unchanged public continuation keeps Ellis on the unpaid autonomous paint approach.")
	check(bool(motion.waiting) and float(motion.wait_started)>=0.0 and Vector3(motion.wait_destination).is_finite() and not app.traversal.routes.has("housemate_1"),"Ellis remains in the occupied-easel FIFO with the approach route retired at the wait point.")
	await press("Ⅱ");_exclude_inputs();app._process(.05);await frames(1)
	var before:Dictionary=_busy_record();var all_routes:Dictionary=app.traversal.routes.duplicate(true)
	for i:int in range(10):_exclude_inputs();app._process(.05);await frames(1)
	check(_speeds()==[0,0,0,0,0] and before==_busy_record() and all_routes==app.traversal.routes,"Ten actual paused calls freeze every captured fact including FIFO wait ownership.")
	await press("Build & buy");_exclude_inputs();var building:Dictionary=_busy_record()
	check(app.mode=="build" and not app.traversal.routes.has("housemate_1"),"Actual Build entry leaves the waiting paint approach without inventing a traversal route.")
	check(before.people==building.people and before.food==building.food and before.at==building.at and before.funds==building.funds and before.waits==building.waits,"Unchanged Build replan preserves bodies, full activities, needs, custody, clock, funds and FIFO facts.")
	var build_routes:Dictionary=app.traversal.routes.duplicate(true)
	for i:int in range(10):_exclude_inputs();app._process(.05);await frames(1)
	check(building==_busy_record() and build_routes==app.traversal.routes,"Ordinary Build calls neither invent routes nor advance existing physical/queue state.")
	await press("Live");_exclude_inputs();check(app.mode=="live" and _speeds()==[0,0,0,0,0],"Return Live restores the actual paused speed.")
	await press("▶");_exclude_inputs();app._process(.05);await frames(1)
	var resumed:Dictionary=app.motion_states.housemate_1
	var resumed_action:Dictionary=sim.get_current_action()
	check(str(resumed_action.id)=="paint" and str(resumed_action.phase)=="approach" and bool(resumed.waiting) and float(resumed.wait_started)==float(motion.wait_started) and not app.traversal.routes.has("housemate_1"),"Ordinary resumed play keeps the same unpaid paint FIFO wait without fabricating a route.")
	audit.before_pause=before;audit.build=building;audit.final=_busy_record()
