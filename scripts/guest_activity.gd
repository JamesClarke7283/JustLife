extends RefCounted
class_name LifeGuestActivity
## A visitor keeps their own needs and one physical activity, without becoming a
## playable household member. The visit owns the route and the food ledger owns
## meals; no effect is earned until the visitor reaches the actual use point.
const NEEDS = ["hunger", "energy", "hygiene", "bladder", "fun", "social"]
const ALLOWED = ["roam", "toilet", "wash_hands", "shower", "bath", "snack", "relax", "read", "sleep", "watch_together", "enjoy_outdoors", "play_garden_game", "friendly", "joke", "hug", "talk_to_baby", "play_with_baby", "pet_pet", "pet_play",
	# What a guest at a party does (scripts/party_flow.gd): eat from the platter, dance, set down a dish, sing.
	"eat_party_food", "dance", "bring_dish", "sing_birthday"]
var _owner: WeakRef
var visit:
	get: return _owner.get_ref()
var app:
	get: return visit.app
var data: Dictionary = {}
var _journey_restored: bool = false

func _init(owner_visit) -> void: _owner = weakref(owner_visit)
func person() -> String: return str(visit.state.get("guest", ""))
func body() -> LifeActor: return app.world.actors.get(person())
func now() -> float: return visit._now()
func current_action() -> Dictionary: return data.get("current", {})
func activity() -> Dictionary: return current_action()
func active() -> bool: return not current_action().is_empty()
func owns_place() -> bool: return active()

func ensure() -> void:
	if not data.is_empty(): return
	data = {"version":1, "needs":{"hunger":76.0,"energy":82.0,"hygiene":82.0,"bladder":72.0,"fun":66.0,"social":60.0}, "last_at":now(), "next_at":now()+5.0, "current":{}, "serial":0, "completed":0, "bed_requested":false, "pending_meal":""}

func tick_needs() -> void:
	ensure()
	var minutes: float = maxf(0.0, now()-float(data.last_at))
	if int(app.household.speed)<=0: return
	for key: String in NEEDS:
		data.needs[key] = clampf(float(data.needs[key])-float(LifeSim.NEED_DECAY[key])*minutes/60.0,0.0,100.0)
	data.last_at = now()

func reset() -> void:
	if not data.is_empty() and is_instance_valid(app) and is_instance_valid(app.world): _release()
	data = {}

func snapshot() -> Dictionary:
	ensure()
	var saved: Dictionary = data.duplicate(true)
	if not saved.current.is_empty(): saved.current.target_position = _pack(saved.current.target_position)
	if bool(data.get("managed_route",false)):
		saved.journey={"version":LifeJourneyState.VERSION,"next_identity":app.traversal.next_identity,"next_ticket":app.traversal.next_ticket,"members":{person():app.traversal.snapshot_person(person(),current_action())}}
	return saved

func restore(saved: Dictionary = {}) -> void:
	data = saved.duplicate(true)
	_journey_restored=false
	ensure()
	if not current_action().is_empty() and current_action().target_position is Array:
		current_action().target_position = _vector(current_action().target_position)

func can_talk() -> bool:
	return not app.traversal.busy(person())

func interrupt_for_social() -> bool:
	if not can_talk():cancel("");return false
	if visit.meal.active():
		visit.meal.cancel("")
		return false
	cancel("")
	data.next_at = now()+5.0
	return true

func cancel(_reason: String = "") -> void:
	ensure()
	data.erase("pending_pet")
	_release()
	if app.traversal.cancel(person()):
		data.cancel_pending=true
		return
	data.current = {}
	data.erase("cancel_pending")
	data.next_at = now()+5.0
	if is_instance_valid(body()):
		visit.state.route = {"points":PackedVector3Array([body().position]),"point":1}

func _route_to(destination: Vector3) -> PackedVector3Array:
	var route: Dictionary=app.world.route_to(body().position,destination)
	return route.points if bool(route.ok) else PackedVector3Array()

func restore_journey() -> Dictionary:
	if _journey_restored or not bool(data.get("managed_route",false)):return {"ok":true}
	var result: Dictionary=app.traversal.restore(data.journey,true)
	if bool(result.ok):
		_journey_restored=true
		result=app.traversal.reconstruct()
	return result

func prepare_departure() -> void:
	ensure();data.returning=true
	if not app.traversal.busy(person()):cancel("")

func release_route() -> void:
	app.traversal.cancel(person())
	data.erase("managed_route");data.erase("journey")

func departure_tick(delta: float) -> bool:
	if not bool(data.get("returning",false)):return false
	if not app.traversal.active(person()) and app.world.point_level(body().position)==0:
		cancel("");data.returning=false
		release_route()
		visit.state.route={"points":PackedVector3Array(),"point":0}
		return false
	if not app.traversal.active(person()):
		var plan: Dictionary={"id":"roam","target_id":"","target_position":visit.state.inside,"duration":1.0,"changes":{}}
		if not _begin_plan(plan,false):return true
	_move(delta)
	return true

## A visitor who goes into the water changes into swimwear for it, and back into
## what they came in afterwards. The clothes they arrived in are kept on the
## visit record, so a paused save restores the same swimmer.
func _swim_dress(on: bool) -> void:
	var actor: LifeActor = body()
	if not is_instance_valid(actor): return
	if on:
		var kept: Dictionary = data.get("look_before", LifeCharacterIdentity.wardrobe_fields(actor.profile))
		if str(actor.profile.get("outfit_category", "")) == "swim" and data.has("look_before"): return
		data["look_before"] = kept
		var look: Dictionary = actor.profile.duplicate(true)
		LifeCharacterIdentity.apply_category(look, "swim")
		actor.apply_wardrobe(look)
	elif data.has("look_before"):
		actor.apply_wardrobe(data.look_before)
		data.erase("look_before")

func _release() -> void:
	_swim_dress(false)
	var current: Dictionary = current_action()
	if str(current.get("id",""))=="snack":
		var fridge: Dictionary=app._find_item(str(current.target_id))
		if not fridge.is_empty():_fridge_pose(fridge,0.0)
	if str(current.get("id","")) in ["pet_pet","pet_play"]:
		var pet: LifePetActor = app.pet_actors.get(str(current.target_id))
		if is_instance_valid(pet): pet.clear_interaction()
	if is_instance_valid(body()): body().clear_activity_anchor()

func holds_pet(id: String) -> bool:
	return not bool(data.get("cancel_pending",false)) and str(current_action().get("id","")) in ["pet_pet","pet_play"] and str(current_action().get("target_id",""))==id

func blocks(action: Dictionary, member_id: String = "") -> bool:
	if not active() or bool(data.get("cancel_pending",false)): return false
	var own: Dictionary = current_action()
	# A welcomed overnight guest may use the unoccupied half of the host bed.
	if member_id==str(data.get("sleep_host","")) and _shares_bed(own,action):
		return false
	if _shares_game(own,action): return false
	var held: Array[String] = app._activity_resources(own)
	for resource: String in app._activity_resources(action):
		if held.has(resource): return true
	return false

func _available(plan: Dictionary) -> bool:
	if is_instance_valid(app.get("sanitation_flow")) and app.sanitation_flow.privacy_blocks(plan,person()):return false
	if is_instance_valid(app.get("relationship_flow")) and app.relationship_flow.blocks(plan,person()):return false
	var wanted: Array[String] = app._activity_resources(plan)
	for member: Dictionary in app.household.members:
		var other: Dictionary = member.sim.get_current_action()
		if other.is_empty(): continue
		if str(member.id)==str(data.get("sleep_host","")) and _shares_bed(plan,other): continue
		if _shares_game(plan,other): continue
		for resource: String in app._activity_resources(other):
			if wanted.has(resource): return false
	# Another guest's place is theirs: two guests never take the same seat or bed.
	for other_visit: LifeHomeVisit in app.residents.visits():
		if other_visit==visit or not other_visit.active(): continue
		var theirs: Dictionary=other_visit.meal.activity() if other_visit.meal.owns_place() else (other_visit.activity.current_action() if not bool(other_visit.activity.data.get("cancel_pending",false)) else {})
		if theirs.is_empty() or _shares_game(plan,theirs): continue
		for resource: String in app._activity_resources(theirs):
			if wanted.has(resource): return false
	return true

func _shares_bed(own: Dictionary, other: Dictionary) -> bool:
	return str(own.id)=="sleep" and str(other.get("id","")) in ["sleep","nap","relax"] and str(other.get("target_id",""))==str(own.target_id) and str(other.get("seat_slot",""))!=str(own.get("seat_slot","")) and not str(other.get("seat_slot","")).is_empty()

func _shares_game(own: Dictionary, other: Dictionary) -> bool:
	return str(own.id)=="play_garden_game" and str(other.get("id",""))=="play_garden_game" and str(own.target_id)==str(other.get("target_id","")) and Vector3(own.target_position).distance_to(other.get("target_position",own.target_position))>=.8

func _target_plan(id: String, target: String) -> Dictionary:
	if id not in ALLOWED: return {}
	var plan: Dictionary = app.sim._actions.get(id,{}).duplicate(true)
	if id=="roam": plan={"id":id,"duration":1.0,"changes":{}}
	if plan.is_empty(): return {}
	plan.merge({"target_id":target,"phase":"approach","elapsed":0.0,"progress":0.0,"paid":false},true)
	var item: Dictionary = app._find_item(target)
	if not item.is_empty():
		if id=="enjoy_outdoors":
			if not LifeOutdoorActs.act_error(str(item.kind),"adult").is_empty(): return {}
			plan.duration=LifeOutdoorActs.acts(str(item.kind)).get("duration",40.0)
			plan.changes=LifeOutdoorActs.changes_for(str(item.kind))
		elif id=="play_garden_game":
			if not LifeGardenGames.GAMES.has(str(item.kind)):return {}
			plan.duration=LifeGardenGames.DURATION;plan.changes=LifeGardenGames.CHANGES.duplicate(true)
		plan.target_kind=str(item.kind)
		if id=="snack" and str(item.kind)=="fridge":
			# Stand to the handle side, outside the lower door sweep. The same
			# supported route endpoint is retained throughout reaching and eating.
			for offset: Vector3 in [Vector3(-.45,0,1.0),Vector3(-.25,0,1.1),Vector3(-.65,0,1.0)]:
				var at: Vector3=app.world.nearest_clear_point(item.node.to_global(offset),app.world.item_level(item),1)
				if not at.is_finite() or not app.traversal._free(person(),at):continue
				var local: Vector3=item.node.to_local(at)
				if local.x<-.9 or local.x>-.1 or local.z<.85 or local.z>1.3:continue
				plan.target_position=at
				if _available(plan) and not _route_to(at).is_empty():return plan
			return {}
		if id=="enjoy_outdoors" and str(item.kind) in LifeTVGroup.WATER:
			for lane: int in LifeOutdoorActs.MAX_JOIN:
				var wish: Vector3=item.node.to_global(Vector3((float(lane)-1.5)*.8,0,float(item.size.y)*.5+.65))
				var at: Vector3=app.world.nearest_clear_point(wish,app.world.item_level(item),2)
				plan.swim_lane=lane;plan.target_position=at
				if at.is_finite() and _available(plan) and not _route_to(at).is_empty():return plan
			return {}
		if id=="play_garden_game":
			for turn: int in range(8):
				var offset: Vector3=Vector3(sin(turn*PI*.25),0,cos(turn*PI*.25))*(maxf(float(item.size.x),float(item.size.y))*.5+.7)
				var at: Vector3=app.world.nearest_clear_point(item.node.to_global(offset),app.world.item_level(item),1)
				plan.target_position=at
				if at.is_finite() and _available(plan) and not _route_to(at).is_empty():return plan
			return {}
		var slots: Array[String] = app.world.seat_slots(item)
		for slot: String in slots:
			if str(item.kind)=="bed" and not _bed_slot_free(str(item.id),slot):continue
			plan.seat_slot=slot
			plan.target_position=app.world.bed_side_approach(item,slot) if str(item.kind)=="bed" else (app.world.slot_approach(item,slot) if slots.size()>1 else app.world.approach(item))
			if not Vector3(plan.target_position).is_finite() or not _available(plan): continue
			if not _route_to(plan.target_position).is_empty(): return plan
		return {}
	var target_body: Node3D = app.pet_actors.get(target) if id in ["pet_pet","pet_play"] else app.world.actors.get(target)
	if not is_instance_valid(target_body) or not target_body.visible or app.world.point_level(target_body.position)<0: return {}
	if id in ["pet_pet","pet_play"]:
		if not app._pet_errand(target).is_empty() or app.care_motion().holds(target): return {}
	else:
		var other: LifeSim = app.household.member_sim(target)
		if other==null or other.is_away(): return {}
		var doing: Dictionary = other.get_current_action()
		if not doing.is_empty(): return {}
	var distance: float = .85 if id in ["pet_pet","pet_play"] else 1.0
	for turn: int in range(8):
		var wish: Vector3 = target_body.position+Vector3(sin(turn*PI*.25),0,cos(turn*PI*.25))*distance
		var at: Vector3 = app.world.nearest_clear_point(wish,app.world.point_level(target_body.position),1)
		if not at.is_finite() or at.distance_to(target_body.position)>1.35 or not app.traversal._free(person(),at): continue
		if _route_to(at).is_empty(): continue
		plan.target_position=at
		return plan
	return {}

func request(id: String, target: String, explicit: bool = true) -> bool:
	ensure()
	if not visit.active() or str(visit.state.phase)!="inside" or visit.meal.active() or not app.residents._speaker(person()).is_empty(): return false
	if id in ["pet_pet","pet_play"] and not app.care_motion().holds(target) and not app._pet_errand(target).is_empty():
		if active() and (not explicit or not can_talk()):return false
		app.pet_behavior().command(target,"pet_stop_playing")
		if not app._pet_errand(target).is_empty():
			cancel("")
			data.pending_pet={"id":id,"target":target,"explicit":explicit,"until":now()+90.0}
			return true
	var plan: Dictionary = _target_plan(id,target)
	return request_plan(plan,explicit) if not plan.is_empty() else false

func request_plan(plan: Dictionary, explicit: bool = true) -> bool:
	ensure()
	if plan.is_empty() or str(plan.get("id","")) not in ALLOWED or str(visit.state.get("phase",""))!="inside" or visit.meal.active() or not app.residents._speaker(person()).is_empty(): return false
	if active() and (not explicit or not can_talk()): return false
	return _begin_plan(plan,explicit)

func _begin_plan(plan: Dictionary, explicit: bool) -> bool:
	var destination: Vector3 = plan.get("target_position",Vector3.INF)
	if not destination.is_finite() or app.world.point_level(destination)<0 or not _available(plan): return false
	var route: Dictionary = app.traversal.request(person(),destination)
	if not bool(route.ok): return false
	_release()
	data.managed_route=true
	data.serial=int(data.serial)+1
	data.current=plan.duplicate(true)
	data.current.merge({"phase":"approach","elapsed":0.0,"progress":0.0,"paid":false,"explicit":explicit,"serial":int(data.serial),"started_at":now(),"target_position":destination},true)
	visit.state.route={"points":PackedVector3Array([body().position]),"point":1}
	return true

func come_join(host_id: String, explicit: bool = true) -> bool:
	ensure()
	var host: LifeSim = app.household.member_sim(host_id)
	if host==null or host.is_away(): return false
	var current: Dictionary = host.get_current_action()
	if current.is_empty(): return request("friendly",host_id,explicit)
	if str(current.get("id","")) in ["watch","watch_together"] or current.has("tv"):
		if app.get("tv_group")!=null:
			var plan: Dictionary = app.tv_group.guest_target(host_id,self)
			if not plan.is_empty(): return request_plan(plan,explicit)
	if str(current.get("id",""))=="eat_meal":
		return offer_meal(str(current.get("meal_source","")),explicit)
	var item: Dictionary = app._find_item(str(current.get("target_id","")))
	if item.is_empty(): return false
	var action: String = str(current.id)
	if action not in ALLOWED: action="enjoy_outdoors" if LifeOutdoorActs.is_outdoor_act(str(item.kind)) else "relax"
	return request(action,str(item.id),explicit)

func seek_bed() -> bool:
	ensure();data.bed_requested=true
	data.sleep_host=app.household.selected_id()
	if active() and str(current_action().id)=="sleep":
		data.bed_requested=false
		return true
	if active() and can_talk():cancel("")
	var accepted: bool=_choose_kind("sleep",["bed"])
	if accepted:data.bed_requested=false
	return accepted

func _bed_slot_free(bed: String, slot: String) -> bool:
	for member: Dictionary in app.household.members:
		var reserved: String=app.household.assigned_bed_side(str(member.id),bed)
		if reserved==slot:return false
		var current: Dictionary=member.sim.get_current_action()
		if str(current.get("target_id",""))!=bed:continue
		if str(current.get("seat_slot",""))==slot:return false
		if str(member.id)!=str(data.get("sleep_host",app.household.selected_id())):return false
	return true

## Try the furnishings of these kinds nearest first, or, when `spread` is set,
## starting one further along each time so a visitor tries the pool, the hot tub
## and the swing in turn rather than always the nearest.
func _choose_kind(id: String, kinds: Array, spread: bool = false) -> bool:
	var candidates: Array = app.world.items.filter(func(item: Dictionary): return str(item.kind) in kinds)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return body().position.distance_squared_to(a.node.position)<body().position.distance_squared_to(b.node.position))
	if spread and candidates.size()>1:
		var turn: int=(int(data.get("pick",0))/AUTONOMY_CATEGORIES.size())%candidates.size()
		candidates=candidates.slice(turn)+candidates.slice(0,turn)
	for item: Dictionary in candidates:
		if request(id,str(item.id),false): return true
	return false

func _choose() -> void:
	data.next_at=now()+10.0
	if not str(data.pending_meal).is_empty():
		var meal_id: String = str(data.pending_meal)
		var batch: Dictionary=app.household.meals.batch(meal_id)
		if batch.is_empty() or int(batch.remaining)<=0 or now()>=float(batch.expires) or str(batch.storage)!="surface": data.pending_meal=""
		elif visit.meal.offer(meal_id): data.pending_meal="";return
		elif app.world.point_level(body().position)>0 and request_plan({"id":"roam","target_id":"","target_position":visit.state.inside,"duration":1.0,"changes":{}},false):return
	if float(data.needs.bladder)<45.0 and _choose_kind("toilet",["toilet"]): return
	if float(data.needs.hygiene)<40.0 and (_choose_kind("shower",["shower"]) or _choose_kind("bath",["bathtub"])): return
	if float(data.needs.hunger)<50.0:
		for batch: Dictionary in app.household.meals.batches:
			if visit.meal.offer(str(batch.id)): return
		if LifeGroceries.can_cook(app.household.groceries) and _choose_kind("snack",["fridge"]): return
	if bool(visit.state.get("stay_over",false)) and (bool(data.bed_requested) or float(data.needs.energy)<40.0):
		if _choose_kind("sleep",["bed"]):data.bed_requested=false;return
	# Shared host activity is preferred to wandering when needs are comfortable.
	if app.get("tv_group")!=null:
		for member: Dictionary in app.household.members:
			var plan: Dictionary = app.tv_group.guest_target(str(member.id),self)
			if not plan.is_empty() and request_plan(plan,false): return
	var host: LifeSim=app.household.selected()
	var host_action: Dictionary=host.get_current_action()
	if str(host_action.get("id","")) in ["relax","enjoy_outdoors","play_garden_game"] and come_join(app.household.selected_id(),false):return
	# Comfortable and idle, the visitor picks from everything the house offers.
	# The order turns with each choice so they do not repeat themselves, and
	# comes forward for the thing they are short of: fun brings the pets, the
	# garden and the lawn games up, company brings the household up. A choice
	# that cannot be carried out simply hands over to the next, never to a bare walk.
	data.pick=int(data.get("pick",0))+1
	# At a party the guest first looks for party things: a bite to eat, a dance.
	if visit.state.has("party") and app.get("party_flow")!=null and app.party_flow.guest_choose(self):return
	for category: String in _autonomy_order():
		if _try_category(category): return
	_roam()

const AUTONOMY_CATEGORIES: Array[String] = ["pets", "household", "outdoors", "games", "seats", "drink"]
const GAME_KINDS: Array[String] = ["game_trampoline", "game_hopscotch", "game_hoop", "game_croquet", "game_ring_toss", "game_mini_golf", "game_table_tennis", "game_badminton", "game_football_goal", "game_basketball", "game_giant_chess", "game_checkers"]

## The categories in the order this visitor tries them now.
func _autonomy_order() -> Array[String]:
	var turn: int = int(data.get("pick",0))%AUTONOMY_CATEGORIES.size()
	var ordered: Array[String] = []
	ordered.append_array(AUTONOMY_CATEGORIES.slice(turn))
	ordered.append_array(AUTONOMY_CATEGORIES.slice(0,turn))
	var wants_fun: bool = float(data.needs.fun)<55.0
	var wants_company: bool = float(data.needs.social)<55.0
	var urgent: Array[String] = []
	var rest: Array[String] = []
	for category: String in ordered:
		if (wants_fun and category in ["pets","outdoors","games"]) or (wants_company and category=="household"): urgent.append(category)
		else: rest.append(category)
	return urgent+rest

func _try_category(category: String) -> bool:
	match category:
		"pets":
			for pet: Dictionary in app.household.pets.get("pets",[]):
				if request("pet_play" if float(data.needs.fun)<55.0 else "pet_pet",str(pet.id),false): return true
		"household":
			# Everyone in the home gets a visit: a small child is played with, an
			# older one, a teenager or an adult is joked with and hugged.
			var members: Array = app.household.members
			var first: int = (int(data.get("pick",0))/AUTONOMY_CATEGORIES.size())%maxi(1,members.size())
			for offset: int in members.size():
				var member: Dictionary = members[(first+offset)%members.size()]
				var stage: String = str(member.sim.character.age_stage)
				var options: Array[String] = []
				if stage=="baby": options.append("play_with_baby")
				elif stage=="child": options.append_array(["joke","hug"])
				else: options.append_array(["joke","friendly"])
				for action: String in options:
					if request(action,str(member.id),false): return true
		"outdoors": return _choose_kind("enjoy_outdoors",["pool","hot_tub","outdoor_swing"],true)
		"games": return _choose_kind("play_garden_game",GAME_KINDS,true)
		"seats": return _choose_kind("relax",["sofa","armchair","loveseat","bench","garden_table"],true)
		"drink":
			# A cold drink from the fridge is a snack that is mostly a drink.
			if LifeGroceries.can_cook(app.household.groceries) and _choose_kind("snack",["fridge"]):
				if active() and str(current_action().get("id",""))=="snack":
					data.current.label="Grab a drink";data.current.flavour="drink"
				return true
	return false

func _roam() -> bool:
	var points: Array[Vector3]=[]
	for floor: Dictionary in visit._building().get("floors",[]):
		var rect: Rect2 = LifeBuildingState.rect(floor)
		for dx: float in [.25,.5,.75]:
			for dz: float in [.25,.5,.75]:
				points.append(Vector3(snappedf(rect.position.x+rect.size.x*dx,.25),LifeBuildingState.level_y(int(floor.level)),snappedf(rect.position.y+rect.size.y*dz,.25)))
	for offset: int in points.size():
		var at: Vector3=points[(offset+int(data.serial)*3)%points.size()]
		if at.distance_to(body().position)<1.0 or not app.traversal._free(person(),at): continue
		if app.traversal._aside_blocks_doorway(at):continue
		var level: int=app.world.point_level(at)
		var footprint:=Rect2(Vector2(at.x,at.z)-Vector2(.3,.3),Vector2(.6,.6))
		var landing: bool=false
		for stair: Dictionary in app.world.construction.building_state.get("stairs",[]):
			var lower: int=int(stair.lower)
			if level in [lower,lower+1] and footprint.intersects(LifeBuildingState.landing_rect(stair,level==lower+1)):landing=true;break
		if landing:continue
		if request_plan({"id":"roam","target_id":"","target_position":at,"duration":1.0,"changes":{}},false): return true
	return false

func tick(delta: float) -> bool:
	ensure();tick_needs()
	if is_instance_valid(app.get("relationship_flow")) and app.relationship_flow.listener_held(person()):
		app.relationship_flow.present_conversation(person())
		body().animate(delta,float(app.household.speed),false,"friendly")
		return true
	if bool(data.get("cancel_pending",false)):
		_move(delta)
		if not app.traversal.active(person()):cancel("")
		return true
	if not app.residents._speaker(person()).is_empty(): return false
	if visit.meal.active(): return false
	if data.has("pending_pet"):
		var waiting: Dictionary=data.pending_pet
		if now()>float(waiting.until) or not app.pet_actors.has(str(waiting.target)):data.erase("pending_pet")
		elif app._pet_errand(str(waiting.target)).is_empty():
			data.erase("pending_pet")
			request(str(waiting.id),str(waiting.target),bool(waiting.explicit))
		else:return true
	if not active():
		if int(app.household.speed)>0 and now()>=float(data.next_at): _choose()
		if not active(): return false
	var current: Dictionary=current_action()
	if str(current.get("id","")) in ["friendly","joke","hug","talk_to_baby","play_with_baby","pet_pet","pet_play"]:
		var target: Node3D=app.pet_actors.get(str(current.target_id)) if str(current.id) in ["pet_pet","pet_play"] else app.world.actors.get(str(current.target_id))
		if not is_instance_valid(target) or not target.visible or (str(current.phase)=="active" and target.position.distance_to(body().position)>1.8):cancel("");return false
	if int(app.household.speed)<=0: present();return true
	if now()-float(current.started_at)>float(current.duration)+180.0:
		cancel("The visitor could not reach that activity.");return false
	if str(current.phase)=="approach":
		if not _move(delta):return true
		if not active():return false
		if not _available(current): cancel("");return false
		if str(current.id)=="snack" and not bool(app.household.take_meal_for(null,"snack").ok): cancel("");return false
		current.phase="active";current.paid=true;current.last_at=now()
		if current.has("tv"): current.tv.ready=true
		if str(current.id)=="enjoy_outdoors" and LifeWetness.is_water_kind(str(current.get("target_kind",""))): _swim_dress(true)
		present();return true
	var elapsed: float=minf(maxf(0.0,now()-float(current.get("last_at",now()))),float(current.duration)-float(current.elapsed))
	var effect_minutes: float=elapsed
	var effect_duration: float=float(current.duration)
	if str(current.id)=="snack":
		effect_minutes=maxf(0.0,float(current.elapsed)+elapsed-3.0)-maxf(0.0,float(current.elapsed)-3.0)
		effect_duration=maxf(.001,float(current.duration)-3.0)
	current.last_at=now();current.elapsed=float(current.elapsed)+elapsed
	current.progress=float(current.elapsed)/maxf(.001,float(current.duration))
	for key: String in current.get("changes",{}):
		if data.needs.has(key): data.needs[key]=clampf(float(data.needs[key])+float(current.changes[key])*effect_minutes/maxf(.001,effect_duration),0,100)
	present()
	body().animate(delta,float(app.household.speed),false,str(current.get("animation",current.id)))
	if float(current.elapsed)>=float(current.duration): _finish()
	return true

func _move(delta: float) -> bool:
	var result: Dictionary=app.traversal.advance(person(),delta,int(app.household.speed))
	body().animate(delta,float(app.household.speed),bool(result.moving),"")
	visit.state.route={"points":PackedVector3Array([body().position]),"point":1}
	if not str(result.error).is_empty():cancel(str(result.error));return false
	return bool(result.finished)

func present(reconstruct: bool = false) -> void:
	if not active() or not is_instance_valid(body()): return
	var current: Dictionary=current_action()
	# A saved swimmer comes back in swimwear: the actor is rebuilt from the profile.
	if str(current.get("phase",""))=="active" and str(current.get("id",""))=="enjoy_outdoors" and LifeWetness.is_water_kind(str(current.get("target_kind",""))) and str(body().profile.get("outfit_category",""))!="swim": _swim_dress(true)
	if str(current.phase)!="active": body().clear_activity_anchor();return
	var anchor: Dictionary={}
	if current.has("tv") and app.get("tv_group")!=null:
		anchor=app.tv_group.anchor(current,body())
	elif current.get("face") is Array and str(current.id) in ["dance","bring_dish","sing_birthday"]:
		# A party guest stands where they are and turns to what the party is about: the stereo, the table, the cake.
		var face: Array=current.face
		var toward:=Vector3(face[0],face[1],face[2])-body().position
		anchor={"position":body().position,"yaw":atan2(toward.x,toward.z),"kind":"standing"}
	else:
		var item: Dictionary=app._find_item(str(current.target_id))
		if not item.is_empty():
			anchor=app.world.activity_anchor(item,LifeWetness.DRY_SIT_ID if str(item.kind)=="garden_table" and str(current.id)=="relax" else str(current.id),current)
			if str(current.id)=="snack" and str(item.kind)=="fridge":
				var elapsed: float=float(current.elapsed)
				var opened: float=smoothstep(0.0,1.0,elapsed)*(1.0-smoothstep(2.0,3.0,elapsed))
				var handle: Vector3=_fridge_pose(item,opened)
				current.animation="car_open_door" if elapsed<3.0 else "snack"
				anchor.position=current.target_position
				var facing: Vector3=(handle if elapsed<3.0 and handle.is_finite() else item.node.global_position)-Vector3(anchor.position)
				anchor.yaw=atan2(facing.x,facing.z)
				if elapsed<3.0 and handle.is_finite():anchor.care_target=handle
			if str(current.id)=="play_garden_game":
				var toward: Vector3=item.node.position-body().position
				anchor={"position":body().position,"yaw":atan2(toward.x,toward.z),"kind":"standing"}
		elif str(current.id) in ["pet_pet","pet_play"]:
			var pet: LifePetActor=app.pet_actors.get(str(current.target_id))
			if is_instance_valid(pet):
				var toward: Vector3=pet.position-body().position
				anchor={"position":body().position,"yaw":atan2(toward.x,toward.z),"kind":"standing","care_target":pet.back_point(),"care_time":float(current.elapsed)/LifeSim.GAME_MINUTES_PER_SECOND}
				pet.set_interaction(str(current.id),float(current.elapsed)/LifeSim.GAME_MINUTES_PER_SECOND,body().position)
		elif app.world.actors.has(str(current.target_id)):
			var toward: Vector3=app.world.actors[str(current.target_id)].position-body().position
			anchor={"position":body().position,"yaw":atan2(toward.x,toward.z),"kind":"standing"}
			current.animation="friendly" if str(current.id) in ["talk_to_baby","play_with_baby"] else str(current.id)
	if not anchor.is_empty():
		if anchor.has("animation"):current.animation=str(anchor.animation)
		var animation: String=str(current.get("animation",current.id))
		body().set_activity_anchor(anchor.position,anchor.yaw,str(anchor.kind),animation,anchor)
		if reconstruct:body().reconstruct_guest_pose(animation,float(current.elapsed)/LifeSim.GAME_MINUTES_PER_SECOND)

func _fridge_pose(item: Dictionary, opened: float) -> Vector3:
	var model: Node3D=item.node.find_child("KitchenFridge",true,false)
	if not is_instance_valid(model):return Vector3.INF
	var pivot: Node3D=model.get_node_or_null("VisitorFridgeDoor")
	if pivot==null:
		pivot=Node3D.new();pivot.name="VisitorFridgeDoor";model.add_child(pivot)
		pivot.position=Vector3(.39,0,.366)
		# Keep the authored door, handle and selected front finish together.
		# The freezer and cabinet shell retain their own original transforms.
		for child: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var at: Vector3=model.to_local(child.global_position)
			if at.z>.33 and at.y<1.30:child.reparent(pivot,true)
	pivot.rotation.y=clampf(opened,0.0,1.0)*1.05
	return pivot.to_global(Vector3(-.68,1.06,.084))

func _finish() -> void:
	var current: Dictionary=current_action().duplicate(true)
	if str(current.id) in ["pet_pet","pet_play"]:
		LifePetCare.apply_interaction(app.household.pet_care(str(current.target_id)),str(current.id),person())
	elif str(current.id) in ["friendly","joke","hug","talk_to_baby","play_with_baby"]:
		var peer: LifeSim=app.household.member_sim(str(current.target_id))
		if peer!=null and body().position.distance_to(app.world.actors[str(current.target_id)].position)<1.8:
			peer.needs.social=minf(100.0,float(peer.needs.social)+18.0)
			peer.needs.fun=minf(100.0,float(peer.needs.fun)+(20.0 if str(current.id)=="play_with_baby" else 6.0))
			if peer.relationships.has(person()):
				peer.relationships[person()].friendship=minf(100.0,float(peer.relationships[person()].friendship)+6.0)
				peer._update_relationship_status(peer.relationships[person()])
			peer._emit_changed()
	elif str(current.id)=="eat_party_food":app.party_flow.platter_taken(current)
	elif str(current.id)=="bring_dish":app.party_flow.dish_set_down(person(),current)
	data.completed=int(data.completed)+1
	data.last_completed=str(current.id)
	cancel("")
	data.next_at=now()+10.0
	if str(current.id)=="toilet":
		var sink: Dictionary=app.sanitation_flow.bathroom_sink(app.sim,str(current.target_id))
		if not sink.is_empty():request("wash_hands",str(sink.target_id),false)

func holds_member(id: String) -> bool:
	return not bool(data.get("cancel_pending",false)) and str(current_action().get("target_id",""))==id and str(current_action().get("id","")) in ["friendly","joke","hug","talk_to_baby","play_with_baby"]

func show_choices() -> void:
	ensure()
	app.close_overlay();app.overlay_open=true;app.dismiss_layer()
	app.card(Vector2(395,92),Vector2(610,592),app.P.WHITE,22,app.overlay)
	app.text_label(str(LifeResidents.PEOPLE[person()].name) if visit.state.has("party") else "Your visitor",Vector2(420,110),Vector2(550,40),26,app.P.INK,true,app.overlay)
	var summary: Array[String]=[]
	for key: String in NEEDS:summary.append("%s %d" % [key.capitalize(),roundi(data.needs[key])])
	app.paragraph(" · ".join(summary),Vector2(420,156),Vector2(550,54),14,app.P.MUTED,app.overlay)
	var scroll:=ScrollContainer.new();app.rect(scroll,Vector2(420,212),Vector2(558,428),app.overlay)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);scroll.add_child(column)
	for item: Dictionary in app.world.items:
		var action: String={"toilet":"toilet","shower":"shower","bathtub":"bath","fridge":"snack","bed":"sleep","sofa":"relax","loveseat":"relax","armchair":"relax","bench":"relax","garden_table":"relax","pool":"enjoy_outdoors","hot_tub":"enjoy_outdoors","outdoor_swing":"enjoy_outdoors"}.get(str(item.kind),"")
		if LifeGardenGames.GAMES.has(str(item.kind)):action="play_garden_game"
		if not action.is_empty():_choice_button(column,str(app.sim._actions[action].label)+" · "+str(item.get("label",item.kind)),action,str(item.id))
	for pet: Dictionary in app.household.pets.get("pets",[]):
		_choice_button(column,"Pet "+str(pet.get("name","pet")),"pet_pet",str(pet.id))
		_choice_button(column,"Play with "+str(pet.get("name","pet")),"pet_play",str(pet.id))
	for member: Dictionary in app.household.members:
		var baby: bool=str(member.sim.character.age_stage)=="baby"
		_choice_button(column,"Talk to "+str(member.sim.character.name),"talk_to_baby" if baby else "friendly",str(member.id))
		_choice_button(column,"Play with "+str(member.sim.character.name),"play_with_baby" if baby else "joke",str(member.id))

func _choice_button(column: VBoxContainer, label: String, action: String, target: String) -> void:
	var button:=Button.new();button.text=label;button.custom_minimum_size=Vector2(530,38)
	button.name="GuestActivity_"+action+"_"+target
	button.pressed.connect(func():
		var accepted: bool=request(action,target,true)
		app.close_overlay();app.show_notice("Your visitor is on the way." if accepted else "That activity is busy or has no clear path right now."))
	column.add_child(button)

func offer_meal(source: String, explicit: bool = false) -> bool:
	ensure()
	if not visit.active() or str(visit.state.phase)!="inside" or visit.meal.active() or str(data.pending_meal)==source:return false
	var batch: Dictionary=app.household.meals.batch(source)
	if batch.is_empty() or int(batch.remaining)<=0 or now()>=float(batch.expires) or str(batch.storage)!="surface":return false
	data.pending_meal=source
	if explicit or (not bool(current_action().get("explicit",false)) and str(current_action().get("id","")) not in ["toilet","shower","bath","sleep"]):cancel("")
	if not active() and visit.meal.offer(source):data.pending_meal=""
	return true

func feed_from_meal(amount: float) -> void:
	ensure();data.needs.hunger=minf(100.0,float(data.needs.hunger)+maxf(0.0,amount))

func physical_error() -> String:
	if bool(data.get("managed_route",false)):
		if not app.traversal.busy(person()) and not app.world.lot_navigation.point_clear(app.world.point_level(body().position),body().position):return "The visitor is outside supported clear floor."
		if not app.traversal.busy(person()) and not app.traversal._free(person(),body().position,false):return "The visitor overlaps another body or reserved landing."
		var occupancy: Dictionary=app.traversal.validate_occupancy()
		if not bool(occupancy.ok):return str(occupancy.error)
	if not active(): return ""
	var current: Dictionary=current_action()
	if not app.world.lot_navigation.point_clear(app.world.point_level(current.target_position),current.target_position): return "The visitor's activity is on blocked ground."
	if str(current.phase)=="active" and body().position.distance_to(current.target_position)>.02:return "The visitor has not arrived at their activity."
	if not str(current.target_id).is_empty() and app._find_item(str(current.target_id)).is_empty() and not app.world.actors.has(str(current.target_id)) and not app.pet_actors.has(str(current.target_id)):return "The visitor's activity target is missing."
	return ""

static func _pack(at: Vector3) -> Array: return [at.x,at.y,at.z]
static func _vector(at: Array) -> Vector3: return Vector3(at[0],at[1],at[2])
static func allows_elevated_position(visit_state: Dictionary) -> bool:
	var saved: Variant=visit_state.get("activity",{})
	return saved is Dictionary and saved.get("managed_route",false)==true

## `others` are the other saved guests' visit states. Any of them on a managed route
## joins the same check, with the highest counters of all, so two guests on the
## stairs can neither share a lock nor reuse a journey number.
static func validate_route(visit_state: Dictionary, household: Dictionary, others: Array = []) -> String:
	if not allows_elevated_position(visit_state):return ""
	var activity_state: Dictionary=visit_state.activity
	var journey: Variant=activity_state.get("journey")
	var id: String=str(visit_state.guest)
	if not journey is Dictionary or journey.get("version")!=LifeJourneyState.VERSION or not journey.get("members") is Dictionary or journey.members.size()!=1 or not journey.members.has(id):return "Save is missing the visitor's physical journey."
	var record: Variant=journey.members[id]
	if not record is Dictionary or record.get("position")!=visit_state.get("position") or record.get("yaw")!=visit_state.get("rotation"):return "The visitor and journey positions disagree."
	if not LifeJourneyState.number(journey.get("next_identity"),1,1e9,true) or not LifeJourneyState.number(journey.get("next_ticket"),1,1e9,true):return "Save contains invalid visitor journey counters."
	var combined: Dictionary=household.duplicate(true)
	var travel: Dictionary=combined.get("journeys",{"version":LifeJourneyState.VERSION,"next_identity":1,"next_ticket":1,"members":{}})
	for member: Dictionary in combined.members:
		if str(member.id)==id:return "The visitor is already in this household."
		if travel.members.has(str(member.id)):continue
		var context: Dictionary=member.state.character.get("world_state",{})
		travel.members[str(member.id)]={"position":context.get("player",[]),"yaw":context.get("player_rotation",0.0),"motion":{}}
	travel.next_identity=maxi(int(travel.next_identity),int(journey.next_identity))
	travel.next_ticket=maxi(int(travel.next_ticket),int(journey.next_ticket))
	travel.members[id]=record
	var profile: Dictionary=LifeResidents.PEOPLE[id].duplicate(true)
	profile.world_state={"player":record.position,"player_rotation":record.yaw}
	var queue: Array=[]
	if not activity_state.current.is_empty():queue.append(activity_state.current)
	combined.members.append({"id":id,"state":{"character":profile,"action_queue":queue}})
	for other: Variant in others:
		# Another guest on a managed route is checked in the same journey. Its own
		# record is validated on its own turn, so a malformed one is skipped here.
		if not other is Dictionary or not allows_elevated_position(other):continue
		var other_id: String=str(other.get("guest",""))
		var other_state: Dictionary=other.activity
		var other_journey: Variant=other_state.get("journey")
		if other_id==id or not LifeResidents.PEOPLE.has(other_id) or not other_journey is Dictionary or not other_journey.get("members") is Dictionary or not other_journey.members.get(other_id) is Dictionary:continue
		if not LifeJourneyState.number(other_journey.get("next_identity"),1,1e9,true) or not LifeJourneyState.number(other_journey.get("next_ticket"),1,1e9,true) or not other_state.get("current") is Dictionary:continue
		travel.next_identity=maxi(int(travel.next_identity),int(other_journey.next_identity))
		travel.next_ticket=maxi(int(travel.next_ticket),int(other_journey.next_ticket))
		travel.members[other_id]=other_journey.members[other_id]
		var other_profile: Dictionary=LifeResidents.PEOPLE[other_id].duplicate(true)
		other_profile.world_state={"player":other_journey.members[other_id].get("position",[]),"player_rotation":other_journey.members[other_id].get("yaw",0.0)}
		var other_queue: Array=[]
		if not other_state.current.is_empty():other_queue.append(other_state.current)
		combined.members.append({"id":other_id,"state":{"character":other_profile,"action_queue":other_queue}})
	var prior_land: Dictionary=LifeBuildingState.land
	var checked: Dictionary=LifeJourneyState.validate(travel,combined)
	LifeBuildingState.land=prior_land
	return "" if bool(checked.ok) else str(checked.error)

static func validate(visit_state: Dictionary, at: float) -> String:
	var saved: Variant=visit_state.get("activity",{})
	if not saved is Dictionary:return "Save contains invalid visitor activities."
	if saved.is_empty():return ""
	if saved.get("version")!=1 or not saved.get("needs") is Dictionary:return "Save contains invalid visitor needs."
	for key: String in NEEDS:
		if not LifeBuildingState.number(saved.needs.get(key),0,100):return "Save contains invalid visitor needs."
	for key: String in ["last_at","next_at"]:
		if not LifeBuildingState.number(saved.get(key),0,at+180.0):return "Save contains an invalid visitor clock."
	for key: String in ["serial","completed"]:
		if not LifeBuildingState.number(saved.get(key),0,10000000,true):return "Save contains invalid visitor activity counts."
	if saved.has("pick") and not LifeBuildingState.number(saved.pick,0,100000000,true):return "Save contains invalid visitor activity counts."
	if not saved.get("current") is Dictionary or not saved.get("bed_requested") is bool or not saved.get("pending_meal") is String:return "Save contains invalid visitor activity state."
	for key: String in ["managed_route","cancel_pending","returning"]:
		if saved.has(key) and not saved[key] is bool:return "Save contains invalid visitor movement state."
	if saved.has("pending_pet"):
		var waiting: Variant=saved.pending_pet
		if not waiting is Dictionary or str(waiting.get("id","")) not in ["pet_pet","pet_play"] or not waiting.get("target") is String or not waiting.get("explicit") is bool or not LifeBuildingState.number(waiting.get("until"),0,at+90.0):return "Save contains an invalid visitor pet request."
	var current: Dictionary=saved.current
	if current.is_empty():return ""
	if str(current.get("id","")) not in ALLOWED or str(current.get("phase","")) not in ["approach","active"] or not current.get("target_id") is String or not LifeJourneyState.vector_valid(current.get("target_position")) or LifeJourneyState.level(_vector(current.target_position))<0:return "Save contains an invalid visitor activity."
	if not LifeBuildingState.number(current.get("duration"),.1,360.0) or not LifeBuildingState.number(current.get("elapsed"),0,float(current.duration)) or not LifeBuildingState.number(current.get("started_at"),0,at) or not current.get("explicit") is bool or not current.get("paid") is bool:return "Save contains invalid visitor activity progress."
	if str(current.phase)=="active" and (not current.paid or not LifeBuildingState.number(current.get("last_at"),0,at)):return "Save contains an unstarted visitor activity."
	if not current.get("changes",{}) is Dictionary:return "Save contains invalid visitor activity effects."
	for key: Variant in current.get("changes",{}):
		if not key is String or key not in NEEDS or not LifeBuildingState.number(current.changes[key],-100,100):return "Save contains invalid visitor activity effects."
	if current.has("tv"):
		var tv_error: String=LifeTVGroup.save_error(current)
		if not tv_error.is_empty():return tv_error
	return ""
