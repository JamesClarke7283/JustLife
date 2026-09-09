extends RefCounted
class_name PreviousStairJourneyState
## Saved physical facts, validated before adopting a household. Paths, gait
## schedules, temporary graph indices and runtime node references are derived.
const VERSION:int=2
const Building=preload("res://scripts/building_state.gd")
const Navigation=preload("res://scripts/lot_navigation.gd")
const Gait=preload("res://scripts/stair_gait.gd")
const PHASES:Array[String]=["route","to_wait","waiting","entry","transit","clear"]
const OWNED:Array[String]=["entry","transit","clear"]
static var _shoe_extents:Dictionary={}

static func number(value:Variant,low:float,high:float,whole:bool=false)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high and (not whole or float(value)==floorf(float(value)))

static func vector_valid(value:Variant)->bool:
	return value is Array and value.size()==3 and value.all(func(axis:Variant)->bool:return number(axis,-100,100))

static func vector(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
static func packed(value:Vector3)->Array:return [value.x,value.y,value.z]

static func level(point:Vector3)->int:
	for floor:int in [0,1]:
		if absf(point.y-Building.level_y(floor))<.00001:return floor
	return -1

static func _model_transform(node:Node3D,root:Node3D)->Transform3D:
	var result:Transform3D=node.transform
	var parent:Node=node.get_parent()
	while parent!=root:
		if parent is Node3D:result=parent.transform*result
		parent=parent.get_parent()
	return result

static func rear_extent(profile:Dictionary,direction:int)->float:
	# Read imported rest-shoe geometry off-tree without configuring an actor,
	# consuming its RNG or allocating voice/held-prop presentation state.
	var frame:int=clampi(int(profile.get("frame",0)),0,1)
	var stage:String=str(profile.get("age_stage","young_adult"))
	var path:String="res://assets/models/character"+("_broad" if frame else "")+"_lod.glb"
	if stage in ["child","teen","elder"]:path="res://assets/models/character_%s%s_lod.glb"%[stage,"_broad" if frame else ""]
	if not _shoe_extents.has(path):
		if not ResourceLoader.exists(path):return -1
		var model:Node3D=load(path).instantiate()
		var forward:float=0;var backward:float=0
		for side:String in ["L","R"]:
			var shin:Node3D=model.find_child("Shin_"+side,true,false)
			if not is_instance_valid(shin):model.free();return -1
			var low:Vector3=Vector3.INF;var high:Vector3=-Vector3.INF
			for mesh:MeshInstance3D in shin.find_children("Shoes_Sole*","MeshInstance3D",true,false):
				var transform:Transform3D=_model_transform(mesh,model)
				for i:int in 8:
					var point:Vector3=transform*mesh.get_aabb().get_endpoint(i);low=low.min(point);high=high.max(point)
			if not low.is_finite():model.free();return -1
			var center_z:float=(low.z+high.z)*.5
			for mesh:MeshInstance3D in shin.find_children("Shoes_*","MeshInstance3D",true,false):
				var transform:Transform3D=_model_transform(mesh,model)
				for i:int in 8:
					var z:float=(transform*mesh.get_aabb().get_endpoint(i)).z-center_z
					forward=maxf(forward,z);backward=maxf(backward,-z)
		model.free();_shoe_extents[path]=Vector2(forward,backward)
	var value:Vector2=_shoe_extents[path]
	return (value.x if direction==1 else value.y)*clampf(float(profile.get("body_scale",1.0)),.85,1.15)

static func stair_plan(stair:Dictionary,profile:Dictionary,direction:int)->Dictionary:
	var transform:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(stair.rotation))),Vector3(float(stair.x),Building.level_y(0),float(stair.z)))
	var extent:float=rear_extent(profile,direction)
	if extent<=0:return {}
	return Gait.plan(transform,direction,extent)

static func layout_context(layout:Array)->Dictionary:
	var inspector=load("res://scripts/world.gd").new()
	var error:String=inspector.validate_home_layout(layout)
	if not error.is_empty():inspector.free();return {"ok":false,"error":error}
	var building:Dictionary={};var items:Dictionary={};var obstacles:Array=[]
	for record:Dictionary in layout:
		if str(record.kind)=="__construction":
			var migrated:Dictionary=Building.migrate(record)
			if not bool(migrated.ok):inspector.free();return migrated
			building=migrated.state
		else:items[str(record.id)]=record
	if building.is_empty():inspector.free();return {"ok":false,"error":"A journey save requires its complete construction record."}
	for record:Dictionary in items.values():
		if str(record.kind) in ["rug","painting","meal","plate"]:continue
		var bounds:Rect2=inspector.furnishing_rect(record)
		obstacles.append({"id":str(record.id),"level":int(record.get("level",0)),"x":bounds.get_center().x,"z":bounds.get_center().y,"w":bounds.size.x,"d":bounds.size.y})
	inspector.free()
	var nav:=Navigation.new();var rebuilt:Dictionary=nav.rebuild(building,obstacles)
	if not bool(rebuilt.ok):return rebuilt
	var stairs:Dictionary={}
	for stair:Dictionary in building.stairs:stairs[str(stair.id)]=stair
	return {"ok":true,"state":building,"navigation":nav,"items":items,"stairs":stairs}

static func _floor_route(nav:LifeLotNavigation,from:Vector3,to:Vector3)->bool:
	var result:Dictionary=nav.route(Navigation.floor_location(level(from),from),Navigation.floor_location(level(to),to))
	if not bool(result.ok):return false
	return result.segments.all(func(segment:Dictionary)->bool:return str(segment.kind)=="floor")

static func _intent_error(intent:Variant,member:Dictionary,safety:bool)->String:
	if not intent is Dictionary or intent.get("kind") not in ["idle","walk","action"]:return "Invalid saved movement intent."
	var queue:Array=member.state.action_queue
	if intent.kind=="action":
		if queue.is_empty():return "A saved action journey has no current action."
		var action:Dictionary=queue[0]
		for key:String in ["id","target_id","meal_source","meal_stage","meal_plate"]:
			if not intent.get(key,"") is String or str(intent.get(key,""))!=str(action.get(key,"")):return "A saved journey does not match the current action."
		if str(action.get("phase",""))!="approach":return "An active action cannot also be traveling to its target."
	elif not queue.is_empty():return "An idle or walking journey conflicts with its action queue."
	elif intent.kind=="idle" and not safety:return "Only a safe-exit journey can continue without an instruction."
	if intent.kind=="walk" and not vector_valid(intent.get("destination")):return "Invalid saved walking destination."
	return ""

static func validate(data:Variant,household:Dictionary)->Dictionary:
	if not data is Dictionary or (data.get("version")!=1 and data.get("version")!=VERSION) or not number(data.get("next_identity"),1,1e9,true) or not number(data.get("next_ticket"),1,1e9,true) or not data.get("members") is Dictionary:return {"ok":false,"error":"Invalid saved journey format."}
	var people:Dictionary={}
	for member:Dictionary in household.members:people[str(member.id)]=member
	if data.members.size()!=people.size():return {"ok":false,"error":"Journey locations do not match the household."}
	var selected:Dictionary=household.members[int(household.selected_index)].state.character
	var context:Variant=selected.get("world_state",{})
	if not context is Dictionary:return {"ok":false,"error":"Missing saved world context."}
	var venue:Variant=context.get("venue","home")
	if context.has("view_level") and not number(context.view_level,0,1,true):return {"ok":false,"error":"Invalid saved visible floor."}
	if not venue is String or not LifeNeighborhood.PLACES.has(venue):return {"ok":false,"error":"Invalid saved venue."}
	var checked:Dictionary=layout_context(household.world)
	if not bool(checked.ok):return checked
	var layouts:Dictionary={venue:household.world}
	if not context.get("home_layout",[]) is Array or not context.get("venue_layouts",{}) is Dictionary:return {"ok":false,"error":"Invalid saved venue layouts."}
	if venue!="home":layouts.home=context.home_layout
	elif not context.get("home_layout",[]).is_empty():
		var cached_home:Dictionary=layout_context(context.home_layout)
		if not bool(cached_home.ok):return {"ok":false,"error":"Invalid cached home layout: "+str(cached_home.error)}
	for key:Variant in context.get("venue_layouts",{}):
		if not key is String or not LifeNeighborhood.PLACES.has(key) or key=="home" or not context.venue_layouts[key] is Array:return {"ok":false,"error":"Invalid cached venue layout."}
		var stored:Dictionary=layout_context(context.venue_layouts[key])
		if not bool(stored.ok):return {"ok":false,"error":"Invalid cached "+str(key)+" layout: "+str(stored.error)}
		if key!=venue:layouts[key]=context.venue_layouts[key]
	for key:String in layouts:
		if key==venue:continue
		var cached:Dictionary=layout_context(layouts[key])
		if not bool(cached.ok):return {"ok":false,"error":"Invalid cached "+key+" layout: "+str(cached.error)}
	var nav:LifeLotNavigation=checked.navigation
	var owners:Dictionary={};var queues:Dictionary={};var identities:Dictionary={};var tickets:Dictionary={};var custody:Dictionary={}
	var reservations:Array=[]
	for id:Variant in data.members:
		if not id is String or not people.has(id):return {"ok":false,"error":"A saved location refers to an unknown Lifelet."}
		var record:Variant=data.members[id]
		if not record is Dictionary or not vector_valid(record.get("position")) or not number(record.get("yaw"),-1000,1000) or not record.get("motion") is Dictionary:return {"ok":false,"error":"Invalid saved physical location."}
		var at:Vector3=vector(record.position);var motion:Dictionary=record.motion
		if int(data.version)==1 and motion.has("courtesy"):return {"ok":false,"error":"A legacy journey cannot contain courtesy ownership."}
		var old:Variant=people[id].state.character.get("world_state",{})
		if not old is Dictionary or not vector_valid(old.get("player")) or vector(old.player).distance_to(at)>.00001 or not number(old.get("player_rotation"),-1000,1000) or absf(float(old.player_rotation)-float(record.yaw))>.00001:return {"ok":false,"error":"Saved actor and journey locations disagree."}
		if motion.is_empty():
			if not nav.point_clear(level(at),at):return {"ok":false,"error":"A stationary Lifelet is outside supported clear floor."}
			continue
		if motion.get("phase") not in PHASES or not number(motion.get("identity"),1,float(data.next_identity)-1,true) or identities.has(motion.identity) or not number(motion.get("ticket"),0,float(data.next_ticket)-1,true) or not motion.get("safety") is bool or not motion.get("custody") is String:return {"ok":false,"error":"Invalid saved journey identity or phase."}
		identities[motion.identity]=id
		if not vector_valid(motion.get("destination")) or not motion.get("stair_id") is String or not number(motion.get("direction"),-1,1,true) or not number(motion.get("distance"),0,100) or not motion.get("wait") is Array or not motion.get("clear") is Array:return {"ok":false,"error":"Invalid saved route facts."}
		if not nav.point_clear(level(vector(motion.destination)),vector(motion.destination)):return {"ok":false,"error":"A saved route destination has no clear supported floor."}
		var intent_error:String=_intent_error(motion.get("intent"),people[id],bool(motion.safety))
		if not intent_error.is_empty():return {"ok":false,"error":intent_error}
		if not bool(motion.safety) and str(motion.intent.kind)=="walk" and vector(motion.intent.destination).distance_to(vector(motion.destination))>.00001:return {"ok":false,"error":"The saved walking intent disagrees with its route destination."}
		if bool(motion.safety) and motion.phase not in OWNED:return {"ok":false,"error":"Safe-exit movement has no owned staircase."}
		if int(motion.ticket)>0:
			if tickets.has(motion.ticket):return {"ok":false,"error":"Two Lifelets share an arrival ticket."}
			tickets[motion.ticket]=id
		if motion.phase in ["route","to_wait"]:
			if int(motion.ticket)!=0 or float(motion.distance)!=0 or not nav.point_clear(level(at),at):return {"ok":false,"error":"Invalid floor approach to a staircase."}
			if not motion.wait.is_empty() and (not vector_valid(motion.wait) or not _floor_route(nav,at,vector(motion.wait))):return {"ok":false,"error":"An approaching waiter cannot reach their saved place."}
		elif not checked.stairs.has(str(motion.stair_id)) or int(motion.direction) not in [-1,1] or int(motion.ticket)==0:return {"ok":false,"error":"A saved stair journey has no valid stair or arrival ticket."}
		if str(motion.stair_id).is_empty():
			if motion.phase!="route" or int(motion.direction)!=0 or not motion.wait.is_empty() or not motion.clear.is_empty() or not _floor_route(nav,at,vector(motion.destination)):return {"ok":false,"error":"A floor route contains conflicting staircase data."}
		else:
			if not checked.stairs.has(str(motion.stair_id)) or int(motion.direction) not in [-1,1]:return {"ok":false,"error":"Invalid saved stair identity or direction."}
			var plan:Dictionary=stair_plan(checked.stairs[motion.stair_id],people[id].state.character,int(motion.direction))
			if plan.is_empty():return {"ok":false,"error":"The saved Lifelet has no valid shoe contact model."}
			if float(motion.distance)>float(plan.length):return {"ok":false,"error":"Saved stair progress exceeds its real schedule."}
			var entry:Vector3=Gait.sample(plan,0).root;var exit:Vector3=Gait.sample(plan,plan.length).root
			if not bool(nav.route(Navigation.floor_location(level(exit),exit),Navigation.floor_location(level(vector(motion.destination)),vector(motion.destination))).ok):return {"ok":false,"error":"The saved stair exit cannot reach the route destination."}
			if motion.phase in ["route","to_wait"]:
				if not motion.clear.is_empty() or not _floor_route(nav,at,entry):return {"ok":false,"error":"The saved approach cannot reach this stair entry."}
				if motion.phase=="to_wait" and not vector_valid(motion.wait):return {"ok":false,"error":"The approaching waiter has no saved place."}
			if motion.phase=="waiting":
				if not motion.clear.is_empty() or not vector_valid(motion.wait) or at.distance_to(vector(motion.wait))>.00001 or at.distance_to(entry)<.72 or not _floor_route(nav,at,entry) or float(motion.distance)!=0:return {"ok":false,"error":"An arrived waiter is not at a clear saved waiting place."}
				if not queues.has(motion.stair_id):queues[motion.stair_id]=[]
				queues[motion.stair_id].append({"id":id,"ticket":int(motion.ticket)})
			elif motion.phase in OWNED:
				if owners.has(motion.stair_id) or not motion.wait.is_empty() or not vector_valid(motion.clear):return {"ok":false,"error":"Conflicting staircase ownership or clearance."}
				var clear:Vector3=vector(motion.clear)
				if clear.distance_to(exit)<.85 or clear.distance_to(exit)>2.0 or not _floor_route(nav,exit,clear):return {"ok":false,"error":"The reserved stair exit cannot be safely cleared."}
				owners[motion.stair_id]={"owner":id,"exit":exit,"clear":clear}
				reservations.append({"owner":id,"exit":exit,"clear":clear})
				if motion.phase=="transit":
					var sample:Dictionary=Gait.sample(plan,float(motion.distance))
					if at.distance_to(sample.root)>.00001 or absf(angle_difference(float(record.yaw),float(sample.yaw)))>.00001:return {"ok":false,"error":"Saved stair position or facing disagrees with its progress."}
				elif motion.phase=="entry":
					if float(motion.distance)!=0 or not _floor_route(nav,at,entry):return {"ok":false,"error":"Invalid saved entry walk."}
				elif absf(float(motion.distance)-float(plan.length))>.00001 or not _floor_route(nav,at,clear):return {"ok":false,"error":"Invalid saved stair clearance walk."}
		if not str(motion.custody).is_empty():
			if not bool(motion.safety) or motion.phase not in OWNED or custody.has(motion.custody):return {"ok":false,"error":"Invalid safe-exit food custody."}
			custody[motion.custody]=id
	for queue:Array in queues.values():
		for waiter:Dictionary in queue:
			var at:Vector3=vector(data.members[waiter.id].position)
			for id:String in data.members:
				if id==str(waiter.id):continue
				var other:Vector3=vector(data.members[id].position)
				if absf(at.y-other.y)<.1 and at.distance_to(other)<.72:return {"ok":false,"error":"Two saved Lifelets overlap an arrived waiting place."}
	for reservation:Dictionary in reservations:
		for id:String in data.members:
			if id==str(reservation.owner):continue
			var at:Vector3=vector(data.members[id].position)
			for point:Vector3 in [reservation.exit,reservation.clear]:
				if absf(at.y-point.y)<.1 and at.distance_to(point)<.72:return {"ok":false,"error":"Another Lifelet occupies a saved reserved exit."}
	for first:int in reservations.size():
		for second:int in range(first+1,reservations.size()):
			for a:Vector3 in [reservations[first].exit,reservations[first].clear]:
				for b:Vector3 in [reservations[second].exit,reservations[second].clear]:
					if absf(a.y-b.y)<.1 and a.distance_to(b)<.72:return {"ok":false,"error":"Two staircase owners reserve overlapping exits."}
	for key:String in queues:
		var queue:Array=queues[key]
		queue.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.ticket)<int(b.ticket))
		if owners.has(key):
			var owner_ticket:int=int(data.members[owners[key].owner].motion.ticket)
			if not queue.is_empty() and owner_ticket>=int(queue[0].ticket):return {"ok":false,"error":"A staircase owner bypasses an earlier arrived waiter."}
	var courtesy_error:String=_courtesy_error(data,people,nav,reservations,(float(household.day)-1)*1440.0+float(household.minutes))
	if not courtesy_error.is_empty():return {"ok":false,"error":courtesy_error}
	return {"ok":true,"owners":owners,"queues":queues,"custody":custody,"context":checked,"venue":venue,"layouts":layouts}

static func clear_corridor(nav:LifeLotNavigation,points:PackedVector3Array,occupied:Array[Vector3])->bool:
	# Existing protected clearance is a physical swept path, not a new .78 route.
	if points.is_empty():return false
	for index:int in range(1,points.size()):
		var from:Vector3=points[index-1];var to:Vector3=points[index]
		if level(from)<0 or level(from)!=level(to) or not nav.segment_clear(level(from),from,to):return false
		var delta:Vector3=to-from
		for at:Vector3 in occupied:
			if absf(at.y-to.y)>=.1:continue
			var part:float=clampf((at-from).dot(delta)/maxf(.00000001,delta.length_squared()),0,1)
			if from.lerp(to,part).distance_to(at)<.72-.000001:return false
	return true

static func _courtesy_error(data:Dictionary,people:Dictionary,nav:LifeLotNavigation,reservations:Array,now:float)->String:
	var count:int=0
	for id:String in data.members:
		var record:Dictionary=data.members[id];var motion:Dictionary=record.motion
		if not motion.has("courtesy"):continue
		count+=1
		if count>1:return "Two household members claim courtesy movement."
		var fact:Variant=motion.courtesy
		if not fact is Dictionary or (fact.get("version")!=1 and fact.get("version")!=2) or fact.size()!=(6 if fact.get("version")==1 else 7) or (fact.get("version")==2 and fact.get("beneficiary_kind") not in ["action","stair_clear"]) or fact.get("phase") not in ["retreat","hold"] or not vector_valid(fact.get("anchor")) or not fact.get("beneficiary_id") is String or not number(fact.get("beneficiary_identity"),1,float(data.next_identity)-1,true) or not number(fact.get("expires_at"),now,now+60.0) or float(fact.expires_at)<=now:return "Invalid saved courtesy facts or deadline."
		var fields:Array=["version","phase","anchor","beneficiary_id","beneficiary_identity","expires_at"]
		if fact.version==2:fields.append("beneficiary_kind")
		for key:Variant in fact:
			if key not in fields:return "Unknown saved courtesy field."
		var kind:String=str(fact.get("beneficiary_kind","action"))
		var peer:String=str(fact.beneficiary_id)
		if peer==id or not data.members.has(peer):return "Invalid saved courtesy beneficiary."
		var other_motion:Dictionary=data.members[peer].motion
		if other_motion.is_empty() or int(other_motion.identity)!=int(fact.beneficiary_identity):return "Saved courtesy ownership refers to a retired route."
		var at:Vector3=vector(record.position);var anchor:Vector3=vector(fact.anchor)
		if level(at)!=level(anchor) or level(at)!=level(vector(data.members[peer].position)) or not nav.point_clear(level(anchor),anchor) or at.distance_to(anchor)>2.0 or not _floor_route(nav,at,anchor):return "The saved courtesy anchor is not a supported local retreat."
		if str(fact.phase)=="hold" and at.distance_to(anchor)>.00001:return "A saved courtesy hold is not at its anchor."
		if kind=="stair_clear" and (str(other_motion.phase)!="clear" or str(other_motion.stair_id).is_empty() or not reservations.any(func(r:Dictionary)->bool:return str(r.owner)==peer and r.clear==vector(other_motion.clear))):return "Courtesy beneficiary does not own protected stair clearance."
		for member_id:String in [id,peer]:
			if member_id==peer and kind=="stair_clear":continue
			var route:Dictionary=data.members[member_id].motion;var state:Dictionary=people[member_id].state
			if route.phase!="route" or not str(route.stair_id).is_empty() or bool(route.safety) or str(route.intent.kind)!="action" or level(vector(route.destination))!=level(anchor):return "Courtesy movement conflicts with a protected journey."
			if float(state.character.world_state.get("resource_wait_started",-1))>=0 or bool(state.character.world_state.get("resource_action_active",false)) or not str(state.action_queue[0].get("cooperation_role","")).is_empty():return "A resource owner cannot take courtesy movement."
		for member_id:String in data.members:
			if member_id==id or str(people[member_id].state.get("away_state",{}).get("phase",""))=="away":continue
			var other:Vector3=vector(data.members[member_id].position)
			if level(other)==level(anchor) and anchor.distance_to(other)<.78:return "Another Lifelet occupies the saved courtesy anchor."
			var other_route:Dictionary=data.members[member_id].motion
			if float(people[member_id].state.character.world_state.get("resource_wait_started",-1))>=0:
				var reserved:Vector3=other if other_route.is_empty() else vector(other_route.destination)
				if level(reserved)==level(anchor) and anchor.distance_to(reserved)<.8:return "Courtesy movement occupies an earlier resource waiting place."
			if not other_route.is_empty() and not other_route.wait.is_empty():
				var wait:Vector3=vector(other_route.wait)
				if level(wait)==level(anchor) and anchor.distance_to(wait)<.78:return "Courtesy movement occupies a saved FIFO waiting place."
		var occupied:Array[Vector3]=[]
		for member_id:String in data.members:
			if member_id==peer or str(people[member_id].state.get("away_state",{}).get("phase",""))=="away":continue
			occupied.append(anchor if member_id==id else vector(data.members[member_id].position))
			var other:Dictionary=data.members[member_id].motion
			if not other.is_empty() and not other.wait.is_empty():occupied.append(vector(other.wait))
			if float(people[member_id].state.character.world_state.get("resource_wait_started",-1))>=0:occupied.append(vector(other.destination) if not other.is_empty() else vector(data.members[member_id].position))
		for reservation:Dictionary in reservations:
			if kind=="stair_clear" and str(reservation.owner)==peer:continue
			occupied.append(reservation.exit);occupied.append(reservation.clear)
		var from:Vector3=vector(data.members[peer].position);var destination:Vector3=vector(other_motion.clear if kind=="stair_clear" else other_motion.destination)
		var priority:Dictionary
		if kind=="stair_clear":
			# Match the existing protected restore: derive body-to-clear geometry,
			# then validate its complete sweep under the saved donor anchor.
			priority=nav.route(Navigation.floor_location(level(from),from),Navigation.floor_location(level(destination),destination))
		else:priority=nav.route_avoiding(Navigation.floor_location(level(from),from),Navigation.floor_location(level(destination),destination),occupied,.78)
		if not bool(priority.ok) or not priority.segments.all(func(leg:Dictionary)->bool:return str(leg.kind)=="floor"):return "The saved courtesy beneficiary has no supported priority route."
		if kind=="stair_clear" and not clear_corridor(nav,priority.points,occupied):return "The saved protected clearance corridor is occupied."
		for reservation:Dictionary in reservations:
			for point:Vector3 in [reservation.exit,reservation.clear]:
				if level(point)==level(anchor) and anchor.distance_to(point)<.78:return "Courtesy movement occupies a reserved stair exit."
	return ""

static func validate_actions(household:Dictionary)->String:
	# v2 restores exact phases instead of turning every action into a new
	# approach. Validate those raw facts before any candidate state is adopted.
	var now:float=(float(household.day)-1)*1440.0+float(household.minutes)
	for member:Dictionary in household.members:
		var queue:Array=member.state.action_queue
		var saved:Dictionary=member.state.character.world_state
		for index:int in queue.size():
			var action:Dictionary=queue[index]
			if not action.get("phase") is String or action.phase not in ["queued","approach","active"]:return "A saved action has an invalid physical phase."
			if (index==0 and action.phase=="queued") or (index>0 and action.phase!="queued"):return "The saved action phases disagree with their queue positions."
		for key:String in ["waiting_action_id","waiting_target_id"]:
			if not saved.get(key) is String:return "A saved resource wait has an invalid action identity."
		if not number(saved.get("resource_wait_started"),-1,now) or (float(saved.resource_wait_started)<0 and float(saved.resource_wait_started)!=-1) or not saved.get("resource_action_active") is bool:return "Invalid saved resource wait priority."
		var current:Dictionary=queue[0] if not queue.is_empty() else {}
		if str(saved.waiting_action_id)!=str(current.get("id","")) or str(saved.waiting_target_id)!=str(current.get("target_id","")):return "The saved resource wait does not match its current action."
		if current.is_empty():
			if float(saved.resource_wait_started)!=-1 or bool(saved.resource_action_active):return "An idle Lifelet owns an activity reservation."
		else:
			if str(current.phase)=="active" and (not bool(saved.resource_action_active) or float(saved.resource_wait_started)!=-1):return "An active saved activity has inconsistent resource ownership."
			if bool(saved.resource_action_active) and not bool(current.get("paid",false)) and str(current.id) not in ["school_day","career_day"]:return "An unstarted activity claims an active resource."
		var motion:Dictionary=household.journeys.members[str(member.id)].motion
		if not motion.is_empty() and not bool(motion.safety) and str(motion.intent.kind)=="action" and float(saved.resource_wait_started)<0:
			var target:Variant=current.get("target_position")
			if target is Vector3:target=packed(target)
			if not vector_valid(target) or vector(target).distance_to(vector(motion.destination))>.00001:return "The saved action journey disagrees with its current target position."
	return ""
