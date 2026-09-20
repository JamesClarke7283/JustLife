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
const STANDOFF_TIME:float=2.0   # scaled seconds stuck on one step before somebody yields
const STANDOFF_HOLD:float=2.5   # scaled seconds a yielder waits at its anchor for the other body to pass
const STANDOFF_LIMIT:int=3      # retreats on one route before the walker squeezes past bodies
const STANDOFF_ERROR:String="Somebody is in the way."
const WAIT_HOLD_TIME:float=4.0   # scaled seconds an owned turn retries a fresh landing plan
const WAIT_ENTRY_ERROR:String="The staircase cannot be reached from here."
const WAIT_EXIT_ERROR:String="There is no clear place to step off the stairs."
var squeeze_count:int=0   # routes that finished by squeezing past bodies after repeated standoffs
const ASIDE_DISTANCES:Array=[.5,.75,1.0,1.5]
const ASIDE_DIRECTIONS:Array=[Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1),Vector2(.7071,.7071),Vector2(-.7071,.7071),Vector2(.7071,-.7071),Vector2(-.7071,-.7071)]
var app:Node
var routes:Dictionary={}
var stairs:Dictionary={}
var next_ticket:int=1
var next_identity:int=1
var courtesy=preload("res://scripts/courtesy.gd").new()
var standoff_count:int=0   # retreats started because a step stayed refused
var make_way_count:int=0   # idle Lifelets asked to step aside

func _init(controller:Node)->void:app=controller

func reset()->void:
	routes.clear();stairs.clear();next_ticket=1;next_identity=1;courtesy.reset()

func busy(id:String)->bool:
	return routes.has(id) and str(routes[id].phase) in ["entry","transit","clear"]

func safety(id:String)->bool:return routes.has(id) and bool(routes[id].safety)
func active(id:String)->bool:return routes.has(id)
func making_way(id:String)->bool:return routes.has(id) and bool(routes[id].get("make_way",false))
func standing_off(id:String)->bool:return routes.has(id) and routes[id].has("standoff")
func squeezing(id:String)->bool:return routes.has(id) and bool(routes[id].get("squeeze",false))

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
	# An away Lifelet is not in the lot at all: its saved position is where it
	# will come home, not a body that can walk now. Planning from there produced
	# a route nobody could ever advance, so say so instead of accepting it. A
	# returning member is visible again and walks normally.
	if not actor.visible:return {"ok":false,"error":"This Lifelet is away from home right now."}
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
		if not _step_clear(id,actor.position,next) and not (bool(route.get("squeeze",false)) and _step_clear_of_structure(id,actor.position,next)):
			if not _step_clear_of_structure(id,actor.position,next) and courtesy.step_allowed(self,id,actor.position,next):
				# Even without any body nearby this step is refused by walls,
				# furniture or floors: the planned corridor is not truly
				# walkable. Learn the edge so the planner routes around it.
				route.structure_refusals=int(route.get("structure_refusals",0))+1
				if int(route.structure_refusals)>=4:
					route.structure_refusals=0
					app.world.lot_navigation.penalize_segment(app.world.point_level(actor.position),actor.position,goal)
					var detour:PackedVector3Array=_floor_route(actor.position,route.points[-1],id)
					if not detour.is_empty():route.points=detour;route.point=0
				return {"time":0.0,"moved":moved,"blocked":true}
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

func _step_clear_of_structure(id:String,from:Vector3,to:Vector3)->bool:
	# The step test without other bodies: walls, floors and stair reservations.
	if not courtesy.step_allowed(self,id,from,to):return false
	var level:int=app.world.point_level(to)
	if level<0 or not app.world.lot_navigation.point_clear(level,to):return false
	for lock:Dictionary in stairs.values():
		if str(lock.owner).is_empty() or str(lock.owner)==id:continue
		for reserved:Vector3 in [lock.exit,lock.clear]:
			if reserved.is_finite() and _same_floor(to,reserved) and to.distance_to(reserved)<BODY_GAP:return false
	return true

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
		if not bool(route.prepared):
			if not _prepare(id,route):
				# The approach place for a stair, or the floor entry route to it,
				# is not available yet. Retry for a bounded time, then report an
				# honest reason instead of standing on an unprepared route.
				route.wait_hold=float(route.get("wait_hold",0.0))+remaining
				if float(route.wait_hold)<WAIT_HOLD_TIME:break
				_remove_waiter(id)
				routes.erase(id)
				courtesy.reconcile(self)
				response.error=WAIT_ENTRY_ERROR
				break
			route.erase("wait_hold")
		if str(route.phase) in ["route","to_wait","entry","clear"]:
			if route.has("standoff"):
				response.moving=_advance_standoff(id,route,remaining) or bool(response.moving)
				break
			var attempted:float=remaining
			var result:Dictionary=_walk(id,route,remaining)
			remaining=result.time;response.moving=bool(response.moving) or bool(result.moved)
			# A step refused for the same body long enough is a standoff: somebody
			# yields, so two Lifelets meeting in a doorway or at a shared use point
			# never stand facing each other for the rest of the day.
			if bool(result.blocked) and not bool(result.moved):
				route.standoff_age=float(route.get("standoff_age",0.0))+attempted
				if float(route.standoff_age)>=STANDOFF_TIME and str(route.phase)=="route" and not route.has("courtesy") and courtesy.owner(self).is_empty():_resolve_standoff(id,route)
			elif bool(result.moved):route.standoff_age=0.0
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
			if exit.is_empty() or entry.is_empty():
				# An arrived waiter whose turn cannot produce a landing plan does
				# not stand still holding a ticket: it retries a fresh exit and
				# entry search for a bounded time while it legitimately owns the
				# turn, then releases its place in the queue so the Lifelets
				# behind it can proceed, and reports why through the ordinary
				# notice channel instead of leaving a silent queue ticket.
				route.wait_hold=float(route.get("wait_hold",0.0))+remaining
				if float(route.wait_hold)<WAIT_HOLD_TIME:break
				_remove_waiter(id)
				var reason:String=WAIT_EXIT_ERROR if exit.is_empty() else WAIT_ENTRY_ERROR
				routes.erase(id)
				courtesy.reconcile(self)
				response.error=reason
				break
			lock.queue.pop_front();lock.owner=id;lock.exit=leg.to;lock.clear=exit.point
			route.exit=leg.to;route.clear=exit.point;route.clear_points=exit.points
			route.points=entry;route.point=0;route.phase="entry";route.wait=Vector3.INF
			route.erase("wait_hold")
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
		if routes.has(id) and not bool(routes[id].get("make_way",false)):
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

# --- Standoffs: yielding in doorways and at shared use points ---------------

func _blocking_bodies(id:String,from:Vector3,to:Vector3)->Array:
	# The same body test as _step_clear, returning who refuses the step.
	var found:Array=[]
	for other_id:String in app.world.actors:
		if other_id==id:continue
		var actor:LifeActor=app.world.actors[other_id]
		if not actor.visible or not _same_floor(to,actor.position):continue
		var before:float=from.distance_to(actor.position);var after:float=to.distance_to(actor.position)
		var step:Vector3=to-from
		var part:float=clampf((actor.position-from).dot(step)/maxf(.00000001,step.length_squared()),0.0,1.0)
		var closest:float=from.lerp(to,part).distance_to(actor.position)
		if before<BODY_GAP:
			if after<=before+.000001 or closest<before-.000001:found.append(other_id)
		elif closest<BODY_GAP-.000001:found.append(other_id)
	return found

func _corridor_points(route:Dictionary)->PackedVector3Array:
	var points:PackedVector3Array=PackedVector3Array()
	for index:int in range(int(route.point),route.points.size()):points.append(route.points[index])
	if Vector3(route.destination).is_finite():points.append(route.destination)
	return points

func _corridor_distance(point:Vector3,corridor:PackedVector3Array)->float:
	if corridor.is_empty():return INF
	var best:float=point.distance_to(corridor[0])
	for index:int in range(1,corridor.size()):best=minf(best,courtesy._point_distance(point,corridor[index-1],corridor[index]))
	return best

func _sweep_clear(id:String,from:Vector3,to:Vector3)->bool:
	var level:int=app.world.point_level(to)
	if level<0 or not app.world.lot_navigation.segment_clear(level,from,to):return false
	return _blocking_bodies(id,from,to).is_empty()

func _remaining_length(route:Dictionary)->float:
	var length:float=0.0
	var previous:Vector3=Vector3.INF
	for point:Vector3 in _corridor_points(route):
		if previous.is_finite():length+=previous.distance_to(point)
		previous=point
	return length

func _floor_only(route:Dictionary)->bool:
	for leg:Dictionary in route.legs:
		if str(leg.kind)!="floor":return false
	return int(route.ticket)==0 and str(route.stair_id).is_empty() and not bool(route.safety)

func _aside_anchor(id:String,start:Vector3,corridor:PackedVector3Array,away_from:Vector3)->Vector3:
	# The nearest free cell clear of the other body's corridor, preferring cells
	# that lead away from the refused step so the yielder backs off rather than
	# squeezing past.
	var best:Vector3=Vector3.INF;var best_score:float=INF
	for distance:float in ASIDE_DISTANCES:
		for direction:Vector2 in ASIDE_DIRECTIONS:
			var anchor:Vector3=start+Vector3(direction.x,0,direction.y)*distance
			anchor.x=snappedf(anchor.x,.25);anchor.z=snappedf(anchor.z,.25);anchor.y=start.y
			if anchor.distance_to(start)<.2 or not _free(id,anchor) or not _sweep_clear(id,start,anchor):continue
			if _corridor_distance(anchor,corridor)<ROUTE_CLEARANCE:continue
			var score:float=distance-(anchor.distance_to(away_from) if away_from.is_finite() else 0.0)*.5
			if score<best_score:best_score=score;best=anchor
	return best

func _resolve_standoff(id:String,route:Dictionary)->void:
	if int(route.point)>=route.points.size() or not _floor_only(route):return
	# After several fruitless retreats the walker squeezes past the bodies in its
	# way for the rest of this route, the way people do in a crowded hallway,
	# rather than shuffling back and forth all evening. Walls, stairs and
	# courtesy corridors are still respected. A real detour around the holding
	# body is tried first, so nobody walks through anybody on open floor.
	if int(route.get("standoffs",0))>=STANDOFF_LIMIT:
		if int(route.get("bypasses",0))<4 and _try_body_bypass(id,route):
			route.bypasses=int(route.get("bypasses",0))+1
			return
		if not bool(route.get("squeeze",false)):route.squeeze=true;squeeze_count+=1
		return
	var actor:LifeActor=app.world.actors[id]
	var next:Vector3=route.points[int(route.point)]
	var blockers:Array=_blocking_bodies(id,actor.position,next)
	if blockers.is_empty():return
	blockers.sort()
	for other_id:String in blockers:
		if routes.has(other_id) and not bool(routes[other_id].get("make_way",false)):
			var other:Dictionary=routes[other_id]
			if other.has("standoff") or other.has("courtesy"):continue
			# Two walkers: the one with the longer way to go steps aside.
			var mine:float=_remaining_length(route);var theirs:float=_remaining_length(other)
			var i_yield:bool=mine>theirs+.001 or (absf(mine-theirs)<=.001 and id>other_id)
			if i_yield and _retreat(id,route,other_id):return
			continue
		if not routes.has(other_id) and _make_way(other_id,id,route):return
	# Nobody else could move: back off anyway and try again shortly.
	_retreat(id,route,"")

func _try_body_bypass(id:String,route:Dictionary)->bool:
	# Step around the holding body through walkable floor: an approach step to
	# one side, then the planner rejoins the original destination from there.
	var actor:LifeActor=app.world.actors[id]
	if int(route.point)>=route.points.size():return false
	var goal:Vector3=route.points[int(route.point)]
	var forward:Vector3=goal-actor.position;forward.y=0.0
	if forward.length()<.05:return false
	forward=forward.normalized()
	var side:Vector3=Vector3(-forward.z,0,forward.x)
	var level:int=app.world.point_level(actor.position)
	for candidate_dir:Vector3 in [side,-side]:
		var waypoint:Vector3=goal+candidate_dir*.9+forward*.25
		waypoint.y=actor.position.y
		if not app.world.lot_navigation.point_clear(level,waypoint):continue
		var approach:Vector3=actor.position+candidate_dir*.45
		approach.y=actor.position.y
		if not app.world.lot_navigation.point_clear(level,approach):continue
		if not _step_clear(id,actor.position,approach):continue
		var onward:PackedVector3Array=_floor_route(waypoint,route.points[-1],id)
		if onward.is_empty():continue
		var spliced:PackedVector3Array=PackedVector3Array([approach])
		spliced.append(waypoint)
		for index:int in range(1,onward.size()):spliced.append(onward[index])
		route.points=spliced;route.point=0
		return true
	return false
func _retreat(id:String,route:Dictionary,peer:String)->bool:
	var actor:LifeActor=app.world.actors[id]
	var corridor:PackedVector3Array=_corridor_points(routes[peer]) if not peer.is_empty() and routes.has(peer) else PackedVector3Array()
	if not peer.is_empty() and app.world.actors.has(peer) and corridor.is_empty():corridor.append(app.world.actors[peer].position)
	var next:Vector3=route.points[int(route.point)]
	var anchor:Vector3=_aside_anchor(id,actor.position,corridor,next)
	if not anchor.is_finite():return false
	route.standoff={"anchor":anchor,"points":PackedVector3Array([actor.position,anchor]),"point":0,"hold":STANDOFF_HOLD,"peer":peer}
	route.standoff_age=0.0;standoff_count+=1;route.standoffs=int(route.get("standoffs",0))+1
	return true

func _make_way(other_id:String,walker_id:String,route:Dictionary)->bool:
	# An idle Lifelet standing on somebody's path or use point steps aside.
	var person:LifeSim=app.household.member_sim(other_id)
	if not is_instance_valid(person) or person.is_away() or not person.get_current_action().is_empty():return false
	var actor:LifeActor=app.world.actors.get(other_id)
	if not is_instance_valid(actor) or not actor.visible:return false
	var anchor:Vector3=_aside_anchor(other_id,actor.position,_corridor_points(route),app.world.actors[walker_id].position)
	if not anchor.is_finite():return false
	var start:Vector3=actor.position
	routes[other_id]={"identity":next_identity,"generation":app.world.lot_navigation.generation,"destination":anchor,"legs":[{"key":"floor:","kind":"floor","stair_id":"","points":PackedVector3Array([start,anchor]),"from":start,"to":anchor}],"cursor":0,"phase":"route","points":PackedVector3Array([start,anchor]),"point":0,"prepared":true,"wait":Vector3.INF,"ticket":0,"distance":0.0,"safety":false,"stair_id":"","error":"","make_way":true}
	next_identity+=1;make_way_count+=1
	return true

func _advance_standoff(id:String,route:Dictionary,time:float)->bool:
	var standoff:Dictionary=route.standoff
	if int(standoff.point)<standoff.points.size():
		var walking:Dictionary={"points":standoff.points,"point":standoff.point}
		var result:Dictionary=_walk(id,walking,time,false)
		standoff.points=walking.points;standoff.point=walking.point
		if bool(result.blocked) and not bool(result.moved):
			standoff.hold-=time
			if float(standoff.hold)<=0.0:_finish_standoff(id,route)
		return bool(result.moved)
	standoff.hold-=time
	var peer:String=str(standoff.peer)
	var passed:bool=peer.is_empty() or not app.world.actors.has(peer) or not routes.has(peer)
	if not passed:
		var next:Vector3=route.points[int(route.point)] if int(route.point)<route.points.size() else route.destination
		passed=app.world.actors[peer].position.distance_to(next)>BODY_GAP+.2 and app.world.actors[peer].position.distance_to(app.world.actors[id].position)>BODY_GAP+.2
	if float(standoff.hold)<=0.0 or (passed and float(standoff.hold)<=STANDOFF_HOLD-.5):_finish_standoff(id,route)
	return false

func _finish_standoff(id:String,route:Dictionary)->void:
	route.erase("standoff");route.standoff_age=0.0
	var from:Vector3=app.world.actors[id].position
	var points:PackedVector3Array=_floor_route(from,route.destination,id)
	if points.is_empty():points=_floor_route(from,route.destination)
	if points.is_empty():return
	route.legs=[{"key":"floor:","kind":"floor","stair_id":"","points":points,"from":from,"to":route.destination}]
	route.cursor=0;route.prepared=false;route.points=PackedVector3Array();route.point=0
