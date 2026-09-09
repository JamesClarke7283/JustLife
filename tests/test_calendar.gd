extends SceneTree
var checks:int=0
var failures:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func of_kind(entries:Array,kind:String,date:int=-1) -> Array:
	return entries.filter(func(entry:Dictionary)->bool:return str(entry.kind)==kind and (date<0 or int(entry.day)==date))
func run() -> void:
	var household:=LifeHousehold.new();root.add_child(household)
	household.new_household([{"name":"School child","age_stage":"child"},{"name":"Working adult","age_stage":"adult"}])
	var child:LifeSim=household.members[0].sim
	var adult:LifeSim=household.members[1].sim
	var before:Dictionary=household.get_state().duplicate(true)
	var agenda:Array=LifeCalendar.entries(household,1)
	check(of_kind(agenda,"school").size()==5 and of_kind(agenda,"work").size()==5,"A normal seven-day week has five school days and five workdays.")
	check(agenda.all(func(entry:Dictionary)->bool:return int(entry.day)<6),"Neither school nor work appears on Saturday or Sunday.")
	check(household.get_state()==before,"Reading all schedules preserves the full household state.")
	child.education.first_class_day=2
	check(of_kind(LifeCalendar.entries(household,1),"school",1).is_empty(),"An adopted child's settling-in day has no class.")
	child.education.first_class_day=1;child.education.last_attendance_day=1;adult.career.worked_day=1
	agenda=LifeCalendar.entries(household,1)
	check(of_kind(agenda,"school",1)[0].status=="Completed" and of_kind(agenda,"work",1)[0].status=="Completed","Home and off-lot completion markers both produce completed attendance.")
	child.education.last_attendance_day=0;adult.career.worked_day=0
	adult.away_state={"activity":"career","phase":"away"}
	check(of_kind(LifeCalendar.entries(household,1),"work",1)[0].status=="Away","A physically absent worker is visibly away.")
	adult.away_state.phase="returning"
	check(of_kind(LifeCalendar.entries(household,1),"work",1)[0].status=="Returning home","A return journey remains distinct from completed attendance.")
	adult.away_state.clear();adult.minutes=800.0
	check(of_kind(LifeCalendar.entries(household,1),"work",1)[0].status=="Attendance not completed","A closed departure window does not claim future attendance.")
	adult.minutes=480.0
	child.lifecycle.progress=1.0-960.0/(LifeLifecycle.duration("child","normal")*1440.0)
	var expected:float=LifeCalendar.birthday_time(child)
	check(absf(expected-1440.0)<.000001,"A birthday sixteen hours after Day 1 08:00 falls at Day 2 midnight.")
	agenda=LifeCalendar.entries(household,1)
	check(of_kind(agenda,"birthday").size()==1 and int(of_kind(agenda,"birthday")[0].day)==2,"The midnight birthday belongs to the following date.")
	check(of_kind(agenda,"school").size()==1,"Current school forecasting stops before the age transition.")
	child.lifecycle.auto_age=false
	check(of_kind(LifeCalendar.entries(household,1),"birthday").is_empty() and of_kind(LifeCalendar.entries(household,1),"school").size()==5,"Turning automatic aging off removes its prediction and restores the current routine.")
	child.lifecycle.auto_age=true;child.lifecycle.progress=1.0-120.0/(14.0*1440.0)
	check(absf(float(of_kind(LifeCalendar.entries(household,1),"school",1)[0].end)-600.0)<.000001,"A birthday during school marks an early end instead of promising a full day.")
	adult.lifecycle.progress=1.0-120.0/(42.0*1440.0)
	check(LifeCalendar.clock_text(fmod(LifeCalendar.birthday_time(adult),1440.0))=="10:00","Fractional adult age progress preserves the intended exact-minute birthday label.")
	child.lifecycle.progress=1.0-960.0/(14.0*1440.0)
	child.day=2;child.minutes=0;child._advance_age(960.0)
	check(child.character.age_stage=="teen" and of_kind(LifeCalendar.entries(household,2),"school",2)[0].title=="Morrow Secondary","After the real lifecycle transition, the calendar uses the new school stage.")
	adult.lifecycle.progress=.9999;adult.character.age_stage="elder"
	check(not is_finite(LifeCalendar.birthday_time(adult)),"Elders do not receive an unsupported extra birthday.")
	check(LifeCalendar.entries(household,1000000,14).all(func(entry:Dictionary)->bool:return int(entry.day)<=1000000),"The agenda respects the game's last valid date.")
	check(LifeCalendar.clock_text(480)=="08:00" and LifeCalendar.clock_text(1020)=="17:00","Agenda times use readable twenty-four-hour clock labels.")
	check(LifeCalendar.clock_text(1439.9)=="23:59","A late-night birthday is not labeled midnight on the wrong date.")
	household.free()
	print("Calendar data: %d checks, %d failures." % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
