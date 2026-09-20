extends "res://tests/test_build_world_levels.gd"
## Regression for "a Lifelet stands upstairs holding only a stair queue ticket".
## Two independent defects produced it, and both are ordinary public behaviour:
##  * the floor graph dropped a bought staircase when a ground appliance merely
##    grazed the lower landing's wider reserved clearance, so no route connected
##    the floors at all and the HUD only ever showed a walk with no crossing;
##  * an away Lifelet (no body in the lot) was handed a floor route from its
##    saved return position, which no frame could ever advance.
## Actual main controller, actual floor graph, manual 50ms frames. The staircase
## is the ordinary validated two-storey structure and the appliances are ordinary
## layout furnishings.
var app:Node
var stuck_observations:Array=[]

func _stuck_layout()->Array:
	# `fixture()` already carries one supported staircase at (0,-2). The graze
	# stove overlaps that staircase's lower landing clearance while leaving the
	# walker's body box there clear: exactly the ordinary kitchen the graph used
	# to drop the staircase for. The blocking stove covers a free spot's landing.
	return [{"id":"graze_stove","kind":"stove","x":0.75,"z":-3.0,"rotation":0.0},
		{"id":"blocking_stove","kind":"stove","x":2.0,"z":-2.5,"rotation":0.0},fixture()]

func _setup(people:int=2)->void:
	app.household_profiles=[]
	for index:int in people:app.household_profiles.append({"name":"Stuck Walker "+str(index),"age_stage":"young_adult","traits":[],"hair":0})
	app.creator_family_links=[];app.start_household();app.set_process(false)
	app.loading_game=true
	app.setup_live(_stuck_layout())
	app.loading_game=false
	check(app.world.last_layout_error.is_empty(),"The two-storey home with its kitchen builds without a layout error.")
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false;member.sim.set_aging("normal",false);member.sim.household_bills_enabled=false;member.sim.wants.clear()
		for need:String in LifeSim.NEED_NAMES:member.sim.needs[need]=80
	app.household.set_speed(3)
	app.world.actors.player.position=Vector3(-2,.16,2)
	if people>1:app.world.actors.housemate_1.position=Vector3(2,3.16,2)
	app._store_motion()

func _step(count:int=1,delta:float=.05)->void:
	for i:int in count:app._process(delta)

func _stair()->Dictionary:
	var state:Dictionary=app.world.construction.snapshot()
	return state.stairs[0] if not state.stairs.is_empty() else {}

func _graph()->void:
	var stair:Dictionary=_stair()
	check(not stair.is_empty(),"The two-storey home loads its bought staircase.")
	if stair.is_empty():return
	var lower:Vector3=Building.stair_point(stair,-.5)
	check(app.world.lot_navigation.point_clear(0,lower),"The appliance beside the staircase really leaves the walker's lower body box clear.")
	check(app.world.lot_navigation.stair_connected(str(stair.id)),"A staircase an appliance merely grazes stays a linked crossing in the floor graph.")
	var ground:Vector3=app.world.nearest_clear_point(Vector3(-2,.16,2),0)
	var upper:Vector3=app.world.nearest_clear_point(Vector3(2,3.16,2),1)
	var route:Dictionary=app.world.route_to(ground,upper)
	var stair_segments:Array=route.get("segments",[]).filter(func(segment:Dictionary)->bool:return str(segment.kind)=="stair")
	check(bool(route.ok) and route.points.size()>2,"A real ground-to-upper route crosses that staircase.")
	check(not stair_segments.is_empty(),"The two-floor route really includes a stair segment.")
	stuck_observations.append({"lower_clear":app.world.lot_navigation.point_clear(0,lower),"stair_id":str(stair.id),"route_points":route.points.size(),"stair_segments":stair_segments.size()})

func _purchase_refusal()->void:
	# A staircase whose foot the appliance occupies cannot be walked to, so the
	# household must not be sold one. The grazed staircase beside it was bought.
	var operation:Dictionary={"op":"add","collection":"stairs","record":{"x":2.0,"z":-2.0,"rotation":0}}
	var blocked:Dictionary=app.build_transactions.prepare(operation,true)
	check(not bool(blocked.ok) and str(blocked.get("error","")).begins_with("That staircase has no usable way"),"A staircase whose foot is covered is refused at purchase with the honest reason.")
	check(app.world.construction.snapshot().stairs.size()==1,"The refused staircase is never added to the home.")
	stuck_observations.append({"refusal":str(blocked.get("error",""))})

func _opposing_walks()->void:
	_setup(2)
	if app.world.actors.is_empty():return
	var ground:Vector3=app.world.nearest_clear_point(Vector3(-2,.16,2),0)
	var upper:Vector3=app.world.nearest_clear_point(Vector3(2,3.16,2),1)
	var start_up:Vector3=app.world.actors.player.position
	var start_down:Vector3=app.world.actors.housemate_1.position
	app.on_ground_clicked(upper)
	var up_accepted:bool=app.traversal.active("player")
	app.select_household_member(1);app.on_ground_clicked(ground)
	var down_accepted:bool=app.traversal.active("housemate_1")
	check(up_accepted and down_accepted,"Both opposing public ground clicks retain a real two-floor route through the bought staircase.")
	# Only a genuinely waiting Lifelet that ends up exactly where it started is a
	# stall: a waiter that still crosses is ordinary FIFO, not the reported bug.
	var parked:Array[String]=[]
	for frame:int in 1600:
		_step()
		for id:String in ["player","housemate_1"]:
			var route:Dictionary=app.traversal.routes.get(id,{})
			if str(route.get("phase",""))!="waiting":continue
			var began:Vector3=start_up if id=="player" else start_down
			if app.world.actors[id].position.distance_to(began)<.001 and not parked.has(id):parked.append(id)
		if not app.traversal.active("player") and not app.traversal.active("housemate_1"):break
	var upstairs:LifeActor=app.world.actors.player
	var downstairs:LifeActor=app.world.actors.housemate_1
	check(parked.is_empty(),"No opposing Lifelet waits on a stair ticket without moving at all.")
	check(upstairs.position.distance_to(upper)<.01 and app.world.point_level(upstairs.position)==1,"The ascending Lifelet physically reaches the upper floor through the staircase.")
	check(downstairs.position.distance_to(ground)<.01 and app.world.point_level(downstairs.position)==0,"The descending Lifelet physically reaches the ground floor through the same staircase.")
	check(app.player.stair_presentation.is_empty() and app.traversal.stairs.values().all(func(lock:Dictionary)->bool:return str(lock.owner).is_empty()),"Both crossings release their real stair ownership.")
	stuck_observations.append({"parked":parked,"up":upstairs.position,"down":downstairs.position})

func _away_refusal()->void:
	var id:String="housemate_1"
	app.world.set_actor_away(id,true,true)
	var target:Vector3=app.world.nearest_clear_point(Vector3(-2,.16,2),0)
	var refused:Dictionary=app.traversal.request(id,target)
	check(not bool(refused.ok) and not str(refused.get("error","")).is_empty(),"An away Lifelet is refused a floor route with an honest reason.")
	check(not app.traversal.routes.has(id),"No route nobody can advance is left behind for an away Lifelet.")
	app.world.set_actor_away(id,false,false)
	stuck_observations.append({"away_error":str(refused.get("error",""))})

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup(2)
	_graph()
	_purchase_refusal()
	_opposing_walks()
	_away_refusal()
	var report:Dictionary={"checks":checks,"failures":failures,"observations":stuck_observations,"scope":"Actual main controller, validated two-storey structure, real floor graph and public ground clicks at manual 50ms frames. No fresh-process save or rendered contact acceptance."}
	var dir:String="user://regression/stuck_upstairs";DirAccess.make_dir_recursive_absolute(dir)
	var file:=FileAccess.open(dir.path_join("stuck.json"),FileAccess.WRITE)
	if file==null:push_error("Cannot write the stuck-upstairs report.");quit(1);return
	file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("STUCK_UPSTAIRS checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
