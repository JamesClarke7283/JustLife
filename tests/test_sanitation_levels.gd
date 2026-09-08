extends "res://tests/test_sanitation.gd"
## Draft gate: merge into a private V2 source before executing.
const Building=preload("res://scripts/building_state.gd")
var level_facts:Array=[]
var active_slot:String=""
func fixture()->Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	for level:int in [0,1]:
		for side:int in [-1,1]:state.walls.append({"id":("upper_" if level else "")+("north" if side<0 else "south"),"level":level,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	var quote:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
	check(bool(quote.ok),"The sanitation fixture has a validated staircase and supported upper slab.")
	return quote.after if bool(quote.ok) else state
func setup_levels()->void:
	app.household_profiles=[{"name":"Alex Rivera","frame":0},{"name":"Jamie Rowan","frame":1}]
	app.start_household();app.set_process(false);app.loading_game=true
	app.setup_live([{"id":"upper_plant","kind":"plant","x":-2.0,"z":2.0,"rotation":0.0,"level":1},{"id":"upper_shelf","kind":"bookshelf","x":3.25,"z":0.0,"rotation":0.0,"level":1},{"id":"ground_shelf","kind":"bookshelf","x":-3.25,"z":0.0,"rotation":0.0},fixture()])
	app.loading_game=false;reset_needs()
	for member:Dictionary in app.household.members:
		member.sim.set_aging("normal",false);member.sim.household_bills_enabled=false;member.sim.wants.clear()
	app.player.position=Vector3(-2,.16,-3.5);app.world.actors.housemate_1.position=Vector3(2,.16,3.5)
	app._store_motion();app._refresh_sim_targets(false)
func route()->Dictionary:return app.traversal.routes.get("player",{})
func until_transit()->bool:
	for index:int in 1600:
		app._process(.05)
		if str(route().get("phase",""))=="transit" and float(route().distance)>.6:return true
	return false
func walk_to(at:Vector3)->void:
	app.on_ground_clicked(at)
	check(until(func()->bool:return not app.walk_only,400.0),"The real controller finishes walking to "+str(at)+".")
	check(app.player.position.distance_to(at)<.00001,"The Lifelet actually occupies the requested supported destination.")
func facts()->Dictionary:
	var people:Dictionary={}
	for id:String in app.world.actors:
		var actor:LifeActor=app.world.actors[id]
		people[id]={"transform":actor.transform,"stair_pose":actor.stair_presentation.duplicate(true)}
	return {"household":app.household.get_state(app.world.serialize_items()),"routes":app.traversal.snapshot(),"locks":app.traversal.stairs.duplicate(true),"actors":people,"selected":app.household.selected_id(),"bound":app.bound_member_id,"mode":app.mode}
func check_read_only(label:String)->void:
	var before:Dictionary=facts()
	for index:int in 6:
		var detached:Dictionary=app.household.get_state(app.world.serialize_items())
		check(not detached.has("snapshot_error"),label+": read-only physical capture is complete.")
	check(facts()==before,label+": repeated snapshots leave clocks, urgency, sanitation, actors and stair ownership unchanged.")
func pending_crossing(down:bool=false,cancel:bool=false)->void:
	setup_levels()
	if down:walk_to(Vector3(2,3.16,3.5))
	var destination:Vector3=Vector3(-2,.16,-3.5) if down else Vector3(2,3.16,3.5)
	app.on_ground_clicked(destination)
	check(until_transit(),"Pending urgency test reaches real "+("descending" if down else "ascending")+" stair transit.")
	var identity:int=int(route().identity);var ticket:int=int(route().ticket)
	if cancel:
		app.cancel_current_action()
		check(app.traversal.safety("player"),"Cancel keeps the admitted crossing as movement-only safety transit.")
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=10.0
	check_read_only("Pending mid-stair accident")
	app.household.set_speed(0)
	check(app.save_game("","Pending stair accident - "+str(down)+" - "+str(cancel)),"The public named save captures capped urgency during actual stair transit.")
	var saved_slot:String=app.active_save_id;var decoded:Dictionary=LifeSaveLibrary.read_slot(saved_slot).data
	app.load_game(saved_slot)
	check(app.household.sanitation.puddles.is_empty() and app.sim.bladder_grace==10.0 and app.household.speed==0,"Same-process physical reconstruction preserves the pending accident without firing it.")
	check(int(route().identity)==identity and int(route().ticket)==ticket and str(route().phase)=="transit" and float(route().distance)==float(decoded.journeys.members.player.motion.distance),"Pending same-process load restores exact decoded stair progress, identity and FIFO ticket.")
	if cancel:
		var file:=FileAccess.open("user://sanitation_pending_expected.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"slot":saved_slot,"data":decoded},"  ",true,true));file.close()
	app.household.set_speed(1)
	var no_stair_puddle:bool=true;var identity_kept:bool=true
	for index:int in 1800:
		if not app.traversal.busy("player"):break
		app._process(.05)
		no_stair_puddle=no_stair_puddle and app.household.sanitation.puddles.is_empty()
		if app.traversal.busy("player"):identity_kept=identity_kept and int(route().identity)==identity and int(route().ticket)==ticket
	check(no_stair_puddle and identity_kept,"Urgency emits no stair mess and preserves the admitted route and FIFO ticket through safe clearance.")
	check(not app.traversal.busy("player") and app.world.point_level(app.player.position)==(0 if down else 1),"The Lifelet reaches a supported destination landing before the accident.")
	var at:Vector3=app.player.position
	app._process(.05)
	check(app.household.sanitation.puddles.size()==1,"The first supported Live tick resolves the pending accident once.")
	if not app.household.sanitation.puddles.is_empty():
		var value:Dictionary=app.household.sanitation.puddles[0]
		check(Vector3(value.position[0],value.position[1],value.position[2]).distance_to(at)<.00001 and int(value.level)==(0 if down else 1),"The accident retains the actual clear landing position and explicit floor.")
	step(2.0);check(app.household.sanitation.puddles.size()==1,"Post-landing time does not repeat the resolved zero crossing.")
func stacked_floors()->void:
	setup_levels();walk_to(Vector3(2,3.16,3.5));app.world.set_view_level(0)
	for member:Dictionary in app.household.members:member.sim.needs.bladder=0.0;member.sim.bladder_grace=10.0
	app._process(.05)
	check(app.household.sanitation.puddles.size()==2,"A culled upper Lifelet and a present lower Lifelet retain independent accidents.")
	for value:Dictionary in app.household.sanitation.puddles:
		var item:Dictionary=app._find_item(value.id);var level:int=int(value.level)
		check(item.node.get_child(0).layers==(LifeWorld.VIEW_GROUND if level==0 else LifeWorld.VIEW_UPPER),"Wet-patch geometry belongs only to its own storey.")
		check(item.node.get_node("PuddlePicking").collision_layer==(LifeWorld.PICK_GROUND if level==0 else LifeWorld.PICK_UPPER),"Wet-patch picking belongs only to its own storey.")
		var at:Vector3=Vector3(value.position[0],value.position[1],value.position[2])
		check(absf(item.node.position.y-(app.meal_flow._floor_height(at)+.004))<.00001,"Wet patch rests just above the measured supporting slab.")
		level_facts.append({"value":value.duplicate(true),"mesh_y":item.node.position.y,"mask":item.node.get_node("PuddlePicking").collision_layer})
	check_read_only("Puddles on both floors")
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	pending_crossing();pending_crossing(true);pending_crossing(false,true);stacked_floors()
	var report:Dictionary={"checks":checks,"failures":failures,"floors":level_facts}
	var file:=FileAccess.open("user://sanitation_levels.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("Sanitation levels: %d checks, %d failures."%[checks,failures.size()])
	app.queue_free();await frames(5);await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
