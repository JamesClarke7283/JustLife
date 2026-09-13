extends "res://tests/test_meal_autonomy.gd"
## Paid-action persistence and build/controller probes. Arrivals and clock steps
## are explicitly supplied; this component test is not rendered motion evidence.
func _phase_progress(name:String,part:float=.5)->float:
	for phase_entry:Array in LifeOvenSequence.PHASES:
		if str(phase_entry[0])==name:return lerpf(float(phase_entry[1]),float(phase_entry[2]),part)
	return 0.0

func _advance_oven_minutes(amount:float)->void:
	var rate:float=LifeSim.GAME_MINUTES_PER_SECOND*float(app.household.speed)
	assert(rate>0.0)
	while amount>0.0:
		var step:float=minf(amount,60.0*rate)
		app.household.tick(step/rate)
		amount-=step

func _bake(progress:float,second:bool=false) -> Dictionary:
	app.household_profiles=[{"name":"Oven Audit","age_stage":"adult","traits":[]}]
	if second:app.household_profiles.append({"name":"Waiting Cook","age_stage":"adult","traits":[]})
	app.creator_family_links=[];app.start_household();app.set_process(false)
	for member:Dictionary in app.household.members:member.sim.autonomy=false;member.sim.set_aging("normal",false);member.sim.household_bills_enabled=false;member.sim.wants.clear()
	app.sim.autonomy=false;app.sim.set_aging("normal",false);app.sim.household_bills_enabled=false;app.sim.wants.clear()
	app.sim._gain_skill("cooking",450.0)
	for need:String in LifeSim.NEED_NAMES:app.sim.needs[need]=70.0
	app.household.set_funds(1000);app.household.set_speed(1)
	var oven:Dictionary=app.world.closest_item("stove",Vector3.ZERO)
	check(app.sim.queue_action("cook",str(oven.id),app.world.approach(oven),"harvest_bake"),"The unlocked bake queues through the real recipe definition.")
	var action:Dictionary=app.sim.get_current_action()
	app.player.position=action.target_position # Controlled arrival callback, no walking claim.
	app.household.begin_action("player")
	_advance_oven_minutes(70.0*progress)
	check(str(action.phase)=="active" and bool(action.paid) and is_equal_approx(float(action.elapsed),70.0*progress),"Actual paid cooking time reaches the chosen probe phase.")
	check(app.household.funds==976 and app.household.meals.batches.is_empty(),"Ingredients charge exactly once; unfinished cooking creates no serving ledger.")
	app.meal_flow.present_actor("player");app._update_activity_facing(.1,action,"cook");app.player.animate(.1,1.0,false,"cook")
	app.household.set_speed(0);app.meal_flow.sync_world();app.world._process(.01)
	return {"action":action,"id":str(oven.id),"elapsed":float(action.elapsed),"progress":float(action.progress),"at":action.target_position}

func _door(id:String)->float:
	var oven:Dictionary=app._find_item(id)
	if oven.is_empty():return -1
	return oven.node.find_child("OvenDoor",true,false).rotation.x

func _refresh_and_build() -> void:
	var f:Dictionary=_bake(_phase_progress("open_load",.7))
	app._refresh_sim_targets()
	check(str(f.action.phase)=="active" and f.action.target_position==f.at,"Unchanged-target refresh preserves the exact active oven destination.")
	check(is_equal_approx(_door(f.id),PI*.5*LifeOvenSequence.door_open(f.progress)),"The paused open door matches actual paid progress.")
	app.set_build_mode(true);app.move_item(app._find_item(f.id))
	check(app.meal_flow.action_title(f.action).begins_with("Getting ready to cook "),"A detached oven cannot claim the cook is actively preparing.")
	check(app._find_item(f.id).is_empty() and is_same(app.sim.get_current_action(),f.action),"Temporary oven removal preserves the exact paid instruction.")
	check(float(f.action.elapsed)==float(f.elapsed) and app.household.funds==976,"Build preview does not advance or recharge cooking.")
	app.cancel_placement();app.meal_flow.sync_world();app.world._process(.01)
	check(str(f.action.phase)=="active" and f.action.target_position==f.at,"Canceling the same oven move restores its active destination without spurious replanning.")
	check(is_equal_approx(_door(f.id),PI*.5*LifeOvenSequence.door_open(f.progress)),"Recreated paused oven restores its open door from paid activity state.")
	app.cancel_current_action();app.meal_flow.sync_world();app.world._process(.01)
	check(app.sim.action_queue.is_empty() and is_zero_approx(_door(f.id)),"Canceling in Build clears the oven visual even while actor animation is frozen.")
	check(app.household.funds==976 and app.household.meals.batches.is_empty(),"Canceled ingredients are not refunded and no unfinished food becomes edible.")

func _paused_named_restore() -> void:
	for fraction:float in [_phase_progress("load",.7),_phase_progress("bake",.5)]:
		var f:Dictionary=_bake(fraction)
		check(app.save_game("","Paused paid oven"),"A paused paid bake writes a valid named whole-household save.")
		var id:String=app.active_save_id
		app.load_game(id);app.set_process(false);app.meal_flow.sync_world();app.world._process(.01)
		var current:Dictionary=app.sim.get_current_action()
		check(app.household.speed==0 and bool(current.paid) and is_equal_approx(float(current.elapsed),f.elapsed),"Named load preserves pause and exact paid cooking progress.")
		check(app.meal_flow.action_title(current)=="Preparing harvest vegetable bake","A paid cook restored at the unchanged oven retains its preparation title while paused.")
		check(current.target_position==f.at and app.household.funds==976,"Named load preserves the oven route and one ingredient charge.")
		check(is_equal_approx(_door(f.id),PI*.5*LifeOvenSequence.door_open(f.progress)),"A paused freshly reconstructed oven immediately restores its correct door phase.")
		check(app.household.meals.batches.is_empty(),"Paused reconstruction cannot fabricate an edible serving batch.")

func _interior_and_completion() -> void:
	var f:Dictionary=_bake(.68)
	check(app.world.oven_food_views.size()==1 and app.world.oven_food_views.has(f.id),"The current paid interior phase has exactly one world presentation dish.")
	var view:Node3D=app.world.oven_food_views.get(f.id)
	check(is_instance_valid(view) and view.visible and view.get_parent()==app._find_item(f.id).node,"Interior food belongs to the actual stove, independent of animator state.")
	check(app.world.items.all(func(entry:Dictionary)->bool:return entry.node!=view),"Preparation food is not pickable or a usable serving resource.")
	app.player.cooking_presentation={"recipe":"garden_skillet","progress":0.0}
	app.meal_flow.sync_world()
	check(app.world.oven_food_views.size()==1 and app.world.oven_presentations[f.id].progress==f.progress,"A deliberately stale actor cache cannot change the paid oven state.")
	app.meal_flow.present_actor("player")
	check(bool(app.player.cooking_presentation.get("oven_interior",false)),"The actor receives the same interior ownership flag to avoid a duplicate tray.")
	check(app.save_game("","Paid interior finish"),"Interior cooking can be saved without a duplicate edible batch.")
	app.load_game(app.active_save_id);app.set_process(false);app.meal_flow.sync_world()
	check(app.world.oven_food_views.size()==1 and app.world.oven_food_views.has(f.id),"Paused named load reconstructs exactly one interior dish before animation runs.")
	var action:Dictionary=app.sim.get_current_action()
	app.household.set_speed(1);app.player.position=action.target_position # Controlled re-arrival, not rendered proof.
	app.household.begin_action("player")
	_advance_oven_minutes(70.0-float(action.elapsed)+.01)
	app.meal_flow.sync_world()
	check(app.household.meals.batches.size()==1 and int(app.household.meals.batches[0].initial)==8,"Only finishing the remaining real cooking time creates one eight-serving batch.")
	check(app.household.funds==976 and app.world.oven_food_views.is_empty() and app.world.oven_presentations.is_empty(),"Completion removes preparation visuals with no second ingredient charge.")

func _moved_host_and_sale() -> void:
	var f:Dictionary=_bake(.68)
	app.set_build_mode(true);app.move_item(app._find_item(f.id));app.meal_flow.sync_world()
	check(app.world.oven_food_views.is_empty() and app.world.oven_presentations.is_empty(),"A temporarily removed oven has no unsupported floating interior view.")
	app.meal_flow.present_actor("player")
	check(bool(app.player.cooking_presentation.get("oven_suspended",false)),"Detached Build preview explicitly suspends held cooking props too.")
	var destination:Vector3=Vector3.INF
	for candidate:Vector3 in [Vector3(3,.16,2),Vector3(3,.16,-3),Vector3(-2,.16,1),Vector3(1,.16,3)]:
		if app.world.can_place("stove",candidate,90):destination=candidate;break
	check(destination.is_finite(),"The fixture has a real valid relocated oven footprint.")
	if not destination.is_finite():return
	app.on_placement("stove",destination,90)
	var moved:Dictionary=app._find_item(f.id)
	check(not moved.is_empty() and is_same(app.sim.get_current_action(),f.action),"Committing the move preserves the exact paid action and stove identity.")
	check(app.meal_flow.action_title(f.action).begins_with("Getting ready to cook "),"A paid cook away from its relocated oven still needs to approach.")
	check(str(f.action.phase)=="approach" and f.action.target_position==app.world.oven_approach(moved) and f.action.target_position!=f.at,"Moved cooking routes to the new exact oven endpoint before work resumes.")
	app.household.tick(10.0)
	check(float(f.action.elapsed)==f.elapsed and app.household.funds==976,"Paused moved cooking retains elapsed ingredients without unattended progress.")
	check(app.world.oven_food_views.size()==1 and app.world.oven_food_views[f.id].get_parent()==moved.node,"Interior presentation follows the newly placed oven while the cook is still approaching.")
	var rack:Node3D=moved.node.find_child("OvenRack",true,false)
	check(app.world.oven_food_views[f.id].global_position.is_equal_approx(rack.global_position),"Rotated moved oven uses its real authored rack transform.")
	check(app.save_game("","Moved paid oven"),"Paused relocated paid preparation remains a valid named household save.")
	var shelf:Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	check(app.sim.queue_action("read",str(shelf.id),app.world.approach(shelf)),"A later explicit home instruction remains available behind the bake.")
	var later:Dictionary=app.sim.action_queue[1]
	var credit:int=int(LifeCatalog.ITEMS.stove.price*.7)
	app.sell_item(moved);app.meal_flow.sync_world()
	check(is_same(app.sim.get_current_action(),later) and str(later.phase)=="approach","Selling the oven cancels only its bake and retains the exact later instruction.")
	print("SALE_WALLET selected=",app.sim.funds," household_before_adoption=",app.household.funds," credit=",credit)
	check(app.sim.funds==976+credit and app.household.meals.batches.is_empty(),"Sale pays only the furniture credit; canceled ingredients produce neither refund nor edible food.")
	check(app.world.oven_food_views.is_empty() and app.world.oven_presentations.is_empty(),"Selling the host clears all preparation ownership and views.")
	check(app.save_game("","Oven sold, still reading"),"The post-sale household with its remaining queue saves successfully.")
	check(app.household.funds==976+credit,"The public save adopts the selected wallet exactly once after the sale.")

func _unpaid_contender() -> void:
	var f:Dictionary=_bake(.68,true)
	var other:LifeSim=app.household.member_sim("housemate_1")
	other._gain_skill("cooking",450.0)
	check(other.queue_action("cook",f.id,app.world.oven_approach(app._find_item(f.id)),"harvest_bake"),"A second qualified cook can queue an unpaid request at the occupied oven.")
	var other_action:Dictionary=other.get_current_action()
	app._store_motion();app._bind_member("housemate_1")
	check(not app._activity_available(other_action),"The active paid owner blocks the later cook at the real shared resource gate.")
	app._bind_member("player");app.meal_flow.sync_world();app.meal_flow.present_actor("housemate_1")
	check(app.world.oven_presentations[f.id].person=="player" and app.world.oven_food_views.size()==1,"An unpaid contender cannot replace or duplicate the paid owner's oven dish.")
	check(not app.player.cooking_presentation.is_empty() and not bool(app.world.actors.housemate_1.cooking_presentation.get("oven_interior",false)),"Only the paid owner presents the interior portion.")
	app.cancel_current_action();app.meal_flow.sync_world()
	check(other.action_queue.size()==1 and not bool(other_action.paid) and app.world.oven_presentations.is_empty(),"Owner cancellation preserves the waiting instruction without transferring paid food or ingredients.")

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_refresh_and_build();_paused_named_restore();_interior_and_completion();_moved_host_and_sale();_unpaid_contender()
	var report:Dictionary={"checks":checks,"failures":failures,"scope":"Controlled real paid recipe time, named save/load and public build controller methods; no rendered motion claim."}
	var file:=FileAccess.open("user://oven_controller.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("OVEN_CONTROLLER ",JSON.stringify(report));app.queue_free();await process_frame;await process_frame;await process_frame
	# Audio playback releases are processed on the mixer thread after nodes
	# leave the tree; give shutdown a real engine interval before process exit.
	await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
