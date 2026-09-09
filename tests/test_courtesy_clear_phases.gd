extends "res://tests/test_courtesy_clear.gd"

func _run()->void:
	phase_tag="clear_phases";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	audit={"events":[],"saves":[],"continuations":[],"mode":mode_tag,"scope":"Actual public phase saves or separate process public fresh loads from same genuine landing; ordinary controller steps, no injected physical/state recovery."}
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	if mode_tag=="producer":await _produce()
	else:await _fresh()
	await _finish()

func _produce()->void:
	for wanted:String in ["retreat","hold"]:
		await _load_exact(LANDING_SLOT)
		await press("▶")
		var found:bool=false;var moved:bool=false
		var start:Vector3=app.world.actors.housemate_3.position
		for step:int in range(200):
			app._process(.05);await frames(1)
			var owner_id:String=app.traversal.courtesy.owner(app.traversal)
			if owner_id.is_empty():continue
			var fact:Dictionary=app.traversal.routes[owner_id].courtesy
			moved=app.world.actors[owner_id].position!=start
			if str(fact.phase)==wanted and moved:
				found=true;break
		check(found,"Actual ordinary movement reaches "+wanted+" after leaving original body point.")
		if not found:return
		await press("Ⅱ");app._process(.05);await frames(1)
		var before:Dictionary=_physical_facts()
		check(app.household.speed==0 and app.sim.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Public pause is adopted by all clocks before phase observation.")
		await _public_save("Landing clearance — "+wanted)
		var slot:String=app.active_save_id;var read:Dictionary=LifeSaveLibrary.read_slot(slot)
		check(bool(read.get("ok",false)),"Actual "+wanted+" named bytes validate with new protected kind.")
		check(_physical_facts()==before,"Public "+wanted+" save keeps complete typed physical/food/queue/clock/journey facts.")
		if not bool(read.get("ok",false)):return
		var old:Dictionary=load("res://tests/fixtures/courtesy_pre_kind_reader.gd").validate(read.data.journeys,read.data)
		check(not bool(old.ok) and str(old.error).contains("courtesy"),"Unchanged previous reader explicitly rejects new courtesy version/kind.")
		var entry:Dictionary={"phase":wanted,"slot":slot,"saved":read.data,"facts":before,"after_save":_physical_facts(),"old_reader":old}
		audit.saves.append(entry)
		DirAccess.copy_absolute(LifeSaveLibrary._slot_path(slot),ProjectSettings.globalize_path(screenshot_dir.path_join("actual_"+wanted+".json")))
	var file:=FileAccess.open(screenshot_dir.path_join("phase_slots.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit.saves.map(func(e:Dictionary):return {"phase":e.phase,"slot":e.slot}),"  ",true,true));file.close()

func _fresh()->void:
	var entries:Variant=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("phase_slots.json")))
	check(entries is Array and entries.size()==2,"Separate process receives both immutable actual named phase slots.")
	if not entries is Array:return
	for entry:Dictionary in entries:
		var slot:String=str(entry.slot);await _load_exact(slot)
		var disk:Dictionary=LifeSaveLibrary.read_slot(slot).data
		check(app.household.speed==0 and app.sim.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Fresh "+str(entry.phase)+" is paused in every clock.")
		check(_same(_project_journeys(disk.journeys),app.traversal.snapshot()),"Fresh authoritative "+str(entry.phase)+" journey scalars match disk with exact typed vectors/yaw only.")
		for saved:Dictionary in disk.members:
			var sim:LifeSim=app.household.member_sim(str(saved.id))
			check(_same(_project_queue(saved.state.action_queue),sim.action_queue) and sim.needs==saved.state.needs and sim.career==saved.state.career,"Fresh complete queue/paid/progress and exact decoded needs/career: "+str(saved.id))
		check(app.household.meals.get_state()==_decoded_integer_fields(disk.meals,["version","serial"],"food"),"Fresh food/custody ledger exact apart from documented integer fields.")
		var before:Dictionary=_physical_facts()
		for i:int in range(10):app._process(.05);await frames(1)
		check(_physical_facts()==before,"Ten paused "+str(entry.phase)+" steps preserve all typed physical/queue/food/stair/deadline/clock facts.")
		check(app.traversal.routes.player.phase=="clear" and app.traversal.stairs.stairs_2.owner=="player" and app.traversal.routes.housemate_3.courtesy_priority.size()>1,"Fresh protected route retains lock while corridor derives from actual remaining body-to-clear path.")
		audit.continuations.append(await _resume_one(str(entry.phase)))

func _resume_one(label:String)->Dictionary:
	var t:LifeTraversal=app.traversal;var donor:String=t.courtesy.owner(t);var peer:String="player"
	var original:Dictionary=t.routes[peer].duplicate(true);var queue:Array=app.household.member_sim(donor).action_queue.duplicate(true)
	var object:Dictionary=app.household.member_sim(donor).get_current_action();var fact:Dictionary=t.routes[donor].courtesy.duplicate(true)
	var result:Dictionary={"phase":label,"initial":_record_clear(),"steps":[]}
	var resumed:bool=false;var changed:bool=false;var minimum:float=INF
	await press("▶")
	for i:int in range(700):
		if _now()>=float(fact.expires_at):break
		app._process(.05);await frames(1);result.steps.append(_record_clear())
		if t.routes.has(peer) and int(t.routes[peer].identity)==int(original.identity):
			for key:String in ["identity","ticket","phase","destination","stair_id","exit","clear","safety","custody"]:
				if t.routes[peer].get(key,"")!=original.get(key,""):changed=true
			if t.stairs.stairs_2.owner!=peer:changed=true
		for a:String in app.world.actors:
			if not app.world.actors[a].visible:continue
			for m:Dictionary in app.household.members:
				var b:String=str(m.id)
				if a==b or not app.world.actors[b].visible:continue
				if t._same_floor(app.world.actors[a].position,app.world.actors[b].position):minimum=minf(minimum,app.world.actors[a].position.distance_to(app.world.actors[b].position))
		if (not t.routes.has(peer) or int(t.routes[peer].identity)!=int(original.identity)) and t.courtesy.owner(t).is_empty() and app.world.actors[donor].position!=fact.anchor:
			resumed=is_same(object,app.household.member_sim(donor).get_current_action()) and app.household.member_sim(donor).action_queue==queue
			if resumed:break
	check(not changed,"Fresh "+label+" keeps protected physical route/ticket/custody/lock until actual retirement.")
	check(resumed,"Fresh "+label+" actually clears Rowan and resumes unchanged Casey queue before expiry.")
	check(t.courtesy.trace.any(func(r:Dictionary):return r.get("released","")==donor and r.get("reason","") in ["beneficiary_cleared","beneficiary_retired"]),"Fresh "+label+" releases only on real clearance/retirement.")
	check(minimum>=.72,"Fresh "+label+" household-versus-visible physical gap remains at least.72.")
	result["minimum"]=minimum;result["resumed"]=resumed;result["final"]=_record_clear()
	await press("Ⅱ");app._process(.05);await frames(1)
	return result
