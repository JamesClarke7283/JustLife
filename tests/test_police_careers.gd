extends "res://tests/test_school_day.gd"
## Police pay, midnight attendance, restart and the physical crime handoff.
func run() -> void:
	for track:String in ["police","investigator","sergeant"]:
		for shift:String in ["day","night"]:
			var sim:LifeSim=setup("adult",500.0,5)
			sim.autonomy=false
			sim.skills.logic.level=10
			check(sim.choose_career(track),"Can join "+track)
			check(bool(sim.choose_police_shift(shift).ok),"Can choose "+shift+" for "+track)
			var expected:int=(150 if shift=="night" else 100) if track=="police" else (200 if track=="investigator" else 300)
			check(sim.career_pay()==expected and int(sim.career.salary)==expected,"Exact pay for "+track+" "+shift)
			var changes:Array=[]
			sim.career_shift_changed.connect(func(event:Dictionary):changes.append(event.duplicate(true)))
			var pattern:Dictionary=LifeCareerSchedule.pattern(sim.career)
			sim.minutes=float(pattern.open)
			check(sim.queue_action("career_day","lot_exit"),"Can queue "+shift)
			observe(sim)
			sim.begin_current_action()
			check(not sim.choose_police_shift("day" if shift=="night" else "night").ok,"Cannot switch an active shift")
			var before:int=sim.funds
			advance(sim,440.0)
			check(sim.is_away() and not bool(sim.away_state.completed),"Shift stays active through its first 440 minutes")
			var saved:Dictionary=snapshot(sim)
			var resumed:LifeSim=setup("adult")
			var restored:Dictionary=resumed.restore_state(saved)
			check(restored.ok,"Active "+shift+" restores: "+str(restored))
			advance(sim,float(pattern.length)-440.0)
			advance(resumed,float(pattern.length)-440.0)
			check(sim.funds==before+expected and resumed.funds==sim.funds,"Completing shift pays exactly once, also after restart")
			check(sim.career.worked_day==5 and sim.career.schedule.attended==1 and sim.career.schedule.missed==0,"Attendance uses departure day across midnight")
			check(sim.day==(6 if shift=="night" else 5) and sim.minutes==float(pattern.end),"Shift completes at its actual return clock")
			check(changes.size()==2 and str(changes[0].event)=="started" and str(changes[1].event)=="finished","Active shift handover events fire once")
			check(setup("adult").restore_state(snapshot(sim)).ok,"Returning shift is saveable")
			var corrupt:Dictionary=snapshot(sim)
			corrupt.away_state.return_day+=1
			check(not setup("adult").restore_state(corrupt).ok,"Wrong overnight return day rejects")
			sim.complete_away_return()
			check(sim.funds==before+expected,"Arriving home does not pay again")
	var weekend:LifeSim=setup("adult",1020.0,6)
	weekend.skills.logic.level=10
	weekend.choose_career("police")
	weekend.choose_police_shift("night")
	check(weekend.queue_action("career_day","lot_exit"),"Police can cover weekend night shifts")
	var early:LifeSim=setup("adult",500.0)
	early.choose_career("police");early.choose_police_shift("night");early.minutes=1020.0
	early.queue_action("career_day","lot_exit");early.begin_current_action();advance(early,600.0)
	var unpaid_before:int=early.funds
	check(early.request_return_home() and not early.away_state.completed and early.funds==unpaid_before,"Early overnight return earns no full shift pay")
	check(setup("adult").restore_state(snapshot(early)).ok,"Early return after midnight remains saveable")
	early.complete_away_return();early.minutes=1020.0
	check(early._autonomy_duty_id()=="career_day","Returning early after midnight does not suppress the following night's shift")
	var attendance:Dictionary=LifeCareerSchedule.fresh(1)
	attendance=LifeCareerSchedule.advance(attendance,2,0,true,{"track":"police","shift":"day"}).state
	check(attendance.missed==1,"One skipped day shift is counted once")
	attendance=LifeCareerSchedule.advance(attendance,3,0,true,{"track":"police","shift":"night"}).state
	check(attendance.missed==1,"Changing to nights cannot count a prior absence twice")
	attendance=LifeCareerSchedule.attend(attendance,2,0.0)
	attendance=LifeCareerSchedule.attend(attendance,3,0.0)
	attendance=LifeCareerSchedule.advance(attendance,4,3,true,{"track":"police","shift":"day"}).state
	check(attendance.missed==1 and attendance.attended==2,"Changing back to days retains both completed shifts")
	var old:LifeSim=setup("adult",540.0)
	old.skills.logic.level=10;old.choose_career("police")
	old.queue_action("career_day","lot_exit");old.begin_current_action();advance(old,60.0)
	var old_save:Dictionary=snapshot(old)
	old_save.career.erase("shift");old_save.away_state.erase("shift")
	old_save.career.salary=240;old_save.away_state.salary=240;old_save.career.title="Police cadet"
	var migrated:LifeSim=setup("adult")
	check(migrated.restore_state(old_save).ok and migrated.career.salary==100,"Old police salary migrates together with active work snapshot")
	check(setup("adult").restore_state(snapshot(migrated)).ok,"Migrated active police shift can be saved again")
	var cover:LifeSim=setup("adult")
	var alarms:Array=[]
	var crimes:Array=[]
	cover.insurance_alarm_requested.connect(func():alarms.append(true))
	cover.robbery_requested.connect(func():crimes.append(true))
	var purse:int=cover.funds
	check(cover.buy_insurance().ok and cover.funds==purse-200 and alarms.size()==1,"Home insurance costs 200 and requests its included alarm")
	purse=cover.funds
	check(not cover.robbery_check(.01).ok and cover.robbery_check(.0099).ok,"One-percent chance boundary is exact")
	check(crimes.size()==1 and cover.funds==purse,"Burglary requests physical controller with no instant cash mutation")
	cover.mark_robbery_shaken()
	check(cover.moodlets.any(func(m:Dictionary)->bool:return str(m.label)=="Upset / Shaken" and float(m.remaining)==2880.0),"Robbery moodlet lasts two in-game days")
	check(setup("adult").restore_state(snapshot(cover)).ok,"Insurance and shaken moodlet survive save")
	check(observer_errors.is_empty(),"Every shift callback exposes valid state: "+str(observer_errors))
	for sim:LifeSim in owned:sim.free()
	print("POLICE_CAREERS %d checks, %d failures; %d callback snapshots"%[checks,failures.size(),observer_count])
	quit(0 if failures.is_empty() else 1)
