extends SceneTree
## Make Baby with an Elder partner, headless through the public paths.
##
## A Young Adult or Adult woman may try for a baby with an Elder man, and either
## partner may start it from the bed. An Elder woman cannot carry, so every pair
## whose woman is an Elder is refused with a plain reason. The pregnancy that
## follows keeps the Elder father through a save and a load and through the
## birth, an Elder's grey hair is never handed to the newborn, and a mother who
## ages into an Elder during the term (or in the middle of the beat) is still
## handled.

var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _initialize()->void:_run.call_deferred()

func _find(app:Node,kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}

func _home()->Node:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	return app

func _rename(household:Node,index:int,value:String)->void:
	household.members[index].sim.character.name=value
	for i:int in range(household.members.size()):
		if i==index:continue
		household.members[i].sim.relationships[str(household.members[index].id)].name=value
		household.members[index].sim.relationships[str(household.members[i].id)].name=str(household.members[i].sim.character.name)

## Move a Lifelet to another life stage the way a birthday does: the school record
## follows the stage, or the household would not be a valid save.
func _stage(sim:LifeSim,stage:String)->void:
	sim.character["age_stage"]=stage
	sim.character["life_stage"]=LifeLifecycle.eligibility(stage)
	sim.education["stage"]=stage

## Ada (female) and Ben (male) are partners and Cass is a third housemate. The
## stages are set before the models spawn, so an Elder really lies down as an Elder.
func _setup(app:Node,stages:Array)->void:
	app.selected_lot=0;app.start_household()
	var household=app.household
	while household.members.size()<3:household.add_member({"name":"Extra","age_stage":"adult","gender":"Male"})
	var names=["Ada","Ben","Cass"]
	for i:int in range(3):
		var sim=household.members[i].sim
		sim.autonomy=false
		_rename(household,i,names[i])
		_stage(sim,str(stages[i]))
		sim.needs.energy=85.0
		sim.needs.bladder=10.0
		sim.needs.hunger=10.0
		if not app.world.actors.has(str(household.members[i].id)):
			app.spawn_actor(str(household.members[i].id),sim.character.duplicate(true),Vector3(6.5,.16,6.5))
	var ids:Array[String]=[str(household.members[0].id),str(household.members[1].id),str(household.members[2].id)]
	household.members[0].sim.character.gender="female"
	household.members[1].sim.character.gender="male"
	household.members[2].sim.character.gender="female"
	household.members[0].sim.character.frame=0
	household.members[1].sim.character.frame=1
	household.members[2].sim.character.frame=0
	household.members[0].sim.romantic_partner=ids[1]
	household.members[1].sim.romantic_partner=ids[0]
	for pair:Array in [[0,1],[1,0]]:
		var relationship:Dictionary=household.members[pair[0]].sim.relationships[ids[pair[1]]]
		relationship["bond"]="partners"
		relationship["family_role"]="none"
		relationship["status"]=LifeFamilyGraph.label("none")

func _sleep(app:Node,bed:Dictionary,index:int)->void:
	app.select_household_member(index)
	app.queue_interaction({"id":str(bed.id),"kind":str(bed.kind),"node":bed.node,"size":bed.size},"sleep")

func _admit(app:Node,bed:Dictionary)->void:
	for i:int in range(10):await process_frame
	for member:Dictionary in app.household.members:
		if member.sim.get_current_action().is_empty():continue
		app._member_action_started(str(member.id),member.sim.get_current_action())
		app._bind_member(str(member.id))
		app.player.position=Vector3(member.sim.get_current_action().target_position)
		app._advance_movement(0.016)
		app.household.begin_action(str(member.id))

func _admit_beat(app:Node)->void:
	for i:int in range(6):await process_frame
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if str(action.get("id",""))!=LifeBabyPlan.ACTION_ID:continue
		app._bind_member(str(member.id))
		app.player.position=Vector3(action.target_position)
		app._advance_movement(0.016)
		app.household.begin_action(str(member.id))

func _offer(sim:LifeSim,bed:Dictionary)->Dictionary:
	for entry:Dictionary in sim.get_actions_for("bed",str(bed.id)):
		if str(entry.id)==LifeBabyPlan.ACTION_ID:return entry
	return {}

func _roundtrip(household:Node,app:Node)->Dictionary:
	return JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(household.get_state(app.world.serialize_items()))))

func _run()->void:
	_hair_cases()
	await _offer_cases()
	await _refusal_cases()
	await _initiator_case()
	await _conception_case()
	await _mid_beat_cases()
	print("MAKE_BABY_ELDER %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

## The roll leans on the parents, but an Elder's grey is age and not heredity.
func _hair_cases()->void:
	var greys:Array[String]=LifeCharacterIdentity.ELDER_HAIR_COLORS
	var mother:Dictionary={"name":"Ada Vale","age_stage":"adult","gender":"female","hair_color":"54382a","skin_color":"d9a17d","eye_color":"55738f","top_color":"417a71","bottom_color":"3e5955","aspiration":"Maker"}
	var elder:Dictionary={"name":"Ben Vale","age_stage":"elder","gender":"male","hair_color":"d9d6cd","skin_color":"b77e58","eye_color":"704b36","top_color":"7195b3","bottom_color":"292f32","aspiration":"Successful"}
	var adult_twin:Dictionary=elder.duplicate(true)
	adult_twin.age_stage="adult"
	var grey_babies:int=0
	var mother_hair:int=0
	var held_back:int=0
	var identical:bool=true
	var valid:bool=true
	for serial:int in range(1,41):
		var baby:Dictionary=LifeBabyPlan.roll(mother,elder,serial)
		var twin:Dictionary=LifeBabyPlan.roll(mother,adult_twin,serial)
		if str(baby.hair_color) in greys:grey_babies+=1
		if str(baby.hair_color)==str(mother.hair_color):mother_hair+=1
		valid=valid and LifeBabyPlan.profile_error(baby).is_empty()
		# The twin is the same father with the same draws as an adult. They differ only
		# where the adult would have passed the grey on; every other baby is identical.
		if str(twin.hair_color)==str(elder.hair_color):
			held_back+=1
		elif JSON.stringify(baby,"",true)!=JSON.stringify(twin,"",true):
			identical=false
	check(grey_babies==0,"An Elder father's grey hair is never rolled for the baby (%d of 40)." % grey_babies)
	check(mother_hair>0,"The mother's hair colour is still inherited (%d of 40)." % mother_hair)
	check(valid,"Every baby rolled with an Elder father is a valid newborn profile.")
	check(held_back>0 and identical,"The grey is held back only where an adult father would have passed it on (%d of 40); every other baby is identical." % held_back)
	var brown:Dictionary=elder.duplicate(true)
	brown.hair_color="684632"
	var from_father:int=0
	for serial:int in range(1,41):
		if str(LifeBabyPlan.roll(mother,brown,serial).hair_color)=="684632":from_father+=1
	check(from_father>0,"An Elder who kept a natural hair colour can still pass it on (%d of 40)." % from_father)
	check(not LifeBabyPlan.can_carry(elder) and LifeBabyPlan.can_carry(mother) and LifeBabyPlan.can_carry({"age_stage":"young_adult"}) and not LifeBabyPlan.can_carry({"age_stage":"teen"}),"Only a Young Adult or Adult can carry a baby.")

func _offer_cases()->void:
	for woman:String in ["young_adult","adult"]:
		var label:String=LifeLifecycle.with_article(woman)
		var app=_home()
		await process_frame
		await process_frame
		_setup(app,[woman,"elder","adult"])
		var household=app.household
		var bed:Dictionary=_find(app,"bed")
		var ada=household.members[0].sim
		var ben=household.members[1].sim
		var ids:Array[String]=[str(household.members[0].id),str(household.members[1].id)]
		var woman_offer:Dictionary=_offer(ada,bed)
		check(not woman_offer.is_empty() and bool(woman_offer.available),"%s woman is offered Make Baby by a bed with her Elder partner (%s)." % [label.capitalize(),str(woman_offer.get("reason",""))])
		var elder_offer:Dictionary=_offer(ben,bed)
		check(not elder_offer.is_empty() and bool(elder_offer.available),"The Elder man is offered Make Baby by the same bed (%s)." % str(elder_offer.get("reason","")))
		for starter:int in [0,1]:
			var plan:Dictionary=household.try_for_baby_plan(ids[starter],str(bed.id))
			check(bool(plan.ok),"The household plan accepts the %s as initiator: %s." % ["woman" if starter==0 else "Elder man",str(plan.get("error",""))])
			if bool(plan.ok):
				check(str(plan.request.mother_id)==ids[0] and str(plan.request.father_id)==ids[1] and str(plan.request.a_id)==ids[0],"Whoever starts it, the woman is the mother and the Elder man is the father.")
		app.queue_free();await process_frame

func _refusal_cases()->void:
	for scenario:String in ["elder_woman","elder_pair","spirit_elder","teen_partner","teen_initiator"]:
		var app=_home()
		await process_frame
		await process_frame
		var stages:Array=["adult","elder","adult"]
		match scenario:
			"elder_woman":stages=["elder","adult","adult"]
			"elder_pair":stages=["elder","elder","adult"]
			"teen_partner":stages=["adult","teen","adult"]
			"teen_initiator":stages=["teen","elder","adult"]
		_setup(app,stages)
		var household=app.household
		if scenario=="spirit_elder":household.members[1].sim.character["life_status"]="passed"
		var ids:Array[String]=[str(household.members[0].id),str(household.members[1].id)]
		var bed:Dictionary=_find(app,"bed")
		for starter:int in [0,1]:
			var sim=household.members[starter].sim
			var offered:Dictionary=sim.get_action_availability(LifeBabyPlan.ACTION_ID,str(bed.id))
			var plan:Dictionary=household.try_for_baby_plan(ids[starter],str(bed.id))
			var reason:String=str(plan.get("error",""))
			check(not bool(offered.available) and not bool(plan.ok) and not reason.is_empty(),"%s: the %s is refused with a reason (%s)." % [scenario,"woman" if starter==0 else "man",reason])
			match scenario:
				"elder_woman","elder_pair":check(reason.contains("cannot carry") and reason.contains("Young Adult or Adult"),"%s: the reason says an Elder cannot carry and who can." % scenario)
				"spirit_elder":check(reason.contains("living"),"A Lifelet who has passed on cannot be either partner: %s." % reason)
				"teen_partner","teen_initiator":check(reason.contains("grown-up") or reason.contains("Young Adult, Adult or Elder"),"%s: a teen is still refused as a parent: %s." % [scenario,reason])
		app.queue_free();await process_frame

## The Elder man starts it from his own bed menu: the woman still carries.
func _initiator_case()->void:
	var app=_home()
	await process_frame
	await process_frame
	_setup(app,["adult","elder","adult"])
	var household=app.household
	var bed:Dictionary=_find(app,"bed")
	_sleep(app,bed,0)
	_sleep(app,bed,1)
	await _admit(app,bed)
	var ada=household.members[0].sim
	var ben=household.members[1].sim
	check(str(ada.get_current_action().get("id",""))=="sleep" and str(ben.get_current_action().get("id",""))=="sleep","The woman and her Elder partner sleep in one bed first.")
	app.select_household_member(1)
	app.try_for_baby(bed)
	check(household.cooperations.size()==1,"The Elder man choosing Make Baby from the bed starts exactly one beat.")
	if household.cooperations.is_empty():
		app.queue_free();await process_frame
		return
	var session:Dictionary=household.cooperations[0]
	check(str(session.mother_id)==str(household.members[0].id) and str(session.father_id)==str(household.members[1].id),"The beat names the woman as mother and the Elder man as father.")
	for i:int in range(3):await process_frame
	check(str(ada.get_current_action().get("id",""))==LifeBabyPlan.ACTION_ID and str(ben.get_current_action().get("id",""))==LifeBabyPlan.ACTION_ID,"Both partners carry the beat.")
	check(str(ada.action_queue[1].get("id",""))=="sleep" and str(ben.action_queue[1].get("id",""))=="sleep","Their interrupted sleep waits behind the beat.")
	ben.cancel_action()
	for i:int in range(3):await process_frame
	check(household.cooperations.is_empty() and str(ada.get_current_action().get("id",""))=="sleep" and str(ben.get_current_action().get("id",""))=="sleep","The Elder man can stop it, and both go back to sleep.")
	app.queue_free();await process_frame

## A Young Adult mother and an Elder father: the whole beat, the pregnancy, a
## save in the middle of it, the birth and the baby's family links.
func _conception_case()->void:
	var app=_home()
	await process_frame
	await process_frame
	_setup(app,["young_adult","elder","adult"])
	var household=app.household
	var ada_id:String=str(household.members[0].id)
	var ben_id:String=str(household.members[1].id)
	household.members[1].sim.character["hair_color"]="d9d6cd"
	var bed:Dictionary=_find(app,"bed")
	_sleep(app,bed,0)
	_sleep(app,bed,1)
	await _admit(app,bed)
	var started:Dictionary=household.begin_try_for_baby(ada_id,str(bed.id))
	check(bool(started.ok),"The woman starts Make Baby with her Elder partner: %s." % str(started.get("error","")))
	await _admit_beat(app)
	household.set_speed(1)
	household.tick((LifeBabyPlan.DURATION+1.0)/LifeSim.GAME_MINUTES_PER_SECOND)
	check(household.cooperations.is_empty() and bool(household.pregnancy.get("active",false)),"Finishing the beat begins a pregnancy.")
	check(str(household.pregnancy.get("mother_id",""))==ada_id and str(household.pregnancy.get("father_id",""))==ben_id,"The pregnancy records the woman as mother and the Elder man as father.")
	check(str(household.pregnancy.baby.hair_color) not in LifeCharacterIdentity.ELDER_HAIR_COLORS,"The baby already rolled does not carry the Elder's grey hair (%s)." % str(household.pregnancy.baby.hair_color))
	var state:Dictionary=household.get_state(app.world.serialize_items())
	check(bool(LifeSaveLibrary._validate_household(state).ok),"A household expecting a baby with an Elder father is a valid save.")
	var restored_home:=LifeHousehold.new()
	root.add_child(restored_home)
	var restored:Dictionary=restored_home.restore_state(_roundtrip(household,app))
	check(bool(restored.ok),"The save loads: %s." % str(restored.get("error","")))
	check(bool(restored_home.pregnancy.get("active",false)) and str(restored_home.pregnancy.mother_id)==ada_id and str(restored_home.pregnancy.father_id)==ben_id and str(restored_home.member_sim(ben_id).character.age_stage)=="elder","The loaded pregnancy keeps the Elder father.")
	restored_home.queue_free()
	# She conceived as an adult and may be an Elder herself by the birth: that save must keep loading.
	_stage(household.members[0].sim,"elder")
	check(bool(LifeSaveLibrary._validate_household(household.get_state(app.world.serialize_items())).ok),"A mother who ages into an Elder during the term keeps a valid pregnancy save.")
	_stage(household.members[0].sim,"young_adult")
	for member:Dictionary in household.members:
		member.sim.set_aging(str(member.sim.lifecycle.lifespan),false)
	var guard:int=0
	var hours:int=ceili(LifeBabyPlan.PREGNANCY_MINUTES/60.0)+24
	while bool(household.pregnancy.get("active",false)) and guard<hours:
		for member:Dictionary in household.members:
			for key:String in member.sim.needs:member.sim.needs[key]=80.0
		household.tick(60.0/LifeSim.GAME_MINUTES_PER_SECOND)
		guard+=1
	for i:int in range(8):await process_frame
	check(bool(household.pregnancy.get("pending",false)),"The countdown ends in a birth with the Elder father still a household member.")
	check(app.mode=="creator" and app.creator_purpose=="baby","The birth opens the baby creator.")
	check(str(app.profile.get("hair_color","")) not in LifeCharacterIdentity.ELDER_HAIR_COLORS and LifeBabyPlan.profile_error(app.profile).is_empty(),"The newborn offered to the player is valid and not grey-haired.")
	var members_before:int=household.members.size()
	app.confirm_baby_creator()
	await process_frame
	check(household.members.size()==members_before+1,"Welcoming the baby adds one Lifelet.")
	var baby_id:String=""
	for member:Dictionary in household.members:
		if str(member.sim.character.get("age_stage",""))=="baby":baby_id=str(member.id)
	var parents:Array=[]
	for edge:Dictionary in household.family_graph.parents:
		if str(edge.b)==baby_id:parents.append(str(edge.a))
	check(not baby_id.is_empty() and parents.has(ada_id) and parents.has(ben_id),"Both the woman and the Elder man are recorded as the baby's parents.")
	check(not baby_id.is_empty() and household.member_sim(baby_id).relationships.has(ben_id) and household.member_sim(ben_id).relationships.has(baby_id),"The Elder father and the baby have relationship rows both ways.")
	var after:Dictionary=LifeSaveLibrary._validate_household(household.get_state(app.world.serialize_items()))
	check(bool(after.ok),"The household with the new baby and its Elder father saves: %s." % str(after.get("error","")))
	app.queue_free();await process_frame

## A save taken in the middle of the beat keeps an Elder father, and refuses an
## Elder mother. A mother who ages into an Elder while it runs ends the beat.
func _mid_beat_cases()->void:
	var app=_home()
	await process_frame
	await process_frame
	_setup(app,["adult","elder","adult"])
	var household=app.household
	var ada_id:String=str(household.members[0].id)
	var bed:Dictionary=_find(app,"bed")
	_sleep(app,bed,0)
	_sleep(app,bed,1)
	await _admit(app,bed)
	var started:Dictionary=household.begin_try_for_baby(str(household.members[1].id),str(bed.id))
	check(bool(started.ok),"The Elder man starts the beat for the saved-session case: %s." % str(started.get("error","")))
	await _admit_beat(app)
	household.set_speed(1)
	household.tick(8.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(household.cooperations.size()==1 and str(household.cooperations[0].phase)=="active","The beat is under way.")
	var saved:Dictionary=_roundtrip(household,app)
	var fresh:=LifeHousehold.new()
	root.add_child(fresh)
	var loaded:Dictionary=fresh.restore_state(saved)
	check(bool(loaded.ok) and fresh.cooperations.size()==1,"A save in the middle of a beat with an Elder father loads: %s." % str(loaded.get("error","")))
	fresh.queue_free()
	var tampered:Dictionary=saved.duplicate(true)
	for entry:Dictionary in tampered.members:
		if str(entry.id)==ada_id:
			entry.state.character.age_stage="elder"
			entry.state.education.stage="elder"
	var rejected:=LifeHousehold.new()
	root.add_child(rejected)
	var refusal:Dictionary=rejected.restore_state(tampered)
	check(not bool(refusal.ok) and str(refusal.get("error","")).contains("mother"),"A saved beat whose mother is an Elder is refused: %s." % str(refusal.get("error","")))
	rejected.queue_free()
	# Live: she turns Elder in the middle of the moment.
	var session:Dictionary=household.cooperations[0]
	check(household._baby_session_error(session).is_empty(),"Before she ages up, the beat has no problem.")
	_stage(household.members[0].sim,"elder")
	check(household._baby_session_error(session).contains("mother-to-be"),"An Elder mother ends the beat: %s." % household._baby_session_error(session))
	household.before_member_notification()
	for i:int in range(3):await process_frame
	check(household.cooperations.is_empty() and not bool(household.pregnancy.get("active",false)),"The moment ends without a pregnancy when the mother is an Elder.")
	app.queue_free();await process_frame
