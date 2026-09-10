extends "res://tests/test_home_visit.gd"
var slots:Dictionary={}
func _first(kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}
func _load_phase(name:String)->void:
	_load(str(slots[name]));await process_frame
	app.household.set_speed(1)
func _active()->bool:
	for index:int in 500:
		var action:Dictionary=app.sim.get_current_action()
		if str(action.get("phase",""))=="active":return true
		_step()
	return false
func _reject(raw:Dictionary,label:String)->void:
	var result:Dictionary=LifeSaveLibrary.save_slot("",label,raw)
	if not bool(result.ok):check(true,label+" is refused before load");return
	var before:Dictionary=_facts();var epoch:int=app.load_epoch
	app.load_game(str(result.id))
	check(app.load_epoch==epoch and _facts()==before,label+" is refused without live mutation")
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	slots=JSON.parse_string(FileAccess.get_file_as_string("user://home_visit_slots.json"))
	await _load_phase("waiting")
	var friendship:float=app.sim.relationships.maya.friendship
	app.residents.home_visit.welcome(app.household.selected_id())
	check(_active(),"Welcome becomes an actual paid conversation before goodbye")
	var active:Dictionary=app.sim.get_current_action()
	app.queue_interaction(_first("bookshelf"),"read")
	app.residents.home_visit.goodbye()
	check(_phase()=="leaving" and is_same(app.sim.get_current_action(),active) and app.residents.present("maya"),"Goodbye retains the actual active Welcome and visible guest")
	check(not active.has("home_visit_serial") and not active.has("home_visit_token"),"Converted departure releases welcome-only token ownership")
	app.household.set_speed(0);check(app.save_game("","Goodbye during Welcome"),"Goodbye during paid Welcome can be saved")
	var departure_slot:String=app.active_save_id
	var expected:Dictionary=app.residents.snapshot();_load(departure_slot);await process_frame
	check(app.residents.snapshot()==expected and _phase()=="leaving","Paid-Welcome goodbye restores its exact departure identity")
	app.household.set_speed(1)
	check(_until("absent"),"Retained Welcome finishes before one physical departure")
	check(app.sim.relationships.maya.friendship==friendship+12,"Goodbye grants only the existing real friendly completion")
	check(app.sim.action_queue.any(func(a:Dictionary)->bool:return str(a.id)=="read"),"Later unrelated instruction survives guest departure")
	await _load_phase("waiting")
	app.queue_interaction(_first("bookshelf"),"read")
	app.residents.home_visit.welcome(app.household.selected_id())
	var token:Dictionary=app.sim.action_queue[-1]
	app.cancel_current_action(app.sim.action_queue.size()-1)
	app.residents.home_visit.reconcile()
	check(app.residents.home_visit.state.greeting.is_empty() and not app.sim.action_queue.has(token),"Canceling queued Welcome clears only its visit token")
	check(str(app.sim.get_current_action().get("id",""))=="read","Canceling Welcome preserves earlier work")
	app.cancel_current_action()
	app.sim.queue_action("friendly","maya",app.world.actors.maya.position+Vector3(0,0,.8))
	check(_active(),"An ordinary untagged friendly conversation can actually start")
	for index:int in 250:
		if app.sim.action_queue.is_empty():break
		_step()
	check(_phase()=="waiting" and app.residents.home_visit.state.admitted_at==-1,"Untagged friendly completion cannot admit a home guest")
	check(_until("absent",4000),"Unwelcomed guest times out and physically leaves")
	await _load_phase("waiting")
	var before:Dictionary=_facts()
	check(not app.residents.home_visit.invite("leo") and _facts()==before,"A second simultaneous invitation leaves the live state unchanged")
	var raw:Dictionary=LifeSaveLibrary.read_slot(str(slots.greeting)).data
	var v:Dictionary=LifeHomeVisit.saved_visit(raw).value.visit
	v.greeting.token=float(v.greeting.token)+1
	_reject(raw,"Mismatched saved welcome token")
	raw=LifeSaveLibrary.read_slot(str(slots.greeting)).data
	var owner:Dictionary=raw.members[0].state.action_queue[0].duplicate(true)
	raw.members[1].state.action_queue=[owner]
	_reject(raw,"Duplicate active guest owner")
	raw=LifeSaveLibrary.read_slot(str(slots.inside)).data
	v=LifeHomeVisit.saved_visit(raw).value.visit
	raw.members[0].state.character.world_state.player=v.position.duplicate()
	_reject(raw,"Guest and restored household body overlap")
	raw=LifeSaveLibrary.read_slot(str(slots.inside)).data
	v=LifeHomeVisit.saved_visit(raw).value.visit
	v.route.point=999
	_reject(raw,"Out-of-range saved guest route cursor")
	raw=LifeSaveLibrary.read_slot(str(slots.inside)).data
	LifeHomeVisit.saved_visit(raw).residents.version=0
	_reject(raw,"Unsupported enclosing resident version")
	raw=LifeSaveLibrary.read_slot(str(slots.inside)).data
	LifeHomeVisit.saved_visit(raw).residents.locations.home.maya.wait=-1
	_reject(raw,"Invalid active guest resident schedule")
	raw=LifeSaveLibrary.read_slot(str(slots.waiting)).data
	LifeHomeVisit.saved_visit(raw).value.visit.phase_at-=1
	_reject(raw,"Inconsistent waiting phase clock")
	await _load_phase("inside")
	var created:float=app.residents.home_visit.state.phase_at
	check(_until("leaving",9000),"An admitted guest begins departure after a bounded stay")
	check(app.residents.home_visit._now()>=created+LifeHomeVisit.STAY_MINUTES,"The stay deadline is measured from actual indoor arrival")
	check(_until("absent"),"Stay expiry walks to the sidewalk before absence")
	var out:=FileAccess.open("user://home_visit_departure_slot.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"slot":departure_slot}));out.close()
	await _finish()
