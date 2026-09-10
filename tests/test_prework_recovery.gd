extends "res://tests/test_autonomy_policy.gd"
## Component policy and ownership checks. Arrival is supplied; this is not commute proof.

func furnished(stage:String="adult",clock:float=488.4,date:int=1) -> LifeSim:
	var sim:LifeSim=setup(stage,clock,date)
	var all:Array=targets()
	all.append({"id":"easel","kind":"easel","position":Vector3(5,.16,5)})
	all.append({"id":"tv","kind":"tv","position":Vector3(6,.16,5)})
	sim.register_targets(all)
	return sim

func run() -> void:
	for stage:String in ["child","teen","young_adult","adult"]:
		var sim:LifeSim=furnished(stage)
		sim.needs.fun=6.42;sim.needs.energy=39.42;sim.needs.bladder=16.78
		var before:Dictionary=sim.get_state().duplicate(true)
		var choice:Dictionary=sim._autonomous_choice()
		check(str(choice.get("id",""))=="relax",stage+": critical boredom before a scheduled day chooses short recovery that also restores energy.")
		check(sim.get_state()==before,stage+": selecting pre-work recovery does not mutate needs, funds, clock or queues.")
		check(str(sim._autonomous_choice(["sofa"]).get("id",""))=="read",stage+": excluding the seat falls back to available shorter reading.")
		check(str(sim._autonomous_choice(["sofa","shelf"]).get("id",""))=="watch",stage+": unavailable reading falls back to an actual television.")
		check(str(sim._autonomous_choice(["lot_exit"]).get("id",""))=="paint",stage+": excluding the duty destination keeps ordinary leisure preferences.")
	var free_day:LifeSim=furnished("adult",488.4,6)
	free_day.needs.fun=6.0
	check(str(free_day._autonomous_choice().get("id",""))=="paint","Weekend leisure retains the usual painting preference.")
	var early:LifeSim=furnished("adult",359.999)
	early.needs.fun=6.0
	check(str(early._autonomous_choice().get("id",""))=="paint","Before the preparation window, ordinary hobbies remain available.")
	early.minutes=360.0
	check(str(early._autonomous_choice().get("id",""))=="relax","The actual preparation-window boundary selects shorter leisure.")
	var late:LifeSim=furnished("adult",720.001)
	late.needs.fun=6.0
	check(str(late._autonomous_choice().get("id",""))=="paint","After the departure deadline, the expired duty does not constrain leisure.")
	var deferred:LifeSim=furnished()
	deferred.needs.fun=6.0;deferred.defer_autonomous_responsibility("career_day",120.0)
	check(str(deferred._autonomous_choice().get("id",""))=="paint","A player-deferred shift does not keep the preparation leisure preference.")
	var bookworm:LifeSim=furnished("adult",800.0)
	bookworm.character.traits=["Bookworm"];bookworm.needs.fun=6.0
	check(str(bookworm._autonomous_choice().get("id",""))=="read","Bookworm leisure outside preparation remains reading.")
	bookworm.minutes=488.4
	check(str(bookworm._autonomous_choice().get("id",""))=="read","Bookworm keeps reading as the first fun choice during work preparation.")
	var fallback:LifeSim=furnished()
	fallback.needs.fun=6.0
	check(str(fallback._autonomous_choice(["sofa","shelf","tv"]).get("id",""))=="paint","When every short leisure target is excluded, the valid canvas remains available.")
	fallback.needs.bladder=1.0
	check(str(fallback._autonomous_choice().get("id",""))=="toilet","More critical bladder recovery still precedes the changed fun recommendation.")
	var moderate:LifeSim=furnished("adult",400.0)
	moderate.needs.fun=40.0
	check(str(moderate._autonomous_choice().get("id",""))=="relax","Normal boredom before opening also avoids a long paid canvas.")
	moderate.minutes=540.0;moderate.needs.fun=17.0
	check(str(moderate._autonomous_choice().get("id",""))=="relax","At 09:00 moderate boredom still takes the forty-minute break that ends before the 10:00 deadline.")
	moderate.minutes=570.0
	check(str(moderate._autonomous_choice().get("id",""))=="career_day","Once no pastime ends in time for an on-time arrival, moderate boredom yields to the open shift.")
	moderate.needs.fun=11.0
	check(str(moderate._autonomous_choice().get("id",""))=="relax","Critical boredom past the deadline still takes the shortest available pastime.")
	# A late riser: the shift is due, Fun 46 projects under 20 by the evening,
	# and a forty-minute relax at 09:05 still reaches the lot exit by 10:00.
	var riser:LifeSim=furnished("adult",545.0)
	riser.character.traits=["Creative"];riser.needs.fun=46.0
	check(riser._autonomy_projection_need("career_day",60.0,true)=="fun","A Creative late riser at Fun 46 projects evening boredom across the shift.")
	check(str(riser._autonomous_choice().get("id",""))=="relax","At 09:05 the due shift waits for a brief relax because arrival stays on time.")
	riser._choose_autonomous_action();complete_front(riser)
	check(is_equal_approx(riser.minutes,585.0) and riser.needs.fun>60.0,"The relax ends at 09:45 with Fun restored above 60.")
	riser._choose_autonomous_action()
	check(current_id(riser)=="career_day","After the break the shift is the next autonomous choice.")
	complete_front(riser)
	check(riser.career.schedule.attended==1 and is_zero_approx(float(riser.career.schedule.late_minutes)),"The late riser still arrives on time: attended %d, late %.0f." % [int(riser.career.schedule.attended),float(riser.career.schedule.late_minutes)])
	check(riser.needs.fun>=20.0,"The shift ends with Fun at or above 20 (%.1f) instead of coming home bored." % float(riser.needs.fun))
	var riser_late:LifeSim=furnished("adult",565.0)
	riser_late.character.traits=["Creative"];riser_late.needs.fun=46.0
	check(str(riser_late._autonomous_choice().get("id",""))=="career_day","At 09:25 no pastime ends in time, so the shift leaves at once.")
	# The pastime rotation cannot make the pre-work break long enough to be late:
	# with relax, read and watch as the last three pastimes, 08:40 offers the
	# yoga mat rather than a ninety-minute canvas.
	var rotated:LifeSim=furnished("adult",520.0)
	rotated.register_targets(rotated._targets+[{"id":"mat","kind":"yoga_mat","position":Vector3(7,.16,5)},{"id":"hearth","kind":"fireplace","position":Vector3(8,.16,5)}])
	rotated.character.traits=["Creative"];rotated.needs.fun=46.0
	rotated._leisure_history.assign(["watch","read","relax"])
	check(str(rotated._autonomous_choice().get("id",""))=="stretch","With relax, read and watch in the history, the 08:40 break is a thirty-minute stretch, not a canvas.")
	rotated._choose_autonomous_action();complete_front(rotated)
	rotated._choose_autonomous_action()
	check(current_id(rotated)=="career_day","The stretch ends at 09:10 and the shift follows.")
	complete_front(rotated)
	check(rotated.career.schedule.attended==1 and is_zero_approx(float(rotated.career.schedule.late_minutes)),"A history-laden 08:40 break arrives on time: late %.0f." % float(rotated.career.schedule.late_minutes))
	var rotated_plain:LifeSim=furnished("adult",520.0)
	rotated_plain.character.traits=["Creative"];rotated_plain.needs.fun=46.0
	rotated_plain._leisure_history.assign(["watch","read","relax"])
	check(str(rotated_plain._autonomous_choice().get("id",""))=="relax","Without a mat or hearth the same morning repeats the shortest fitting pastime rather than painting.")
	var rotated_early:LifeSim=furnished("adult",480.0)
	rotated_early.character.traits=["Creative"];rotated_early.needs.fun=46.0
	rotated_early._leisure_history.assign(["watch","read","relax"])
	check(str(rotated_early._autonomous_choice(["sofa","shelf","tv"]).get("id",""))=="paint","At 08:00 the canvas still ends before the deadline, so it stays on offer.")
	rotated_early.minutes=520.0
	check(str(rotated_early._autonomous_choice(["sofa","shelf","tv"]).get("id",""))!="paint","At 08:40 the canvas would end after the deadline, so moderate boredom no longer starts one.")
	rotated_early.needs.fun=6.0
	check(str(rotated_early._autonomous_choice(["sofa","shelf","tv"]).get("id",""))=="paint","Critical boredom with only the easel left still paints, accepting a late arrival.")
	var kept:LifeSim=furnished("adult",520.0)
	kept.needs.fun=6.0;kept.queue_action("relax","sofa");kept.get_current_action().autonomous=true;kept.begin_current_action();advance(kept,5.0)
	kept.needs.fun=60.0;kept.minutes=545.0
	kept._reconsider_active_autonomy()
	check(current_id(kept)=="relax","A relax that still ends before the deadline is not cut short when the shift opens.")
	kept.minutes=575.0;kept._reconsider_active_autonomy()
	check(current_id(kept)=="career_day","Once the remaining relax would make the Lifelet late, the open shift takes over.")
	var homework:LifeSim=furnished("teen",1000.0)
	homework.education.last_attendance_day=1;homework.needs.fun=21.0
	check(homework._autonomy_duty_id()=="homework" and homework._autonomy_projection_need("homework")=="fun","The homework control needs a fun break but has no upcoming school departure.")
	check(str(homework._autonomous_choice().get("id",""))=="paint","An afternoon homework break retains ordinary hobby choices.")
	var paid:LifeSim=furnished()
	paid.needs.fun=6.0
	check(paid.queue_action("paint","easel"),"The player can still choose a full canvas before work.")
	paid.get_current_action().autonomous=true;paid.begin_current_action();advance(paid,5.0)
	var paid_before:Dictionary=paid.get_state().duplicate(true)
	paid._reconsider_active_autonomy()
	check(paid.get_state()==paid_before and paid.funds==2480,"An already-paid canvas retains progress and its single charge.")
	check(paid.queue_action("read","shelf"),"A later explicit instruction can follow the canvas.")
	var queue_before:Array=paid.action_queue.duplicate(true)
	paid.needs.bladder=1.0;paid._reconsider_active_autonomy()
	check(paid.action_queue==queue_before,"Urgent reconsideration preserves a later player instruction and the active canvas.")
	var rest:LifeSim=furnished()
	rest.needs.fun=6.42;rest.needs.energy=39.42;rest.needs.bladder=16.78
	rest._choose_autonomous_action()
	check(current_id(rest)=="relax" and rest.get_current_action().phase=="approach","The chosen short recovery requests a real arrival before earning needs.")
	var funds:int=rest.funds
	rest.begin_current_action();advance(rest,40.0)
	check(rest.needs.fun>25.0 and rest.needs.energy>45.0 and rest.funds==funds,"Forty actual minutes complete useful fun and energy recovery without a charge.")
	check(rest.career.worked_day==0 and rest.career.schedule.attended==0,"Recovery cannot fabricate attendance or pay a shift.")
	for node:Node in owned:node.free()
	print("PREWORK_RECOVERY %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
