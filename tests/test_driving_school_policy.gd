extends SceneTree
## The driving school's rules on their own: no app, no sim. Who holds a licence from
## the start, when lessons open (20 days as a teenager, scaled by the lifespan, or on
## becoming a young adult), the seven theory days, the five lessons inside a
## fourteen-day course and what happens when the days run out, the lesson windows and
## the bookable slots, reminders every three days, and the validation of a saved record.
const School = preload("res://scripts/driving_school.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, detail: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", detail)
	if not value: failures.append(detail)

## A teenager's lifecycle record: the birthday that made them a teen fell on `began`.
func teen_life(began: int, lifespan: String = "normal") -> Dictionary:
	return {"progress": 0.2, "lifespan": lifespan, "auto_age": true, "history": [{"from": "child", "to": "teen", "day": began}], "stage_day": began}

func adult_life() -> Dictionary:
	return {"progress": 0.2, "lifespan": "normal", "auto_age": true, "history": [], "stage_day": 1}

## A teenager's record with the theory done and the given lessons taken.
func learner(theory: int = 7, taken: Array = []) -> Dictionary:
	var record: Dictionary = School.fresh("teen")
	record["theory_days"] = theory
	record["last_theory_day"] = 0 if theory == 0 else 2
	record["lesson_days"] = taken
	return record

func run() -> void:
	_licence_from_the_start()
	_when_lessons_open()
	_theory()
	_windows_and_slots()
	_lessons_and_course()
	_events()
	_validation()
	_migration()
	print("DRIVING_SCHOOL_POLICY %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _licence_from_the_start() -> void:
	for stage: String in ["young_adult", "adult", "elder"]:
		var record: Dictionary = School.fresh(stage)
		check(School.is_licensed(record) and int(record.licensed_day) == 0 and School.lessons(record) == 0, stage + " starts life with a licence")
	for stage: String in ["baby", "child", "teen"]:
		check(not School.is_licensed(School.fresh(stage)), stage + " starts without one")
	check(School.validate(School.fresh("adult"), 5) == "" and School.validate(School.fresh("teen"), 1) == "", "Fresh records are valid")

func _when_lessons_open() -> void:
	check(School.needed_days("normal") == 20 and School.needed_days("short") == 10 and School.needed_days("long") == 80, "Twenty days as a teenager at the normal pace, ten on a short life, eighty on a long one")
	var record: Dictionary = School.fresh("teen")
	# The birthday that made them a teenager fell on day 5: day 24 is 19 days in, day 25 is 20.
	check(not School.eligible(record, "teen", teen_life(5), 24) and School.eligible(record, "teen", teen_life(5), 25), "Day 24 is 19 days as a teenager and day 25 is 20")
	check(School.days_until_open("teen", teen_life(5), 24) == 1 and School.days_until_open("teen", teen_life(5), 5) == 20 and School.days_until_open("teen", teen_life(5), 40) == 0, "The countdown reads 1, 20 and 0")
	check(not School.eligible(record, "teen", teen_life(5, "short"), 14) and School.eligible(record, "teen", teen_life(5, "short"), 15), "A short life needs ten days")
	check(not School.eligible(record, "teen", teen_life(5, "long"), 84) and School.eligible(record, "teen", teen_life(5, "long"), 85), "A long life needs eighty")
	# A Lifelet created as a teenager part of the way in is dated from how far in they began.
	var created: Dictionary = {"progress": 19.0 / 21.0, "lifespan": "normal", "auto_age": false, "history": []}
	check(LifeLifecycle.days_in_stage(created, "teen", 9) == 19, "A teen created 19/21 of the way in has been one for 19 days")
	check(not School.eligible(record, "teen", created, 9) and School.eligible(record, "teen", {"progress": 20.0 / 21.0, "lifespan": "normal", "auto_age": false, "history": []}, 9), "...so 20/21 is exactly when lessons open")
	check(not School.eligible(record, "child", adult_life(), 99) and not School.eligible(record, "baby", adult_life(), 99), "Children are too young")
	var unlicensed: Dictionary = School.fresh("teen")
	for stage: String in ["young_adult", "adult", "elder"]:
		check(School.eligible(unlicensed, stage, adult_life(), 10), "An unlicensed " + stage + " can take the course")
	check(not School.eligible(School.fresh("adult"), "adult", adult_life(), 10), "A licensed adult has nothing to learn")
	check(not School.eligible(unlicensed, "young_adult", adult_life(), 10, true), "A spirit cannot")
	check(School.menu_ids(School.fresh("teen"), "teen", teen_life(5), 24).is_empty() and School.menu_ids(School.fresh("adult"), "adult", adult_life(), 24).is_empty() and School.menu_ids(School.fresh("child"), "child", adult_life(), 24).is_empty(), "A teen with 19 days, a licensed adult and a child see nothing added to their menus")
	check(School.menu_ids(School.fresh("teen"), "teen", teen_life(5), 25) == ["learn_to_drive"], "At 20 days Learn to drive appears")
	check(School.menu_ids(learner(), "teen", teen_life(5), 30) == ["book_driving_lesson"], "With the theory done the menu offers booking instead")

func _theory() -> void:
	var record: Dictionary = School.fresh("teen")
	check(School.theory_error(record, "teen", teen_life(5), 24).contains("20 days as a teenager") and School.theory_error(record, "teen", teen_life(5), 24).contains("1 more day"), "Too soon says how long: " + School.theory_error(record, "teen", teen_life(5), 24))
	check(School.theory_error(record, "child", adult_life(), 24).contains("teenagers"), "A child is told lessons are for teenagers")
	check(School.theory_error(School.fresh("adult"), "adult", adult_life(), 24) == "Already has a driving licence.", "A licensed Lifelet is told so")
	check(School.theory_error(record, "teen", teen_life(5), 25) == "", "Open at 20 days")
	var once: Dictionary = School.credit_theory(record, 25)
	check(int(once.theory_days) == 1 and int(once.last_theory_day) == 25, "One session counts one day")
	check(School.credit_theory(once, 25) == once and School.theory_error(once, "teen", teen_life(5), 25).contains("Come back tomorrow"), "A second session on the same day does not count and says why")
	var every_day: Dictionary = School.fresh("teen")
	for day: int in range(25, 32): every_day = School.credit_theory(every_day, day)
	check(int(every_day.theory_days) == 7 and School.theory_done(every_day), "Seven different days finish the theory")
	check(School.credit_theory(every_day, 40) == every_day and School.theory_error(every_day, "teen", teen_life(5), 40).contains("Book a practical lesson"), "It stops at seven")
	var skipping: Dictionary = School.fresh("teen")
	for day: int in [25, 27, 31, 40, 41, 50, 51]: skipping = School.credit_theory(skipping, day)
	check(School.theory_done(skipping), "The seven days need not be in a row")
	check(School.THEORY_MINUTES == 60.0 and School.THEORY_DAYS == 7, "A session is an hour and the theory is seven days at any lifespan")

func _windows_and_slots() -> void:
	# Day 1 is a Monday: 6 is Saturday and 7 is Sunday.
	check(not School.lesson_window(1, 959.0) and School.lesson_window(1, 960.0) and School.lesson_window(1, 1170.0) and not School.lesson_window(1, 1171.0), "Weekdays: lessons start from 16:00 to 19:30")
	check(not School.lesson_window(6, 539.0) and School.lesson_window(6, 540.0) and School.lesson_window(6, 1080.0) and not School.lesson_window(6, 1081.0), "Saturday: from 09:00 to 18:00")
	check(School.lesson_window(7, 720.0) and not School.lesson_window(7, 500.0), "Sunday is a weekend too")
	check(School.is_weekday(5) and not School.is_weekday(6) and School.is_saturday(13) and School.is_sunday(14) and School.is_weekday(15), "Weeks repeat every seven days")
	var record: Dictionary = learner(7, [])
	var life: Dictionary = teen_life(1)
	# Day 30 is a Tuesday (29 % 7 == 1).
	check(School.lesson_error(record, "teen", life, 30, 600.0).contains("16:00 to 19:30") and School.lesson_error(record, "teen", life, 30, 1000.0) == "", "Tuesday 10:00 refused, 16:40 allowed")
	check(School.lesson_error(learner(6, []), "teen", life, 30, 1000.0).contains("Finish the driving theory first (6 of 7"), "Lessons wait for the theory: " + School.lesson_error(learner(6, []), "teen", life, 30, 1000.0))
	check(School.lesson_error(learner(7, [30]), "teen", life, 30, 1000.0) == "Only one driving lesson a day.", "Only one lesson a day")
	check(School.lesson_error(School.fresh("adult"), "adult", adult_life(), 30, 1000.0) == "Already has a driving licence.", "A licensed Lifelet is refused")
	check(School.lesson_error(record, "teen", life, 30, 1170.0) == "" and 1170.0 + School.LESSON_MINUTES < School.LATEST_END and 1080.0 + School.LESSON_MINUTES < School.LATEST_END, "Every lesson that may start also ends before 22:00")
	# Booking slots from Wednesday day 31 at 10:00: today's 16:00, Saturday day 34, Sunday day 35.
	var options: Array = School.booking_options(record, "teen", life, 31, 600.0)
	check(options.size() == 3 and int(options[0].day) == 31 and options[0].minutes == 960.0 and options[0].id == "weekday", "From Wednesday morning the after-school slot is today at 16:00")
	check(int(options[1].day) == 34 and options[1].minutes == 600.0 and options[1].id == "saturday" and int(options[2].day) == 35 and options[2].minutes == 600.0, "Saturday and Sunday are at 10:00")
	options = School.booking_options(record, "teen", life, 31, 1000.0)
	check(int(options[0].day) == 32, "Once today's slot is past the next one is tomorrow (Thursday)")
	options = School.booking_options(record, "teen", life, 34, 800.0)
	check(options.size() == 3 and int(options[0].day) == 36 and int(options[1].day) == 41 and int(options[2].day) == 35, "On Saturday afternoon the next Saturday is a week away and the weekday slot is Monday: " + str(options.map(func(o: Dictionary) -> int: return int(o.day))))
	options = School.booking_options(record, "teen", life, 34, 500.0)
	check(int(options[1].day) == 34, "Saturday before 10:00 still offers today")
	check(School.booking_options(learner(5, []), "teen", life, 31, 600.0).is_empty() and School.booking_options(School.fresh("adult"), "adult", adult_life(), 31, 600.0).is_empty(), "Nothing to book before the theory is done, or once licensed")
	for option: Dictionary in School.booking_options(record, "teen", life, 31, 600.0): check(int(option.day) - 31 <= School.BOOKING_HORIZON, "Every slot is inside the week: " + str(option.id))
	# Booking reasons.
	check(School.booking_error(record, "teen", life, 31, 30, 960.0).contains("already gone") and School.booking_error(record, "teen", life, 31, 39, 960.0).contains("a week ahead"), "A past day and a day more than a week away are refused")
	var started: Dictionary = learner(7, [31])
	check(School.booking_error(started, "teen", life, 40, 45, 960.0).contains("course ends on day 44") and School.booking_error(started, "teen", life, 40, 44, 600.0) == "", "A day after the course ends is refused, the last day is not")
	check(School.booking_error(started, "teen", life, 32, 31, 600.0) == "Only one driving lesson a day." and School.booking_error(started, "teen", life, 32, 33, 960.0) == "", "A day that already has a lesson is refused")

func _lessons_and_course() -> void:
	var record: Dictionary = learner(7, [])
	var days: Array = [30, 31, 32, 33, 34]
	var after: Dictionary = record
	for index: int in range(days.size()):
		after = School.credit_lesson(after, int(days[index]))
		check(School.lessons(after) == index + 1 and School.is_licensed(after) == (index == 4), "Lesson %d: %d done, licensed %s" % [index + 1, School.lessons(after), str(School.is_licensed(after))])
	check(int(after.licensed_day) == 34 and School.validate(after, 34) == "", "The fifth lesson passes on its own day and the record is valid")
	check(School.credit_lesson(learner(7, [30]), 30).lesson_days == [30], "Two lessons on one day count once")
	check(School.credit_lesson(after, 35).lesson_days == after.lesson_days, "Nothing is added once five are done")
	var booked: Dictionary = School.book(record, 31, 960.0)
	check(School.has_booking(booked) and not School.has_booking(School.credit_lesson(booked, 31)), "A lesson uses up the booking")
	check(School.course_end_day(learner(7, [10, 12])) == 23 and School.course_end_day(record) == 0, "A course that began on day 10 ends on day 23")
	# The window: day 10 start; day 23 is the last day, day 24 is too late.
	var partial: Dictionary = learner(7, [10, 12])
	var life: Dictionary = teen_life(1)
	check(not School.events(partial, "teen", life, 23, 1000.0, false).has("lapse"), "On day 23 the course is still open")
	check(School.events(partial, "teen", life, 24, 100.0, false).has("lapse"), "On day 24 it has run out")
	var lapsed: Dictionary = School.lapse(partial)
	check(lapsed.lesson_days == [] and School.theory_done(lapsed) and not School.has_booking(lapsed) and School.lessons(lapsed) == 0, "A lapsed course clears the lessons and keeps the theory")
	check(School.validate(lapsed, 24) == "", "...and is a valid record")
	check(not School.events(learner(7, [10, 11, 12, 13, 14]), "teen", life, 40, 100.0, false).has("lapse"), "A finished course never lapses")
	check(not School.events(learner(7, []), "teen", life, 40, 100.0, false).has("lapse"), "Nor does one that never began")
	check(School.lesson_error(record, "teen", life, 31, 1000.0) == "", "After a lapse a new first lesson is allowed")

func _events() -> void:
	var life: Dictionary = teen_life(5)
	var record: Dictionary = School.fresh("teen")
	check(School.events(record, "teen", life, 24, 480.0, false).is_empty(), "No notice before day 25")
	check(School.events(record, "teen", life, 25, 419.0, false).is_empty() and School.events(record, "teen", life, 25, 420.0, false) == ["introduce"], "The notice comes at 07:00 on day 25")
	check(School.events(record, "teen", life, 25, 600.0, true).is_empty(), "Not while the Lifelet is away")
	var told: Dictionary = School.introduced(record, 25)
	check(School.events(told, "teen", life, 26, 600.0, false).is_empty(), "...and only once")
	# Reminders: the theory finished on Monday day 29; the finishing notice counts as the first.
	var done: Dictionary = learner(7, [])
	done["last_reminder_day"] = 29
	done["introduced_day"] = 25
	check(School.events(done, "teen", life, 30, 1000.0, false).is_empty() and School.events(done, "teen", life, 31, 1000.0, false).is_empty(), "Not on the next two days")
	check(School.events(done, "teen", life, 32, 959.0, false).is_empty() and School.events(done, "teen", life, 32, 960.0, false) == ["remind"], "Day 32 (a Thursday) reminds at 16:00")
	check(School.events(done, "teen", life, 32, 960.0, true).is_empty(), "Not while away")
	check(School.events(School.book(done, 33, 960.0), "teen", life, 32, 960.0, false).is_empty(), "Not while a lesson is booked")
	var lessoned: Dictionary = learner(7, [32])
	lessoned["last_reminder_day"] = 29
	check(not School.events(lessoned, "teen", life, 32, 1100.0, false).has("remind"), "Not on a day the lesson was already taken")
	var weekend: Dictionary = School.reminded(done, 32)
	# From Thursday day 32 the next is Sunday day 35 (3 days later); Sunday reminds from 09:30.
	check(School.events(weekend, "teen", life, 35, 569.0, false).is_empty() and School.events(weekend, "teen", life, 35, 570.0, false) == ["remind"], "At the weekend the reminder comes at 09:30")
	check(School.events(weekend, "teen", life, 34, 570.0, false).is_empty(), "...never earlier than three days after the last")
	check(not School.events(learner(6, []), "teen", life, 32, 1000.0, false).has("remind"), "No reminders before the theory is done")
	check(School.events(School.fresh("adult"), "adult", adult_life(), 32, 1000.0, false).is_empty(), "A licensed Lifelet is never reminded")
	var booking: Dictionary = School.book(learner(7, []), 31, 960.0)
	check(not School.booking_due(booking, 31, 959.0) and School.booking_due(booking, 31, 960.0) and School.booking_due(booking, 31, 990.0) and not School.booking_due(booking, 31, 990.5), "A booking is due from its time to 30 minutes after")
	check(not School.booking_missed(booking, 31, 990.0) and School.booking_missed(booking, 31, 991.0) and School.booking_missed(booking, 32, 100.0), "...and missed after that")
	check(School.events(booking, "teen", life, 31, 991.0, false).has("missed"), "The missed event is raised")
	check(School.booking_soon(booking, 31, 930.0, 45.0) and not School.booking_soon(booking, 31, 900.0, 45.0) and not School.booking_soon(booking, 32, 100.0, 45.0), "A booking is 'soon' within 45 minutes")
	var summary: Dictionary = School.summary(learner(7, [30, 31]))
	check(int(summary.theory) == 7 and int(summary.lessons) == 2 and int(summary.course_end_day) == 43 and not bool(summary.licensed), "The summary reads 7 of 7, 2 of 5, ending day 43")
	# The tooltip line.
	check(School.status_text(School.fresh("adult"), "adult", adult_life(), 30) == "" and School.status_text(School.fresh("child"), "child", adult_life(), 30) == "", "Nothing to say for a child or an adult who always held a licence")
	check(School.status_text(School.fresh("teen"), "teen", teen_life(5), 24) == "Can learn to drive in 1 day" and School.status_text(School.fresh("teen"), "teen", teen_life(5), 5) == "Can learn to drive in 20 days", "A young teenager is told how long to wait")
	check(School.status_text(School.fresh("teen"), "teen", teen_life(5), 30) == "Learner driver · theory 0 of 7 days" and School.status_text(learner(3, []), "teen", teen_life(5), 30) == "Learner driver · theory 3 of 7 days", "A learner's theory is counted")
	check(School.status_text(learner(7, []), "teen", teen_life(5), 30) == "Learner driver · lessons 0 of 5" and School.status_text(learner(7, [30, 31]), "teen", teen_life(5), 32) == "Learner driver · lessons 2 of 5 · course ends day 43", "...then the lessons and the end of the course")
	var passed: Dictionary = learner(7, [])
	for day: int in [30, 31, 32, 33, 34]: passed = School.credit_lesson(passed, day)
	check(School.status_text(passed, "young_adult", adult_life(), 40) == "Driving licence held" and School.status_text(passed, "young_adult", adult_life(), 40, true) == "", "A Lifelet who passed says so, a spirit says nothing")

func _validation() -> void:
	var good: Dictionary = learner(7, [30, 32])
	good["introduced_day"] = 25
	check(School.validate(null, 40) == "" and School.validate(good, 40) == "", "Absent or null is legal; a good record is valid")
	check(School.validate({}, 40) != "" and School.validate("licensed", 40) != "" and School.validate([], 40) != "", "Wrong shapes are refused")
	var broken: Dictionary
	broken = good.duplicate(true); broken["theory_days"] = 8
	check(School.validate(broken, 40) != "", "Theory of 8 days is refused")
	broken = good.duplicate(true); broken["last_theory_day"] = 41
	check(School.validate(broken, 40) != "", "A study day in the future is refused")
	broken = good.duplicate(true); broken["theory_days"] = 0; broken["last_theory_day"] = 0
	check(School.validate(broken, 40) != "", "Lessons without theory are refused")
	broken = good.duplicate(true); broken["theory_days"] = 3; broken["last_theory_day"] = 0
	check(School.validate(broken, 40) != "", "Study days that disagree with their dates are refused")
	broken = good.duplicate(true); broken["lesson_days"] = [32, 30]
	check(School.validate(broken, 40) != "", "Unsorted lessons are refused")
	broken = good.duplicate(true); broken["lesson_days"] = [30, 30]
	check(School.validate(broken, 40) != "", "Two lessons on one day are refused")
	broken = good.duplicate(true); broken["lesson_days"] = [30, 44]
	check(School.validate(broken, 50) != "", "Lessons spread over more than 14 days are refused")
	broken = good.duplicate(true); broken["lesson_days"] = [30, 31, 32, 33, 34, 35]
	check(School.validate(broken, 40) != "", "Six lessons are refused")
	broken = good.duplicate(true); broken["lesson_days"] = [30, 31, 32, 33, 34]
	check(School.validate(broken, 40) != "", "Five lessons without a licence are refused")
	broken = good.duplicate(true); broken["licensed"] = true; broken["licensed_day"] = 32
	check(School.validate(broken, 40) != "", "A licence with two lessons dated after them is refused")
	broken = good.duplicate(true); broken["licensed_day"] = 32
	check(School.validate(broken, 40) != "", "A licence date on someone who has not passed is refused")
	broken = learner(7, [30, 31, 32, 33, 34]); broken["licensed"] = true; broken["licensed_day"] = 34
	check(School.validate(broken, 40) == "", "A passed course is valid")
	broken["licensed_day"] = 33
	check(School.validate(broken, 40) != "", "...but its licence day must be the last lesson")
	broken = School.fresh("adult"); broken["booking"] = {"day": 41, "minutes": 960.0}
	check(School.validate(broken, 40) != "", "A booking on a licensed Lifelet is refused")
	var booked: Dictionary = School.book(good, 41, 960.0)
	check(School.validate(booked, 40) == "", "A good booking for tomorrow is valid")
	for bad_booking: Dictionary in [{"day": 36, "minutes": 960.0}, {"day": 43, "minutes": 600.0}, {"day": 48, "minutes": 960.0}, {"day": 41}, {"day": 41, "minutes": 960.0, "x": 1}, {"day": 41, "minutes": NAN}]:
		broken = good.duplicate(true); broken["booking"] = bad_booking
		check(School.validate(broken, 40) != "", "A bad booking is refused: " + str(bad_booking))
	check(School.validate(School.book(good, 43, 600.0), 40) != "" and School.validate(School.book(good, 41, 600.0), 40) == "", "A morning slot is only for a weekend day (day 41 is a Saturday, day 43 a Monday)")
	broken = good.duplicate(true); broken["version"] = 2
	check(School.validate(broken, 40) != "", "A wrong version is refused")
	broken = good.duplicate(true); broken["extra"] = 1
	check(School.validate(broken, 40) != "", "An extra key is refused")
	broken = good.duplicate(true); broken.erase("booking")
	check(School.validate(broken, 40) != "", "A missing key is refused")
	broken = good.duplicate(true); broken["introduced_day"] = 41
	check(School.validate(broken, 40) != "", "An introduction in the future is refused")
	broken = good.duplicate(true); broken["last_reminder_day"] = -1
	check(School.validate(broken, 40) != "", "A negative reminder day is refused")
	broken = good.duplicate(true); broken["licensed"] = "yes"
	check(School.validate(broken, 40) != "", "A licence that is not a bool is refused")
	# The record does not depend on the age, so Change Age on the farewell dialog cannot strand a save.
	check(School.validate(School.fresh("elder"), 40) == "" and School.validate(School.fresh("child"), 40) == "", "Any stage's record validates")

func _migration() -> void:
	var roundtrip: Dictionary = School.migrate(JSON.parse_string(JSON.stringify(learner(7, [30, 32]))), "teen")
	check(School.validate(roundtrip, 40) == "" and roundtrip.lesson_days == [30, 32] and typeof(roundtrip.lesson_days[0]) == TYPE_INT and typeof(roundtrip.theory_days) == TYPE_INT, "A JSON round trip gives whole numbers back")
	var with_booking: Dictionary = School.migrate(JSON.parse_string(JSON.stringify(School.book(learner(7, []), 41, 960.0))), "teen")
	check(School.validate(with_booking, 40) == "" and typeof(with_booking.booking.day) == TYPE_INT, "...and a booking")
	check(School.migrate(null, "adult").licensed and not School.migrate(null, "teen").licensed and School.migrate({}, "elder").licensed, "An older save with no record is licensed when the Lifelet is a young adult or older")
	check(not School.migrate({"licensed": false}, "adult").licensed, "A saved record that says unlicensed stays so")
