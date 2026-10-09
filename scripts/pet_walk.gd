extends RefCounted
## A leash walk uses the same floor/stair traversal and doors as an ordinary
## Lifelet. The dog follows its own checked route and the walker waits for it.
const LEAD_LENGTH: float = 1.65
const DETOUR_LEAD: float = 2.4
const CLIP_SECONDS: float = 1.8
var app: Node
var walks: Dictionary = {}
var route_failure: String = ""

func _init(owner: Node) -> void:
	app = owner

func ready(id: String) -> bool:
	return bool(walks.get(id, {}).get("done", false))

func phase(id: String) -> String:
	var state: Dictionary = walks.get(id, {})
	if float(state.get("clock", 0.0)) < CLIP_SECONDS: return "clip"
	return "walk" if bool(state.get("moving", false)) else "hold"

func release(id: String) -> void:
	var state: Dictionary = walks.get(id, {})
	walks.erase(id)
	if state.is_empty(): return
	app.traversal.companion_bodies.erase(id)
	app.traversal.cancel(id) # A stair crossing retains its normal safe exit.
	var dog: LifePetActor = app.pet_actors.get(str(state.pet))
	if is_instance_valid(dog) and app.world.point_level(dog.position) < 0:
		# Let a canceled dog finish the authored stair edge before autonomy resumes.
		var path: Dictionary = state.get("dog_route", {})
		if not path.is_empty(): app.pet_errands[str(state.pet)] = path

func advance(id: String, action: Dictionary, delta: float) -> bool:
	var body: LifeActor = app.world.actors.get(id)
	var dog: LifePetActor = app.pet_actors.get(str(action.target_id))
	if not is_instance_valid(body) or not is_instance_valid(dog): return false
	var state: Dictionary = walks.get(id, {})
	if state.is_empty():
		state = {"pet":str(action.target_id), "clock":0.0, "index":0, "planned":false, "done":false, "moving":false, "pet_moving":false, "replan":0.0, "blocked":0.0, "dog_route":{}, "points":_destinations(body.position)}
		walks[id] = state
		app.traversal.companion_bodies[id] = dog
		if (state.points as Array).is_empty(): return _fail(id, "There is no clear front-door route for this walk.")
	var seconds: float = delta * float(app.household.speed)
	state.clock = float(state.clock) + seconds
	state.moving = false
	state.pet_moving = false
	if float(state.clock) < CLIP_SECONDS or bool(state.done) or seconds <= 0.0: return false
	var points: Array = state.points
	var target: Vector3 = points[int(state.index)]
	if not bool(state.planned):
		if float(state.get("plan_retry", 0.0)) > 0.0:
			state.plan_retry = maxf(0.0, float(state.plan_retry) - seconds)
			return false
		var human_route: Dictionary = app.traversal.request(id, target)
		var pet_route: Dictionary = _route(dog, id, target)
		if not bool(human_route.get("ok", false)) or not bool(pet_route.get("ok", false)):
			route_failure = "walker: %s; pet: %s" % [str(human_route.get("error", "clear")), str(pet_route.get("error", "clear"))]
			if bool(pet_route.get("temporary", false)) and bool(human_route.get("ok", false)):
				state.blocked = float(state.blocked) + .6
				state.plan_retry = .6
				if float(state.blocked) < 15.0: return false
			return _fail(id, "The way is blocked. Leave a clear route for both you and your dog.")
		route_failure = ""
		state.dog_route = {"action":"pet_move", "label":"Walking on the lead", "target":"", "access":"", "at":target, "entry":target, "path":pet_route.points, "segments":pet_route.segments, "index":0, "phase":"walking", "walking":true, "elapsed":0.0, "commanded":true, "inside":false, "blocked":0.0}
		state.planned = true
	var before: Vector3 = body.position
	var pet_before: Vector3 = dog.position
	if body.position.distance_to(dog.position) <= LEAD_LENGTH:
		var result: Dictionary = app.traversal.advance(id, delta, float(app.household.speed))
		if not str(result.get("error", "")).is_empty() or bool(result.get("blocked", false)):
			return _fail(id, "The walk stopped because the way is blocked.")
	state.moving = body.position.distance_to(before) > .00001
	state.replan = float(state.replan) - seconds
	# Follow the walker's reachable position, not their distant waypoint. This
	# also lets the dog take a fresh detour around moving street pedestrians.
	if float(state.replan) <= 0.0 and app.world.point_level(dog.position) >= 0:
		state.replan = .6
		var follow:Vector3 = body.position if app.world.point_level(body.position)>=0 else target
		var following:Dictionary = _route(dog,id,follow)
		if bool(following.get("ok",false)):
			state.dog_route.path=following.points;state.dog_route.segments=following.segments;state.dog_route.index=0
	_step_dog(dog, body, state.dog_route, seconds)
	state.pet_moving = dog.position.distance_to(pet_before) > .00001
	var moved: bool = bool(state.moving) or bool(state.pet_moving)
	state.blocked = 0.0 if moved else float(state.blocked) + seconds
	if body.position.distance_to(target) < .14 and dog.position.distance_to(body.position) < 1.15 and app.world.point_level(dog.position) == app.world.point_level(target):
		state.index = int(state.index) + 1
		state.planned = false
		state.blocked = 0.0
		if int(state.index) >= points.size(): state.done = true
	elif float(state.blocked) > 15.0:
		return _fail(id, "The walk stopped because somebody is in the way.")
	return bool(state.moving)

func _fail(id: String, message: String) -> bool:
	app.show_notice(message)
	var member: LifeSim = app.household.member_sim(id)
	release(id)
	if member != null and str(member.get_current_action().get("id", "")) == "pet_walk": member.cancel_action()
	return false

func _destinations(origin: Vector3) -> Array:
	var front: Dictionary = {}
	for door: Dictionary in app.world.construction.doors.doors.values():
		if int(door.level) != 0: continue
		var a: Vector3 = door.root.to_global(Vector3(0, 0, -.85))
		var b: Vector3 = door.root.to_global(Vector3(0, 0, .85))
		var a_inside: bool = app.world.construction.floor_contains(Vector2(a.x,a.z), 0)
		var b_inside: bool = app.world.construction.floor_contains(Vector2(b.x,b.z), 0)
		if a_inside == b_inside: continue
		if front.is_empty() or door.root.position.z > float(front.z): front = {"inside":a if a_inside else b, "outside":b if a_inside else a, "z":door.root.position.z}
	if front.is_empty(): return []
	var points: Array = []
	for point: Vector3 in [front.inside, front.outside, Vector3(-3.0,.16,8.0), Vector3(3.0,.16,8.0), front.outside, front.inside, origin]:
		var level: int = app.world.point_level(point)
		var clear: Vector3 = app.world.nearest_clear_point(point, level, 6)
		if not clear.is_finite() or clear.distance_to(point) > 1.5: return []
		points.append(clear)
	# A restored queue may attach the lead again out on the street. Finish
	# inside the front door instead of treating that transient spot as home.
	var level:int=app.world.point_level(origin)
	points[-1] = origin if level>=0 and app.world.construction.floor_contains(Vector2(origin.x,origin.z),level) else points[0]
	return points

func _route(dog: LifePetActor, owner: String, target: Vector3) -> Dictionary:
	var occupied: Array[Vector3] = []
	for id: String in app.world.actors:
		var actor: Node3D = app.world.actors[id]
		if id != owner and actor.visible: occupied.append(actor.position)
	for id: String in app.pet_actors:
		var actor: Node3D = app.pet_actors[id]
		if actor != dog and actor.visible: occupied.append(actor.position)
	var from: Dictionary = LifeLotNavigation.floor_location(app.world.point_level(dog.position), dog.position)
	var to: Dictionary = LifeLotNavigation.floor_location(app.world.point_level(target), target)
	var result: Dictionary = app.world.lot_navigation.pet_route_avoiding(from, to, occupied, LifeTraversal.ROUTE_CLEARANCE, dog.wall_hull(), dog.rotation.y)
	if not bool(result.get("ok", false)) and not occupied.is_empty():
		result.temporary = bool(app.world.lot_navigation.pet_route_avoiding(from, to, [], LifeTraversal.ROUTE_CLEARANCE, dog.wall_hull(), dog.rotation.y).get("ok", false))
	return result

func _step_dog(dog: LifePetActor, owner: LifeActor, route: Dictionary, seconds: float) -> void:
	var path: PackedVector3Array = route.path
	var budget: float = seconds * LifePetBehavior.WALK_SPEED
	while int(route.index) < path.size() and budget > 0.0:
		var segments: Array = route.segments
		var segment: Dictionary = segments[int(route.index)-1] if int(route.index)>0 and int(route.index)<=segments.size() else {}
		if bool(segment.get("turn", false)):
			var turn: Dictionary = app.pet_behavior().turn_step(dog, segment, budget / LifePetBehavior.WALK_SPEED)
			if not bool(turn.ok): return
			budget -= float(turn.seconds) * LifePetBehavior.WALK_SPEED
			if bool(turn.finished): route.index = int(route.index) + 1
			else: return
			continue
		var target: Vector3 = path[int(route.index)]
		var gap: float = dog.position.distance_to(target)
		if gap < .00001: route.index = int(route.index) + 1; continue
		var step: float = minf(gap, minf(.08, budget))
		var next: Vector3 = dog.position.move_toward(target, step)
		var distance: float = next.distance_to(owner.position)
		if distance < .78 or (distance > DETOUR_LEAD and distance > dog.position.distance_to(owner.position)): return
		var stair: bool = str(segment.get("kind","floor")) == "stair"
		var yaw: float = float(segment.get("yaw_to", atan2(target.x - dog.position.x, target.z - dog.position.z)))
		if stair:
			if not app.pet_behavior()._stair_clear(dog, next, segment, yaw): return
		elif app._pet_step_blocked(dog, next, yaw): return
		if app.world.construction.doors.before_pet_step(dog, next, seconds): return
		dog.traversing_stairs = stair
		dog.rotation.y = yaw
		dog.position = next
		var level: int = app.world.point_level(next)
		if level >= 0: dog.floor_level = level; dog.traversing_stairs = false
		budget -= step
		if gap <= step + .00001: route.index = int(route.index)+1
