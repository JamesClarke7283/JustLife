extends SceneTree
## Controlled occupancy and player-intent checks, separate from public dining.
var app:Node
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func reset_pair()->void:
	for member:Dictionary in app.household.members:
		member.sim.action_queue.clear();member.sim.autonomy=false
		app.motion_states[str(member.id)]=app._empty_motion()
		app.world.actors[str(member.id)].position=Vector3(-4,.16,.25)
	app._bind_member("player");app.idle_space.review_in=0;app.household.set_speed(1)
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await process_frame;app.set_process(false);app.set_sound(false)
	app.household_profiles=[{"name":"Alex","age_stage":"adult"},{"name":"Blair","age_stage":"adult"}]
	app.start_household();app.set_process(false);await process_frame
	reset_pair()
	var positions:Array=[]
	for member:Dictionary in app.household.members:positions.append(app.world.actors[str(member.id)].position)
	var household_before:Dictionary=app.household.get_state()
	app.idle_space.update(.3)
	var yielding:int=0;var chosen:String=""
	for i:int in range(app.household.members.size()):
		var id:String=str(app.household.members[i].id);var motion:Dictionary=app.motion_states[id]
		if bool(motion.walk):yielding+=1;chosen=id
		check(app.world.actors[id].position==positions[i],"Courtesy planning never teleports "+id)
	check(yielding==1,"Only one of two coincident idle Lifelets yields")
	check(app.bound_member_id=="player" and app.household.selected_id()=="player","Courtesy preserves selected and bound Lifelet")
	check(app.household.get_state()==household_before,"Courtesy planning changes no needs, money, skills, queues or household state")
	if not chosen.is_empty():
		var motion:Dictionary=app.motion_states[chosen]
		check(motion.path.size()>1 and motion.path[-1]==motion.destination,"Courtesy uses a real route to its reserved destination")
		var before:Dictionary=motion.duplicate(true)
		app.idle_space.update(.3)
		check(app.motion_states[chosen]==before,"Existing courtesy walk is not repeatedly replanned")
	reset_pair()
	app.household.set_speed(0)
	var paused:Dictionary=app.motion_states.duplicate(true)
	app.idle_space.update(1)
	check(app.motion_states==paused,"Pause does not create courtesy movement")
	reset_pair()
	var shelf:Dictionary=app.world.closest_item("bookshelf",app.player.position)
	app.queue_interaction(shelf,"read")
	var queued:Dictionary=app.sim.get_current_action().duplicate(true)
	var requested_route:PackedVector3Array=app.path.duplicate()
	app._store_motion();app.idle_space.update(.3)
	check(app.sim.get_current_action()==queued,"Explicit queued reading remains unchanged")
	check(app.path==requested_route and not app.walk_only,"Courtesy preserves the player's approach route")
	app.sim.begin_current_action()
	app._clear_motion();app._store_motion()
	var active:Dictionary=app.sim.get_current_action().duplicate(true)
	app.idle_space.review_in=0;app.idle_space.update(.3)
	check(app.sim.get_current_action()==active and str(active.phase)=="active","Active reading is not interrupted to step aside")
	check(not bool(app.motion_states.player.walk),"Busy Lifelet receives no courtesy route")
	reset_pair()
	app.on_ground_clicked(Vector3(-4,.16,1.75));app._store_motion()
	var directed:Dictionary=app.motion_states.player.duplicate(true)
	check(bool(directed.walk),"Controlled fixture begins an actual player-directed ground walk")
	app.idle_space.update(.3)
	check(app.motion_states.player==directed,"Player-directed destination and route have priority over courtesy")
	app.queue_free();await process_frame;await process_frame
	var out:=FileAccess.open("user://idle_space_checks.json",FileAccess.WRITE);out.store_string(JSON.stringify({"checks":checks,"failures":failures}));out.close()
	print("IDLE_SPACE %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
