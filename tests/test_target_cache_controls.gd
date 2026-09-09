extends "res://tests/test_home_visit.gd"
var cold:Dictionary={}
func _uncached()->Array:
	var expected:Array=[{"id":"lot_exit","kind":"lot_exit","position":app.world.lot_exit_position()}]
	for item:Dictionary in app.world.items:
		var at:Vector3=app.world.approach(item)
		if at.is_finite():expected.append({"id":item.id,"kind":item.kind,"position":at,"level":app.world.item_level(item)})
	for id:String in app.world.actors:
		if bool(app.world.actors[id].get_meta("away",false)):continue
		expected.append({"id":id,"kind":"neighbor","position":app.world.actors[id].position+Vector3(0,0,.8)})
	return expected
func _verify(label:String)->void:
	var before:Dictionary=_facts()
	var actual:Array=app.world.simulation_targets()
	check(_same_value(actual,_uncached()),label+": exact cached versus original uncached targets")
	check(_same_value(before,_facts()),label+": target reads preserve layout, household, queues, clocks and physical state")
func _position(id:String)->Vector3:
	for item:Dictionary in app.world.simulation_targets():
		if str(item.id)==id:return item.position
	return Vector3.INF
func _transient(id:String,puddle:bool,point:Vector3)->Dictionary:
	var node:=Node3D.new();app.world.house.add_child(node);node.position=point
	var item:Dictionary={"id":id,"kind":"puddle" if puddle else "plate","node":node,"size":Vector2(.35,.35),"level":0,"transient_food":not puddle,"transient_puddle":puddle}
	app.world.items.append(item);return item
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false);_setup()
	_step(3)
	app.world.rebuild_navigation()
	var started:int=Time.get_ticks_usec();app.world.simulation_targets();cold.first_target_query_ms=(Time.get_ticks_usec()-started)/1000.0
	app.world.rebuild_navigation()
	started=Time.get_ticks_usec();_step();cold.first_controller_step_ms=(Time.get_ticks_usec()-started)/1000.0
	cold.warm_steps_ms=[]
	for index:int in 20:
		started=Time.get_ticks_usec();_step();cold.warm_steps_ms.append((Time.get_ticks_usec()-started)/1000.0)
	_verify("Warm unchanged scene")
	var item:Dictionary=app.world.items.filter(func(value:Dictionary)->bool:return str(value.kind)=="chair")[0]
	var transform:Transform3D=item.node.transform;var size:Vector2=item.size;var level:int=app.world.item_level(item)
	item.node.position.x+=.5;_verify("Moved furnishing before navigation rebuild")
	item.node.rotation.y+=PI*.5;_verify("Rotated furnishing before navigation rebuild")
	item.size=Vector2(size.x,size.y+.75);_verify("Resized furnishing approach")
	item.level=1;item.node.position.y=LifeBuildingState.level_y(1);_verify("Changed floor level")
	item.node.transform=transform;item.size=size;item.level=level;_verify("Restored furnishing")
	var parent:Node3D=item.node.get_parent();var parent_transform:Transform3D=parent.transform
	parent.position.x+=.5;_verify("Moved furnishing parent transform")
	parent.transform=parent_transform;_verify("Restored parent transform")
	var food:Dictionary=_transient("cache_food",false,Vector3(4,.9,7))
	_verify("New transient food")
	var previous:Vector3=_position("cache_food");food.node.position.x-=1;_verify("Moving transient food")
	check(_position("cache_food")!=previous,"Moving food actually changes its target")
	var puddle:Dictionary=_transient("cache_puddle",true,Vector3(-4,.16,7))
	_verify("New transient puddle")
	previous=_position("cache_puddle");puddle.node.position.x+=1;_verify("Moving transient puddle")
	check(_position("cache_puddle")!=previous,"Moving puddle actually changes its target")
	food.node.position=Vector3(4,.16,6);food.size=Vector2(1,1.2);previous=_position("cache_food")
	food.transient_puddle=true;_verify("Changed transient approach behavior")
	check(_position("cache_food")!=previous,"Transient behavior change exercises a different approach")
	food.transient_puddle=false
	var retired:int=food.node.get_instance_id();app.world.items=app.world.items.filter(func(value:Dictionary)->bool:return str(value.id)!="cache_food")
	food.node.queue_free();_verify("Removed transient item without a geometry rebuild")
	check(not app.world._target_approaches.has(retired),"Removed node is pruned from the memo table")
	food=_transient("cache_food",false,Vector3(5,.9,7));_verify("Reused item ID with a new node")
	check(food.node.get_instance_id()!=retired,"Reused item ID has distinct physical node ownership")
	previous=_position("maya");app.world.actors.maya.position.x+=.5;_verify("Moving resident")
	check(_position("maya")!=previous,"Live actor target updates immediately")
	app.world.set_actor_away("maya",true,true);_verify("Departed resident")
	check(not _position("maya").is_finite(),"Absent resident is removed from live targets")
	app.world.set_actor_away("maya",false,false)
	var prior_generation:int=app.world.lot_navigation.generation
	var state:Dictionary=app.world.lot_navigation.state_snapshot()
	var obstacles:Array=app.world.lot_navigation._obstacles.duplicate(true)
	var at:Vector3=_position("cache_food")
	obstacles.append({"id":"cache_obstacle","level":0,"x":at.x,"z":at.z,"w":.5,"d":.5})
	check(bool(app.world.lot_navigation.rebuild(state,obstacles).ok),"Direct navigation rebuild accepts a changed obstacle")
	_verify("Successful navigation generation change")
	check(app.world.lot_navigation.generation>prior_generation and _position("cache_food")!=at,"Changed navigation invalidates an otherwise unchanged target")
	prior_generation=app.world.lot_navigation.generation
	var before_targets:Array=app.world.simulation_targets()
	check(not bool(app.world.lot_navigation.rebuild({"version":-1}).ok),"Malformed navigation rebuild is rejected")
	check(app.world.lot_navigation.generation==prior_generation and _same_value(before_targets,app.world.simulation_targets()),"Rejected navigation preserves the previous exact target set")
	_verify("Rejected direct navigation rebuild")
	var building:Dictionary=app.world.construction.building_state
	app.world.construction.building_state=building.duplicate(true);app.world.construction.building_state.version=-1
	app.world.rebuild_navigation()
	check(not app.world.last_layout_error.is_empty() and app.world._target_approaches.is_empty(),"Failed world rebuild clears memoized compatibility-grid queries")
	app.world.construction.building_state=building;_verify("Failed world rebuild retains original navigation answers")
	app.world.rebuild_navigation();app.world.last_layout_error="";_verify("Successful world geometry rebuild")
	var navigation=app.world.lot_navigation
	var replacement:=LifeLotNavigation.new();check(bool(replacement.rebuild(navigation.state_snapshot(),navigation._obstacles).ok),"Replacement navigation instance is valid")
	# Equal generation counters on separate objects must not alias one cache.
	replacement.generation=navigation.generation;app.world.lot_navigation=replacement
	_verify("Navigation object replacement at an equal generation")
	check(app.world._target_navigation_id==replacement.get_instance_id(),"Memo ownership follows the current navigation object")
	var file:=FileAccess.open("user://target_cache_controls.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"timing":cold},"",true,true));file.close()
	await _finish()
