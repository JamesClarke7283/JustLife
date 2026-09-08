extends RefCounted
class_name LifePhysicalSnapshot
## Read live physical facts into detached save data. Never bind a member, store
## movement, resolve an action, advance clocks or overwrite cached journeys.
static func capture(app:Node)->Dictionary:
	if not is_instance_valid(app.world):return {"error":"The current physical world is unavailable."}
	if app.world.construction.building_state.is_empty():
		return {} if app.household.journeys.is_empty() else {"error":"The current venue has no complete structure for its versioned physical snapshot."}
	for member:Dictionary in app.household.members:
		if not is_instance_valid(app.world.actors.get(str(member.id))):return {"error":"A current household actor is missing from its physical snapshot."}
	var layout:Array=app.world.serialize_items()
	var home:Array=layout.duplicate(true) if app.current_venue=="home" else app.home_layout.duplicate(true)
	var venues:Dictionary=app.venue_layouts.duplicate(true)
	if app.current_venue!="home":venues[app.current_venue]=layout.duplicate(true)
	var physical:Dictionary=app.traversal.snapshot()
	var states:Dictionary={}
	for member:Dictionary in app.household.members:
		var id:String=str(member.id);var actor:LifeActor=app.world.actors[id]
		var action:Dictionary=member.sim.get_current_action()
		var motion:Dictionary=app.motion_states.get(id,app._empty_motion()).duplicate(true)
		if id==app.bound_member_id:
			# A just-issued UI command can precede the next per-member store.
			motion.waiting=app.waiting_for_target;motion.wait_started=app.wait_started
			motion.resume_active=app.resume_activity;motion.walk=app.walk_only;motion.destination=app.walk_destination
		var state:Dictionary=member.sim.character.get("world_state",{}).duplicate(true)
		state.player=LifeJourneyState.packed(actor.position);state.player_rotation=actor.rotation.y
		state.resource_wait_started=float(motion.wait_started) if bool(motion.waiting) else -1.0
		state.resource_action_active=str(action.get("phase",""))=="active" or bool(motion.get("resume_active",false))
		state.waiting_action_id=str(action.get("id",""));state.waiting_target_id=str(action.get("target_id",""))
		if id==app.household.selected_id():
			state.merge({"camera":LifeJourneyState.packed(app.world.camera_target),"angle":app.world.camera_angle,"elevation":app.world.camera_elevation,"zoom":app.world.camera.size,"floor":app.floor_color,"lot":app.selected_lot,"cutaway":app.world.cutaway,"view_level":app.world.view_level,"sound":app.sound_enabled,"venue":app.current_venue,"home_layout":home,"venue_layouts":venues,"residents":app.residents.snapshot()},true)
		states[id]=state
		var journey:Dictionary=physical.members[id].motion
		if not journey.is_empty() and action.is_empty():
			journey.intent={"kind":"walk","destination":LifeJourneyState.packed(motion.destination)} if bool(motion.walk) else {"kind":"idle"}
	return {"journeys":physical,"world":layout,"members":states}
