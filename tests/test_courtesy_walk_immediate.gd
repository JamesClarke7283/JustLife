extends "res://tests/test_courtesy_walk_controls.gd"

func _run()->void:
	phase_tag="walk_immediate";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	audit={"events":[],"controls":[],"saves":[],"mode":mode_tag,"scope":"Public command then immediate public named save with no simulation step; separate-process exact decoded fresh checks and ten paused steps. Schema mutations are detached components only. No needs, body, queue, deadline, or clock injection."}
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	if mode_tag=="producer":await _produce_immediate()
	else:await _fresh_immediate()
	await _finish()

func _produce_immediate()->void:
	for label:String in ["replacement","cancel","new_action"]:
		await _load_walk()
		if label=="replacement":_additional_schema()
		var cached_before:Vector3=app.motion_states[WALKER].destination
		# An explicit existing geometry sync precedes the command/fact boundary.
		# The subsequent command/save sequence never advances simulation.
		app.meal_flow.sync_world(true)
		if label=="replacement":await _replace_walk()
		elif label=="cancel":await _cancel_walk()
		else:await _real_action()
		var before:Dictionary=_physical_facts()
		var expected:Dictionary=before.duplicate(true)
		var live_destination:Vector3=app.walk_destination
		if label=="replacement":
			check(LifeJourneyState.vector(before.journeys.members[WALKER].motion.intent.destination)==cached_before and app.motion_states[WALKER].destination==cached_before and live_destination==app.traversal.routes[WALKER].destination and live_destination!=cached_before,"Replacement still has the old command cache while the actual bound walk and route hold the new destination.")
			expected.journeys.members[WALKER].motion.intent.destination=LifeJourneyState.packed(live_destination)
		await _public_save("Walk ownership — immediate "+label)
		var slot:String=app.active_save_id;var result:Dictionary=LifeSaveLibrary.read_slot(slot)
		check(bool(result.get("ok",false)) and slot!=WALK_SLOT,"Immediate public "+label+" creates distinct valid named bytes.")
		if label=="replacement":
			check(app.motion_states[WALKER].destination==live_destination and app.walk_destination==live_destination and _physical_facts()==expected,"Immediate replacement save adopts only the actual live walk destination into its former cache; all other typed facts stay exact.")
		else:check(_physical_facts()==before,"Immediate public "+label+" save preserves exact typed people/queues/food/journeys/locks/clock/deadline.")
		audit.saves.append({"label":label,"slot":slot,"before":before,"expected":expected,"live_destination":live_destination,"after":_physical_facts(),"read":result})
		DirAccess.copy_absolute(LifeSaveLibrary._slot_path(slot),ProjectSettings.globalize_path(screenshot_dir.path_join("walk_immediate_"+label+".json")))
	var file:=FileAccess.open(screenshot_dir.path_join("walk_immediate_slots.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit.saves.map(func(row:Dictionary):return {"label":row.label,"slot":row.slot}),"  ",true,true));file.close()

func _additional_schema()->void:
	var original:Dictionary=LifeSaveLibrary.read_slot(WALK_SLOT).data
	for label:String in ["resource_wait","resource_active","custody","stair_ticket"]:
		var altered:Dictionary=original.duplicate(true)
		var saved:Dictionary=altered.members.filter(func(m:Dictionary):return m.id==WALKER)[0].state
		var route:Dictionary=altered.journeys.members[WALKER].motion
		if label=="resource_wait":saved.character.world_state.resource_wait_started=4800.0
		elif label=="resource_active":saved.character.world_state.resource_action_active=true
		elif label=="custody":route.custody="plate_missing"
		else:route.ticket=1
		var result:Dictionary=LifeSaveLibrary._validate_household(altered)
		check(not bool(result.ok) and not str(result.error).is_empty(),"Detached walk schema rejects conflicting "+label+" ownership.")
		audit.controls.append({"schema":label,"result":result})

func _fresh_immediate()->void:
	var entries:Variant=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("walk_immediate_slots.json")))
	check(entries is Array and entries.size()==3,"Fresh process receives exactly three actual immediate command saves.")
	if not entries is Array:return
	for entry:Dictionary in entries:
		await _load_exact(str(entry.slot));var disk:Dictionary=LifeSaveLibrary.read_slot(str(entry.slot)).data
		check(app.traversal.courtesy.owner(app.traversal).is_empty(),"Fresh "+str(entry.label)+" does not resurrect the retired courtesy owner.")
		check(_same(_project_journeys(disk.journeys),app.traversal.snapshot()),"Fresh "+str(entry.label)+" retains exact decoded authoritative journeys with explicit typed vectors/yaw only.")
		for saved:Dictionary in disk.members:
			var id:String=str(saved.id);var sim:LifeSim=app.household.member_sim(id)
			check(_same(_project_queue(saved.state.action_queue),sim.action_queue) and sim.needs==saved.state.needs and sim.career==_decoded_integer_fields(saved.state.career,["level","salary"],id+".career"),"Fresh exact decoded queue/paid/progress, needs and career: "+id)
			check(sim.education==_decoded_integer_fields(saved.state.education,["attended","enrolled_day","first_class_day","homework","last_attendance_day","last_day","last_homework_day","last_prepared_homework_day","missed","prepared","version"],id+".education"),"Fresh education retains all decoded values with only existing explicit integer fields: "+id)
			check(app.world.actors[id].position==LifeJourneyState.vector(disk.journeys.members[id].position),"Fresh exact canonical typed body: "+id)
		check(app.household.meals.get_state()==_decoded_integer_fields(disk.meals,["version","serial"],"food"),"Fresh authoritative food exact to decoded bytes except existing version/serial integer fields.")
		check(app.household.speed==0 and app.sim.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Fresh command slot starts paused at every clock.")
		var before:Dictionary=_physical_facts()
		for i:int in range(10):app._process(.05);await frames(1)
		check(_physical_facts()==before,"Ten paused frames after "+str(entry.label)+" preserve complete typed body/queue/food/journey/lock/clock facts.")
		audit.saves.append({"label":entry.label,"slot":entry.slot,"disk":disk,"initial":before,"after":_physical_facts()})
