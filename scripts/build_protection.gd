extends RefCounted
class_name LifeBuildProtection
## A detached view of current controller and ledger ownership. Stored journeys
## are save data, not the authority for an edit while the household is moving.
const Building=preload("res://scripts/building_state.gd")
const Navigation=preload("res://scripts/lot_navigation.gd")
const RoofRules=preload("res://scripts/roof_rules.gd")
const Meals=preload("res://scripts/meals.gd")
const BUSY:Array[String]=["entry","transit","clear"]

static func snapshot(app:Node)->Dictionary:
	var context:Dictionary={"routes":{},"stairs":{},"foods":{},"actors":{},"venue":str(app.current_venue)}
	if is_instance_valid(app.traversal):
		for id:String in app.traversal.routes:
			var source:Dictionary=app.traversal.routes[id];var route:Dictionary={}
			for key:String in ["identity","generation","destination","cursor","phase","points","point","prepared","wait","ticket","distance","safety","stair_id","exit","clear","clear_points","custody","error"]:
				if source.has(key):route[key]=source[key]
			route.legs=[]
			for source_leg:Dictionary in source.legs:
				var leg:Dictionary={}
				for key:String in ["kind","stair_id","points","from","to","direction"]:
					if source_leg.has(key):leg[key]=source_leg[key]
				if source_leg.has("schedule"):leg.transform=source_leg.schedule.transform
				route.legs.append(leg)
			context.routes[id]=route
		context.stairs=app.traversal.stairs.duplicate(true)
		context.next_identity=app.traversal.next_identity;context.next_ticket=app.traversal.next_ticket
	if is_instance_valid(app.household):
		context.foods=app.household.meals.get_state()
		context.sanitation=app.household.sanitation.get_state()
	for id:String in app.world.actors:
		var actor:Node3D=app.world.actors[id]
		if is_instance_valid(actor):context.actors[id]={"position":actor.position,"height":actor.get_display_height()+.12 if actor.has_method("get_display_height") else 2.0}
	return context.duplicate(true)

static func _level(point:Vector3)->int:
	for level:int in [0,1]:
		if absf(point.y-Building.level_y(level))<.00001:return level
	return -1

static func _points_clear(nav:LifeLotNavigation,points:PackedVector3Array)->bool:
	if points.is_empty():return false
	for index:int in points.size():
		var level:int=_level(points[index])
		if level<0 or not nav.point_clear(level,points[index]):return false
		if index>0 and not nav.segment_clear(level,points[index-1],points[index]):return false
	return true

static func _remaining_points(route:Dictionary,position:Vector3)->PackedVector3Array:
	var result:=PackedVector3Array([position])
	for index:int in range(int(route.point),route.points.size()):result.append(route.points[index])
	return result

static func _leg(route:Dictionary)->Dictionary:
	var cursor:int=int(route.get("cursor",-1))
	return route.legs[cursor] if cursor>=0 and cursor<route.legs.size() else {}

static func proven_transit(context:Dictionary,id:String,before:Dictionary,after:Dictionary)->bool:
	var route:Dictionary=context.get("routes",{}).get(id,{})
	if str(route.get("phase",""))!="transit":return false
	var leg:Dictionary=_leg(route);var stair_id:String=str(leg.get("stair_id",""))
	var lock:Dictionary=context.get("stairs",{}).get(stair_id,{})
	var stair:Dictionary=Building.find(before,stair_id)
	return not stair.is_empty() and leg.get("kind")=="stair" and str(route.stair_id)==stair_id and str(lock.get("owner",""))==id and stair==Building.find(after,stair_id)

static func validate(context:Dictionary,before:Dictionary,after:Dictionary,nav:LifeLotNavigation,layout:Array)->String:
	for stair_id:String in context.get("stairs",{}):
		var lock:Dictionary=context.stairs[stair_id]
		if str(lock.owner).is_empty() and lock.queue.is_empty():continue
		if Building.find(before,stair_id)!=Building.find(after,stair_id):return "A Lifelet owns or is waiting for that staircase. Keep its stairs and landings in place."
	for id:String in context.get("routes",{}):
		var route:Dictionary=context.routes[id];var phase:String=str(route.phase)
		var custody:String=str(route.get("custody",""))
		if not custody.is_empty():
			var held:Dictionary={}
			for group:String in ["batches","portions"]:
				for food:Dictionary in context.get("foods",{}).get(group,[]):
					if str(food.id)==custody:held=food
			if held.is_empty() or str(held.owner)!=id or str(held.storage)!="carried" or str(held.venue)!=str(context.venue) or not bool(route.safety) or phase not in BUSY:return "The traveling Lifelet's carried dish ownership changed. Finish its safe set-down before editing."
		if phase not in BUSY and phase!="waiting":continue
		var leg:Dictionary=_leg(route);var stair_id:String=str(leg.get("stair_id",""))
		var stair:Dictionary=Building.find(before,stair_id)
		if stair.is_empty() or stair!=Building.find(after,stair_id):return "A Lifelet is using that staircase. Keep its stairs and landings in place."
		if phase in BUSY:
			var lock:Dictionary=context.get("stairs",{}).get(stair_id,{})
			if str(lock.get("owner",""))!=id or lock.get("exit")!=route.exit or lock.get("clear")!=route.clear:return "The live stair reservation changed. Wait for the Lifelet to reach the landing."
			if not _points_clear(nav,route.get("clear_points",PackedVector3Array())):return "Keep the traveling Lifelet's reserved exit and clear landing route supported and open."
			# Reserve the occupied run's complete body envelope, including future
			# ascent headroom, rather than testing only the present tread position.
			var run:Rect2=Building.stair_rect(stair)
			var height:float=float(context.actors.get(id,{}).get("height",2.0))
			var envelope:=AABB(Vector3(run.position.x,Building.level_y(int(stair.lower)),run.position.y),Vector3(run.size.x,Building.RISE+height,run.size.y))
			if not RoofRules.obstruction(after,envelope).is_empty():return "Keep headroom clear above the occupied staircase."
			if phase in ["entry","clear"] and not _points_clear(nav,_remaining_points(route,context.actors[id].position)):return "Keep the occupied staircase approach and exit route open."
		else:
			var wait:Vector3=route.wait
			if not nav.point_clear(_level(wait),wait):return "Keep the arrived stair waiter's standing space supported and open."
			var to_entry:Dictionary=nav.route(Navigation.floor_location(_level(wait),wait),Navigation.floor_location(_level(leg.from),leg.from))
			if not bool(to_entry.ok) or to_entry.segments.any(func(segment:Dictionary)->bool:return str(segment.kind)!="floor"):return "Keep a floor approach from the arrived waiter to the reserved staircase."
	for puddle:Dictionary in context.get("sanitation",{}).get("puddles",[]):
		if str(puddle.venue)!=str(context.venue):continue
		var floor_error:String=LifeSanitation.support_error(puddle,layout)
		var area:Rect2=LifeSanitation.bounds(puddle);var level:int=int(puddle.level)
		if not floor_error.is_empty() or (Building.footprint_supported(before,level,area) and not Building.footprint_supported(after,level,area)):
			return "Mop the accident before changing its supporting floor."
	for group:String in ["batches","portions"]:
		for food:Dictionary in context.get("foods",{}).get(group,[]):
			if str(food.venue)!=str(context.venue) or str(food.storage)=="carried" or not str(food.host).is_empty():continue
			var error:String=Meals._saved_floor_error(food,layout)
			if not error.is_empty():return "Move the food or dishes before changing their floor support: "+error
	return ""

static func unchanged_routes(context:Dictionary,before:Dictionary,after:Dictionary,nav:LifeLotNavigation)->Array[String]:
	var preserved:Array[String]=[]
	for id:String in context.get("routes",{}):
		var route:Dictionary=context.routes[id];var valid:bool=true
		# Changes beyond a safe canceled landing no longer affect its journey.
		var end:int=int(route.cursor)+1 if bool(route.safety) else route.legs.size()
		for index:int in range(int(route.cursor),end):
			var leg:Dictionary=route.legs[index]
			if str(leg.kind)=="stair":
				if Building.find(before,str(leg.stair_id))!=Building.find(after,str(leg.stair_id)):valid=false;break
			elif not _points_clear(nav,leg.points):valid=false;break
		if not valid:continue
		if bool(route.prepared) and str(route.phase) in ["route","to_wait","entry","clear"]:
			if not _points_clear(nav,_remaining_points(route,context.actors[id].position)):continue
		if str(route.phase)=="waiting" and not nav.point_clear(_level(route.wait),route.wait):continue
		preserved.append(id)
	return preserved

static func acknowledge_rebuild(app:Node,context:Dictionary,ids:Array[String])->void:
	# A successful synchronous detached transaction changes only the graph
	# generation for unchanged routes. It neither requests a new journey nor
	# modifies an owner's identity, gait, custody or arrived FIFO ticket.
	for id:String in ids:
		if not app.traversal.routes.has(id):continue
		var route:Dictionary=app.traversal.routes[id]
		if int(route.identity)==int(context.routes[id].identity):route.generation=app.world.lot_navigation.generation
