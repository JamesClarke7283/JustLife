extends "res://tests/test_guest_meal.gd"
## Controlled failure boundaries use real dining geometry, ledger and routes.
var producer:Dictionary={}
func _load_phase(phase:String)->void:
	_load(str(producer[phase]));await process_frame;app.meal_flow.sync_world(false)
func _clock(value:float)->void:
	app.household.day=int(value/1440.0)+1;app.household.minutes=fmod(value,1440.0)
	for member:Dictionary in app.household.members:
		member.sim.day=int(value/1440.0)+1;member.sim.minutes=fmod(value,1440.0)
func _visit_raw(data:Dictionary)->Dictionary:return LifeHomeVisit.saved_visit(data).value.visit
func _reject(data:Dictionary,label:String)->void:
	var validator:=LifeHousehold.new();root.add_child(validator)
	var result:Dictionary=validator.restore_state(data)
	check(not bool(result.ok),"Strict guest save rejection: "+label)
	events.append({"rejection":label,"result":result})
	validator.free()
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var file:=FileAccess.open("user://guest_meal_slots.json",FileAccess.READ)
	if file==null:check(false,"Producer slots exist");await _finish();return
	producer=JSON.parse_string(file.get_as_text());file.close()
	await _load_phase("to_place")
	var visit:LifeHomeVisit=app.residents.home_visit
	var meal:LifeGuestMeal=visit.meal
	var actor:LifeActor=meal.body()
	var positions:Dictionary={}
	for id:String in app.world.actors:positions[id]=app.world.actors[id].position
	var seats:Array=[]
	for entry:Dictionary in app.world.items:
		if str(entry.kind)=="chair" and not app.meal_flow._chair_table(entry).is_empty() and not visit._route(actor.position,app.world.approach(entry),"maya").is_empty():seats.append(entry)
	seats.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.node.position.distance_squared_to(actor.position)<b.node.position.distance_squared_to(actor.position))
	check(seats.size()>=2,"Actual house supplies at least two reachable dining chairs")
	if seats.size()>=2:
		app.world.actors.player.position=app.world.approach(seats[0])
		check(visit._route(actor.position,app.world.approach(seats[0]),"maya").is_empty(),"Visible household body blocks the nearest guest chair route")
		var action:Dictionary=meal.activity();action.meal_seat="";action.meal_standing=false
		check(app.meal_flow._choose_seat("maya",action) and str(action.meal_seat)!=str(seats[0].id),"Guest skips blocked nearest chair for a reachable farther place")
		events.append({"nearest":str(seats[0].id),"chosen":str(action.get("meal_seat","")),"standing":action.get("meal_standing",false)})
	for id:String in positions:app.world.actors[id].position=positions[id]
	# Existing household reservations participate before guest selection.
	var original_queue:Array=app.sim.action_queue.duplicate(true)
	var reserved:String=str(meal.state.seat)
	app.sim.action_queue=[{"id":"sit","phase":"approach","target_id":reserved,"target_position":meal.state.target}]
	var alternate:Dictionary=meal.activity();alternate.meal_seat=""
	check(app.meal_flow._choose_seat("maya",alternate) and str(alternate.meal_seat)!=reserved,"Guest avoids a household member's already queued chair")
	app.sim.action_queue=original_queue
	# Remove only chairs from candidate inventory to exercise the existing standing geometry.
	var entries:Array=app.world.items.duplicate()
	app.world.items=app.world.items.filter(func(entry:Dictionary)->bool:return str(entry.kind)!="chair")
	var standing:Dictionary=meal.activity();standing.meal_seat="";standing.meal_standing=false
	check(app.meal_flow._choose_seat("maya",standing) and bool(standing.get("meal_standing",false)),"No usable chair falls back to a supported body-clear standing slot")
	if bool(standing.get("meal_standing",false)):
		meal.state.seat="";meal.state.standing=true;meal.state.target=standing.target_position
		check(app.meal_flow.standing_place_blocks("player",{"id":"sit","target_id":"","target_position":standing.target_position}),"Later household admission respects the guest standing reservation")
	app.world.items=entries
	await _load_phase("eating")
	visit=app.residents.home_visit;meal=visit.meal
	var progress:float=float(meal.plate().progress)
	var start:float=visit._now();var expires:float=start+.125
	meal.plate().expires=expires;meal.state.last_at=start
	app.household.set_speed(1);_step(1)
	var released:Dictionary=app.household.meals.portions[0]
	check(float(released.progress)==progress+(expires-start)/LifeMeals.EATING_MINUTES,"Expiry crossing consumes exactly the eligible fractional interval")
	check(str(released.owner).is_empty(),"Expired guest portion is safely set down once")
	await _load_phase("eating")
	visit=app.residents.home_visit;meal=visit.meal
	var deadline:float=float(visit.state.phase_at)+LifeHomeVisit.STAY_MINUTES
	_clock(deadline-.125);meal.state.last_at=visit._now();meal.plate().expires=deadline+100
	progress=float(meal.plate().progress);start=visit._now()
	app.household.set_speed(1);_step(1)
	released=app.household.meals.portions[0]
	check(float(released.progress)==progress+(deadline-start)/LifeMeals.EATING_MINUTES,"Visit deadline crossing consumes only the original eligible interval")
	check(_phase()=="leaving" and float(visit.state.phase_at)==deadline,"Guest leaves at the unchanged original visit deadline")
	await _load_phase("to_place")
	visit=app.residents.home_visit;meal=visit.meal
	var plate_id:String=str(meal.state.plate);var food_before:Dictionary=app.household.meals.get_state()
	visit.goodbye()
	var departure_at:float=float(visit.state.phase_at)
	# Controlled complete floor obstruction exercises real _settle_food failure.
	entries=app.world.items.duplicate()
	app.world.items=app.world.items.filter(func(entry:Dictionary)->bool:return not LifeMealFlow.SURFACE_HEIGHTS.has(str(entry.kind)))
	var blocker:=Node3D.new();app.world.house.add_child(blocker);blocker.position=Vector3(0,.16,0)
	app.world.items.append({"id":"controlled_no_slot","kind":"plant","level":0,"node":blocker,"size":Vector2(40,40)})
	check(not meal._release(),"Fully blocked real floor geometry refuses a setdown")
	check(_same_value(food_before,app.household.meals.get_state()) and str(meal.state.plate)==plate_id,"Failed setdown preserves exact owner, serving progress and all ledger fields")
	check(_phase()=="leaving" and app.residents.present("maya") and float(visit.state.phase_at)==departure_at,"Blocked release keeps guest visible without restarting departure")
	app.household.set_speed(1);meal.tick(.05)
	check(str(meal.state.phase)=="release" and float(meal.state.retry_at)==visit._now()+5.0,"Blocked release schedules a bounded five-minute retry")
	app.world.items=entries;blocker.free();meal.state.retry_at=0
	check(meal._release() and str(app.household.meals.portion(plate_id).owner).is_empty(),"Removing obstruction safely releases the original portion exactly once")
	check(_until("absent"),"Recovered release returns to the actual visitor exit lifecycle")
	await _load_phase("eating")
	visit=app.residents.home_visit;meal=visit.meal
	var expected_progress:float=float(meal.plate().progress)
	app.household.set_speed(1)
	var cadence_ok:bool=true
	for index:int in 12:
		var clock_before:float=visit._now();_step(1)
		expected_progress+=(visit._now()-clock_before)/LifeMeals.EATING_MINUTES
		cadence_ok=cadence_ok and float(meal.plate().progress)==expected_progress
	check(cadence_ok,"Every ordinary eating step matches its exact eligible simulation-minute increment")
	# Strict version/custody checks use an untouched decoded named eating save.
	var valid:Dictionary=LifeSaveLibrary.read_slot(str(producer.eating)).data
	var checker:=LifeHousehold.new();root.add_child(checker);check(bool(checker.restore_state(valid).ok),"Versioned guest custody accepts its exact named source");checker.free()
	var corrupt:Dictionary=valid.duplicate(true);corrupt.meals.portions[0].owner="leo";_reject(corrupt,"different resident owner")
	corrupt=valid.duplicate(true);corrupt.meals.portions[0].guest_visit+=1;_reject(corrupt,"different visit serial")
	corrupt=valid.duplicate(true);corrupt.meals.portions[0].guest_meal+=1;_reject(corrupt,"different meal token")
	corrupt=valid.duplicate(true);corrupt.meals.portions[0].storage="carried";_reject(corrupt,"eating without physical table custody")
	corrupt=valid.duplicate(true);_visit_raw(corrupt).meal.plate="";_reject(corrupt,"missing owned plate")
	corrupt=valid.duplicate(true);_visit_raw(corrupt).meal.phase="pickup";_reject(corrupt,"pickup claiming a reserved plate")
	corrupt=valid.duplicate(true);_visit_raw(corrupt).meal.last_at=INF;_reject(corrupt,"nonfinite consumption clock")
	corrupt=valid.duplicate(true);_visit_raw(corrupt).admitted_at="bad";_reject(corrupt,"malformed visit clock before meal validation")
	corrupt=valid.duplicate(true);corrupt.meals.version=1;_reject(corrupt,"guest in legacy household-only food version")
	corrupt=valid.duplicate(true);LifeHomeVisit.saved_visit(corrupt).value.version=1;_reject(corrupt,"guest meal in legacy visit version")
	corrupt=valid.duplicate(true);corrupt.meals.batches[0].chef="maya";_reject(corrupt,"guest falsely owning household cooking")
	corrupt=valid.duplicate(true);_visit_raw(corrupt).meal.seat="missing_chair";_reject(corrupt,"plate and reserved chair disagree")
	corrupt=valid.duplicate(true)
	var current_seat:String=str(_visit_raw(corrupt).meal.seat)
	for entry:Dictionary in app.world.items:
		if str(entry.kind)=="chair" and str(entry.id)!=current_seat and not app.meal_flow._chair_table(entry).is_empty():
			_visit_raw(corrupt).meal.seat=str(entry.id);corrupt.meals.portions[0].seat=str(entry.id);break
	var untouched:Dictionary=_record()
	var physical:Dictionary=app._prepare_loaded_world(corrupt)
	check(not bool(physical.ok),"Physical candidate rejects a chair binding at a different actual approach")
	if bool(physical.ok):physical.viewport.free();physical.candidate.free()
	check(_same_value(_record(),untouched),"Rejected physical guest candidate leaves the live household wholly unchanged")
	# Actual previous versions had a visitor but no guest meal ownership.
	var legacy:Dictionary=LifeSaveLibrary.read_slot(str(producer.pickup)).data
	var found:Dictionary=LifeHomeVisit.saved_visit(legacy)
	found.value.version=1;legacy.meals.version=1
	var old_visit:Dictionary=found.value.visit
	old_visit.erase("meal");old_visit.erase("next_meal")
	old_visit.position=old_visit.inside.duplicate()
	old_visit.route={"points":[old_visit.inside.duplicate()],"point":1}
	found.residents.locations.home[str(old_visit.guest)].position=old_visit.position.duplicate()
	var prior_save:Dictionary=LifeSaveLibrary.save_slot("","Previous guest format",legacy)
	check(bool(prior_save.ok),"Previous visit and household-only food versions still pass named-save validation")
	if bool(prior_save.ok):
		_load(str(prior_save.id));await process_frame;app.meal_flow.sync_world(false)
		check(_phase()=="inside" and not app.residents.home_visit.meal.active() and int(app.residents.home_visit.state.next_meal)==1,"Previous guest format restores as a paused ordinary visitor with fresh meal identity")
		check(app.meal_flow.call_to_meal(str(app.household.meals.batches[0].id))==1,"Previously saved ordinary guest can join a new correctly versioned meal")
		visit=app.residents.home_visit;meal=visit.meal
		var base_visit:Dictionary=visit.state.duplicate(true);var base_food:Dictionary=app.household.meals.get_state()
		# Controlled competing physical-arrival seam: ordinary claim takes the
		# last serving just before the guest's claim runs. No save uses this fixture.
		var batch:Dictionary=app.household.meals.batch(str(meal.state.source));batch.remaining=1;batch.discarded=3
		var rival:Dictionary=app.household.meals.claim(str(batch.id),"player",visit._now())
		meal.body().position=meal.state.target;meal._pickup()
		check(not rival.is_empty() and app.household.meals.portions.size()==1 and str(meal.state.plate).is_empty() and int(batch.remaining)==0,"Competing last-serving claim cannot debit or create a second guest portion")
		app.household.meals.restore(base_food);visit.state=base_visit.duplicate(true)
		batch=app.household.meals.batch(str(meal.state.source));batch.storage="fridge"
		meal._pickup()
		check(app.household.meals.portions.is_empty() and int(batch.remaining)==4 and str(meal.state.phase)=="release","Dish moved to storage before pickup cancels the guest offer without a debit")
		app.household.meals.restore(base_food);visit.state=base_visit.duplicate(true)
		batch=app.household.meals.batch(str(meal.state.source));batch.expires=visit._now()
		meal.body().position=meal.state.target;meal._pickup()
		check(app.household.meals.portions.is_empty() and int(batch.remaining)==4 and str(meal.state.phase)=="release","Spoilage at the physical pickup boundary creates no guest portion")
	await _finish()
