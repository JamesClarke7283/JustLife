extends SceneTree
## Physical boarding admission, dynamic-body detours and honest bounded failure.
## Uses a private JUSTLIFE_DATA_DIR and ordinary controller travel transitions.
const Entry=preload("res://scripts/car_entry.gd")
const DT:float=.05
var app:Node
var checks:int=0
var failures:int=0

class EntryProbe extends "res://scripts/car_entry.gd":
	var controller:Node
	var admitted:bool=false
	var exact:bool=true
	func tick(delta:float,actors:Dictionary)->bool:
		if not admitted:
			admitted=true
			for id:String in controller.residents.trip.boarding:
				var record:Dictionary=controller.residents.trip.boarding[id]
				exact=exact and actors[id].position.distance_to(Vector3(record.endpoint))<=.02
		return super.tick(delta,actors)

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func frames(n:int=2)->void:
	for i:int in n:await process_frame
func clock_minutes()->float:return (app.household.day-1)*1440.0+app.household.minutes
func observe_entry()->EntryProbe:
	var old:RefCounted=app.residents.car_entry
	var probe:=EntryProbe.new()
	probe.car=old.car;probe.cabin_scale=old.cabin_scale;probe.doors=old.doors;probe.steps=old.steps;probe.controller=app
	app.residents.car_entry=probe
	return probe
func finish_trip(probe:EntryProbe)->Dictionary:
	var safe:bool=true;var walking_frames:int=0;var elapsed:float=0.0;var entered:bool=false
	for step:int in 1800:
		if app.mode!="travel":break
		var before:Dictionary={}
		if str(app.residents.trip.get("phase",""))=="boarding" and not probe.admitted:
			for id:String in app.residents.trip.boarding:before[id]=app.world.actors[id].position
		app._process(DT);elapsed+=DT
		if not before.is_empty() and not probe.admitted:
			walking_frames+=1
			for id:String in before:
				var actor:LifeActor=app.world.actors[id]
				safe=safe and actor.position.distance_to(before[id])<=DT*2.1+.002
				if actor.position!=before[id]:
					var inward:bool=app.world.lot_navigation.boundary_entry_step(before[id],actor.position)
					safe=safe and (app.world.lot_navigation.segment_clear(0,before[id],actor.position) or inward)
					if id=="housemate_1" and Vector3(before[id]).z==9.0:
						entered=inward and actor.position.z<9.0 and actor.position.x==-9.25
		if step%20==0:await process_frame
	return {"safe":safe,"walking_frames":walking_frames,"seconds":elapsed,"entered":entered}
func quiet_fixture()->void:
	app.household.set_speed(0)
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false
		while not member.sim.action_queue.is_empty():member.sim.cancel_action()
	for id:String in LifeResidents.PEOPLE:app.world.actors[id].visible=false

func run()->void:
	if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():push_error("Use private JUSTLIFE_DATA_DIR");quit(2);return
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	app.household_profiles=[{"name":"Boarding walker","age_stage":"adult","traits":[],"hair":0},{"name":"Boarding companion","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();await frames()
	await social_boundary_control()
	app.current_venue="park";app.loading_game=true;app.setup_live(LifeNeighborhood.layout("park"));app.loading_game=false
	quiet_fixture()
	app.world.actors.player.position=Vector3(-3,.16,3)
	app.world.actors.housemate_1.position=Vector3(-9.25,.16,9)
	check(not app.world.lot_navigation.point_clear(0,app.world.actors.housemate_1.position),"The legacy saved boundary centre lacks full-body clearance")
	# A refused preflight must not hide the household member staying behind.
	app.traversal.routes.player={"phase":"transit"}
	check(not app.residents.begin_trip("library",["player"]) and app.world.actors.housemate_1.visible,"A refused trip leaves the nontraveller visible")
	app.traversal.routes.clear()
	var clock_before:float=clock_minutes()
	check(app.residents.begin_trip("library"),"Two Lifelets receive actual legacy-lot boarding paths")
	check(app.world.actors.housemate_1.position==Vector3(-9.25,.16,9),"Boarding preflight preserves the boundary body's exact saved position")
	if app.mode!="travel":await finish();return
	var probe:EntryProbe=observe_entry()
	var route:PackedVector3Array=app.residents.trip.boarding.player.path
	var blocker:LifeActor=app.world.actors.maya
	var placed:bool=false
	for point:Vector3 in route:
		if point.distance_to(app.world.actors.player.position)<2.0 or point.distance_to(Vector3(app.residents.trip.boarding.player.endpoint))<2.0:continue
		if point.distance_to(app.world.actors.housemate_1.position)<1.0:continue
		blocker.position=point;blocker.visible=true;placed=true;break
	check(placed,"A stationary resident blocks the already-planned boarding walk")
	var report:Dictionary=await finish_trip(probe)
	check(probe.admitted and probe.exact,"Car-entry choreography begins only after both actors physically reach their endpoints")
	check(bool(report.safe) and int(report.walking_frames)>0,"The boarding walkers move in bounded steps through clear floor segments")
	check(bool(report.entered),"The boundary walker physically steps inward before following the car route")
	check(app.mode=="live" and app.current_venue=="library" and float(report.seconds)<60.0,"The party detours around the resident and reaches the library without forced boarding")
	check(is_equal_approx(clock_minutes(),clock_before+15.0),"Successful travel advances only the ordinary fifteen-minute drive")
	if app.current_venue!="library":await finish();return
	quiet_fixture()
	var parked:Node3D=app.residents.venue_car
	var world:Node=app.world
	var funds:int=app.household.funds
	clock_before=clock_minutes()
	var before_visibility:bool=app.world.actors.housemate_1.visible
	check(is_instance_valid(parked) and app.residents.begin_trip("home",["player"]),"The return takes the same parked car and leaves the companion at the venue")
	if app.mode!="travel":await finish();return
	probe=observe_entry()
	# An actor occupying the exact reserved endpoint cannot be reached by a
	# collision-safe detour. The attempt must end without a fabricated arrival.
	var endpoint:Vector3=app.residents.trip.boarding.player.endpoint
	app.world.actors.maya.position=endpoint;app.world.actors.maya.visible=true
	var position_before_abort:Vector3=app.world.actors.player.position
	for step:int in 1300:
		if app.mode!="travel":break
		position_before_abort=app.world.actors.player.position
		app._process(DT)
		if step%20==0:await process_frame
	check(app.mode=="live" and app.current_venue=="library" and app.residents.trip.is_empty(),"A permanently blocked endpoint ends the attempt within the boarding deadline")
	check(not probe.admitted and app.world.actors.player.position.distance_to(endpoint)>.02,"The blocked Lifelet is never admitted to the car from a distance")
	check(app.world.actors.player.position==position_before_abort and is_same(app.world,world),"Failure retains the actual walking position and original venue world")
	check(app.world.actors.player.visible and app.world.actors.housemate_1.visible==before_visibility,"Failure restores both travelling and staying members' visibility")
	check(is_same(app.residents.venue_car,parked) and app.world.pick_extras.has(LifeResidents.VENUE_CAR_ID) and app.residents.car==null,"Failure restores the same parked car and its public interaction target")
	check(clock_minutes()==clock_before and app.household.funds==funds and app.household.speed==0,"Failure charges no drive time or funds and restores the paused speed")
	check(str(app.notice_text).contains("path to the car is blocked") and app.residents.car_entry==null,"Failure returns a clear notice and removes the unfinished entry presentation")
	# A body obstructing the only inward prefix cannot be ignored to repair an
	# older boundary pose. Preflight refuses without starting a trip or moving it.
	quiet_fixture();app.world.actors.player.position=Vector3(-9.25,.16,9)
	app.world.actors.maya.position=Vector3(-9.25,.16,8.75);app.world.actors.maya.visible=true
	check(not app.residents.begin_trip("home",["player"]),"An occupied inward boundary step refuses departure")
	check(app.world.actors.player.position==Vector3(-9.25,.16,9) and app.mode=="live" and app.residents.trip.is_empty() and clock_minutes()==clock_before,"Refused boundary recovery preserves the body, venue and clock")
	await finish()

func social_boundary_control()->void:
	quiet_fixture()
	app.world.actors.player.position=Vector3(-10,.16,7.25)
	app.world.actors.housemate_1.position=Vector3(3,.16,3)
	var leo:LifeActor=app.world.actors.leo
	leo.position=Vector3(-8.5,.16,8.2);app.world.set_actor_away("leo",false,false)
	app.residents.locations.home.leo.phase="walking";app.residents.locations.home.leo.wait=0.0
	app._refresh_sim_targets(false)
	check(not app._social_point_clear(Vector3(-9.25,.16,9),leo),"A sidewalk chat refuses a centre on the lot boundary")
	check(app._social_point_clear(Vector3(-9.5,.16,8.25),leo),"A nearby inward sidewalk conversation retains full-body and peer clearance")
	var score:float=float(app.sim.relationships.leo.friendship)
	app.queue_interaction({"id":"leo","kind":"neighbor","label":"Leo","node":leo,"size":Vector2(.6,.6)},"friendly")
	var action:Dictionary=app.sim.get_current_action()
	check(str(action.get("id",""))=="friendly" and app.world.lot_navigation.point_clear(0,action.get("target_position",Vector3.INF)),"Ordinary social admission chooses a supported sidewalk alternative")
	app.household.set_speed(8)
	for frame:int in 300:
		app._process(DT)
		if frame%20==0:await process_frame
		if not is_same(app.sim.get_current_action(),action):break
	check(float(action.get("elapsed",0.0))>=float(action.get("duration",INF)) and float(app.sim.relationships.leo.friendship)>score,"The inward sidewalk chat physically arrives and completes with its real friendship reward")
	check(app.world.lot_navigation.point_clear(0,app.player.position),"A completed sidewalk chat leaves a position ordinary routes can depart")

func finish()->void:
	app.queue_free();await frames(3)
	print("TRIP_BOARDING %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
