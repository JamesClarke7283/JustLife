extends "res://tests/test_autonomy_week.gd"
## Rendered week with the second furnishing collection: the eight-member Reed
## family in Willow Cottage gains a treadmill, toy chest, piano, bathtub,
## stereo, yoga mat, mirror and armchair, one adult is made Active, and the
## household runs autonomously for seven days (five weekdays and a weekend).
## Harness mutations are limited to the granted furniture budget and that
## trait; needs, time and completions are observed, never edited.
const EXTRA_FURNISHINGS: Array = [["treadmill",2.3,-.5,90],["toybox",-1.7,1.2,0],["piano",-1.7,-1.4,0],["bathtub",2.4,-2.6,0],["stereo",-5.5,-2.5,90],["yoga_mat",-1.6,3.3,0],["mirror",-5.5,-1.0,90],["armchair",-1.4,3.2,0]]
const NEW_ACTIONS: Array = ["jog","play_toys","play_piano","bath","dance","stretch","practice_speech","play_chess","play_games","warm_up","change_outfit"]

func _run()->void:
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
		print("CATALOGUE_WEEK_RESULT assertions=0 failures=0 resume=true");quit(0);return
	await _create_genealogy()
	var active_id:String=""
	for member:Dictionary in app.household.members:
		if str(member.sim.character.name)==FAMILY_NAMES[2]:
			member.sim.character.traits=["Active","Outgoing","Foodie"];active_id=str(member.id)
	check(not active_id.is_empty(),"One adult carries the Active trait for the treadmill preference.")
	app.household.set_funds(app.sim.funds+6000)
	await press("Build & buy")
	var placed:int=0
	for entry:Array in EXTRA_FURNISHINGS:
		var before:int=app.world.items.size()
		app.on_placement(str(entry[0]),Vector3(float(entry[1]),0.16,float(entry[2])),float(entry[3]))
		if app.world.items.size()>before:placed+=1
		else:check(false,"Catalogue furnishing could not be placed in Willow Cottage: "+str(entry[0]))
	check(placed==EXTRA_FURNISHINGS.size(),"All eight second-collection furnishings are purchased into the furnished cottage.")
	await press("Live")
	await screenshot("00_catalogue_cottage",false,false)
	for member:Dictionary in app.household.members:member.sim.autonomy=true
	var stages:Array=[]
	for member:Dictionary in app.household.members:
		stages.append(member.sim.character.age_stage)
		audit.members[str(member.id)]={"name":member.sim.character.name,"stage":member.sim.character.age_stage,"traits":member.sim.character.traits.duplicate(),"minimum_needs":member.sim.needs.duplicate(true),"critical_minutes":{},"waiting_minutes":0.0,"idle_minutes":0.0,"max_stationary_approach_minutes":0.0}
		for need:String in LifeSim.NEED_NAMES:audit.members[str(member.id)].critical_minutes[need]=0.0
	audit["fixture"]={"source":"isolated development candidate; see source_snapshot.json","lot":"Willow Cottage","extra_furnishings":EXTRA_FURNISHINGS,"granted_funds":6000,"active_adult":active_id,"note":"Second furnishing collection added through the public purchase path; one adult given the Active trait; no needs, time or completions edited."}
	for i:int in range(7):
		await _run_days(audit_start+float(i+1)*1440.0)
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
	var total_new:int=0
	for value:int in counts.values():total_new+=value
	check(total_new>=8,"The household completes at least eight second-collection activities over the week.")
	var file:=FileAccess.open(screenshot_dir.path_join("audit_first.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "));file.close()
	_write_report();app.queue_free();await frames(3)
	print("CATALOGUE_WEEK_RESULT assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)
