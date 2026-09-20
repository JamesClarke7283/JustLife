extends SceneTree
## Real meal ledger/service with controlled controller-arrival callbacks.
## Headless component coverage; this does not test walking or visual contact.
var app: Node
var checks: int = 0
var failures: Array[String] = []
## The purse after the fixture's own grocery order, so the cases below can prove
## nothing else charges the household for food.
var shop_funds: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures.append(detail)
		push_error(detail)

func _fixture() -> Dictionary:
	app.household_profiles=[{"name":"Meal Policy","age_stage":"adult","traits":[]}]
	app.creator_family_links=[]
	app.start_household()
	app.set_process(false)
	app.household.day=6;app.household.minutes=1080.0
	var sim: LifeSim=app.sim
	sim.day=6;sim.minutes=1080.0;sim.set_aging("normal",false)
	sim.household_bills_enabled=false;sim.wants.clear();sim.autonomy=true
	for need: String in LifeSim.NEED_NAMES:sim.needs[need]=70.0
	app.household.set_funds(1000);app.household.set_speed(1)
	# A snack is drawn from the kitchen, so the fixture stocks it through the
	# household's own order before the spoiled-food case asks for one.
	var ordered:Dictionary=app.household.order_groceries("weekly")
	var collected:Dictionary=app.household.collect_groceries()
	check(bool(ordered.ok) and bool(collected.ok),"The fixture stocks its own kitchen through the household's order.")
	# The one shop the fixture itself placed is the only money the purse should
	# ever lose, so the cases below compare against that rather than a bare 1000.
	shop_funds=int(app.household.funds)
	var batch: Dictionary=app.household.meals.create_batch("garden_skillet","player",1,"home",sim._autonomy_now())
	var table: Dictionary=app.world.closest_item("dining",Vector3.ZERO)
	var at: Vector3=table.node.to_global(Vector3(0,LifeMeals.SURFACE_HEIGHTS.dining,0))
	app.household.meals.set_batch_location(str(batch.id),"surface",str(table.id),at,sim._autonomy_now())
	batch.offset=[0.0,LifeMeals.SURFACE_HEIGHTS.dining,0.0]
	app._refresh_sim_targets()
	check(sim.queue_action("eat_meal",str(batch.id),at),"Fresh meal is available through the actual service.")
	# Arrival at the dish claims one portion; arrival at its chair starts eating.
	app.household.begin_action("player")
	app.household.begin_action("player")
	var action: Dictionary=sim.get_current_action()
	check(str(action.get("phase",""))=="active" and str(action.get("meal_stage",""))=="eat","Controller callbacks produce active eating.")
	action.autonomous=true
	var plate: Dictionary=app.household.meals.portion(str(action.get("meal_plate","")))
	check(not plate.is_empty() and int(batch.served)==1 and int(batch.remaining)==3,"Physical pickup claimed exactly one owned plate.")
	check(action.changes.is_empty(),"Nourishment remains a real service effect, without synthetic action deltas.")
	return {"sim":sim,"batch":batch,"plate":plate,"action":action}

func _advance(minutes: int) -> void:
	for i: int in range(minutes):app.household.tick(1.0/LifeSim.GAME_MINUTES_PER_SECOND)

func _fresh_food_recovery() -> void:
	var f: Dictionary=_fixture();var sim: LifeSim=f.sim
	sim.needs.hunger=5.0;sim.needs.energy=4.0
	_advance(1)
	check(is_same(sim.get_current_action(),f.action),"A second urgent need does not abandon the active plate.")
	check(is_equal_approx(float(f.plate.progress),1.0/32.0),"The first minute advances the actual portion once.")
	_advance(31)
	check(float(f.plate.progress)==1.0 and str(f.plate.storage)=="dirty","One short eating turn completes useful nourishment and leaves its plate.")
	check(int(f.batch.served)==1 and app.household.meals.portions.size()==1,"Urgent replanning does not claim extra servings.")
	var expected: float=5.0+70.0-float(LifeSim.NEED_DECAY.hunger)*32.0/60.0
	check(absf(float(sim.needs.hunger)-expected)<.00001,"The recipe grants precisely one portion's nutrition, minus actual decay.")
	check(app.household.funds==shop_funds,"Eating and replanning do not recharge ingredients or buy snacks.")
	sim._choose_autonomous_action()
	check(str(sim.get_current_action().get("id",""))in ["nap","sleep"],"The still-urgent second need receives recovery after eating.")
	app.household.begin_action("player");var before: float=float(sim.needs.energy);_advance(1)
	check(float(sim.needs.energy)>before,"The follow-up rest makes useful recovery progress.")

func _explicit_queue() -> void:
	var f: Dictionary=_fixture();var sim: LifeSim=f.sim
	var shelf: Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	check(sim.queue_action("read",str(shelf.id),app.world.approach(shelf)),"A player can queue reading after the current meal.")
	var later: Dictionary=sim.action_queue[1]
	sim.needs.hunger=5;sim.needs.energy=4;_advance(1)
	check(sim.action_queue.size()==2 and is_same(sim.action_queue[0],f.action) and is_same(sim.action_queue[1],later),"Meal classification preserves the explicit queue and its exact ordering.")
	check(not bool(later.get("autonomous",false)),"The later instruction keeps player ownership.")

func _expired_food() -> void:
	var f: Dictionary=_fixture();var sim: LifeSim=f.sim
	f.plate.expires=sim._autonomy_now()-1.0;f.batch.expires=sim._autonomy_now()-1.0
	sim.needs.hunger=5;sim.needs.energy=4
	_advance(1)
	check(not is_same(sim.get_current_action(),f.action),"Expired food receives no short-recovery protection.")
	check(float(f.plate.progress)==0.0 and float(sim.needs.hunger)<5.0,"Expired food grants no nutrition or portion progress.")
	check(str(sim.get_current_action().get("id",""))in ["nap","sleep"],"An available urgent recovery replaces spoiled food.")
	check(str(f.plate.owner).is_empty(),"Canceling spoiled eating releases the diner ownership.")
	sim.cancel_action();sim.needs.energy=70;sim._choose_autonomous_action()
	check(str(sim.get_current_action().get("id",""))=="snack","Hunger falls back to an available snack when all prepared food is spoiled.")
	check(int(f.batch.served)==1 and app.household.funds==shop_funds,"Spoilage/replanning does not double-claim or charge before arrival.")

func _missing_portion() -> void:
	var f: Dictionary=_fixture();var sim: LifeSim=f.sim
	app.household.meals.portions.clear()
	sim.needs.hunger=5;sim.needs.energy=4;_advance(1)
	check(not is_same(sim.get_current_action(),f.action) and str(sim.get_current_action().get("id",""))in ["nap","sleep"],"An absent portion cannot shield a stale eating action from recovery.")
	check(float(sim.needs.hunger)<5 and app.household.funds==shop_funds,"A missing portion gives neither phantom nutrition nor an extra charge.")

func _cancel_and_resume() -> void:
	var f: Dictionary=_fixture();var sim: LifeSim=f.sim
	sim.needs.hunger=5;sim.needs.energy=4;_advance(8)
	check(absf(float(f.plate.progress)-.25)<.00001,"Partial real nourishment is retained before explicit cancellation.")
	sim.cancel_action()
	check(sim.action_queue.is_empty() and str(f.plate.owner).is_empty(),"The player can still cancel a protected autonomous meal.")
	app._refresh_sim_targets()
	check(sim.queue_action("eat_meal",str(f.plate.id),Vector3.ZERO),"The same partially eaten plate can be chosen again.")
	app.household.begin_action("player");app.household.begin_action("player")
	var resumed: Dictionary=sim.get_current_action()
	check(str(resumed.get("meal_plate",""))==str(f.plate.id) and absf(float(resumed.elapsed)-8.0)<.00001,"Resume uses the same plate and completed eating time.")
	resumed.autonomous=true;_advance(24)
	check(float(f.plate.progress)==1.0 and int(f.batch.served)==1 and app.household.meals.portions.size()==1,"Resumed eating completes without creating another serving.")
	var expected: float=5.0+70.0-float(LifeSim.NEED_DECAY.hunger)*32.0/60.0
	check(absf(float(sim.needs.hunger)-expected)<.00001 and app.household.funds==shop_funds,"Cancel/resume grants exactly the remaining nutrition and no new charge.")

func _run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	_fresh_food_recovery();_explicit_queue();_expired_food();_missing_portion();_cancel_and_resume()
	var report: Dictionary={"checks":checks,"failures":failures,"scope":"Headless actual ledger/service; controller arrivals supplied, no navigation/render claims."}
	var file: FileAccess=FileAccess.open("user://meal_autonomy_result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MEAL_AUTONOMY "+JSON.stringify(report))
	app.queue_free()
	await process_frame;await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
