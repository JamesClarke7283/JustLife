extends SceneTree
## Residents keep the shared body gap everywhere they walk. A visiting
## resident never steps closer to a parked body, and a waypoint another body
## occupies is abandoned for the next one instead of being clipped through.
## The bare-lot boarding walk respects the same rule. Headless.

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
	app.sim.speed=1
	var residents=app.residents
	var gap:float=app.traversal.BODY_GAP

	# --- Visiting resident with a parked body on her next waypoint. ---
	residents.active_place="library"
	residents.locations["library"]={}
	for resident_id: String in residents.PEOPLE:
		residents.locations["library"][resident_id]={"position":[2.5,.16,2.75],"direction":-1,"phase":"home","wait":999999.0,"rotation":0.0,"waypoint":0}
	residents.locations["library"]["priya"]={"position":[2.2,.16,2.75],"direction":-1,"phase":"visiting","wait":0.0,"rotation":0.0,"waypoint":0}
	# Priya's routine venue is the library with a bookshelf anchor, so seed
	# the anchor circuit with a waypoint right past a parked body.
	residents._anchor_cache["library/bookshelf"]=[Vector3(1.6,.16,2.75),Vector3(-2.0,.16,2.8)]
	var person:Dictionary=residents.PEOPLE["priya"]
	var actor=app.spawn_actor("priya",person,Vector3(2.2,.16,2.75))
	var member:Dictionary=app.household.members[0]
	var member_actor=app.world.actors[str(member.id)]
	member_actor.position=Vector3(1.6,.16,2.75)
	var initial:float=actor.position.distance_to(member_actor.position)
	var minimum:float=INF
	for i:int in range(240):
		residents.tick(1.0/30.0)
		minimum=minf(minimum,actor.position.distance_to(member_actor.position))
		if int(residents.locations["library"]["priya"].waypoint)!=0:break
		await process_frame
	check(minimum>=initial-.01,"A visiting resident never steps closer to a body inside her gap (start %.3f m, minimum %.3f m)."%[initial,minimum])
	check(int(residents.locations["library"]["priya"].waypoint)!=0,"A waypoint occupied by another body is abandoned for the next one.")

	# --- Bare-lot boarding keeps the gap too. ---
	var boarder:Dictionary=app.household.members[0]
	var boarder_actor=app.world.actors[str(boarder.id)]
	boarder_actor.position=Vector3(3.0,.16,1.0)
	var blocker=app.spawn_actor("leo",residents.PEOPLE["leo"],Vector3(3.0,.16,6.0))
	var path:=PackedVector3Array([boarder_actor.position,Vector3(3.0,.16,6.0),Vector3(3.0,.16,10.25)])
	residents.trip={"destination":"park","resume":0,"phase":"boarding","time":0.0,"canonical":false,
		"boarding":{str(boarder.id):{"path":path,"index":0,"boarded":false,"endpoint":Vector3(3.0,.16,10.25)}}}
	boarder_actor.visible=true;blocker.visible=true
	var minimum_board:float=INF
	for i:int in range(120):
		residents.tick_trip(1.0/30.0)
		minimum_board=minf(minimum_board,boarder_actor.position.distance_to(blocker.position))
		if residents.trip.is_empty() or bool(residents.trip.boarding[str(boarder.id)].boarded):break
		await process_frame
	check(minimum_board>=gap-.001,"The boarding walk never steps inside the body gap (minimum %.3f m)."%minimum_board)
	residents.trip={}
	blocker.queue_free();app.world.actors.erase("leo")

	# --- A held-up walker gets past a standing resident: the resident yields. ---
	var walker_id:String=str(app.household.members[0].id)
	var walker:LifeActor=app.world.actors[walker_id]
	walker.position=Vector3(-2.0,.16,-1.0)
	var stood=app.spawn_actor("tom",residents.PEOPLE["tom"],Vector3(-2.0,.16,.2))
	residents.locations["library"]["tom"]={"position":[-2.0,.16,.2],"direction":-1,"phase":"visiting","wait":30.0,"rotation":0.0,"waypoint":0}
	var before_yield:Vector3=stood.position
	var route_ok:bool=app.traversal.request(walker_id,Vector3(-2.0,.16,1.6)).ok
	var advanced:bool=false
	for i:int in range(240):
		residents.tick(1.0/30.0)
		app.traversal.advance(walker_id,1.0/30.0,1)
		if walker.position.z>1.2:advanced=true;break
		await process_frame
	check(route_ok,"The member's route through the resident is publicly requested.")
	check(advanced and stood.position.distance_to(before_yield)>.1,
		"A standing resident yields aside so a held-up walker gets past (walker z=%.2f, resident moved %.2f m)."%[walker.position.z,float(stood.position.distance_to(before_yield))])
	residents.trip={}
	stood.queue_free();app.world.actors.erase("tom");actor.queue_free();app.world.actors.erase("priya")
	print("RESIDENT_BODY_GAP %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
