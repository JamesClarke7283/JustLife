extends "res://tests/test_guest_activity_company.gd"
## Without any command, a comfortable visitor works through the whole house: the
## pets, every member of the household from the baby to the adults, the garden,
## the lawn games, the seats and the fridge. A need that grows urgent comes first.
var seen: Dictionary={}

## Let the visitor decide once and report what they chose, then stand them down.
func decide(needs: Dictionary = {}) -> String:
	guest().cancel("")
	for step: int in 400:
		if not guest().active():break
		app._process(.05)
	for need: String in needs:guest().data.needs[need]=needs[need]
	guest().data.next_at=guest().now()
	guest().data.last_at=guest().now()
	guest()._choose()
	var chosen: String=str(guest().current_action().get("id",""))
	if chosen=="snack" and str(guest().current_action().get("flavour",""))=="drink":chosen="drink"
	var target: String=str(guest().current_action().get("target_id",""))
	if not chosen.is_empty():
		seen[chosen]=seen.get(chosen,0)+1
		if not target.is_empty():seen[chosen+"@"+target]=true
	return chosen

func comfortable() -> Dictionary:
	return {"hunger":90.0,"energy":90.0,"hygiene":90.0,"bladder":90.0,"fun":70.0,"social":70.0}

func _run() -> void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	if not family_setup():await _finish();return
	var draft: Dictionary=LifePets.candidate(1,0);draft.name="Guest's friend"
	var prepared: Dictionary=app.household.prepare_pet(draft)
	var home: Vector3=app.pet_home_spot()
	var adopted: Dictionary=app.household.commit_pet(prepared.get("request",{}),home)
	check(bool(adopted.get("ok",false)),"Real pet is adopted for the visitor")
	if not bool(adopted.get("ok",false)):await _finish();return
	var pet_id: String=str(adopted.pet.id)
	app.spawn_pet(pet_id,adopted.pet,home,home)
	app.world.add_item({"id":"guest_swing","kind":"outdoor_swing","x":6.5,"z":7.0,"rotation":0.0})
	app.world.add_item({"id":"guest_game","kind":"game_ring_toss","x":-6.5,"z":7.0,"rotation":0.0})
	app.world.add_item({"id":"guest_hot_tub","kind":"hot_tub","x":-11.0,"z":-2.0,"rotation":0.0})
	app.world.add_item({"id":"guest_pool","kind":"pool","x":-11.0,"z":2.0,"rotation":0.0})
	app._refresh_sim_targets()
	check(visit().invite("maya"),"Friend is invited")
	app.household.set_speed(8)
	check(await frames_until(func():return _phase()=="waiting"),"Visitor reaches the front door")
	check(visit().welcome("player"),"Host welcomes the visitor")
	app.household.set_speed(8)
	await frames_until(func():return _phase() in ["inside","absent","leaving"])
	check(_phase()=="inside","Visitor is inside")
	if _phase()!="inside":await _finish();return
	app.household.set_speed(0)
	if not idle_family():await _finish();return

	# ---- needs come first, by themselves
	var wash: String=await decide({"hygiene":10.0})
	check(wash in ["shower","bath"],"A dirty visitor washes without being asked (%s)" % wash)
	var snack: String=await decide({"hygiene":90.0,"hunger":20.0})
	check(snack in ["snack","drink"] or str(visit().meal.state.get("phase",""))!="","A hungry visitor goes to the fridge or the table unasked (%s)" % snack)
	visit().meal.cancel("")
	var toilet: String=await decide({"hunger":90.0,"bladder":10.0})
	check(toilet=="toilet","A visitor who needs the toilet goes unasked (%s)" % toilet)

	# ---- then, round after round, everything the house offers
	seen.clear()
	for round: int in 30:
		await decide(comfortable())
	check(seen.has("pet_pet") or seen.has("pet_play"),"Left alone, the visitor goes to the pet (%s)" % str(seen.keys()))
	check(seen.has("play_with_baby@housemate_3"),"Left alone, the visitor plays with the baby (%s)" % str(seen.keys()))
	check(seen.has("joke@housemate_2") or seen.has("hug@housemate_2"),"Left alone, the visitor joins in with the child (%s)" % str(seen.keys()))
	check(seen.has("joke@player") or seen.has("friendly@player") or seen.has("joke@housemate_1") or seen.has("friendly@housemate_1"),"Left alone, the visitor talks to the adults (%s)" % str(seen.keys()))
	check(seen.has("enjoy_outdoors"),"Left alone, the visitor uses the garden (%s)" % str(seen.keys()))
	check(seen.has("play_garden_game"),"Left alone, the visitor plays a lawn game (%s)" % str(seen.keys()))
	check(seen.has("relax"),"Left alone, the visitor sits down somewhere (%s)" % str(seen.keys()))
	check(seen.has("drink"),"Left alone, the visitor gets something from the fridge (%s)" % str(seen.keys()))
	var outdoor_targets: Array=[]
	for key: Variant in seen:
		if str(key).begins_with("enjoy_outdoors@"):outdoor_targets.append(str(key).trim_prefix("enjoy_outdoors@"))
	check(outdoor_targets.size()>=2,"The garden choices are spread over the swing, pool and hot tub (%s)" % str(outdoor_targets))

	# ---- short of fun, the fun things come first
	seen.clear()
	for round: int in 6:
		var picked: String=await decide({"fun":20.0,"social":70.0,"hunger":90.0,"hygiene":90.0,"bladder":90.0,"energy":90.0})
		check(picked in ["pet_play","pet_pet","enjoy_outdoors","play_garden_game"],"A bored visitor picks something fun (%s)" % picked)
	# ---- short of company, the household comes first
	seen.clear()
	for round: int in 6:
		var picked: String=await decide({"fun":90.0,"social":15.0,"hunger":90.0,"hygiene":90.0,"bladder":90.0,"energy":90.0})
		check(picked in ["play_with_baby","joke","hug","friendly"],"A lonely visitor looks for company (%s)" % picked)

	# ---- into the water in swimwear, and out of it in the clothes they came in
	guest().cancel("")
	for step: int in 400:
		if not guest().active():break
		app._process(.05)
	var arrived_in: Dictionary=LifeCharacterIdentity.wardrobe_fields(app.world.actors.maya.profile)
	check(guest().request("enjoy_outdoors","guest_pool",true),"The visitor can be sent to the pool")
	app.household.set_speed(8)
	check(await frames_until(func()->bool:return str(guest().current_action().get("phase",""))=="active",3000),"The visitor walks to the water")
	app.household.set_speed(0)
	check(str(app.world.actors.maya.profile.get("outfit_category",""))=="swim","The visitor swims in swimwear")
	check(guest().data.has("look_before"),"What they came in is remembered")
	check(app.save_game("","Visitor in the pool"),"A visitor in the pool saves")
	var slot: String=app.active_save_id
	app.load_game(slot)
	await process_frame
	guest().present(true)
	check(str(app.world.actors.maya.profile.get("outfit_category",""))=="swim","A paused load puts the swimmer back in swimwear")
	guest().cancel("")
	for step: int in 400:
		if not guest().active():break
		app._process(.05)
	check(LifeCharacterIdentity.wardrobe_fields(app.world.actors.maya.profile)==arrived_in,"Out of the water they wear exactly what they came in")

	# ---- an explicit request still beats whatever they would have chosen
	guest().cancel("")
	guest().data.next_at=guest().now()+600
	check(guest().request("relax",str(first("sofa").id),true),"A direct request still overrides autonomy")
	await _finish()
