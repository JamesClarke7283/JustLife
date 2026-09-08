extends "res://tests/test_school_day.gd"
## Controlled schedule/save adversaries. Rendered career UI proves navigation.
func targets() -> Array:
	var result:Array=super.targets()
	result.append({"id":"shower","kind":"shower","position":Vector3(5,.16,2)})
	result.append({"id":"maya","kind":"neighbor","position":Vector3(1,.16,5)})
	return result

func run() -> void:
	for stage:String in ["young_adult","adult","elder"]:
		var worker:LifeSim=setup(stage,540.0)
		check(worker.queue_action("career_day","lot_exit"),stage+": weekday work queues a real exit.")
		check(not worker.is_away() and worker.career.worked_day==0,"Walking alone earns no pay or absence.")
		observe(worker);worker.begin_current_action()
		check(worker.is_away() and worker.away_state.activity=="career","Actual arrival starts work absence.")
		var before:int=worker.funds
		advance(worker,77.125)
		var saved:Dictionary=snapshot(worker)
		var resumed:LifeSim=setup(stage)
		check(resumed.restore_state(saved).ok,"Partially worked day restores through JSON.")
		advance(worker,402.875);advance(resumed,402.875)
		for need:String in LifeSim.NEED_NAMES:check(is_equal_approx(worker.needs[need],resumed.needs[need]),"Resumed work preserves proportional "+need+" care.")
		check(worker.away_state.completed and worker.away_state.phase=="returning" and worker.career.worked_day==1,"17:00 earns attendance before the route home.")
		check(worker.funds==before+180 and resumed.funds==worker.funds,"A full workday pays its salary once across restart.")
		check(worker.career.schedule.attended==1 and worker.skills.creativity.xp>0,"Ordinary work advances actual career skill and attendance.")
		var returning:Dictionary=snapshot(worker)
		check(setup(stage).restore_state(returning).ok,"Paid returning work state is valid before walking home.")
		worker._tick_away(1.0);worker.complete_away_return();worker.complete_away_return()
		check(worker.funds==before+180 and not worker.is_away(),"Repeated end/arrival callbacks cannot pay twice.")
		check(not worker.queue_action("job","desk") and not worker.queue_action("career_day","lot_exit"),"A paid day cannot be repeated at home or off lot.")
	for departure:float in [540.0,600.125,659.375,719.999,720.0]:
		var late:LifeSim=setup("adult",departure)
		late.queue_action("career_day","lot_exit");late.begin_current_action()
		var before:int=late.funds
		advance(late,LifeCareerSchedule.END-departure)
		check(late.funds-before==roundi(180.0*(1020.0-departure)/480.0),"Late salary reflects actual time at work: "+str(departure))
		check(is_equal_approx(late.career.schedule.late_minutes,maxf(0.0,departure-600.0)),"Exact lateness is recorded at "+str(departure))
		check(setup("adult").restore_state(snapshot(late)).ok,"Fractional paid return remains loadable at "+str(departure))
	var early:LifeSim=setup("adult",600.0);early.queue_action("career_day","lot_exit");early.begin_current_action()
	advance(early,20.0);var before:int=early.funds
	check(early.request_return_home() and not early.away_state.completed,"Player can return early without earning a full shift.")
	check(setup("adult").restore_state(snapshot(early)).ok,"Early return is persisted without a completion reward.")
	early.complete_away_return()
	check(early.funds==before and early.career.worked_day==0 and early._autonomy_duty_id().is_empty(),"Early return does not pay or immediately resend the worker.")
	early.autonomy=false;early.career.performance=50
	advance(early,1440.0-early.minutes)
	check(early.career.schedule.missed==1 and early.career.performance==42.0,"A missed weekday lowers career performance once.")
	var saved:Dictionary=snapshot(early);check(setup("adult").restore_state(saved).ok,"Missed-work consequence survives a day-boundary save.")
	var explicit:LifeSim=setup("adult",600.0)
	explicit.queue_action("read","shelf");var queue:Array=explicit.action_queue.duplicate(true);explicit._choose_autonomous_action()
	check(explicit.action_queue==queue,"Explicit player plans override autonomous workplace departure.")
	for need:String in ["hunger","energy","bladder","hygiene","fun","social"]:
		var urgent:LifeSim=setup("adult",600.0);urgent.needs[need]=1.0
		check(str(urgent._autonomous_choice().get("id",""))!="career_day","Critical "+need+" does not send an unprepared worker.")
	for time:float in [539.999,720.001,1020.0]:
		check(not setup("adult",time).queue_action("career_day","lot_exit"),"Unavailable work clock rejects: "+str(time))
	for date:int in [6,7]:check(not setup("adult",600,date).queue_action("career_day","lot_exit"),"Weekend leaves ordinary workers at home.")
	check(not setup("teen",600).queue_action("career_day","lot_exit"),"School-age teens cannot enter the adult workplace.")
	var corrupt_source:LifeSim=setup("adult",650.125);corrupt_source.queue_action("career_day","lot_exit");corrupt_source.begin_current_action();advance(corrupt_source,50)
	for key:String in ["activity","return_minutes","departure_minutes","salary","career_track","completed","ended_at"]:
		var corrupt:Dictionary=snapshot(corrupt_source)
		match key:
			"activity":corrupt.away_state.activity="holiday"
			"return_minutes":corrupt.away_state.return_minutes=900
			"departure_minutes":corrupt.away_state.departure_minutes=100
			"salary":corrupt.away_state.salary=99999
			"career_track":corrupt.away_state.career_track="culinary"
			"completed":corrupt.away_state.completed=true
			"ended_at":corrupt.away_state.ended_at=900
		var receiver:LifeSim=setup("adult");var prior:Dictionary=receiver.get_state()
		check(not receiver.restore_state(corrupt).ok and receiver.get_state()==prior,"Malformed work "+key+" rejects atomically.")
	check(observer_errors.is_empty(),"Every work callback exposes serializable committed state: "+str(observer_errors))
	for sim:LifeSim in owned:sim.free()
	print("CAREER_DAY %d checks, %d failures; %d callback snapshots"%[checks,failures.size(),observer_count])
	quit(0 if failures.is_empty() else 1)
