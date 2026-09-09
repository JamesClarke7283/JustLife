extends RefCounted
## One short household courtesy move. This helper owns no controller references.
const GAP:float=.72
const CLEARANCE:float=.78
const LIMIT:float=60.0
const QUERY_LIMIT:int=24
var blocked:Dictionary={}
var attempted:Array=[]
var rejected:Array=[]
var trace:Array=[]
var queries:int=0
var attempted_at:float=-1.0

func reset()->void:
	blocked.clear();attempted=[];rejected=[];trace.clear();queries=0;attempted_at=-1.0

func now(t)->float:return float(t.app.household.day-1)*1440.0+t.app.household.minutes

func owner(t)->String:
	for id:String in t.routes:
		if t.routes[id].has("courtesy"):return id
	return ""

func _action(t,id:String)->Dictionary:
	var person:LifeSim=t.app.household.member_sim(id)
	return person.get_current_action() if is_instance_valid(person) else {}

func _eligible(t,id:String)->bool:
	if not t.routes.has(id) or not t.app.world.actors.has(id):return false
	var person:LifeSim=t.app.household.member_sim(id)
	if not is_instance_valid(person) or person.is_away():return false
	var actor:LifeActor=t.app.world.actors[id];var route:Dictionary=t.routes[id]
	var motion:Dictionary=t.app.motion_states.get(id,{})
	if not actor.visible or str(route.phase)!="route" or bool(route.safety) or Vector3(route.wait).is_finite():return false
	if bool(motion.get("waiting",false)) or bool(motion.get("resume_active",false)) or float(motion.get("wait_started",-1))>=0:return false
	var action:Dictionary=person.get_current_action()
	if str(action.get("phase",""))!="approach" or str(action.get("cooperation_role",""))!="":return false
	if Vector3(action.target_position)!=Vector3(route.destination):return false
	for leg:Dictionary in route.legs:
		if str(leg.kind)!="floor":return false
	return t.app.world.point_level(actor.position)==t.app.world.point_level(route.destination)

func reservations(t,except_id:String)->Array[Vector3]:
	var points:Array[Vector3]=[]
	for id:String in t.routes:
		if id!=except_id and t.routes[id].has("courtesy"):points.append(t.routes[id].courtesy.anchor)
	return points

func _positions(t)->Array:
	var facts:Array=[int(t.app.world.lot_navigation.generation)]
	var anchors:Array[Vector3]=[];var paths:Array=[]
	var members:Array=[]
	for member:Dictionary in t.app.household.members:members.append(str(member.id))
	members.sort()
	for id:String in members:
		if not t.app.world.actors.has(id):continue
		var actor:LifeActor=t.app.world.actors[id]
		facts.append([id,actor.visible,actor.position])
		if t.routes.has(id):
			var route:Dictionary=t.routes[id]
			facts.append([id,int(route.identity),route.destination,route.phase])
			anchors.append(actor.position);anchors.append(route.destination)
			paths.append(route.points)
	var ids:Array=t.app.world.actors.keys();ids.sort()
	for id:String in ids:
		if id in members:continue
		var actor:LifeActor=t.app.world.actors[id]
		if not actor.visible:continue
		var relevant:bool=anchors.any(func(point:Vector3)->bool:return t._same_floor(point,actor.position) and point.distance_to(actor.position)<=3.5)
		if not relevant:
			for points:PackedVector3Array in paths:
				for i:int in range(1,points.size()):
					if t._same_floor(actor.position,points[i]) and _point_distance(actor.position,points[i-1],points[i])<=CLEARANCE:relevant=true;break
				if relevant:break
		if relevant:facts.append([id,actor.position])
	facts.append(_resource_waits(t,""))
	for id:String in t.routes:
		facts.append([id,t.routes[id].wait])
	for key:String in t.stairs:
		var lock:Dictionary=t.stairs[key]
		facts.append([key,lock.owner,lock.exit,lock.clear])
	return facts

func _resource_waits(t,except_id:String,restoring:bool=false)->Array[Vector3]:
	var points:Array[Vector3]=[]
	for member:Dictionary in t.app.household.members:
		var id:String=str(member.id)
		if id==except_id:continue
		if restoring:
			var state:Dictionary=member.sim.character.get("world_state",{})
			if float(state.get("resource_wait_started",-1))<0:continue
			var saved:Dictionary=t.app.household.journeys.members[id].motion
			points.append(LifeJourneyState.vector(saved.destination) if not saved.is_empty() else t.app.world.actors[id].position)
		else:
			var motion:Dictionary=t.app.motion_states.get(id,{})
			if not bool(motion.get("waiting",false)):continue
			var point:Vector3=motion.get("wait_destination",Vector3.INF)
			# A paused fresh waiter has a saved authoritative route destination;
			# the ordinary UI cache can still be unset until their first step.
			if not point.is_finite():point=t.routes[id].destination if t.routes.has(id) else t.app.world.actors[id].position
			points.append(point)
	return points

func _anchor_clear(t,id:String,anchor:Vector3)->bool:
	if not t._free(id,anchor):return false
	for point:Vector3 in _resource_waits(t,id):
		if t._same_floor(point,anchor) and point.distance_to(anchor)<.8:return false
	for peer:String in t.routes:
		if peer==id:continue
		var wait:Vector3=t.routes[peer].wait
		if wait.is_finite() and t._same_floor(wait,anchor) and wait.distance_to(anchor)<CLEARANCE:return false
	for point:Vector3 in t._occupied(id):
		if t._same_floor(point,anchor) and point.distance_to(anchor)<CLEARANCE:return false
	return true

func _sweep(t,id:String,from:Vector3,to:Vector3)->bool:
	var count:int=maxi(1,ceili(from.distance_to(to)/.125))
	for index:int in count:
		if not t._step_clear(id,from.lerp(to,float(index)/count),from.lerp(to,float(index+1)/count)):return false
	return true

func _next(t,id:String)->Vector3:
	var route:Dictionary=t.routes[id];var actor:LifeActor=t.app.world.actors[id]
	for index:int in range(int(route.point),route.points.size()):
		var point:Vector3=route.points[index]
		if actor.position.distance_to(point)>.00001:return actor.position.move_toward(point,.08)
	return Vector3.INF

func _hypothetical(t,beneficiary:String,donor:String,anchor:Vector3,restoring:bool=false)->Array[Vector3]:
	var points:Array[Vector3]=[]
	for id:String in t.app.world.actors:
		if id==beneficiary or not t.app.world.actors[id].visible:continue
		points.append(anchor if id==donor else t.app.world.actors[id].position)
	for lock:Dictionary in t.stairs.values():
		if str(lock.owner).is_empty() or str(lock.owner)==beneficiary:continue
		points.append(lock.exit);points.append(lock.clear)
	for id:String in t.routes:
		if id==beneficiary:continue
		var wait:Vector3=t.routes[id].wait
		if wait.is_finite():points.append(wait)
	points.append_array(_resource_waits(t,beneficiary,restoring))
	return points

func _hypothetical_step(t,id:String,next:Vector3,occupied:Array[Vector3])->bool:
	if not next.is_finite():return false
	var from:Vector3=t.app.world.actors[id].position;var delta:Vector3=next-from
	for at:Vector3 in occupied:
		if not t._same_floor(next,at):continue
		var before:float=from.distance_to(at);var after:float=next.distance_to(at)
		var part:float=clampf((at-from).dot(delta)/maxf(.00000001,delta.length_squared()),0,1)
		var closest:float=from.lerp(next,part).distance_to(at)
		if before<GAP:
			if after<=before+.000001 or closest<before-.000001:return false
		elif closest<GAP-.000001:return false
	return true

func note_block(t,id:String,time:float,moved:bool)->void:
	if not _eligible(t,id):return
	var at:Vector3=t.app.world.actors[id].position
	var old:Dictionary=blocked.get(id,{})
	var age:float=float(old.get("age",0))+time if not moved and old.get("at",Vector3.INF)==at and int(old.get("identity",-1))==int(t.routes[id].identity) else time
	blocked[id]={"at":at,"age":age,"identity":int(t.routes[id].identity)}

func consider(t)->void:
	if t.app.household.speed<=0 or not owner(t).is_empty():return
	var ids:Array=[]
	for peer:String in blocked:
		if _eligible(t,peer) and float(blocked[peer].age)>=.25 and blocked[peer].at==t.app.world.actors[peer].position and int(blocked[peer].identity)==int(t.routes[peer].identity):ids.append(peer)
	ids.sort()
	if ids.size()<2:return
	var key:Array=_positions(t)+[ids]
	if _positions(t)==rejected:return
	# Local body/route changes reopen selection. A bounded periodic retry covers
	# a distant actor changing an alternative route outside the observed corridor.
	if key==attempted and now(t)-attempted_at<60.0:return
	if now(t)-attempted_at<3.0:return
	attempted=key;attempted_at=now(t)
	var candidates:Array=[]
	for donor:String in ids:
		var start:Vector3=t.app.world.actors[donor].position;var seen:Array[Vector3]=[]
		for distance:float in [.5,.75,1.0,1.5]:
			for direction:Vector2 in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1),Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
				var anchor:Vector3=start+Vector3(direction.x,0,direction.y)*distance
				anchor.x=snappedf(anchor.x,.25);anchor.z=snappedf(anchor.z,.25)
				if anchor in seen:continue
				seen.append(anchor)
				if not _anchor_clear(t,donor,anchor) or not _sweep(t,donor,start,anchor):continue
				var freed:int=0
				for peer:String in ids:
					if peer!=donor and _hypothetical_step(t,peer,_next(t,peer),_hypothetical(t,peer,donor,anchor)):freed+=1
				candidates.append({"donor":donor,"anchor":anchor,"distance":start.distance_to(anchor),"freed":freed,"beneficiaries":[]})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.freed!=b.freed:return a.freed>b.freed
		if a.distance!=b.distance:return a.distance<b.distance
		if a.donor!=b.donor:return a.donor<b.donor
		if a.anchor.x!=b.anchor.x:return a.anchor.x<b.anchor.x
		return a.anchor.z<b.anchor.z)
	var used:int=0;var evaluated:Array=[];var best:Dictionary={}
	for candidate:Dictionary in candidates.slice(0,12):
		var count:int=0
		for peer:String in ids:
			if peer==str(candidate.donor):continue
			if count>=2 or used>=QUERY_LIMIT:break
			count+=1;used+=1
			var from:Vector3=t.app.world.actors[peer].position;var to:Vector3=t.routes[peer].destination
			var route:Dictionary=t.app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(t.app.world.point_level(from),from),LifeLotNavigation.floor_location(t.app.world.point_level(to),to),_hypothetical(t,peer,candidate.donor,candidate.anchor),CLEARANCE)
			var ok:bool=bool(route.ok) and route.segments.all(func(leg:Dictionary)->bool:return str(leg.kind)=="floor")
			evaluated.append({"donor":candidate.donor,"anchor":candidate.anchor,"beneficiary":peer,"complete":ok})
			if ok:
				candidate.beneficiaries.append(peer)
				if not candidate.has("priority"):candidate.priority=route.points
		if not candidate.beneficiaries.is_empty():best=candidate;break
	queries+=used
	trace.append({"at":now(t),"queries":used,"evaluated":evaluated,"selected":best.duplicate(true)})
	if trace.size()>32:trace.pop_front()
	if best.is_empty():return
	var donor:String=str(best.donor);var peer:String=str(best.beneficiaries[0]);var route:Dictionary=t.routes[donor]
	route.courtesy={"version":1,"phase":"retreat","anchor":best.anchor,"beneficiary_id":peer,"beneficiary_identity":int(t.routes[peer].identity),"expires_at":now(t)+LIMIT}
	route.courtesy_action=_action(t,donor);route.courtesy_peer_action=_action(t,peer)
	route.courtesy_generation=t.app.world.lot_navigation.generation
	route.courtesy_priority=best.priority
	_install_priority(t,peer,best.priority)
	route.courtesy_start=t.app.world.actors[donor].position
	route.courtesy_points=PackedVector3Array([t.app.world.actors[donor].position,best.anchor]);route.courtesy_point=0

func _still_owned(t,id:String)->bool:
	var route:Dictionary=t.routes[id];var fact:Dictionary=route.courtesy;var peer:String=str(fact.beneficiary_id)
	if now(t)>=float(fact.expires_at) or not _eligible(t,id) or not _eligible(t,peer):return false
	if not is_same(_action(t,id),route.courtesy_action) or not is_same(_action(t,peer),route.courtesy_peer_action):return false
	if int(t.routes[peer].identity)!=int(fact.beneficiary_identity):return false
	return _anchor_clear(t,id,fact.anchor)

func release(t,id:String,reason:String="changed_intent")->void:
	if not t.routes.has(id) or not t.routes[id].has("courtesy"):return
	var route:Dictionary=t.routes[id]
	trace.append({"at":now(t),"released":id,"phase":route.courtesy.phase,"reason":reason})
	for key:String in ["courtesy","courtesy_action","courtesy_peer_action","courtesy_start","courtesy_points","courtesy_point","courtesy_priority","courtesy_generation"]:route.erase(key)
	rejected=_positions(t)
	# Replan only motion. Keep identity/destination and the current instruction.
	var from:Vector3=t.app.world.actors[id].position
	var points:PackedVector3Array=t._floor_route(from,route.destination,id)
	if points.is_empty():points=t._floor_route(from,route.destination)
	if points.is_empty():route.error="The original route is no longer supported.";return
	route.legs=[{"key":"floor:","kind":"floor","stair_id":"","points":points,"from":from,"to":route.destination}]
	route.cursor=0;route.prepared=false;route.points=PackedVector3Array();route.point=0

func reconcile(t,recheck:bool=false)->void:
	var id:String=owner(t)
	if id.is_empty():return
	var fact:Dictionary=t.routes[id].courtesy;var peer:String=str(fact.beneficiary_id)
	if not _still_owned(t,id):
		var reason:String="changed_intent"
		if now(t)>=float(fact.expires_at):reason="expired"
		elif not t.routes.has(peer) or int(t.routes[peer].identity)!=int(fact.beneficiary_identity):reason="beneficiary_retired"
		release(t,id,reason);return
	if recheck or int(t.routes[id].courtesy_generation)!=t.app.world.lot_navigation.generation:rebuild(t)

func preserve_request(t,id:String,destination:Vector3)->bool:
	var donor:String=owner(t)
	if donor.is_empty() or not t.routes.has(id):return false
	var owned:Dictionary=t.routes[donor]
	if id!=donor and id!=str(owned.courtesy.beneficiary_id):return false
	var expected:Dictionary=owned.courtesy_action if id==donor else owned.courtesy_peer_action
	return is_same(_action(t,id),expected) and Vector3(t.routes[id].destination)==destination and _eligible(t,id)

func advance(t,id:String,time:float)->Dictionary:
	var route:Dictionary=t.routes[id];var fact:Dictionary=route.courtesy
	if str(fact.phase)=="hold":return {"moving":false,"finished":false,"cleared":false,"error":""}
	# Separate polyline and cursor prevent the anchor from becoming action arrival.
	var walking:Dictionary={"points":route.courtesy_points,"point":route.courtesy_point}
	var result:Dictionary=t._walk(id,walking,time,false)
	route.courtesy_points=walking.points;route.courtesy_point=walking.point
	if int(walking.point)>=walking.points.size():fact.phase="hold"
	return {"moving":bool(result.moved),"finished":false,"cleared":false,"error":""}

func restore(t,id:String,saved:Dictionary)->void:
	var route:Dictionary=t.routes[id];var fact:Dictionary=saved.duplicate(true)
	fact.anchor=LifeJourneyState.vector(saved.anchor)
	route.courtesy_generation=t.app.world.lot_navigation.generation
	route.courtesy=fact;route.courtesy_action=_action(t,id);route.courtesy_peer_action=_action(t,str(fact.beneficiary_id))
	route.courtesy_start=t.app.world.actors[id].position
	route.courtesy_points=PackedVector3Array([t.app.world.actors[id].position,fact.anchor]);route.courtesy_point=0
	route.courtesy_priority=_priority_route(t,id,true)
	if not route.courtesy_priority.is_empty():_install_priority(t,str(fact.beneficiary_id),route.courtesy_priority)

func _point_distance(point:Vector3,a:Vector3,b:Vector3)->float:
	var line:Vector3=b-a
	return point.distance_to(a+line*clampf((point-a).dot(line)/maxf(.00000001,line.length_squared()),0,1))

func _segment_distance(a:Vector3,b:Vector3,c:Vector3,d:Vector3)->float:
	var ab:Vector2=Vector2(b.x-a.x,b.z-a.z);var cd:Vector2=Vector2(d.x-c.x,d.z-c.z)
	var ac:Vector2=Vector2(c.x-a.x,c.z-a.z);var cross:float=ab.cross(cd)
	if absf(cross)>.00000001:
		var first:float=ac.cross(cd)/cross;var second:float=ac.cross(ab)/cross
		if first>=0 and first<=1 and second>=0 and second<=1:return 0.0
	return minf(minf(_point_distance(a,c,d),_point_distance(b,c,d)),minf(_point_distance(c,a,b),_point_distance(d,a,b)))

func _corridor(t,id:String)->PackedVector3Array:
	var donor:String=owner(t)
	if donor.is_empty() or id==donor or id==str(t.routes[donor].courtesy.beneficiary_id) or t.busy(id):return []
	return t.routes[donor].get("courtesy_priority",PackedVector3Array())

func point_allowed(t,id:String,point:Vector3)->bool:
	var points:PackedVector3Array=_corridor(t,id)
	for index:int in range(1,points.size()):
		if t._same_floor(point,points[index]) and _point_distance(point,points[index-1],points[index])<CLEARANCE:return false
	return true

func step_allowed(t,id:String,from:Vector3,to:Vector3)->bool:
	var points:PackedVector3Array=_corridor(t,id)
	var before:float=INF;var after:float=INF;var swept:float=INF
	for index:int in range(1,points.size()):
		if not t._same_floor(to,points[index]):continue
		before=minf(before,_point_distance(from,points[index-1],points[index]))
		after=minf(after,_point_distance(to,points[index-1],points[index]))
		swept=minf(swept,_segment_distance(from,to,points[index-1],points[index]))
	if before<CLEARANCE:return after>before+.000001 and swept>=before-.000001
	return swept>=CLEARANCE-.000001

func _priority_route(t,donor:String,restoring:bool=false)->PackedVector3Array:
	var fact:Dictionary=t.routes[donor].courtesy;var peer:String=str(fact.beneficiary_id)
	var from:Vector3=t.app.world.actors[peer].position;var to:Vector3=t.routes[peer].destination
	var result:Dictionary=t.app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(t.app.world.point_level(from),from),LifeLotNavigation.floor_location(t.app.world.point_level(to),to),_hypothetical(t,peer,donor,fact.anchor,restoring),CLEARANCE)
	if not bool(result.ok) or not result.segments.all(func(leg:Dictionary)->bool:return str(leg.kind)=="floor"):return []
	return result.points

func rebuild(t)->bool:
	var donor:String=owner(t)
	if donor.is_empty():return false
	var route:Dictionary=t.routes[donor];var peer:String=str(route.courtesy.beneficiary_id)
	var points:PackedVector3Array=_priority_route(t,donor)
	if points.is_empty():release(t,donor,"blocked_priority");return false
	var original:PackedVector3Array=t._floor_route(t.app.world.actors[donor].position,route.destination)
	if original.is_empty():release(t,donor,"changed_layout");return false
	route.courtesy_priority=points
	route.courtesy_generation=t.app.world.lot_navigation.generation
	for id:String in [donor,peer]:
		var current:Dictionary=t.routes[id];var at:Vector3=t.app.world.actors[id].position
		var ordinary:PackedVector3Array=original if id==donor else points
		current.legs=[{"key":"floor:","kind":"floor","stair_id":"","points":ordinary,"from":at,"to":current.destination}]
		current.points=ordinary;current.point=0;current.cursor=0;current.prepared=true;current.generation=t.app.world.lot_navigation.generation
	if str(route.courtesy.phase)=="retreat":
		var at:Vector3=t.app.world.actors[donor].position
		if not _sweep(t,donor,at,route.courtesy.anchor):release(t,donor,"blocked_retreat");return false
		route.courtesy_points=PackedVector3Array([at,route.courtesy.anchor]);route.courtesy_point=0
	return true

func _install_priority(t,peer:String,points:PackedVector3Array)->void:
	var current:Dictionary=t.routes[peer];var at:Vector3=t.app.world.actors[peer].position
	current.legs=[{"key":"floor:","kind":"floor","stair_id":"","points":points,"from":at,"to":current.destination}]
	current.points=points;current.point=0;current.cursor=0;current.prepared=true

func beneficiary(t,id:String)->bool:
	var donor:String=owner(t)
	return not donor.is_empty() and str(t.routes[donor].courtesy.beneficiary_id)==id

func generation_current(t)->bool:
	var id:String=owner(t)
	return not id.is_empty() and int(t.routes[id].courtesy_generation)==t.app.world.lot_navigation.generation
