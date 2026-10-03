extends RefCounted
class_name LifeMarriage
## Prepare and validate the complete household before moving a spouse in.

static func reason(household:Node,host_id:String,target_id:String)->String:
	var host:LifeSim=household.member_sim(host_id)
	if host==null or host_id==target_id:return "Choose another adult Lifelet."
	var error:String=LifeRelationshipProgress.proposal_reason(host,target_id)
	if not error.is_empty():return error
	var relation:Dictionary=host.relationships[target_id]
	if LifeFamilyGraph.is_family(str(relation.get("family_role","none"))):return "Family members cannot marry each other."
	if str(host.character.life_stage)!="adult" or str(relation.get("life_stage","adult"))!="adult" or host.is_spirit():return "Marriage needs two living adult Lifelets."
	var target:LifeSim=household.member_sim(target_id)
	if target!=null:
		if target.is_spirit() or str(target.romantic_partner)!=host_id:return "Both partners must agree to the relationship."
		if int(target.relationships.get(host_id,{}).get("completed_dates",0))<2:return "Complete two dates together before proposing."
	else:
		if not LifeResidentCatalogue.PEOPLE.has(target_id) or household.resident_members.has(target_id):return "This neighbor has already moved into a household."
		if household.members.size()>=LifeHousehold.MAX_MEMBERS:return "Make room in the household before inviting a spouse to move in."
		for member:Dictionary in household.members:
			if str(member.id)!=host_id and str(member.sim.romantic_partner)==target_id:return "This Lifelet already has a partner."
	return ""

static func married_name(incoming:String,host:String)->String:
	var host_words:PackedStringArray=host.strip_edges().split(" ",false)
	var words:PackedStringArray=incoming.strip_edges().split(" ",false)
	# Only a host with a surname of their own has one to give: a single name leaves
	# the incoming spouse's name as it was, rather than lending them a first name.
	if host_words.size()<2:return incoming.strip_edges()
	var surname:String=host_words[-1]
	if words.size()>1:words.remove_at(words.size()-1)
	return (" ".join(words)+" "+surname).strip_edges()

static func validate_aliases(data:Dictionary)->String:
	var aliases:Variant=data.get("resident_members",{})
	if not aliases is Dictionary or aliases.size()>LifeResidentCatalogue.IDS.size():return "Invalid moved-in resident identities."
	var ids:Array=[]
	for member:Variant in data.get("members",[]):
		if not member is Dictionary:return "Invalid moved-in resident household."
		ids.append(member.get("id"))
	var graph:Variant=data.get("family_graph",{})
	if not graph is Dictionary or not graph.get("departed",[]) is Array:return "Invalid saved family data."
	ids.append_array(LifeFamilyGraph.departed_ids(graph))
	var used:Array=[]
	for resident:Variant in aliases:
		if not resident is String or not LifeResidentCatalogue.PEOPLE.has(resident) or not aliases[resident] is String or aliases[resident] not in ids or aliases[resident] in used:return "Invalid moved-in resident identity."
		used.append(aliases[resident])
	for member:Dictionary in data.get("members",[]):
		if not member.get("state") is Dictionary or member.state.get("resident_aliases",{})!=aliases:return "Household members disagree about moved-in neighbors."
	var invitation:Variant=data.get("date_invitation",{})
	if not invitation is Dictionary:return "Invalid date invitation."
	if not invitation.is_empty():
		if not invitation.get("host") is String or invitation.host not in ids or not invitation.get("target") is String or invitation.target not in LifeResidentCatalogue.IDS or aliases.has(invitation.target) or not LifeJourneyState.number(invitation.get("visit_serial"),1,1000000000,true):return "Invalid date invitation."
		var saved:Variant=LifeHomeVisit.saved_visit(data)
		if saved==null or not saved.value is Dictionary or not saved.value.get("visit") is Dictionary:return "The invited date has no matching home visit."
		if str(saved.value.visit.get("guest",""))!=str(invitation.target) or saved.value.visit.get("serial")!=invitation.visit_serial:return "The invited date has no matching home visit."
	return ""

static func _remap(value:Variant,old_id:String,new_id:String)->void:
	if value is Array:
		for entry:Variant in value:_remap(entry,old_id,new_id)
	elif value is Dictionary:
		for key:Variant in value:
			if key in ["target_id","partner_id","source_id","beneficiary","owner"] and value[key]==old_id:value[key]=new_id
			else:_remap(value[key],old_id,new_id)

static func complete(household:Node,host_id:String,target_id:String,position:Vector3,yaw:float,layout:Array,incoming_needs:Dictionary={})->Dictionary:
	var error:String=reason(household,host_id,target_id)
	if not error.is_empty():return {"ok":false,"error":error}
	if not position.is_finite() or not is_finite(yaw):return {"ok":false,"error":"The incoming spouse needs a valid place in the home."}
	var data:Dictionary=household.get_state(layout)
	if data.has("snapshot_error"):return {"ok":false,"error":str(data.snapshot_error)}
	var joined:bool=household.member_sim(target_id)==null
	var spouse_id:String="housemate_%d" % household.members.size() if joined else target_id
	if joined:
		var next_id:int=household.members.size()
		var departed:Array[String]=LifeFamilyGraph.departed_ids(household.family_graph)
		while household.member_sim(spouse_id)!=null or departed.has(spouse_id):
			next_id+=1;spouse_id="housemate_%d" % next_id
	var host:LifeSim=household.member_sim(host_id)
	var spouse_state:Dictionary={}
	if joined:
		var newcomer:=LifeSim.new()
		var profile:Dictionary=LifeResidentCatalogue.PEOPLE[target_id].duplicate(true)
		profile.name=married_name(str(profile.name),str(host.character.name));profile.wants_and_fears=true
		newcomer.new_household(profile)
		newcomer.day=household.day;newcomer.minutes=household.minutes;newcomer.funds=household.funds;newcomer.speed=household.speed
		newcomer.set_aging(str(host.lifecycle.lifespan),bool(host.lifecycle.auto_age))
		newcomer.career.schedule=LifeCareerSchedule.fresh(household.day)
		newcomer._story_generated_day=household.day
		household._mirror_bills_onto(newcomer)
		for need:String in newcomer.needs:
			if incoming_needs.has(need):newcomer.needs[need]=clampf(float(incoming_needs[need]),0,100)
		newcomer.character.world_state={"player":LifeJourneyState.packed(position),"player_rotation":yaw,"resource_wait_started":-1.0,"resource_action_active":false,"waiting_action_id":"","waiting_target_id":""}
		spouse_state=newcomer.get_state();newcomer.free()
		data.members.append({"id":spouse_id,"state":spouse_state})
		data.resident_members[target_id]=spouse_id
		if data.has("journeys"):data.journeys.members[spouse_id]={"position":LifeJourneyState.packed(position),"yaw":yaw,"motion":{}}
	else:
		for entry:Dictionary in data.members:
			if str(entry.id)==spouse_id:spouse_state=entry.state
		spouse_state.character.name=married_name(str(spouse_state.character.name),str(host.character.name))
	for entry:Dictionary in data.members:
		var state:Dictionary=entry.state
		if joined and str(entry.id)!=spouse_id:
			var old:Dictionary=state.relationships.get(target_id,{"name":spouse_state.character.name,"friendship":8.0,"romance":0.0,"status":"Housemate","life_stage":"adult","bond":"none","milestones":[],"family_role":"none"}).duplicate(true)
			old.name=spouse_state.character.name
			state.relationships[spouse_id]=old
			var reverse:Dictionary=old.duplicate(true)
			reverse.name=state.character.name;reverse.life_stage=state.character.life_stage
			spouse_state.relationships[str(entry.id)]=reverse
		state.resident_aliases=data.resident_members.duplicate(true)
		for retired:String in data.resident_members:state.relationships.erase(retired)
		if joined:
			state.relationships.erase(target_id)
			if str(state.romantic_partner)==target_id:state.romantic_partner=spouse_id
			_remap(state.action_queue,target_id,spouse_id);_remap(state.social_history,target_id,spouse_id)
			if state.autonomy_state.contacts.has(target_id):
				state.autonomy_state.contacts[spouse_id]=state.autonomy_state.contacts[target_id]
				state.autonomy_state.contacts.erase(target_id)
			for key:String in ["last_hugs","last_gossip","social_cooldowns"]:
				if state.get(key,{}) is Dictionary and state.get(key,{}).has(target_id):state[key][spouse_id]=state[key][target_id];state[key].erase(target_id)
			var context:Dictionary=state.character.get("world_state",{})
			var residents:Dictionary=context.get("residents",{})
			for place:Dictionary in residents.get("locations",{}).values():place.erase(target_id)
			if str(residents.get("home_visit",{}).get("visit",{}).get("guest",""))==target_id:residents.home_visit.visit={}
			if residents.get("party_visits") is Array:residents.party_visits=residents.party_visits.filter(func(record:Variant)->bool:return not record is Dictionary or str(record.get("visit",{}).get("guest",""))!=target_id)
		if str(entry.id)!=spouse_id and state.relationships.has(spouse_id):state.relationships[spouse_id].name=spouse_state.character.name
	var host_state:Dictionary={}
	for entry:Dictionary in data.members:
		if str(entry.id)==host_id:host_state=entry.state
	for pair:Array in [[host_state,spouse_id],[spouse_state,host_id]]:
		var state:Dictionary=pair[0];var relation:Dictionary=state.relationships[str(pair[1])]
		state.romantic_partner=str(pair[1]);relation.bond="committed";relation.married=true;relation.status="Spouse"
	if joined and data.has("journeys"):_remap(data.journeys,target_id,spouse_id)
	if str(data.get("date_invitation",{}).get("target",""))==target_id:data.date_invitation={}
	var validator:=LifeHousehold.new()
	var checked:Dictionary=validator.restore_state(data)
	if not bool(checked.ok):validator.free();return checked
	var added:LifeSim=validator.member_sim(spouse_id) if joined else null
	if joined:validator.remove_child(added)
	validator.free()
	# Only validated fields cross into the live objects, preserving existing
	# action identities, service bindings, routes and selected Lifelet.
	for entry:Dictionary in data.members:
		if joined and str(entry.id)==spouse_id:continue
		var live:LifeSim=household.member_sim(str(entry.id));var state:Dictionary=entry.state
		live.relationships=state.relationships.duplicate(true);live.romantic_partner=str(state.romantic_partner)
		live.resident_aliases=state.resident_aliases.duplicate(true);live.social_history=state.social_history.duplicate(true)
		live.autonomy_state=state.autonomy_state.duplicate(true)
		live.character.name=state.character.name
		if joined:
			_remap(live.action_queue,target_id,spouse_id)
			for key:String in ["last_hugs","last_gossip","social_cooldowns"]:live.set(key,state.get(key,{}).duplicate(true))
	if joined:
		household.members.append({"id":spouse_id,"sim":added});household.add_child(added)
		added.name="Life_"+spouse_id;added.household_bills_enabled=false;added.set_home_value_provider(household.home_value_provider)
		household.connect_member(spouse_id,added)
	household.resident_members=data.resident_members.duplicate(true)
	household.date_invitation=data.get("date_invitation",{}).duplicate(true)
	if data.has("journeys"):household.journeys=data.journeys.duplicate(true)
	for id:String in [host_id,spouse_id]:
		var member:LifeSim=household.member_sim(id)
		member._record_social_event(spouse_id if id==host_id else host_id,"married",false)
		member.add_moodlet("Just married","Happy","A shared home and a future together.",720,4)
	household._sync_social_context();household._sync_bill_mirror()
	return {"ok":true,"host_id":host_id,"spouse_id":spouse_id,"resident_id":target_id if joined else "","joined":joined,"name":str(spouse_state.character.name)}
