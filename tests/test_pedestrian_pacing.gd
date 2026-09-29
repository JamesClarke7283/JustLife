extends SceneTree
## Pedestrians walk at a natural, distinct pace for their age, the same number of
## metres per real second whatever the game speed allows, with a gait clock that
## covers exactly the ground they move (no skating). Every life stage and a dog
## walk past on their own schedule. Headless, no main scene.

var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

## Metres actually moved per real second by one passer at a game speed, taken
## from the street simulation itself in 50 ms frames.
func measure(kind: String, game_speed: float) -> float:
	var street := LifeStreetLife.new()
	var passer: Dictionary = {}
	for entry: Dictionary in street.passers:
		if str(entry.kind) == kind and str(entry.get("follows", "")).is_empty():
			passer = entry
			break
	# Start mid-lane, heading east, already on its lane, so no turn or lane
	# shift is measured.
	passer["x"] = -6.0
	passer["dir"] = 1
	passer["lane"] = LifeStreetLife.lane_for(passer)
	var start: Vector3 = street.position_of(passer)
	var seconds: float = 0.0
	for _frame: int in range(60):
		street.tick(.05, game_speed)
		seconds += .05
	return start.distance_to(street.position_of(passer)) / seconds

func _run() -> void:
	# Pace table: natural, distinct per age, and never faster than a Lifelet.
	var child: float = LifePedestrianPace.metres_per_second("child")
	var teen: float = LifePedestrianPace.metres_per_second("teen")
	var adult: float = LifePedestrianPace.metres_per_second("adult")
	var elder: float = LifePedestrianPace.metres_per_second("elder")
	var dog: float = LifePedestrianPace.metres_per_second("dog")
	check(elder < child and child < adult and adult < teen, "Paces differ by age: elder %.2f < child %.2f < adult %.2f < teen %.2f m/s." % [elder, child, adult, teen])
	for kind: String in ["child", "teen", "adult", "elder", "dog"]:
		var pace: float = LifePedestrianPace.metres_per_second(kind)
		check(pace >= .6 and pace <= LifeTraversal.WALK_SPEED, "%s walks at a natural %.2f m/s, no faster than a Lifelet's %.1f." % [kind.capitalize(), pace, LifeTraversal.WALK_SPEED])
	check(adult == 1.1, "Adults keep the pace the neighbours have always strolled (%.2f m/s)." % adult)
	check(LifeStreetLife.new().passers.all(func(p: Dictionary) -> bool: return float(p.speed) < 1.5), "No passer runs the old 2.4 m/s treadmill.")

	# Measured ground speed equals the intended pace at every game speed, up to
	# the fastest gait clock; past it walkers stay at that clock rather than skate.
	for kind: String in ["child", "teen", "adult", "elder", "pet"]:
		var pace_kind: String = "dog" if kind == "pet" else kind
		var intended: float = LifePedestrianPace.metres_per_second(pace_kind)
		for game_speed: float in [1.0, 2.0, 3.0]:
			var measured: float = measure(kind, game_speed)
			check(absf(measured - intended * game_speed) < .01, "%s walks %.3f m/s at %dx (intended %.3f)." % [kind.capitalize(), measured, int(game_speed), intended * game_speed])
		var fast: float = measure(kind, 8.0)
		check(absf(fast - intended * LifePedestrianPace.FASTEST_CLOCK) < .01, "%s stays at the 3x gait ceiling (%.3f m/s) at 8x." % [kind.capitalize(), fast])
		check(measure(kind, 0.0) == 0.0, "%s stands still while paused." % kind.capitalize())

	# The gait clock keeps up: cycles per second times the body's stride is the
	# ground speed, at every speed, for every age and a dog.
	for stage: String in ["child", "teen", "adult", "elder"]:
		var actor := LifeActor.new()
		root.add_child(actor)
		actor.configure({"name": "Pace " + stage, "age_stage": stage, "low_detail": true})
		actor.voice_enabled = false
		for game_speed: float in [1.0, 3.0, 8.0]:
			var before: float = actor._time
			var frames: int = 120
			for _frame: int in range(frames):
				actor.animate(1.0 / 60.0, LifePedestrianPace.gait_factor(stage, game_speed), true, "")
			var cycles_per_second: float = (actor._time - before) / (float(frames) / 60.0) * 7.6 / TAU
			var ground: float = cycles_per_second * LifePedestrianPace.stride_length(stage)
			var expected: float = LifePedestrianPace.metres_per_second(stage) * LifePedestrianPace.clock_scale(game_speed)
			check(absf(ground - expected) < expected * .02, "%s feet cover %.3f m/s of ground at %dx, matching the %.3f m/s walked." % [stage.capitalize(), ground, int(game_speed), expected])
		actor.queue_free()
	var dog_actor := LifePetActor.new()
	root.add_child(dog_actor)
	dog_actor.configure("pace_dog", "dog", {}, "Pace", "female")
	for game_speed: float in [1.0, 3.0, 8.0]:
		var start_time: float = dog_actor._time
		for _frame: int in range(120):
			dog_actor.animate(1.0 / 60.0, true, LifePedestrianPace.gait_factor("dog", game_speed))
		var phase_rate: float = (dog_actor._time - start_time) / 2.0 * float(LifePetActor.SPECIES_LENGTH.dog) * 6.0
		var dog_ground: float = phase_rate / TAU * LifePedestrianPace.stride_length("dog")
		var dog_expected: float = LifePedestrianPace.metres_per_second("dog") * LifePedestrianPace.clock_scale(game_speed)
		check(absf(dog_ground - dog_expected) < dog_expected * .02, "A dog's legs cover %.3f m/s of ground at %dx, matching the %.3f m/s trotted." % [dog_ground, int(game_speed), dog_expected])
	dog_actor.queue_free()

	# Schedule: every life stage and a dog walk past over a day, and the lane is
	# empty in the small hours.
	var day := LifeStreetLife.new()
	var seen: Dictionary = {}
	var passes: Dictionary = {}
	var night_visible: int = 0
	var minute: float = 0.0
	while minute < 1440.0:
		day.tick(1.0, 1.0, minute)
		for passer: Dictionary in day.visible_passers():
			seen[str(passer.kind)] = true
			passes[str(passer.id)] = int(passer.passed_home)
		if minute >= 60.0 and minute < 300.0 and not day.visible_passers().is_empty():
			night_visible += 1
		minute += 1.0
	for kind: String in ["child", "teen", "adult", "elder", "pet"]:
		check(seen.has(kind), "A %s walks past on the schedule." % kind)
	check(night_visible == 0, "Nobody walks the lane between 01:00 and 05:00.")
	check(passes.size() == LifeStreetLife.ROSTER.size(), "Every passer, including the dog on a lead, appears in the day (%d of %d)." % [passes.size(), LifeStreetLife.ROSTER.size()])
	var adult_ids: Array = ["street_adult", "street_walker_dog"]
	for id: String in adult_ids:
		check(int(passes.get(id, 0)) >= 1, "%s passes the home on the morning and evening walk." % id)
	# The dog on a lead stays ahead of and beside its person.
	var lead := LifeStreetLife.new()
	for _step: int in range(200):
		lead.tick(.25, 1.0)
	var person: Dictionary = lead.find("street_adult")
	var pup: Dictionary = lead.find("street_walker_dog")
	check(absf(float(pup.x) - float(person.x) - float(person.dir) * LifeStreetLife.LEAD_LENGTH) < .001 and int(pup.dir) == int(person.dir), "The dog on a lead trots one lead-length ahead of its walker.")

	# Hold and release: a passer stops for a conversation and resumes at the
	# natural pace; an unrenewed hold expires on its own; a dog holds its person.
	var street := LifeStreetLife.new()
	var teen_passer: Dictionary = street.find("street_teen")
	teen_passer["x"] = -3.0
	teen_passer["dir"] = 1
	teen_passer["lane"] = LifeStreetLife.lane_for(teen_passer)
	check(street.hold("street_teen", "player"), "A passer can be held for a chat.")
	var held_at: Vector3 = street.position_of(teen_passer)
	for _step: int in range(8):
		street.tick(.25, 1.0)
	check(street.position_of(teen_passer) == held_at and street.is_held("street_teen"), "A held passer stands exactly still while the hold lasts.")
	for _step: int in range(8):
		street.tick(.25, 1.0)
	check(not street.is_held("street_teen") and street.position_of(teen_passer).distance_to(held_at) > .1, "An unrenewed hold expires and the passer walks on by themselves.")
	street.hold("street_teen", "player", 60.0)
	held_at = street.position_of(teen_passer)
	for _step: int in range(40):
		street.tick(.25, 3.0)
	check(street.position_of(teen_passer) == held_at, "A renewed hold keeps them in place at 3x as well.")
	street.release("street_teen")
	check(not street.is_held("street_teen"), "Release frees the passer at once.")
	var before_resume: Vector3 = street.position_of(teen_passer)
	for _step: int in range(20):
		street.tick(.2, 1.0)
	var resumed: float = before_resume.distance_to(street.position_of(teen_passer)) / 4.0
	check(absf(resumed - teen) < .02, "After a chat the teen resumes at the natural %.2f m/s (%.3f)." % [teen, resumed])
	street.hold("street_walker_dog", "player")
	check(street.is_held("street_adult") and street.is_held("street_walker_dog"), "Holding the dog holds its person and the reverse.")
	for _step: int in range(30):
		street.tick(1.0, 1.0)
	check(not street.is_held("street_adult") and not street.is_held("street_walker_dog"), "An unrenewed hold expires by itself after %d game minutes." % int(LifeStreetLife.HOLD_MINUTES))

	print("PEDESTRIAN_PACING %d checks, %d failures" % [checks, failures.size()])
	await process_frame
	quit(1 if not failures.is_empty() else 0)
