extends SceneTree
## The child desk: a child can do homework, study logic, draw and colour there,
## and the menu says so. Pure simulation, no scene.
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label);print("FAIL ",label)

func make(stage:String,minutes:float,day_offset:int=0)->LifeSim:
	var sim:LifeSim=LifeSim.new()
	sim.new_household({"name":"Kid","age_stage":stage,"traits":[]})
	sim.autonomy=false;sim.household_bills_enabled=false;sim.set_aging("normal",false);sim.wants.clear()
	sim.minutes=minutes
	sim.day+=day_offset
	for need:String in LifeSim.NEED_NAMES:sim.needs[need]=50.0
	sim.register_targets([
		{"id":"cd","kind":"child_desk","position":Vector3(1,.16,1)},
		{"id":"desk1","kind":"desk","position":Vector3(3,.16,1)},
		{"id":"table1","kind":"dining","position":Vector3(5,.16,1)},
	])
	return sim

func by_id(sim:LifeSim,kind:String,target:String)->Dictionary:
	var out:Dictionary={}
	for entry:Dictionary in sim.get_actions_for(kind,target):out[str(entry.id)]=entry
	return out

## A weekday afternoon, so homework is open: find a school day by stepping forward.
func school_day(sim:LifeSim)->void:
	var guard:int=0
	while not LifeEducation.weekday(sim.day) and guard<8:
		sim.day+=1;guard+=1

func run_action(sim:LifeSim,id:String)->bool:
	if not sim.queue_action(id,"cd",Vector3(1,.16,1)):return false
	sim.begin_current_action()
	var duration:float=float(sim.get_current_action().duration)
	sim.tick(duration/LifeSim.GAME_MINUTES_PER_SECOND+.05)
	return sim.get_current_action().is_empty()

func run()->void:
	# ---- the menu a child sees
	var kid:LifeSim=make("child",1000.0)
	school_day(kid)
	var menu:Dictionary=by_id(kid,"child_desk","cd")
	check(menu.has("homework") and menu.has("child_desk_study") and menu.has("child_draw") and menu.has("child_colour"),"A child's desk offers homework, logic study, drawing and colouring")
	check(menu.get("child_desk_study",{}).get("label","")=="Study Logic","The logic entry says what it trains")
	check(menu.get("child_draw",{}).get("label","")=="Draw a picture" and menu.get("child_colour",{}).get("label","")=="Colour in","Drawing and colouring are named plainly")
	check(menu.get("homework",{}).get("label","")=="Do Homework","A child's homework reads as Do Homework")
	for id:String in ["homework","child_desk_study","child_draw","child_colour"]:
		check(bool(menu.get(id,{}).get("available",false)),"%s is available to a child at the desk on a school afternoon" % id)
	check(menu.has("read"),"A child can still read at the desk")

	# ---- every entry really runs to the end
	for id:String in ["child_desk_study","child_draw","child_colour"]:
		var sim:LifeSim=make("child",1000.0);school_day(sim)
		var fun_before:float=float(sim.needs.fun)
		var skill:String=str(sim._actions[id].skill)
		var xp_before:float=float(sim.skills[skill].xp)
		check(run_action(sim,id),"%s queues and finishes at the child desk" % id)
		check(float(sim.needs.fun)>fun_before,"%s makes the child happier" % id)
		check(float(sim.skills[skill].xp)>xp_before,"%s trains %s" % [id,skill])
		sim.free()
	var homework:LifeSim=make("child",1000.0);school_day(homework)
	var logic_before:float=float(homework.skills.logic.xp)
	check(run_action(homework,"homework"),"Homework queues and finishes at the child desk")
	check(int(homework.education.homework)==1,"Homework at the child desk counts as the day's homework")
	check(float(homework.skills.logic.xp)>logic_before,"Homework at the child desk trains logic")
	check(not bool(by_id(homework,"child_desk","cd").get("homework",{}).get("available",true)),"Once done, homework is shown but unavailable")
	check(str(by_id(homework,"child_desk","cd").get("homework",{}).get("unavailable_reason","")).length()>0,"An unavailable homework entry says why")

	# ---- on a weekend homework is still listed, with its own reason
	var weekend:LifeSim=make("child",1000.0)
	var guard:int=0
	while LifeEducation.weekday(weekend.day) and guard<8:
		weekend.day+=1;guard+=1
	var rest:Dictionary=by_id(weekend,"child_desk","cd")
	check(rest.has("homework") and rest.has("child_draw"),"The desk is not empty at the weekend")
	check(not bool(rest.get("homework",{}).get("available",true)) and not str(rest.homework.unavailable_reason).begins_with("Choose a desk"),"Weekend homework is refused for its day, not for the furniture")
	check(bool(rest.get("child_draw",{}).get("available",false)) and bool(rest.get("child_colour",{}).get("available",false)),"Drawing and colouring are open at the weekend")
	var morning:LifeSim=make("child",480.0);school_day(morning)
	check(bool(by_id(morning,"child_desk","cd").get("homework",{}).get("available",false)),"A school morning's homework is not hidden")

	# ---- a toddler may scribble; a teenager has no use for it
	var toddler:LifeSim=make("baby",1000.0)
	toddler.character["infant_stage"]="toddler"
	check(not LifeStagePolicy.BABY_ACTIONS.is_empty() and "child_draw" in LifeStagePolicy.BABY_ACTIONS,"A toddler's allowed activities include drawing")
	var teen:LifeSim=make("teen",1000.0);school_day(teen)
	var teen_menu:Dictionary=by_id(teen,"child_desk","cd")
	check(not teen_menu.has("homework"),"A teenager is not offered homework at a child's desk")
	for id:String in ["child_draw","child_colour","child_desk_study"]:
		check(not bool(teen_menu.get(id,{}).get("available",false)),"The child desk is not for a teenager (%s)" % id)
	check(teen_menu.has("child_desk_study") and "toddler or a child" in str(teen_menu.child_desk_study.unavailable_reason),"A teenager who clicks it is told whose desk it is")

	# ---- the ordinary study desk still has its online classes and skill study
	var at_desk:Dictionary=by_id(kid,"desk","desk1")
	var order:Array=kid.get_actions_for("desk","desk1").map(func(a:Dictionary)->String:return str(a.id))
	check(order.size()>0 and order[0]=="school","A child at the study desk still sees online classes first")
	check(at_desk.has("homework") and at_desk.has("study") and at_desk.has("study_hard"),"A child at the study desk keeps homework and skill study")
	check(at_desk.has("child_desk_study") and at_desk.has("read"),"A child at the study desk also gets the children's choices")
	check(by_id(kid,"dining","table1").has("child_desk_study"),"A child at the table can still study")

	# ---- the queue refuses nothing a menu offered
	for id:String in menu:
		var probe:LifeSim=make("child",1000.0);school_day(probe)
		var wanted:bool=bool(by_id(probe,"child_desk","cd").get(id,{}).get("available",false))
		var queued:bool=probe.queue_action(id,"cd",Vector3(1,.16,1))
		check(queued==wanted,"%s queues exactly when the menu says it is available" % id)
		probe.free()

	print("CHILD_DESK ",checks," checks, ",failures.size()," failures")
	for message:String in failures:print("  ",message)
	quit(0 if failures.is_empty() else 1)
