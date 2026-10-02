extends RefCounted
## A work commute owns the body from the walk to the car until the back-door
## return. Its small phase record lives on the ordinary saved work action.
const Entry = preload("res://scripts/car_entry.gd")
const GateFlow = preload("res://scripts/gate_flow.gd")
const DRIVE_SECONDS: float = 4.0
const DRIVE_DISTANCE: float = 22.0
## A walk to the car, or home from it, that has made no progress in this many
## game seconds is given up on rather than left standing in the road.
const WALK_LIMIT: float = 90.0
const BACK_LIMIT: float = 90.0
## Standing still this long, with somewhere to be, is a stall: the walk is planned
## again, then made for the front door, and last of all simply finished.
const STALL_LIMIT: float = 8.0
const PHASES: Array[String] = ["walk", "board", "depart", "away", "return", "exit", "back"]
var app: Node
var views: Dictionary = {}

func _init(owner: Node) -> void: app = owner

func owns(action: Dictionary) -> bool:
	return str(action.get("id", "")) == "drive_to_work" or action.has("commute")

func prepare(action: Dictionary) -> void:
	if views.has(app.bound_member_id) and not is_same(views[app.bound_member_id].action, action): _release(app.bound_member_id)
	if not action.has("commute"):
		action["commute"] = {"vehicle": str(action.target_id), "phase": "walk", "time": 0.0, "leg": 0}
	app._clear_motion()
	app.pending_action = action

func caption(action: Dictionary) -> String:
	return str({"walk": "Walking to the car", "board": "Opening the door and getting in", "depart": "Driving to work", "away": "", "return": "Driving home and parking", "exit": "Getting out and closing the door", "back": "Walking home through the back entrance"}.get(str(action.get("commute", {}).get("phase", "")), ""))

func cleanup() -> void:
	for id: String in views.keys():
		var member: LifeSim = app.household.member_sim(id)
		if not is_instance_valid(member) or not owns(member.get_current_action()) or not is_same(views[id].action, member.get_current_action()) or not is_instance_valid(views[id].car):
			_release(id)

func _release(id: String) -> void:
	if not views.has(id): return
	var view: Dictionary = views[id]
	if is_instance_valid(view.get("body")):
		var body: LifeActor = view.body
		if body.has_meta("commute_inside"):
			body.remove_meta("commute_inside")
			if is_instance_valid(view.get("car")):
				view.car.global_transform = view.home
				body.global_position = view.entry.stand_point("front")
				body.global_position.y = .16
			body.clear_activity_anchor(); body.visible = true
	if is_instance_valid(view.get("parked")): view.parked.visible = true
	if is_instance_valid(view.get("car")): view.car.queue_free()
	views.erase(id)

func _view(id: String, action: Dictionary) -> Dictionary:
	if views.has(id) and is_instance_valid(views[id].car): return views[id]
	var item: Dictionary = app._find_item(str(action.commute.vehicle))
	if item.is_empty() or not is_instance_valid(item.get("node")): return {}
	# One parked car belongs to one driver at a time. The next worker waits.
	for other: String in views:
		if other != id and str(views[other].vehicle) == str(item.id): return {}
	var parked: Node3D = item.node
	var car: Node3D = parked.duplicate()
	car.name = "WorkCommuteCar_" + id
	app.world.house.add_child(car)
	car.global_transform = parked.global_transform
	for body: Node in car.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0; body.collision_mask = 0
	var rig: RefCounted = Entry.new(car, [{"id": id, "stage": "adult"}], LifeCatalogVariants.size_scale(str(item.get("variant", {}).get("size", ""))))
	var view: Dictionary = {"car": car, "parked": parked, "home": parked.global_transform,
		"entry": rig, "vehicle": str(item.id), "body": app.player, "action": action}
	views[id] = view
	parked.visible = false
	return view

func tick(delta: float) -> void:
	var action: Dictionary = app.sim.get_current_action()
	if not owns(action): return
	if not action.has("commute"): prepare(action)
	if not app.player.has_meta("preview_profile") and LifeCharacterIdentity.wardrobe_fields(app.player.profile) != LifeCharacterIdentity.wardrobe_fields(app.sim.character):
		app.player.apply_wardrobe(app.sim.character)
		if app.bound_member_id == app.household.selected_id(): app.portrait_stale = true
	app.player.pregnancy_bump = app.household.pregnancy_progress() if app.household.pregnancy_mother_id() == app.bound_member_id else 0.0
	var state: Dictionary = action.commute
	var id: String = app.bound_member_id
	var view: Dictionary = _view(id, action)
	if view.is_empty():
		if app._find_item(str(state.vehicle)).is_empty():
			if not app.sim.is_away():
				app.sim.cancel_action(); app.show_notice("The car is no longer parked here.")
			elif str(app.sim.away_state.get("phase", "")) == "returning":
				action.erase("commute")
				app.away_phases[id] = "away"
				app.show_notice("The car is unavailable. Walking home from the street.")
		app.player.animate(delta, float(app.sim.speed), false, "")
		return
	var car: Node3D = view.car
	var rig: RefCounted = view.entry
	var home: Transform3D = view.home
	var phase: String = str(state.phase)
	var step: float = delta * float(app.sim.speed)
	var time: float = float(state.time)
	if phase == "away" and str(app.sim.away_state.get("phase", "")) == "returning":
		_phase(state, "return"); phase = "return"; time = 0.0
	if phase in ["board", "depart", "away", "return", "exit"]: app.player.set_meta("commute_inside", true)
	else: app.player.remove_meta("commute_inside")
	var visible_body: bool = phase in ["walk", "board", "exit", "back"]
	app.world.set_actor_away(id, not visible_body, app.sim.is_away())
	car.visible = phase != "away"
	# A car on the move holds any gate in its way open; a parked one never does.
	if phase in ["depart", "return"]: car.add_to_group(GateFlow.DRIVING_GROUP)
	else: car.remove_from_group(GateFlow.DRIVING_GROUP)
	# Rebuild even paused snapshots at their actual saved position.
	var sign: float = float(state.get("drive_sign", 1.0))
	if phase == "depart":
		car.global_position = home.origin + home.basis.z.normalized() * sign * DRIVE_DISTANCE * smoothstep(0.0, 1.0, time / DRIVE_SECONDS)
	elif phase == "return":
		car.global_position = home.origin + home.basis.z.normalized() * sign * DRIVE_DISTANCE * (1.0 - smoothstep(0.0, 1.0, time / DRIVE_SECONDS))
	else: car.global_transform = home
	if step <= 0.0:
		if phase == "board": rig.time = time; rig.tick(0.0, {id: app.player})
		elif phase == "exit": rig.tick_exit(time, app.player, 0.0)
		return
	state.time = time + step
	match phase:
		"walk":
			var destination: Vector3 = rig.stand_point("front"); destination.y = .16
			# Where the door will be may be inside a neighbouring car or a wall:
			# walk to the nearest free spot beside it, found once and kept.
			var kept_walk: Variant = state.get("walk_to", null)
			if kept_walk is Array and (kept_walk as Array).size() == 3:
				destination = Vector3(float(kept_walk[0]), float(kept_walk[1]), float(kept_walk[2]))
			elif not app.world.lot_navigation.point_clear(0, destination):
				var near: Vector3 = app.world.nearest_clear_point(destination, 0, 8)
				if near.is_finite(): destination = near
				state["walk_to"] = [destination.x, destination.y, destination.z]
			else:
				state["walk_to"] = [destination.x, destination.y, destination.z]
			var walk_from: Vector3 = app.player.position
			var arrived: bool = _walk(destination, delta)
			if not arrived and (_stalled(state, walk_from, step) or float(state.time) > WALK_LIMIT):
				app._clear_motion(); app.sim.cancel_action(); app.show_notice("The way to the car is blocked. Clear a path to it and try again."); return
			if arrived:
				app._clear_motion()
				var direction: float = drive_direction(app.world, home, str(state.vehicle))
				if is_zero_approx(direction):
					app.sim.cancel_action(); app.show_notice("Clear the driveway so the car can reach the road."); return
				state["drive_sign"] = direction
				state.erase("walk_to"); state.erase("stall_at"); state["stall"] = 0.0
				_phase(state, "board")
		"board":
			# Reconstruct the beat from saved time; each stage must finish before
			# driving may start. No timeout ever boards a distant walker.
			rig.time = float(state.time); rig.total = 0.0
			if rig.tick(0.0, {id: app.player}):
				_phase(state, "depart")
		"depart":
			car.global_position = home.origin + home.basis.z.normalized() * sign * DRIVE_DISTANCE * smoothstep(0.0, 1.0, float(state.time) / DRIVE_SECONDS)
			if float(state.time) >= DRIVE_SECONDS:
				# The actual work action starts only once the closed car has left.
				var commute: Dictionary = state
				action.merge(app.sim._actions.career_day.duplicate(true), true)
				action.merge({"target_id": "lot_exit", "target_kind": "lot_exit", "target_position": app.world.lot_exit_position(app._member_index(id)), "phase": "approach", "elapsed": 0.0, "progress": 0.0, "paid": false}, true)
				action["commute"] = commute
				_phase(state, "away")
				app.sim.begin_current_action()
		"away":
			car.visible = false
		"return":
			car.global_position = home.origin + home.basis.z.normalized() * sign * DRIVE_DISTANCE * (1.0 - smoothstep(0.0, 1.0, float(state.time) / DRIVE_SECONDS))
			if float(state.time) >= DRIVE_SECONDS:
				car.global_transform = home; _phase(state, "exit")
		"exit":
			car.global_transform = home
			if rig.tick_exit(float(state.time), app.player, delta):
				app._clear_motion()
				# Beside the car may be a neighbouring car, a fence or a wall:
				# step to the nearest free spot so the walk home has a start.
				_land_clear()
				state["back_side"] = app.player.position.x
				state["back_start_z"] = app.player.position.z
				_phase(state, "back")
		"back":
			car.global_transform = home
			var points: PackedVector3Array = _back_points(state)
			var leg: int = int(state.leg)
			if (float(state.time) > BACK_LIMIT or int(state.get("recovery", 0)) >= 3) and leg < points.size():
				# Walled in by furniture or a fence: put them at the nearest free
				# spot to the end of the route and let them be home.
				var last: Vector3 = points[points.size() - 1]
				var free: Vector3 = app.world.nearest_clear_point(Vector3(last.x, .16, last.z), 0, 16)
				app.player.global_position = free if free.is_finite() else app.world.lot_return_position(app._member_index(id))
				state.leg = points.size()
				leg = points.size()
			if leg < points.size():
				var walk_from: Vector3 = app.player.position
				if _walk(points[leg], delta):
					app._clear_motion(); state.leg = leg + 1; state["stall"] = 0.0; state.erase("stall_at")
				elif _stalled(state, walk_from, step):
					_recover(state)
			if int(state.leg) >= points.size():
				app._clear_motion(); app.away_phases[id] = ""
				app.player.remove_meta("commute_inside")
				_release(id)
				app.world.set_actor_away(id, false, false)
				app.sim.complete_away_return()

## Whether the body has made no real headway for too long while it had somewhere
## to go. Headway is measured against an anchor spot, not frame to frame, so how
## fast the screen refreshes cannot make a walker look stalled.
func _stalled(state: Dictionary, _before: Vector3, step: float) -> bool:
	var anchor: Variant = state.get("stall_at", null)
	var here: Vector3 = app.player.position
	if not (anchor is Array and (anchor as Array).size() == 3) or here.distance_to(Vector3(float(anchor[0]), float(anchor[1]), float(anchor[2]))) > .25:
		state["stall_at"] = [here.x, here.y, here.z]
		state["stall"] = 0.0
		return false
	state["stall"] = float(state.get("stall", 0.0)) + step
	return float(state.stall) > STALL_LIMIT

## Plan the walk home again from wherever they are standing: first the rear
## entrance from here, then the front door, then give up and put them home.
func _recover(state: Dictionary) -> void:
	state["stall"] = 0.0
	state.erase("stall_at")
	state["recovery"] = int(state.get("recovery", 0)) + 1
	state.erase("back_route")
	state.leg = 0
	app._clear_motion()
	_land_clear()
	state["back_side"] = app.player.position.x
	state["back_start_z"] = app.player.position.z

## The points of the walk home, planned once and kept on the saved commute so a
## paused save walks the same way.
func _back_points(state: Dictionary) -> PackedVector3Array:
	var kept: Variant = state.get("back_route", null)
	if kept is Array and (kept as Array).size() > 0:
		var again := PackedVector3Array()
		var sound: bool = (kept as Array).size() <= 4
		for point: Variant in kept:
			if not point is Array or (point as Array).size() != 3: sound = false; break
			again.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		if sound: return again
	var from := Vector3(float(state.get("back_side", app.player.position.x)), .16, float(state.get("back_start_z", app.player.position.z)))
	var route := PackedVector3Array()
	state.leg = 0 # a route planned now is walked from its first point
	if int(state.get("recovery", 0)) < 2: route = plan_back(app.world, from)
	# No usable rear entrance: come in by the front door instead of standing
	# beside the car for good.
	if route.is_empty(): route = front_route(from)
	var packed: Array = []
	for point: Vector3 in route: packed.append([point.x, point.y, point.z])
	state["back_route"] = packed
	return route

## The rear route with every waypoint made real: a point that is inside a piece
## of furniture is moved to the nearest free spot, and each leg must be walkable
## from the last. A route whose last point cannot be reached is no route.
static func plan_back(world: LifeWorld, from: Vector3) -> PackedVector3Array:
	var raw: PackedVector3Array = back_route(world, from)
	var out := PackedVector3Array()
	var cursor: Vector3 = from
	for index: int in range(raw.size()):
		var last: bool = index == raw.size() - 1
		var at: Vector3 = raw[index]
		if not world.lot_navigation.point_clear(0, at): at = world.nearest_clear_point(at, 0, 8)
		if not at.is_finite():
			if last: return PackedVector3Array()
			continue
		if at.distance_to(cursor) < .09:
			if last: out.append(at)
			continue
		if bool(world.route_to(cursor, at).ok):
			out.append(at); cursor = at
		elif last:
			return PackedVector3Array()
	return out

## Move a body that has just got out of the car to the nearest free spot, when
## where the door put it is blocked.
func _land_clear() -> void:
	var at: Vector3 = app.player.global_position
	var flat := Vector3(at.x, .16, at.z)
	if app.world.lot_navigation.point_clear(0, flat): return
	var clear: Vector3 = app.world.nearest_clear_point(flat, 0, 12)
	if clear.is_finite(): app.player.global_position = clear

## Home by the front door, from wherever the car stopped: the doorstep, then a
## free spot just inside that can really be walked to. Without any exterior door
## it is the usual standing place on the lot.
func front_route(from: Vector3 = Vector3.INF) -> PackedVector3Array:
	if not from.is_finite(): from = Vector3(app.player.position.x, .16, app.player.position.z)
	var door: Dictionary = app.residents.home_visit.front_door()
	var route := PackedVector3Array()
	if door.is_empty():
		route.append(app.world.lot_return_position(app._member_index(app.bound_member_id)))
		return route
	var centre := Vector3(door.position.x, .16, door.position.z)
	var outward: Vector3 = door.outward
	var side := Vector3(outward.z, 0, -outward.x)
	var outside: Vector3 = app.world.nearest_clear_point(centre + outward * 1.4, 0, 8)
	if not outside.is_finite() or not bool(app.world.route_to(from, outside).ok):
		route.append(app.world.lot_return_position(app._member_index(app.bound_member_id)))
		return route
	route.append(outside)
	for depth: float in [1.2, 1.6, 2.0, 2.4]:
		for offset: float in [0.0, .5, -.5, 1.0, -1.0]:
			var wish: Vector3 = centre - outward * depth + side * offset
			var inside: Vector3 = app.world.nearest_clear_point(wish, 0, 2)
			if inside.is_finite() and inside.distance_to(wish) <= .3 and bool(app.world.route_to(outside, inside).ok):
				route.append(inside)
				return route
	return route

func _walk(destination: Vector3, delta: float) -> bool:
	app.sim.get_current_action().commute["destination"] = [destination.x, destination.y, destination.z]
	if app.player.position.distance_to(destination) < .09: return true
	if app.path.is_empty() or app.path_index >= app.path.size():
		if not app._set_route(destination):
			app.player.animate(delta, float(app.sim.speed), false, ""); return false
	var moved: bool = app._advance_path(delta)
	app.player.clear_activity_anchor()
	app.player.animate(delta, float(app.sim.speed), moved, "")
	return app.player.position.distance_to(destination) < .09

func _phase(state: Dictionary, phase: String) -> void:
	state.phase = phase; state.time = 0.0

## Find a gap in the rear exterior wall. Walking through three exterior
## waypoints keeps the homeward route around the house until that doorway.
static func back_route(world: LifeWorld, from: Vector3) -> PackedVector3Array:
	var walls: Array = world.construction.records
	if walls.is_empty(): return PackedVector3Array([world.lot_return_position()])
	var rear: float = INF; var front: float = -INF; var left: float = INF; var right: float = -INF
	for wall: Dictionary in walls:
		if int(wall.get("level", 0)) != 0: continue
		var rect: Rect2 = world.construction.wall_rect(wall)
		rear = minf(rear, rect.position.y); front = maxf(front, rect.end.y)
		left = minf(left, rect.position.x); right = maxf(right, rect.end.x)
	var spans: Array[Vector2] = []
	for wall: Dictionary in walls:
		if int(wall.get("level", 0)) != 0: continue
		var rect: Rect2 = world.construction.wall_rect(wall)
		if absf(rect.position.y - rear) < .2 and rect.size.x > rect.size.y: spans.append(Vector2(rect.position.x, rect.end.x))
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for i: int in range(1, spans.size()):
		if spans[i].x - spans[i-1].y < 1.0: continue
		var x: float = (spans[i].x + spans[i-1].y) * .5
		var side: float = minf(left - .9, from.x) if from.x < (left + right) * .5 else maxf(right + .9, from.x)
		# A car parked beside the house may overlap the usual front corner.
		# Start beside the actual exit; a front-yard car first goes outward at
		# that exit's Z, while a side-yard car goes straight toward the rear.
		var outside_z: float = from.z if from.x < left - .9 or from.x > right + .9 else maxf(front + .9, from.z)
		return PackedVector3Array([Vector3(side, .16, outside_z), Vector3(side, .16, rear - .9), Vector3(x, .16, rear - .9), Vector3(x, .16, rear + 1.35)])
	return PackedVector3Array()

## Use a corridor whose complete car footprint clears the house and furniture.
## A car facing the house reverses out; it returns along the same clear bay.
static func drive_direction(world: LifeWorld, home: Transform3D, vehicle: String) -> float:
	var scale: float = 1.0
	for item: Dictionary in world.items:
		if str(item.id) == vehicle: scale = LifeCatalogVariants.size_scale(str(item.get("variant", {}).get("size", "")))
	for sign: float in [1.0, -1.0]:
		var clear: bool = true
		for step: int in range(1, 45):
			var center: Vector3 = home.origin + home.basis.z.normalized() * sign * float(step) * .5
			var x_extent: float = absf(home.basis.x.x) * 1.0 + absf(home.basis.z.x) * 2.25
			var z_extent: float = absf(home.basis.x.z) * 1.0 + absf(home.basis.z.z) * 2.25
			x_extent *= scale; z_extent *= scale
			var area := Rect2(Vector2(center.x - x_extent, center.z - z_extent), Vector2(x_extent * 2.0, z_extent * 2.0))
			for wall: Dictionary in world.construction.records:
				if int(wall.get("level", 0)) == 0 and area.intersects(world.construction.wall_rect(wall)): clear = false; break
			if not clear: break
			for item: Dictionary in world.items:
				if str(item.id) == vehicle or world.item_level(item) != 0 or LifeCatalog.passable(str(item.kind)): continue
				for panel: Rect2 in world.item_panels(item):
					if area.intersects(panel): clear = false; break
				if not clear: break
			if not clear: break
		if clear: return sign
	return 0.0

static func save_error(value: Variant, action: Dictionary = {}, away: Dictionary = {}) -> String:
	if not value is Dictionary or not value.get("vehicle") is String or str(value.vehicle).is_empty() or str(value.get("phase", "")) not in PHASES: return "Invalid work commute."
	if not LifeBuildingState.number(value.get("time"), 0.0, 100000000.0) or not LifeBuildingState.number(value.get("leg"), 0, 4, true): return "Invalid work commute progress."
	var phase: String = str(value.phase)
	var phase_limit: float = float({"board": 3.2, "depart": DRIVE_SECONDS, "return": DRIVE_SECONDS, "exit": 2.6}.get(phase, 100000000.0))
	if float(value.time) > phase_limit: return "Saved car choreography exceeds its phase."
	if not action.is_empty():
		if str(action.id) == "drive_to_work":
			if not away.is_empty() or phase not in ["walk", "board", "depart"] or str(action.get("phase", "")) not in ["queued", "approach"] or str(action.get("target_id", "")) != str(value.vehicle): return "Saved boarding conflicts with work attendance."
		elif str(action.id) == "career_day":
			if str(away.get("activity", "")) != "career" or phase not in ["away", "return", "exit", "back"]: return "Saved car return has no workday."
			if phase != "away" and str(away.get("phase", "")) != "returning": return "Saved car returns before work ends."
		else: return "Saved commute has no work action."
	if phase != "walk" and not value.has("drive_sign"): return "Saved commute has no clear driveway."
	if phase == "back" and not value.has("back_side"): return "Saved commute has no back entrance route."
	if value.has("drive_sign") and (not LifeBuildingState.number(value.drive_sign, -1, 1, true) or float(value.drive_sign) == 0.0): return "Invalid saved driveway direction."
	if value.has("back_side") and not LifeBuildingState.number(value.back_side, -10000, 10000): return "Invalid saved back entrance route."
	if value.has("back_start_z") and not LifeBuildingState.number(value.back_start_z, -10000, 10000): return "Invalid saved back entrance route."
	if value.has("destination") and not LifeJourneyState.vector_valid(value.destination): return "Invalid saved commute walking destination."
	if value.has("back_route"):
		var route: Variant = value.back_route
		if not route is Array or (route as Array).size() > 4: return "Invalid saved walk home."
		for point: Variant in route:
			if not LifeJourneyState.vector_valid(point): return "Invalid saved walk home."
	if value.has("walk_to") and not LifeJourneyState.vector_valid(value.walk_to): return "Invalid saved walk to the car."
	if value.has("stall_at") and not LifeJourneyState.vector_valid(value.stall_at): return "Invalid saved walk progress."
	if value.has("recovery") and not LifeBuildingState.number(value.recovery, 0, 3, true): return "Invalid saved walk recovery."
	if value.has("stall") and not LifeBuildingState.number(value.stall, 0, 1000): return "Invalid saved walk progress."
	return ""

## Cabin choreography is a supported vehicle pose, not ordinary floor walking.
## Validate its exact saved point against the same time-based entry/exit beats.
static func cabin_position_matches(action: Dictionary, at: Vector3, vehicle: Dictionary) -> bool:
	var state: Dictionary = action.get("commute", {})
	if state.is_empty() or vehicle.is_empty() or str(vehicle.get("kind", "")) not in ["car", "car_electric", "electric_car"]: return false
	var phase: String = str(state.phase)
	if phase not in ["board", "depart", "away", "return", "exit"]: return false
	var transform := Transform3D(Basis(Vector3.UP, deg_to_rad(float(vehicle.get("rotation", 0)))), Vector3(float(vehicle.x), .16 + float(vehicle.get("hang", 0)), float(vehicle.z)))
	var scale: float = LifeCatalogVariants.size_scale(str(vehicle.get("size", "")))
	var stand: Vector3 = transform * (Vector3(1.42, 0, -.092) * scale)
	var seat: Vector3 = transform * (Vector3(.36, 0, .05) * scale)
	var expected: Vector3 = seat
	var time: float = float(state.time)
	if phase == "board":
		if time < 1.5: expected = stand
		elif time < 2.6: expected = stand.lerp(seat, smoothstep(0, 1, (time - 1.5) / 1.1))
	elif phase == "exit":
		stand.y = .16
		if time >= 1.9: expected = stand
		elif time >= .8: expected = seat.lerp(stand, smoothstep(0, 1, (time - .8) / 1.1))
	return at.distance_to(expected) < .1
