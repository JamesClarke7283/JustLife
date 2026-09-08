extends "res://tests/test_standing_dining.gd"
func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var f:Dictionary=_group();var action:Dictionary=_pickup("player",f)
	var sofa:Dictionary=app.world.closest_item("sofa",Vector3.ZERO)
	var approach:Vector3=app.world.approach(sofa)
	var reserved:Vector3=Vector3.INF
	for x:int in range(-3,4):
		for z:int in range(-3,4):
			var point:Vector3=approach+Vector3(x*.25,0,z*.25)
			var gap:float=point.distance_to(approach)
			if gap<.49 or gap>.84 or not app.meal_flow._standing_route("player",point):continue
			var cell_a:=Vector2i(roundi(point.x*2),roundi(point.z*2));var cell_b:=Vector2i(roundi(approach.x*2),roundi(approach.z*2))
			if cell_a==cell_b:continue
			reserved=point;break
		if reserved.is_finite():break
	check(reserved.is_finite(),"Actual sofa has a nearby valid standing endpoint in a distinct resource cell.")
	if reserved.is_finite():
		action.target_position=reserved;app.world.actors.player.position=reserved
		app.household.begin_action("player")
		check(str(action.phase)=="active" and bool(action.paid),"The existing standing diner already owns an active paid serving.")
		var incoming:LifeSim=app.household.member_sim("housemate_1")
		check(incoming.queue_action("nap",str(sofa.id),approach),"Later explicit nap uses the real sofa and approach.")
		app._bind_member("housemate_1")
		var admitted:bool=app._activity_available(incoming.get_current_action())
		check(not admitted,"Later nap must wait while its arrival point intrudes on the existing standing diner.")
		var queued:Dictionary=incoming.get_current_action()
		check(str(queued.phase)=="approach" and not bool(queued.paid),"The later explicit nap remains unpaid and queued for ordinary admission.")
		print("ARRIVAL_PROBE ",JSON.stringify({"admitted":admitted,"standing":sim_position(reserved),"nap_approach":sim_position(approach),"gap":reserved.distance_to(approach),"existing":action,"incoming":incoming.get_current_action()}))
		app.household.member_sim("player").cancel_action()
		check(app._activity_available(queued),"Releasing the standing reservation admits the same later nap.")
		check(is_same(incoming.get_current_action(),queued) and not bool(queued.autonomous),"Admission preserves the exact explicit instruction and its ownership.")
	var file:=FileAccess.open("user://standing_arrival_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("STANDING_ARRIVAL ",checks," checks ",failures.size()," failures");app.queue_free();await process_frame;await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
func sim_position(value:Vector3)->Array:return [value.x,value.y,value.z]
