extends "res://tests/test_adoption_journeys.gd"
var phase:String=OS.get_environment("ADOPTION_JOURNEY_STAGE")
var receipt:Dictionary={}

func _same(a:Variant,b:Variant)->bool:
	return _equal_value(LifeSaveLibrary._json_safe(a),LifeSaveLibrary._json_safe(b))

func _equal_value(a:Variant,b:Variant)->bool:
	# Exact numeric values can have different int/float JSON representations.
	# Compare recursively without serializing internal INF route sentinels.
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	if typeof(a)!=typeof(b):return false
	if a is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not _equal_value(a[key],b[key]):return false
		return true
	if a is Array:
		if a.size()!=b.size():return false
		for index:int in a.size():
			if not _equal_value(a[index],b[index]):return false
		return true
	return a==b

func _phone_confirm()->void:
	app.adoption_flow.show_phone();app.overlay.get_node("PhoneAdoptChild").pressed.emit()
	app.overlay.get_node("AdoptionCandidate_0").pressed.emit()
	app.overlay.get_node("AdoptionConfirm").pressed.emit()

func _provider_facts()->Dictionary:
	var queues:Array=[];var states:Array=[]
	for member:Dictionary in app.household.members:
		queues.append(member.sim.action_queue.duplicate(true));states.append(member.sim.character.get("world_state",{}).duplicate(true))
	return {"routes":app.traversal.routes.duplicate(true),"locks":app.traversal.stairs.duplicate(true),"motion":app.motion_states.duplicate(true),"bound":app.bound_member_id,"queues":queues,"world_state":states,"cached":app.household.journeys.duplicate(true),"ledger":app.household.meals.get_state(),"minutes":app.household.minutes,"elapsed":app.elapsed}

func _paused_facts(value:Dictionary)->Dictionary:
	var result:Dictionary=value.duplicate(true)
	# The normal presentation clock continues while paused. An idle member's
	# first frame also records the absent traversal cache as an empty dictionary.
	# Neither is simulation/action/journey advancement.
	result.erase("elapsed")
	for motion:Dictionary in result.motion.values():
		if not motion.has("traversal"):motion.traversal={}
	return result

func _producer()->void:
	_setup(3)
	app.loading_game=true
	app.setup_live([{"id":"ground_oven","kind":"stove","x":-2.0,"z":-3.0,"rotation":0.0},{"id":"upper_table","kind":"dining","x":2.0,"z":0.0,"rotation":0.0,"level":1},{"id":"ground_shelf","kind":"bookshelf","x":-3.25,"z":0.0,"rotation":0.0},fixture()])
	app.loading_game=false
	app.world.actors.player.position=Vector3(-2,.16,-4);app.world.actors.housemate_1.position=Vector3(2,3.16,4);app.world.actors.housemate_2.position=Vector3(-2,.16,-2)
	app.select_household_member(2);app.sim.skills.cooking.level=5
	var money:int=app.household.funds
	app.meal_flow.queue_recipe("ground_oven","harvest_bake")
	var cooking:bool=false
	for frame:int in 1200:
		_step()
		var action:Dictionary=app.sim.get_current_action()
		if str(action.get("id",""))=="cook" and bool(action.paid) and float(action.elapsed)>8:cooking=true;break
	check(cooking and app.household.funds==money-52,"Explicit skill-unlock fixture actually approaches its oven and pays exactly§52 for a progressing bake.")
	if not cooking:return
	app.household.set_speed(0);app.overlay_open=true
	check(app.save_game("","Before household expansion"),"Named positive save includes the actual paid oven before the later adoption.")
	var positive:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(positive.ok) and int(positive.data.household_version)==2,"Paid-oven positive V2 save passes the root5452 validation overlay.")
	if not bool(positive.ok):return
	app.overlay_open=false;app.select_household_member(0)
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet","player",2,"home",app.meal_flow.now())
	check(not batch.is_empty(),"Second serving dish is an explicit ledger API fixture; its cooking is not claimed.")
	app.meal_flow.sync_world();app._refresh_sim_targets(false)
	app.household.set_speed(1);app.sim.queue_action("serve_meal",str(batch.id))
	check(_until_transit("player"),"Actual serving instruction carries that dish onto the stairs while the other adult bakes.")
	if str(_route("player").get("phase",""))!="transit":return
	app.queue_interaction(app._find_item("ground_shelf"),"read");app.cancel_current_action()
	check(app.traversal.safety("player") and str(_route("player").custody)==str(batch.id),"Actual cancellation retains the original carried food under stair custody and defers later reading.")
	app.household.set_speed(0)
	var facts:Dictionary=_provider_facts();var snapshot:Dictionary=app._physical_snapshot_context()
	check(_same(_provider_facts(),facts),"Capturing live physical facts changes no bindings, movement cache, queues, cached journeys, ledger or clocks.")
	check(snapshot.journeys.members.player.motion.custody==str(batch.id) and snapshot.members.player.waiting_action_id=="read","Detached snapshot uses live custody and current later-action identity instead of the prior save.")
	var current:Dictionary=app.sim.get_current_action();var baker:LifeSim=app.household.member_sim("housemate_2");var bake:Dictionary=baker.get_current_action()
	var identity:int=int(_route("player").identity);var funds:int=app.household.funds
	_phone_confirm()
	check(app.household.members.size()==4 and app.household.funds==funds-1000,"Actual Phone confirmation adds one child and charges once with both owned transit and paid baking present.")
	if app.household.members.size()!=4:
		print("ADOPTION_CUSTODY_REJECTION ",app.notice_label.text);return
	check(is_same(current,app.household.member_sim("player").get_current_action()) and is_same(bake,baker.get_current_action()) and _same(app.household.meals.get_state(),facts.ledger),"Successful household expansion preserves exact current read/bake dictionaries and the whole paid-food ledger.")
	check(_same(app.traversal.routes.player,facts.routes.player) and app.traversal.stairs==facts.locks and int(_route("player").identity)==identity,"Existing owner route, gait distance, safety, food custody and FIFO locks remain exact.")
	var child:LifeSim=app.household.member_sim("housemate_3");child.autonomy=false
	var new_journey:Dictionary=app.traversal.snapshot().members.housemate_3
	check(str(new_journey.motion.intent.id)=="arrive_home" and str(new_journey.motion.phase)=="route" and new_journey.position==child.character.world_state.player,"New physical child and actual arrival journey agree at their real street spawn.")
	app.household.set_speed(0);app.overlay_open=true
	check(app.save_game("","Adopted during food custody"),"Actual main writes all four members, paid oven, canceled dish custody and new child arrival to a named V2 save.")
	var read:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(read.ok),"Named post-adoption save passes full family, journey, paid action and food ownership validation: "+str(read.get("error","valid")))
	if not bool(read.ok):return
	receipt={"slot":app.active_save_id,"state":read.data,"journeys":app.traversal.snapshot(),"ledger":app.household.meals.get_state(),"funds":app.household.funds,"minutes":app.household.minutes,"batch_id":str(batch.id),"arrival_position":new_journey.position,"scope":"Actual paid bake, API-created separate carried serving dish, actual canceled stair transit and Phone Button callbacks; separate fresh process restore."}
	var f:=FileAccess.open("user://adoption_custody_expected.json",FileAccess.WRITE);f.store_string(JSON.stringify(LifeSaveLibrary._json_safe(receipt),"  ",true,true));f.close()

func _consumer()->void:
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://adoption_custody_expected.json"))
	check(parsed is Dictionary,"Fresh process reads the original producer's actual named-save receipt.")
	if not parsed is Dictionary:return
	receipt=parsed
	app.load_game(str(receipt.slot));app.set_process(false)
	check(app.household.members.size()==4 and app.active_save_id==str(receipt.slot),"Fresh main loads the four-member V2 adoption save through staged world restoration.")
	if app.household.members.size()!=4:return
	check(_same(app.traversal.snapshot(),receipt.journeys) and _same(app.household.meals.get_state(),receipt.ledger),"Fresh restore retains exact owner/FIFO/child-arrival facts and all original paid food.")
	check(app.household.speed==0 and app.household.funds==int(receipt.funds) and app.household.minutes==float(receipt.minutes),"Fresh adoption save keeps exact pause, wallet and clock.")
	check(app.household.physical_snapshot_provider.get_object()==app,"Staged adoption rebinds the physical provider to the surviving actual app, not the retired candidate.")
	var facts:Dictionary=_provider_facts();var provider:Dictionary=app._physical_snapshot_context()
	check(_same(_provider_facts(),facts) and _same(provider.journeys,receipt.journeys),"Fresh paused capture remains detached and does not alter restored state.")
	_step(20)
	check(_same(_paused_facts(_provider_facts()),_paused_facts(facts)),"Twenty paused actual controller frames preserve paid cooking, custody and new arrival without advancement.")
	var child:LifeSim=app.household.member_sim("housemate_3");child.autonomy=false
	var batch:Dictionary=app.household.meals.batch(str(receipt.batch_id))
	app.household.set_speed(1)
	var arrived:bool=false;var cleared:bool=false
	for frame:int in 2200:
		_step()
		arrived=child.get_current_action().is_empty();cleared=not app.traversal.safety("player")
		if arrived and cleared:break
	check(arrived and app.world.actors.housemate_3.position.distance_to(LifeJourneyState.vector(receipt.arrival_position))>.5,"Fresh-process child actually walks away from its saved street spawn and completes arrival.")
	check(cleared and str(batch.owner).is_empty() and str(batch.storage)=="surface" and int(batch.remaining)==4,"Original canceled serving dish reaches its real landing and is set down once after fresh restore.")
	check(app.household.adoptions.events.size()==1 and app.household.funds==int(receipt.funds),"Resumed arrival and stair clearance cannot repeat adoption or either payment.")
	# Direct snapshot immediately after a UI movement command, before _process
	# stores that bound member's new walk fields, exercises the stale-cache edge.
	app.select_household_member(3);app.on_ground_clicked(app.world.actors.housemate_3.position+Vector3(1,0,0))
	var instant:Dictionary=app._physical_snapshot_context()
	check(instant.journeys.members.housemate_3.motion.intent.kind=="walk" and instant.journeys.members.housemate_3.motion.intent.destination==LifeJourneyState.packed(app.walk_destination),"Immediate pre-frame UI walk snapshot reads live bound intent rather than the previous stored movement.")
	var detached:Dictionary=app.household.get_state(app.world.serialize_items());var verifier:=LifeHousehold.new();var checked:Dictionary=verifier.restore_state(detached);verifier.free()
	check(bool(checked.ok),"Ordinary get_state after further live movement remains a valid fresh physical household snapshot: "+str(checked.get("error","valid")))
	var missing:LifeActor=app.world.actors.housemate_3;app.world.actors.erase("housemate_3")
	var broken:Dictionary=app.household.get_state(app.world.serialize_items());app.world.actors.housemate_3=missing
	var rejector:=LifeHousehold.new();var rejected:Dictionary=rejector.restore_state(broken);rejector.free()
	check(broken.has("snapshot_error") and not bool(rejected.ok),"Missing live actor fails closed instead of silently reusing stale cached journeys.")

func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	if phase=="produce":_producer()
	else:_consumer()
	var result:Dictionary={"phase":phase,"checks":checks,"failures":failures,"process_id":OS.get_process_id(),"receipt_slot":receipt.get("slot","")}
	var f:=FileAccess.open("user://adoption_custody_"+phase+".json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	print("ADOPTION_JOURNEY_CUSTODY ",JSON.stringify(result))
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
