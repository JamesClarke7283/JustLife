extends SceneTree
const Education = preload("res://scripts/education.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var state: Dictionary = Education.fresh("child",1)
	check(Education.validate(state,"child",1).is_empty(),"Fresh child schooling must be valid.")
	check(Education.grade(state) == "C" and Education.summary(state).school == "Willow School","Enrollment must begin with a clear grade and original school identity.")
	check(Education.weekday(1) and Education.weekday_name(1) == "Monday" and not Education.weekday(6) and not Education.weekday(7),"The school calendar must consistently identify weekdays.")
	var initial: Dictionary = state.duplicate(true)
	var menu: Array = Education.actions(state,"child",1,480)
	check(menu.size() == 2 and menu[0].available and menu[1].available,"Children must have available weekday class and homework actions.")
	check(state == initial,"Reading actions must not mutate persistent state.")
	check(not Education.actions(state,"child",1,420)[0].available,"School cannot start before 08:00.")
	check(not Education.actions(state,"child",1,841)[0].available,"School cannot start after 14:00.")
	check(not Education.complete(state,"child",1,420,"school").ok and state == initial,"An unavailable early class must be rejected without changes.")
	check(not Education.complete(state,"child",1,480,"invented").ok,"Unknown school actions must be rejected.")
	var homework: Dictionary = Education.complete(state,"child",1,460,"homework")
	check(homework.ok and homework.state.homework == 1 and homework.state.last_homework_day == 1,"Completing homework must persist its day and total.")
	check(homework.effects.skill_xp.logic == 6.0 and homework.effects.needs.fun < 0 and not homework.effects.has("funds"),"Homework must trade leisure and energy for real learning, without wages.")
	check(state == initial,"Action completion must return a new state instead of mutating the caller.")
	state = homework.state
	check(Education.summary(state).homework_ready,"Completed homework must prepare the next class.")
	check(not Education.complete(state,"child",1,500,"homework").ok,"Homework cannot be farmed repeatedly on the same day.")
	var lesson: Dictionary = Education.complete(state,"child",1,660,"school")
	check(lesson.ok and lesson.state.attended == 1 and lesson.state.prepared == 1,"School attendance must consume the prepared assignment exactly once.")
	check(lesson.effects.skill_xp.logic == 10.0 and lesson.effects.needs.social > 0 and lesson.effects.needs.energy < 0,"Prepared lessons must teach more and have meaningful need tradeoffs.")
	state = lesson.state
	check(not Education.summary(state).homework_ready and not Education.actions(state,"child",1,700)[0].available,"After school, the prepared assignment and repeat attendance must both be unavailable.")
	check(not Education.complete(state,"child",1,720,"school").ok,"Repeated class completion cannot grant duplicate learning.")
	for day: int in range(2,6):
		var next: Dictionary = Education.advance(state,"child",day)
		check(next.ok and next.state.missed == 0,"Attending each previous weekday must avoid absences.")
		state = next.state
		lesson = Education.complete(state,"child",day,660,"school")
		check(lesson.ok and lesson.effects.skill_xp.logic == 6.0,"Lessons without prepared homework still teach, with a smaller benefit.")
		state = lesson.state
	var friday: Dictionary = Education.complete(state,"child",5,960,"homework")
	state = friday.state
	check(Education.summary(state).homework_ready,"Friday homework must remain ready for the next school day.")
	var weekend: Dictionary = Education.advance(state,"child",8)
	check(weekend.ok and weekend.state.missed == 0,"Saturday and Sunday must never count as missed school.")
	check(not Education.complete(state,"child",6,660,"school").ok and not Education.complete(state,"child",7,960,"homework").ok,"Weekend school and homework completions must be unavailable.")
	state = weekend.state
	lesson = Education.complete(state,"child",8,660,"school")
	check(lesson.ok and lesson.state.prepared == 2,"An unused Friday assignment must benefit Monday's lesson.")
	state = lesson.state
	var absence: Dictionary = Education.advance(state,"child",10)
	check(absence.ok and absence.state.missed == 1,"Skipping Tuesday must record exactly one missed weekday.")
	check(Education.score(absence.state) == Education.score(state)-4.0 and not absence.notices.is_empty(),"An absence must lower the grade and explain that consequence.")
	state = absence.state
	var replay: Dictionary = Education.advance(state,"child",10)
	check(replay.ok and replay.state == state and replay.notices.is_empty(),"Repeated day updates cannot double-charge absences.")
	var parsed: Variant = JSON.parse_string(JSON.stringify(state))
	check(Education.validate(parsed,"child",10).is_empty(),"Schooling must validate after JSON converts integer values to numbers.")
	var normalized: Dictionary = Education.advance(parsed,"child",10)
	check(normalized.ok and normalized.state == state and normalized.state.attended is int,"Reload must normalize counters without losing attendance.")
	var promotion: Dictionary = Education.advance(state,"teen",10)
	check(promotion.ok and promotion.state.stage == "teen" and promotion.state.records.size() == 1,"A child birthday must preserve the primary-school report and enroll secondary school.")
	check(promotion.state.records[0].outcome == "completed" and promotion.state.records[0].attended == 6,"Primary completion must reflect earned attendance, without inventing graduation.")
	state = promotion.state
	for day: int in range(10,15):
		var current: Dictionary = Education.advance(state,"teen",day)
		check(current.ok,"Teen schooling must advance across the calendar.")
		state = current.state
		if Education.weekday(day):
			state = Education.complete(state,"teen",day,460,"homework").state
			state = Education.complete(state,"teen",day,660,"school").state
	var graduation: Dictionary = Education.advance(state,"young_adult",15)
	check(graduation.ok and graduation.state.records.size() == 2,"A teen birthday must preserve both schooling stages.")
	check(graduation.state.records[1].outcome == "graduated" and graduation.state.records[1].attended == 3,"Graduation requires a passing record and at least three attended classes.")
	check(graduation.effects.needs.fun > 0 and not graduation.effects.has("funds"),"Graduation may improve mood-related needs but cannot invent wages.")
	check(Education.actions(graduation.state,"young_adult",15,600).is_empty() and not Education.complete(graduation.state,"young_adult",15,660,"school").ok,"Graduates cannot keep farming child or teen classes.")
	parsed = JSON.parse_string(JSON.stringify(graduation.state))
	check(Education.validate(parsed,"young_adult",15).is_empty(),"All completion records must survive JSON round-trip.")
	check(Education.advance(parsed,"adult",16).ok,"School records must persist through later adult birthdays.")
	var unearned: Dictionary = Education.advance(Education.fresh("teen",1),"young_adult",2)
	check(unearned.ok and unearned.state.records[0].outcome == "unfinished" and unearned.effects.is_empty(),"A rushed teen birthday must record unfinished school without unearned graduation benefits.")
	var adult: Dictionary = Education.fresh("adult",20)
	check(adult.records.is_empty() and Education.validate(adult,"adult",20).is_empty(),"Adults created directly must not receive fabricated school history.")
	check(not Education.advance(state,"child",15).ok and not Education.advance(Education.fresh("child",1),"young_adult",2).ok,"School records cannot reverse or skip educational stages.")
	var damaged: Dictionary = graduation.state.duplicate(true)
	damaged.records[1].score = 100.0
	check(not Education.validate(damaged,"young_adult",15).is_empty(),"Forged graduation grades must be rejected.")
	damaged = unearned.state.duplicate(true); damaged.records[0].outcome = "graduated"
	check(not Education.validate(damaged,"young_adult",2).is_empty(),"A malformed save cannot promote an unfinished record to graduation.")
	for value: Variant in [-1,1.5,"3",INF,NAN]:
		damaged = initial.duplicate(true);damaged.attended = value
		check(not Education.validate(damaged,"child",1).is_empty(),"Malformed attendance counters must be rejected.")
	damaged = initial.duplicate(true);damaged.homework = 1;damaged.last_homework_day = 6
	check(not Education.validate(damaged,"child",6).is_empty(),"Saved homework must match a valid weekday and current school calendar.")
	damaged = initial.duplicate(true);damaged.prepared = 1
	check(not Education.validate(damaged,"child",1).is_empty(),"Prepared lessons require both attendance and homework.")
	damaged = graduation.state.duplicate(true);damaged.records.reverse()
	check(not Education.validate(damaged,"young_adult",15).is_empty(),"Graduation records must remain chronologically ordered.")
	damaged = graduation.state.duplicate(true);damaged.records[1].stage = "child"
	check(not Education.validate(damaged,"young_adult",15).is_empty(),"Duplicate school-stage records must be rejected.")
	damaged = initial.duplicate(true);damaged.last_day = 4
	check(not Education.validate(damaged,"child",4).is_empty(),"A save cannot erase attendance accounting for completed school days.")
	check(not Education.actions(initial,"child",1,1400)[1].available,"Homework must start early enough to finish before the next calendar day.")
	check(not Education.complete(initial,"child",1,1021,"school").ok,"School completion after its latest scheduled finish must fail.")
	var late_class: Dictionary = Education.complete(initial,"child",1,1020,"school")
	check(late_class.ok,"A class started at14:00 must be allowed to finish at17:00.")
	var catch_up: Dictionary = Education.advance(Education.fresh("teen",1),"teen",1000000)
	check(catch_up.ok and catch_up.state.missed == 714285,"Large calendar catch-up must count weekdays accurately without a million-step loop.")
	print("EDUCATION TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
