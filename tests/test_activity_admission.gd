extends "res://tests/test_activity_flow.gd"
var calls:Array=[]
func _run()->void:
	await _start_activity("checks")
	audit.scope="Declared component changes, restored before simulation. Natural evidence is separate. No timing, progress or physical completion inferred from these predicates."
	if test_phase!="checks":check(false,"Unknown admission control phase.")
	elif await _load_busy(EASEL_SLOT):
		await _admission_controls()
		await _availability_controls()
		_policy_controls()
	await _finish()
func _admission_controls()->void:
	await _select_busy("housemate_1")
	var action:Dictionary=app.sim.get_current_action();var owner:LifeSim=app.household.member_sim("housemate_2");var other:Dictionary=owner.get_current_action()
	var original:Dictionary=other.duplicate(true);var body:Vector3=app.player.position;var peer:LifeActor=app.world.actors.housemate_2;var peer_body:Vector3=peer.position
	var before:Dictionary=_busy_record();var routes:Dictionary=app.traversal.routes.duplicate(true);var route_objects:Dictionary=app.traversal.routes.duplicate()
	check(not app.world.lot_navigation.segment_clear(0,body,action.target_position) and app._near_active_resource_owner(action,0),"Actual paid active owner has valid curved access despite the blocked direct segment.")
	other.paid=false;check(not app._near_active_resource_owner(action,0),"Unpaid peer cannot stand in for an active owner.");other.paid=original.paid
	other.phase="approach";check(not app._near_active_resource_owner(action,0),"Another approaching action is not an active-owner witness.");other.phase=original.phase
	other.cooperation_id="component_owner";check(not app._near_active_resource_owner(action,0),"Cooperative active ownership is excluded.");other.erase("cooperation_id")
	peer.position+=Vector3(0,0,.05);check(not app._near_active_resource_owner(action,0),"Paid active peer at a different physical anchor cannot witness the requested anchor.");peer.position=peer_body
	other.target_id="unrelated_component_resource";check(not app._near_active_resource_owner(action,0),"An unrelated action sharing only standing-cell ownership is excluded.");other.target_id=original.target_id
	check(not app._near_active_resource_owner(action,1),"Other-floor query cannot claim a Ground active owner.")
	for role:String in ["donor","beneficiary"]:
		var id:String="housemate_2" if role=="donor" else "player"
		app.traversal.routes[id]={"phase":"route","safety":false,"courtesy":{"beneficiary_id":"player" if role=="donor" else "housemate_2"}}
		check(not app._near_active_resource_owner(action,0),"An active courtesy "+role+" cannot witness furnishing admission.")
		if route_objects.has(id):app.traversal.routes[id]=route_objects[id]
		else:app.traversal.routes.erase(id)
	var third:Dictionary=app.motion_states.player;var original_third:Dictionary=third.duplicate(true)
	third.waiting=true;third.wait_started=_now()-1;third.wait_destination=body
	check(not app._near_active_resource_owner(action,0),"Foreign ordinary waiting destination at the caller body remains reserved.");third.assign(original_third)
	app.traversal.routes.player={"phase":"waiting","wait":body,"safety":false}
	check(not app._near_active_resource_owner(action,0),"An existing stair waiting reservation remains in the route witness.")
	if route_objects.has("player"):app.traversal.routes.player=route_objects.player
	else:app.traversal.routes.erase("player")
	var long_found:bool=false;audit.long_candidates=[]
	for z:float in [1.8,1.85,1.9,1.95,1.965]:
		app.player.position=Vector3(body.x,body.y,z)
		var occupied:Array[Vector3]=app.traversal._occupied("housemate_1");occupied.erase(peer_body)
		var route:Dictionary=app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(0,app.player.position),LifeLotNavigation.floor_location(0,peer_body),occupied,LifeTraversal.ROUTE_CLEARANCE)
		audit.long_candidates.append({"body":app.player.position,"direct":app.player.position.distance_to(peer_body),"route":route})
		if app.player.position.distance_to(peer_body)<=1.0 and bool(route.ok) and float(route.distance)>1.0:
			check(not app._near_active_resource_owner(action,0),"A supported curved route longer than1m is refused even with a Euclidean-near active owner.");long_found=true;break
	check(long_found,"Current layout supplies the bounded geodesic-long control.");app.player.position=body
	audit.admission_before=before;audit.admission_after=_busy_record();audit.routes_before=routes;audit.routes_after=app.traversal.routes.duplicate(true);audit.action_before=original;audit.action_after=other.duplicate(true)
	check(before==_busy_record() and app.traversal.routes==routes and other==original,"All admission controls restore exact bodies, full queues, needs, food, routes and wait facts.")
func _binding()->Dictionary:
	return {"id":app.bound_member_id,"sim":app.sim,"player":app.player,"path":app.path,"index":app.path_index,"pending":app.pending_action.duplicate(true),"generation":app.route_generation,"destination":app.walk_destination,"walk":app.walk_only,"waiting":app.waiting_for_target,"started":app.wait_started,"review":app.wait_review,"wait_destination":app.wait_destination,"resume":app.resume_activity,"cache":app.motion_states.duplicate(true)}
func _availability_controls()->void:
	await _select_busy("player")
	var id:String="housemate_1";var requester:LifeSim=app.household.member_sim(id);var action:Dictionary=requester.get_current_action();var owner:LifeSim=app.household.member_sim("housemate_2");var other:Dictionary=owner.get_current_action()
	var queue:Array=owner.action_queue.duplicate();var original:Dictionary=other.duplicate(true);var before:Dictionary=_busy_record();var bound:Dictionary=_binding()
	for member:Dictionary in app.household.members:
		var provider:Callable=member.sim.autonomy_activity_available
		check(provider.is_valid() and provider.get_object()==app and provider.get_bound_arguments()==[str(member.id)],"Adopted provider belongs to live controller and exact member: "+str(member.id))
	check(not bool(requester.autonomy_activity_available.call(action)),"Unbound requester sees the actual active owner with a different member bound.")
	owner.action_queue.clear();check(bool(requester.autonomy_activity_available.call(action)),"Availability responds immediately when actual resource ownership is removed.");owner.action_queue.assign(queue)
	var own_motion:Dictionary=app.motion_states[id];var peer_motion:Dictionary=app.motion_states.housemate_2;var own_before:Dictionary=own_motion.duplicate(true);var peer_before:Dictionary=peer_motion.duplicate(true)
	other.phase="approach";peer_motion.waiting=true;peer_motion.wait_started=_now()-10;peer_motion.resume_active=false
	own_motion.waiting=true;own_motion.wait_started=_now()-20;own_motion.resume_active=false
	check(bool(requester.autonomy_activity_available.call(action)),"Unbound caller retains its earlier FIFO origin rather than borrowing bound Rowan's timer.")
	own_motion.wait_started=_now()-5;check(not bool(requester.autonomy_activity_available.call(action)),"Unbound later caller cannot jump an earlier arrived waiter.")
	own_motion.wait_started=peer_motion.wait_started;check(bool(requester.autonomy_activity_available.call(action)),"Equal-time FIFO retains stable household-ID ordering.")
	own_motion.wait_started=-1;own_motion.resume_active=true;check(bool(requester.autonomy_activity_available.call(action)),"Unbound saved active owner may resume ahead of arrived waiters.")
	other.phase="active";check(not bool(requester.autonomy_activity_available.call(action)),"Resume ownership cannot override a different actual active owner.")
	other.assign(original);own_motion.assign(own_before);peer_motion.assign(peer_before)
	check(bound==_binding() and before==_busy_record(),"Pure member queries and restored controls leave complete bound fields/cache and physical/simulation facts unchanged.")
func _make_policy()->LifeSim:
	var person:=LifeSim.new();person.new_household({"name":"Declared policy component","age_stage":"adult","traits":["Creative"]});person.day=2;person.minutes=1100
	person.register_targets(app.world.simulation_targets())
	for need:String in LifeSim.NEED_NAMES:person.needs[need]=90.0
	var shelf:Dictionary=app._find_item("item_14")
	check(person.queue_action("read",str(shelf.id),app.world.approach(shelf)),"Component builds a normal unpaid reading approach through queue_action.")
	person.get_current_action().autonomous=true
	return person
func _record_availability(action:Dictionary)->bool:
	calls.append(action.duplicate(true));return app._activity_available_for_member(action,"housemate_1")
func _deny_record(action:Dictionary)->bool:calls.append(action.duplicate(true));return false
func _policy_controls()->void:
	var before:Dictionary=_busy_record();var binding:Dictionary=_binding()
	var person:LifeSim=_make_policy();person.needs.fun=4.0;person.needs.hygiene=5.0
	var current:Dictionary=person.get_current_action();var exact:Dictionary=current.duplicate(true);var next:Dictionary=person._autonomous_choice()
	check(next.id=="paint" and next.target_id=="item_15","Actual target metadata reproduces the occupied preferred-paint alternative.")
	person.autonomy_activity_available=_record_availability;calls.clear();person._reconsider_active_autonomy()
	check(is_same(current,person.get_current_action()) and current==exact and calls.size()==1 and calls[0]=={"id":next.id,"target_id":next.target_id,"target_position":next.position},"Unavailable automatic replacement preserves exact current identity and sends correct candidate target shape.")
	var owner:LifeSim=app.household.member_sim("housemate_2");var original_queue:Array=owner.action_queue.duplicate();owner.action_queue.clear();person._reconsider_active_autonomy()
	check(person.get_current_action().id=="paint" and not is_same(current,person.get_current_action()) and not person.get_current_action().paid,"The same automatic choice may interrupt when live ownership becomes free.");owner.action_queue.assign(original_queue);person.free()
	person=_make_policy();person.needs.fun=4;person.needs.hygiene=5;person._reconsider_active_autonomy();check(person.get_current_action().id=="paint","Standalone LifeSim without a provider preserves its prior replacement behavior.");person.free()
	person=_make_policy();person.needs.hunger=3;person.autonomy_activity_available=_record_availability;calls.clear();person._reconsider_active_autonomy()
	# first_meal keeps cook ahead of snack while that want is open (d11fa58); either
	# recovery is a genuine hunger interrupt of the reading approach.
	var hunger_id:String=str(person.get_current_action().get("id",""))
	check(hunger_id in ["snack","cook"] and calls.size()==1 and not person.get_current_action().paid,"A genuinely available urgent hunger recovery still interrupts the ordinary reading approach.");person.free()
	person=_make_policy();person.minutes=600;person.autonomy_activity_available=_record_availability;calls.clear();person._reconsider_active_autonomy()
	check(person.get_current_action().id=="career_day" and calls.size()==1 and not person.get_current_action().paid,"A due available work departure still interrupts an optional approach.");person.free()
	person=_make_policy();person.autonomy_activity_available=_deny_record;calls.clear();person.needs.hunger=3
	var later:Dictionary=person._actions.shower.duplicate(true);later.merge({"target_id":"item_22","target_position":Vector3(5,.16,-3),"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":false});person.action_queue.append(later)
	var prior:Array=person.action_queue.duplicate(true);person._reconsider_active_autonomy()
	check(person.action_queue==prior and calls.is_empty(),"A later explicit instruction retains original queue precedence without querying replacement admission.");person.free()
	person=LifeSim.new();person.register_targets(app.world.simulation_targets());person.autonomy_activity_available=_deny_record;calls.clear();person.needs.hunger=3;person._choose_autonomous_action()
	check(not person.action_queue.is_empty() and calls.is_empty(),"Initial ordinary autonomous queue choice remains outside the replacement-only provider.");person.free()
	person=LifeSim.new();person.register_targets(app.world.simulation_targets());person.autonomy_activity_available=_deny_record;calls.clear()
	check(person.queue_action("paint","item_15",Vector3(-.5,.16,1)) and calls.is_empty(),"Explicit player queueing remains outside the automatic replacement provider.");person.free()
	check(before==_busy_record() and binding==_binding(),"Standalone policy components never alter actual household, controller binding, motion cache or custody.")
