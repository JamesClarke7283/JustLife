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
# Who owns each rectangle in `_blockers`, index for index: a placed item (by its
# own id, however many solid bands it has), a wall, a staircase or an object
# that is not furniture (the parked food truck). Blocked-route notices read it.
var _blocker_sources:Array=[[],[]]
const ITEM_COST:float=6.0    # weight of a cell a placed item covers, in `blocker_between`
const HARD_COST:float=40.0   # weight of a wall or staircase cell: crossed only when nothing else joins the two spots

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
	_support_surfaces=candidate._support_surfaces;_support_holes=candidate._support_holes;_blockers=candidate._blockers;_blocker_sources=candidate._blocker_sources
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
		# A staircase is usable when the walker's own body box fits at both
		# landings and nothing occupies the run it climbs. The landing cells
		# already answer the first half: `point_clear` tests that body box and
		# `_blockers` already carries the authored run at its own level. Asking
		# instead whether a furnishing grazes the landing's wider reserved
		# clearance - or a neighbour of a shared counter row - dropped a
		# staircase a Lifelet can really walk to, leaving the home with a
		# staircase that no route ever used.
		var start:Vector3=Building.stair_point(stair,-.5)
		var finish:Vector3=Building.stair_point(stair,Building.STAIR_RUN+.5,Building.RISE)
		var first:String=_cell_key(0,Vector2i(roundi(start.x/CELL),roundi(start.z/CELL)))
		var last:String=_cell_key(1,Vector2i(roundi(finish.x/CELL),roundi(finish.z/CELL)))
		if not _floor_ids.has(first) or not _floor_ids.has(last):continue
		var run_blocked:bool=false
		for obstacle:Dictionary in _obstacles:
			if int(obstacle.level)!=int(stair.lower):continue
			if Building.stair_rect(stair).intersects(Building.rect(obstacle)):run_blocked=true;break
		if run_blocked:continue
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
	_support_surfaces=[[],[]];_support_holes=[[],[]];_blockers=[[],[]];_blocker_sources=[[],[]]
	for level:int in [0,1]:
		var surfaces:Array=Building._rects(_state,"floors",level)
		# Bearings are computed from the original slabs and openings once.
		surfaces.append_array(Building._wall_bearing_rects(_state,level))
		if level==0:surfaces.append(Building.lot())
		_support_surfaces[level]=surfaces
		_support_holes[level]=Building._rects(_state,"openings",level)
		for wall:Dictionary in _state.walls:
			if int(wall.level)==level:_block(level,Building.rect(wall),"wall",str(wall.get("id","")))
		for stair:Dictionary in _state.stairs:
			if level==int(stair.lower):_block(level,Building.stair_rect(stair),"stair",str(stair.id))
			if level==int(stair.upper):
				for guard:Rect2 in Building.guard_footprints(stair):_block(level,guard,"stair",str(stair.id))
		for obstacle:Dictionary in _obstacles:
			if int(obstacle.level)==level:_block(level,Building.rect(obstacle),"item" if obstacle.has("item") else "object",str(obstacle.get("item",obstacle.id)))

func _block(level:int,area:Rect2,kind:String,id:String)->void:
	_blockers[level].append(area);_blocker_sources[level].append({"kind":kind,"id":id})

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
	# The nodes a point stands on: within a fifth of a metre, which is the cell it
	# is in. A wider net penalized every edge round the walker's own node when it
	# stood against a solid, leaving it no way out.
	var found:PackedInt64Array=[]
	var cell:=Vector2i(roundi(point.x/CELL),roundi(point.z/CELL))
	for x:int in range(-1,2):
		for z:int in range(-1,2):
			var key:String=_cell_key(level,cell+Vector2i(x,z))
			if not _floor_ids.has(key):continue
			var id:int=_floor_ids[key]
			if _graph.get_point_position(id).distance_to(point)<=.2:found.append(id)
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

func stair_connected(stair_id:String) -> bool:
	# Whether the built graph really links this staircase's landings. A blocked
	# landing leaves the stair standing but unreachable, so a caller that must
	# not accept an unusable staircase asks this instead of assuming. The
	# builder records a tagged edge for every tread it links, so a tagged edge
	# for this staircase means the whole crossing - both landings and every
	# tread between them - is in the graph. Cheap enough for a live preview.
	return _stair_edges.values().has(stair_id)

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

# --- Blocked-route diagnosis --------------------------------------------------
# Routing itself never asks who is in the way. These answer it afterwards, from
# the same rectangles the graph was built from, so a notice can name the placed
# item a Lifelet or pet cannot get past instead of guessing.

static func _rect_gap(area:Rect2,point:Vector2)->float:
	return Vector2(maxf(maxf(area.position.x-point.x,point.x-area.end.x),0.0),maxf(maxf(area.position.y-point.y,point.y-area.end.y),0.0)).length()

static func _body_box(point:Vector3,slack:float=0.0)->Rect2:
	var half:=Vector2(RADIUS+slack,RADIUS+slack)
	return Rect2(Vector2(point.x,point.z)-half,half*2)

static func is_item_source(source:Dictionary)->bool:return str(source.get("kind","")) in ["item","object"]

func blockers_touching(level:int,area:Rect2)->Array:
	# The solid things a body box meets, nearest first, each {kind,id,rect,gap,level}.
	# A placed item sorts ahead of a wall at the same distance: it is the one a
	# player can move.
	var found:Array=[]
	if level not in [0,1]:return found
	var centre:=area.get_center()
	for index:int in range(_blockers[level].size()):
		var footprint:Rect2=_blockers[level][index]
		if not footprint.intersects(area):continue
		var source:Dictionary=_blocker_sources[level][index].duplicate()
		source.rect=footprint;source.level=level;source.gap=_rect_gap(footprint,centre)
		found.append(source)
	found.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if absf(float(a.gap)-float(b.gap))>.001:return float(a.gap)<float(b.gap)
		return is_item_source(a) and not is_item_source(b))
	return found

func first_blocker(level:int,from:Vector3,to:Vector3,slack:float=0.0)->Dictionary:
	# The first solid a body meets walking straight from one point to the next,
	# or {} when the way is open. `slack` widens the body for a gap that only
	# pinches it.
	var span:float=Vector2(to.x-from.x,to.z-from.z).length()
	var steps:int=maxi(1,ceili(span/(CELL*.5)))
	for index:int in range(steps+1):
		var hits:Array=blockers_touching(level,_body_box(from.lerp(to,float(index)/float(steps)),slack))
		if not hits.is_empty():return hits[0]
	return {}

func blocker_between(from_level:int,from:Vector3,to_level:int,to:Vector3,ignore:Array=[])->Dictionary:
	# Whose footprint a failed route runs into. A spot that itself sits inside a
	# solid names it; otherwise the cheapest way across the lot is found with
	# walls and staircases nearly impassable and every placed item merely
	# expensive, and the item on that way nearest the destination is named (so
	# among several ringing it, the one closest to it). A wall only when the
	# two spots are closed off by walls alone, and {} when nothing solid is
	# responsible. `ignore` lists item ids that are the goal itself.
	if _state.is_empty() or from_level not in [0,1] or to_level not in [0,1] or not from.is_finite() or not to.is_finite():return {}
	if from_level!=to_level:return _stair_blocker(from_level,from,to_level,to,ignore)
	return _level_blocker(from_level,from,to,ignore)

func _level_blocker(level:int,from:Vector3,to:Vector3,ignore:Array)->Dictionary:
	var fallback:Dictionary={}
	for point:Vector3 in [to,from]:
		if point_clear(level,point):continue
		for hit:Dictionary in blockers_touching(level,_body_box(point)):
			if ignore.has(str(hit.id)):continue
			if is_item_source(hit):return hit
			if fallback.is_empty():fallback=hit
	var start:=Vector2i(roundi(from.x/CELL),roundi(from.z/CELL));var goal:=Vector2i(roundi(to.x/CELL),roundi(to.z/CELL))
	for margin:int in [24,-1]:
		var crossing:Dictionary=_cheapest_crossing(level,start,goal,Vector2(to.x,to.z),margin,ignore)
		if not bool(crossing.found):continue
		var hard:Dictionary={};var soft:Dictionary={}
		for source:Dictionary in crossing.crossed:
			if is_item_source(source):
				if soft.is_empty() or float(source.gap)<float(soft.gap):soft=source
			elif hard.is_empty() or float(source.gap)<float(hard.gap):hard=source
		if not hard.is_empty():return hard
		return soft if not soft.is_empty() else fallback
	return fallback

func _cheapest_crossing(level:int,start:Vector2i,goal:Vector2i,destination:Vector2,margin:int,ignore:Array)->Dictionary:
	# A weighted 4-neighbour search over the level's cells. A cell the graph
	# already walks is cheap, a cell an item covers costs ITEM_COST, a wall or
	# staircase cell HARD_COST and anything else is solid. Returns the owners
	# of every covered cell on the cheapest way, each once, with their gap to
	# the destination.
	var full:Rect2i=Building.cell_range()
	var window:Rect2i=full
	if margin>=0:window=Rect2i(Vector2i(mini(start.x,goal.x),mini(start.y,goal.y))-Vector2i(margin,margin),Vector2i(absi(start.x-goal.x),absi(start.y-goal.y))+Vector2i(margin,margin)*2+Vector2i.ONE).intersection(full)
	if not window.has_point(start) or not window.has_point(goal):return {"found":false,"crossed":[]}
	var grid:=AStarGrid2D.new()
	grid.region=window;grid.cell_size=Vector2.ONE;grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_MANHATTAN;grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	grid.fill_solid_region(window,true)
	for x:int in range(window.position.x,window.end.x):
		for z:int in range(window.position.y,window.end.y):
			if _floor_ids.has(_cell_key(level,Vector2i(x,z))):grid.set_point_solid(Vector2i(x,z),false)
	var cost:Dictionary={};var owners:Dictionary={};var freed:Dictionary={}
	for index:int in range(_blockers[level].size()):
		var source:Dictionary=_blocker_sources[level][index]
		var area:Rect2=Rect2(_blockers[level][index]).grow(RADIUS)
		var gone:bool=ignore.has(str(source.id))
		var weight:float=ITEM_COST if is_item_source(source) else HARD_COST
		for x:int in range(maxi(floori(area.position.x/CELL),window.position.x),mini(ceili(area.end.x/CELL)+1,window.end.x)):
			for z:int in range(maxi(floori(area.position.y/CELL),window.position.y),mini(ceili(area.end.y/CELL)+1,window.end.y)):
				var cell:=Vector2i(x,z)
				if not area.has_point(Vector2(x*CELL,z*CELL)) or _floor_ids.has(_cell_key(level,cell)):continue
				if gone:freed[cell]=true;continue
				cost[cell]=maxf(float(cost.get(cell,0.0)),weight)
				var entry:Dictionary=source.duplicate();entry.rect=_blockers[level][index];entry.level=level;entry.gap=_rect_gap(entry.rect,destination)
				if not owners.has(cell):owners[cell]=[]
				owners[cell].append(entry)
	for cell:Vector2i in freed:
		if not cost.has(cell):grid.set_point_solid(cell,false)
	for cell:Vector2i in cost:
		grid.set_point_solid(cell,false);grid.set_point_weight_scale(cell,float(cost[cell]))
	grid.set_point_solid(start,false);grid.set_point_solid(goal,false)
	var cells:Array[Vector2i]=grid.get_id_path(start,goal)
	if cells.is_empty():return {"found":false,"crossed":[]}
	var crossed:Dictionary={}
	for cell:Vector2i in cells:
		for entry:Dictionary in owners.get(cell,[]):
			var key:String=str(entry.kind)+":"+str(entry.id)
			if not crossed.has(key) or float(entry.gap)<float(crossed[key].gap):crossed[key]=entry
	return {"found":true,"crossed":crossed.values()}

func _stair_blocker(from_level:int,from:Vector3,to_level:int,to:Vector3,ignore:Array)->Dictionary:
	# Between floors a walker needs a staircase: name what closes the nearest
	# one's run or landing, or what stands between the walker and its foot, or
	# between its head and the destination.
	var best:Dictionary={};var best_gap:float=INF
	for stair:Dictionary in _state.stairs:
		var foot:Vector3=Building.stair_point(stair,-.5)
		var head:Vector3=Building.stair_point(stair,Building.STAIR_RUN+.5,Building.RISE)
		var up:bool=from_level==int(stair.lower)
		var entry:Vector3=foot if up else head
		var reach:float=Vector2(from.x-entry.x,from.z-entry.z).length()
		if reach>=best_gap:continue
		var found:Dictionary={}
		if not stair_connected(str(stair.id)):found=_landing_blocker(stair,foot,head,ignore)
		else:
			found=_level_blocker(from_level,from,entry,ignore)
			if found.is_empty():found=_level_blocker(to_level,head if up else foot,to,ignore)
		if found.is_empty():continue
		best=found;best_gap=reach
	return best

func _landing_blocker(stair:Dictionary,foot:Vector3,head:Vector3,ignore:Array)->Dictionary:
	var run:Rect2=Building.stair_rect(stair)
	for obstacle:Dictionary in _obstacles:
		if int(obstacle.level)!=int(stair.lower) or not run.intersects(Building.rect(obstacle)) or ignore.has(str(obstacle.get("item",obstacle.id))):continue
		return {"kind":"item" if obstacle.has("item") else "object","id":str(obstacle.get("item",obstacle.id)),"rect":Building.rect(obstacle),"level":int(obstacle.level),"gap":0.0}
	for landing:Array in [[int(stair.lower),foot],[int(stair.upper),head]]:
		for hit:Dictionary in blockers_touching(int(landing[0]),_body_box(landing[1])):
			if is_item_source(hit) and not ignore.has(str(hit.id)):return hit
	return {}
