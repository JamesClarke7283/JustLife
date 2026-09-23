extends SceneTree
## "Try for Baby" and the baby creator, headless through the public paths.
##
## The pair's beat is a cooperative session: it is offered only for a male and
## a female adult partner asleep in one bed, refused for every other pair, runs
## a bounded beat whose clock belongs to one member, and on completion opens the
## ordinary creator seeded as the baby stage. Confirming adds the edited baby to
## the household, and a fresh save/load restores both the pending birth and the
## baby member.

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

## A fresh app whose starter household is three adults: two partners plus one
## outsider, so "same-gender / non-partner" cases have a real third Lifelet.
func _home()->Node:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	return app

func _ensure_actors(app:Node)->void:
	for member:Dictionary in app.household.members:
		if app.world.actors.has(str(member.id)):continue
		app.spawn_actor(str(member.id),member.sim.character.duplicate(true),Vector3(6.5,.16,6.5))

## Rename a member the way the game does: every housemate's relationship row
## carries the other Lifelet's name, so both directions follow the rename.
func _rename(household:Node,index:int,value:String)->void:
	household.members[index].sim.character.name=value
	for i:int in range(household.members.size()):
		if i==index:continue
		household.members[i].sim.relationships[str(household.members[index].id)].name=value
		household.members[index].sim.relationships[str(household.members[i].id)].name=str(household.members[i].sim.character.name)

func _setup(app:Node)->void:
	app.selected_lot=0;app.start_household()
	var household=app.household
	while household.members.size()<3:household.add_member({"name":"Extra","age_stage":"adult","gender":"Male"})
	var names=["Ada","Ben","Cass"]
	for i:int in range(3):
		var sim=household.members[i].sim
		sim.autonomy=false
		_rename(household,i,names[i])
		sim.character["life_stage"]="adult"
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
	# Partner status is declared both ways, exactly as the ask_partner action
	# writes it, so the household stays a valid save.
	for pair:Array in [[0,1],[1,0]]:
		var relationship:Dictionary=household.members[pair[0]].sim.relationships[ids[pair[1]]]
		relationship["bond"]="partners"
		relationship["family_role"]="none"
		relationship["status"]=LifeFamilyGraph.label("none")

func _sleep(app:Node,bed:Dictionary,index:int)->void:
	app.select_household_member(index)
	app.queue_interaction({"id":str(bed.id),"kind":str(bed.kind),"node":bed.node,"size":bed.size},"sleep")

func _admit(app:Node,bed:Dictionary)->void:
	# Approach the bed, then confirm the arrival so the action becomes active
	# and the pair is genuinely asleep in it.
	for i:int in range(10):await process_frame
	for member:Dictionary in app.household.members:
		if member.sim.get_current_action().is_empty():continue
		app._member_action_started(str(member.id),member.sim.get_current_action())
		app._bind_member(str(member.id))
		app.player.position=Vector3(member.sim.get_current_action().target_position)
		app._advance_movement(0.016)
		app.household.begin_action(str(member.id))

## Both partners reach the bed and the beat becomes active, as the ordinary
## arrival path does when each partner walks up and starts the shared action.
func _admit_beat(app:Node)->void:
	for i:int in range(6):await process_frame
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if str(action.get("id",""))!=LifeBabyPlan.ACTION_ID:continue
		app._bind_member(str(member.id))
		app.player.position=Vector3(action.target_position)
		app._advance_movement(0.016)
		app.household.begin_action(str(member.id))

func _run()->void:
	await _offer_cases()
	await _refusal_cases()
	await _beat_case()
	await _creator_case()
	await _persistence_case()
	print("MAKE_BABY %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _offer_cases()->void:
	var app=_home()
	await process_frame
	await process_frame
	_setup(app)
	var household=app.household
	var bed:Dictionary=_find(app,"bed")
	check(not bed.is_empty(),"The starter home has a bed.")
	_sleep(app,bed,0)
	_sleep(app,bed,1)
	await _admit(app,bed)
	var ada=household.members[0].sim
	var action:Dictionary=ada.get_current_action()
	check(str(action.get("id",""))=="sleep","The pair sleeps in the shared bed before the beat is offered.")
	var actions:Array=ada.get_actions_for("bed",str(bed.id))
	var offer:Dictionary={}
	for entry:Dictionary in actions:
		if str(entry.id)==LifeBabyPlan.ACTION_ID:offer=entry
	check(not offer.is_empty() and bool(offer.available),"Try for Baby is offered for a male+female adult partner pair asleep in one bed.")
	var plan:Dictionary=household.try_for_baby_plan(str(household.members[0].id),str(bed.id))
	check(bool(plan.ok),"The household's own plan accepts the sleeping pair.")
	check(str(plan.request.get("mother_id",""))==str(household.members[0].id) and str(plan.request.get("father_id",""))==str(household.members[1].id),"The female partner carries the baby and the male partner fathers it.")
	app.queue_free();await process_frame

func _refusal_cases()->void:
	for scenario:String in ["same_gender","non_partner","not_asleep","baby_present","household_full"]:
		var app=_home()
		await process_frame
		await process_frame
		_setup(app)
		var household=app.household
		var ids:Array[String]=[str(household.members[0].id),str(household.members[1].id),str(household.members[2].id)]
		var bed:Dictionary=_find(app,"bed")
		match scenario:
			"same_gender":household.members[0].sim.character.gender="male"
			"non_partner":
				household.members[0].sim.romantic_partner=""
				household.members[1].sim.romantic_partner=""
				for pair:Array in [[0,1],[1,0]]:
					var relationship:Dictionary=household.members[pair[0]].sim.relationships[ids[pair[1]]]
					relationship["bond"]="none"
					relationship["romance"]=0.0
			"not_asleep":pass
			"baby_present":
				household.add_member({"name":"Baby Vale","age_stage":"baby","life_stage":"minor","gender":"female"})
			"household_full":
				while household.members.size()<LifeHousehold.MAX_MEMBERS:household.add_member({"name":"Extra","age_stage":"adult","gender":"Male"})
		_ensure_actors(app)
		var first=household.members[0].sim
		if scenario!="not_asleep":
			_sleep(app,bed,0)
			_sleep(app,bed,1)
			await _admit(app,bed)
		var offered:Dictionary=first.get_action_availability(LifeBabyPlan.ACTION_ID,str(bed.id))
		check(not bool(offered.available),"Try for Baby is refused when %s: %s." % [scenario,str(offered.reason)])
		var plan:Dictionary=household.try_for_baby_plan(ids[0],str(bed.id))
		check(not bool(plan.ok) and not str(plan.get("error","")).is_empty(),"The household refuses %s with a notice: %s." % [scenario,str(plan.get("error",""))])
		app.queue_free();await process_frame

func _beat_case()->void:
	var app=_home()
	await process_frame
	await process_frame
	_setup(app)
	var household=app.household
	var bed:Dictionary=_find(app,"bed")
	_sleep(app,bed,0)
	_sleep(app,bed,1)
	await _admit(app,bed)
	var before_funds:int=household.funds
	# The bed menu's own button calls this public entry point.
	app.try_for_baby(bed)
	var started:Dictionary={"ok":not household.cooperations.is_empty(),"session_id":str(household.cooperations[0].id) if not household.cooperations.is_empty() else ""}
	check(bool(started.ok),"Choosing the bed's Try for Baby starts the beat.")
	check(is_instance_valid(app.cover_beat),"The beat presents its own cover overlay above the bed.")
	var covers_before:bool=is_instance_valid(app.cover_beat)
	for i:int in range(3):await process_frame
	var ada=household.members[0].sim
	var ben=household.members[1].sim
	var beat_a:Dictionary=ada.get_current_action()
	var beat_b:Dictionary=ben.get_current_action()
	check(str(beat_a.get("id",""))==LifeBabyPlan.ACTION_ID and str(beat_b.get("id",""))==LifeBabyPlan.ACTION_ID,"Both partners carry the beat.")
	check(str(beat_a.get("cooperation_id",""))==str(beat_b.get("cooperation_id","")),"The pair shares one beat token.")
	check(float(beat_a.get("duration",0.0))==LifeBabyPlan.DURATION and LifeBabyPlan.DURATION>=30.0 and LifeBabyPlan.DURATION<=45.0,"The beat is bounded to 30-45 real seconds at normal speed (%d s)." % int(LifeBabyPlan.DURATION))
	check(bool(beat_a.get("cooperation_primary",false))!=bool(beat_b.get("cooperation_primary",false)),"Exactly one partner owns the beat's clock.")
	check(str(ada.action_queue[1].get("id",""))=="sleep" and str(ben.action_queue[1].get("id",""))=="sleep","The interrupted sleep waits behind the beat for both partners.")
	check(household.funds==before_funds,"The beat charges nothing.")
	# Cancelling before completion releases both and returns them to their sleep.
	ada.cancel_action()
	for i:int in range(3):await process_frame
	check(covers_before and not is_instance_valid(app.cover_beat),"Cancelling the beat clears its cover overlay.")
	check(household.cooperations.is_empty() and str(ada.get_current_action().get("id",""))=="sleep" and str(ben.get_current_action().get("id",""))=="sleep","Cancelling the beat cleanly returns both partners to the sleep they interrupted.")
	# A completed beat conceives exactly once.
	await _admit(app,bed)
	var again:Dictionary=household.begin_try_for_baby(str(household.members[0].id),str(bed.id))
	check(bool(again.ok),"The pair can choose the beat again after cancelling.")
	check(household.cooperations.size()==1,"Starting the beat creates exactly one session.")
	check(float(ada.action_queue[0].get("elapsed",0.0))==0.0 and float(ben.action_queue[0].get("elapsed",0.0))==0.0,"The beat begins with both clocks at zero.")
	await _admit_beat(app)
	household.set_speed(1)
	# The owner's clock alone drives the beat to completion; the partner mirrors.
	household.tick((LifeBabyPlan.DURATION*.25)/LifeSim.GAME_MINUTES_PER_SECOND)
	check(is_equal_approx(float(ada.action_queue[0].get("elapsed",0.0)),float(ben.action_queue[0].get("elapsed",0.0))),"The pair's beat clocks stay together.")
	for i:int in range(4):household.tick((LifeBabyPlan.DURATION+1.0)/LifeSim.GAME_MINUTES_PER_SECOND)
	check(household.cooperations.is_empty() and ada.action_queue.size()==1,"Completing the beat clears the session and the beat action together.")
	# Sims-4 order: the beat conceives a pregnancy, and the birth
	# (when the countdown completes) is what produces the pending baby.
	check(bool(household.pregnancy.get("active",false)) and not bool(household.pregnancy.get("pending",false)),"The beat's completion begins a pregnancy rather than an instant birth.")
	check(LifeBabyPlan.days_remaining(household.pregnancy,household.day,household.minutes)==int(LifeBabyPlan.PREGNANCY_DAYS),"The pregnancy runs fourteen game days.")
	var expecting:LifeSim=household.members[0].sim
	var has_moodlet:bool=false
	for mood:Dictionary in expecting.moodlets:has_moodlet = has_moodlet or str(mood.get("label",""))=="Expecting"
	check(has_moodlet,"The expecting mother carries a visible Expecting moodlet with the countdown.")
	var blocked:Dictionary=household.try_for_baby_plan(str(household.members[0].id),str(bed.id))
	check(not bool(blocked.ok),"A household already expecting is refused another beat: %s." % str(blocked.error))
	var baby:Dictionary=household.pending_baby_profile()
	check(baby.is_empty(),"No baby exists before the birth.")
	# Advance the household clock through the countdown: the birth follows.
	household.set_speed(1)
	# The guard follows the real term (fourteen days since 2184c56), with a
	# day of slack; it used to be sized for the old three-day pregnancy.
	var guard:int=0
	var hours:int=ceili(LifeBabyPlan.PREGNANCY_MINUTES/60.0)+24
	while bool(household.pregnancy.get("active",false)) and guard<hours:
		household.tick(60.0/LifeSim.GAME_MINUTES_PER_SECOND)
		guard+=1
	check(not bool(household.pregnancy.get("active",false)) and bool(household.pregnancy.get("pending",false)),"Completing the countdown delivers the birth.")
	baby=household.pending_baby_profile()
	check(str(baby.get("age_stage",""))=="baby" and str(baby.get("life_stage",""))=="minor","The born baby is a minor baby profile.")
	check(LifeBabyPlan.profile_error(baby).is_empty(),"The rolled baby profile is valid for the creator: %s." % LifeBabyPlan.profile_error(baby))
	app.queue_free();await process_frame

func _creator_case()->void:
	var app=_home()
	await process_frame
	await process_frame
	_setup(app)
	var household=app.household
	var bed:Dictionary=_find(app,"bed")
	_sleep(app,bed,0)
	_sleep(app,bed,1)
	await _admit(app,bed)
	var started:Dictionary=household.begin_try_for_baby(str(household.members[0].id),str(bed.id))
	check(bool(started.ok),"The creator case starts its beat.")
	await _admit_beat(app)
	# The beat runs its bounded course, then the pregnancy countdown completes:
	# the birth event opens the creator, exactly as the Sims-4 flow ends.
	household.tick((LifeBabyPlan.DURATION+1.0)/LifeSim.GAME_MINUTES_PER_SECOND)
	household.set_speed(1)
	# The guard follows the real term (fourteen days since 2184c56), with a
	# day of slack; it used to be sized for the old three-day pregnancy.
	var guard:int=0
	var hours:int=ceili(LifeBabyPlan.PREGNANCY_MINUTES/60.0)+24
	while bool(household.pregnancy.get("active",false)) and guard<hours:
		household.tick(60.0/LifeSim.GAME_MINUTES_PER_SECOND)
		guard+=1
	for i:int in range(8):await process_frame
	check(bool(household.pregnancy.get("pending",false)),"The completed countdown leaves a pending birth for the creator.")
	var members_before:int=household.members.size()
	check(app.mode=="creator" and app.creator_purpose=="baby","The birth opens the ordinary creator for the baby.")
	check(app.creator_age_stages()==["baby"],"The baby creator offers the baby stage alone.")
	check(str(app.profile.get("age_stage",""))=="baby","The creator is seeded as the baby stage.")
	# Since 2184c56 the parents stay in the profile list (so cancelling cannot
	# strand the live bar); the creator edits only the appended newborn.
	check(app.household_profiles.size()==members_before+1 and app.creator_index==app.household_profiles.size()-1 and str(app.household_profiles[app.creator_index].get("age_stage",""))=="baby","The baby creator customises the single new Lifelet.")
	# Every clothing button the baby creator actually shows must be one the
	# newborn model has. The ordinary creator drew all five tops and both bottoms
	# for every stage, and the birth validator refuses clothing a baby's model
	# does not author, so pressing the offered Jacket or Shorts made "Welcome the
	# baby" refuse for good. The hairstyle row already filtered for this reason.
	app.set_creator_tab("Wardrobe")
	await process_frame
	var offered_clothing:Array[String]=[]
	for node:Node in app.find_children("*","Button",true,false):
		var clothing_button:Button=node
		if clothing_button.is_visible_in_tree() and clothing_button.text in ["Casual","Jacket","Cardigan","Tee","Hoodie","Trousers","Shorts"]:
			offered_clothing.append(str(clothing_button.text))
	check(offered_clothing==["Casual","Trousers"],"The baby creator offers only the garments the newborn model authors (got %s)." % str(offered_clothing))
	for label:String in offered_clothing:
		for node:Node in app.find_children("*","Button",true,false):
			var clothing_button:Button=node
			if clothing_button.is_visible_in_tree() and str(clothing_button.text)==label:
				clothing_button.pressed.emit();await process_frame;break
	check(LifeBabyPlan.profile_error(app.profile).is_empty(),"Pressing every offered clothing button leaves a newborn the game accepts: %s" % LifeBabyPlan.profile_error(app.profile))
	# The player edits name, gender, skin, hair, eyes and a face slider.
	app.profile.name="Wren Solis"
	app.profile.frame=0
	app.profile.gender="female"
	app.profile.skin_color="925c40"
	app.profile.hair=2
	app.profile.hair_color="dfccb0"
	app.profile.eye_color="55738f"
	app.profile.face_round=.42
	app.profile.aspiration="Balanced"
	app.confirm_baby_creator()
	await process_frame
	check(app.mode=="live","Confirming the baby creator returns to live play so the household clock can advance.")
	check(household.members.size()==members_before+1,"Confirming the creator adds one baby to the household.")
	var baby_id:String=""
	for member:Dictionary in household.members:
		if str(member.sim.character.get("age_stage",""))=="baby":baby_id=str(member.id)
	check(not baby_id.is_empty(),"The new member is a baby.")
	var baby=household.member_sim(baby_id)
	check(str(baby.character.name)=="Wren Solis" and int(baby.character.frame)==0 and str(baby.character.skin_color)=="925c40" and int(baby.character.hair)==2 and str(baby.character.hair_color)=="dfccb0" and str(baby.character.eye_color)=="55738f" and absf(float(baby.character.face_round)-.42)<.001,"The baby keeps every edit the player made.")
	check(not bool(baby.household_bills_enabled),"The baby carries no household bills.")
	# A born Lifelet is built directly rather than through add_member, so it needs
	# the household's Wants and Fears flag too; without it the newborn had no
	# whims at all and their Wishes panel stayed empty for life.
	check(baby.get_whims().size()==3 and bool(baby.whims.get("enabled",false)),"The newborn has the household's three active whims.")
	var parents:Array=[]
	for edge:Dictionary in household.family_graph.parents:
		if str(edge.b)==baby_id:parents.append(str(edge.a))
	check(parents.has(str(household.members[0].id)) and parents.has(str(household.members[1].id)),"Both parents are recorded in the family graph.")
	check(app.world.actors.has(baby_id),"The baby is placed at the home lot.")
	# Since 4977452 a newborn waits at the hospital with its mother until
	# Welcome Baby Home drives them back; it no longer walks in from the street.
	check(baby.is_away() and str(baby.away_state.get("activity",""))=="hospital" and LifeBirthHomecoming.in_hospital(household.birth_homecoming) and LifeBirthHomecoming.party_ids(household.birth_homecoming).has(baby_id),"The baby waits at the hospital for Welcome Baby Home.")
	check(household.pregnancy.get("pending",false)==false,"The pending birth is consumed by the confirmation.")
	app.queue_free();await process_frame

func _persistence_case()->void:
	var app=_home()
	await process_frame
	await process_frame
	_setup(app)
	var household=app.household
	var bed:Dictionary=_find(app,"bed")
	_sleep(app,bed,0)
	_sleep(app,bed,1)
	await _admit(app,bed)
	var started:Dictionary=household.begin_try_for_baby(str(household.members[0].id),str(bed.id))
	await _admit_beat(app)
	household.tick((LifeBabyPlan.DURATION+1.0)/LifeSim.GAME_MINUTES_PER_SECOND)
	household.set_speed(1)
	# The guard follows the real term (fourteen days since 2184c56), with a
	# day of slack; it used to be sized for the old three-day pregnancy.
	var guard:int=0
	var hours:int=ceili(LifeBabyPlan.PREGNANCY_MINUTES/60.0)+24
	while bool(household.pregnancy.get("active",false)) and guard<hours:
		household.tick(60.0/LifeSim.GAME_MINUTES_PER_SECOND)
		guard+=1
	for i:int in range(4):await process_frame
	app.show_baby_creator()
	app.profile.name="Kit Linden"
	app.profile.frame=1
	app.profile.gender="male"
	app.profile.eye_color="704b36"
	app.confirm_baby_creator()
	await process_frame
	var baby_id:String=""
	for member:Dictionary in household.members:
		if str(member.sim.character.get("age_stage",""))=="baby":baby_id=str(member.id)
	var state:Dictionary=household.get_state(app.world.serialize_items())
	var roundtrip:Dictionary=JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(state)))
	var fresh:=LifeHousehold.new()
	root.add_child(fresh)
	var restored:Dictionary=fresh.restore_state(roundtrip)
	check(bool(restored.ok),"The save with the new baby loads: %s." % str(restored.get("error","")))
	var loaded=fresh.member_sim(baby_id)
	check(is_instance_valid(loaded) and str(loaded.character.name)=="Kit Linden" and str(loaded.character.age_stage)=="baby" and str(loaded.character.eye_color)=="704b36","A fresh load restores the created baby with its edited name and appearance.")
	check(not LifeBabyPlan.expecting(fresh.pregnancy) and fresh.pregnancy.baby.is_empty() and str(fresh.pregnancy.mother_id).is_empty() and str(fresh.pregnancy.father_id).is_empty(),"A confirmed birth leaves no pending or running pregnancy behind.")
	check(fresh.member_sim(str(household.members[0].id)).relationships.has(baby_id) and fresh.member_sim(baby_id).relationships.has(str(household.members[0].id)),"The parents' relationship rows survive the load with the baby, in both directions.")
	# An older save without the field stays readable.
	var old:Dictionary=roundtrip.duplicate(true)
	old.erase("pregnancy")
	var older:=LifeHousehold.new()
	root.add_child(older)
	check(bool(older.restore_state(old).ok),"A save without the new pregnancy field stays readable.")
	var legacy:Dictionary=fresh.get_state()
	legacy.erase("pregnancy")
	check(LifeBabyPlan.validate(legacy.get("pregnancy"),legacy).is_empty(),"A missing pregnancy record validates as no pregnancy.")
	var broken:Dictionary=roundtrip.duplicate(true)
	broken.pregnancy={"version":1,"active":true,"pending":false,"mother_id":str(household.members[0].id),"father_id":str(household.members[1].id),"conceived_at":0.0,"due_at":0.0,"serial":1,"baby":{}}
	var rejected:=LifeHousehold.new()
	root.add_child(rejected)
	check(not bool(rejected.restore_state(broken).ok),"A malformed pregnancy record is refused, not silently dropped.")
	app.queue_free();fresh.queue_free();older.queue_free();rejected.queue_free();await process_frame
