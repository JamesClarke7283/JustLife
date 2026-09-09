extends "res://tests/test_guest_meal.gd"
## Ordinary paused Build mutations must still reconcile hosted food explicitly.
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false);_setup()
	var batch:Dictionary=_batch();var source:String=str(batch.id);var host_id:String=str(batch.host)
	app.household.set_speed(0)
	var before:Dictionary=app.household.meals.get_state();_step(5)
	check(_same_value(before,app.household.meals.get_state()),"Paused ordinary Live presentation preserves exact authoritative food fields")
	app.set_build_mode(true)
	check(app.mode=="build" and app.household.speed==0,"Public Build entry is paused without an active guest")
	var host:Dictionary=app._find_item(host_id);var old_position:Vector3=host.node.position
	app.move_item(host)
	check(not app.pending_move.is_empty(),"Public move preserves a pending identity for the occupied dining table")
	check(str(app.household.meals.batch(source).host)==host_id,"Pending table move retains food custody and supporting identity")
	var moved:bool=false
	for x:int in range(-10,11):
		for z:int in range(-8,9):
			var target:=Vector3(x*.5,.16,z*.5)
			if target.distance_to(old_position)<1.0 or not app.world.can_place("dining",target,0):continue
			app.on_placement("dining",target,0)
			if app.pending_move.is_empty():moved=true;break
		if moved:break
	check(moved,"Paused public placement commits the moved table through Build validation")
	if moved:
		host=app._find_item(host_id);batch=app.household.meals.batch(source)
		var expected:Vector3=host.node.to_global(Vector3(batch.offset[0],batch.offset[1],batch.offset[2]))
		check(batch.position==[expected.x,expected.y,expected.z] and host.node.position!=old_position,"Explicit paused Build mutation reconciles food to its actual moved support")
		app.sell_item(host)
		check(app._find_item(host_id).is_empty(),"Public paused sale removes the original food support")
		batch=app.household.meals.batch(source)
		check(str(batch.host)!=host_id and str(batch.owner).is_empty(),"Deleted support safely relocates its unowned dish")
		check(app.meal_flow._floor_level(Vector3(batch.position[0],batch.position[1],batch.position[2]))==0,"Deleted support leaves food on the actual ground floor")
	app.set_build_mode(false);app.household.set_speed(0)
	before=app.household.meals.get_state();_step(3)
	check(_same_value(before,app.household.meals.get_state()),"Returning to paused Live preserves the explicitly reconciled placement")
	# Isolate the resume boundary without changing the authoritative host offset.
	var replacement:Dictionary=app.world.closest_item("counter",Vector3.ZERO)
	if replacement.is_empty():replacement=app.world.closest_item("desk",Vector3.ZERO)
	check(not replacement.is_empty(),"Authored house offers another real support for resume reconciliation")
	if not replacement.is_empty():
		batch=app.household.meals.batch(source)
		var slot:Vector3=app.meal_flow._surface_slot(replacement,LifeMeals.PLATTER_HALF_SIZE,source)
		if slot.is_finite():
			app.household.meals.set_batch_location(source,"surface",str(replacement.id),replacement.node.to_global(slot),app.meal_flow.now());batch.offset=[slot.x,slot.y,slot.z]
			batch.position[0]=float(batch.position[0])+.25
			var saved:Array=batch.position.duplicate();_step(2)
			check(batch.position==saved,"Paused presentation does not repair a controlled stale cached world coordinate")
			app.household.set_speed(1);_step(1)
			var expected:Vector3=replacement.node.to_global(slot)
			check(batch.position==[expected.x,expected.y,expected.z],"Resuming Live reconciles actual support geometry on its first simulation step")
		else:check(false,"Replacement support accepts the controlled platter")
	await _finish()
