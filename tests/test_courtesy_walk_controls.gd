extends "res://tests/test_courtesy_clear_phases.gd"
const WALK_SLOT="walk_actual_retreat"
const WALKER="housemate_2"
const DONOR="player"

func _run()->void:
	phase_tag="walk_controls";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	audit={"events":[],"controls":[],"scope":"Mutation/schema controls from independent actual0de93f retreat save. Commands use public buttons or production world ground/action signals without native pointer. Explicit eligibility/schema/expiry components are separate from natural recovery; no needs/time/progress injection."}
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	await _load_walk();_schema();_eligibility()
	await _same_request_and_build()
	await _load_walk();await _replace_walk()
	await _load_walk();await _cancel_walk()
	await _load_walk();await _real_action()
	await _load_walk();await _crossfloor_command()
	await _load_walk();_expiry_walk()
	await _finish()

func _load_walk()->void:
	await _load_exact(WALK_SLOT);await press_member("Morgan Vale")
	check(app.household.speed==0 and app.sim.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Actual walk control seed is paused for all clocks.")
	check(app.traversal.courtesy.owner(app.traversal)==DONOR and app.traversal.routes[DONOR].courtesy.beneficiary_kind=="walk" and app.traversal.courtesy._walk_eligible(app.traversal,WALKER),"Exact real retreat restores ordinary walk ownership with empty current queue.")

func _schema()->void:
	var disk:Dictionary=LifeSaveLibrary.read_slot(WALK_SLOT).data
	var old:Dictionary=load("res://tests/fixtures/courtesy_pre_walk_reader.gd").validate(disk.journeys,disk)
	check(not bool(old.ok) and str(old.error).contains("courtesy"),"Previous strict stairV2 reader explicitly rejects unsupported walk kind.")
	audit["old_reader"]=old
	for label:String in ["missing_kind","unknown_kind","action_kind","stair_kind","cleared_intent","different_intent_target","future_stair","legacy_version"]:
		var copy:Dictionary=disk.duplicate(true);var route:Dictionary=copy.journeys.members[WALKER].motion;var fact:Dictionary=copy.journeys.members[DONOR].motion.courtesy
		match label:
			"missing_kind":fact.erase("beneficiary_kind")
			"unknown_kind":fact.beneficiary_kind="automatic_idle"
			"action_kind":fact.beneficiary_kind="action"
			"stair_kind":fact.beneficiary_kind="stair_clear"
			"cleared_intent":route.intent={"kind":"idle"}
			"different_intent_target":route.intent.destination[0]+=.25
			"future_stair":route.stair_id="stairs_2";route.direction=1
			"legacy_version":fact.version=1
		var result:Dictionary=LifeSaveLibrary._validate_household(copy)
		check(not bool(result.ok) and not str(result.get("error","")).is_empty(),"Strict saved walk ownership rejects: "+label)
		audit.controls.append({"schema":label,"result":result})

func _eligibility()->void:
	var t:LifeTraversal=app.traversal;var helper=t.courtesy;var before:Dictionary=_physical_facts();var route:Dictionary=t.routes[WALKER].duplicate(true)
	check(not helper._eligible(t,WALKER) and helper._eligible(t,DONOR),"Actionless walk is a beneficiary only; original activity donor rule is unchanged.")
	var body:Vector3=app.world.actors[WALKER].position
	for field:String in ["waiting_for_target","resume_activity"]:
		var old:Variant=app.get(field);app.set(field,true)
		check(not helper._walk_eligible(t,WALKER),"Bound live "+field+" owner is excluded from ordinary walk courtesy.")
		app.set(field,old)
	var old_walk:bool=app.walk_only;app.walk_only=false
	check(not helper._walk_eligible(t,WALKER),"Clearing live walk intent invalidates eligibility even before its cache is stored.")
	app.walk_only=old_walk
	t.routes[WALKER].legs.append({"kind":"stair"})
	check(not helper._walk_eligible(t,WALKER),"An ordinary first floor leg does not make a future stair journey eligible.")
	t.routes[WALKER]=route
	check(_physical_facts()==before and app.world.actors[WALKER].position==body,"Eligibility components restore exact typed bodies/queues/food/journeys/clock without movement.")

func _same_request_and_build()->void:
	var t:LifeTraversal=app.traversal;app.meal_flow.sync_world(true)
	var before:Dictionary=_physical_facts();var route:Dictionary=t.routes[WALKER].duplicate(true);var donor:Dictionary=t.routes[DONOR].courtesy.duplicate(true)
	var destination:Vector3=route.destination
	app.world.ground_clicked.emit(destination)
	check(t.courtesy.owner(t)==DONOR and int(t.routes[WALKER].identity)==int(route.identity) and t.routes[WALKER].destination==destination and t.routes[DONOR].courtesy==donor,"Same-destination real ground request preserves original walk identity and donor courtesy.")
	check(_physical_facts()==before,"Harmless same-intent request leaves exact paused physical/queue/food/journey facts unchanged.")
	await press("Build & buy");var entered:Dictionary=_physical_facts()
	check(app.mode=="build" and _ordinary_refresh_equal(before,entered,2),"Public Build entry keeps all facts exactly except two verified ordinary nonparticipant route-ID renewals.")
	await press("Live");var returned:Dictionary=_physical_facts()
	check(app.mode=="live" and _ordinary_refresh_equal(entered,returned,2),"Public Live return retains exact donor/walk and all remaining facts, with only two ordinary nonparticipant route-ID renewals.")
	var generation:int=app.world.lot_navigation.generation
	app.world.rebuild_navigation();var response:Dictionary=t.request(WALKER,destination)
	check(bool(response.ok) and app.world.lot_navigation.generation>generation and t.courtesy.generation_current(t) and _ordinary_refresh_equal(returned,_physical_facts(),0),"Same walk navigation rebuild rederives priority without changing identity/destination/queue or deadline.")
	audit.controls.append({"same_request":{"before":before,"entered":entered,"returned":returned,"after":_physical_facts(),"request":response}})

func _find_new_destination(level:int)->Vector3:
	var from:Vector3=app.world.actors[WALKER].position;var old:Vector3=app.traversal.routes[WALKER].destination
	var points:Array=[Vector3(4,.16,-3.5),Vector3(4.5,.16,-3.5),Vector3(3.5,.16,-3),Vector3(3,.16,-3)] if level==0 else [Vector3(-3.5,3.16,2.5),Vector3(-4,3.16,2.5),Vector3(2,3.16,2.5)]
	for candidate:Vector3 in points:
		if candidate==old or not app.world.lot_navigation.point_clear(level,candidate):continue
		var path:Dictionary=app.world.route_to(from,candidate)
		if bool(path.ok):return candidate
	return Vector3.INF

func _replace_walk()->void:
	var t:LifeTraversal=app.traversal;var original:Dictionary=t.routes[WALKER].duplicate(true);var target:Vector3=_find_new_destination(0)
	var body:Vector3=app.world.actors[WALKER].position;var donor_queue:Array=app.household.member_sim(DONOR).action_queue.duplicate(true)
	check(target.is_finite(),"Actual layout has a distinct supported reachable ground-walk destination.")
	if not target.is_finite():return
	var cached:Vector3=app.motion_states[WALKER].destination
	app.world.ground_clicked.emit(target)
	check(t.courtesy.owner(t).is_empty() and t.routes.has(WALKER) and int(t.routes[WALKER].identity)!=int(original.identity) and t.routes[WALKER].destination==target,"Real changed ground request retires previous walk ownership and creates the requested destination normally.")
	check(app.motion_states[WALKER].destination==cached and app.walk_destination==target,"Replacement observes live bound intent before the older motion cache is stored.")
	check(app.world.actors[WALKER].position==body and app.sim.action_queue.is_empty() and app.household.member_sim(DONOR).action_queue==donor_queue,"Changed walk request teleports nobody, invents no action and preserves donor's complete instruction queue.")
	audit.controls.append({"replace":{"target":target,"old":original,"after":_record_clear()}})

func _cancel_walk()->void:
	var t:LifeTraversal=app.traversal;var body:Vector3=app.world.actors[WALKER].position;var queue:Array=app.household.member_sim(DONOR).action_queue.duplicate(true)
	await press("Cancel action")
	check(not t.active(WALKER) and t.courtesy.owner(t).is_empty() and not app.walk_only,"Public cancellation clears the actual walk and releases only courtesy.")
	check(app.world.actors[WALKER].position==body and app.household.member_sim(DONOR).action_queue==queue,"Canceled walk leaves current body and donor queue unchanged.")
	audit.controls.append({"cancel":_record_clear()})

func _real_action()->void:
	var t:LifeTraversal=app.traversal;var original:Dictionary=t.routes[WALKER].duplicate(true);var body:Vector3=app.world.actors[WALKER].position;var donor_queue:Array=app.household.member_sim(DONOR).action_queue.duplicate(true)
	var shelf:Dictionary=app._find_item("item_14")
	check(not shelf.is_empty(),"The genuine household has its actual bookshelf for a supported new instruction.")
	app.queue_interaction(shelf,"read")
	check(not app.sim.action_queue.is_empty() and str(app.sim.get_current_action().id)=="read" and not bool(app.sim.get_current_action().paid) and float(app.sim.get_current_action().elapsed)==0,"Real queued read instruction replaces empty walking intent without early payment/progress.")
	check(t.courtesy.owner(t).is_empty() and (not t.routes.has(WALKER) or int(t.routes[WALKER].identity)!=int(original.identity)),"Adding a genuine action retires the old walk beneficiary ownership.")
	check(app.world.actors[WALKER].position==body and app.household.member_sim(DONOR).action_queue==donor_queue,"New action admission preserves physical body and donor's full queue.")
	audit.controls.append({"new_action":_record_clear()})

func _crossfloor_command()->void:
	var t:LifeTraversal=app.traversal;var target:Vector3=_find_new_destination(1);var at:Vector3=app.world.actors[WALKER].position
	check(target.is_finite(),"Actual paid two-storey home supplies a supported new upper-floor walk goal.")
	if not target.is_finite():return
	app.world.ground_clicked.emit(target)
	check(t.courtesy.owner(t).is_empty() and t.routes.has(WALKER) and t.routes[WALKER].legs.any(func(leg:Dictionary):return leg.kind=="stair") and not t.courtesy._walk_eligible(t,WALKER),"Real new floor-transfer walk is excluded from ordinary walk courtesy.")
	check(app.world.actors[WALKER].position==at and app.sim.action_queue.is_empty(),"New floor-transfer command preserves current body and empty action queue.")
	audit.controls.append({"crossfloor":_record_clear()})

func _expiry_walk()->void:
	var t:LifeTraversal=app.traversal;var before:Dictionary=_physical_facts();var walker:Dictionary=t.routes[WALKER].duplicate(true)
	t.routes[DONOR].courtesy.expires_at=_now()
	check(app.save_game("","Component — expired walk courtesy"),"Explicit expiry is reconciled before read-only named save snapshot.")
	var after:Dictionary=_physical_facts()
	check(t.courtesy.owner(t).is_empty() and t.routes[WALKER]==walker,"Expiry releases donor without rewriting or retiring the original beneficiary walk.")
	check(before.people==after.people and before.clock==after.clock and before.funds==after.funds,"Expiry does not advance or replace body/queue/needs/clock/funds.")
	check(t.courtesy.trace.any(func(r:Dictionary):return r.get("released","")==DONOR and r.get("reason","")=="expired"),"Walk courtesy safety expiry remains distinct from actual destination completion.")
	audit.controls.append({"expiry":{"before":before,"after":after}})

func _ordinary_refresh_equal(before:Dictionary,after:Dictionary,allocations:int)->bool:
	var expected:Dictionary=before.duplicate(true);var actual:Dictionary=after.duplicate(true)
	var old_next:int=int(before.journeys.next_identity);var new_next:int=int(after.journeys.next_identity)
	if new_next-old_next!=allocations:return false
	var changed:int=0;var seen:Array=[]
	for id:String in after.journeys.members:
		var old:Dictionary=before.journeys.members[id].motion;var now:Dictionary=after.journeys.members[id].motion
		if now.is_empty():
			if not old.is_empty():return false
			continue
		if int(now.identity) in seen:return false
		seen.append(int(now.identity))
		if int(now.identity)>=new_next:return false
		if old.is_empty():return false
		if int(now.identity)==int(old.identity):continue
		if id not in ["housemate_1","housemate_3"] or int(now.identity)<old_next:return false
		for motion:Dictionary in [old,now]:
			if motion.phase!="route" or motion.intent.kind!="action" or not str(motion.stair_id).is_empty() or bool(motion.safety) or not motion.wait.is_empty() or not motion.clear.is_empty() or int(motion.ticket)!=0 or not str(motion.custody).is_empty() or motion.has("courtesy"):return false
		actual.journeys.members[id].motion.identity=old.identity;changed+=1
	actual.journeys.next_identity=before.journeys.next_identity
	return changed==allocations and actual==expected
