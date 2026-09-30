extends Node
class_name LifeStrollerFlow
## A walk is a sequence of ordinary floor journeys. The queued action owns the
## stage, child and clock; nodes below are only reconstructible presentation.
const KINDS: Array[String] = ["baby_pram", "pushchair"]
const STAGES: Array[String] = ["fetch", "pickup", "carry", "buckle", "walk", "home", "unbuckle", "return_child", "put_down", "done"]
const STILL: Array[String] = ["pickup", "buckle", "unbuckle", "put_down"]
const SECONDS: float = 2.0
var app: Node
var views: Dictionary = {}

static func owns(action: Dictionary) -> bool:
	return str(action.get("id", "")) == LifeOutdoorActs.ACTION_ID and str(action.get("target_kind", "")) in KINDS

static func vector(value: Variant) -> Vector3:
	return value if value is Vector3 else Vector3(float(value[0]), float(value[1]), float(value[2]))

static func packed(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func save_error(action: Dictionary) -> String:
	if not action.has("stroller"):return ""
	if not owns(action) or not action.stroller is Dictionary:return "Invalid stroller activity."
	var state:Dictionary=action.stroller
	if str(state.get("stage", "")) not in STAGES or not state.get("child") is String or str(state.child).is_empty():return "Invalid stroller passenger or stage."
	for key:String in ["child_home", "child_visual", "pram_home", "handle_home", "fetch", "destination"]:
		if not LifeJourneyState.vector_valid(state.get(key)):return "Invalid stroller position."
	if not LifeJourneyState.number(state.get("time"),0,SECONDS+.1) or not LifeJourneyState.number(state.get("leg"),0,4,true) or not LifeJourneyState.number(state.get("yaw"),-100,100) or not state.get("cancelled") is bool:return "Invalid stroller progress."
	return ""

static func household_error(data:Dictionary)->String:
	var people:Dictionary={};var furniture:Dictionary={};var used:Dictionary={}
	for member:Dictionary in data.members:people[str(member.id)]=member.state
	for item:Variant in data.get("world",[]):
		if item is Dictionary:furniture[str(item.get("id", ""))]=item
	for member:Dictionary in data.members:
		for action:Dictionary in member.state.get("action_queue",[]):
			if not action.has("stroller"):continue
			var error:String=save_error(action)
			if not error.is_empty():return error
			var child_id:String=str(action.stroller.child)
			var target:String=str(action.target_id)
			if child_id==str(member.id) or not people.has(child_id) or used.has(child_id) or used.has(target):return "Invalid or duplicate stroller passenger."
			var child:Dictionary=people[child_id]
			if LifeLifecycle.stage_for(child.character) not in ["baby","child"] or not child.get("action_queue",[]).is_empty() or not child.get("away_state",{}).is_empty():return "The stroller passenger is unavailable."
			if str(action.target_kind)=="baby_pram" and LifeLifecycle.stage_for(child.character)!="baby":return "A pram needs an infant passenger."
			if not furniture.has(target) or str(furniture[target].kind)!=str(action.target_kind):return "The saved stroller is missing."
			used[child_id]=true;used[target]=true
	return ""

func passenger(sim:LifeSim)->bool:
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if owns(action) and action.has("stroller") and str(action.stroller.stage)!="done" and app.household.member_sim(str(action.stroller.child))==sim:return true
	return false

func child_for(sim:LifeSim,kind:String="")->String:
	for age:String in (["baby"] if kind=="baby_pram" else ["baby", "child"]):
		for member:Dictionary in app.household.members:
			var child:LifeSim=member.sim
			if child==sim or child.is_away() or LifeLifecycle.stage_for(child.character)!=age or passenger(child):continue
			if not child.action_queue.is_empty():continue
			if is_instance_valid(app.world.actors.get(str(member.id))):return str(member.id)
	return ""

func availability(sim:LifeSim,target_id:String)->String:
	var item:Dictionary=app._find_item(target_id)
	if item.is_empty() or str(item.kind) not in KINDS:return "Choose a pram or pushchair."
	var current:Dictionary=sim.get_current_action()
	if owns(current) and str(current.target_id)==target_id and current.has("stroller"):return ""
	for member:Dictionary in app.household.members:
		for action:Dictionary in member.sim.action_queue:
			if owns(action) and str(action.target_id)==target_id and member.sim!=sim:return "Another Lifelet is using this stroller."
	if child_for(sim,str(item.kind)).is_empty():return "A baby or child needs to be home and free for a walk."
	return ""

func resolve(sim:LifeSim, action:Dictionary)->void:
	if not owns(action):return
	if action.has("stroller"):
		action.target_position=vector(action.stroller.destination)
		return
	var reason:String=availability(sim,str(action.target_id))
	if not reason.is_empty():sim._emit_notice(reason);sim.cancel_action();return
	var item:Dictionary=app._find_item(str(action.target_id))
	var child_id:String=child_for(sim,str(item.kind))
	var child:LifeActor=app.world.actors[child_id]
	var adult:LifeActor=app.world.actors[sim.cooperation_member_id]
	var toward:Vector3=adult.position-child.position;toward.y=0
	if toward.length()<.1:toward=Vector3.FORWARD
	var fetch:Vector3=app.world.nearest_clear_point(child.position+toward.normalized()*.95,app.world.point_level(child.position),2)
	var handle:Vector3=_handle(item)
	var handle_home:Vector3=app.world.nearest_clear_point(Vector3(handle.x, item.node.position.y,handle.z)-item.node.global_basis.orthonormalized().z*.36,app.world.item_level(item),2)
	if not fetch.is_finite() or not handle_home.is_finite():sim._emit_notice("Make space beside the child and stroller first.");sim.cancel_action();return
	action["stroller"]={"stage":"fetch","child":child_id,"time":0.0,"leg":0,"child_home":packed(child.position),"child_visual":packed(child.visual.global_position),"pram_home":packed(item.node.position),"handle_home":packed(handle_home),"fetch":packed(fetch),"destination":packed(fetch),"yaw":item.node.rotation.y,"cancelled":false}
	action["label"]="Walk with "+str(app.household.member_sim(child_id).character.name)
	action.target_position=fetch
	app.traversal.cancel(child_id)

func before_begin(sim:LifeSim,action:Dictionary)->bool:
	if not owns(action):return true
	if not action.has("stroller"):resolve(sim,action)
	if not action.has("stroller"):return false
	var state:Dictionary=action.stroller
	match str(state.stage):
		"fetch":_stage(state,"pickup")
		"carry":_stage(state,"buckle")
		"walk":
			state.leg=int(state.leg)+1
			if int(state.leg)>=3:_route(sim,action,"home",vector(state.handle_home))
			else:_route(sim,action,"walk",_waypoint(int(state.leg)))
		"home":_stage(state,"unbuckle")
		"return_child":_stage(state,"put_down")
		"done":return true
	return false

func _stage(state:Dictionary,stage:String)->void:
	state.stage=stage;state.time=0.0

func _waypoint(index:int)->Vector3:
	var exit:Vector3=app.world.lot_exit_position()
	var desired:Vector3=exit+Vector3(-7 if index==1 else (7 if index==2 else 0),0,0)
	return app.world.nearest_clear_point(desired,0,4)

func _route(sim:LifeSim,action:Dictionary,stage:String,to:Vector3)->void:
	if not to.is_finite():sim._emit_notice("There is no clear route for this stroller walk.");sim.cancel_action();return
	_stage(action.stroller,stage)
	action.stroller.destination=packed(to);action.target_position=to
	app._member_action_started(sim.cooperation_member_id,action)

func holds(sim:LifeSim)->bool:
	if passenger(sim):return true
	var action:Dictionary=sim.get_current_action()
	return owns(action) and action.has("stroller") and str(action.stroller.stage) in STILL

func advance(id:String,delta:float)->void:
	var sim:LifeSim=app.household.member_sim(id)
	var action:Dictionary=sim.get_current_action()
	if not owns(action) or not action.has("stroller"):return
	var state:Dictionary=action.stroller
	if str(state.stage)=="done":return
	if app._find_item(str(action.target_id)).is_empty() or not is_instance_valid(app.world.actors.get(str(state.child))):sim.cancel_action();return
	if str(state.stage) in STILL:
		state.time=minf(SECONDS,float(state.time)+delta*float(sim.speed))
		if float(state.time)>=SECONDS:
			match str(state.stage):
				"pickup":_route(sim,action,"carry",vector(state.handle_home))
				"buckle":
					var item:Dictionary=app._find_item(str(action.target_id))
					item["carried"]=true;item["rest"]={"x":vector(state.pram_home).x,"y":vector(state.pram_home).y,"z":vector(state.pram_home).z,"rotation":rad_to_deg(float(state.yaw))}
					app.world.rebuild_navigation()
					_route(sim,action,"walk",_waypoint(0))
				"unbuckle":_route(sim,action,"return_child",vector(state.fetch))
				"put_down":
					_stage(state,"done")
					cleanup(id,action)
					if bool(state.cancelled):sim.cancel_action()
					else:
						# Credit the actual completed trip once; it may take longer than
						# the nominal activity duration in a large house.
						sim._apply_continuous_effects(action,1.0)
						action.elapsed=float(action.duration);action.progress=1.0
						sim.begin_current_action()

func cancel_request(sim:LifeSim)->bool:
	var action:Dictionary=sim.get_current_action()
	if not owns(action) or not action.has("stroller"):return false
	var state:Dictionary=action.stroller
	if str(state.stage) in ["fetch", "done"]:return false
	state.cancelled=true
	if str(state.stage) in ["walk", "home"]:
		_route(sim,action,"home",vector(state.handle_home))
	elif str(state.stage) in ["pickup", "carry", "buckle"]:
		_route(sim,action,"return_child",vector(state.fetch))
	return true

func _find_mesh(node:Node,wanted:String)->MeshInstance3D:
	if node is MeshInstance3D and node.name.to_lower().begins_with(wanted.to_lower()):return node
	for child:Node in node.get_children():
		var found:MeshInstance3D=_find_mesh(child,wanted)
		if found!=null:return found
	return null

func _handle(item:Dictionary)->Vector3:
	var mesh:MeshInstance3D=_find_mesh(item.node,"Handle")
	return mesh.to_global(mesh.get_aabb().get_center()) if mesh!=null else item.node.to_global(Vector3(0,.95,-.28))

func _seat(item:Dictionary)->Vector3:
	var mesh:MeshInstance3D=_find_mesh(item.node,"Seat" if str(item.kind)=="pushchair" else "Body")
	if mesh==null:return item.node.to_global(Vector3(0,.6,0))
	var bounds:AABB=mesh.get_aabb()
	return mesh.to_global(Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z))

func _mount(id:String,action:Dictionary)->Dictionary:
	if views.has(id):return views[id]
	var child:LifeActor=app.world.actors[str(action.stroller.child)]
	var holder:=Node3D.new();holder.name="StrollerPassenger_"+str(action.stroller.child);app.world.add_child(holder)
	var rest_visual:Transform3D=child.visual.transform
	child.visual.reparent(holder)
	child.visible=false
	var view:Dictionary={"child":child,"holder":holder,"rest_visual":rest_visual}
	var item:Dictionary=app._find_item(str(action.target_id))
	if str(item.kind)=="baby_pram":
		var hood:MeshInstance3D=_find_mesh(item.node,"Hood")
		if hood!=null:
			view["hood"]=hood;view["hood_rest"]=hood.transform
			hood.position.z-=.22;hood.scale.z*=.3
	views[id]=view
	return view

func present(id:String)->void:
	var sim:LifeSim=app.household.member_sim(id)
	if sim==null:return
	var action:Dictionary=sim.get_current_action()
	if not owns(action) or not action.has("stroller"):return
	var state:Dictionary=action.stroller
	if str(state.stage) in ["fetch", "done"]:return
	var item:Dictionary=app._find_item(str(action.target_id))
	if item.is_empty():return
	var adult:LifeActor=app.world.actors[id]
	var view:Dictionary=_mount(id,action)
	var child:LifeActor=view.child
	var stage:String=str(state.stage)
	var p:float=smoothstep(0.0,1.0,float(state.time)/SECONDS)
	var bend:float=sin(p*PI) if stage in ["pickup","put_down"] else (.80*sin(p*PI) if stage in ["buckle","unbuckle"] else 0.0)
	adult.visual.position.y=-.55*bend
	adult.visual.rotation.x=.45*bend
	if stage in ["pickup", "put_down"]:
		var to:Vector3=vector(state.child_home)-adult.position;to.y=0
		if to.length()>.01:adult.rotation.y=atan2(to.x,to.z)
	elif stage in ["buckle", "unbuckle"]:
		var to:Vector3=item.node.position-adult.position;to.y=0
		if to.length()>.01:adult.rotation.y=atan2(to.x,to.z)
	var frame:Basis=Basis(Vector3.UP,adult.rotation.y)
	var held:Vector3=adult.position+frame*Vector3(0,adult._hip_height+.30*adult._proportion-.55*bend,.30)
	var seat:Vector3=_seat(item)
	if stage in ["walk", "home"]:
		# Wheelbase follows the walker's heading; the authored handle remains
		# at reachable arm length, with both hands solved to the real mesh.
		var local_handle:Vector3=item.node.to_local(_handle(item))
		item.node.rotation.y=adult.rotation.y
		var handle_target:Vector3=adult.position+frame*Vector3(0,0,.34)
		item.node.position=Vector3(handle_target.x,adult.position.y,handle_target.z)-frame*Vector3(local_handle.x,0,local_handle.z)
		seat=_seat(item)
	var in_seat:bool=stage in ["walk", "home"]
	var lay:bool=str(item.kind)=="baby_pram"
	var seat_basis:Basis=item.node.global_basis.orthonormalized()
	var seat_origin:Vector3=seat+Vector3(0,.015,0)
	if lay:
		seat_origin+=seat_basis.x*.23+Vector3.UP*.065*child._proportion
		seat_basis=seat_basis*Basis(Vector3.UP,PI*.5)*Basis(Vector3.RIGHT,-PI*.5)
	else:
		seat_origin-=seat_basis.y*child._hip_height*child._height
	var child_position:Vector3=held-frame.y*child._hip_height*child._height
	var child_basis:Basis=frame
	if stage=="pickup":child_position=vector(state.child_visual).lerp(child_position,p)
	elif stage=="put_down":child_position=child_position.lerp(vector(state.child_visual),p)
	elif stage=="buckle":
		child_position=child_position.lerp(seat_origin,p);child_basis=frame.slerp(seat_basis,p)
	elif stage=="unbuckle":
		child_position=seat_origin.lerp(child_position,p);child_basis=seat_basis.slerp(frame,p)
	elif in_seat:child_position=seat_origin;child_basis=seat_basis
	child.visual.global_transform=Transform3D(child_basis*Basis.from_scale(Transform3D(view.rest_visual).basis.get_scale()),child_position)
	child.stroller_pose({},true,lay and (in_seat or stage in ["buckle","unbuckle"]))
	var hands:Dictionary={}
	if in_seat:
		var handle:Vector3=_handle(item)
		var spread:float=.17 if str(item.kind)=="pushchair" else .22
		hands={"L":handle-frame.x*spread,"R":handle+frame.x*spread}
	else:
		var contact:Vector3=child.visual.to_global(Vector3(0,child._hip_height,.03))
		hands={"L":contact-frame.x*.11,"R":contact+frame.x*.11}
		if stage=="buckle" and p>.8:
			var handle:Vector3=_handle(item)
			var release:float=smoothstep(.8,1.0,p)
			hands.L=Vector3(hands.L).lerp(handle-frame.x*.18,release)
			hands.R=Vector3(hands.R).lerp(handle+frame.x*.18,release)
	if adult.door_presentation.has("target"):
		var side:String=str(adult.door_presentation.side)
		hands[side]=Vector3(hands[side]).lerp(adult.door_presentation.target,float(adult.door_presentation.weight))
	adult.stroller_pose(hands,false,false,bend,.85 if in_seat else .35)

func cleanup(id:String,action:Dictionary)->void:
	if views.has(id):
		var view:Dictionary=views[id]
		if is_instance_valid(view.get("hood")):view.hood.transform=view.hood_rest
		if is_instance_valid(view.child):
			view.child.visual.reparent(view.child)
			view.child.visual.transform=view.rest_visual
			view.child.visible=true
		if is_instance_valid(view.holder):view.holder.queue_free()
		views.erase(id)
	if action.has("stroller"):
		var item:Dictionary=app._find_item(str(action.target_id))
		if not item.is_empty():
			item.node.position=vector(action.stroller.pram_home);item.node.rotation.y=float(action.stroller.yaw)
			item["carried"]=false;item.erase("rest")
			app.world.rebuild_navigation()

func canceled(sim:LifeSim,action:Dictionary)->void:
	if owns(action) and action.has("stroller"):cleanup(sim.cooperation_member_id,action)

func reset()->void:
	for id:String in views.keys():
		var sim:LifeSim=app.household.member_sim(id)
		cleanup(id,sim.get_current_action() if sim!=null else {})

func restore()->String:
	var used:Dictionary={}
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if not owns(action) or not action.has("stroller"):continue
		var state:Dictionary=action.stroller
		var item:Dictionary=app._find_item(str(action.target_id))
		var child:LifeSim=app.household.member_sim(str(state.child))
		if item.is_empty() or child==null or child==member.sim or LifeLifecycle.stage_for(child.character) not in ["baby","child"] or not child.action_queue.is_empty() or used.has(str(state.child)) or used.has(str(action.target_id)):return "The saved stroller has no available child or stroller."
		if str(item.kind)=="baby_pram" and LifeLifecycle.stage_for(child.character)!="baby":return "A pram needs an infant passenger."
		used[str(state.child)]=true;used[str(action.target_id)]=true
		action.target_position=vector(state.destination)
		if str(state.stage) in ["walk","home","unbuckle","return_child","put_down"]:
			item["carried"]=true;item["rest"]={"x":vector(state.pram_home).x,"y":vector(state.pram_home).y,"z":vector(state.pram_home).z,"rotation":rad_to_deg(float(state.yaw))}
		present(str(member.id))
	if not used.is_empty():app.world.rebuild_navigation()
	return ""
