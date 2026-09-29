extends SceneTree
## Solid pools and furniture stop every walker, blocked routes name the item in
## the way, and a walker refused by a solid turns, goes round it or gives up with
## that notice. Headless.
##
##  A. pool, hot tub and slide solids cover the models at every style, size and
##     rotation, and no route across or around a pool touches the water;
##  B. `first_blocker` / `blocker_between` name the right item (a doorway
##     blocked by a piece of furniture, a spot ringed by several, a spot inside
##     one, a room closed by walls alone) and the notice wording is exact;
##  C. a live Lifelet refused by a solid it was not told about goes round it, or
##     gives the walk up once, naming the item, without ever standing in it.
const Variants=preload("res://scripts/catalog_variants.gd")
const DT:float=1.0/30.0

var checks:int=0
var failures:Array[String]=[]
var app:Node
var world:LifeWorld

func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _initialize()->void:_run.call_deferred()

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0;app.start_household();await process_frame
	app.set_process(false)
	app.set_sound(false)
	world=app.world
	_solid_water()
	_named_blockers()
	_notice_wording()
	_live_sizes()
	_walker_reroutes()
	_walker_gives_up()
	_plain_path_reroutes()
	_ground_click_notice()
	app.queue_free();await process_frame
	print("NAVIGATION_BLOCKERS %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

# --- A. water is solid -------------------------------------------------------

func _points(node:Node,at:Transform3D,prefix:String,out:Array[Vector2])->void:
	if node is Node3D:at=at*(node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null and (prefix.is_empty() or str(node.name).begins_with(prefix)):
		var box:AABB=(node as MeshInstance3D).mesh.get_aabb()
		for x:int in [0,1]:
			for y:int in [0,1]:
				for z:int in [0,1]:
					var corner:Vector3=at*(box.position+box.size*Vector3(x,y,z))
					out.append(Vector2(corner.x,corner.z))
	for child:Node in node.get_children():_points(child,at,prefix,out)

## The ground rectangle the named surfaces of a shipped model cover at one size,
## yaw and place, measured off the model itself.
func _mesh_rect(kind:String,style:String,scale:float,yaw:float,at:Vector2,prefix:String)->Rect2:
	var scene:Node3D=load(Variants.model_path(kind,style)).instantiate()
	var origin:=Transform3D(Basis(Vector3.UP,deg_to_rad(yaw))*Basis.from_scale(Vector3.ONE*scale),Vector3(at.x,0,at.y))
	var found:Array[Vector2]=[]
	_points(scene,origin,prefix,found)
	scene.free()
	if found.is_empty():return Rect2()
	var area:=Rect2(found[0],Vector2.ZERO)
	for point:Vector2 in found:area=area.expand(point)
	return area

func _hull(records:Array)->Rect2:
	var area:=Rect2()
	for index:int in range(records.size()):
		var band:Rect2=LifeBuildingState.rect(records[index])
		area=band if index==0 else area.merge(band)
	return area

func _walked_clear(nav:LifeLotNavigation,route:Dictionary,hull:Rect2,water:Rect2)->int:
	var bad:int=0
	for index:int in range(1,route.points.size()):
		var from:Vector3=route.points[index-1];var to:Vector3=route.points[index]
		var steps:int=maxi(1,ceili(from.distance_to(to)/.05))
		for step:int in range(steps+1):
			var at:Vector3=from.lerp(to,float(step)/float(steps))
			if not nav.point_clear(0,at) or hull.has_point(Vector2(at.x,at.z)) or water.has_point(Vector2(at.x,at.z)):bad+=1
	return bad

func _solid_water()->void:
	var centre:=Vector2(0.0,-1.5)
	for size:String in ["small","medium","large"]:
		var scale:float=Variants.size_scale(size)
		for style:String in ["classic","roman","lagoon"]:
			for yaw:float in [0.0,90.0,45.0]:
				var label:String="%s %s pool at %d degrees"%[size,style,int(yaw)]
				var entry:Dictionary={"id":"probe_pool","kind":"pool","x":centre.x,"z":centre.y,"rotation":yaw,"style":style,"size":size}
				var records:Array=world.furnishing_obstacles(entry,0)
				var nav:=LifeLotNavigation.new()
				var built:Dictionary=nav.rebuild(LifeBuildingState.fresh(),records)
				check(bool(built.ok),label+" builds a navigation graph: "+str(built.get("error","")))
				if not bool(built.ok):continue
				var hull:Rect2=_hull(records)
				var mesh:Rect2=_mesh_rect("pool",style,scale,yaw,centre,"")
				var water:Rect2=_mesh_rect("pool",style,scale,yaw,centre,"Water")
				check(hull.grow(.06).encloses(mesh),label+" is solid over its whole model (solid %s, model %s)"%[hull,mesh])
				check(hull.grow(.01).encloses(water),label+" is solid over all of its water")
				var open:int=0
				var inner:Rect2=water.grow(-.05)
				var x:float=inner.position.x
				while x<=inner.end.x:
					var z:float=inner.position.y
					while z<=inner.end.y:
						if nav.point_clear(0,Vector3(x,LifeBuildingState.level_y(0),z)):open+=1
						z+=.25
					x+=.25
				check(open==0,label+" leaves no walkable point in its water (%d found)"%open)
				var y:float=LifeBuildingState.level_y(0)
				var ends:Dictionary={
					"west":Vector3(snappedf(hull.position.x-1.2,.25),y,snappedf(hull.get_center().y,.25)),
					"east":Vector3(snappedf(hull.end.x+1.2,.25),y,snappedf(hull.get_center().y,.25)),
					"north":Vector3(snappedf(hull.get_center().x,.25),y,snappedf(hull.position.y-1.2,.25)),
					"south":Vector3(snappedf(hull.get_center().x,.25),y,snappedf(hull.end.y+1.2,.25))}
				for pair:Array in [["west","east"],["north","south"]]:
					var route:Dictionary=nav.route(nav.floor_location(0,ends[pair[0]]),nav.floor_location(0,ends[pair[1]]))
					check(bool(route.ok),"%s: a route runs %s to %s"%[label,pair[0],pair[1]])
					if not bool(route.ok):continue
					check(_walked_clear(nav,route,hull,water)==0,"%s: the %s to %s route never touches the pool"%[label,pair[0],pair[1]])
					check(float(route.distance)>ends[pair[0]].distance_to(ends[pair[1]])+.5,"%s: the %s to %s route goes round rather than across"%[label,pair[0],pair[1]])
					var blocker:Dictionary=nav.first_blocker(0,ends[pair[0]],ends[pair[1]])
					check(str(blocker.get("kind",""))=="item" and str(blocker.get("id",""))=="probe_pool","%s: the straight line %s to %s meets the pool"%[label,pair[0],pair[1]])
	# The other water furnishings are solid over their whole model too.
	for kind:String in ["hot_tub","pool_slide"]:
		for style:String in Variants.styles(LifeCatalog.get_item(kind)):
			for yaw:float in [0.0,90.0]:
				var entry:Dictionary={"id":"probe_"+kind,"kind":kind,"x":centre.x,"z":centre.y,"rotation":yaw,"style":style}
				var records:Array=world.furnishing_obstacles(entry,0)
				var mesh:Rect2=_mesh_rect(kind,style,1.0,yaw,centre,"")
				check(_hull(records).grow(.06).encloses(mesh),"%s %s at %d degrees is solid over its whole model"%[style,kind,int(yaw)])
	# A size choice scales the solid with the model, for a piece whose footprint is
	# one plain box as much as for a pool.
	var sofa_small:Array=world.furnishing_obstacles({"id":"s","kind":"sofa","x":0.0,"z":0.0,"rotation":0.0,"size":"small"},0)
	var sizes:Array=Variants.sizes(LifeCatalog.get_item("sofa"))
	if not sizes.is_empty():
		var biggest:String=str(sizes.back())
		var big:Array=world.furnishing_obstacles({"id":"s","kind":"sofa","x":0.0,"z":0.0,"rotation":0.0,"size":biggest},0)
		check(_hull(big).size.x>_hull(sofa_small).size.x+.01 or biggest=="small","A larger sofa blocks a larger footprint")

# --- B. naming the blocker ---------------------------------------------------

func _wall(id:String,x:float,z:float,w:float,d:float)->Dictionary:
	return {"id":id,"level":0,"x":x,"z":z,"w":w,"d":d,"material":"cccccc","height":2.6,"cut":false}

## A 4 x 4 m room centred on the origin. Its south wall has a 1.2 m doorway
## unless `closed`.
func _room(closed:bool)->Dictionary:
	var state:Dictionary=LifeBuildingState.fresh()
	state.walls=[_wall("north",0,-2,4.15,.15),_wall("west",-2,0,.15,4.0),_wall("east",2,0,.15,4.0)]
	if closed:state.walls.append(_wall("south",0,2,4.15,.15))
	else:state.walls.append_array([_wall("south_a",-1.3,2,1.55,.15),_wall("south_b",1.3,2,1.55,.15)])
	state.next_serial=20
	return state

func _named_blockers()->void:
	var y:float=LifeBuildingState.level_y(0)
	var outside:=Vector3(0,y,4.0);var inside:=Vector3(0,y,0)
	# A doorway blocked by one piece of furniture names that piece, not the wall.
	var nav:=LifeLotNavigation.new()
	check(bool(nav.rebuild(_room(false),[{"id":"wardrobe_door","level":0,"x":0.0,"z":2.0,"w":.9,"d":.6,"item":"wardrobe_door"}]).ok),"The doorway room builds with a wardrobe in the door")
	check(not bool(nav.route(nav.floor_location(0,outside),nav.floor_location(0,inside)).ok),"A wardrobe in the doorway closes the room")
	var found:Dictionary=nav.blocker_between(0,outside,0,inside)
	check(str(found.get("kind",""))=="item" and str(found.get("id",""))=="wardrobe_door","A closed doorway names the item in it (%s)"%str(found))
	check(nav.blocker_between(0,outside,0,inside,["wardrobe_door"]).is_empty(),"Ignoring that item leaves nothing to blame: the way is open without it")
	# A room with no door at all is closed by its walls.
	var sealed:=LifeLotNavigation.new()
	sealed.rebuild(_room(true),[])
	var wall:Dictionary=sealed.blocker_between(0,outside,0,inside)
	check(str(wall.get("kind",""))=="wall","A room closed by walls names a wall (%s)"%str(wall))
	# Several items ring a spot: the one nearest it is named. The far ring (a table)
	# is crossed first from outside, the near one (a shelf) sits against the spot.
	var ring:=LifeLotNavigation.new()
	var records:Array=[
		{"id":"far_a","level":0,"x":0.0,"z":-3.2,"w":9.0,"d":.6,"item":"far"},
		{"id":"far_b","level":0,"x":0.0,"z":3.2,"w":9.0,"d":.6,"item":"far"},
		{"id":"far_c","level":0,"x":-4.2,"z":0.0,"w":.6,"d":7.0,"item":"far"},
		{"id":"far_d","level":0,"x":4.2,"z":0.0,"w":.6,"d":7.0,"item":"far"},
		{"id":"near_a","level":0,"x":0.0,"z":-.8,"w":2.6,"d":.3,"item":"near"},
		{"id":"near_b","level":0,"x":0.0,"z":.8,"w":2.6,"d":.3,"item":"near"},
		{"id":"near_c","level":0,"x":-.8,"z":0.0,"w":.3,"d":2.6,"item":"near"},
		{"id":"near_d","level":0,"x":.8,"z":0.0,"w":.3,"d":2.6,"item":"near"}]
	ring.rebuild(LifeBuildingState.fresh(),records)
	var goal:=Vector3(0,y,0)
	var named:Dictionary=ring.blocker_between(0,Vector3(9.0,y,0),0,goal)
	check(str(named.get("id",""))=="near","Items ringing a spot: the one nearest it is named (%s)"%str(named.get("id","")))
	# A spot that itself sits inside an item names it, whatever else is around.
	var inside_item:Dictionary=ring.blocker_between(0,Vector3(9.0,y,0),0,Vector3(0,y,-3.2))
	check(str(inside_item.get("id",""))=="far","A spot inside an item names that item (%s)"%str(inside_item.get("id","")))
	# The first blocker along a straight step is the first solid met.
	var step:Dictionary=ring.first_blocker(0,Vector3(9.0,y,0),Vector3(0,y,0))
	check(str(step.get("id",""))=="far","The first blocker on a straight walk is the first solid met (%s)"%str(step.get("id","")))
	check(ring.first_blocker(0,Vector3(9.0,y,8.0),Vector3(9.0,y,6.0)).is_empty(),"An open step has no blocker")
	# Two floors: a stair that no landing can reach names the item on its run.
	var multi:=LifeLotNavigation.new()
	check(multi.blocker_between(0,outside,1,inside).is_empty(),"A lot with no staircase has nothing to name between floors")

func _notice_wording()->void:
	var pool_label:String=str(LifeCatalog.get_item("pool").label)
	check(pool_label=="Swimming pool","The pool's catalogue name is what the notice uses")
	world.add_item({"id":"wording_pool","kind":"pool","x":-12.0,"z":-7.0,"rotation":0,"style":"classic","size":"small"})
	var item:Dictionary=app._find_item("wording_pool")
	var blocker:Dictionary={"kind":"item","id":"wording_pool"}
	check(world.blocker_notice(blocker,"fallback")=="Please move the Swimming pool blocking the path.","A pool is named exactly: Please move the Swimming pool blocking the path.")
	check(world.blocker_notice({"kind":"item","id":"no_such_item"},"fallback")=="fallback","An unknown item keeps the generic message")
	check(world.blocker_notice({},"fallback")=="fallback","No blocker keeps the generic message")
	check(world.blocker_notice({"kind":"wall","id":"w"},"")=="The wall is blocking the path.","A wall is named as a wall")
	check(world.blocker_notice({"kind":"stair","id":"s"},"")=="The staircase is blocking the path.","A staircase is named as a staircase")
	# A destination inside the pool is named from the real world.
	var inside:=Vector3(-12.0,LifeBuildingState.level_y(0),-7.0)
	var from:=Vector3(-16.0,LifeBuildingState.level_y(0),-1.0)
	check(world.blocked_notice(from,inside,"fallback")=="Please move the Swimming pool blocking the path.","A route into a pool says which item to move")
	var north:=Vector3(-12.0,LifeBuildingState.level_y(0),-10.5)
	check(world.step_notice(north,inside,"fallback")=="Please move the Swimming pool blocking the path.","A walker refused at a step names the item that step meets")
	check(world.step_notice(north,north+Vector3(1,0,0),"fallback")=="fallback","A step across open ground names nothing")
	world.remove_item(str(item.id))

## The live world builds its obstacles from placed items, whose own `size` is a
## footprint rather than a size choice: a medium or large pool once blocked only
## its small footprint.
func _live_sizes()->void:
	for size:String in ["small","medium","large"]:
		var id:String="live_"+size
		world.add_item({"id":id,"kind":"pool","x":-12.0,"z":-5.0,"rotation":0,"style":"roman","size":size})
		var item:Dictionary=app._find_item(id)
		var hull:Rect2=world.item_panels(item)[0]
		var scale:float=Variants.size_scale(size)
		check(absf(hull.size.x-5.62*scale)<.01 and absf(hull.size.y-3.82*scale)<.01,"The %s pool's placed solid is %.2f x %.2f m (%s)"%[size,5.62*scale,3.82*scale,hull.size])
		var nav:LifeLotNavigation=world.lot_navigation
		var y:float=LifeBuildingState.level_y(0)
		var edge:=Vector3(hull.get_center().x,y,hull.position.y+.1)
		var beyond:=Vector3(hull.get_center().x,y,hull.position.y-.16-.3)
		check(not nav.point_clear(0,edge),"The %s pool's live navigation is solid right up to its far edge"%size)
		check(str(nav.first_blocker(0,Vector3(hull.get_center().x,y,hull.position.y-1.0),edge).get("id",""))==id,"The %s pool is what stops a walker at its far edge"%size)
		check(nav.point_clear(0,beyond),"Ground just past the %s pool stays walkable"%size)
		world.remove_item(id)

# --- C. a live walker ----------------------------------------------------------

func _sofa_records(at:Vector2,rotation:float,id:String)->Dictionary:
	return {"id":id,"kind":"sofa","x":at.x,"z":at.y,"rotation":rotation,"level":0}

func _stand(actor:LifeActor,at:Vector3)->void:
	actor.position=at
	actor.visible=true

## Advance a walker one frame at a time. Returns the frame count it took, or -1.
func _walk_until(id:String,limit:int)->Dictionary:
	var nav:LifeLotNavigation=world.lot_navigation
	var actor:LifeActor=world.actors[id]
	var inside:int=0;var turned:float=0.0;var last:float=actor.rotation.y
	var answer:Dictionary={"finished":false,"blocked":false,"frames":0,"inside":0,"turned":0.0,"response":{}}
	for frame:int in range(limit):
		var response:Dictionary=app.traversal.advance(id,DT,1)
		if not nav.point_clear(0,actor.position):inside+=1
		turned=maxf(turned,absf(angle_difference(last,actor.rotation.y)));last=actor.rotation.y
		answer.frames=frame+1
		if bool(response.finished):answer.finished=true;break
		if bool(response.get("blocked",false)):answer.blocked=true;answer.response=response;break
	answer.inside=inside;answer.turned=turned
	return answer

func _walker_reroutes()->void:
	var id:String=app.bound_member_id
	var actor:LifeActor=world.actors[id]
	var y:float=LifeBuildingState.level_y(0)
	var start:=Vector3(-16.0,y,-8.0);var goal:=Vector3(-8.0,y,-8.0)
	_stand(actor,start)
	var planned:Dictionary=app.traversal.request(id,goal)
	check(bool(planned.ok),"A straight route across the west garden is planned")
	# A sofa lands across the corridor. The walker's plan is stamped current, as if
	# it had never heard of it, so the walk itself is refused.
	world.add_item(_sofa_records(Vector2(-12.0,-8.0),90.0,"probe_block"))
	app.traversal.routes[id].generation=world.lot_navigation.generation
	var ended:Dictionary=_walk_until(id,900)
	check(bool(ended.finished) and not bool(ended.blocked),"A walker refused by a sofa goes round it and arrives (%d frames)"%int(ended.frames))
	check(actor.position.distance_to(goal)<.06,"It ends on its destination (%.2f m away)"%actor.position.distance_to(goal))
	check(int(ended.inside)==0,"It never stands inside a solid on the way (%d frames inside)"%int(ended.inside))
	check(int(ended.frames)<=600,"The detour takes a bounded time (%.1f s)"%(float(ended.frames)*DT))
	check(float(ended.turned)>.5,"It turned round or away from the sofa (largest turn %.2f rad in a frame)"%float(ended.turned))
	world.remove_item("probe_block")

## Four pieces around a 1 m pocket: two wide swimming pools north and south, a
## pool slide east and west. Returns the pocket centre.
func _ring(with_east:bool)->Vector3:
	var y:float=LifeBuildingState.level_y(0)
	var pocket:=Vector2(12.0,-4.0)
	world.add_item({"id":"ring_north","kind":"pool","x":pocket.x,"z":pocket.y-.5-1.9,"rotation":0,"style":"classic","size":"small"},false)
	world.add_item({"id":"ring_south","kind":"pool","x":pocket.x,"z":pocket.y+.5+1.9,"rotation":0,"style":"classic","size":"small"},false)
	world.add_item({"id":"ring_west","kind":"pool_slide","x":pocket.x-.5-.62,"z":pocket.y-.135,"rotation":0,"style":"straight"},false)
	if with_east:world.add_item({"id":"ring_east","kind":"pool_slide","x":pocket.x+.5+.62,"z":pocket.y-.135,"rotation":0,"style":"straight"},false)
	world.rebuild_navigation()
	return Vector3(pocket.x,y,pocket.y)

func _clear_ring()->void:
	for id:String in ["ring_north","ring_south","ring_west","ring_east"]:
		if not app._find_item(id).is_empty():world.remove_item(id)

func _walker_gives_up()->void:
	var id:String=app.bound_member_id
	var actor:LifeActor=world.actors[id]
	var y:float=LifeBuildingState.level_y(0)
	var pocket:Vector3=_ring(false)
	_stand(actor,Vector3(16.0,y,-4.0))
	var planned:Dictionary=app.traversal.request(id,pocket)
	check(bool(planned.ok),"A route into the open-sided pocket is planned")
	# The last piece closes it while the walker is on its way.
	world.add_item({"id":"ring_east","kind":"pool_slide","x":pocket.x+.5+.62,"z":pocket.z-.135,"rotation":0,"style":"straight"})
	app.traversal.routes[id].generation=world.lot_navigation.generation
	var ended:Dictionary=_walk_until(id,1200)
	check(bool(ended.blocked),"A walker whose way is closed for good gives the walk up (%d frames)"%int(ended.frames))
	check(int(ended.frames)<=900,"It does so in a bounded time (%.1f s)"%(float(ended.frames)*DT))
	check(int(ended.inside)==0,"It never stands inside a solid while giving up")
	check(not app.traversal.active(id),"Nothing is left holding its route")
	var response:Dictionary=ended.response
	check(str(response.get("error",""))==LifeTraversal.BLOCKED_ERROR,"The response carries the blocked error")
	var said:String=world.blocked_notice(response.get("origin",Vector3.ZERO),response.get("destination",Vector3.ZERO),"generic")
	check(said=="Please move the Pool slide blocking the path.","The notice names the slide in the way: "+said)
	# The same walk driven through the controller ends with that notice on screen.
	world.remove_item("ring_east")
	_stand(actor,Vector3(16.0,y,-4.0))
	app.household.set_speed(1)
	app.notice_time=0.0
	app._blocked_notice_at=-100000
	var again:bool=app._set_route(pocket)
	check(again,"The controller plans into the pocket while it is open")
	app.walk_only=true;app.walk_destination=pocket
	world.add_item({"id":"ring_east","kind":"pool_slide","x":pocket.x+.5+.62,"z":pocket.z-.135,"rotation":0,"style":"straight"})
	if app.traversal.routes.has(id):app.traversal.routes[id].generation=world.lot_navigation.generation
	var frames:int=0;var buried:int=0
	while frames<1200 and app.walk_only:
		app._advance_path(DT);frames+=1
		if world.navigation.is_point_solid(Vector2i(roundi(actor.position.x*4),roundi(actor.position.z*4))):buried+=1
	check(not app.walk_only and not app.traversal.active(id),"The controller drops the closed walk (%d frames)"%frames)
	check(buried==0,"Its walker never steps into a solid cell (%d frames inside)"%buried)
	check(app.notice_text=="Please move the Pool slide blocking the path.","The player is told exactly which item to move: "+app.notice_text)
	check(not app.walk_only and app.path.is_empty(),"A plain stroll that cannot go on is forgotten")
	# Said once: the same refusal does not rebuild the notice card.
	app.notice_time=1.0
	app.show_blocked_notice("Please move the Pool slide blocking the path.")
	check(is_equal_approx(app.notice_time,1.0),"The same notice is not repeated at once")
	app.notice_time=1.0
	app.show_blocked_notice("Please move the Swimming pool blocking the path.")
	check(app.notice_time>1.0,"A different notice still shows")
	_clear_ring()

## The default lot has no versioned building, so its walkers step along a plain
## path with no traversal route behind it. That stepping is checked too: a stale
## path through a sofa is refused, planned again round it, and walked.
func _plain_path_reroutes()->void:
	var id:String=app.bound_member_id
	var actor:LifeActor=world.actors[id]
	var y:float=LifeBuildingState.level_y(0)
	var goal:=Vector3(-8.0,y,-8.0)
	_stand(actor,Vector3(-16.0,y,-8.0))
	app._clear_motion()
	app.household.set_speed(1)
	check(app._set_route(goal),"A plain path across the garden is planned")
	app.walk_only=true;app.walk_destination=goal
	world.add_item(_sofa_records(Vector2(-12.0,-8.0),90.0,"plain_block"))
	var frames:int=0;var buried:int=0
	while frames<900 and app.walk_only:
		var was_moving:bool=app._advance_path(DT);frames+=1
		if world.navigation.is_point_solid(Vector2i(roundi(actor.position.x*4),roundi(actor.position.z*4))):buried+=1
		if was_moving and app.path_index>=app.path.size():app.walk_only=false
	check(actor.position.distance_to(goal)<.06,"The plain-path walker goes round the sofa and arrives (%d frames, %.2f m away)"%[frames,actor.position.distance_to(goal)])
	check(buried==0,"It never steps into a solid cell (%d frames inside)"%buried)
	check(frames<=600,"The detour takes a bounded time (%.1f s)"%(float(frames)*DT))
	world.remove_item("plain_block")

func _ground_click_notice()->void:
	var y:float=LifeBuildingState.level_y(0)
	var id:String=app.bound_member_id
	var actor:LifeActor=world.actors[id]
	var pocket:Vector3=_ring(true)
	_stand(actor,Vector3(16.0,y,-4.0))
	app._clear_motion()
	app.notice_time=0.0
	app._blocked_notice_at=-100000
	app.on_ground_clicked(pocket)
	check(app.notice_text=="Please move the Pool slide blocking the path.","Clicking a sealed pocket names the piece to move: "+app.notice_text)
	check(app.path.is_empty() and not app.walk_only,"No walk starts into a sealed pocket")
	_clear_ring()
