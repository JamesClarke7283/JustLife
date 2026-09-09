extends "res://tests/test_meal_autonomy.gd"
## Controlled ledger/arrival component cases. Rendered public-flow proof is separate.
func _standing_fixture() -> Dictionary:
	var f:Dictionary=_fixture();f.sim.autonomy=false
	for value:Dictionary in app.world.items.duplicate():
		if str(value.kind) in ["chair","dining","counter","stove"]:app.world.remove_item(str(value.id))
	app.meal_flow.carry_diner_plate(f.action)
	check(app.meal_flow._choose_seat("player",f.action),"The cleared home offers a supported standing reservation.")
	var destination:Vector3=f.action.target_position
	var route:PackedVector3Array=app.world.path_to(app.world.actors.player.position,destination)
	check(not route.is_empty() and route[-1]==destination,"Standing fixture uses the exact endpoint of a real reachable route.")
	# Supply the physical arrival required by the actual meal service. This
	# component fixture does not claim to animate or traverse this route.
	app.world.actors.player.position=destination
	f.action.phase="approach";app.household.begin_action("player")
	check(str(f.action.meal_seat).is_empty() and str(f.plate.host).is_empty(),"No chairs or nearby support produces a real held standing serving.")
	return f

func _floor_finish() -> void:
	var f:Dictionary=_standing_fixture();_advance(32)
	check(float(f.plate.progress)==1 and str(f.plate.storage)=="dirty" and str(f.plate.owner).is_empty(),"Standing eating completes one actual portion and leaves unowned dirty ceramic.")
	var p:Array=f.plate.position;var at:=Vector3(p[0],p[1],p[2])
	check(absf(at.y-app.meal_flow._floor_support(at,LifeMeals.PLATE_HALF_SIZE))<.00001 and at.y<.2,"Finished standing plate rests on the measured floor instead of the former hand transform.")
	check(int(f.batch.served)==1 and int(f.batch.remaining)==3,"Setting down dirty ceramic does not alter serving conservation.")

func _floor_cancel() -> void:
	var f:Dictionary=_standing_fixture();_advance(8);f.sim.cancel_action()
	var p:Array=f.plate.position;var at:=Vector3(p[0],p[1],p[2])
	check(absf(float(f.plate.progress)-.25)<.000001 and str(f.plate.storage)=="surface" and str(f.plate.owner).is_empty(),"Cancellation keeps the real unfinished quarter-eaten portion.")
	check(absf(at.y-app.meal_flow._floor_support(at,LifeMeals.PLATE_HALF_SIZE))<.00001 and at.y<.2,"Canceled standing portion rests on measured floor without phantom nutrition.")

func _packing() -> void:
	var f:Dictionary=_fixture();f.sim.cancel_action();f.sim.autonomy=false
	app.household.meals.clear()
	var table:Dictionary=app.world.closest_item("dining",Vector3.ZERO)
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet","player",1,"home",app.meal_flow.now())
	var center:Vector3=table.node.to_global(Vector3(0,LifeMeals.SURFACE_HEIGHTS.dining,0))
	app.household.meals.set_batch_location(str(batch.id),"surface",str(table.id),center,app.meal_flow.now());batch.offset=[0.0,LifeMeals.SURFACE_HEIGHTS.dining,0.0]
	check(not app.meal_flow._surface_clear(table,Vector3(0,LifeMeals.SURFACE_HEIGHTS.dining,0),LifeMeals.PLATE_HALF_SIZE),"A fresh platter blocks an overlapping plate footprint.")
	for i:int in range(4):
		var plate:Dictionary=app.household.meals.claim(str(batch.id),"player",app.meal_flow.now())
		app.household.meals.finish_portion(str(plate.id))
		app.meal_flow._settle_food(plate,table.node.position+Vector3(0,0,.72))
		var p:Array=plate.position;var at:=Vector3(p[0],p[1],p[2])
		if str(plate.host)==str(table.id):
			check(app.meal_flow._surface_clear(table,table.node.to_local(at),LifeMeals.PLATE_HALF_SIZE,str(plate.id)),"Dirty plate keeps a unique wholly supported tabletop footprint.")
		else:check(absf(at.y-app.meal_flow._floor_support(at,LifeMeals.PLATE_HALF_SIZE))<.00001,"A crowded table falls back to supported floor.")
	var slot:Vector3=app.meal_flow._surface_slot(table,LifeMeals.PLATTER_HALF_SIZE)
	check(not slot.is_finite() or app.meal_flow._surface_clear(table,slot,LifeMeals.PLATTER_HALF_SIZE),"A later platter either has a wholly clear slot or rejects the full tabletop.")
	check(LifeMeals.validate(app.household.meals.get_state(),["player"],app.meal_flow.now()).is_empty(),"Packed food still has a valid conserved ledger.")

func _cleanup_policy() -> void:
	var f:Dictionary=_fixture();f.sim.autonomy=false;_advance(32)
	f.sim.autonomy=true
	app._refresh_sim_targets()
	var choice:Dictionary=f.sim._autonomous_choice()
	check(str(choice.get("id",""))=="clean_plate" and str(choice.target_id)==str(f.plate.id),"Safe idle Lifelet chooses actual dirty ceramic for washing.")
	f.sim._choose_autonomous_action()
	check(str(f.sim.get_current_action().get("id",""))=="clean_plate" and bool(f.sim.get_current_action().autonomous),"Housekeeping uses the ordinary autonomous queue.")
	app.household.begin_action("player");app.household.begin_action("player");_advance(18)
	check(app.household.meals.portion(str(f.plate.id)).is_empty(),"Actual pickup, sink arrival and elapsed washing remove the dirty plate.")
	f=_fixture();f.sim.autonomy=false;_advance(32)
	f.sim.needs.bladder=5;f.sim.autonomy=true
	choice=f.sim._autonomous_choice()
	check(str(choice.get("id",""))=="toilet","Urgent recovery outranks optional cleanup.")
	f.sim.needs.bladder=70;f.sim.day=1;f.sim.minutes=480
	choice=f.sim._autonomous_choice()
	check(str(choice.get("id",""))!="clean_plate","Morning school/work preparation outranks optional cleanup.")
	f.sim.day=6;f.sim.minutes=1080
	var shelf:Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	f.sim.queue_action("read",str(shelf.id),app.world.approach(shelf));var player_action:Dictionary=f.sim.get_current_action()
	f.sim._choose_autonomous_action()
	check(is_same(f.sim.get_current_action(),player_action) and not bool(player_action.autonomous),"Existing explicit player action is preserved while dishes are dirty.")

func _waiting_washer() -> void:
	var f:Dictionary=_fixture();var sim:LifeSim=f.sim
	sim.career.schedule=LifeCareerSchedule.fresh(sim.day);sim.education=LifeEducation.fresh("adult",sim.day);sim.autonomy=false;_advance(32)
	app._refresh_sim_targets();sim.autonomy=true;sim._choose_autonomous_action();app.household.begin_action("player")
	var washing:Dictionary=sim.get_current_action();var sink_id:String=str(washing.target_id)
	check(str(washing.get("meal_stage",""))=="wash" and str(f.plate.owner)=="player","Waiting washer owns the dirty plate after actual pickup.")
	var shelf:Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	sim.queue_action("read",str(shelf.id),app.world.approach(shelf));var queued_player_action:Dictionary=sim.action_queue[1]
	sim.needs.bladder=30
	check(sim.reconsider_waiting_autonomy([sink_id],30),"A long sink wait can replan toward moderate need recovery.")
	check(str(f.plate.owner).is_empty() and str(sim.get_current_action().id)=="toilet","Waiting replan releases matching food ownership before replacing its action.")
	check(sim.action_queue.size()==2 and is_same(sim.action_queue[1],queued_player_action) and not bool(queued_player_action.autonomous),"Waiting replan preserves the exact later player instruction.")
	var clone:=LifeHousehold.new();var saved:Dictionary=app.household.get_state(app.world.serialize_items())
	var restored:Dictionary=clone.restore_state(JSON.parse_string(JSON.stringify(sim._json_safe(saved))))
	check(bool(restored.ok),"Replanned washer remains a valid complete household save.");clone.free()

func _run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_floor_finish();_floor_cancel();_packing();_cleanup_policy();_waiting_washer()
	await _release_fixture()
	var report:Dictionary={"checks":checks,"failures":failures,"method":"Controlled ledger and actual controller arrival callbacks; no rendered navigation claim."}
	var file:=FileAccess.open("user://meal_placement_result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("MEAL_PLACEMENT "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func _release_fixture() -> void:
	var ambience:WeakRef=weakref(app.ambience_player.stream)
	var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free()
	await process_frame;await process_frame
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:
		await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Fixture teardown releases its ambience stream and backend playback before quitting.")
