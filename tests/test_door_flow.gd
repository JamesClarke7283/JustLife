extends SceneTree
var checks:int=0
var failures:Array[String]=[]
var world:LifeWorld
var actor:LifeActor
var flow:Node3D
var captures:Dictionary={}
var capture_enabled:bool=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func capture(name:String)->void:
	if not capture_enabled or captures.has(name):return
	captures[name]=true
	world.camera_target=Vector3(0,1.25,5.10);world.camera.size=3.4;world.camera_angle=.38;world.camera_elevation=.32;world.update_camera()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/justlife-door-"+name+".png")
func drive(from:Vector3,to:Vector3,label:String)->void:
	actor.position=from
	var reached:bool=false;var seen:Dictionary={};var contacts:int=0;var contact_error:float=0.0;var close_error:float=0.0
	var key:String="";var was_crossed:bool=false
	for frame:int in range(200):
		flow.tick(.05)
		var next:Vector3=actor.position.move_toward(to,.08)
		var held:bool=flow.before_step(actor,"walker",next,.05)
		if not held:actor.position=next
		actor.animate(.05,1.0,not held,"")
		var state:Dictionary=flow.passages.get("walker",{})
		if not state.is_empty():
			key=str(state.door);seen[str(state.phase)]=true
			var door:Dictionary=flow.doors[key]
			if label=="Front entry" and str(state.phase)=="pass":await capture("open")
			if str(state.phase)=="pass" and absf(door.root.to_local(actor.position).z)<.15:
				check(float(door.progress)>.98,label+" crosses only after leaf is fully open");was_crossed=true
			if actor.door_presentation.has("target") and float(actor.door_presentation.weight)>.99:
				if label=="Front entry" and str(state.phase)=="reach":await capture("handle")
				var side:String=str(actor.door_presentation.side)
				var actual:Vector3=actor._joints["Forearm_"+side].to_global(actor._grip_offset(side))
				var error:float=actual.distance_to(actor.door_presentation.target)
				contact_error=maxf(contact_error,error);contacts+=1
				if str(state.phase)=="close":close_error=maxf(close_error,error)
		if actor.position.distance_to(to)<.001:reached=true;break
	check(reached,label+" completes the walk")
	check(seen.has("reach") and seen.has("open") and seen.has("pass") and seen.has("close"),label+" touches, opens, crosses and closes")
	check(was_crossed,label+" traverses the doorway")
	check(contacts>0 and contact_error<.04,label+" hand reaches rendered handle within4cm; error="+str(contact_error)+" close="+str(close_error))
	if not key.is_empty():check(float(flow.doors[key].progress)<.001,label+" closes behind the Lifelet")
	flow.cancel("walker")
func run()->void:
	capture_enabled=OS.get_cmdline_user_args().has("--capture")
	world=LifeWorld.new();root.add_child(world);world.set_process(false)
	world.create_home([])
	actor=LifeActor.new();root.add_child(actor);actor.voice_enabled=false;world.actors["walker"]=actor
	flow=world.construction.doors
	world.construction.update_cutaway(false)
	check(flow.doors.size()==4,"Starter front, rear, bedroom and bathroom all have framed doors")
	await drive(Vector3(0,.16,6.4),Vector3(0,.16,3.6),"Front entry")
	await drive(Vector3(0,.16,3.6),Vector3(0,.16,6.4),"Front exit")
	await drive(Vector3(-.4,.16,-.35),Vector3(2.4,.16,-.35),"Bedroom rotated doorway")
	await drive(Vector3(3.4,.16,.25),Vector3(3.4,.16,-2.55),"Bathroom doorway")
	var records:Array=[{"id":"a","x":-1.28,"z":0,"w":1.5,"d":.15,"height":2.6},{"id":"b","x":1.28,"z":0,"w":1.5,"d":.15,"height":2.6}]
	flow.sync(records,[])
	await drive(Vector3(0,.16,-1.4),Vector3(0,.16,1.4),"Single leaf")
	actor.configure({"name":"Child visitor","age_stage":"child"})
	await drive(Vector3(0,.16,-1.4),Vector3(0,.16,1.4),"Child single leaf")
	actor.configure({"name":"Adult visitor","age_stage":"adult"})
	actor.position=Vector3(0,.16,-.28)
	for frame:int in 12:
		flow.tick(.05);flow.before_step(actor,"walker",Vector3(0,.16,-.20),.05)
	var door:Dictionary=flow.doors.values()[0]
	var before:float=float(door.progress)
	flow.set_cutaway(true);flow.sync(records,[]);flow.set_cutaway(false)
	check(is_equal_approx(float(door.progress),before),"Wall toggle preserves active door angle")
	flow.tick(0.0)
	check(is_equal_approx(float(door.progress),before),"Pause freezes hinge progress")
	flow.cancel("walker");actor.position=Vector3(0,.16,2)
	for frame:int in 30:flow.tick(.05)
	check(float(door.progress)<.001 and actor.door_presentation.is_empty(),"Cancelled walk releases hand and automatically closes empty doorway")
	var pet:=Node3D.new();root.add_child(pet);pet.position=Vector3(0,.16,-.28)
	for frame:int in 20:flow.tick(.05);flow.before_pet_step(pet,Vector3(0,.16,-.20),.05)
	check(float(door.progress)>.98,"Pet entry automatically opens door")
	pet.position=Vector3(0,.16,2)
	for frame:int in 30:flow.tick(.05)
	check(float(door.progress)<.001,"Pet exit automatically closes door after clearing threshold")
	pet.free()
	# A loaded route can resume exactly on a doorway plane without a leaf
	# appearing around the restored body.
	actor.position=Vector3(0,.16,0)
	flow.before_step(actor,"walker",Vector3(0,.16,.08),.05)
	check(float(door.progress)>.98,"Restored body within threshold reopens leaf before its first step")
	flow.cancel("walker");actor.position=Vector3(0,.16,2)
	for frame:int in 30:flow.tick(.05)
	var fixture:=Node3D.new();root.add_child(fixture);fixture.position=Vector3(0,.16,0)
	var model:Node3D=load("res://assets/models/house_door_b.glb").instantiate();fixture.add_child(model)
	flow.sync(records,[{"kind":"house_door","id":"bought","level":0,"node":fixture}])
	door=flow.doors.values()[0]
	check(int(door.fixture_id)==fixture.get_instance_id(),"Purchased door supplies the animated leaf instead of a duplicate standard door")
	await drive(Vector3(0,.16,-1.4),Vector3(0,.16,1.4),"Purchased leaf")
	flow.sync(records,[{"kind":"archway","id":"arch","level":0,"node":fixture}])
	check(flow.doors.is_empty(),"An archway stays open without a generated door")
	fixture.free();actor.free();world.free()
	print("DOOR_FLOW ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
