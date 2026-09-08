extends "res://tests/test_sanitation_levels.gd"
## Restore validates real targets without repeating the initial desperation gate.
var rejected:Array=[]
func reject(data:Dictionary,label:String)->void:
	var before:Dictionary=facts();var world:Node=app.world;var flow:Node=app.sanitation_flow;var household:Node=app.household
	var prepared:Dictionary=app._prepare_loaded_world(data)
	var accepted:bool=bool(prepared.ok)
	check(not accepted,label+" is rejected before adoption.")
	if accepted:prepared.viewport.free();prepared.candidate.free()
	check(app.world==world and app.sanitation_flow==flow and app.household==household and facts()==before,label+" preserves exact live state and service ownership.")
	rejected.append({"case":label,"accepted":accepted,"error":str(prepared.get("error",""))})
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	setup_levels();app.world.add_item({"id":"second_upper_plant","kind":"plant","x":-2.0,"z":-2.0,"rotation":0.0,"level":1});app._refresh_sim_targets(false);app.sim.needs.bladder=8.0
	app.queue_interaction(app._find_item("upper_plant"),"plant_wee")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active",200.0),"A real desperate Lifelet walks upstairs and starts using the actual pot.")
	step(2.0);app.household.set_speed(0)
	check(app.sim.needs.bladder>LifeSim.BLADDER_DESPERATE and float(app.sim.get_current_action().elapsed)>0.0,"The legitimate saved pot action has already relieved bladder above the initial threshold.")
	check(app.save_game("","Partly relieved upper pot"),"The actual partly relieved action writes a physical named save.")
	var slot:String=app.active_save_id;var read:Dictionary=LifeSaveLibrary.read_slot(slot)
	check(bool(read.ok),"The exact legitimate pot save is readable.")
	var original:Dictionary=read.data;var expected:Dictionary=original.members[0].state.action_queue[0]
	for target:String in ["ground_shelf","missing_plant","second_upper_plant"]:
		var damaged:Dictionary=original.duplicate(true)
		damaged.members[0].state.action_queue[0].target_id=target
		damaged.members[0].state.character.world_state.waiting_target_id=target
		reject(damaged,"Saved pot target "+target)
	app.load_game(slot)
	check(str(app.sim.get_current_action().get("id",""))=="plant_wee" and float(app.sim.get_current_action().elapsed)==float(expected.elapsed) and app.sim.needs.bladder>LifeSim.BLADDER_DESPERATE,"Valid progressed pot load retains exact decoded progress despite partial relief.")
	check(app.sim.sanitation_service==app.sanitation_flow and app.world.point_level(app.player.position)==1,"The restored current-lot pot uses the adopted flow and real upper floor.")
	var bladder:float=app.sim.needs.bladder;app.household.set_speed(1);step(.5)
	check(app.sim.needs.bladder>bladder,"The valid partly relieved action continues its earned relief.")
	check(until(func()->bool:return app.sim.get_current_action().is_empty(),30.0),"The resumed real pot action completes normally.")
	check(app.household.sanitation.puddles.is_empty(),"Valid pot continuation emits no accidental or remote floor mess.")
	check(LifeSaveLibrary.read_slot(slot).data==original,"All malformed-memory probes preserve the exact original named save.")
	var file:=FileAccess.open("user://sanitation_restore_targets.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rejected":rejected},"  ",true,true));file.close()
	print("Sanitation restore: %d checks, %d failures."%[checks,failures.size()])
	app.queue_free();await frames(5);await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
