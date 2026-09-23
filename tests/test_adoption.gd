extends SceneTree
## Controlled model/save transactions. No claims of rendered arrival or UI use.
var checks:int=0
var failures:Array[String]=[]
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",label)
	if not value:failures.append(label);push_error(label)
func fixture(count:int=3,date:int=6) -> LifeHousehold:
	var household:=LifeHousehold.new();root.add_child(household)
	var profiles:Array=[]
	for index:int in range(count):profiles.append({"name":"Existing %d" % index,"age_stage":"adult" if index<2 else "child","traits":["Creative"]})
	household.new_household(profiles)
	if count>=3:check(bool(household.configure_family([{"a":"player","b":"housemate_2","role":"parent"}]).ok),"Fixture declares its existing parent-child relationship before play.")
	household.day=date;household.minutes=1100
	for member:Dictionary in household.members:
		var person:LifeSim=member.sim;person.day=date;person.minutes=1100
		person.education=LifeEducation.fresh(str(person.character.age_stage),date)
		person.career.schedule=LifeCareerSchedule.fresh(date);person._story_generated_day=date
		person.set_aging("long",false);person.autonomy=false
	household.set_funds(2500);household.set_speed(0)
	return household
func state(household:LifeHousehold) -> Dictionary:return JSON.parse_string(JSON.stringify(household.json_safe(household.get_state())))
func positive(saved:Dictionary,label:String) -> void:
	var clone:=LifeHousehold.new();var result:Dictionary=clone.restore_state(saved)
	print("RESTORE ",label," ",JSON.stringify(result));check(bool(result.ok),label);clone.free()
func reject(saved:Dictionary,label:String) -> void:
	var clone:LifeHousehold=fixture(1);var before:Dictionary=state(clone)
	var result:Dictionary=clone.restore_state(saved)
	check(not bool(result.ok),label+" rejects")
	check(state(clone)==before,label+" leaves the current household intact");clone.free()
func apply(household:LifeHousehold,request:Dictionary) -> Dictionary:
	return household.commit_adoption(request,Vector3(0,.16,8.5),Vector3(0,.16,6.5),[])
func _main_case() -> void:
	var household:LifeHousehold=fixture()
	var old:LifeSim=household.selected();old.speed=1
	check(old.queue_action("cook","stove_test",Vector3.ZERO),"Controlled existing cook can be queued.")
	household.begin_action("player");household.tick(1.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(old.queue_action("read","shelf_test",Vector3.ONE),"A later explicit read is retained in the fixture.")
	household.set_speed(0)
	var paid:Dictionary=old.action_queue[0];var later:Dictionary=old.action_queue[1]
	var live_before:Dictionary=household.get_state()
	var old_snapshot:Dictionary=state(household);positive(old_snapshot,"Played positive control is save-valid before adoption.")
	var prepared:Dictionary=household.prepare_adoption(["player","housemate_1"],0)
	check(bool(prepared.ok),"Two adult guardians can review adoption.")
	check(state(household)==old_snapshot,"Preparing the review charges nothing and changes no saved state.")
	var result:Dictionary=apply(household,prepared.request);print("ADOPT ",JSON.stringify(result))
	check(bool(result.ok),"The complete proposed household passes validation before append.")
	if not bool(result.ok):household.free();return
	var id:String=str(result.child);var child:LifeSim=household.member_sim(id)
	check(household.members.size()==4 and id=="housemate_3","Append respects the existing canonical member identities.")
	check(household.selected()==old and household.selected_index==0,"Selection and the played LifeSim instance are unchanged.")
	check(is_same(old.action_queue[0],paid) and is_same(old.action_queue[1],later) and bool(paid.paid) and float(paid.elapsed)>0,"Paid partial activity and exact later dictionary survive the transaction.")
	check(household.funds==int(old_snapshot.funds)-LifeAdoption.FEE and household.members.all(func(member:Dictionary)->bool:return member.sim.funds==household.funds),"The shared wallet pays the original fee exactly once.")
	for index:int in range(3):
		var before:Dictionary=live_before.members[index].state;var current:Dictionary=household.members[index].sim.get_state()
		for other:String in before.relationships:check(current.relationships[other]==before.relationships[other],"Existing relationship history preserved %d/%s." % [index,other])
		for field:String in ["needs","skills","education","career","lifecycle","social_history","wants"]:check(current[field]==before[field],"Existing %s preserved for %d." % [field,index])
	check(household.family_relationship("player",id)=="child" and household.family_relationship(id,"housemate_1")=="parent" and household.family_relationship(id,"housemate_2")=="siblings","Parent and sibling kinship derive from canonical links.")
	check(not bool(child.get_action_availability("flirt","player").available),"The adopted child's close-family romance is unavailable.")
	check(int(child.education.enrolled_day)==6 and int(child.education.first_class_day)==7 and int(child.education.missed)==0 and int(child.education.attended)==0 and int(child.career.schedule.last_day)==6,"New child has current calendars, school tomorrow and no invented history.")
	check(child.lifecycle.lifespan=="long" and not bool(child.lifecycle.auto_age) and str(child.character.age_stage)=="child","The child's stage and inherited aging preference are coherent.")
	check(child.needs=={"hunger":76.0,"energy":85.0,"hygiene":86.0,"bladder":78.0,"fun":62.0,"social":58.0},"The child receives the normal initial needs, without fabricated recovery.")
	check(str(child.get_current_action().id)=="arrive_home" and not bool(child.get_current_action().paid),"Only an unpaid arrival route is pending after membership is committed.")
	# The household enables Wants and Fears for every Lifelet it holds, and an
	# adopted child is built directly rather than through add_member. Without the
	# same flag here the child started with no whims at all and could never earn
	# one, so their Wishes panel stayed permanently empty.
	check(child.get_whims().size()==3 and bool(child.whims.get("enabled",false)),"The adopted child has the household's three active whims.")
	var adopted:Dictionary=state(household);positive(adopted,"JSON roundtrip preserves the partial paid queue and new unpaid arrival.")
	var repeated:Dictionary=apply(household,prepared.request)
	check(bool(repeated.ok) and bool(repeated.duplicate) and state(household)==adopted,"Repeated confirmation returns the same child and changes nothing.")
	var clone:=LifeHousehold.new();clone.restore_state(adopted)
	var clone_before:Dictionary=state(clone)
	check(bool(apply(clone,prepared.request).get("duplicate",false)) and state(clone)==clone_before,"Duplicate defense persists after JSON restoration.")
	clone.free()
	var partial:Dictionary=child.get_current_action()
	check(child.complete_adoption_arrival(partial) and not child.complete_adoption_arrival(partial),"Physical arrival completion can be acknowledged exactly once.")
	check(household.funds==int(adopted.funds) and household.members.size()==4,"Arrival completion has no membership or financial side effects.")
	positive(state(household),"Completed adoption remains save-valid without an arrival action.")
	var variants:Array=[]
	var bad:Dictionary=adopted.duplicate(true);bad.adoptions.events[0].fee="1000";variants.append([bad,"String adoption fee"])
	bad=adopted.duplicate(true);bad.adoptions.events[0].fee=false;variants.append([bad,"Boolean adoption fee"])
	bad=adopted.duplicate(true);bad.adoptions.events[0].guardians=["player","player"];variants.append([bad,"Repeated guardian"])
	bad=adopted.duplicate(true);bad.adoptions.events[0].guardians=["housemate_2"];variants.append([bad,"Minor guardian"])
	bad=adopted.duplicate(true);bad.adoptions.events[0].guardians=["maya"];variants.append([bad,"Outside-household guardian"])
	bad=adopted.duplicate(true);bad.adoptions.events[0].minutes=float(adopted.minutes)+1;variants.append([bad,"Future adoption"])
	bad=adopted.duplicate(true);bad.adoptions.events.append(bad.adoptions.events[0].duplicate(true));bad.adoptions.next_serial=3;variants.append([bad,"Duplicate event identity"])
	bad=adopted.duplicate(true);bad.members[3].state.action_queue[0].adoption_serial="1";variants.append([bad,"String arrival serial"])
	bad=adopted.duplicate(true);bad.members[3].state.action_queue[0].paid=true;variants.append([bad,"Paid arrival"])
	bad=adopted.duplicate(true);bad.members[3].state.action_queue[0].elapsed=.5;variants.append([bad,"Fabricated arrival progress"])
	bad=adopted.duplicate(true);bad.members[0].state.action_queue=[bad.members[3].state.action_queue[0].duplicate(true)];bad.members[3].state.action_queue=[];variants.append([bad,"Other member's arrival"])
	for metadata:Variant in [{},[],false,"1",1]:
		bad=adopted.duplicate(true);bad.members[0].state.action_queue[1].adoption_serial=metadata;variants.append([bad,"Adoption metadata on an unrelated read: "+str(metadata)])
	bad=adopted.duplicate(true);bad.erase("family_graph")
	for entry:Dictionary in bad.members:
		for relation:Dictionary in entry.state.relationships.values():relation.family_role="none";relation.status="Housemate"
	variants.append([bad,"Adoption history without an explicit family graph"])
	for variant:Array in variants:reject(variant[0],variant[1])
	var saved:Dictionary=old_snapshot.duplicate(true);saved.erase("adoptions");positive(saved,"Legacy households without adoption history still restore.")
	household.free()
func _boundaries() -> void:
	for count:int in [7,8]:
		var household:LifeHousehold=fixture(count)
		var prepared:Dictionary=household.prepare_adoption(["player"],1)
		check(bool(prepared.ok)==(count==7),"Capacity %d is handled before confirmation." % count)
		if count==7:check(bool(apply(household,prepared.request).ok) and household.members.size()==8,"The eighth household place is available through one confirmation.")
		household.free()
	for funds:int in [999,1000]:
		var household:LifeHousehold=fixture(1);household.set_funds(funds)
		var prepared:Dictionary=household.prepare_adoption(["player"],2)
		check(bool(prepared.ok)==(funds==1000),"Affordability boundary ℒ%d is exact." % funds)
		if funds==1000:check(bool(apply(household,prepared.request).ok) and household.funds==0,"Exactly ℒ1,000 supports one adoption without negative funds.")
		household.free()
	var household:LifeHousehold=fixture(1)
	var prepared:Dictionary=household.prepare_adoption(["player"],0);household.set_funds(999)
	var before:Dictionary=state(household)
	check(not bool(apply(household,prepared.request).ok) and state(household)==before,"Spending after preview rejects before any family or wallet mutation.")
	household.set_funds(2500);household.selected().character.age_stage="teen";household.selected().character.life_stage="minor"
	check(not bool(apply(household,prepared.request).ok),"A guardian becoming ineligible before confirmation is rechecked.")
	household.free()
	household=fixture(1)
	check(bool(household.buy_insurance("home").ok),"The fixture household takes out home insurance.")
	prepared=household.prepare_adoption(["player"],0)
	var insured:Dictionary=apply(household,prepared.request)
	check(bool(insured.ok),"An insured household can adopt: %s" % str(insured.get("error","")))
	if bool(insured.ok):
		check(str(household.member_sim(str(insured.child)).insurance_policy_id)=="home","The adopted child shares the household's insurance.")
		positive(state(household),"An insured household with an adopted child saves.")
	household.free()
	for date:int in [5,6,100]:
		household=fixture(1,date);prepared=household.prepare_adoption(["player"],0)
		check(bool(apply(household,prepared.request).ok),"Late/day-%d entry validates without retroactive absences." % date)
		var child:LifeSim=household.members[-1].sim
		check(int(child.education.first_class_day)==date+1 and int(child.education.last_day)==date and int(child.career.schedule.last_day)==date,"Every new calendar starts on the actual entry day %d." % date)
		child.cancel_action();check(child.action_queue.is_empty() and household.members.size()==2 and household.adoptions.events.size()==1,"Canceling arrival keeps the confirmed family on day %d." % date)
		positive(state(household),"Canceled arrival saves on day %d." % date)
		household.free()
func _run() -> void:
	_main_case();_boundaries()
	var legacy:LifeHousehold=fixture(1);var old_idle:Dictionary=state(legacy);legacy.free()
	old_idle.erase("adoptions");old_idle.members[0].state.erase("action_queue")
	positive(old_idle,"A legacy idle household may omit its optional empty action queue.")
	for invalid_queue:Variant in [null,{},"empty",false]:
		var bad:Dictionary=old_idle.duplicate(true);bad.members[0].state.action_queue=invalid_queue
		reject(bad,"Non-array legacy action queue: "+str(invalid_queue))
	var report:Dictionary={"checks":checks,"failures":failures,"method":"Controlled model/JSON transaction tests; public arrival and fresh-process UI are separate gates."}
	var file:=FileAccess.open("user://adoption_result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("ADOPTION_RESULT ",JSON.stringify(report));await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
