extends SceneTree
## A pet held up by furniture recovers within a bounded time instead of pressing
## on the same edge, trotting in place or standing inside a piece for good. Headless.
##
##  1. a stale walk through a newly placed sofa goes round it;
##  2. a walk whose goal is sealed in gives up inside the timeout, says which item
##     to move, and the pet stands still rather than trotting;
##  3. a pet found under a furnishing is lifted to clear floor;
##  4. a pet held at the edge of its bed is set down instead of waiting for ever;
##  5. an arrival held at a doorway ends after eight scaled seconds;
##  6. an autonomous errand that cannot start backs off instead of replanning every
##     frame, and a walled-in urgent need is reported once.
const DT:float=.1

var checks:int=0
var failures:Array[String]=[]
var app:Node
var world:LifeWorld
var controller:LifePetBehavior
var dog:Dictionary
var dog_id:String

func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _initialize()->void:_run.call_deferred()

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	for n:int in 4:await process_frame
	app.selected_lot=0;app.start_household()
	for n:int in 4:await process_frame
	app.set_process(false);app.world.set_process(false)
	app.household.set_speed(1);app.set_sound(false)
	world=app.world
	controller=app.pet_behavior()
	dog=LifePets.record_from(LifePets.candidate(1,1),"stuck_dog",1)
	app.household.pets.pets.append(dog)
	app.household.pets.next_serial=2
	dog_id=str(dog.id)
	app.spawn_pet(dog_id,dog,Vector3(16,.16,4),Vector3(16,.16,4))
	_reroutes_round_furniture()
	_sealed_goal_gives_up()
	_lifted_from_under_furniture()
	_bed_edge_released()
	_arrival_timeout()
	_errand_backoff()
	app.queue_free();await process_frame
	print("PET_STUCK_RECOVERY %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _actor()->LifePetActor:return app.pet_actors[dog_id]

func _reset(at:Vector3)->void:
	app.pet_errands.clear();app.pet_arrivals.clear()
	controller.toy_claims.clear();controller.cooldown.clear();controller.notified.clear()
	_actor().position=at;_actor().clear_behavior();_actor().traversing_stairs=false
	controller.idle_minutes[dog_id]=-1000.0
	for need:String in LifePetCare.NEED_NAMES:app.household.pet_care(dog_id).needs[need]=90.0

func _clear()->bool:
	return world.lot_navigation.point_clear(world.point_level(_actor().position),_actor().position)

func _sofa(id:String,at:Vector2,rotation:float)->void:
	world.add_item({"id":id,"kind":"sofa","x":at.x,"z":at.y,"level":0,"rotation":rotation})

func _ring(with_east:bool)->Vector3:
	var pocket:=Vector2(12.0,-4.0)
	world.add_item({"id":"ring_north","kind":"pool","x":pocket.x,"z":pocket.y-.5-1.9,"rotation":0,"style":"classic","size":"small"},false)
	world.add_item({"id":"ring_south","kind":"pool","x":pocket.x,"z":pocket.y+.5+1.9,"rotation":0,"style":"classic","size":"small"},false)
	world.add_item({"id":"ring_west","kind":"pool_slide","x":pocket.x-.5-.62,"z":pocket.y-.135,"rotation":0,"style":"straight"},false)
	if with_east:world.add_item({"id":"ring_east","kind":"pool_slide","x":pocket.x+.5+.62,"z":pocket.y-.135,"rotation":0,"style":"straight"},false)
	world.rebuild_navigation()
	return Vector3(pocket.x,LifeBuildingState.level_y(0),pocket.y)

func _remove(ids:Array[String])->void:
	for id:String in ids:
		if not app._find_item(id).is_empty():world.remove_item(id)

func _tick(seconds:float)->int:
	# Steps the pet controller the way the game does, and counts the ticks in
	# which the dog is reported as having moved.
	var moved:int=0
	for step:int in range(int(seconds/DT)):
		controller.tick(DT,1.0)
		if controller.moved_ids.has(dog_id):moved+=1
	return moved

func _reroutes_round_furniture()->void:
	var y:float=LifeBuildingState.level_y(0)
	var goal:=Vector3(8.5,y,4.0)
	_reset(Vector3(16,y,4))
	check(bool(controller.command(dog_id,"pet_move",goal).ok),"The dog accepts a walk across the east garden")
	_sofa("stuck_sofa",Vector2(12.0,4.0),90.0)
	var buried:int=0;var seconds:float=0.0
	while seconds<60.0 and _actor().position.distance_to(goal)>.15:
		controller.tick(DT,1.0);seconds+=DT
		if not _clear():buried+=1
	check(_actor().position.distance_to(goal)<=.15,"A dog whose walk was cut by a new sofa goes round it (%.1f s)"%seconds)
	check(buried==0,"It never stands inside the sofa (%d ticks inside)"%buried)
	_remove(["stuck_sofa"])

func _sealed_goal_gives_up()->void:
	var y:float=LifeBuildingState.level_y(0)
	_reset(Vector3(16,y,-4))
	var pocket:Vector3=_ring(false)
	check(bool(controller.command(dog_id,"pet_move",pocket).ok),"The dog accepts a walk into an open-sided pocket")
	world.add_item({"id":"ring_east","kind":"pool_slide","x":pocket.x+.5+.62,"z":pocket.z-.135,"rotation":0,"style":"straight"})
	app.notice_time=0.0;app._blocked_notice_at=-100000
	var seconds:float=0.0;var trotted_while_held:int=0;var buried:int=0
	while seconds<40.0 and not app.pet_errands.get(dog_id,{}).is_empty():
		controller.tick(DT,1.0);seconds+=DT
		if not _clear():buried+=1
		var held:float=float(app.pet_errands.get(dog_id,{}).get("blocked",0.0))
		if held>1.0 and controller.moved_ids.has(dog_id):trotted_while_held+=1
	check(app.pet_errands.get(dog_id,{}).is_empty(),"A dog that can never get where it was sent lets the errand go (%.1f s)"%seconds)
	check(seconds<=LifePetBehavior.BLOCKED_TIMEOUT+3.0,"It does so within the timeout (%.1f s of %.0f s)"%[seconds,LifePetBehavior.BLOCKED_TIMEOUT])
	check(trotted_while_held==0,"Held at the slide it stands rather than trotting in place (%d ticks)"%trotted_while_held)
	check(buried==0,"It never stands inside a piece meanwhile (%d ticks)"%buried)
	check(app.notice_text=="Please move the Pool slide blocking the path.","The player is told which item to move: "+app.notice_text)
	# Free of the errand, the pet is a normal idle pet again.
	controller.idle_minutes[dog_id]=-1000.0
	_tick(1.0)
	check(str(controller.state(dog_id).action)=="idle","The pet is idle again, ready for its next choice")
	# A command that cannot even be planned names the piece too.
	var refused:Dictionary=controller.command(dog_id,"pet_move",pocket)
	check(not bool(refused.ok) and str(refused.message)=="Please move the Pool slide blocking the path.","A command into the sealed pocket is refused naming the slide: "+str(refused.get("message","")))
	_remove(["ring_north","ring_south","ring_west","ring_east"])

func _lifted_from_under_furniture()->void:
	var y:float=LifeBuildingState.level_y(0)
	_reset(Vector3(16,y,4))
	_sofa("stuck_cover",Vector2(16.0,4.0),0.0)
	check(not _clear(),"A furnishing set down on the dog leaves it inside the piece")
	controller.tick(DT,1.0)
	check(_clear(),"The next tick lifts it to clear floor")
	check(_actor().position.distance_to(Vector3(16,y,4))<3.0,"It is set down close by (%.2f m)"%_actor().position.distance_to(Vector3(16,y,4)))
	_remove(["stuck_cover"])

func _bed_edge_released()->void:
	var y:float=LifeBuildingState.level_y(0)
	_reset(Vector3(14,y,-9))
	world.add_item({"id":"stuck_bed","kind":"pet_bed_dog","x":14.0,"z":-7.0,"level":0,"rotation":0.0},false)
	world.rebuild_navigation()
	check(bool(controller.command(dog_id,"pet_go_bed").ok),"The dog accepts its bed")
	var seconds:float=0.0
	while seconds<60.0 and str(controller.state(dog_id).phase)!="using":
		controller.tick(DT,1.0);seconds+=DT
	check(str(controller.state(dog_id).phase)=="using","The dog lies on its bed")
	var entry:Vector3=Vector3(app.pet_errands[dog_id].entry)
	# A sofa is set down over the spot it steps off to.
	_sofa("stuck_edge",Vector2(entry.x,entry.z),0.0)
	controller.command(dog_id,"pet_stop_playing")
	check(str(controller.state(dog_id).phase)=="exiting","Stop Playing sends it off the bed")
	seconds=0.0
	while seconds<30.0 and not app.pet_errands.get(dog_id,{}).is_empty():
		controller.tick(DT,1.0);seconds+=DT
	check(app.pet_errands.get(dog_id,{}).is_empty(),"A dog held at its bed's edge is set down within the timeout (%.1f s)"%seconds)
	check(seconds<=LifePetBehavior.ACCESS_TIMEOUT+2.0,"That is within %.0f s"%LifePetBehavior.ACCESS_TIMEOUT)
	check(_clear(),"It ends on clear floor, not inside the sofa")
	_remove(["stuck_edge","stuck_bed"])

func _arrival_timeout()->void:
	var y:float=LifeBuildingState.level_y(0)
	_reset(Vector3(16,y,-4))
	var pocket:Vector3=_ring(true)
	var start:=Vector3(16,y,-4)
	app.pet_arrivals[dog_id]={"destination":pocket,"path":PackedVector3Array([start,pocket]),"index":0}
	var seconds:float=0.0
	while seconds<30.0 and app.pet_arrivals.has(dog_id):
		app._advance_pet_arrivals(DT);seconds+=DT
	check(not app.pet_arrivals.has(dog_id),"An arrival that cannot get in is ended (%.1f s)"%seconds)
	check(seconds<=app.PET_ARRIVAL_TIMEOUT+2.0,"That takes about %.0f scaled seconds"%app.PET_ARRIVAL_TIMEOUT)
	check(_clear(),"The pet ends on clear floor")
	check(_actor().position.distance_to(pocket)>1.0,"It is not dropped into the sealed pocket")
	_remove(["ring_north","ring_south","ring_west","ring_east"])

func _errand_backoff()->void:
	var y:float=LifeBuildingState.level_y(0)
	# Wall a dog in completely: nowhere to wander, and its bowl is out of reach.
	_reset(Vector3(12,y,-4))
	_ring(true)
	app.household.pet_care(dog_id).needs.hunger=10.0
	world.add_item({"id":"stuck_bowl","kind":"pet_bowl","x":16.0,"z":-4.0,"level":0,"rotation":0.0})
	controller.idle_minutes[dog_id]=100.0
	app.notice_time=0.0;app._blocked_notice_at=-100000
	controller.tick(DT,1.0)
	check(app.pet_errands.get(dog_id,{}).is_empty(),"A walled-in hungry dog has no errand it can start")
	check(float(controller.cooldown.get(dog_id,0.0))>0.0,"It backs off before trying again")
	check(app.notice_text=="Please move the Pool slide blocking the path.","Its urgent need is reported naming the item in the way: "+app.notice_text)
	var stamp:int=int(app._blocked_notice_at)
	app.notice_time=1.0
	for step:int in 20:controller.tick(DT,1.0)
	check(is_equal_approx(app.notice_time,1.0) and int(app._blocked_notice_at)==stamp,"The report is not repeated every frame")
	_remove(["ring_north","ring_south","ring_west","ring_east","stuck_bowl"])
