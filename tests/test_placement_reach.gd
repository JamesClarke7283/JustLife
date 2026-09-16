extends SceneTree
## A furnishing may not seal a doorway. On the furnished starter cottage the
## treadmill beside the bedroom door is refused with a reason, a spot along the
## east wall is accepted, and after a wall is painted (which converts the home
## to room-aware navigation) the bedroom and bathroom stay reachable. Headless.
var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0;app.start_household();await process_frame
	app.set_process(false)
	var world=app.world
	app.household.set_funds(app.sim.funds+9000)
	app.set_build_mode(true)
	for entry:Array in [["toybox",-1.7,1.2,0],["piano",-1.7,-1.4,0],["bathtub",2.4,-2.6,0],["stereo",-5.5,-2.5,90],["yoga_mat",-1.6,3.3,0],["mirror",-5.5,-1.0,90],["armchair",-1.4,3.2,0]]:
		app.on_placement(str(entry[0]),Vector3(float(entry[1]),0.16,float(entry[2])),float(entry[3]))
	var before:int=world.items.size()
	var blocked:Array=world.serialize_items();blocked.append({"id":"probe","kind":"treadmill","x":2.3,"z":-0.5,"rotation":90.0})
	var reason:String=app.build_transactions.furnishing_error(blocked)
	check(reason.begins_with("That would block the way"),"A treadmill beside the bedroom doorway is refused with a reason: '"+reason+"'")
	check(world.placement_reach_check.is_valid() and not bool(world.placement_reach_check.call("treadmill",Vector3(2.3,0.16,-0.5),90.0)),"The placement preview applies the same rule, so the ghost is red where the click refuses.")
	var state:Dictionary=app.build_transactions.current().state
	var fresh_total:int=0
	for i:int in range(6):
		var fresh:Array=world.serialize_items();fresh.append({"id":"probe","kind":"treadmill","x":2.3+i*.25,"z":-0.75,"rotation":90.0})
		var started:int=Time.get_ticks_msec();app.build_transactions._reach_error(state,fresh);fresh_total+=Time.get_ticks_msec()-started
	var started_again:int=Time.get_ticks_msec()
	for i:int in range(5):app.build_transactions._reach_error(state,blocked)
	var repeat_ms:float=float(Time.get_ticks_msec()-started_again)/5.0
	check(repeat_ms<5.0 and fresh_total/6<80,"The reach rule answers a hovering ghost fast: %d ms per new spot on the live graph, %.1f ms from the cache." % [fresh_total/6,repeat_ms])
	app.on_placement("treadmill",Vector3(2.3,0.16,-0.5),90.0)
	check(world.items.size()==before,"The public purchase path refuses the doorway treadmill.")
	# A spot the validator accepts. The previous east-wall coordinate is now taken
	# by the starter wardrobe and the corridor reserved to reach it, so the
	# validator refuses a treadmill there for a different and correct reason.
	var clear:Array=world.serialize_items();clear.append({"id":"probe","kind":"treadmill","x":-3.5,"z":0.0,"rotation":90.0})
	check(app.build_transactions.furnishing_error(clear).is_empty(),"A treadmill on open floor keeps every doorway open.")
	app.on_placement("treadmill",Vector3(-3.5,0.16,0.0),90.0)
	check(world.items.size()==before+1,"The public purchase path accepts the treadmill on open floor.")
	var bed:Dictionary=world.closest_item("bed",Vector3(3.5,.16,1.5));var toilet:Dictionary=world.closest_item("toilet",Vector3(2.35,.16,-4.1));var treadmill:Dictionary=world.closest_item("treadmill",Vector3(-3.5,.16,0.0))
	var living:Vector3=Vector3(-2.0,.16,-2.5)
	check(not world.path_to(living,world.approach(bed)).is_empty() and not world.path_to(living,world.approach(toilet)).is_empty(),"On the legacy grid the bedroom and bathroom are reachable from the living room.")
	# Painting one wall converts the home to room-aware navigation; nothing may be lost.
	app.set_build_level(0)
	var tx=app.build_transactions
	var wall:Dictionary=world.construction.building_state.walls[0]
	var paint:Dictionary=tx.commit(tx.prepare({"op":"structure","tool":"paint","level":0,"id":str(wall.id),"material":"8faf9f" if str(wall.material)!="8faf9f" else "e6d8c5"}))
	check(bool(paint.ok),"A wall is painted, converting the starter home to canonical rooms.")
	for pair:Array in [["bed",bed],["toilet",toilet],["treadmill",treadmill]]:
		var route:Dictionary=world.route_to(living,world.approach(pair[1]))
		check(bool(route.ok),"After the conversion the %s is still reachable from the living room (%s)." % [str(pair[0]),str(route.get("error",""))])
	app.queue_free()
	await process_frame;await process_frame;await process_frame
	print("PLACEMENT_REACH %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
