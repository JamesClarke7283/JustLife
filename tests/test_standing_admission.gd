extends "res://tests/test_standing_dining.gd"
## A later nap waits while its own arrival point intrudes on an existing standing
## diner, and is admitted the moment that reservation is released.
##
## The couch is genuinely shared seating, so a nap on it claims one of its places
## and arrives at that cushion's own approach rather than the furnishing's centre
## — and a place whose arrival the diner cannot reach is genuinely free, which is
## correct sharing rather than a hole in the rule. The fixture therefore asks the
## production rule itself which of the couch's places a diner can really intrude
## on, reserves the diner there, and asserts the nap waits on that place and is
## admitted the instant the diner gives it up.
func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var f:Dictionary=_group();var action:Dictionary=_pickup("player",f)
	var sofa:Dictionary=app.world.closest_item("sofa",Vector3.ZERO)
	var incoming:LifeSim=app.household.member_sim("housemate_1")
	check(incoming.queue_action("nap",str(sofa.id),app.world.approach(sofa)),"Later explicit nap uses the real sofa and approach.")
	var queued:Dictionary=incoming.get_current_action()
	check(app.world.seat_capacity(sofa)>1,"The sofa is shared seating with more than one place (%d)." % app.world.seat_capacity(sofa))
	# Ask the production rule which place a diner can genuinely intrude on.
	var reserved:Vector3=Vector3.INF
	var chosen_slot:String=""
	for slot:String in app.world.seat_slots(sofa):
		var arrival:Vector3=app.world.slot_approach(sofa,slot)
		var probe:Dictionary=queued.duplicate(true)
		probe["seat_slot"]=slot
		probe["target_position"]=arrival
		for x:int in range(-8,9):
			for z:int in range(-8,9):
				var point:=Vector3(arrival.x+float(x)*.25,0.16,arrival.z+float(z)*.25)
				if not app.meal_flow._standing_route("player",point):continue
				action.target_position=point
				app.world.actors.player.position=point
				if app.meal_flow.standing_place_blocks("housemate_1",probe):
					reserved=point;chosen_slot=slot;break
			if reserved.is_finite():break
		if reserved.is_finite():break
	check(reserved.is_finite(),"A diner can really stand where one of the sofa's places is claimed.")
	if not reserved.is_finite():
		await _release_fixture()
		quit(1);return
	# The nap claims exactly the place the diner obstructs.
	queued["seat_slot"]=chosen_slot
	queued["target_position"]=app.world.slot_approach(sofa,chosen_slot)
	app.world.actors.player.position=reserved
	action.target_position=reserved
	app.household.begin_action("player")
	check(str(action.phase)=="active" and bool(action.paid),"The existing standing diner already owns an active paid serving.")
	app._bind_member("housemate_1")
	var admitted:bool=app._activity_available(queued)
	check(not admitted,"Later nap must wait while its arrival point intrudes on the existing standing diner.")
	check(str(queued.phase)=="approach" and not bool(queued.paid),"The later explicit nap remains unpaid and queued for ordinary admission.")
	print("ARRIVAL_PROBE ",JSON.stringify({"admitted":admitted,"standing":sim_position(reserved),"nap_arrival":sim_position(Vector3(queued.get("target_position",Vector3.ZERO))),"gap":Vector3(queued.get("target_position",Vector3.ZERO)).distance_to(reserved),"seat_slot":chosen_slot,"existing":action,"incoming":queued}))
	app.household.member_sim("player").cancel_action()
	check(app._activity_available(queued),"Releasing the standing reservation admits the same later nap.")
	check(is_same(incoming.get_current_action(),queued) and not bool(queued.autonomous),"Admission preserves the exact explicit instruction and its ownership.")
	await _release_fixture()
	var file:=FileAccess.open("user://standing_arrival_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("STANDING_ARRIVAL ",checks," checks ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
func sim_position(value:Vector3)->Array:return [value.x,value.y,value.z]

func _release_fixture() -> void:
	var ambience:WeakRef=weakref(app.ambience_player.stream)
	var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free()
	await process_frame;await process_frame
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:
		await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Fixture teardown releases its ambience stream and backend playback before quitting.")
