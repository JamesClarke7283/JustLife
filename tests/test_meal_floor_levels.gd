extends "res://tests/test_build_world_levels.gd"
## Actual imported two-floor world with controlled meal callbacks and ray queries.
## This does not claim normal-frame traversal or public save/custody coverage.
class FoodApp:
	extends Node
	var world:LifeWorld
	var household:LifeHousehold
	var current_venue:String="home"
	var pending_move:Dictionary={}
	var motion_states:Dictionary={}
	func _find_item(id:String)->Dictionary:
		for entry:Dictionary in world.items:
			if str(entry.id)==id:return entry
		return {}
var food_app:FoodApp
var flow:LifeMealFlow
var scene_world:LifeWorld
var member_ids:Array[String]=[]
var began:int=0

func _position(value:Dictionary)->Vector3:return Vector3(value.position[0],value.position[1],value.position[2])
func _floor_batch(at:Vector3)->Dictionary:
	var chef:String=""
	for person:String in member_ids:
		if food_app.household.meals.carried_by(person).is_empty():chef=person;break
	assert(not chef.is_empty(),"Fixture needs a cook who is not holding another plate.")
	var value:Dictionary=food_app.household.meals.create_batch("garden_skillet",chef,1,"home",480)
	assert(not value.is_empty(),"Fixture batch must exist before further cases.")
	food_app.household.meals.set_batch_location(str(value.id),"surface","",at,480)
	return value
func _hosted_batch(id:String)->Dictionary:
	var host:Dictionary=food_app._find_item(id)
	var value:Dictionary=_floor_batch(host.node.to_global(Vector3(0,LifeMeals.SURFACE_HEIGHTS.dining,0)))
	value.host=id;value.offset=[0.0,LifeMeals.SURFACE_HEIGHTS.dining,0.0]
	return value
func _save()->Dictionary:
	var saved:Dictionary=food_app.household.get_state(scene_world.serialize_items())
	saved.household_version=2.0 # Exercise JSON-number equality, independent of journey validator.
	return JSON.parse_string(JSON.stringify(food_app.household.selected()._json_safe(saved)))
func _validate(saved:Dictionary)->String:return LifeMeals.validate_layout(saved.meals,saved)
func _layout_entry(saved:Dictionary,id:String)->Dictionary:
	for entry:Dictionary in saved.world:
		if str(entry.get("id",""))==id:return entry
	return {}

func _run()->void:
	food_app=FoodApp.new();root.add_child(food_app)
	scene_world=World.new();food_app.add_child(scene_world);food_app.world=scene_world
	food_app.household=LifeHousehold.new();food_app.add_child(food_app.household)
	food_app.household.new_household([{"name":"Ground diner","age_stage":"adult"},{"name":"Upper diner","age_stage":"child"}])
	for member:Dictionary in food_app.household.members:
		member_ids.append(str(member.id));member.sim.autonomy=false
	flow=LifeMealFlow.new();food_app.add_child(flow);flow.app=food_app
	food_app.household.member_action_started.connect(func(_id:String,_action:Dictionary):began+=1)
	await process_frame
	var state:Dictionary=fixture()
	var layout:Array=[]
	for level:int in [0,1]:
		layout.append({"id":"table"+str(level),"kind":"dining","x":-2.0,"z":0.0,"rotation":0.0,"level":level})
		layout.append({"id":"chair"+str(level),"kind":"chair","x":-2.0,"z":-1.0,"rotation":0.0,"level":level})
	layout.append(state)
	var loaded:Dictionary=scene_world.load_home(layout)
	check(bool(loaded.ok),"Actual two-floor meal fixture validates/imports.")
	if not bool(loaded.ok):_finish_food();return
	for member:Dictionary in food_app.household.members:
		var avatar:=LifeActor.new();scene_world.add_child(avatar);avatar.configure(member.sim.character);avatar.voice_enabled=false
		scene_world.actors[str(member.id)]=avatar
	for index:int in member_ids.size():scene_world.actors[member_ids[index]].position=Vector3(2,Building.level_y(index),2.5)
	await process_frame;await physics_frame
	_floor_support_cases()
	_floor_query_rebuild_cases()
	_surface_and_standing_cases()
	await _food_views_and_validation()
	_seated_and_held_cases()
	_cancel_and_failure_cases()
	_routed_selection()
	_legacy_ground_cases()
	_finish_food()

func _floor_support_cases()->void:
	var ground:=Vector3(2,.16,2.5);var upper:=Vector3(2,3.16,2.5)
	check(absf(flow._floor_height(ground)-.162)<.00001,"Ground dish support measures the ground slab.")
	check(absf(flow._floor_height(upper)-3.162)<.00001,"Coincident upper dish support measures the upper slab.")
	check(absf(flow._floor_support(upper,LifeMeals.PLATE_HALF_SIZE)-3.162)<.00001,"Whole upper plate footprint is supported at upper height.")
	check(not is_finite(flow._floor_height(Vector3(2,1.6,2.5))),"Mid-stair height is not silently projected onto a floor.")
	check(not is_finite(flow._floor_support(Vector3(0,3.16,0),LifeMeals.PLATE_HALF_SIZE)),"Actual stair opening does not support a floor dish.")
	check(not is_finite(flow._floor_support(Vector3(3.95,3.16,2.5),LifeMeals.PLATE_HALF_SIZE)),"A plate overhanging the upper slab is rejected.")
	check(not is_finite(flow._floor_support(Vector3(-2,3.16,0),LifeMeals.PLATE_HALF_SIZE)),"Upper table footprint blocks an upper floor dish.")
	scene_world.remove_item("table1")
	check(is_finite(flow._floor_support(Vector3(-2,3.16,0),LifeMeals.PLATE_HALF_SIZE)),"Ground table at coincident XZ does not block clear upper floor.")
	scene_world.add_item({"id":"table1","kind":"dining","x":-2.0,"z":0.0,"rotation":0.0,"level":1})
	var first:Dictionary=_floor_batch(Vector3(2,.162,2.5));var second:Dictionary=_floor_batch(Vector3(2,3.162,2.5))
	var body_blocked:Vector3=flow._floor_slot(upper,second)
	check(body_blocked.is_finite() and Vector2(body_blocked.x-upper.x,body_blocked.z-upper.z).length()>=.45,"Actual upper Lifelet feet displace a floor dish to a supported clear point.")
	scene_world.actors[member_ids[1]].position=Vector3(3,3.16,4)
	var slot:Vector3=flow._floor_slot(upper,second)
	check(slot.is_equal_approx(Vector3(2,3.162,2.5)),"Ground dish does not displace upper dish at coincident XZ.")
	var third:Dictionary=_floor_batch(Vector3(1,3.162,2.5));var distinct:Vector3=flow._floor_slot(upper,third)
	check(distinct.is_finite() and absf(distinct.y-3.162)<.00001 and Vector2(distinct.x-slot.x,distinct.z-slot.z).length()>.25,"Two dishes on the same upper floor receive distinct supported slots.")
	check(not flow._floor_slot(Vector3(2,1.6,2.5),third).is_finite(),"Mid-stair set-down query has no floor slot.")
	food_app.household.meals.clear()

func _floor_query_rebuild_cases()->void:
	# Return-value checks use real geometry/ledger changes, never cache fields.
	# The upper actor forces grid fallback so a removed obstacle's newly free
	# cells matter; an unblocked exact origin would bypass that regression.
	var actor:LifeActor=scene_world.actors[member_ids[1]];var before_body:Vector3=actor.position
	var origin:=Vector3(2.125,3.16,2.625)
	var value:Dictionary=_floor_batch(origin);var generation:int=scene_world.lot_navigation.generation
	var open:Vector3=flow._floor_slot(origin,value)
	check(open.is_finite() and Vector2(open.x,open.z)==Vector2(origin.x,origin.z),"Clear off-grid origin is the preferred floor slot.")
	actor.position=origin
	var preferred:Vector3=flow._floor_slot(origin,value)
	var mirror:=Vector3(2*origin.x-preferred.x,preferred.y,2*origin.z-preferred.z)
	var gap:Vector2=LifeMeals.PLATTER_HALF_SIZE+Vector2(.30,.30)
	check(preferred.is_finite() and preferred!=open and preferred!=mirror and preferred.distance_squared_to(origin)==mirror.distance_squared_to(origin),"Blocking the origin produces a genuinely tied grid fallback.")
	check(flow._floor_navigation_clear(mirror) and is_finite(flow._floor_support(mirror,LifeMeals.PLATTER_HALF_SIZE)) and (absf(mirror.x-origin.x)>=gap.x or absf(mirror.z-origin.z)>=gap.y),"Distinct equidistant contender clears navigation, whole dish support and the blocking actor.")
	check(flow._floor_slot(origin,value)==preferred,"Repeated floor search keeps the same tied choice.")
	actor.position=before_body
	check(flow._floor_slot(origin,value)==open and scene_world.lot_navigation.generation==generation,"Moving the body frees the origin immediately without a rebuild.")
	var other:Dictionary=_floor_batch(open)
	check(flow._floor_slot(origin,value)!=open,"New floor food immediately displaces a previously clear slot.")
	food_app.household.meals.set_batch_location(str(other.id),"surface","",Vector3(3,3.162,4),480)
	check(flow._floor_slot(origin,value)==open and scene_world.lot_navigation.generation==generation,"Moving food frees the same slot without a rebuild.")
	food_app.household.meals.clear();actor.position=origin
	var floors:Array=_floor_boxes(scene_world,1);var visibility:Array=[]
	for node:MeshInstance3D in floors:visibility.append(node.visible);node.visible=false
	check(not flow._floor_slot(origin,value).is_finite(),"Hidden upper floor meshes cannot support a cached upper slot.")
	for i:int in floors.size():floors[i].visible=visibility[i]
	check(flow._floor_slot(origin,value)==preferred and scene_world.lot_navigation.generation==generation,"Restored physical floor support is observed without a rebuild.")
	var outward:=Vector3(preferred.x-origin.x,0,preferred.z-origin.z).normalized()
	var obstacle:Vector3=preferred+outward*.35
	scene_world.add_item({"id":"query_plant","kind":"plant","x":obstacle.x,"z":obstacle.z,"rotation":0.0,"level":1})
	# Warm a fresh query while blocked; a formerly clear cached grid could
	# otherwise hide a missed invalidation through the final clearance check.
	var queries:=LifeMealFlow.new();food_app.add_child(queries);queries.app=food_app
	var blocked:Vector3=queries._floor_slot(origin,value)
	check(scene_world.lot_navigation.generation>generation and blocked.is_finite() and blocked!=preferred,"A real added furnishing and successful rebuild displace the old preferred grid cell.")
	generation=scene_world.lot_navigation.generation
	var state:Dictionary=scene_world.construction.building_state.duplicate(true)
	var prior_error:String=scene_world.last_layout_error
	scene_world.construction.building_state.version=999;scene_world.rebuild_navigation()
	check(scene_world.lot_navigation.generation==generation and not scene_world.last_layout_error.is_empty() and queries._floor_slot(origin,value)==blocked,"Rejected world validation retains the old navigation's selected floor slot.")
	scene_world.construction.building_state=state;scene_world.last_layout_error=prior_error
	scene_world.remove_item("query_plant")
	check(scene_world.lot_navigation.generation>generation and queries._floor_slot(origin,value)==preferred,"Removing the furnishing and rebuilding restores the newly free tied cell.")
	# Warm while blocked again, then replace the navigation with the same
	# generation reached by actual successful rebuilds, not a counter edit.
	scene_world.add_item({"id":"query_plant","kind":"plant","x":obstacle.x,"z":obstacle.z,"rotation":0.0,"level":1})
	check(queries._floor_slot(origin,value)!=preferred,"Replacement control starts from the blocked cached grid.")
	var previous:LifeLotNavigation=scene_world.lot_navigation;generation=previous.generation
	scene_world.remove_item("query_plant");scene_world.lot_navigation=LifeLotNavigation.new()
	for i:int in generation:scene_world.rebuild_navigation()
	check(scene_world.lot_navigation!=previous and scene_world.lot_navigation.generation==generation and queries._floor_slot(origin,value)==preferred,"A new navigation instance at the same generation restores its own clear tied cell.")
	queries.free();actor.position=before_body;food_app.household.meals.clear()

func _surface_and_standing_cases()->void:
	for level:int in [0,1]:
		check(str(flow._chair_table(food_app._find_item("chair"+str(level))).get("id",""))=="table"+str(level),"Chair finds table on its own floor "+str(level))
	var value:Dictionary=_floor_batch(Vector3(-2,3.16,.7))
	check(flow.call("_settle_food",value,Vector3(-2,3.16,.7))==true and str(value.host)=="table1" and absf(_position(value).y-4.007)<.00001,"Nearby set-down uses upper table at coincident XZ.")
	value.offset=[0,0,0]
	check(not flow._surface_clear(food_app._find_item("table1"),Vector3.ZERO,LifeMeals.PLATTER_HALF_SIZE),"Horizontal containment alone cannot certify a dish underneath the table top.")
	check(flow.call("_settle_food",value,Vector3(-2,3.16,.7))==true and absf(_position(value).y-4.007)<.00001,"An invalid historical support offset is repaired to a real tabletop slot.")
	scene_world.remove_item("table1");value.host="";value.offset=[0,0,0]
	check(flow.call("_settle_food",value,Vector3(-2,3.16,.7))==true and str(value.host).is_empty() and absf(_position(value).y-3.162)<.00001,"Absent upper table falls back to upper floor, never lower table.")
	scene_world.add_item({"id":"table1","kind":"dining","x":-2.0,"z":0.0,"rotation":0.0,"level":1})
	food_app.household.meals.clear()
	var at:=Vector3(2,3.16,2.5)
	check(flow.standing_geometry_clear(at),"Standing dining accepts exact supported upper navigation point.")
	check(not flow.standing_geometry_clear(at+Vector3(0,-.2,0)),"Standing dining rejects an ungrounded vertical offset.")
	check(flow._standing_clear(member_ids[1],at),"Ground Lifelet at same XZ does not occupy upper standing space.")
	var lower:LifeActor=scene_world.actors[member_ids[0]];lower.position.y=3.16
	check(not flow._standing_clear(member_ids[1],at),"Same-floor Lifelet does occupy standing space.")
	lower.position.y=.16
	var standing:Vector3=flow._standing_slot(member_ids[1])
	check(standing.is_finite() and absf(standing.y-3.16)<.00001,"Standing slot search stays on the actor's actual upper floor.")
	var sim:LifeSim=food_app.household.member_sim(member_ids[0]);sim.action_queue=[{"id":"eat_meal","meal_standing":true,"phase":"active","target_position":Vector3(2,.16,2.5)}]
	check(not flow.standing_place_blocks(member_ids[1],{"id":"read","target_position":at}),"Lower standing reservation does not block upper activity.")
	sim.action_queue[0].target_position=at
	check(flow.standing_place_blocks(member_ids[1],{"id":"read","target_position":at}),"Same-floor standing reservation blocks competing activity.")
	sim.action_queue.clear()

func _food_views_and_validation()->void:
	var lower:Dictionary=_hosted_batch("table0");var upper:Dictionary=_hosted_batch("table1")
	var floor_lower:Dictionary=_floor_batch(Vector3(2,.162,1.5));var floor_upper:Dictionary=_floor_batch(Vector3(2,3.162,1.5))
	var before:String=JSON.stringify(food_app.household.meals.get_state());var events:int=began
	flow.sync_world(false)
	check(JSON.stringify(food_app.household.meals.get_state())==before and began==events,"Quiet restoration creates food views without ledger mutation or starting actions.")
	for pair:Array in [[lower,0],[upper,1],[floor_lower,0],[floor_upper,1]]:
		var value:Dictionary=pair[0];var level:int=pair[1];var entry:Dictionary=food_app._find_item(str(value.id));var node:Node3D=flow.views[value.id]
		check(scene_world.item_level(entry)==level,"Food target records actual level "+str(value.id))
		# Food carries its support floor's pick bit, and the surface bit that lets
		# it be picked ahead of the furniture it rests on.
		var floor_bit:int=World.PICK_GROUND if level==0 else World.PICK_UPPER
		var layer:int=node.get_node("FoodPicking").collision_layer
		check((layer&floor_bit)==floor_bit and (layer&World.PICK_SURFACE)==World.PICK_SURFACE,"Food picking mask follows support floor "+str(value.id))
		check(node.find_children("*","MeshInstance3D",true,false).all(func(mesh:MeshInstance3D)->bool:return mesh.layers==(World.VIEW_GROUND if level==0 else World.VIEW_UPPER)),"Every food mesh follows its support view layer "+str(value.id))
	await physics_frame;await physics_frame
	for level:int in [0,1]:
		var query:=PhysicsRayQueryParameters3D.create(Vector3(2,5,1.5),Vector3(2,-.2,1.5),World.PICK_GROUND if level==0 else World.PICK_UPPER)
		var hit:Dictionary=scene_world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and str(hit.collider.get_meta("item_id",""))==str(floor_lower.id if level==0 else floor_upper.id),"Real physics ray selects coincident floor dish on requested level "+str(level))
	var saved:Dictionary=_save();check(_validate(saved).is_empty(),"Exact JSON-number V2 hosted and floor dishes validate on both levels.")
	for bad_level:Variant in [true,false,1.5,-1,2,"1",null,[],{}]:
		var bad:Dictionary=saved.duplicate(true);_layout_entry(bad,"table1").level=bad_level
		check(not _validate(bad).is_empty(),"Malformed host level rejected atomically: "+str(bad_level))
	var moved:Dictionary=saved.duplicate(true);_layout_entry(moved,"table1").level=0
	check(not _validate(moved).is_empty(),"Upper food position cannot validate against ground host with same XZ.")
	for absence:Variant in [null,[],{},"missing"]:
		var bad:Dictionary=saved.duplicate(true);bad.world=absence
		check(not _validate(bad).is_empty(),"V2 absent or malformed venue layout rejected: "+str(absence))
	var old_component:Dictionary=saved.duplicate(true);old_component.household_version=1;old_component.erase("world")
	check(_validate(old_component).is_empty(),"Legacy V1 detached component state may still omit furniture.")
	for bad_at:Vector3 in [Vector3(0,3.162,0),Vector3(3.95,3.162,1.5),Vector3(2,1.6,1.5),Vector3(-2,3.162,0),Vector3(2,-.148,1.5)]:
		var bad:Dictionary=saved.duplicate(true);bad.meals.batches[3].position=[bad_at.x,bad_at.y,bad_at.z]
		check(not _validate(bad).is_empty(),"V2 unsupported/opening/overlap floor position rejected: "+str(bad_at))
	var no_marker:Dictionary=saved.duplicate(true);no_marker.world=no_marker.world.filter(func(entry:Dictionary)->bool:return str(entry.get("kind",""))!="__construction")
	check(not _validate(no_marker).is_empty(),"V2 floor dishes require actual saved building support.")
	var offsetless:Dictionary=saved.duplicate(true);offsetless.meals.batches[1].erase("offset")
	check(not _validate(offsetless).is_empty(),"V2 hosted dish cannot omit its supporting offset.")
	var remote:Dictionary=saved.duplicate(true);remote.meals.batches[1].venue="park";remote.members[0].state.character.world_state={"venue":"home","venue_layouts":{"park":saved.world}}
	check(_validate(remote).is_empty(),"Stored other-venue food validates against that venue's supplied layout.")
	remote.members[0].state.character.world_state.venue_layouts.erase("park")
	check(not _validate(remote).is_empty(),"V2 food cannot bypass checks through a missing other-venue layout.")
	check(JSON.stringify(food_app.household.meals.get_state())==before,"All malformed-layout probes leave the live food ledger exact.")
	food_app.household.meals.clear();flow.sync_world(false)

func _seated_and_held_cases()->void:
	var plates:Array=[]
	for level:int in [0,1]:
		var batch:Dictionary=_hosted_batch("table"+str(level));var person:String=member_ids[level]
		var plate:Dictionary=food_app.household.meals.claim(str(batch.id),person,flow.now());plates.append(plate)
		var sim:LifeSim=food_app.household.member_sim(person);sim.needs.hunger=20
		var chair:Dictionary=food_app._find_item("chair"+str(level));scene_world.actors[person].position=scene_world.approach(chair)
		var action:Dictionary=sim.get_action_definition("eat_meal")
		action.merge({"target_id":str(chair.id),"target_position":scene_world.approach(chair),"meal_plate":str(plate.id),"meal_source":str(batch.id),"meal_seat":str(chair.id),"meal_stage":"eat","phase":"active","progress":0.0,"elapsed":0.0,"autonomous":false},true);sim.action_queue=[action]
		check(flow.before_begin(sim,action),"Controlled real chair arrival starts seated eating on floor "+str(level))
		check(str(plate.host)=="table"+str(level) and absf(_position(plate).y-(Building.level_y(level)+LifeMeals.SURFACE_HEIGHTS.dining))<.00001,"Seated plate rests on actual table top on floor "+str(level))
		flow.consume(sim,action,8)
		check(absf(float(plate.progress)-.25)<.000001 and absf(float(sim.needs.hunger)-37.5)<.000001,"Each floor diner consumes one real quarter serving without synthetic reward "+str(level))
	var state_before:String=JSON.stringify(food_app.household.meals.get_state());var queue_before:Array=[]
	for member:Dictionary in food_app.household.members:queue_before.append(JSON.stringify(member.sim._json_safe(member.sim.action_queue)))
	var events:int=began;flow.sync_world(false)
	check(JSON.stringify(food_app.household.meals.get_state())==state_before and began==events,"Quiet seated reconstruction preserves exact food progress/owners without callbacks.")
	for i:int in member_ids.size():
		check(JSON.stringify(food_app.household.member_sim(member_ids[i])._json_safe(food_app.household.member_sim(member_ids[i]).action_queue))==queue_before[i],"Quiet seated reconstruction preserves exact action queue on floor "+str(i))
	var saved:Dictionary=_save();check(_validate(saved).is_empty(),"Both real seated plates/offsets/chairs pass direct V2 JSON layout validation.")
	var wrong:Dictionary=saved.duplicate(true);_layout_entry(wrong,"chair1").level=0
	check(not _validate(wrong).is_empty(),"Seated plate cannot use a chair from the other floor at coincident XZ.")
	# Pickup can retain historical host metadata. Presentation follows the real
	# carrier, not that former table. Custody/action validation is root-owned.
	var plate:Dictionary=plates[0];plate.storage="carried"
	var carrier:LifeActor=scene_world.actors[member_ids[0]];carrier.position=Vector3(2,3.16,2.5)
	flow.sync_world(false)
	var view:Node3D=flow.views[plate.id]
	check(scene_world.item_level(food_app._find_item(str(plate.id)))==1 and view.get_node("FoodPicking").collision_layer==0,"Held food with old lower host follows upper carrier and is not independently pickable.")
	check(view.find_children("*","MeshInstance3D",true,false).all(func(mesh:MeshInstance3D)->bool:return mesh.layers==World.VIEW_ACTOR_UPPER),"Held upper food receives the upper actor view mask.")
	carrier.position.y=1.6;flow.sync_world(false)
	check(view.find_children("*","MeshInstance3D",true,false).all(func(mesh:MeshInstance3D)->bool:return mesh.layers==(World.VIEW_ACTOR_GROUND|World.VIEW_ACTOR_UPPER)),"In-flight held presentation spans both views without inventing a settled floor.")
	carrier.position.y=.16
	for member:Dictionary in food_app.household.members:member.sim.action_queue.clear()
	food_app.household.meals.clear();flow.sync_world(false)

func _cancel_and_failure_cases()->void:
	var sim:LifeSim=food_app.household.member_sim(member_ids[1]);var avatar:LifeActor=scene_world.actors[member_ids[1]];avatar.position=Vector3(2,3.16,2.5)
	var batch:Dictionary=_floor_batch(Vector3(2,3.162,2.5));var plate:Dictionary=food_app.household.meals.claim(str(batch.id),member_ids[1],480)
	plate.progress=.25
	var action:Dictionary={"id":"eat_meal","meal_plate":str(plate.id),"meal_stage":"eat","phase":"active"};var later:Dictionary={"id":"read","target_id":"book","autonomous":false}
	sim.action_queue=[action,later]
	flow.canceled(sim,action)
	check(str(plate.owner).is_empty() and absf(_position(plate).y-3.162)<.00001 and absf(float(plate.progress)-.25)<.000001,"Controlled held cancellation settles actual partial food on reached upper landing.")
	check(int(batch.served)==1 and int(batch.remaining)==3 and is_same(sim.action_queue[1],later),"Set-down preserves servings and exact later explicit queue.")
	sim.action_queue.clear();food_app.household.meals.clear()
	var value:Dictionary=_floor_batch(Vector3(2,3.162,2.5));var old:Dictionary=value.duplicate(true)
	check(flow.call("_settle_food",value,Vector3(2,1.6,2.5))==false and value==old,"Intermediate-stair set-down returns false without mutating candidate food.")
	var blocker:=Node3D.new();scene_world.furniture.add_child(blocker);blocker.position=Vector3(0,3.16,0)
	scene_world.items.append({"id":"controlled_no_slot","kind":"plant","level":1,"node":blocker,"size":Vector2(18,16)})
	check(flow.call("_settle_food",value,Vector3(2,3.16,2.5))==false and value==old,"Controlled fully blocked floor returns false without changing ledger placement.")
	scene_world.items=scene_world.items.filter(func(entry:Dictionary)->bool:return str(entry.id)!="controlled_no_slot");blocker.free();food_app.household.meals.clear()

func _routed_selection()->void:
	scene_world.remove_item("table0");scene_world.remove_item("chair0")
	var from:=Vector3(2,.16,2.5);scene_world.actors[member_ids[0]].position=from
	var surface:Dictionary=flow._serving_surface(from)
	check(str(surface.get("id",""))=="table1","Serving may choose a reachable other-floor table through the real stair route.")
	var route:PackedVector3Array=scene_world.path_to(from,scene_world.approach(food_app._find_item("table1")))
	check(not route.is_empty() and Array(route).any(func(point:Vector3)->bool:return point.y>.2 and point.y<3.1),"Cross-floor service selection includes actual intermediate stair path points.")
	var action:Dictionary={}
	check(flow._choose_seat(member_ids[0],action) and str(action.get("meal_seat",""))=="chair1","Diner may choose a reachable other-floor chair; table pairing stays on that floor.")

func _legacy_ground_cases()->void:
	var loaded:Dictionary=scene_world.load_home([])
	check(bool(loaded.ok),"Legacy starter home loads for actual wood/lawn compatibility checks.")
	for sample:Dictionary in [{"name":"wood","at":Vector3(-.75,.16,2.75),"height":.1295},{"name":"lawn","at":Vector3(7,.16,2),"height":-.093}]:
		var value:Dictionary=_floor_batch(sample.at)
		check(flow.call("_settle_food",value,sample.at)==true and str(value.host).is_empty() and absf(_position(value).y-float(sample.height))<.00001,"Legacy "+str(sample.name)+" set-down measures its actual authored top.")
		check(absf(flow._floor_support(_position(value),LifeMeals.PLATTER_HALF_SIZE)-float(sample.height))<.00001,"Saved physical "+str(sample.name)+" height retains floor identity below navigationY.")
	check(_validate(_save()).is_empty(),"V2 layout validation accepts real legacy wood and lawn food supports.")
	var lawn:Dictionary=food_app.household.meals.batches[-1];var origin:=Vector3(7.125,.16,2.125)
	var actor:=LifeActor.new();scene_world.add_child(actor);actor.voice_enabled=false;actor.set_process(false);actor.position=origin
	scene_world.actors["floor_query_legacy"]=actor
	var slot:Vector3=flow._floor_slot(origin,lawn);var generation:int=scene_world.lot_navigation.generation
	var cell:=Vector2i(roundi(slot.x*4),roundi(slot.z*4))
	scene_world.navigation.set_point_solid(cell,true)
	var queries:=LifeMealFlow.new();food_app.add_child(queries);queries.app=food_app
	check(queries._floor_slot(origin,lawn)!=slot and scene_world.lot_navigation.generation==generation,"Legacy blocked-cell fixture starts with a different floor fallback.")
	scene_world.navigation.set_point_solid(cell,false)
	check(queries._floor_slot(origin,lawn)==slot,"Restoring a legacy cell without a generation change restores its preferred fallback.")
	queries.free();scene_world.actors.erase("floor_query_legacy");actor.free()

func _finish_food()->void:
	check(checks>=86,"All intended floor, seated and held phases reached their assertions.")
	var report:Dictionary={"checks":checks,"failures":failures,"scope":"Actual imported floor/furniture geometry, floor-aware placement, real physics picking rays, strict direct JSON layout validation, controlled release callback. No normal-frame traversal or public save/custody acceptance."}
	DirAccess.make_dir_recursive_absolute("user://regression/evidence")
	FileAccess.open("user://regression/evidence/meal_floor_levels.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MEAL_FLOOR_LEVELS checks=",checks," failures=",failures.size());food_app.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
