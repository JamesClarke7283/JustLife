extends RefCounted
class_name LifeHomeVisit
## One invited neighbor follows real ground routes; household actions keep ownership.
const ARRIVAL_MINUTES:float=180.0
const WELCOME_MINUTES:float=120.0
const STAY_MINUTES:float=360.0
## Asking a guest to stay over extends their visit by this many game minutes
## from the moment they accept, overriding the ordinary leave timer.
const STAY_OVER_EXTRA_MINUTES:float=720.0
const GREETING_MINUTES:float=25.0
## A party guest's stay can run no longer than the longest party.
const PARTY_MAX_MINUTES:float=300.0
## How far apart two guests' standing places and routes' ends must be.
const GUEST_GAP:float=.85
## An uninvited caller rings the doorbell and waits on the doorstep. They stay
## outside the whole time: ringing is the only way in, and letting them in is the
## household's decision. A visitor who was invited over is expected, so their
## arrival is announced by the ordinary invite notice instead of a second ring.
const RING_WAIT_MINUTES:float=90.0
## How long the doorstep decision stays open before the caller gives up and
## walks away on their own.
const RING_LINGER_MINUTES:float=15.0
const Building=preload("res://scripts/building_state.gd")
var _owner:WeakRef
var app:Node:
	get:
		var current:Variant=_owner.get_ref()
		return current.app if current!=null else null
var state:Dictionary={}
var next_serial:int=1
## An uninvited caller on the doorstep, or empty. Their own record so a ring
## never collides with an invited visit's saved state.
var bell:Dictionary={}
var next_bell_serial:int=1
var _bell_action:Dictionary={}
var _bell_notice_in:float=0.0
## resident id -> absolute game day they were last turned away, so a caller does
## not simply ring again the moment they are sent off.
var _bell_denied:Dictionary={}
var _welcome_action:Dictionary={}
var _departure_action:Dictionary={}
var _notice_in:float=0.0
## Real seconds before a party guest held at the door asks to come in again.
var _party_door_in:float=0.0
var meal:LifeGuestMeal
var activity:LifeGuestActivity

func _init(residents:RefCounted)->void:_owner=weakref(residents);meal=LifeGuestMeal.new(self);activity=LifeGuestActivity.new(self)
func active()->bool:return not state.is_empty()
func owns(id:String)->bool:return active() and str(state.guest)==id
func _now()->float:return (app.household.day-1)*1440.0+app.household.minutes
func _body(id:String)->LifeActor:return app.world.actors.get(id)
func _packed(point:Vector3)->Array:return [point.x,point.y,point.z]
func _vector(value:Array)->Vector3:return Vector3(value[0],value[1],value[2])
func reset()->void:
	_release_entrance()
	activity.reset()
	state.clear();next_serial=1;_welcome_action={};_departure_action={};_notice_in=0.0
	bell.clear();next_bell_serial=1;_bell_action={};_bell_notice_in=0.0

func social_allowed(id:String,action:Dictionary={})->bool:
	if not owns(id):return true
	if str(state.phase)!="leaving":return true
	return not _departure_action.is_empty() and is_same(action,_departure_action) and str(action.get("phase","")) in ["active","approach"] and bool(action.get("paid",false))

func prepare_social(id:String)->bool:
	if not owns(id):return true
	if str(state.phase)=="leaving":return false
	if str(state.phase)=="inside":activity.interrupt_for_social()
	return true

func conversation_start_allowed(id:String,action:Dictionary)->bool:
	if not owns(id):return true
	if action.has("home_visit_serial"):return welcome_start_allowed(action)
	if str(state.phase)=="leaving":return social_allowed(id,action)
	if str(state.phase)=="entering" or meal.active():return false
	if str(state.phase)=="inside" and activity.active():return activity.interrupt_for_social()
	return not app.world.construction.doors.passages.has(id)

func welcome_start_allowed(action:Dictionary)->bool:
	if not action.has("home_visit_serial"):return true
	if not active() or not is_same(action,_welcome_action):return false
	if not state.get("entrance",{}).is_empty():
		return str(state.entrance.stage)=="greeting"
	if str(state.phase)!="waiting":return false
	return _started_at(action)<=float(state.arrived_at)+WELCOME_MINUTES if bool(action.get("paid",false)) else _now()<=float(state.arrived_at)+WELCOME_MINUTES

func requirement(id:String)->String:
	if active():return "One neighbor is already visiting. Say goodbye and let them leave first."
	if _residents().party_active() or app.party_on():return "Your party is still on. Let it finish before inviting someone else."
	if ringing():return "Somebody is already at the door. Let them in or turn them away first."
	if app.current_venue!="home" or app.mode!="live":return "Invite a neighbor while you are at home in Live mode."
	if not LifeResidents.PEOPLE.has(id) or not app.residents.can_visit(id):return "Reach 20 friendship with this neighbor before inviting them over."
	if _building().is_empty():return "This home needs a supported ground-floor layout before inviting a guest."
	if not app.residents.trip.is_empty():return "Finish the current trip before inviting a neighbor."
	if not app.residents._speaker(id).is_empty():return "Finish the current conversation with this neighbor before inviting them over."
	return ""

## The rules for inviting a neighbor to a party. The one-neighbor rule does not
## apply, so several guests can be here at once, but every layout, trip and
## conversation check of an ordinary invitation still does, and a neighbor who is
## already a guest or is standing at the door cannot be asked twice.
func party_requirement(id:String)->String:
	var residents=_residents()
	for visit:LifeHomeVisit in residents.visits():
		if visit.owns(id) or visit.owns_bell(id):return "That neighbor is already visiting."
	if app.current_venue!="home" or app.mode!="live":return "Invite a neighbor while you are at home in Live mode."
	if not LifeResidents.PEOPLE.has(id) or not residents.can_visit(id):return "Reach 20 friendship with this neighbor before inviting them over."
	if _building().is_empty():return "This home needs a supported ground-floor layout before inviting a guest."
	if not residents.trip.is_empty():return "Finish the current trip before inviting a neighbor."
	if not residents._speaker(id).is_empty():return "Finish the current conversation with this neighbor before inviting them over."
	return ""

## The residents service that owns this visit.
func _residents()->Variant:return _owner.get_ref()

# ------------------------------------------------------------------ doorbell

## Somebody uninvited is at the door. The porch is outside the house at every
## point of the ring, so this can only ever resolve into an invitation.
func ringing()->bool:return not bell.is_empty()
func owns_bell(id:String)->bool:return ringing() and str(bell.guest)==id
func bell_answered()->bool:return ringing() and str(bell.get("decision",""))=="let_in"
func bell_refused()->bool:return ringing() and str(bell.get("decision",""))=="turned_away"
func _bell_now()->float:return (app.household.day-1)*1440.0+app.household.minutes

## A neighbor standing on the porch with no visit of their own and no
## conversation under way rings the doorbell. Whether they are a friend or a
## stranger, the household decides who comes in.
func consider_ring(force:bool=false)->bool:
	if app.current_venue!="home" or app.mode!="live" or app.household==null:return false
	if ringing() or active() or not app.residents.trip.is_empty():return false
	# Nobody rings while a party is on: the guests are already arriving.
	if app.residents.party_active() or app.party_on():return false
	if force:return _start_ring()
	if not app.residents.present("maya"):pass
	for id:String in LifeResidents.PEOPLE:
		if not app.residents.present(id):continue
		if int(_bell_denied.get(id,-1))>=app.household.day:continue
		if not app.residents._speaker(id).is_empty():continue
		# Only somebody who has actually come to the door rings it. A neighbor
		# merely walking the sidewalk lane passes within the doorstep radius of
		# the porch, and ringing for them froze that pass at the door for the
		# whole ring wait instead of letting them walk on.
		if str(app.residents.locations.get(app.residents.active_place,{}).get(id,{}).get("phase",""))!="visiting":continue
		if not _at_doorstep(id,app.world.actors[id].position):continue
		return _start_ring(id)
	return false

func _at_doorstep(id:String,at:Vector3)->bool:
	# The doorstep sits on the ground outside the threshold, past the porch step.
	if app.world.point_level(at)!=0:return false
	return Vector2(at.x,at.z).distance_to(Vector2(_door().x,_door().z))<=2.6

## Choose a real exterior doorway, preferring the street-facing south edge.
## The transform follows rebuilt/moved doors instead of a starter-house offset.
func front_door()->Dictionary:
	var building:Dictionary=_building()
	var best:Dictionary={};var score:float=-INF
	for key:String in app.world.construction.doors.doors:
		var door:Dictionary=app.world.construction.doors.doors[key]
		if int(door.level)!=0:continue
		var center:Vector3=door.root.global_position
		var normal:Vector3=door.root.global_basis.z.normalized()
		for sign_value:float in [-1.0,1.0]:
			var outward:Vector3=normal*sign_value
			var outside:Vector3=center+outward*.9
			var inside:Vector3=center-outward*.9
			var inner:bool=Building.footprint_supported(building,0,Rect2(Vector2(inside.x,inside.z)-Vector2(.2,.2),Vector2(.4,.4)),false)
			var outer:bool=Building.footprint_supported(building,0,Rect2(Vector2(outside.x,outside.z)-Vector2(.2,.2),Vector2(.4,.4)),false)
			if not inner or outer:continue
			var rank:float=outward.z*1000.0+center.z-absf(center.x)*.01
			if rank>score:score=rank;best={"id":key,"position":center,"outward":outward}
	return best

func _door()->Vector3:
	var door:Dictionary=front_door()
	return door.position+door.outward*.72 if not door.is_empty() else Vector3.INF

func _grid(point:Vector3)->Vector3:return Vector3(snappedf(point.x,.25),Building.GROUND_Y,snappedf(point.z,.25))

func _start_ring(id:String="")->bool:
	var guest:String=id
	if guest.is_empty():
		for candidate:String in LifeResidents.PEOPLE:
			if app.residents.present(candidate) and app.residents._speaker(candidate).is_empty():_at_doorstep(candidate,app.world.actors[candidate].position)
		for candidate:String in LifeResidents.PEOPLE:
			if app.residents.present(candidate):guest=candidate;break
	if guest.is_empty() or not LifeResidents.PEOPLE.has(guest):return false
	var actor:LifeActor=_body(guest)
	if not is_instance_valid(actor):return false
	var doorstep:Vector3=_doorstep_point(guest)
	if not doorstep.is_finite():return false
	bell={"serial":next_bell_serial,"guest":guest,"rang_at":_bell_now(),"phase_at":_bell_now(),"doorstep":doorstep,"decision":"","admitted_at":-1.0,"ring_announced":false,"blocked":false,"position":_packed(actor.position),"rotation":actor.rotation.y}
	next_bell_serial+=1
	app.show_notice("%s is at the door. Let them in, or ask them to leave." % str(LifeResidents.PEOPLE[guest].name).split(" ")[0])
	if app.has_method("_refresh_guest_status"):app._refresh_guest_status()
	return true

## A clear standing spot on the porch, clear of the front step and of bodies.
func _doorstep_point(id:String)->Vector3:
	var door:Dictionary=front_door()
	if door.is_empty():return Vector3.INF
	var side:=Vector3(door.outward.z,0,-door.outward.x)
	for depth:float in [1.25,1.5,1.75,2.0]:
		for offset:float in [0.0,.5,-.5,1.0,-1.0]:
			var point:Vector3=_grid(door.position+door.outward*depth+side*offset)
			if _clear(id,point):return point
	return Vector3.INF

## Let the caller in: they walk the ordinary welcome path and join the normal
## invited visit, so everything downstream (greeting, meal, goodbye) is unchanged.
func let_in()->bool:
	if not ringing():app.show_notice("Nobody is at the door.");return false
	if bell_answered():app.show_notice("They are already coming in.");return false
	var guest:String=str(bell.guest)
	if not app.residents.present(guest):app.show_notice("They have already left the door.");return false
	if app.household.selected()==null:return false
	# The doorstep record is spent the moment the household answers, so the
	# ordinary invite's own "somebody is already at the door" rule does not
	# refuse the very visit this answer is starting.
	_clear_bell()
	if not _begin_visit(guest," is coming in.",true):
		app.residents.home_visit_bell_departed(guest)
		return false
	app.show_notice("You let %s in." % str(LifeResidents.PEOPLE[guest].name).split(" ")[0])
	if app.has_method("_refresh_guest_status"):app._refresh_guest_status()
	return true

## Turn the caller away. They walk back to the street and life carries on.
func turn_away(message:String="")->bool:
	if not ringing():app.show_notice("Nobody is at the door.");return false
	var guest:String=str(bell.guest)
	bell.decision="turned_away"
	bell.phase_at=_bell_now()
	_bell_denied[guest]=app.household.day
	_clear_bell()
	app.residents.home_visit_bell_departed(guest)
	app.show_notice(message if not message.is_empty() else "%s heads off. Maybe another time." % str(LifeResidents.PEOPLE[guest].name).split(" ")[0])
	if app.has_method("_refresh_guest_status"):app._refresh_guest_status()
	return true

func _clear_bell()->void:
	bell={};_bell_action={};_bell_notice_in=0.0

## The doorstep tick: the caller waits outside, facing the door, and gives up
## after RING_LINGER_MINUTES. They never cross the threshold on their own.
func tick_bell(delta:float)->void:
	if not ringing():return
	var id:String=str(bell.guest)
	var actor:LifeActor=_body(id)
	if not is_instance_valid(actor) or not actor.visible:
		_clear_bell();return
	var speed:float=float(app.household.speed)
	if speed<=0:actor.animate(delta,0,false,"");return
	var staying:bool=str(bell.get("decision",""))=="turned_away"
	var deadline:float=float(bell.rang_at)+(RING_LINGER_MINUTES if staying else RING_WAIT_MINUTES)
	if _bell_now()>=deadline:
		turn_away("%s waited at the door and then headed home." % str(LifeResidents.PEOPLE[id].name).split(" ")[0]);return
	var moving:bool=false
	if staying:
		var exit:Vector3=_curb_point(id)
		if exit.is_finite():
			var route:PackedVector3Array=app.traversal._floor_route(actor.position,exit,id)
			if route.size()>1:
				var next:Vector3=actor.position.move_toward(route[1],LifePedestrianPace.distance("indoor",delta,speed))
				if app.traversal._step_clear(id,actor.position,next) and not app.world.construction.doors.before_step(actor,id,next,delta*float(speed)):
					var direction:Vector3=route[1]-actor.position
					actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.z),minf(delta*6,1))
					actor.position=next;moving=true
				if actor.position.distance_to(exit)<.4:
					_clear_bell();actor.animate(delta,LifePedestrianPace.gait_factor("indoor",speed) if moving else speed,moving,"");return
	else:
		var doorstep:Vector3=bell.doorstep if bell.doorstep is Vector3 else _doorstep_point(id)
		if actor.position.distance_to(doorstep)>.25:
			var route:PackedVector3Array=app.traversal._floor_route(actor.position,doorstep,id)
			if route.size()>1:
				var next:Vector3=actor.position.move_toward(route[1],LifePedestrianPace.distance("indoor",delta,speed))
				if app.traversal._step_clear(id,actor.position,next) and not app.world.construction.doors.before_step(actor,id,next,delta*float(speed)):
					actor.position=next;moving=true
		# Face the door while waiting to be answered.
		var toward:Vector3=_door()-actor.position
		if toward.length()>.01:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(toward.x,toward.z),minf(delta*4,1))
	actor.animate(delta,LifePedestrianPace.gait_factor("indoor",speed) if moving else speed,moving,"")
	bell.position=_packed(actor.position);bell.rotation=actor.rotation.y
	var resident:Dictionary=app.residents.locations.home.get(id,{})
	if not resident.is_empty():
		resident.position=_packed(actor.position);resident.rotation=actor.rotation.y


func invite(id:String)->bool:
	var reason:String=requirement(id)
	if not reason.is_empty():app.show_notice(reason);return false
	return _begin_visit(id," is coming over. Welcome them when they arrive.")

## The doorbell's own admission. A caller is a neighbour, not necessarily a
## friend, so this skips only the friendship rule — every layout, path and
## presence check the ordinary invite makes still applies, and the guest then
## joins exactly the same visit state machine.
func _begin_visit(id:String,notice:String,auto_welcome:bool=false,party:int=0,party_until:float=0.0)->bool:
	var actor:LifeActor=_body(id)
	if not is_instance_valid(actor):app.show_notice("This neighbor is unavailable right now.");return false
	var start:Vector3=actor.position if app.residents.present(id) else _curb_point(id)
	if not start.is_finite():app.show_notice("Clear a place on the sidewalk for your guest.");return false
	var door:Dictionary=front_door()
	if door.is_empty():app.show_notice("Add a clear exterior front door before inviting a guest.");return false
	var welcome:Vector3=_doorstep_point(id)
	var incoming:PackedVector3Array=_route(start,welcome,id) if welcome.is_finite() else PackedVector3Array()
	if incoming.is_empty():app.show_notice("Clear a path from the sidewalk to the front door.");return false
	var exit:Vector3=_curb_point(id)
	var inside:Vector3=_inside_point(id,door.position-door.outward*1.7,exit)
	if not inside.is_finite() or not exit.is_finite() or _route(inside,exit,id).is_empty():
		app.show_notice("Make room for a clear ground-floor gathering place and a route back to the sidewalk.");return false
	# All fallible layout/presence checks precede any queue, body or lifecycle change.
	state={"serial":next_serial,"guest":id,"phase":"arriving","created_at":_now(),"arrived_at":-1.0,"admitted_at":-1.0,"phase_at":_now(),"welcome":welcome,"inside":inside,"exit":exit,"route":{"points":incoming,"point":0},"greeting":{},"next_greeting":1,"departure":{},"blocked":false,"meal":{},"next_meal":1,"auto_welcome":auto_welcome,"front_door":str(door.id),"entrance":{}}
	# A party guest is admitted at the door without a host greeting and goes home when the party ends.
	if party>0:state.party=party;state.party_until=party_until
	next_serial+=1
	activity.restore({})
	actor.position=start;app.world.set_actor_away(id,false,false)
	var resident:Dictionary=app.residents.locations.home[id]
	resident.phase="walking";resident.position=_packed(start)
	app.residents.publish_targets(true)
	app.show_notice(str(LifeResidents.PEOPLE[id].name)+notice)
	return true

func _route(from:Vector3,to:Vector3,id:String,tolerant:bool=false)->PackedVector3Array:
	if app.world.point_level(from)!=0 or app.world.point_level(to)!=0:return []
	var strict:PackedVector3Array=app.traversal._floor_route(from,to,id)
	if not strict.is_empty() or not tolerant:return strict
	# Admission checks a geometric origin behind the doorway, which can overlap
	# a temporary household body; serving points can also be temporarily occupied.
	# Keep static geometry validation while allowing runtime `_walk` to wait for
	# those bodies. Actual destination choice still requires a clear standing spot.
	return app.traversal._floor_route(from,to,"")

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
	# Other guests' places are theirs: two guests never share a doorstep or room spot.
	for reserved:Vector3 in _residents().reserved_guest_points(self):
		if point.distance_to(reserved)<GUEST_GAP:return false
	return true

func _curb_point(id:String)->Vector3:
	for x:float in [-8.25,8.25,-7.25,7.25,-6.25,6.25]:
		for z:float in [8.25,8.75,7.75]:
			var point:=Vector3(x,.16,z)
			if _clear(id,point):return point
	return Vector3.INF

func _inside_point(id:String,from:Vector3,exit:Vector3=Vector3.INF)->Vector3:
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
		if exit.is_finite() and _route(point,exit,id).is_empty():continue
		if not _route(from,point,id,true).is_empty():return point
	return Vector3.INF

func reconcile()->void:
	if active() and not state.greeting.is_empty() and not _valid_greeting():
		_release_entrance()
		state.greeting={};_welcome_action={}
		if str(state.phase)=="waiting":state.entrance={}
		elif str(state.phase)=="entering":state.entrance={}


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
	var plan:Dictionary=_entrance_plan(member_id)
	if plan.is_empty():app.show_notice("Clear space just inside the front door for the welcome.");return false
	state.entrance=plan
	if not sim.queue_action("friendly",guest,_body(guest).position+Vector3(0,0,.8)):
		state.entrance={};return false
	_welcome_action=sim.action_queue[-1]
	var token:int=int(state.next_greeting);state.next_greeting=token+1
	_welcome_action.home_visit_serial=int(state.serial);_welcome_action.home_visit_token=token
	state.greeting={"member":member_id,"token":token,"active_at":-1.0}
	if is_same(sim.get_current_action(),_welcome_action):
		var prior:String=app.bound_member_id
		app._store_motion();app._bind_member(member_id);app.on_action_started(_welcome_action);app._store_motion();app._bind_member(prior)
	app.show_notice("Welcome queued. Your Lifelet will finish their earlier activities first.")
	return true

func _entrance_plan(member_id:String)->Dictionary:
	var door:Dictionary=front_door()
	if door.is_empty():return {}
	var guest:String=str(state.guest)
	var side:=Vector3(door.outward.z,0,-door.outward.x)
	var building:Dictionary=_building()
	var closing:Array[Vector3]=[]
	for depth:float in [.65,.5,.35]:
		for offset:float in [-.75,.75,-.5,.5,-.25,.25]:
			var point:Vector3=_grid(door.position-door.outward*depth+side*offset)
			if _clear(member_id,point):closing.append(point)
	for depth:float in [.85,1.25,1.75,2.25]:
		for offset:float in [-1.5,1.5,-1.0,1.0,-1.75,1.75]:
			var wait:Vector3=_grid(door.position-door.outward*depth+side*offset)
			if not _clear(member_id,wait):continue
			if not bool(app.world.route_to(_body(member_id).position,wait).ok):continue
			for close:Vector3 in closing:
				for inside_depth:float in [1.75,2.0,2.25]:
					for lateral:float in [0.0,-.5,.5,-1.0]:
						var inside:Vector3=_grid(door.position-door.outward*inside_depth+side*lateral)
						if inside.distance_to(close)<.9 or inside.distance_to(close)>1.75 or inside.distance_to(wait)<.9 or not _clear(guest,inside):continue
						if not Building.footprint_supported(building,0,Rect2(Vector2(inside.x,inside.z)-Vector2(.4,.4),Vector2(.8,.8)),false):continue
						# Reserve the future bodies while planning both legs. A free
						# endpoint alone can still leave the host blocking the guest.
						if _entrance_route(_body(guest).position,inside,guest,member_id,wait).is_empty():continue
						if _entrance_route(wait,close,member_id,guest,inside).is_empty():continue
						state.inside=inside
						return {"door":str(door.id),"host":member_id,"stage":"host_approach","wait":wait,"close":close,"closed":false}
	return {}

func _entrance_route(from:Vector3,to:Vector3,id:String,other:String,reserved:Vector3)->PackedVector3Array:
	var occupied:Array[Vector3]=[]
	for actor_id:String in app.world.actors:
		if actor_id in [id,other] or not app.world.actors[actor_id].visible:continue
		occupied.append(app.world.actors[actor_id].position)
	occupied.append(reserved)
	var result:Dictionary=app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(0,from),LifeLotNavigation.floor_location(0,to),occupied,LifeTraversal.ROUTE_CLEARANCE)
	return result.points if bool(result.ok) else PackedVector3Array()

func holds_social_approach(action:Dictionary)->bool:
	if not active() or is_same(action,_welcome_action) or str(action.get("phase",""))!="approach" or str(action.get("target_id",""))!=str(state.guest) or str(action.get("id","")) not in LifeSim.SOCIAL_ACTIONS:return false
	if not state.get("entrance",{}).is_empty() and str(state.phase) in ["waiting","entering"]:return true
	return str(state.phase)=="inside" and not activity.can_talk()

func owns_host_action(member_id:String,action:Dictionary)->bool:
	return active() and str(state.phase) in ["waiting","entering"] and not state.get("entrance",{}).is_empty() and str(state.entrance.host)==member_id and is_same(action,_welcome_action)

## The ordinary traversal owns all host walking, including stairs and save custody.
## Only the sequencing around the front door is visitor-specific.
func prepare_host_action(member_id:String,action:Dictionary)->bool:
	if holds_social_approach(action):
		action.target_position=_body(member_id).position
		app.pending_action=action;return true
	if not owns_host_action(member_id,action):return false
	var stage:String=str(state.entrance.stage)
	var target:Vector3=state.entrance.wait if stage in ["host_approach","guest_enter"] else state.entrance.close
	action.target_position=target;app.pending_action=action
	if stage in ["host_approach","host_close"]:
		if not app._set_route(target):app.show_notice("The host's path to the front door is blocked.")
	return true

func advance_host(member_id:String,delta:float)->bool:
	if app.household.speed<=0:return false
	if not owns_host_action(member_id,app.sim.get_current_action()):return false
	var entry:Dictionary=state.entrance
	var actor:LifeActor=_body(member_id)
	var stage:String=str(entry.stage)
	if stage in ["host_approach","host_close"]:
		var target:Vector3=entry.wait if stage=="host_approach" else entry.close
		if _welcome_action.target_position!=target:
			_welcome_action.target_position=target;app._set_route(target)
		if actor.position.distance_to(target)>.001:
			if not app.traversal.active(member_id) and app.path_index>=app.path.size():app._set_route(target)
			return app._advance_path(delta)
		app.traversal.cancel(member_id);app.path.clear();app.path_index=0
		if stage=="host_approach":_admit(str(state.guest),_now());return false
		entry.stage="closing"
	if str(entry.stage)=="guest_enter":
		app.world.construction.doors.hold_open(str(entry.door),member_id)
		return false
	if str(entry.stage)=="closing":
		if app.world.construction.doors.close_by(actor,member_id,str(entry.door),delta*float(app.household.speed)):
			entry.closed=true;entry.stage="greeting"
			_welcome_action.target_position=actor.position
			app.household.begin_action(member_id)
			state.greeting.active_at=_started_at(_welcome_action)
		return false
	return false

func _release_entrance()->void:
	if state.get("entrance",{}).is_empty() or app==null or not is_instance_valid(app.world):return
	var entry:Dictionary=state.entrance
	app.world.construction.doors.release_hold(str(entry.door),str(entry.host))
	app.world.construction.doors.cancel(str(entry.host))

func _complete_entry(at:float)->void:
	if not active():return
	var guest:String=str(state.guest)
	_release_entrance()
	state.phase="inside";state.phase_at=at;state.entrance={};state.greeting={};_welcome_action={}
	state.route={"points":PackedVector3Array([_body(guest).position]),"point":1}
	state.inside=_body(guest).position
	app.residents.publish_targets(true)
	app._reconcile_social_routes()
	if app.relationship_flow!=null:app.relationship_flow.guest_entered(guest)

func detach_moved_in(guest_id:String)->void:
	if not owns(guest_id):return
	_release_entrance()
	activity.cancel("")
	if meal.active():
		state.phase="leaving"
		meal._release()
	activity.reset()
	app.world.construction.doors.cancel(guest_id)
	state={};_welcome_action={};_departure_action={}

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
	if not active() or str(state.phase) not in ["waiting","entering"] or state.greeting.is_empty():return
	if member_id!=str(state.greeting.member) or not is_same(action,_welcome_action):return
	var event_sim:LifeSim=app.household.member_sim(member_id)
	var event_time:float=(event_sim.day-1)*1440.0+event_sim.minutes
	var started:float=_started_at(action)
	if started<0 or started>maxf(float(state.arrived_at)+WELCOME_MINUTES,float(state.admitted_at)+ARRIVAL_MINUTES) or not bool(action.get("paid",false)) or float(action.get("duration",-1))!=GREETING_MINUTES or float(action.get("elapsed",-1))<GREETING_MINUTES:return
	if not bool(action.get("social_accepted",false)) or str(action.get("id",""))!="friendly":return
	var host:LifeActor=_body(member_id);var guest:LifeActor=_body(str(state.guest))
	if not is_instance_valid(host) or not host.visible or not guest.visible or host.position.distance_to(guest.position)>1.8:return
	if str(state.phase)=="entering":_complete_entry(event_time)
	else:_admit(str(state.guest),event_time)

## A welcomed guest walks inside. Shared by the ordinary "Welcome in" greeting
## and by a caller the household already let in at the doorbell. A `patient` guest (a
## party guest, who has nobody to open the door) does not go home when the way in is
## blocked: it reports false and the guest waits on the doorstep to try again. Returns
## whether the guest is on their way in.
func _admit(guest:String,event_time:float,patient:bool=false)->bool:
	if not active() or guest!=str(state.guest):return false
	var actor:LifeActor=_body(guest)
	if not is_instance_valid(actor):return false
	var inside:Vector3=state.inside
	if not _clear(guest,inside):inside=_inside_point(guest,actor.position)
	if not inside.is_finite():
		if patient:state.blocked=true;return false
		goodbye("There is no clear gathering space. Your guest is heading home.",event_time);return false
	var route:PackedVector3Array=_route(actor.position,inside,guest)
	if route.is_empty():
		if patient:state.blocked=true;return false
		goodbye("The route inside is blocked. Your guest is heading home.",event_time);return false
	state.inside=inside;state.phase="entering";state.phase_at=event_time;state.admitted_at=event_time;state.route={"points":route,"point":0}
	if not state.get("entrance",{}).is_empty():state.entrance.stage="guest_enter"
	else:state.greeting={};_welcome_action={}
	app.show_notice(str(LifeResidents.PEOPLE[guest].name)+" is coming inside.")
	return true

## Absolute game-minute when an inside guest should leave. Stay Over lengthens
## this without rewriting phase_at, so meal and save clocks stay consistent.
func stay_deadline() -> float:
	if not active(): return 0.0
	# A party guest stays until the party ends.
	if state.has("party_until"): return float(state.party_until)
	var base: float = float(state.get("phase_at", 0.0)) + STAY_MINUTES
	if bool(state.get("stay_over", false)):
		return base + STAY_OVER_EXTRA_MINUTES
	return base


## Ask the current guest to stay overnight. Overrides the ordinary leave timer.
## The closest friend the guest has in the household has to be a proper friend, or
## a partner, before they will stay the night.
const STAY_OVER_FRIENDSHIP:float=40.0

func stay_over_refusal() -> String:
	if not active() or app == null or not is_instance_valid(app.household): return ""
	var guest: String = str(state.guest)
	var best: float = -100.0
	for member: Dictionary in app.household.members:
		var relation: Dictionary = member.sim.relationships.get(guest, {})
		if str(relation.get("bond", "none")) in ["partners", "committed"]: return ""
		best = maxf(best, float(relation.get("friendship", 0.0)))
	if best >= STAY_OVER_FRIENDSHIP: return ""
	return "Thanks, but I'd better head home tonight. Let's get to know each other a little better first."

func ask_to_stay_over() -> bool:
	if active() and state.has("party"):
		if app != null: app.show_notice("They came for the party and will head home when it ends.")
		return false
	if not active() or str(state.phase) != "inside":
		if app != null: app.show_notice("Welcome your guest inside before asking them to stay.")
		return false
	if bool(state.get("stay_over", false)):
		if app != null: app.show_notice("They are already staying over.")
		return false
	var guest: String = str(state.guest)
	var name: String = str(LifeResidents.PEOPLE.get(guest, {}).get("name", "Your guest")).split(" ")[0]
	var refusal: String = stay_over_refusal()
	if not refusal.is_empty():
		# Asking is always allowed; an acquaintance simply says no thank you.
		if app != null: app.show_notice("%s says: %s" % [name, refusal])
		return false
	state["stay_over"] = true
	activity.seek_bed()
	if app != null: app.show_notice("%s is delighted to stay over." % name)
	if app != null and app.has_method("_refresh_guest_status"): app._refresh_guest_status()
	return true


func goodbye(message:String="Your guest is heading home after the current conversation.",event_time:float=-1.0)->void:
	if not active() or str(state.phase)=="leaving":return
	_release_entrance()
	activity.cancel("")
	_departure_action={};state.departure={}
	var speaker:Dictionary=app.residents._speaker(str(state.guest))
	if not speaker.is_empty():
		var current:Dictionary=speaker.sim.get_current_action()
		if str(current.get("phase",""))=="active" and not (is_same(current,_welcome_action) and _started_at(current)>float(state.arrived_at)+WELCOME_MINUTES):
			_departure_action=current;state.departure={"member":str(speaker.id),"id":str(current.id),"started_at":_started_at(current),"duration":float(current.duration)}
	# Welcome identity ends here; the same paid action now owns departure only.
	if not _departure_action.is_empty():
		_departure_action.erase("home_visit_serial");_departure_action.erase("home_visit_token")
	state.entrance={}
	state.phase="leaving";state.phase_at=event_time if event_time>=0 else _now();state.route={"points":PackedVector3Array(),"point":0};state.greeting={};_welcome_action={}
	meal.cancel("Your guest is heading home.")
	activity.prepare_departure()
	if app.world.point_level(_body(str(state.guest)).position)==0 and not app.traversal.active(str(state.guest)):
		activity.data.returning=false;activity.data.managed_route=false
		if not meal.active():state.route={"points":PackedVector3Array(),"point":0}
	app._cancel_guest_conversations(str(state.guest),_departure_action)
	app.residents.publish_targets(true);app.show_notice(message)

func _departure_held()->bool:
	if state.departure.is_empty() or _departure_action.is_empty():return false
	var sim:LifeSim=app.household.member_sim(str(state.departure.member))
	return is_instance_valid(sim) and is_same(sim.get_current_action(),_departure_action) and str(_departure_action.get("phase","")) in ["active","approach"] and bool(_departure_action.get("paid",false)) and _now()<=float(state.departure.started_at)+float(state.departure.duration)+.001

func tick(delta:float)->void:
	if not active():return
	var id:String=str(state.guest);var actor:LifeActor=_body(id)
	var speed:float=float(app.household.speed);var now:float=_now()
	activity.tick_needs()
	if speed<=0:actor.animate(delta,0,false,"");return
	reconcile()
	var phase:String=str(state.phase)
	if phase=="arriving" and now>=float(state.created_at)+ARRIVAL_MINUTES:goodbye("The welcome path took too long. Your guest is heading home.")
	if phase=="entering" and now>=float(state.phase_at)+ARRIVAL_MINUTES:goodbye("The way inside is still blocked. Your guest is heading home.")
	if phase=="waiting":
		reconcile()
		var bounded:bool=false
		if _valid_greeting() and str(_welcome_action.get("phase",""))=="active":
			var started:float=_started_at(_welcome_action)
			bounded=started>=0 and started<=float(state.arrived_at)+WELCOME_MINUTES and now<=started+GREETING_MINUTES+.001
			if bounded:state.greeting.active_at=started
		if now>=float(state.arrived_at)+WELCOME_MINUTES and not bounded:goodbye("Your guest waited for a welcome and is heading home.")
	if str(state.phase)=="inside" and now>=stay_deadline():
		var until:float=stay_deadline()
		meal.consume_until(until)
		goodbye("It is time for your guest to head home.",until)
	phase=str(state.phase)
	if phase=="inside" and not meal.active() and activity.tick(delta):
		_sync_guest();return
	if meal.active():
		meal.tick(delta)
		var location:Dictionary=app.residents.locations.home[id]
		location.position=_packed(actor.position);location.rotation=actor.rotation.y
		return
	if phase=="leaving" and bool(activity.data.get("returning",false)):
		if activity.departure_tick(delta):
			_sync_guest();return
		activity.data.managed_route=false
		state.route={"points":PackedVector3Array(),"point":0}
	var moving:bool=false;var talk:String=""
	var speaking:bool=phase=="arriving" and not app.residents._speaker(id).is_empty() and not app.world.construction.doors.passages.has(id)
	var awaiting_host:bool=phase=="entering" and not state.get("entrance",{}).is_empty() and str(state.entrance.stage)!="guest_enter"
	if phase in ["arriving","entering","leaving"] and not speaking and not awaiting_host and not (phase=="leaving" and _departure_held()):
		var destination:Vector3=state.welcome if phase=="arriving" else (state.inside if phase=="entering" else state.exit)
		if state.route.points.is_empty():state.route={"points":_route(actor.position,destination,id),"point":0}
		if not state.route.points.is_empty():
			var result:Dictionary=app.traversal._walk(id,state.route,delta*speed)
			moving=bool(result.moved);state.blocked=bool(result.blocked)
			if int(state.route.point)>=state.route.points.size():
				if phase=="arriving":
					state.phase="waiting";state.arrived_at=now;state.phase_at=now
					# A party guest walks straight in: no host greets each one at the door.
					if state.has("party"):
						# Somebody standing in the hall can hold the guest at the door: they ask again every second.
						_party_door_in=maxf(0.0,_party_door_in-delta)
						if _party_door_in<=0.0:
							_party_door_in=1.0
							if _admit(id,now,true):return
							_notice_in-=1.0
							if _notice_in<=0:_notice_in=5.0;app.show_notice("Your guest's path is blocked. Move a nearby Lifelet in Live mode so they can pass.")
						state.phase="arriving";state.arrived_at=-1.0;state.phase_at=float(state.created_at)
						actor.animate(delta,speed,false,"");_sync_guest();return
					if bool(state.get("auto_welcome",false)):
						# The household already answered the doorbell: this caller
						# was let in, so they come straight inside instead of being
						# asked a second time at the threshold.
						welcome(app.household.selected_id())
						return
					if app.household.speed>1:
						app.household.set_speed(1);app.show_notice(str(LifeResidents.PEOPLE[id].name)+" is here. Slowing down so you can welcome them.")
					else:app.show_notice("Your guest is here. Choose Welcome them in to invite them inside.")
				elif phase=="entering":
						if state.get("entrance",{}).is_empty():_complete_entry(now)
						else:
							app.world.construction.doors.cancel(id)
							state.entrance.stage="host_close"
				else:_finish();return
		else:state.blocked=true
		if phase=="entering" and not state.get("entrance",{}).is_empty():app.world.construction.doors.hold_open(str(state.entrance.door),str(state.entrance.host))
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
	_sync_guest()

func _sync_guest()->void:
	if not active():return
	var actor:LifeActor=_body(str(state.guest))
	var resident:Dictionary=app.residents.locations.home.get(str(state.guest),{})
	if is_instance_valid(actor) and not resident.is_empty():resident.position=_packed(actor.position);resident.rotation=actor.rotation.y

func _finish()->void:
	if meal.active() or not app.household.meals.carried_by(str(state.guest)).is_empty():return
	_release_entrance();activity.reset()
	var id:String=str(state.guest);var actor:LifeActor=_body(id)
	var resident:Dictionary=app.residents.locations.home[id]
	resident.phase="home";resident.position=_packed(actor.position);resident.rotation=actor.rotation.y;resident.wait=float(LifeResidentCatalogue.PEOPLE.get(id,{}).get("home_wait",60.0))
	app.world.set_actor_away(id,true,true);state={};_welcome_action={};_departure_action={}
	app.residents.publish_targets(true);app.show_notice(str(LifeResidents.PEOPLE[id].name)+" has headed home.")

func snapshot()->Dictionary:
	reconcile()
	var saved:Dictionary=state.duplicate(true)
	if not saved.is_empty():
		if str(saved.phase) in ["waiting","entering"] and not _valid_greeting():saved.greeting={}
		saved.activity=activity.snapshot()
		if not saved.get("entrance",{}).is_empty():
			var door:Dictionary=app.world.construction.doors.doors.get(str(saved.entrance.door),{})
			if not door.is_empty():
				saved.entrance.gate={"progress":float(door.progress),"direction":float(door.direction),"clock":float(app.world.construction.doors.passages.get(str(saved.entrance.host),{}).get("clock",0.0)) if str(saved.entrance.stage)=="closing" else 0.0}
			for key:String in ["wait","close"]:saved.entrance[key]=_packed(saved.entrance[key])
		for key:String in ["welcome","inside","exit"]:saved[key]=_packed(saved[key])
		saved.route.points=Array(saved.route.points).map(func(point:Vector3)->Array:return _packed(point))
		var actor:LifeActor=_body(str(saved.guest))
		saved.position=_packed(actor.position);saved.rotation=actor.rotation.y
		if not saved.get("meal",{}).is_empty():saved.meal.target=_packed(saved.meal.target)
	var saved_bell:Dictionary=bell.duplicate(true)
	if not saved_bell.is_empty():
		# The doorstep is a Vector3 in memory and must be packed like every other
		# point the save carries: `_point` validates an Array, so an unpacked
		# doorstep made the game refuse its own save ("Save contains an invalid
		# doorstep position") for as long as a caller stood at the door.
		if saved_bell.get("doorstep") is Vector3:saved_bell.doorstep=_packed(saved_bell.doorstep)
		var bell_actor:LifeActor=_body(str(saved_bell.guest))
		if is_instance_valid(bell_actor):
			saved_bell.position=_packed(bell_actor.position);saved_bell.rotation=bell_actor.rotation.y
		elif saved_bell.get("position") is Vector3:saved_bell.position=_packed(saved_bell.position)
	return {"version":2,"next_serial":next_serial,"visit":saved,"doorbell":saved_bell,"next_bell_serial":next_bell_serial}

func restore(value:Dictionary)->void:
	state=value.get("visit",{}).duplicate(true);next_serial=int(value.get("next_serial",1));_welcome_action={};_departure_action={}
	bell=value.get("doorbell",{}).duplicate(true);next_bell_serial=int(value.get("next_bell_serial",1));_bell_action={};_bell_notice_in=0.0
	if not bell.is_empty():
		bell.doorstep=_vector(bell.get("doorstep",[0.0,.16,6.15]))
		bell.rang_at=float(bell.get("rang_at",0.0));bell.phase_at=float(bell.get("phase_at",0.0))
		bell.serial=int(bell.get("serial",1));bell.rotation=float(bell.get("rotation",0.0))
		bell.position=_vector(bell.get("position",[0.0,.16,6.15]))
		if str(bell.get("decision","")) not in ["","let_in","turned_away"]:bell.decision=""
	if state.is_empty():return
	state.meal=state.get("meal",{});state.next_meal=int(state.get("next_meal",1))
	state.entrance=state.get("entrance",{})
	if not state.entrance.is_empty():
		for key:String in ["wait","close"]:state.entrance[key]=_vector(state.entrance[key])
	activity.restore(state.get("activity",{}))
	if not state.meal.is_empty():state.meal.target=_vector(state.meal.target)
	state.serial=int(state.serial);state.next_greeting=int(state.next_greeting)
	if state.has("party"):state.party=int(state.party);state.party_until=float(state.party_until)
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

## Restore the visible latch state only after the candidate world has its actors.
func present()->void:
	if not active() or state.get("entrance",{}).is_empty():return
	var entry:Dictionary=state.entrance
	if not entry.has("gate"):return
	var gate:Dictionary=entry.gate
	app.world.construction.doors.restore_hold(str(entry.door),str(entry.host),float(gate.progress),float(gate.direction),float(gate.clock) if str(entry.stage)=="closing" else -1.0)
	# Legacy queue loading restarts every ordinary action in approach. This
	# identified greeting already owns its reached body and paid start clock.
	# Reconstruct that validated active state without spending or advancing it.
	if str(entry.stage)=="greeting" and _valid_greeting() and bool(_welcome_action.get("paid",false)) and float(state.greeting.active_at)>=0:
		_welcome_action.phase="active"
		var prior:String=app.bound_member_id
		app._store_motion();app._bind_member(str(entry.host));app._clear_motion()
		app.pending_action=_welcome_action
		app._store_motion();app._bind_member(prior)

func physical_error()->String:
	if not active():return ""
	if app.current_venue!="home":return "A home guest was saved in a different venue."
	var id:String=str(state.guest);var actor:LifeActor=_body(id)
	if not is_instance_valid(actor) or not actor.visible:return "The saved guest is not physically present."
	# The saved transform round-trips through JSON doubles while the actor
	# carries float32; compare with engine float32 tolerance.
	if actor.position.distance_to(_vector(state.position))>.01 or absf(actor.rotation.y-float(state.rotation))>.01:return "The saved guest transform is inconsistent."
	var managed:bool=bool(activity.data.get("managed_route",false))
	if not managed and not app.world.lot_navigation.point_clear(0,actor.position):return "The saved guest is on unsupported or blocked ground."
	for key:String in ["welcome","inside","exit"]:
		if not app.world.lot_navigation.point_clear(0,state[key]):return "A saved guest destination is unsupported or blocked."
	if not Building.footprint_supported(_building(),0,Rect2(Vector2(state.inside.x,state.inside.z)-Vector2(.4,.4),Vector2(.8,.8)),false):return "The saved gathering place is outside the home floor."
	var points:PackedVector3Array=state.route.points
	if not managed:
		for index:int in range(1,points.size()):
			if not app.world.lot_navigation.segment_clear(0,points[index-1],points[index]):return "The saved guest route crosses an obstruction."
		if not app.traversal._free(id,actor.position,false):return "The saved guest overlaps another body or stair clearance."
	if not state.get("entrance",{}).is_empty():
		var entry:Dictionary=state.entrance
		if not app.world.construction.doors.doors.has(str(entry.door)):return "The saved entrance doorway no longer exists."
		var door:Dictionary=app.world.construction.doors.doors[str(entry.door)]
		var close:Vector3=door.root.to_local(entry.close)
		if absf(close.y)>.01 or absf(close.z)>1.0 or absf(close.x)>float(door.width)*.5+.4:return "The saved host cannot reach this door handle."
		var host:LifeActor=_body(str(entry.host))
		if str(entry.stage) in ["closing","greeting"] and host.position.distance_to(entry.close)>.01:return "The saved host has not reached the entrance handle."
		if str(entry.stage)=="greeting" and (host.position.distance_to(actor.position)>1.8 or not app.world.sight_line_clear(host.position,actor.position)):return "The saved hallway greeting has no nearby guest."
		for key:String in ["wait","close"]:
			if not app.world.lot_navigation.point_clear(0,entry[key]):return "The saved host entrance is obstructed."
	if meal.active():return meal.physical_error()
	return activity.physical_error()

static func _point(value:Variant)->bool:
	if not value is Array or value.size()!=3:return false
	return Building.number(value[0],-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN) and Building.number(value[1],.15999999,.16000001) and Building.number(value[2],-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN)

## The saved resident record of the selected Lifelet, which carries every guest, or null.
static func saved_context(data:Dictionary)->Variant:
	var members:Variant=data.get("members")
	if not members is Array:return null
	var selected:Variant=data.get("selected_index",0)
	if not Building.number(selected,0,members.size()-1,true):return null
	var entry:Variant=members[int(selected)]
	if not entry is Dictionary or not entry.get("state") is Dictionary:return null
	var character:Variant=entry.state.get("character")
	if not character is Dictionary or not character.get("world_state") is Dictionary:return null
	var residents:Variant=character.world_state.get("residents")
	if not residents is Dictionary:return null
	return {"residents":residents,"context":character.world_state,"member_state":entry.state}

## The ordinary visit's saved record (and its context), or null when none was saved.
static func saved_visit(data:Dictionary)->Variant:
	var found:Variant=saved_context(data)
	if found==null or not found.residents.has("home_visit"):return null
	found["value"]=found.residents.home_visit
	return found

## Each saved party visit's record with the same context, in saved order.
static func saved_party_visits(data:Dictionary)->Array:
	var result:Array=[]
	var found:Variant=saved_context(data)
	if found==null or not found.residents.get("party_visits") is Array:return result
	for value:Variant in found.residents.party_visits:
		var entry:Dictionary=found.duplicate()
		entry["value"]=value
		result.append(entry)
	return result

## The saved visit states of the party guests, for the food validators.
static func saved_party_guests(data:Dictionary)->Array:
	var guests:Array=[]
	for entry:Dictionary in saved_party_visits(data):
		if entry.value is Dictionary and entry.value.get("visit") is Dictionary and not entry.value.visit.is_empty():guests.append(entry.value.visit)
	return guests

static func validate_saved(data:Dictionary)->String:
	var found:Variant=saved_visit(data)
	var ordinary:Dictionary={}
	if found!=null and found.value is Dictionary and found.value.get("visit") is Dictionary:ordinary=found.value.visit
	var base:Variant=saved_context(data)
	if base!=null and base.residents.has("party_visits") and (not base.residents.party_visits is Array or base.residents.party_visits.size()>LifeResidents.PEOPLE.size()):return "Save contains an invalid party-visit list."
	var party:Array=saved_party_visits(data)
	# Every saved guest's state, so each one's journey is checked with the others on the stairs.
	var everyone:Array=[]
	if not ordinary.is_empty():everyone.append(ordinary)
	for entry:Dictionary in party:
		if entry.value is Dictionary and entry.value.get("visit") is Dictionary and not entry.value.visit.is_empty():everyone.append(entry.value.visit)
	if found!=null:
		var error:String=validate_value(found.value,found,data,false,everyone.filter(func(other:Dictionary)->bool:return not is_same(other,ordinary)))
		if not error.is_empty():return error
	var seen:Dictionary={}
	if not ordinary.is_empty():seen[str(ordinary.get("guest",""))]=true
	for entry:Dictionary in party:
		var party_state:Dictionary=entry.value.get("visit",{}) if entry.value is Dictionary and entry.value.get("visit") is Dictionary else {}
		var error:String=validate_value(entry.value,entry,data,true,everyone.filter(func(other:Dictionary)->bool:return not is_same(other,party_state)))
		if not error.is_empty():return error
		if seen.has(str(party_state.guest)):return "A neighbor cannot be two guests at once."
		seen[str(party_state.guest)]=true
	if found!=null and found.value is Dictionary and found.value.get("doorbell") is Dictionary and seen.has(str(found.value.doorbell.get("guest",""))) and str(found.value.doorbell.get("guest",""))!=str(ordinary.get("guest","")):return "A party guest is also at the door."
	return ""

## One saved visit record. `is_party` marks a party guest's record; `others` are the
## other saved guests' visit states (ordinary and party) for the shared checks.
static func validate_value(value:Variant,found:Dictionary,data:Dictionary,is_party:bool=false,others:Array=[])->String:
	if not value is Dictionary or not Building.number(value.get("version"),1,2,true) or not Building.number(value.get("next_serial"),1,1000000000,true) or not value.get("visit") is Dictionary:return "Save contains an invalid party-visit record." if is_party else "Save contains an invalid home-visit record."
	var doorbell_error:String=_validate_bell(value.get("doorbell",{}),value.get("next_bell_serial",1),found)
	if not doorbell_error.is_empty():return doorbell_error
	if is_party and not value.get("doorbell",{}).is_empty():return "A party guest cannot be ringing the doorbell."
	var visit:Dictionary=value.visit
	if visit.is_empty():return "Save contains an empty party visit." if is_party else ""
	if int(value.version)==1 and (visit.has("meal") or visit.has("next_meal")):return "A version-one visit cannot contain a guest meal."
	if int(value.version)==2 and (not visit.get("meal") is Dictionary or not Building.number(visit.get("next_meal"),1,1000000,true)):return "Save contains an invalid guest meal envelope."
	if not Building.number(found.residents.get("version"),1,1,true):return "An active home visit requires the supported resident state version."
	if str(found.context.get("venue",""))!="home":return "An active home guest requires a physical home snapshot."
	if not Building.number(visit.get("serial"),1,float(value.next_serial)-1,true) or not LifeResidents.PEOPLE.has(str(visit.get("guest",""))):return "Save contains an unknown guest or visit identity."
	var phase:String=str(visit.get("phase",""))
	if phase not in ["arriving","waiting","entering","inside","leaving"]:return "Save contains an invalid guest phase."
	if is_party and phase=="waiting":return "A party guest never waits at the door for a greeting."
	if not visit.get("blocked") is bool:return "Save contains invalid guest movement state."
	var managed:bool=LifeGuestActivity.allows_elevated_position(visit)
	for key:String in ["welcome","inside","exit"]:
		if not _point(visit.get(key)):return "Save contains an invalid guest ground position."
	if not (LifeJourneyState.vector_valid(visit.get("position")) if managed else _point(visit.get("position"))):return "Save contains an invalid guest position."
	if not Building.number(visit.get("rotation"),-1000000,1000000):return "Save contains an invalid guest rotation."
	var clock:Dictionary=found.member_state
	if not Building.number(clock.get("day"),1,1000000,true) or not Building.number(clock.get("minutes"),0,1440):return "Save contains an invalid guest clock."
	var now:float=(float(clock.day)-1)*1440.0+float(clock.minutes)
	for key:String in ["created_at","arrived_at","admitted_at","phase_at"]:
		if not Building.number(visit.get(key),-1,now):return "Save contains an invalid guest phase clock."
	var party_error:String=_validate_party_keys(visit,data,is_party,now)
	if not party_error.is_empty():return party_error
	var meal_error:String=LifeGuestMeal.validate(visit,now)
	if not meal_error.is_empty():return meal_error
	var activity_error:String=LifeGuestActivity.validate(visit,now)
	if not activity_error.is_empty():return activity_error
	if managed:
		if phase not in ["inside","leaving"] or not visit.get("meal",{}).is_empty():return "The visitor journey conflicts with its current phase."
		var travel_error:String=LifeGuestActivity.validate_route(visit,data,others)
		if not travel_error.is_empty():return travel_error
	var entrance_error:String=_validate_entrance(visit,data)
	if not entrance_error.is_empty():return entrance_error
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
		if not (LifeJourneyState.vector_valid(point) if managed else _point(point)):return "Save contains an invalid guest route point."
	if managed:
		if route.points.size()!=1 or route.points[0]!=visit.position or int(route.point)!=1:return "The visitor journey marker does not match its current body."
	elif route.points.is_empty():
		if phase!="leaving":return "Save is missing an active guest route."
	else:
		var target:Array=visit.welcome if phase in ["arriving","waiting"] else (visit.exit if phase=="leaving" else visit.inside)
		if not visit.get("meal",{}).is_empty():target=visit.meal.target
		elif not visit.get("activity",{}).get("current",{}).is_empty():target=visit.activity.current.target_position
		elif phase=="inside" and visit.has("activity"):target=route.points[-1]
		if route.points[-1]!=target:return "Save contains an inconsistent guest route destination."
		var position:=Vector3(visit.position[0],visit.position[1],visit.position[2]);var cursor:int=int(route.point)
		if cursor==0 and position.distance_to(Vector3(route.points[0][0],route.points[0][1],route.points[0][2]))>.00001:return "The guest is not at the saved route origin."
		if cursor==route.points.size() and position.distance_to(Vector3(target[0],target[1],target[2]))>.00001:return "The guest has not reached the saved destination."
		if cursor>0 and cursor<route.points.size():
			var a:=Vector3(route.points[cursor-1][0],route.points[cursor-1][1],route.points[cursor-1][2]);var b:=Vector3(route.points[cursor][0],route.points[cursor][1],route.points[cursor][2]);var segment:Vector3=b-a
			var fraction:float=clampf((position-a).dot(segment)/maxf(segment.length_squared(),.00000001),0,1)
			if position.distance_to(a+fraction*segment)>.00001:return "The guest position is not on the saved route segment."
		if phase in ["waiting","inside"] and visit.get("meal",{}).is_empty() and visit.get("activity",{}).get("current",{}).is_empty() and cursor!=route.points.size():return "A stationary guest has an unfinished route."
		if not visit.get("meal",{}).is_empty() and str(visit.meal.phase) in ["eating","release"] and cursor!=route.points.size():return "The guest meal requires an arrived body."
	var locations:Variant=found.residents.get("locations")
	if not locations is Dictionary or not locations.get("home") is Dictionary:return "Save is missing the guest's home-lot presence."
	var resident:Variant=locations.home.get(str(visit.guest))
	if not resident is Dictionary or resident.get("position")!=visit.position or resident.get("rotation")!=visit.rotation or str(resident.get("phase",""))!="walking":return "The guest and resident transform records disagree."
	if not Building.number(resident.get("wait"),0,999999) or not Building.number(resident.get("direction"),-1,1,true) or float(resident.direction)==0 or not Building.number(resident.get("waypoint"),0,2,true):return "Save contains invalid guest resident scheduling state."
	if not visit.get("greeting") is Dictionary or not visit.get("departure") is Dictionary or not Building.number(visit.get("next_greeting"),1,1000000,true):return "Save contains an invalid guest conversation record."
	if is_party and (not visit.greeting.is_empty() or not visit.get("entrance",{}).is_empty()):return "A party guest has no host greeting."
	var members:Dictionary={}
	for entry:Variant in data.members:
		if entry is Dictionary and entry.get("state") is Dictionary:members[str(entry.get("id",""))]=entry.state
	if not visit.greeting.is_empty():
		var greeting:Dictionary=visit.greeting
		if phase not in ["waiting","entering"] or not members.has(str(greeting.get("member",""))) or not Building.number(greeting.get("token"),1,float(visit.next_greeting)-1,true) or not Building.number(greeting.get("active_at"),-1,now):return "Save contains an invalid welcome identity."
		var matches:Array=[]
		for action:Variant in members[str(greeting.member)].get("action_queue",[]):
			if action is Dictionary and action.get("home_visit_serial")==visit.serial and action.get("home_visit_token")==greeting.token:matches.append(action)
		if matches.size()!=1 or str(matches[0].get("id",""))!="friendly" or str(matches[0].get("target_id",""))!=str(visit.guest):return "The saved welcome does not match one actual friendly action."
		if float(matches[0].get("duration",-1))!=GREETING_MINUTES:return "The saved welcome has an invalid duration."
		var match:Dictionary=matches[0]
		if float(greeting.active_at)>=0 and (str(match.get("phase",""))!="active" or not bool(match.get("paid",false)) or _raw_started(match)!=float(greeting.active_at)):return "The saved active welcome does not match its actual conversation clock."
		if str(match.get("phase",""))=="active" and (_raw_started(match)<float(visit.arrived_at) or _raw_started(match)>maxf(float(visit.arrived_at)+WELCOME_MINUTES,float(visit.admitted_at)+ARRIVAL_MINUTES)):return "The saved welcome started outside the waiting window."
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
				# Welcome tokens belong to the ordinary visit alone; its own record checks them.
				if is_party:
					if str(action.get("target_id",""))==str(visit.guest):return "The saved welcome token has no matching visit owner."
				elif visit.greeting.is_empty() or member_id!=str(visit.greeting.member) or action.get("home_visit_serial")!=visit.serial or action.get("home_visit_token")!=visit.greeting.token:return "The saved welcome token has no matching visit owner."
			if str(action.get("target_id",""))!=str(visit.guest) or str(action.get("id","")) not in LifeSim.SOCIAL_ACTIONS or str(action.get("phase",""))!="active":continue
			active_hosts+=1
			if not visit.get("meal",{}).is_empty() or not visit.get("activity",{}).get("current",{}).is_empty():return "The guest has conflicting activity and conversation ownership."
			if index!=0 or phase not in ["arriving","waiting","entering","inside","leaving"]:return "The saved guest conversation is active in an incompatible phase."
			if phase=="entering" and (visit.greeting.is_empty() or member_id!=str(visit.greeting.member) or str(visit.get("entrance",{}).get("stage",""))!="greeting"):return "The entrance conversation is not owned by its host."
			if phase=="leaving" and (visit.departure.is_empty() or member_id!=str(visit.departure.member)):return "A departing guest has an unowned active conversation."
	if active_hosts>1:return "Two household members cannot own the same guest conversation."
	return ""

## A visit's optional party keys: a whole number for the party and the absolute
## minute the guest goes home, no earlier than the invitation and no more than the
## longest party's length after the save's own time (a party has already begun, so
## it cannot end later than that). Every party guest's record must carry them, and
## when the save also holds the household's party record the guest must be on its
## list and stay no later than it ends.
static func _validate_party_keys(visit:Dictionary,data:Dictionary,is_party:bool,now:float)->String:
	if not (is_party or visit.has("party") or visit.has("party_until")):return ""
	if not Building.number(visit.get("party"),1,1000000000,true) or not Building.number(visit.get("party_until"),float(visit.created_at),now+PARTY_MAX_MINUTES):return "Save contains an invalid party guest stay."
	var record:Variant=data.get("party")
	if record is Dictionary and not record.is_empty():
		if record.has("serial") and not is_equal_approx(float(record.get("serial",0)),float(visit.party)):return "A party guest belongs to a different party."
		if record.get("guests") is Array:
			var listed:bool=false
			for entry:Variant in record.guests:
				if entry is Dictionary and str(entry.get("id",""))==str(visit.guest):listed=true
			if not listed:return "A party guest is not on the party's guest list."
		if Building.number(record.get("ends_at"),0,1e12) and float(visit.party_until)>float(record.ends_at)+.001:return "A party guest stays past the party's end."
	return ""

static func _validate_entrance(visit:Dictionary,data:Dictionary)->String:
	var entrance:Variant=visit.get("entrance",{})
	if not entrance is Dictionary:return "Save contains an invalid visitor entrance."
	if entrance.is_empty():return ""
	if str(visit.phase) not in ["waiting","entering"] or str(entrance.get("stage","")) not in ["host_approach","guest_enter","host_close","closing","greeting"]:return "Save contains an invalid visitor entrance stage."
	if not entrance.get("door") is String or str(entrance.door).is_empty() or not entrance.get("closed") is bool:return "Save contains invalid visitor door state."
	if (str(visit.phase)=="waiting")!=(str(entrance.stage)=="host_approach"):return "The visitor entrance stage disagrees with its visit phase."
	if bool(entrance.closed)!=(str(entrance.stage)=="greeting"):return "The visitor entrance has an inconsistent closed-door state."
	if not _point(entrance.get("wait")) or not _point(entrance.get("close")):return "Save contains invalid host entrance positions."
	var host:String=str(entrance.get("host",""));var found:bool=false
	for member:Dictionary in data.members:
		if str(member.id)==host:found=true
	if not found or visit.get("greeting",{}).get("member","")!=host:return "The entrance has no matching household host."
	if entrance.has("gate"):
		var gate:Variant=entrance.gate
		if not gate is Dictionary or not Building.number(gate.get("progress"),0,1) or not Building.number(gate.get("direction"),-1,1) or absf(float(gate.direction))!=1 or not Building.number(gate.get("clock"),0,10):return "Save contains invalid entrance latch progress."
	if str(entrance.stage)=="greeting" and not bool(entrance.closed):return "The entrance greeting began before the host closed the door."
	return ""

## A doorstep record is optional so older saves load unchanged. When present it
## must name a known neighbor on a real ground point, with its clock inside the
## save's own elapsed time — the same discipline the invited-visit record keeps.
static func _validate_bell(bell:Variant,next_serial:Variant,found:Dictionary)->String:
	if not bell is Dictionary:return "Save contains an invalid doorbell record."
	if not Building.number(next_serial,1,1000000000,true):return "Save contains an invalid doorbell counter."
	if bell.is_empty():return ""
	if not Building.number(bell.get("serial"),1,float(next_serial)-1,true):return "Save contains an invalid doorbell identity."
	if not LifeResidents.PEOPLE.has(str(bell.get("guest",""))):return "Save contains an unknown caller at the door."
	if str(bell.get("decision","")) not in ["","let_in","turned_away"]:return "Save contains an invalid doorbell answer."
	if not bell.get("ring_announced",false) is bool or not bell.get("blocked",false) is bool:return "Save contains invalid doorbell state."
	var clock:Dictionary=found.member_state
	if not Building.number(clock.get("day"),1,1000000,true) or not Building.number(clock.get("minutes"),0,1440):return "Save contains an invalid doorbell clock."
	var now:float=(float(clock.day)-1)*1440.0+float(clock.minutes)
	for key:String in ["rang_at","phase_at"]:
		if not Building.number(bell.get(key),0,now):return "Save contains an invalid doorbell phase clock."
	if not Building.number(bell.get("admitted_at"),-1,now):return "Save contains an invalid doorbell admission time."
	if float(bell.phase_at)<float(bell.rang_at):return "Save contains a doorbell phase before its ring."
	if not _point(bell.get("doorstep")) or not _point(bell.get("position")):return "Save contains an invalid doorstep position."
	if not Building.number(bell.get("rotation"),-1000000,1000000):return "Save contains an invalid doorbell rotation."
	# The caller must still be outside the house, on supported ground.
	var at:=Vector3(bell.position[0],bell.position[1],bell.position[2])
	if float(at.y)<.15999999 or float(at.y)>.16000001:return "The saved caller is not standing on the ground."
	if not found.residents.get("locations",{}).get("home",{}).has(str(bell.guest)):return "Save is missing the caller's home-lot presence."
	return ""

static func _raw_started(action:Dictionary)->float:
	if not Building.number(action.get("started_day"),1,1000000,true) or not Building.number(action.get("started_minutes"),0,1440):return -1
	return (float(action.started_day)-1)*1440.0+float(action.started_minutes)
