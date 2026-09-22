extends "res://tests/test_courtesy.gd"
const SLOT="life_1788951101795_688290719"
const PERSON="housemate_1"
const PLATE="plate_11"
var tag:String="natural"
func _run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):tag=arg.trim_prefix("--phase=")
	phase_tag=tag;root.size=Vector2i(1440,900);root.gui_disable_input=true;screenshot_dir="res://evidence"
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false)
	await frames(4);app.set_sound(false)
	if tag=="fresh":await _fresh()
	else:await _natural()
	await _finish()
func _paused_load(slot:String)->bool:
	var read:Dictionary=LifeSaveLibrary.read_slot(slot)
	check(bool(read.ok),"Actual named slot is readable: "+slot)
	if not bool(read.ok):return false
	await _load_slot(slot)
	check(app.mode=="live" and app.active_save_id==slot and app.household.speed==0,"Public named load is paused: "+slot)
	if app.mode!="live":return false
	check(_same(_project_journeys(read.data.journeys),app.traversal.snapshot()),"Decoded journeys reconstruct exactly with typed actor/vector projection.")
	if not audit.has("load_facts"):audit.load_facts=[]
	audit.load_facts.append({"slot":slot,"decoded":read.data,"actual":_record(),"differences":_differences(read.data.members.map(func(member:Dictionary):return member.state.action_queue),app.household.members.map(func(member:Dictionary):return member.sim.action_queue))})
	for member:Dictionary in read.data.members:
		check(_same(_restored_queue(member.state.action_queue),app.household.member_sim(str(member.id)).action_queue),"Exact saved queue/payment/elapsed with derived progress projection for "+str(member.id))
	check(_same(read.data.meals,app.household.meals.get_state()),"Decoded serving ledger and custody reconstruct exactly.")
	var before:Dictionary=_record()
	for i:int in range(10):app._process(.05);await frames(1)
	check(before==_record(),"Ten paused calls preserve clock, complete queues, bodies, routes, needs and food.")
	return failures.is_empty()
func _restored_queue(queue:Array)->Array:
	# The loader rebuilds each stored action from the live definition table and
	# adopts the saved progress, so a definition-derived field (`label`, `changes`,
	# `cost`, `description`, `skill`, `xp`) reflects today's code rather than the
	# text that was saved — which is what lets a retuned activity load. `sleep`
	# is the case here: 7e8b5d0 made it fun-neutral, so its `changes` gained `fun`
	# and its description names the boredom it now chases away. The saved
	# duration, elapsed, identity, payment and ownership are what a load must
	# preserve, and they are compared below through this same projection the
	# sibling courtesy suites use.
	var projected:Array=queue.duplicate(true)
	for action:Dictionary in projected:
		action.progress=clampf(float(action.elapsed)/float(action.duration),0.0,1.0)
		var definition:Dictionary=app.sim._actions.get(str(action.get("id","")),{})
		if definition.is_empty():continue
		var rebuilt:Dictionary=definition.duplicate(true)
		if str(action.get("id",""))=="cook":rebuilt=LifeMeals.cooking_definition(rebuilt,str(action.get("recipe","garden_skillet")))
		for key:String in ["label","changes","cost","description","skill","xp"]:
			if rebuilt.has(key):action[key]=rebuilt[key]
	return projected
func _save_owned(label:String)->void:
	await press("Ⅱ")
	var before:Dictionary=_record();await _public_save("Owned portion — "+label)
	var read:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(read.ok) and app.active_save_name=="Owned portion — "+label,"Public save records actual "+label+" meal phase.")
	check(before==_record(),"Public "+label+" save preserves exact paused runtime facts.")
	if bool(read.ok):audit.saves.append({"phase":label,"slot":app.active_save_id,"data":read.data})
	for i:int in range(5):app._process(.05);await frames(1)
	check(before==_record(),"Paused "+label+" remains stable after public save.")
	await press("▶")
func _natural()->void:
	if not await _paused_load(SLOT):return
	check(not app.residents.home_visit.active(),"Natural final checkpoint has no guest.")
	var sim:LifeSim=app.household.member_sim(PERSON)
	var initial:Dictionary=sim.get_current_action();var identity:int=int(app.traversal.routes[PERSON].identity)
	var origin:Vector3=app.world.actors[PERSON].position
	var plate:Dictionary=app.household.meals.portion(PLATE)
	var served:int=int(app.household.meals.batch(str(plate.batch)).served)
	check(initial.id=="eat_meal" and initial.phase=="approach" and initial.meal_stage=="eat" and plate.owner==PERSON and float(plate.progress)==0.0,"Natural fixture owns the actual fresh unfinished portion on its eating approach.")
	audit.initial=_record()
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):audit.completions.append({"id":id,"action":action.duplicate(true),"at":_now()}))
	await press("▶")
	# The continuation must reach the end of the dish before it spoils: the plate
	# is 36 game-minutes from expiry, and each step advances .05 real seconds, so
	# the run needs enough steps at this speed to cover that whole window rather
	# than stopping a fifth of the way in.
	var step_budget:int=int(ceil((float(plate.expires)-_now())/maxf(0.001,0.05*float(app.household.speed)*LifeSim.GAME_MINUTES_PER_SECOND)))+40
	var saved_approach:bool=false;var saved_active:bool=false;var moved:bool=false;var held_identity:bool=true;var nutrition_exact:bool=true
	for i:int in range(step_budget):
		if _now()>=float(plate.expires):break
		var before:Dictionary=sim.get_current_action();var hunger:float=float(sim.needs.hunger)
		var expected:float=_next_hunger(sim,plate)
		var start:int=Time.get_ticks_usec();app._process(.05);var cpu:int=Time.get_ticks_usec()-start;await frames(1)
		var current:Dictionary=sim.get_current_action();var row:Dictionary=_record();row.step=i;row.cpu_us=cpu;audit.steps.append(row)
		nutrition_exact=nutrition_exact and float(sim.needs.hunger)==expected
		if app.world.actors[PERSON].position!=origin:moved=true
		if not current.is_empty() and current.id=="eat_meal" and str(current.get("meal_plate",""))==PLATE:
			held_identity=held_identity and is_same(current,initial)
			if current.phase=="approach":held_identity=held_identity and int(app.traversal.routes.get(PERSON,{}).get("identity",-1))==identity
			if not saved_approach and current.phase=="approach" and moved:
				saved_approach=true;check(float(plate.progress)==0.0 and not bool(current.paid),"Real approach moves with no early payment, progress or nutrition.")
				await _save_owned("approach")
			if not saved_active and current.phase=="active" and float(plate.progress)>.02:
				saved_active=true
				check(app.world.actors[PERSON].position.distance_to(current.target_position)<.02 and bool(current.paid),"Actual body arrival begins paid eating at its reserved place.")
				await _save_owned("eating")
		if float(plate.progress)==1.0:break
	await press("Ⅱ")
	check(moved and saved_approach and saved_active,"Natural continuation physically reaches approach, arrival and eating milestones.")
	check(held_identity,"The actual action and approach journey identity survive hunger reconsideration without cancel/reacquire.")
	check(nutrition_exact,"Each ordinary frame grants exactly eligible portion nutrition after actual need decay; no approach-frame nutrition.")
	check(float(plate.progress)==1.0 and str(plate.storage)=="dirty" and str(plate.owner).is_empty(),"The same real portion completes before spoilage and releases one dirty plate.")
	check(int(app.household.meals.batch(str(plate.batch)).served)==served and app.household.meals.portions.filter(func(value:Dictionary):return str(value.id)==PLATE).size()==1,"Completion neither claims another serving nor duplicates its plate.")
	check(audit.completions.filter(func(e:Dictionary):return str(e.id)==PERSON and str(e.action.get("meal_plate",""))==PLATE and str(e.action.id)=="eat_meal").size()==1,"One actual action completion belongs to this portion.")
	audit.final=_record()
func _next_hunger(sim:LifeSim,plate:Dictionary)->float:
	var minutes:float=.05*LifeSim.GAME_MINUTES_PER_SECOND
	var value:float=clampf(float(sim.needs.hunger)-float(LifeSim.NEED_DECAY.hunger)*minutes/60.0,0.0,100.0)
	var current:Dictionary=sim.get_current_action()
	if current.get("id")=="eat_meal" and current.get("phase")=="active" and str(current.get("meal_plate",""))==PLATE:
		var step:float=minf(minutes,float(current.duration)-float(current.elapsed))
		var amount:float=minf(1.0-float(plate.progress),step/LifeMeals.EATING_MINUTES)
		var batch:Dictionary=app.household.meals.batch(str(plate.batch))
		value=minf(100.0,value+amount*float(LifeMeals.RECIPES[str(batch.recipe)].nutrition))
	return value
func _fresh()->void:
	var produced:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/natural.json"))
	check(produced.saves.size()==2,"Producer supplies both naturally reached public meal saves.")
	for saved:Dictionary in produced.saves:
		if "--only-eating" in OS.get_cmdline_user_args() and saved.phase!="eating":continue
		if not await _paused_load(str(saved.slot)):return
		var sim:LifeSim=app.household.member_sim(PERSON);var current:Dictionary=sim.get_current_action();var plate:Dictionary=app.household.meals.portion(PLATE)
		var starting:Dictionary=_record();var route_id:int=int(app.traversal.routes.get(PERSON,{}).get("identity",0))
		check(str(current.phase)==("approach" if saved.phase=="approach" else "active") and plate.owner==PERSON,"Fresh load preserves actual "+str(saved.phase)+" custody and phase.")
		await press("▶")
		# Same reach as the natural continuation: each step advances .05 real
		# seconds, so size the run to the portion's whole remaining freshness
		# window instead of stopping part-way and blaming the product.
		var step_budget:int=int(ceil((float(plate.expires)-_now())/maxf(0.001,0.05*float(app.household.speed)*LifeSim.GAME_MINUTES_PER_SECOND)))+40
		var exact:bool=true;var identity_preserved:bool=true
		for i:int in range(step_budget):
			if _now()>=float(plate.expires):break
			var expected:float=_next_hunger(sim,plate)
			app._process(.05);await frames(1)
			exact=exact and float(sim.needs.hunger)==expected
			var row:Dictionary=_record();row.fresh_phase=str(saved.phase);audit.steps.append(row)
			var next:Dictionary=sim.get_current_action()
			if next.get("id")=="eat_meal" and next.get("meal_plate")==PLATE:
				identity_preserved=identity_preserved and is_same(next,current)
				if next.phase=="approach":identity_preserved=identity_preserved and int(app.traversal.routes.get(PERSON,{}).get("identity",-1))==route_id
			if float(plate.progress)==1.0:break
		await press("Ⅱ")
		check(exact and identity_preserved,"Fresh "+str(saved.phase)+" uses the existing action and exactly remaining nourishment.")
		check(float(plate.progress)==1.0 and str(plate.owner).is_empty() and plate.storage=="dirty","Fresh "+str(saved.phase)+" physically completes its same portion before expiry.")
		audit.saves.append({"phase":saved.phase,"starting":starting,"final":_record()})
func _finish()->void:
	var ambience:WeakRef=weakref(app.ambience_player.stream);var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free();await frames(2)
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Private app audio releases before exit.")
	audit.assertions=assertions;audit.failures=failures
	var f:=FileAccess.open(screenshot_dir.path_join(tag+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(_json(audit),"  ",true,true));f.close()
	print("OWNED_MEAL_RESULT assertions=%d failures=%d"%[assertions,failures.size()]);quit(0 if failures.is_empty() else 1)
