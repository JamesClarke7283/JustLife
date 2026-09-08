extends RefCounted
class_name LifeEducation
## Pure schooling state: callers own time, action queues, needs, skills, and UI.

const VERSION: int = 1
const STAGES: Array[String] = ["child", "teen", "young_adult", "adult", "elder", "unknown"]
const SCHOOL_STAGES: Array[String] = ["child", "teen"]
const DAY_LIMIT: int = 1000000
const COUNTERS: Array[String] = ["attended", "missed", "homework", "prepared"]
const DATES: Array[String] = ["last_attendance_day", "last_homework_day", "last_prepared_homework_day"]


static func fresh(stage: String, day: int = 1) -> Dictionary:
	var valid_stage: String = stage if stage in STAGES else "unknown"
	return {"version":VERSION, "stage":valid_stage, "last_day":clampi(day,1,DAY_LIMIT),
		"enrolled_day":clampi(day,1,DAY_LIMIT) if valid_stage in SCHOOL_STAGES else 0,
		"first_class_day":clampi(day,1,DAY_LIMIT) if valid_stage in SCHOOL_STAGES else 0,
		"attended":0, "missed":0, "homework":0, "prepared":0,
		"last_attendance_day":0, "last_homework_day":0, "last_prepared_homework_day":0,
		"records":[]}


static func weekday(day: int) -> bool:
	return day >= 1 and (day-1)%7 < 5


static func weekday_name(day: int) -> String:
	return ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][posmod(day-1,7)]


static func score(state: Dictionary) -> float:
	return clampf(60.0+float(state.get("attended",0))*2.0+float(state.get("prepared",0))*3.0+float(state.get("homework",0))-float(state.get("missed",0))*4.0,0.0,100.0)


static func grade(state: Dictionary) -> String:
	var value: float = score(state)
	if value >= 85.0: return "A"
	if value >= 70.0: return "B"
	if value >= 55.0: return "C"
	if value >= 40.0: return "D"
	return "F"


static func summary(state: Dictionary) -> Dictionary:
	var scheduled: int = int(state.get("attended",0))+int(state.get("missed",0))
	return {"enrolled":str(state.get("stage","")) in SCHOOL_STAGES,
		"school":"Willow School" if str(state.get("stage","")) == "child" else "Morrow Secondary",
		"grade":grade(state), "score":score(state),
		"attendance":float(state.get("attended",0))/float(scheduled) if scheduled > 0 else 1.0,
		"homework_ready":int(state.get("last_homework_day",0)) > int(state.get("last_prepared_homework_day",0)),
		"records":state.get("records",[]).duplicate(true)}


static func actions(state: Dictionary, stage: String, day: int, minutes: float) -> Array:
	if stage not in SCHOOL_STAGES:
		return []
	var advanced: Dictionary = advance(state,stage,day,minutes)
	if not bool(advanced.ok) or not is_finite(minutes) or minutes < 0.0 or minutes >= 1440.0:
		return []
	var current: Dictionary = advanced.state
	var school_error: String = _availability(current,day,minutes,"school",false)
	var homework_error: String = _availability(current,day,minutes,"homework",false)
	return [
		{"id":"school", "label":"Attend online classes", "duration":180.0, "available":school_error.is_empty(),
			"unavailable_reason":school_error, "description":"Weekdays, 08:00–14:00. Attend lessons, meet classmates, and build your grade. Prepared homework improves learning."},
		{"id":"homework", "label":"Do homework", "duration":45.0, "available":homework_error.is_empty(),
			"unavailable_reason":homework_error, "description":"One assignment each weekday. Builds logic and prepares your next attended school day."}
	]


static func advance(state: Dictionary, stage: String, day: int, enrollment_minutes: float = 480.0) -> Dictionary:
	if stage not in STAGES or day < 1 or day > DAY_LIMIT or not is_finite(enrollment_minutes) or enrollment_minutes < 0 or enrollment_minutes >= 1440:
		return _error("School calendar or age stage is invalid.")
	var old_stage: String = str(state.get("stage",""))
	var problem: String = validate(state,old_stage,day)
	if not problem.is_empty(): return _error(problem)
	if stage != old_stage and not _allowed_transition(old_stage,stage):
		return _error("School records cannot move backward or skip an age stage.")
	var next: Dictionary = _normalized(state)
	var notices: Array[String] = []
	var effects: Dictionary = {}
	if old_stage in SCHOOL_STAGES and day > int(next.last_day):
		var missed: int = _weekdays_between(maxi(int(next.last_day),int(next.first_class_day)),day)
		if int(next.last_attendance_day) == int(next.last_day) and weekday(int(next.last_day)):
			missed -= 1
		if missed > 0:
			next.missed += missed
			notices.append("%d missed school day%s. Current grade: %s." % [missed,"" if missed == 1 else "s",grade(next)])
	next.last_day = day
	if stage != old_stage:
		if old_stage in SCHOOL_STAGES:
			var record: Dictionary = _term_record(next,day)
			next.records.append(record)
			if str(record.outcome) == "graduated":
				notices.append("Graduated from Morrow Secondary with a %s grade." % str(record.grade))
				effects = {"needs":{"fun":8.0,"social":4.0}}
			elif str(record.outcome) == "completed":
				notices.append("Completed Willow School with a %s grade. Secondary school is next." % str(record.grade))
			else:
				notices.append("School record closed with a %s grade; attendance or coursework was incomplete." % str(record.grade))
		var records: Array = next.records
		next = fresh(stage,day)
		if stage in SCHOOL_STAGES and enrollment_minutes > 840.0:
			next.first_class_day = day + 1
		next.records = records
	return {"ok":true,"state":next,"effects":effects,"notices":notices}


static func complete(state: Dictionary, stage: String, day: int, minutes: float, action_id: String) -> Dictionary:
	# This is called only after the controller completes the corresponding queued action.
	var advanced: Dictionary = advance(state,stage,day,minutes)
	if not bool(advanced.ok): return advanced
	if stage not in SCHOOL_STAGES: return _error("Only children and teens are enrolled in school.")
	if not is_finite(minutes) or minutes < 0.0 or minutes >= 1440.0:
		return _error("The school clock is invalid.")
	var next: Dictionary = advanced.state
	var problem: String = _availability(next,day,minutes,action_id,true)
	if not problem.is_empty(): return _error(problem)
	var effects: Dictionary
	var notices: Array = advanced.notices
	if action_id == "school":
		var prepared: bool = int(next.last_homework_day) > int(next.last_prepared_homework_day)
		next.attended += 1
		next.last_attendance_day = day
		if prepared:
			next.prepared += 1
			next.last_prepared_homework_day = int(next.last_homework_day)
		effects = {"needs":{"energy":-10.0,"hunger":-8.0,"fun":-6.0,"social":16.0},
			"skill_xp":{"logic":10.0 if prepared else 6.0,"charisma":3.0}}
		notices.append("School finished%s. Current grade: %s." % [" with homework prepared" if prepared else "",grade(next)])
	else:
		next.homework += 1
		next.last_homework_day = day
		effects = {"needs":{"energy":-3.0,"fun":-5.0},"skill_xp":{"logic":6.0}}
		notices.append("Homework is ready for the next attended school day.")
	return {"ok":true,"state":next,"effects":effects,"notices":notices}


static func validate(state: Variant, stage: String, day: int) -> String:
	if not state is Dictionary or stage not in STAGES or day < 1 or day > DAY_LIMIT:
		return "Save contains invalid schooling data."
	if not _integer(state.get("version"),VERSION,VERSION) or str(state.get("stage","")) != stage:
		return "Save contains an incompatible school record."
	if not _integer(state.get("last_day"),1,day) or not _integer(state.get("enrolled_day"),0,int(state.last_day)):
		return "Save contains an invalid school calendar."
	if not _integer(state.get("first_class_day",state.enrolled_day),int(state.enrolled_day),int(state.enrolled_day)+1):
		return "Save contains an invalid first school day."
	for key: String in COUNTERS:
		if not _integer(state.get(key),0,DAY_LIMIT): return "Save contains an invalid school counter."
	for key: String in DATES:
		if not _integer(state.get(key),0,int(state.last_day)): return "Save contains an invalid school activity date."
	if not state.get("records") is Array or state.records.size() > 2:
		return "Save contains invalid graduation records."
	if stage in SCHOOL_STAGES:
		if int(state.enrolled_day) < 1: return "Save is missing a school enrollment date."
		var allowed_days: int = _weekdays_between(int(state.enrolled_day),int(state.last_day)+1)
		var completed_days: int = _weekdays_between(int(state.get("first_class_day",state.enrolled_day)),int(state.last_day))
		var attended_today: int = 1 if int(state.last_attendance_day) == int(state.last_day) else 0
		if int(state.attended)+int(state.missed) != completed_days+attended_today or int(state.homework) > allowed_days:
			return "Save school attendance does not match its calendar."
	else:
		if int(state.enrolled_day) != 0 or int(state.get("first_class_day",0)) != 0: return "Save enrolls an adult in child schooling."
		for key: String in COUNTERS+DATES:
			if int(state[key]) != 0: return "Save contains active schooling for an unenrolled Lifelet."
	if int(state.prepared) > mini(int(state.attended),int(state.homework)):
		return "Save contains inconsistent prepared lessons."
	if (int(state.attended) == 0) != (int(state.last_attendance_day) == 0) or (int(state.homework) == 0) != (int(state.last_homework_day) == 0) or (int(state.prepared) == 0) != (int(state.last_prepared_homework_day) == 0):
		return "Save contains inconsistent school activity dates."
	if int(state.last_attendance_day) > 0 and int(state.last_attendance_day) < int(state.get("first_class_day",state.enrolled_day)):
		return "Save contains attendance before classes began."
	if int(state.last_prepared_homework_day) > int(state.last_homework_day) or int(state.last_prepared_homework_day) > int(state.last_attendance_day):
		return "Save contains homework prepared after its lesson."
	for key: String in DATES:
		if int(state[key]) > 0 and (int(state[key]) < int(state.enrolled_day) or not weekday(int(state[key]))):
			return "Save contains a school activity outside its enrollment or weekday calendar."
	if stage == "unknown" and not state.records.is_empty(): return "Save contains school history for an unspecified age."
	var seen: Array[String] = []
	var previous_day: int = 0
	for record: Variant in state.records:
		var error: String = _validate_record(record,day)
		if not error.is_empty(): return error
		var record_stage: String = str(record.stage)
		if record_stage in seen or (record_stage == "child" and "teen" in seen) or int(record.day) < previous_day:
			return "Save contains duplicate or unordered graduation records."
		if STAGES.find(record_stage) >= STAGES.find(stage): return "Save contains graduation from a future age stage."
		seen.append(record_stage)
		previous_day = int(record.day)
	if stage in SCHOOL_STAGES and previous_day > int(state.enrolled_day):
		return "Save contains school enrollment before its previous completion."
	return ""


static func _availability(state: Dictionary, day: int, minutes: float, action_id: String, completion: bool) -> String:
	if action_id not in ["school","homework"]: return "That school activity does not exist."
	if not weekday(day): return "School and homework are available Monday through Friday."
	if action_id == "school":
		if day < int(state.get("first_class_day",state.enrolled_day)): return "Classes begin on the next school day."
		if int(state.last_attendance_day) == day: return "School has already been attended today."
		# A class begun by 14:00 can finish at 17:00; the queued action owns duration.
		if minutes < 480.0 or minutes > (1020.0 if completion else 840.0):
			return "Start school between 08:00 and 14:00 on weekdays."
	else:
		if int(state.last_homework_day) == day: return "Today's homework is already complete."
		if not completion and minutes > 1380.0: return "Start homework by 23:00 so it finishes today."
	return ""


static func _term_record(state: Dictionary, day: int) -> Dictionary:
	var scheduled: int = int(state.attended)+int(state.missed)
	var attendance: float = float(state.attended)/float(scheduled) if scheduled > 0 else 0.0
	var passed: bool = int(state.attended) >= 3 and attendance >= .70 and score(state) >= 55.0
	return {"stage":str(state.stage),"enrolled_day":int(state.enrolled_day),"first_class_day":int(state.get("first_class_day",state.enrolled_day)),"day":day,
		"attended":int(state.attended),"missed":int(state.missed),"homework":int(state.homework),"prepared":int(state.prepared),
		"grade":grade(state),"score":score(state),"outcome":("completed" if str(state.stage) == "child" else "graduated") if passed else "unfinished"}


static func _validate_record(record: Variant, day: int) -> String:
	if not record is Dictionary or str(record.get("stage","")) not in SCHOOL_STAGES:
		return "Save contains an invalid graduation record."
	if not _integer(record.get("day"),1,day) or not _integer(record.get("enrolled_day"),1,int(record.day)):
		return "Save contains an invalid graduation date."
	for key: String in COUNTERS:
		if not _integer(record.get(key),0,DAY_LIMIT): return "Save contains invalid graduation totals."
	if not _integer(record.get("first_class_day",record.enrolled_day),int(record.enrolled_day),int(record.enrolled_day)+1): return "Save contains an invalid first school day in a term."
	var available: int = _weekdays_between(int(record.get("first_class_day",record.enrolled_day)),int(record.day)+1)
	var assignment_days: int = _weekdays_between(int(record.enrolled_day),int(record.day)+1)
	if int(record.attended)+int(record.missed) > available or int(record.homework) > assignment_days or int(record.prepared) > mini(int(record.attended),int(record.homework)):
		return "Save contains inconsistent graduation totals."
	if not (record.get("score") is float or record.get("score") is int) or not is_finite(float(record.score)) or float(record.score) != score(record) or str(record.get("grade","")) != grade(record):
		return "Save contains an inconsistent graduation grade."
	var expected: Dictionary = _term_record(record,int(record.day))
	if str(record.get("outcome","")) != str(expected.outcome): return "Save contains an unearned graduation."
	return ""


static func _allowed_transition(previous: String, current: String) -> bool:
	return ["child>teen","teen>young_adult","young_adult>adult","adult>elder"].has(previous+">"+current)


static func _normalized(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	result["first_class_day"] = int(result.get("first_class_day",result.enrolled_day))
	for key: String in ["version","last_day","enrolled_day"]+COUNTERS+DATES:
		result[key] = int(result[key])
	for record: Dictionary in result.records:
		record["first_class_day"] = int(record.get("first_class_day",record.enrolled_day))
		for key: String in ["enrolled_day","day"]+COUNTERS:
			record[key] = int(record[key])
	return result


static func _weekdays_between(first: int, end: int) -> int:
	# Count [first,end) arithmetically, keeping large save catch-up bounded.
	var length: int = maxi(0,end-first)
	var result: int = (length/7)*5
	for offset: int in range(length%7):
		if weekday(first+offset): result += 1
	return result


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message,"effects":{},"notices":[]}
