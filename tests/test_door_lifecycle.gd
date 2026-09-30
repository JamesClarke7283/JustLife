extends SceneTree
## World-level door lifecycle: actual paths and articulated actors, with no
## simulation clock edits or app/UI instances competing with long playthroughs.
var world:LifeWorld
var actor:LifeActor
var flow:Node3D
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func step(next:Vector3,seconds:float=.05)->void:
	flow.tick(seconds)
	if not flow.before_step(actor,"walker",next,seconds):actor.position=next
func walk(to:Vector3,limit:int=800)->bool:
	var points:PackedVector3Array=world.path_to(actor.position,to)
	if points.is_empty():return false
	var point:int=0
	for frame:int in limit:
		while point<points.size() and actor.position.distance_to(points[point])<.001:point+=1
		if point>=points.size():return actor.position.distance_to(to)<.15
		step(actor.position.move_toward(points[point],.08))
	return false
func settle()->void:
	for frame:int in 30:flow.tick(.05)
func run()->void:
	world=LifeWorld.new();root.add_child(world);world.set_process(false);world.create_home([])
	actor=LifeActor.new();root.add_child(actor);actor.voice_enabled=false;world.actors["walker"]=actor
	flow=world.construction.doors
	actor.position=Vector3(0,.16,5.30)
	for frame:int in 12:step(Vector3(0,.16,5.22))
	var key:String=str(flow.passages.get("walker",{}).get("door",""))
	check(not key.is_empty() and float(flow.doors[key].progress)>0,"Approaching front door starts its real opening sequence")
	check(walk(Vector3(0,.16,7.0)),"Redirected Lifelet returns to front garden")
	# Keep walking (not an idle timeout), so an old door may not borrow a
	# future destination's movement to keep its ownership alive.
	check(flow.passages.is_empty(),"Walking away from a cancelled crossing releases the old doorway immediately")
	check(str(flow.doors[key].owner).is_empty(),"Cancelled crossing cannot retain door ownership")
	settle()
	check(float(flow.doors[key].progress)<.001,"Abandoned front door closes after the walker leaves")
	# A player can turn back immediately after the leaf has closed, before
	# leaving the old passage's outer clearance rectangle.
	actor.position=Vector3(0,.16,5.30)
	var closed_behind:bool=false
	for frame:int in 150:
		step(actor.position.move_toward(Vector3(0,.16,3.6),.08))
		if str(flow.passages.get("walker",{}).get("phase",""))=="leave":closed_behind=true;break
	check(closed_behind,"Crossing reaches the just-closed departure phase")
	var closed_crossings:int=0
	for frame:int in 150:
		var previous:Vector3=actor.position
		step(actor.position.move_toward(Vector3(0,.16,7.0),.08))
		if (previous.z-5.04)*(actor.position.z-5.04)<0 and float(flow.doors[key].progress)<.98:closed_crossings+=1
		if actor.position.distance_to(Vector3(0,.16,7.0))<.001:break
	check(closed_crossings==0,"Immediate return reopens door before crossing the leaf again")
	settle()
	# Saved animals can resume from the exact doorway plane too.
	var pet:=Node3D.new();root.add_child(pet);pet.position=Vector3(0,.16,5.04)
	flow.before_pet_step(pet,Vector3(0,.16,5.12),.05)
	check(float(flow.doors[key].progress)>.98,"Pet restored within doorway opens the leaf before moving out")
	pet.free();settle()
	actor.position=Vector3(0,.16,5.04)
	flow.before_step(actor,"walker",Vector3(.08,.16,5.04),.05)
	check(float(flow.doors[key].progress)>.98 and absf(float(flow.doors[key].leaves[0].hinge.rotation.y))>1.5,"Sideways restored step clears actual leaf instead of setting a zero swing direction")
	flow.cancel("walker");actor.position=Vector3(0,.16,7.0);settle()
	# A freshly restored world must not retain references to the previous
	# door or make a bought door's model disappear when its opening is removed.
	var saved:Array=world.serialize_items()
	check(bool(world.load_home(saved).ok),"Saved home reloads successfully")
	await process_frame
	actor=LifeActor.new();root.add_child(actor);actor.voice_enabled=false
	flow=world.construction.doors
	check(flow.passages.is_empty(),"Loading home starts without stale passage ownership")
	var fixture:=Node3D.new();world.add_child(fixture);fixture.position=Vector3(0,.16,5.04)
	var model:Node3D=load("res://assets/models/house_door_a.glb").instantiate();fixture.add_child(model)
	flow.sync(world.construction.records,[{"kind":"house_door","id":"test_door","node":fixture,"level":0}])
	check(model.get_parent()!=fixture,"Bought door is mounted on its hinge")
	flow.sync([],[])
	check(model.get_parent()==fixture and model.position.is_zero_approx(),"Removing the opening returns bought model to its original transform")
	fixture.free()
	flow.sync(world.construction.records,[])
	# Actors live outside the rebuilt furniture/house tree for this world test.
	world.actors["walker"]=actor;actor.position=Vector3(0,.16,7.0)
	# A visitor arriving during the closer's reach owns the threshold's
	# physical clearance. The door waits open until both bodies are clear.
	var visitor:=LifeActor.new();root.add_child(visitor);visitor.voice_enabled=false
	visitor.position=Vector3(3,.16,8);world.actors["guest"]=visitor
	actor.position=Vector3(0,.16,5.30)
	var closing:bool=false
	for frame:int in 150:
		step(actor.position.move_toward(Vector3(0,.16,3.6),.08))
		if str(flow.passages.get("walker",{}).get("phase",""))=="close":closing=true;break
	visitor.position=Vector3(0,.16,5.04)
	step(actor.position.move_toward(Vector3(0,.16,3.6),.08))
	key=""
	for candidate:String in flow.doors:
		if flow.doors[candidate].root.position.distance_to(Vector3(0,.16,5.04))<.01:key=candidate;break
	check(closing and not key.is_empty() and float(flow.doors[key].progress)>.98,"Arriving visitor prevents door from closing across occupied threshold")
	for frame:int in 150:
		flow.tick(.05)
		var next:Vector3=visitor.position.move_toward(Vector3(0,.16,7.0),.08)
		if not flow.before_step(visitor,"guest",next,.05):visitor.position=next
		if visitor.position.distance_to(Vector3(0,.16,7.0))<.001:break
	check(visitor.position.distance_to(Vector3(0,.16,7.0))<.001,"Visitor crosses occupied doorway and completes exit")
	check(walk(Vector3(0,.16,3.6)),"Original walker continues after yielding door closure to visitor")
	world.actors.erase("guest");visitor.free();settle()
	check(flow.doors.values().all(func(door:Dictionary)->bool:return str(door.owner).is_empty() and float(door.progress)<.001),"Removing departing visitor leaves no door locks or stale body references")
	actor.position=Vector3(0,.16,7.0)
	var complete:int=0
	for crossing:int in range(120):
		var destination:Vector3=Vector3(0,.16,3.6) if crossing%2==0 else Vector3(0,.16,7.0)
		if not walk(destination):break
		complete+=1
		if crossing%12==0:flow.set_cutaway(crossing%24==0)
	settle()
	check(complete==120,"120 consecutive planned front-door crossings finish")
	check(flow.passages.is_empty(),"Repeated crossings retire every completed passage")
	check(flow.doors.values().all(func(door:Dictionary)->bool:return str(door.owner).is_empty() and float(door.progress)<.001),"Repeated crossings leave all four doors closed and unowned")
	actor.free();world.free()
	print("DOOR_LIFECYCLE ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
