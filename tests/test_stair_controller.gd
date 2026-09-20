extends "res://tests/test_build_world_levels.gd"
var app:Node
var observations_controller:Array=[]

func _setup(people:int=1,yaw:int=0)->void:
	app.household_profiles=[]
	for index:int in people:app.household_profiles.append({"name":"Stair Walker "+str(index),"age_stage":"child" if index==1 else "young_adult","traits":[],"hair":0})
	app.creator_family_links=[];app.start_household();app.set_process(false)
	app.loading_game=true
	var building:Dictionary=fixture() if yaw==0 else fixture(false)
	if yaw==90:
		var rotated:Dictionary=Building.propose(building,{"op":"add","collection":"stairs","record":{"x":-2.0,"z":-1.0,"rotation":90}},10000)
		check(bool(rotated.ok),"Rotated controller fixture uses a valid supported staircase proposal.")
		if bool(rotated.ok):building=rotated.after
	app.setup_live([{"id":"upper_shelf","kind":"bookshelf","x":3.25,"z":0.0,"rotation":0.0,"level":1},{"id":"ground_shelf","kind":"bookshelf","x":-3.25,"z":0.0,"rotation":0.0},building])
	app.loading_game=false
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false;member.sim.set_aging("normal",false);member.sim.household_bills_enabled=false;member.sim.wants.clear()
		for need:String in LifeSim.NEED_NAMES:member.sim.needs[need]=80
	app.household.set_speed(1)
	app.player.position=Vector3(-2,.16,-3.5)
	if people>1:app.world.actors.housemate_1.position=Vector3(2,3.16,3.5)
	app._store_motion()

func _step(count:int=1,delta:float=.05)->void:
	for i:int in count:app._process(delta)

func _route(id:String)->Dictionary:return app.traversal.routes.get(id,{})

func _until_transit(id:String)->bool:
	for frame:int in 1600:
		_step()
		if str(_route(id).get("phase",""))=="transit" and float(_route(id).distance)>.6:return true
	return false

func _walking()->void:
	for speed:int in [1,3,8]:
		_setup();app.household.set_speed(speed)
		var goal:=Vector3(2,3.16,3.5)
		app.on_ground_clicked(goal)
		check(app.traversal.active("player"),"Public ground click retains a typed upstairs route at speed"+str(speed))
		check(_until_transit("player"),"The real main controller reaches stair gait at speed"+str(speed))
		var pose:Transform3D=app.player.transform;var paused:Dictionary=_route("player").duplicate(true)
		app.household.set_speed(0);_step(20)
		check(app.player.transform==pose and _route("player")==paused,"Paused main loop freezes exact stair position, route distance and owner at speed"+str(speed))
		app.household.set_speed(speed)
		var frames:int=0
		while app.walk_only and frames<1600:_step();frames+=1
		check(not app.walk_only and app.player.position.distance_to(goal)<.001,"Upstairs walk naturally completes at the exact destination at speed"+str(speed))
		check(app.player.stair_presentation.is_empty() and app.traversal.stairs.values().all(func(value:Dictionary)->bool:return str(value.owner).is_empty()),"Finished crossing releases its real exit and stair pose.")
		app.on_ground_clicked(Vector3(-2,.16,-3.5));frames=0
		while app.walk_only and frames<1600:_step();frames+=1
		check(not app.walk_only and app.player.position.distance_to(Vector3(-2,.16,-3.5))<.001,"Real controller descends and returns to the ground at speed"+str(speed))
		observations_controller.append({"speed":speed,"final_position":app.player.position,"route":_route("player")})

func _opposite_fifo()->void:
	_setup(2)
	app.on_ground_clicked(Vector3(2,3.16,4))
	app.select_household_member(1);app.on_ground_clicked(Vector3(-2,.16,-4))
	var admissions:Array[String]=[];var last:String="";var minimum:float=INF;var saw_wait:bool=false
	var tickets:Dictionary={}
	var refreshed:bool=false
	for frame:int in 2200:
		_step()
		for id:String in app.traversal.routes:
			var ticket:int=int(_route(id).ticket)
			if ticket>0 and not tickets.has(id):tickets[id]=ticket
		for lock:Dictionary in app.traversal.stairs.values():
			var owner:String=str(lock.owner)
			if not owner.is_empty() and owner!=last:admissions.append(owner)
			last=owner
			if not lock.queue.is_empty() and not owner.is_empty():saw_wait=true
			if not refreshed and not lock.queue.is_empty() and not owner.is_empty():
				var queue:Array=lock.queue.duplicate(true)
				var id:String=str(queue[0].id);var identity:int=int(_route(id).identity)
				app.world.rebuild_navigation();app._refresh_sim_targets()
				check(lock.queue==queue and int(_route(id).identity)==identity and str(lock.owner)==owner,"Equivalent navigation and target refresh preserve arrived FIFO ticket, identity and crossing owner.")
				refreshed=true
		var first:LifeActor=app.world.actors.player;var second:LifeActor=app.world.actors.housemate_1
		minimum=minf(minimum,first.position.distance_to(second.position))
		if frame>10 and app.traversal.routes.is_empty():break
	check(admissions==["housemate_1","player"] or admissions==["player","housemate_1"],"Opposite adult/child approaches admit exactly one complete crossing each.")
	check(admissions.size()==2 and int(tickets.get(admissions[0],999))<int(tickets.get(admissions[1],0)),"Crossings follow actual arrived-waiter ticket order, independent of selected member.")
	check(saw_wait,"An opposing Lifelet visibly waits while the staircase has an owner.")
	check(refreshed,"The navigation refresh control actually ran with an arrived opposing waiter.")
	check(minimum>=.70,"Opposing walkers retain distinct body locations through stairs and exit clearance.")
	check(app.world.actors.player.position.distance_to(Vector3(2,3.16,4))<.001 and app.world.actors.housemate_1.position.distance_to(Vector3(-2,.16,-4))<.001,"Both opposite-direction ground clicks reach their intended floors.")
	observations_controller.append({"admissions":admissions,"minimum_actor_distance":minimum,"remaining_routes":app.traversal.routes.duplicate(true)})

func _crowding()->void:
	_setup(2)
	app.world.actors.housemate_1.position=app.player.position+Vector3(.5,0,0)
	var start:Vector3=app.player.position
	app.on_ground_clicked(start+Vector3(-1,0,0))
	app._advance_path(.05)
	check(app.player.position.x<start.x-.05,"A small outward step escapes an existing crowded pair.")
	check(not app.traversal._step_clear("player",app.player.position,app.player.position+Vector3(.08,0,0)),"The same body gate still rejects a step deeper into the overlap.")
	app.world.actors.housemate_1.position=app.player.position+Vector3(.1,0,0)
	check(not app.traversal._step_clear("player",app.player.position,app.player.position+Vector3(.25,0,0)),"A step ending farther away cannot cross through an already overlapping body.")
	app.world.actors.housemate_1.position=app.player.position+Vector3(.125,0,.715)
	check(not app.traversal._step_clear("player",app.player.position,app.player.position+Vector3(.25,0,0)),"A segment cannot cut through a body-gap circle even when both endpoints are outside it.")
	_setup(2)
	app.world.actors.housemate_1.position=app.player.position+Vector3(.9,0,0)
	var destination:Vector3=app.player.position+Vector3(2,0,0)
	app.on_ground_clicked(destination)
	for frame:int in 300:
		app._advance_path(.05)
		if not app.traversal.active("player"):break
	check(app.player.position.distance_to(destination)<.001,"A through-walk locally routes around a stationary idle body.")
	var lock:Dictionary=app.traversal._lock("controlled_exit")
	lock.owner="housemate_1";lock.exit=app.player.position+Vector3(.125,0,.715);lock.clear=lock.exit+Vector3(0,0,1)
	check(not app.traversal._step_clear("player",app.player.position,app.player.position+Vector3(.25,0,0)),"The complete movement segment also respects another owner's reserved exit.")

func _invalid_pose()->void:
	_setup();app.on_ground_clicked(Vector3(2,3.16,3.5))
	check(_until_transit("player"),"Invalid-pose control starts from a real accepted crossing.")
	var route:Dictionary=_route("player");var leg:Dictionary=route.legs[int(route.cursor)]
	var distance:float=float(route.distance);var position:Transform3D=app.player.transform
	var pose:Dictionary=app.player.stair_presentation.duplicate(true)
	for stage:Dictionary in leg.schedule.stages:
		stage.before.L+=Vector3(0,10,0);stage.after.L+=Vector3(0,10,0)
	_step(3)
	check(not str(route.error).is_empty() and float(route.distance)==distance and app.player.transform==position,"An impossible stair pose rolls back root/distance and stops subsequent frame attempts.")
	check(app.player.stair_presentation==pose and str(app.traversal.stairs[route.stair_id].owner)=="player","Invalid contact preserves the last valid pose and ownership instead of abandoning the stair.")

func _late_waiter()->void:
	_setup(2);app.on_ground_clicked(Vector3(2,3.16,4))
	check(_until_transit("player"),"Late-arrival control begins after the first owner is already on the stair.")
	app.select_household_member(1);app.on_ground_clicked(Vector3(-2,.16,-4))
	var joined:bool=false
	for frame:int in 1500:
		_step()
		for lock:Dictionary in app.traversal.stairs.values():
			if str(lock.owner)=="player" and lock.queue.any(func(entry:Dictionary)->bool:return str(entry.id)=="housemate_1"):joined=true
		if frame>10 and app.traversal.routes.is_empty():break
	check(joined,"A new opposing arrival can reach its waiting place while the owner's exit stays reserved.")
	check(app.world.actors.player.position.distance_to(Vector3(2,3.16,4))<.001 and app.world.actors.housemate_1.position.distance_to(Vector3(-2,.16,-4))<.001,"Late opposing arrival and prior owner both finish their intended trips.")

func _cancel()->void:
	for later:bool in [false,true]:
		_setup()
		var upper:Dictionary=app._find_item("upper_shelf");var ground:Dictionary=app._find_item("ground_shelf")
		app.queue_interaction(upper,"read")
		if later:app.queue_interaction(ground,"read")
		check(_until_transit("player"),"An actual queued activity remains in approach while climbing.")
		var later_action:Dictionary=app.sim.action_queue[1] if later else {}
		var identity:int=int(_route("player").identity);var position:Vector3=app.player.position
		app.cancel_current_action()
		check(app.traversal.safety("player") and int(_route("player").identity)==identity and app.player.position==position,"Cancel preserves the admitted crossing identity and actual position.")
		if later:check(is_same(app.sim.get_current_action(),later_action) and str(later_action.phase)=="approach","Later queued action is retained and deferred until safe exit.")
		else:check(app.sim.action_queue.is_empty(),"Empty-queue cancellation keeps movement-only stair transit.")
		for frame:int in 1800:
			_step()
			if not app.traversal.safety("player"):break
		check(not app.traversal.safety("player") and app.world.point_level(app.player.position)==1,"Canceled crossing reaches its originally reserved upper landing first.")
		if later:
			for frame:int in 1800:
				_step()
				if str(later_action.phase)=="active":break
			check(is_same(app.sim.get_current_action(),later_action) and str(later_action.phase)=="active" and app.world.point_level(app.player.position)==0,"Deferred later action descends by the real stairs and begins at its ground furnishing.")
		else:check(app.player.stair_presentation.is_empty() and app.traversal.routes.is_empty(),"Canceled empty queue ends stationary on supported upper floor.")

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_walking();_opposite_fifo();_cancel();_crowding();_invalid_pose();_late_waiter()
	var report:Dictionary={"checks":checks,"failures":failures,"observations":observations_controller,"scope":"Actual main controller ground-click/activity/FIFO/cancel and paused manual 50ms frame updates. No fresh-process save, food custody or rendered continuous contact acceptance."}
	DirAccess.make_dir_recursive_absolute("user://regression/stair_integration")
	var file:=FileAccess.open("user://regression/stair_integration/controller.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("STAIR_CONTROLLER checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
