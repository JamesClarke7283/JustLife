extends RefCounted
class_name LifeTraversal
## The real route, stair FIFO and movement-only safety transit. A stair remains
## owned through its supported exit clearance, independently of the action queue.
const Gait=preload("res://scripts/stair_gait.gd")
const Building=preload("res://scripts/building_state.gd")
const WALK_SPEED:float=1.6
const BODY_GAP:float=.72
const ROUTE_CLEARANCE:float=BODY_GAP+.06
const REPLAN_OBSERVATION_TIME:float=.25
var app:Node
var routes:Dictionary={}
var stairs:Dictionary={}
var next_ticket:int=1
var next_identity:int=1
var courtesy=preload("res://scripts/courtesy.gd").new()

func _init(controller:Node)->void:app=controller

func reset()->void:
	routes.clear();stairs.clear();next_ticket=1;next_identity=1;courtesy.reset()

func busy(id:String)->bool:
	return routes.has(id) and str(routes[id].phase) in ["entry","transit","clear"]

func safety(id:String)->bool:return routes.has(id) and bool(routes[id].safety)
func active(id:String)->bool:return routes.has(id)

func cancel(id:String)->bool:
	if not routes.has(id):return false
	if busy(id):
		routes[id].safety=true
		return true
	_remove_waiter(id)
	routes.erase(id)
	courtesy.reconcile(self)
	return false

func request(id:String,destination:Vector3)->Dictionary:
	if busy(id):return {"ok":false,"error":"Finish the current stair crossing first."}
	var actor:LifeActor=app.world.actors.get(id)
	if not is_instance_valid(actor):return {"ok":false,"error":"Missing moving Lifelet."}
	courtesy.reconcile(self)
	if courtesy.preserve_request(self,id,destination):
		var kept:Dictionary=routes[id]
		if int(kept.generation)==app.world.lot_navigation.generation and courtesy.generation_current(self):return {"ok":true,"points":PackedVector3Array([actor.position,destination]),"already_reached":false}
		if courtesy.rebuild(self):return {"ok":true,"points":PackedVector3Array([actor.position,destination]),"already_reached":false}
	var route:Dictionary=app.world.route_to(actor.position,destination)
	if not bool(route.ok):return route
	var legs:Array=[]
	for source:Dictionary in route.segments:
		var key:String=str(source.kind)+":"+str(source.stair_id)
		if legs.is_empty() or str(legs[-1].key)!=key:
			legs.append({"key":key,"kind":str(source.kind),"stair_id":str(source.stair_id),"points":PackedVector3Array([source.from]),"from":source.from,"to":source.to})
		legs[-1].points.append(source.to);legs[-1].to=source.to
	for leg:Dictionary in legs:
		if leg.kind!="stair":continue
		var node:Node3D=app.world.construction.stair_nodes.get(str(leg.stair_id))
		if not is_instance_valid(node):return {"ok":false,"error":"The route's staircase no longer exists."}
		leg.direction=1 if leg.to.y>leg.from.y else -1
		leg.schedule=Gait.plan(node.global_transform,int(leg.direction),actor.stair_rear_extent(int(leg.direction)))
		var first:Dictionary=Gait.sample(leg.schedule,0);var last:Dictionary=Gait.sample(leg.schedule,leg.schedule.length)
		if first.root.distance_to(leg.from)>.001 or last.root.distance_to(leg.to)>.001:return {"ok":false,"error":"Stair route and authored landings disagree."}
	# A harmless navigation rebuild does not make an arrived waiter a new arrival.
	if routes.has(id) and str(routes[id].phase)=="waiting" and Vector3(routes[id].destination).is_equal_approx(destination):
		var old:Dictionary=routes[id];var old_leg:Dictionary=old.legs[int(old.cursor)]
		for index:int in legs.size():
			var leg:Dictionary=legs[index]
			if leg.kind!="stair" or str(leg.stair_id)!=str(old_leg.stair_id):continue
			if leg.from!=old_leg.from or leg.to!=old_leg.to or leg.schedule.transform!=old_leg.schedule.transform:continue
			if actor.position.distance_to(old.wait)>.001 or _floor_route(actor.position,leg.from).is_empty():continue
			old.legs=legs;old.cursor=index;old.generation=int(route.generation)
			return {"ok":true,"points":route.points,"already_reached":false}
	_remove_waiter(id)
	if routes.get(id,{}).has("replan_observation"):courtesy.blocked.erase(id)
	routes[id]={"identity":next_identity,"generation":int(route.generation),"destination":destination,"legs":legs,"cursor":0,"phase":"route","points":PackedVector3Array(),"point":0,"prepared":false,"wait":Vector3.INF,"ticket":0,"distance":0.0,"safety":false,"stair_id":"","exit":Vector3.INF,"clear":Vector3.INF,"error":""}
	next_identity+=1
	return {"ok":true,"points":route.points,"already_reached":bool(route.already_reached)}

func _remove_waiter(id:String)->void:
	for key:String in stairs:
		var queue:Array=stairs[key].queue
		for i:int in range(queue.size()-1,-1,-1):
			if str(queue[i].id)==id:queue.remove_at(i)

func _lock(stair_id:String)->Dictionary:
	if not stairs.has(stair_id):stairs[stair_id]={"owner":"","queue":[],"exit":Vector3.INF,"clear":Vector3.INF}
	return stairs[stair_id]

func _same_floor(a:Vector3,b:Vector3)->bool:return absf(a.y-b.y)<.1

func _free(id:String,point:Vector3,include_waits:bool=true)->bool:
	if not courtesy.point_allowed(self,id,point):return false
	var level:int=app.world.point_level(point)
	if level<0 or not app.world.lot_navigation.point_clear(level,point):return false
	for other_id:String in app.world.actors:
		if other_id==id:continue
		var actor:LifeActor=app.world.actors[other_id]
		if not actor.visible:continue
		if _same_floor(point,actor.position) and point.distance_to(actor.position)<BODY_GAP:return false
	for key:String in stairs:
		var lock:Dictionary=stairs[key]
		if str(lock.owner).is_empty() or str(lock.owner)==id:continue
		for reserved:Vector3 in [lock.exit,lock.clear]:
			if reserved.is_finite() and _same_floor(point,reserved) and point.distance_to(reserved)<BODY_GAP:return false
	if include_waits:
		for other_id:String in routes:
			if other_id==id:continue
			var wait:Vector3=routes[other_id].wait
			if wait.is_finite() and _same_floor(point,wait) and point.distance_to(wait)<BODY_GAP:return false
	for reserved:Vector3 in courtesy.reservations(self,id):
		if _same_floor(point,reserved) and point.distance_to(reserved)<BODY_GAP:return false
	return true

func _occupied(id:String)->Array[Vector3]:
	var occupied:Array[Vector3]=[]
	for other_id:String in app.world.actors:
		if other_id!=id and app.world.actors[other_id].visible:occupied.append(app.world.actors[other_id].position)
	for lock:Dictionary in stairs.values():
		if str(lock.owner).is_empty() or str(lock.owner)==id:continue
		occupied.append(lock.exit);occupied.append(lock.clear)
	occupied.append_array(courtesy.reservations(self,id))
	return occupied

func _floor_route(from:Vector3,to:Vector3,id:String="")->PackedVector3Array:
	var result:Dictionary
	if id.is_empty():result=app.world.route_to(from,to)
	else:result=app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(app.world.point_level(from),from),LifeLotNavigation.floor_location(app.world.point_level(to),to),_occupied(id),ROUTE_CLEARANCE)
	if not bool(result.ok):return []
	for segment:Dictionary in result.segments:
		if str(segment.kind)!="floor":return []
	return result.points

func _waiting_place(id:String,leg:Dictionary)->Dictionary:
	var actor:LifeActor=app.world.actors[id]
	var entry:Vector3=leg.from
	var basis:Basis=leg.schedule.transform.basis
	var best:Dictionary={};var length:float=INF
	# Wait off the actual landing, leaving both an arriving body and an exiting
	# body room. Candidate routes stay on this floor and never enter another stair.
	for depth:float in [.5,1.25,2.0]:
		for side:float in [-1.0,1.0,-1.75,1.75]:
			var point:Vector3=entry+basis*Vector3(side,0,-depth*float(leg.direction))
			point.x=snappedf(point.x,.25);point.z=snappedf(point.z,.25)
			if not _free(id,point):continue
			var points:PackedVector3Array=_floor_route(actor.position,point,id)
			if points.is_empty() or _floor_route(point,entry).is_empty():continue
			var distance:float=0.0
			for i:int in range(1,points.size()):distance+=points[i-1].distance_to(points[i])
			if distance<length:best={"point":point,"points":points};length=distance
	return best

func _exit_place(id:String,leg:Dictionary)->Dictionary:
	var exit:Vector3=leg.to
	var basis:Basis=leg.schedule.transform.basis
	for offset:Vector2 in [Vector2(0,1),Vector2(1,1),Vector2(-1,1),Vector2(1,0),Vector2(-1,0),Vector2(0,1.5)]:
		var point:Vector3=exit+basis*Vector3(offset.x,0,offset.y*float(leg.direction))
		point.x=snappedf(point.x,.25);point.z=snappedf(point.z,.25)
		if not _free(id,point) or not _free(id,exit):continue
		var points:PackedVector3Array=_floor_route(exit,point,id)
		if not points.is_empty():return {"point":point,"points":points}
	return {}

func _can_observe_replan(id:String,route:Dictionary)->bool:
	# Keep this brief retry observation inside the existing ordinary activity
	# donor contract. Walking intents, protected crossings and resource/food
	# owners continue through their existing movement paths.
	if not courtesy._eligible(self,id) or route.has("courtesy") or courtesy.beneficiary(self,id):return false
	if int(route.ticket)!=0 or not str(route.stair_id).is_empty() or not str(route.get("custody","")).is_empty():return false
	var action:Dictionary=app.household.member_sim(id).get_current_action()
	if not str(action.get("cooperation_id","")).is_empty() or not app.household.meals.carried_by(id).is_empty():return false
	var motion:Dictionary=courtesy._walk_intent(self,id)
	return not bool(motion.get("walk",false)) and not bool(motion.get("waiting",false)) and not bool(motion.get("resume_active",false)) and float(motion.get("wait_started",-1.0))<0

func _observe_replan(id:String,route:Dictionary,remaining:float,moved:bool)->bool:
	var at:Vector3=app.world.actors[id].position
	var observation:Dictionary=route.get("replan_observation",{})
	if moved or observation.get("at",Vector3.INF)!=at or int(observation.get("identity",-1))!=int(route.identity) or int(observation.get("generation",-1))!=int(route.generation):observation={}
	var age:float=float(observation.get("age",0.0))
	route.replan_observation={"at":at,"identity":int(route.identity),"generation":int(route.generation),"age":minf(REPLAN_OBSERVATION_TIME,age+remaining)}
	courtesy.note_block(self,id,remaining,moved)
	# The threshold-reaching call returns with the blocked path intact so the
	# end-of-household selector gets one opportunity. A later blocked call must
	# requery, even if no anchor was found or its last alternative was empty.
	return age<REPLAN_OBSERVATION_TIME

func _walk(id:String,route:Dictionary,time:float,consider_courtesy:bool=true)->Dictionary:
	var actor:LifeActor=app.world.actors[id]
	var remaining:float=maxf(0,time);var moved:bool=false
	while int(route.point)<route.points.size() and remaining>.0000001:
		var goal:Vector3=route.points[int(route.point)]
		var difference:Vector3=goal-actor.position;var distance:float=difference.length()
		if distance<.00001:route.point+=1;continue
		var step:float=minf(distance,remaining*WALK_SPEED)
		var next:Vector3=actor.position+difference/distance*step
		if not courtesy.step_allowed(self,id,actor.position,next):return {"time":0.0,"moved":moved,"blocked":true}
		if not _step_clear(id,actor.position,next):
			if courtesy.beneficiary(self,id):return {"time":0.0,"moved":moved,"blocked":true}
			var observing:bool=consider_courtesy and _can_observe_replan(id,route)
			if observing and _observe_replan(id,route,remaining,moved):return {"time":0.0,"moved":moved,"blocked":true}
			if consider_courtesy and str(route.get("phase",""))=="clear":courtesy.note_block(self,id,time,moved)
			var alternative:PackedVector3Array=_floor_route(actor.position,route.points[-1],id)
			if not alternative.is_empty():route.points=alternative;route.point=0
			elif not observing and consider_courtesy and str(route.get("phase",""))!="clear":courtesy.note_block(self,id,time,moved)
			return {"time":0.0,"moved":moved,"blocked":true}
		actor.rotation.y=lerp_angle(actor.rotation.y,atan2(difference.x,difference.z),minf(1,remaining*12))
		actor.position=next;remaining-=step/WALK_SPEED;moved=true
		if route.has("replan_observation"):
			route.erase("replan_observation");courtesy.blocked.erase(id)
		if step>=distance-.000001:actor.position=goal;route.point+=1
	return {"time":remaining,"moved":moved,"blocked":false}

func _step_clear(id:String,from:Vector3,to:Vector3)->bool:
	if not courtesy.step_allowed(self,id,from,to):return false
	var level:int=app.world.point_level(to)
	if level<0 or not app.world.lot_navigation.point_clear(level,to):return false
	for other_id:String in app.world.actors:
		if other_id==id:continue
		var actor:LifeActor=app.world.actors[other_id]
		if not actor.visible or not _same_floor(to,actor.position):continue
		var before:float=from.distance_to(actor.position);var after:float=to.distance_to(actor.position)
		var step:Vector3=to-from
		var part:float=clampf((actor.position-from).dot(step)/maxf(.00000001,step.length_squared()),0.0,1.0)
		var closest:float=from.lerp(to,part).distance_to(actor.position)
		if before<BODY_GAP:
			if after<=before+.000001 or closest<before-.000001:return false
		elif closest<BODY_GAP-.000001:return false
	for lock:Dictionary in stairs.values():
		if str(lock.owner).is_empty() or str(lock.owner)==id:continue
		for reserved:Vector3 in [lock.exit,lock.clear]:
			if not _same_floor(to,reserved):continue
			var step:Vector3=to-from
			var part:float=clampf((reserved-from).dot(step)/maxf(.00000001,step.length_squared()),0.0,1.0)
			if from.lerp(to,part).distance_to(reserved)<BODY_GAP:return false
	for reserved:Vector3 in courtesy.reservations(self,id):
		if not _same_floor(to,reserved):continue
		var step:Vector3=to-from
		var part:float=clampf((reserved-from).dot(step)/maxf(.00000001,step.length_squared()),0.0,1.0)
		if from.lerp(to,part).distance_to(reserved)<BODY_GAP:return false
	return true

func _prepare(id:String,route:Dictionary)->bool:
	var leg:Dictionary=route.legs[int(route.cursor)]
	if leg.kind=="floor":
		route.points=leg.points;route.point=0
		if int(route.cursor)+1<route.legs.size() and route.legs[int(route.cursor)+1].kind=="stair":
			var wait:Dictionary=_waiting_place(id,route.legs[int(route.cursor)+1])
			if wait.is_empty():return false
			route.wait=wait.point;route.points=wait.points
		route.prepared=true;return true
	# A route may start exactly at a landing. It still has to reach a free waiting
	# place before joining the FIFO, so it cannot occupy somebody else's exit.
	if not Vector3(route.wait).is_finite():
		var wait:Dictionary=_waiting_place(id,leg)
		if wait.is_empty():return false
		route.wait=wait.point;route.points=wait.points;route.point=0;route.phase="to_wait"
	else:route.phase="waiting"
	route.stair_id=str(leg.stair_id);route.prepared=true
	return true

func advance(id:String,delta:float,speed:int)->Dictionary:
	var response:Dictionary={"moving":false,"finished":false,"cleared":false,"error":""}
	if not routes.has(id) or speed<=0 or delta<=0:return response
	courtesy.reconcile(self)
	var route:Dictionary=routes[id]
	if route.has("courtesy"):
		if int(route.generation)!=app.world.lot_navigation.generation:courtesy.rebuild(self)
		if route.has("courtesy"):return courtesy.advance(self,id,delta*float(speed))
	if not str(route.error).is_empty():return response
	var actor:LifeActor=app.world.actors[id]
	var remaining:float=delta*float(speed)
	# A bounded loop consumes actual simulation time across walking, stair and
	# exit segments, rather than moving eight times farther with a three-times gait.
	for iteration:int in range(128):
		if remaining<=.0000001:break
		if int(route.cursor)>=route.legs.size():
			routes.erase(id);response.finished=true;break
		if int(route.generation)!=app.world.lot_navigation.generation and not busy(id):
			var rebuilt:Dictionary=request(id,route.destination)
			if not bool(rebuilt.ok):response.error=str(rebuilt.error);break
			route=routes[id];continue
		var leg:Dictionary=route.legs[int(route.cursor)]
		if not bool(route.prepared) and not _prepare(id,route):break
		if str(route.phase) in ["route","to_wait","entry","clear"]:
			var result:Dictionary=_walk(id,route,remaining)
			remaining=result.time;response.moving=bool(response.moving) or bool(result.moved)
			if int(route.point)<route.points.size():break
			match str(route.phase):
				"route":route.cursor+=1;route.prepared=false
				"to_wait":route.phase="waiting"
				"entry":route.phase="transit";route.distance=0.0
				"clear":
					if not str(route.get("custody","")).is_empty() and not app.meal_flow.release_stair_custody(id,str(route.custody)):
						response.error="There is no supported clear place to set down the carried dish.";break
					var lock:Dictionary=_lock(str(route.stair_id));lock.owner="";lock.exit=Vector3.INF;lock.clear=Vector3.INF
					actor.present_stair({},true)
					app.world.assign_structure_layer(actor,app.world.point_level(actor.position))
					response.cleared=true
					if bool(route.safety):routes.erase(id);response.finished=true;break
					route.phase="route"
					# Clearing creates a new supported floor start. Keep the original
					# destination; the old landing polyline is no longer our position.
					var again:Dictionary=request(id,route.destination)
					if not bool(again.ok):response.error=str(again.error);break
					route=routes[id]
			continue
		if str(route.phase)=="waiting":
			var lock:Dictionary=_lock(str(leg.stair_id))
			if int(route.ticket)==0:
				route.ticket=next_ticket;next_ticket+=1
				lock.queue.append({"id":id,"ticket":route.ticket})
			if not str(lock.owner).is_empty() or lock.queue.is_empty() or str(lock.queue[0].id)!=id:break
			var exit:Dictionary=_exit_place(id,leg)
			var entry:PackedVector3Array=_floor_route(actor.position,leg.from,id)
			if exit.is_empty() or entry.is_empty():break
			lock.queue.pop_front();lock.owner=id;lock.exit=leg.to;lock.clear=exit.point
			route.exit=leg.to;route.clear=exit.point;route.clear_points=exit.points
			route.points=entry;route.point=0;route.phase="entry";route.wait=Vector3.INF
			continue
		if str(route.phase)=="transit":
			var prior_distance:float=float(route.distance)
			var prior_transform:Transform3D=actor.transform
			var prior_pose:Dictionary=actor.stair_presentation.duplicate(true)
			var distance:float=minf(float(leg.schedule.length)-float(route.distance),remaining*Gait.SPEED)
			route.distance+=distance;remaining-=distance/Gait.SPEED
			var state:Dictionary=Gait.sample(leg.schedule,float(route.distance))
			actor.position=state.root;actor.rotation.y=state.yaw;actor.present_stair(state,true)
			app.world.assign_stair_layer(actor)
			response.moving=bool(response.moving) or distance>0
			if not actor.stair_pose_valid:
				route.error=actor.stair_pose_error;route.distance=prior_distance;actor.transform=prior_transform
				actor.present_stair(prior_pose,true)
				response.error=str(route.error);response.moving=false;break
			if bool(state.finished):
				actor.present_stair({},true);route.phase="clear";route.points=route.clear_points;route.point=0
			else:break
	return response

func snapshot()->Dictionary:
	var people:Dictionary={}
	for member:Dictionary in app.household.members:
		var id:String=str(member.id);var actor:LifeActor=app.world.actors[id]
		var motion:Dictionary={}
		if routes.has(id):
			var route:Dictionary=routes[id];var leg:Dictionary={}
			for index:int in range(int(route.cursor),route.legs.size()):
				if str(route.legs[index].kind)=="stair":leg=route.legs[index];break
			var action:Dictionary=member.sim.get_current_action()
			var state:Dictionary=app.motion_states.get(id,app._empty_motion())
			var intent:Dictionary={"kind":"idle"}
			if not action.is_empty():
				intent.kind="action"
				for key:String in ["id","target_id","meal_source","meal_stage","meal_plate"]:intent[key]=str(action.get(key,""))
			elif bool(state.walk):intent={"kind":"walk","destination":LifeJourneyState.packed(state.destination)}
			var phase:String=str(route.phase)
			if phase=="waiting" and int(route.ticket)==0:phase="to_wait"
			motion={"phase":phase,"identity":int(route.identity),"ticket":int(route.ticket),"safety":bool(route.safety),"custody":str(route.get("custody","")),"destination":LifeJourneyState.packed(route.destination),"stair_id":str(leg.get("stair_id","")),"direction":int(leg.get("direction",0)),"distance":float(route.distance),"wait":LifeJourneyState.packed(route.wait) if Vector3(route.wait).is_finite() else [],"clear":LifeJourneyState.packed(route.clear) if Vector3(route.clear).is_finite() else [],"intent":intent}
			if route.has("courtesy"):
				motion.courtesy=route.courtesy.duplicate(true);motion.courtesy.anchor=LifeJourneyState.packed(route.courtesy.anchor)
		people[id]={"position":LifeJourneyState.packed(actor.position),"yaw":actor.rotation.y,"motion":motion}
	return {"version":LifeJourneyState.VERSION,"next_identity":next_identity,"next_ticket":next_ticket,"members":people}

func restore(data:Dictionary)->Dictionary:
	# The detached household validator has already checked the complete layout,
	# profiles, saved facts, exit reservations and FIFO identities. Install all
	# actor positions before deriving any body-aware runtime path.
	reset()
	for id:String in data.members:
		var record:Dictionary=data.members[id];var actor:LifeActor=app.world.actors[id]
		actor.position=LifeJourneyState.vector(record.position);actor.rotation.y=float(record.yaw)
	for id:String in data.members:
		var saved:Dictionary=data.members[id].motion
		if saved.is_empty():continue
		var actor:LifeActor=app.world.actors[id]
		var destination:Vector3=LifeJourneyState.vector(saved.destination)
		var stair_id:String=str(saved.stair_id)
		var legs:Array=[];var points:PackedVector3Array=[];var clear_points:PackedVector3Array=[]
		var exit:Vector3=Vector3.INF
		var wait:Vector3=LifeJourneyState.vector(saved.wait) if not saved.wait.is_empty() else Vector3.INF
		var clear:Vector3=LifeJourneyState.vector(saved.clear) if not saved.clear.is_empty() else Vector3.INF
		if stair_id.is_empty():
			var built:Dictionary=request(id,destination)
			if not bool(built.ok):return built
			legs=routes[id].legs
		else:
			var node:Node3D=app.world.construction.stair_nodes[stair_id]
			var schedule:Dictionary=Gait.plan(node.global_transform,int(saved.direction),actor.stair_rear_extent(int(saved.direction)))
			var entry:Vector3=Gait.sample(schedule,0).root;exit=Gait.sample(schedule,schedule.length).root
			var leg:Dictionary={"key":"stair:"+stair_id,"kind":"stair","stair_id":stair_id,"points":PackedVector3Array([entry,exit]),"from":entry,"to":exit,"direction":int(saved.direction),"schedule":schedule}
			if str(saved.phase)=="route":
				# Preserve an already chosen approach place; if no place was chosen
				# yet, the ordinary prepare step will select it after loading.
				points=_floor_route(actor.position,wait if wait.is_finite() else entry)
				legs.append({"key":"floor:","kind":"floor","stair_id":"","points":points,"from":actor.position,"to":entry})
			legs.append(leg)
			match str(saved.phase):
				"to_wait":points=_floor_route(actor.position,wait)
				"entry":points=_floor_route(actor.position,entry)
				"clear":points=_floor_route(actor.position,clear)
			if str(saved.phase) in ["entry","transit","clear"]:
				clear_points=_floor_route(exit,clear)
				var lock:Dictionary=_lock(stair_id);lock.owner=id;lock.exit=exit;lock.clear=clear
			elif str(saved.phase)=="waiting":_lock(stair_id).queue.append({"id":id,"ticket":int(saved.ticket)})
		var prepared:bool=str(saved.phase)!="route" or (not stair_id.is_empty() and wait.is_finite())
		routes[id]={"identity":int(saved.identity),"generation":app.world.lot_navigation.generation,"destination":destination,"legs":legs,"cursor":0,"phase":str(saved.phase),"points":points,"point":0,"prepared":prepared,"wait":wait,"ticket":int(saved.ticket),"distance":float(saved.distance),"safety":bool(saved.safety),"custody":str(saved.custody),"stair_id":stair_id,"exit":exit,"clear":clear,"clear_points":clear_points,"error":""}
		var motion:Dictionary=app.motion_states[id]
		motion.traversal=routes[id];motion.path=PackedVector3Array([actor.position,destination]);motion.index=0
		motion.walk=str(saved.intent.kind)=="walk"
		motion.destination=LifeJourneyState.vector(saved.intent.destination) if motion.walk else destination
		motion.pending=app.household.member_sim(id).get_current_action()
	for id:String in data.members:
		if data.members[id].motion.has("courtesy"):courtesy.restore(self,id,data.members[id].motion.courtesy)
	for lock:Dictionary in stairs.values():lock.queue.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.ticket)<int(b.ticket))
	next_identity=int(data.next_identity);next_ticket=int(data.next_ticket)
	return {"ok":true}

func validate_current_floor_courtesy()->Dictionary:
	return courtesy.validate_restored_current_floor(self)

func reconstruct()->Dictionary:
	# Called after held props have their exact saved ownership/presentation.
	# This paints a zero-time pose; no step, reservation, food or clock advances.
	for id:String in app.household.journeys.members:
		var actor:LifeActor=app.world.actors[id]
		if routes.has(id) and str(routes[id].phase)=="transit":
			var route:Dictionary=routes[id]
			actor.present_stair(Gait.sample(route.legs[int(route.cursor)].schedule,float(route.distance)),true)
			if not actor.stair_pose_valid:return {"ok":false,"error":"The saved stair pose cannot be reconstructed: "+actor.stair_pose_error}
			app.world.assign_stair_layer(actor)
		else:app.world.assign_structure_layer(actor,app.world.point_level(actor.position))
	return {"ok":true}

func validate_occupancy()->Dictionary:
	# Imported scene actors include visitors as well as household members. The
	# file validator cannot see those nodes; check them before adopting a load.
	for key:String in stairs:
		var lock:Dictionary=stairs[key];var owner:String=str(lock.owner)
		if not owner.is_empty() and (not _free(owner,lock.exit,false) or not _free(owner,lock.clear,false)):return {"ok":false,"error":"A visible Lifelet blocks the saved staircase clearance."}
	for id:String in routes:
		if routes[id].has("courtesy") and (not courtesy._anchor_clear(self,id,routes[id].courtesy.anchor) or routes[id].courtesy_priority.is_empty()):return {"ok":false,"error":"A visible Lifelet blocks the saved courtesy anchor."}
		if str(routes[id].phase)=="waiting" and not _free(id,app.world.actors[id].position,false):return {"ok":false,"error":"A visible Lifelet blocks a saved waiting place."}
	return {"ok":true}
