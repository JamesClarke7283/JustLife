extends "res://tests/test_guest_meal.gd"
## A separate process reads producer-named files without reusing the old world.
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var filename:String="guest_meal_company_slot.json" if "--company-only" in OS.get_cmdline_user_args() else ("guest_meal_source_slot.json" if "--source-only" in OS.get_cmdline_user_args() else "guest_meal_slots.json")
	var file:=FileAccess.open("user://"+filename,FileAccess.READ)
	if file==null:check(false,"Producer phase slots exist");await _finish();return
	var ids:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	for phase:String in ids:
		var raw:Dictionary=LifeSaveLibrary.read_slot(str(ids[phase])).data
		var expected:Dictionary=LifeHomeVisit.saved_visit(raw).residents
		_load(str(ids[phase]));await process_frame;app.meal_flow.sync_world(false)
		check(_same_value(app.residents.snapshot(),expected),"Fresh process restores exact decoded guest identity, route and meal clocks: "+phase)
		check(_same_value(app.household.meals.get_state(),raw.meals),"Fresh process restores every authoritative decoded food scalar: "+phase)
		var visit:LifeHomeVisit=app.residents.home_visit
		check(visit.meal.body().position==visit._vector(expected.home_visit.visit.position),"Saved actor projects exactly to its typed physical transform: "+phase)
		check(app.household.speed==0,"Fresh guest meal remains paused: "+phase)
		var before:Dictionary=_record();var actor:LifeActor=visit.meal.body();var pose:Transform3D=actor.transform
		var presentation:Dictionary=actor.meal_presentation.duplicate(true)
		_step(4)
		check(_same_value(_record(),before) and actor.transform==pose and actor.meal_presentation==presentation,"Paused fresh restoration does not mutate ledger, route, queue, deadline or actor presentation: "+phase)
		if phase=="eating":
			check(not actor._activity_anchor.is_empty() and str(actor._activity_anchor.action)=="eat_meal","Paused fresh eater has a reconstructed seat or standing anchor")
			var plate_id:String=str(visit.meal.state.plate);var servings:int=int(app.household.meals.batches[0].served)
			app.household.set_speed(1)
			check(_meal_until("none",1000),"Fresh partial meal completes then returns to the visit")
			var plate:Dictionary=app.household.meals.portion(plate_id)
			check(float(plate.progress)==1 and str(plate.owner).is_empty() and str(plate.storage)=="dirty","Completed meal leaves one cleanable empty dish")
			check(_phase()=="inside" and int(app.household.meals.batches[0].served)==servings,"Completion preserves one serving and returns to the admitted lifecycle")
			check(app.residents.home_visit.social_allowed("maya"),"Finished meal restores ordinary guest social availability")
		elif phase=="to_place":
			check(bool(actor.meal_presentation.get("carrying",false)),"Paused fresh carrier visibly retains their portion")
			app.household.set_speed(1);check(_meal_until("eating"),"Fresh carrier reaches its reserved place")
			check(float(visit.meal.plate().progress)==0,"Arrival frame charges no pickup or walking time as eating")
		app.residents.home_visit.goodbye();app.household.set_speed(1)
		check(_until("absent"),"Fresh "+phase+" releases custody before the real sidewalk exit")
	await _finish()
