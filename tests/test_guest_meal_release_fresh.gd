extends "res://tests/test_guest_meal.gd"
## Persist release custody and retry time, then resume in a separate process.
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var fresh:bool="--fresh" in OS.get_cmdline_user_args()
	var file:=FileAccess.open("user://guest_meal_release_slot.json" if fresh else "user://guest_meal_slots.json",FileAccess.READ)
	if file==null:check(false,"Required release producer file exists");await _finish();return
	var ids:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	var slot:String=str(ids.release) if fresh else str(ids.goodbye) if "--standing-release" in OS.get_cmdline_user_args() else str(ids.to_place)
	_load(slot);await process_frame;app.meal_flow.sync_world(false)
	var visit:LifeHomeVisit=app.residents.home_visit;var meal:LifeGuestMeal=visit.meal
	var plate_id:String=str(meal.state.plate)
	var held_standing:bool=str(meal.plate().storage)=="table" and str(meal.plate().host).is_empty()
	if held_standing:
		check(bool(meal.body().meal_presentation.get("carrying",false)),"Paused standing release reconstructs a holding pose while the plate remains owned")
	if fresh:
		var raw:Dictionary=LifeSaveLibrary.read_slot(slot).data
		check(_same_value(app.household.meals.get_state(),raw.meals) and _same_value(app.residents.snapshot(),LifeHomeVisit.saved_visit(raw).residents),"Fresh pending release restores every decoded owner, plate, route and retry field")
		var frozen:Dictionary=_record();_step(4)
		check(_same_value(_record(),frozen),"Fresh blocked-release save remains exactly paused")
		var retry_at:float=float(meal.state.retry_at);var progress:float=float(meal.plate().progress)
		app.household.set_speed(1);_step(1)
		check(visit._now()<retry_at and str(meal.state.phase)=="release" and str(meal.plate().owner)=="maya","Restored pending retry retains custody before its actual retry clock")
		check(_until("absent"),"Once its retry is due, guest releases safely then physically exits")
		var plate:Dictionary=app.household.meals.portion(plate_id)
		check(str(plate.owner).is_empty() and float(plate.progress)==progress and int(app.household.meals.batches[0].served)==1,"Fresh release spends no extra serving or eating progress")
	else:
		visit.goodbye();var serving:Dictionary=meal.plate().duplicate(true)
		var surfaces:Array=[]
		for entry:Dictionary in app.world.items:
			if LifeMealFlow.SURFACE_HEIGHTS.has(str(entry.kind)):
				surfaces.append({"entry":entry,"position":entry.node.position,"level":entry.get("level",0),"had_level":entry.has("level")})
				entry.level=1;entry.node.position.y+=3.0
		var blocker:=Node3D.new();app.world.house.add_child(blocker);blocker.position=Vector3(0,.16,0)
		app.world.items.append({"id":"controlled_no_slot","kind":"plant","level":0,"node":blocker,"size":Vector2(40,40)})
		app.household.set_speed(1);meal.tick(.05)
		check(_same_value(serving,meal.plate()) and str(meal.state.phase)=="release" and float(meal.state.retry_at)==visit._now()+5.0,"Real setdown failure retains exact custody and schedules one bounded retry")
		# The artificial geometry obstruction is removed before the named save;
		# the actual pending owner/retry state is preserved and must not reset.
		app.world.items=app.world.items.filter(func(entry:Dictionary)->bool:return str(entry.id)!="controlled_no_slot");blocker.free()
		for saved:Dictionary in surfaces:
			saved.entry.node.position=saved.position
			if saved.had_level:saved.entry.level=saved.level
			else:saved.entry.erase("level")
		app.meal_flow.sync_world()
		meal.present()
		if held_standing:check(bool(meal.body().meal_presentation.get("carrying",false)),"Blocked standing release retains its holding pose while retry is pending")
		if await _save_phase("blocked_release"):
			var output:=FileAccess.open("user://guest_meal_release_slot.json",FileAccess.WRITE);output.store_string(JSON.stringify({"release":app.active_save_id},"",true,true));output.close()
	await _finish()
