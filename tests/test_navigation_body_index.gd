extends SceneTree
## Detached graph equivalence and an optional saved-lot benchmark. No actors,
## rendering, household ticks, or writes to the supplied save.
## Run headless with --script res://tests/test_navigation_body_index.gd.
## NAV_BENCH_SAVE optionally names a save-library JSON copied into private data.
const Building=preload("res://scripts/building_state.gd")
const Navigation=preload("res://scripts/lot_navigation.gd")
var checks:int=0
var failures:int=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1

## Exact pre-index implementation, retained independently as the oracle.
func original_scan(nav:LifeLotNavigation,start:Vector3,occupied:Array[Vector3],radius:float)->PackedInt64Array:
	var changed:PackedInt64Array=[]
	for id:int in nav._graph.get_point_ids():
		if str(nav._locations[id].kind)!="floor" or nav._graph.is_point_disabled(id):continue
		var point:Vector3=nav._graph.get_point_position(id)
		for body:Vector3 in occupied:
			if absf(body.y-point.y)>.1 or point.distance_to(body)>=radius:continue
			if point.distance_to(start)<.36 and point.distance_to(body)>=start.distance_to(body)-.00001:continue
			nav._graph.set_point_disabled(id,true);changed.append(id);break
	return changed

func restore_points(nav:LifeLotNavigation,changed:PackedInt64Array)->void:
	for id:int in changed:nav._graph.set_point_disabled(id,false)

func disabled_points(nav:LifeLotNavigation)->PackedInt64Array:
	var disabled:PackedInt64Array=[]
	for id:int in nav._graph.get_point_ids():
		if nav._graph.is_point_disabled(id):disabled.append(id)
	disabled.sort();return disabled

func equivalent(nav:LifeLotNavigation,label:String,from:Dictionary,to:Dictionary,bodies:Array[Vector3],radius:float,pre_disabled:PackedInt64Array=[])->void:
	for id:int in pre_disabled:nav._graph.set_point_disabled(id,true)
	var before:PackedInt64Array=disabled_points(nav)
	var generation:int=nav.generation
	var expected_ids:PackedInt64Array=original_scan(nav,from.position,bodies,radius)
	var expected:Dictionary=nav.route(from,to)
	restore_points(nav,expected_ids);expected_ids.sort()
	var actual_ids:PackedInt64Array=nav._disable_occupied_points(from.position,bodies,radius)
	var actual:Dictionary=nav.route(from,to)
	var no_stairs:bool=true
	for id:int in actual_ids:
		if str(nav._locations[id].kind)!="floor":no_stairs=false
	restore_points(nav,actual_ids);actual_ids.sort()
	var wrapper:Dictionary=nav.route_avoiding(from,to,bodies,radius)
	check(actual_ids==expected_ids and actual==expected and wrapper==expected and disabled_points(nav)==before and nav.generation==generation and no_stairs,label+": identical disabled mask, exact route, generation and restored flags")
	for id:int in pre_disabled:nav._graph.set_point_disabled(id,false)

func model_controls()->void:
	var previous:Dictionary=Building.land
	Building.set_land(null)
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	state.walls=[{"id":"north","level":0,"x":0.0,"z":-5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"},{"id":"south","level":0,"x":0.0,"z":5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"}]
	var stair:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
	check(bool(stair.ok),"The two-floor fixture has a real supported staircase")
	if not bool(stair.ok):Building.land=previous;return
	var nav:=Navigation.new()
	check(bool(nav.rebuild(stair.after).ok),"The two-floor graph builds")
	var y:float=Building.level_y(0);var upper:float=Building.level_y(1)
	var start:Dictionary=Navigation.floor_location(0,Vector3(-3,y,-3))
	var goal:Dictionary=Navigation.floor_location(0,Vector3(3,y,3))
	var high_start:Dictionary=Navigation.floor_location(1,Vector3(-3,upper,-3))
	var high_goal:Dictionary=Navigation.floor_location(1,Vector3(3,upper,3))
	check(bool(nav.route(start,high_goal).ok),"The fixture includes a successful route through its stair nodes")
	var cases:Array=[
		{"label":"empty occupancy","bodies":[],"radius":.78},
		{"label":"negative coordinates","bodies":[Vector3(-2.62,y,-2.38)],"radius":.78},
		{"label":"duplicate and overlapping bodies","bodies":[Vector3(-2,y,-2),Vector3(-2,y,-2),Vector3(-1.75,y,-2)],"radius":.78},
		{"label":"start overlap and outward escape","bodies":[Vector3(-2.8,y,-3)],"radius":.78},
		{"label":"strict radius boundary","bodies":[Vector3(-2.5,y,-2.5)],"radius":.5},
		{"label":"below radius boundary","bodies":[Vector3(-2.5,y,-2.5)],"radius":.49999999},
		{"label":"above radius boundary","bodies":[Vector3(-2.5,y,-2.5)],"radius":.50000001},
		{"label":"vertical positive boundary","bodies":[Vector3(-2,y+.1,-2)],"radius":.78},
		{"label":"vertical negative boundary","bodies":[Vector3(-2,y-.1,-2)],"radius":.78},
		{"label":"outside vertical tolerance","bodies":[Vector3(-2,y+.10001,-2)],"radius":.78},
		{"label":"both floors and stair feet","bodies":[Vector3(0,y,-2),Vector3(2,upper,2),Vector3(-2,upper+.1,-2)],"radius":.78},
		{"label":"blocked destination","bodies":[goal.position],"radius":.78},
		{"label":"zero radius","bodies":[Vector3.ZERO],"radius":0.0},
		{"label":"negative radius","bodies":[Vector3.ZERO],"radius":-1.0},
		{"label":"huge radius bounded fallback","bodies":[Vector3(-2,y,-2)],"radius":1.0e100},
		{"label":"infinite radius compatibility","bodies":[Vector3(-2,y,-2)],"radius":INF},
		{"label":"negative infinite radius compatibility","bodies":[Vector3(-2,y,-2)],"radius":-INF},
		{"label":"NaN radius compatibility","bodies":[Vector3(-2,y,-2)],"radius":NAN},
		{"label":"huge body coordinates bounded fallback","bodies":[Vector3(1.0e30,y,-1.0e30)],"radius":.78},
		{"label":"infinite body compatibility","bodies":[Vector3(INF,y,0)],"radius":.78},
		{"label":"NaN body compatibility","bodies":[Vector3(NAN,y,0)],"radius":.78}]
	for spec:Dictionary in cases:
		var bodies:Array[Vector3]=[];bodies.assign(spec.bodies)
		equivalent(nav,str(spec.label),start,goal,bodies,float(spec.radius))
	var upper_bodies:Array[Vector3]=[Vector3(-2,upper,-2),Vector3(2,y,2),Vector3(2,upper+.1,2)]
	equivalent(nav,"upper-floor route",high_start,high_goal,upper_bodies,.78)
	equivalent(nav,"cross-floor route",start,high_goal,upper_bodies,.78)
	var disabled:PackedInt64Array=[int(nav._floor_ids[Navigation._cell_key(0,Vector2i(-8,-8))])]
	for id:int in nav._graph.get_point_ids():
		if str(nav._locations[id].kind)=="stair":disabled.append(id);break
	var overlaps:Array[Vector3]=[Vector3(-2,y,-2),Vector3(0,y,-2)]
	equivalent(nav,"pre-disabled floor and stair nodes",start,high_goal,overlaps,.78,disabled)
	# A venue changes the static land context while a detached old graph remains
	# queryable; its existing index, rather than that global context, owns bounds.
	Building.land={"version":1,"west":1,"east":0,"north":0}
	equivalent(nav,"land changed after graph rebuild",start,goal,overlaps,.78)
	Building.land=previous

func benchmark_saved(path:String)->void:
	var envelope:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not envelope is Dictionary or not envelope.get("data") is Dictionary:
		check(false,"The optional benchmark save is readable");return
	var data:Dictionary=envelope.data
	var context:Dictionary=data.members[0].state.character.world_state
	var previous:Dictionary=Building.land
	Building.set_land(context.get("land"))
	var state:Dictionary={};var obstacles:Array=[]
	var world:=LifeWorld.new()
	for entry:Dictionary in data.world:
		if str(entry.kind)=="__construction":state=Building.migrate(entry).get("state",{});continue
		if str(entry.kind) in ["meal","plate","puddle"] or bool(entry.get("derived",false)) or bool(entry.get("carried",false)) or LifeCatalog.passable(str(entry.kind)):continue
		obstacles.append_array(world.furnishing_obstacles(entry,int(entry.get("level",0))))
	world.free()
	var nav:=Navigation.new()
	var built:Dictionary=nav.rebuild(state,obstacles)
	check(bool(built.ok),"The saved lot's detached navigation graph reconstructs")
	if bool(built.ok):
		var residents:Dictionary=context.residents.locations.home
		var queries:Array=[]
		for id:String in residents:
			var start:Vector3=Vector3(residents[id].position[0],residents[id].position[1],residents[id].position[2])
			var goal:=Vector3(8.5*float(residents[id].direction),Building.level_y(0),float(LifeResidentCatalogue.PEOPLE[id].lane))
			var bodies:Array[Vector3]=[]
			for peer:String in residents:
				if peer!=id and str(residents[peer].phase)!="home":
					var at:Array=residents[peer].position;bodies.append(Vector3(at[0],at[1],at[2]))
			for member:Dictionary in data.members:
				if not member.state.away_state.is_empty():continue
				var at:Array=member.state.character.world_state.player;bodies.append(Vector3(at[0],at[1],at[2]))
			queries.append({"from":Navigation.floor_location(0,start),"to":Navigation.floor_location(0,goal),"bodies":bodies})
		var scan_us:int=0;var route_us:int=0;var restore_us:int=0;var indexed_us:int=0;var indexed_route_us:int=0;var changed_total:int=0;var runs:int=0
		var all_equal:bool=true
		for repeat:int in range(12):
			for query:Dictionary in queries:
				var clock:int=Time.get_ticks_usec()
				var changed:PackedInt64Array=original_scan(nav,query.from.position,query.bodies,LifeTraversal.ROUTE_CLEARANCE)
				var after_scan:int=Time.get_ticks_usec()
				var expected:Dictionary=nav.route(query.from,query.to)
				var after_route:int=Time.get_ticks_usec()
				restore_points(nav,changed)
				if repeat>1:
					scan_us+=after_scan-clock;route_us+=after_route-after_scan;restore_us+=Time.get_ticks_usec()-after_route;changed_total+=changed.size();runs+=1
				clock=Time.get_ticks_usec()
				var indexed:PackedInt64Array=nav._disable_occupied_points(query.from.position,query.bodies,LifeTraversal.ROUTE_CLEARANCE)
				after_scan=Time.get_ticks_usec()
				var actual:Dictionary=nav.route(query.from,query.to)
				after_route=Time.get_ticks_usec()
				restore_points(nav,indexed);indexed.sort();changed.sort()
				all_equal=all_equal and indexed==changed and actual==expected
				if repeat>1:indexed_us+=after_scan-clock;indexed_route_us+=after_route-after_scan
		check(all_equal,"Every repeated saved-lot query has the exact original disabled mask and route")
		print("NAV_BODY_BENCHMARK ",JSON.stringify({"points":nav._graph.get_point_count(),"queries":runs,"original_scan_us_per_query":float(scan_us)/runs,"original_route_us_per_query":float(route_us)/runs,"indexed_scan_us_per_query":float(indexed_us)/runs,"indexed_route_us_per_query":float(indexed_route_us)/runs,"restore_us_per_query":float(restore_us)/runs,"disabled_per_query":float(changed_total)/runs}))
	Building.land=previous

func run()->void:
	model_controls()
	var path:String=OS.get_environment("NAV_BENCH_SAVE")
	if not path.is_empty():benchmark_saved(path)
	print("NAVIGATION_BODY_INDEX %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 and checks>0 else 1)
