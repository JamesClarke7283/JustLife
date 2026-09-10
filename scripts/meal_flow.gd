extends Node
class_name LifeMealFlow
## Routes preparation, carrying, independent diners, leftovers and washing.
const Building=preload("res://scripts/building_state.gd")
const ACTIONS := ["serve_meal","eat_meal","store_meal","clean_plate","discard_meal"]
# Top faces in tools/create_furniture.py, measured from each furniture root.
# Meal meshes have their underside at local Y=0; 2 mm avoids contact flicker.
const SURFACE_HEIGHTS := LifeMeals.SURFACE_HEIGHTS
var app: Node
var views: Dictionary = {}
var revision: String = ""
var sync_due: bool = true
var _carry_grips_cache:Dictionary={}
# Static default-footprint candidates; bodies, food and visible floor support
# remain live checks. Failed rebuilds keep their actual previous navigation.
var _floor_grid_navigation:LifeLotNavigation
var _floor_grid_generation:int=-1
var _floor_grid_region:Rect2i
var _floor_grid_candidates:Dictionary={}


func food() -> LifeMeals:return app.household.meals
func now() -> float:return (app.household.day-1)*1440.0+app.household.minutes
func member_id(sim:LifeSim) -> String:
	for member: Dictionary in app.household.members:
		if member.sim==sim:return str(member.id)
	return ""
func item(id:String) -> Dictionary:return app._find_item(id)
func actor(id:String) -> LifeActor:return app.world.actors.get(id)

func _home_visit()->LifeHomeVisit:
	var residents:Variant=app.get("residents")
	return residents.home_visit if residents!=null else null

func _reconcile_guest_offer()->void:
	var visit:LifeHomeVisit=_home_visit()
	if visit!=null:visit.meal.reconcile_source()

func activity_for(person:String)->Dictionary:
	var sim:LifeSim=app.household.member_sim(person)
	if is_instance_valid(sim):return sim.get_current_action()
	var visit:LifeHomeVisit=_home_visit()
	if visit!=null and visit.owns(person) and visit.meal.owns_place():return visit.meal.activity()
	return {}

func activity_records()->Array:
	var result:Array=[]
	for member:Dictionary in app.household.members:
		if not member.sim.is_away():result.append({"id":str(member.id),"action":member.sim.get_current_action()})
	var visit:LifeHomeVisit=_home_visit()
	if visit!=null and visit.meal.owns_place():result.append({"id":str(visit.state.guest),"action":visit.meal.activity()})
	return result

func guest_blocks(action:Dictionary)->bool:
	var visit:LifeHomeVisit=_home_visit()
	if visit==null or not visit.meal.owns_place():return false
	var held:Array[String]=app._activity_resources(visit.meal.activity())
	for resource:String in app._activity_resources(action):
		if held.has(resource):return true
	return false

func guest_place_valid(action:Dictionary,restoring:bool=false)->bool:
	var person:String=str(app.residents.home_visit.state.guest)
	if bool(action.get("meal_standing",false)):
		if not _standing_clear(person,action.target_position):return false
	else:
		var chair:Dictionary=item(str(action.get("meal_seat","")))
		if chair.is_empty() or _host_level(chair)!=0 or action.target_position!=app.world.approach(chair):return false
		var table:Dictionary=_chair_table(chair)
		if table.is_empty() or not _surface_clear(table,_plate_offset(chair,table),LifeMeals.PLATE_HALF_SIZE,str(action.get("meal_plate",""))):return false
		for member:Dictionary in app.household.members:
			var other:Dictionary=member.sim.get_current_action()
			if str(other.get("meal_seat",""))==str(chair.id):return false
			if str(other.get("target_id",""))==str(chair.id) and (str(other.get("phase",""))=="active" or bool(app.motion_states.get(str(member.id),{}).get("resume_active",false))):return false
	if not restoring and actor(person).position.distance_to(action.target_position)>.02:return false
	return true

func _pending_furniture(id:String) -> bool:
	var pending:Variant=app.get("pending_move")
	return not id.is_empty() and pending is Dictionary and not pending.is_empty() and str(pending.get("entry",{}).get("id",""))==id

func action_availability(sim:LifeSim,id:String,target:String) -> String:
	var person:String=member_id(sim)
	if id=="cook":
		if food().batches.size()>=LifeMeals.MAX_BATCHES:return "Clear old meals before making more food."
		if not food().carried_by(person).is_empty():return "Put down the food you are carrying first."
		if app.world.closest_item("stove",Vector3.ZERO).is_empty():return "Place a stove to cook a hot meal."
		return ""
	if id=="eat_meal":
		var held:Dictionary=food().carried_by(person)
		if not held.is_empty() and held.has("batch") and float(held.progress)<1:return ""
		var batch:Dictionary=food().batch(target)
		if not batch.is_empty():
			if int(batch.remaining)<=0:return "That dish has no servings left."
			if now()>=float(batch.expires):return "This meal has spoiled. Clear it away."
			if str(batch.storage)=="carried":return "Wait until the cook puts the serving dish down."
			return ""
		var plate:Dictionary=food().portion(target)
		if not plate.is_empty() and str(plate.owner).is_empty() and float(plate.progress)<1 and now()<float(plate.expires):return ""
		return "Choose an available serving or a plate with food."
	if id=="store_meal":
		var batch:Dictionary=food().batch(target)
		if batch.is_empty() or int(batch.remaining)<=0 or now()>=float(batch.expires):return "Only fresh remaining servings can be stored."
		if str(batch.storage)!="surface" or not str(batch.owner).is_empty():return "That dish is already stored or being carried."
		if app.world.closest_item("fridge",Vector3.ZERO).is_empty():return "Place a fridge for leftovers."
	if id=="discard_meal":
		var batch:Dictionary=food().batch(target)
		if batch.is_empty() or int(batch.remaining)<=0 or not str(batch.owner).is_empty():return "That serving dish is empty or being carried."
		if app.world.closest_item("sink",Vector3.ZERO).is_empty():return "Place a sink to clear the dish."
	if id=="clean_plate":
		var plate:Dictionary=food().portion(target)
		if plate.is_empty() or not str(plate.owner).is_empty():return "That plate is being used."
		if app.world.closest_item("sink",Vector3.ZERO).is_empty():return "Place a sink to wash dishes."
	return ""

func actions_for(sim:LifeSim,kind:String,target:String) -> Array:
	var ids:Array=[]
	if kind=="meal":ids=["eat_meal","store_meal","discard_meal"]
	if kind=="plate":ids=["eat_meal","clean_plate"]
	var result:Array=[]
	for id:String in ids:
		var definition:Dictionary=sim.get_action_definition(id)
		var reason:String=action_availability(sim,id,target)
		definition.merge({"available":reason.is_empty(),"unavailable_reason":reason},true)
		result.append(definition)
	return result

func resolve(sim:LifeSim,action:Dictionary) -> void:
	if str(action.id)=="cook" and str(action.get("recipe",""))=="harvest_bake":
		var oven:Dictionary=item(str(action.target_id))
		if not oven.is_empty():action.target_position=app.world.oven_approach(oven)
		return
	if str(action.id) not in ACTIONS:return
	var person:String=member_id(sim)
	if not action.has("meal_source"):action.meal_source=str(action.target_id)
	if not action.has("meal_stage"):action.meal_stage="pickup"
	if action.id=="serve_meal":
		var surface:Dictionary=_serving_surface(actor(person).position,str(action.meal_source))
		if not surface.is_empty():action.target_id=surface.id
	elif action.id=="eat_meal" and action.get("meal_stage")=="eat":
		var chair:Dictionary=item(str(action.get("meal_seat","")))
		if chair.is_empty() or _chair_table(chair).is_empty():
			if not _choose_seat(person,action):_stop(sim,"There is no clear place to enjoy this serving.");return
			var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
			if not plate.is_empty():plate.storage="carried";plate.seat=""
		# A carried plate is the diner’s own resource, not their destination.
		# Preserve the exact reserved walking endpoint through every resolver.
		if bool(action.get("meal_standing",false)):return
	elif action.get("meal_stage")=="store":
		var fridge:Dictionary=app.world.closest_item("fridge",actor(person).position)
		if not fridge.is_empty():action.target_id=fridge.id
	elif action.get("meal_stage") in ["wash","discard"]:
		var sink:Dictionary=app.world.closest_item("sink",actor(person).position)
		if not sink.is_empty():action.target_id=sink.id
	var target:Dictionary=item(str(action.target_id))
	if not target.is_empty():action.target_position=app.world.approach(target)

func before_begin(sim:LifeSim,action:Dictionary) -> bool:
	if str(action.id)=="cook":
		var problem:String=action_availability(sim,"cook",str(action.target_id))
		if not problem.is_empty():_stop(sim,problem);return false
	if str(action.id) not in ACTIONS:return true
	var person:String=member_id(sim)
	if action.id=="eat_meal" and action.get("meal_stage")=="pickup":
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		if plate.is_empty():
			if not food().batch(str(action.meal_source)).is_empty():plate=food().claim(str(action.meal_source),person,now())
			elif food().take_portion(str(action.meal_source),person,now()):plate=food().portion(str(action.meal_source))
		if plate.is_empty():_stop(sim,"There is no fresh serving available.");return false
		action.meal_plate=plate.id;action.meal_stage="eat"
		_reconcile_guest_offer()
		action.elapsed=float(plate.progress)*LifeMeals.EATING_MINUTES
		action.progress=float(plate.progress)
		if not _choose_seat(person,action):_stop(sim,"There is no clear place to enjoy this serving.");return false
		sync_due=true;sim._emit_action_started(action);return false
	if action.id=="eat_meal":
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		if plate.is_empty() or str(plate.owner)!=person or now()>=float(plate.expires):_stop(sim,"This serving is no longer available.");return false
		if bool(action.get("meal_standing",false)):
			if not _standing_clear(person,action.target_position):
				action.erase("meal_standing")
				if not _choose_seat(person,action):_stop(sim,"There is no clear place to enjoy this serving.");return false
				sim._emit_action_started(action);return false
			if actor(person).position.distance_to(action.target_position)>.02:
				sim._emit_action_started(action);return false
		var place:Dictionary=eating_anchor(person,action)
		var host:Dictionary=item(str(place.get("table_id","")))
		var offset:Vector3=host.node.to_local(place.plate_position) if not host.is_empty() else Vector3.ZERO
		food().put_portion(str(plate.id),str(place.get("table_id","")),str(action.get("meal_seat","")),place.plate_position,true,offset)
	if action.id in ["store_meal","discard_meal"] and action.get("meal_stage")=="pickup":
		var batch:Dictionary=food().batch(str(action.meal_source))
		if batch.is_empty() or str(batch.storage) not in (["surface"] if action.id=="store_meal" else ["surface","fridge"]) or not str(batch.owner).is_empty() or (action.id=="store_meal" and now()>=float(batch.expires)) or not food().set_batch_location(str(batch.id),"carried","",actor(person).position,now(),person):_stop(sim,"That dish is no longer available.");return false
		action.meal_stage="store" if action.id=="store_meal" else "discard";_reconcile_guest_offer();sim._emit_action_started(action);return false
	if action.id=="clean_plate" and action.get("meal_stage")=="pickup":
		var plate:Dictionary=food().portion(str(action.meal_source))
		if plate.is_empty() or not str(plate.owner).is_empty() or not food().carried_by(person).is_empty():_stop(sim,"That plate is no longer available.");return false
		plate.owner=person;plate.storage="carried";plate.seat=""
		action.meal_stage="wash";sim._emit_action_started(action);return false
	return true

func _stop(sim:LifeSim,message:String) -> void:
	sim._emit_notice(message);sim.cancel_action();sync_due=true

func carry_diner_plate(action:Dictionary) -> void:
	var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
	if not plate.is_empty():
		plate.storage="carried"
		plate.seat=""

func _footprint(value:Dictionary) -> Vector2:
	return LifeMeals.PLATE_HALF_SIZE if value.has("batch") else LifeMeals.PLATTER_HALF_SIZE

func _plate_offset(chair:Dictionary,table:Dictionary) -> Vector3:
	var toward:Vector3=(table.node.position-chair.node.position).normalized()
	var at:Vector3=table.node.to_local(chair.node.position+toward*.48)
	return Vector3(clampf(at.x,-.62,.62),SURFACE_HEIGHTS.dining,clampf(at.z,-.39,.39))

func _surface_clear(host:Dictionary,at:Vector3,half:Vector2,except_id:String="") -> bool:
	if not at.is_finite() or absf(at.y-float(SURFACE_HEIGHTS[str(host.kind)]))>.003:return false
	var extent:Vector2=LifeMeals.SURFACE_HALF_SIZE[str(host.kind)]
	if absf(at.x)+half.x+LifeMeals.SURFACE_INSET>extent.x+.00001 or absf(at.z)+half.y+LifeMeals.SURFACE_INSET>extent.y+.00001:return false
	for value:Dictionary in food().batches+food().portions:
		if str(value.id)==except_id or str(value.host)!=str(host.id) or str(value.venue)!=app.current_venue or str(value.storage) in ["carried","fridge"]:continue
		# Empty platters are no longer rendered; retained ledger records do not
		# occupy physical tabletop space while their dirty plates await washing.
		if not value.has("batch") and int(value.remaining)<=0:continue
		var other:Vector2=_footprint(value)
		var offset:Array=value.get("offset",[0,0,0])
		if absf(at.x-float(offset[0]))<half.x+other.x+.01 and absf(at.z-float(offset[2]))<half.y+other.y+.01:return false
	# A diner walking to a free chair already reserves their reachable setting.
	for member:Dictionary in activity_records():
		var action:Dictionary=member.action
		if str(action.get("id",""))!="eat_meal" or str(action.get("meal_plate",""))==except_id:continue
		var chair:Dictionary=item(str(action.get("meal_seat","")))
		if chair.is_empty() or str(_chair_table(chair).get("id",""))!=str(host.id):continue
		var reserved:Vector3=_plate_offset(chair,host)
		if absf(at.x-reserved.x)<half.x+LifeMeals.PLATE_HALF_SIZE.x+.01 and absf(at.z-reserved.z)<half.y+LifeMeals.PLATE_HALF_SIZE.y+.01:return false
	return true

func _surface_slot(host:Dictionary,half:Vector2,except_id:String="") -> Vector3:
	var extent:Vector2=LifeMeals.SURFACE_HALF_SIZE[str(host.kind)]-half-Vector2.ONE*LifeMeals.SURFACE_INSET
	var candidates:Array[Vector3]=[Vector3(0,SURFACE_HEIGHTS[str(host.kind)],0)]
	for x:int in range(-8,9):
		for z:int in range(-8,9):candidates.append(Vector3(extent.x*x/8.0,SURFACE_HEIGHTS[str(host.kind)],extent.y*z/8.0))
	candidates.sort_custom(func(a:Vector3,b:Vector3)->bool:return Vector2(a.x,a.z).length_squared()<Vector2(b.x,b.z).length_squared())
	for at:Vector3 in candidates:
		if _surface_clear(host,at,half,except_id):return at
	return Vector3.INF

func _floor_level(at:Vector3) -> int:
	if not at.is_finite():return -1
	for level:int in [0,1]:
		if absf(at.y-Building.level_y(level))<.025:return level
	# Authored wood, tile, foundation and lawn tops lie below navigationY.
	# No upper/stair point is rounded down through a floor.
	if at.y>=-.175 and at.y<=Building.GROUND_Y+.025:return 0
	return -1

func _host_level(host:Dictionary) -> int:
	if Building.number(host.get("level"),0,1,true):return int(host.level)
	return _floor_level(host.node.global_position) if is_instance_valid(host.get("node")) else -1

func _food_level(value:Dictionary,host:Dictionary={}) -> int:
	if not str(value.get("owner","")).is_empty() and (str(value.storage)=="carried" or (str(value.storage)=="table" and str(value.host).is_empty())):
		var carrier:LifeActor=actor(str(value.owner))
		if is_instance_valid(carrier):return _floor_level(carrier.position)
	if not host.is_empty():return _host_level(host)
	var at:=Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))
	# A removed host's saved offset preserves its former floor identity.
	if not str(value.host).is_empty():at.y-=float(value.get("offset",[0,0,0])[1])
	return _floor_level(at)

func _same_floor_space(first:Vector3,second:Vector3) -> bool:
	# Activity anchors may sit above the floor (chairs/beds); adjacent storeys
	# are3m apart. Keep their reservations separate without dropping anchors.
	return first.is_finite() and second.is_finite() and absf(first.y-second.y)<Building.RISE*.5

func _floor_navigation_clear(at:Vector3,half:Vector2=Vector2(.16,.16)) -> bool:
	var level:int=_floor_level(at)
	if level<0:return false
	var point:=Vector3(at.x,Building.level_y(level),at.z)
	if not app.world.construction.building_state.is_empty():return app.world.lot_navigation.point_clear(level,point,half)
	var cell:=Vector2i(roundi(point.x*4),roundi(point.z*4))
	return level==0 and app.world.navigation.region.has_point(cell) and not app.world.navigation.is_point_solid(cell)

func _serving_surface(from:Vector3,except_id:String="") -> Dictionary:
	var level:int=_floor_level(from)
	if level<0:return {}
	for kind:String in ["dining","counter","stove"]:
		var candidates:Array=[]
		for host:Dictionary in app.world.items:
			if _host_level(host)>=0 and str(host.kind)==kind and _surface_slot(host,LifeMeals.PLATTER_HALF_SIZE,except_id).is_finite():candidates.append(host)
		candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.node.position.distance_squared_to(from)<b.node.position.distance_squared_to(from))
		for host:Dictionary in candidates:
			if not app.world.path_to(from,app.world.approach(host)).is_empty():return host
	return {}

func _floor_surface_snapshot() -> Array:
	# Reused only within a synchronous query, never across layout/view changes.
	var nodes:Array=app.world.house.get_children()
	if is_instance_valid(app.world.construction):nodes.append_array(app.world.construction.floor_nodes)
	var surfaces:Array=[]
	for node:Node in nodes:
		if not node is MeshInstance3D or not node.mesh is BoxMesh or not node.visible:continue
		var half:Vector3=node.mesh.size*.5
		var transform:Transform3D=node.global_transform
		surfaces.append({"half":half,"inverse":transform.affine_inverse(),"top":(transform*Vector3(0,half.y,0)).y})
	return surfaces

func _floor_height(at:Vector3,surfaces:Variant=null) -> float:
	var level:int=_floor_level(at)
	if level<0:return INF
	if surfaces==null:surfaces=_floor_surface_snapshot()
	var height:float=-.15 if level==0 else -INF
	for surface:Dictionary in surfaces:
		var half:Vector3=surface.half
		var local:Vector3=surface.inverse*at
		var top:float=surface.top
		if top>Building.level_y(level)+.025 or top<Building.level_y(level)-.32 or top<height or absf(local.x)>half.x or absf(local.z)>half.z:continue
		height=top
	return height+.002 if is_finite(height) else INF

func _floor_support(at:Vector3,half:Vector2,surfaces:Variant=null) -> float:
	var level:int=_floor_level(at)
	if level<0:return INF
	var bounds:Rect2=Rect2(Vector2(at.x,at.z)-half,half*2)
	var state:Dictionary=app.world.construction.building_state
	if not state.is_empty() and (not Building.footprint_supported(state,level,bounds,level==0) or Building.blocked_rect(state,level,bounds.grow(.002))):return INF
	if app.world.construction.rect_blocked(bounds.grow(.002),level):return INF
	for furnishing:Dictionary in app.world.items:
		if _host_level(furnishing)!=level:continue
		if str(furnishing.kind) in ["meal","plate","puddle"] or LifeCatalog.passable(str(furnishing.kind)):continue
		# Project the whole dish footprint into the furnishing's local axes.
		# This conservative rectangle also covers furnishings at arbitrary yaw.
		var inverse:Basis=furnishing.node.global_basis.inverse()
		var across:Vector3=inverse*Vector3(half.x,0,0)
		var along:Vector3=inverse*Vector3(0,0,half.y)
		var extent:Vector2=Vector2(absf(across.x)+absf(along.x),absf(across.z)+absf(along.z))
		var local:Vector3=furnishing.node.to_local(at)
		var body:Vector2=furnishing.size*.5
		if absf(local.x)<body.x+extent.x+.002 and absf(local.z)<body.y+extent.y+.002:return INF
	var low:float=INF;var high:float=-INF
	if surfaces==null:surfaces=_floor_surface_snapshot()
	for x:float in [-half.x,0.0,half.x]:
		for z:float in [-half.y,0.0,half.y]:
			var height:float=_floor_height(at+Vector3(x,0,z),surfaces)
			if not is_finite(height):return INF
			low=minf(low,height);high=maxf(high,height)
	# Small authored board/tile details differ by millimetres. A raised floor
	# edge must support every corner/edge of the ceramic at the same level.
	return high if high-low<=.012 else INF

func _floor_grid(level:int,region:Rect2i) -> Array[Vector3]:
	var navigation:LifeLotNavigation=app.world.lot_navigation
	var cacheable:bool=not app.world.construction.building_state.is_empty()
	if not cacheable:
		# The legacy compatibility grid can change without a lot generation.
		_floor_grid_candidates.clear();_floor_grid_navigation=null
	elif navigation!=_floor_grid_navigation or navigation.generation!=_floor_grid_generation or region!=_floor_grid_region:
		_floor_grid_candidates.clear();_floor_grid_navigation=navigation
		_floor_grid_generation=navigation.generation;_floor_grid_region=region
	if cacheable and _floor_grid_candidates.has(level):return _floor_grid_candidates[level].duplicate()
	var result:Array[Vector3]=[]
	for x:int in range(region.position.x,region.end.x):
		for z:int in range(region.position.y,region.end.y):
			var at:=Vector3(x*.25,Building.level_y(level),z*.25)
			if _floor_navigation_clear(at):result.append(at)
	if cacheable:_floor_grid_candidates[level]=result
	return result.duplicate()

func _floor_slot(from:Vector3,value:Dictionary) -> Vector3:
	var level:int=_floor_level(from)
	if level<0:return Vector3.INF
	var candidates:Array[Vector3]=[Vector3(from.x,Building.level_y(level),from.z)]
	var region:Rect2i=app.world.navigation.region
	candidates.append_array(_floor_grid(level,region))
	candidates.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.distance_squared_to(from)<b.distance_squared_to(from))
	var surfaces:Variant=null
	for at:Vector3 in candidates:
		var cell:Vector2i=Vector2i(roundi(at.x*4),roundi(at.z*4))
		if not region.has_point(cell) or not _floor_navigation_clear(at):continue
		if surfaces==null:surfaces=_floor_surface_snapshot()
		var height:float=_floor_support(at,_footprint(value),surfaces)
		if not is_finite(height):continue
		var clear:bool=true
		# Leave the complete dish outside visible feet, including its carrier.
		# A supported floor point underneath a Lifelet is not a set-down place.
		var body_gap:Vector2=_footprint(value)+Vector2(.30,.30)
		for person:LifeActor in app.world.actors.values():
			if not is_instance_valid(person) or not person.visible or not _same_floor_space(at,person.position):continue
			if absf(at.x-person.position.x)<body_gap.x and absf(at.z-person.position.z)<body_gap.y:clear=false;break
		if not clear:continue
		for other:Dictionary in food().batches+food().portions:
			if str(other.id)==str(value.id) or str(other.venue)!=app.current_venue or not str(other.host).is_empty() or not str(other.owner).is_empty() or _food_level(other)!=level:continue
			if not other.has("batch") and int(other.remaining)<=0:continue
			var gap:Vector2=_footprint(value)+_footprint(other)+Vector2(.01,.01)
			if absf(at.x-float(other.position[0]))<gap.x and absf(at.z-float(other.position[2]))<gap.y:clear=false;break
		if clear:at.y=height;return at
	# No fallback may silently overlap a wall or hang over an unsupported edge.
	return Vector3.INF

func _settle_food(value:Dictionary,from:Vector3) -> bool:
	# Keep a legitimate current setting. Otherwise set food down within reach,
	# then fall back to an unoccupied visible floor point, never hand height.
	var level:int=_floor_level(from)
	if level<0:return false # A caller must reach a real landing before releasing custody.
	var host:Dictionary=item(str(value.host))
	var offset:Array=value.get("offset",[0,0,0])
	var local:Vector3=Vector3(float(offset[0]),float(offset[1]),float(offset[2]))
	if not host.is_empty() and _host_level(host)==level and SURFACE_HEIGHTS.has(str(host.kind)) and _surface_clear(host,local,_footprint(value),str(value.id)):
		var position:Vector3=host.node.to_global(local);value.position=[position.x,position.y,position.z]
		return true
	var near:Array=[]
	for candidate:Dictionary in app.world.items:
		if _host_level(candidate)!=level or not SURFACE_HEIGHTS.has(str(candidate.kind)):continue
		var slot:Vector3=_surface_slot(candidate,_footprint(value),str(value.id))
		if not slot.is_finite():continue
		var position:Vector3=candidate.node.to_global(slot)
		if Vector2(position.x-from.x,position.z-from.z).length()<=.85:near.append({"host":candidate,"slot":slot,"position":position})
	near.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.position.distance_squared_to(from)<b.position.distance_squared_to(from))
	if not near.is_empty():
		var selected:Dictionary=near[0];value.host=str(selected.host.id)
		value.offset=[selected.slot.x,selected.slot.y,selected.slot.z]
		value.position=[selected.position.x,selected.position.y,selected.position.z]
	else:
		var at:Vector3=_floor_slot(from,value)
		if not at.is_finite():
			return false
		value.host="";value.offset=[0.0,0.0,0.0];value.position=[at.x,at.y,at.z]
	if value.has("batch"):value.seat=""

	return true

func autonomous_cleanup_choice(sim:LifeSim,excluded:Array=[]) -> Dictionary:
	if not sim.action_queue.is_empty() or sim.is_away() or not food().carried_by(member_id(sim)).is_empty():return {}
	var person:LifeActor=actor(member_id(sim))
	if not is_instance_valid(person):return {}
	var candidates:Array=[]
	for plate:Dictionary in food().portions:
		if str(plate.venue)!=app.current_venue or not str(plate.owner).is_empty() or excluded.has(str(plate.id)):continue
		if str(plate.storage)!="dirty" and now()<float(plate.expires):continue
		var reserved:bool=false
		for member:Dictionary in app.household.members:
			for action:Dictionary in member.sim.action_queue:
				if str(action.id)=="clean_plate" and str(action.get("meal_source",action.target_id))==str(plate.id):reserved=true
		if reserved or not action_availability(sim,"clean_plate",str(plate.id)).is_empty():continue
		var target:Dictionary=item(str(plate.id))
		if target.is_empty():continue
		var at:Vector3=app.world.approach(target)
		if app.world.path_to(person.position,at).is_empty():continue
		candidates.append({"id":"clean_plate","target_id":str(plate.id),"position":at})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.position.distance_squared_to(person.position)<b.position.distance_squared_to(person.position))
	return candidates[0] if not candidates.is_empty() else {}

func _chair_table(chair:Dictionary) -> Dictionary:
	var table:Dictionary={};var nearest:float=1.6
	for candidate:Dictionary in app.world.items:
		if str(candidate.kind)!="dining" or _host_level(candidate)!=_host_level(chair):continue
		var distance:float=candidate.node.position.distance_to(chair.node.position)
		if distance<nearest:table=candidate;nearest=distance
	if table.is_empty():return {}
	var direction:Vector3=(table.node.position-chair.node.position).normalized()
	if chair.node.global_basis.z.dot(direction)<.65:return {}
	return table

func standing_geometry_clear(at:Vector3) -> bool:
	var level:int=_floor_level(at)
	if level<0:return false
	var cell:=Vector2i(roundi(at.x*4),roundi(at.z*4))
	if not at.is_equal_approx(Vector3(cell.x*.25,Building.level_y(level),cell.y*.25)):return false
	return _floor_navigation_clear(at,Vector2(.30,.30)) and is_finite(_floor_support(at,Vector2(.30,.30)))

func _standing_clear(person:String,at:Vector3) -> bool:
	if not standing_geometry_clear(at):return false
	var prior_reservation:bool=bool(activity_for(person).get("meal_standing",false))
	for other_id:String in app.world.actors:
		if other_id==person:continue
		var other_actor:Node3D=app.world.actors[other_id]
		if not is_instance_valid(other_actor) or not other_actor.visible:continue
		var other_sim:LifeSim=app.household.member_sim(other_id)
		var other:Dictionary=activity_for(other_id)
		var clearance:float=1.15 if str(other.get("id","")) in ["nap","sleep"] else .85
		if _same_floor_space(at,other_actor.position) and Vector2(at.x-other_actor.position.x,at.z-other_actor.position.z).length()<clearance:return false
		if not other.is_empty() and (not is_instance_valid(other_sim) or not other_sim.is_away()) and (not prior_reservation or str(other.get("phase",""))=="active" or bool(other.get("meal_standing",false))):
			for target:Vector3 in _activity_places(other):
				if _same_floor_space(at,target) and Vector2(at.x-target.x,at.z-target.z).length()<clearance:return false
			var displayed:Variant=other_actor.get("_activity_anchor")
			if displayed is Dictionary and displayed.get("position") is Vector3:
				var shown:Vector3=displayed.position
				if _same_floor_space(at,shown) and Vector2(at.x-shown.x,at.z-shown.z).length()<clearance:return false
		var motion:Dictionary=app.motion_states.get(other_id,{})
		var waiting:Vector3=motion.get("wait_destination",Vector3.INF)
		if bool(motion.get("waiting",false)) and _same_floor_space(at,waiting) and Vector2(at.x-waiting.x,at.z-waiting.z).length()<.85:return false
	for other:Dictionary in food().batches+food().portions:
		if str(other.venue)!=app.current_venue or not str(other.host).is_empty() or not str(other.owner).is_empty() or _food_level(other)!=_floor_level(at):continue
		if not other.has("batch") and int(other.remaining)<=0:continue
		var half:Vector2=_footprint(other)+Vector2(.30,.30)
		if absf(at.x-float(other.position[0]))<half.x and absf(at.z-float(other.position[2]))<half.y:return false
	return true

func _activity_places(action:Dictionary) -> Array[Vector3]:
	var places:Array[Vector3]=[action.get("target_position",Vector3.INF)]
	var target:Dictionary=item(str(action.get("target_id","")))
	if not target.is_empty() and str(target.kind) not in ["meal","plate"]:
		# Empty landmarks avoid creating a child desk booster during admission.
		var anchor:Dictionary=app.world.activity_anchor(target,str(action.get("id","")))
		if anchor.get("position") is Vector3:places.append(anchor.position)
	return places

func standing_place_blocks(person:String,action:Dictionary) -> bool:
	if bool(action.get("meal_standing",false)):return false
	var clearance:float=1.15 if str(action.get("id","")) in ["nap","sleep"] else .85
	for member:Dictionary in activity_records():
		if str(member.id)==person:continue
		var other:Dictionary=member.action
		if not bool(other.get("meal_standing",false)) or str(other.get("phase","")) not in ["approach","active"]:continue
		var reserved:Vector3=other.target_position
		for at:Vector3 in _activity_places(action):
			if _same_floor_space(at,reserved) and Vector2(at.x-reserved.x,at.z-reserved.z).length()<clearance:return true
	return false

func _standing_route(person:String,at:Vector3) -> bool:
	if not _standing_clear(person,at):return false
	var route:PackedVector3Array=_dining_route(person,at)
	return not route.is_empty() and route[-1].is_equal_approx(at)

func _dining_route(person:String,at:Vector3)->PackedVector3Array:
	var visit:LifeHomeVisit=_home_visit()
	if app.household.member_sim(person)==null and visit!=null and visit.owns(person):return visit._route(actor(person).position,at,person)
	return app.world.path_to(actor(person).position,at)

func _standing_slot(person:String) -> Vector3:
	var from:Vector3=actor(person).position
	var level:int=_floor_level(from)
	if level<0:return Vector3.INF
	var candidates:Array[Vector3]=[]
	var origin:=Vector2i(roundi(from.x*4),roundi(from.z*4))
	for x:int in range(-12,13):
		for z:int in range(-12,13):
			var at:=Vector3((origin.x+x)*.25,Building.level_y(level),(origin.y+z)*.25)
			if at.distance_to(from)<=3.0:candidates.append(at)
	candidates.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.distance_squared_to(from)<b.distance_squared_to(from))
	for at:Vector3 in candidates:
		if _standing_route(person,at):return at
	return Vector3.INF

func _choose_seat(person:String,action:Dictionary) -> bool:
	if bool(action.get("meal_standing",false)) and _standing_route(person,action.target_position):return true
	action.erase("meal_standing")
	var chairs:Array=[]
	for candidate:Dictionary in app.world.items:
		if str(candidate.kind)!="chair" or _chair_table(candidate).is_empty():continue
		if app.household.member_sim(person)==null and _host_level(candidate)!=0:continue
		var occupied:bool=false
		for member:Dictionary in activity_records():
			if member.id==person:continue
			var other:Dictionary=member.action
			if str(other.get("meal_seat",""))==str(candidate.id) or str(other.get("target_id",""))==str(candidate.id):occupied=true
		for plate:Dictionary in food().portions:
			if str(plate.seat)==str(candidate.id) and str(plate.owner)!=person:occupied=true
		var table:Dictionary=_chair_table(candidate)
		if not _surface_clear(table,_plate_offset(candidate,table),LifeMeals.PLATE_HALF_SIZE,str(action.get("meal_plate",""))):occupied=true
		if not occupied and not _dining_route(person,app.world.approach(candidate)).is_empty():chairs.append(candidate)
	chairs.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.node.position.distance_squared_to(actor(person).position)<b.node.position.distance_squared_to(actor(person).position))
	if not chairs.is_empty():
		action.meal_seat=str(chairs[0].id);action.target_id=str(chairs[0].id);action.target_position=app.world.approach(chairs[0])
		return true
	else:
		var at:Vector3=_standing_slot(person)
		if not at.is_finite():return false
		action.meal_seat="";action.meal_standing=true;action.target_id=str(action.meal_plate)
		action.target_position=at
		return true

func eating_anchor(person:String,action:Dictionary) -> Dictionary:
	var chair:Dictionary=item(str(action.get("meal_seat","")))
	if not chair.is_empty():
		var table:Dictionary=_chair_table(chair)
		if not table.is_empty():
			var seated:Dictionary=app.world.activity_anchor(chair,"eat_meal",actor(person).get_body_landmarks())
			var toward:Vector3=(table.node.position-chair.node.position).normalized()
			var local:Vector3=_plate_offset(chair,table)
			if str(actor(person).profile.get("age_stage",""))=="child":
				app.world._show_desk_booster(chair.node)
				seated.position+=Vector3(0,.18,0)+toward*.10
			seated.merge({"plate_position":table.node.to_global(local),"table_id":str(table.id)},true)
			return seated
	var at:Vector3=actor(person).position
	return {"position":at,"yaw":actor(person).rotation.y,"kind":"standing","plate_position":actor(person).meal_carry_transform().origin,"table_id":""}

func consume(sim:LifeSim,action:Dictionary,minutes:float) -> void:
	var person:String=member_id(sim)
	var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
	if plate.is_empty() or now()>=float(plate.expires):_stop(sim,"This meal has spoiled.");return
	var gained:float=food().eat(str(plate.id),person,minutes,(sim.day-1)*1440.0+sim.minutes)
	sim.needs.hunger=minf(100.0,float(sim.needs.hunger)+gained)
	record_company(person,plate,minutes)

func record_company(person:String,plate:Dictionary,minutes:float)->void:
	if str(plate.host).is_empty():return
	for other:Dictionary in food().portions:
		if str(other.id)==str(plate.id) or str(other.storage)!="table" or str(other.host)!=str(plate.host) or str(other.owner).is_empty():continue
		var current:Dictionary=activity_for(str(other.owner))
		if str(current.get("id",""))!="eat_meal" or str(current.get("phase",""))!="active":continue
		var sim:LifeSim=app.household.member_sim(person)
		if is_instance_valid(sim):sim.needs.social=minf(100.0,float(sim.needs.social)+minutes*.35)
		plate.shared_minutes=minf(LifeMeals.EATING_MINUTES,float(plate.shared_minutes)+minutes)
		if not plate.company.has(str(other.owner)):plate.company.append(str(other.owner))
		break

func finished(sim:LifeSim,action:Dictionary) -> void:
	var person:String=member_id(sim)
	if action.id=="cook":
		var batch:Dictionary=food().create_batch(str(action.get("recipe","garden_skillet")),person,clampi(int(sim.skills.cooking.level)/3+1,1,3),app.current_venue,now())
		if not batch.is_empty():_prepend(sim,"serve_meal",str(batch.id),{"meal_source":str(batch.id)})
	elif action.id=="serve_meal":
		var target:Dictionary=item(str(action.target_id))
		var batch:Dictionary=food().batch(str(action.meal_source))
		var slot:Vector3=_surface_slot(target,LifeMeals.PLATTER_HALF_SIZE,str(batch.id)) if not target.is_empty() and SURFACE_HEIGHTS.has(str(target.kind)) else Vector3.INF
		var position:Vector3=target.node.to_global(slot) if slot.is_finite() else actor(person).position
		food().set_batch_location(str(batch.id),"surface",str(target.id) if slot.is_finite() else "",position,now())
		if slot.is_finite():batch.offset=[slot.x,slot.y,slot.z]
		else:_settle_food(batch,actor(person).position)
		if not batch.is_empty():sim._emit_notice("Dinner is ready: %d servings of %s." % [int(batch.remaining),str(LifeMeals.RECIPES[str(batch.recipe)].label).to_lower()])
		if float(sim.needs.hunger)<75:_prepend(sim,"eat_meal",str(action.meal_source),{})
	elif action.id=="eat_meal":
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		if not plate.is_empty():
			if float(plate.shared_minutes)>=5:
				sim.add_moodlet("Around the table","Happy","Good food and familiar company.",180,2)
				for partner:String in plate.company:
					if sim.relationships.has(partner):sim.relationships[partner].friendship=minf(100,float(sim.relationships[partner].friendship)+4)
			food().finish_portion(str(plate.id))
			_settle_food(plate,actor(person).position)
	elif action.id=="store_meal":
		var fridge:Dictionary=item(str(action.target_id))
		if not fridge.is_empty():
			food().set_batch_location(str(action.meal_source),"fridge",str(fridge.id),fridge.node.position,now())
			food().batch(str(action.meal_source)).offset=[0.0,0.0,0.0]
	elif action.id=="discard_meal":
		food().set_batch_location(str(action.meal_source),"surface","",actor(person).position,now())
		food().discard_batch(str(action.meal_source))
	elif action.id=="clean_plate":food().clean_portion(str(action.meal_source),person)
	_reconcile_guest_offer()
	sync_due=true

func _prepend(sim:LifeSim,id:String,target:String,metadata:Dictionary) -> void:
	var action:Dictionary=sim.get_action_definition(id)
	action.merge({"target_id":target,"target_position":Vector3.ZERO,"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":true},true)
	action.merge(metadata,true)
	sim.action_queue.push_front(action)

func canceled(sim:LifeSim,action:Dictionary) -> void:
	if str(action.id) not in ACTIONS:return
	var person:String=member_id(sim)
	var carried:Dictionary=food().carried_by(person)
	var owned_id:String=str(action.get("meal_plate",action.get("meal_source","")))
	if not carried.is_empty() and str(carried.id)==owned_id and is_same(sim.get_current_action(),action) and is_instance_valid(actor(person)):
		var traversal:LifeTraversal=app.get("traversal")
		if traversal!=null and traversal.busy(person):
			traversal.cancel(person)
			traversal.routes[person].custody=str(carried.id)
		else:
			food().release_member(person,actor(person).position)
			_settle_food(carried,actor(person).position)
	sync_due=true

func release_stair_custody(person:String,id:String) -> bool:
	var carrier:LifeActor=actor(person)
	if not is_instance_valid(carrier) or not app.traversal.busy(person):return false
	var route:Dictionary=app.traversal.routes[person]
	if str(route.phase)!="clear" or str(route.get("custody",""))!=id or carrier.position.distance_to(route.clear)>.00001:return false
	var held:Dictionary=food().carried_by(person)
	if held.is_empty() or str(held.id)!=id or str(held.storage)!="carried" or str(held.venue)!=app.current_venue:return false
	# Find a supported local placement without altering the live ledger. If the
	# landing cannot accept it, keep both food and staircase ownership intact.
	var candidate:Dictionary=held.duplicate(true)
	candidate.owner="";candidate.host="";candidate.offset=[0.0,0.0,0.0]
	candidate.storage="dirty" if candidate.has("batch") and float(candidate.progress)>=1.0 else "surface"
	if candidate.has("batch"):candidate.seat=""
	if not _settle_food(candidate,carrier.position):return false
	held.merge(candidate,true)
	route.custody=""
	sync_due=true
	return true

func call_to_meal(target:String) -> int:
	var count:int=0
	for member:Dictionary in app.household.members:
		var sim:LifeSim=member.sim
		if not sim.action_queue.is_empty() or float(sim.needs.hunger)>85 or not is_instance_valid(actor(str(member.id))) or not actor(str(member.id)).visible:continue
		if float(sim.needs.energy)<12 or float(sim.needs.bladder)<12:continue
		if sim.queue_action("eat_meal",target,Vector3.ZERO):count+=1
	var visit:LifeHomeVisit=_home_visit()
	if visit!=null and visit.meal.offer(target):count+=1
	return count

func _mesh_view(value:Dictionary) -> Node3D:
	var recipe:String=str(food().batch(str(value.batch)).recipe) if value.has("batch") else str(value.recipe)
	var scene:PackedScene=load(LifeMeals.model_path(recipe,value.has("batch")))
	var root:Node3D=scene.instantiate()
	var body:StaticBody3D=StaticBody3D.new();body.name="FoodPicking";body.collision_layer=2;body.set_meta("item_id",str(value.id));root.add_child(body)
	var shape:CollisionShape3D=CollisionShape3D.new();var bounds:BoxShape3D=BoxShape3D.new()
	bounds.size=Vector3(.3,.10,.3) if value.has("batch") else Vector3(.5,.12,.335)
	shape.shape=bounds;shape.position.y=.04;body.add_child(shape)
	return root

func sync_world(reconcile:bool=true) -> void:
	if not is_instance_valid(app.world.house):return
	sync_oven_presentations()
	if reconcile:
		_reconcile_guest_offer()
		_reconcile_dining_furniture()
	var present:Dictionary={}
	var rebuilt:bool=false
	for value:Dictionary in food().batches+food().portions:
		if str(value.venue)!=app.current_venue:continue
		var key:String=str(value.id);present[key]=true
		if not views.has(key) or not is_instance_valid(views[key]):
			var node:Node3D=_mesh_view(value);node.name=key;app.world.house.add_child(node);views[key]=node;rebuilt=true
			app.world.items.append({"id":key,"kind":"plate" if value.has("batch") else "meal","label":"Plate" if value.has("batch") else str(LifeMeals.RECIPES[str(value.recipe)].label),"node":node,"size":Vector2(.35,.35),"transient_food":true})
		var host:Dictionary=item(str(value.host))
		if reconcile and not host.is_empty() and str(value.storage) in ["surface","fridge","dirty","table"]:
			var offset:Array=value.get("offset",[0.0,float(SURFACE_HEIGHTS.get(str(host.kind),.847)),0.0])
			var at:Vector3=host.node.to_global(Vector3(float(offset[0]),float(offset[1]),float(offset[2])))
			value.position=[at.x,at.y,at.z]
		elif reconcile and host.is_empty() and not str(value.host).is_empty() and str(value.storage)!="carried" and not _pending_furniture(str(value.host)):
			var level:int=_food_level(value)
			if level<0:continue
			var at:=Vector3(float(value.position[0]),Building.level_y(level),float(value.position[2]))
			if value.has("batch"):
				value.position=[at.x,at.y,at.z];value.host="";value.seat=""
			else:food().set_batch_location(key,"surface","",at,now())
			if str(value.owner).is_empty():_settle_food(value,at)
		if reconcile and str(value.owner).is_empty() and str(value.host).is_empty() and str(value.storage) in ["surface","dirty"]:
			var at:Vector3=Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))
			var support:float=_floor_support(at,_footprint(value))
			if not is_finite(support) or absf(at.y-support)>.025:_settle_food(value,at)
		var view:Node3D=views[key]
		view.visible=str(value.storage)!="fridge" and not _pending_furniture(str(value.host)) and (value.has("batch") or int(value.remaining)>0)
		if not str(value.owner).is_empty() and (str(value.storage)=="carried" or (str(value.storage)=="table" and str(value.host).is_empty())) and is_instance_valid(actor(str(value.owner))):
			view.global_transform=actor(str(value.owner)).meal_carry_transform()
		else:
			view.global_position=Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))
			view.global_basis=host.node.global_basis if not host.is_empty() else Basis.IDENTITY
		var body:StaticBody3D=view.get_node("FoodPicking") if view.has_node("FoodPicking") else view.get_child(view.get_child_count()-1)
		var level:int=_food_level(value,host)
		var held:bool=not str(value.owner).is_empty() and (str(value.storage)=="carried" or (str(value.storage)=="table" and str(value.host).is_empty()))
		var mask:int=(LifeWorld.VIEW_ACTOR_GROUND|LifeWorld.VIEW_ACTOR_UPPER) if level<0 else ((LifeWorld.VIEW_ACTOR_GROUND if level==0 else LifeWorld.VIEW_ACTOR_UPPER) if held else (LifeWorld.VIEW_GROUND if level==0 else LifeWorld.VIEW_UPPER))
		app.world._assign_layers(view,mask)
		var entry:Dictionary=item(key)
		if level>=0:entry["level"]=level
		else:entry.erase("level")
		body.collision_layer=(LifeWorld.PICK_GROUND if level==0 else LifeWorld.PICK_UPPER) if level>=0 and view.visible and str(value.storage) not in ["carried","table"] else 0
		var food_view:Node3D=view.find_child("Food",true,false)
		food_view.visible=not value.has("batch") or float(value.progress)<1.0
		if value.has("batch"):food_view.scale=Vector3(1.0,maxf(.05,1.0-float(value.progress)*.85),1.0)
	for key:String in views.keys():
		if not present.has(key) or not is_instance_valid(views[key]):
			if is_instance_valid(views[key]):views[key].queue_free()
			views.erase(key)
			app.world.items=app.world.items.filter(func(entry:Dictionary)->bool:return str(entry.id)!=key)
	var signature:String=JSON.stringify(present.keys())
	_sync_table_settings()
	if signature!=revision or rebuilt:
		revision=signature
		app.household.register_targets(app.world.simulation_targets(),reconcile)
	sync_due=false

func _sync_table_settings() -> void:
	# The authored fruit centerpiece belongs on an otherwise unused table.
	# Clear it while persistent food/dishes occupy that same surface.
	var occupied:Dictionary={}
	for value:Dictionary in food().batches+food().portions:
		if str(value.venue)==app.current_venue and str(value.storage) in ["table","surface","dirty"] and (value.has("batch") or int(value.remaining)>0):occupied[str(value.host)]=true
	for table:Dictionary in app.world.items:
		if str(table.kind)!="dining":continue
		for decoration:Node in table.node.find_children("Fruit*","Node3D",true,false):
			decoration.visible=not occupied.has(str(table.id))


func present_actor(person:String) -> void:
	var lifelet:LifeActor=actor(person)
	if not is_instance_valid(lifelet):return
	var held:Dictionary=food().carried_by(person)
	lifelet.meal_presentation={"carrying":not held.is_empty() and str(held.storage)=="carried","platter":not held.is_empty() and not held.has("batch")}
	if not held.is_empty() and not held.has("batch"):lifelet.meal_presentation["grips"]=carry_grips_for_recipe(str(held.recipe))
	var current:Dictionary=app.household.member_sim(person).get_current_action()
	lifelet.cooking_presentation={"recipe":str(current.get("recipe","garden_skillet")),"progress":float(current.get("progress",0))} if str(current.get("id",""))=="cook" else {}
	if str(current.get("id",""))=="cook" and str(current.get("recipe",""))=="harvest_bake":
		lifelet.cooking_presentation["oven_suspended"]=_pending_furniture(str(current.target_id))
	var oven_state:Dictionary=oven_presentation(person)
	if not oven_state.is_empty():
		lifelet.cooking_presentation.merge({"oven":item(str(oven_state.target_id)).node,"oven_interior":bool(oven_state.inside),"progress":float(oven_state.progress)},true)

func oven_presentation(person:String) -> Dictionary:
	# Only the current paid instruction owns preparation. No animator cache or
	# separate job advances this state while the cook is walking or paused.
	var current:Dictionary=app.household.member_sim(person).get_current_action()
	if str(current.get("id",""))!="cook" or str(current.get("recipe",""))!="harvest_bake" or not bool(current.get("paid",false)):return {}
	if str(current.get("phase","")) not in ["active","approach"]:return {}
	var target:String=str(current.target_id)
	var oven:Dictionary=item(target)
	if _pending_furniture(target) or oven.is_empty() or str(oven.kind)!="stove":return {}
	var progress:float=clampf(float(current.elapsed)/float(current.duration),0.0,1.0)
	return {"person":person,"target_id":target,"recipe":"harvest_bake","progress":progress,"inside":LifeOvenSequence.inside(progress)}

func sync_oven_presentations() -> void:
	var states:Dictionary={}
	for member:Dictionary in app.household.members:
		var state:Dictionary=oven_presentation(str(member.id))
		if not state.is_empty():states[str(state.target_id)]=state
	app.world.update_oven_presentations(states)


func show_leftovers(fridge_id:String) -> void:
	app._begin_pause_overlay()
	app.dismiss_layer()
	app.card(Vector2(410,165),Vector2(620,565),app.P.WHITE,22,app.overlay)
	app.text_label("Something for later",Vector2(442,189),Vector2(544,51),32,app.P.INK,true,app.overlay)
	app.paragraph("Choose a fresh serving from the fridge. Leftovers keep longer, but they still spoil.",Vector2(443,249),Vector2(545,59),16,app.P.MUTED,app.overlay)
	var scroll:ScrollContainer=ScrollContainer.new();app.rect(scroll,Vector2(441,331),Vector2(551,285),app.overlay)
	var column:VBoxContainer=VBoxContainer.new();column.add_theme_constant_override("separation",12);scroll.add_child(column)
	var shown:int=0
	for batch:Dictionary in food().batches:
		if str(batch.storage)!="fridge" or str(batch.host)!=fridge_id or str(batch.venue)!=app.current_venue or int(batch.remaining)<=0:continue
		shown+=1
		var row:Button=Button.new();row.custom_minimum_size=Vector2(529,64)
		var fresh:bool=now()<float(batch.expires)
		row.text="%s · %d servings\n%s" % [str(LifeMeals.RECIPES[str(batch.recipe)].label),int(batch.remaining),("Fresh for about %d hours" % maxi(1,ceili((float(batch.expires)-now())/60.0))) if fresh else "Spoiled"]
		row.disabled=false
		if not fresh:row.text+=" · Clear spoiled food"
		row.pressed.connect(func():
			app.close_overlay()
			var target:Dictionary=item(str(batch.id))
			if not target.is_empty():app.queue_interaction(target,"eat_meal" if fresh else "discard_meal"))
		column.add_child(row)
	if shown==0:app.paragraph("No leftovers yet. Cook a meal and put away the extra servings.",Vector2(452,370),Vector2(518,92),20,app.P.MUTED,app.overlay)
	app.button("Back to life",Vector2(734,657),Vector2(256,43),app.close_overlay,true,app.overlay)


func action_title(action:Dictionary) -> String:
	if str(action.get("id",""))=="cook":
		var host_available:bool=not _pending_furniture(str(action.target_id)) and not item(str(action.target_id)).is_empty()
		var preparing:bool=str(action.get("phase",""))=="active" and host_available
		# Loading revalidates routes before play. A paid cook already at its
		# unchanged appliance still displays the preparation restored on pause.
		if not preparing and bool(action.get("paid",false)) and host_available:
			for member:Dictionary in app.household.members:
				if is_same(member.sim.get_current_action(),action):
					var lifelet:LifeActor=actor(str(member.id))
					preparing=is_instance_valid(lifelet) and lifelet.position.distance_to(action.target_position)<.02
					break
		return ("Preparing " if preparing else "Getting ready to cook ")+str(LifeMeals.RECIPES[str(action.get("recipe","garden_skillet"))].label).to_lower()
	if str(action.get("id","")) not in ACTIONS:return ""
	var approaching:bool=str(action.get("phase",""))=="approach"
	match str(action.id):
		"serve_meal":return "Bringing dinner to the table" if approaching else "Dinner is ready"
		"eat_meal":
			if str(action.get("meal_stage",""))=="pickup":return "Getting a serving"
			return "Finding a place to eat" if approaching else "Enjoying a meal"
		"store_meal":return "Putting away leftovers"
		"clean_plate":return "Taking a plate to the sink" if approaching else "Washing a plate"
		"discard_meal":return "Clearing away the meal"
	return ""


func company_label(person:String) -> String:
	var plate:Dictionary=food().carried_by(person)
	if plate.is_empty() or str(plate.storage)!="table" or str(plate.host).is_empty():return ""
	var names:Array[String]=[]
	for other:Dictionary in food().portions:
		if str(other.owner).is_empty() or str(other.owner)==person or str(other.storage)!="table" or str(other.host)!=str(plate.host):continue
		var companion:LifeSim=app.household.member_sim(str(other.owner))
		if activity_for(str(other.owner)).get("phase")=="active":names.append(str(companion.character.name) if companion else str(LifeResidents.PEOPLE.get(str(other.owner),{}).get("name","Guest")))
	return "AT THE TABLE WITH "+", ".join(names).to_upper() if not names.is_empty() else ""


func _reconcile_dining_furniture() -> void:
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if action.get("id")!="eat_meal" or action.get("phase")!="active" or str(action.get("meal_seat","")).is_empty():continue
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		# Move temporarily removes furniture from the world. Preserve ownership
		# and progress until placement or cancel restores the same stable ID.
		if _pending_furniture(str(action.meal_seat)) or _pending_furniture(str(plate.get("host",""))):continue
		var chair:Dictionary=item(str(action.meal_seat))
		if not chair.is_empty() and not _chair_table(chair).is_empty():
			var anchor:Dictionary=eating_anchor(str(member.id),action)
			var host:Dictionary=item(str(anchor.table_id))
			food().put_portion(str(action.get("meal_plate","")),str(anchor.table_id),str(action.meal_seat),anchor.plate_position,true,host.node.to_local(anchor.plate_position))
			continue
		if not plate.is_empty():plate.storage="carried";plate.seat=""
		action.phase="approach"
		_choose_seat(str(member.id),action)
		member.sim._emit_action_started(action)


func show_recipes(target_id:String) -> void:
	app._begin_pause_overlay();app.dismiss_layer()
	app.card(Vector2(321,118),Vector2(798,664),app.P.WHITE,22,app.overlay)
	app.text_label("What’s cooking?",Vector2(352,140),Vector2(720,51),34,app.P.INK,true,app.overlay)
	app.paragraph("Cooking level %d · Choose a dish to share. Ingredients are paid for when cooking begins." % int(app.sim.skills.cooking.level),Vector2(355,206),Vector2(721,49),16,app.P.MUTED,app.overlay)
	var index:int=0
	for recipe:String in LifeMeals.RECIPES:
		var definition:Dictionary=LifeMeals.RECIPES[recipe]
		var row:Control=Control.new();row.name="RecipeRow_"+recipe
		app.rect(row,Vector2(349,276+index*135),Vector2(742,122),app.overlay)
		app.card(Vector2.ZERO,Vector2(742,122),Color("f3f4ed"),13,row)
		_recipe_preview(recipe,row)
		app.text_label(str(definition.label),Vector2(179,11),Vector2(533,30),23,app.P.INK,true,row)
		app.paragraph("%d servings  ·  §%d  ·  %d min  ·  Cooking %d" % [int(definition.servings),int(definition.cost),int(definition.duration),int(definition.skill)],Vector2(181,45),Vector2(533,25),13,app.P.INK,row)
		var reason:String=LifeMeals.recipe_error(recipe,int(app.sim.skills.cooking.level),str(app.sim.character.age_stage),app.sim.funds)
		if reason.is_empty():reason=action_availability(app.sim,"cook",target_id)
		app.paragraph(str(definition.description) if reason.is_empty() else reason,Vector2(181,79),Vector2(310,35),12,app.P.MUTED,row)
		var choose:Button=app.button("Cook "+str(definition.label).to_lower(),Vector2(509,78),Vector2(218,34),queue_recipe.bind(target_id,recipe),true,row)
		choose.name="Recipe_"+recipe;choose.disabled=not reason.is_empty();choose.tooltip_text=reason
		index+=1
	app.button("Back to life",Vector2(866,718),Vector2(221,39),app.close_overlay,false,app.overlay)

func queue_recipe(target_id:String,recipe:String) -> void:
	var target:Dictionary=item(target_id)
	if target.is_empty():app.show_notice("This kitchen item is no longer here.");return
	if app.sim.is_away():app.show_notice("This Lifelet will be available after coming home.");return
	if app.sim.queue_action("cook",target_id,app.world.approach(target),recipe):
		app.close_overlay();app.refresh_hud()

func _recipe_preview(recipe:String,parent:Control) -> void:
	var viewport:SubViewport=SubViewport.new();viewport.name="DishPreview";viewport.size=Vector2i(300,204)
	viewport.own_world_3d=true;viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	parent.add_child(viewport)
	var model:Node3D=load(LifeMeals.model_path(recipe)).instantiate();viewport.add_child(model)
	var camera:Camera3D=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.42
	viewport.add_child(camera);camera.position=Vector3(.33,.48,.57);camera.look_at(Vector3(0,.035,0));camera.current=true
	var light:DirectionalLight3D=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-30,0);light.light_energy=.8;viewport.add_child(light)
	var world_environment:WorldEnvironment=WorldEnvironment.new();world_environment.environment=Environment.new()
	world_environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world_environment.environment.ambient_light_color=Color("fff4de");world_environment.environment.ambient_light_energy=.35;world_environment.environment.tonemap_mode=Environment.TONE_MAPPER_REINHARDT
	viewport.add_child(world_environment)
	var picture:TextureRect=TextureRect.new();picture.texture=viewport.get_texture();picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.rect(picture,Vector2(9,9),Vector2(153,104),parent)


func carry_grips_for_recipe(recipe:String)->Dictionary:
	if _carry_grips_cache.has(recipe):return _carry_grips_cache[recipe].duplicate()
	if not LifeMeals.RECIPES.has(recipe):return {}
	var model:Node3D=load(LifeMeals.model_path(recipe,false)).instantiate()
	var contacts:Dictionary={}
	for side:String in ["L","R"]:
		var marker:Node3D=model.find_child("GripLeft" if side=="L" else "GripRight",true,false)
		if not is_instance_valid(marker):continue
		var point:Vector3=Vector3.ZERO;var cursor:Node3D=marker
		while cursor!=model:
			point=cursor.transform*point;cursor=cursor.get_parent() as Node3D
		contacts[side]=point
	model.free()
	_carry_grips_cache[recipe]=contacts
	return contacts.duplicate()
