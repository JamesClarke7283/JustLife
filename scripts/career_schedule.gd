extends RefCounted
class_name LifeCareerSchedule
## Original weekday schedule for ordinary off-lot careers. Home shifts remain
## explicit alternatives and share the same daily attendance/reward marker.
const OPEN:float=540.0
const ON_TIME:float=600.0
const CLOSE:float=720.0
const END:float=1020.0
const LENGTH:float=480.0

## All police roles use the same two patterns; the night shift belongs to the
## date it starts and finishes at 09:00 the following morning.
static func pattern(career: Dictionary) -> Dictionary:
	if LifeCareers.is_police(str(career.get("track", ""))) and str(career.get("shift", "day")) == "night":
		return {"open":1020.0,"on_time":1080.0,"close":1200.0,"end":540.0,"length":960.0,"return_offset":1,"label":"Night shift · 17:00–09:00"}
	return {"open":OPEN,"on_time":ON_TIME,"close":CLOSE,"end":END,"length":LENGTH,"return_offset":0,"label":"Day shift · 09:00–17:00"}

static func workday(day: int, career: Dictionary) -> bool:
	return LifeCareers.is_police(str(career.get("track", ""))) or LifeEducation.weekday(day)

static func fresh(day:int,first_day:int=-1) -> Dictionary:
	return {"version":1,"first_day":day if first_day<0 else first_day,"last_day":day,"attended":0,"missed":0,"late_minutes":0.0,"last_attendance_day":0,"reviewed_day":day-1}

static func advance(previous:Dictionary,day:int,worked_day:int,eligible:bool,career:Dictionary={}) -> Dictionary:
	var state:Dictionary=previous.duplicate(true)
	var missed:int=0
	if eligible:
		var offset:int=int(pattern(career).return_offset)
		for date:int in range(maxi(int(state.get("reviewed_day",int(state.last_day)-1))+1,int(state.first_day)),day-offset):
			if workday(date,career) and date!=worked_day:missed+=1
	state.reviewed_day=maxi(int(state.get("reviewed_day",0)),day-int(pattern(career).return_offset)-1)
	state.last_day=day
	state.missed=int(state.missed)+missed
	return {"state":state,"missed":missed}

static func attend(previous:Dictionary,day:int,late:float) -> Dictionary:
	var state:Dictionary=previous.duplicate(true)
	if int(state.last_attendance_day)==day:return state
	state.attended=int(state.attended)+1
	state.last_attendance_day=day
	state.reviewed_day=maxi(int(state.get("reviewed_day",0)),day)
	state.late_minutes=float(state.late_minutes)+late
	return state

static func validate(value:Variant,day:int,worked_day:int,career:Dictionary={}) -> String:
	if not value is Dictionary:return "Save contains an invalid career schedule."
	for key:String in ["version","first_day","last_day","attended","missed","last_attendance_day"]:
		var number:Variant=value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number)!=floorf(float(number)) or float(number)<0.0 or float(number)>1000001.0:return "Save contains invalid career attendance counters."
	if int(value.version)!=1 or int(value.first_day)<1 or int(value.first_day)>day+1 or int(value.last_day)!=day:return "Save contains an invalid career calendar."
	var possible:int=maxi(0,day-int(value.first_day)) if LifeCareers.is_police(str(career.get("track",""))) else LifeEducation._weekdays_between(int(value.first_day),day)
	if int(value.missed)>possible:return "Save contains absence before an elapsed workday."
	if int(value.attended)+int(value.missed)>maxi(0,day-int(value.first_day)+1):return "Save contains impossible career attendance totals."
	if int(value.last_attendance_day)>day or (int(value.attended)==0)!=(int(value.last_attendance_day)==0):return "Save contains an invalid paid career date."
	if int(value.last_attendance_day)>0 and (int(value.last_attendance_day)<int(value.first_day) or int(value.last_attendance_day)!=worked_day):return "Save contradicts its paid career attendance."
	if value.has("reviewed_day") and (not LifeCareers.integer(value.reviewed_day,0,day) or int(value.reviewed_day)<int(value.last_attendance_day)):return "Save contains an invalid reviewed career date."
	var late:Variant=value.get("late_minutes")
	if not (late is int or late is float) or not is_finite(float(late)) or float(late)<0.0 or float(late)>float(value.attended)*(CLOSE-ON_TIME):return "Save contains invalid late-work time."
	return ""
