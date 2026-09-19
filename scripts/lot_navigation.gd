extends RefCounted
class_name LifeLotNavigation
## Explicit supported floor graph plus tagged real stair segments. No movement,
## nearest-floor fallback, actor state mutation, rewards or physics shortcuts.
const Building=preload("res://scripts/building_state.gd")
const RADIUS:float=.16
const CELL:float=.25
var _state:Dictionary={}
var _obstacles:Array=[]
var _graph:AStar3D=AStar3D.new()
var _floor_ids:Dictionary={}
var _locations:Dictionary={}
var _stair_edges:Dictionary={}
var generation:int=0
var penalties:Dictionary={}
# Derived geometry belongs to the same immutable rebuild as the graph.
var _support_surfaces:Array=[[],[]]
var _support_holes:Array=[[],[]]
var _blockers:Array=[[],[]]

func rebuild(state:Variant,obstacles:Variant=[]) -> Dictionary:
	var error:String=Building.validate(state)
	if not error.is_empty():return {"ok":false,"error":error}
	if not obstacles is Array or obstacles.size()>512:return {"ok":false,"error":"Invalid navigation obstacles."}
	var identities:Dictionary={}
	for item:Variant in obstacles:
		if not item is Dictionary or not Building.identifier(item.get("id")) or identities.has(item.id) or not Building.number(item.get("level"),0,1,true):return {"ok":false,"error":"Invalid obstacle identity or level."}
		identities[item.id]=true
		if not Building._rect_error(item).is_empty():return {"ok":false,"error":"Invalid obstacle footprint."}
	# Build off to the side: even a valid schema can have a blocked stair landing.
	var candidate=load("res://scripts/lot_navigation.gd").new()
	candidate._state=state.duplicate(true)
	candidate._obstacles=obstacles.duplicate(true)
	var result:Dictionary=candidate._build_graph()
	if not bool(result.ok):return result
	_state=candidate._state;_obstacles=candidate._obstacles;_graph=candidate._graph
	_floor_ids=candidate._floor_ids;_locations=candidate._locations;_stair_edges=candidate._stair_edges
	_support_surfaces=candidate._support_surfaces;_support_holes=candidate._support_holes;_blockers=candidate._blockers
	generation+=1
	return {"ok":true,"generation":generation,"points":_graph.get_point_count(),"stairs":_state.stairs.size()}

static func _cell_key(level:int,cell:Vector2i) -> String:return "%d:%d:%d"%[level,cell.x,cell.y]
static func _edge_key(first:int,second:int) -> String:return "%d:%d"%[mini(first,second),maxi(first,second)]
static func floor_location(level:int,point:Vector3) -> Dictionary:return {"kind":"floor","level":level,"position":point}

func _add(point:Vector3,location:Dictionary) -> int:
	var id:int=_graph.get_available_point_id()
	_graph.add_point(id,point)
	_locations[id]=location
	return id

func _build_graph() -> Dictionary:
	_prepare_geometry()
	for level:int in [0,1]:
		var cells:Rect2i=Building.cell_range()
		for x:int in range(cells.position.x,cells.end.x):
			for z:int in range(cells.position.y,cells.end.y):
				var cell:=Vector2i(x,z)
				var at:=Vector3(x*CELL,Building.level_y(level),z*CELL)
				if point_clear(level,at):_floor_ids[_cell_key(level,cell)]=_add(at,floor_location(level,at))
	for key:String in _floor_ids:
		var id:int=int(_floor_ids[key])
		var location:Dictionary=_locations[id]
		var point:Vector3=location.position
		var cell:=Vector2i(roundi(point.x/CELL),roundi(point.z/CELL))
		for offset:Vector2i in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
			var next:String=_cell_key(int(location.level),cell+offset)
			if not _floor_ids.has(next):continue
			if offset.x!=0 and offset.y!=0:
				if not _floor_ids.has(_cell_key(int(location.level),cell+Vector2i(offset.x,0))) or not _floor_ids.has(_cell_key(int(location.level),cell+Vector2i(0,offset.y))):continue
			var next_id:int=int(_floor_ids[next])
			if _segment_bounds_clear(int(location.level),point,_graph.get_point_position(next_id)):_graph.connect_points(id,next_id)
	for stair:Dictionary in _state.stairs:
		# Placement validates the entire landing. An obstacle added afterwards may
		# make this staircase unavailable; never snap its endpoint through it.
		var start:Vector3=Building.stair_point(stair,-.5)
		var finish:Vector3=Building.stair_point(stair,Building.STAIR_RUN+.5,Building.RISE)
		var first:String=_cell_key(0,Vector2i(roundi(start.x/CELL),roundi(start.z/CELL)))
		var last:String=_cell_key(1,Vector2i(roundi(finish.x/CELL),roundi(finish.z/CELL)))
		var clear:bool=_floor_ids.has(first) and _floor_ids.has(last)
		for obstacle:Dictionary in _obstacles:
			if Building.stair_rect(stair).intersects(Building.rect(obstacle)) or Building.landing_rect(stair,int(obstacle.level)==1).intersects(Building.rect(obstacle)):clear=false
		if not clear:continue
		var prior:int=int(_floor_ids[first])
		for step:int in range(Building.STAIR_STEPS+1):
			var point:Vector3=Building.stair_point(stair,float(step)*Building.STAIR_RUN/Building.STAIR_STEPS,float(step)*Building.RISE/Building.STAIR_STEPS)
			var id:int=_add(point,{"kind":"stair","stair_id":str(stair.id),"step":step,"position":point})
			_graph.connect_points(prior,id)
			_stair_edges[_edge_key(prior,id)]=str(stair.id)
			prior=id
		_graph.connect_points(prior,int(_floor_ids[last]))
		_stair_edges[_edge_key(prior,int(_floor_ids[last]))]=str(stair.id)
	return {"ok":true}

func _prepare_geometry()->void:
	_support_surfaces=[[],[]];_support_holes=[[],[]];_blockers=[[],[]]
	for level:int in [0,1]:
		var surfaces:Array=Building._rects(_state,"floors",level)
		# Bearings are computed from the original slabs and openings once.
		surfaces.append_array(Building._wall_bearing_rects(_state,level))
		if level==0:surfaces.append(Building.lot())
		_support_surfaces[level]=surfaces
		_support_holes[level]=Building._rects(_state,"openings",level)
		for wall:Dictionary in _state.walls:
			if int(wall.level)==level:_blockers[level].append(Building.rect(wall))
		for stair:Dictionary in _state.stairs:
			if level==int(stair.lower):_blockers[level].append(Building.stair_rect(stair))
			if level==int(stair.upper):_blockers[level].append_array(Building.guard_footprints(stair))
		for obstacle:Dictionary in _obstacles:
			if int(obstacle.level)==level:_blockers[level].append(Building.rect(obstacle))

func _bounds_clear(level:int,bounds:Rect2)->bool:
	if not Building.lot().encloses(bounds) or not Building._covered(bounds,_support_surfaces[level],_support_holes[level]):return false
	for blocker:Rect2 in _blockers[level]:
		if blocker.intersects(bounds):return false
	return true

func point_clear(level:int,point:Vector3,half:Vector2=Vector2(RADIUS,RADIUS)) -> bool:
	if _state.is_empty() or level not in [0,1] or not point.is_finite() or absf(point.y-Building.level_y(level))>.00001 or half.x<=0 or half.y<=0:return false
	return _bounds_clear(level,Rect2(Vector2(point.x,point.z)-half,half*2))

func _segment_bounds_clear(level:int,from:Vector3,to:Vector3)->bool:
	var low:=Vector2(minf(from.x,to.x)-RADIUS,minf(from.z,to.z)-RADIUS)
	var high:=Vector2(maxf(from.x,to.x)+RADIUS,maxf(from.z,to.z)+RADIUS)
	return _bounds_clear(level,Rect2(low,high-low))

func segment_clear(level:int,from:Vector3,to:Vector3) -> bool:
	if not point_clear(level,from) or not point_clear(level,to):return false
	return _segment_bounds_clear(level,from,to)

func _endpoint(value:Variant) -> Dictionary:
	if not value is Dictionary or value.get("kind")!="floor" or not Building.number(value.get("level"),0,1,true):return {"ok":false,"error":"Route endpoint requires an explicit floor level."}
	var point:Variant=value.get("position")
	if point is Array:
		if point.size()!=3:return {"ok":false,"error":"Invalid route position."}
		for component:Variant in point:
			if not Building.number(component,-100,100):return {"ok":false,"error":"Invalid route position."}
		point=Vector3(point[0],point[1],point[2])
	if not point is Vector3 or not point_clear(int(value.level),point):return {"ok":false,"error":"The exact route endpoint is unsupported or blocked."}
	var candidates:Array=[]
	var cell:=Vector2i(roundi(point.x/CELL),roundi(point.z/CELL))
	var exact:String=_cell_key(int(value.level),cell)
	if _floor_ids.has(exact) and _graph.get_point_position(int(_floor_ids[exact])).is_equal_approx(point):
		return {"ok":true,"point":point,"level":int(value.level),"ids":[int(_floor_ids[exact])]}
	for x:int in range(-1,2):
		for z:int in range(-1,2):
			var key:String=_cell_key(int(value.level),cell+Vector2i(x,z))
			if not _floor_ids.has(key):continue
			var id:int=int(_floor_ids[key]);var node:Vector3=_graph.get_point_position(id)
			if node.distance_to(point)<=.36 and segment_clear(int(value.level),point,node):candidates.append(id)
	if candidates.is_empty():return {"ok":false,"error":"No exact local connection to the floor graph."}
	return {"ok":true,"point":point,"level":int(value.level),"ids":candidates}

func route(from:Variant,to:Variant) -> Dictionary:
	var start:Dictionary=_endpoint(from)
	if not bool(start.ok):return start
	var finish:Dictionary=_endpoint(to)
	if not bool(finish.ok):return finish
	if start.point.is_equal_approx(finish.point) and start.level==finish.level:return {"ok":true,"already_reached":true,"points":PackedVector3Array([start.point]),"segments":[],"distance":0.0,"generation":generation}
	var disabled:Array=[]
	if not penalties.is_empty():
		var now:int=Time.get_ticks_msec()
		for key:String in penalties.keys():
			if int(penalties[key])<now:continue
			var parts:PackedStringArray=key.split(":")
			var a:int=int(parts[0]);var b:int=int(parts[1])
			if _graph.are_points_connected(a,b):
				_graph.disconnect_points(a,b);_graph.disconnect_points(b,a);disabled.append([a,b])
	var best:PackedInt64Array=[];var best_distance:float=INF
	for first:int in start.ids:
		for last:int in finish.ids:
			var ids:PackedInt64Array=_graph.get_id_path(first,last,false)
			if ids.is_empty():continue
			var distance:float=start.point.distance_to(_graph.get_point_position(first))+finish.point.distance_to(_graph.get_point_position(last))
			for index:int in range(1,ids.size()):distance+=_graph.get_point_position(ids[index-1]).distance_to(_graph.get_point_position(ids[index]))
			if distance<best_distance:best_distance=distance;best=ids
	for pair:Array in disabled:
		_graph.connect_points(pair[0],pair[1]);_graph.connect_points(pair[1],pair[0])
	if best.is_empty():return {"ok":false,"error":"No complete route connects these floors or rooms.","generation":generation}
	var points:PackedVector3Array=[start.point]
	var segments:Array=[]
	for index:int in range(best.size()):
		var at:Vector3=_graph.get_point_position(best[index])
		if points[-1].is_equal_approx(at):continue
		var stair_id:String="" if index==0 else str(_stair_edges.get(_edge_key(best[index-1],best[index]),""))
		segments.append({"kind":"floor" if stair_id.is_empty() else "stair","stair_id":stair_id,"level":int(_locations[best[index]].get("level",-1)),"from":points[-1],"to":at})
		points.append(at)
	if not points[-1].is_equal_approx(finish.point):segments.append({"kind":"floor","stair_id":"","level":int(finish.level),"from":points[-1],"to":finish.point});points.append(finish.point)
	return {"ok":true,"already_reached":false,"points":points,"segments":segments,"distance":best_distance,"generation":generation}


func penalize_segment(level:int,from:Vector3,to:Vector3,duration_ms:int=45000)->void:
	# Learn from an actual refused step: graph edges under it are avoided by
	# later routes until the penalty expires, so a corridor the walker cannot
	# truly use is not planned twice.
	var now:int=Time.get_ticks_msec()
	for key:String in penalties.keys():
		if int(penalties[key])<now:penalties.erase(key)
	for a:int in _ids_near(level,from):
		for b:int in _ids_near(level,to):
			if a==b:continue
			penalties[_edge_key(a,b)]=now+duration_ms

func _ids_near(level:int,point:Vector3)->PackedInt64Array:
	var found:PackedInt64Array=[]
	for key:String in _floor_ids:
		var parts:PackedStringArray=key.split(":")
		if int(parts[0])!=level:continue
		var id:int=_floor_ids[key]
		if _graph.get_point_position(id).distance_to(point)<=.4:found.append(id)
	return found

func reachable_from(level:int,point:Vector3,excluded:Dictionary={}) -> Dictionary:
	# Every graph point a walker can reach from here, across stairs, as a set of
	# point ids. One flood fill answers reachability for every furnishing at once;
	# `excluded` point ids are treated as gone, so a candidate furnishing can be
	# tested against the live graph without rebuilding it.
	var start:Dictionary=_endpoint(floor_location(level,point))
	var seen:Dictionary={}
	if not bool(start.ok):return seen
	var frontier:Array=[]
	for id:int in start.ids:
		if excluded.has(id):continue
		seen[id]=true;frontier.append(id)
	while not frontier.is_empty():
		var id:int=int(frontier.pop_back())
		for next:int in _graph.get_point_connections(id):
			if seen.has(next) or excluded.has(next):continue
			seen[next]=true;frontier.append(next)
	return seen

func points_touching(level:int,area:Rect2) -> Dictionary:
	# Floor point ids whose walking clearance would intersect a new obstacle.
	var grown:Rect2=area.grow(RADIUS+CELL*.5)
	var found:Dictionary={}
	for x:int in range(floori(grown.position.x/CELL),ceili(grown.end.x/CELL)+1):
		for z:int in range(floori(grown.position.y/CELL),ceili(grown.end.y/CELL)+1):
			var key:String=_cell_key(level,Vector2i(x,z))
			if not _floor_ids.has(key):continue
			var at:Vector3=_graph.get_point_position(int(_floor_ids[key]))
			if area.grow(RADIUS).has_point(Vector2(at.x,at.z)):found[int(_floor_ids[key])]=true
	return found

func point_reachable(reach:Dictionary,level:int,point:Vector3) -> bool:
	var key:String=_cell_key(level,Vector2i(roundi(point.x/CELL),roundi(point.z/CELL)))
	return _floor_ids.has(key) and reach.has(int(_floor_ids[key]))

func state_snapshot() -> Dictionary:return _state.duplicate(true)

func route_avoiding(from:Dictionary,to:Dictionary,occupied:Array[Vector3],radius:float) -> Dictionary:
	# Per-query dynamic bodies do not change the authored graph or generation.
	# Calls are synchronous; restore exactly the points disabled by this query.
	var changed:PackedInt64Array=[]
	var start:Vector3=from.position
	for id:int in _graph.get_point_ids():
		if str(_locations[id].kind)!="floor" or _graph.is_point_disabled(id):continue
		var point:Vector3=_graph.get_point_position(id)
		for body:Vector3 in occupied:
			if absf(body.y-point.y)>.1 or point.distance_to(body)>=radius:continue
			# Preserve the start and outward escape from an existing crowding;
			# a disabled start would prevent even a route out of that overlap.
			if point.distance_to(start)<.36 and point.distance_to(body)>=start.distance_to(body)-.00001:continue
			_graph.set_point_disabled(id,true);changed.append(id);break
	var result:Dictionary=route(from,to)
	for id:int in changed:_graph.set_point_disabled(id,false)
	return result
