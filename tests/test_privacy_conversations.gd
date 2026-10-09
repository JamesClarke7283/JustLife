extends SceneTree
## Controlled policy fixtures run actual app routes and clocks. Give this test
## private JUSTLIFE_DATA_DIR and XDG_DATA_HOME folders before starting Godot.
var app:Node
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path() or not OS.get_environment("XDG_DATA_HOME").is_absolute_path():quit(2);return
	run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func frames(count:int=2)->void:
	for i:int in count:await process_frame
func step(seconds:float)->void:
	for i:int in ceili(seconds/.05):app._process(.05)
func until(condition:Callable,seconds:float=60.0)->bool:
	for i:int in ceili(seconds/.05):
		if condition.call():return true
		app._process(.05)
	return bool(condition.call())
func first(kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}
func select(id:String)->void:
	app._store_motion();app.household.select(app._member_index(id));app._bind_member(id)
func clear_actions()->void:
	for member:Dictionary in app.household.members:
		select(str(member.id))
		while not app.sim.action_queue.is_empty():app.cancel_current_action()
		app._clear_motion();app._store_motion();member.sim.autonomy=false
	select("player")
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await frames(4)
	app.set_process(false);app.set_sound(false);app.selected_lot=0
	app.household_profiles=[{"name":"Speaker","age_stage":"adult"},{"name":"Listener","age_stage":"adult"},{"name":"Urgent child","age_stage":"child"}]
	app.start_household();await frames(3)
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false
		for need:String in member.sim.needs:member.sim.needs[need]=90.0
	app.household.set_speed(1)
	street_controls()
	collision_controls()
	bathroom_controls()
	conversation_controls()
	app.queue_free();await frames(2)
	print("PRIVACY_CONVERSATIONS %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)

func collision_controls()->void:
	var state:Dictionary=LifeBuildingState.fresh()
	state.walls=[{"id":"thin_wall","x":0.0,"z":0.0,"w":.08,"d":4.0,"level":0,"height":2.6,"material":"eae7d7","cut":true}]
	var nav:=LifeLotNavigation.new();check(bool(nav.rebuild(state).ok),"A thin wall builds a real floor graph")
	var from:=Vector3(-1,.16,0);var to:=Vector3(1,.16,0)
	check(nav.point_clear(0,from) and nav.point_clear(0,to) and not nav.walking_step_clear(0,from,to),"A whole movement segment cannot tunnel through a thin wall")
	var route:Dictionary=nav.route(nav.floor_location(0,from),nav.floor_location(0,to))
	check(bool(route.ok) and float(route.distance)>2.0,"The route goes around the wall instead of crossing it")
	var safe:bool=bool(route.ok)
	for segment:Dictionary in route.get("segments",[]):safe=safe and nav.segment_clear(0,segment.from,segment.to)
	check(safe,"Every routed wall detour segment sweeps a clear body hull")
	check(not nav.walking_step_clear(0,Vector3(0,.16,0),Vector3(.08,.16,0)),"An invalid wall overlap cannot authorize arbitrary walking through walls")
	var obstacles:Array=[{"id":"chair","item":"chair","x":0.0,"z":0.0,"w":1.0,"d":1.0,"level":0}]
	check(bool(nav.rebuild(LifeBuildingState.fresh(),obstacles).ok),"An old overlapping furniture anchor has a recovery fixture")
	check(nav.walking_step_clear(0,Vector3(.60,.16,0),Vector3(.70,.16,0)) and not nav.walking_step_clear(0,Vector3(.60,.16,0),Vector3(.50,.16,0)),"Furniture recovery permits only a bounded step out of the existing overlap")
	state.walls[0].x=1.0
	check(bool(nav.rebuild(state,obstacles).ok) and not nav.walking_step_clear(0,Vector3(.60,.16,0),Vector3(.70,.16,0)),"Leaving old furniture overlap never admits a step into the full wall hull")

func bathroom_controls()->void:
	clear_actions();select("player")
	var toilet:Dictionary=first("toilet");var shower:Dictionary=first("shower")
	app.queue_interaction(toilet,"toilet")
	var arrived:bool=until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active")
	check(arrived,"The occupant walks to the toilet before bathroom privacy begins")
	if not arrived:
		print("ARRIVAL_DEBUG ",app.player.position," ",app.sim.get_current_action()," ",app.notice_text)
		return
	app.sim.get_current_action().duration=180.0
	var room:String=app.sanitation_flow.room_for_action(app.sim.get_current_action())
	app.sanitation_flow.sync_privacy()
	check(not room.is_empty() and app.sanitation_flow.privacy_owner(room)=="player","A real enclosed bathroom is owned by its toilet user")
	var locked:Dictionary={};var inside:float=0.0
	for door:Dictionary in app.world.construction.doors.doors.values():
		for side:Dictionary in door.get("privacy_rooms",[]):
			if str(side.room)==room:locked=door;inside=float(side.inside);break
		if not locked.is_empty():break
	check(not locked.is_empty() and bool(locked.get("privacy_locked",false)),"The bathroom door exposes its live privacy lock")
	if locked.is_empty():return
	var outside:Vector3=locked.root.to_global(Vector3(0,0,-inside*.75))
	var inward:Vector3=locked.root.to_global(Vector3(0,0,-inside*.35))
	var adult:LifeActor=app.world.actors.housemate_1;adult.position=outside
	check(not app.sanitation_flow.privacy_step_allowed(adult,"housemate_1",inward),"Another adult is refused before crossing the occupied bathroom door")
	var second_action:Dictionary={"id":"shower","target_id":str(shower.id),"target_position":app.world.approach(shower)}
	check(app.sanitation_flow.privacy_blocks(second_action,"housemate_1") and not app._activity_available_for_member(second_action,"housemate_1"),"Different bathroom fixtures still share room privacy")
	var child:LifeSim=app.household.member_sim("housemate_2")
	var saved_stage:String=str(child.character.age_stage)
	for stage:String in ["child","toddler","baby","teen","adult"]:
		child.character.age_stage=stage;child.needs.bladder=22.0
		check(app.sanitation_flow.urgent_child("housemate_2")==bool(stage in ["child","toddler"]),"The red bladder exception belongs only to a "+stage)
	child.character.age_stage=saved_stage;child.needs.bladder=22.01
	check(not app.sanitation_flow.urgent_child("housemate_2"),"A child's bladder above the red cutoff does not interrupt")
	child.needs.bladder=22.0
	var child_actor:LifeActor=app.world.actors.housemate_2;child_actor.position=outside
	check(app.sanitation_flow.privacy_step_allowed(child_actor,"housemate_2",inward),"A child with red bladder may cross the privacy lock")
	adult.position=Vector3(-5,.16,6)
	var entered:Vector3=locked.root.to_global(Vector3(0,0,inside*.85))
	for stage:String in ["child","toddler"]:
		child.character.age_stage=stage
		for bladder:float in [22.01,22.0]:
			child.needs.bladder=bladder;child_actor.position=outside
			app.traversal.cancel("housemate_2")
			var planned:Dictionary=app.traversal.request("housemate_2",entered)
			var crossed:bool=false
			for tick:int in 150:
				app.world.construction.doors.tick(.05)
				var motion:Dictionary=app.traversal.advance("housemate_2",.05,1)
				if bool(motion.finished):crossed=true;break
			check(bool(planned.ok) and crossed==bool(bladder<=22.0),stage+" physically enters an occupied bathroom only with red bladder")
			check(app.sanitation_flow.bathroom_hurry("housemate_2",entered)==(1.35 if bladder<=22.0 else 1.0),stage+" hurries only while bladder is critical")
			if bladder>22.0:check(locked.root.to_local(child_actor.global_position).z*inside<-.40,stage+" waits with their body outside the bathroom door")
	child.character.age_stage=saved_stage;child.needs.bladder=90.0
	app.traversal.cancel("housemate_2")
	app.world.construction.doors.cancel("housemate_2")
	child_actor.position=Vector3(5,.16,6)
	adult.position=outside
	select("housemate_1");app.queue_interaction(shower,"shower");step(1.0)
	check(adult.position.distance_to(outside)<.4 and str(app.sim.get_current_action().get("phase",""))=="approach","An adult with a real shower route physically waits outside the locked bathroom")
	select("player");app.cancel_current_action();app.sanitation_flow.sync_privacy()
	check(app.sanitation_flow.privacy_owner(room).is_empty() and not bool(locked.privacy_locked),"Canceling the visit releases the bathroom door")
	app.player.position=Vector3(-5,.16,6)
	select("housemate_1")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active",30.0),"The waiting shower route resumes after the bathroom becomes free")

func conversation_controls()->void:
	clear_actions()
	app.world.actors.player.position=Vector3(-5,.16,6)
	app.world.actors.housemate_1.position=Vector3(-4,.16,6)
	app.world.actors.housemate_2.position=Vector3(5,.16,6)
	app._refresh_sim_targets(false)
	select("housemate_1");app.queue_interaction(first("bookshelf"),"read")
	var pending:Dictionary=app.sim.get_current_action()
	select("player");app.queue_interaction({"id":"housemate_1","kind":"neighbor","node":app.world.actors.housemate_1,"size":Vector2(.6,.6)},"friendly")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active",10.0),"The friendly chat begins at a real clear social approach")
	if str(app.sim.get_current_action().get("phase",""))!="active":return
	var initiator:Vector3=app.player.position;var listener:Vector3=app.world.actors.housemate_1.position
	var elapsed:float=float(pending.elapsed);step(2.0)
	check(app.player.position==initiator and app.world.actors.housemate_1.position==listener,"Both participants remain fixed throughout the conversation")
	check(float(pending.elapsed)==elapsed and app.relationship_flow.listener_held("housemate_1"),"The listener's queued activity keeps its progress while talking")
	var a:LifeActor=app.world.actors.player;var b:LifeActor=app.world.actors.housemate_1
	var direction:Vector3=(b.position-a.position).normalized()
	check(a.basis.z.dot(direction)>.99 and b.basis.z.dot(-direction)>.99,"The speaker and listener face one another")
	var before:Vector3=b.position
	app.traversal.advance("housemate_1",1.0,1)
	check(b.position==before,"A direct traversal tick cannot move a held conversation listener")
	check(not app.traversal._make_way("housemate_1","player",{"phase":"route"}) and not app.traversal.courtesy._eligible(app.traversal,"housemate_1"),"Neither yielding nor courtesy selection can move a conversation listener")
	app.household.set_speed(0);step(1.0)
	check(a.position==initiator and b.position==listener,"Pause preserves both conversation anchors")
	app.household.set_speed(1);app.cancel_current_action()
	check(not app.relationship_flow.holds("housemate_1") and is_same(app.household.member_sim("housemate_1").get_current_action(),pending),"Canceling conversation releases the listener without replacing their queued activity")
	step(1.0)
	check(b.position.distance_to(before)>.05,"The listener resumes the original route after the conversation releases")

func street_controls()->void:
	var original:LifeLotNavigation=app.world.lot_navigation
	var original_street:LifeStreetLife=app.street_life
	var nav:=LifeLotNavigation.new()
	var state:Dictionary=LifeBuildingState.fresh()
	state.walls=[{"id":"frontage_wall","x":0.0,"z":8.35,"w":.08,"d":1.0,"level":0,"height":2.6,"material":"eae7d7","cut":true}]
	check(bool(nav.rebuild(state).ok),"A built frontage wall participates in street navigation")
	app.world.lot_navigation=nav
	for id:String in ["street_child_a","street_pet","street_adult"]:
		var street:=LifeStreetLife.new();app.street_life=street
		street.step_allowed=Callable(app.street_bodies,"_structure_step")
		street.route_provider=Callable(app.street_bodies,"_structure_route")
		street.structure_generation=nav.generation
		var passer:Dictionary=street.find(id);passer.x=-2.0;passer.dir=1;passer.lane=LifeStreetLife.lane_for(passer)
		street._seeded=true;street._follow()
		app.street_bodies.sync(0.0)
		var safe:bool=true;var meshes_clear:bool=true;var detoured:bool=false;var progress:bool=false;var correct_heading:bool=true
		for tick:int in 350:
			var previous:Dictionary={}
			for member:Dictionary in street.party_of(id):previous[str(member.id)]=street.position_of(member)
			street.tick(.05,1,-1)
			app.street_bodies.sync(.05)
			for member:Dictionary in street.party_of(id):
				var from:Vector3=previous[str(member.id)];var to:Vector3=street.position_of(member)
				safe=safe and nav.structure_step_clear(0,from,to,.65 if str(member.kind)=="pet" else LifeLotNavigation.WALL_RADIUS)
				if str(member.kind)=="pet":meshes_clear=meshes_clear and _mesh_wall_clear(app.street_bodies.body_of(str(member.id)),LifeBuildingState.rect(state.walls[0]))
				if to.distance_to(from)>.00001:
					var facing:=Vector3(sin(street.heading_of(member)),0,cos(street.heading_of(member)))
					correct_heading=correct_heading and facing.dot((to-from).normalized())>.95
			detoured=detoured or float(passer.lane)<7.55
			if float(passer.x)>1.5:progress=true;break
		check(progress and detoured,id+" physically walks around the frontage wall")
		check(safe,id+" and every leashed companion keep their swept hull out of walls")
		check(correct_heading,id+" faces the actual direction of its detour")
		check(meshes_clear,id+" keeps the visible dog muzzle, coat and tail outside the wall")
	app.world.lot_navigation=original;app.street_life=original_street

func _mesh_wall_clear(body:Node3D,wall:Rect2)->bool:
	for part:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or not part.is_visible_in_tree():continue
		var bounds:AABB=part.mesh.get_aabb();var footprint:=Rect2();var started:bool=false
		for x:int in [0,1]:
			for y:int in [0,1]:
				for z:int in [0,1]:
					var at:Vector3=part.global_transform*(bounds.position+bounds.size*Vector3(x,y,z))
					if not started:footprint=Rect2(Vector2(at.x,at.z),Vector2.ZERO);started=true
					else:footprint=footprint.expand(Vector2(at.x,at.z))
		if wall.intersects(footprint):return false
	return true
