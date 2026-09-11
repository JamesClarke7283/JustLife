extends "res://tests/test_autonomy_week.gd"
## Rendered week with the second furnishing collection: the eight-member Reed
## family in Willow Cottage gains a treadmill, toy chest, piano, bathtub,
## stereo, yoga mat, mirror and armchair, builds a garden annex with a second
## bed, fridge and bookcase through the public build and purchase paths
## (JUSTLIFE_WEEK_ANNEX=0 keeps the advertised one-bed cottage), one adult is
## made Active, and the household runs autonomously for seven days (five
## weekdays and a weekend). Harness mutations are limited to the granted
## budget, those paths and that trait; needs, time and completions are
## observed, never edited.
const EXTRA_FURNISHINGS: Array = [["treadmill",4.75,-.5,90],["toybox",-1.7,1.2,0],["piano",-1.7,-1.4,0],["bathtub",2.4,-2.6,0],["stereo",-5.5,-2.5,90],["yoga_mat",-1.6,3.3,0],["mirror",-5.5,-1.0,90],["armchair",-1.4,3.2,0],["bed",6.4,6.9,0],["fridge",3.2,8.3,180],["desk",4.3,6.05,0]]
# A five-by-three-and-a-half garden annex holds the second bed, a second
# fridge and a second desk for homework, with its doorway on the west wall;
# the cottage's own rooms have no floor left for them. The north strip beside
# the bed stays open: it is the bed's route from the door.
const ANNEX: Dictionary = {"ax":2.6,"az":5.5,"bx":7.6,"bz":8.9,"door_center":6.3}
const NEW_ACTIONS: Array = ["jog","play_toys","play_piano","bath","dance","stretch","practice_speech","play_chess","play_games","warm_up","change_outfit"]

var result_printed:bool=false
func print_result(extra:String="") -> void:
	if result_printed:return
	result_printed=true
	print("CATALOGUE_WEEK_RESULT assertions=%d failures=%d resume=%s %s"%[assertions,failures.size(),str(resume_only),extra])

func _run()->void:
	# The reviewer's one silent exit(1) after the Live press had no RESULT
	# line; this watchdog marks any run that dies before its real result.
	var timeout_s:float=float(OS.get_environment("JUSTLIFE_WEEK_TIMEOUT")) if OS.has_environment("JUSTLIFE_WEEK_TIMEOUT") else 2400.0
	create_timer(timeout_s).timeout.connect(func():print_result("incomplete — exited before completion"))
	screenshot_dir="res://art/catalogue_week"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):
		member_completed.append(id+":"+str(action.id))
		if audit_enabled:audit.completions.append({"id":id,"day":app.household.day,"minutes":app.household.minutes,"action":action.id,"target":action.target_id,"autonomous":bool(action.get("autonomous",false))}))
	app.household.notice.connect(func(message:String):
		notices.append(message)
		if audit_enabled:audit.notices.append({"at":_now(),"message":message}))
	if resume_only:
		print_result();quit(0);return
	await _create_genealogy()
	var active_id:String=""
	for member:Dictionary in app.household.members:
		if str(member.sim.character.name)==FAMILY_NAMES[2]:
			member.sim.character.traits=["Active","Outgoing","Foodie"];active_id=str(member.id)
	check(not active_id.is_empty(),"One adult carries the Active trait for the treadmill preference.")
	app.household.set_funds(app.sim.funds+9000)
	await press("Build & buy")
	# The one-bed cottage cannot hold a second bed, so the family builds a
	# five-by-three-and-a-half annex in the garden with a doorway facing the path.
	# The garden annex with a second bed, fridge and bookcase is part of the
	# contract fixture; JUSTLIFE_WEEK_ANNEX=0 keeps the advertised one-bed
	# cottage for comparison. Iteration 58's annex runs froze because the
	# treadmill beside the bedroom doorway sealed the bedroom for room-aware
	# navigation once the annex converted the home; placement now refuses such
	# spots, the treadmill stands along the east wall, and crowded walkers yield
	# or squeeze past each other instead of standing still.
	var with_annex:bool=OS.get_environment("JUSTLIFE_WEEK_ANNEX")!="0"
	var purchases:Array=EXTRA_FURNISHINGS if with_annex else EXTRA_FURNISHINGS.filter(func(entry:Array)->bool:return str(entry[0]) not in ["bed","fridge","desk"])
	if with_annex:
		var tx=app.build_transactions
		var annex:Dictionary=tx.prepare({"op":"structure","tool":"room","level":0,"ax":ANNEX.ax,"az":ANNEX.az,"bx":ANNEX.bx,"bz":ANNEX.bz})
		check(bool(annex.ok) and bool(tx.commit(annex).ok),"A garden annex is built through the public build transaction (§%d)." % int(annex.get("cost",0)))
		var door_wall:Dictionary={}
		for wall:Dictionary in app.world.construction.building_state.walls:
			if is_equal_approx(float(wall.x),float(ANNEX.ax)) and is_equal_approx(float(wall.z),(float(ANNEX.az)+float(ANNEX.bz))*.5):door_wall=wall
		var door:Dictionary=tx.prepare({"op":"structure","tool":"door","level":0,"id":str(door_wall.get("id","")),"center":float(ANNEX.door_center)})
		check(bool(door.ok) and bool(tx.commit(door).ok),"The annex gets a doorway on its west wall (§%d)." % int(door.get("cost",0)))
	var placed:int=0
	for entry:Array in purchases:
		var before:int=app.world.items.size()
		app.on_placement(str(entry[0]),Vector3(float(entry[1]),0.16,float(entry[2])),float(entry[3]))
		if app.world.items.size()>before:placed+=1
		else:check(false,"Catalogue furnishing could not be placed in Willow Cottage: "+str(entry[0]))
	check(placed==purchases.size(),"All %d purchases land: eight second-collection furnishings%s." % [purchases.size(),", the annex bed, fridge and desk" if with_annex else ""])
	await press("Live")
	await screenshot("00_catalogue_cottage",false,false)
	if with_annex:
		# The annex projects under the HUD from the default view; frame it once.
		var saved_target:Vector3=app.world.camera_target;var saved_size:float=app.world.camera.size
		app.world.camera_target=Vector3(4.6,0.5,7.0);app.world.camera.size=12.0;app.world.update_camera()
		await frames(3)
		await screenshot("00_catalogue_annex",false,false)
		app.world.camera_target=saved_target;app.world.camera.size=saved_size;app.world.update_camera()
	for member:Dictionary in app.household.members:member.sim.autonomy=true
	var stages:Array=[]
	for member:Dictionary in app.household.members:
		stages.append(member.sim.character.age_stage)
		audit.members[str(member.id)]={"name":member.sim.character.name,"stage":member.sim.character.age_stage,"traits":member.sim.character.traits.duplicate(),"minimum_needs":member.sim.needs.duplicate(true),"critical_minutes":{},"waiting_minutes":0.0,"idle_minutes":0.0,"max_stationary_approach_minutes":0.0}
		for need:String in LifeSim.NEED_NAMES:audit.members[str(member.id)].critical_minutes[need]=0.0
	audit["fixture"]={"source":"isolated development candidate; see source_snapshot.json","lot":"Willow Cottage","extra_furnishings":purchases,"annex":ANNEX if with_annex else {},"granted_funds":9000,"active_adult":active_id,"note":"Second furnishing collection, a second fridge and an annex bedroom added through the public build and purchase paths; one adult given the Active trait; no needs, time or completions edited."}
	# JUSTLIFE_WEEK_DAYS shortens the audit for frame-time samples; the weekly
	# attendance and use checks only apply to the full seven days.
	var days:int=clampi(int(OS.get_environment("JUSTLIFE_WEEK_DAYS")) if OS.has_environment("JUSTLIFE_WEEK_DAYS") else 7,1,7)
	for i:int in range(days):
		await _run_days(audit_start+float(i+1)*1440.0)
	audit["days"]=days
	if days<7:
		var frame_list:Array=audit.frame_ms.duplicate();frame_list.sort()
		audit["frame_summary"]={"frames":frame_list.size(),"p50":frame_list[frame_list.size()/2],"p95":frame_list[int(frame_list.size()*.95)],"max":frame_list.back()}
		var short_file:=FileAccess.open(screenshot_dir.path_join("audit_first.json"),FileAccess.WRITE)
		short_file.store_string(JSON.stringify(audit,"  "));short_file.close()
		_write_report();app.queue_free();await frames(3)
		print_result("days=%d"%days)
		quit(0 if failures.is_empty() else 1);return
	await _final_review()
	var counts:Dictionary={}
	for event:Dictionary in audit.completions:
		if str(event.action) in NEW_ACTIONS:
			var key:String=str(event.id)+":"+str(event.action)
			counts[key]=int(counts.get(key,0))+1
	audit["new_action_completions"]=counts
	var active_jogs:int=int(counts.get(active_id+":jog",0))
	check(active_jogs>0,"The Active adult chooses the treadmill at least once during the week.")
	var child_toys:int=0
	for member:Dictionary in app.household.members:
		if str(member.sim.character.age_stage)=="child":child_toys+=int(counts.get(str(member.id)+":play_toys",0))
	check(child_toys>0,"A child plays with the toy chest at least once during the week.")
	var adult_toys:int=0;var child_jogs:int=0
	for event:Dictionary in audit.completions:
		var stage:String=str(app.household.member_sim(str(event.id)).character.age_stage)
		if str(event.action)=="play_toys" and stage!="child":adult_toys+=1
		if str(event.action)=="jog" and stage=="child":child_jogs+=1
	check(adult_toys==0 and child_jogs==0,"Age rules hold under autonomy: no adult toy play and no child treadmill runs.")
	var by_action:Dictionary={}
	for key:String in counts:by_action[key.split(":")[1]]=int(by_action.get(key.split(":")[1],0))+int(counts[key])
	audit["completions_by_new_action"]=by_action
	for expected:Array in [["treadmill","jog"],["toybox","play_toys"],["piano","play_piano"],["bathtub","bath"],["stereo","dance"],["yoga_mat","stretch"],["mirror","practice_speech"]]:
		# Four weeks of audits put the per-action minima at stretch 1-5, dance
		# 2-4 and the rest 3-10 with Fun floors 23-46: members with abundant
		# leisure rotate, so the bar per purchased furnishing is one use, and
		# the breadth of rotation is carried by the varied-adult check below.
		check(int(by_action.get(str(expected[1]),0))>=1,"The purchased %s is used at least once during the week (%s ×%d)." % [str(expected[0]),str(expected[1]),int(by_action.get(str(expected[1]),0))])
	var varied_adult:bool=false
	for member:Dictionary in app.household.members:
		if str(member.id)==active_id or str(member.sim.character.age_stage)=="child":continue
		for leisure:String in ["dance","stretch","play_piano","practice_speech"]:
			if int(counts.get(str(member.id)+":"+leisure,0))>0:varied_adult=true
	check(varied_adult,"At least one non-Active adult dances, stretches, plays the piano or practices a speech during the week.")
	audit["attendance"]={}
	for member:Dictionary in app.household.members:
		var stats:Dictionary=audit.members[str(member.id)]
		check(float(stats.waiting_minutes)<=4.0*60.0,"Weekly resource waiting stays at or under four hours: %s (%.1f h)." % [str(member.sim.character.name),float(stats.waiting_minutes)/60.0])
		check(float(stats.minimum_needs.fun)>=14.0,"Fun never falls below 14 during the week: %s (minimum %.1f)." % [str(member.sim.character.name),float(stats.minimum_needs.fun)])
		var critical_total:float=0.0
		for need:String in stats.critical_minutes:critical_total+=float(stats.critical_minutes[need])
		check(is_zero_approx(critical_total),"No need of %s enters the critical zone during the week (%.0f critical minutes)." % [str(member.sim.character.name),critical_total])
		var pupil:bool=str(member.sim.character.age_stage) in LifeEducation.SCHOOL_STAGES
		var late:float=float(member.sim.education.get("late_minutes",0.0)) if pupil else float(member.sim.career.get("schedule",{}).get("late_minutes",0.0))
		var attended:int=int(member.sim.education.get("attended",0)) if pupil else int(member.sim.career.get("schedule",{}).get("attended",0))
		var rest:Dictionary={"sleep":0,"nap":0}
		for event:Dictionary in audit.completions:
			if str(event.id)==str(member.id) and str(event.action) in rest:rest[str(event.action)]+=1
		audit.attendance[str(member.id)]={"name":member.sim.character.name,"attended":attended,"late_minutes":late,"rest":rest}
		check(is_zero_approx(late),"Nobody arrives late at school or work during the week: %s (%.0f late minutes over %d days)." % [str(member.sim.character.name),late,attended])
	var file:=FileAccess.open(screenshot_dir.path_join("audit_first.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "));file.close()
	_write_report();app.queue_free();await frames(3)
	print_result()
	quit(0 if failures.is_empty() else 1)
