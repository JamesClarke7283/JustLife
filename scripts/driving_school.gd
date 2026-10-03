extends RefCounted
class_name LifeDrivingSchool
## Learning to drive, as pure rules: no nodes, no clock and no wallet.
##
## A Lifelet keeps a small record (below) and asks these functions what it means.
## Lifelets who start life as a young adult, an adult or an elder (created, or
## loaded from a save that has no record) already hold a licence. Only a Lifelet
## who grows up through the teen stage has to learn:
##
##   1. Lessons open after 20 days as a teenager (scaled by the lifespan setting
##      like every age-tied threshold: 10 on a short life, 80 on a long one), or
##      on becoming a young adult, whichever comes first. The days are calendar
##      days counted by `LifeLifecycle.days_in_stage`, so they keep counting while
##      automatic birthdays are off.
##   2. Theory: one 60-minute "Learn to drive" study session on each of seven
##      different days (fixed, not scaled).
##   3. Practical: five 90-minute lessons with an instructor, at most one a day,
##      all within a 14-day course that starts at the first lesson. The fifth
##      lesson passes the test. If the 14 days run out first the lessons start
##      over; the theory is kept.
##
## Lessons run on weekdays from 16:00 to 19:30 (after the school bus has gone) and
## on Saturday and Sunday from 09:00 to 18:00 (the time a lesson starts). A lesson
## may be booked for the next after-school slot, Saturday 10:00 or Sunday 10:00,
## with 30 minutes' grace. Reminders come every three days once the theory is done.
##
## The record, saved on the Lifelet as the optional key "driving":
##   version, licensed, licensed_day (the day the fifth lesson passed; 0 for a
##   Lifelet who held a licence from the start or has none), introduced_day (the
##   day the "you can learn to drive" notice was given; 0 until then), theory_days
##   (0..7), last_theory_day, lesson_days (the day of each lesson, in order),
##   last_reminder_day, booking ({} or {day, minutes}).
## The number of lessons is always `lesson_days.size()`; it is never stored twice.

const VERSION: int = 1
## Days as a teenager before lessons open, at the normal lifespan.
const TEEN_DAYS: int = 20
const THEORY_DAYS: int = 7
const THEORY_MINUTES: float = 60.0
const LESSONS_REQUIRED: int = 5
const COURSE_DAYS: int = 14
const LESSON_MINUTES: float = 90.0
## What a lesson costs. The brief names no price, so lessons are free.
const LESSON_FEE: int = 0
const REMINDER_DAYS: int = 3
## When a lesson may start: after school on weekdays, a long day at the weekend.
const WEEKDAY_FIRST: float = 960.0
const WEEKDAY_LAST: float = 1170.0
const WEEKEND_FIRST: float = 540.0
const WEEKEND_LAST: float = 1080.0
## The slots a booking holds, and how long after one a booking still counts.
const SLOT_AFTER_SCHOOL: float = 960.0
const SLOT_WEEKEND: float = 600.0
const BOOKING_GRACE: float = 30.0
const BOOKING_HORIZON: int = 7
## A reminder arrives at this minute of the day, and the notice that lessons have
## opened comes at 07:00.
const REMINDER_WEEKDAY: float = 960.0
const REMINDER_WEEKEND: float = 570.0
const INTRO_MINUTE: float = 420.0
## No lesson may still be running at this time.
const LATEST_END: float = 1320.0
## The three action ids. Theory is studied at the bookcase (not the reading nook) and at every
## desk; booking is a panel, not an action that is ever queued; the lesson is the car and the walk.
const THEORY_ACTION: String = "learn_to_drive"
const BOOK_ACTION: String = "book_driving_lesson"
const LESSON_ACTION: String = "driving_lesson"
const KEYS: Array[String] = ["version", "licensed", "licensed_day", "introduced_day", "theory_days", "last_theory_day", "lesson_days", "last_reminder_day", "booking"]
const SLOT_LABELS: Dictionary = {"weekday": "After school", "saturday": "Saturday morning", "sunday": "Sunday morning"}


static func fresh(stage: String) -> Dictionary:
	return {"version": VERSION, "licensed": LifeLifecycle.at_least(stage, "young_adult"), "licensed_day": 0, "introduced_day": 0,
		"theory_days": 0, "last_theory_day": 0, "lesson_days": [], "last_reminder_day": 0, "booking": {}}

static func is_licensed(record: Dictionary) -> bool:
	return bool(record.get("licensed", false))

## Whole days a teenager must have been one before lessons open.
static func needed_days(lifespan: String) -> int:
	return maxi(1, ceili(LifeLifecycle.scaled_days(float(TEEN_DAYS), lifespan) - 0.000001))

## Days of being a teenager still to wait; 0 once lessons are open (or for anyone older).
static func days_until_open(stage: String, lifecycle: Dictionary, day: int) -> int:
	if stage != "teen": return 0
	return maxi(0, needed_days(str(lifecycle.get("lifespan", "normal"))) - LifeLifecycle.days_in_stage(lifecycle, "teen", day))

## Whether this Lifelet may study for and take the driving course: not yet
## licensed, living, and either a young adult or older or a teenager who has been
## one long enough.
static func eligible(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, passed: bool = false) -> bool:
	if passed or is_licensed(record): return false
	if stage == "teen": return days_until_open(stage, lifecycle, day) == 0
	return LifeLifecycle.at_least(stage, "young_adult")

static func lessons(record: Dictionary) -> int:
	return (record.get("lesson_days", []) as Array).size()

static func theory_done(record: Dictionary) -> bool:
	return int(record.get("theory_days", 0)) >= THEORY_DAYS

## The last day the course may still be completed, or 0 before the first lesson.
static func course_end_day(record: Dictionary) -> int:
	var taken: Array = record.get("lesson_days", [])
	return 0 if taken.is_empty() else int(taken[0]) + COURSE_DAYS - 1

static func is_weekday(day: int) -> bool: return day >= 1 and (day - 1) % 7 < 5
static func is_saturday(day: int) -> bool: return day >= 1 and (day - 1) % 7 == 5
static func is_sunday(day: int) -> bool: return day >= 1 and (day - 1) % 7 == 6

## Whether a lesson may start at this minute of this day.
static func lesson_window(day: int, minutes: float) -> bool:
	if day < 1: return false
	if is_weekday(day): return minutes >= WEEKDAY_FIRST and minutes <= WEEKDAY_LAST
	return minutes >= WEEKEND_FIRST and minutes <= WEEKEND_LAST

static func window_text() -> String:
	return "Lessons start after school (16:00 to 19:30) on weekdays and between 09:00 and 18:00 on Saturday and Sunday."

## Why theory study is closed right now, in words a player can read. Empty means open.
static func theory_error(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, passed: bool = false) -> String:
	if passed: return "A spirit has finished that chapter of life."
	if is_licensed(record): return "Already has a driving licence."
	if not LifeLifecycle.at_least(stage, "teen"): return "Driving lessons are for teenagers and older."
	var wait: int = days_until_open(stage, lifecycle, day)
	if wait > 0: return "Driving lessons open after %d days as a teenager (%d more %s)." % [needed_days(str(lifecycle.get("lifespan", "normal"))), wait, "day" if wait == 1 else "days"]
	if theory_done(record): return "The theory is finished. Book a practical lesson."
	if int(record.get("last_theory_day", 0)) == day: return "Today's driving study is done. Come back tomorrow."
	return ""

## Why the "Book a driving lesson" panel is closed, or "" when it can open. It is
## about the course, not the clock: a lesson taken today still leaves tomorrow to book.
static func panel_error(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, passed: bool = false) -> String:
	if passed: return "A spirit has finished that chapter of life."
	if is_licensed(record): return "Already has a driving licence."
	if not eligible(record, stage, lifecycle, day): return theory_error(record, stage, lifecycle, day)
	if not theory_done(record): return "Finish the driving theory first (%d of %d study days)." % [int(record.get("theory_days", 0)), THEORY_DAYS]
	return ""

## Why a practical lesson cannot start at this minute. Empty means it can.
static func lesson_error(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, minutes: float, passed: bool = false) -> String:
	if passed: return "A spirit has finished that chapter of life."
	var closed: String = booking_error(record, stage, lifecycle, day, day, minutes, false)
	if not closed.is_empty(): return closed
	if not lesson_window(day, minutes): return window_text()
	if minutes + LESSON_MINUTES >= LATEST_END: return "There is not enough of the evening left for a lesson."
	return ""

## Why a lesson cannot be given on `book_day`, whatever the time. `today` is the
## current day; `check_future` also asks that the day is not in the past, not more
## than a week ahead and inside the course window.
static func booking_error(record: Dictionary, stage: String, lifecycle: Dictionary, today: int, book_day: int, _minutes: float, check_future: bool = true) -> String:
	if is_licensed(record): return "Already has a driving licence."
	if not eligible(record, stage, lifecycle, today):
		var closed: String = theory_error(record, stage, lifecycle, today)
		return closed if not closed.is_empty() else "Driving lessons are not open to this Lifelet yet."
	if not theory_done(record): return "Finish the driving theory first (%d of %d study days)." % [int(record.get("theory_days", 0)), THEORY_DAYS]
	if (record.get("lesson_days", []) as Array).has(book_day): return "Only one driving lesson a day."
	if check_future:
		if book_day < today: return "That day has already gone."
		if book_day > today + BOOKING_HORIZON: return "Lessons can be booked up to a week ahead."
		var end: int = course_end_day(record)
		if end > 0 and book_day > end: return "The course ends on day %d. Book a day before it." % end
	return ""

## The slots a lesson can be booked for from now: the next after-school start, the
## next Saturday at 10:00 and the next Sunday at 10:00, each inside the horizon.
## Every entry is {id, label, day, minutes}.
static func booking_options(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, minutes: float) -> Array:
	var options: Array = []
	for slot: String in ["weekday", "saturday", "sunday"]:
		var at: float = SLOT_AFTER_SCHOOL if slot == "weekday" else SLOT_WEEKEND
		var found: int = 0
		for ahead: int in range(0, BOOKING_HORIZON + 1):
			var candidate: int = day + ahead
			var right_day: bool = is_weekday(candidate) if slot == "weekday" else (is_saturday(candidate) if slot == "saturday" else is_sunday(candidate))
			if not right_day: continue
			if candidate == day and minutes >= at: continue
			if not booking_error(record, stage, lifecycle, day, candidate, at).is_empty(): continue
			found = candidate
			break
		if found > 0: options.append({"id": slot, "label": SLOT_LABELS[slot], "day": found, "minutes": at})
	return options

## The record after one more day of theory (once a day, never past seven).
static func credit_theory(record: Dictionary, day: int) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	if theory_done(next) or int(next.last_theory_day) == day: return next
	next["theory_days"] = int(next.theory_days) + 1
	next["last_theory_day"] = day
	return next

## The record after one lesson on `day`. The fifth passes the test. The booking, if
## any, is used up.
static func credit_lesson(record: Dictionary, day: int) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	var taken: Array = (next.lesson_days as Array).duplicate()
	if taken.has(day) or taken.size() >= LESSONS_REQUIRED: return next
	taken.append(day)
	next["lesson_days"] = taken
	next["booking"] = {}
	if taken.size() >= LESSONS_REQUIRED:
		next["licensed"] = true
		next["licensed_day"] = day
	return next

## The record after the course's days ran out: the lessons start over, the theory stays.
static func lapse(record: Dictionary) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	next["lesson_days"] = []
	next["booking"] = {}
	return next

static func introduced(record: Dictionary, day: int) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	next["introduced_day"] = day
	return next

static func reminded(record: Dictionary, day: int) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	next["last_reminder_day"] = day
	return next

static func book(record: Dictionary, day: int, minutes: float) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	next["booking"] = {"day": day, "minutes": minutes}
	return next

static func unbook(record: Dictionary) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	next["booking"] = {}
	return next

static func has_booking(record: Dictionary) -> bool:
	return not (record.get("booking", {}) as Dictionary).is_empty()

## Whether the booked lesson is due now: its day, from its time to the end of the grace.
static func booking_due(record: Dictionary, day: int, minutes: float) -> bool:
	if not has_booking(record): return false
	var booking: Dictionary = record.booking
	return int(booking.day) == day and minutes >= float(booking.minutes) and minutes <= float(booking.minutes) + BOOKING_GRACE

## Whether the booked lesson has been missed: its grace ran out.
static func booking_missed(record: Dictionary, day: int, minutes: float) -> bool:
	if not has_booking(record): return false
	var booking: Dictionary = record.booking
	return day > int(booking.day) or (day == int(booking.day) and minutes > float(booking.minutes) + BOOKING_GRACE)

## Whether a booking is due within `within` minutes from now (not yet missed).
static func booking_soon(record: Dictionary, day: int, minutes: float, within: float) -> bool:
	if not has_booking(record): return false
	var booking: Dictionary = record.booking
	if int(booking.day) != day: return false
	return minutes <= float(booking.minutes) + BOOKING_GRACE and float(booking.minutes) - minutes <= within

## What should happen this minute, as event names for the Lifelet to carry out:
## "introduce" (lessons have opened and nobody has said so), "lapse" (the course's
## days ran out), "missed" (a booking's grace ran out) and "remind" (time to nudge
## towards a lesson). A Lifelet who is away is never reminded.
static func events(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, minutes: float, away: bool, passed: bool = false) -> Array[String]:
	var out: Array[String] = []
	if passed or is_licensed(record): return out
	var taken: int = lessons(record)
	if taken > 0 and taken < LESSONS_REQUIRED and day > course_end_day(record): out.append("lapse")
	if booking_missed(record, day, minutes): out.append("missed")
	if not eligible(record, stage, lifecycle, day): return out
	if int(record.introduced_day) == 0 and minutes >= INTRO_MINUTE and not away: out.append("introduce")
	var due_time: float = REMINDER_WEEKDAY if is_weekday(day) else REMINDER_WEEKEND
	if theory_done(record) and not has_booking(record) and not away and not (record.lesson_days as Array).has(day) and day - int(record.last_reminder_day) >= REMINDER_DAYS and minutes >= due_time and minutes < LATEST_END and not out.has("lapse"):
		out.append("remind")
	return out

## The action ids a study furnishing adds for this Lifelet: learning the theory
## until it is done, then booking a lesson. Nothing for anyone who cannot take the
## course, so ordinary menus are unchanged.
static func menu_ids(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, passed: bool = false) -> Array:
	if not eligible(record, stage, lifecycle, day, passed): return []
	return [BOOK_ACTION] if theory_done(record) else [THEORY_ACTION]

## One line about where the Lifelet stands, for a tooltip: empty for a child, a spirit, or
## a Lifelet who held a licence from the start.
static func status_text(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, passed: bool = false) -> String:
	if passed or not LifeLifecycle.at_least(stage, "teen"): return ""
	if is_licensed(record): return "Driving licence held" if int(record.get("licensed_day", 0)) > 0 else ""
	var wait: int = days_until_open(stage, lifecycle, day)
	if wait > 0: return "Can learn to drive in %d %s" % [wait, "day" if wait == 1 else "days"]
	if not theory_done(record): return "Learner driver · theory %d of %d days" % [int(record.get("theory_days", 0)), THEORY_DAYS]
	var line: String = "Learner driver · lessons %d of %d" % [lessons(record), LESSONS_REQUIRED]
	return line + (" · course ends day %d" % course_end_day(record) if lessons(record) > 0 else "")

## What a panel shows about the course.
static func summary(record: Dictionary) -> Dictionary:
	var end: int = course_end_day(record)
	return {"licensed": is_licensed(record), "theory": int(record.get("theory_days", 0)), "theory_needed": THEORY_DAYS, "lessons": lessons(record),
		"lessons_needed": LESSONS_REQUIRED, "course_end_day": end, "booking": (record.get("booking", {}) as Dictionary).duplicate(), "theory_done": theory_done(record)}

static func clock_text(minutes: float) -> String:
	var whole: int = clampi(int(floor(minutes)), 0, 1439)
	return "%02d:%02d" % [whole / 60, whole % 60]

## A record as a save gives it back: JSON turns every whole number into a float.
## Anything that is not a record is the start of a Lifelet whose licence follows
## their age: held by anyone who is a young adult or older, otherwise to be earned.
static func migrate(value: Variant, stage: String) -> Dictionary:
	if not value is Dictionary or (value as Dictionary).is_empty(): return fresh(stage)
	var source: Dictionary = value
	var record: Dictionary = fresh(stage)
	for key: String in ["version", "licensed_day", "introduced_day", "theory_days", "last_theory_day", "last_reminder_day"]: record[key] = int(source.get(key, record[key]))
	record["licensed"] = bool(source.get("licensed", false))
	var days: Array = []
	for entry: Variant in source.get("lesson_days", []): days.append(int(entry))
	record["lesson_days"] = days
	var booking: Variant = source.get("booking", {})
	record["booking"] = {"day": int((booking as Dictionary).get("day", 0)), "minutes": float((booking as Dictionary).get("minutes", 0.0))} if booking is Dictionary and not (booking as Dictionary).is_empty() else {}
	return record

## What a save says about the licence record, as the reason it cannot be loaded
## (empty when it can). Missing or null is an older save and is fine. Nothing here
## looks at the Lifelet's age, because Change Age on the farewell dialog can move it.
static func validate(value: Variant, day: int) -> String:
	if value == null: return ""
	var bad: String = "Save contains an invalid driving record."
	if not value is Dictionary: return bad
	var record: Dictionary = value
	if record.size() != KEYS.size(): return bad
	for key: String in KEYS:
		if not record.has(key): return bad
	if not _whole(record.version, VERSION, VERSION): return "Save contains an unsupported driving record."
	if not record.licensed is bool: return bad
	for key: String in ["licensed_day", "introduced_day", "last_theory_day", "last_reminder_day"]:
		if not _whole(record[key], 0, day): return "Save contains a driving date that is not a real day."
	if not _whole(record.theory_days, 0, THEORY_DAYS): return "Save contains impossible driving study."
	if (int(record.theory_days) == 0) != (int(record.last_theory_day) == 0): return "Save contains driving study that does not match its dates."
	var taken: Variant = record.lesson_days
	if not taken is Array or (taken as Array).size() > LESSONS_REQUIRED: return "Save contains impossible driving lessons."
	var previous: int = 0
	for entry: Variant in taken:
		if not _whole(entry, 1, day) or int(entry) <= previous: return "Save contains driving lessons that are not on separate days in order."
		previous = int(entry)
	if not (taken as Array).is_empty():
		if int(record.theory_days) < THEORY_DAYS: return "Save contains driving lessons before the theory was done."
		if int((taken as Array).back()) - int((taken as Array)[0]) > COURSE_DAYS - 1: return "Save contains driving lessons spread over more than the course allows."
	var booking: Variant = record.booking
	if not booking is Dictionary: return bad
	if bool(record.licensed):
		if not (booking as Dictionary).is_empty(): return "Save books a driving lesson for a Lifelet who has passed."
		if int(record.licensed_day) != 0 and ((taken as Array).size() != LESSONS_REQUIRED or int(record.licensed_day) != int((taken as Array).back())): return "Save contains a licence that does not follow the lessons."
	else:
		if int(record.licensed_day) != 0: return "Save dates a licence for a Lifelet who has not passed."
		if (taken as Array).size() >= LESSONS_REQUIRED: return "Save contains a finished course without a licence."
	if not (booking as Dictionary).is_empty():
		var slot: Dictionary = booking
		if slot.size() != 2 or not slot.has("day") or not slot.has("minutes") or not _whole(slot.day, 1, day + BOOKING_HORIZON) or not (slot.minutes is int or slot.minutes is float) or not is_finite(float(slot.minutes)): return "Save contains an invalid driving booking."
		if int(slot.day) < day - 1 or not lesson_window(int(slot.day), float(slot.minutes)): return "Save books a driving lesson at a time lessons do not run."
		if int(record.theory_days) < THEORY_DAYS: return "Save books a driving lesson before the theory was done."
	return ""

## What a saved lesson absence says, as the reason it cannot be loaded (empty when
## it can). `state` is the whole saved Lifelet. The lesson is the front action; its
## time away is 90 minutes from the minute it left; the licence record has the
## lesson only once it has been earned; an early return earns nothing.
static func lesson_away_error(state: Dictionary) -> String:
	var bad: String = "Save contains an invalid driving lesson absence."
	var value: Dictionary = state.get("away_state", {})
	var queue: Array = state.get("action_queue", [])
	var day: int = int(state.get("day", 1))
	var now: float = float(day - 1) * 1440.0 + float(state.get("minutes", 0.0))
	if not _whole(value.get("version"), 1, 1) or str(value.get("phase", "")) not in ["away", "returning"] or not value.get("completed") is bool: return bad
	if queue.is_empty() or str(queue[0].get("id", "")) != LESSON_ACTION or queue.filter(func(entry: Dictionary) -> bool: return str(entry.get("id", "")) in [LESSON_ACTION, "school_day", "career_day"]).size() != 1:
		return "Save has a driving lesson absence without its lesson."
	if not _whole(value.get("departure_day"), 1, day) or not _whole(value.get("return_day"), int(value.departure_day), int(value.departure_day)): return "Save contains an invalid driving lesson day."
	if not _number(value.get("departure_minutes"), 0.0, 1320.0) or not _number(value.get("return_minutes"), 0.0, 1439.99999): return "Save contains invalid driving lesson times."
	if absf(float(value.return_minutes) - float(value.departure_minutes) - LESSON_MINUTES) > 0.00001: return "Save contains a driving lesson that is not 90 minutes long."
	if not _whole(value.get("lesson"), 1, LESSONS_REQUIRED) or str(value.get("age_stage", "")) not in LifeLifecycle.STAGES or str(value.get("exit_id", "")) != "lot_exit": return bad
	var position: Variant = value.get("exit_position")
	if not _vector_ok(position): return "Save contains an invalid driving lesson return position."
	var departed: float = float(int(value.departure_day) - 1) * 1440.0 + float(value.departure_minutes)
	var due: float = departed + LESSON_MINUTES
	if now < departed or not _number(value.get("ended_at"), 0.0, now): return "Save contains future driving lesson progress."
	var action: Dictionary = queue[0]
	if action.get("paid") != true or str(action.get("phase", "")) != "active" or str(action.get("target_id", "")) != "lot_exit" or str(action.get("target_kind", "")) != "lot_exit" or not _vec(action.get("target_position")).is_equal_approx(_vec(position)): return "Save contains a mismatched driving lesson action or exit."
	if not _number(action.get("duration"), LESSON_MINUTES, LESSON_MINUTES) or not _whole(action.get("started_day"), int(value.departure_day), int(value.departure_day)) or not _number(action.get("started_minutes"), float(value.departure_minutes) - 0.00001, float(value.departure_minutes) + 0.00001): return "Save contains an invalid driving lesson start."
	var record: Dictionary = state.get("driving", {}) if state.get("driving") is Dictionary else {}
	if int(record.get("theory_days", 0)) < THEORY_DAYS: return "Save contains a driving lesson before the theory was done."
	var taken: Array = record.get("lesson_days", [])
	var credited: bool = taken.any(func(entry: Variant) -> bool: return int(entry) == int(value.departure_day))
	if str(value.phase) == "away":
		if bool(value.completed) or float(value.ended_at) != 0.0 or now >= due or credited or taken.size() != int(value.lesson) - 1: return "Save contains a driving lesson that has already ended."
		if not _number(action.get("elapsed"), maxf(0.0, now - departed - 0.00001), minf(LESSON_MINUTES, now - departed + 0.00001)): return "Save contains impossible time on a driving lesson."
		return ""
	if float(value.ended_at) < departed or float(value.ended_at) > due: return "Save contains an invalid driving lesson return."
	if bool(value.completed):
		if absf(float(value.ended_at) - due) > 0.00001 or now < due or not credited or taken.size() != int(value.lesson): return "Save rewards a driving lesson that was not finished."
	elif credited or taken.size() != int(value.lesson) - 1 or float(value.ended_at) >= due: return "Save counts a driving lesson that ended early."
	if not _number(action.get("elapsed"), maxf(0.0, float(value.ended_at) - departed - 0.00001), minf(LESSON_MINUTES, float(value.ended_at) - departed + 0.00001)): return "Save contains impossible time on a driving lesson."
	return ""

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _vector_ok(value: Variant) -> bool:
	if value is Vector3: return (value as Vector3).is_finite()
	if value is Array and (value as Array).size() == 3: return (value as Array).all(func(axis: Variant) -> bool: return _number(axis, -100000.0, 100000.0))
	return false

static func _vec(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and (value as Array).size() == 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.INF

static func _whole(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float): return false
	var number: float = float(value)
	return is_finite(number) and number == floorf(number) and number >= float(low) and number <= float(high)
