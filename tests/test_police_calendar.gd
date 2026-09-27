extends SceneTree
var checks:int=0
var failures:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func work(entries:Array,date:int) -> Array:
	return entries.filter(func(e:Dictionary)->bool:return str(e.kind)=="work" and int(e.day)==date)
func run() -> void:
	var household:=LifeHousehold.new();root.add_child(household)
	household.new_household([{"name":"Night officer","age_stage":"young_adult"},{"name":"Pupil","age_stage":"child"}])
	var officer:LifeSim=household.members[0].sim
	for member:Dictionary in household.members:member.sim.set_aging("normal",false)
	officer.choose_career("police");officer.choose_police_shift("night")
	var before:Dictionary=household.get_state().duplicate(true)
	var agenda:Array=LifeCalendar.entries(household,1)
	var duties:Array=agenda.filter(func(e:Dictionary)->bool:return e.kind=="work")
	check(duties.size()==7,"Police agenda includes both weekend shifts")
	check(agenda.filter(func(e:Dictionary)->bool:return e.kind=="school").size()==5,"Police calendar does not change weekday-only schooling")
	check(duties.all(func(e:Dictionary)->bool:return e.minutes==1020.0 and e.end==1980.0),"Night duty runs 17:00 through next-day 09:00")
	check(LifeCalendar.entry_clock_text(duties[0])=="17:00–09:00\nnext day","Overnight agenda shows a real end clock and explicit next-day label")
	check(str(duties[0].detail).contains("ℒ150") and not str(duties[0].detail).contains("home shift"),"Night agenda states the correct pay and station assignment")
	check(household.get_state()==before,"Reading police calendar does not change household state")
	officer.minutes=1020
	check(work(LifeCalendar.entries(household,1),1)[0].status=="Due today","Night shift is due at 17:00, not marked absent after noon")
	officer.minutes=1201
	check(work(LifeCalendar.entries(household,1),1)[0].status=="Attendance not completed","Closed night departure window is marked correctly")
	officer.day=2;officer.minutes=120
	officer.away_state={"activity":"career","phase":"away","departure_day":1,"departure_minutes":1020.0,"return_day":2,"return_minutes":540.0}
	officer.action_queue=[{"id":"career_day","phase":"active","started_day":1}]
	var today:Array=work(LifeCalendar.entries(household,2),2)
	check(today.size()==2,"After midnight agenda separates current overnight duty and next evening's shift")
	check(today[0].status=="Away" and bool(today[0].continuation) and today[0].end==540.0,"Ongoing night shift remains visible until its return")
	check(today[1].status=="Later today","Working last night's shift does not mark tonight's shift as already active")
	officer.away_state.phase="returning";officer.minutes=540
	check(work(LifeCalendar.entries(household,2),2)[0].status=="Returning home","Night return has an explicit ongoing journey status")
	officer.away_state.clear();officer.action_queue.clear();officer.career.worked_day=1
	check(work(LifeCalendar.entries(household,2),2).size()==1,"Completed return does not leave a stale overnight entry")
	officer.choose_police_shift("day")
	var day_entry:Dictionary=work(LifeCalendar.entries(household,2),2)[0]
	check(day_entry.minutes==540.0 and day_entry.end==1020.0 and LifeCalendar.entry_clock_text(day_entry)=="09:00–17:00","Switching to day work immediately updates agenda clocks")
	household.free()
	print("POLICE_CALENDAR %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
