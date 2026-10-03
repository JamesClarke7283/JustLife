extends Node
class_name LifeTVGroup
## A television is the shared resource; seats and water places remain ordinary
## physical activities. Session facts travel with those activities in saves.
const SEATS = ["sofa", "loveseat", "armchair", "bench", "chair"]
const WATER = ["pool", "hot_tub"]
## The menu ids of the garden-television choices at the water. The pool is watched
## from a seat on its coping, the hot tub from the water itself.
const EDGE_TV = "watch_pool_edge_tv"
const EDGE_LABEL = "Sit by the pool and watch TV"
const WATER_TV = "watch_water_tv"
const SHOWS = ["Garden Detectives", "Kitchen Stories", "Neighborhood Cup"]
const TOPICS = [
	["That gardener has definitely hidden the key!", "I think the robin found our next clue.", "The greenhouse mystery gets better every week."],
	["That cake looks amazing. Shall we try it?", "A little less pepper next time!", "I'd give that recipe ten out of ten."],
	["What a pass! Did you see that?", "Come on, there's still time to score!", "That was the best goal all season."]
]
var app: Node
var screens: Dictionary = {}
var serial: int = 0

static func owns(action: Dictionary) -> bool:
	return action.get("tv") is Dictionary

## Whether this viewing is from a seat on a pool's coping rather than from the water.
static func edge(action: Dictionary) -> bool:
	return action.get("edge_side") != null

static func save_error(action: Dictionary) -> String:
	if not action.has("tv"): return ""
	if not owns(action) or str(action.get("id", "")) not in ["watch", "watch_together", "enjoy_outdoors"]: return "Invalid television activity."
	var state: Dictionary = action.tv
	for key: String in ["id", "session", "show"]:
		if not state.get(key) is String or str(state[key]).is_empty() or str(state[key]).length()>100: return "Invalid television session."
	if str(state.show) not in SHOWS: return "Unknown television programme."
	for key: String in ["clock", "chat"]:
		if not (state.get(key) is float or state.get(key) is int) or not is_finite(float(state[key])) or float(state[key])<0 or float(state[key])>10000000: return "Invalid television clock."
	if not state.get("ready") is bool or not state.get("shared") is bool: return "Invalid television attendance."
	if bool(state.ready) and not bool(action.get("paid",false)): return "Television attendance has not started."
	if str(action.id)=="enjoy_outdoors" and not LifeBuildingState.number(action.get("swim_lane"),0,LifeOutdoorActs.MAX_JOIN-1,true): return "Invalid television water place."
	if edge(action) and (str(action.id)!="watch_together" or not LifeBuildingState.number(action.get("swim_lane"),0,LifeOutdoorActs.MAX_JOIN-1,true) or not LifeBuildingState.number(action.get("edge_side"),0,1,true)): return "Invalid television poolside place."
	return ""

func _guest():
	if not is_instance_valid(app.residents) or not app.residents.home_visit.active(): return null
	return app.residents.home_visit.activity

func records(queued: bool = false) -> Array:
	var result: Array = []
	for member: Dictionary in app.household.members:
		var actions: Array = member.sim.action_queue if queued else [member.sim.get_current_action()]
		for action: Dictionary in actions:
			if owns(action): result.append({"id":str(member.id), "action":action, "body":app.world.actors.get(str(member.id)), "sim":member.sim})
	var guest = _guest()
	if guest!=null and owns(guest.current_action()): result.append({"id":guest.person(), "action":guest.current_action(), "body":guest.body(), "sim":null})
	return result

func _member_id(who: LifeSim) -> String:
	for member: Dictionary in app.household.members:
		if member.sim==who: return str(member.id)
	return ""

func session_for(tv_id: String) -> Dictionary:
	for record: Dictionary in records(true):
		if str(record.action.tv.id)==tv_id: return record.action.tv.duplicate(true)
	serial+=1
	return {"id":tv_id,"session":"%s:%d:%d" % [tv_id,Time.get_ticks_msec(),serial],"show":SHOWS[posmod(app.household.day+serial,SHOWS.size())],"clock":0.0,"chat":0.0,"ready":false,"shared":false}

func _free(plan: Dictionary, person: String, reserved: Array = []) -> bool:
	var wanted: Array[String] = app._activity_resources(plan)
	for member: Dictionary in app.household.members:
		if str(member.id)==person: continue
		for other: Dictionary in member.sim.action_queue:
			if other!=member.sim.get_current_action() and not owns(other): continue
			for resource: String in app._activity_resources(other):
				if wanted.has(resource): return false
	var guest = _guest()
	if guest!=null and guest.person()!=person and guest.blocks(plan): return false
	for other: Dictionary in reserved:
		for resource: String in app._activity_resources(other):
			if wanted.has(resource): return false
	return true

func blocks(action: Dictionary, person: String) -> bool:
	# A walking viewer already owns their chosen cushion. Do not let an idle
	# sitter overtake that reservation while the viewer passes through a door.
	var wanted: Array[String] = app._activity_resources(action)
	for record: Dictionary in records(true):
		if str(record.id)==person: continue
		for resource: String in app._activity_resources(record.action):
			if wanted.has(resource): return true
	return false

func _visible(tv: Dictionary, furnishing: Dictionary) -> bool:
	return not tv.is_empty() and not furnishing.is_empty() and app.world.item_level(tv)==app.world.item_level(furnishing) and tv.node.position.distance_to(furnishing.node.position)<10.0 and app.world.sight_line_clear(tv.node.position,furnishing.node.position)

func _plan(person: String, tv: Dictionary, session: Dictionary, preferred: String = "", reserved: Array = [], poolside: bool = false) -> Dictionary:
	var body: LifeActor = app.world.actors.get(person)
	if not is_instance_valid(body): return {}
	var who: LifeSim = app.household.member_sim(person)
	var current: Dictionary = who.get_current_action() if who!=null else {}
	var wet: Dictionary = app._find_item(str(current.get("target_id","")))
	if str(current.get("id",""))=="enjoy_outdoors" and str(wet.get("kind","")) in WATER and str(tv.kind)=="outdoor_tv" and _visible(tv,wet):
		var plan: Dictionary = current.duplicate(true)
		plan.tv=session.duplicate(true)
		plan.swim_lane=int(current.get("swim_lane",0))
		plan.tv.ready=str(current.phase)=="active"
		return plan
	var preferred_item: Dictionary = app._find_item(preferred)
	if str(preferred_item.get("kind","")) in WATER and str(tv.kind)=="outdoor_tv":
		if poolside and str(preferred_item.kind)=="pool": return _edge_plan(person,preferred_item,tv,session,reserved)
		return _water_plan(person,preferred_item,session,reserved)
	var seats: Array = []
	for item: Dictionary in app.world.items:
		if str(item.kind) in SEATS and _visible(tv,item): seats.append(item)
	seats.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		var a_score: float = a.node.position.distance_to(tv.node.position)-(100.0 if str(a.id)==preferred else 0.0)-(20.0 if app.world.seat_capacity(a)>1 else 0.0)
		var b_score: float = b.node.position.distance_to(tv.node.position)-(100.0 if str(b.id)==preferred else 0.0)-(20.0 if app.world.seat_capacity(b)>1 else 0.0)
		return a_score<b_score)
	for seat: Dictionary in seats:
		for slot: String in app.world.seat_slots(seat):
			var plan: Dictionary = app.sim._actions.watch_together.duplicate(true)
			plan.merge({"target_id":str(seat.id),"seat_slot":slot,"target_kind":str(seat.kind),"target_position":app.world.slot_approach(seat,slot),"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"tv":session.duplicate(true)},true)
			plan.tv.ready=false
			if not _free(plan,person,reserved): continue
			if app.world.path_to(body.position,plan.target_position).is_empty(): continue
			return plan
	return {}

func _water_plan(person: String, item: Dictionary, session: Dictionary, reserved: Array = []) -> Dictionary:
	var body: LifeActor = app.world.actors.get(person)
	if not is_instance_valid(body): return {}
	var who: LifeSim = app.household.member_sim(person)
	if who!=null and not bool(who.get_action_availability("enjoy_outdoors",str(item.id)).available): return {}
	for lane: int in LifeOutdoorActs.MAX_JOIN:
		var plan: Dictionary = app.sim._outdoor_definition(app.sim._actions.enjoy_outdoors,str(item.kind),1).duplicate(true)
		# Separate clear rim approaches keep walkers out of each other's place.
		var offset: float = (float(lane)-1.5)*.8
		var wish: Vector3 = item.node.to_global(Vector3(offset,0,float(item.size.y)*.5+.65))
		var point: Vector3 = app.world.nearest_clear_point(wish,app.world.item_level(item),2)
		if app.world.construction.building_state.is_empty():
			var cell: Vector2i = app.world.nearest_free(wish)
			point=Vector3(cell.x*.25,.16,cell.y*.25)
		plan.merge({"target_id":str(item.id),"target_kind":str(item.kind),"target_position":point,"swim_lane":lane,"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"tv":session.duplicate(true)},true)
		plan.tv.ready=false
		if point.is_finite() and _free(plan,person,reserved) and not app.world.path_to(body.position,point).is_empty(): return plan
	return {}

## A seat on the pool's coping, facing the garden television across the water. The
## sitter stays dry and in their own clothes: it is the same shared viewing a sofa
## gives, with the pool as the place and the coping as the seat.
func _edge_plan(person: String, item: Dictionary, tv: Dictionary, session: Dictionary, reserved: Array = []) -> Dictionary:
	var body: LifeActor = app.world.actors.get(person)
	if not is_instance_valid(body): return {}
	var who: LifeSim = app.household.member_sim(person)
	if who!=null and not LifeOutdoorActs.act_error("pool",str(who.character.age_stage),who.is_away()).is_empty(): return {}
	for place: Dictionary in app.world.pool_edge_seats(item,tv.node.position):
		var seat: Dictionary = app.world.pool_edge_seat(item,int(place.side),int(place.lane),tv.node.position)
		if seat.is_empty(): continue
		var plan: Dictionary = app.sim._actions.watch_together.duplicate(true)
		plan.merge({"label":EDGE_LABEL,"description":"Sit on the edge of the pool with your feet over the water and watch the garden television.","target_id":str(item.id),"target_kind":"pool","target_position":seat.approach,"swim_lane":int(seat.lane),"edge_side":int(seat.side),"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"tv":session.duplicate(true)},true)
		plan.tv.ready=false
		if _free(plan,person,reserved) and not app.world.path_to(body.position,seat.approach).is_empty(): return plan
	return {}

func _enqueue(who: LifeSim, plan: Dictionary) -> bool:
	if who==null or who.is_away() or who.action_queue.size()>=LifeSim.MAX_QUEUE: return false
	var current: Dictionary = who.get_current_action()
	if str(plan.get("id",""))=="enjoy_outdoors" and str(current.get("target_id",""))==str(plan.target_id):
		current.tv=plan.tv
		current.swim_lane=int(plan.get("swim_lane",0))
		return true
	who.action_queue.append(plan)
	if who.action_queue.size()==1: who._start_front()
	who._emit_changed()
	return true

func request(who: LifeSim, tv_id: String, together: bool = false) -> bool:
	if who==null or who.is_away() or who.action_queue.size()>=LifeSim.MAX_QUEUE: return false
	var tv: Dictionary = app._find_item(tv_id)
	if str(tv.get("kind","")) not in ["tv","outdoor_tv"]: return false
	if not bool(who.get_action_availability("watch",tv_id).available): return false
	var person: String = _member_id(who)
	var state: Dictionary = session_for(tv_id)
	state.shared=together
	var first: Dictionary = _plan(person,tv,state)
	if first.is_empty(): app.show_notice("Place a reachable seat with a clear view of the television.");return false
	var invited: Array = []
	if together:
		for member: Dictionary in app.household.members:
			if str(member.id)==person or member.sim.is_away() or str(member.sim.character.age_stage) in ["baby","toddler"]: continue
			var action: Dictionary = member.sim.get_current_action()
			if not action.is_empty() and str(app._find_item(str(action.get("target_id",""))).get("kind","")) not in WATER: continue
			var plan: Dictionary = _plan(str(member.id),tv,state,str(first.target_id),[first],edge(first))
			if not plan.is_empty(): invited.append({"sim":member.sim,"plan":plan});break
		if invited.is_empty():
			var guest = _guest()
			if guest!=null:
				var plan: Dictionary = _plan(guest.person(),tv,state,str(first.target_id),[first],edge(first))
				if not plan.is_empty() and guest.request_plan(plan,true): invited.append({"sim":null,"plan":plan})
		if invited.is_empty() and not records().any(func(record: Dictionary)->bool:return str(record.action.tv.id)==tv_id and str(record.id)!=person):
			app.show_notice("A free housemate or welcomed visitor and a second seat are needed to watch together.");return false
	if not together and str(first.id)!="enjoy_outdoors": first.id="watch";first.merge(who._actions.watch,true)
	if not _enqueue(who,first): return false
	for invitation: Dictionary in invited:
		if invitation.sim!=null: _enqueue(invitation.sim,invitation.plan)
	return true

func host_record(id: String) -> Dictionary:
	for record: Dictionary in records():
		if str(record.id)==id or str(record.action.tv.id)==id: return record
	return {}

func join(who: LifeSim, id: String) -> bool:
	var host: Dictionary = host_record(id)
	if host.is_empty(): return false
	var state: Dictionary = host.action.tv.duplicate(true)
	state.shared=true
	var plan: Dictionary = _plan(_member_id(who),app._find_item(str(state.id)),state,str(host.action.target_id),[],edge(host.action))
	if plan.is_empty(): app.show_notice("There is no free, reachable place beside these viewers.");return false
	if not _enqueue(who,plan): return false
	host.action.tv.shared=true
	return true

func guest_target(host_id: String) -> Dictionary:
	var guest = _guest()
	var host: Dictionary = host_record(host_id)
	if guest==null or host.is_empty(): return {}
	var state: Dictionary = host.action.tv.duplicate(true)
	state.shared=true
	return _plan(guest.person(),app._find_item(str(state.id)),state,str(host.action.target_id),[],edge(host.action))

func nearby_tv(item: Dictionary) -> Dictionary:
	for tv: Dictionary in app.world.items:
		if str(tv.kind)=="outdoor_tv" and _visible(tv,item): return tv
	return {}

func menu(item: Dictionary, actions: Array) -> void:
	var host: Dictionary = host_record(str(item.id))
	if not host.is_empty() and str(host.id)!=app.bound_member_id:
		actions.append({"id":"join_tv","label":"Join watching "+str(host.action.tv.show),"duration":60,"cost":0,"available":true,"description":"Sit beside them, watch the same programme and talk about the show."})
	if str(item.kind) in WATER:
		var viewer: Dictionary = water_viewer(str(item.id))
		if not viewer.is_empty() and str(viewer.id)!=app.bound_member_id:
			actions.append({"id":"join_tv","label":"Join watching "+str(viewer.action.tv.show),"duration":60,"cost":0,"available":true,"description":"Settle in beside them, watch the same programme and talk about the show."})
		actions.append(_water_choice(item))

## The garden-television choice a pool or hot tub offers beside its swim or soak: a
## seat on the pool's coping, or a relaxed place in the tub. It is listed even with
## no television in view, unavailable and saying what is missing.
func _water_choice(item: Dictionary) -> Dictionary:
	var poolside: bool = str(item.kind)=="pool"
	var reason: String = ""
	var tv: Dictionary = nearby_tv(item)
	if tv.is_empty(): reason="Place a garden TV in clear view of the %s first." % ("pool" if poolside else "hot tub")
	elif not bool(app.sim.get_action_availability("watch",str(tv.id)).available): reason=str(app.sim.get_action_availability("watch",str(tv.id)).reason)
	elif poolside: reason=LifeOutdoorActs.act_error("pool",str(app.sim.character.age_stage),app.sim.is_away())
	else: reason=str(app.sim.get_action_availability("enjoy_outdoors",str(item.id)).reason)
	return {"id":EDGE_TV if poolside else WATER_TV,
		"label":"Sit by the edge and watch the garden TV" if poolside else "Relax and watch the garden TV",
		"duration":60,"cost":0,"available":reason.is_empty(),"unavailable_reason":reason,
		"description":"Sit on the edge of the pool, dry, with your feet over the water, and watch the garden television. A free housemate sits beside you." if poolside else "Soak in the warm water and watch the garden television. A free housemate soaks beside you."}

## Someone watching the garden television from this pool or hot tub, or {}.
func water_viewer(furnishing_id: String) -> Dictionary:
	for record: Dictionary in records():
		if str(record.action.get("target_id",""))==furnishing_id and str(record.action.get("id","")) in ["watch_together","enjoy_outdoors"]: return record
	return {}

func dispatch(item: Dictionary, id: String) -> bool:
	if id=="join_tv":
		var viewer: Dictionary = water_viewer(str(item.id)) if str(item.kind) in WATER else {}
		join(app.sim,str(viewer.id) if not viewer.is_empty() else str(item.id));app.refresh_hud();return true
	if id in ["watch","watch_together"] and str(item.kind) in ["tv","outdoor_tv"]:
		request(app.sim,str(item.id),id=="watch_together");app.refresh_hud();return true
	if id==WATER_TV or id==EDGE_TV:
		var poolside: bool = id==EDGE_TV and str(item.kind)=="pool"
		var tv: Dictionary = nearby_tv(item)
		if tv.is_empty(): app.show_notice("Place a garden TV in clear view of the %s first." % ("pool" if str(item.kind)=="pool" else "hot tub"));return true
		var watching: Dictionary = app.sim.get_action_availability("watch",str(tv.id))
		if not bool(watching.available): app.show_notice(str(watching.reason));return true
		var state: Dictionary = session_for(str(tv.id))
		state.shared=true
		var current: Dictionary = app.sim.get_current_action()
		if not poolside and str(current.get("id",""))=="enjoy_outdoors" and str(current.get("target_id",""))==str(item.id):
			current.tv=state;current.tv.ready=str(current.phase)=="active";current.swim_lane=int(current.get("swim_lane",0))
		else:
			var first: Dictionary = _edge_plan(app.bound_member_id,item,tv,state) if poolside else _water_plan(app.bound_member_id,item,state)
			if first.is_empty():
				app.show_notice("There is no free, reachable place by the water to watch from.");return true
			if not _enqueue(app.sim,first): return true
		for member: Dictionary in app.household.members:
			if str(member.id)==app.bound_member_id or not member.sim.action_queue.is_empty(): continue
			var plan: Dictionary = _edge_plan(str(member.id),item,tv,state) if poolside else _water_plan(str(member.id),item,state)
			if not plan.is_empty(): _enqueue(member.sim,plan);break
		app.refresh_hud();return true
	return false

func resolve(action: Dictionary) -> bool:
	if owns(action): return true
	if str(action.get("id","")) not in ["watch","watch_together"]: return false
	var tv: Dictionary = app._find_item(str(action.get("target_id","")))
	if str(tv.get("kind","")) not in ["tv","outdoor_tv"]: return false
	var plan: Dictionary = _plan(app.bound_member_id,tv,session_for(str(tv.id)))
	if plan.is_empty(): return false
	var id: String = str(action.id)
	action.merge(plan,true);action.id=id;action.phase="approach"
	return true

func before_begin(who: LifeSim, action: Dictionary) -> bool:
	if not owns(action): return true
	if not valid_target(action): who.cancel_action();return false
	action.tv.ready=true
	# Social gains are enabled only by tick when another viewer is physically
	# present. Walking toward the same sofa does not already count as company.
	action.changes=action.changes.duplicate(true)
	action.changes.social=0.0
	return true

func valid_target(action: Dictionary) -> bool:
	var tv: Dictionary = app._find_item(str(action.tv.id))
	var seat: Dictionary = app._find_item(str(action.get("target_id","")))
	if str(tv.get("kind","")) not in ["tv","outdoor_tv"] or not _visible(tv,seat): return false
	if edge(action):
		return str(tv.kind)=="outdoor_tv" and str(seat.kind)=="pool" and LifeBuildingState.number(action.get("swim_lane"),0,LifeOutdoorActs.MAX_JOIN-1,true) and LifeBuildingState.number(action.get("edge_side"),0,1,true)
	if str(action.get("id",""))=="enjoy_outdoors":
		return str(tv.kind)=="outdoor_tv" and str(seat.kind) in WATER and LifeBuildingState.number(action.get("swim_lane"),0,LifeOutdoorActs.MAX_JOIN-1,true)
	return str(seat.kind) in SEATS and app.world.seat_slots(seat).has(str(action.get("seat_slot","")))

func effects(action: Dictionary) -> void:
	var company: int = 0
	for record: Dictionary in records():
		if str(record.action.tv.id)==str(action.tv.id) and str(record.action.tv.session)==str(action.tv.session) and str(record.action.phase)=="active" and valid_target(record.action): company+=1
	action.changes=action.changes.duplicate(true)
	action.changes.social=26.0 if company>1 else 0.0

func _attending(record: Dictionary) -> bool:
	if str(record.action.phase)=="active": return true
	# Legacy loads resume a paid activity through approach at its exact saved
	# endpoint. Keep the paused body and programme visible until that resumes.
	return record.sim!=null and is_instance_valid(record.body) and bool(record.action.tv.ready) and bool(record.action.get("paid",false)) and bool(app.motion_states.get(str(record.id),{}).get("resume_active",false)) and record.body.position.distance_to(record.action.target_position)<.02

## The place on a pool's coping this viewing was given, worked out from where the
## pool and the screen stand now, or {}. Its approach (where the walker stops) is
## left out when only the seat is wanted, as the per-frame anchor does.
func edge_spot(action: Dictionary, with_approach: bool = true) -> Dictionary:
	if not edge(action) or not owns(action): return {}
	var pool: Dictionary = app._find_item(str(action.get("target_id","")))
	var tv: Dictionary = app._find_item(str(action.tv.id))
	if pool.is_empty() or tv.is_empty(): return {}
	return app.world.pool_edge_seat(pool,int(action.edge_side),int(action.swim_lane),tv.node.position,with_approach)

func anchor(action: Dictionary, body: LifeActor) -> Dictionary:
	if not owns(action) or not valid_target(action): return {}
	var seat: Dictionary = app._find_item(str(action.target_id))
	var tv: Dictionary = app._find_item(str(action.tv.id))
	if edge(action):
		var spot: Dictionary = edge_spot(action,false)
		if spot.is_empty(): return {}
		var sitter: Dictionary = {"position":spot.position,"yaw":spot.yaw,"kind":"seat","tv_target":tv.node.position+Vector3(0,1.1,0),"animation":str(action.id)}
		return _share_gaze(action,body,sitter)
	var result: Dictionary = app.world.activity_anchor(seat,str(action.id),action)
	if str(seat.kind) in WATER:
		result=app.world.outdoor_water_anchor(seat,action)
		var lane: int = clampi(int(action.get("swim_lane",0)),0,LifeOutdoorActs.MAX_JOIN-1)
		if str(seat.kind)=="pool":
			result.position=Vector3(result.position).lerp(result.swim_to,.2 if lane%2==0 else .8)
			result.position.y-=.35
		else:
			# The authored tub's two rear headrests are separate seats; keep
			# the first pair side by side instead of the old overlapping arc.
			result.position=seat.node.to_global(Vector3(-.38 if lane%2==0 else .38,.40,-.46 if lane<2 else .35))
		result.kind="seat"
		result.tv_water=true
		var toward: Vector3 = tv.node.position-result.position
		result.yaw=atan2(toward.x,toward.z)
	result.tv_target=tv.node.position+Vector3(0,1.1,0)
	result.animation=str(action.id)
	return _share_gaze(action,body,result)

## While the viewers talk, whoever is next to speak turns to look at the others.
func _share_gaze(action: Dictionary, body: LifeActor, result: Dictionary) -> Dictionary:
	for other: Dictionary in records():
		if other.body!=body and is_instance_valid(other.body) and str(other.action.tv.id)==str(action.tv.id) and str(other.action.tv.session)==str(action.tv.session) and str(other.action.phase)=="active":
			if fmod(float(action.tv.chat),5.0)<1.8: result.tv_target=other.body.to_global(other.body.get_portrait_center())
			break
	return result

func tick(delta: float) -> void:
	if app.household.speed<=0: delta=0.0
	var groups: Dictionary = {}
	for record: Dictionary in records():
		var action: Dictionary = record.action
		if not valid_target(action):
			if str(action.id)=="enjoy_outdoors": action.erase("tv")
			elif record.sim!=null: record.sim.cancel_action()
			else: _guest().cancel("")
			continue
		var key: String = str(action.tv.id)+":"+str(action.tv.session)
		if not groups.has(key): groups[key]=[]
		groups[key].append(record)
	var on: Array[String] = []
	for key: String in groups:
		var group: Array = groups[key]
		var active: Array = group.filter(_attending)
		if active.is_empty(): continue
		var state: Dictionary = active[0].action.tv
		var old_chat: float = float(state.chat)
		var clock: float = float(state.clock)+delta*float(app.household.speed)
		var chat: float = old_chat+delta
		for record: Dictionary in group:
			record.action.tv.clock=clock;record.action.tv.chat=chat
			record.action.tv.shared=active.size()>1
			if str(record.action.phase)=="active":
				record.action.changes=record.action.changes.duplicate(true)
				record.action.changes.social=26.0 if active.size()>1 else 0.0
		if active.size()>1 and int(chat/5.0)>int(old_chat/5.0):
			var turn: int = int(chat/5.0)-1
			var speaker: Dictionary = active[posmod(turn,active.size())]
			if is_instance_valid(speaker.body): speaker.body.speech(TOPICS[SHOWS.find(str(state.show))][posmod(turn,3)])
		var tv_id: String = str(state.id)
		on.append(tv_id)
		_screen(tv_id,str(state.show),clock)
	for id: String in screens.keys():
		if not on.has(id): _clear_screen(id)

func _screen(id: String, show: String, clock: float) -> void:
	var tv: Dictionary = app._find_item(id)
	if tv.is_empty(): return
	if not screens.has(id):
		var changed: Array = []
		for child: Node in tv.node.find_children("*","MeshInstance3D",true,false):
			var mesh_name: String = child.name.to_lower()
			if mesh_name in ["abstract screen horizon","screen sun"]:
				changed.append({"node":child,"tv_node":tv.node,"visible":child.visible,"original":child.material_override,"material":null})
				child.visible=false
				continue
			if mesh_name!="television screen" and not mesh_name.begins_with("screen panel"): continue
			var original: Material = child.material_override
			var material:=ShaderMaterial.new()
			material.shader=preload("res://scripts/tv_program.gdshader")
			var bounds:AABB=child.mesh.get_aabb()
			material.set_shader_parameter("screen_bounds",Vector4(bounds.position.x,bounds.position.y,maxf(bounds.size.x,.001),maxf(bounds.size.y,.001)))
			changed.append({"node":child,"tv_node":tv.node,"original":original,"material":material,"visible":child.visible})
			child.material_override=material
		screens[id]=changed
	for entry: Dictionary in screens[id]:
		if not is_instance_valid(entry.node) or entry.material==null: continue
		entry.material.set_shader_parameter("programme",SHOWS.find(show))
		entry.material.set_shader_parameter("playback",clock)
	tv.node.set_meta("tv_show",show)
	tv.node.set_meta("tv_clock",clock)

func _clear_screen(id: String) -> void:
	for entry: Dictionary in screens.get(id,[]):
		if is_instance_valid(entry.get("tv_node")):
			entry.tv_node.remove_meta("tv_show");entry.tv_node.remove_meta("tv_clock")
		if is_instance_valid(entry.node):
			entry.node.material_override=entry.original;entry.node.visible=entry.visible
	screens.erase(id)

func reset() -> void:
	for id: String in screens.keys(): _clear_screen(id)

func restore() -> String:
	reset()
	var programmes: Dictionary = {}
	var occupied: Dictionary = {}
	for record: Dictionary in records(true):
		var error: String = save_error(record.action)
		if not error.is_empty(): return error
		if not valid_target(record.action): return "The saved television or viewing place is no longer available."
		var state: Dictionary = record.action.tv
		if programmes.has(str(state.id)) and programmes[str(state.id)]!=[str(state.session),str(state.show)]: return "The saved viewers disagree about the television programme."
		programmes[str(state.id)]=[str(state.session),str(state.show)]
		for resource: String in app._activity_resources(record.action):
			if occupied.has(resource) and str(occupied[resource])!=str(record.id): return "Two saved television viewers occupy the same place."
			occupied[resource]=str(record.id)
	for record: Dictionary in records():
		if bool(record.action.tv.ready): _screen(str(record.action.tv.id),str(record.action.tv.show),float(record.action.tv.clock))
	return ""

func reconstruct() -> void:
	for record: Dictionary in records():
		if not is_instance_valid(record.body): continue
		if not _attending(record): continue
		var details: Dictionary = anchor(record.action,record.body)
		if details.is_empty(): continue
		record.body.set_activity_anchor(details.position,details.yaw,details.kind,str(record.action.id),details)
		record.body.reconstruct_tv_pose(str(record.action.id))
