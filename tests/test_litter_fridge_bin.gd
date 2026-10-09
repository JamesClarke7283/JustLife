extends SceneTree
var app:Node
var checks:int=0
var failures:Array[String]=[]
var finished_ids:Array[String]=[]
var carried_from_fridge:bool=false
var reached_bin:bool=false
var picked_up_at_fridge:bool=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,why:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",why)
	if not ok:failures.append(why)
func frames(n:int=3)->void:
	for i:int in n:await process_frame
func drive(limit:int=3000)->void:
	app.household.set_speed(8)
	for i:int in limit:
		app._process(.05)
		var action:Dictionary=app.sim.get_current_action()
		var held:Dictionary=app.household.meals.carried_by(app.household.selected_id())
		if not held.is_empty() and str(action.get("id",""))=="discard_meal":
			if not carried_from_fridge:
				var fridge:Dictionary=app.world.closest_item("fridge",app.player.position)
				picked_up_at_fridge=app.player.position.distance_to(app.world.approach(fridge))<.15
			carried_from_fridge=true
			if app.player.position.distance_to(app.world.approach(app.household_flow.kitchen_bin()))<.15:reached_bin=true
		if i%20==0:await process_frame
		if action.is_empty():break
	app.household.set_speed(0)
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false);app.selected_lot=0;app.start_household();await frames(4)
	app.set_process(false);app.household.set_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	var flow:LifeHouseholdFlow=app.household_flow
	var bin:Dictionary=flow.kitchen_bin()
	var fridge:Dictionary=app.world.closest_item("fridge",Vector3.ZERO)
	var tray:Dictionary={}
	for at:Vector2 in [Vector2(-3,3),Vector2(-4,3),Vector2(0,3)]:
		if app.world.can_place("litter_tray",Vector3(at.x,.16,at.y),0.0):
			app.world.add_item({"id":"hygiene_tray","kind":"litter_tray","x":at.x,"z":at.y,"rotation":0.0,"level":0},false);break
	app.world.rebuild_navigation();app._refresh_sim_targets(false);tray=app._find_item("hygiene_tray")
	check(not tray.is_empty() and not bin.is_empty() and not fridge.is_empty(),"Fixture has a reachable litter tray, fridge, sink and kitchen bin")
	if tray.is_empty():app.queue_free();await frames();quit(1);return
	flow.litter[str(tray.id)]=1
	var original:String=str(app.sim.character.age_stage)
	for stage:String in ["baby","toddler","child","young_adult","adult","elder"]:
		app.sim.character.age_stage=stage
		check(bool(app.sim.get_action_availability("clean_litter_tray",str(tray.id)).available)==(stage in ["young_adult","adult","elder"]),"Litter cleaning admission for "+stage)
	app.sim.character.age_stage="adult"
	app.household.pregnancy={"active":true,"mother_id":app.household.selected_id()}
	check(not bool(app.sim.get_action_availability("clean_litter_tray",str(tray.id)).available),"Pregnancy refuses direct litter cleaning")
	app.household.pregnancy=LifeBabyPlan.fresh()
	app.sim.action_finished.connect(func(action:Dictionary):finished_ids.append(str(action.id)))
	app.queue_interaction(tray,"clean_litter_tray")
	var shelf:Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	app.sim.queue_action("read",str(shelf.id),app.world.approach(shelf))
	await drive()
	check(int(flow.litter.get(str(tray.id),0))==0 and int(flow.fill.get(str(bin.id),0))==1,"Physical litter cleaning puts one unit in the kitchen bin")
	check(finished_ids.size()>=2 and finished_ids[0]=="clean_litter_tray" and finished_ids[1]=="wash_hands","Wash Hands is the immediate next completed action")
	check(finished_ids.size()>=3 and finished_ids[2]=="read","Immediate handwashing preserves the player's later queued activity")
	flow.fill[str(bin.id)]=3;app.notice_text=""
	check(flow.add_rubbish(1) and flow.bin_is_full(str(bin.id)),"Fourth unit fills kitchen bin")
	check("full" in app.notice_text.to_lower(),"Player gets full bin notification")
	check(not flow.add_rubbish(1) and int(flow.fill[str(bin.id)])==4,"A full bin refuses additional waste")
	flow.empty_bin(str(bin.id));flow.add_rubbish(4)
	check("full" in app.notice_text.to_lower(),"Refilling the bin on the same day notifies again")
	flow.litter[str(tray.id)]=1
	app.queue_interaction(tray,"clean_litter_tray");await frames()
	var litter_option:Button=app.overlay.find_child("EmptyBinFirst",true,false)
	check(is_instance_valid(litter_option) and int(flow.litter.get(str(tray.id),0))==1,"Full bin offers Empty Bin First without deleting litter")
	app.close_overlay()
	var now:float=app.meal_flow.now()
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet",app.household.selected_id(),1,"home",now)
	app.household.meals.set_batch_location(str(batch.id),"fridge",str(fridge.id),fridge.node.position,now)
	batch.created=0.0;batch.expires=now-1.0
	app.meal_flow.sync_world()
	check("spoiled" in app.notice_text.to_lower() and bool(batch.get("spoilage_notified",false)),"Fridge spoilage produces a player notice")
	app.notice_text="sentinel";app.meal_flow.sync_world()
	check(app.notice_text=="sentinel","Same spoiled dish does not repeatedly notify")
	var restored:LifeMeals=LifeMeals.new();restored.restore(app.household.meals.get_state())
	check(bool(restored.batch(str(batch.id)).get("spoilage_notified",false)),"Spoilage notification flag survives food ledger restore")
	app.meal_flow._queue_fridge_leftover(str(fridge.id),str(batch.id),false)
	await frames()
	var option:Button=app.overlay.find_child("EmptyBinFirst",true,false)
	check(is_instance_valid(option),"Discard into a full bin offers Empty Bin First")
	check(str(batch.storage)=="fridge" and int(batch.remaining)>0,"Full bin leaves spoiled food in the fridge until player chooses")
	if is_instance_valid(option):option.pressed.emit()
	await drive(5000)
	check(picked_up_at_fridge and carried_from_fridge and reached_bin,"Lifelet physically removes food at the fridge and carries it all the way to the bin")
	check(app.household.meals.batch(str(batch.id)).is_empty() and int(flow.fill.get(str(bin.id),0))==1,"Emptying first then disposing keeps one new waste unit")
	var table:Dictionary=app.world.closest_item("dining",Vector3.ZERO)
	var dish:Dictionary=app.household.meals.create_batch("garden_skillet",app.household.selected_id(),1,"home",app.meal_flow.now())
	app.household.meals.set_batch_location(str(dish.id),"surface",str(table.id),table.node.position,app.meal_flow.now())
	var plate:Dictionary=app.household.meals.claim(str(dish.id),app.household.selected_id(),app.meal_flow.now())
	app.household.meals.put_portion(str(plate.id),str(table.id),"",table.node.position)
	app.household.meals.finish_portion(str(plate.id));app.meal_flow.sync_world()
	flow.fill[str(bin.id)]=4
	app.queue_interaction(table,"clear_table");await frames()
	var table_option:Button=app.overlay.find_child("EmptyBinFirst",true,false)
	check(is_instance_valid(table_option) and not app.household.meals.portion(str(plate.id)).is_empty(),"Clearing a table into a full bin offers Empty Bin First and preserves plates")
	if is_instance_valid(table_option):table_option.pressed.emit()
	await drive(5000)
	check(app.household.meals.portion(str(plate.id)).is_empty() and int(flow.fill.get(str(bin.id),0))==1,"Emptying first then clearing the table commits one waste unit")
	var extras:Dictionary=flow.get_state()
	check(LifeHouseholdFlow.validate(extras,app.world.serialize_items()).is_empty(),"Litter and bin state validate for save")
	app.sim.character.age_stage=original
	print("LITTER_FRIDGE_BIN ",checks," checks ",failures.size()," failures")
	app.queue_free();await frames();quit(0 if failures.is_empty() else 1)
