extends Node
class_name LifeHousehold
## A shared home and wallet, with independent needs, careers and action queues.

signal member_age_changed(member_id: String, previous: String, current: String)
signal member_action_started(member_id: String, action: Dictionary)
signal member_action_finished(member_id: String, action: Dictionary)
signal member_passed(member_id: String)
signal baby_born(mother_id: String)
## Raised the moment a couple conceives, so the view can tell the player the
## news with a sound and a notice before the birth arrives days later.
signal pregnancy_began(mother_id: String)
signal notice(message: String)
signal selection_changed(member_id: String)
signal member_passed_away(id: String, name: String, memorial_kind: String, payout: int)

const SAVE_PATH = "user://justlife_save.json"
const MAX_MEMBERS = 8
## Raised when the household's home cover changes, so the app can keep the
## property record in step with the sims and the two can never disagree.
signal insurance_changed(policy_id: String)
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
var extras_provider:Callable=Callable()
## Where the household's post boxes stand. The controller owns the world's layout,
## so it answers this; the household only asks whether there is anywhere to post
## to, rather than reaching into the world itself.
var post_box_provider:Callable=Callable()
## Reports what everything placed in the home is worth. Pulled when a bill is
## issued, so the amount always reflects the house the player has built.
var home_value_provider:Callable=Callable()
var extras_restore_provider:Callable=Callable()
var family_graph: Dictionary = LifeFamilyGraph.fresh()
var adoptions: Dictionary = LifeAdoption.fresh()
var pets: Dictionary = LifePets.fresh()
## The household's post box. Letters and bills are filed here when the household
## owns a post box; without one, bills arrive by notice exactly as before.
var mail: Dictionary = LifeMail.fresh()
var pregnancy: Dictionary = LifeBabyPlan.fresh()
var _family_roles: Dictionary = {}
var meals: LifeMeals = LifeMeals.new()
## The household's kitchen: what is in the fridge, and the delivery on its way.
## A household restocks by ordering from the computer rather than by cooking
## straight out of the fridge, so this is real state rather than a convenience.
var groceries: Dictionary = LifeGroceries.fresh()
## What the household runs: the businesses it owns, who they employ, and what
## they have paid and made. A business is bought at a high rung of the skill it
## needs, so owning one is what a long career builds towards.
var business: Dictionary = {}
var sanitation: LifeSanitation = LifeSanitation.new()
var cooperations: Array = []
var cooperation_serial: int = 0
var birth_serial: int = 1
var memorials: Array = []
var heirlooms: Array = []
const ESTATE_GIFT: int = 80
var _cooperation_depth: int = 0
const COOPERATION_WAIT_LIMIT: float = 60.0

func new_household(profiles: Array) -> void:
	journeys.clear()
	adoptions=LifeAdoption.fresh()
	pets=LifePets.fresh()
	mail=LifeMail.fresh()
	pregnancy=LifeBabyPlan.fresh()
	meals.clear()
	sanitation.clear()
	cooperations.clear()
	cooperation_serial = 0
	birth_serial = 1
	memorials.clear()
	heirlooms.clear()
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
	var member_profile: Dictionary = profile.duplicate(true)
	member_profile["wants_and_fears"] = true
	sim.new_household(member_profile)
	sim.day=day;sim.minutes=minutes;sim.funds=funds;sim.speed=speed
	sim.household_bills_enabled=members.is_empty()
	sim.set_home_value_provider(home_value_provider)
	sim.register_targets(targets.filter(func(target:Dictionary):return str(target.id)!=id))
	members.append({"id":id,"sim":sim})
	connect_member(id,sim)
	_sync_bill_mirror()
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
	sim.life_changed.connect(func(status: String):
		if not restoring and status == "passed": _record_passing(id))
	sim.action_started.connect(func(action:Dictionary):
		if not restoring:member_action_started.emit(id,action))
	sim.action_finished.connect(func(action:Dictionary):
		if not restoring:
			var target:LifeSim=member_sim(str(action.get("target_id","")))
			if target and str(action.id) in LifeSim.SOCIAL_ACTIONS and bool(action.get("social_accepted",true)) and sim.relationships.has(str(action.target_id)):
				var relationship:Dictionary=sim.relationships[str(action.target_id)].duplicate(true)
				target.receive_social_result(id,str(sim.character.name),str(sim.character.life_stage),relationship,str(action.id),action.get("social_events",[]))
				target.needs.social=minf(100,target.needs.social+16)
			# Playing together in the garden is a shared moment: whoever else is
			# at the same furnishing shares the fun and the friendship, which is
			# what the swing, the sand pit and the garden swing are for.
			if str(action.id) in [LifeOutdoorActs.ACTION_ID, LifeOutdoorActs.PUSH_ID]:
				_credit_garden_company(id, action, sim)
			_sync_social_context()
			member_action_finished.emit(id,action))
	sim.notice.connect(func(message:String):
		if not restoring:notice.emit(message))

## Share one garden activity with whoever else is standing at the same
## furnishing: they gain the fun, and the two of them gain friendship with each
## other. A push at the swings reaches the children on them, so the rule "an
## adult pushes the children and it lifts their fun and friendship" is real.
func _credit_garden_company(actor_id: String, action: Dictionary, actor: LifeSim) -> void:
	var place: String = str(action.get("target_id", ""))
	if place.is_empty(): return
	var present: Array = []
	for member: Dictionary in members:
		if str(member.id) == actor_id: continue
		var other: LifeSim = member.sim
		var theirs: Dictionary = other.get_current_action()
		if str(theirs.get("target_id", "")) != place: continue
		present.append(member)
	if present.is_empty(): return
	var pushing: bool = str(action.id) == LifeOutdoorActs.PUSH_ID
	for member: Dictionary in present:
		var other: LifeSim = member.sim
		other.needs["fun"] = minf(100.0, float(other.needs["fun"]) + LifeOutdoorActs.PUSH_CHILD_FUN)
		other.needs["social"] = minf(100.0, float(other.needs["social"]) + LifeOutdoorActs.PUSH_CHILD_SOCIAL)
		# Both directions of the friendship: the actor gains, and so does the one
		# who was actually there.
		for pair: Array in [[actor, other], [other, actor]]:
			var from_sim: LifeSim = pair[0]
			var to_sim: LifeSim = pair[1]
			var to_id: String = str(to_sim.cooperation_member_id)
			if not from_sim.relationships.has(to_id): continue
			var rel: Dictionary = from_sim.relationships[to_id]
			# A push is the deeper moment; playing alongside is a smaller one.
			var lift: float = 14.0 if pushing else 8.0
			rel["friendship"] = clampf(float(rel.friendship) + lift, -100.0, 100.0)
			from_sim.relationships[to_id] = rel
		if pushing:
			other.add_moodlet("Pushed on the swings", "Happy", "%s pushed you on the swings." % str(actor.character.name), 120, 2)


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
	var adults:Dictionary={}
	for resident_id:String in LifeResidentCatalogue.IDS:adults[resident_id]=true
	for member:Dictionary in members:
		partners[member.id]=member.sim.romantic_partner
		adults[member.id]=str(member.sim.character.get("life_stage","adult"))=="adult"
		if str(member.sim.romantic_partner) in LifeResidentCatalogue.IDS:
			partners[member.sim.romantic_partner]=member.id
	for member:Dictionary in members:
		var reciprocal:Dictionary={}
		var family_roles:Dictionary={}
		for other:Dictionary in members:
			if other.id!=member.id and other.sim.relationships.has(str(member.id)):
				var relationship:Dictionary=other.sim.relationships[str(member.id)]
				relationship.life_stage = str(member.sim.character.life_stage)
				reciprocal[other.id]={"friendship":relationship.friendship,"romance":relationship.romance,"traits":other.sim.character.get("traits",[]),"fun":float(other.sim.needs.get("fun",100.0))}
				family_roles[other.id]=family_relationship(str(member.id),str(other.id))
		# Neighbors join the context with their catalogue traits and workday
		# mood schedule, so conditional interactions land for them too.
		for neighbor:String in LifeResidentCatalogue.PEOPLE:
			if not member.sim.relationships.has(neighbor) or reciprocal.has(neighbor):continue
			var known:Dictionary=LifeResidentCatalogue.PEOPLE[neighbor]
			var link:Dictionary=member.sim.relationships[neighbor]
			reciprocal[neighbor]={"friendship":float(link.get("friendship",0.0)),"romance":float(link.get("romance",0.0)),"traits":known.get("traits",[]),"resident_fun":known.get("fun",{"work":40,"off":80})}
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
		if sim == bill_owner() and sim.day != start_day:
			_sync_bill_mirror()
	day=members[0].sim.day
	minutes=members[0].sim.minutes
	if day!=start_day:
		_sync_bill_mirror()
		# A break-in is the household's own event, rolled once by the money owner
		# on the shared clock. It fires on the night it is due while the player
		# simply plays, rather than waiting to be asked for.
		var robber:LifeSim=bill_owner()
		if robber!=null:
			robber.funds=funds
			robber.robbery_check()
			funds=robber.funds
			_sync_wallet()
		# Every Lifelet on the criminal line of work takes their own chance of
		# being caught once a day, on the shared clock, so a practised thief's
		# lower risk is something the player sees rather than reads about.
		_criminal_tick()
		# A sentence ends on the shared clock, so a Lifelet really comes home on
		# the day their record says they are free.
		_prison_release_tick()
	# A grocery delivery arrives when its van does, on the shared clock, so a
	# household that ordered one is restocked while the player simply plays.
	_grocery_tick()
	# An owned business pays its takings on the same shared clock.
	_business_tick()
	# Conception to birth runs on the shared game clock, so fast speed, pause
	# and a save/load all agree about when the baby is due.
	pregnancy_tick()
	_caregiving_tick()
	# A pet's own day runs on the same clock, so a paused household freezes its
	# pets' needs exactly as it freezes its Lifelets.
	# The clock wraps at midnight, so a tick that crosses a day boundary owes the
	# pets the rest of the old day as well as the new one.
	_tick_pet_care(float(minutes) - start_minutes + float(day - start_day) * 1440.0)
	_sync_wallet()
	_sync_grocery_service()
	if paired:
		_reconcile_cooperations()
		_end_cooperation_change()

## Compatibility entry point for callers that explicitly request a farewell.
## LifeSim owns eligibility and the single passing signal; the Lifelet remains
## selectable as a spirit, so identity, genealogy and household clocks survive.
func pass_away(id: String) -> Dictionary:
	adopt_selected_changes()
	var dying: LifeSim = member_sim(id)
	if dying == null:
		return {"ok": false, "error": "Unknown member"}
	if not dying.pass_on():
		return {"ok": false, "error": "This Lifelet is not ready to pass on."}
	return {"ok": true, "departed_id": id, "name": str(dying.character.name), "payout": ESTATE_GIFT, "memorial_kind": "memorial", "memorial_id": "memorial_%s" % id}

func _caregiving_tick() -> void:
	# A baby cannot meet its own needs. When one is desperate, an available
	# adult housemate takes over: the carer walks to the baby and the need is
	# restored through the carer's own time, so care is visible and costs the
	# caregiver something rather than topping the baby up for free.
	if speed<=0:return
	var baby:LifeSim=null
	for member:Dictionary in members:
		if str(member.sim.character.get("age_stage",""))=="baby":
			if baby==null or _urgent_needs(member.sim)>_urgent_needs(baby):baby=member.sim
	if baby==null:return
	var need:String=_most_urgent_need(baby)
	if need.is_empty():return
	var carer:LifeSim=null
	for member:Dictionary in members:
		var candidate:LifeSim=member.sim
		if str(candidate.character.get("age_stage","")) not in ["young_adult","adult","elder"]:continue
		if not candidate.get_current_action().is_empty() or not candidate.action_queue.is_empty():continue
		# A desperate baby outranks the carer's own comfort: only a carer who is
		# themselves about to collapse is excused, and any candidate serves.
		if carer==null or float(candidate.needs.get("energy",100.0))>float(carer.needs.get("energy",100.0)):carer=candidate
	if carer==null:return
	if float(carer.needs.get("energy",100.0))<2.0:return
	baby.needs[need]=minf(100.0,float(baby.needs.get(need,0.0))+45.0)
	baby.add_moodlet("Looked after","Happy","Someone noticed and helped.",180,2)
	carer.add_moodlet("Caring","Happy","Looking after the little one.",120,2)
	carer._gain_skill("parenting",8.0)
	notice.emit("%s looked after the baby." % str(carer.character.get("name","A grown-up")).split(" ")[0])

func _urgent_needs(who:LifeSim) -> float:
	var worst:float=0.0
	for key:String in ["hunger","energy","hygiene","bladder","fun","social"]:
		worst=maxf(worst,100.0-float(who.needs.get(key,100.0)))
	return worst

func _most_urgent_need(who:LifeSim) -> String:
	var need:String=""
	var worst:float=100.0
	for key:String in ["hunger","energy","hygiene","bladder","fun","social"]:
		var value:float=float(who.needs.get(key,100.0))
		if value<35.0 and value<worst:worst=value;need=key
	return need

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
	var result:Dictionary={"household_version":2 if not journeys.is_empty() else 1,"selected_index":selected_index,"funds":funds,"day":day,"minutes":minutes,"speed":speed,"members":states,"world":world_data.duplicate(true),"family_graph":family_graph.duplicate(true),"adoptions":adoptions.duplicate(true),"pets":pets.duplicate(true),"mail":mail.duplicate(true),"pregnancy":pregnancy.duplicate(true),"birth_serial":birth_serial,"memorials":memorials.duplicate(true),"heirlooms":heirlooms.duplicate(true),"cooperation_version":1,"cooperation_serial":cooperation_serial,"cooperations":cooperations.duplicate(true),"meals":meals.get_state(),"groceries":groceries.duplicate(true),"business":business.duplicate(true),"sanitation":sanitation.get_state(),"extras":extras_provider.call() if extras_provider.is_valid() else {}}
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
	var lead_policy:String=str(lead.insurance_policy_id)
	for candidate:Dictionary in candidates:
		if str(candidate.sim.insurance_policy_id)!=lead_policy:
			for c in candidates:c.sim.free()
			return {"ok":false,"error":"The saved Lifelets disagree about home insurance."}
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
	var pet_error_text:String=LifePets.validate(data.get("pets",null),data)
	if not pet_error_text.is_empty():
		for candidate:Dictionary in candidates:candidate.sim.free()
		return {"ok":false,"error":pet_error_text}
	var mail_error:String=LifeMail.validate(data.get("mail",null))
	if not mail_error.is_empty():
		for candidate:Dictionary in candidates:candidate.sim.free()
		return {"ok":false,"error":mail_error}
	var pregnancy_data:Variant=data.get("pregnancy",null)
	var pregnancy_error:String=LifeBabyPlan.validate(pregnancy_data,data)
	if pregnancy_error.is_empty():pregnancy_error=LifeBabyPlan.validate_pending(pregnancy_data,data,pregnancy_data if pregnancy_data is Dictionary else {})
	if not pregnancy_error.is_empty():
		for candidate:Dictionary in candidates:candidate.sim.free()
		return {"ok":false,"error":pregnancy_error}
	if not LifeJourneyState.number(data.get("birth_serial",1),1,LifeBabyPlan.MAX_BIRTHS,true):
		for candidate:Dictionary in candidates:candidate.sim.free()
		return {"ok":false,"error":"Save contains an invalid birth counter."}
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
	# The kitchen is validated before it is adopted, so a corrupt delivery
	# cannot strand a household with food that never arrives.
	var business_error: String = LifeBusiness.validate_owned(data.get("business"))
	if not business_error.is_empty():
		for c in candidates: c.sim.free()
		return {"ok":false,"error":business_error}
	var grocery_error: String = LifeGroceries.validate(data.get("groceries"))
	if not grocery_error.is_empty():
		for c in candidates: c.sim.free()
		return {"ok":false,"error":grocery_error}
	var meal_data: Variant = data.get("meals",LifeMeals.new().get_state())
	var meal_error: String = LifeMeals.validate(meal_data,ids,(lead.day-1)*1440.0+lead.minutes,guest)
	if meal_error.is_empty():meal_error=LifeMeals.validate_actions(meal_data,data.members,journey_result.get("custody",{}),str(journey_result.get("venue","")),guest)
	if meal_error.is_empty():meal_error=LifeMeals.validate_layout(meal_data,data)
	if not meal_error.is_empty():
		for c in candidates:c.sim.free()
		return {"ok":false,"error":meal_error}
	var extras_error:String=LifeHouseholdFlow.validate(data.get("extras",null),data.get("world",[]))
	if not extras_error.is_empty():
		for c in candidates:c.sim.free()
		return {"ok":false,"error":extras_error}
	var memorial_error:String=_validate_memorials(data.get("memorials",[]),ids)
	if not memorial_error.is_empty():
		for c in candidates:c.sim.free()
		return {"ok":false,"error":memorial_error}
	var heirloom_error:String=_validate_heirlooms(data.get("heirlooms",[]))
	if not heirloom_error.is_empty():
		for c in candidates:c.sim.free()
		return {"ok":false,"error":heirloom_error}
	restoring=true
	journeys=data.get("journeys",{}).duplicate(true)
	if not journeys.is_empty():
		for index:int in candidates.size():
			for action_index:int in candidates[index].sim.action_queue.size():
				candidates[index].sim.action_queue[action_index].phase=data.members[index].state.action_queue[action_index].phase
	adoptions=data.get("adoptions",LifeAdoption.fresh()).duplicate(true)
	pets=LifePets.fresh() if not data.get("pets") is Dictionary else (data.get("pets") as Dictionary).duplicate(true)
	# A household saved before it had a post box loads with an empty one rather
	# than losing mail it never had.
	mail=LifeMail.fresh() if not data.get("mail") is Dictionary else (data.get("mail") as Dictionary).duplicate(true)
	# A pet saved before pets had a condition loads with a fresh one rather than
	# being left without needs for the rest of the save's life.
	for pet:Dictionary in pets.get("pets",[]):
		if not pet.get("care") is Dictionary:pet["care"]=LifePetCare.fresh()
	pregnancy=LifeBabyPlan.fresh() if pregnancy_data==null else (pregnancy_data as Dictionary).duplicate(true)
	birth_serial=int(data.get("birth_serial",1))
	meals.restore(meal_data)
	groceries=LifeGroceries.from_save(data.get("groceries"))
	# A household that owns no business holds no record at all; the validator
	# above has already refused anything that does not agree with the table.
	business=(data.get("business") as Dictionary).duplicate(true) if data.get("business") is Dictionary else {}
	sanitation.restore(sanitation_data)
	if extras_restore_provider.is_valid():extras_restore_provider.call(data.get("extras",null))
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
	memorials=_clean_memorials(data.get("memorials",[]))
	heirlooms=_clean_heirlooms(data.get("heirlooms",[]))
	_rebuild_family_roles()
	selected_index=int(selected_value)
	funds=members[selected_index].sim.funds
	day=members[selected_index].sim.day;minutes=members[selected_index].sim.minutes;speed=members[selected_index].sim.speed
	for i in range(members.size()):
		var member:Dictionary=members[i]
		add_child(member.sim)
		member.sim.name="Life_"+member.id
		member.sim.household_bills_enabled=i==0
		member.sim.set_home_value_provider(home_value_provider)
		connect_member(member.id,member.sim)
		if not targets.is_empty(): member.sim.register_targets(targets.filter(func(target:Dictionary):return str(target.id)!=str(member.id)))
	_sync_wallet()
	_sync_bill_mirror()
	restoring=false
	return {"ok":true,"world":data.get("world",[]).duplicate(true)}

func _prepare_saved_family(data:Dictionary) -> Dictionary:
	var ids:Array[String]=[]
	for entry:Dictionary in data.members:ids.append(str(entry.id))
	var departed_set: Array[String] = LifeFamilyGraph.departed_ids(data.get("family_graph", {}))
	for entry:Dictionary in data.members:
		for target:String in entry.state.relationships:
			if not ids.has(target) and not departed_set.has(target) and str(entry.state.relationships[target].get("family_role","none"))!="none":
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
	var departed_set: Array[String] = LifeFamilyGraph.departed_ids(data.get("family_graph", {}))
	if departed_set.is_empty():
		for index:int in range(data.members.size()):
			expected_ids.append("player" if index==0 else "housemate_%d" % index)
		for index:int in range(data.members.size()):
			var entry:Variant=data.members[index]
			if not entry is Dictionary or entry.get("id")!=expected_ids[index] or not entry.get("state") is Dictionary:
				return "The saved household has an invalid Lifelet identity."
	else:
		for index:int in range(data.members.size()):
			var entry:Variant=data.members[index]
			if not entry is Dictionary or not entry.get("id") is String or not entry.get("state") is Dictionary:
				return "The saved household has an invalid Lifelet identity."
			var mid: String = str(entry.id)
			if (mid != "player" and not mid.begins_with("housemate_")) or expected_ids.has(mid) or departed_set.has(mid):
				return "The saved household has an invalid Lifelet identity."
			expected_ids.append(mid)
	for index:int in range(data.members.size()):
		var entry:Variant=data.members[index]
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
			if not relation_id is String or (str(relation_id) not in LifeResidentCatalogue.IDS and str(relation_id) not in expected_ids and str(relation_id) not in departed_set):
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
		elif partner_id in LifeResidentCatalogue.IDS:
			if neighbor_partners.has(partner_id):return "A neighbor cannot have two household partners."
			neighbor_partners[partner_id]=expected_ids[index]
	return ""

func keepsake_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for entry: Dictionary in heirlooms:
		var note: String = str(entry.get("note", ""))
		lines.append(str(entry.label) if note.is_empty() else "%s — %s" % [str(entry.label), note])
	return lines

func inspect_keepsake(index: int = 0) -> Dictionary:
	if index < 0 or index >= heirlooms.size():
		return {}
	return (heirlooms[index] as Dictionary).duplicate(true)

func _record_passing(member_id: String) -> void:
	var who: LifeSim = member_sim(member_id)
	if who == null:
		return
	for existing: Dictionary in memorials:
		if str(existing.member_id) == member_id:
			return
	set_funds(who.funds + ESTATE_GIFT)
	var cause: String = who.passing_cause() if who.has_method("passing_cause") else "old_age"
	var why: String = str(LifeSim.PASSING_CAUSES.get(cause, "a life remembered"))
	heirlooms.append({
		"from":str(who.character.name),
		"label":"%s's keepsake" % str(who.character.name),
		"day":who.day,
		"cause":cause,
		"note":"A small object they carried. Held after they passed from %s." % why,
	})
	memorials.append({"member_id":member_id,"name":str(who.character.name),"day":who.day,"kind":"memorial","funds":funds,"cause":cause})
	for member: Dictionary in members:
		if str(member.id) == member_id or member.sim.is_spirit():
			continue
		member.sim.add_moodlet("In mourning","Sad","Someone beloved has passed.",960,2)
		member.sim.trigger_fear("fear_of_loss")
		member.sim.remember("A farewell","%s left a keepsake and ℒ%d for the household." % [str(who.character.name), ESTATE_GIFT])
	member_passed.emit(member_id)
	member_passed_away.emit(member_id, str(who.character.name), "memorial", ESTATE_GIFT)
	notice.emit("%s left a keepsake and ℒ%d. Their story stays in the family." % [str(who.character.name), ESTATE_GIFT])

func _validate_memorials(raw: Variant, ids: Array) -> String:
	if raw == null:
		return ""
	if not raw is Array or raw.size() > 8:
		return "The saved household has invalid memorials."
	var seen: Dictionary = {}
	for entry: Variant in raw:
		if not entry is Dictionary or not entry.get("member_id") is String or not entry.get("name") is String:
			return "The saved household has an invalid memorial."
		if not ids.has(str(entry.member_id)) or seen.has(str(entry.member_id)):
			return "The saved household has an invalid memorial."
		if not LifeJourneyState.number(entry.get("day", 1), 1, 1000000, true):
			return "The saved household has an invalid memorial date."
		seen[str(entry.member_id)] = true
	return ""

func _clean_memorials(raw: Variant) -> Array:
	var result: Array = []
	if not raw is Array:
		return result
	for entry: Variant in raw:
		if entry is Dictionary:
			result.append({"member_id":str(entry.member_id),"name":str(entry.name),"day":int(entry.get("day",1)),"kind":"memorial","funds":int(entry.get("funds",0)),"cause":str(entry.get("cause","old_age"))})
	return result

func _validate_heirlooms(raw: Variant) -> String:
	if raw == null:
		return ""
	if not raw is Array or raw.size() > 8:
		return "The saved household has invalid heirlooms."
	for entry: Variant in raw:
		if not entry is Dictionary or not entry.get("from") is String or not entry.get("label") is String:
			return "The saved household has an invalid heirloom."
		if not LifeJourneyState.number(entry.get("day", 1), 1, 1000000, true):
			return "The saved household has an invalid heirloom date."
	return ""

func _clean_heirlooms(raw: Variant) -> Array:
	var result: Array = []
	if not raw is Array:
		return result
	for entry: Variant in raw:
		if entry is Dictionary:
			result.append({"from":str(entry.from),"label":str(entry.label),"day":int(entry.get("day",1)),"cause":str(entry.get("cause","old_age")),"note":str(entry.get("note",""))})
	return result

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

## Bills are a household matter: every member reads the same home value from the
## owning scene, and the first member owns the ledger.
func set_home_value_provider(provider: Callable) -> void:
	home_value_provider = provider
	for member: Dictionary in members:
		member.sim.set_home_value_provider(provider)

## The bill ledger lives with the first member, matching household_bills_enabled.
func bill_owner() -> LifeSim:
	return null if members.is_empty() else members[0].sim

## Everyone shares one bill, so every member's action availability and phone show
## the same record as the owner's ledger. Refreshed only when the bill can have
## changed: a new day, or a payment.
func _sync_bill_mirror() -> void:
	var owner: LifeSim = bill_owner()
	if owner == null:
		return
	for member: Dictionary in members:
		if member.sim != owner:
			member.sim.set_bill_mirror(owner.pending_bill, owner.utilities_cut, owner.bills_paid_total, owner.bills_late, owner.last_bill_day, owner.insurance_policy_id)

## The outstanding bill as the household sees it, empty when nothing is due.
func bill() -> Dictionary:
	var owner: LifeSim = bill_owner()
	return {} if owner == null else owner.pending_bill

func bill_total_due() -> int:
	var owner: LifeSim = bill_owner()
	return 0 if owner == null else owner.bill_total_due()

## True while the utilities are cut for non-payment.
func utilities_cut() -> bool:
	var owner: LifeSim = bill_owner()
	return false if owner == null else owner.utilities_cut

## Settle the household bill from the shared purse, then mirror the outcome to
## every member and return the result to the phone.
func pay_bill() -> Dictionary:
	var owner: LifeSim = bill_owner()
	if owner == null:
		return {"ok": false, "reason": "There is no household to bill."}
	owner.funds = funds
	var result: Dictionary = owner.pay_bill()
	if bool(result.get("ok", false)):
		funds = owner.funds
		_sync_bill_mirror()
		_sync_wallet()
	return result


## The household's home insurance, empty while uninsured. Mirrored from the
## owner so the phone shows the same cover whoever is selected.
func insurance() -> Dictionary:
	var owner: LifeSim = bill_owner()
	return {} if owner == null else owner.insurance_policy()


## Buy home insurance with the shared purse. Refused, with its reason, while a
## policy is already in force or the wallet cannot cover the premium; the money
## is charged only on success. Returns `{ok, error}` for the phone.
func buy_insurance(policy_id: String = "home") -> Dictionary:
	var owner: LifeSim = bill_owner()
	if owner == null:
		return {"ok": false, "error": "There is no household to insure."}
	owner.funds = funds
	var result: Dictionary = owner.buy_insurance(policy_id)
	if bool(result.get("ok", false)):
		funds = owner.funds
		_sync_bill_mirror()
		_sync_wallet()
		insurance_changed.emit(policy_id)
	else:
		result["error"] = str(result.get("error", result.get("reason", "That policy could not be bought.")))
	return result


## Give up the cover. Nothing is refunded; the owner's notice carries the news.
func cancel_insurance() -> Dictionary:
	var owner: LifeSim = bill_owner()
	if owner == null:
		return {"ok": false, "error": "There is no household to insure."}
	var result: Dictionary = owner.cancel_insurance()
	_sync_bill_mirror()
	if bool(result.get("ok", false)): insurance_changed.emit("")
	return result


## Whether a Lifelet may cook right now, as the reason they may not. Empty means
## the kitchen has food. The stove's menu and `begin_current_action` both read
## this, so a greyed-out recipe and a refused cook never disagree.
func cooking_availability(_sim: LifeSim, _target_id: String = "") -> String:
	if not LifeGroceries.can_cook(groceries):
		return "The kitchen is empty. Order a delivery from the computer, or from the fridge."
	return ""


## Whether a Lifelet may order right now, as the reason they may not. Empty means
## the shop can be ordered: a delivery already on its way, a purse that cannot
## afford the smallest basket, or a kitchen that is already stocked all refuse it
## with their own reason, so a menu row and a refused order never disagree.
func grocery_availability() -> String:
	if LifeGroceries.has_order(groceries):
		return LifeGroceries.order_error(groceries, "small", funds)
	if not LifeGroceries.needs_restock(groceries):
		return "The kitchen is stocked. A shop now would only spoil."
	return LifeGroceries.order_error(groceries, "small", funds)


## Order the largest basket the household can afford, for a Lifelet shopping from
## the kitchen rather than from the computer. The smallest basket is the bar: a
## household that cannot afford even that is refused and told why, exactly as the
## computer's own panel refuses it.
func order_groceries_best() -> Dictionary:
	var basket_id: String = LifeGroceries.best_basket_for(groceries, funds)
	if basket_id.is_empty():
		return {"ok": false, "error": LifeGroceries.order_error(groceries, "small", funds)}
	return order_groceries(basket_id)


## Take one meal out of the kitchen for a recipe or a snack. Refused with a
## reason when the kitchen is empty, so nothing is cooked from nothing.
func take_meal_for(_sim: LifeSim, _action_id: String = "") -> Dictionary:
	var result: Dictionary = LifeGroceries.take_meal(groceries)
	if not bool(result.ok):
		return result
	groceries = result.state
	_sync_grocery_mirror()
	return result


## Order a grocery delivery from the computer. The shared purse pays, and the van
## is given its own arrival time; a household that orders and cooks in the same
## minute has to wait for it like anybody else.
func order_groceries(basket_id: String = "weekly") -> Dictionary:
	var owner: LifeSim = bill_owner()
	if owner == null:
		return {"ok": false, "error": "There is no household to order for."}
	var reason: String = LifeGroceries.order_error(groceries, basket_id, funds)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var placed_day: int = day if owner.day == day else day
	var placed_minutes: float = minutes if absf(owner.minutes - minutes) < .0001 else minutes
	var result: Dictionary = LifeGroceries.order(groceries, basket_id, funds, placed_day, placed_minutes)
	if not bool(result.ok):
		return result
	groceries = result.state
	funds = int(result.funds)
	_sync_wallet()
	owner.funds = funds
	owner._emit_notice("Groceries ordered. A delivery of %d meals arrives %s." % [int(result.meals), "today" if int(result.day) == placed_day else "tomorrow"])
	owner._emit_changed()
	return result


## What the van has brought, if anything is due. The household drives this from
## its own clock, so a delivery arrives while the player simply plays.
func collect_groceries() -> Dictionary:
	var result: Dictionary = LifeGroceries.collect(groceries)
	if not bool(result.ok):
		return result
	groceries = result.state
	_sync_grocery_mirror()
	var owner: LifeSim = bill_owner()
	if owner != null:
		owner._emit_notice("The organic delivery van arrived: %d meals into the kitchen." % int(result.meals))
		owner._emit_changed()
	return result


## The kitchen as the player reads it.
func kitchen() -> String:
	return LifeGroceries.describe(groceries)


## Every basket the computer may order, with its price and its own refusal.
func grocery_offers() -> Array:
	var result: Array = []
	for basket_id: String in LifeGroceries.baskets():
		var reason: String = LifeGroceries.order_error(groceries, basket_id, funds)
		var data: Dictionary = LifeGroceries.basket(basket_id)
		result.append({
			"id": basket_id, "label": str(data.label), "meals": int(data.meals),
			"price": int(data.price), "description": str(data.description),
			"available": reason.is_empty(), "reason": reason,
		})
	return result


## Whether the van has arrived, checked once a tick on the shared clock.
func _grocery_tick() -> void:
	if speed <= 0:
		return
	var owner: LifeSim = bill_owner()
	if owner == null:
		return
	if LifeGroceries.arrival_due(groceries, day, minutes):
		collect_groceries()


func _sync_grocery_mirror() -> void:
	for member in members:
		member.sim.grocery_service = self


## Hand every member this household as its kitchen, so the stove's menu and the
## cook gate read the same fridge.
func _sync_grocery_service() -> void:
	for member in members:
		member.sim.grocery_service = self


## Buy a business. The skill and level the table demands are checked against the
## Lifelet actually applying, and the purse pays, so owning a business is a real
## achievement rather than a purchase.
func buy_business(business_id: String, member_id: String = "") -> Dictionary:
	var owner: LifeSim = member_sim(member_id) if not member_id.is_empty() else bill_owner()
	if owner == null:
		return {"ok": false, "error": "There is nobody to run a business."}
	if not business.is_empty():
		return {"ok": false, "error": "This household already runs a business. A second one is not supported yet."}
	var reason: String = LifeBusiness.purchase_error(business_id, str(owner.character.life_stage), owner.skills, funds)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var cost: int = int(LifeBusiness.info(business_id).cost)
	business = {"version": LifeBusiness.VERSION, "id": business_id, "staff": [], "invested": cost, "earned": 0}
	funds -= cost
	_sync_wallet()
	owner._emit_notice("You now run the %s. Hire people to make it pay." % str(LifeBusiness.info(business_id).label))
	owner._emit_changed()
	return {"ok": true, "cost": cost, "funds": funds}


## Hire one Lifelet as an employee. The hire fee is paid from the shared purse
## and the employee joins the roster.
func hire_employee(member_id: String) -> Dictionary:
	if business.is_empty():
		return {"ok": false, "error": "This household does not run a business."}
	var employee: LifeSim = member_sim(member_id)
	if employee == null:
		return {"ok": false, "error": "That Lifelet is not in this household."}
	var name: String = str(employee.character.name)
	var roster: Array = business.get("staff", [])
	var reason: String = LifeBusiness.hire_error(str(business.id), roster, funds)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	if roster.has(name):
		return {"ok": false, "error": "%s already works here." % name}
	var cost: int = LifeBusiness.hire_cost(str(business.id))
	business["staff"] = roster + [name]
	funds -= cost
	_sync_wallet()
	var owner: LifeSim = bill_owner()
	if owner != null:
		owner._emit_notice("%s now works at the %s." % [name, str(LifeBusiness.info(str(business.id)).label)])
		owner._emit_changed()
	return {"ok": true, "cost": cost, "funds": funds, "staff": business.staff.duplicate()}


## What the business pays a day, for the day boundary to credit.
func business_income() -> int:
	return LifeBusiness.daily_income(business) if not business.is_empty() else 0


## Every business the household could run, with its requirement and its own
## refusal, so the panel and the purchase agree.
func business_offers(member_id: String = "") -> Array:
	var owner: LifeSim = member_sim(member_id) if not member_id.is_empty() else bill_owner()
	var result: Array = []
	for business_id: String in LifeBusiness.ids():
		var info: Dictionary = LifeBusiness.info(business_id)
		var reason: String = "" if owner == null else LifeBusiness.purchase_error(business_id, str(owner.character.life_stage), owner.skills, funds)
		if owner == null: reason = "There is nobody to run a business."
		result.append({
			"id": business_id, "label": str(info.label), "cost": int(info.cost),
			"income": LifeBusiness.daily_income({"id": business_id, "staff": []}),
			"staff": int(info.staff), "skill": str(info.skill), "level": int(info.level),
			"requirements": LifeBusiness.requirement_text(business_id),
			"available": reason.is_empty(), "reason": reason,
			"owned": not business.is_empty() and str(business.get("id", "")) == business_id,
		})
	return result


## The daily takings of an owned business, credited at the day boundary beside
## the other household income.
func _business_tick() -> void:
	if business.is_empty() or speed <= 0:
		return
	var owner: LifeSim = bill_owner()
	if owner == null:
		return
	var income: int = business_income()
	if income <= 0:
		return
	business["earned"] = int(business.get("earned", 0)) + income
	funds += income
	_sync_wallet()
	owner.funds = funds
	owner._emit_notice("The %s took ℒ%d today." % [str(LifeBusiness.info(str(business.id)).label), income])
	owner._emit_changed()


## Every member on the criminal line of work takes one chance of being caught a
## day, on the shared clock. It is rolled by the household rather than by the
## Lifelet alone so that the odds apply while the player simply plays, exactly as
## the burglar's night does.
##
## A Lifelet already inside serves their sentence and cannot be caught again
## until they are out, and someone caught today is not re-rolled the same day.
func _criminal_tick() -> void:
	if speed <= 0:
		return
	for member: Dictionary in members:
		var sim: LifeSim = member.sim
		if not LifeCareers.is_criminal(str(sim.career.get("track", ""))):
			continue
		if sim.is_imprisoned():
			continue
		sim.funds = funds
		var outcome: Dictionary = sim.criminal_day_check()
		funds = sim.funds
		if bool(outcome.get("ok", false)) and bool(outcome.get("caught", false)):
			_sync_wallet()


## Release every member whose sentence has run out, so being caught really ends
## and a released Lifelet comes back to the household's lot.
func _prison_release_tick() -> void:
	for member: Dictionary in members:
		var sim: LifeSim = member.sim
		if not sim.is_at_prison():
			continue
		if sim.day < int(sim.criminal_record.get("prison_until_day", 0)):
			continue
		sim.prison_check()


## A break-in against the shared purse. The owner rolls it and the household
## takes the outcome, exactly as it settles a bill, so the loss is real money and
## an insured home ends the night even.
func robbery() -> Dictionary:
	var owner: LifeSim = bill_owner()
	if owner == null:
		return {"ok": false, "reason": "There is no household to rob."}
	owner.funds = funds
	var result: Dictionary = owner.robbery()
	funds = owner.funds
	_sync_wallet()
	return result

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
		if _cooperation_member_ids(session).has(member_id): return session
	return {}

func _cooperation_member_ids(session: Dictionary) -> Array[String]:
	# Homework sessions keep their learner/helper roles. An intimate session is
	# symmetric: both members are participants and neither is "the helper".
	if LifeBabyPlan.session_kind(session) == LifeBabyPlan.SESSION_KIND:
		return [str(session.get("a_id","")),str(session.get("b_id",""))]
	return [str(session.get("learner_id","")),str(session.get("helper_id",""))]

func _sessions_of_kind(kind: String) -> Array:
	var found:Array=[]
	for session:Dictionary in cooperations:
		if LifeBabyPlan.session_kind(session) == kind: found.append(session)
	return found

func _cooperation(token: String) -> Dictionary:
	for session: Dictionary in cooperations:
		if str(session.id) == token: return session
	return {}

func cooperation_state(token: String) -> Dictionary:
	# Presentation only: the beat's cover animation asks whether its own session
	# is still running, exactly as the queue asks for a presentation view.
	return _cooperation(token)

func cooperative_presentation(member_id: String) -> Dictionary:
	var session: Dictionary = _member_cooperation(member_id)
	if session.is_empty(): return {}
	if LifeBabyPlan.session_kind(session) == LifeBabyPlan.SESSION_KIND:
		return _baby_presentation(session,member_id)
	var learner: LifeSim = member_sim(str(session.learner_id))
	var action: Dictionary = learner.get_current_action()
	var role: String = "learner" if member_id == str(session.learner_id) else "helper"
	return {"session_id":str(session.id),"role":role,"phase":str(session.phase),"ready":session.ready.has(member_id),"partner_id":str(session.helper_id) if role == "learner" else str(session.learner_id),"learner_id":str(session.learner_id),"helper_id":str(session.helper_id),"furniture_id":str(session.furniture_id),"elapsed":float(action.get("elapsed",0.0)),"duration":45.0,"progress":float(action.get("progress",0.0)),"learner_position":Vector3(session.learner_position[0],session.learner_position[1],session.learner_position[2]),"helper_position":Vector3(session.helper_position[0],session.helper_position[1],session.helper_position[2])}

func _baby_presentation(session: Dictionary, member_id: String) -> Dictionary:
	# One shared clock: the pair's elapsed/minutes are mirrored by the session
	# owner below, exactly as a shared homework session mirrors its learner.
	var owner: LifeSim = member_sim(str(session.a_id))
	var action: Dictionary = owner.get_current_action()
	var role: String = "a" if member_id == str(session.a_id) else "b"
	return {"kind":LifeBabyPlan.SESSION_KIND,"session_id":str(session.id),"role":role,"phase":str(session.phase),"ready":session.ready.has(member_id),"partner_id":str(session.b_id) if role == "a" else str(session.a_id),"a_id":str(session.a_id),"b_id":str(session.b_id),"furniture_id":str(session.furniture_id),"elapsed":float(action.get("elapsed",0.0)),"duration":LifeBabyPlan.DURATION,"progress":float(action.get("progress",0.0))}

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
			for id: String in _cooperation_member_ids(session):
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
	var reason:String = "Homework together was cancelled. The assignment is still available today."
	if LifeBabyPlan.session_kind(session) == LifeBabyPlan.SESSION_KIND:
		reason = "The moment passed. The bed is free again whenever you both want to try."
	_begin_cooperation_change()
	_cancel_cooperation(session,reason)
	_end_cooperation_change()
	return true

func _cancel_cooperation(session: Dictionary, reason: String) -> void:
	cooperations.erase(session)
	for id: String in _cooperation_member_ids(session):
		var actor: LifeSim = member_sim(id)
		if actor == null: continue
		var front_removed: bool = not actor.action_queue.is_empty() and str(actor.action_queue[0].get("cooperation_id","")) == str(session.id)
		for index: int in range(actor.action_queue.size()-1,-1,-1):
			if str(actor.action_queue[index].get("cooperation_id","")) == str(session.id): actor.action_queue.remove_at(index)
		if front_removed: actor._start_front()
		actor._emit_changed()
	var lead: LifeSim = member_sim(str(session.get("learner_id",session.get("a_id",""))))
	if lead != null and not reason.is_empty(): lead._emit_notice(reason)

func _cooperation_error(session: Dictionary) -> String:
	if LifeBabyPlan.session_kind(session) == LifeBabyPlan.SESSION_KIND:
		return _baby_session_error(session)
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

func _baby_session_error(session: Dictionary) -> String:
	# Interruption, a moved bed or a new life stage ends the beat for both. The
	# beat carries its own action, so a partner who was woken already broke the
	# shared action identity below; no separate sleep check is needed.
	if str(session.phase) == "assembling" and float(session.waited) >= COOPERATION_WAIT_LIMIT:
		return "The Lifelets could not settle in together. Choose the bed again when they are both asleep."
	var first: LifeSim = member_sim(str(session.a_id))
	var second: LifeSim = member_sim(str(session.b_id))
	if first == null or second == null: return "One partner is no longer part of this household."
	if first.day != int(session.day) or second.day != int(session.day):
		return "A new day begins. Try for Baby again tonight."
	for pair: Array in [[first,str(session.a_id)],[second,str(session.b_id)]]:
		var actor: LifeSim = pair[0]
		var action: Dictionary = actor.get_current_action()
		if str(action.get("cooperation_id","")) != str(session.id) or str(action.get("target_id","")) != str(session.furniture_id):
			return "The moment ends early. Both partners can try again when they are settled in together."
		if str(actor.character.get("life_stage","adult")) != "adult":
			return "The moment ends early. Both partners must be adults."
	return ""

func _reconcile_cooperations() -> void:
	for session: Dictionary in cooperations.duplicate():
		var reason: String = _cooperation_error(session)
		if not reason.is_empty():
			_cancel_cooperation(session,reason)
			continue
		var ids:Array[String] = _cooperation_member_ids(session)
		var source: Dictionary = member_sim(ids[0]).get_current_action()
		for other_id:String in ids.slice(1):
			var mirror: Dictionary = member_sim(other_id).get_current_action()
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

func finish_cooperative_action(token: String) -> void:
	var session: Dictionary = _cooperation(token)
	if session.is_empty(): return
	if LifeBabyPlan.session_kind(session) == LifeBabyPlan.SESSION_KIND:
		finish_try_for_baby(session)
		return
	finish_cooperative_homework(token)

func finish_try_for_baby(session: Dictionary) -> void:
	# The pair's beat completes: the shared clock must have run its course, and
	# the household conceives exactly once, on the moment the beat finishes.
	_begin_cooperation_change()
	var reason: String = _cooperation_error(session)
	var first: LifeSim = member_sim(str(session.a_id))
	if reason.is_empty() and (str(session.phase) != "active" or first == null or float(first.get_current_action().elapsed) < LifeBabyPlan.DURATION):
		reason = "Both partners must stay together for the whole moment."
	if not reason.is_empty():
		_cancel_cooperation(session,reason)
		_end_cooperation_change()
		return
	var ids:Array[String] = _cooperation_member_ids(session)
	cooperations.erase(session)
	pregnancy = LifeBabyPlan.conceive(member_sim(str(session.mother_id)),str(session.mother_id),member_sim(str(session.father_id)),str(session.father_id),day,minutes,birth_serial)
	birth_serial = mini(int(pregnancy.get("serial",1))+1,LifeBabyPlan.MAX_BIRTHS)
	# Sims-4 flow: the beat conceives a pregnancy, and the birth follows when
	# the countdown completes (pregnancy_tick), which opens the baby creator.
	var actions:Array = []
	for id:String in ids:
		var actor:LifeSim = member_sim(id)
		var action:Dictionary = actor.action_queue.pop_front()
		action.phase="finished"
		action.elapsed=LifeBabyPlan.DURATION
		action.progress=1.0
		action["baby_conceived"]=true
		actions.append([actor,action,id])
	var mother:LifeSim = member_sim(str(session.mother_id))
	if mother != null:
		# Conception is a beginning, not the arrival itself: the birth moodlet
		# comes later, and the Expecting countdown stays the strongest tile.
		mother.add_moodlet("A little one on the way","Happy","The family is expecting. The baby arrives in about three days.",LifeBabyPlan.PREGNANCY_MINUTES,2)
		mother.remember("A new beginning","The family is welcoming a new baby.")
	pregnancy_began.emit(str(session.mother_id))
	var father:LifeSim = member_sim(str(session.father_id))
	if father != null:
		father.add_moodlet("A shared secret","Confident","Something wonderful is beginning for the family.",720,2)
	_sync_social_context()
	for entry:Array in actions:
		var actor:LifeSim = entry[0]
		var action:Dictionary = entry[1]
		actor._emit_action_finished(action)
		actor._idle_minutes=0.0
		actor._start_front()
		actor._emit_changed()
	_end_cooperation_change()

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
		if LifeBabyPlan.session_kind(session) == LifeBabyPlan.SESSION_KIND:
			var baby_error:String = _validate_saved_baby_session(session,data,by_id,used_members,used_tokens)
			if not baby_error.is_empty(): return baby_error
			bound_actions += 2
			continue
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

func _validate_saved_baby_session(session: Dictionary, data: Dictionary, by_id: Dictionary, used_members: Array[String], used_tokens: Array[String]) -> String:
	for key: String in ["id","kind","a_id","b_id","mother_id","father_id","furniture_id","phase"]:
		if not session.get(key) is String: return "Save contains an invalid intimate session identity."
	var token: String = str(session.id)
	var suffix: String = token.trim_prefix(LifeBabyPlan.TOKEN_PREFIX)
	if not token.begins_with(LifeBabyPlan.TOKEN_PREFIX) or not suffix.is_valid_int() or str(int(suffix)) != suffix or int(suffix) < 1 or int(suffix) > int(data.get("cooperation_serial",0)) or used_tokens.has(token): return "Save contains a duplicate or invalid intimate session token."
	used_tokens.append(token)
	var a_id: String = str(session.a_id)
	var b_id: String = str(session.b_id)
	if a_id == b_id or not by_id.has(a_id) or not by_id.has(b_id) or used_members.has(a_id) or used_members.has(b_id): return "Save assigns a Lifelet to impossible or overlapping intimate sessions."
	used_members.append_array([a_id,b_id])
	if str(session.furniture_id).is_empty() or by_id.has(str(session.furniture_id)): return "Save assigns an intimate session to a missing bed."
	if [a_id,b_id].has(str(session.mother_id)) == false or [a_id,b_id].has(str(session.father_id)) == false or str(session.mother_id) == str(session.father_id): return "Save contains an intimate session with unrelated parents."
	if str(session.phase) not in ["assembling","active"] or not session.get("ready") is Array or session.ready.size() > 2: return "Save contains an invalid intimate session phase."
	var ready: Array = []
	for id: Variant in session.ready:
		if not id is String or str(id) not in [a_id,b_id] or ready.has(id): return "Save contains invalid intimate arrival flags."
		ready.append(id)
	if str(session.phase) == "active" and ready.size() != 2: return "Save starts an intimate session before both Lifelets arrive."
	if not _cooperation_number(session.get("day"),float(data.get("day",1)),float(data.get("day",1)),true) or not _cooperation_number(session.get("created_minutes"),0,float(data.get("minutes",0))): return "Save contains an expired or invalid intimate meeting."
	if not _cooperation_number(session.get("waited"),0,COOPERATION_WAIT_LIMIT-.000001): return "Save contains impossible intimate waiting time."
	var first: Dictionary = by_id[a_id]
	var second: Dictionary = by_id[b_id]
	if str(first.character.get("life_stage","")) != "adult" or str(second.character.get("life_stage","")) != "adult": return "Save contains an intimate session with a non-adult."
	if str(first.get("romantic_partner","")) != b_id or str(second.get("romantic_partner","")) != a_id: return "Save starts an intimate session without a partnership."
	if LifeBabyPlan.gender_of(first.character) == LifeBabyPlan.gender_of(second.character): return "Save starts an intimate session without opposite genders."
	for role: String in [a_id,b_id]:
		var state: Dictionary = by_id[role]
		if not state.get("action_queue") is Array or state.action_queue.is_empty() or not state.action_queue[0] is Dictionary: return "Save is missing a paired intimate action."
		var action: Dictionary = state.action_queue[0]
		if str(action.get("id","")) != LifeBabyPlan.ACTION_ID or str(action.get("cooperation_id","")) != token or str(action.get("cooperation_role","")) != role or str(action.get("target_id","")) != str(session.furniture_id): return "Save links an intimate session to the wrong action or bed."
		if not _cooperation_number(action.get("duration"),LifeBabyPlan.DURATION,LifeBabyPlan.DURATION) or not _cooperation_number(action.get("elapsed"),0,LifeBabyPlan.DURATION-.000001) or not action.get("paid") is bool or bool(action.get("autonomous",false)): return "Save contains invalid paired intimate progress."
		if str(action.get("phase","")) != ("active" if str(session.phase) == "active" else "approach"): return "Save contains inconsistent paired intimate phases."
		if str(action.get("seat_slot","")) not in ["left","right"]: return "Save contains an intimate action without a bed half."
		if bool(action.paid) != (str(session.phase) == "active"): return "Save contains an intimate beat that never began."
		if bool(action.paid) and action.get("started_day") != data.get("day"): return "Save contains an intimate beat started on another day."
	return ""


# --- Try for Baby, pregnancy and birth -------------------------------------
# The pair's beat is a cooperative session like shared homework: both members
# hold one action, one shared clock, and either can end it for both.

func try_for_baby_plan(initiator_id: String, bed_id: String) -> Dictionary:
	var initiator:LifeSim=member_sim(initiator_id)
	if initiator==null:return {"ok":false,"error":"That Lifelet is not part of this household."}
	var reason:String=LifeBabyPlan.try_error(initiator,bed_id,members,pregnancy)
	if not reason.is_empty():return {"ok":false,"error":reason}
	var partner:LifeSim=member_sim(str(initiator.romantic_partner))
	var pair:Array=LifeBabyPlan.mother_of(initiator,initiator_id,partner,str(initiator.romantic_partner))
	var bed:Dictionary=_target(bed_id)
	if bed.is_empty():return {"ok":false,"error":"Choose the bed both partners are sleeping in."}
	# Both sleepers keep the half they already hold; the beat adds no new slot.
	var a:LifeSim=member_sim(str(pair[0]))
	var b:LifeSim=member_sim(str(pair[1]))
	if LifeBabyPlan.now_of(day,minutes) <= 0.0:return {"ok":false,"error":"The household clock is not ready."}
	return {"ok":true,"request":{"token":LifeBabyPlan.TOKEN_PREFIX+str(cooperation_serial+1),"a_id":str(pair[0]),"b_id":str(pair[1]),"mother_id":str(pair[0]),"father_id":str(pair[1]),"bed_id":bed_id,"slot_a":str(a.get_current_action().get("seat_slot","left")),"slot_b":str(b.get_current_action().get("seat_slot","right")),"position_a":a.get_current_action().get("target_position",Vector3.ZERO),"position_b":b.get_current_action().get("target_position",Vector3.ZERO),"day":day,"minutes":minutes}}

func begin_try_for_baby(initiator_id: String, bed_id: String) -> Dictionary:
	var plan:Dictionary=try_for_baby_plan(initiator_id,bed_id)
	if not bool(plan.ok):return plan
	var request:Dictionary=plan.request
	# Re-check the exact bed claim, since a live household may have changed
	# between the menu and the click.
	for id:String in [str(request.a_id),str(request.b_id)]:
		var actor:LifeSim=member_sim(id)
		if not LifeBabyPlan.sleeping_in(actor,str(request.bed_id)):return {"ok":false,"error":"Both partners must be asleep in the same bed first."}
	_begin_cooperation_change()
	cooperation_serial += 1
	var token:String=LifeBabyPlan.TOKEN_PREFIX+str(cooperation_serial)
	var session:Dictionary={"id":token,"kind":LifeBabyPlan.SESSION_KIND,"a_id":str(request.a_id),"b_id":str(request.b_id),"mother_id":str(request.mother_id),"father_id":str(request.father_id),"furniture_id":str(request.bed_id),"day":int(request.day),"created_minutes":float(request.minutes),"phase":"assembling","ready":[],"waited":0.0}
	cooperations.append(session)
	var initiator:String=initiator_id
	var ids:Array=[str(request.a_id),str(request.b_id)]
	for id:String in ids:
		var actor:LifeSim=member_sim(id)
		var action:Dictionary=actor._actions[LifeBabyPlan.ACTION_ID].duplicate(true)
		var slot:String=str(request.slot_a) if id==str(request.a_id) else str(request.slot_b)
		var position:Vector3=request.position_a if id==str(request.a_id) else request.position_b
		action.merge({"target_id":str(request.bed_id),"target_kind":"bed","target_position":position,"seat_slot":slot,"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":false,"cooperation_id":token,"cooperation_role":id,"cooperation_primary":id==str(request.a_id),"partner_id":str(request.b_id) if id==str(request.a_id) else str(request.a_id)},true)
		# The pair is already asleep in this bed: the beat takes the front of
		# the queue and the sleep it interrupted waits behind it, so finishing
		# or cancelling the beat puts both partners straight back to sleep.
		actor.action_queue.push_front(action)
		actor._idle_minutes=0.0
		actor._start_front()
		actor._emit_changed()
	if not initiator.is_empty() and member_sim(initiator)==null:initiator=""
	_end_cooperation_change()
	return {"ok":true,"session_id":token}

func pregnancy_tick() -> void:
	# The due moment is a game-minute countdown, so fast speed and a load both
	# work without any wall-clock timer. Called once per household tick.
	if not bool(pregnancy.get("active",false)):return
	var expecting:LifeSim=member_sim(str(pregnancy.mother_id))
	if expecting!=null:
		# Sims-4 shows the wait as a moodlet with the days left on it.
		expecting.add_moodlet("Expecting","Happy",LifeBabyPlan.countdown_text(pregnancy,day,minutes)+" until the baby arrives.",60,2)
	if LifeBabyPlan.remaining_minutes(pregnancy,day,minutes) > 0.0:return
	var mother:LifeSim=member_sim(str(pregnancy.mother_id))
	var father:LifeSim=member_sim(str(pregnancy.father_id))
	if mother==null or father==null:return
	_begin_cooperation_change()
	pregnancy=LifeBabyPlan.resolve_birth(pregnancy,day,minutes)
	if mother!=null:
		mother.add_moodlet("A new arrival","Happy","The wait is over. A baby is ready to meet the family.",1440,3)
	if father!=null:
		father.add_moodlet("A new arrival","Happy","The wait is over. A baby is ready to meet the family.",1440,3)
	baby_born.emit(str(pregnancy.get("mother_id","")))
	_end_cooperation_change()

func birth_ready() -> bool:
	return bool(pregnancy.get("pending",false))

## How far the current pregnancy has advanced, 0..1, or -1 when nobody is
## expecting. The bump, the HUD meter and any notice all read this one number.
func pregnancy_progress() -> float:
	if not bool(pregnancy.get("active",false)):return -1.0
	var total:float=float(LifeBabyPlan.PREGNANCY_MINUTES)
	if total<=0.0:return 0.0
	return clampf(1.0-float(LifeBabyPlan.remaining_minutes(pregnancy,day,minutes))/total,0.0,1.0)

func pregnancy_mother_id() -> String:
	if not bool(pregnancy.get("active",false)):return ""
	return str(pregnancy.get("mother_id",""))

func pending_baby_profile() -> Dictionary:
	if not birth_ready():return {}
	return LifeBabyPlan.pending_birth(pregnancy,day,minutes).baby

## The only place a baby joins the household. The player's creator profile is
## the baby's own; the family graph and both parents' relationship rows are
## written exactly as an adoption writes its guardian links.
func commit_baby(profile: Dictionary, spawn: Vector3, destination: Vector3, world_data: Array) -> Dictionary:
	if not birth_ready():return {"ok":false,"error":"This household is not expecting a baby right now."}
	var reason:String=LifeBabyPlan.profile_error(profile)
	if not reason.is_empty():return {"ok":false,"error":reason}
	if members.size()>=MAX_MEMBERS:return {"ok":false,"error":"Your household already has eight Lifelets."}
	var mother_id:String=str(pregnancy.mother_id)
	var father_id:String=str(pregnancy.father_id)
	var mother:LifeSim=member_sim(mother_id)
	if mother==null or member_sim(father_id)==null:return {"ok":false,"error":"The parents are no longer part of this household."}
	if not LifeAdoption.point(spawn) or not LifeAdoption.point(destination):return {"ok":false,"error":"A safe arrival route is required."}
	var snapshot:Dictionary=get_state(world_data)
	if snapshot.has("snapshot_error"):return {"ok":false,"error":str(snapshot.snapshot_error)}
	var id:String="housemate_%d" % members.size()
	var baby:=LifeSim.new()
	# The household enables Wants and Fears for every Lifelet it adds, exactly as
	# add_member does. A born or adopted member builds its LifeSim directly, so
	# without this it started with no whims at all and could never earn one.
	var baby_profile:Dictionary=profile.duplicate(true)
	baby_profile["wants_and_fears"]=true
	baby.new_household(baby_profile)
	baby.day=day;baby.minutes=minutes;baby.funds=funds;baby.speed=speed
	baby.education=LifeEducation.fresh("baby",day)
	baby.career.schedule=LifeCareerSchedule.fresh(day)
	baby._story_generated_day=day
	baby.set_aging(str(mother.lifecycle.lifespan),bool(mother.lifecycle.auto_age))
	baby.character.world_state={"player":[spawn.x,spawn.y,spawn.z],"player_rotation":PI,"resource_wait_started":-1.0,"resource_action_active":false,"waiting_action_id":"arrive_home","waiting_target_id":"lot_exit"}
	var arrival:Dictionary=baby._actions.arrive_home.duplicate(true)
	arrival.merge({"target_id":"lot_exit","target_kind":"lot_exit","target_position":destination,"elapsed":0.0,"progress":0.0,"phase":"approach","paid":false,"autonomous":false,"baby_serial":int(pregnancy.get("serial",1))},true)
	baby.action_queue.append(arrival)
	var baby_state:Dictionary=baby.get_state();baby.free()
	snapshot.members.append({"id":id,"state":baby_state})
	if snapshot.has("journeys"):
		var journey_identity:int=int(snapshot.journeys.next_identity)
		snapshot.journeys.next_identity=journey_identity+1
		snapshot.journeys.members[id]={"position":LifeJourneyState.packed(spawn),"yaw":PI,"motion":{"phase":"route","identity":journey_identity,"ticket":0,"safety":false,"custody":"","destination":LifeJourneyState.packed(destination),"stair_id":"","direction":0,"distance":0.0,"wait":[],"clear":[],"intent":{"kind":"action","id":"arrive_home","target_id":"lot_exit","meal_source":"","meal_stage":"","meal_plate":""}}}
	for parent:String in [mother_id,father_id]:snapshot.family_graph.parents.append({"a":parent,"b":id})
	var ids:Array=[]
	for entry:Dictionary in snapshot.members:ids.append(str(entry.id))
	snapshot.family_graph=LifeFamilyGraph.canonical(snapshot.family_graph,ids)
	for entry:Dictionary in snapshot.members:
		if str(entry.id)==id:continue
		var role:String=LifeFamilyGraph.relationship(snapshot.family_graph,str(entry.id),id)
		var familiar:bool=LifeFamilyGraph.is_family(role)
		var relation:Dictionary={"name":baby_state.character.name,"friendship":55.0 if familiar else 18.0,"romance":0.0,"status":LifeFamilyGraph.label(role),"life_stage":"minor","bond":"none","milestones":["met","friends"] if familiar else [],"family_role":role}
		entry.state.relationships[id]=relation
		var reverse:Dictionary=relation.duplicate(true)
		reverse.name=entry.state.character.name;reverse.life_stage=entry.state.character.life_stage
		reverse.family_role=LifeFamilyGraph.inverse(role);reverse.status=LifeFamilyGraph.label(str(reverse.family_role))
		baby_state.relationships[str(entry.id)]=reverse
	snapshot.pregnancy=LifeBabyPlan.fresh()
	snapshot.birth_serial=mini(int(pregnancy.get("serial",1))+1,LifeBabyPlan.MAX_BIRTHS)
	# Validate the complete proposed household before mutating any live member.
	var validator:=LifeHousehold.new()
	var checked:Dictionary=validator.restore_state(snapshot)
	if not bool(checked.ok):validator.free();return checked
	var added:LifeSim=validator.member_sim(id)
	validator.remove_child(added)
	validator.free()
	for entry:Dictionary in snapshot.members:
		if str(entry.id)!=id:member_sim(str(entry.id)).relationships[id]=entry.state.relationships[id].duplicate(true)
	family_graph=snapshot.family_graph.duplicate(true)
	pregnancy=LifeBabyPlan.fresh()
	birth_serial=int(snapshot.birth_serial)
	if snapshot.has("journeys"):journeys=snapshot.journeys.duplicate(true)
	members.append({"id":id,"sim":added});add_child(added)
	added.name="Life_"+id;added.household_bills_enabled=false
	added.set_home_value_provider(home_value_provider)
	connect_member(id,added)
	_rebuild_family_roles()
	_sync_bill_mirror()
	return {"ok":true,"child":id,"spawn":spawn}

func _target(id: String) -> Dictionary:
	for target:Dictionary in targets:
		if str(target.id)==id:return target
	return {}

## ---------------------------------------------------------------- pet shop

## A pet review is offered only when the household has room and can pay.
func pet_availability(species: String) -> String:
	if not LifePets.SPECIES.has(species):return "Choose a cat or a dog."
	if pets.get("pets",[]).size()>=LifePets.MAX_PETS:return "Your household already has %d pets." % LifePets.MAX_PETS
	if selected().funds<LifePets.price_for(species):return "A %s costs ℒ%d. Your household needs more funds." % [LifePets.species_label(species).to_lower(),LifePets.price_for(species)]
	return ""

## The shop entry point is offered while either species can be adopted. The
## reason shown is the cat's, since that is the first choice on offer.
func pet_shop_availability() -> String:
	var cat:String=pet_availability("cat")
	if cat.is_empty():return ""
	if pet_availability("dog").is_empty():return ""
	return cat

func prepare_pet(review:Dictionary) -> Dictionary:
	var reason:String=pet_availability(str(review.get("species","")))
	if not reason.is_empty():return {"ok":false,"error":reason}
	reason=LifePets.profile_error(review)
	if not reason.is_empty():return {"ok":false,"error":reason}
	var request:Dictionary=review.duplicate(true)
	request["member_count"]=members.size()
	request["fee"]=LifePets.price_for(str(review.species))
	return {"ok":true,"request":request}

## Take a reviewed pet home. The household owns the fee; the view spawns the
## body on the returned spawn point. A repeated confirmation returns the
## original receipt, so a double click can never charge twice.
func commit_pet(request:Dictionary,spawn:Vector3) -> Dictionary:
	var reason:String=LifePets.request_error(request)
	if not reason.is_empty():return {"ok":false,"error":reason}
	for existing:Dictionary in pets.get("pets",[]):
		if int(existing.serial)==int(request.serial):
			if str(existing.species)==str(request.species) and str(existing.name)==str(request.name).strip_edges() and str(existing.coat_color)==LifePets.normalised_colour(request.coat_color,"89563a"):
				return {"ok":true,"duplicate":true,"pet":existing.duplicate(true),"spawn":spawn}
			return {"ok":false,"error":"That pet review has already been used. Open the shop again."}
	if int(request.serial)!=int(pets.next_serial):return {"ok":false,"error":"Your pets changed. Please review the shop again."}
	if int(request.member_count)!=members.size() or int(request.fee)!=LifePets.price_for(str(request.species)):
		return {"ok":false,"error":"Your household changed. Please review the shop again."}
	reason=pet_availability(str(request.species))
	if not reason.is_empty():return {"ok":false,"error":reason}
	if not LifePets.point(spawn):return {"ok":false,"error":"A safe arrival route is required."}
	var record:Dictionary=LifePets.record_from(request,"pet_%d" % int(pets.next_serial),day)
	pets.pets.append(record)
	pets.next_serial=int(pets.next_serial)+1
	set_funds(funds-LifePets.price_for(str(record.species)))
	return {"ok":true,"duplicate":false,"pet":record.duplicate(true),"spawn":spawn}

## ---------------------------------------------------------- pet care

## Advance every pet's own needs by a span of game minutes. A pet whose record
## predates the condition block gains a fresh one rather than being skipped, so
## an older save's animals start living on load.
func _tick_pet_care(minutes: float) -> void:
	if minutes <= 0.0: return
	for pet: Dictionary in pets.get("pets", []):
		if not pet.get("care") is Dictionary:
			pet["care"] = LifePetCare.fresh()
		LifePetCare.tick(pet.care, minutes)

## One pet's condition record, created on first use so a caller never has to
## check whether an older save carried one.
func pet_care(id: String) -> Dictionary:
	var pet: Dictionary = pet_record(id)
	if pet.is_empty(): return {}
	if not pet.get("care") is Dictionary:
		pet["care"] = LifePetCare.fresh()
	return pet.care

func pet_record(id: String) -> Dictionary:
	for pet: Dictionary in pets.get("pets", []):
		if str(pet.id) == id: return pet
	return {}

## What one Lifelet may do with one pet, in the order the card shows them. The
## list is filtered by the actor's own life stage and availability, so the
## offered options and a refused call agree.
func pet_actions(pet_id: String, member_id: String) -> Array:
	var pet: Dictionary = pet_record(pet_id)
	if pet.is_empty(): return []
	var sim: LifeSim = member_sim(member_id)
	if sim == null: return []
	var away: bool = sim.is_away()
	var out: Array = []
	for interaction: Dictionary in LifePetCare.INTERACTIONS:
		var reason: String = LifePetCare.interaction_error(str(interaction.id), str(sim.character.age_stage), away)
		out.append({
			"id": str(interaction.id),
			"label": str(interaction.label),
			"duration": float(interaction.duration),
			"available": reason.is_empty(),
			"unavailable_reason": reason,
			"description": _pet_action_description(str(interaction.id), pet),
		})
	return out

## What one interaction does, said in terms of what the player will actually
## see: which need it lifts, which trick it may teach, and what the actor learns.
func _pet_action_description(id: String, pet: Dictionary) -> String:
	var entry: Dictionary = LifePetCare.interaction(id)
	if entry.is_empty(): return ""
	var care: Dictionary = pet.get("care", LifePetCare.fresh())
	var parts: Array[String] = []
	if id == "pet_feed": parts.append("Fill the bowl and let %s eat their fill." % str(pet.get("name", "your pet")))
	if id == "pet_pet": parts.append("A quiet fuss. %s warms to you." % str(pet.get("name", "your pet")).capitalize())
	if id == "pet_play": parts.append("Play until you are both out of breath. Builds Agility.")
	if id == "pet_teach_trick":
		var next: Dictionary = LifePetCare.next_trick(care)
		parts.append("Teach the next trick: %s." % str(next.get("label", "something new")) if not next.is_empty() else "%s already knows every trick you can teach." % str(pet.get("name", "your pet")).capitalize())
	if id == "pet_train": parts.append("Patient repetition. Builds Obedience and your own Parenting.")
	var teaches: String = str(entry.get("teaches", ""))
	if not teaches.is_empty(): parts.append("You build %s too." % teaches.capitalize())
	return " ".join(parts)

## Do one interaction, on the household's side of the ledger: the pet's needs and
## skill move, its bond with this person deepens, and the person's own skill
## grows by what the interaction teaches. Returns what changed.
func do_pet_interaction(pet_id: String, member_id: String, interaction_id: String) -> Dictionary:
	var pet: Dictionary = pet_record(pet_id)
	if pet.is_empty(): return {"ok": false, "error": "That pet is no longer here."}
	var sim: LifeSim = member_sim(member_id)
	if sim == null: return {"ok": false, "error": "That Lifelet is no longer here."}
	var reason: String = LifePetCare.interaction_error(interaction_id, str(sim.character.age_stage), sim.is_away())
	if not reason.is_empty(): return {"ok": false, "error": reason}
	var care: Dictionary = pet_care(pet_id)
	var result: Dictionary = LifePetCare.apply_interaction(care, interaction_id, member_id)
	# The actor's own skill grows by what this interaction teaches, which is how
	# a child teaching a trick also becomes more logical.
	var teaches: String = str(result.get("teaches", ""))
	var teach_xp: float = float(result.get("teach_xp", 0.0))
	if not teaches.is_empty() and teach_xp > 0.0:
		sim.gain_skill(teaches, teach_xp)
	return {"ok": true, "pet": pet.duplicate(true), "care": care.duplicate(true), "result": result}

## ---------------------------------------------------------------- post box

## Whether the household owns a post box. Without one, bills arrive by notice
## and are paid from the phone exactly as they always did; the box adds a place,
## not a rule.
func owns_post_box() -> bool:
	return not _post_box_ids().is_empty()

## The identities of every placed post box, so one is enough however many are
## bought and a sold box stops delivering.
func _post_box_ids() -> Array[String]:
	var out: Array[String] = []
	if not post_box_provider.is_valid(): return out
	for id: Variant in post_box_provider.call():
		out.append(str(id))
	return out

## File one letter in the box, if the household has one. Returns the letter that
## was filed, or {} when there is nowhere to post it.
func deliver_mail(value: Dictionary) -> Dictionary:
	if not owns_post_box() or value.is_empty(): return {}
	var serial: int = int(mail.get("next_serial", 1))
	var filed: Dictionary = value.duplicate(true)
	filed["id"] = "mail_%d" % serial
	filed["serial"] = serial
	var delivered: Dictionary = LifeMail.deliver(mail, filed)
	notice.emit("The post has arrived: %s." % str(delivered.get("title", "a letter")))
	return delivered


## A letter for one of the household's own milestones. Written once per event,
## so a reload never re-posts the same school place.
func post_milestone(reason: String, who: String) -> Dictionary:
	if not LifeMail.LETTERS.has(reason): return {}
	for entry: Dictionary in mail.get("letters", []):
		if str(entry.get("subject", "")) == who and str(entry.get("title", "")) == str(LifeMail.LETTERS[reason].title):
			return {}
	var serial: int = int(mail.get("next_serial", 1))
	return deliver_mail(LifeMail.milestone(serial, reason, who, day))


## Post the household's outstanding bill, so the box can show what is owed. One
## bill is posted at a time; a reload of the same bill does not post a second.
func post_bill() -> Dictionary:
	if not owns_post_box(): return {}
	var record: Dictionary = bill()
	if record.is_empty(): return {}
	for entry: Dictionary in mail.get("letters", []):
		if LifeMail.is_bill(entry) and not bool(entry.get("read", false)):
			return {}
	return deliver_mail(LifeMail.bill_letter(int(mail.get("next_serial", 1)), int(record.amount) + int(record.get("late_fee", 0)), day, int(record.due_day)))

## Read one letter, which is what settles a bill the box is holding.
func read_mail(id: String) -> Dictionary:
	var letter: Dictionary = {}
	for entry: Dictionary in mail.get("letters", []):
		if str(entry.id) == id: letter = entry
	if letter.is_empty(): return {"ok": false, "error": "That letter is no longer in the box."}
	if LifeMail.is_bill(letter) and not bool(letter.get("read", false)):
		var settlement: Dictionary = pay_bill()
		if not bool(settlement.ok): return {"ok": false, "error": str(settlement.get("error", settlement.get("reason", "The bill could not be paid.")))}
		LifeMail.mark_read(mail, id)
		return {"ok": true, "paid": int(settlement.paid), "letter": letter}
	LifeMail.mark_read(mail, id)
	return {"ok": true, "paid": 0, "letter": letter}

## Whether the post box can deliver its own mail rather than the phone doing it.
func mail_availability() -> String:
	if not owns_post_box(): return "Place a post box in the garden and the post will be delivered there."
	if mail.get("letters", []).is_empty(): return "Nothing has been posted yet."
	return ""

## Buying a pet accessory is an ordinary furnishing purchase: the caller places
## it through the same build path, so support, doorway and reach checks apply.
func accessory_availability(kind:String) -> String:
	var reason:String=LifePets.accessory_kind_error(kind,pets.get("pets",[]))
	if not reason.is_empty():return reason
	if not LifeCatalog.ITEMS.has(kind):return "That accessory is not for sale."
	if selected().funds<int(LifeCatalog.ITEMS[kind].price):return "That costs ℒ%d. Your household needs more funds." % int(LifeCatalog.ITEMS[kind].price)
	return ""

func adoption_availability(guardians:Array) -> String:
	if members.size()>=MAX_MEMBERS:return "Your household already has eight Lifelets."
	if selected().funds<LifeAdoption.FEE:return "Adoption costs ℒ1,000. Your household needs more funds."
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
	# Same household rule as a birth and as add_member: every Lifelet the
	# household holds has Wants and Fears enabled.
	var child_profile:Dictionary=LifeAdoption.candidate(int(request.serial),int(request.choice)).duplicate(true)
	child_profile["wants_and_fears"]=true
	child.new_household(child_profile)
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
	added.set_home_value_provider(home_value_provider)
	connect_member(id,added)
	_rebuild_family_roles();set_funds(int(snapshot.funds))
	_sync_bill_mirror()
	return {"ok":true,"duplicate":false,"child":id,"spawn":spawn}
