extends RefCounted
## Heading belongs to a pet's route: movement and turning both reserve the
## entire long body, without making narrow aligned doors impassable.
const CELL:float=.25
const TURN_COST:float=.15
const HEADINGS:int=8
const MAX_EXPANSIONS:int=4096
# Favor a complete route through the actual rooms within the bounded search.
# All translation and rotation edges still require their full body sweep.
const HEURISTIC_WEIGHT:float=1.10
const OFFSETS:Array[Vector2i]=[Vector2i(0,1),Vector2i(1,1),Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,-1),Vector2i(-1,0),Vector2i(-1,1)]
var nav:RefCounted
var occupied:Array=[]
var body_gap:float=.65
var hull:Dictionary={}
var level:int=0
var origin:Vector3
var _poses:Dictionary={}
var _remaining:Dictionary={}

func _init(navigation:RefCounted)->void:nav=navigation

func route(from:Dictionary,to:Dictionary,bodies:Array,gap:float,shape:Dictionary,start_yaw:float,target_yaw:float)->Dictionary:
	if not is_finite(gap) or gap<0.0 or not is_finite(start_yaw) or (not is_nan(target_yaw) and not is_finite(target_yaw)):return _error("Invalid pet route clearance or heading.")
	var checked_bodies:Array[Vector3]=[]
	for body:Variant in bodies:
		if not body is Vector3 or not body.is_finite():return _error("Invalid pet route body.")
		checked_bodies.append(body)
	var exact_start:Dictionary=nav._endpoint(from);var exact_finish:Dictionary=nav._endpoint(to)
	if not bool(exact_start.ok):return exact_start
	if not bool(exact_finish.ok):return exact_finish
	occupied=bodies;body_gap=gap;hull=shape;origin=exact_start.point
	if not nav.pet_wall_pose_clear(exact_start.point,start_yaw,hull):return _error("The pet's body overlaps a wall at its starting place.")
	if is_finite(target_yaw) and not nav.pet_wall_pose_clear(exact_finish.point,target_yaw,hull):return _error("The pet's final facing would overlap a wall.")
	if int(exact_start.level)==int(exact_finish.level) and not _learning_active():
		var direct:Array=_connector(int(exact_start.level),exact_start.point,exact_finish.point,start_yaw,target_yaw)
		var unchanged:bool=exact_start.point.is_equal_approx(exact_finish.point) and (not is_finite(target_yaw) or absf(angle_difference(start_yaw,target_yaw))<.00001)
		if not direct.is_empty() or unchanged:
			var reached:Dictionary={"ok":true,"already_reached":unchanged,"points":PackedVector3Array([exact_start.point]),"segments":[],"distance":0.0,"generation":nav.generation}
			_append(reached,direct);return reached
	var baseline:Dictionary=nav.route_avoiding(from,to,checked_bodies,gap)
	if not bool(baseline.ok):return baseline
	occupied=bodies;body_gap=gap;hull=shape;origin=baseline.points[0]
	if not nav.pet_wall_pose_clear(baseline.points[0],start_yaw,hull):return _error("The pet's body overlaps a wall at its starting place.")
	var result:Dictionary={"ok":true,"already_reached":false,"points":PackedVector3Array([baseline.points[0]]),"segments":[],"distance":0.0,"generation":nav.generation}
	var yaw:float=start_yaw;var cursor:int=0
	if baseline.segments.is_empty():
		var turn:Array=_connector(int(from.level),baseline.points[0],baseline.points[0],yaw,target_yaw)
		if turn.is_empty() and is_finite(target_yaw) and absf(angle_difference(yaw,target_yaw))>.00001:return _error("There is no room for the pet to turn at its destination.")
		_append(result,turn);result.already_reached=result.segments.is_empty();return result
	while cursor<baseline.segments.size():
		var leg:Dictionary=baseline.segments[cursor]
		if str(leg.kind)=="stair":
			var direction:Vector3=Vector3(leg.to)-Vector3(leg.from)
			var stair_yaw:float=atan2(direction.x,direction.z)
			if absf(angle_difference(yaw,stair_yaw))>.00001:
				if not nav.pet_wall_step_clear(leg.from,leg.from,yaw,stair_yaw,hull):return _error("There is no room for the pet to turn onto the stairs.")
				level=int(from.level) if cursor==0 else int(baseline.segments[cursor-1].level)
				_append(result,[_segment(leg.from,leg.from,yaw,stair_yaw,true)])
				yaw=stair_yaw
			if not nav.pet_wall_step_clear(leg.from,leg.to,yaw,yaw,hull):return _error("A wall blocks the pet's body on the stairs.")
			var copied:Dictionary=leg.duplicate();copied.yaw_from=yaw;copied.yaw_to=yaw;copied.turn=false
			_append(result,[copied]);yaw=stair_yaw;cursor+=1;continue
		var floor_from:Vector3=leg.from;var floor_to:Vector3=leg.to;var floor_level:int=int(leg.level)
		cursor+=1
		while cursor<baseline.segments.size() and str(baseline.segments[cursor].kind)=="floor" and int(baseline.segments[cursor].level)==floor_level:
			floor_to=baseline.segments[cursor].to;cursor+=1
		var finish_yaw:float=target_yaw if cursor>=baseline.segments.size() else NAN
		if cursor<baseline.segments.size() and str(baseline.segments[cursor].kind)=="stair":
			var stair_direction:Vector3=Vector3(baseline.segments[cursor].to)-Vector3(baseline.segments[cursor].from)
			finish_yaw=atan2(stair_direction.x,stair_direction.z)
		var floor_route:Dictionary=_floor_route(floor_level,floor_from,floor_to,yaw,finish_yaw)
		if not bool(floor_route.ok):return floor_route
		_append(result,floor_route.segments)
		if not floor_route.segments.is_empty():yaw=float(floor_route.segments[-1].yaw_to)
	result.already_reached=result.segments.is_empty()
	return result

func _error(message:String)->Dictionary:return {"ok":false,"error":message,"generation":nav.generation}

func _learning_active()->bool:
	var now:int=Time.get_ticks_msec()
	for expiry:Variant in nav.penalties.values():
		if int(expiry)>now:return true
	return false

func _append(result:Dictionary,segments:Array)->void:
	for segment:Dictionary in segments:
		result.segments.append(segment);result.points.append(segment.to)
		result.distance=float(result.distance)+Vector3(segment.from).distance_to(segment.to)

func _segment(at:Vector3,to:Vector3,from_yaw:float,to_yaw:float,turn:bool)->Dictionary:
	return {"kind":"floor","stair_id":"","level":level,"from":at,"to":to,"yaw_from":from_yaw,"yaw_to":to_yaw,"turn":turn}

func _crowd_clear(from:Vector3,to:Vector3)->bool:
	var movement:Vector3=to-from
	for value:Variant in occupied:
		if not value is Vector3:return false
		var body:Vector3=value
		if absf(body.y-from.y)>.1:continue
		var before:float=from.distance_to(body)
		if before<body_gap and (body-from).dot(movement)<=.000001 and from.distance_to(origin)<.36:continue
		var weight:float=clampf((body-from).dot(movement)/maxf(movement.length_squared(),.0000001),0.0,1.0)
		if body.distance_to(from+movement*weight)<body_gap:return false
	return true

func _clear(from:Vector3,to:Vector3,from_yaw:float,to_yaw:float)->bool:
	return nav.segment_clear(level,from,to) and _crowd_clear(from,to) and nav.pet_wall_step_clear(from,to,from_yaw,to_yaw,hull)

func _connector(floor_level:int,from:Vector3,to:Vector3,from_yaw:float,to_yaw:float)->Array:
	level=floor_level
	var result:Array=[];var yaw:float=from_yaw
	if from.distance_to(to)>.00001:
		var direction:Vector3=to-from;var walking_yaw:float=atan2(direction.x,direction.z)
		if absf(angle_difference(yaw,walking_yaw))>.00001:
			if not _clear(from,from,yaw,walking_yaw):return []
			result.append(_segment(from,from,yaw,walking_yaw,true));yaw=walking_yaw
		if not _clear(from,to,yaw,yaw):return []
		result.append(_segment(from,to,yaw,yaw,false))
	if is_finite(to_yaw) and absf(angle_difference(yaw,to_yaw))>.00001:
		if not _clear(to,to,yaw,to_yaw):return []
		result.append(_segment(to,to,yaw,to_yaw,true))
	return result

func _position(state:Vector3i)->Vector3:return Vector3(state.x*CELL,LifeBuildingState.level_y(level),state.y*CELL)
func _yaw(state:Vector3i)->float:return float(state.z)*TAU/float(HEADINGS)
func _grid_key(cell:Vector2i)->String:return "%d:%d:%d"%[level,cell.x,cell.y]

func _pose(state:Vector3i)->bool:
	if _poses.has(state):return bool(_poses[state])
	var clear:bool=nav._floor_ids.has(_grid_key(Vector2i(state.x,state.y))) and nav.pet_wall_pose_clear(_position(state),_yaw(state),hull)
	_poses[state]=clear;return clear

func _cost(segments:Array)->float:
	var cost:float=0.0
	for segment:Dictionary in segments:cost+=Vector3(segment.from).distance_to(segment.to)+absf(angle_difference(float(segment.yaw_from),float(segment.yaw_to)))*TURN_COST
	return cost

func _anchors(point:Vector3,yaw:float,starting:bool)->Dictionary:
	var result:Dictionary={};var cell:=Vector2i(roundi(point.x/CELL),roundi(point.z/CELL))
	for x:int in range(-1,2):
		for z:int in range(-1,2):
			for heading:int in HEADINGS:
				var state:=Vector3i(cell.x+x,cell.y+z,heading)
				if not _pose(state):continue
				var at:Vector3=_position(state)
				if at.distance_to(point)>.36:continue
				var segments:Array=_connector(level,point,at,yaw,_yaw(state)) if starting else _connector(level,at,point,_yaw(state),yaw)
				var same:bool=at.distance_to(point)<.00001 and (not is_finite(yaw) or absf(angle_difference(_yaw(state),yaw))<.00001)
				if segments.is_empty() and not same:continue
				result[state]={"segments":segments,"cost":_cost(segments)}
	return result

func _floor_distances(goals:Dictionary,to:Vector3)->void:
	# Euclidean distance points at a wall even when the real entrance is at
	# the far side of the house. The ordinary floor graph supplies a lower
	# bound through those rooms; heading and full-body clearance add costs.
	_remaining.clear()
	var allowed:Dictionary={};var prefix:String=str(level)+":"
	for key:String in nav._floor_ids:
		if key.begins_with(prefix):allowed[int(nav._floor_ids[key])]=true
	var queue:Array=[];var settled:Dictionary={}
	for state:Vector3i in goals:
		var id:int=int(nav._floor_ids[_grid_key(Vector2i(state.x,state.y))])
		var cost:float=_position(state).distance_to(to)
		if cost>=float(_remaining.get(id,INF)):continue
		_remaining[id]=cost;_push(queue,[cost,cost,id])
	var learned:bool=_learning_active();var now:int=Time.get_ticks_msec()
	while not queue.is_empty():
		var entry:Array=_pop(queue);var id:int=int(entry[2])
		if settled.has(id) or float(entry[0])>float(_remaining.get(id,INF))+.000001:continue
		settled[id]=true
		var from:Vector3=nav._graph.get_point_position(id)
		for next:int in nav._graph.get_point_connections(id):
			if not allowed.has(next) or settled.has(next):continue
			if learned and int(nav.penalties.get(nav._edge_key(id,next),0))>now:continue
			var cost:float=float(entry[0])+from.distance_to(nav._graph.get_point_position(next))
			if cost>=float(_remaining.get(next,INF))-.000001:continue
			_remaining[next]=cost;_push(queue,[cost,cost,next])

func _heuristic(state:Vector3i)->float:
	var id:int=int(nav._floor_ids[_grid_key(Vector2i(state.x,state.y))])
	return float(_remaining.get(id,INF))

func _floor_route(floor_level:int,from:Vector3,to:Vector3,from_yaw:float,to_yaw:float)->Dictionary:
	level=floor_level;origin=from;_poses.clear()
	# Most bowl and resting routes are unobstructed. Their exact swept body and
	# end-facing turn can be checked without searching every nearby heading.
	if not _learning_active():
		var direct:Array=_connector(level,from,to,from_yaw,to_yaw)
		if not direct.is_empty():return {"ok":true,"segments":direct}
	var starts:Dictionary=_anchors(from,from_yaw,true);var goals:Dictionary=_anchors(to,to_yaw,false)
	if starts.is_empty() or goals.is_empty():return _error("There is no wall-clear place for the pet to enter or finish this route.")
	_floor_distances(goals,to)
	var queue:Array=[];var costs:Dictionary={};var parents:Dictionary={};var finished:Dictionary={}
	for state:Vector3i in starts:
		if not is_finite(_heuristic(state)):continue
		costs[state]=float(starts[state].cost)
		_push(queue,[costs[state]+_heuristic(state)*HEURISTIC_WEIGHT,float(costs[state]),state])
	var best:Vector3i;var best_cost:float=INF
	while not queue.is_empty():
		var entry:Array=_pop(queue);var state:Vector3i=entry[2]
		if float(entry[1])>float(costs.get(state,INF))+.000001 or finished.has(state):continue
		if float(entry[0])>=best_cost:break
		if finished.size()>=MAX_EXPANSIONS:return _error("No wall-clear pet route was found within the local search limit.")
		finished[state]=true
		if goals.has(state):
			var final_cost:float=float(costs[state])+float(goals[state].cost)
			if final_cost<best_cost:best_cost=final_cost;best=state
		var successors:Array=[]
		for turn:int in [-1,1]:successors.append(Vector3i(state.x,state.y,posmod(state.z+turn,HEADINGS)))
		var offset:Vector2i=OFFSETS[state.z];successors.append(Vector3i(state.x+offset.x,state.y+offset.y,state.z))
		for next:Vector3i in successors:
			if finished.has(next) or not _pose(next) or not is_finite(_heuristic(next)):continue
			var a:Vector3=_position(state);var b:Vector3=_position(next)
			if not _clear(a,b,_yaw(state),_yaw(next)):continue
			if a!=b:
				var first:int=int(nav._floor_ids[_grid_key(Vector2i(state.x,state.y))]);var last:int=int(nav._floor_ids[_grid_key(Vector2i(next.x,next.y))])
				var edge:String=nav._edge_key(first,last)
				if int(nav.penalties.get(edge,0))>Time.get_ticks_msec():continue
			var cost:float=float(costs[state])+a.distance_to(b)+absf(angle_difference(_yaw(state),_yaw(next)))*TURN_COST
			if cost>=float(costs.get(next,INF))-.000001:continue
			costs[next]=cost;parents[next]=state;_push(queue,[cost+_heuristic(next)*HEURISTIC_WEIGHT,cost,next])
	if not is_finite(best_cost):return _error("No route keeps the pet's body and turns clear of walls.")
	var states:Array[Vector3i]=[best];var cursor:Vector3i=best
	while parents.has(cursor):cursor=parents[cursor];states.push_front(cursor)
	var segments:Array=starts[states[0]].segments.duplicate(true)
	for index:int in range(1,states.size()):
		var a:Vector3i=states[index-1];var b:Vector3i=states[index]
		segments.append(_segment(_position(a),_position(b),_yaw(a),_yaw(b),a.x==b.x and a.y==b.y))
	segments.append_array(goals[best].segments)
	return {"ok":true,"segments":segments}

func _push(heap:Array,entry:Array)->void:
	heap.append(entry);var index:int=heap.size()-1
	while index>0:
		var parent:int=(index-1)/2
		if float(heap[parent][0])<=float(entry[0]):break
		heap[index]=heap[parent];index=parent
	heap[index]=entry

func _pop(heap:Array)->Array:
	var first:Array=heap[0];var last:Array=heap.pop_back()
	if heap.is_empty():return first
	var index:int=0
	while index*2+1<heap.size():
		var child:int=index*2+1
		if child+1<heap.size() and float(heap[child+1][0])<float(heap[child][0]):child+=1
		if float(heap[child][0])>=float(last[0]):break
		heap[index]=heap[child];index=child
	heap[index]=last;return first
