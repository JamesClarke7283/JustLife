extends "res://tests/test_school_day.gd"
## Learning to drive, one Lifelet at a time. A teenager is told lessons are open after
## 20 days (or on becoming a young adult), studies for an hour on seven different days,
## and then takes five 90-minute lessons inside a fourteen-day course; the fifth passes
## the test. Created and older Lifelets already hold a licence. The licence gates driving
## to work. The lesson absence, its early return, its saves and every corrupt save are
## covered here; the car and the walk are in test_driving_lesson_car.gd.
func targets() -> Array:
	var result: Array = super.targets()
	result.append({"id": "car", "kind": "car", "position": Vector3(9, .16, 3)})
	result.append({"id": "nook", "kind": "book_nook", "position": Vector3(1, .16, 4)})
	result.append({"id": "study", "kind": "study_desk", "position": Vector3(3, .16, 4)})
	result.append({"id": "computer", "kind": "computer", "position": Vector3(5, .16, 4)})
	result.append({"id": "office", "kind": "office_desk", "position": Vector3(7, .16, 4)})
	return result

func check(value: bool, detail: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", detail)
	if not value: failures.append(detail)

## A teenager whose birthday into the stage fell on `began`, now on `calendar_day`, with no
## automatic ageing so only the calendar moves.
func teen(began: int, calendar_day: int, clock: float = 480.0, lifespan: String = "normal") -> LifeSim:
	var sim: LifeSim = setup("teen", clock, calendar_day)
	sim.set_aging(lifespan, false)
	sim.autonomy = false
	sim.lifecycle.history = [{"from": "child", "to": "teen", "day": began}]
	sim.lifecycle["stage_day"] = began
	sim.driving = LifeDrivingSchool.fresh("teen")
	return sim

## A young adult or adult who grew up through the teen stage and never learned.
func unlicensed(stage: String = "young_adult", clock: float = 480.0, calendar_day: int = 40) -> LifeSim:
	var sim: LifeSim = setup(stage, clock, calendar_day)
	sim.set_aging("normal", false)
	sim.autonomy = false
	sim.driving = LifeDrivingSchool.fresh("teen")
	return sim

func listen(sim: LifeSim) -> Array:
	var heard: Array = []
	sim.milestone.connect(func(kind: String, data: Dictionary): heard.append({"kind": kind, "data": data}))
	return heard

func count(heard: Array, kind: String) -> int:
	return heard.filter(func(entry: Dictionary) -> bool: return str(entry.kind) == kind).size()

func notices(sim: LifeSim) -> Array:
	var heard: Array = []
	sim.notice.connect(func(text: String): heard.append(text))
	return heard

func said(heard: Array, fragment: String) -> bool:
	return heard.any(func(text: String) -> bool: return text.contains(fragment))

func run_to(sim: LifeSim, to_day: int, at_minutes: float = 0.5) -> void:
	var target: float = float(to_day - 1) * 1440.0 + at_minutes
	while float(sim.day - 1) * 1440.0 + sim.minutes < target - 0.0001:
		for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 100.0
		sim._step(minf(60.0, target - (float(sim.day - 1) * 1440.0 + sim.minutes)))

func loads(state: Dictionary) -> bool: return unlicensed().restore_state(state).ok

func menu_ids(sim: LifeSim, kind: String) -> Array:
	return sim.get_actions_for(kind, kind).map(func(entry: Dictionary) -> String: return str(entry.id))

## One hour of theory at a desk, on the day it is.
func study(sim: LifeSim, target: String = "study") -> bool:
	for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 100.0
	if not sim.queue_action("learn_to_drive", target, Vector3(3, .16, 4)): return false
	sim.begin_current_action()
	advance(sim, 61.0)
	return sim.action_queue.is_empty()

## Put a learner who has finished the theory on a given day and time.
func ready(began: int = 1, calendar_day: int = 30, clock: float = 1000.0) -> LifeSim:
	var sim: LifeSim = teen(began, calendar_day, clock)
	sim.driving["theory_days"] = 7
	sim.driving["last_theory_day"] = calendar_day - 1
	sim.driving["introduced_day"] = began + 20
	sim.driving["last_reminder_day"] = calendar_day - 1
	return sim

## Take one whole lesson, from queueing it to the car coming home, as the controller would.
func take_lesson(sim: LifeSim) -> bool:
	for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 100.0
	if not sim.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5)): return false
	if sim.begin_driving_lesson() != "": return false
	advance(sim, 91.0)
	if not sim.is_away() or str(sim.away_state.phase) != "returning": return false
	return sim.complete_away_return()

func run() -> void:
	_licence_from_the_start()
	_introduction()
	_menus()
	_theory()
	_gates()
	_lesson_absence()
	_early_return()
	_course_and_licence()
	_bookings_and_reminders()
	_saves()
	_ages_and_homework()
	check(observer_errors.is_empty(), "Every callback saw a serializable, committed state: " + str(observer_errors.slice(0, 3)))
	for sim: LifeSim in owned: sim.free()
	print("DRIVING_SCHOOL_SIM %d checks, %d failures; %d callback snapshots" % [checks, failures.size(), observer_count])
	quit(0 if failures.is_empty() else 1)

func _licence_from_the_start() -> void:
	for stage: String in ["young_adult", "adult", "elder"]:
		check(setup(stage).is_licensed(), "A new " + stage + " holds a licence")
	for stage: String in ["child", "teen"]:
		check(not setup(stage).is_licensed(), "A new " + stage + " does not")
	check(LifeSim.new().is_licensed(), "The default Lifelet is an adult and licensed")
	# A save from before licences loads an adult as licensed and a teenager as not.
	var adult: LifeSim = setup("adult")
	var state: Dictionary = snapshot(adult)
	state.erase("driving")
	var reborn: LifeSim = unlicensed("adult")
	check(reborn.restore_state(state).ok and reborn.is_licensed(), "An older adult save loads as licensed")
	var kid: LifeSim = teen(1, 30)
	state = snapshot(kid)
	state.erase("driving")
	var kid_back: LifeSim = adult
	check(kid_back.restore_state(state).ok and not kid_back.is_licensed(), "An older teenager save loads as unlicensed")

func _introduction() -> void:
	var sim: LifeSim = teen(5, 24, 400.0)
	observe(sim)
	var heard: Array = listen(sim)
	run_to(sim, 24, 1000.0)
	check(count(heard, "driving_introduced") == 0, "Day 24 is 19 days as a teenager: no notice")
	run_to(sim, 25, 400.0)
	check(count(heard, "driving_introduced") == 0 and int(sim.driving.introduced_day) == 0, "Day 25 before 07:00: not yet")
	run_to(sim, 25, 421.0)
	check(count(heard, "driving_introduced") == 1 and int(sim.driving.introduced_day) == 25, "At 07:00 on day 25 the lessons-open notice arrives once")
	var note: Dictionary = heard.filter(func(entry: Dictionary) -> bool: return entry.kind == "driving_introduced")[0].data
	check(str(note.name) == "School Lifelet" and str(note.text).contains("Learn to drive"), "It names the Lifelet and says where to learn: " + str(note.text))
	run_to(sim, 28, 900.0)
	check(count(heard, "driving_introduced") == 1, "...and never again")
	check(loads(snapshot(sim)), "The state after the notice loads")
	var copy: LifeSim = unlicensed()
	copy.restore_state(snapshot(sim))
	var copy_heard: Array = listen(copy)
	run_to(copy, 31, 900.0)
	check(count(copy_heard, "driving_introduced") == 0, "A reload does not tell them again")
	# Lifespan scales the twenty days: ten on a short life, eighty on a long one.
	var short: LifeSim = teen(5, 14, 400.0, "short")
	var short_heard: Array = listen(short)
	run_to(short, 14, 1000.0)
	check(count(short_heard, "driving_introduced") == 0, "A short life: day 14 is 9 days in")
	run_to(short, 15, 500.0)
	check(count(short_heard, "driving_introduced") == 1, "A short life opens after ten days")
	var long: LifeSim = teen(5, 84, 400.0, "long")
	var long_heard: Array = listen(long)
	run_to(long, 84, 1000.0)
	run_to(long, 85, 500.0)
	check(count(long_heard, "driving_introduced") == 1, "A long life opens after eighty days")
	# A teenager created part of the way through is dated from their progress, with aging off.
	var created: LifeSim = setup("teen", 400.0, 9)
	created.set_aging("normal", false)
	created.autonomy = false
	created.lifecycle.progress = 19.5 / 21.0
	created.lifecycle.erase("stage_day")
	var created_heard: Array = listen(created)
	run_to(created, 9, 1000.0)
	check(count(created_heard, "driving_introduced") == 0 and int(created.lifecycle.stage_day) > 0, "A teenager created at 19.5/21 gets no notice yet")
	created.lifecycle.progress = 20.0 / 21.0
	created.lifecycle["stage_day"] = created.day
	check(LifeLifecycle.days_in_stage(created.lifecycle, "teen", created.day) == 0, "(the day the stage began is today)")
	created.lifecycle.erase("stage_day")
	created.lifecycle.history = []
	run_to(created, 10, 500.0)
	check(count(created_heard, "driving_introduced") == 0, "(with a stage day recorded, progress no longer counts)")
	# A birthday into young adulthood introduces straight away, even on a short life.
	var grown: LifeSim = teen(5, 8, 600.0, "short")
	grown.set_aging("short", true)
	grown.lifecycle.progress = 0.99999
	var grown_heard: Array = listen(grown)
	grown.driving["introduced_day"] = 0
	advance(grown, 5.0)
	check(str(grown.character.age_stage) == "young_adult" and not grown.is_licensed() and count(grown_heard, "driving_introduced") == 1, "Becoming a young adult unlicensed opens lessons at once")
	check(count(grown_heard, "birthday") == 1 and grown_heard.map(func(e: Dictionary) -> String: return e.kind).find("birthday") < grown_heard.map(func(e: Dictionary) -> String: return e.kind).find("driving_introduced"), "...after the birthday banner")

func _menus() -> void:
	var open: LifeSim = teen(5, 26)
	for kind: String in ["bookshelf", "desk", "study_desk", "computer", "office_desk"]:
		var ids: Array = menu_ids(open, kind)
		check(ids.has("learn_to_drive") and not ids.has("book_driving_lesson"), "A teenager past 20 days sees Learn to drive at " + kind)
		for entry: Dictionary in open.get_actions_for(kind, kind):
			if str(entry.id) == "learn_to_drive": check(bool(entry.available) and int(entry.cost) == 0 and float(entry.duration) == 60.0, "...free, an hour, available at " + kind)
	check(not menu_ids(open, "book_nook").has("learn_to_drive"), "Not at the reading nook")
	var ids: Array = menu_ids(open, "desk")
	check(ids.has("homework") and ids.has("school") and ids.has("study"), "A pupil's desk menu keeps school and homework: " + str(ids))
	var young: LifeSim = teen(5, 20)
	check(not menu_ids(young, "bookshelf").has("learn_to_drive") and not menu_ids(young, "study_desk").has("learn_to_drive"), "A teenager with 15 days sees nothing")
	var wait: Dictionary = young.get_action_availability("learn_to_drive", "shelf")
	check(not bool(wait.available) and str(wait.reason).contains("20 days as a teenager"), "...and a direct request says why: " + str(wait.reason))
	check(not menu_ids(setup("child"), "bookshelf").has("learn_to_drive") and not menu_ids(setup("child"), "desk").has("learn_to_drive"), "A child sees nothing")
	check(not menu_ids(setup("adult"), "bookshelf").has("learn_to_drive") and not menu_ids(setup("adult"), "computer").has("learn_to_drive"), "A licensed adult sees nothing")
	for stage: String in ["young_adult", "adult", "elder"]:
		var late: LifeSim = unlicensed(stage)
		check(menu_ids(late, "bookshelf").has("learn_to_drive") and menu_ids(late, "office_desk").has("learn_to_drive"), "An unlicensed " + stage + " is offered the course")
	check(not menu_ids(open, "bed").has("learn_to_drive") and not menu_ids(open, "fridge").has("learn_to_drive"), "Nowhere else")
	var done: LifeSim = ready()
	check(menu_ids(done, "bookshelf").has("book_driving_lesson") and not menu_ids(done, "bookshelf").has("learn_to_drive"), "With the theory done the menu offers booking instead")
	check(not done.queue_action("book_driving_lesson", "shelf", Vector3.ZERO) and done.action_queue.is_empty(), "Booking opens a panel; it cannot be queued as an action")
	var licensed: LifeSim = setup("adult")
	check(not bool(licensed.get_action_availability("driving_lesson", "lot_exit").available), "A licensed Lifelet cannot take a lesson")

func _theory() -> void:
	var sim: LifeSim = teen(5, 30, 600.0)
	observe(sim)
	var says: Array = notices(sim)
	var heard: Array = listen(sim)
	for index: int in range(7):
		check(study(sim), "Day %d: an hour of theory completes" % sim.day)
		check(int(sim.driving.theory_days) == index + 1 and int(sim.driving.last_theory_day) == sim.day, "...and counts as study day %d" % (index + 1))
		if index == 0:
			check(said(says, "studied for the driving theory (1 of 7 days)"), "The first day is noted: " + str(says.back()))
			check(not sim.queue_action("learn_to_drive", "shelf", Vector3(2, .16, 0)) and said(says, "Come back tomorrow"), "A second session the same day is refused with a reason")
			check(int(sim.driving.theory_days) == 1, "...and does not count")
		if index < 6:
			run_to(sim, sim.day + 1, 600.0)
	check(LifeDrivingSchool.theory_done(sim.driving) and said(says, "finished the driving theory"), "Seven different days finish it, with a notice: " + str(says.back()))
	check(int(sim.driving.last_reminder_day) == sim.day, "The finishing notice counts as the first reminder")
	check(sim.get_action_availability("learn_to_drive", "shelf").reason.contains("Book a practical lesson"), "Studying more is refused: pointing at booking")
	check(count(heard, "driving_licensed") == 0, "No licence yet")
	check(loads(snapshot(sim)), "The finished theory loads")
	var skip: LifeSim = teen(5, 30, 600.0)
	check(study(skip), "A day of study")
	run_to(skip, 33, 600.0)
	check(study(skip) and int(skip.driving.theory_days) == 2, "Days need not follow one another")
	var pause: LifeSim = teen(5, 30, 600.0)
	check(pause.queue_action("learn_to_drive", "shelf", Vector3(2, .16, 0)), "Studying can be queued")
	pause.begin_current_action()
	advance(pause, 30.0)
	check(int(pause.driving.theory_days) == 0, "Half an hour of study counts for nothing yet")
	pause.cancel_action()
	check(int(pause.driving.theory_days) == 0 and pause.action_queue.is_empty(), "A cancelled session counts for nothing")

func _gates() -> void:
	var sim: LifeSim = unlicensed("young_adult", 540.0, 40)
	sim.career.schedule = LifeCareerSchedule.fresh(40)
	var drive: Dictionary = sim.get_action_availability("drive_to_work", "car")
	check(not bool(drive.available) and str(drive.reason).contains("driving licence"), "An aged-up young adult cannot drive to work: " + str(drive.reason))
	check(not sim.queue_action("drive_to_work", "car", Vector3(9, .16, 3)), "...and the action is refused")
	check(str(sim._commute_choice("career_day", []).get("id", "")) != "drive_to_work", "Autonomy does not send them to the car")
	var licensed: LifeSim = setup("adult", 540.0, 40)
	licensed.career.schedule = LifeCareerSchedule.fresh(40)
	check(str(licensed.get_action_availability("drive_to_work", "car").reason).is_empty(), "A grandfathered adult may drive to work")
	check(str(licensed._commute_choice("career_day", []).get("id", "")) == "drive_to_work", "...and autonomy sends them")
	var passed: LifeSim = unlicensed("adult", 540.0, 40)
	passed.career.schedule = LifeCareerSchedule.fresh(40)
	passed.driving["licensed"] = true
	check(str(passed.get_action_availability("drive_to_work", "car").reason).is_empty(), "A Lifelet who passes the test may drive to work")
	# The wording of the refusal is plain.
	check(str(drive.reason).begins_with("School") and str(drive.reason).contains("Walk to work"), "The reason names who and offers the walk: " + str(drive.reason))

func _lesson_absence() -> void:
	# Day 6 is a Saturday.
	var sim: LifeSim = ready(1, 36, 1000.0)
	observe(sim)
	var says: Array = notices(sim)
	var heard: Array = listen(sim)
	check(not bool(ready(1, 31, 600.0).get_action_availability("driving_lesson", "lot_exit").available), "Day 31 is a Wednesday: not at 10:00")
	check(bool(ready(1, 31, 1000.0).get_action_availability("driving_lesson", "lot_exit").available), "...but at 16:40")
	check(not sim.queue_action("driving_lesson", "shelf", Vector3.ZERO), "A lesson needs the neighborhood exit")
	check(sim.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5)), "Day 36 is a Monday: after school it queues")
	check(sim.get_current_action().id == "driving_lesson" and sim.get_current_action().phase == "approach" and not sim.is_away(), "Queued, the lesson is an approach at home: the controller owns the walk")
	sim.begin_current_action()
	check(not sim.is_away() and sim.get_current_action().phase == "approach", "begin_current_action does not start it; the car does")
	advance(sim, 20.0)
	check(not sim.is_away() and int(sim.driving.theory_days) == 7, "Waiting for the car costs nothing and credits nothing")
	var left_at: float = sim.minutes
	check(sim.begin_driving_lesson() == "" and sim.is_away(), "When the car has left the lesson begins")
	var away: Dictionary = sim.away_state
	check(away.activity == "driving_lesson" and away.phase == "away" and int(away.lesson) == 1 and float(away.return_minutes) == left_at + 90.0 and int(away.return_day) == sim.day, "An absence of 90 minutes, lesson 1")
	check(sim.get_current_action().phase == "active" and bool(sim.get_current_action().paid), "The lesson is the active front action")
	check(said(says, "driving lesson") and count(heard, "driving_licensed") == 0, "A notice says it has begun")
	check(not bool(sim.get_action_availability("driving_lesson", "lot_exit").available), "Nobody can start a second lesson while away")
	var needs_before: float = float(sim.needs.fun)
	advance(sim, 45.0)
	check(is_equal_approx(float(sim.get_current_action().elapsed), 45.0) and float(sim.needs.fun) > needs_before - 1.0, "Time and effects accrue while away")
	check(loads(snapshot(sim)), "A save in the middle of the lesson loads")
	var copy: LifeSim = unlicensed()
	check(copy.restore_state(snapshot(sim)).ok and copy.is_away() and str(copy.away_state.activity) == "driving_lesson" and is_equal_approx(float(copy.away_state.return_minutes), left_at + 90.0), "...and restores the absence")
	check(not sim.driving.lesson_days.has(36), "Nothing is credited until it ends")
	advance(sim, 44.0)
	check(str(sim.away_state.phase) == "away", "Still away at 89 minutes")
	advance(sim, 1.5)
	check(str(sim.away_state.phase) == "returning" and bool(sim.away_state.completed) and sim.driving.lesson_days == [36], "At 90 minutes the lesson counts and they head home")
	check(said(says, "lesson 1 of 5") and say_count(says, "lesson 1 of 5") == 1, "One notice for the lesson: " + str(says.back()))
	check(sim.moodlets.any(func(m: Dictionary) -> bool: return str(m.label) == "Behind the wheel"), "A good lesson lifts the mood")
	check(loads(snapshot(sim)), "A save on the way home loads")
	check(sim.complete_away_return() and not sim.is_away() and sim.action_queue.is_empty(), "Arriving home ends the absence and the action")
	check(not bool(sim.get_action_availability("driving_lesson", "lot_exit").available) and str(sim.get_action_availability("driving_lesson", "lot_exit").reason).contains("one driving lesson a day"), "Only one lesson a day")
	check(sim.character.outfit_category == "everyday", "They wear everyday clothes after the lesson")
	# A hungry learner is told to eat first.
	var hungry: LifeSim = ready(1, 36, 1000.0)
	hungry.needs.hunger = 5.0
	check(str(hungry.get_action_availability("driving_lesson", "lot_exit").reason).contains("urgent needs"), "Urgent needs come first")

func say_count(heard: Array, fragment: String) -> int:
	return heard.filter(func(text: String) -> bool: return text.contains(fragment)).size()

func _early_return() -> void:
	var sim: LifeSim = ready(1, 36, 1000.0)
	var says: Array = notices(sim)
	check(sim.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5)) and sim.begin_driving_lesson() == "", "A lesson begins")
	advance(sim, 30.0)
	sim.cancel_action()
	check(str(sim.away_state.phase) == "returning" and not bool(sim.away_state.completed) and said(says, "coming back from the driving lesson early"), "Calling it off brings them home early, saying it will not count")
	check(loads(snapshot(sim)), "The early return loads")
	check(sim.complete_away_return() and sim.driving.lesson_days.is_empty(), "Nothing is credited")
	check(bool(sim.get_action_availability("driving_lesson", "lot_exit").available), "A new lesson may be taken the same day")
	# A birthday does not cut a lesson short and does not end it.
	var grower: LifeSim = ready(1, 36, 1000.0)
	grower.set_aging("normal", true)
	grower.lifecycle.progress = 0.99999
	grower.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	grower.begin_driving_lesson()
	advance(grower, 5.0)
	check(str(grower.character.age_stage) == "young_adult" and str(grower.away_state.phase) == "away" and str(grower.away_state.activity) == "driving_lesson", "A birthday into young adulthood leaves the lesson running")
	check(loads(snapshot(grower)), "...and the save still loads")
	advance(grower, 90.0)
	check(grower.driving.lesson_days == [36], "...and it counts")
	# A birthday while only the lesson's walk is under way still starts no absence.
	var walker: LifeSim = ready(1, 36, 1000.0)
	walker.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	walker.cancel_action()
	check(not walker.is_away() and walker.action_queue.is_empty(), "Cancelling during the walk out simply ends it")
	# The window closing on the way does not turn a lesson that has left back.
	var late: LifeSim = ready(1, 36, 1169.0)
	late.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	late.minutes = 1195.0
	check(late.begin_driving_lesson() == "" and late.is_away(), "A lesson requested in the window may leave after it")

func _course_and_licence() -> void:
	var sim: LifeSim = ready(1, 36, 1000.0)
	observe(sim)
	var heard: Array = listen(sim)
	var says: Array = notices(sim)
	for index: int in range(5):
		check(take_lesson(sim), "Lesson %d is taken on day %d" % [index + 1, sim.day])
		check(sim.driving.lesson_days.size() == index + 1, "...%d done" % (index + 1))
		if index < 4:
			check(count(heard, "driving_licensed") == 0 and not sim.is_licensed(), "Not licensed after lesson %d" % (index + 1))
			run_to(sim, sim.day + 1, 1000.0)
	check(sim.is_licensed() and int(sim.driving.licensed_day) == sim.day and count(heard, "driving_licensed") == 1, "The fifth lesson passes the test, with the milestone")
	check(sim.driving_status() == "Driving licence held" and setup("adult").driving_status() == "" and ready(1, 36, 600.0).driving_status() == "Learner driver · lessons 0 of 5", "The age tooltip line follows the licence")
	check(said(says, "passed the driving test"), "...and a notice: " + str(says.back()))
	var licence: Dictionary = heard.filter(func(entry: Dictionary) -> bool: return entry.kind == "driving_licensed")[0].data
	check(str(licence.name) == "School Lifelet" and str(licence.text).contains("passed the driving test"), "The milestone names them: " + str(licence.text))
	check(sim.memories.any(func(m: Dictionary) -> bool: return str(m.label) == "Passed the driving test"), "It is remembered")
	check(loads(snapshot(sim)), "The licence loads")
	check(not bool(sim.get_action_availability("driving_lesson", "lot_exit").available) and not menu_ids(sim, "bookshelf").has("book_driving_lesson"), "Nothing more to book")
	var after_pass: int = says.size()
	run_to(sim, sim.day + 3, 1000.0)
	check(not said(says.slice(after_pass), "could have a driving lesson"), "No reminders once licensed")
	# The course lapses after 14 days with fewer than 5 lessons.
	var slow: LifeSim = ready(1, 36, 1000.0)
	var slow_says: Array = notices(slow)
	check(take_lesson(slow) and take_lesson(slow) == false, "Two lessons on one day are refused")
	run_to(slow, 38, 1000.0)
	check(take_lesson(slow) and slow.driving.lesson_days == [36, 38], "A second lesson two days later")
	run_to(slow, 49, 1000.0)
	check(slow.driving.lesson_days == [36, 38] and int(slow.driving.theory_days) == 7, "On day 49 (the 14th day of the course) it is still open")
	run_to(slow, 50, 100.0)
	check(slow.driving.lesson_days.is_empty() and int(slow.driving.theory_days) == 7 and not slow.is_licensed(), "On day 50 it has lapsed: lessons cleared, theory kept")
	check(said(slow_says, "course ran out with 2 of 5 lessons") and said(slow_says, "theory still counts"), "...with a notice: " + str(slow_says.filter(func(t: String) -> bool: return t.contains("ran out"))))
	check(loads(snapshot(slow)), "A lapsed course loads")
	run_to(slow, 53, 1000.0)
	check(take_lesson(slow) and slow.driving.lesson_days == [53], "A fresh course starts with the next lesson")
	# Five lessons need five different days.
	var quick: LifeSim = ready(1, 36, 1000.0)
	for day: int in [36, 37, 38, 39]:
		run_to(quick, day, 1000.0)
		check(take_lesson(quick), "Day %d lesson" % day)
	check(not quick.is_licensed(), "Four lessons are not enough")

func _bookings_and_reminders() -> void:
	# Monday day 36. Book the after-school slot, Saturday and Sunday.
	var sim: LifeSim = ready(1, 36, 600.0)
	var says: Array = notices(sim)
	var options: Array = sim.driving_summary().options
	check(options.size() == 3 and int(options[0].day) == 36 and float(options[0].minutes) == 960.0, "From Monday morning: this afternoon, Saturday and Sunday")
	check(bool(sim.book_driving_lesson(36, 960.0).ok) and LifeDrivingSchool.has_booking(sim.driving), "A booking is held")
	check(said(says, "booked for today at 16:00"), "...with a notice: " + str(says.back()))
	check(not sim.driving_booking_due() and sim.driving_booking_soon(400.0) and not sim.driving_booking_soon(45.0), "It is not due at 10:00")
	check(not bool(sim.book_driving_lesson(36, 600.0).ok) and not bool(sim.book_driving_lesson(30, 960.0).ok) and not bool(sim.book_driving_lesson(50, 960.0).ok), "A morning slot on a school day, a past day and a day too far ahead are refused")
	check(bool(sim.book_driving_lesson(41, 600.0).ok) and int(sim.driving.booking.day) == 41, "Booking again replaces it (Saturday day 41)")
	check(sim.cancel_driving_booking() and not LifeDrivingSchool.has_booking(sim.driving) and not sim.cancel_driving_booking(), "A booking can be cancelled")
	sim.book_driving_lesson(36, 960.0)
	run_to(sim, 36, 959.0)
	check(not sim.driving_booking_due(), "At 15:59 it is not due")
	run_to(sim, 36, 961.0)
	check(sim.driving_booking_due(), "From 16:00 it is due")
	run_to(sim, 36, 991.0)
	check(not sim.driving_booking_due() and not LifeDrivingSchool.has_booking(sim.driving) and said(says, "missed the booked driving lesson"), "After half an hour's grace it is given up with a notice: " + str(says.back()))
	check(loads(snapshot(sim)), "The cleared booking loads")
	# A booking that is used up by the lesson, and one that survives a save.
	var kept: LifeSim = ready(1, 36, 600.0)
	kept.book_driving_lesson(36, 960.0)
	check(loads(snapshot(kept)), "A booked lesson loads")
	var again: LifeSim = unlicensed()
	again.restore_state(snapshot(kept))
	check(LifeDrivingSchool.has_booking(again.driving) and int(again.driving.booking.day) == 36, "...and is restored")
	run_to(kept, 36, 970.0)
	kept.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	kept.begin_driving_lesson()
	check(not LifeDrivingSchool.has_booking(kept.driving), "A lesson that has left uses the booking up, so calling it off cannot bring it round again")
	# Reminders: the theory is finished on Wednesday day 38 (that notice counts as the first reminder).
	var reminded: LifeSim = teen(1, 36, 600.0)
	var reminders: Array = notices(reminded)
	reminded.driving["theory_days"] = 6
	reminded.driving["last_theory_day"] = 35
	reminded.driving["introduced_day"] = 21
	run_to(reminded, 38, 600.0)
	check(study(reminded) and LifeDrivingSchool.theory_done(reminded.driving), "The seventh day of theory is done on day 38")
	var base: int = reminders.size()
	run_to(reminded, 39, 1000.0)
	run_to(reminded, 40, 1000.0)
	check(not said(reminders.slice(base), "could have a driving lesson"), "No reminder on the next two days, even after 16:00")
	run_to(reminded, 41, 569.0)
	check(not said(reminders.slice(base), "could have a driving lesson"), "Day 41 (a Saturday) at 09:29: not yet")
	run_to(reminded, 41, 571.0)
	check(say_count(reminders.slice(base), "could have a driving lesson after school, or on Saturday or Sunday (0 of 5 lessons)") == 1, "Three days on, at the weekend, the reminder comes at 09:30: " + str(reminders.back()))
	run_to(reminded, 42, 1000.0)
	check(say_count(reminders.slice(base), "could have a driving lesson") == 1, "Not again the next day")
	run_to(reminded, 44, 959.0)
	check(say_count(reminders.slice(base), "could have a driving lesson") == 1, "Day 44 (a Tuesday) at 15:59: not yet")
	run_to(reminded, 44, 961.0)
	check(say_count(reminders.slice(base), "could have a driving lesson") == 2, "On a school day it is 16:00")
	# A booking holds reminders back, and so does being away.
	var quiet: LifeSim = ready(1, 36, 600.0)
	var quiet_says: Array = notices(quiet)
	quiet.driving["last_reminder_day"] = 30
	quiet.book_driving_lesson(41, 600.0)
	run_to(quiet, 36, 1000.0)
	check(not said(quiet_says, "could have a driving lesson"), "No reminder while a lesson is booked")
	var control: LifeSim = ready(1, 36, 600.0)
	var control_says: Array = notices(control)
	control.driving["last_reminder_day"] = 30
	run_to(control, 36, 1000.0)
	check(said(control_says, "could have a driving lesson"), "(control: without a booking the same Lifelet is reminded)")
	var away_quiet: LifeSim = ready(1, 41, 550.0)
	var away_says: Array = notices(away_quiet)
	away_quiet.driving["last_reminder_day"] = 30
	away_quiet.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	away_quiet.begin_driving_lesson()
	run_to(away_quiet, 41, 600.0)
	check(away_quiet.is_away() and not said(away_says, "could have a driving lesson"), "No reminder while away on a lesson (Saturday 09:30)")
	run_to(away_quiet, 41, 1000.0)
	check(not said(away_says, "could have a driving lesson"), "...and none the day a lesson was taken")

func _saves() -> void:
	var good: Dictionary = snapshot(ready(1, 36, 1000.0))
	check(loads(good), "A learner's save loads")
	var sim: LifeSim = ready(1, 36, 1000.0)
	sim.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	sim.begin_driving_lesson()
	advance(sim, 10.0)
	var mid: Dictionary = snapshot(sim)
	mid.action_queue[0]["lesson"] = {"phase": "away", "time": 0.0, "leg": 0}
	check(loads(mid), "A lesson in progress with its choreography record loads")
	var broken: Dictionary
	broken = mid.duplicate(true); broken.away_state.return_minutes = float(broken.away_state.return_minutes) + 5.0
	check(not loads(broken), "A lesson that is not 90 minutes long is refused")
	broken = mid.duplicate(true); broken.away_state.erase("lesson")
	check(not loads(broken), "A lesson absence without its number is refused")
	broken = mid.duplicate(true); broken.driving.lesson_days = [36]
	check(not loads(broken), "A lesson already credited before it ended is refused")
	broken = mid.duplicate(true); broken.away_state.phase = "returning"; broken.away_state.completed = true; broken.away_state.ended_at = float(broken.away_state.departure_day - 1) * 1440.0 + float(broken.away_state.return_minutes)
	check(not loads(broken), "A completed lesson missing from the licence record is refused")
	broken = mid.duplicate(true); broken.action_queue.clear()
	check(not loads(broken), "A lesson absence without its action is refused")
	broken = mid.duplicate(true); broken.action_queue[0].lesson = {"phase": "walk", "time": 1.0, "leg": 0}
	check(not loads(broken), "A walking record on an absent lesson is refused")
	broken = mid.duplicate(true); broken.away_state.activity = "career"
	check(not loads(broken), "An absence that is not a lesson cannot carry one")
	broken = mid.duplicate(true); broken.away_state.exit_position = [999999.0, 0.0, 0.0]
	check(not loads(broken), "An impossible return position is refused")
	broken = mid.duplicate(true); broken.away_state.departure_minutes = 100.0; broken.away_state.return_minutes = 190.0
	check(not loads(broken), "A lesson whose times disagree with the action that carries it is refused")
	broken = mid.duplicate(true); broken.action_queue[0].elapsed = 80.0
	check(not loads(broken), "Impossible progress is refused")
	broken = mid.duplicate(true); broken.driving.theory_days = 6
	check(not loads(broken), "A lesson without the theory is refused")
	broken = mid.duplicate(true); broken.driving.licensed = true; broken.driving.licensed_day = 36; broken.driving.lesson_days = [31, 32, 33, 34, 36]
	check(not loads(broken), "A licence earned by a lesson still in progress is refused")
	# Before the car leaves: the walk out is saved on the action.
	var walking: LifeSim = ready(1, 36, 1000.0)
	walking.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	walking.get_current_action()["lesson"] = {"phase": "walk", "time": 2.0, "leg": 0, "walk_to": [0.0, .16, 8.0], "destination": [0.0, .16, 8.0]}
	var walk_state: Dictionary = snapshot(walking)
	check(loads(walk_state), "A save during the walk out loads")
	broken = walk_state.duplicate(true); broken.driving.theory_days = 3; broken.driving.last_theory_day = 30; broken.driving.lesson_days = []
	check(not loads(broken), "A queued lesson with the theory unfinished is refused")
	broken = walk_state.duplicate(true); broken.action_queue[0].lesson.phase = "away"
	check(not loads(broken), "An away phase with no absence is refused")
	broken = walk_state.duplicate(true); broken.action_queue[0].lesson.phase = "fly"
	check(not loads(broken), "An unknown phase is refused")
	broken = walk_state.duplicate(true); broken.action_queue[0].lesson["walk_to"] = [NAN, 0.0, 0.0]
	check(not loads(broken), "A walk to nowhere is refused")
	broken = walk_state.duplicate(true); broken.action_queue[0].lesson["back_route"] = [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]
	check(not loads(broken), "A long walk home is refused")
	broken = walk_state.duplicate(true); broken.action_queue[0].lesson.time = 9999.0; broken.action_queue[0].lesson.phase = "board"
	check(not loads(broken), "Boarding that lasts forever is refused")
	broken = walk_state.duplicate(true); broken.action_queue[0].erase("lesson")
	check(loads(broken), "A queued lesson with no record yet loads (the controller makes one)")
	broken = walk_state.duplicate(true); broken.action_queue[0].id = "study"
	check(not loads(broken), "A lesson record on another action is refused")
	broken = walk_state.duplicate(true); broken.driving.licensed = true; broken.driving.lesson_days = [31, 32, 33, 34, 35]; broken.driving.licensed_day = 35
	check(not loads(broken), "A queued lesson for someone already licensed is refused")
	broken = good.duplicate(true); broken.driving.theory_days = 9
	check(not loads(broken), "Corrupt driving records are refused when a Lifelet loads")
	broken = good.duplicate(true); broken.driving = {"version": 1}
	check(not loads(broken), "...and so is a half-empty one")

func _ages_and_homework() -> void:
	# Change Age on the farewell dialog starts the licence afresh: held by a young adult or older.
	var elder: LifeSim = setup("elder")
	elder.pending_passing_cause = "old_age"
	check(elder.is_licensed() and elder.cancel_pending_passing("teen") and not elder.is_licensed() and str(elder.character.age_stage) == "teen", "An elder changed back to a teenager must learn again")
	check(loads(snapshot(elder)), "...and the save loads")
	var back: LifeSim = setup("elder")
	back.pending_passing_cause = "old_age"
	back.cancel_pending_passing("adult")
	check(back.is_licensed() and loads(snapshot(back)), "An elder changed to an adult keeps their licence")
	var kid: LifeSim = teen(1, 40)
	kid.pending_passing_cause = "hunger"
	kid.driving["theory_days"] = 3
	kid.driving["last_theory_day"] = 38
	kid.cancel_pending_passing("child")
	check(not kid.is_licensed() and int(kid.driving.theory_days) == 0 and loads(snapshot(kid)), "Changing to a child starts the course over and still loads")
	# Required teenage homework gives way to a lesson, queued or booked within 45 minutes.
	var pupil: LifeSim = homework_due(1210.0)
	check(pupil.homework_mandatory(), "(a teenager with homework due at 20:10)")
	pupil.queue_action("relax", "desk", Vector3(0, .16, 0))
	pupil._enforce_mandatory_homework()
	check(pupil.action_queue.size() >= 1 and str(pupil.action_queue[0].id) == "homework", "Control: with no lesson near, the curfew puts homework first")
	var lesson_first: LifeSim = homework_due(1210.0)
	lesson_first.queue_action("relax", "desk", Vector3(0, .16, 0))
	lesson_first.driving["booking"] = {"day": 36, "minutes": 1230.0}
	lesson_first._enforce_mandatory_homework()
	check(str(lesson_first.action_queue[0].id) == "relax", "A lesson booked within 45 minutes keeps the curfew from taking over")
	var late_booking: LifeSim = homework_due(1210.0)
	late_booking.queue_action("relax", "desk", Vector3(0, .16, 0))
	late_booking.driving["booking"] = {"day": 37, "minutes": 960.0}
	late_booking._enforce_mandatory_homework()
	check(str(late_booking.action_queue[0].id) == "homework", "A lesson tomorrow does not")
	var queued_lesson: LifeSim = homework_due(1100.0)
	queued_lesson.queue_action("relax", "desk", Vector3(0, .16, 0))
	queued_lesson.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	queued_lesson.minutes = 1210.0
	queued_lesson._enforce_mandatory_homework()
	check(str(queued_lesson.action_queue[0].id) == "relax" and queued_lesson.action_queue.size() == 2, "A lesson in the queue is never put behind homework")
	var on_its_way: LifeSim = homework_due(1100.0)
	on_its_way.queue_action("driving_lesson", "lot_exit", Vector3(0, .16, 8.5))
	on_its_way.minutes = 1210.0
	on_its_way._enforce_mandatory_homework()
	check(str(on_its_way.action_queue[0].id) == "driving_lesson", "...nor is one already on its way")

## A learner with the theory done, who went to school on day 36 and has homework due at the given time.
func homework_due(clock: float) -> LifeSim:
	var sim: LifeSim = ready(1, 36, clock)
	sim.autonomy = true
	var state: Dictionary = LifeEducation.fresh("teen", 36)
	var done: Dictionary = LifeEducation.complete(state, "teen", 36, 500.0, "school")
	sim.education = done.state if bool(done.ok) else state
	sim.driving["booking"] = {}
	return sim
