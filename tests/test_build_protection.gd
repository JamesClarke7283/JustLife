extends "res://tests/test_stair_controller.gd"
const MainScene=preload("res://scenes/main.tscn")
## Actual main/controller frames and Build callbacks. Food is created through
## the ledger API as explicit setup; this does not qualify paid cooking or art.
var protection_observations:Array=[]

func _remote_wall()->Dictionary:return {"op":"structure","tool":"wall","level":0,"ax":5.0,"az":1.0,"bx":6.0,"bz":1.0}

func _motion_without_generation()->Dictionary:
	var state:Dictionary=app.build_protection_context()
	for route:Dictionary in state.routes.values():route.erase("generation")
	return state

func _check_rejected(operation:Dictionary,text:String)->void:
	var geometry:Dictionary=app.world.construction.snapshot();var funds:int=app.household.funds
	var route:Dictionary=app.build_protection_context()
	var quote:Dictionary=app.build_transactions.prepare(operation,true)
	check(not bool(quote.ok),text+": "+str(quote.get("error","unexpected acceptance")))
	check(geometry==app.world.construction.snapshot() and funds==app.household.funds and route==app.build_protection_context(),"Rejected preview is read-only: "+text)

func _owned_and_waiting()->void:
	_setup(2)
	app.on_ground_clicked(Vector3(2,3.16,4))
	check(_until_transit("player"),"First real ground-click walker enters the stair before the opposing request.")
	app.select_household_member(1);app.on_ground_clicked(Vector3(-2,.16,-4))
	var joined:bool=false
	for frame:int in 800:
		_step()
		if str(_route("housemate_1").get("phase",""))=="waiting" and int(_route("housemate_1").ticket)>0 and str(_route("player").get("phase",""))=="transit":joined=true;break
	check(joined,"Opposing child actually arrives and takes a FIFO ticket while the adult remains on stairs.")
	if not joined:return
	app.set_build_mode(true)
	var state:Dictionary=app.world.construction.snapshot()
	var route:Dictionary=_route("player")
	var facts:Dictionary=_motion_without_generation();var pose:Transform3D=app.world.actors.player.transform
	var clock:float=app.household.minutes;var money:int=app.household.funds
	var detached:Dictionary=app.build_protection_context();detached.routes.player.safety=true;detached.stairs.clear();detached.foods.clear()
	check(_motion_without_generation()==facts,"Read-only Build context owns no mutable live route, lock or ledger dictionaries.")
	check(app.world.point_level(pose.origin)<0 and LifeBuildProtection.proven_transit(app.build_protection_context(),"player",state,state),"An actual mid-height gait has live owner and exact stair geometry proof.")
	_check_rejected({"op":"remove","id":str(route.stair_id)},"Cannot demolish a staircase with a live owner and arrived waiter")
	var clear:Vector3=route.clear
	_check_rejected({"op":"structure","tool":"wall","level":1,"ax":clear.x-.5,"az":clear.z,"bx":clear.x+.5,"bz":clear.z},"Cannot wall across the owner's reserved clear landing")
	var wait:Vector3=_route("housemate_1").wait
	_check_rejected({"op":"structure","tool":"wall","level":1,"ax":wait.x-.5,"az":wait.z,"bx":wait.x+.5,"bz":wait.z},"Cannot wall across an arrived waiter's position")
	var quote:Dictionary=app.build_transactions.prepare(_remote_wall(),true)
	check(bool(quote.ok),"A separate ground wall remains available during occupied stair transit: "+str(quote.get("error","valid")))
	if not bool(quote.ok):return
	var identity:int=int(route.identity);var ticket:int=int(_route("housemate_1").ticket)
	var generation:int=app.world.lot_navigation.generation
	app.on_construction({"valid":true,"build_quote":quote})
	check(app.build_undo.size()==1 and app.household.funds==money-int(quote.cost) and app.household.members.all(func(member:Dictionary)->bool:return member.sim.funds==money-int(quote.cost)),"Actual Build callback installs the unaffected wall and charges once.")
	check(app.world.lot_navigation.generation>generation and int(_route("player").generation)==app.world.lot_navigation.generation and int(_route("housemate_1").generation)==app.world.lot_navigation.generation,"Equivalent remaining routes acknowledge the actual rebuilt graph generation.")
	check(_motion_without_generation()==facts and app.world.actors.player.transform==pose and app.household.minutes==clock,"Build target refresh retains every route/lock/body/ledger fact except graph generation, without time advance.")
	app.undo_build()
	check(app.build_undo.is_empty() and app.household.funds==money and LifeBuildTransactions.new(app)._same_geometry(state,app.world.construction.snapshot()),"Real Undo refunds only the unrelated wall and restores its geometry.")
	check(_motion_without_generation()==facts and int(_route("player").identity)==identity and int(_route("housemate_1").ticket)==ticket,"Unchanged owner and arrived waiter keep exact identity, ticket, phase and distance through Undo.")
	app.set_build_mode(false);app.household.set_speed(1)
	var minimum:float=INF
	for frame:int in 2000:
		_step();minimum=minf(minimum,app.world.actors.player.position.distance_to(app.world.actors.housemate_1.position))
		if app.traversal.routes.is_empty():break
	check(app.traversal.routes.is_empty() and app.world.actors.player.position.distance_to(Vector3(2,3.16,4))<.001 and app.world.actors.housemate_1.position.distance_to(Vector3(-2,.16,-4))<.001,"Both walkers naturally complete their original opposite-direction destinations after Build and Undo.")
	check(minimum>=.70,"Post-edit crossing retains the existing body spacing gate.")
	protection_observations.append({"case":"owner_and_waiter","owner_identity":identity,"waiter_ticket":ticket,"minimum_distance":minimum,"before":facts,"final":app.build_protection_context()})

func _food_custody()->void:
	_setup()
	app.loading_game=true
	app.setup_live([{"id":"upper_table","kind":"dining","x":2.0,"z":0.0,"rotation":0.0,"level":1},{"id":"ground_shelf","kind":"bookshelf","x":-3.25,"z":0.0,"rotation":0.0},fixture()])
	app.loading_game=false;app.player.position=Vector3(-2,.16,-4);app.sim.needs.hunger=100;app._store_motion()
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet","player",2,"home",app.meal_flow.now())
	check(not batch.is_empty(),"Explicit API fixture creates one original four-serving batch; no actual cooking claim.")
	app.meal_flow.sync_world();app._refresh_sim_targets(false)
	check(app.sim.queue_action("serve_meal",str(batch.id)),"Actual simulation serve instruction accepts the API-created held batch.")
	check(_until_transit("player"),"Serving instruction actually walks onto the stairs with its original batch.")
	if str(_route("player").get("phase",""))!="transit":return
	app.queue_interaction(app._find_item("ground_shelf"),"read")
	app.set_build_mode(true)
	var quote:Dictionary=app.build_transactions.prepare(_remote_wall(),true)
	check(bool(quote.ok),"A carried serving dish does not become a fabricated unsupported floor object during preview.")
	if not bool(quote.ok):return
	var geometry:Dictionary=app.world.construction.snapshot();var money:int=app.household.funds
	var ledger:Dictionary=app.household.meals.get_state();var pose:Transform3D=app.player.transform
	var clock:float=app.household.minutes
	app.cancel_current_action()
	var current:Dictionary=app.sim.get_current_action()
	check(app.traversal.safety("player") and str(_route("player").custody)==str(batch.id) and app.player.transform==pose,"Actual current-action cancellation changes live custody and safety while the paused actor stays still.")
	check(app.household.meals.get_state()==ledger and str(current.id)=="read" and str(current.phase)=="approach" and float(current.elapsed)==0,"Cancellation retains exactly one owned batch, all four servings and the unstarted later read.")
	var stale:Dictionary=app.build_transactions.commit(quote)
	check(not bool(stale.ok) and str(stale.error).contains("changed"),"Pre-cancel quote rejects changed live custody even though geometry, wallet and actor position are identical.")
	check(app.household.funds==money and app.world.construction.snapshot()==geometry and app.household.meals.get_state()==ledger,"Stale ownership quote cannot charge, install geometry, release food or claim a serving.")
	var facts:Dictionary=_motion_without_generation()
	var fresh:Dictionary=app.build_transactions.prepare(_remote_wall(),true)
	check(bool(fresh.ok),"A freshly reviewed unaffected edit remains possible during canceled dish custody.")
	if not bool(fresh.ok):return
	app.on_construction({"valid":true,"build_quote":fresh})
	check(_motion_without_generation()==facts and is_same(current,app.sim.get_current_action()) and app.household.minutes==clock,"Actual Build commit preserves canceled transit, food custody and exact later-action dictionary.")
	app.undo_build()
	check(_motion_without_generation()==facts and app.household.funds==money,"Actual Undo preserves the same canceled dish custody and refunds only its wall.")
	app.overlay_open=true
	check(app.save_game("","Build protected dish"),"Current main writes the paused named save after structural commit and Undo.")
	var saved:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(saved.ok),"Named save validates actual current journey, canceled custody and original food IDs: "+str(saved.get("error","valid")))
	app.overlay_open=false;app.set_build_mode(false);app.household.set_speed(1)
	var prematurely_active:bool=false
	for frame:int in 2000:
		_step()
		if not app.traversal.safety("player"):break
		if str(current.phase)!="approach" or float(current.elapsed)!=0:prematurely_active=true
	check(not prematurely_active and not app.traversal.safety("player") and app.world.point_level(app.player.position)==1,"Actual canceled crossing reaches its clear upper landing before later work begins.")
	check(str(batch.owner).is_empty() and str(batch.storage)=="surface" and int(batch.remaining)==4 and app.household.meals.batches.size()==1 and app.household.meals.portions.is_empty(),"Landing release sets down the original batch once, without duplicate food, claims or consumption.")
	for frame:int in 2200:
		_step()
		if str(current.phase)=="active":break
	check(is_same(current,app.sim.get_current_action()) and str(current.phase)=="active" and app.world.point_level(app.player.position)==0,"Original later read descends by actual stairs and begins at its ground shelf.")
	protection_observations.append({"case":"api_food_cancel_custody","paid_cooking":false,"before":facts,"after":app.build_protection_context(),"save_slot":app.active_save_id})

func _loose_food_and_undo()->void:
	_setup();app.set_build_mode(true)
	var money:int=app.household.funds
	var quote:Dictionary=app.build_transactions.prepare({"op":"add","collection":"floors","record":{"level":0,"x":6.0,"z":3.0,"w":2.0,"d":2.0,"material":"cfa97e"}},true)
	check(bool(quote.ok),"Separate ground slab previews before a loose food fixture is placed.")
	if not bool(quote.ok):return
	app.on_construction({"valid":true,"build_quote":quote})
	var food:Dictionary=app.household.meals.create_batch("herb_pasta","player",2,"home",app.meal_flow.now())
	check(app.household.meals.set_batch_location(str(food.id),"surface","",Vector3(6,.162,3),app.meal_flow.now()),"Explicit ledger API places a whole original pasta dish on the new slab.")
	# Intentionally no sync_world: hidden/uncached ledger records still count.
	check(app.world.items.all(func(item:Dictionary)->bool:return str(item.id)!=str(food.id)),"Food protection control has no transient view to accidentally rely on.")
	var before:Dictionary=app.world.construction.snapshot();var funds:int=app.household.funds
	app.undo_build()
	check(app.build_undo.size()==1 and before==app.world.construction.snapshot() and app.household.funds==funds,"Actual Undo refuses to remove a loose ledger dish's supporting floor, without refund.")
	_check_rejected({"op":"structure","tool":"wall","level":0,"ax":5.5,"az":3.0,"bx":6.5,"bz":3.0},"Cannot construct a wall through uncached food's full footprint")
	var cached:Dictionary=app.build_transactions.prepare(_remote_wall(),true)
	check(bool(cached.ok),"A loose dish still permits a distant unaffected wall.")
	check(app.household.meals.set_batch_location(str(food.id),"surface","",Vector3(6.5,.162,3),app.meal_flow.now()),"Actual ledger location changes while body, wallet and geometry stay fixed.")
	var stale:Dictionary=app.build_transactions.commit(cached)
	check(not bool(stale.ok) and str(stale.error).contains("changed"),"Live ledger-only location change invalidates the old construction quote.")
	check(app.household.meals.set_batch_location(str(food.id),"surface","",Vector3(-2,.162,2),app.meal_flow.now()),"API fixture moves its dish to the supported original ground floor.")
	app.undo_build()
	check(app.build_undo.is_empty() and app.household.funds==money,"After actual support is freed, the same Undo removes its slab and refunds exactly once.")

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_owned_and_waiting();_food_custody();_loose_food_and_undo()
	var report:Dictionary={"checks":checks,"failures":failures,"observations":protection_observations,"scope":"Actual controller 50ms frames, Build callbacks, FIFO, cancel-custody and named-save read. Food created via ledger API, not paid cooking. No rendered pointer or fresh-process restoration qualification."}
	var file:=FileAccess.open("user://build_protection.json",FileAccess.WRITE);file.store_string(JSON.stringify(LifeSaveLibrary._json_safe(report),"  ",true,true));file.close()
	print("BUILD_PROTECTION checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
