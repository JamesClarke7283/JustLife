extends SceneTree
## Lot exits and return spots stay in the open: a garden room built across the
## front lawn must not capture a departure slot inside it, and every slot keeps
## a walkable path to the front door. Headless; real World, construction and
## build transactions on the furnished starter cottage.
var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func _initialize()->void:_run.call_deferred()
func _inside_room(world,p:Vector3)->bool:return world.construction.floor_contains(Vector2(p.x,p.z),0)
func _slots(world)->Dictionary:
	var exits:Array=[];var returns:Array=[]
	for i in range(8):exits.append(world.lot_exit_position(i));returns.append(world.lot_return_position(i))
	return {"exits":exits,"returns":returns}
func _run()->void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0
	app.start_household()
	await process_frame
	app.set_process(false)
	app.set_build_mode(true);app.set_build_level(0)
	var world=app.world
	var before:Dictionary=_slots(world)
	check(before.exits.all(func(p:Vector3)->bool:return not _inside_room(world,p) and absf(p.z-8.5)<.01),"Without a garden room all eight exit slots sit on the sidewalk outside the house.")
	check(before.returns.all(func(p:Vector3)->bool:return not _inside_room(world,p)),"Without a garden room all eight return spots are outdoors.")
	var tx=app.build_transactions
	for annex:Dictionary in [{"ax":2.6,"az":5.8,"bx":5.6,"bz":8.8,"door":7.3},{"ax":2.6,"az":5.8,"bx":6.6,"bz":8.8,"door":6.6}]:
		var room:Dictionary=tx.commit(tx.prepare({"op":"structure","tool":"room","level":0,"ax":annex.ax,"az":annex.az,"bx":annex.bx,"bz":annex.bz}))
		check(bool(room.ok),"A garden room to x=%.1f is built through the public build transaction." % float(annex.bx))
		var door_wall:Dictionary={}
		for wall:Dictionary in world.construction.building_state.walls:
			if is_equal_approx(float(wall.x),float(annex.ax)) and is_equal_approx(float(wall.z),(float(annex.az)+float(annex.bz))*.5):door_wall=wall
		var door:Dictionary=tx.commit(tx.prepare({"op":"structure","tool":"door","level":0,"id":str(door_wall.get("id","")),"center":float(annex.door)}))
		check(bool(door.ok),"The garden room gets a west doorway.")
		var after:Dictionary=_slots(world)
		var captured:Array=after.exits.filter(func(p:Vector3)->bool:return _inside_room(world,p))+after.returns.filter(func(p:Vector3)->bool:return _inside_room(world,p))
		check(captured.is_empty(),"No exit or return slot lands inside the garden room to x=%.1f (captured %s)." % [float(annex.bx),str(captured)])
		check(after.exits.all(func(p:Vector3)->bool:return not world.navigation.is_point_solid(Vector2i(roundi(p.x*4),roundi(p.z*4)))),"Every exit slot is a free cell with the garden room to x=%.1f." % float(annex.bx))
		var reachable:int=0
		for p:Vector3 in after.exits+after.returns:
			if not world.path_to(p,Vector3(0,.16,5.5)).is_empty():reachable+=1
		check(reachable==16,"All sixteen slots keep a walkable path to the front door with the garden room to x=%.1f (%d of 16)." % [float(annex.bx),reachable])
		check(bool(tx.undo(door.receipt).ok) and bool(tx.undo(room.receipt).ok),"The garden room undoes cleanly.")
	check(_slots(world).exits==before.exits and _slots(world).returns==before.returns,"After the undo the slots return to their sidewalk positions.")
	app.queue_free()
	await process_frame;await process_frame;await process_frame
	print("LOT_EXITS %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
