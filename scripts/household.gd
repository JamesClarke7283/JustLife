extends Node
class_name LifeHousehold
## A shared home and wallet, with independent needs, careers and action queues.

signal member_age_changed(member_id: String, previous: String, current: String)
signal member_action_started(member_id: String, action: Dictionary)
signal member_action_finished(member_id: String, action: Dictionary)
signal notice(message: String)
signal selection_changed(member_id: String)

const SAVE_PATH = "user://justlife_save.json"
const MAX_MEMBERS = 8
var members: Array = []
var selected_index: int = 0
var funds: int = 2500
var speed: int = 1
var day: int = 1
var minutes: float = 480
var targets: Array = []
var restoring: bool = false
var journeys: Dictionary = {}
var physical_snapshot_provider:Callable=Callable()
var family_graph: Dictionary = LifeFamilyGraph.fresh()
var adoptions: Dictionary = LifeAdoption.fresh()
var _family_roles: Dictionary = {}
var meals: LifeMeals = LifeMeals.new()
var sanitation: LifeSanitation = LifeSanitation.new()
var cooperations: Array = []
var cooperation_serial: int = 0
var _cooperation_depth: int = 0
const COOPERATION_WAIT_LIMIT: float = 60.0

func new_household(profiles: Array) -> void:
	journeys.clear()
	adoptions=LifeAdoption.fresh()
	meals.clear()
	sanitation.clear()
	cooperations.clear()
	cooperation_serial = 0
	for member in members:member.sim.queue_free()
	members.clear()
	family_graph = LifeFamilyGraph.fresh()
	_family_roles.clear()
	selected_index=0;funds=2500;speed=1;day=1;minutes=480
	for profile in profiles.slice(0,MAX_MEMBERS):add_member(profile)
	if members.is_empty():add_member({})
	_sync_wallet()

func add_member(profile: Dictionary) -> String:
	if members.size()>=MAX_MEMBERS:return ""
	var id:String="player" if members.is_empty() else "housemate_%d" % members.size()
	var sim=LifeSim.new()
	sim.name="Life_"+id
	add_child(sim)
	sim.new_household(profile)
	sim.day=day;sim.minutes=minutes;sim.funds=funds;sim.speed=speed
	sim.household_bills_enabled=members.is_empty()
	sim.register_targets(targets.filter(func(target:Dictionary):return str(target.id)!=id))
	members.append({"id":id,"sim":sim})
	connect_member(id,sim)
	for other:Dictionary in members:
		if other.id==id:continue
		sim.relationships[other.id]={"name":other.sim.character.name,"friendship":18.0,"romance":0.0,"status":"Housemate","life_stage":other.sim.character.life_stage,"bond":"none","milestones":[],"family_role":"none"}
		other.sim.relationships[id]={"name":sim.character.name,"friendship":18.0,"romance":0.0,"status":"Housemate","life_stage":sim.character.life_stage,"bond":"none","milestones":[],"family_role":"none"}
	_rebuild_family_roles()
	_sync_social_context()
	return id

func connect_member(id: String, sim: LifeSim) -> void:
	sim.cooperation_owner = self
	sim.cooperation_member_id = id
	sim.age_changed.connect(func(previous: String, current: String):
		_sync_social_context()
		if not restoring: member_age_changed.emit(id, previous, current))
	sim.action_started.connect(func(action:Dictionary):
		if not restoring:member_action_started.emit(id,action))
	sim.action_finished.connect(func(action:Dictionary):
		if not restoring:
			var target:LifeSim=member_sim(str(action.get("target_id","")))
			if target and str(action.id) in LifeSim.SOCIAL_ACTIONS and bool(action.get("social_accepted",true)) and sim.relationships.has(str(action.target_id)):
				var relationship:Dictionary=sim.relationships[str(action.target_id)].duplicate(true)
				target.receive_social_result(id,str(sim.character.name),str(sim.character.life_stage),relationship,str(action.id),action.get("social_events",[]))
				target.needs.social=minf(100,target.needs.social+16)
			_sync_social_context()
			member_action_finished.emit(id,action))
	sim.notice.connect(func(message:String):
		if not restoring:notice.emit(message))

func selected() -> LifeSim:
	return null if members.is_empty() else members[selected_index].sim

func selected_id() -> String:
	return "" if members.is_empty() else members[selected_index].id

func select(index: int) -> void:
	if index<0 or index>=members.size() or index==selected_index:return
	adopt_selected_changes()
	selected_index=index
	selection_changed.emit(selected_id())

func member_sim(id: String) -> LifeSim:
	for member in members:
		if member.id==id:return member.sim
	return null

func adopt_selected_changes() -> void:
	if selected():
		funds=selected().funds
		speed=selected().speed
	_sync_wallet()

func _sync_wallet() -> void:
	for member in members:
		member.sim.funds=funds
		member.sim.speed=speed
	_sync_social_context()

func _sync_social_context() -> void:
	var partners:Dictionary={}
	var adults:Dictionary={"maya":true,"leo":true}
	for member:Dictionary in members:
		partners[member.id]=member.sim.romantic_partner
		adults[member.id]=str(member.sim.character.get("life_stage","adult"))=="adult"
		if str(member.sim.romantic_partner) in ["maya","leo"]:
			partners[member.sim.romantic_partner]=member.id
	for member:Dictionary in members:
		var reciprocal:Dictionary={}
		var family_roles:Dictionary={}
		for other:Dictionary in members:
			if other.id!=member.id and other.sim.relationships.has(str(member.id)):
				var relationship:Dictionary=other.sim.relationships[str(member.id)]
				relationship.life_stage = str(member.sim.character.life_stage)
				reciprocal[other.id]={"friendship":relationship.friendship,"romance":relationship.romance}
				family_roles[other.id]=family_relationship(str(member.id),str(other.id))
		member.sim.set_social_context(str(member.id),partners,adults,reciprocal,family_roles)

func set_funds(value: int) -> void:
	funds=maxi(value,0)
	_sync_wallet()

func set_speed(value: int) -> void:
	speed=value if value in [0,1,3,8] else 1
	_sync_wallet()

func register_targets(new_targets: Array, reconcile:bool=true) -> void:
	var paired: bool = reconcile and not cooperations.is_empty()
	if paired: _begin_cooperation_change()
	targets=new_targets.duplicate(true)
	for member in members:member.sim.register_targets(targets.filter(func(target:Dictionary):return str(target.id)!=str(member.id)),reconcile)
	if paired:
		_reconcile_cooperations()
		_end_cooperation_change()

func tick(delta: float) -> void:
	if members.is_empty():return
	var paired: bool = not cooperations.is_empty()
	if paired: _begin_cooperation_change()
	adopt_selected_changes()
	if paired and speed > 0 and delta > 0 and is_finite(delta):
		for session: Dictionary in cooperations:
			if str(session.phase) == "assembling": session.waited = float(session.waited) + minf(delta,60.0)*LifeSim.GAME_MINUTES_PER_SECOND*float(speed)
	var start_day:int=day
	var start_minutes:float=minutes
	for member in members:
		var sim:LifeSim=member.sim
		sim.day=start_day;sim.minutes=start_minutes;sim.speed=speed;sim.funds=funds
		sim.tick(delta)
		funds=sim.funds
	day=members[0].sim.day
	minutes=members[0].sim.minutes
	_sync_wallet()
	if paired:
		_reconcile_cooperations()
		_end_cooperation_change()

func begin_action(id: String) -> void:
	adopt_selected_changes()
	var sim=member_sim(id)
	if not sim:return
	sim.funds=funds
	sim.begin_current_action()
	funds=sim.funds
	_sync_wallet()

func get_state(world_data: Array = []) -> Dictionary:
	adopt_selected_changes()
	var states:Array=[]
	for member in members:states.append({"id":member.id,"state":member.sim.get_state()})
	var result:Dictionary={"household_version":2 if not journeys.is_empty() else 1,"selected_index":selected_index,"funds":funds,"day":day,"minutes":minutes,"speed":speed,"members":states,"world":world_data.duplicate(true),"family_graph":family_graph.duplicate(true),"adoptions":adoptions.duplicate(true),"cooperation_version":1,"cooperation_serial":cooperation_serial,"cooperations":cooperations.duplicate(true),"meals":meals.get_state(),"sanitation":sanitation.get_state()}
	if not journeys.is_empty():result.journeys=journeys.duplicate(true)
	if physical_snapshot_provider.is_valid():
		var physical:Dictionary=physical_snapshot_provider.call()
		if physical.has("error"):result.snapshot_error=str(physical.error)
		elif not physical.is_empty():
			result.household_version=2;result.journeys=physical.journeys.duplicate(true)
			result.world=physical.world.duplicate(true)
			for member:Dictionary in result.members:member.state.character.world_state=physical.members[str(member.id)].duplicate(true)
	return result

func get_family_links() -> Array:
	var links:Array=LifeFamilyGraph.links(family_graph)
	for first:int in range(members.size()):
		for second:int in range(first+1,members.size()):
			var relationship:Dictionary=members[first].sim.relationships[str(members[second].id)]
			if str(relationship.get("bond","none")) in ["partners","committed"]:
				links.append({"a":str(members[first].id),"b":str(members[second].id),"role":"partners"})
	return links

func family_parent_links() -> Array:
	return LifeFamilyGraph.links(family_graph).filter(func(link:Dictionary)->bool:return str(link.role)=="parent")

func family_relationship(a:String,b:String) -> String:
	var roles:Dictionary=_family_roles.get(a,{})
	return str(roles.get(b,"none"))

func _rebuild_family_roles() -> void:
	# Genealogy changes only when members or family declarations are replaced.
	# Social scores, partners, and birthdays are synchronized separately each tick.
	_family_roles.clear()
	for member:Dictionary in members:
		var roles:Dictionary={}
		for other:Dictionary in members:
			if member.id!=other.id:
				roles[str(other.id)]=LifeFamilyGraph.relationship(family_graph,str(member.id),str(other.id))
		_family_roles[str(member.id)]=roles

func configure_family(links:Array) -> Dictionary:
	# Creator declarations describe existing family, not a live-game shortcut.
	if members.is_empty() or day!=1 or absf(minutes-480.0)>.00001:
		return {"ok":false,"error":"Family setup is available before the household starts living."}
	for member:Dictionary in members:
		if not member.sim.action_queue.is_empty() or not member.sim.social_history.is_empty():
			return {"ok":false,"error":"Finish family setup before beginning household activities."}
	var by_id:Dictionary={}
	var profiles:Dictionary={}
	var states:Array=[]
	for member:Dictionary in members:
		var id:String=str(member.id)
		var snapshot:Dictionary=member.sim.get_state()
		by_id[id]=snapshot
		profiles[id]=snapshot.character
		states.append({"id":id,"state":snapshot})
	var built:Dictionary=LifeFamilyGraph.create(profiles,links)
	if not bool(built.ok):return built
	var graph:Dictionary=built.graph
	# Validate detached snapshots before changing the graph, relationships, or Nodes.
	for entry:Dictionary in states:
		entry.state.romantic_partner=""
		for other:Dictionary in states:
			if entry.id==other.id:continue
			var relationship:Dictionary=entry.state.relationships[str(other.id)]
			var role:String=LifeFamilyGraph.relationship(graph,str(entry.id),str(other.id))
			var related:bool=LifeFamilyGraph.is_family(role)
			relationship.family_role=role
			relationship.bond="none"
			relationship.friendship=55.0 if related else 18.0
			relationship.romance=0.0
			relationship.milestones=["met","friends"] if related else []
			relationship.status=LifeFamilyGraph.label(role)
	for link:Dictionary in built.partners:
		var a:String=str(link.a)
		var b:String=str(link.b)
		if str(by_id[a].character.life_stage)!="adult" or str(by_id[b].character.life_stage)!="adult":
			return {"ok":false,"error":"A partnership requires two adult Lifelets."}
		if not str(by_id[a].romantic_partner).is_empty() or not str(by_id[b].romantic_partner).is_empty():
			return {"ok":false,"error":"A Lifelet can begin with one partner."}
		by_id[a].romantic_partner=b
		by_id[b].romantic_partner=a
		for pair:Array in [[a,b],[b,a]]:
			var relationship:Dictionary=by_id[str(pair[0])].relationships[str(pair[1])]
			relationship.bond="partners"
			relationship.friendship=60.0
			relationship.romance=50.0
			relationship.milestones=["met","friends","spark"]
			relationship.status="Partner"
	var candidate:Dictionary={"household_version":1,"selected_index":selected_index,"funds":funds,"day":day,"minutes":minutes,"speed":speed,"members":states,"world":[],"family_graph":graph}
	var validator:LifeHousehold=LifeHousehold.new()
	var validation:Dictionary=validator.restore_state(candidate)
	validator.free()
	if not bool(validation.ok):return validation
	family_graph=graph.duplicate(true)
	_rebuild_family_roles()
	for member:Dictionary in members:
		member.sim.relationships=by_id[str(member.id)].relationships.duplicate(true)
		member.sim.romantic_partner=str(by_id[str(member.id)].romantic_partner)
	_sync_social_context()
	for member:Dictionary in members:member.sim.changed.emit()
	return {"ok":true}

func save_game(world_data: Array = []) -> bool:
	var data=get_state(world_data)
	var temp_path=SAVE_PATH+".tmp"
	var file=FileAccess.open(temp_path,FileAccess.WRITE)
	if not file:return false
	file.store_string(JSON.stringify(json_safe(data),"  "))
	file.flush();file.close()
	var error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),ProjectSettings.globalize_path(SAVE_PATH))
	return error==OK

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):return {"ok":false,"error":"No saved household yet."}
	var file=FileAccess.open(SAVE_PATH,FileAccess.READ)
	if not file or file.get_length()>8*1024*1024:return {"ok":false,"error":"The household save could not be read."}
	var parser=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return {"ok":false,"error":"The household save is damaged."}
	return restore_state(parser.data)

func restore_state(data: Dictionary) -> Dictionary:
	if data.has("snapshot_error"):return {"ok":false,"error":"Cannot restore an incomplete live physical snapshot: "+str(data.snapshot_error)}
	data=data.duplicate(true)
	# Single-Lifelet saves from the first playable version are accepted.
	if data.has("version") and not data.has("household_version"):
		if data.has("journeys"):return {"ok":false,"error":"A legacy save cannot contain versioned journeys."}
		var legacy_state:Dictionary=data.duplicate(true)
		if legacy_state.get("relationships") is Dictionary:
			for relation_id:Variant in legacy_state.relationships.keys():
				if str(relation_id)=="player" or str(relation_id).begins_with("housemate_"):legacy_state.relationships.erase(relation_id)
		data={"household_version":1,"selected_index":0,"funds":data.get("funds",2500),"members":[{"id":"player","state":legacy_state}],"world":data.get("world",[])}
	if not LifeJourneyState.number(data.get("household_version"),1,2,true) or not data.get("members") is Array:return {"ok":false,"error":"This household save uses an unsupported format."}
	if data.members.is_empty() or data.members.size()>MAX_MEMBERS or not data.get("world",[]) is Array:return {"ok":false,"error":"The saved household has invalid members."}
	if (data.get("household_version")==2)!=data.has("journeys"):return {"ok":false,"error":"The household and journey save versions disagree."}
	if data.get("household_version")==2:
		for key:String in ["selected_index","funds","day","minutes","speed","world"]:
			if not data.has(key):return {"ok":false,"error":"The physical household save is missing "+key+"."}
	var identity_error:String=_validate_member_identity(data)
	if not identity_error.is_empty():return {"ok":false,"error":identity_error}
	var family_result:Dictionary=_prepare_saved_family(data)
	if not bool(family_result.ok):return family_result
	var candidates:Array=[]
	var ids:Array=[]
	for entry in data.members:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("state") is Dictionary or ids.has(entry.id):
			for c in candidates:c.sim.free()
			return {"ok":false,"error":"The saved household has an invalid Lifelet."}
		var sim=LifeSim.new()
		var result=sim.restore_state(entry.state,true)
		if not result.ok:
			sim.free()
			for c in candidates:c.sim.free()
			return result
		ids.append(entry.id);candidates.append({"id":entry.id,"sim":sim})
	var cooperation_error: String = _validate_saved_cooperations(data)
	if not cooperation_error.is_empty():
		for candidate: Dictionary in candidates: candidate.sim.free()
		return {"ok":false,"error":cooperation_error}
	var selected_value:Variant=data.get("selected_index",0)
	if not (selected_value is int or selected_value is float) or not is_finite(float(selected_value)) or float(selected_value)!=floorf(float(selected_value)) or int(selected_value)<0 or int(selected_value)>=candidates.size():
		for c in candidates:c.sim.free()
		return {"ok":false,"error":"The selected Lifelet is invalid."}
	var lead:LifeSim=candidates[int(selected_value)].sim
	for field:String in ["funds","day","minutes","speed"]:
		var expected:float=float(lead.get(field))
		var saved_value:Variant=data.get(field,expected)
		if not (saved_value is int or saved_value is float) or not is_finite(float(saved_value)) or absf(float(saved_value)-expected)>.00001:
			for c in candidates:c.sim.free()
			return {"ok":false,"error":"The saved household has inconsistent shared %s." % field}
		for candidate:Dictionary in candidates:
			if absf(float(candidate.sim.get(field))-expected)>.00001:
				for c in candidates:c.sim.free()
				return {"ok":false,"error":"The saved Lifelets do not share the same %s." % field}
	var adoption_error:String=LifeAdoption.validate(data.get("adoptions",LifeAdoption.fresh()),data)
	if not adoption_error.is_empty():
		for candidate:Dictionary in candidates:candidate.sim.free()
		return {"ok":false,"error":adoption_error}
	var journey_result:Dictionary={"ok":true}
	if data.has("journeys"):
		journey_result=LifeJourneyState.validate(data.journeys,data)
		if bool(journey_result.ok):
			var physical_error:String=LifeJourneyState.validate_actions(data)
			if not physical_error.is_empty():journey_result={"ok":false,"error":physical_error}
		if not bool(journey_result.ok):
			for candidate:Dictionary in candidates:candidate.sim.free()
			return journey_result
	var sanitation_data:Variant=data.get("sanitation",LifeSanitation.fresh())
	var sanitation_error:String=LifeSanitation.validate(sanitation_data,ids,data.members,(lead.day-1)*1440.0+lead.minutes)
	if sanitation_error.is_empty():sanitation_error=LifeSanitation.validate_layout(sanitation_data,data)
	if not sanitation_error.is_empty():
		for candidate:Dictionary in candidates:candidate.sim.free()
		return {"ok":false,"error":sanitation_error}
	var visit_error:String=LifeHomeVisit.validate_saved(data)
	if not visit_error.is_empty():
		for candidate:Dictionary in candidates:candidate.sim.free()
		return {"ok":false,"error":visit_error}
	var guest:Dictionary={}
	var saved_visit:Variant=LifeHomeVisit.saved_visit(data)
	if saved_visit!=null and not saved_visit.value.visit.is_empty():guest=saved_visit.value.visit
	var meal_data: Variant = data.get("meals",LifeMeals.new().get_state())
	var meal_error: String = LifeMeals.validate(meal_data,ids,(lead.day-1)*1440.0+lead.minutes,guest)
	if meal_error.is_empty():meal_error=LifeMeals.validate_actions(meal_data,data.members,journey_result.get("custody",{}),str(journey_result.get("venue","")),guest)
	if meal_error.is_empty():meal_error=LifeMeals.validate_layout(meal_data,data)
	if not meal_error.is_empty():
		for c in candidates:c.sim.free()
		return {"ok":false,"error":meal_error}
	restoring=true
	journeys=data.get("journeys",{}).duplicate(true)
	if not journeys.is_empty():
		for index:int in candidates.size():
			for action_index:int in candidates[index].sim.action_queue.size():
				candidates[index].sim.action_queue[action_index].phase=data.members[index].state.action_queue[action_index].phase
	adoptions=data.get("adoptions",LifeAdoption.fresh()).duplicate(true)
	meals.restore(meal_data)
	sanitation.restore(sanitation_data)
	for old in members:old.sim.queue_free()
	members=candidates
	# The saved world is rebuilt after restoration; old target IDs belong to the previous venue.
	targets=[]
	cooperations=data.get("cooperations",[]).duplicate(true)
	cooperation_serial=int(data.get("cooperation_serial",0))
	for session: Dictionary in cooperations:
		session.phase="assembling"
		session.ready=[]
	family_graph=family_result.graph.duplicate(true)
	_rebuild_family_roles()
	selected_index=int(selected_value)
	funds=members[selected_index].sim.funds
	day=members[selected_index].sim.day;minutes=members[selected_index].sim.minutes;speed=members[selected_index].sim.speed
	for i in range(members.size()):
		var member:Dictionary=members[i]
		add_child(member.sim)
		member.sim.name="Life_"+member.id
		member.sim.household_bills_enabled=i==0
		connect_member(member.id,member.sim)
		if not targets.is_empty(): member.sim.register_targets(targets.filter(func(target:Dictionary):return str(target.id)!=str(member.id)))
	_sync_wallet()
	restoring=false
	return {"ok":true,"world":data.get("world",[]).duplicate(true)}

func _prepare_saved_family(data:Dictionary) -> Dictionary:
	var ids:Array[String]=[]
	for entry:Dictionary in data.members:ids.append(str(entry.id))
	for entry:Dictionary in data.members:
		for target:String in entry.state.relationships:
			if not ids.has(target) and str(entry.state.relationships[target].get("family_role","none"))!="none":
				return {"ok":false,"error":"The family graph cannot declare relatives outside this household."}
	var legacy:bool=not data.has("family_graph")
	var graph:Dictionary=LifeFamilyGraph.fresh()
	if not legacy:
		var error:String=LifeFamilyGraph.validate(data.family_graph,ids)
		if not error.is_empty():return {"ok":false,"error":error}
		graph=LifeFamilyGraph.canonical(data.family_graph,ids)
	else:
		for index:int in range(ids.size()):
			for other_index:int in range(index+1,ids.size()):
				var relation:Dictionary=data.members[index].state.relationships[ids[other_index]]
				var role:String=str(relation.get("family_role","none"))
				if role not in ["none","siblings"]:return {"ok":false,"error":"The save is missing its directed family graph."}
				if role=="siblings":graph.siblings.append({"a":ids[index],"b":ids[other_index]})
		graph=LifeFamilyGraph.canonical(graph,ids)
	for index:int in range(ids.size()):
		for other_index:int in range(ids.size()):
			if index==other_index:continue
			var relation:Dictionary=data.members[index].state.relationships[ids[other_index]]
			var role:String=LifeFamilyGraph.relationship(graph,ids[index],ids[other_index])
			if not legacy and str(relation.get("family_role","none"))!=role:
				return {"ok":false,"error":"The saved relationship roles do not match the family graph."}
			# Legacy declarations may imply additional siblings. Preserve all numeric
			# history so individual validation rejects any conflicting romantic state.
			relation.family_role=role
			if LifeFamilyGraph.is_family(role):relation.status=LifeFamilyGraph.label(role)
	return {"ok":true,"graph":graph}

func _validate_member_identity(data:Dictionary) -> String:
	var expected_ids:Array[String]=[]
	var neighbor_partners:Dictionary={}
	for index:int in range(data.members.size()):
		expected_ids.append("player" if index==0 else "housemate_%d" % index)
	for index:int in range(data.members.size()):
		var entry:Variant=data.members[index]
		if not entry is Dictionary or entry.get("id")!=expected_ids[index] or not entry.get("state") is Dictionary:
			return "The saved household has an invalid Lifelet identity."
		var relations:Variant=entry.state.get("relationships")
		if not relations is Dictionary:return "The saved household has invalid relationships."
		if relations.has(expected_ids[index]):return "A Lifelet cannot have a relationship with their own household identity."
		for other_index:int in range(expected_ids.size()):
			if other_index==index:continue
			var other_entry:Variant=data.members[other_index]
			if not other_entry is Dictionary or not other_entry.get("state") is Dictionary or not other_entry.state.get("character") is Dictionary:
				return "The saved household has an invalid Lifelet profile."
			var relationship:Variant=relations.get(expected_ids[other_index])
			if not relationship is Dictionary or relationship.get("name")!=other_entry.state.character.get("name"):
				return "The saved household is missing a matching housemate relationship."
			var reverse_relations:Variant=other_entry.state.get("relationships")
			if not reverse_relations is Dictionary or not reverse_relations.get(expected_ids[index]) is Dictionary:
				return "The saved household is missing a reciprocal housemate relationship."
			if LifeFamilyGraph.inverse(str(relationship.get("family_role","none")))!=str(reverse_relations[expected_ids[index]].get("family_role","none")):
				return "The saved household has one-sided family roles."
		for relation_id:Variant in relations:
			if not relation_id is String or (str(relation_id) not in ["maya","leo"] and str(relation_id) not in expected_ids):
				return "The saved household contains an unknown relationship identity."
		var partner_id:String=str(entry.state.get("romantic_partner",""))
		if partner_id in expected_ids:
			var partner_entry:Dictionary=data.members[expected_ids.find(partner_id)]
			if str(partner_entry.state.get("romantic_partner",""))!=expected_ids[index]:
				return "The saved household contains a one-sided partnership."
			var peer_relations:Variant=partner_entry.state.get("relationships")
			if not peer_relations is Dictionary or not peer_relations.get(expected_ids[index]) is Dictionary:
				return "The saved household contains a missing reciprocal relationship."
			if str(peer_relations[expected_ids[index]].get("bond","none"))!=str(relations[partner_id].get("bond","none")):
				return "The saved household contains mismatched partnership stages."
		elif partner_id in ["maya","leo"]:
			if neighbor_partners.has(partner_id):return "A neighbor cannot have two household partners."
			neighbor_partners[partner_id]=expected_ids[index]
	return ""

func json_safe(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Color:return value.to_html()
	if value is Array:
		var result:Array=[]
		for item in value:result.append(json_safe(item))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=json_safe(value[key])
		return result
	return value

func set_aging(lifespan: String, enabled: bool) -> bool:
	if lifespan not in LifeLifecycle.SPANS: return false
	for member: Dictionary in members:
		member.sim.set_aging(lifespan, enabled)
	return true

# Cooperative homework has one authoritative clock: the learner's ordinary
# homework action. Its helper action cannot advance or finish independently.
func homework_helpers(learner_id: String, furniture_id: String) -> Array:
	var result: Array = []
	for member: Dictionary in members:
		if str(member.id) == learner_id: continue
		var reason: String = _homework_pair_error(learner_id,str(member.id),furniture_id,true)
		result.append({"id":str(member.id),"name":str(member.sim.character.name),"available":reason.is_empty(),"reason":reason,"parenting_level":int(member.sim.skills.parenting.level)})
	return result

func _target_kind(id: String) -> String:
	for target: Dictionary in targets:
		if str(target.id) == id: return str(target.kind)
	return ""

func _homework_pair_error(learner_id: String, helper_id: String, furniture_id: String, require_idle: bool) -> String:
	var learner: LifeSim = member_sim(learner_id)
	var helper: LifeSim = member_sim(helper_id)
	if learner == null or helper == null or learner == helper: return "Choose two different members of this household."
	if str(learner.character.age_stage) not in LifeEducation.SCHOOL_STAGES: return "Only children and teens have homework."
	if str(helper.character.age_stage) not in ["young_adult","adult","elder"] or str(helper.character.life_stage) != "adult": return "Choose an adult caregiver."
	if _target_kind(learner_id) != "neighbor" or _target_kind(helper_id) != "neighbor": return "Both Lifelets must be present at this destination."
	if _target_kind(furniture_id) not in ["desk","computer"]: return "Choose a desk or computer for homework together."
	if minf(float(learner.relationships[helper_id].friendship),float(helper.relationships[learner_id].friendship)) < 20.0: return "Build at least 20 friendship in both directions before studying together."
	if require_idle:
		if not learner.action_queue.is_empty() or not helper.action_queue.is_empty(): return "Both Lifelets must finish or cancel their current plans first."
		for session: Dictionary in cooperations:
			if str(session.furniture_id) == furniture_id: return "That desk already has a homework session."
		return learner._school_availability("homework",furniture_id)
	return ""

func queue_supported_homework(learner_id: String, helper_id: String, furniture_id: String, learner_position: Vector3 = Vector3.ZERO, helper_position: Vector3 = Vector3.ZERO) -> Dictionary:
	var reason: String = _homework_pair_error(learner_id,helper_id,furniture_id,true)
	if not reason.is_empty(): return {"ok":false,"error":reason}
	if not learner_position.is_finite() or not helper_position.is_finite(): return {"ok":false,"error":"The homework approach positions are invalid."}
	var learner: LifeSim = member_sim(learner_id)
	var helper: LifeSim = member_sim(helper_id)
	_begin_cooperation_change()
	cooperation_serial += 1
	var token: String = "homework_%d" % cooperation_serial
	var session: Dictionary = {"id":token,"learner_id":learner_id,"helper_id":helper_id,"furniture_id":furniture_id,"day":day,"created_minutes":minutes,"learner_stage":str(learner.character.age_stage),"parenting_level":int(helper.skills.parenting.level),"phase":"assembling","ready":[],"waited":0.0,"learner_position":[learner_position.x,learner_position.y,learner_position.z],"helper_position":[helper_position.x,helper_position.y,helper_position.z]}
	cooperations.append(session)
	for role: String in ["learner","helper"]:
		var actor: LifeSim = learner if role == "learner" else helper
		var id: String = "homework" if role == "learner" else "help_homework"
		var action: Dictionary = actor._actions[id].duplicate(true)
		action.merge({"target_id":furniture_id,"target_kind":_target_kind(furniture_id),"target_position":learner_position if role == "learner" else helper_position,"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":false,"cooperation_id":token,"cooperation_role":role})
		actor.action_queue.append(action)
		actor._idle_minutes=0.0
		actor._start_front()
		actor._emit_changed()
	_end_cooperation_change()
	return {"ok":true,"session_id":token}

func _member_cooperation(member_id: String) -> Dictionary:
	for session: Dictionary in cooperations:
		if member_id in [str(session.learner_id),str(session.helper_id)]: return session
	return {}

func _cooperation(token: String) -> Dictionary:
	for session: Dictionary in cooperations:
		if str(session.id) == token: return session
	return {}

func cooperative_presentation(member_id: String) -> Dictionary:
	var session: Dictionary = _member_cooperation(member_id)
	if session.is_empty(): return {}
	var learner: LifeSim = member_sim(str(session.learner_id))
	var action: Dictionary = learner.get_current_action()
	var role: String = "learner" if member_id == str(session.learner_id) else "helper"
	return {"session_id":str(session.id),"role":role,"phase":str(session.phase),"ready":session.ready.has(member_id),"partner_id":str(session.helper_id) if role == "learner" else str(session.learner_id),"learner_id":str(session.learner_id),"helper_id":str(session.helper_id),"furniture_id":str(session.furniture_id),"elapsed":float(action.get("elapsed",0.0)),"duration":45.0,"progress":float(action.get("progress",0.0)),"learner_position":Vector3(session.learner_position[0],session.learner_position[1],session.learner_position[2]),"helper_position":Vector3(session.helper_position[0],session.helper_position[1],session.helper_position[2])}

func mark_cooperative_ready(member_id: String) -> void:
	var session: Dictionary = _member_cooperation(member_id)
	if session.is_empty() or str(session.phase) != "assembling": return
	_begin_cooperation_change()
	var reason: String = _cooperation_error(session)
	if not reason.is_empty():
		_cancel_cooperation(session,reason)
	else:
		if not session.ready.has(member_id): session.ready.append(member_id)
		if session.ready.size() == 2:
			session.phase="active"
			for id: String in [str(session.learner_id),str(session.helper_id)]:
				var actor: LifeSim = member_sim(id)
				var action: Dictionary = actor.get_current_action()
				action.phase="active"
				action.paid=true
				if not action.has("started_minutes"):
					action.started_day=day
					action.started_minutes=minutes
				actor._emit_changed()
		else:
			member_sim(member_id)._emit_changed()
	_end_cooperation_change()

func cancel_cooperative_action(member_id: String) -> bool:
	var session: Dictionary = _member_cooperation(member_id)
	if session.is_empty(): return false
	_begin_cooperation_change()
	_cancel_cooperation(session,"Homework together was cancelled. The assignment is still available today.")
	_end_cooperation_change()
	return true

func _cancel_cooperation(session: Dictionary, reason: String) -> void:
	cooperations.erase(session)
	for id: String in [str(session.learner_id),str(session.helper_id)]:
		var actor: LifeSim = member_sim(id)
		if actor == null: continue
		var front_removed: bool = not actor.action_queue.is_empty() and str(actor.action_queue[0].get("cooperation_id","")) == str(session.id)
		for index: int in range(actor.action_queue.size()-1,-1,-1):
			if str(actor.action_queue[index].get("cooperation_id","")) == str(session.id): actor.action_queue.remove_at(index)
		if front_removed: actor._start_front()
		actor._emit_changed()
	var learner: LifeSim = member_sim(str(session.learner_id))
	if learner != null and not reason.is_empty(): learner._emit_notice(reason)

func _cooperation_error(session: Dictionary) -> String:
	var reason: String = _homework_pair_error(str(session.learner_id),str(session.helper_id),str(session.furniture_id),false)
	if not reason.is_empty(): return reason
	var learner: LifeSim = member_sim(str(session.learner_id))
	if str(learner.character.age_stage) != str(session.learner_stage) or learner.day != int(session.day): return "A new school day or age stage ends the shared assignment."
	if str(session.phase) == "assembling" and float(session.waited) >= COOPERATION_WAIT_LIMIT: return "The Lifelets could not meet within an hour. Choose a fresh homework plan."
	for role: String in ["learner","helper"]:
		var actor: LifeSim = learner if role == "learner" else member_sim(str(session.helper_id))
		var action: Dictionary = actor.get_current_action()
		if str(action.get("cooperation_id","")) != str(session.id) or str(action.get("cooperation_role","")) != role or str(action.get("target_id","")) != str(session.furniture_id): return "One Lifelet's homework plans changed."
	return learner._school_action_error(learner.get_current_action())

func _reconcile_cooperations() -> void:
	for session: Dictionary in cooperations.duplicate():
		var reason: String = _cooperation_error(session)
		if not reason.is_empty():
			_cancel_cooperation(session,reason)
			continue
		var learner: LifeSim = member_sim(str(session.learner_id))
		var helper: LifeSim = member_sim(str(session.helper_id))
		var source: Dictionary = learner.get_current_action()
		var mirror: Dictionary = helper.get_current_action()
		mirror.elapsed=float(source.elapsed)
		mirror.progress=float(source.progress)

func before_member_notification() -> void:
	if _cooperation_depth > 0 or restoring or cooperations.is_empty(): return
	_begin_cooperation_change()
	_reconcile_cooperations()
	_sync_social_context()
	_end_cooperation_change()

func _begin_cooperation_change() -> void:
	_cooperation_depth += 1
	for member: Dictionary in members: member.sim.begin_notifications()

func _end_cooperation_change() -> void:
	_cooperation_depth = maxi(0,_cooperation_depth-1)
	var batches: Array = []
	for member: Dictionary in members:
		batches.append({"sim":member.sim,"events":member.sim.release_notifications()})
	for batch: Dictionary in batches: batch.sim.dispatch_notifications(batch.events)

func finish_cooperative_homework(token: String) -> void:
	var session: Dictionary = _cooperation(token)
	if session.is_empty(): return
	_begin_cooperation_change()
	var reason: String = _cooperation_error(session)
	var learner: LifeSim = member_sim(str(session.learner_id))
	var helper: LifeSim = member_sim(str(session.helper_id))
	if reason.is_empty() and (str(session.phase) != "active" or float(learner.get_current_action().elapsed) < 45.0): reason="Both Lifelets must complete the assignment together."
	if not reason.is_empty():
		_cancel_cooperation(session,reason)
		_end_cooperation_change()
		return
	var result: Dictionary = LifeEducation.complete(learner.education,str(learner.character.age_stage),learner.day,learner.minutes,"homework")
	if not bool(result.ok):
		_cancel_cooperation(session,str(result.error))
		_end_cooperation_change()
		return
	# Remove both reservations before any result notification can be observed.
	cooperations.erase(session)
	var learner_action: Dictionary = learner.action_queue.pop_front()
	var helper_action: Dictionary = helper.action_queue.pop_front()
	learner._apply_education_result(result)
	learner._gain_skill("logic",4.0+float(mini(int(session.parenting_level)-1,4)))
	helper._gain_skill("parenting",20.0)
	learner.needs.social=minf(100.0,float(learner.needs.social)+8.0)
	learner.needs.fun=minf(100.0,float(learner.needs.fun)+5.0)
	helper.needs.social=minf(100.0,float(helper.needs.social)+8.0)
	helper.needs.energy=maxf(0.0,float(helper.needs.energy)-4.0)
	for pair: Array in [[learner,helper,str(session.helper_id)],[helper,learner,str(session.learner_id)]]:
		var actor: LifeSim = pair[0]
		var partner: LifeSim = pair[1]
		var target: String = str(pair[2])
		actor.relationships[target].friendship=minf(100.0,float(actor.relationships[target].friendship)+6.0)
		actor._record_social_milestones(target,"help_homework")
		actor._update_relationship_status(actor.relationships[target])
		actor.remember("Learning together","Completed homework together with %s." % str(partner.character.name))
		actor.add_moodlet("Learning together","Focused","A little support made this assignment easier.",120,1)
	learner._activity_memory("homework")
	learner._record_chapter_activity("homework",0)
	_sync_social_context()
	for entry: Array in [[learner,learner_action],[helper,helper_action]]:
		var actor: LifeSim = entry[0]
		var action: Dictionary = entry[1]
		action.phase="finished";action.elapsed=45.0;action.progress=1.0
		actor._emit_action_finished(action)
		actor._idle_minutes=0.0
		actor._update_wants()
		actor._start_front()
		actor._emit_changed()
	_end_cooperation_change()

func _cooperation_number(value: Variant, minimum: float, maximum: float, integer: bool = false) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)): return false
	return float(value) >= minimum and float(value) <= maximum and (not integer or float(value) == floorf(float(value)))

func _cooperation_position(value: Variant) -> bool:
	if value is Vector3: return value.is_finite() and maxf(absf(value.x),maxf(absf(value.y),absf(value.z))) <= 100000.0
	if not value is Array or value.size() != 3: return false
	for component: Variant in value:
		if not _cooperation_number(component,-100000.0,100000.0): return false
	return true

func _cooperation_vector(value: Variant) -> Vector3:
	return value if value is Vector3 else Vector3(value[0],value[1],value[2])

func _validate_saved_cooperations(data: Dictionary) -> String:
	var sessions: Variant = data.get("cooperations",[])
	if not sessions is Array or sessions.size() > MAX_MEMBERS/2: return "Save contains invalid cooperative homework sessions."
	if not _cooperation_number(data.get("cooperation_version",1),1,1,true) or not _cooperation_number(data.get("cooperation_serial",0),0,1000000000,true): return "Save contains an invalid cooperation version or identity counter."
	var by_id: Dictionary = {}
	for entry: Dictionary in data.members: by_id[str(entry.id)] = entry.state
	var used_members: Array[String] = []
	var used_desks: Array[String] = []
	var used_tokens: Array[String] = []
	var bound_actions: int = 0
	for session: Variant in sessions:
		if not session is Dictionary: return "Save contains an invalid homework session."
		for key: String in ["id","learner_id","helper_id","furniture_id","learner_stage","phase"]:
			if not session.get(key) is String: return "Save contains an invalid homework identity."
		var token: String = str(session.id)
		var suffix: String = token.trim_prefix("homework_")
		if not token.begins_with("homework_") or not suffix.is_valid_int() or str(int(suffix)) != suffix or int(suffix) < 1 or int(suffix) > int(data.get("cooperation_serial",0)) or used_tokens.has(token): return "Save contains a duplicate or invalid homework token."
		used_tokens.append(token)
		var learner_id: String = str(session.learner_id)
		var helper_id: String = str(session.helper_id)
		if learner_id == helper_id or not by_id.has(learner_id) or not by_id.has(helper_id) or used_members.has(learner_id) or used_members.has(helper_id): return "Save assigns a Lifelet to impossible or overlapping homework sessions."
		used_members.append_array([learner_id,helper_id])
		if str(session.furniture_id).is_empty() or used_desks.has(str(session.furniture_id)) or by_id.has(str(session.furniture_id)): return "Save assigns multiple homework pairs to one desk."
		used_desks.append(str(session.furniture_id))
		var learner: Dictionary = by_id[learner_id]
		var helper: Dictionary = by_id[helper_id]
		if str(session.learner_stage) not in LifeEducation.SCHOOL_STAGES or LifeLifecycle.stage_for(learner.character) != str(session.learner_stage) or LifeLifecycle.stage_for(helper.character) not in ["young_adult","adult","elder"] or str(helper.character.get("life_stage","")) != "adult": return "Save contains an age-ineligible homework pair."
		if minf(float(learner.relationships[helper_id].get("friendship",-100)),float(helper.relationships[learner_id].get("friendship",-100))) < 20.0: return "Save contains a homework pair without mutual trust."
		if not _cooperation_number(session.get("day"),float(learner.day),float(learner.day),true) or not _cooperation_number(session.get("created_minutes"),0,float(learner.minutes)) or not _cooperation_number(session.get("waited"),0,COOPERATION_WAIT_LIMIT-.000001): return "Save contains an expired or invalid homework meeting."
		if float(session.waited) > float(learner.minutes)-float(session.created_minutes)+.001: return "Save contains impossible homework waiting time."
		var level: Variant = helper.get("skills",{}).get("parenting",{}).get("level",1)
		if not _cooperation_number(session.get("parenting_level"),1,10,true) or float(session.parenting_level) > float(level): return "Save contains inconsistent caregiver skill."
		if str(session.phase) not in ["assembling","active"] or not session.get("ready") is Array or session.ready.size() > 2: return "Save contains an invalid homework meeting phase."
		var ready: Array = []
		for id: Variant in session.ready:
			if not id is String or str(id) not in [learner_id,helper_id] or ready.has(id): return "Save contains invalid homework arrival flags."
			ready.append(id)
		if str(session.phase) == "active" and ready.size() != 2: return "Save starts homework before both Lifelets arrive."
		for key: String in ["learner_position","helper_position"]:
			if not _cooperation_position(session.get(key)): return "Save contains invalid shared-homework approach positions."
		var actions: Array = []
		for role: String in ["learner","helper"]:
			var state: Dictionary = learner if role == "learner" else helper
			if not state.get("action_queue") is Array or state.action_queue.is_empty() or not state.action_queue[0] is Dictionary: return "Save is missing a paired homework action."
			var action: Dictionary = state.action_queue[0]
			if str(action.get("id","")) != ("homework" if role == "learner" else "help_homework") or action.get("cooperation_id") != token or action.get("cooperation_role") != role or action.get("target_id") != session.furniture_id or str(action.get("target_kind","")) not in ["desk","computer"]: return "Save links a homework session to the wrong action or furniture."
			if not _cooperation_position(action.get("target_position")) or not _cooperation_vector(action.target_position).is_equal_approx(_cooperation_vector(session[role+"_position"])): return "Save contains mismatched homework approach positions."
			if not _cooperation_number(action.get("duration"),45,45) or not _cooperation_number(action.get("elapsed"),0,45-.000001) or not action.get("paid") is bool or bool(action.get("autonomous",false)): return "Save contains invalid paired homework progress."
			if str(action.get("phase","")) != ("active" if str(session.phase) == "active" else "approach"): return "Save contains inconsistent paired action phases."
			actions.append(action)
			bound_actions += 1
		if bool(actions[0].paid) != bool(actions[1].paid) or absf(float(actions[0].elapsed)-float(actions[1].elapsed)) > .00001: return "Save contains two different homework clocks."
		if str(session.phase) == "active" and not bool(actions[0].paid): return "Save contains homework that never began."
		if bool(actions[0].paid):
			if actions[0].get("started_day") != actions[1].get("started_day") or actions[0].get("started_minutes") != actions[1].get("started_minutes"): return "Save contains different homework start times."
		else:
			if float(actions[0].elapsed) != 0 or float(actions[1].elapsed) != 0: return "Save contains homework progress before arrival."
		# The learner's normal school validator checks paid progress and schedule.
		if not bool(actions[0].paid):
			for option: Dictionary in LifeEducation.actions(learner.education,str(session.learner_stage),int(learner.day),float(learner.minutes)):
				if str(option.id) == "homework" and not bool(option.available): return "Save contains homework queued outside its schedule."
	var actual_actions: int = 0
	for member_id: String in by_id:
		var state: Dictionary = by_id[member_id]
		if not state.get("action_queue",[]) is Array: return "Save contains an invalid action queue."
		for index: int in range(state.get("action_queue",[]).size()):
			var action: Variant = state.action_queue[index]
			if not action is Dictionary: continue
			if action.has("cooperation_id") or action.has("cooperation_role") or str(action.get("id","")) == "help_homework":
				actual_actions += 1
				if index != 0 or not used_members.has(member_id) or not used_tokens.has(str(action.get("cooperation_id",""))): return "Save contains an orphaned or delayed paired action."
	if actual_actions != bound_actions: return "Save contains mismatched homework sessions and actions."
	return ""


func adoption_availability(guardians:Array) -> String:
	if members.size()>=MAX_MEMBERS:return "Your household already has eight Lifelets."
	if selected().funds<LifeAdoption.FEE:return "Adoption costs §1,000. Your household needs more funds."
	if guardians.is_empty() or guardians.size()>2:return "Choose one or two adult guardians."
	var seen:Array=[]
	for id:Variant in guardians:
		if not id is String or seen.has(id):return "Choose different adult guardians."
		var guardian:LifeSim=member_sim(str(id))
		if guardian==null or str(guardian.character.life_stage)!="adult":return "An adult Lifelet must become the child's guardian."
		if guardian.is_away():return "All chosen guardians must be home before adoption."
		seen.append(id)
	return ""

func prepare_adoption(guardians:Array,choice:int) -> Dictionary:
	var reason:String=adoption_availability(guardians)
	if not reason.is_empty():return {"ok":false,"error":reason}
	if choice<0 or choice>=LifeAdoption.CANDIDATE_COUNT:return {"ok":false,"error":"Choose a child to review."}
	return {"ok":true,"request":{"serial":int(adoptions.next_serial),"choice":choice,"member_count":members.size(),"fee":LifeAdoption.FEE,"guardians":guardians.duplicate()}}

func commit_adoption(request:Dictionary,spawn:Vector3,destination:Vector3,world_data:Array) -> Dictionary:
	var reason:String=LifeAdoption.request_error(request)
	if not reason.is_empty():return {"ok":false,"error":reason}
	# Returning the original receipt makes a repeated confirmation harmless.
	for event:Dictionary in adoptions.events:
		if int(event.serial)==int(request.serial):
			if int(event.choice)==int(request.choice) and event.guardians==request.guardians:return {"ok":true,"duplicate":true,"child":str(event.child)}
			return {"ok":false,"error":"That adoption review has already been used. Open the phone again."}
	if int(request.serial)!=int(adoptions.next_serial) or int(request.member_count)!=members.size():return {"ok":false,"error":"Your household changed. Please review the adoption again."}
	reason=adoption_availability(request.guardians)
	if not reason.is_empty():return {"ok":false,"error":reason}
	if not LifeAdoption.point(spawn) or not LifeAdoption.point(destination):return {"ok":false,"error":"A safe arrival route is required."}
	var snapshot:Dictionary=get_state(world_data)
	if snapshot.has("snapshot_error"):return {"ok":false,"error":str(snapshot.snapshot_error)}
	var id:String="housemate_%d" % members.size()
	var child:=LifeSim.new()
	child.new_household(LifeAdoption.candidate(int(request.serial),int(request.choice)))
	child.day=day;child.minutes=minutes;child.funds=funds-LifeAdoption.FEE;child.speed=speed
	child.education=LifeEducation.fresh("child",day);child.education.first_class_day=day+1
	child.career.schedule=LifeCareerSchedule.fresh(day)
	child._story_generated_day=day
	var guardian:LifeSim=member_sim(str(request.guardians[0]))
	child.set_aging(str(guardian.lifecycle.lifespan),bool(guardian.lifecycle.auto_age))
	child.character.world_state={"player":[spawn.x,spawn.y,spawn.z],"player_rotation":PI,"resource_wait_started":-1.0,"resource_action_active":false,"waiting_action_id":"arrive_home","waiting_target_id":"lot_exit"}
	var arrival:Dictionary=child._actions.arrive_home.duplicate(true)
	arrival.merge({"target_id":"lot_exit","target_kind":"lot_exit","target_position":destination,"elapsed":0.0,"progress":0.0,"phase":"approach","paid":false,"autonomous":false,"adoption_serial":int(request.serial)},true)
	child.action_queue.append(arrival)
	var child_state:Dictionary=child.get_state();child.free()
	for entry:Dictionary in snapshot.members:entry.state.funds=funds-LifeAdoption.FEE
	snapshot.members.append({"id":id,"state":child_state});snapshot.funds=funds-LifeAdoption.FEE
	if snapshot.has("journeys"):
		var journey_identity:int=int(snapshot.journeys.next_identity)
		snapshot.journeys.next_identity=journey_identity+1
		snapshot.journeys.members[id]={"position":LifeJourneyState.packed(spawn),"yaw":PI,"motion":{"phase":"route","identity":journey_identity,"ticket":0,"safety":false,"custody":"","destination":LifeJourneyState.packed(destination),"stair_id":"","direction":0,"distance":0.0,"wait":[],"clear":[],"intent":{"kind":"action","id":"arrive_home","target_id":"lot_exit","meal_source":"","meal_stage":"","meal_plate":""}}}
	for parent:String in request.guardians:snapshot.family_graph.parents.append({"a":parent,"b":id})
	var ids:Array=[]
	for entry:Dictionary in snapshot.members:ids.append(str(entry.id))
	snapshot.family_graph=LifeFamilyGraph.canonical(snapshot.family_graph,ids)
	for entry:Dictionary in snapshot.members:
		if str(entry.id)==id:continue
		var role:String=LifeFamilyGraph.relationship(snapshot.family_graph,str(entry.id),id)
		var familiar:bool=LifeFamilyGraph.is_family(role)
		var relation:Dictionary={"name":child_state.character.name,"friendship":55.0 if familiar else 18.0,"romance":0.0,"status":LifeFamilyGraph.label(role),"life_stage":"minor","bond":"none","milestones":["met","friends"] if familiar else [],"family_role":role}
		entry.state.relationships[id]=relation
		var reverse:Dictionary=relation.duplicate(true)
		reverse.name=entry.state.character.name;reverse.life_stage=entry.state.character.life_stage
		reverse.family_role=LifeFamilyGraph.inverse(role);reverse.status=LifeFamilyGraph.label(str(reverse.family_role))
		child_state.relationships[str(entry.id)]=reverse
	snapshot.adoptions.events.append({"serial":int(request.serial),"choice":int(request.choice),"child":id,"guardians":request.guardians.duplicate(),"day":day,"minutes":minutes,"fee":LifeAdoption.FEE})
	snapshot.adoptions.next_serial=int(request.serial)+1
	# Validate the complete proposed household before mutating any live member.
	var validator:=LifeHousehold.new()
	var checked:Dictionary=validator.restore_state(snapshot)
	if not bool(checked.ok):validator.free();return checked
	var added:LifeSim=validator.member_sim(id)
	validator.remove_child(added)
	validator.free()
	# No signals, awaits, queue reconstruction or whole-world rebuild here.
	for entry:Dictionary in snapshot.members:
		if str(entry.id)!=id:member_sim(str(entry.id)).relationships[id]=entry.state.relationships[id].duplicate(true)
	family_graph=snapshot.family_graph.duplicate(true);adoptions=snapshot.adoptions.duplicate(true)
	if snapshot.has("journeys"):journeys=snapshot.journeys.duplicate(true)
	members.append({"id":id,"sim":added});add_child(added)
	added.name="Life_"+id;added.household_bills_enabled=false
	connect_member(id,added)
	_rebuild_family_roles();set_funds(int(snapshot.funds))
	return {"ok":true,"duplicate":false,"child":id,"spawn":spawn}
