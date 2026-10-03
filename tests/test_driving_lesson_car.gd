extends SceneTree
## A practical driving lesson as the player sees it. The instructor's car (blue, with L
## plates on the bonnet, the boot lid and the roof) drives in along the road and stops
## on the kerb spot exactly, the learner walks out and gets in through the front door of
## the car, it drives off, the lesson runs for 90 game minutes, the car comes back, the
## learner gets out and walks indoors while the empty car drives away. A save in the
## middle of the drive rebuilds the same pose. The car waits while the school bus is
## on the lot, a booking starts a lesson by itself, trips and the planner know about it.
const DT: float = .05
const Road = preload("res://scripts/road.gd")
const Planner = preload("res://scripts/vehicle_planner.gd")
const Lesson = preload("res://scripts/driving_lesson.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame
func gap(a: float, b: float) -> float: return absf(wrapf(a - b, -PI, PI))

## A household of a parent and a teenager who has finished the driving theory, on the
## given calendar day at the given time (day 41 is a Saturday, 36 a Monday).
func fresh(day: int, minutes: float, speed: int = 3, canonical: bool = false, teen_first: bool = false) -> String:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "teen", "traits": []}]
	if teen_first: app.household_profiles.reverse()
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find("willow"))
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_speed(0)
	if canonical:
		# Saves keep every Lifelet's journey only in the versioned construction format.
		var migrated: Dictionary = LifeBuildingState.migrate(app.world.construction.snapshot())
		check(migrated.ok, "The fixture migrates to versioned construction")
		app.world.construction.restore(migrated.state)
		app.world.rebuild_navigation(); app._refresh_sim_targets()
	app.household.day = day
	app.household.minutes = minutes
	var kit: String = ""
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		sim.day = day; sim.minutes = minutes; sim.autonomy = false
		sim.career.schedule = LifeCareerSchedule.fresh(day)
		if str(sim.character.age_stage) == "teen": sim.education = LifeEducation.fresh("teen", day)
		for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 100.0
		if str(sim.character.age_stage) == "teen":
			kit = str(member.id)
			sim.lifecycle["stage_day"] = 1
			sim.driving = LifeDrivingSchool.fresh("teen")
			sim.driving["theory_days"] = 7
			sim.driving["last_theory_day"] = day - 1
			sim.driving["introduced_day"] = 21
			sim.driving["last_reminder_day"] = day - 1
	app.household.set_speed(speed)
	return kit

func view_of(kit: String) -> Dictionary: return app.driving_lesson.views.get(kit, {})
func phase_of(sim: LifeSim) -> String: return str(sim.get_current_action().get("lesson", {}).get("phase", ""))

## The angle a front tyre is steered, read off the wheel node itself.
func steer_of(rig: Dictionary) -> float:
	for wheel: Dictionary in rig.wheels:
		if bool(wheel.front) and not bool(wheel.hub):
			var delta: Basis = (wheel.node as Node3D).transform.basis * (wheel.rest as Transform3D).basis.inverse()
			var axle: Vector3 = delta * Vector3(1, 0, 0)
			return atan2(-axle.z, axle.x)
	return 0.0

func kerb_distance(car: Node3D) -> float:
	return Vector2(car.global_position.x - Road.KERB_PARK_X, car.global_position.z - Road.KERB_PARK_Z).length()

func run() -> void:
	await _a_whole_lesson()
	await _refusals_and_the_bus()
	await _a_booking_starts_by_itself()
	await _trips_and_the_planner()
	await _saves()
	await _reload_in_every_phase()
	await _cancel_while_waiting()
	await _departure_refused()
	await _driver_sits_in_front()
	print("DRIVING_LESSON_CAR %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _a_whole_lesson() -> void:
	var kit: String = await fresh(41, 600.0)
	var sim: LifeSim = app.household.member_sim(kit)
	var actor: LifeActor = app.world.actors[kit]
	var started_at: Vector3 = actor.position
	check(app.driving_lesson.request(kit) == "", "A lesson is requested on a Saturday morning with the theory done")
	check(str(sim.get_current_action().get("id", "")) == "driving_lesson", "The lesson is the learner's front action")
	var seen: Array[String] = []
	var first_car: Vector3 = Vector3.INF
	var kerb_best: float = INF
	var kerb_yaw: float = INF
	var plates_visible: bool = false
	var plate_size: float = 0.0
	var door_max: float = 0.0
	var boarded_hidden: bool = false
	var walked: float = 0.0
	var reached_door: float = INF
	var last_actor: Vector3 = actor.position
	var left_x: float = -INF
	var away_seen: bool = false
	var car_hidden_away: bool = false
	var returned_at_kerb: float = INF
	var exit_visible: bool = false
	var came_in: bool = false
	var orphan_seen: bool = false
	var orphan_max_x: float = -INF
	var steer_seen: float = 0.0
	var in_body_shape: bool = false
	for frame: int in 20000:
		app._process(DT)
		var phase: String = phase_of(sim)
		if sim.is_away() and phase.is_empty(): phase = "away" if str(sim.away_state.phase) == "away" else "return"
		if not phase.is_empty() and not seen.has(phase): seen.append(phase)
		var view: Dictionary = view_of(kit)
		var car: Node3D = view.get("car") if is_instance_valid(view.get("car")) else null
		if car != null:
			if first_car == Vector3.INF and car.visible: first_car = car.global_position
			if phase == "arrive" and car.visible: steer_seen = maxf(steer_seen, absf(steer_of(view.wheels)))
			if phase in ["walk", "board"]:
				kerb_best = minf(kerb_best, kerb_distance(car))
				kerb_yaw = gap(car.rotation.y, PI * .5)
				for plate_name: String in ["LearnerPlateFront", "LearnerPlateRear", "LearnerRoofSign"]:
					var plate: Node3D = car.get_node_or_null(plate_name)
					plates_visible = plate != null and plate.is_visible_in_tree()
					if plate != null: plate_size = minf(plate_size if plate_size > 0.0 else 9.0, float(plate.get_meta("plate_size", 0.0)))
		if phase == "walk":
			walked += actor.position.distance_to(last_actor)
			if view.has("entry"): reached_door = minf(reached_door, Vector2(actor.position.x - view.entry.stand_point("front").x, actor.position.z - view.entry.stand_point("front").z).length())
		if phase == "board" and view.has("entry"):
			door_max = maxf(door_max, view.entry.door_amount("front"))
			reached_door = minf(reached_door, Vector2(actor.position.x - view.entry.stand_point("front").x, actor.position.z - view.entry.stand_point("front").z).length())
		if phase == "depart" and not actor.visible: boarded_hidden = true
		if phase == "depart" and car != null: left_x = maxf(left_x, car.global_position.x)
		if phase == "away":
			away_seen = true
			if car == null or not car.visible: car_hidden_away = true
		if phase == "exit" and car != null:
			returned_at_kerb = minf(returned_at_kerb, kerb_distance(car))
			if actor.visible: exit_visible = true
		if phase == "back" and not app.driving_lesson.orphans.is_empty():
			orphan_seen = true
			for orphan: Dictionary in app.driving_lesson.orphans:
				if is_instance_valid(orphan.car): orphan_max_x = maxf(orphan_max_x, (orphan.car as Node3D).global_position.x)
		if phase == "back" and app.world.construction.floor_contains(Vector2(actor.position.x, actor.position.z), 0) and actor.position.z < 7.8: came_in = true
		last_actor = actor.position
		if not sim.is_away() and phase.is_empty() and sim.driving.lesson_days.size() > 0: break
		if sim.is_away() and str(sim.away_state.phase) == "away" and frame % 400 == 0: app.household.set_speed(8)
	check(seen == ["arrive", "walk", "board", "depart", "away", "return", "exit", "back"] or seen.slice(0, 5) == ["arrive", "walk", "board", "depart", "away"], "The lesson runs through its phases in order: " + str(seen))
	check(first_car.x < -15.0 and absf(first_car.z - Road.LANE_NEAR_Z) < .2, "The car first appears out on the road at the west edge, in the near lane (%.1f, %.1f)" % [first_car.x, first_car.z])
	check(steer_seen > deg_to_rad(3.0), "Its front wheels steer as it pulls in (%.0f degrees)" % rad_to_deg(steer_seen))
	check(kerb_best < .01 and kerb_yaw < deg_to_rad(.5), "It stops within a centimetre of the kerb spot, facing east (%.4f m, %.2f deg)" % [kerb_best, rad_to_deg(kerb_yaw)])
	check(plates_visible and plate_size >= .3, "The L plates (bonnet, boot, roof) are there, visible and large (smallest %.2f m)" % plate_size)
	check(walked > 2.0 and started_at.distance_to(Vector3(0, started_at.y, 8.83)) > 2.0, "The learner walks out to the car (%.1f m)" % walked)
	check(reached_door < .12, "...to the front door of the car (%.2f m away at the nearest)" % reached_door)
	check(door_max > .9, "The front door swings open (%.2f)" % door_max)
	check(boarded_hidden, "The learner is in the car when it drives off")
	check(left_x > 20.0, "The car drives off along the road to the east edge (x %.1f)" % left_x)
	check(away_seen and car_hidden_away, "The lesson is away with the car out of sight")
	check(returned_at_kerb < .01, "At the end of the lesson the car is back on the kerb spot (%.4f m)" % returned_at_kerb)
	check(exit_visible, "The learner gets out of the car")
	check(orphan_seen and orphan_max_x > 10.0, "The empty car drives away while the learner walks home (x %.1f)" % orphan_max_x)
	check(came_in, "The learner walks in through the front door and is indoors")
	check(not sim.is_away() and sim.action_queue.is_empty() and sim.driving.lesson_days == [41], "The lesson counts: lesson_days is [41]")
	check(app.driving_lesson.views.is_empty(), "The controller lets go")
	for frame: int in 400: app._process(DT)
	check(app.driving_lesson.orphans.is_empty() and LifeLessonCar.active == null, "The empty car is taken away once it has left")
	check(actor.visible and app.world.construction.floor_contains(Vector2(actor.position.x, actor.position.z), 0), "The learner is standing indoors at the end")
	check(float(sim.needs.fun) > 50.0 and sim.moodlets.any(func(m: Dictionary) -> bool: return str(m.label) == "Behind the wheel"), "They enjoyed it")
	# One lesson a day.
	var again: String = app.driving_lesson.request(kit)
	check(again.contains("one driving lesson a day"), "A second lesson the same day is refused: " + again)

func _refusals_and_the_bus() -> void:
	var kit: String = await fresh(36, 600.0)
	var sim: LifeSim = app.household.member_sim(kit)
	check(app.driving_lesson.request(kit).contains("Lessons start after school"), "A weekday morning is refused with the times")
	app.household.minutes = 1000.0
	for member: Dictionary in app.household.members: member.sim.minutes = 1000.0
	sim.queue_action("relax", "bookshelf", Vector3(0, .16, 0))
	check(not sim.action_queue.is_empty() and app.driving_lesson.request(kit).contains("Finish or cancel"), "A learner with something else planned is asked to finish it first")
	sim.cancel_action()
	var parent: String = str(app.household.members[0].id)
	var parent_sim: LifeSim = app.household.member_sim(parent)
	check(app.driving_lesson.request(parent) != "", "A licensed adult cannot take a lesson")
	# The school bus is on the lot: the car holds off the road until it has gone.
	# A bus of the test's own, so the app's clock does not send it on its way.
	var bus: LifeSchoolBus = LifeSchoolBus.new()
	bus.phase = "dropping"
	bus.position = LifeSchoolBus.CURB
	LifeSchoolBus.active = bus
	var asked: String = app.driving_lesson.request(kit)
	check(asked == "", "At 16:40 a lesson can be asked for (%s)" % asked)
	var held_frames: int = 0
	var car_visible_while_bus: bool = false
	for frame: int in 120:
		app._process(DT)
		var view: Dictionary = view_of(kit)
		if is_instance_valid(view.get("car")) and (view.car as Node3D).visible: car_visible_while_bus = true
		held_frames += 1
	check(not car_visible_while_bus and phase_of(sim) == "arrive" and float(sim.get_current_action().lesson.time) == 0.0, "While the bus is at the kerb the car waits out of sight and the lesson does not move on")
	check(app.driving_lesson.caption(sim.get_current_action()) == "Waiting for the instructor's car", "...and the caption says so")
	bus.phase = "gone"
	for frame: int in 40: app._process(DT)
	var view_after: Dictionary = view_of(kit)
	check(is_instance_valid(view_after.get("car")) and (view_after.car as Node3D).visible and float(sim.get_current_action().lesson.time) > 0.0, "Once the bus has gone the car comes in")
	# The way to the car is a real walk: blocking the front garden cancels the lesson with a notice.
	sim.cancel_action()
	for frame: int in 400: app._process(DT)

func _a_booking_starts_by_itself() -> void:
	# Sunday day 42, 09:55: a lesson booked for 10:00 starts with nobody asking.
	var kit: String = await fresh(42, 595.0, 1)
	var sim: LifeSim = app.household.member_sim(kit)
	check(bool(sim.book_driving_lesson(42, 600.0).ok), "A lesson is booked for Sunday at 10:00")
	var started_at: float = -1.0
	for frame: int in 800:
		app._process(DT)
		if str(sim.get_current_action().get("id", "")) == "driving_lesson":
			started_at = float(app.household.minutes)
			break
	check(started_at >= 600.0 and started_at < 602.0, "It starts at 10:00 without any call (%.1f)" % started_at)
	check(str(sim.get_current_action().get("phase", "")) == "approach", "...as the car is called to the kerb")
	# A learner who is busy with a duty or a ritual is not interrupted; one at leisure is.
	var busy: String = await fresh(42, 595.0, 1)
	var busy_sim: LifeSim = app.household.member_sim(busy)
	busy_sim.queue_action("relax", "bookshelf", Vector3(0, .16, 0))
	busy_sim.book_driving_lesson(42, 600.0)
	for frame: int in 400: app._process(DT)
	check(str(busy_sim.get_current_action().get("id", "")) == "driving_lesson", "A booking puts aside a pastime that was under way")
	var shower: String = await fresh(42, 595.0, 1)
	var shower_sim: LifeSim = app.household.member_sim(shower)
	shower_sim.needs.hygiene = 10.0
	var bathroom: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "shower": bathroom = item
	check(not bathroom.is_empty(), "(the home has a shower)")
	shower_sim.queue_action("shower", str(bathroom.get("id", "")), app.world.approach(bathroom))
	shower_sim.book_driving_lesson(42, 600.0)
	for frame: int in 200: app._process(DT)
	check(str(shower_sim.get_current_action().get("id", "")) != "driving_lesson", "A short need break (a shower) is left alone while the booking waits")

func _trips_and_the_planner() -> void:
	var kit: String = await fresh(41, 600.0)
	var sim: LifeSim = app.household.member_sim(kit)
	check(app.residents.driver_error([]) == "", "With no car of the household's own nobody needs a licence to ride the town's car")
	app.world.add_item({"id": "lesson_test_car", "kind": "car", "x": -12.0, "z": 3.0, "rotation": 0})
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	var parent: String = str(app.household.members[0].id)
	check(app.residents.driver_error([kit]).contains("driving licence") and app.residents.driver_error([parent]) == "" and app.residents.driver_error([]) == "" and app.residents.driver_error([kit, parent]) == "", "The household car needs a licensed driver in the party")
	check(not app.residents.begin_trip("park", [kit]) and app.mode == "live", "A trip with only the unlicensed teenager is refused")
	var street_before: int = (Planner.scene_from_world(app.world, "lesson_test_car").street as Array).size()
	var street_before_had_it: bool = false
	for rect: Rect2 in Planner.scene_from_world(app.world, "lesson_test_car").street:
		if rect.has_point(Vector2(Road.KERB_PARK_X, Road.KERB_PARK_Z)): street_before_had_it = true
	check(app.driving_lesson.request(kit) == "", "A lesson starts")
	for frame: int in 20: app._process(DT)
	check(app.driving_lesson.running() and not app.residents.begin_trip("park", [parent]) and app.mode == "live", "While the lesson runs, trips are refused")
	var parked: bool = false
	for frame: int in 3000:
		app._process(DT)
		var view: Dictionary = view_of(kit)
		if phase_of(sim) == "walk" and is_instance_valid(view.get("car")) and kerb_distance(view.car) < .01:
			parked = true
			break
	check(parked, "The car parks")
	var parked_scene: Dictionary = Planner.scene_from_world(app.world, "lesson_test_car")
	var found: bool = false
	for rect: Rect2 in parked_scene.street:
		if rect.has_point(Vector2(Road.KERB_PARK_X, Road.KERB_PARK_Z)) and rect.size.x > 3.0: found = true
	check(found and not street_before_had_it, "A parked lesson car is a street obstacle for the household's own car (%d rectangles before, %d now)" % [street_before, (parked_scene.street as Array).size()])
	check(LifeLessonCar.active != null and LifeLessonCar.active.visible, "The parked car is the one the planner knows")
	# House moves are refused while it is running.
	check(app.driving_lesson.running(), "The controller says a lesson is running")
	for frame: int in 6000:
		app._process(DT)
		if not app.driving_lesson.running(): break
	check(not app.driving_lesson.running() and LifeLessonCar.active == null, "When the lesson is over nothing is left on the kerb")

func _saves() -> void:
	var kit: String = await fresh(41, 600.0, 1, true)
	var sim: LifeSim = app.household.member_sim(kit)
	check(app.driving_lesson.request(kit) == "", "A lesson starts")
	var saved_car: Vector3 = Vector3.INF
	var saved_yaw: float = 0.0
	var saved_phase: String = ""
	for frame: int in 6000:
		app._process(DT)
		var view: Dictionary = view_of(kit)
		if phase_of(sim) == "depart" and float(sim.get_current_action().lesson.time) > 2.0 and is_instance_valid(view.get("car")):
			var car: Node3D = view.car
			saved_car = car.global_position
			saved_yaw = car.rotation.y
			saved_phase = "depart"
			var written: bool = app.save_game("", "Lesson departure")
			check(written, "A save in the middle of the drive off is written (%s)" % str(app.notice_text))
			var read: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
			check(read.ok, "...reads back and validates: " + str(read.get("error", "")))
			if read.ok:
				var prepared: Dictionary = app._prepare_loaded_world(read.data)
				check(prepared.ok, "...and reconstructs physically: " + str(prepared.get("error", "")))
				if prepared.ok:
					var candidate: Node = prepared.candidate
					candidate.household.set_speed(0)
					candidate._bind_member(kit)
					candidate.driving_lesson.tick(0.0)
					var reborn: Dictionary = candidate.driving_lesson.views.get(kit, {})
					check(not reborn.is_empty() and is_instance_valid(reborn.get("car")), "The loaded game rebuilds the lesson car")
					if not reborn.is_empty() and is_instance_valid(reborn.get("car")):
						var twin: Node3D = reborn.car
						var apart: float = Vector2(twin.global_position.x - saved_car.x, twin.global_position.z - saved_car.z).length()
						check(apart < .01 and gap(twin.rotation.y, saved_yaw) < deg_to_rad(.5), "It stands where it was saved, within a centimetre (%.4f m)" % apart)
					prepared.viewport.free(); candidate.free()
			break
	check(saved_phase == "depart", "A save was made during the drive off")
	# A save while away, and one on the way home, load too.
	var away_saved: bool = false
	var home_saved: bool = false
	app.household.set_speed(8)
	for frame: int in 20000:
		app._process(DT)
		if sim.is_away() and str(sim.away_state.phase) == "away" and not away_saved:
			away_saved = true
			var state: Dictionary = JSON.parse_string(JSON.stringify(sim._json_safe(sim.get_state())))
			var copy: LifeSim = LifeSim.new()
			check(bool(copy.restore_state(state).ok), "A save while the lesson is away loads (%s)" % str(copy.restore_state(state).get("error", "")))
			copy.free()
			var away_written: bool = app.save_game("", "Lesson away")
			check(away_written, "...and the household save is accepted (%s)" % str(app.notice_text))
			var away_read: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
			check(away_read.ok, "...and validates: " + str(away_read.get("error", "")))
			if away_read.ok:
				var away_prepared: Dictionary = app._prepare_loaded_world(away_read.data)
				check(away_prepared.ok, "...and reconstructs: " + str(away_prepared.get("error", "")))
				if away_prepared.ok:
					var away_candidate: Node = away_prepared.candidate
					check(away_candidate.household.member_sim(kit).is_away() and str(away_candidate.household.member_sim(kit).away_state.activity) == "driving_lesson", "The reloaded learner is still on their lesson")
					away_prepared.viewport.free(); away_candidate.free()
		if phase_of(sim) == "exit" and not home_saved and float(sim.get_current_action().lesson.time) > 1.0:
			home_saved = true
			var exit_written: bool = app.save_game("", "Lesson exit")
			check(exit_written, "A save while stepping out of the car is accepted (%s)" % str(app.notice_text))
			var exit_read: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
			check(exit_read.ok, "...and validates: " + str(exit_read.get("error", "")))
			if exit_read.ok:
				var exit_prepared: Dictionary = app._prepare_loaded_world(exit_read.data)
				check(exit_prepared.ok, "...and reconstructs: " + str(exit_prepared.get("error", "")))
				if exit_prepared.ok: exit_prepared.viewport.free(); exit_prepared.candidate.free()
		if not sim.is_away() and phase_of(sim).is_empty() and sim.action_queue.is_empty() and away_saved and home_saved: break
	check(away_saved and home_saved, "Saves were made while away and while getting out")

## Save in each phase of the lesson, load that save into the running game, and watch the lesson
## carry on to the end: the car is rebuilt, the learner is where they were, the lesson counts.
func _reload_in_every_phase() -> void:
	for target: String in ["walk", "board", "depart", "away", "return", "exit", "back"]:
		var kit: String = await fresh(41, 600.0, 3, true)
		var sim: LifeSim = app.household.member_sim(kit)
		check(app.driving_lesson.request(kit) == "", "[%s] a lesson starts" % target)
		var saved_slot: String = ""
		for frame: int in 30000:
			app._process(DT)
			var phase: String = phase_of(sim)
			if phase.is_empty() and sim.is_away(): phase = "away" if str(sim.away_state.phase) == "away" else "return"
			if sim.is_away() and str(sim.away_state.phase) == "away": app.household.set_speed(8)
			elif app.household.speed != 3: app.household.set_speed(3)
			var into: float = float(sim.get_current_action().get("lesson", {}).get("time", 0.0))
			var ready: bool = phase == target and (into > 1.0 or target in ["walk", "away", "return", "depart"] and into > .2 or target == "back" and into > .5)
			if target == "away": ready = phase == "away" and float(sim.away_state.get("ended_at", 0.0)) == 0.0 and float(sim.get_current_action().get("elapsed", 0.0)) > 30.0
			if ready:
				var written: bool = app.save_game("", "Lesson " + target)
				check(written, "[%s] saved (%s)" % [target, str(app.notice_text)])
				saved_slot = app.active_save_id
				break
		check(not saved_slot.is_empty(), "[%s] a save was made in that phase" % target)
		if saved_slot.is_empty(): continue
		app.load_game(saved_slot)
		for frame: int in 5: await process_frame
		app.household.set_speed(3)
		sim = app.household.member_sim(kit)
		var actor: LifeActor = app.world.actors[kit]
		check(sim != null and (not sim.action_queue.is_empty() or sim.is_away()), "[%s] the loaded game still has the lesson" % target)
		var finished: bool = false
		for frame: int in 30000:
			app._process(DT)
			sim = app.household.member_sim(kit)
			if sim.is_away() and str(sim.away_state.phase) == "away": app.household.set_speed(8)
			elif app.household.speed != 3: app.household.set_speed(3)
			if not sim.is_away() and sim.action_queue.is_empty() and not sim.driving.lesson_days.is_empty():
				finished = true
				break
		check(finished and sim.driving.lesson_days == [41], "[%s] the lesson finishes after the load and counts once (%s)" % [target, str(sim.driving.lesson_days)])
		actor = app.world.actors[kit]
		for frame: int in 300: app._process(DT)
		check(actor.visible and app.world.construction.floor_contains(Vector2(actor.position.x, actor.position.z), 0), "[%s] the learner ends indoors, visible" % target)
		check(app.driving_lesson.views.is_empty() and app.driving_lesson.orphans.is_empty(), "[%s] nothing is left on the kerb" % target)

func _cancel_while_waiting() -> void:
	var kit: String = await fresh(41, 600.0)
	var sim: LifeSim = app.household.member_sim(kit)
	check(app.driving_lesson.request(kit) == "", "A lesson starts")
	var cancelled: bool = false
	for frame: int in 3000:
		app._process(DT)
		if phase_of(sim) == "walk":
			sim.cancel_action()
			cancelled = true
			break
	check(cancelled and sim.action_queue.is_empty() and not sim.is_away(), "The lesson is called off while the learner walks out")
	for frame: int in 30: app._process(DT)
	check(app.driving_lesson.views.is_empty() and not app.driving_lesson.orphans.is_empty(), "The car is left to drive off by itself")
	for frame: int in 600: app._process(DT)
	check(app.driving_lesson.orphans.is_empty() and sim.driving.lesson_days.is_empty() and app.world.actors[kit].visible, "...and is taken away; no lesson counts; the learner is on their feet")
	check(app.driving_lesson.request(kit) == "", "A new lesson can be asked for straight away")

## A learner whose needs run out between the request and the car leaving is not driven off: the lesson
## is called off, nobody is away, and they are back on their feet at the kerb.
func _departure_refused() -> void:
	var kit: String = await fresh(41, 600.0)
	var sim: LifeSim = app.household.member_sim(kit)
	var actor: LifeActor = app.world.actors[kit]
	check(app.driving_lesson.request(kit) == "", "A lesson starts")
	var starved: bool = false
	for frame: int in 6000:
		app._process(DT)
		if not starved and phase_of(sim) == "depart" and float(sim.get_current_action().lesson.time) > 3.0:
			sim.needs.hunger = 3.0
			starved = true
		if starved and sim.action_queue.is_empty(): break
	check(starved and not sim.is_away() and sim.action_queue.is_empty() and sim.driving.lesson_days.is_empty(), "The lesson is called off when an urgent need appears before the car has left, with nobody away")
	for frame: int in 60: app._process(DT)
	var stand: Vector3 = Lesson.home() * Vector3(1.42, 0, -.092)
	check(actor.visible and app.driving_lesson.views.is_empty() and Vector2(actor.position.x - stand.x, actor.position.z - stand.z).length() < .5, "The learner is back on their feet beside the kerb (%.2f m from the car door)" % Vector2(actor.position.x - stand.x, actor.position.z - stand.z).length())
	check(app.driving_lesson.orphans.is_empty() and LifeLessonCar.active == null, "...and the car is gone")

## On a trip in the household's own car, the licensed grown-up is the one at the wheel (the front door),
## even when an unlicensed teenager comes first in the household.
func _driver_sits_in_front() -> void:
	var kit: String = await fresh(41, 600.0, 1, false, true)
	var parent: String = ""
	for member: Dictionary in app.household.members:
		if str(member.id) != kit: parent = str(member.id)
	check(str(app.household.members[0].id) == kit, "(the teenager is first in the household)")
	app.world.add_item({"id": "lesson_test_car", "kind": "car", "x": -12.0, "z": 3.0, "rotation": 0})
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(app.residents.begin_trip("park", []), "The household takes its own car on a trip")
	var steps: Array = app.residents.car_entry.steps
	check(not steps.is_empty() and str(steps[0].get("who", "")) == parent and str(steps[0].get("door", "")) == "front", "The licensed parent boards first, by the front door (%s)" % str(steps))
