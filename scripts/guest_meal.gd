extends RefCounted
class_name LifeGuestMeal
## A visit owns one ground-floor meal; food remains in the household ledger.
var _visit:WeakRef
var visit:LifeHomeVisit:
	get:return _visit.get_ref()
var app:Node:
	get:return visit.app
var state:Dictionary:
	get:return visit.state.get("meal",{})
func _init(owner_visit:LifeHomeVisit)->void:_visit=weakref(owner_visit)
func active()->bool:return not state.is_empty()
func person()->String:return str(visit.state.get("guest",""))
func body()->LifeActor:return app.world.actors.get(person())
func flow()->LifeMealFlow:return app.meal_flow
func plate()->Dictionary:return app.household.meals.portion(str(state.get("plate","")))
func activity()->Dictionary:
	if not active():return {}
	return {"id":"eat_meal","target_id":str(state.seat) if not str(state.seat).is_empty() else (str(state.plate) if not str(state.plate).is_empty() else str(state.source)),"target_position":state.target,"phase":"active" if str(state.phase)=="eating" else "approach","meal_source":state.source,"meal_plate":state.plate,"meal_seat":state.seat,"meal_standing":state.standing,"meal_stage":"pickup" if str(state.plate).is_empty() else "eat"}
func owns_place()->bool:return active() and not str(state.plate).is_empty() and str(state.phase) in ["to_place","eating","release"]
func offer(source:String)->bool:
	if not visit.active() or str(visit.state.phase)!="inside" or active() or not app.residents._speaker(person()).is_empty():return false
	var batch:Dictionary=app.household.meals.batch(source)
	if batch.is_empty() or str(batch.venue)!="home" or str(batch.storage)!="surface" or not str(batch.owner).is_empty() or int(batch.remaining)<=0 or visit._now()>=float(batch.expires):return false
	var entry:Dictionary=flow().item(source)
	if entry.is_empty() or flow()._food_level(batch,flow().item(str(batch.host)))!=0:return false
	var target:Vector3=app.world.approach(entry)
	var route:PackedVector3Array=visit._route(body().position,target,person())
	if route.is_empty():return false
	var token:int=int(visit.state.next_meal);visit.state.next_meal=token+1
	visit.state.meal={"token":token,"source":source,"plate":"","phase":"pickup","target":target,"seat":"","standing":false,"last_at":visit._now(),"retry_at":0.0,"reason":""}
	visit.state.route={"points":route,"point":0}
	app.residents.publish_targets(true)
	return true
func reconcile_source()->void:
	if not active() or str(state.phase)!="pickup":return
	var source:Dictionary=app.household.meals.batch(str(state.source))
	if source.is_empty() or str(source.storage)!="surface" or str(source.venue)!="home" or not str(source.owner).is_empty() or int(source.remaining)<=0 or visit._now()>=float(source.expires):
		cancel("The serving dish is no longer available for your guest.")

func cancel(reason:String)->void:
	if not active():return
	if not reason.is_empty():app.show_notice(reason)
	state.reason=reason;state.phase="release";state.target=body().position;state.retry_at=0.0
	visit.state.route={"points":PackedVector3Array([body().position]),"point":1}
	state.last_at=visit._now()
func _choose_place()->bool:
	var action:Dictionary=activity()
	if not flow()._choose_seat(person(),action):return false
	var route:PackedVector3Array=visit._route(body().position,action.target_position,person())
	if route.is_empty():return false
	state.seat=str(action.get("meal_seat",""));state.standing=bool(action.get("meal_standing",false));state.target=action.target_position;state.phase="to_place"
	visit.state.route={"points":route,"point":0}
	return true
func _pickup()->void:
	var batch:Dictionary=app.household.meals.batch(str(state.source))
	if batch.is_empty() or str(batch.storage)!="surface" or str(batch.venue)!="home" or flow()._food_level(batch,flow().item(str(batch.host)))!=0:
		cancel("The serving dish is no longer available.");return
	var item:Dictionary=flow().item(str(state.source))
	if item.is_empty():cancel("The serving dish is no longer available.");return
	var pickup:Vector3=app.world.approach(item)
	if body().position.distance_to(pickup)>.02:
		var route:PackedVector3Array=visit._route(body().position,pickup,person())
		if route.is_empty():cancel("Your guest cannot reach the serving dish.");return
		state.target=pickup;visit.state.route={"points":route,"point":0};return
	var serving:Dictionary=app.household.meals.claim(str(state.source),person(),visit._now())
	if serving.is_empty():cancel("There is no fresh serving left for your guest.");return
	# The stage and ledger binding change together; restore never calls claim.
	state.plate=str(serving.id);serving.guest_visit=int(visit.state.serial);serving.guest_meal=int(state.token)
	if not _choose_place():cancel("There is no clear place for your guest to eat.")
	flow().sync_due=true
func _begin_eating()->void:
	var action:Dictionary=activity()
	if not flow().guest_place_valid(action):
		if not _choose_place():cancel("Your guest's dining place is blocked.")
		return
	var serving:Dictionary=plate()
	if serving.is_empty() or visit._now()>=float(serving.expires):cancel("Your guest's serving has spoiled.");return
	var anchor:Dictionary=flow().eating_anchor(person(),action)
	var host:Dictionary=flow().item(str(anchor.table_id))
	app.household.meals.put_portion(str(serving.id),str(anchor.table_id),str(state.seat),anchor.plate_position,true,host.node.to_local(anchor.plate_position) if not host.is_empty() else Vector3.ZERO)
	state.phase="eating";state.last_at=visit._now();flow().sync_due=true
func _release()->bool:
	var serving:Dictionary=plate()
	if not serving.is_empty():
		var placed:Dictionary=serving.duplicate(true)
		placed.owner="";placed.seat="";placed.storage="dirty" if float(placed.progress)>=1 else "surface"
		placed.erase("guest_visit");placed.erase("guest_meal")
		if str(serving.storage)=="carried" or str(serving.host).is_empty():placed.host="";placed.offset=[0.0,0.0,0.0]
		if not flow()._settle_food(placed,body().position):return false
		serving.clear();serving.merge(placed,true)
	state.plate="";state.seat="";state.standing=false
	body().meal_presentation={};body().clear_activity_anchor();flow().sync_due=true
	if str(visit.state.phase)=="leaving":
		visit.state.meal={};visit.state.route={"points":PackedVector3Array(),"point":0}
		return true
	var destination:Vector3=visit.state.inside
	var route:PackedVector3Array=visit._route(body().position,destination,person())
	if not visit._clear(person(),destination) or route.is_empty():
		destination=visit._inside_point(person(),body().position)
		if destination.is_finite():route=visit._route(body().position,destination,person())
	if not destination.is_finite() or route.is_empty():
		# Keep a valid stationary return state until somebody makes room.
		state.phase="return";state.target=body().position;visit.state.route={"points":PackedVector3Array([body().position]),"point":1};return false
	visit.state.inside=destination;state.phase="return";state.target=destination;visit.state.route={"points":route,"point":0}
	return true
func consume_until(end:float)->void:
	if not active() or str(state.phase)!="eating":return
	var serving:Dictionary=plate()
	if serving.is_empty():return
	var start:float=float(state.last_at)
	var eligible_end:float=minf(end,float(serving.expires))
	var taken:float=minf(maxf(0.0,eligible_end-start),(1.0-float(serving.progress))*LifeMeals.EATING_MINUTES)
	if taken>0:
		# Freshness is checked at the eligible interval's start. Time after its
		# expiration or the visit deadline is never included in this amount.
		app.household.meals.eat(str(serving.id),person(),taken,start)
		flow().record_company(person(),serving,taken)
	state.last_at=maxf(start,end)
func tick(delta:float)->void:
	if not active():return
	reconcile_source()
	var now:float=visit._now()
	var phase:String=str(state.phase);var moving:bool=false
	if phase in ["pickup","to_place","return"]:
		var result:Dictionary=app.traversal._walk(person(),visit.state.route,delta*float(app.household.speed))
		moving=bool(result.moved);visit.state.blocked=bool(result.blocked)
		if int(visit.state.route.point)>=visit.state.route.points.size():
			if phase=="pickup":_pickup()
			elif phase=="to_place":_begin_eating()
			elif body().position.distance_to(visit.state.inside)<.00001:visit.state.meal={}
			elif now>=float(state.retry_at):
				if not _release():state.retry_at=now+5.0
	elif phase=="eating":
		var serving:Dictionary=plate()
		if serving.is_empty():cancel("Your guest's serving has spoiled.")
		else:
			consume_until(now)
			if float(serving.progress)>=1:cancel("")
			elif now>=float(serving.expires):cancel("Your guest's serving has spoiled.")
	if active() and str(state.phase)=="release" and now>=float(state.retry_at):
		if not _release():visit.state.blocked=true;state.retry_at=now+5.0
	if active():state.last_at=now;present()
	else:body().meal_presentation={};body().clear_activity_anchor()
	body().animate(delta,float(app.household.speed),moving,"eat_meal" if active() and str(state.phase)=="eating" else "")
	flow().sync_world()
func present(reconstruct:bool=false)->void:
	if not active():return
	var serving:Dictionary=plate()
	var held:bool=not serving.is_empty() and (str(serving.storage)=="carried" or (str(serving.storage)=="table" and str(serving.host).is_empty() and str(state.phase)!="eating"))
	body().meal_presentation={"carrying":held,"platter":false}
	body().clear_activity_anchor()
	if str(state.phase)=="eating":
		var anchor:Dictionary=flow().eating_anchor(person(),activity())
		body().set_activity_anchor(anchor.position,anchor.yaw,anchor.kind,"eat_meal",anchor)
	if reconstruct:body().reconstruct_meal_pose(str(state.phase)=="eating")
func physical_error()->String:
	if not active():return ""
	if str(state.phase) in ["to_place","eating"] and not flow().guest_place_valid(activity(),true):return "The saved guest dining reservation is unavailable."
	var serving:Dictionary=plate()
	if not serving.is_empty() and (str(serving.owner)!=person() or str(serving.venue)!="home"):return "The saved guest no longer owns their plate."
	if str(state.phase)=="eating" and body().position.distance_to(state.target)>.00001:return "The saved guest is not at their dining place."
	if str(state.phase)=="eating" and not bool(state.standing):
		var anchor:Dictionary=flow().eating_anchor(person(),activity())
		var host:Dictionary=flow().item(str(anchor.table_id))
		var offset:Vector3=host.node.to_local(anchor.plate_position)
		# Use the same local-to-world projection as normal food reconciliation,
		# including its deterministic float32 transform round trip.
		var position:Vector3=host.node.to_global(offset)
		if str(serving.host)!=str(anchor.table_id) or Vector3(serving.position[0],serving.position[1],serving.position[2])!=position or Vector3(serving.offset[0],serving.offset[1],serving.offset[2])!=offset:return "The saved guest plate is not at their actual dining setting."
	return ""
func label()->String:
	if not active():return ""
	return {"pickup":"Getting a serving","to_place":"Finding a place to eat","eating":"Enjoying a meal","release":"Setting down their plate","return":"Returning to their visit"}.get(str(state.phase),"")
static func validate(visit_state:Dictionary,now:float)->String:
	var value:Variant=visit_state.get("meal",{})
	if not value is Dictionary:return "Save contains an invalid guest meal."
	if value.is_empty():return ""
	if str(visit_state.phase) not in ["inside","leaving"]:return "A guest meal requires an admitted visitor."
	if not LifeBuildingState.number(visit_state.get("next_meal"),2,1000000,true) or not LifeBuildingState.number(value.get("token"),1,float(visit_state.next_meal)-1,true):return "Save contains an invalid guest meal identity."
	if str(value.get("phase","")) not in ["pickup","to_place","eating","release","return"]:return "Save contains an invalid guest meal phase."
	if str(visit_state.phase)=="leaving" and str(value.phase)!="release":return "A departing guest must release their meal first."
	for key:String in ["source","plate","seat","reason"]:
		if not value.get(key) is String:return "Save contains invalid guest meal references."
	if not str(value.source).begins_with("meal_") or not value.get("standing") is bool or not LifeHomeVisit._point(value.get("target")) or not LifeBuildingState.number(value.get("last_at"),float(visit_state.admitted_at),now):return "Save contains invalid guest meal placement or time."
	if not LifeBuildingState.number(value.get("retry_at"),0,now+5.0):return "Save contains an invalid guest meal retry clock."
	if str(value.phase) in ["pickup","return"] and (not str(value.plate).is_empty() or not str(value.seat).is_empty() or value.standing):return "A guest without a serving cannot reserve a dining place."
	if str(value.phase) in ["to_place","eating"] and (str(value.plate).is_empty() or (str(value.seat).is_empty()==not bool(value.standing))):return "The guest meal is missing its plate or unique dining place."
	return ""
