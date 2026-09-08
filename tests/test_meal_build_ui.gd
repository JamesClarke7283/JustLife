extends "res://tests/test_meal_playthrough.gd"
## Ordinary meal/save flow interrupted through actual Build & buy controls.

func _meal_closeup() -> void:
	var table:Dictionary=first_item("dining")
	var table_id:String=str(table.id)
	var table_position:Vector3=table.node.position
	var table_angle:float=table.node.rotation_degrees.y
	var before:Dictionary=app.household.meals.get_state()
	var funds:int=app.household.funds
	var plate_ids:Array=before.portions.map(func(p:Dictionary)->String:return str(p.id))
	_meal_checkpoint("before_build")
	await press("Build & buy")
	check(app.mode=="build" and app.sim.speed==0,"Editing the dining room pauses both diners.")
	# Clicking food must not offer furniture sale or movement.
	var dish:Dictionary=app._find_item(str(before.batches[0].id))
	app.world.object_clicked.emit(dish,app.world.camera.unproject_position(dish.node.position))
	await frames(3)
	check(not _visible_button("Move furnishing"),"Build mode cannot sell or move a food view as furniture.")
	await _begin_move(table_id)
	await frames(3)
	_meal_checkpoint("pending_table")
	check(_same_json(app.household.meals.get_state(),before),"Temporarily lifting the table preserves every serving, plate, owner and progress.")
	check(not app.meal_flow.views[str(before.batches[0].id)].visible,"Food on a temporarily lifted table is hidden during placement preview.")
	await _escape()
	check(app.pending_move.is_empty() and not app._find_item(table_id).is_empty(),"Escape restores the original table through the normal placement control.")
	check(_same_json(app.household.meals.get_state(),before),"Canceling a table move restores the exact meal state.")
	await screenshot("07_table_move_canceled",false,false)
	var action:Dictionary=app.sim.get_current_action()
	var chair_id:String=str(action.get("meal_seat",""))
	var chair:Dictionary=app._find_item(chair_id)
	check(not chair.is_empty(),"The selected diner still owns a real dining chair.")
	if chair.is_empty():return
	var chair_position:Vector3=chair.node.position
	var chair_angle:float=chair.node.rotation_degrees.y
	var plate_id:String=str(action.meal_plate)
	var remaining_before:float=float(app.household.meals.portion(plate_id).progress)
	await _begin_move(chair_id)
	if not await _place_move("chair",chair_position+(chair_position-table_position).normalized()*.25,chair_angle):return
	var moved_action:Dictionary=app.sim.get_current_action()
	check(moved_action.get("phase")=="approach" and str(moved_action.get("meal_plate",""))==plate_id,"Moving an occupied chair reroutes its diner with the same partial plate.")
	check(app.household.meals.portion(plate_id).storage=="carried","The rerouting diner carries the plate instead of walking empty-handed.")
	check(float(app.household.meals.portion(plate_id).progress)==remaining_before,"Build movement does not advance eating progress.")
	await _begin_move(table_id)
	var moved_position:Vector3=table_position+Vector3(.25,0,0)
	if not await _place_move("dining",moved_position,table_angle):return
	check(app.household.meals.batches[0].host==table_id,"Committed movement retains the serving dish's table identity.")
	check(app.household.meals.portions.map(func(p:Dictionary)->String:return str(p.id))==plate_ids,"Moving the table preserves the original individual plates.")
	for plate:Dictionary in app.household.meals.portions:
		check(plate.host==table_id and float(plate.progress)==float(_prior_plate(before,str(plate.id)).progress),"Moving the table changes support without consuming or dropping "+str(plate.id)+".")
	await screenshot("08_table_moved_with_food",false,false)
	await press("Live")
	check(app.sim.speed==0,"Leaving Build retains the existing pause.")
	await screenshot("09_chair_moved_plate_in_hand",false,false)
	await press("▶")
	if not await wait_until(func()->bool:return _both_eating(),"both diners naturally settle after the furniture edits",30):return
	await press("Ⅱ")
	check(app.household.meals.portions.size()==2 and app.household.meals.batches[0].remaining==2,"Reseating claims no extra servings or plates.")
	check(app.household.funds==funds,"Moving dining furniture charges no ingredients or furniture cost.")
	for member:Dictionary in app.household.members:
		var current:Dictionary=member.sim.get_current_action()
		var lifelet:LifeActor=app.world.actors[str(member.id)]
		var view:Node3D=app.meal_flow.views[str(current.meal_plate)]
		check(lifelet._activity_anchor.get("plate_position",Vector3.INF).distance_to(view.global_position)<.002,"Resettled "+str(member.id)+" aims at its actual moved plate.")
	await screenshot("10_dining_after_build",false,false)
	await super._meal_closeup()

func _prior_plate(state:Dictionary,id:String) -> Dictionary:
	for plate:Dictionary in state.portions:
		if str(plate.id)==id:return plate
	return {}

func _visible_button(label:String) -> bool:
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and node.text==label:return true
	return false

func _begin_move(id:String) -> void:
	var furnishing:Dictionary=app._find_item(id)
	check(not furnishing.is_empty(),"The furnishing is present before the move: "+id)
	if furnishing.is_empty():return
	app.world.object_clicked.emit(furnishing,app.world.camera.unproject_position(furnishing.node.position))
	await frames(3);await press("Move furnishing")
	check(str(app.pending_move.get("entry",{}).get("id",""))==id,"Move furnishing lifts the requested stable identity: "+id)

func _place_move(kind:String,at:Vector3,angle:float) -> bool:
	at=Vector3(snappedf(at.x,.25),.16,snappedf(at.z,.25))
	check(app.world.can_place(kind,at,angle),"The intended moved "+kind+" fits the real layout.")
	if not app.world.can_place(kind,at,angle):return false
	var screen:Vector2=app.world.camera.unproject_position(at)
	await mouse_move(screen)
	check(app.world.ghost_valid,"The mouse-driven "+kind+" preview accepts the moved position.")
	await mouse_click(screen)
	check(app.pending_move.is_empty(),"Mouse placement commits the moved "+kind+".")
	return app.pending_move.is_empty()

func _escape() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.physical_keycode=KEY_ESCAPE;event.pressed=true
	Input.parse_input_event(event);await frames(3)
	event=InputEventKey.new();event.keycode=KEY_ESCAPE;event.physical_keycode=KEY_ESCAPE;event.pressed=false
	Input.parse_input_event(event);await frames(3)

func _meal_checkpoint(label:String) -> void:
	var out:=FileAccess.open(screenshot_dir+"/"+label+".json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"food":app.household.meals.get_state(),"queues":app.household.members.map(func(m:Dictionary)->Array:return m.sim.action_queue.duplicate(true))},"\t"));out.close()
