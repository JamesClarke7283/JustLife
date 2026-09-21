extends "res://tests/test_courtesy_beneficiary_base.gd"

func _run()->void:
	phase_tag="clear_natural";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	audit={"events":[],"samples":[],"scope":"Same actual1b404 checkpoint public fresh load; ten paused frames then ordinary .05 process + one yielded frame. No phase save, manual movement, needs/clock/queue injection or rescue; stop after actual protected retirement and original donor movement, at most60game minutes/90wall seconds."}
	var read:Dictionary=LifeSaveLibrary.read_slot(LANDING_SLOT)
	check(bool(read.get("ok",false)),"Actual landing save passes production detached validation.")
	if not bool(read.get("ok",false)):quit(1);return
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false)
	await frames(4);app.set_sound(false);await _public_load()
	check(app.active_save_id==LANDING_SLOT and app.household.speed==0 and app.sim.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Actual public fresh load is paused for all clocks.")
	var initial:Dictionary=_physical_facts()
	for i:int in range(10):app._process(.05);await frames(1)
	check(_physical_facts()==initial,"Ten paused ordinary frames preserve all typed physical/queue/food/clock/stair facts.")
	var t:LifeTraversal=app.traversal;var donor:String="housemate_3";var peer:String="player"
	var protected:Dictionary=t.routes[peer].duplicate(true);var original:Dictionary=t.routes[donor].duplicate(true)
	var current:Dictionary=app.household.member_sim(donor).get_current_action();var queue:Array=app.household.member_sim(donor).action_queue.duplicate(true)
	check(t.courtesy._eligible(t,donor) and not t.courtesy._eligible(t,peer) and t.courtesy._beneficiary_kind(t,peer)=="stair_clear","Casey remains ordinary donor; Rowan is eligible only as protected-clear beneficiary.")
	check(not t._step_clear(peer,app.world.actors[peer].position,t.courtesy._next(t,peer)),"Actual protected next step is blocked before any courtesy.")
	audit["initial"]=_record_clear();audit["base_save"]=LANDING_SLOT
	var seen:bool=false;var hold:bool=false;var retired:bool=false;var resumed:bool=false;var invalid:bool=false;var donor_changed:bool=false
	var minimum:float=INF;var minimum_pair:Array=[];var selected:Dictionary={};var release_reason:String=""
	await press("▶▶▶")
	var until:float=_now()+60.0;var wall:int=Time.get_ticks_msec()+90000
	while _now()<until and Time.get_ticks_msec()<wall:
		app._process(.05);await frames(1)
		audit.samples.append(_record_clear())
		for id:String in app.world.actors:
			if not app.world.actors[id].visible:continue
			for member:Dictionary in app.household.members:
				var other:String=str(member.id)
				if id==other or not app.world.actors[other].visible:continue
				var a:Vector3=app.world.actors[id].position;var b:Vector3=app.world.actors[other].position
				if not t._same_floor(a,b):continue
				var distance:float=a.distance_to(b)
				if distance<minimum:minimum=distance;minimum_pair=[id,other,a,b,_now()]
		if t.routes.has(peer) and int(t.routes[peer].identity)==int(protected.identity):
			var route:Dictionary=t.routes[peer];var lock:Dictionary=t.stairs[str(protected.stair_id)]
			for key:String in ["identity","ticket","phase","destination","stair_id","exit","clear","safety"]:
				if route[key]!=protected[key]:invalid=true
			if lock.owner!=peer or lock.exit!=protected.exit or lock.clear!=protected.clear:invalid=true
		else:retired=true
		# The gate must ask about this donor's own courtesy, not about any owner:
		# a different member owning one left `donor`'s route without a `courtesy`
		# key and the read below aborted the phase.
		if t.routes.has(donor) and t.routes[donor].has("courtesy"):
			seen=true
			var route:Dictionary=t.routes[donor];var fact:Dictionary=route.courtesy
			if selected.is_empty():selected=fact.duplicate(true);audit["first_retreat"]=_record_clear()
			if str(fact.phase)=="hold":
				hold=true
				if not audit.has("first_hold"):audit["first_hold"]=_record_clear()
			if not is_same(current,app.household.member_sim(donor).get_current_action()) or app.household.member_sim(donor).action_queue!=queue or route.destination!=original.destination or int(route.identity)!=int(original.identity):donor_changed=true
		for row:Dictionary in t.courtesy.trace:
			if str(row.get("released",""))==donor:release_reason=str(row.reason)
		if retired and seen and t.courtesy.owner(t).is_empty() and not selected.is_empty() and app.world.actors[donor].position!=selected.anchor:
			resumed=is_same(current,app.household.member_sim(donor).get_current_action()) and app.household.member_sim(donor).action_queue==queue
			if resumed:break
	check(seen and str(selected.get("beneficiary_kind",""))=="stair_clear" and int(selected.get("version",0))==2,"Ordinary controller selects an explicitly versioned protected-clear courtesy.")
	check(hold,"Actual retreat physically reaches its holding anchor.")
	check(not invalid,"Protected route identity/phase/ticket/destination/exit/clear and held lock remain exact until natural retirement.")
	check(not donor_changed,"Retreat/hold preserve original donor action object, complete queue, route identity/destination and paid/progress fields.")
	check(retired and str(t.stairs[str(protected.stair_id)].owner)!=peer,"Rowan naturally completes clearance and releases the owned lock.")
	check(release_reason in ["beneficiary_cleared","beneficiary_retired"],"Donor releases for actual protected completion/retirement, never expiry.")
	check(resumed,"Casey physically resumes the same original instruction after the clear route retires.")
	check(minimum>=.72,"Every sampled household body remains at least.72m from every visible Lifelet.")
	check(app.active_save_id==LANDING_SLOT,"No public or phase save was used to induce recovery.")
	audit["result"]={"selected":selected,"seen_hold":hold,"retired":retired,"resumed":resumed,"protected_changed":invalid,"donor_changed":donor_changed,"release_reason":release_reason,"minimum":minimum,"minimum_pair":minimum_pair,"samples":audit.samples.size()}
	audit["final"]=_record_clear()
	await _finish()

func _public_load()->void:
	await press("Saved lives")
	var selected:bool=false
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and str(node.get_meta("save_id",""))==LANDING_SLOT:
			node.pressed.emit();await frames(2);selected=true;break
	check(selected,"Public picker selects the exact original landing seed even when phase saves exist.")
	await press("Load selected life",true)
