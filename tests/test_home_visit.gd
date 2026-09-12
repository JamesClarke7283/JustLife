extends SceneTree
const MainScene=preload("res://scenes/main.tscn")
var app:Node
var checks:int=0
var failures:Array[String]=[]
var events:Array=[]
var decoded_layout:Array=[]
var loaded_layout:Array=[]
var finished_welcome:Dictionary={}
func _initialize()->void:
	if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty() or OS.get_environment("XDG_DATA_HOME").is_empty() or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):quit(2);return
	_run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func _step(count:int=1,delta:float=.05)->void:
	for index:int in count:app._process(delta)
func _phase()->String:return str(app.residents.home_visit.state.get("phase","absent"))
## Budgets are .05 s steps at normal speed, which advances one game minute per real
## second, so a 120-minute welcome needs 2,400 steps and a 360-minute stay 7,200.
func _until(phase:String,limit:int=3000)->bool:
	for index:int in limit:
		if _phase()==phase:return true
		_step()
	return _phase()==phase
func _load(slot:String)->void:
	var raw:Dictionary=LifeSaveLibrary.read_slot(slot).data
	decoded_layout=raw.world.duplicate(true)
	var prior:int=app.load_epoch
	app.load_game(slot)
	loaded_layout=app.world.serialize_items().duplicate(true)
	check(app.load_epoch==prior+1,"Named load actually replaces the live household: "+slot)

func _same_snapshot(a:Variant,b:Variant)->bool:
	# Live positions are float32 (Vector3); the JSON round trip keeps doubles.
	# Compare with engine float32 tolerance instead of bit equality.
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for k:Variant in a:
			if not b.has(k) or not _same_snapshot(a[k],b[k]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i:int in range(a.size()):
			if not _same_snapshot(a[i],b[i]):return false
		return true
	if (a is float or a is int) and (b is float or b is int):return is_equal_approx(float(a),float(b))
	return a==b
func _same_value(a:Variant,b:Variant)->bool:
	# Positions pass through Vector3 (float32) on the live path while saves
	# carry JSON doubles; numerics compare with engine float32 tolerance.
	if (a is float or a is int) and (b is float or b is int):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not _same_value(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index:int in a.size():
			if not _same_value(a[index],b[index]):return false
		return true
	return a==b

func _facts()->Dictionary:
	return {"household":app.household.get_state(app.world.serialize_items()),"physical":app._physical_snapshot_context(),"resident":app.residents.snapshot(),"mode":app.mode,"selection":app.bound_member_id}
func _setup()->void:
	app.household_profiles=[{"name":"Avery","age_stage":"young_adult","traits":[],"hair":0},{"name":"River","age_stage":"young_adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();app.set_process(false);app.set_sound(false)
	if "--canonical-fixture" in OS.get_cmdline_user_args():
		var layout:Array=app.world.serialize_items()
		for index:int in layout.size():
			if str(layout[index].get("kind",""))=="__construction":layout[index]=LifeBuildingState.migrate(layout[index]).state
		app.loading_game=true;app.setup_live(layout);app.loading_game=false
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false;member.sim.set_aging("normal",false);member.sim.household_bills_enabled=false;member.sim.wants.clear()
		for need:String in LifeSim.NEED_NAMES:member.sim.needs[need]=85
	app.sim.relationships.maya.friendship=30;app.sim.relationships.leo.friendship=30
	app.household.set_speed(1)
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup()
	check(not app.residents.home_visit._building().is_empty(),"Home exposes a validated physical navigation view")
	var initial_layout:Array=app.world.serialize_items().duplicate(true)
	var funds:int=app.household.funds;var friendship:float=app.sim.relationships.maya.friendship
	app.show_relationships()
	var invite:Button=app.overlay.find_child("InviteResident_maya",true,false)
	check(is_instance_valid(invite) and not invite.disabled,"People exposes an enabled Invite over button for a known friend")
	if not is_instance_valid(invite):await _finish();return
	invite.pressed.emit()
	check(_phase()=="arriving","Public invitation starts a physical arrival")
	check(app.household.funds==funds and app.sim.relationships.maya.friendship==friendship,"Invitation grants no money or friendship")
	check(app.world.serialize_items()==initial_layout,"Invitation leaves the original layout byte-value exact")
	if _phase()!="arriving":events.append(app.notice_label.text);await _finish();return
	_step(12)
	app.household.set_speed(0)
	var frozen:Dictionary=_facts();var actor_pose:Transform3D=app.world.actors.maya.transform
	_step(12)
	check(_facts()==frozen and app.world.actors.maya.transform==actor_pose,"Pause preserves exact guest route, clocks and household state")
	check(app.save_game("","Guest arriving"),"Named save records a mid-route arriving guest")
	var arriving_slot:String=app.active_save_id;var expected:Dictionary=app.residents.snapshot()
	_load(arriving_slot);await process_frame
	if app.residents.snapshot()!=expected:events.append({"expected_arrival":expected,"actual_arrival":app.residents.snapshot()})
	check(_same_snapshot(app.residents.snapshot(),expected) and _phase()=="arriving","Same-process named load preserves exact paused arrival")
	check(app.residents.home_visit.app==app,"Adopted helper resolves the live owner controller")
	if "--layout-probe" in OS.get_cmdline_user_args():
		events.append({"layout_before":initial_layout,"layout_after":app.world.serialize_items()})
		await _finish();return
	app.household.set_speed(8)
	check(_until("waiting"),"Guest walks collision-aware route to the welcome point")
	check(app.household.speed==1,"Fast arrival slows to1 exactly when the guest starts waiting")
	app.refresh_hud()
	var welcome:Button=app.ui.find_child("WelcomeGuest",true,false)
	check(is_instance_valid(welcome) and not welcome.disabled,"Persistent Live HUD offers Welcome in")
	var before:Dictionary=_facts();app.set_build_mode(true)
	check(_facts()==before,"Build refusal leaves queues, clocks, selection and guest unchanged")
	app.travel_to("park")
	check(_facts()==before,"Travel refusal leaves the complete live state unchanged")
	app.household.set_speed(0)
	check(app.save_game("","Guest waiting"),"Waiting phase can be saved")
	var waiting_slot:String=app.active_save_id;expected=app.residents.snapshot();_load(waiting_slot);await process_frame
	check(_same_snapshot(app.residents.snapshot(),expected) and app.household.speed==0,"Paused waiting load does not repeat arrival or change speed")
	app.household.set_speed(1)
	app.residents.home_visit.welcome(app.household.selected_id())
	check(not app.residents.home_visit.state.greeting.is_empty(),"Welcome queues an identified ordinary friendly action")
	var action:Dictionary=app.sim.action_queue[-1]
	check(str(action.id)=="friendly" and float(action.duration)==25 and action.has("home_visit_token"),"Greeting keeps ordinary duration and records its visit token")
	var started:bool=false
	for step:int in 300:
		if str(app.sim.get_current_action().get("phase",""))=="active":started=true;break
		_step()
	check(started,"Welcome reaches an actual paid conversation")
	if not started:await _finish();return
	app.household.set_speed(0);check(app.save_game("","Guest greeting"),"Active identified greeting can be saved")
	var greeting_slot:String=app.active_save_id;expected=app.residents.snapshot();_load(greeting_slot);await process_frame
	check(_same_snapshot(app.residents.snapshot(),expected),"Active greeting load preserves exact visit token and start clock")
	app.household.member_action_finished.connect(func(id:String,done:Dictionary):
		if done.has("home_visit_token"):
			var speaker:LifeSim=app.household.member_sim(id)
			finished_welcome={"action":done.duplicate(true),"clock":(speaker.day-1)*1440.0+speaker.minutes})
	app.household.set_speed(1)
	check(_until("entering"),"Actual completed friendly admits the guest at its member event time")
	if _phase()!="entering":await _finish();return
	check(not finished_welcome.is_empty() and float(finished_welcome.action.elapsed)==25 and float(app.residents.home_visit.state.admitted_at)==float(finished_welcome.clock),"Paid completion keeps exact event clock despite frame overshoot")
	app.household.set_speed(0);check(app.save_game("","Guest entering"),"Partial indoor arrival can be saved")
	var entering_slot:String=app.active_save_id;expected=app.residents.snapshot();_load(entering_slot);await process_frame
	check(_same_snapshot(app.residents.snapshot(),expected),"Entering load preserves exact route cursor")
	app.household.set_speed(1)
	check(_until("inside"),"Actual walking and accepted friendly completion admit the guest")
	events.append({"phase":_phase(),"notice":app.notice_label.text,"visit":app.residents.home_visit.snapshot(),"queue":str(app.sim.action_queue)})
	if _phase()!="inside":await _finish();return
	check(app.world.serialize_items()==loaded_layout,"Admission retains the exact immediately restored layout")
	check(app.sim.relationships.maya.friendship==friendship+12,"Only the completed ordinary friendly action grants friendship")
	app.household.set_speed(0);check(app.save_game("","Guest inside"),"Indoor visit saves without changing household membership")
	var inside_slot:String=app.active_save_id;expected=app.residents.snapshot();_load(inside_slot);await process_frame
	check(_same_snapshot(app.residents.snapshot(),expected) and app.household.members.size()==2,"Indoor load preserves guest phase and household size")
	app.residents.home_visit.goodbye();check(_phase()=="leaving" and app.residents.present("maya"),"Goodbye keeps the departing guest physically visible")
	app.household.set_speed(1);_step(15);app.household.set_speed(0)
	check(app.save_game("","Guest leaving"),"Partial physical departure can be saved")
	var leaving_slot:String=app.active_save_id;expected=app.residents.snapshot();_load(leaving_slot);await process_frame
	check(_same_snapshot(app.residents.snapshot(),expected) and _phase()=="leaving","Named load preserves exact departure cursor")
	app.household.set_speed(1);check(_until("absent"),"Guest follows the exit route and becomes absent only at the sidewalk")
	check(not app.residents.present("maya"),"Finished guest returns to the resident home schedule")
	var receipt:=FileAccess.open("user://home_visit_slots.json",FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"arriving":arriving_slot,"waiting":waiting_slot,"greeting":greeting_slot,"entering":entering_slot,"inside":inside_slot,"leaving":leaving_slot},"",true,true));receipt.close()
	await _finish()
func _finish()->void:
	var file:=FileAccess.open("user://home_visit_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":LifeSaveLibrary._json_safe(events)},"",true,true));file.close()
	print("HOME_VISIT ",checks,"/",failures.size())
	app.queue_free();await process_frame;await process_frame;await create_timer(.3).timeout
	quit(0 if failures.is_empty() else 1)
