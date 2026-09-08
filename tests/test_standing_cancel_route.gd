extends "res://tests/test_standing_dining.gd"
## Controlled no-standing-space branch using visible blocker proxies; not a
## supported household-size or rendered collision test. Navigation stays real.
func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var f:Dictionary=_group();var prior:Dictionary=_pickup("player",f)
	var sim:LifeSim=app.household.member_sim("player");var shelf:Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	check(sim.queue_action("read",str(shelf.id),app.world.approach(shelf)),"A later explicit reading instruction is queued behind the actual held meal.")
	var later:Dictionary=sim.action_queue[1];var origin:Vector3=app.world.actors.player.position
	for x:int in range(-6,7):
		for z:int in range(-6,7):
			var proxy:=Node3D.new();app.world.add_child(proxy);proxy.position=origin+Vector3(x*.5,0,z*.5)
			app.world.actors["crowd_proxy_%d_%d"%[x,z]]=proxy
	check(not app.meal_flow._standing_slot("player").is_finite(),"Visible crowd proxies reject every body-clear destination in the bounded search.")
	app._bind_member("player");app.on_action_started(prior)
	check(is_same(sim.get_current_action(),later) and str(later.id)=="read" and not bool(later.autonomous),"The no-space cancellation preserves the exact later player instruction.")
	check(str(app.household.meals.portion(str(prior.meal_plate)).owner).is_empty(),"The canceled meal releases its one matching plate.")
	check(int(f.batch.served)==1 and int(f.batch.remaining)==3 and float(app.household.meals.portion(str(prior.meal_plate)).progress)==0,"No-space cancellation preserves one portion and grants no fabricated nutrition or extra claim.")
	check(is_same(app.pending_action,later),"The outer canceled meal callback cannot replace the later reading motion.")
	check(not app.path.is_empty() and app.path[-1].is_equal_approx(later.target_position),"Remaining movement really ends at the later instruction’s target.")
	var report:Dictionary={"checks":checks,"failures":failures,"current":sim._json_safe(sim.get_current_action()),"pending":sim._json_safe(app.pending_action),"path":sim._json_safe(app.path)}
	var file:=FileAccess.open("user://standing_cancel_route.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CANCEL_ROUTE ",checks," checks ",failures.size()," failures");app.queue_free();await process_frame;await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
