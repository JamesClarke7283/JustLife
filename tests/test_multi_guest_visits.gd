extends "res://tests/test_home_visit.gd"
## Several guests at once. Three neighbors arrive together as party visits: each gets a
## doorstep place and a place inside of their own, all walk in without a host greeting,
## a save in the middle restores all three, travel and building are refused, and each
## goes home at their own deadline. Also checks the helpers on the residents service,
## the saved-record validation, the food validators over several guests, and that a
## guest's own wheel, activities and conversations reach that guest and no other.
const GUESTS:Array[String]=["maya","leo","priya"]
var closest:float=100.0
## Where each household member started, so a scene that moves one can put them back.
var spots:Dictionary={}
func _first(kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}
func _visit(id:String)->LifeHomeVisit:return app.residents.visit_for(id)
func _guest_phase(id:String)->String:
	var visit:LifeHomeVisit=_visit(id)
	return str(visit.state.get("phase","absent")) if visit.owns(id) else "absent"
func _all(phase:String,ids:Array=GUESTS)->bool:
	for id:String in ids:
		if _guest_phase(id)!=phase:return false
	return true
## Keep the closest any two guests ever came, to prove bodies never pile up.
func _track()->void:
	for first:int in GUESTS.size():
		for second:int in range(first+1,GUESTS.size()):
			var a:LifeActor=app.world.actors.get(GUESTS[first]);var b:LifeActor=app.world.actors.get(GUESTS[second])
			if is_instance_valid(a) and is_instance_valid(b) and a.visible and b.visible and _visit(GUESTS[first]).owns(GUESTS[first]) and _visit(GUESTS[second]).owns(GUESTS[second]):
				closest=minf(closest,a.position.distance_to(b.position))
func _until_all(phase:String,limit:int=4000,ids:Array=GUESTS)->bool:
	for index:int in limit:
		if _all(phase,ids):return true
		_step();_track()
	return _all(phase,ids)
func _spread(key:String,ids:Array=GUESTS)->float:
	var least:float=100.0
	for first:int in ids.size():
		for second:int in range(first+1,ids.size()):
			least=minf(least,Vector3(_visit(ids[first]).state[key]).distance_to(Vector3(_visit(ids[second]).state[key])))
	return least
func _party_data(slot:String)->Dictionary:return LifeSaveLibrary.read_slot(slot).data
func _party_records(raw:Dictionary)->Array:return LifeHomeVisit.saved_context(raw).residents.party_visits
func _refuse(slot:String,label:String,mutate:Callable)->void:
	var raw:Dictionary=_party_data(slot)
	mutate.call(raw)
	var error:String=LifeHomeVisit.validate_saved(raw)
	check(not error.is_empty(),label+" is refused by the visit validator ("+error+")")
	_reject(raw,label)
func _reject(raw:Dictionary,label:String)->void:
	var result:Dictionary=LifeSaveLibrary.save_slot("",label,raw)
	if not bool(result.ok):check(true,label+" is refused before load");return
	var before:Dictionary=_facts();var epoch:int=app.load_epoch
	app.load_game(str(result.id))
	check(app.load_epoch==epoch and _facts()==before,label+" is refused without live mutation")

func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup()
	for member:Dictionary in app.household.members:
		for id:String in GUESTS:
			if member.sim.relationships.has(id):member.sim.relationships[id].friendship=30
	var residents:LifeResidents=app.residents
	for member:Dictionary in app.household.members:spots[str(member.id)]=app.world.actors[str(member.id)].position
	# ---------------------------------------------------------- with nobody here
	check(residents.visits()==[residents.home_visit] and residents.party_visits.is_empty(),"With no party the only visit is the ordinary one")
	check(not residents.any_visit_active() and not residents.party_active() and residents.guest_ids().is_empty(),"Nobody is visiting before anyone is asked")
	check(residents.visit_for("maya")==residents.home_visit,"A neighbor nobody owns resolves to the ordinary visit, as it always did")
	check(residents.reserved_guest_points(residents.home_visit).is_empty(),"With one visit nothing is reserved")
	# ---------------------------------------------------------- invite three together
	var now:float=residents.home_visit._now()
	var untils:Array[float]=[now+120.0,now+150.0,now+180.0]
	var queue_before:int=app.sim.action_queue.size()
	for index:int in GUESTS.size():
		check(residents.visit_for(GUESTS[index]).party_requirement(GUESTS[index]).is_empty(),"A friend may be asked to the party: "+GUESTS[index])
		check(residents.invite_to_party(GUESTS[index],1,untils[index]),"Party invitation starts a visit of their own: "+GUESTS[index])
	check(residents.party_visits.size()==3 and residents.home_visit.state.is_empty(),"Three party visits exist and the ordinary visit stays free")
	check(residents.any_visit_active() and residents.party_active() and residents.guest_ids()==GUESTS,"Every guest is listed as visiting")
	for id:String in GUESTS:
		check(_visit(id)!=residents.home_visit and _visit(id).owns(id),"The visit that owns "+id+" is not the ordinary one")
	check(residents.visit_for("tom")==residents.home_visit,"A neighbor who is not visiting still resolves to the ordinary visit")
	check(not residents.party_visits[0].party_requirement("maya").is_empty(),"A guest cannot be asked twice")
	check(not residents.home_visit.requirement("tom").is_empty() and not residents.home_visit.invite("tom"),"An ordinary invitation waits while party guests are here")
	check(not residents.home_visit.consider_ring(true),"Nobody rings the doorbell while a party is on")
	check(_spread("welcome")>=LifeHomeVisit.GUEST_GAP-.001,"Three guests get three different doorstep places (%.2f m apart)" % _spread("welcome"))
	check(_spread("inside")>=LifeHomeVisit.GUEST_GAP-.001,"Three guests get three different places inside (%.2f m apart)" % _spread("inside"))
	check(_spread("exit")>=LifeHomeVisit.GUEST_GAP-.001,"Three guests get three different places at the kerb (%.2f m apart)" % _spread("exit"))
	for index:int in GUESTS.size():
		check(is_equal_approx(_visit(GUESTS[index]).stay_deadline(),untils[index]) and int(_visit(GUESTS[index]).state.party)==1,"The stay of "+GUESTS[index]+" ends when the party says")
	check(not residents.party_visits[0].ask_to_stay_over(),"A party guest does not stay over")
	check(not residents.reserved_guest_points(residents.party_visits[0]).is_empty(),"The other guests' places are reserved against a fourth")
	# ---------------------------------------------------------- travel and building are refused
	var frozen:Dictionary=_facts()
	app.travel_to("park")
	check(_facts()==frozen and not residents.begin_trip("park"),"Travel is refused while any guest is here")
	app.set_build_mode(true)
	check(app.mode=="live","Building is refused while any guest is here")
	# ---------------------------------------------------------- a save while they walk over
	app.household.set_speed(1);_step(40);app.household.set_speed(0)
	check(app.save_game("","Three guests arriving"),"Three guests mid-route can be saved")
	var arriving_slot:String=app.active_save_id;var expected:Dictionary=residents.snapshot()
	check(expected.has("party_visits") and expected.party_visits.size()==3,"The snapshot carries all three party visits")
	_load(arriving_slot);await process_frame
	residents=app.residents
	check(_same_snapshot(residents.snapshot(),expected),"Reloading mid-arrival restores all three exactly")
	check(residents.party_visits.size()==3 and residents.guest_ids()==GUESTS,"All three are still guests after the reload")
	# ---------------------------------------------------------- a save while one is coming through the door
	app.household.set_speed(4);closest=100.0
	var entering:bool=false
	for step:int in 4000:
		_step();_track()
		for id:String in GUESTS:
			if _guest_phase(id)=="entering":entering=true
		if entering:break
	app.household.set_speed(0)
	check(entering,"One guest is admitted while the others are still on their way")
	check(app.save_game("","Guest coming through the door"),"A guest coming in beside two others can be saved")
	var entering_slot:String=app.active_save_id;expected=residents.snapshot()
	_load(entering_slot);await process_frame
	residents=app.residents
	check(_same_snapshot(residents.snapshot(),expected) and residents.party_visits.size()==3,"Reloading mid-entry restores every guest exactly")
	# ---------------------------------------------------------- they all walk in, no welcome pressed
	app.household.set_speed(4)
	check(_until_all("inside",6000),"All three walk in without anybody welcoming them")
	app.household.set_speed(0)
	check(closest>.3,"Bodies kept apart on the way in (closest %.2f m)" % closest)
	check(app.sim.action_queue.size()==queue_before and app.household.speed==0,"No host was needed and nobody was slowed or queued")
	for id:String in GUESTS:
		var visit:LifeHomeVisit=_visit(id)
		check(visit.state.greeting.is_empty() and visit.state.entrance.is_empty() and not bool(visit.state.auto_welcome),"No host greeting for "+id)
	var spots:Array[Vector3]=[]
	for id:String in GUESTS:spots.append(app.world.actors[id].position)
	check(spots[0].distance_to(spots[1])>.5 and spots[0].distance_to(spots[2])>.5 and spots[1].distance_to(spots[2])>.5,"The three stand in three different places inside")
	# ---------------------------------------------------------- a save with all three inside
	check(app.save_game("","Three guests inside"),"Three guests inside can be saved")
	var inside_slot:String=app.active_save_id;expected=residents.snapshot()
	_load(inside_slot);await process_frame
	residents=app.residents
	check(_same_snapshot(residents.snapshot(),expected) and _all("inside"),"Reloading with all three inside restores them exactly")
	for index:int in GUESTS.size():
		check(is_equal_approx(_visit(GUESTS[index]).stay_deadline(),untils[index]) and int(_visit(GUESTS[index]).state.party)==1,"The party number and end time of "+GUESTS[index]+" survive the save")
	check(LifeHomeVisit.validate_saved(_party_data(inside_slot)).is_empty(),"The saved party visits validate")
	# ---------------------------------------------------------- tampered records are refused
	_refuse(inside_slot,"Duplicate party guest",func(raw:Dictionary):_party_records(raw).append(_party_records(raw)[0].duplicate(true)))
	_refuse(inside_slot,"Party stay past five hours from now",func(raw:Dictionary):
		var clock:Dictionary=LifeHomeVisit.saved_context(raw).member_state
		_party_records(raw)[0].visit.party_until=(float(clock.day)-1.0)*1440.0+float(clock.minutes)+301.0)
	_refuse(inside_slot,"Party stay ending before the invitation",func(raw:Dictionary):_party_records(raw)[0].visit.party_until=float(_party_records(raw)[0].visit.created_at)-1.0)
	_refuse(inside_slot,"Party guest without a party number",func(raw:Dictionary):_party_records(raw)[1].visit.erase("party"))
	_refuse(inside_slot,"Party guest with a host greeting",func(raw:Dictionary):_party_records(raw)[2].visit.greeting={"member":"player","token":1,"active_at":-1})
	_refuse(inside_slot,"Party guest at the door",func(raw:Dictionary):_party_records(raw)[0].doorbell={"serial":1,"guest":"maya"})
	_refuse(inside_slot,"Party list that is not a list",func(raw:Dictionary):LifeHomeVisit.saved_context(raw).residents.party_visits="nobody")
	_refuse(inside_slot,"Party guest waiting for a greeting",func(raw:Dictionary):_party_records(raw)[0].visit.phase="waiting")
	_refuse(inside_slot,"Party guest of another party",func(raw:Dictionary):raw.party={"serial":9,"guests":[{"id":"maya"},{"id":"leo"},{"id":"priya"}],"ends_at":1000000.0})
	_refuse(inside_slot,"Party guest missing from the guest list",func(raw:Dictionary):raw.party={"serial":1,"guests":[{"id":"maya"},{"id":"leo"}],"ends_at":1000000.0})
	_refuse(inside_slot,"Party guest staying past the party's end",func(raw:Dictionary):raw.party={"serial":1,"guests":[{"id":"maya"},{"id":"leo"},{"id":"priya"}],"ends_at":float(_party_records(raw)[2].visit.party_until)-10.0})
	var agreeing:Dictionary=_party_data(inside_slot)
	agreeing.party={"serial":1,"guests":[{"id":"maya"},{"id":"leo"},{"id":"priya"}],"ends_at":untils[2]}
	check(LifeHomeVisit.validate_saved(agreeing).is_empty(),"A party record that agrees with its guests is accepted")
	# ---------------------------------------------------------- each guest's own wheel, activity and conversation
	for id:String in GUESTS:_visit(id).activity.cancel("")
	app.show_interactions({"id":"leo","kind":"neighbor","label":"Leo"},Vector2(700,420))
	await process_frame;await process_frame
	var ring:Button=app.overlay.find_child("WheelCategory_fun",true,false)
	if is_instance_valid(ring):ring.pressed.emit();await process_frame;await process_frame
	var suggest:Button=app.overlay.find_child("WheelAction_guest_activity",true,false)
	check(is_instance_valid(suggest) and not suggest.disabled,"A party guest's wheel offers Suggest an activity once they are inside")
	if is_instance_valid(suggest):
		suggest.pressed.emit();await process_frame;await process_frame
		var toilet:Dictionary=_first("toilet")
		var choice:Button=app.overlay.find_child("GuestActivity_toilet_"+str(toilet.id),true,false)
		check(is_instance_valid(choice),"The activity list opens for the guest who was clicked")
		if is_instance_valid(choice):
			choice.pressed.emit();await process_frame
			check(_visit("leo").activity.active() and not _visit("maya").activity.active() and not _visit("priya").activity.active(),"The chosen activity goes to the clicked guest and to nobody else")
			check(str(_visit("leo").activity.current_action().get("id",""))=="toilet","Leo is on the way to the toilet")
			check(not _visit("maya").activity.request("toilet",str(toilet.id),true),"A second guest cannot take the toilet the first is using")
			check(_visit("maya").activity.request("relax",str(_first("sofa").id),true) if not _first("sofa").is_empty() else true,"The second guest can still do something else")
	app.close_overlay()
	for id:String in GUESTS:_visit(id).activity.cancel("")
	# a household member talks to a party guest
	var friendship:float=app.sim.relationships.priya.friendship
	app.household.set_speed(8)
	app.queue_interaction({"id":"priya","kind":"neighbor","label":"Priya","node":app.world.actors.priya,"size":Vector2(.6,.6)},"friendly")
	var talking:bool=false
	for step:int in 1200:
		if str(app.sim.get_current_action().get("phase",""))=="active":talking=true;break
		_step();_track()
	check(talking,"A household member reaches and starts talking with a party guest")
	for step:int in 800:
		if app.sim.action_queue.is_empty():break
		_step();_track()
	app.household.set_speed(0)
	check(app.sim.action_queue.is_empty() and app.sim.relationships.priya.friendship>friendship,"The conversation finishes and the friendship grows")
	check(_all("inside"),"All three guests are still inside after the talk")
	# ---------------------------------------------------------- television beside the host
	await _tv_checks()
	# ---------------------------------------------------------- the food checks over several guests
	_food_checks()
	# ---------------------------------------------------------- they leave at their own deadlines
	app.household.set_speed(8)
	var left:Dictionary={};var gone:Dictionary={}
	for step:int in 12000:
		_step();_track()
		for index:int in GUESTS.size():
			var id:String=GUESTS[index]
			if not left.has(id) and _guest_phase(id) in ["leaving","absent"]:
				left[id]=residents.home_visit._now()
				check(left[id]>=untils[index]-.5 and left[id]<=untils[index]+8.0,"%s starts leaving at their own deadline (%.0f of %.0f)" % [id,left[id],untils[index]])
				if id!="priya":check(_guest_phase("priya")=="inside","The others stay until their own time after "+id+" goes")
		for id:String in GUESTS:
			if not gone.has(id) and _guest_phase(id)=="absent":
				gone[id]=true
				check(not residents.present(id),id+" has gone home when their visit ends")
		if residents.party_visits.is_empty() and left.size()==3:break
	app.household.set_speed(0)
	check(left.size()==3 and left.maya<left.leo and left.leo<left.priya,"They leave in the order of their deadlines")
	check(residents.party_visits.is_empty() and not residents.any_visit_active() and residents.guest_ids().is_empty(),"Finished party visits are forgotten")
	check(gone.size()==3,"Every guest finished their visit and walked off")
	check(residents.home_visit.state.is_empty() and residents.home_visit.next_serial==1,"The ordinary visit was never touched")
	app.set_build_mode(true)
	check(app.mode=="build","Building works again once everyone has gone")
	app.set_build_mode(false)
	await _mixed_party()
	await _finish()

## An ordinary visitor inside with two party guests: all three live side by side, share a
## dish without clashing over places, survive a save in the middle of the meal, and go.
func _mixed_party()->void:
	var residents:LifeResidents=app.residents
	var ids:Array=["tom","maya","leo"]
	for member:Dictionary in app.household.members:
		if member.sim.relationships.has("tom"):member.sim.relationships.tom.friendship=30
	app.household.set_speed(8)
	check(residents.home_visit.invite("tom"),"An ordinary invitation works again once the party is over")
	check(_until("waiting",3000),"The ordinary visitor reaches the door")
	check(residents.home_visit.welcome(app.household.selected_id()),"The host welcomes the ordinary visitor")
	app.household.set_speed(8)
	check(_until("inside",4000),"The ordinary visitor comes in the old way, through a welcome")
	var now:float=residents.home_visit._now()
	check(residents.invite_to_party("maya",2,now+150.0) and residents.invite_to_party("leo",2,now+170.0),"Two party guests are asked while the ordinary visitor is inside")
	check(residents.guest_ids()==ids and residents.visit_for("tom")==residents.home_visit,"The ordinary visit keeps tom and the party visits keep the others")
	app.household.set_speed(8);closest=100.0
	check(_until_all("inside",6000,ids),"All three, ordinary and party, end up inside")
	app.household.set_speed(0)
	check(closest>.3,"Bodies kept apart on the way in (closest %.2f m)" % closest)
	check(not residents.home_visit.state.has("party") and int(_visit("maya").state.party)==2,"Only the party guests carry the party number")
	check(_spread("inside",ids)>=.5,"The ordinary visitor and the party guests stand apart inside (%.2f m)" % _spread("inside",ids))
	check(not residents.begin_trip("park"),"Travel is refused while the visitors are here")
	check(app.save_game("","Mixed party inside"),"An ordinary visitor and two party guests can be saved together")
	var mixed_slot:String=app.active_save_id;var expected:Dictionary=residents.snapshot()
	_load(mixed_slot);await process_frame
	residents=app.residents
	check(_same_snapshot(residents.snapshot(),expected) and _all("inside",ids) and residents.party_visits.size()==2,"All three come back exactly")
	check(LifeHomeVisit.validate_saved(_party_data(mixed_slot)).is_empty(),"The mixed save validates")
	_refuse(mixed_slot,"Party guest who is also the ordinary visitor",func(raw:Dictionary):_party_records(raw)[0].visit.guest="tom")
	# ---- a shared dish: nobody takes another guest's chair or plate
	for id:String in ids:
		_visit(id).activity.cancel("");_visit(id).activity.data.needs.hunger=20.0
	var dish:Dictionary=app.meal_flow.place_potluck("maya")
	check(not dish.is_empty(),"A dish is set out on a table")
	if dish.is_empty():return
	app.meal_flow.call_to_meal(str(dish.id))
	app.household.set_speed(8)
	var plated:int=0;var saved_mid:bool=false
	for step:int in 4000:
		_step();_track()
		plated=0
		for id:String in ids:
			if not str(_visit(id).meal.state.get("plate","")).is_empty():plated+=1
		if plated>=2:break
	check(plated>=2,"At least two guests have taken a serving at the same time")
	app.household.set_speed(0)
	var places:Dictionary={};var distinct:bool=true
	for id:String in ids:
		var meal:Dictionary=_visit(id).meal.state
		if str(meal.get("plate","")).is_empty():continue
		var key:String=str(meal.seat) if not str(meal.seat).is_empty() else "standing:%s" % str(meal.target)
		if places.has(key):distinct=false
		places[key]=id
	check(distinct,"Each guest with a serving has a place of their own")
	var plates:Array=[]
	for portion:Dictionary in app.household.meals.portions:
		if LifeResidentCatalogue.PEOPLE.has(str(portion.owner)):plates.append(str(portion.owner))
	check(plates.size()>=2 and plates.size()==plated,"The food ledger holds one plate for each guest who took one")
	check(app.save_game("","Mixed party mid-meal"),"A save with several guests holding plates is accepted")
	var meal_slot:String=app.active_save_id;expected=residents.snapshot()
	_load(meal_slot);await process_frame
	residents=app.residents
	check(_same_snapshot(residents.snapshot(),expected) and residents.party_visits.size()==2,"The meal comes back exactly with every guest's plate")
	var owned:int=0
	for portion:Dictionary in app.household.meals.portions:
		if LifeResidentCatalogue.PEOPLE.has(str(portion.owner)):owned+=1
	check(owned==plates.size(),"Each guest's plate is still owned by that guest")
	var tampered:Dictionary=_party_data(meal_slot);var owner_id:String=str(plates[0])
	for portion:Dictionary in tampered.meals.portions:
		if str(portion.owner)==owner_id:portion.guest_visit=float(portion.get("guest_visit",1))+7
	_reject(tampered,"Guest plate bound to another visit")
	tampered=_party_data(meal_slot)
	for portion:Dictionary in tampered.meals.portions:
		if str(portion.owner)==owner_id:portion.owner="priya" if owner_id!="priya" else "leo"
	_reject(tampered,"Guest plate handed to a different guest")
	app.household.set_speed(8)
	var fed:Dictionary={}
	for step:int in 6000:
		_step();_track()
		var done:bool=true
		for id:String in ids:
			if _visit(id).meal.active() or not str(_visit(id).activity.data.get("pending_meal","")).is_empty():done=false
			if float(_visit(id).activity.data.needs.hunger)>45.0:fed[id]=true
		if done and fed.size()==plated:break
	app.household.set_speed(0)
	check(fed.size()>=plated and plated>=2,"Every guest who took a serving ate it and is less hungry")
	check(_all("inside",ids),"All three are still inside after the meal")
	# ---- and they go home, each at their own time
	app.household.set_speed(8)
	for step:int in 12000:
		_step();_track()
		if _all("absent",ids):break
	app.household.set_speed(0)
	check(_all("absent",ids) and not residents.any_visit_active(),"All three leave and the visits are forgotten")

## Two party guests join the host in front of the television: they take different places,
## share the host's programme, and come back exactly after a save.
func _tv_checks()->void:
	var tv:Dictionary=_first("tv")
	check(not tv.is_empty(),"The starter home has a television")
	if tv.is_empty():return
	var host_id:String=app.household.selected_id()
	for id:String in GUESTS:
		_visit(id).activity.cancel("");_visit(id).activity.data.next_at=_visit(id).activity.now()+170.0
	check(app.tv_group.request(app.sim,str(tv.id),false),"The host turns on the television")
	app.household.set_speed(8)
	var hosting:bool=false
	for step:int in 1500:
		_step();_track()
		if str(app.sim.get_current_action().get("phase",""))=="active":hosting=true;break
	check(hosting,"The host sits down and the programme starts")
	var joiners:Array=["maya","leo"]
	for id:String in joiners:
		var activity:LifeGuestActivity=_visit(id).activity
		var plan:Dictionary=app.tv_group.guest_target(host_id,activity)
		check(not plan.is_empty() and activity.request_plan(plan,true),id+" is given a place beside the viewers")
	var watching:bool=false
	for step:int in 1800:
		_step();_track()
		watching=true
		for id:String in joiners:
			var current:Dictionary=_visit(id).activity.current_action()
			if not LifeTVGroup.owns(current) or str(current.get("phase",""))!="active":watching=false
		if watching:break
	app.household.set_speed(0)
	check(watching,"Both guests walk over and watch")
	if not watching:return
	var host_action:Dictionary=app.sim.get_current_action()
	var places:Dictionary={str(host_action.target_id)+":"+str(host_action.get("seat_slot","")):host_id}
	var shared:bool=true;var apart:bool=true
	for id:String in joiners:
		var current:Dictionary=_visit(id).activity.current_action()
		var key:String=str(current.target_id)+":"+str(current.get("seat_slot",""))
		if places.has(key):apart=false
		places[key]=id
		if str(current.tv.session)!=str(host_action.tv.session):shared=false
	check(apart,"The host and both guests sit in three different places")
	check(shared,"Everyone watches the host's programme")
	var viewers:Array=[]
	for record:Dictionary in app.tv_group.records():viewers.append(str(record.id))
	check("maya" in viewers and "leo" in viewers and host_id in viewers,"The television counts every viewer, guests included")
	var maya_tv:Dictionary=_visit("maya").activity.current_action().tv.duplicate(true)
	var saved_tv:bool=app.save_game("","Two guests watching television")
	check(saved_tv,"A save with two guests watching is accepted")
	if saved_tv:
		_load(app.active_save_id);await process_frame
		check(_visit("maya").activity.current_action().get("tv",{})==maya_tv and LifeTVGroup.owns(_visit("leo").activity.current_action()),"Both guests are back in front of the programme after a load")
	for id:String in joiners:_visit(id).activity.cancel("")
	app.cancel_current_action()
	_step(5)
	check(not LifeTVGroup.owns(app.sim.get_current_action()),"The host stops watching")
	# A host left standing in the narrow hall would block the guests' way out, which only
	# the player can clear, so put the household back where they began.
	for id:String in spots:app.world.actors[id].position=spots[id]
	_step(2)

## Plates owned by several guests: each is checked against its own guest's visit and meal.
func _food_checks()->void:
	var meals:=LifeMeals.new()
	var at:float=app.residents.home_visit._now()
	var batch:Dictionary=meals.create_batch("garden_skillet","player",2,"home",at)
	meals.set_batch_location(str(batch.id),"surface","",Vector3(0,.16,1),at)
	var plate:Dictionary=meals.claim(str(batch.id),"leo",at)
	plate.guest_visit=2;plate.guest_meal=3
	var data:Dictionary=meals.get_state()
	var ids:Array=["player","river"]
	var maya_visit:Dictionary={"guest":"maya","serial":2,"meal":{}}
	var leo_visit:Dictionary={"guest":"leo","serial":2,"meal":{"source":str(batch.id),"plate":str(plate.id),"phase":"to_place","seat":"","standing":true,"token":3}}
	check(not plate.is_empty() and LifeMeals.validate(data,ids,at,maya_visit,[leo_visit]).is_empty(),"A plate a second guest is carrying passes with that guest's visit listed")
	check(not LifeMeals.validate(data,ids,at,maya_visit).is_empty(),"The same plate fails when no saved guest owns it")
	check(LifeMeals.validate(data,ids,at,leo_visit).is_empty(),"A single guest's plate still passes the way it always did")
	var wrong:Dictionary=leo_visit.duplicate(true);wrong.meal.token=4
	check(not LifeMeals.validate(data,ids,at,maya_visit,[wrong]).is_empty(),"A plate bound to a different meal of its guest fails")
	var members:Array=[{"id":"player","state":{"action_queue":[]}},{"id":"river","state":{"action_queue":[]}}]
	check(LifeMeals.validate_actions(data,members,{},"home",maya_visit,[leo_visit]).is_empty(),"The second guest's carried plate has a matching meal action")
	check(not LifeMeals.validate_actions(data,members,{},"home",maya_visit).is_empty(),"A carried plate nobody owns is refused")

func _finish()->void:
	var file:=FileAccess.open("user://home_visit_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":LifeSaveLibrary._json_safe(events)},"",true,true));file.close()
	print("HOME_VISIT ",checks,"/",failures.size())
	app.queue_free();await process_frame;await process_frame;await create_timer(.3).timeout
	quit(0 if failures.is_empty() else 1)
