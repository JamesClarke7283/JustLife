extends RefCounted
## Courtesy movement uses the ordinary walking controller, with no activity rewards.
var app:Node
var review_in:float=0.0
# Yield before occupying a clearance cell that the walking planner excludes.
# A smaller courtesy radius leaves a blocked walker unable to ask for space.
const BODY_GAP:float=LifeTraversal.ROUTE_CLEARANCE

func update(delta:float) -> void:
	if app.household.speed<=0:return
	review_in-=delta
	if review_in>0:return
	review_in=.25
	app._store_motion()
	var previous:String=app.bound_member_id
	for member:Dictionary in app.household.members:
		var id:String=str(member.id)
		if not _idle(id):continue
		var person:LifeActor=app.world.actors.get(id)
		if not _needs_space(id,person):continue
		app._bind_member(id)
		var route:PackedVector3Array=_clear_route(id,person.position)
		if route.is_empty():continue
		# Preserve the same movement path semantics as a ground click. Future
		# player actions can replace this walk through on_action_started.
		app._clear_motion()
		app._set_route(route[-1]);app.walk_only=true
		app.walk_destination=route[-1]
		app._store_motion()
	app._bind_member(previous)

func _idle(id:String) -> bool:
	var sim:LifeSim=app.household.member_sim(id)
	var person:LifeActor=app.world.actors.get(id)
	if not is_instance_valid(sim) or not is_instance_valid(person) or not person.visible:return false
	if sim.is_away() or not sim.action_queue.is_empty():return false
	if app.traversal.active(id):return false
	var motion:Dictionary=app.motion_states.get(id,app._empty_motion())
	return not bool(motion.walk) and not bool(motion.waiting) and int(motion.index)>=motion.path.size()

func _needs_space(id:String,person:LifeActor) -> bool:
	for other_id:String in app.world.actors:
		if other_id==id:continue
		var other:LifeActor=app.world.actors[other_id]
		if not is_instance_valid(other) or not other.visible:continue
		if _distance(person.position,other.position)<BODY_GAP:
			var motion:Dictionary=app.motion_states.get(other_id,app._empty_motion())
			if bool(motion.walk) and int(motion.index)<motion.path.size() and _distance(person.position,motion.destination)>_distance(person.position,other.position)+.25:continue
			# One idle member yields, so an overlapping pair does not both
			# repeatedly choose new positions in response to each other.
			if not _idle(other_id) or id>other_id:return true
	for member:Dictionary in app.household.members:
		if str(member.id)==id:continue
		var action:Dictionary=member.sim.get_current_action()
		if action.is_empty() or str(action.get("phase",""))!="approach":continue
		if str(action.target_id)==id:continue # The person is a social destination.
		var other:LifeActor=app.world.actors.get(str(member.id))
		if not is_instance_valid(other) or not other.visible:continue
		var destination:Vector3=action.target_position
		if _distance(destination,person.position)<BODY_GAP and _distance(other.position,destination)<1.8:return true
	return false

func _clear_route(id:String,origin:Vector3,min_length:float=0.0) -> PackedVector3Array:
	var candidates:Array[Vector3]=[]
	var center:Vector3=Vector3(roundf(origin.x*4)*.25,origin.y,roundf(origin.z*4)*.25)
	for radius:int in range(1,7):
		for x:int in range(-radius,radius+1):
			for z:int in range(-radius,radius+1):
				if absi(x)==radius or absi(z)==radius:candidates.append(center+Vector3(x*.5,0,z*.5))
	candidates.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.distance_squared_to(origin)<b.distance_squared_to(origin))
	for destination:Vector3 in candidates:
		if not app._wait_position_clear(destination):continue
		var reserved:bool=false
		for other_id:String in app.motion_states:
			if other_id==id:continue
			var motion:Dictionary=app.motion_states[other_id]
			if bool(motion.walk) and _distance(motion.destination,destination)<.8:reserved=true;break
		if reserved:continue
		var route:PackedVector3Array=app.world.path_to(origin,destination)
		if route.is_empty() or route[-1].distance_to(destination)>.02:continue
		var length:float=0.0
		var at:Vector3=origin
		for point:Vector3 in route:length+=at.distance_to(point);at=point
		if length>4.0:continue # Step aside locally; do not take a tour around the house.
		if length+0.000001<min_length:continue
		return route
	return PackedVector3Array()

func _distance(a:Vector3,b:Vector3) -> float:
	if absf(a.y-b.y)>.1:return INF
	return Vector2(a.x-b.x,a.z-b.z).length()
