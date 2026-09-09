extends RefCounted
class_name LifeCalendar
## Read-only household agenda. Each forecast ends at its next age transition.

static func birthday_time(person:LifeSim) -> float:
	var stage:String=LifeLifecycle.stage_for(person.character)
	if not bool(person.lifecycle.auto_age) or LifeLifecycle.next_stage(stage).is_empty():return INF
	var at:float=float(person.day-1)*1440.0+person.minutes+maxf(0.0,1.0-float(person.lifecycle.progress))*LifeLifecycle.duration(stage,str(person.lifecycle.lifespan))*1440.0
	# Fractional age progress can put an exact minute a few nanoseconds early.
	return round(at) if absf(at-round(at))<.000001 else at

static func clock_text(minutes:float) -> String:
	var whole:int=clampi(int(floor(minutes)),0,1439)
	return "%02d:%02d" % [whole/60,whole%60]

static func _status(person:LifeSim,kind:String,date:int) -> String:
	if date!=person.day:return "Upcoming"
	var activity:String="school" if kind=="school" else "career"
	if not person.away_state.is_empty() and str(person.away_state.get("activity",""))==activity:
		return "Returning home" if str(person.away_state.phase)=="returning" else "Away"
	if (kind=="school" and int(person.education.last_attendance_day)==date) or (kind=="work" and int(person.career.worked_day)==date):return "Completed"
	for action:Dictionary in person.action_queue:
		if str(action.id) not in (["school","school_day"] if kind=="school" else ["job","career_day"]):continue
		if str(action.phase)=="active":return "In progress"
		return "In the queue"
	if person.minutes>720.0:return "Attendance not completed"
	return "Due today" if person.minutes>=(480.0 if kind=="school" else LifeCareerSchedule.OPEN) else "Later today"

static func entries(household:LifeHousehold,first_day:int,count:int=7) -> Array:
	var result:Array=[]
	var last_day:int=mini(1000000,first_day+clampi(count,1,14)-1)
	for member:Dictionary in household.members:
		var person:LifeSim=member.sim
		var stage:String=LifeLifecycle.stage_for(person.character)
		var birthday:float=birthday_time(person)
		if is_finite(birthday):
			var birthday_day:int=int(floor(birthday/1440.0))+1
			if birthday_day>=first_day and birthday_day<=last_day:
				result.append({"kind":"birthday","member_id":str(member.id),"name":str(person.character.name),"day":birthday_day,
					"minutes":fmod(birthday,1440.0),"end":fmod(birthday,1440.0),"title":"Birthday · "+str(LifeLifecycle.LABELS[LifeLifecycle.next_stage(stage)]),
					"status":"Expected","detail":"An automatic birthday with your current aging settings. School and work plans refresh after this age change."})
		for date:int in range(maxi(first_day,person.day),last_day+1):
			if not LifeEducation.weekday(date):continue
			var school:bool=stage in LifeEducation.SCHOOL_STAGES
			if not school and str(person.character.life_stage)!="adult":continue
			var first:int=int(person.education.first_class_day) if school else int(person.career.get("schedule",LifeCareerSchedule.fresh(person.day)).first_day)
			if date<first:continue
			var start:float=480.0 if school else LifeCareerSchedule.OPEN
			var end:float=900.0 if school else LifeCareerSchedule.END
			var midnight:float=float(date-1)*1440.0
			if midnight+start>=birthday:continue
			var title:String=("Willow School" if stage=="child" else "Morrow Secondary") if school else str(person.career.title)
			var detail:String="Leave 08:00–12:00; arrive by 09:00. Online classes share today's attendance." if school else "Leave 09:00–12:00; arrive by 10:00. A home shift shares today's paid attendance."
			if midnight+end>=birthday:
				end=maxf(start,birthday-midnight)
				detail="A birthday may end this day early. Plans refresh after the age change."
			result.append({"kind":"school" if school else "work","member_id":str(member.id),"name":str(person.character.name),"day":date,
				"minutes":start,"end":end,"title":title,"status":_status(person,"school" if school else "work",date),"detail":detail})
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if int(a.day)!=int(b.day):return int(a.day)<int(b.day)
		if float(a.minutes)!=float(b.minutes):return float(a.minutes)<float(b.minutes)
		if str(a.name)!=str(b.name):return str(a.name).naturalnocasecmp_to(str(b.name))<0
		return str(a.member_id)<str(b.member_id))
	return result
