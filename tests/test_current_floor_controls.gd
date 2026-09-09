extends "res://tests/test_current_floor_phases.gd"
var cases:Array=[]

func _run_composed()->void:
	var data:Dictionary=audit.decoded.duplicate(true)
	check(bool(LifeJourneyState.validate(data.journeys,data).ok),"Actual held v3 data passes the complete current journey validator.")
	check(typeof(data.journeys.members[DONOR].motion.courtesy.version)==TYPE_FLOAT and data.journeys.members[DONOR].motion.courtesy.version==3.0,"Actual JSON-decoded floating version3 is accepted without typed membership.")
	for version:float in [1.0,2.0]:
		var legacy_fact:Dictionary=data.duplicate(true);var fact:Dictionary=legacy_fact.journeys.members[DONOR].motion.courtesy
		fact.version=version;fact.erase("donor_kind")
		if version==1.0:fact.erase("beneficiary_kind")
		else:fact.beneficiary_kind="action"
		var boundary:Dictionary=LifeJourneyState.validate(legacy_fact.journeys,legacy_fact)
		cases.append({"case":"legacy numeric version "+str(version),"result":boundary})
		check(not bool(boundary.ok) and str(boundary.error)=="Courtesy movement conflicts with a protected journey.","Floating legacy version passes its exact schema while retaining old route restrictions: "+str(version))
	var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/original_slot.json")).data
	check(bool(LifeJourneyState.validate(original.journeys,original).ok),"Original genuine v2 journey remains readable with absent courtesy.")
	var legacy:Dictionary=original.duplicate(true);legacy.journeys.version=1
	check(bool(LifeJourneyState.validate(legacy.journeys,legacy).ok),"Legacy v1 absent-courtesy journey retains its existing compatibility.")
	for item:Array in [["version",0],["version",4],["version","3"],["version",true],["version",null],["version",[]],["version",{}],["version",NAN],["version",INF],["version",3.5],["donor_kind","action"],["beneficiary_kind","walk"],["phase","waiting"],["expires_at",float(data.day-1)*1440.0+float(data.minutes)],["beneficiary_identity",1]]:
		var changed:Dictionary=data.duplicate(true);changed.journeys.members[DONOR].motion.courtesy[item[0]]=item[1]
		_reject(changed,"Invalid typed courtesy "+str(item[0])+"="+str(item[1]))
	for field:String in ["donor_kind","beneficiary_kind"]:
		for value:Variant in [7,true,null,[],{}]:
			var invalid:Dictionary=data.duplicate(true);invalid.journeys.members[DONOR].motion.courtesy[field]=value
			_reject(invalid,"Non-string "+field+" type"+str(typeof(value)))
	var changed:Dictionary=data.duplicate(true);changed.journeys.members[DONOR].motion.courtesy.extra=true;_reject(changed,"Unknown v3 field")
	changed=data.duplicate(true);changed.journeys.members[DONOR].motion.courtesy.erase("donor_kind");_reject(changed,"Missing donor kind")
	changed=data.duplicate(true);changed.journeys.members[DONOR].motion.wait=[];_reject(changed,"Pending donor without its chosen stair wait")
	changed=data.duplicate(true);changed.journeys.members[DONOR].motion.ticket=1;_reject(changed,"Donor with actual stair ticket")
	changed=data.duplicate(true);_member(changed,DONOR).state.action_queue[0].paid=true;_reject(changed,"Paid donor")
	changed=data.duplicate(true);_member(changed,PEER).state.action_queue[0].cooperation_id="component-cooperation";_reject(changed,"Cooperative resource-return peer")
	changed=data.duplicate(true);_member(changed,PEER).state.character.world_state.resource_wait_started=-1.0;_reject(changed,"Peer without actual FIFO age")
	changed=data.duplicate(true);_member(changed,PEER).state.character.world_state.resource_action_active=true;_reject(changed,"Resuming active resource owner")
	changed=data.duplicate(true);changed.meals.batches[0].owner=DONOR;_reject(changed,"Declared carried-food donor ownership")
	changed=data.duplicate(true)
	_member(changed,PEER).state.action_queue[0].target_id="absent-furnishing"
	_member(changed,PEER).state.character.world_state.waiting_target_id="absent-furnishing"
	changed.journeys.members[PEER].motion.intent.target_id="absent-furnishing"
	_reject(changed,"Missing actual furnishing with internally matched action identity")
	await _third_member_reconstruct(data)
	await _earlier_waiter(data)
	audit["controls"]=cases

func _member(data:Dictionary,id:String)->Dictionary:
	for member:Dictionary in data.members:
		if str(member.id)==id:return member
	return {}

func _reject(data:Dictionary,label_text:String)->void:
	var result:Dictionary=LifeJourneyState.validate(data.journeys,data)
	cases.append({"case":label_text,"ok":result.ok,"error":result.get("error","")})
	check(not bool(result.ok) and not str(result.get("error","")).is_empty(),label_text+" is explicitly rejected.")

func _third_member_reconstruct(original:Dictionary)->void:
	# Declared component: omit only Ellis's derived approach motion. Its actual
	# saved body, complete snack queue and every other saved fact remain exact.
	var data:Dictionary=original.duplicate(true);var other:String="housemate_1"
	check(str(_member(data,other).state.action_queue[0].phase)=="approach" and not data.journeys.members[other].motion.is_empty(),"The real third member supplies an existing ordinary approach to reconstruct.")
	data.journeys.members[other].motion={}
	var before:Dictionary=_facts();var prepared:Dictionary=app._prepare_loaded_world(data)
	cases.append({"case":"third member empty motion","result":{"ok":prepared.ok,"error":prepared.get("error","")}})
	check(bool(prepared.ok),"Prepared load reconstructs an unrelated missing approach without dropping the staged saved hold.")
	if bool(prepared.ok):
		var candidate:Node=prepared.candidate
		var saved:Dictionary=original.journeys.members[DONOR].motion.courtesy.duplicate(true);saved.anchor=LifeJourneyState.vector(saved.anchor)
		check(candidate.traversal.courtesy.owner(candidate.traversal)==DONOR and candidate.traversal.courtesy.staged_current_floor.is_empty() and _same(candidate.traversal.routes[DONOR].courtesy,saved),"The exact expected donor, peer, hold and deadline survive third-member request/reconcile.")
		check(int(candidate.traversal.routes[DONOR].identity)==219 and int(candidate.traversal.routes[PEER].identity)==218 and int(candidate.traversal.routes[other].identity)==int(original.journeys.next_identity) and candidate.traversal.next_identity==int(original.journeys.next_identity)+1,"Only the unrelated missing route receives one fresh unique identity.")
		check(candidate.motion_states[PEER].waiting and candidate.motion_states[PEER].wait_started==float(_member(original,PEER).state.character.world_state.resource_wait_started) and candidate.world.actors[other].position==LifeJourneyState.vector(original.journeys.members[other].position),"FIFO age and all affected actual body positions remain saved facts.")
		cases[-1]["routes"]=candidate.traversal.snapshot();cases[-1]["peer_wait"]=candidate.motion_states[PEER].wait_started
		prepared.viewport.free();candidate.free();await frames(2)
	check(before==_facts(),"The staged third-member control leaves the active household entirely unchanged.")

func _earlier_waiter(original:Dictionary)->void:
	# Declared ownership negative, not a naturally produced second queue. Keep
	# all bodies, but give Ellis an earlier matching furnishing-return instruction.
	var data:Dictionary=original.duplicate(true);var other:String="housemate_1";var peer:Dictionary=_member(data,PEER).state
	var state:Dictionary=_member(data,other).state
	state.action_queue=[peer.action_queue[0].duplicate(true)]
	state.character.world_state.resource_wait_started=float(peer.character.world_state.resource_wait_started)-1.0
	state.character.world_state.resource_action_active=false
	state.character.world_state.waiting_action_id=peer.character.world_state.waiting_action_id
	state.character.world_state.waiting_target_id=peer.character.world_state.waiting_target_id
	# Arrived ownership reserves the same actual body, leaving the furnishing
	# corridor geometrically open so the live FIFO provider is the deciding gate.
	data.journeys.members[other].motion={}
	check(bool(LifeJourneyState.validate(data.journeys,data).ok),"Earlier-waiter component retains valid structural journey geometry before live resource validation.")
	var before:Dictionary=_facts();var prepared:Dictionary=app._prepare_loaded_world(data)
	cases.append({"case":"earlier matching FIFO owner","result":{"ok":prepared.ok,"error":prepared.get("error","")}})
	check(not bool(prepared.ok) and str(prepared.get("error","")).contains("available furnishing return"),"Prepared load refuses the unavailable saved resource-return owner before adoption.")
	if bool(prepared.ok):prepared.viewport.free();prepared.candidate.free()
	await frames(2)
	check(before==_facts(),"Failed resource validation leaves the active household entirely unchanged.")
