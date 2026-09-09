extends "res://tests/test_courtesy_clear_phases.gd"
var hold_slot:String=""

func _run()->void:
	phase_tag="clear_controls";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	audit={"events":[],"rejections":[],"scope":"Declared controller and geometry components using the actual held-clear save. Temporary collision/query facts are restored before simulation; corruption and expiry controls are explicitly synthetic. No claim these are natural player outcomes."}
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	var entries:Array=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("phase_slots.json")))
	hold_slot=str(entries.filter(func(e:Dictionary):return e.phase=="hold")[0].slot)
	await _load_exact(LANDING_SLOT);_detour_control()
	await _load_exact(hold_slot);_reservations_and_eligibility();_navigation_control();_integrity()
	await _load_exact(hold_slot);await _donor_cancel()
	await _load_exact(hold_slot);await _expiry()
	await _finish()

func _detour_control()->void:
	var t:LifeTraversal=app.traversal;var helper=t.courtesy;var actor:LifeActor=app.world.actors.player;var other:LifeActor=app.world.actors.housemate_2
	var original_route:Dictionary=t.routes.player.duplicate(true);var original_body:Vector3=actor.position;var other_body:Vector3=other.position;var original_visibility:bool=other.visible
	var before:Dictionary=_physical_facts();var lock:Dictionary=t.stairs.stairs_2.duplicate(true)
	check(helper._blocked_candidate(t,"player"),"Original held-clear observation is still blocked at selection time.")
	var found:Dictionary={};var nav:LifeLotNavigation=app.world.lot_navigation;var clear:Vector3=t.routes.player.clear
	var queries:int=0
	for x:float in [-4.5,-4.0,-3.5,-3.0,-2.5,-.5,0.0,.5,1.0]:
		if not found.is_empty():break
		for z:float in [-.5,0,.5,1.0,1.5,2.0,2.5,2.75]:
			var from:Vector3=Vector3(x,clear.y,z)
			if from.distance_to(clear)<1.7 or not nav.point_clear(1,from):continue
			var static_path:PackedVector3Array=t._floor_route(from,clear)
			if static_path.size()<3:continue
			for obstacle:Vector3 in static_path:
				if obstacle.distance_to(from)<.85 or obstacle.distance_to(clear)<.85:continue
				queries+=1
				actor.position=from;other.position=obstacle;other.visible=true
				var occupied:Array[Vector3]=helper._hypothetical(t,"player","housemate_3",Vector3(-.5,clear.y,2.75))
				var alternate:Dictionary=nav.route_avoiding(LifeLotNavigation.floor_location(1,from),LifeLotNavigation.floor_location(1,clear),occupied,.78)
				if not bool(alternate.ok) or not alternate.segments.all(func(leg:Dictionary):return leg.kind=="floor") or not LifeJourneyState.clear_corridor(nav,alternate.points,occupied):continue
				actor.position=from;other.position=obstacle;other.visible=true;t.routes.player.points=alternate.points;t.routes.player.point=0
				if not helper._stair_clear(t,"player"):continue
				var admissible:PackedVector3Array=helper._clear_priority(t,"player",occupied)
				found={"from":from,"obstacle":obstacle,"live_detour":Array(alternate.points),"static_reconstruction":Array(static_path),"occupied":Array(occupied),"live_clear":LifeJourneyState.clear_corridor(nav,alternate.points,occupied),"static_clear":LifeJourneyState.clear_corridor(nav,static_path,occupied),"admission":admissible,"next_step_clear":t._step_clear("player",from,helper._next(t,"player")),"blocked_candidate":helper._blocked_candidate(t,"player")}
				break
			if not found.is_empty():break
	check(not found.is_empty(),"Bounded actual-navigation query finds a supported detour with a body blocking only its canonical shortcut.")
	if not found.is_empty():
		check(bool(found.live_clear) and not bool(found.static_clear) and found.admission.is_empty(),"Protected admission conservatively refuses a clear live detour whose fresh shortest reconstruction is blocked.")
		check(bool(found.next_step_clear) and not bool(found.blocked_candidate),"An already clear replanned next step cannot be selected using an earlier blocked observation.")
	actor.position=original_body;other.position=other_body;other.visible=original_visibility;t.routes.player=original_route
	check(_physical_facts()==before and t.stairs.stairs_2==lock,"Temporary detour/collision query fixture restores exact household physical/action/custody/clock and lock state.")
	audit["detour"]={"queries":queries,"found":found}

func _reservations_and_eligibility()->void:
	var t:LifeTraversal=app.traversal;var helper=t.courtesy;var route:Dictionary=t.routes.housemate_3;var anchor:Vector3=route.courtesy.anchor
	var protected:Dictionary=t.routes.player.duplicate(true);var motion:Dictionary=app.motion_states.housemate_3.duplicate(true)
	var before:Dictionary=_physical_facts()
	for phase_name:String in ["entry","transit"]:
		t.routes.player.phase=phase_name
		check(helper._beneficiary_kind(t,"player").is_empty(),"Protected "+phase_name+" is excluded from the new clear-only beneficiary kind.")
	t.routes.player.phase="clear"
	for field:String in ["waiting","resume_active"]:
		app.motion_states.housemate_3[field]=true
		check(not helper._eligible(t,"housemate_3"),"Ordinary donor exclusion retains "+field+" ownership.")
		app.motion_states.housemate_3=motion.duplicate(true)
	var action:Dictionary=app.household.member_sim("housemate_3").get_current_action();var had:bool=action.has("cooperation_role");var role:Variant=action.get("cooperation_role","")
	action.cooperation_role="learner";check(not helper._eligible(t,"housemate_3"),"Cooperative work cannot donate courtesy movement.")
	if had:action.cooperation_role=role
	else:action.erase("cooperation_role")
	var other_motion:Dictionary=app.motion_states.housemate_2.duplicate(true)
	app.motion_states.housemate_2.waiting=true;app.motion_states.housemate_2.wait_destination=anchor+Vector3(.79,0,0)
	check(not helper._anchor_clear(t,"housemate_3",anchor),"Existing ordinary resource wait keeps its .8m reservation against a new courtesy anchor.")
	app.motion_states.housemate_2=other_motion
	var corridor:PackedVector3Array=route.courtesy_priority;var point:Vector3=corridor[corridor.size()/2]
	check(not helper.point_allowed(t,"housemate_2",point) and not t._free("housemate_2",point),"A new ordinary wait or stair exit cannot reserve the protected clearance corridor.")
	check(helper.point_allowed(t,"player",point),"Already-owned protected clearance remains exempt from its own corridor.")
	check(_physical_facts()==before and t.routes.player==protected,"Eligibility/reservation component controls leave complete typed physical and protected route facts unchanged.")
	audit["reservation_corridor"]=corridor

func _navigation_control()->void:
	var t:LifeTraversal=app.traversal;var before:Dictionary=_physical_facts();var owned:Dictionary=t.routes.player.duplicate(true);var donor:Dictionary=t.routes.housemate_3.courtesy.duplicate(true)
	var generation:int=app.world.lot_navigation.generation
	app.world.rebuild_navigation()
	var response:Dictionary=t.request("housemate_3",t.routes.housemate_3.destination)
	check(bool(response.ok) and app.world.lot_navigation.generation>generation and t.courtesy.generation_current(t),"Successful navigation rebuild revalidates both clear corridors and refreshes actual donor motion.")
	check(t.routes.player==owned and t.routes.housemate_3.courtesy==donor,"Generation rebuild never rewrites protected polyline/phase/ticket/clear/custody and preserves the courtesy deadline.")
	check(_physical_facts()==before,"Unchanged navigation geometry preserves exact typed physical/queue/food/clock/journey facts.")
	var invalid:Dictionary=app.world.construction.snapshot().duplicate(true);invalid.floors[0].level=8
	generation=app.world.lot_navigation.generation;var failed_before:Dictionary=_physical_facts()
	var rejected:Dictionary=app.world.lot_navigation.rebuild(invalid,[])
	check(not bool(rejected.ok) and generation==app.world.lot_navigation.generation and _physical_facts()==failed_before,"Failed navigation rebuild retains the old graph and all authoritative courtesy/physical facts.")
	audit["navigation"]={"response":response,"failed_rebuild":rejected,"protected_before":owned,"protected_after":t.routes.player.duplicate(true)}

func _integrity()->void:
	var disk:Dictionary=LifeSaveLibrary.read_slot(hold_slot).data
	for label:String in ["missing_kind","walk_kind","unknown_kind","future_nested","legacy_has_kind","ordinary_kind_on_clear","expired","unknown_field","retired_identity","missing_ticket","unsupported_anchor","outer_legacy"]:
		var state:Dictionary=disk.duplicate(true);var fact:Dictionary=state.journeys.members.housemate_3.motion.courtesy
		match label:
			"missing_kind":fact.erase("beneficiary_kind")
			"walk_kind":fact.beneficiary_kind="walk"
			"unknown_kind":fact.beneficiary_kind="teleport"
			"future_nested":fact.version=3
			"legacy_has_kind":fact.version=1
			"ordinary_kind_on_clear":fact.beneficiary_kind="action"
			"expired":fact.expires_at=(float(state.day)-1)*1440+float(state.minutes)
			"unknown_field":fact.extra=true
			"retired_identity":fact.beneficiary_identity=1
			"missing_ticket":state.journeys.members.player.motion.ticket=0
			"unsupported_anchor":fact.anchor=[90,3.16,90]
			"outer_legacy":state.journeys.version=1
		var result:Dictionary=LifeSaveLibrary._validate_household(state)
		check(not bool(result.ok) and not str(result.get("error","")).is_empty(),"Strict saved-state preflight rejects: "+label)
		audit.rejections.append({"case":label,"result":result})
	for filename:String in ["legacy_ordinary_retreat.json","legacy_ordinary_hold.json"]:
		var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+filename))
		var result:Dictionary=LifeSaveLibrary._validate_household(old.data)
		check(bool(result.ok),"Existing actual six-field nestedv1 ordinary courtesy remains readable: "+filename)
		audit.rejections.append({"legacy":filename,"result":result})

func _donor_cancel()->void:
	var t:LifeTraversal=app.traversal;var protected:Dictionary=t.routes.player.duplicate(true);var lock:Dictionary=t.stairs.stairs_2.duplicate(true);var at:Vector3=app.world.actors.player.position
	await press_member("Casey Vale");await press("Cancel action")
	check(t.courtesy.owner(t).is_empty() and app.household.member_sim("housemate_3").action_queue.is_empty(),"Normal donor cancellation releases courtesy and cancels only that actual instruction.")
	check(t.routes.player==protected and t.stairs.stairs_2==lock and app.world.actors.player.position==at,"Canceling donor does not move/cancel/rewrite the protected beneficiary or release its lock.")
	audit["donor_cancel"]=_record_clear()

func _expiry()->void:
	var t:LifeTraversal=app.traversal;var before:Dictionary=_physical_facts();var protected:Dictionary=t.routes.player.duplicate(true);var lock:Dictionary=t.stairs.stairs_2.duplicate(true)
	t.routes.housemate_3.courtesy.expires_at=_now()
	check(app.save_game("","Component — expired landing courtesy"),"Pre-save mutation hook releases an explicitly expired courtesy fact before read-only snapshot.")
	var after:Dictionary=_physical_facts()
	check(t.courtesy.owner(t).is_empty() and t.routes.player==protected and t.stairs.stairs_2==lock,"Expiry releases donor only; protected route/custody/ticket/lock remain untouched.")
	check(before.people==after.people and before.food==after.food and before.clock==after.clock and before.funds==after.funds,"Expiry changes no body/queue/needs/food/custody/clock or funds.")
	check(t.courtesy.trace.any(func(e:Dictionary):return e.get("released","")=="housemate_3" and e.get("reason","")=="expired"),"Safety expiry is recorded distinctly from real recovery.")
	audit["expiry"]={"before":before,"after":after,"trace":t.courtesy.trace.duplicate(true)}
