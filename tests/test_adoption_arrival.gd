extends "res://tests/test_adoption.gd"
## Controlled controller/geometry interruption checks, not rendered movement proof.
var app:Node
func adopted() -> LifeSim:
	app.household_profiles=[{"name":"Arrival Guardian","age_stage":"adult","traits":[]}]
	app.creator_family_links=[];app.start_household();app.set_process(false);app.set_sound(false)
	app.household.set_speed(0);app.sim.autonomy=false
	app.adoption_flow.show_phone();app.adoption_flow.show_review(0)
	app.adoption_flow.confirm_adoption()
	check(app.household.members.size()==2,"Controller confirmation creates its actor and household entry together.")
	app.select_household_member(1)
	var child:LifeSim=app.sim;child.autonomy=false
	return child
func _run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
	var child:LifeSim=adopted();var action:Dictionary=child.get_current_action()
	var original:Vector3=action.target_position;var at:Vector3=app.player.position
	var wallet:int=app.household.funds;var clock:float=child.minutes
	var needs:Dictionary=child.needs.duplicate(true)
	app.adoption_flow.advance_arrival(1.0,action)
	check(app.player.position==at and child.minutes==clock and child.needs==needs,"Paused controller does not move, advance time or grant needs.")
	# Controlled actual-world furnishing mutation at the saved destination.
	app.world.add_item({"id":"arrival_blocker","kind":"plant","x":original.x,"z":original.z,"rotation":0},false)
	app.world.rebuild_navigation();app._refresh_sim_targets(false)
	child.set_speed(1);app.adoption_flow.advance_arrival(.01,action)
	check(action.target_position.distance_to(original)>=.5 and str(action.phase)=="approach","A new furnishing at the endpoint produces a different clear arrival route.")
	check(not app.path.is_empty() and app.path[-1].distance_to(action.target_position)<.001,"The rebuilt route reaches its exact reserved endpoint.")
	check(app.household.funds==wallet and not bool(action.paid) and float(action.elapsed)==0 and child.needs==needs,"Rerouting grants no payment, fake progress or need recovery.")
	var region:Rect2i=app.world.navigation.region
	for x:int in range(region.position.x,region.end.x):
		for z:int in range(region.position.y,region.end.y):app.world.navigation.set_point_solid(Vector2i(x,z),true)
	var blocked_at:Vector3=app.player.position
	app.adoption_flow.advance_arrival(.1,action)
	check(app.player.position==blocked_at and is_same(child.get_current_action(),action),"A wholly blocked test navigation region leaves the same child waiting without teleporting.")
	check(bool(app.adoption_flow.blocked.get("housemate_1",false)) and app.notice_label.text.contains("arrival route is blocked"),"Blocked arrival explains how to clear the path or cancel the walk.")
	app.world.remove_item("arrival_blocker");app.world.rebuild_navigation();app._refresh_sim_targets(false)
	app.adoption_flow.advance_arrival(.01,action)
	check(not bool(app.adoption_flow.blocked.get("housemate_1",false)) and app.player.position!=blocked_at,"Clearing the obstruction resumes the same route and clears the blocked status.")
	var shelf:Dictionary=app.world.closest_item("bookshelf",Vector3.ZERO)
	check(child.queue_action("read",str(shelf.id),app.world.approach(shelf)),"The child can retain a later explicit reading instruction during arrival.")
	var later:Dictionary=child.action_queue[1]
	app.player.position=action.target_position # Explicit controlled already-arrived boundary, no rendered claim.
	app.path.clear();app.path_index=0
	app.adoption_flow.advance_arrival(.01,action)
	check(is_same(child.get_current_action(),later) and str(later.id)=="read","An already-reached empty-path boundary completes arrival and starts the exact later instruction.")
	check(not app.path.is_empty() and app.path[-1].distance_to(later.target_position)<.001,"Synchronous later-action routing survives arrival cleanup.")
	check(app.household.funds==wallet and app.household.members.size()==2,"Arrival completion preserves the one confirmed membership and charge.")
	child=adopted();action=child.get_current_action();wallet=app.household.funds
	shelf=app.world.closest_item("bookshelf",Vector3.ZERO);child.queue_action("read",str(shelf.id),app.world.approach(shelf));later=child.action_queue[1]
	app.cancel_current_action()
	check(is_same(child.get_current_action(),later) and app.household.members.size()==2 and app.household.adoptions.events.size()==1 and app.household.funds==wallet,"Public cancel controller removes only the arrival walk and preserves the child, receipt and later instruction.")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(app.household.json_safe(app.household.get_state(app.world.serialize_items()))))
	positive(saved,"Canceled-arrival actor/controller household is save-valid.")
	var routes:Array=app._family_parent_routes([{"a":"morgan","b":"taylor","role":"parent"},{"a":"morgan","b":"wren","role":"parent"},{"a":"jamie","b":"wren","role":"parent"}],{"morgan":Vector2(0,24),"jamie":Vector2(222,24),"taylor":Vector2(0,162),"wren":Vector2(222,162)})
	check(routes.size()==3 and not routes.any(func(route:Dictionary)->bool:return str(route.a)=="jamie" and str(route.b)=="taylor"),"Mixed one/two-guardian diagram draws only the three actual parent edges.")
	check(routes[0].points[0]!=routes[1].points[0] and routes[1].points[-1]!=routes[2].points[-1],"Shared parents and children have separate connector ports, without a false common junction.")
	check(routes.all(func(route:Dictionary)->bool:return route.points[0].y==136.0 and route.points[-1].y==162.0),"Directed parent connectors end at the appropriate card boundaries.")
	var report:Dictionary={"checks":checks,"failures":failures,"method":"Controlled actual-world/controller boundaries, manual geometry and endpoint fixture; public movement separately rendered."}
	var file:=FileAccess.open("user://adoption_arrival_result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("ADOPTION_ARRIVAL ",JSON.stringify(report));app.queue_free();await process_frame;await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
