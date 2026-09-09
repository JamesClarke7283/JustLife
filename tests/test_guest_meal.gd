extends "res://tests/test_home_visit.gd"
var slots:Dictionary={}
func _meal_phase()->String:return str(app.residents.home_visit.meal.state.get("phase","none"))
func _meal_until(phase:String,limit:int=800)->bool:
	var prior:String=_meal_phase()
	for index:int in limit:
		if _meal_phase()==phase:return true
		_step()
		if _meal_phase()!=prior:
			events.append({"transition":prior+" -> "+_meal_phase(),"meal":app.residents.home_visit.meal.state.duplicate(true),"notice":app.notice_label.text})
			prior=_meal_phase()
	return _meal_phase()==phase
func _record()->Dictionary:
	return {"visit":app.residents.snapshot(),"food":app.household.meals.get_state(),"physical":app._physical_snapshot_context(),"household":app.household.get_state(app.world.serialize_items())}
func _save_phase(label:String)->bool:
	app.household.set_speed(0)
	var before:Dictionary=_record()
	var ok:bool=app.save_game("",label)
	check(ok,"Named guest meal save: "+label)
	if not ok:events.append({"save_failure":label,"notice":app.notice_label.text,"facts":before});return false
	slots[label]=app.active_save_id
	var disk:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id).data
	var expected:Dictionary={"visit":LifeHomeVisit.saved_visit(disk).residents,"food":disk.meals}
	var pre_encode:Dictionary={"visit":app.residents.snapshot(),"food":app.household.meals.get_state()}
	if not _same_value(pre_encode,expected):events.append({"codec_boundary":label,"pre_encode":pre_encode,"decoded":expected})
	_load(app.active_save_id)
	await process_frame
	app.meal_flow.sync_world(false)
	if not _same_value(expected,{"visit":app.residents.snapshot(),"food":app.household.meals.get_state()}):events.append({"phase":label,"expected":expected,"actual":{"visit":app.residents.snapshot(),"food":app.household.meals.get_state()}})
	check(_same_value(expected,{"visit":app.residents.snapshot(),"food":app.household.meals.get_state()}),"Exact named guest meal ledger and route restoration: "+label)
	check(app.residents.home_visit.meal.app==app,"Guest meal helper follows the adopted controller")
	var frozen:Dictionary=_record();_step(3)
	check(_same_value(_record(),frozen),"Paused meal state is unchanged: "+label)
	return true
func _batch()->Dictionary:
	var table:Dictionary=app.world.closest_item("dining",Vector3.ZERO)
	var prepared_at:float=floorf(app.residents.home_visit._now())
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet","player",1,"home",prepared_at)
	var slot:Vector3=app.meal_flow._surface_slot(table,LifeMeals.PLATTER_HALF_SIZE,str(batch.id))
	app.household.meals.set_batch_location(str(batch.id),"surface",str(table.id),table.node.to_global(slot),prepared_at)
	batch.offset=[slot.x,slot.y,slot.z];app.meal_flow.sync_world()
	return batch
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false);_setup()
	if "--standing-fixture" in OS.get_cmdline_user_args():
		var removed:Array=[]
		for entry:Dictionary in app.world.items:
			if str(entry.kind)=="chair":removed.append(str(entry.id))
		for id:String in removed:app.world.remove_item(id)
		app._refresh_sim_targets()
	check(app.residents.home_visit.invite("maya"),"Friend can be invited")
	app.household.set_speed(8);check(_until("waiting"),"Guest actually walks to the welcome point")
	check(app.residents.home_visit.welcome("player"),"Ordinary friendly Welcome is queued")
	app.household.set_speed(1);check(_until("inside",1200),"Actual paid Welcome completes and guest walks inside")
	if _phase()!="inside":events.append(_record());await _finish();return
	var deadline:float=float(app.residents.home_visit.state.phase_at)+LifeHomeVisit.STAY_MINUTES
	for member:Dictionary in app.household.members:member.sim.needs.hunger=99
	var batch:Dictionary=_batch();var source:String=str(batch.id)
	var funds:int=app.household.funds
	app.show_interactions(app._find_item(source),Vector2(700,350))
	var call:Button
	for node:Node in app.overlay.find_children("*","Button",true,false):
		if node.text=="Call everyone to eat":call=node
	check(is_instance_valid(call),"Actual dish interaction exposes Call everyone to eat")
	if not is_instance_valid(call):await _finish();return
	call.pressed.emit()
	check(_meal_phase()=="pickup" and app.household.members.size()==2,"Call offers one guest meal without adding a household member")
	check(app.household.meals.batch(source).remaining==4 and app.household.meals.portions.is_empty(),"Calling does not claim food before physical pickup")
	check(not app.residents.home_visit.social_allowed("maya"),"Guest meal excludes conversation ownership")
	check(app.meal_flow.call_to_meal(source)==0,"Repeated call cannot create a second guest meal")
	_step(4)
	if not await _save_phase("pickup"):await _finish();return
	app.household.set_speed(1);check(_meal_until("to_place"),"Guest physically collects one serving and reserves a dining place")
	if _meal_phase()!="to_place":events.append(_record());await _finish();return
	var portion_id:String=str(app.residents.home_visit.meal.state.plate)
	check(app.household.meals.batch(source).remaining==3 and app.household.meals.batch(source).served==1 and app.household.meals.portions.size()==1,"Physical pickup decrements and creates exactly one portion")
	check(app.household.meals.portion(portion_id).owner=="maya","Guest holds their identified portion in the existing ledger")
	var act:Dictionary=app.residents.home_visit.meal.activity()
	check(app.meal_flow.guest_blocks({"id":"sit","target_id":act.target_id,"target_position":act.target_position}),"Household activity admission respects the guest reservation")
	if not await _save_phase("to_place"):await _finish();return
	app.household.set_speed(1);check(_meal_until("eating"),"Guest reaches their dining place before eating")
	if _meal_phase()!="eating":events.append(_record());await _finish();return
	_step(12)
	check(float(app.household.meals.portion(portion_id).progress)>0 and float(app.household.meals.portion(portion_id).progress)<1,"Only arrived eating advances actual portion progress")
	check(app.household.funds==funds,"Guest dining adds no second ingredient debit")
	if not await _save_phase("eating"):await _finish();return
	check(not app.world.actors.maya._activity_anchor.is_empty() and app.world.actors.maya._activity_anchor.action=="eat_meal","Fresh paused load reconstructs the eating anchor")
	check(float(app.residents.home_visit.state.phase_at)+LifeHomeVisit.STAY_MINUTES==deadline,"Meal and restart preserve the original visit deadline")
	var progress:float=float(app.household.meals.portion(portion_id).progress)
	app.residents.home_visit.goodbye()
	check(_phase()=="leaving" and _meal_phase()=="release","Goodbye hands the meal to explicit release custody")
	if not await _save_phase("goodbye"):await _finish();return
	app.household.set_speed(1);_step(1)
	check(app.household.meals.portion(portion_id).owner=="" and float(app.household.meals.portion(portion_id).progress)==progress,"Goodbye safely releases the partial plate without eating or refunding it")
	var exit:Vector3=app.residents.home_visit.state.exit
	check(_phase()=="leaving" and app.residents.present("maya"),"Releasing the plate does not hide the still-indoor guest")
	check(_until("absent"),"Guest exits physically after releasing plate custody")
	check(app.world.actors.maya.position.distance_to(exit)<.00001,"Guest becomes absent at the saved sidewalk exit")
	check(app.household.meals.portions.size()==1 and app.household.meals.batch(source).remaining==3,"Guest departure retains the consumed serving ledger and cleanable partial dish")
	var file:=FileAccess.open("user://guest_meal_slots.json",FileAccess.WRITE);file.store_string(JSON.stringify(slots));file.close()
	await _finish()
