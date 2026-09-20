extends "res://tests/test_meal_autonomy.gd"
## Real service/ledger component controls. Existing fixture supplies arrivals;
## selected age/clock/needs and approach metadata are explicit component inputs.
## Natural movement and named fresh load are tested by test_owned_meal.gd.
func _approach_fixture(partial:bool=false)->Dictionary:
	var f:Dictionary=_fixture()
	if partial:_advance(8)
	f.action.phase="approach";f.plate.storage="carried";f.plate.host="";f.plate.seat=""
	f.sim.needs.hunger=5.0
	return f
func _same_meal_approach()->void:
	var f:Dictionary=_approach_fixture(true)
	var before:Dictionary=f.action.duplicate(true);var food:Dictionary=app.household.meals.get_state()
	var choice:Dictionary=f.sim._autonomous_choice()
	check(str(choice.get("id",""))=="eat_meal" and str(choice.target_id)!=str(f.action.target_id),"Component reproduces a different meal target alias while the same portion is held.")
	f.sim._reconsider_active_autonomy()
	check(is_same(f.sim.get_current_action(),f.action) and before==f.action,"Alias reconsideration preserves the entire partial paid approach action object.")
	check(food==app.household.meals.get_state() and float(f.plate.progress)==.25,"Alias reconsideration does not release, reclaim, duplicate or advance the real portion.")
func _different_urgent_recovery()->void:
	var f:Dictionary=_approach_fixture(true);f.sim.needs.hunger=70.0;f.sim.needs.energy=4.0
	var paid:bool=bool(f.action.paid);var progress:float=float(f.plate.progress);var funds:int=app.household.funds
	f.sim._reconsider_active_autonomy()
	check(not is_same(f.sim.get_current_action(),f.action) and str(f.sim.get_current_action().get("id","")) in ["nap","sleep"],"A genuinely different urgent rest still interrupts the meal approach.")
	check(str(f.plate.owner).is_empty() and float(f.plate.progress)==progress and app.household.funds==funds and paid,"Urgent replacement safely releases partial food without charging or discarding progress.")
func _invalid_custody(kind:String)->void:
	var f:Dictionary=_approach_fixture()
	if kind=="expired":f.plate.expires=f.sim._autonomy_now()-1.0;f.batch.expires=f.sim._autonomy_now()-1.0
	elif kind=="missing":app.household.meals.portions.clear()
	else:f.plate.owner="housemate_1"
	var serial:int=app.household.meals.serial;var funds:int=app.household.funds
	f.sim._reconsider_active_autonomy()
	check(not is_same(f.sim.get_current_action(),f.action),"Invalid "+kind+" ownership cannot shield a stale approach.")
	check(float(f.plate.progress)==0.0 and app.household.meals.serial==serial and app.household.funds==funds,"Invalid "+kind+" grants no nutrition, serving claim or payment before arrival.")
	if kind=="foreign":check(f.plate.owner=="housemate_1","Rejecting foreign custody does not release another owner's portion.")
func _explicit_approach_queue()->void:
	var f:Dictionary=_approach_fixture(true);var shelf:Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	check(f.sim.queue_action("read",str(shelf.id),app.world.approach(shelf)),"A real player reading instruction can follow the partial meal approach.")
	var first:Dictionary=f.sim.action_queue[0];var later:Dictionary=f.sim.action_queue[1];var queue:Array=f.sim.action_queue.duplicate(true)
	f.sim.needs.energy=4.0;f.sim._reconsider_active_autonomy()
	check(is_same(f.sim.action_queue[0],first) and is_same(f.sim.action_queue[1],later) and f.sim.action_queue==queue,"Later player ownership keeps exact current and later action identities, contents and ordering.")
	app.cancel_current_action()
	check(not f.sim.action_queue.is_empty() and is_same(f.sim.get_current_action(),later) and str(f.plate.owner).is_empty(),"Direct player cancellation still releases the plate and starts the queued instruction.")
	check(float(f.plate.progress)==.25 and app.household.funds==shop_funds,"Direct cancellation retains actual partial progress and draws no further meal.")
func _invalid_endpoint()->void:
	var f:Dictionary=_approach_fixture(true);f.action.meal_standing=true;f.action.meal_seat="";f.action.target_id=str(f.plate.id);f.action.target_position=Vector3(200,.16,200)
	var progress:float=float(f.plate.progress);var funds:int=app.household.funds
	app._refresh_sim_targets(true)
	var current:Dictionary=f.sim.get_current_action()
	check(not current.is_empty() and is_same(current,f.action) and current.target_position!=Vector3(200,.16,200),"Production target refresh replaces an invalid eating endpoint with a real supported dining place.")
	check(not app.world.path_to(app.player.position,current.target_position).is_empty() and app.world.point_level(current.target_position)==0,"Reconciled endpoint has a supported same-floor path, without moving the actor.")
	check(f.plate.owner=="player" and float(f.plate.progress)==progress and app.household.funds==funds and current.phase=="approach","Geometry re-resolution preserves custody, partial paid action and funds until real arrival.")
func _blocked_reconsideration()->void:
	var f:Dictionary=_approach_fixture(true);f.sim.needs.hunger=70.0;f.sim.needs.energy=4.0
	var progress:float=float(f.plate.progress);var funds:int=app.household.funds
	var replaced:bool=f.sim.reconsider_waiting_autonomy([str(f.action.target_id)],30.0)
	check(replaced and not is_same(f.sim.get_current_action(),f.action) and str(f.sim.get_current_action().get("id","")) in ["nap","sleep"],"An actual arrived-resource-wait policy call can still replace a blocked meal with a different urgent recovery.")
	check(str(f.plate.owner).is_empty() and float(f.plate.progress)==progress and app.household.funds==funds,"Waiting policy replacement retains partial food progress and releases custody without payment.")
func _run()->void:
	root.gui_disable_input=true
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_same_meal_approach();_different_urgent_recovery();_invalid_custody("expired");_invalid_custody("missing");_invalid_custody("foreign");_explicit_approach_queue();_invalid_endpoint();_blocked_reconsideration()
	# Retain existing active-eating, actual nutrition, spoilage, player queue and
	# cancel/resume component checks; their arrival callbacks are explicit.
	_fresh_food_recovery();_explicit_queue();_expired_food();_missing_portion();_cancel_and_resume()
	var ambience:WeakRef=weakref(app.ambience_player.stream);var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free();await process_frame;await process_frame
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Component app audio releases before exit.")
	var report:Dictionary={"assertions":checks,"failures":failures,"scope":"Actual service/ledger component controls with explicit supplied arrival callbacks and controlled metadata; separate natural/fresh run supplies movement evidence."}
	var f:=FileAccess.open("res://evidence/components.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ",true,true));f.close()
	print("OWNED_CONTROLS_RESULT assertions=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
