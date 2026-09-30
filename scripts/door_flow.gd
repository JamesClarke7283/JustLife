extends Node3D
class_name LifeDoorFlow
## Door leaves are presentation of real wall gaps, not navigation obstacles.
## Every walking substep waits for the latch and swing before entering the gap.
const Building=preload("res://scripts/building_state.gd")
const REACH_TIME:float=.38
const SWING_TIME:float=.55
const APPROACH:float=.30
const EXIT_CLEAR:float=.58
var world:Node3D
var doors:Dictionary={}
var passages:Dictionary={}
var lowered:bool=true
var animals:Dictionary={}

func initialize(owner_world:Node3D)->void:world=owner_world

static func openings(records:Array)->Array[Dictionary]:
	var groups:Dictionary={}
	for wall:Dictionary in records:
		var horizontal:bool=float(wall.w)>float(wall.d)
		var line:float=float(wall.z) if horizontal else float(wall.x)
		var key:String="%d_%s_%.3f" %[int(wall.get("level",0)),str(horizontal),line]
		if not groups.has(key):groups[key]=[]
		groups[key].append(wall)
	var found:Array[Dictionary]=[]
	for group:Array in groups.values():
		var horizontal:bool=float(group[0].w)>float(group[0].d)
		group.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.x if horizontal else a.z)<float(b.x if horizontal else b.z))
		var last:Dictionary=group[0]
		for index:int in range(1,group.size()):
			var wall:Dictionary=group[index]
			var low:float=float(last.x if horizontal else last.z)+float(last.w if horizontal else last.d)*.5
			var high:float=float(wall.x if horizontal else wall.z)-float(wall.w if horizontal else wall.d)*.5
			var width:float=high-low
			if width>=.90 and width<=2.1:
				var center:float=(low+high)*.5
				var level:int=int(wall.get("level",0))
				var position:Vector3=Vector3(center,Building.level_y(level),float(wall.z)) if horizontal else Vector3(float(wall.x),Building.level_y(level),center)
				found.append({"id":"gap_%d_%.3f_%.3f_%s" %[level,position.x,position.z,str(horizontal)],"position":position,"width":width,"yaw":0.0 if horizontal else PI*.5,"level":level,"height":float(wall.get("height",2.6)),"material":str(wall.get("color",wall.get("material","eae7d7")))})
			if high+float(wall.w if horizontal else wall.d)>low:last=wall
	return found

func sync(records:Array,items:Array)->void:
	var keep:Dictionary={}
	for opening:Dictionary in openings(records):
		var fixture:Dictionary={}
		for item:Dictionary in items:
			if str(item.kind) not in ["house_door","archway"] or not is_instance_valid(item.get("node")):continue
			if int(item.get("level",0))!=int(opening.level):continue
			var local:Vector3=Basis(Vector3.UP,-float(opening.yaw))*(item.node.position-Vector3(opening.position))
			if absf(local.x)<float(opening.width)*.5 and absf(local.z)<.3:fixture=item;break
		if str(fixture.get("kind",""))=="archway":continue
		var key:String=str(opening.id)
		var fixture_id:int=fixture.node.get_instance_id() if not fixture.is_empty() else 0
		keep[key]=true
		if doors.has(key) and int(doors[key].fixture_id)==fixture_id and is_equal_approx(float(doors[key].width),float(opening.width)):continue
		if doors.has(key):_remove(key)
		doors[key]=_create(opening,fixture)
	for key:String in doors.keys():
		if not keep.has(key):_remove(key)
	set_cutaway(lowered)

func _remove(key:String)->void:
	var door:Dictionary=doors[key]
	if is_instance_valid(door.root):door.root.queue_free()
	# Restore a purchased model before removing its derived hinge.
	if is_instance_valid(door.get("fixture")) and is_instance_valid(door.get("model")):
		var model:Node3D=door.model
		model.reparent(door.fixture,false);model.transform=door.model_rest;model.show()
		if is_instance_valid(door.get("fixture_hinge")):door.fixture_hinge.queue_free()
	doors.erase(key)
	for id:String in passages.keys():
		if str(passages[id].door)==key:cancel(id)

func _create(opening:Dictionary,fixture:Dictionary)->Dictionary:
	var root:=Node3D.new();root.name="Doorway";add_child(root)
	root.position=opening.position;root.rotation.y=float(opening.yaw)
	root.set_meta("doorway_id",str(opening.id));root.set_meta("building_level",int(opening.level))
	var width:float=float(opening.width)
	for sign_value:float in [-1.0,1.0]:world.box(root,Vector3(sign_value*(width*.5+.018),1.1,0),Vector3(.065,2.2,.20),"efe7d5")
	world.box(root,Vector3(0,2.16,0),Vector3(width+.10,.10,.20),"efe7d5")
	var header_height:float=maxf(.01,float(opening.height)-2.21)
	world.box(root,Vector3(0,2.21+header_height*.5,0),Vector3(width,header_height,.16),str(opening.material))
	var door:Dictionary={"root":root,"width":width,"level":int(opening.level),"leaves":[],"handles":[],"progress":0.0,"direction":1.0,"owner":"","idle":0.0,"fixture_id":0}
	if not fixture.is_empty():
		var node:Node3D=fixture.node
		var handle:Node3D=node.find_child("Handle",true,false)
		if handle!=null:
			var model:Node3D=handle
			while model.get_parent()!=node:model=model.get_parent()
			var hinge:=Node3D.new();hinge.name="DoorHinge";node.add_child(hinge);hinge.position.x=-.48
			door.model_rest=model.transform;model.reparent(hinge,false);model.position.x+=.48
			world.box(hinge,Vector3(.84,1.0,-.055),Vector3(.08,.07,.055),"c9cdd0")
			door.fixture=node;door.model=model;door.fixture_hinge=hinge;door.fixture_id=node.get_instance_id()
			var marker:=Marker3D.new();marker.position=Vector3(.84,1.0,.065);hinge.add_child(marker)
			door.leaves.append({"hinge":hinge,"sign":1.0,"normal":cos(node.rotation.y-root.rotation.y)})
			door.handles.append(marker)
	if door.leaves.is_empty():
		var count:int=2 if width>1.4 else 1
		var leaf_width:float=(width-.07)/float(count)
		for index:int in range(count):
			var side:float=1.0 if index==0 else -1.0
			var hinge:=Node3D.new();hinge.name="DoorHinge";root.add_child(hinge);hinge.position.x=-side*(width*.5-.025)
			var model:Node3D=load("res://assets/models/house_door_a.glb").instantiate();hinge.add_child(model)
			model.position.x=side*leaf_width*.5;model.scale.x=side*leaf_width/.96
			# Both sides have a handle, including when entering from outdoors.
			world.box(hinge,Vector3(side*(leaf_width-.12),1.0,-.055),Vector3(.08,.07,.055),"c9cdd0")
			var marker:=Marker3D.new();marker.position=Vector3(side*(leaf_width-.12),1.0,.065);hinge.add_child(marker)
			door.leaves.append({"hinge":hinge,"sign":side,"normal":1.0});door.handles.append(marker)
	world.assign_structure_layer(root,int(opening.level))
	if is_instance_valid(door.get("fixture_hinge")):world.assign_structure_layer(door.fixture_hinge,int(opening.level))
	return door

func set_cutaway(value:bool)->void:
	lowered=value
	for door:Dictionary in doors.values():
		door.root.visible=not value
		if is_instance_valid(door.get("fixture_hinge")):door.fixture_hinge.visible=not value

func _open(door:Dictionary,progress:float)->void:
	door.progress=clampf(progress,0.0,1.0)
	for leaf:Dictionary in door.leaves:
		if is_instance_valid(leaf.hinge):leaf.hinge.rotation.y=-float(door.direction)*float(leaf.sign)*float(leaf.normal)*PI*.5*float(door.progress)

func cancel(id:String)->void:
	if not passages.has(id):return
	var state:Dictionary=passages[id]
	if is_instance_valid(state.actor):state.actor.door_presentation={}
	if doors.has(str(state.door)) and str(doors[state.door].owner)==id:doors[state.door].owner=""
	passages.erase(id)

func _occupied(door:Dictionary,except:Node3D=null)->bool:
	for actor:Node3D in world.actors.values():
		if actor==except or not actor.visible:continue
		var at:Vector3=door.root.to_local(actor.global_position)
		if absf(at.y)<.25 and absf(at.x)<float(door.width)*.5+.18 and absf(at.z)<.78:return true
	for key:String in animals.keys():
		if not is_instance_valid(animals[key]):animals.erase(key);continue
		var actor:Node3D=animals[key]
		if not actor.visible:continue
		var at:Vector3=door.root.to_local(actor.global_position)
		if absf(at.y)<.25 and absf(at.x)<float(door.width)*.5+.15 and absf(at.z)<.78:return true
	return false

func _present(actor:LifeActor,door:Dictionary,weight:float)->void:
	var grip:Marker3D=door.handles[0]
	for other:Marker3D in door.handles:
		if actor.global_position.distance_squared_to(other.global_position)<actor.global_position.distance_squared_to(grip.global_position):grip=other
	var target:Vector3=grip.to_global(Vector3(0,0,-.12 if grip.to_local(actor.global_position).z<0 else 0.0))
	var local:Vector3=door.root.to_local(actor.global_position)
	actor.rotation.y=door.root.global_rotation.y+(PI if local.z>0 else 0.0)
	var side:String="R" if actor.to_local(target).x>=0 else "L"
	actor.door_presentation={"target":target,"side":side,"weight":weight}

## Return true when this substep must wait at the handle or while closing.
## The caller consumes the frame's remaining movement time without reporting
## a collision, so an intentional latch pause cannot trigger standoff/replans.
func before_step(actor:LifeActor,id:String,to:Vector3,time:float)->bool:
	if str(actor.profile.get("age_stage","adult"))=="baby":return before_pet_step(actor,to,time)
	if passages.has(id) and not doors.has(str(passages[id].door)):cancel(id)
	if not passages.has(id):
		for key:String in doors:
			var door:Dictionary=doors[key]
			var from:Vector3=door.root.to_local(actor.global_position)
			var next:Vector3=door.root.to_local(to)
			if absf(from.y)>.25 or absf(from.x)>float(door.width)*.5-.05:continue
			var in_threshold:bool=absf(from.z)<.16
			if (absf(next.z)>=absf(from.z) and not in_threshold) or absf(from.z)>APPROACH:continue
			if in_threshold and float(door.progress)<.98:
				door.direction=_crossing_direction(from,next,door);_open(door,1.0)
			var direction:float=_crossing_direction(from,next,door)
			passages[id]={"door":key,"actor":actor,"phase":"reach" if float(door.progress)<.98 else "pass","clock":0.0,"direction":direction,"touched":true}
			if str(door.owner).is_empty():door.owner=id;door.direction=direction
			break
	if not passages.has(id):return false
	var state:Dictionary=passages[id];var door:Dictionary=doors[state.door]
	state.touched=true;door.idle=0.0
	var local:Vector3=door.root.to_local(actor.global_position)
	var next_local:Vector3=door.root.to_local(to)
	# Requests can replace a route without an idle frame. Keeping the old
	# passage merely because movement is still ticking would hold this door
	# forever and suppress every later doorway on the new route.
	var outside:bool=absf(local.y)>.25 or absf(local.z)>1.0 or absf(local.x)>float(door.width)*.5+.4
	var retreating:bool=local.z*float(state.direction)<-.02 and (next_local.z-local.z)*float(state.direction)<-.00001
	if outside or (str(state.phase) in ["reach","open","pass"] and retreating):
		cancel(id);return false
	if str(state.phase)=="leave":
		# The old crossing has finished. Turning back immediately is a new
		# entry, even while still within the previous departure clearance.
		if local.z*(next_local.z-local.z)<-.00001:
			cancel(id)
			return before_step(actor,id,to,time)
		return false
	if str(state.phase)=="pass":
		actor.door_presentation={}
		if local.z*float(state.direction)<EXIT_CLEAR:return false
		if _occupied(door,actor) or (not str(door.owner).is_empty() and str(door.owner)!=id):
			cancel(id);return false
		state.phase="close_approach";state.clock=0.0;door.owner=id
	if str(state.phase) in ["close_approach","close"] and _occupied(door,actor):
		cancel(id);return false
	if str(state.phase)=="close_approach":
		var grip:Marker3D=door.handles[0]
		for other:Marker3D in door.handles:
			if actor.global_position.distance_squared_to(other.global_position)<actor.global_position.distance_squared_to(grip.global_position):grip=other
		var handle:Vector3=door.root.to_local(grip.global_position)
		var stand:Vector3=local
		stand.x=clampf(handle.x,-float(door.width)*.5+.32,float(door.width)*.5-.32)
		var destination:Vector3=door.root.to_global(stand)
		var next:Vector3=actor.global_position.move_toward(destination,time*1.2)
		var level:int=world.point_level(next)
		var clear:bool=level>=0 and world.lot_navigation.segment_clear(level,actor.global_position,next)
		for other:Node3D in world.actors.values():
			if other!=actor and other.visible and next.distance_to(other.global_position)<.72:clear=false
		if not clear:
			# A busy doorway remains open; its automatic closer waits for space.
			cancel(id);return false
		actor.door_presentation={"walking":true}
		var direction:Vector3=destination-actor.global_position
		if direction.length()>.01:actor.rotation.y=atan2(direction.x,direction.z)
		actor.global_position=next
		if next.distance_to(destination)<.001:state.phase="close";state.clock=0.0;actor.door_presentation={}
		return true
	if str(door.owner).is_empty():door.owner=id;door.direction=float(state.direction)
	if str(door.owner)!=id:
		actor.door_presentation={}
		if float(door.progress)>=.98:state.phase="pass";return false
		return true
	state.clock=float(state.clock)+maxf(0.0,time)
	match str(state.phase):
		"reach":
			_present(actor,door,smoothstep(0.0,REACH_TIME*.65,float(state.clock)))
			if float(state.clock)>=REACH_TIME:state.phase="open";state.clock=0.0
		"open":
			var part:float=clampf(float(state.clock)/SWING_TIME,0.0,1.0)
			_open(door,smoothstep(0.0,1.0,part))
			_present(actor,door,1.0-smoothstep(0.0,.25,part))
			if part>=1.0:state.phase="pass";actor.door_presentation={}
		"close":
			var part:float=clampf((float(state.clock)-.20)/SWING_TIME,0.0,1.0)
			_open(door,1.0-smoothstep(0.0,1.0,part))
			_present(actor,door,smoothstep(0.0,.16,float(state.clock))*(1.0-smoothstep(0.0,.25,part)))
			if part>=1.0:state.phase="leave";door.owner="";actor.door_presentation={}
	return true

## A host can keep an already opened door clear while an invited guest passes.
func hold_open(key:String,host_id:String)->void:
	if not doors.has(key):return
	var door:Dictionary=doors[key]
	if float(door.progress)>=.98:
		door.owner=host_id;door.idle=0.0

func restore_hold(key:String,host_id:String,progress:float,direction:float,close_clock:float=-1.0)->void:
	if not doors.has(key):return
	var door:Dictionary=doors[key]
	door.direction=direction;_open(door,progress)
	if progress>=.98 or close_clock>=0:door.owner=host_id
	if close_clock>=0 and world.actors.has(host_id):
		var actor:LifeActor=world.actors[host_id]
		passages[host_id]={"door":key,"actor":actor,"phase":"close","clock":close_clock,"direction":direction,"touched":true}
		var part:float=clampf((close_clock-.20)/SWING_TIME,0.0,1.0)
		_present(actor,door,smoothstep(0.0,.16,close_clock)*(1.0-smoothstep(0.0,.25,part)))
		actor.reconstruct_door_pose()

func release_hold(key:String,host_id:String)->void:
	if doors.has(key) and str(doors[key].owner)==host_id:doors[key].owner=""

## Explicit hospitality close uses the same real handle and leaf sequence.
func close_by(actor:LifeActor,host_id:String,key:String,time:float)->bool:
	if not doors.has(key):return true
	var door:Dictionary=doors[key]
	if float(door.progress)<=.001:cancel(host_id);return true
	if _occupied(door,actor):return false
	# Walking up to the latch can itself create a normal crossing passage. The
	# host has now reached the explicit closing stance, so that earlier pass or
	# completed doorway must yield to this close; keep only a matching live close.
	if passages.has(host_id) and (str(passages[host_id].door)!=key or str(passages[host_id].phase)!="close"):
		cancel(host_id)
	if not passages.has(host_id):
		door.owner=host_id
		passages[host_id]={"door":key,"actor":actor,"phase":"close","clock":0.0,"direction":float(door.direction),"touched":true}
	before_step(actor,host_id,actor.global_position,time)
	var finished:bool=float(door.progress)<=.001
	if finished:cancel(host_id)
	return finished

## Retire abandoned/cancelled presentations and gently close empty doorways.
## This also covers a route which finishes just beyond a threshold.
func tick(time:float)->void:
	if time<=0:return
	for id:String in passages.keys():
		var state:Dictionary=passages[id]
		if not is_instance_valid(state.actor) or not state.actor.visible or not bool(state.get("touched",false)):cancel(id)
		else:state.touched=false
	for door:Dictionary in doors.values():
		if not str(door.owner).is_empty() or _occupied(door):door.idle=0.0;continue
		door.idle=float(door.idle)+time
		if float(door.idle)>.35 and float(door.progress)>0:_open(door,maxf(0.0,float(door.progress)-time/SWING_TIME))

## Automatic entry for pets, which cannot reach a human door handle.
func before_pet_step(actor:Node3D,to:Vector3,time:float)->bool:
	animals[str(actor.get_instance_id())]=actor
	for door:Dictionary in doors.values():
		var from:Vector3=door.root.to_local(actor.global_position)
		var next:Vector3=door.root.to_local(to)
		if absf(from.y)>.25 or absf(from.x)>float(door.width)*.5-.05:continue
		if absf(from.z)<.16:
			# A loaded pet (or crawling baby) may already occupy the leaf's
			# sweep. Clear it before its first outward or sideways step.
			if float(door.progress)<.98:
				door.direction=_crossing_direction(from,next,door);_open(door,1.0)
			door.idle=0.0;return false
		if absf(next.z)>APPROACH or absf(next.z)>=absf(from.z):continue
		door.idle=0.0
		if float(door.progress)>=.98:return false
		if str(door.owner).is_empty():
			door.direction=signf(next.z-from.z)
			_open(door,float(door.progress)+time/SWING_TIME)
		return true
	return false

func _crossing_direction(from:Vector3,to:Vector3,door:Dictionary)->float:
	var direction:float=signf(to.z-from.z)
	return direction if direction!=0.0 else float(door.direction)
