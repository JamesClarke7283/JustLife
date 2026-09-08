extends "res://tests/test_meal_autonomy.gd"
## Controlled endpoint/ownership/save adversaries. Actor placement below is
## explicit fixture setup or controller-arrival setup, never rendered proof.
func _group() -> Dictionary:
	app.household_profiles=[{"name":"Standing One","age_stage":"adult","traits":[]},{"name":"Standing Two","age_stage":"adult","traits":[]},{"name":"Resting Three","age_stage":"adult","traits":[]}]
	app.creator_family_links=[];app.start_household();app.set_process(false)
	app.household.day=6;app.household.minutes=1080;app.household.set_speed(1)
	for member:Dictionary in app.household.members:
		member.sim.day=6;member.sim.minutes=1080;member.sim.autonomy=false;member.sim.set_aging("normal",false)
		member.sim.career.schedule=LifeCareerSchedule.fresh(6);member.sim.education=LifeEducation.fresh("adult",6)
		member.sim.household_bills_enabled=false;member.sim.wants.clear()
		for need:String in LifeSim.NEED_NAMES:member.sim.needs[need]=70.0
	for value:Dictionary in app.world.items.duplicate():
		if str(value.kind)=="chair":app.world.remove_item(str(value.id))
	var table:Dictionary=app.world.closest_item("dining",Vector3.ZERO)
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet","player",1,"home",app.meal_flow.now())
	var at:Vector3=table.node.to_global(Vector3(0,LifeMeals.SURFACE_HEIGHTS.dining,0))
	app.household.meals.set_batch_location(str(batch.id),"surface",str(table.id),at,app.meal_flow.now());batch.offset=[0.0,LifeMeals.SURFACE_HEIGHTS.dining,0.0]
	app._refresh_sim_targets()
	var positive:=LifeHousehold.new();var snapshot:Dictionary=JSON.parse_string(JSON.stringify(app.sim._json_safe(app.household.get_state(app.world.serialize_items()))))
	check(bool(positive.restore_state(snapshot).ok),"The initial controlled calendar and whole household are valid before dining.");positive.free()
	return {"batch":batch,"at":at}

func _pickup(id:String,f:Dictionary) -> Dictionary:
	var sim:LifeSim=app.household.member_sim(id)
	check(sim.queue_action("eat_meal",str(f.batch.id),f.at),"A diner requests the same actual platter.")
	app.household.begin_action(id)
	var action:Dictionary=sim.get_current_action()
	check(bool(action.get("meal_standing",false)) and str(action.get("meal_stage",""))=="eat" and str(action.phase)=="approach","Pickup reserves a standing route before any eating.")
	check(str(action.target_id)==str(action.meal_plate),"The reservation uses this diner’s owned plate, not a shared platter resource.")
	return action

func _endpoints_and_blocker() -> void:
	var f:Dictionary=_group()
	var first:Dictionary=_pickup("player",f);var second:Dictionary=_pickup("housemate_1",f)
	var first_at:Vector3=first.target_position;var second_at:Vector3=second.target_position
	check(first_at.distance_to(second_at)>=.85,"Two standing diners reserve distinct body-clear endpoints.")
	for entry:Array in [["player",first],["housemate_1",second]]:
		var route:PackedVector3Array=app.world.path_to(app.world.actors[entry[0]].position,entry[1].target_position)
		check(not route.is_empty() and route[-1].is_equal_approx(entry[1].target_position),"A reservation is the exact route endpoint, without nearest-free substitution.")
	var plate:Dictionary=app.household.meals.portion(str(first.meal_plate));var ledger_before:Dictionary=plate.duplicate(true)
	app._refresh_sim_targets()
	check(first.target_position==first_at and second.target_position==second_at,"Target refresh preserves both standing destinations.")
	check(plate.position==ledger_before.position and float(plate.progress)==0 and str(plate.owner)=="player","Reserving and rebuilding a walking route does not move food or grant nutrition.")
	var resting:LifeSim=app.household.member_sim("housemate_2")
	var sofa:Dictionary=app.world.closest_item("sofa",Vector3.ZERO)
	resting.queue_action("nap",str(sofa.id),first_at);resting.get_current_action().phase="active"
	app.world.actors.housemate_2.position=first_at
	check(not app.meal_flow._standing_clear("player",first_at),"A real visible nap body invalidates the old arrival spot.")
	var before:float=float(app.sim.needs.hunger)
	app.household.begin_action("player")
	check(first.target_position.distance_to(first_at)>=1.15 and str(first.phase)=="approach","An arrival blocker causes a new physical route with reclining clearance.")
	check(float(plate.progress)==0 and is_equal_approx(float(app.household.member_sim("player").needs.hunger),before) and int(f.batch.served)==2,"Obstructed arrival retains exactly two claims and gives no food progress or recovery.")
	check(first.target_position.distance_to(second.target_position)>=.85,"Replanning retains the other diner’s reserved place.")
	var resources_a:Array=app._activity_resources(first);var resources_b:Array=app._activity_resources(second)
	check(resources_a.all(func(value:String)->bool:return not resources_b.has(value)),"Separate dining anchors and plates do not share an exclusive activity resource.")

func _partial_save_and_legacy() -> void:
	var f:Dictionary=_group();var action:Dictionary=_pickup("player",f)
	var sim:LifeSim=app.household.member_sim("player")
	app.world.actors.player.position=action.target_position # Controlled arrival, no rendered movement claim.
	app.household.begin_action("player");_advance(8)
	var plate:Dictionary=app.household.meals.portion(str(action.meal_plate))
	check(str(action.phase)=="active" and bool(action.paid) and absf(float(plate.progress)-.25)<.00001,"Controlled exact arrival permits one quarter of actual elapsed eating.")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(sim._json_safe(app.household.get_state(app.world.serialize_items()))))
	var clone:=LifeHousehold.new();var result:Dictionary=clone.restore_state(saved)
	print("STANDING_SAVE ",JSON.stringify(result))
	var captured:=FileAccess.open("user://standing_save.json",FileAccess.WRITE);captured.store_string(JSON.stringify(saved,"  "));captured.close()
	check(bool(result.ok),"Paid partially eaten standing state is a valid whole household save.")
	if bool(result.ok):
		var restored:Dictionary=clone.member_sim("player").get_current_action()
		check(bool(restored.get("meal_standing",false)) and restored.target_position==action.target_position,"Fresh restore retains the same canonical standing reservation.")
		check(bool(restored.paid) and is_equal_approx(float(restored.elapsed),8) and absf(float(clone.meals.portion(str(action.meal_plate)).progress)-.25)<.00001,"Restored payment and partial nourishment match the actual owned plate.")
	clone.free()
	for malformed:Variant in ["true",false,1]:
		var bad:Dictionary=saved.duplicate(true);bad.members[0].state.action_queue[0].meal_standing=malformed
		var invalid:=LifeHousehold.new();var rejected:Dictionary=invalid.restore_state(bad);check(not bool(rejected.ok) and str(rejected.get("error","")).contains("standing diner"),"Invalid standing reservation marker is rejected specifically: "+str(malformed));invalid.free()
	var legacy:Dictionary=saved.duplicate(true)
	legacy.members[0].state.action_queue[0].erase("meal_standing")
	legacy.members[0].state.action_queue[0].target_id=str(action.meal_source)
	var older:=LifeHousehold.new();var old_result:Dictionary=older.restore_state(legacy);print("LEGACY_SAVE ",JSON.stringify(old_result));check(bool(old_result.ok),"A legitimate earlier standing save without the new marker still loads.");older.free()
	var before:Dictionary=plate.duplicate(true)
	action.erase("meal_standing");action.target_id=str(action.meal_source);action.phase="approach"
	app.meal_flow.resolve(sim,action)
	check(bool(action.get("meal_standing",false)) and str(action.target_id)==str(plate.id),"Legacy standing action obtains an owned exact-route reservation on resolution.")
	check(float(plate.progress)==float(before.progress) and str(plate.owner)==str(before.owner) and bool(action.paid),"Legacy migration preserves consumed amount, ownership and payment.")

func _run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_endpoints_and_blocker();_partial_save_and_legacy()
	var report:Dictionary={"checks":checks,"failures":failures,"method":"Controlled source/arrival/save adversaries; not a rendered navigation or animation proof."}
	var file:=FileAccess.open("user://standing_dining_result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("STANDING_DINING "+JSON.stringify(report));app.queue_free();await process_frame;await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
