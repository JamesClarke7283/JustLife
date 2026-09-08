extends RefCounted
class_name LifeCareerSchedule
## Original weekday schedule for ordinary off-lot careers. Home shifts remain
## explicit alternatives and share the same daily attendance/reward marker.
const OPEN:float=540.0
const ON_TIME:float=600.0
const CLOSE:float=720.0
const END:float=1020.0
const LENGTH:float=480.0

static func fresh(day:int,first_day:int=-1) -> Dictionary:
	return {"version":1,"first_day":day if first_day<0 else first_day,"last_day":day,"attended":0,"missed":0,"late_minutes":0.0,"last_attendance_day":0}

static func advance(previous:Dictionary,day:int,worked_day:int,eligible:bool) -> Dictionary:
	var state:Dictionary=previous.duplicate(true)
	var missed:int=0
	if eligible:
		for date:int in range(maxi(int(state.last_day),int(state.first_day)),day):
			if LifeEducation.weekday(date) and date!=worked_day:missed+=1
	state.last_day=day
	state.missed=int(state.missed)+missed
	return {"state":state,"missed":missed}

static func attend(previous:Dictionary,day:int,late:float) -> Dictionary:
	var state:Dictionary=previous.duplicate(true)
	if int(state.last_attendance_day)==day:return state
	state.attended=int(state.attended)+1
	state.last_attendance_day=day
	state.late_minutes=float(state.late_minutes)+late
	return state

static func validate(value:Variant,day:int,worked_day:int) -> String:
	if not value is Dictionary:return "Save contains an invalid career schedule."
	for key:String in ["version","first_day","last_day","attended","missed","last_attendance_day"]:
		var number:Variant=value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number)!=floorf(float(number)) or float(number)<0.0 or float(number)>1000001.0:return "Save contains invalid career attendance counters."
	if int(value.version)!=1 or int(value.first_day)<1 or int(value.first_day)>day+1 or int(value.last_day)!=day:return "Save contains an invalid career calendar."
	if int(value.missed)>LifeEducation._weekdays_between(int(value.first_day),day):return "Save contains absence before an elapsed workday."
	if int(value.attended)+int(value.missed)>maxi(0,day-int(value.first_day)+1):return "Save contains impossible career attendance totals."
	if int(value.last_attendance_day)>day or (int(value.attended)==0)!=(int(value.last_attendance_day)==0):return "Save contains an invalid paid career date."
	if int(value.last_attendance_day)>0 and (int(value.last_attendance_day)<int(value.first_day) or int(value.last_attendance_day)!=worked_day):return "Save contradicts its paid career attendance."
	var late:Variant=value.get("late_minutes")
	if not (late is int or late is float) or not is_finite(float(late)) or float(late)<0.0 or float(late)>float(value.attended)*(CLOSE-ON_TIME):return "Save contains invalid late-work time."
	return ""
