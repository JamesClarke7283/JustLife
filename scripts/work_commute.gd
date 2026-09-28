extends RefCounted
## A work commute owns the body from the walk to the car until the back-door
## return. Its small phase record lives on the ordinary saved work action.
const Entry = preload("res://scripts/car_entry.gd")
const DRIVE_SECONDS: float = 4.0
const DRIVE_DISTANCE: float = 22.0
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
			if _walk(destination, delta):
				app._clear_motion()
				var direction: float = drive_direction(app.world, home, str(state.vehicle))
				if is_zero_approx(direction):
					app.sim.cancel_action(); app.show_notice("Clear the driveway so the car can reach the road."); return
				state["drive_sign"] = direction
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
				state["back_side"] = app.player.position.x
				state["back_start_z"] = app.player.position.z
				_phase(state, "back")
		"back":
			car.global_transform = home
			var points: PackedVector3Array = back_route(app.world, Vector3(float(state.get("back_side", app.player.position.x)), .16, float(state.get("back_start_z", app.player.position.z))))
			var leg: int = int(state.leg)
			if points.is_empty():
				if time == 0.0: app.show_notice("Clear a path through the back entrance to come home.")
				app.player.animate(delta, float(app.sim.speed), false, "")
				return
			if leg < points.size() and _walk(points[leg], delta):
				app._clear_motion(); state.leg = leg + 1
			if int(state.leg) >= points.size():
				app._clear_motion(); app.away_phases[id] = ""
				app.player.remove_meta("commute_inside")
				_release(id)
				app.world.set_actor_away(id, false, false)
				app.sim.complete_away_return()

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
