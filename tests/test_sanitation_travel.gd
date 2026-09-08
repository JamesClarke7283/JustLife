extends "res://tests/test_sanitation.gd"
## Combined resident-car and sanitation checks against an isolated current-root snapshot.
var trips:Array=[]
var saves:Array=[]
var cleaning:Dictionary={}
var home_puddle:String=""
var maya_retained:String=""
var maya_cleaned:String=""
var leo_puddle:String=""
func record_cleanup(_member:String,action:Dictionary)->void:
	if str(action.id)=="mop_puddle":cleaning[str(action.target_id)]=int(cleaning.get(str(action.target_id),0))+1
func watch_cleanup()->void:
	# V2 named reload atomically replaces the household node and its signals.
	if not app.household.member_action_finished.is_connected(record_cleanup):app.household.member_action_finished.connect(record_cleanup)
func clock_minutes()->float:return (app.household.day-1)*1440.0+app.household.minutes
func urgency()->Dictionary:
	var data:Dictionary={}
	for member:Dictionary in app.household.members:data[member.id]={"grace":member.sim.bladder_grace,"bladder":member.sim.needs.bladder}
	return data
func place_puddles(place:String)->Array:
	return app.household.sanitation.puddles.filter(func(p:Dictionary)->bool:return str(p.venue)==place)
func visible_puddles()->Array:
	var ids:Array=[]
	for item:Dictionary in app.world.items:
		if str(item.kind)=="puddle":ids.append(str(item.id))
	ids.sort();return ids
func check_place(place:String,label:String)->void:
	var ids:Array=[]
	for p:Dictionary in place_puddles(place):ids.append(str(p.id))
	ids.sort()
	check(app.current_venue==place and visible_puddles()==ids,label+": only this location’s puddle targets are present.")
	for id:String in ids:
		var view:Dictionary=app._find_item(id)
		check(view.node.get_parent()==app.world.house and not view.node.is_queued_for_deletion(),label+": "+id+" belongs to the current physical house.")
func car_trip(destination:String,allow_pending:bool=true)->void:
	var origin:String=app.current_venue
	var initial:Dictionary=app.household.sanitation.get_state()
	var initial_clock:float=clock_minutes()
	var trace:Dictionary={"origin":origin,"destination":destination,"clock":initial_clock,"events":[],"frames":0,"charge_events":0,"visible_boarding_motion":false,"car_motion":false}
	var static_clock:bool=true
	var static_urgency:bool=true
	var no_accidents:bool=true
	var parked_simulation:bool=true
	app.travel_to(destination)
	check(app.mode=="travel" and not app.residents.trip.is_empty(),"Actual car travel begins from "+origin+" to "+destination+".")
	var boarding:Dictionary=app.residents.trip.boarding.player
	var endpoint:Vector3=boarding.get("endpoint",boarding.path[-1])
	trace["boarding_distance"]=app.world.actors.player.position.distance_to(endpoint)
	print("CAR_GATE begin ",origin," -> ",destination," boarding_distance=",trace.boarding_distance)
	for index:int in 1500:
		if app.mode!="travel":break
		var phase:String=str(app.residents.trip.phase)
		var before:float=clock_minutes();var before_urgency:Dictionary=urgency()
		var before_actor:Vector3=app.world.actors.player.position
		var before_visible:bool=app.world.actors.player.visible
		var before_car:Node3D=app.residents.car
		var before_x:float=before_car.position.x
		parked_simulation=parked_simulation and app.household.speed==0
		app._process(.05)
		trace.frames+=1
		var after_phase:String=str(app.residents.trip.get("phase","complete"))
		var charge:bool=phase=="departure" and after_phase=="arrival"
		var delta_clock:float=clock_minutes()-before
		if charge:
			trace.charge_events+=1
			check(absf(delta_clock-15.0)<.00000001,"The "+destination+" trip applies one fifteen-minute simulation charge.")
		else:
			static_clock=static_clock and delta_clock==0.0
			static_urgency=static_urgency and urgency()==before_urgency
		if phase=="boarding" and before_visible and app.world.actors.player.position.distance_to(before_actor)>.001:trace.visible_boarding_motion=true
		if phase in ["departure","arrival"] and is_instance_valid(before_car) and is_instance_valid(app.residents.car) and before_car==app.residents.car and absf(before_car.position.x-before_x)>.001:trace.car_motion=true
		no_accidents=no_accidents and app.household.sanitation.get_state()==initial
		if phase!=after_phase:trace.events.append({"from":phase,"to":after_phase,"clock":clock_minutes(),"urgency":urgency(),"place":app.current_venue,"puddles":app.household.sanitation.puddles.size()})
		if index%20==0:await process_frame
	check(app.mode=="live" and app.current_venue==destination,"Actual car travel arrives at "+destination+".")
	check((float(trace.boarding_distance)<=.001 or bool(trace.visible_boarding_motion)) and bool(trace.car_motion),"The "+destination+" journey physically drives, with boarding motion whenever the actual initial position requires it.")
	check(static_clock and static_urgency and parked_simulation,"Boarding/driving animation for "+destination+" advances neither simulation nor bladder urgency continuously.")
	check(trace.charge_events==1 and absf(clock_minutes()-initial_clock-15.0)<.00000001,"The complete "+destination+" trip charges exactly fifteen game minutes once.")
	check(no_accidents,"No trip phase or hidden arrival creates a puddle at stale coordinates for "+destination+".")
	check(app.household.members.all(func(m:Dictionary)->bool:return app.world.actors[m.id].visible),"All Lifelets are visibly present before pending accidents may resolve at "+destination+".")
	trace["arrival_clock"]=clock_minutes();trace["arrival_urgency"]=urgency();trips.append(trace)
	if not allow_pending:check(app.household.sanitation.get_state()==initial,"Healthy travel preserves the exact live sanitation ledger.")
	check_place(destination,"Arrival at "+destination)
	print("CAR_GATE arrived ",destination)
func save_and_reload(title:String)->Dictionary:
	print("CAR_GATE named save/load ",title)
	check(app.save_game("",title),"A named save is written at "+app.current_venue+".")
	var slot:String=app.active_save_id
	var read:Dictionary=LifeSaveLibrary.read_slot(slot)
	check(read.ok,"The named "+app.current_venue+" save validates through the actual save library.")
	var expected:Dictionary=read.data.sanitation.duplicate(true)
	var place:String=app.current_venue
	var old_house:Node3D=app.world.house
	app.load_game(slot);watch_cleanup()
	check(app.current_venue==place and app.world.house!=old_house,"Same-process loading rebuilds the correct house at "+place+".")
	check(app.household.sanitation.puddles==expected.puddles and app.household.sanitation.serial==int(expected.serial),"Same-process loading at "+place+" preserves exact decoded puddle data and integer identity.")
	check_place(place,"Reload at "+place)
	await frames(3)
	saves.append({"id":slot,"place":place,"expected":expected,"title":title})
	return read.data
func create_arrival_accidents(place:String,expected_members:Array)->Array:
	var before_count:int=app.household.sanitation.puddles.size()
	var positions:Dictionary={}
	for member:String in expected_members:positions[member]=app.world.actors[member].position
	app.household.set_speed(1);step(.3)
	var added:Array=app.household.sanitation.puddles.slice(before_count)
	check(added.size()==expected_members.size(),"The first visible Live tick resolves the expected pending accidents at "+place+".")
	for p:Dictionary in added:
		var at:Vector3=Vector3(p.position[0],p.position[1],p.position[2])
		check(str(p.venue)==place and expected_members.has(str(p.member)) and at.distance_to(positions[str(p.member)])<.000001,"Pending accident uses "+str(p.member)+"’s real visible destination coordinates.")
	var count:int=app.household.sanitation.puddles.size();step(2.0)
	check(app.household.sanitation.puddles.size()==count,"Pending arrival events reset once and do not spam new puddles.")
	return added
func clean(id:String,save_partly:bool=false,yielding_id:String="")->void:
	app.select_household_member(0);app.household.set_speed(1)
	var item:Dictionary=app._find_item(id)
	check(not item.is_empty(),"Cleanup target "+id+" exists in the current house.")
	if item.is_empty():return
	var idle_origin:Vector3=Vector3.INF
	if not yielding_id.is_empty():
		idle_origin=app.world.actors[yielding_id].position
		var saved:Dictionary=app.household.sanitation.find(id)
		var accident_origin:=Vector3(saved.position[0],saved.position[1],saved.position[2])
		check(idle_origin.distance_to(accident_origin)<.001,"The legitimate idle housemate still stands at their retained arrival puddle before cleanup.")
		check(app.world.approach(item).distance_to(idle_origin)<LifeTraversal.ROUTE_CLEARANCE,"The real cleanup destination falls inside the idle housemate's reserved route clearance.")
	app.queue_interaction(item,"mop_puddle")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active",180.0),"The Lifelet reaches "+id+" through actual cleanup navigation.")
	if not yielding_id.is_empty():
		check(app.world.actors[yielding_id].position.distance_to(idle_origin)>.1,"The idle housemate makes room using actual courtesy movement.")
		check(app.world.actors[yielding_id].position.distance_to(app.world.actors.player.position)>=LifeTraversal.BODY_GAP-.00001,"The cleaner reaches the wet patch while respecting physical body clearance.")
		check(app.household.member_sim(yielding_id).action_queue.is_empty(),"Courtesy walking creates no activity or cleanup reward for the idle housemate.")
	step(2.0)
	if save_partly:
		var saved:Dictionary=await save_and_reload("Juniper Bay - partial cleanup at "+app.current_venue)
		var expected_elapsed:float=float(saved.members[int(saved.selected_index)].state.action_queue[0].elapsed)
		check(str(app.sim.get_current_action().get("id",""))=="mop_puddle" and float(app.sim.get_current_action().elapsed)==expected_elapsed,"Same-process visiting-home load retains exact decoded paid cleanup progress.")
	app.household.set_speed(1)
	check(until(func()->bool:return app.household.sanitation.find(id).is_empty(),180.0),"Cleanup physically completes for "+id+".")
	check(int(cleaning.get(id,0))==1 and app._find_item(id).is_empty(),"Cleanup removes "+id+" and its current-world target exactly once.")
	check(not app.sim.queue_action("mop_puddle",id),"A stale cleanup request cannot recreate or clear "+id+" twice.")
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false)
	app.household_profiles=[{"name":"Alex Rivera","frame":0},{"name":"Jamie Rowan","frame":1}]
	app.start_household();await frames(3);reset_needs()
	for member:Dictionary in app.household.members:
		member.sim.relationships.maya.friendship=30.0;member.sim.relationships.leo.friendship=30.0
	watch_cleanup()
	check(FileAccess.get_file_as_string("res://scripts/save_library.gd").contains('JSON.stringify(_json_safe(data), "\\t", true, true)'),"Combined root uses the full-precision production save writer.")
	app.sim.needs.bladder=0.0;step(10.01)
	check(place_puddles("home").size()==1,"The household begins with one real home accident.")
	home_puddle=str(place_puddles("home")[0].id)
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=7.0
	app.household.member_sim("housemate_1").needs.bladder=0.0;app.household.member_sim("housemate_1").bladder_grace=4.0
	await car_trip("maya_home")
	check(app.sim.bladder_grace==10.0 and app.household.member_sim("housemate_1").bladder_grace==10.0,"The single trip charge caps both pending urgency timers without emitting accidents.")
	var maya:Array=create_arrival_accidents("maya_home",["player","housemate_1"])
	maya_cleaned=str(maya[0].id);maya_retained=str(maya[1].id)
	await save_and_reload("Juniper Bay - Maya's floor")
	await clean(maya_cleaned,true)
	check(place_puddles("home").size()==1 and place_puddles("maya_home").size()==1,"Cleaning at Maya’s leaves home and the second visitor’s mess intact.")
	app.sim.needs.bladder=0.0;app.sim.bladder_grace=8.0
	app.household.member_sim("housemate_1").needs.bladder=75.0;app.household.member_sim("housemate_1").bladder_grace=0.0
	await car_trip("leo_home")
	var leo:Array=create_arrival_accidents("leo_home",["player"]);leo_puddle=str(leo[0].id)
	await save_and_reload("Juniper Bay - Leo's floor")
	check(place_puddles("home").size()==1 and place_puddles("maya_home").size()==1 and place_puddles("leo_home").size()==1,"Three distinct homes keep independent persistent puddle records.")
	await car_trip("home",false)
	check(not app._find_item(home_puddle).is_empty() and app._find_item(maya_retained).is_empty() and app._find_item(leo_puddle).is_empty(),"Returning home recreates only the original home accident target.")
	await save_and_reload("Juniper Bay - returned home")
	await clean(home_puddle,true)
	await car_trip("maya_home",false)
	check(app._find_item(maya_cleaned).is_empty() and not app._find_item(maya_retained).is_empty(),"Returning to Maya keeps the cleaned puddle deleted and the uncleaned one present.")
	await clean(maya_retained,false,"housemate_1")
	await car_trip("leo_home",false)
	check(not app._find_item(leo_puddle).is_empty() and app.household.sanitation.puddles.size()==1,"Leo’s original puddle survives all other homes’ cleanup and returns.")
	await clean(leo_puddle)
	check(app.household.sanitation.puddles.is_empty() and visible_puddles().is_empty() and cleaning.size()==4 and cleaning.values().all(func(n:Variant)->bool:return int(n)==1),"All four real accidents clean exactly once across three independent homes.")
	await save_and_reload("Juniper Bay - clean floors")
	check(app.household.sanitation.puddles.is_empty(),"A same-process named reload does not resurrect cleaned location records.")
	check(trips.any(func(trip:Dictionary)->bool:return float(trip.boarding_distance)>.1 and bool(trip.visible_boarding_motion)),"The complete car gate includes actual required boarding movement.")
	var report:Dictionary={"checks":checks,"failures":failures,"trips":trips,"saves":saves,"cleaning":cleaning}
	var file:=FileAccess.open("user://sanitation_travel.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("Sanitation travel: %d checks, %d failures." % [checks,failures.size()])
	app.queue_free();await frames(5);await create_timer(.15).timeout;quit(0 if failures.is_empty() else 1)
