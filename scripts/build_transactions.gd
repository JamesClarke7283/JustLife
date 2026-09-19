extends RefCounted
class_name LifeBuildTransactions
## World/wallet bridge for original architecture proposals. Every confirm and
## undo revalidates against current actors, food, furnishings and wallet.
const Building=preload("res://scripts/building_state.gd")
const RoofEdits=preload("res://scripts/roof_edits.gd")
const RoofRules=preload("res://scripts/roof_rules.gd")
const Edits=preload("res://scripts/building_edits.gd")
const Land=preload("res://scripts/land.gd")
const Navigation=preload("res://scripts/lot_navigation.gd")
const Protection=preload("res://scripts/build_protection.gd")
var app:Node
var _busy:bool=false
var _cache_key:String=""
var _cache:Dictionary={}
var _history:Array=[]
var _next_receipt:int=1

func _init(owner_app:Node=null)->void:app=owner_app
func _error(message:String)->Dictionary:return {"ok":false,"error":message}

func current()->Dictionary:
	var result:Dictionary=app.world.construction.validated_state()
	# Legacy household saves kept the starter-floor finish in world_state rather
	# than the construction marker. Preserve that existing visual during the
	# first canonical edit; extra legacy floor records retain their own finish.
	var finish:Variant=app.get("floor_color")
	if bool(result.ok) and app.world.construction.building_state.is_empty() and Building._material(finish):
		for floor:Dictionary in result.state.floors:
			if str(floor.id)=="legacy_starter_floor":floor.material=finish
	return result

func has_unintegrated_levels()->bool:
	if not is_instance_valid(app) or not is_instance_valid(app.world.construction):return false
	for floor:Dictionary in app.world.construction.building_state.get("floors",[]):
		if int(floor.level)>0:return true
	return false

func _layout(state:Dictionary)->Array:
	var layout:Array=app.world.serialize_items().filter(func(entry:Dictionary)->bool:return str(entry.get("kind",""))!="__construction")
	layout.append(state.duplicate(true));return layout

func _protection()->Dictionary:
	return app.build_protection_context() if app.has_method("build_protection_context") else {}

func _context()->String:
	var context:Array=[app.world.serialize_items(),app.sim.funds,app.get("floor_color"),_protection()]
	for id:String in app.world.actors:
		var actor:Node3D=app.world.actors[id]
		if is_instance_valid(actor):context.append([id,actor.position,actor.visible,actor.get_meta("away",false)])
	for item:Dictionary in app.world.items:
		if bool(item.get("transient_food",false)):context.append([item.id,item.node.global_position,item.size])
	return var_to_str(context).sha256_text()

func prepare(operation:Dictionary,force:bool=false)->Dictionary:
	if not is_instance_valid(app) or not is_instance_valid(app.world):return _error("No home is open.")
	var before:Dictionary=current()
	if not bool(before.ok):return before
	var context:String=_context()
	var key:String=var_to_str(operation).sha256_text()+":"+context
	if not force and key==_cache_key:return _cache.duplicate(true)
	var quote:Dictionary=_propose(before.state,operation,app.sim.funds)
	if bool(quote.ok):
		var error:String=_candidate_error(before.state,quote.after)
		if error.is_empty():quote["context"]=context
		else:quote=_error(error)
	_cache_key=key;_cache=quote.duplicate(true)
	return quote

func _propose(state:Dictionary,operation:Variant,funds:Variant)->Dictionary:
	if operation is Dictionary and operation.get("op")=="roof_edit":return RoofEdits.propose(state,operation,funds)
	if operation is Dictionary and operation.get("op")=="structure":return Edits.propose(state,operation,funds)
	return Building.propose(state,operation,funds)

func _commit_quote(state:Dictionary,quote:Dictionary,funds:int)->Dictionary:
	var calculated:Dictionary=_propose(state,quote.get("operation"),funds)
	if not bool(calculated.ok):return calculated
	for key:String in ["before","after","cost","funds_before","funds_after"]:
		if quote.get(key)!=calculated[key]:return _error("The structure quote changed. Preview it again.")
	return {"ok":true,"state":calculated.after,"funds":calculated.funds_after,"receipt":{"before":state.duplicate(true),"after":Building.fingerprint(calculated.after),"funds_delta":calculated.cost,"operation":calculated.operation.duplicate(true),"funds_before":calculated.funds_before}}

func _undo_receipt(state:Dictionary,receipt:Dictionary,funds:int)->Dictionary:
	if receipt.get("after")!=Building.fingerprint(state) or not Building.number(funds,0,1e9,true):return _error("This history entry no longer matches the structure.")
	var original:Dictionary=_propose(receipt.before,receipt.operation,receipt.funds_before)
	if not bool(original.ok) or original.cost!=receipt.funds_delta or Building.fingerprint(original.after)!=receipt.after:return _error("This history entry is not a validated construction.")
	var refunded:int=funds+int(receipt.funds_delta)
	if not Building.number(refunded,0,1e9,true) or int(state.revision)>=1000000000:return _error("Undo exceeds the wallet or revision limits.")
	var restored:Dictionary=receipt.before.duplicate(true);restored.revision=int(state.revision)+1;restored.next_serial=maxi(int(restored.next_serial),int(state.next_serial))
	return {"ok":true,"state":restored,"funds":refunded}

func _obstacles()->Array:
	return _layout_obstacles(app.world.serialize_items())

func _layout_obstacles(layout:Array)->Array:
	var obstacles:Array=[]
	for entry:Dictionary in layout:
		if str(entry.get("kind","")) in ["__construction","meal","plate"] or LifeCatalog.passable(str(entry.get("kind",""))):continue
		var area:Rect2=app.world.furnishing_rect(entry)
		obstacles.append({"id":str(entry.id),"level":int(entry.get("level",0)),"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y})
	return obstacles

func furnishing_error(layout:Array)->String:
	var state:Dictionary=current()
	if not bool(state.ok):return str(state.error)
	var by_id:Dictionary={}
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))!="__construction":by_id[str(entry.id)]=entry
	# A carrying actor already owns its stair run and destination approach.
	# Moving that destination mid-run otherwise starts service at the old spot.
	for member:Dictionary in app.household.members:
		if not app.traversal.busy(str(member.id)):continue
		var held:Dictionary=app.household.meals.carried_by(str(member.id))
		var action:Dictionary=member.sim.get_current_action()
		if held.is_empty() or str(action.get("id","")) not in ["serve_meal","eat_meal","store_meal","clean_plate","discard_meal"]:continue
		# Custody may outlive a canceled action. An unrelated later meal does
		# not reserve its destination merely because this actor still carries food.
		if str(action.get("meal_plate",action.get("meal_source","")))!=str(held.id):continue
		var targets:Array[String]=[str(action.get("target_id",""))]
		if str(action.id)=="eat_meal":
			var chair:Dictionary=app._find_item(str(action.get("meal_seat","")))
			if not chair.is_empty():
				var table:Dictionary=app.meal_flow._chair_table(chair)
				if not table.is_empty():targets.append(str(table.id))
		for original:Dictionary in app.world.serialize_items():
			var target:String=str(original.get("id",""))
			if target in targets and original!=by_id.get(target,{}):return "Let the carried dish reach its landing before moving or selling its destination."
	var candidate:String=_layout_candidate_error(state.state,state.state,layout)
	if not candidate.is_empty():return candidate
	return _reach_error(state.state,layout)

var _reach_cache:Dictionary={}   # layout signature -> reach error, so a hovering ghost asks once per spot
var _live_reach:Dictionary={}    # the live graph's flood fill and standing spots for the current navigation generation

func _reach_error(state:Dictionary,layout:Array)->String:
	# A furnishing must not seal a doorway: every furnishing that the household
	# can reach from the front sidewalk today stays reachable afterwards. The
	# legacy grid used to squeeze past such a placement while the room-aware
	# navigation refused it, which stranded a household the moment any structural
	# change converted the home.
	var obstacles:Array=[]
	var checked:Array=[]
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))=="__construction" or not LifeCatalog.ITEMS.has(str(entry.get("kind",""))):continue
		if str(entry.kind) in ["meal","plate","puddle"]:continue
		if not LifeCatalog.passable(str(entry.kind)):
			var area:Rect2=app.world.furnishing_rect(entry)
			obstacles.append({"id":str(entry.id),"level":int(entry.get("level",0)),"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y})
		checked.append(entry)
	var signature:String=str(int(state.get("revision",0)))+"|"+str(obstacles.hash())+"|"+str(checked.hash())
	if _reach_cache.has(signature):return str(_reach_cache[signature])
	var live=app.world.lot_navigation
	var origin:Vector3=app.world.lot_exit_position(0)
	if not live.point_clear(0,origin):return ""
	# A layout that only adds one furnishing to the live home (a purchase, or a
	# hovering ghost) is tested on the live graph with the new obstacle's cells
	# removed; anything else (a move, a sale) rebuilds a candidate graph.
	var added:Dictionary=_single_addition(layout)
	var candidate=live
	var excluded:Dictionary={}
	if not added.is_empty():
		if not LifeCatalog.passable(str(added.kind)):excluded=live.points_touching(int(added.get("level",0)),app.world.furnishing_rect(added))
	else:
		candidate=load("res://scripts/lot_navigation.gd").new()
		if not bool(candidate.rebuild(state,obstacles).ok):return ""
		if not candidate.point_clear(0,origin):return ""
	# One flood fill per graph instead of a route per furnishing; the live
	# graph's flood and standing spots are kept per navigation generation, so a
	# hovering ghost only pays for the flood with its own cells removed.
	var after_reach:Dictionary=candidate.reachable_from(0,origin,excluded)
	if int(_live_reach.get("generation",-1))!=int(live.generation) or _live_reach.get("origin",Vector3.INF)!=origin:
		_live_reach={"generation":int(live.generation),"origin":origin,"reach":live.reachable_from(0,origin),"spots":{}}
	var before_reach:Dictionary=_live_reach.reach
	var error:String=""
	for entry:Dictionary in checked:
		var level:int=int(entry.get("level",0))
		var spot_key:String=str(entry.get("id",""))+"|"+str(entry.get("kind",""))+"|%.3f|%.3f|%.1f|%d" % [float(entry.get("x",0)),float(entry.get("z",0)),float(entry.get("rotation",0)),level]
		if not _live_reach.spots.has(spot_key):_live_reach.spots[spot_key]=_clear_near(live,level,app.world.layout_approach(entry))
		var before:Vector3=_live_reach.spots[spot_key]
		if not before.is_finite() or not live.point_reachable(before_reach,level,before):continue
		var spot:Vector3=before if candidate==live else _clear_near(candidate,level,app.world.layout_approach(entry))
		if candidate==live and excluded.has(int(live._floor_ids.get(live._cell_key(level,Vector2i(roundi(spot.x/live.CELL),roundi(spot.z/live.CELL))),-1))):
			spot=_clear_near_excluding(live,level,app.world.layout_approach(entry),excluded)
		if not spot.is_finite() or not candidate.point_reachable(after_reach,level,spot):
			error="That would block the way to the %s. Leave a way to it open." % str(LifeCatalog.ITEMS[str(entry.kind)].label).to_lower()
			break
	if _reach_cache.size()>64:_reach_cache.clear()
	_reach_cache[signature]=error
	return error

func _single_addition(layout:Array)->Dictionary:
	# The one entry of `layout` that is not in the live home, when everything
	# else is unchanged; empty for moves, sales or several changes.
	var live:Dictionary={}
	for entry:Dictionary in app.world.serialize_items():
		if str(entry.get("kind",""))!="__construction":live[str(entry.get("id",""))]=entry
	var added:Dictionary={};var seen:int=0
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))=="__construction":continue
		var id:String=str(entry.get("id",""))
		if live.has(id):
			var current:Dictionary=live[id]
			if str(current.get("kind",""))!=str(entry.get("kind","")) or not is_equal_approx(float(current.get("x",0)),float(entry.get("x",0))) or not is_equal_approx(float(current.get("z",0)),float(entry.get("z",0))) or not is_equal_approx(float(current.get("rotation",0)),float(entry.get("rotation",0))) or int(current.get("level",0))!=int(entry.get("level",0)):return {}
			seen+=1
		elif added.is_empty():added=entry
		else:return {}
	if seen!=live.size():return {}
	return added

func _clear_near_excluding(navigation,level:int,wanted:Vector3,excluded:Dictionary)->Vector3:
	var best:Vector3=Vector3.INF;var best_distance:float=INF
	for dx:int in range(-2,3):
		for dz:int in range(-2,3):
			var point:Vector3=Vector3(snappedf(wanted.x,.25)+dx*.25,Building.level_y(level),snappedf(wanted.z,.25)+dz*.25)
			if not navigation.point_clear(level,point):continue
			var key:String=navigation._cell_key(level,Vector2i(roundi(point.x/navigation.CELL),roundi(point.z/navigation.CELL)))
			if excluded.has(int(navigation._floor_ids.get(key,-1))):continue
			var distance:float=point.distance_to(wanted)
			if distance<best_distance:best_distance=distance;best=point
	return best

func _clear_near(navigation,level:int,wanted:Vector3)->Vector3:
	var best:Vector3=Vector3.INF;var best_distance:float=INF
	for dx:int in range(-2,3):
		for dz:int in range(-2,3):
			var point:Vector3=Vector3(snappedf(wanted.x,.25)+dx*.25,Building.level_y(level),snappedf(wanted.z,.25)+dz*.25)
			if not navigation.point_clear(level,point):continue
			var distance:float=point.distance_to(wanted)
			if distance<best_distance:best_distance=distance;best=point
	return best

func furnishing_rebuilt(context:Dictionary)->void:
	var state:Dictionary=current()
	if not bool(state.ok):return
	Protection.acknowledge_rebuild(app,context,Protection.unchanged_routes(context,state.state,state.state,app.world.lot_navigation))

func _candidate_error(before:Dictionary,after:Dictionary)->String:
	return _layout_candidate_error(before,after,_layout(after))

func _layout_candidate_error(before:Dictionary,after:Dictionary,layout:Array)->String:
	var error:String=app.world.validate_home_layout(layout)
	if not error.is_empty():return error
	var changed_stairs:Array=[]
	for stair:Dictionary in before.stairs:
		if Building.find(after,str(stair.id))!=stair:changed_stairs.append(stair)
	for stair:Dictionary in after.stairs:
		if Building.find(before,str(stair.id))!=stair:changed_stairs.append(stair)
	var candidate:=Navigation.new()
	var rebuilt:Dictionary=candidate.rebuild(after,_layout_obstacles(layout))
	if not bool(rebuilt.ok):return str(rebuilt.error)
	var protection:Dictionary=_protection()
	error=Protection.validate(protection,before,after,candidate,layout)
	if not error.is_empty():return error
	var exit_at:Vector3=app.world.lot_exit_position()
	for id:String in app.world.actors:
		var actor:Node3D=app.world.actors[id]
		if not is_instance_valid(actor) or (not actor.visible and bool(actor.get_meta("away",false))):continue
		var at:Vector3=actor.position
		var height:float=actor.get_display_height()+.12 if actor.has_method("get_display_height") else 2.0
		if not RoofRules.obstruction(after,AABB(at-Vector3(.3,0,.3),Vector3(.6,height,.6))).is_empty():return "The roof would cross a Lifelet's headroom. Leave that space clear."
		var level:int=app.world.point_level(at)
		if level<0:
			if Protection.proven_transit(protection,id,before,after):continue
			return "Wait until every Lifelet reaches a floor before changing the structure."
		if app.world.lot_navigation.point_clear(level,at) and not candidate.point_clear(level,at):return "Leave the Lifelet’s current standing space open."
		var body:=Rect2(Vector2(at.x,at.z)-Vector2(.30,.30),Vector2(.60,.60))
		for stair:Dictionary in changed_stairs:
			if Building.stair_rect(stair).intersects(body) or Building.landing_rect(stair,level==1).intersects(body):return "A Lifelet is using the staircase or its landing. Leave that space clear."
		var support:=Rect2(Vector2(at.x,at.z)-Vector2(.16,.16),Vector2(.32,.32))
		if not Building.footprint_supported(after,level,support,level==0):return "This change would remove the floor beneath a Lifelet."
		if Building.blocked_rect(after,level,support) and not Building.blocked_rect(before,level,support):return "This change would build through a Lifelet's standing space."
		var route:Dictionary=candidate.route(Navigation.floor_location(level,at),Navigation.floor_location(0,exit_at))
		if level==1 and not bool(route.ok):return "Keep a clear staircase and route home for the Lifelets upstairs."
		if level==0:
			var original:Dictionary=app.world.lot_navigation.route(Navigation.floor_location(0,at),Navigation.floor_location(0,exit_at))
			if bool(original.ok) and not bool(route.ok):return "This change would block a Lifelet's route out of the home."
	for item:Dictionary in app.world.items:
		if protection.has("foods") or not bool(item.get("transient_food",false)):continue
		var level:int=app.world.item_level(item)
		var at:Vector3=item.node.global_position
		var area:=Rect2(Vector2(at.x,at.z)-Vector2(item.size)*.5,Vector2(item.size))
		if not Building.footprint_supported(after,level,area,level==0):return "Move the food or dishes before removing their supporting floor."
	return ""

func commit(quote:Dictionary)->Dictionary:
	if _busy:return _error("A building change is already being applied.")
	if not quote.get("operation") is Dictionary:return _error("The building quote is no longer available.")
	var checked:Dictionary=prepare(quote.operation,true)
	if not bool(checked.ok):return checked
	for key:String in ["before","after","cost","funds_before","funds_after","context"]:
		if not quote.has(key) or quote[key]!=checked[key]:return _error("The home or quote changed. Preview this construction again.")
	var before:Dictionary=current()
	var result:Dictionary=_commit_quote(before.state,checked,app.sim.funds)
	if not bool(result.ok):return result
	var applied:Dictionary=_apply(before.state,result.state,int(result.funds))
	if not bool(applied.ok):return applied
	var token:int=_next_receipt;_next_receipt+=1
	_history.append({"token":token,"receipt":result.receipt.duplicate(true),"after":result.state.duplicate(true),"live_after":Building.fingerprint(result.state)})
	return {"ok":true,"cost":int(checked.cost),"receipt":{"token":token}}

func undo(receipt:Dictionary)->Dictionary:
	if _busy:return _error("A building change is already being applied.")
	var before:Dictionary=current()
	if not bool(before.ok):return before
	if _history.is_empty() or not receipt.get("token") is int or receipt.token!=_history[-1].token:return _error("Only the current building history entry can be undone.")
	var entry:Dictionary=_history[-1]
	if Building.fingerprint(before.state)!=str(entry.live_after):return _error("The structure changed after this history entry. Undo the later change first.")
	# The original receipt remains strict and is checked against its original
	# paid result. Our private LIFO history authenticates the current revision
	# after preceding undos; never relax the public module's receipt checks.
	var result:Dictionary=_undo_receipt(entry.after,entry.receipt,app.sim.funds)
	if not bool(result.ok):return result
	result.state.revision=int(before.state.revision)+1
	result.state.next_serial=maxi(int(before.state.next_serial),int(result.state.next_serial))
	var error:String=_candidate_error(before.state,result.state)
	if not error.is_empty():return _error(error)
	var applied:Dictionary=_apply(before.state,result.state,int(result.funds))
	if not bool(applied.ok):return applied
	_history.pop_back()
	if not _history.is_empty() and _same_geometry(_history[-1].after,result.state):_history[-1].live_after=Building.fingerprint(result.state)
	return applied

func matches_history_structure(marker:Dictionary,legacy_finish:String)->bool:
	var saved:Dictionary=Building.migrate(marker)
	var live:Dictionary=current()
	if not bool(saved.ok) or not bool(live.ok):return false
	if not marker.has("version") and Building._material(legacy_finish):
		for floor:Dictionary in saved.state.floors:
			if str(floor.id)=="legacy_starter_floor":floor.material=legacy_finish
	return _same_geometry(saved.state,live.state)

func _same_geometry(first:Dictionary,second:Dictionary)->bool:
	var left:Dictionary=first.duplicate(true);var right:Dictionary=second.duplicate(true)
	for key:String in ["revision","next_serial"]:left.erase(key);right.erase(key)
	return left==right

func clear_history()->void:_history.clear();_cache_key="";_cache.clear()

## Buy the next neighbouring plot on one side of the lot, and rebuild the world
## around the larger ground.
##
## It is a transaction like any other build: the quote is priced against the
## land as it stands, the wallet is charged only on success, and the ground,
## hedge, navigation region, compatibility grid and camera bound are all rebuilt
## from the new lot in the same step, so a plot can never be half-bought.
func buy_land(side:String)->Dictionary:
	if _busy:return _error("A building change is already being applied.")
	if not is_instance_valid(app) or not is_instance_valid(app.world):return _error("No home is open.")
	if str(app.current_venue)!="home":return _error("Only the household's own lot can be expanded.")
	var purchase:Dictionary=Land.purchase(Building.land,side,app.sim.funds)
	if not bool(purchase.ok):return purchase
	var before:Dictionary=Building.land.duplicate(true)
	var after:Dictionary=purchase.state
	# Land purchase is not a construction edit, so it takes no building revision
	# and no undo entry. Instead the two changes are applied together: the land
	# is set, the world rebuilds, and the wallet pays only if that succeeded.
	Building.set_land(after)
	var result:Dictionary=_rebuild_for_land()
	if not bool(result.ok):
		Building.set_land(before)
		_rebuild_for_land()
		return result
	if is_instance_valid(app.household):app.household.set_funds(int(purchase.funds))
	else:app.sim.funds=int(purchase.funds)
	# The home layout is re-serialized because the lot moved the ground under it.
	if str(app.get("current_venue"))=="home":app.home_layout=app.world.serialize_items()
	return {"ok":true,"side":side,"cost":int(purchase.cost),"land":after.duplicate(true),"plots":Land.plots(after),"lot":Building.lot()}


## Rebuild the world in place after the land changed, keeping the building state
## and every furnishing exactly where they were.
func _rebuild_for_land()->Dictionary:
	var protection:Dictionary=_protection()
	_busy=true
	# The ground is redrawn first, because the lawn, hedge and street all move
	# with the lot; the building and its furnishings are untouched.
	if app.world.has_method("draw_ground"):app.world.draw_ground()
	app.world.rebuild_navigation()
	var error:String=app.world.last_layout_error
	if error.is_empty():
		var state:Dictionary=app.world.construction.validated_state()
		if not bool(state.ok):error=str(state.error)
	if not error.is_empty():
		_busy=false;return _error(error)
	# Existing routes ride the same graph generation, exactly as any other
	# rebuild does, so nobody is stranded by the boundary moving under them.
	if app.has_method("build_protection_context"):
		var unchanged:Array[String]=Protection.unchanged_routes(protection,app.world.construction.building_state,app.world.construction.building_state,app.world.lot_navigation)
		Protection.acknowledge_rebuild(app,protection,unchanged)
	_cache_key="";_cache.clear();_busy=false
	return {"ok":true}

func _apply(before:Dictionary,after:Dictionary,funds:int)->Dictionary:
	var protection:Dictionary=_protection()
	_busy=true
	app.world.construction.restore(after)
	app.world.last_layout_error=""
	app.world.rebuild_navigation()
	var error:String=app.world.construction.last_error
	if error.is_empty():error=app.world.last_layout_error
	if not error.is_empty():
		app.world.construction.restore(before);app.world.last_layout_error="";app.world.rebuild_navigation()
		_busy=false;return _error(error)
	# State and graph are installed before the single wallet mutation. No action
	# is canceled, advanced or rewarded by this transaction.
	Protection.acknowledge_rebuild(app,protection,Protection.unchanged_routes(protection,before,after,app.world.lot_navigation))
	if app.has_method("build_protection_context") and is_instance_valid(app.household):app.household.set_funds(funds)
	else:app.sim.funds=funds
	_cache_key="";_cache.clear();_busy=false
	return {"ok":true}
