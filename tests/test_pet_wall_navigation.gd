extends SceneTree
## Detached oriented routes: narrow doors, safe corner turns, final bowl facing,
## moving bodies and real tagged stairs. The sweep oracle clips independently
## transformed body polygons against the actual walls at much finer intervals.
const Building=preload("res://scripts/building_state.gd")
const Navigation=preload("res://scripts/lot_navigation.gd")
const DOG:Dictionary={"front":.66,"back":.64,"half_width":.20,"height":.66}
const CAT:Dictionary={"front":.43,"back":.58,"half_width":.15,"height":.43}
var checks:int=0
var failures:int=0

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1;push_error(message)

func wall(id:String,x:float,z:float,w:float,d:float,level:int=0)->Dictionary:
	return {"id":id,"level":level,"x":x,"z":z,"w":w,"d":d,"height":2.6,"cut":true,"material":"eae7d7"}

func shape_clear(state:Dictionary,point:Vector3,yaw:float,hull:Dictionary)->bool:
	var body:=PackedVector2Array()
	var basis:=Basis(Vector3.UP,yaw)
	for local:Vector3 in [Vector3(-hull.half_width,0,-hull.back),Vector3(hull.half_width,0,-hull.back),Vector3(hull.half_width,0,hull.front),Vector3(-hull.half_width,0,hull.front)]:
		var at:Vector3=point+basis*local;body.append(Vector2(at.x,at.z))
	for record:Dictionary in state.walls:
		var base:float=Building.level_y(int(record.level))
		if point.y+float(hull.height)<base or point.y-.06>base+float(record.height):continue
		var rect:Rect2=Building.rect(record)
		var polygon:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		if not Geometry2D.intersect_polygons(body,polygon).is_empty():return false
	return true

func route_clear(state:Dictionary,result:Dictionary,hull:Dictionary,start_yaw:float)->bool:
	if not bool(result.get("ok",false)) or result.points.size()!=result.segments.size()+1:return false
	var prior:Vector3=result.points[0];var yaw:float=start_yaw
	for leg:Dictionary in result.segments:
		var from:Vector3=leg.from;var to:Vector3=leg.to
		if from.distance_to(prior)>.00001 or absf(angle_difference(yaw,float(leg.yaw_from)))>.00001:return false
		if bool(leg.turn) and from.distance_to(to)>.00001:return false
		if not bool(leg.turn) and Vector2(to.x-from.x,to.z-from.z).length()>.00001:
			if absf(angle_difference(float(leg.yaw_to),atan2(to.x-from.x,to.z-from.z)))>.00001:return false
		var samples:int=maxi(1,maxi(ceili(from.distance_to(to)/.005),ceili(absf(angle_difference(float(leg.yaw_from),float(leg.yaw_to)))/.01)))
		for step:int in samples+1:
			var t:float=float(step)/float(samples)
			if not shape_clear(state,from.lerp(to,t),lerp_angle(float(leg.yaw_from),float(leg.yaw_to),t),hull):return false
		prior=to;yaw=float(leg.yaw_to)
	return prior.distance_to(result.points[-1])<.00001

func request(nav:LifeLotNavigation,from:Vector3,to:Vector3,hull:Dictionary,yaw:float,finish:float=NAN,bodies:Array=[])->Dictionary:
	return nav.pet_route_avoiding(nav.floor_location(roundi((from.y-.16)/3.0),from),nav.floor_location(roundi((to.y-.16)/3.0),to),bodies,.65,hull,yaw,finish)

func doors()->void:
	var state:Dictionary=Building.fresh()
	state.walls=[wall("door_n",0,-2.265,.08,3.47),wall("door_s",0,2.265,.08,3.47)]
	var nav:=Navigation.new();check(bool(nav.rebuild(state).ok),"The narrow doorway fixture builds")
	var threshold:=Vector3(0,.16,0)
	check(nav.point_clear(0,threshold) and nav.pet_wall_pose_clear(threshold,PI*.5,DOG),"An aligned dog fits through the ordinary 1.06m doorway")
	check(not nav.pet_wall_pose_clear(threshold,0,DOG) and not nav.pet_wall_step_clear(threshold,threshold,PI*.5,0,DOG),"The long dog cannot stand sideways or turn through the doorway walls")
	for shape:Dictionary in [DOG,CAT]:
		var result:Dictionary=request(nav,Vector3(-2,.16,0),Vector3(2,.16,0),shape,PI*.5,PI*.5)
		check(bool(result.ok) and absf(float(result.get("distance",0))-4.0)<.00001,"An aligned pet crosses the doorway directly without a wide-body detour")
		check(route_clear(state,result,shape,PI*.5),"Every translated and turning body polygon stays outside the doorway walls")
	var destination:=Vector3(0,.16,0)
	var muzzle:=Vector3(-.4,.16,.75)
	check(nav.point_clear(0,muzzle) and not nav.pet_wall_pose_clear(muzzle,PI*.5,DOG),"A clear root position can still leave the muzzle or tail inside a wall")
	var facing:Dictionary=request(nav,Vector3(-2,.16,0),destination,DOG,PI*.5,0)
	check(not bool(facing.ok),"A requested bowl-facing pose is refused when its complete body cannot fit")
	var same:Dictionary=request(nav,threshold,threshold,DOG,PI*.5,0)
	check(not bool(same.ok),"Already-arrived pets cannot bypass the wall check with an unsafe stationary turn")
	var clear_turn:Dictionary=request(nav,Vector3(-2,.16,0),Vector3(-2,.16,0),DOG,PI*.5,0)
	check(bool(clear_turn.ok) and not bool(clear_turn.already_reached) and clear_turn.segments.size()==1 and bool(clear_turn.segments[0].turn),"A safe already-arrived turn remains an explicit route segment")
	check(route_clear(state,clear_turn,DOG,PI*.5),"The final-facing turn clears the walls throughout its rotation")

func corners()->void:
	for outline:int in range(3):
		var state:Dictionary=Building.fresh()
		state.walls=[wall("partition",0,0,.08,4.0)]
		if outline>=1:state.walls.append(wall("corner",1,-2,2.0,.08))
		if outline>=2:state.walls.append(wall("return",2,-1,.08,2.0))
		var nav:=Navigation.new();check(bool(nav.rebuild(state).ok),"Wall outline %d builds"%outline)
		check(not nav.pet_wall_step_clear(Vector3(-2,.16,0),Vector3(3,.16,0),PI*.5,PI*.5,DOG),"A long walking frame cannot tunnel the dog across outline %d"%outline)
		var result:Dictionary=request(nav,Vector3(-2,.16,0),Vector3(3,.16,0),DOG,PI*.5,PI*.5)
		check(bool(result.ok) and float(result.get("distance",0))>5.5,"The oriented dog route detours around outline %d"%outline)
		check(route_clear(state,result,DOG,PI*.5),"The dog clears the full walls through every turn around outline %d"%outline)
		var turns:int=0
		for leg:Dictionary in result.get("segments",[]):
			if bool(leg.turn):turns+=1
		check(turns>=2,"Outline %d includes explicit stationary turns before direction changes"%outline)
		var crowd:Dictionary=request(nav,Vector3(-2,.16,0),Vector3(3,.16,0),CAT,PI*.5,PI*.5,[Vector3(0,.16,2.75)])
		var separated:bool=bool(crowd.ok)
		for leg:Dictionary in crowd.get("segments",[]):
			var from:Vector3=leg.from;var to:Vector3=leg.to;var move:Vector3=to-from
			var body:=Vector3(0,.16,2.75)
			var weight:float=clampf((body-from).dot(move)/maxf(move.length_squared(),.000001),0,1)
			separated=separated and body.distance_to(from+move*weight)>=.65-.00001
		check(separated and route_clear(state,crowd,CAT,PI*.5),"Outline %d respects a stationary body while retaining wall clearance"%outline)

func floors()->void:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	state.walls=[wall("north",0,-5,8,.14),wall("south",0,5,8,.14),wall("upper_partition",2,0,.08,2,1)]
	var stair:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
	check(bool(stair.ok),"The two-floor pet fixture builds a supported real staircase")
	if not bool(stair.ok):return
	var nav:=Navigation.new();check(bool(nav.rebuild(stair.after).ok),"The pet's two-floor graph builds")
	var result:Dictionary=request(nav,Vector3(-2,.16,-3),Vector3(3,3.16,0),DOG,PI*.5,PI*.5)
	var flight:int=0
	for leg:Dictionary in result.get("segments",[]):
		if str(leg.kind)=="stair" and not str(leg.stair_id).is_empty():flight+=1
	check(bool(result.ok) and flight==Building.STAIR_STEPS+2,"The oriented route retains every authored staircase edge")
	check(route_clear(stair.after,result,DOG,PI*.5),"The dog keeps its body clear of walls on both floors and throughout the flight")
	var aligned:Dictionary=request(nav,Building.stair_point(stair.after.stairs[0],-.5),Vector3(3,3.16,2),DOG,PI*.5)
	check(bool(aligned.ok) and bool(aligned.segments[0].turn) and aligned.segments[0].from==aligned.segments[0].to,"A pet starting on a landing turns before walking onto the stair flight")
	check(nav.pet_wall_pose_clear(Vector3(2,.16,0),0,DOG) and not nav.pet_wall_pose_clear(Vector3(2,3.16,0),0,DOG),"Upper walls block upper pets while leaving the lower floor clear")
	check(nav.pet_wall_pose_clear(Vector3(2,2.4,0),0,DOG) and not nav.pet_wall_pose_clear(Vector3(2,2.55,0),0,DOG),"A climbing pet's head meets an upper wall before its root reaches that storey")
	var before:int=nav.generation
	var invalid:Dictionary=stair.after.duplicate(true);invalid.walls[0].w=-1
	check(not bool(nav.rebuild(invalid).ok) and nav.generation==before and not nav.pet_wall_pose_clear(Vector3(2,3.16,0),0,DOG),"Failed rebuilds preserve both navigation and the pet wall geometry")

func distant_entrance()->void:
	var state:Dictionary=Building.fresh()
	state.walls=[wall("front",0,6,12,.14),wall("west",-6,0,.14,12),wall("east",6,0,.14,12),wall("back_west",-3.265,-6,5.47,.14),wall("back_east",3.265,-6,5.47,.14)]
	var nav:=Navigation.new();check(bool(nav.rebuild(state).ok),"A home whose only doorway is at the far side builds")
	var started:int=Time.get_ticks_usec()
	var route:Dictionary=request(nav,Vector3(-2,.16,8.5),Vector3(-1.5,.16,1.5),CAT,0)
	print("PET_DISTANT_ENTRANCE_USEC ",Time.get_ticks_usec()-started)
	check(bool(route.ok) and float(route.get("distance",0))>30.0,"The bounded oriented search finds the long route to the distant doorway")
	check(route_clear(state,route,CAT,0),"The long arrival clears the full walls and turns at the distant doorway")

func inputs()->void:
	var nav:=Navigation.new();nav.rebuild(Building.fresh())
	var bad:Dictionary=DOG.duplicate();bad.front=NAN
	check(not nav.pet_wall_pose_clear(Vector3(0,.16,0),0,bad),"A nonfinite animal hull is refused even on a bare lot")
	check(not bool(request(nav,Vector3(-2,.16,0),Vector3(2,.16,0),DOG,INF).ok),"A nonfinite starting direction is refused")
	check(not bool(request(nav,Vector3(-2,.16,0),Vector3(2,.16,0),DOG,0,INF).ok),"A nonfinite final direction is refused")
	check(not bool(request(nav,Vector3(-2,.16,0),Vector3(2,.16,0),DOG,0,NAN,[Vector3.INF]).ok),"A nonfinite occupied body is refused")
	var body:=Vector3(-1.6,.16,0)
	var crowded:Dictionary=request(nav,Vector3(-2,.16,0),Vector3(2,.16,0),DOG,PI*.5,PI*.5,[body])
	var separating:bool=bool(crowded.ok)
	for leg:Dictionary in crowded.get("segments",[]):
		var from:Vector3=leg.from;var movement:Vector3=Vector3(leg.to)-from
		var weight:float=clampf((body-from).dot(movement)/maxf(movement.length_squared(),.000001),0,1)
		separating=separating and body.distance_to(from+movement*weight)>=.4-.00001
	check(separating and float(crowded.get("distance",0))>4.4,"A pet initially near a body escapes around it instead of using a long direct step through it")
	var started:int=Time.get_ticks_usec()
	for count:int in range(100):
		var direct:Dictionary=request(nav,Vector3(-2,.16,0),Vector3(2,.16,0),DOG,PI*.5,PI*.5)
		if not bool(direct.ok):failures+=1
	print("PET_WALL_DIRECT_100_USEC ",Time.get_ticks_usec()-started)

func run()->void:
	var previous:Dictionary=Building.land;Building.set_land(null)
	doors();corners();floors();distant_entrance();inputs();Building.land=previous
	print("PET_WALL_NAVIGATION %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
