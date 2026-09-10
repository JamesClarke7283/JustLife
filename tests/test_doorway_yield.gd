extends SceneTree
## Two Lifelets and a one-door room whose fridge stands just inside the door:
## an idle body on the use point steps aside for a walker, and a walker and a
## strolling Lifelet meeting head-on in the doorway both get through. Headless;
## real World, LifeSim, traversal and construction; no needs or clock edits.
var checks:int=0
var failures:Array[String]=[]
var app
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func _initialize()->void:_run.call_deferred()
func _drive(frames:int,until:Callable)->int:
	for i:int in range(frames):
		app._process(.05)
		if until.call():return i
	return -1
func _current(id:String)->Dictionary:return app.household.member_sim(id).get_current_action()
func _queue_for(id:String,item:Dictionary,action:String)->void:
	var prior:String=app.bound_member_id
	app._store_motion();app._bind_member(id)
	app.queue_interaction(item,action)
	app._store_motion();app._bind_member(prior)
func _stroll(id:String,destination:Vector3)->bool:
	var prior:String=app.bound_member_id
	app._store_motion();app._bind_member(id)
	var ok:bool=app._set_route(destination)
	app.walk_only=ok;app.walk_destination=destination
	app._store_motion();app._bind_member(prior)
	return ok
func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	var second:Dictionary=app.profile.duplicate(true);second.name="Rowan Vale";app.household_profiles.append(second)
	app.selected_lot=2
	app.start_household()
	await process_frame
	app.set_process(false)
	app.set_build_mode(true);app.set_build_level(0)
	var tx=app.build_transactions
	var room:Dictionary=tx.commit(tx.prepare({"op":"structure","tool":"room","level":0,"ax":-5.5,"az":-1.0,"bx":-2.5,"bz":2.0}))
	check(bool(room.ok),"A three-by-three room is built in the empty home: "+str(room.get("error","")))
	var east:Dictionary={}
	for wall:Dictionary in app.world.construction.building_state.walls:
		if is_equal_approx(float(wall.x),-2.5) and is_equal_approx(float(wall.z),0.5):east=wall
	var door:Dictionary=tx.commit(tx.prepare({"op":"structure","tool":"door","level":0,"id":str(east.get("id","")),"center":0.5}))
	check(bool(door.ok),"Its east wall gets a single doorway: "+str(door.get("error","")))
	app.household.set_funds(app.sim.funds+3000)
	var spawn:float=0.0
	for member:Dictionary in app.household.members:app.world.actors[str(member.id)].position=Vector3(spawn,.16,-2.5);spawn+=1.0
	var before:int=app.world.items.size()
	for spot:Array in [["fridge",-3.1,-0.35,0.0],["sofa",-1.0,3.5,0.0]]:
		var p:Vector3=Vector3(float(spot[1]),0.16,float(spot[2]))
		var proposed:Array=app.world.serialize_items();proposed.append({"id":"probe","kind":str(spot[0]),"x":p.x,"z":p.z,"rotation":float(spot[3])})
		print("PLACE ",spot[0]," can_place=",app.world.can_place(str(spot[0]),p,float(spot[3]))," error='",app.build_transactions.furnishing_error(proposed),"'")
		app.on_placement(str(spot[0]),p,float(spot[3]))
	var fridge:Dictionary=app.world.closest_item("fridge",Vector3(-3.1,0.16,-0.35))
	var sofa:Dictionary=app.world.closest_item("sofa",Vector3(-1.0,0.16,3.5))
	check(app.world.items.size()==before+2 and not fridge.is_empty() and fridge.node.position.x<-2.6 and not sofa.is_empty(),"A fridge stands just inside the doorway and a sofa outside (placed %d)." % [app.world.items.size()-before])
	if sofa.is_empty() or fridge.is_empty():print("DOORWAY_YIELD %d checks, %d failures" % [checks,failures.size()+1]);quit(1);return
	app.set_build_mode(false)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.household.set_speed(3)
	var ids:Array=[]
	for member:Dictionary in app.household.members:ids.append(str(member.id))
	var walker:String=ids[0];var idler:String=ids[1]
	var use_point:Vector3=app.world.approach(fridge)
	print("USE_POINT ",use_point)
	var t=app.traversal
	# Case 1: an idle Lifelet stands on the fridge's use point, a body's width
	# inside the doorway; the other walks in from outside for a snack.
	app.world.actors[idler].position=use_point
	app.world.actors[walker].position=Vector3(-0.5,.16,0.5)
	_queue_for(walker,fridge,"snack")
	check(str(_current(walker).get("id",""))=="snack","The walker queues a snack at the room's fridge.")
	var made_way:bool=false;var standoff_seen:bool=false
	var arrived:int=_drive(1200,func()->bool:
		if t.has_method("making_way") and t.making_way(idler):made_way=true
		if t.has_method("standing_off") and t.standing_off(walker):standoff_seen=true
		return str(_current(walker).get("phase",""))=="active")
	check(arrived>=0,"The walker starts the snack within sixty seconds of walking (frame %d)." % arrived)
	check(app.world.actors[idler].position.distance_to(use_point)>=.4,"The idle Lifelet left the use point (%.2f m away)." % app.world.actors[idler].position.distance_to(use_point))
	check(app.world.actors[idler].position.x<-2.6,"The idle Lifelet stepped aside inside the room rather than through the walker.")
	print("CASE1 arrived_frame=%d made_way=%s standoff=%s idler=%s walker=%s" % [arrived,str(made_way),str(standoff_seen),str(app.world.actors[idler].position),str(app.world.actors[walker].position)])
	# Case 2: head-on in the doorway: the idle Lifelet strolls out from beside
	# the fridge to the garden side while the walker comes in for a snack.
	app.household.member_sim(walker).cancel_action();app.household.member_sim(idler).cancel_action()
	app._process(.05)
	app.world.actors[idler].position=Vector3(-3.25,.16,1.0)
	app.world.actors[walker].position=Vector3(-1.25,.16,0.5)
	check(_stroll(idler,Vector3(1.5,.16,0.5)),"The idle Lifelet starts a stroll out through the doorway.")
	_queue_for(walker,fridge,"snack")
	check(str(_current(walker).get("id",""))=="snack","The walker queues a snack through the same doorway.")
	var yielded:Array=[]
	var both:int=_drive(2400,func()->bool:
		for id:String in [walker,idler]:
			if t.has_method("standing_off") and t.standing_off(id) and not yielded.has(id):yielded.append(id)
		return str(_current(walker).get("phase",""))=="active" and app.world.actors[idler].position.distance_to(Vector3(1.5,.16,0.5))<.3)
	check(both>=0,"The walker reaches the fridge and the stroller reaches the garden side through the one doorway (frame %d)." % both)
	print("CASE2 both_frame=%d yielded=%s walker=%s idler=%s" % [both,str(yielded),str(app.world.actors[walker].position),str(app.world.actors[idler].position)])
	print("DOORWAY_YIELD %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
