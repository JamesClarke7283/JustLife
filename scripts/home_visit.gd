extends RefCounted
class_name LifeHomeVisit
## One invited neighbor follows real ground routes; household actions keep ownership.
const ARRIVAL_MINUTES:float=180.0
const WELCOME_MINUTES:float=120.0
const STAY_MINUTES:float=360.0
const GREETING_MINUTES:float=25.0
const Building=preload("res://scripts/building_state.gd")
var _owner:WeakRef
var app:Node:
	get:
		var current:Variant=_owner.get_ref()
		return current.app if current!=null else null
var state:Dictionary={}
var next_serial:int=1
var _welcome_action:Dictionary={}
var _departure_action:Dictionary={}
var _notice_in:float=0.0

func _init(residents:RefCounted)->void:_owner=weakref(residents)
func active()->bool:return not state.is_empty()
func owns(id:String)->bool:return active() and str(state.guest)==id
func _now()->float:return (app.household.day-1)*1440.0+app.household.minutes
func _body(id:String)->LifeActor:return app.world.actors.get(id)
func _packed(point:Vector3)->Array:return [point.x,point.y,point.z]
func _vector(value:Array)->Vector3:return Vector3(value[0],value[1],value[2])
func reset()->void:
	state.clear();next_serial=1;_welcome_action={};_departure_action={};_notice_in=0.0

func social_allowed(id:String,action:Dictionary={})->bool:
	if not owns(id):return true
	if str(state.phase) in ["waiting","inside"]:return true
	return not _departure_action.is_empty() and is_same(action,_departure_action) and str(action.get("phase","")) in ["active","approach"] and bool(action.get("paid",false))

func welcome_start_allowed(action:Dictionary)->bool:
	if not action.has("home_visit_serial"):return true
	if not active() or str(state.phase)!="waiting" or not is_same(action,_welcome_action):return false
	if bool(action.get("paid",false)):return _started_at(action)<=float(state.arrived_at)+WELCOME_MINUTES
	return _now()<=float(state.arrived_at)+WELCOME_MINUTES

func requirement(id:String)->String:
	if active():return "One neighbor is already visiting. Say goodbye and let them leave first."
	if app.current_venue!="home" or app.mode!="live":return "Invite a neighbor while you are at home in Live mode."
	if not LifeResidents.PEOPLE.has(id) or not app.residents.can_visit(id):return "Reach 20 friendship with this neighbor before inviting them over."
	if _building().is_empty():return "This home needs a supported ground-floor layout before inviting a guest."
	if not app.residents.trip.is_empty():return "Finish the current trip before inviting a neighbor."
	if not app.residents._speaker(id).is_empty():return "Finish the current conversation with this neighbor before inviting them over."
	return ""

func invite(id:String)->bool:
	var reason:String=requirement(id)
	if not reason.is_empty():app.show_notice(reason);return false
	var actor:LifeActor=_body(id)
	if not is_instance_valid(actor):app.show_notice("This neighbor is unavailable right now.");return false
	var start:Vector3=actor.position if app.residents.present(id) else _curb_point(id)
	if not start.is_finite():app.show_notice("Clear a place on the sidewalk for your guest.");return false
	var welcome:Vector3=Vector3.INF
	var incoming:PackedVector3Array=[]
	for z:float in [6.25,6.75,7.25,5.75]:
		for x:float in [-.5,.5,-1.5,1.5,-2.5,2.5]:
			var point:=Vector3(x,.16,z)
			if not _clear(id,point):continue
			var route:PackedVector3Array=_route(start,point,id)
			if route.is_empty():continue
			welcome=point;incoming=route;break
		if welcome.is_finite():break
	if not welcome.is_finite():app.show_notice("Clear a ground-floor path from the sidewalk to welcome your guest.");return false
	var inside:Vector3=_inside_point(id,welcome)
	var exit:Vector3=_curb_point(id)
	if not inside.is_finite() or not exit.is_finite() or _route(inside,exit,id).is_empty():
		app.show_notice("Make room for a clear ground-floor gathering place and a route back to the sidewalk.");return false
	# All fallible layout/presence checks precede any queue, body or lifecycle change.
	state={"serial":next_serial,"guest":id,"phase":"arriving","created_at":_now(),"arrived_at":-1.0,"admitted_at":-1.0,"phase_at":_now(),"welcome":welcome,"inside":inside,"exit":exit,"route":{"points":incoming,"point":0},"greeting":{},"next_greeting":1,"departure":{},"blocked":false}
	next_serial+=1
	actor.position=start;app.world.set_actor_away(id,false,false)
	var resident:Dictionary=app.residents.locations.home[id]
	resident.phase="walking";resident.position=_packed(start)
	app.residents.publish_targets()
	app.show_notice(str(LifeResidents.PEOPLE[id].name)+" is coming over. Welcome them when they arrive.")
	return true

func _route(from:Vector3,to:Vector3,id:String)->PackedVector3Array:
	if app.world.point_level(from)!=0 or app.world.point_level(to)!=0:return []
	return app.traversal._floor_route(from,to,id)

func _building()->Dictionary:
	# The world already builds this read-only migrated view for legacy homes.
	# Reading it does not rewrite construction or the serialized layout.
	var checked:Dictionary=app.world.construction.validated_state()
	return checked.state if bool(checked.ok) else {}

func _clear(id:String,point:Vector3,building:Dictionary={})->bool:
	if app.world.point_level(point)!=0 or not app.traversal._free(id,point):return false
	if building.is_empty():building=_building()
	for stair:Dictionary in building.get("stairs",[]):
		var footprint:=Rect2(Vector2(point.x,point.z)-Vector2(.4,.4),Vector2(.8,.8))
		if footprint.intersects(Building.stair_rect(stair)) or footprint.intersects(Building.landing_rect(stair,false)):return false
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if not action.is_empty() and point.distance_to(action.target_position)<.85:return false
		var motion:Dictionary=app.motion_states.get(str(member.id),{})
		if bool(motion.get("walk",false)) and point.distance_to(motion.get("destination",Vector3.INF))<.85:return false
	return true

func _curb_point(id:String)->Vector3:
	for x:float in [-8.25,8.25,-7.25,7.25,-6.25,6.25]:
		for z:float in [8.25,8.75,7.75]:
			var point:=Vector3(x,.16,z)
			if _clear(id,point):return point
	return Vector3.INF

func _inside_point(id:String,from:Vector3)->Vector3:
	var candidates:Array[Vector3]=[]
	var building:Dictionary=_building()
	for floor:Dictionary in building.get("floors",[]):
		if int(floor.level)!=0:continue
		var area:Rect2=Building.rect(floor)
		for x:int in range(ceili(area.position.x*2)+1,floori(area.end.x*2)):
			for z:int in range(ceili(area.position.y*2)+1,floori(area.end.y*2)):
				var point:=Vector3(x*.5,.16,z*.5)
				if not _clear(id,point,building):continue
				if not Building.footprint_supported(building,0,Rect2(Vector2(point.x,point.z)-Vector2(.4,.4),Vector2(.8,.8)),false):continue
				candidates.append(point)
	candidates.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.distance_squared_to(from)<b.distance_squared_to(from))
	for point:Vector3 in candidates:
		if not _route(from,point,id).is_empty():return point
	return Vector3.INF

func reconcile()->void:
	if active() and str(state.phase)=="waiting" and not state.greeting.is_empty() and not _valid_greeting():
		state.greeting={};_welcome_action={}

func welcome(member_id:String)->bool:
	reconcile()
	if not active() or str(state.phase)!="waiting":app.show_notice("Wait until your guest arrives before welcoming them.");return false
	if not state.greeting.is_empty():app.show_notice("A welcome is already in the queue.");return false
	if _now()>float(state.arrived_at)+WELCOME_MINUTES:app.show_notice("Your guest is getting ready to leave.");return false
	var sim:LifeSim=app.household.member_sim(member_id)
	var actor:LifeActor=_body(member_id)
	if not is_instance_valid(sim) or sim.is_away() or not is_instance_valid(actor) or not actor.visible:
		app.show_notice("Choose a household Lifelet who is here to welcome the guest.");return false
	var guest:String=str(state.guest)
	if not sim.queue_action("friendly",guest,_body(guest).position+Vector3(0,0,.8)):return false
	_welcome_action=sim.action_queue[-1]
	var token:int=int(state.next_greeting);state.next_greeting=token+1
	_welcome_action.home_visit_serial=int(state.serial);_welcome_action.home_visit_token=token
	state.greeting={"member":member_id,"token":token,"active_at":-1.0}
	app.show_notice("Welcome queued. Your Lifelet will finish their earlier activities first.")
	return true

func _started_at(action:Dictionary)->float:
	if not action.has("started_day") or not action.has("started_minutes"):return -1.0
	return (float(action.started_day)-1.0)*1440.0+float(action.started_minutes)

func _valid_greeting()->bool:
	if state.greeting.is_empty() or _welcome_action.is_empty():return false
	var member:String=str(state.greeting.member)
	var sim:LifeSim=app.household.member_sim(member)
	return is_instance_valid(sim) and sim.action_queue.has(_welcome_action) and str(_welcome_action.get("id",""))=="friendly" and str(_welcome_action.get("target_id",""))==str(state.guest)

func action_finished(member_id:String,action:Dictionary)->void:
	if active() and str(state.phase)=="leaving" and is_same(action,_departure_action):state.departure={};_departure_action={};return
	if not active() or str(state.phase)!="waiting" or state.greeting.is_empty():return
	if member_id!=str(state.greeting.member) or not is_same(action,_welcome_action):return
	var event_sim:LifeSim=app.household.member_sim(member_id)
	var event_time:float=(event_sim.day-1)*1440.0+event_sim.minutes
	var started:float=_started_at(action)
	if started<0 or started>float(state.arrived_at)+WELCOME_MINUTES or not bool(action.get("paid",false)) or float(action.get("duration",-1))!=GREETING_MINUTES or float(action.get("elapsed",-1))<GREETING_MINUTES:return
	if not bool(action.get("social_accepted",false)) or str(action.get("id",""))!="friendly":return
	var host:LifeActor=_body(member_id);var guest:LifeActor=_body(str(state.guest))
	if not is_instance_valid(host) or not host.visible or not guest.visible or host.position.distance_to(guest.position)>1.8:return
	var inside:Vector3=state.inside
	if not _clear(str(state.guest),inside):inside=_inside_point(str(state.guest),guest.position)
	if not inside.is_finite():goodbye("There is no clear gathering space. Your guest is heading home.",event_time);return
	var route:PackedVector3Array=_route(guest.position,inside,str(state.guest))
	if route.is_empty():goodbye("The route inside is blocked. Your guest is heading home.",event_time);return
	state.inside=inside;state.phase="entering";state.phase_at=event_time;state.admitted_at=event_time;state.route={"points":route,"point":0};state.greeting={};_welcome_action={}
	app.show_notice(str(LifeResidents.PEOPLE[str(state.guest)].name)+" is coming inside.")

func goodbye(message:String="Your guest is heading home after the current conversation.",event_time:float=-1.0)->void:
	if not active() or str(state.phase)=="leaving":return
	_departure_action={};state.departure={}
	var speaker:Dictionary=app.residents._speaker(str(state.guest))
	if not speaker.is_empty():
		var current:Dictionary=speaker.sim.get_current_action()
		if str(current.get("phase",""))=="active" and not (is_same(current,_welcome_action) and _started_at(current)>float(state.arrived_at)+WELCOME_MINUTES):
			_departure_action=current;state.departure={"member":str(speaker.id),"id":str(current.id),"started_at":_started_at(current),"duration":float(current.duration)}
	# Welcome identity ends here; the same paid action now owns departure only.
	if not _departure_action.is_empty():
		_departure_action.erase("home_visit_serial");_departure_action.erase("home_visit_token")
	state.phase="leaving";state.phase_at=event_time if event_time>=0 else _now();state.route={"points":PackedVector3Array(),"point":0};state.greeting={};_welcome_action={}
	app._cancel_guest_conversations(str(state.guest),_departure_action)
	app.residents.publish_targets();app.show_notice(message)

func _departure_held()->bool:
	if state.departure.is_empty() or _departure_action.is_empty():return false
	var sim:LifeSim=app.household.member_sim(str(state.departure.member))
	return is_instance_valid(sim) and is_same(sim.get_current_action(),_departure_action) and str(_departure_action.get("phase","")) in ["active","approach"] and bool(_departure_action.get("paid",false)) and _now()<=float(state.departure.started_at)+float(state.departure.duration)+.001

func tick(delta:float)->void:
	if not active():return
	var id:String=str(state.guest);var actor:LifeActor=_body(id)
	var speed:float=float(app.household.speed);var now:float=_now()
	if speed<=0:actor.animate(delta,0,false,"");return
	var phase:String=str(state.phase)
	if phase=="arriving" and now>=float(state.created_at)+ARRIVAL_MINUTES:goodbye("The welcome path took too long. Your guest is heading home.")
	if phase=="entering" and now>=float(state.phase_at)+ARRIVAL_MINUTES:goodbye("The way inside is still blocked. Your guest is heading home.")
	if phase=="waiting":
		if not state.greeting.is_empty() and not _valid_greeting():state.greeting={};_welcome_action={}
		var bounded:bool=false
		if _valid_greeting() and str(_welcome_action.get("phase",""))=="active":
			var started:float=_started_at(_welcome_action)
			bounded=started>=0 and started<=float(state.arrived_at)+WELCOME_MINUTES and now<=started+GREETING_MINUTES+.001
			if bounded:state.greeting.active_at=started
		if now>=float(state.arrived_at)+WELCOME_MINUTES and not bounded:goodbye("Your guest waited for a welcome and is heading home.")
	if str(state.phase)=="inside" and now>=float(state.phase_at)+STAY_MINUTES:goodbye("It is time for your guest to head home.")
	phase=str(state.phase)
	var moving:bool=false;var talk:String=""
	if phase in ["arriving","entering","leaving"] and not (phase=="leaving" and _departure_held()):
		var destination:Vector3=state.welcome if phase=="arriving" else (state.inside if phase=="entering" else state.exit)
		if state.route.points.is_empty():state.route={"points":_route(actor.position,destination,id),"point":0}
		if not state.route.points.is_empty():
			var result:Dictionary=app.traversal._walk(id,state.route,delta*speed)
			moving=bool(result.moved);state.blocked=bool(result.blocked)
			if int(state.route.point)>=state.route.points.size():
				if phase=="arriving":
					state.phase="waiting";state.arrived_at=now;state.phase_at=now
					if app.household.speed>1:
						app.household.set_speed(1);app.show_notice(str(LifeResidents.PEOPLE[id].name)+" is here. Slowing down so you can welcome them.")
					else:app.show_notice("Your guest is here. Choose Welcome in to invite them inside.")
				elif phase=="entering":state.phase="inside";state.phase_at=now
				else:_finish();return
		else:state.blocked=true
		if bool(state.blocked):
			_notice_in-=delta
			if _notice_in<=0:_notice_in=5.0;app.show_notice("Your guest's path is blocked. Move a nearby Lifelet in Live mode so they can pass.")
	else:
		var speaker:Dictionary=app.residents._speaker(id)
		if not speaker.is_empty():
			var current:Dictionary=speaker.sim.get_current_action()
			talk=str(current.id) if str(current.get("phase",""))=="active" else ""
			var toward:Vector3=_body(str(speaker.id)).position-actor.position
			actor.rotation.y=lerp_angle(actor.rotation.y,atan2(toward.x,toward.z),minf(delta*4,1))
	actor.animate(delta,speed,moving,talk)
	var resident:Dictionary=app.residents.locations.home[id]
	resident.position=_packed(actor.position);resident.rotation=actor.rotation.y

func _finish()->void:
	var id:String=str(state.guest);var actor:LifeActor=_body(id)
	var resident:Dictionary=app.residents.locations.home[id]
	resident.phase="home";resident.position=_packed(actor.position);resident.rotation=actor.rotation.y;resident.wait=48.0 if id=="maya" else 72.0
	app.world.set_actor_away(id,true,true);state={};_welcome_action={};_departure_action={}
	app.residents.publish_targets();app.show_notice(str(LifeResidents.PEOPLE[id].name)+" has headed home.")

func snapshot()->Dictionary:
	var saved:Dictionary=state.duplicate(true)
	if not saved.is_empty():
		if str(saved.phase)=="waiting" and not _valid_greeting():saved.greeting={}
		for key:String in ["welcome","inside","exit"]:saved[key]=_packed(saved[key])
		saved.route.points=Array(saved.route.points).map(func(point:Vector3)->Array:return _packed(point))
		var actor:LifeActor=_body(str(saved.guest))
		saved.position=_packed(actor.position);saved.rotation=actor.rotation.y
	return {"version":1,"next_serial":next_serial,"visit":saved}

func restore(value:Dictionary)->void:
	state=value.get("visit",{}).duplicate(true);next_serial=int(value.get("next_serial",1));_welcome_action={};_departure_action={}
	if state.is_empty():return
	state.serial=int(state.serial);state.next_greeting=int(state.next_greeting)
	if not state.greeting.is_empty():state.greeting.token=int(state.greeting.token)
	for key:String in ["welcome","inside","exit"]:state[key]=_vector(state[key])
	var points:=PackedVector3Array()
	for point:Array in state.route.points:points.append(_vector(point))
	state.route.points=points;state.route.point=int(state.route.point)
	if not state.greeting.is_empty():
		var sim:LifeSim=app.household.member_sim(str(state.greeting.member))
		for action:Dictionary in sim.action_queue:
			if int(action.get("home_visit_serial",-1))==int(state.serial) and int(action.get("home_visit_token",-1))==int(state.greeting.token):_welcome_action=action
	if not state.departure.is_empty():_departure_action=app.household.member_sim(str(state.departure.member)).get_current_action()

func physical_error()->String:
	if not active():return ""
	if app.current_venue!="home":return "A home guest was saved in a different venue."
	var id:String=str(state.guest);var actor:LifeActor=_body(id)
	if not is_instance_valid(actor) or not actor.visible:return "The saved guest is not physically present."
	if actor.position!=_vector(state.position) or actor.rotation.y!=float(state.rotation):return "The saved guest transform is inconsistent."
	if not app.world.lot_navigation.point_clear(0,actor.position):return "The saved guest is on unsupported or blocked ground."
	for key:String in ["welcome","inside","exit"]:
		if not app.world.lot_navigation.point_clear(0,state[key]):return "A saved guest destination is unsupported or blocked."
	if not Building.footprint_supported(_building(),0,Rect2(Vector2(state.inside.x,state.inside.z)-Vector2(.4,.4),Vector2(.8,.8)),false):return "The saved gathering place is outside the home floor."
	var points:PackedVector3Array=state.route.points
	for index:int in range(1,points.size()):
		if not app.world.lot_navigation.segment_clear(0,points[index-1],points[index]):return "The saved guest route crosses an obstruction."
	if not app.traversal._free(id,actor.position,false):return "The saved guest overlaps another body or stair clearance."
	return ""

static func _point(value:Variant)->bool:
	if not value is Array or value.size()!=3:return false
	return Building.number(value[0],-9,9) and Building.number(value[1],.15999999,.16000001) and Building.number(value[2],-7,9)

static func saved_visit(data:Dictionary)->Variant:
	var members:Variant=data.get("members")
	if not members is Array:return null
	var selected:Variant=data.get("selected_index",0)
	if not Building.number(selected,0,members.size()-1,true):return null
	var entry:Variant=members[int(selected)]
	if not entry is Dictionary or not entry.get("state") is Dictionary:return null
	var character:Variant=entry.state.get("character")
	if not character is Dictionary or not character.get("world_state") is Dictionary:return null
	var residents:Variant=character.world_state.get("residents")
	if not residents is Dictionary or not residents.has("home_visit"):return null
	return {"value":residents.home_visit,"residents":residents,"context":character.world_state,"member_state":entry.state}

static func validate_saved(data:Dictionary)->String:
	var found:Variant=saved_visit(data)
	if found==null:return ""
	var value:Variant=found.value
	if not value is Dictionary or not Building.number(value.get("version"),1,1,true) or not Building.number(value.get("next_serial"),1,1000000000,true) or not value.get("visit") is Dictionary:return "Save contains an invalid home-visit record."
	var visit:Dictionary=value.visit
	if visit.is_empty():return ""
	if not Building.number(found.residents.get("version"),1,1,true):return "An active home visit requires the supported resident state version."
	if str(found.context.get("venue",""))!="home":return "An active home guest requires a physical home snapshot."
	if not Building.number(visit.get("serial"),1,float(value.next_serial)-1,true) or not LifeResidents.PEOPLE.has(str(visit.get("guest",""))):return "Save contains an unknown guest or visit identity."
	var phase:String=str(visit.get("phase",""))
	if phase not in ["arriving","waiting","entering","inside","leaving"]:return "Save contains an invalid guest phase."
	if not visit.get("blocked") is bool:return "Save contains invalid guest movement state."
	for key:String in ["welcome","inside","exit","position"]:
		if not _point(visit.get(key)):return "Save contains an invalid guest ground position."
	if not Building.number(visit.get("rotation"),-1000000,1000000):return "Save contains an invalid guest rotation."
	var clock:Dictionary=found.member_state
	if not Building.number(clock.get("day"),1,1000000,true) or not Building.number(clock.get("minutes"),0,1440):return "Save contains an invalid guest clock."
	var now:float=(float(clock.day)-1)*1440.0+float(clock.minutes)
	for key:String in ["created_at","arrived_at","admitted_at","phase_at"]:
		if not Building.number(visit.get(key),-1,now):return "Save contains an invalid guest phase clock."
	if float(visit.created_at)<0 or float(visit.phase_at)<float(visit.created_at):return "Save contains inconsistent visit clocks."
	if float(visit.arrived_at)>=0 and float(visit.arrived_at)<float(visit.created_at):return "Save contains an arrival before its invitation."
	if float(visit.admitted_at)>=0 and (float(visit.arrived_at)<0 or float(visit.admitted_at)<float(visit.arrived_at)):return "Save contains an admission before its arrival."
	if phase=="arriving" and float(visit.phase_at)!=float(visit.created_at):return "Save contains an inconsistent arrival deadline."
	if phase=="waiting" and float(visit.phase_at)!=float(visit.arrived_at):return "Save contains an inconsistent waiting deadline."
	if phase=="entering" and float(visit.phase_at)!=float(visit.admitted_at):return "Save contains an inconsistent entry deadline."
	if phase in ["inside","leaving"] and float(visit.phase_at)<maxf(float(visit.arrived_at),float(visit.admitted_at)):return "Save contains a phase transition before its prior arrival."
	if phase=="arriving" and (float(visit.arrived_at)!=-1 or float(visit.admitted_at)!=-1):return "An arriving guest cannot already be welcomed."
	if phase in ["waiting","entering","inside"] and float(visit.arrived_at)<float(visit.created_at):return "Save is missing the guest arrival time."
	if phase=="waiting" and float(visit.admitted_at)!=-1:return "A waiting guest cannot already be inside."
	if phase in ["entering","inside"] and float(visit.admitted_at)<float(visit.arrived_at):return "Save is missing the accepted welcome time."
	var route:Variant=visit.get("route")
	if not route is Dictionary or not route.get("points") is Array or route.points.size()>1024 or not Building.number(route.get("point"),0,route.points.size(),true):return "Save contains an invalid guest route cursor."
	for point:Variant in route.points:
		if not _point(point):return "Save contains an invalid guest route point."
	if route.points.is_empty():
		if phase!="leaving":return "Save is missing an active guest route."
	else:
		var target:Array=visit.welcome if phase in ["arriving","waiting"] else (visit.exit if phase=="leaving" else visit.inside)
		if route.points[-1]!=target:return "Save contains an inconsistent guest route destination."
		var position:=Vector3(visit.position[0],visit.position[1],visit.position[2]);var cursor:int=int(route.point)
		if cursor==0 and position.distance_to(Vector3(route.points[0][0],route.points[0][1],route.points[0][2]))>.00001:return "The guest is not at the saved route origin."
		if cursor==route.points.size() and position.distance_to(Vector3(target[0],target[1],target[2]))>.00001:return "The guest has not reached the saved destination."
		if cursor>0 and cursor<route.points.size():
			var a:=Vector3(route.points[cursor-1][0],route.points[cursor-1][1],route.points[cursor-1][2]);var b:=Vector3(route.points[cursor][0],route.points[cursor][1],route.points[cursor][2]);var segment:Vector3=b-a
			var fraction:float=clampf((position-a).dot(segment)/maxf(segment.length_squared(),.00000001),0,1)
			if position.distance_to(a+fraction*segment)>.00001:return "The guest position is not on the saved route segment."
		if phase in ["waiting","inside"] and cursor!=route.points.size():return "A stationary guest has an unfinished route."
	var locations:Variant=found.residents.get("locations")
	if not locations is Dictionary or not locations.get("home") is Dictionary:return "Save is missing the guest's home-lot presence."
	var resident:Variant=locations.home.get(str(visit.guest))
	if not resident is Dictionary or resident.get("position")!=visit.position or resident.get("rotation")!=visit.rotation or str(resident.get("phase",""))!="walking":return "The guest and resident transform records disagree."
	if not Building.number(resident.get("wait"),0,999999) or not Building.number(resident.get("direction"),-1,1,true) or float(resident.direction)==0 or not Building.number(resident.get("waypoint"),0,2,true):return "Save contains invalid guest resident scheduling state."
	if not visit.get("greeting") is Dictionary or not visit.get("departure") is Dictionary or not Building.number(visit.get("next_greeting"),1,1000000,true):return "Save contains an invalid guest conversation record."
	var members:Dictionary={}
	for entry:Variant in data.members:
		if entry is Dictionary and entry.get("state") is Dictionary:members[str(entry.get("id",""))]=entry.state
	if not visit.greeting.is_empty():
		var greeting:Dictionary=visit.greeting
		if phase!="waiting" or not members.has(str(greeting.get("member",""))) or not Building.number(greeting.get("token"),1,float(visit.next_greeting)-1,true) or not Building.number(greeting.get("active_at"),-1,now):return "Save contains an invalid welcome identity."
		var matches:Array=[]
		for action:Variant in members[str(greeting.member)].get("action_queue",[]):
			if action is Dictionary and action.get("home_visit_serial")==visit.serial and action.get("home_visit_token")==greeting.token:matches.append(action)
		if matches.size()!=1 or str(matches[0].get("id",""))!="friendly" or str(matches[0].get("target_id",""))!=str(visit.guest):return "The saved welcome does not match one actual friendly action."
		if float(matches[0].get("duration",-1))!=GREETING_MINUTES:return "The saved welcome has an invalid duration."
		var match:Dictionary=matches[0]
		if float(greeting.active_at)>=0 and (str(match.get("phase",""))!="active" or not bool(match.get("paid",false)) or _raw_started(match)!=float(greeting.active_at)):return "The saved active welcome does not match its actual conversation clock."
		if str(match.get("phase",""))=="active" and (_raw_started(match)<float(visit.arrived_at) or _raw_started(match)>float(visit.arrived_at)+WELCOME_MINUTES):return "The saved welcome started outside the waiting window."
		if str(match.get("phase",""))!="active" and float(greeting.active_at)!=-1:return "A queued welcome cannot already be active."
	if not visit.departure.is_empty():
		var departure:Dictionary=visit.departure
		if phase!="leaving" or not members.has(str(departure.get("member",""))) or not Building.number(departure.get("started_at"),0,now) or not Building.number(departure.get("duration"),1,45):return "Save contains an invalid departure conversation."
		var queue:Variant=members[str(departure.member)].get("action_queue",[])
		if not queue is Array or queue.is_empty():return "The saved departure is missing its current conversation."
		if not queue[0] is Dictionary:return "The saved departure conversation is not an action record."
		var current:Dictionary=queue[0]
		if str(current.get("id",""))!=str(departure.get("id","")) or str(current.get("id","")) not in LifeSim.SOCIAL_ACTIONS or str(current.get("target_id",""))!=str(visit.guest) or str(current.get("phase",""))!="active" or not bool(current.get("paid",false)) or _raw_started(current)!=float(departure.started_at) or current.get("duration")!=departure.duration:return "The saved departure conversation is inconsistent."
	var active_hosts:int=0
	for member_id:String in members:
		var queue:Variant=members[member_id].get("action_queue",[])
		if not queue is Array:return "The saved guest host queue is invalid."
		for index:int in queue.size():
			var action:Variant=queue[index]
			if not action is Dictionary:return "The saved guest host action is invalid."
			if action.has("home_visit_serial") or action.has("home_visit_token"):
				if visit.greeting.is_empty() or member_id!=str(visit.greeting.member) or action.get("home_visit_serial")!=visit.serial or action.get("home_visit_token")!=visit.greeting.token:return "The saved welcome token has no matching visit owner."
			if str(action.get("target_id",""))!=str(visit.guest) or str(action.get("id","")) not in LifeSim.SOCIAL_ACTIONS or str(action.get("phase",""))!="active":continue
			active_hosts+=1
			if index!=0 or phase not in ["waiting","inside","leaving"]:return "The saved guest conversation is active in an incompatible phase."
			if phase=="leaving" and (visit.departure.is_empty() or member_id!=str(visit.departure.member)):return "A departing guest has an unowned active conversation."
	if active_hosts>1:return "Two household members cannot own the same guest conversation."
	return ""

static func _raw_started(action:Dictionary)->float:
	if not Building.number(action.get("started_day"),1,1000000,true) or not Building.number(action.get("started_minutes"),0,1440):return -1
	return (float(action.started_day)-1)*1440.0+float(action.started_minutes)
