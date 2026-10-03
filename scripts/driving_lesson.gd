extends RefCounted
class_name LifeDrivingLesson
## A practical driving lesson as the player sees it. The instructor's car (blue, with
## L plates) drives in along the road and pulls up at the kerb, the learner walks out
## of the front door and gets in, the car drives off, and 90 game minutes later it is
## back: the learner gets out and walks straight back in through the front door while
## the empty car drives away again.
##
## The phase record lives on the saved `driving_lesson` action as `action.lesson`,
## exactly as a work commute keeps its own: phases arrive, walk, board, depart, away,
## return, exit and back. Only the time spent away is the sim's (`begin_driving_lesson`
## and `_tick_lesson_away` in life_sim.gd); everything before and after is body
## choreography that this script owns and a save can resume. The car itself is not
## saved. It is rebuilt from the phase and its time, and a car already driving off
## after the learner is home is simply not there after a load.
##
## The kerb is shared with the school bus, the baby's homecoming car and the
## shared trip car, so the car waits out of sight while the bus is on the lot or
## a birth arrival is under way.

const Entry = preload("res://scripts/car_entry.gd")
const Drive = preload("res://scripts/vehicle_drive.gd")
const Path = preload("res://scripts/vehicle_path.gd")
const Rig = preload("res://scripts/vehicle_rig.gd")
const Road = preload("res://scripts/road.gd")
const LessonCar = preload("res://scripts/lesson_car.gd")
const School = preload("res://scripts/driving_school.gd")

const PHASES: Array[String] = ["arrive", "walk", "board", "depart", "away", "return", "exit", "back"]
## Phases that can be saved before the lesson has left, and while it is away or coming home.
const HOME_PHASES: Array[String] = ["arrive", "walk", "board", "depart"]
const AWAY_PHASES: Array[String] = ["away", "return", "exit", "back"]
const BOARD_SECONDS: float = 3.2
const EXIT_SECONDS: float = 2.6
## A walk to the car, or home from it, that has made no progress in this many game
## seconds is given up on rather than left standing in the road.
const WALK_LIMIT: float = 90.0
const BACK_LIMIT: float = 90.0
## Standing still this long with somewhere to be is a stall: the walk is planned
## again, then finished from the nearest free spot.
const STALL_LIMIT: float = 8.0
## An empty car that has been left at the kerb waits this long before it drives off.
const IDLE_BEFORE_LEAVING: float = 0.6
## Actions that a lesson booking never puts aside (besides a duty or a ritual, see
## `LifeSim.homework_enforcement_blocked`): a short need break, or anything shared.
const KEEPS: Array[String] = ["toilet", "shower", "bath", "eat_meal", "snack", "cook", "serve_meal", "store_meal", "wash_hands", "brush_teeth", "birthday", "help_homework"]

var app: Node
## Member id to the lesson being played for them: {car, entry, wheels, body, action, arrive, leave}.
var views: Dictionary = {}
## Cars with nobody to wait for, driving off (or still pulling up) before they are taken away.
var orphans: Array = []


func _init(owner: Node) -> void: app = owner

## The kerb spot every lesson car stops on, facing east in the near lane.
static func home() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI * .5), Vector3(Road.KERB_PARK_X, 0.0, Road.KERB_PARK_Z))

## The phase record for a lesson that has none yet: a new lesson starts with the car
## coming; one already away (an older save, or a hand-made one) picks up where the sim is.
static func fresh_record(sim: LifeSim) -> Dictionary:
	var phase: String = "arrive"
	if sim.is_away() and str(sim.away_state.get("activity", "")) == School.LESSON_ACTION: phase = "away" if str(sim.away_state.get("phase", "")) == "away" else "return"
	return {"phase": phase, "time": 0.0, "leg": 0}

func owns(action: Dictionary) -> bool:
	return str(action.get("id", "")) == School.LESSON_ACTION

## Whether any lesson is being played out, or a car is still driving off, so trips and
## house moves leave the kerb alone.
func running() -> bool:
	if not orphans.is_empty(): return true
	for member: Dictionary in app.household.members:
		if owns(member.sim.get_current_action()): return true
	return false

func prepare(action: Dictionary) -> void:
	if views.has(app.bound_member_id) and not is_same(views[app.bound_member_id].action, action): _release(app.bound_member_id)
	if not action.has("lesson"): action["lesson"] = fresh_record(app.sim)
	app._clear_motion()
	app.pending_action = action

func caption(action: Dictionary) -> String:
	var phase: String = str(action.get("lesson", {}).get("phase", ""))
	if phase == "arrive" and _kerb_busy(): return "Waiting for the instructor's car"
	return str({"arrive": "The instructor's car is pulling up", "walk": "Walking out to the instructor's car", "board": "Getting into the car", "depart": "Driving off with the instructor",
		"away": "", "return": "Driving back with the instructor", "exit": "Getting out of the car", "back": "Walking home"}.get(phase, ""))


# --------------------------------------------------------------- the booking

## Why a lesson cannot be started for this member now, or "" after queueing it. The
## player's "Have a lesson now" and a booking that has come due both come through here.
func request(member_id: String, give_way: bool = false) -> String:
	if app.mode != "live" or str(app.current_venue) != "home": return "Lessons start from home."
	var sim: LifeSim = app.household.member_sim(member_id)
	if sim == null: return "Choose a household member for the lesson."
	if running(): return "A driving lesson is already under way."
	if not app.birth_arrival.is_empty() or app.residents.home_visit.active() or not app.residents.trip.is_empty(): return "Wait until the arrival, the visit or the trip is over."
	var first: String = str(sim.character.name).split(" ")[0]
	if sim.is_away(): return "%s needs to be home for a lesson." % first
	if not sim.action_queue.is_empty() and not (give_way and _can_give_way(sim)): return "Finish or cancel what %s is doing first." % first
	if app.traversal.busy(member_id): return "Let %s finish on the stairs first." % first
	var problem: String = sim.driving_error(School.LESSON_ACTION)
	if not problem.is_empty(): return problem
	for index: int in range(sim.action_queue.size() - 1, -1, -1): sim.cancel_action(index)
	if not sim.queue_action(School.LESSON_ACTION, "lot_exit", app.world.lot_exit_position(app._member_index(member_id))): return "The lesson could not be started."
	return ""

## Whether the plans a Lifelet has can all give way to a lesson that is due.
func _can_give_way(sim: LifeSim) -> bool:
	for action: Dictionary in sim.action_queue:
		if sim.homework_enforcement_blocked(str(action.id), action) or str(action.id) in KEEPS or str(action.id) == "homework": return false
	return true

## Every frame in live play: a booked lesson that has come due starts, once its learner
## is home and what they are doing can give way. Past the grace the sim gives the booking up.
func consider_bookings() -> void:
	if app.mode != "live" or str(app.current_venue) != "home" or running(): return
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		if not sim.driving_booking_due() or sim.is_away() or not _can_give_way(sim): continue
		if int(app.household.speed) <= 0: return
		if request(str(member.id), true).is_empty(): return


# --------------------------------------------------------------------- bodies

func _kerb_busy() -> bool:
	var bus: LifeSchoolBus = LifeSchoolBus.active
	if bus != null and bus.phase != "gone": return true
	if not app.birth_arrival.is_empty() or not orphans.is_empty(): return true
	return false

func _view(id: String, action: Dictionary) -> Dictionary:
	if views.has(id) and is_same(views[id].action, action): return views[id]
	var view: Dictionary = {"action": action, "body": app.player, "arrive": Drive.kerb_path(true), "leave": Drive.kerb_path(false)}
	views[id] = view
	return view

## The car for this lesson, built when it is first needed (not while it waits for the kerb).
func _car(id: String, view: Dictionary) -> Node3D:
	if is_instance_valid(view.get("car")): return view.car
	var car: Node3D = LessonCar.build()
	app.world.house.add_child(car)
	car.global_transform = home()
	for body: Node in car.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0
	view["car"] = car
	view["wheels"] = Rig.attach(car)
	view["entry"] = Entry.new(car, [{"id": id, "stage": str(app.sim.character.get("age_stage", "teen"))}], 1.0)
	return car

func _pose(view: Dictionary, path: Dictionary, time: float) -> Dictionary:
	var car: Node3D = view.car
	var rig: Dictionary = view.wheels
	var wheelbase: float = float(rig.get("wheelbase", 0.0)) if bool(rig.get("ok", false)) else Path.WHEELBASE
	var now: Dictionary = Path.state_at(path, time, wheelbase)
	car.global_transform = Transform3D(Basis(Vector3.UP, float(now.yaw)), Vector3(float(now.x), 0.0, float(now.z)))
	Rig.apply(rig, float(now.steer), float(now.spin))
	Rig.lights(rig, bool(now.braking) or int(now.gear) < 0)
	return now

func _park(view: Dictionary) -> void:
	view.car.global_transform = home()
	var rig: Dictionary = view.get("wheels", {})
	if rig.is_empty(): return
	Rig.reset(rig)
	Rig.lights(rig, false)

func _phase(state: Dictionary, phase: String) -> void:
	state.phase = phase
	state.time = 0.0

func cleanup(delta: float = 0.0) -> void:
	for id: String in views.keys():
		var member: LifeSim = app.household.member_sim(id)
		if not is_instance_valid(member) or not owns(member.get_current_action()) or not is_same(views[id].action, member.get_current_action()): _release(id)
	_tick_orphans(delta)
	LessonCar.active = null
	for id: String in views:
		var car: Variant = views[id].get("car")
		if is_instance_valid(car) and (car as Node3D).visible: LessonCar.active = car as Node3D
	for orphan: Dictionary in orphans:
		if is_instance_valid(orphan.car) and (orphan.car as Node3D).visible: LessonCar.active = orphan.car

## A lesson that ends or is called off. The learner is put back on their feet beside the
## kerb, and the car (if there is one) drives off by itself.
func _release(id: String) -> void:
	if not views.has(id): return
	var view: Dictionary = views[id]
	var body: Variant = view.get("body")
	if is_instance_valid(body) and (body as LifeActor).has_meta("lesson_inside"):
		(body as LifeActor).remove_meta("lesson_inside")
		var actor: LifeActor = body
		actor.global_position = _kerb_side_spot()
		actor.clear_activity_anchor()
		actor.visible = true
	if is_instance_valid(view.get("car")): _send_off(view)
	views.erase(id)

## Where a learner stands beside the parked car's front door: the spot by the kerb, or the
## nearest free place to it. The car may be anywhere on the road when this is asked.
func _kerb_side_spot() -> Vector3:
	var door: Vector3 = home() * Vector3(1.42, 0, -.092)
	var spot := Vector3(door.x, .16, door.z)
	if app.world.lot_navigation.point_clear(0, spot): return spot
	var near: Vector3 = app.world.nearest_clear_point(spot, 0, 8)
	return near if near.is_finite() else spot

## Hand a car over to drive away on its own: from the kerb, or on with its arrival if it
## has not finished pulling up.
func _send_off(view: Dictionary) -> void:
	var car: Node3D = view.car
	var entry: Variant = view.get("entry")
	if entry != null: for door: String in entry.doors: entry.set_door(door, 0.0)
	var orphan: Dictionary = {"car": car, "wheels": view.get("wheels", {}), "leave": view.leave, "arrive": view.arrive, "phase": "leave", "time": 0.0}
	var action: Dictionary = view.get("action", {})
	var phase: String = str(action.get("lesson", {}).get("phase", ""))
	if phase == "arrive" and float(action.lesson.time) < Path.duration(view.arrive):
		orphan["phase"] = "arrive"
		orphan["time"] = float(action.lesson.time)
	elif phase == "depart":
		orphan["time"] = float(action.lesson.time)
	elif phase == "away" or not car.visible:
		car.queue_free()
		view.erase("car")
		return
	else:
		orphan["time"] = -IDLE_BEFORE_LEAVING
	orphans.append(orphan)
	view.erase("car")

func _tick_orphans(delta: float) -> void:
	var step: float = delta * float(app.household.speed if is_instance_valid(app.household) else 1)
	for index: int in range(orphans.size() - 1, -1, -1):
		var orphan: Dictionary = orphans[index]
		# A car in a world that has been replaced (a load) is gone with it.
		if not is_instance_valid(orphan.car):
			orphans.remove_at(index)
			continue
		var car: Node3D = orphan.car
		orphan.time = float(orphan.time) + step
		var path: Dictionary = orphan.arrive if str(orphan.phase) == "arrive" else orphan.leave
		var t: float = maxf(0.0, float(orphan.time))
		var rig: Dictionary = orphan.wheels
		var wheelbase: float = float(rig.get("wheelbase", 0.0)) if bool(rig.get("ok", false)) else Path.WHEELBASE
		var now: Dictionary = Path.state_at(path, t, wheelbase)
		car.global_transform = Transform3D(Basis(Vector3.UP, float(now.yaw)), Vector3(float(now.x), 0.0, float(now.z)))
		if not rig.is_empty():
			Rig.apply(rig, float(now.steer), float(now.spin))
			Rig.lights(rig, bool(now.braking) or int(now.gear) < 0)
		if t >= Path.duration(path):
			if str(orphan.phase) == "arrive":
				orphan["phase"] = "leave"
				orphan["time"] = -IDLE_BEFORE_LEAVING
			else:
				car.queue_free()
				orphans.remove_at(index)

func _dress() -> void:
	if not app.player.has_meta("preview_profile") and LifeCharacterIdentity.wardrobe_fields(app.player.profile) != LifeCharacterIdentity.wardrobe_fields(app.sim.character):
		app.player.apply_wardrobe(app.sim.character)
		if app.bound_member_id == app.household.selected_id(): app.portrait_stale = true


## One frame of the lesson for the member the controller has bound.
func tick(delta: float) -> void:
	var action: Dictionary = app.sim.get_current_action()
	if not owns(action): return
	if not action.has("lesson"): prepare(action)
	_dress()
	app.player.pregnancy_bump = app.household.pregnancy_progress() if app.household.pregnancy_mother_id() == app.bound_member_id else 0.0
	var state: Dictionary = action.lesson
	var id: String = app.bound_member_id
	var view: Dictionary = _view(id, action)
	var phase: String = str(state.phase)
	var step: float = delta * float(app.sim.speed)
	# The lesson ended early (called off) or the clock ran out: the way home starts.
	if phase == "away" and str(app.sim.away_state.get("phase", "")) == "returning":
		_phase(state, "return")
		phase = "return"
	if phase in ["board", "depart", "away", "return", "exit"]: app.player.set_meta("lesson_inside", true)
	else: app.player.remove_meta("lesson_inside")
	var visible_body: bool = phase in ["arrive", "walk", "board", "exit", "back"]
	app.world.set_actor_away(id, not visible_body, app.sim.is_away())
	match phase:
		"arrive": _tick_arrive(id, view, state, step, delta)
		"walk": _tick_walk(id, view, state, step, delta)
		"board": _tick_board(id, view, state, step)
		"depart": _tick_depart(id, view, state, step)
		"away":
			if is_instance_valid(view.get("car")): view.car.visible = false
		"return": _tick_return(id, view, state, step)
		"exit": _tick_exit(id, view, state, step, delta)
		"back": _tick_back(id, view, state, step, delta)

func _tick_arrive(id: String, view: Dictionary, state: Dictionary, step: float, delta: float) -> void:
	var duration: float = Path.duration(view.arrive)
	if float(state.time) <= 0.0 and not is_instance_valid(view.get("car")):
		if _kerb_busy():
			app.player.animate(delta, float(app.sim.speed), false, "")
			return
		_car(id, view)
		_pose(view, view.arrive, 0.0)
	var car: Node3D = _car(id, view)
	car.visible = true
	state.time = float(state.time) + step
	_pose(view, view.arrive, float(state.time))
	app.player.animate(delta, float(app.sim.speed), false, "")
	if float(state.time) >= duration:
		_park(view)
		_phase(state, "walk")

func _tick_walk(id: String, view: Dictionary, state: Dictionary, step: float, delta: float) -> void:
	var car: Node3D = _car(id, view)
	car.visible = true
	_park(view)
	var rig: RefCounted = view.entry
	state.time = float(state.time) + step
	var destination: Vector3 = rig.stand_point("front")
	destination.y = .16
	# Where the door will be may be inside a neighbouring thing: walk to the nearest free
	# spot beside it, found once and kept.
	var kept: Variant = state.get("walk_to", null)
	if kept is Array and (kept as Array).size() == 3:
		destination = Vector3(float(kept[0]), float(kept[1]), float(kept[2]))
	else:
		if not app.world.lot_navigation.point_clear(0, destination):
			var near: Vector3 = app.world.nearest_clear_point(destination, 0, 8)
			if near.is_finite(): destination = near
		state["walk_to"] = [destination.x, destination.y, destination.z]
	var arrived: bool = _walk(destination, delta)
	if not arrived and (_stalled(state, step) or float(state.time) > WALK_LIMIT):
		app._clear_motion()
		app.sim.cancel_action()
		app.show_notice("The way out to the instructor's car is blocked. Clear a path to the front door and try again.")
		return
	if arrived:
		app._clear_motion()
		state.erase("walk_to")
		state.erase("stall_at")
		state["stall"] = 0.0
		_phase(state, "board")

func _tick_board(id: String, view: Dictionary, state: Dictionary, step: float) -> void:
	var car: Node3D = _car(id, view)
	car.visible = true
	_park(view)
	var rig: RefCounted = view.entry
	state.time = float(state.time) + step
	rig.time = float(state.time)
	rig.total = 0.0
	if rig.tick(0.0, {id: app.player}): _phase(state, "depart")

func _tick_depart(id: String, view: Dictionary, state: Dictionary, step: float) -> void:
	var car: Node3D = _car(id, view)
	car.visible = true
	state.time = float(state.time) + step
	var duration: float = Path.duration(view.leave)
	_pose(view, view.leave, minf(float(state.time), duration))
	if float(state.time) < duration: return
	# The lesson itself starts only once the car has left.
	car.visible = false
	_phase(state, "away")
	# If it cannot start the sim cancels the action, and the next cleanup puts the
	# learner back on their feet at the kerb and takes the car away.
	app.sim.begin_driving_lesson()

func _tick_return(id: String, view: Dictionary, state: Dictionary, step: float) -> void:
	var car: Node3D = _car(id, view)
	state.time = float(state.time) + step
	var duration: float = Path.duration(view.arrive)
	car.visible = true
	_pose(view, view.arrive, minf(float(state.time), duration))
	if float(state.time) >= duration:
		_park(view)
		_phase(state, "exit")

func _tick_exit(id: String, view: Dictionary, state: Dictionary, step: float, delta: float) -> void:
	var car: Node3D = _car(id, view)
	car.visible = true
	_park(view)
	var rig: RefCounted = view.entry
	state.time = float(state.time) + step
	if rig.tick_exit(float(state.time), app.player, delta):
		app._clear_motion()
		app.player.remove_meta("lesson_inside")
		_land_clear()
		_phase(state, "back")
		state.erase("back_route")
		state["leg"] = 0
		# The empty car drives away while the learner walks home.
		_send_off(view)
		app.world.set_actor_away(id, false, app.sim.is_away())

func _tick_back(id: String, view: Dictionary, state: Dictionary, step: float, delta: float) -> void:
	state.time = float(state.time) + step
	var points: PackedVector3Array = _home_points(state)
	var leg: int = int(state.leg)
	if (float(state.time) > BACK_LIMIT or int(state.get("recovery", 0)) >= 3) and leg < points.size():
		# Walled in by furniture: put them at the nearest free spot to the end of the
		# route and let them be home.
		var last: Vector3 = points[points.size() - 1]
		var free: Vector3 = app.world.nearest_clear_point(Vector3(last.x, .16, last.z), 0, 16)
		app.player.global_position = free if free.is_finite() else app.world.lot_return_position(app._member_index(id))
		state.leg = points.size()
		leg = points.size()
	if leg < points.size():
		if _walk(points[leg], delta):
			app._clear_motion()
			state.leg = leg + 1
			state["stall"] = 0.0
			state.erase("stall_at")
		elif _stalled(state, step):
			_recover(state)
	else:
		app.player.animate(delta, float(app.sim.speed), false, "")
	if int(state.leg) >= points.size():
		app._clear_motion()
		app.away_phases[id] = ""
		app.player.remove_meta("lesson_inside")
		var done: LifeSim = app.sim
		_release(id)
		app.world.set_actor_away(id, false, false)
		done.complete_away_return()


# ---------------------------------------------------------------- walking

func _walk(destination: Vector3, delta: float) -> bool:
	app.sim.get_current_action().lesson["destination"] = [destination.x, destination.y, destination.z]
	if app.player.position.distance_to(destination) < .09: return true
	if app.path.is_empty() or app.path_index >= app.path.size():
		if not app._set_route(destination):
			app.player.animate(delta, float(app.sim.speed), false, "")
			return false
	var moved: bool = app._advance_path(delta)
	app.player.clear_activity_anchor()
	app.player.animate(delta, float(app.sim.speed), moved, "")
	return app.player.position.distance_to(destination) < .09

## Whether the body has made no real headway for too long while it had somewhere to
## go. Headway is measured against an anchor spot, so the frame rate cannot make a
## walker look stalled.
func _stalled(state: Dictionary, step: float) -> bool:
	var anchor: Variant = state.get("stall_at", null)
	var here: Vector3 = app.player.position
	if not (anchor is Array and (anchor as Array).size() == 3) or here.distance_to(Vector3(float(anchor[0]), float(anchor[1]), float(anchor[2]))) > .25:
		state["stall_at"] = [here.x, here.y, here.z]
		state["stall"] = 0.0
		return false
	state["stall"] = float(state.get("stall", 0.0)) + step
	return float(state.stall) > STALL_LIMIT

## Plan the walk home again from wherever they are standing, then give up and put them home.
func _recover(state: Dictionary) -> void:
	state["stall"] = 0.0
	state.erase("stall_at")
	state["recovery"] = int(state.get("recovery", 0)) + 1
	state.erase("back_route")
	state.leg = 0
	app._clear_motion()
	_land_clear()

## Move a body that has just got out of the car to the nearest free spot, when where
## the door put it is blocked.
func _land_clear() -> void:
	var at: Vector3 = app.player.global_position
	var flat := Vector3(at.x, .16, at.z)
	if app.world.lot_navigation.point_clear(0, flat): return
	var clear: Vector3 = app.world.nearest_clear_point(flat, 0, 12)
	if clear.is_finite(): app.player.global_position = clear

## The walk home through the front door, planned once and kept on the saved record so a
## paused save walks the same way. A spot just inside that another Lifelet already
## stands on is passed over.
func _home_points(state: Dictionary) -> PackedVector3Array:
	var kept: Variant = state.get("back_route", null)
	if kept is Array and (kept as Array).size() > 0:
		var again := PackedVector3Array()
		var sound: bool = (kept as Array).size() <= 4
		for point: Variant in kept:
			if not point is Array or (point as Array).size() != 3: sound = false; break
			again.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		if sound: return again
	state.leg = 0
	var taken: Array = []
	for other: String in app.world.actors:
		var body: LifeActor = app.world.actors[other]
		if other != app.bound_member_id and body.visible and app.world.point_level(body.position) == 0: taken.append(Vector3(body.position.x, .16, body.position.z))
	var route: PackedVector3Array = app.work_commute.front_route(Vector3(app.player.position.x, .16, app.player.position.z), taken)
	var packed: Array = []
	for point: Vector3 in route: packed.append([point.x, point.y, point.z])
	state["back_route"] = packed
	return route


# ------------------------------------------------------------------- saving

## "" when a saved lesson record is sound. `action` is the lesson action it rides on and
## `away` the Lifelet's absence: before the car has left there is none, and once it has
## the sim's lesson absence says which phases are possible.
static func save_error(value: Variant, action: Dictionary = {}, away: Dictionary = {}) -> String:
	if not value is Dictionary or str(value.get("phase", "")) not in PHASES: return "Invalid driving lesson."
	if not LifeBuildingState.number(value.get("time"), 0.0, 100000000.0) or not LifeBuildingState.number(value.get("leg"), 0, 4, true): return "Invalid driving lesson progress."
	var phase: String = str(value.phase)
	var limit: float = {"board": BOARD_SECONDS, "exit": EXIT_SECONDS, "depart": Path.duration(Drive.kerb_path(false)) + .5, "return": Path.duration(Drive.kerb_path(true)) + .5, "arrive": Path.duration(Drive.kerb_path(true)) + .5}.get(phase, 100000000.0)
	if float(value.time) > limit: return "Saved lesson choreography exceeds its phase."
	if not action.is_empty():
		if str(action.get("id", "")) != School.LESSON_ACTION: return "Saved lesson record has no lesson action."
		if away.is_empty():
			if phase not in HOME_PHASES or str(action.get("phase", "")) not in ["queued", "approach"] or str(action.get("target_id", "")) != "lot_exit": return "Saved lesson conflicts with its action."
		else:
			if str(away.get("activity", "")) != School.LESSON_ACTION: return "Saved lesson record disagrees with the absence."
			if phase not in AWAY_PHASES or (str(away.get("phase", "")) == "away" and phase != "away"): return "Saved lesson record disagrees with the absence."
	for key: String in ["destination", "walk_to", "stall_at"]:
		if value.has(key) and not LifeJourneyState.vector_valid(value[key]): return "Invalid saved lesson walk."
	if value.has("back_route"):
		var route: Variant = value.back_route
		if not route is Array or (route as Array).size() > 4: return "Invalid saved walk home."
		for point: Variant in route:
			if not LifeJourneyState.vector_valid(point): return "Invalid saved walk home."
	if value.has("recovery") and not LifeBuildingState.number(value.recovery, 0, 3, true): return "Invalid saved lesson recovery."
	if value.has("stall") and not LifeBuildingState.number(value.stall, 0, 1000): return "Invalid saved lesson walk progress."
	if phase == "back" and not value.has("back_route") and int(value.get("recovery", 0)) == 0 and float(value.time) > 0.0: return "Saved lesson has no walk home."
	return ""

## Whether a stationary body at `at` is where the lesson's own choreography puts it
## (in or beside the parked car), which is not ordinary floor. The car is always the
## kerb spot, so the door and the seat are fixed points.
static func cabin_position_matches(action: Dictionary, at: Vector3) -> bool:
	var state: Dictionary = action.get("lesson", {})
	if state.is_empty() or str(action.get("id", "")) != School.LESSON_ACTION: return false
	var phase: String = str(state.phase)
	if phase not in ["board", "depart", "away", "return", "exit"]: return false
	var kerb: Transform3D = home()
	var stand: Vector3 = kerb * Vector3(1.42, 0, -.092)
	var seat: Vector3 = kerb * Vector3(.36, 0, .05)
	var expected: Vector3 = seat
	var time: float = float(state.time)
	if phase == "board":
		if time < 1.5: expected = stand
		elif time < 2.6: expected = stand.lerp(seat, smoothstep(0, 1, (time - 1.5) / 1.1))
	elif phase == "exit":
		if time >= 1.9: expected = stand
		elif time >= .8: expected = seat.lerp(stand, smoothstep(0, 1, (time - .8) / 1.1))
	# Height is the car's own, not the lot's, so only the ground plan is compared.
	return Vector2(at.x - expected.x, at.z - expected.z).length() < .1
