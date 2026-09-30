extends SceneTree
## Producer/consumer run in separate processes. Consumers never reposition a
## passer or edit a loaded action; they resume the ordinary saved greeting.
var app:Node
var checks:int=0
var failures:int=0
const PET:String="street_pet"
func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Run with an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
	run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func frames(n:int=2)->void:
	for i:int in n:await process_frame
func step()->void:
	app._process(.1);await process_frame
func near(a:Variant,b:Variant)->bool:
	if (a is int or a is float) and (b is int or b is float):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not near(a[key],b[key]):return false
		return true
	return a==b
func run()->void:
	if OS.get_environment("JUSTLIFE_PASSING_PHASE")=="produce":state_controls()
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
	await frames();app.set_sound(false)
	if OS.get_environment("JUSTLIFE_PASSING_PHASE")=="produce":await produce()
	else:await consume()
	var minimum:int=15 if OS.get_environment("JUSTLIFE_PASSING_PHASE")=="produce" else (10 if OS.get_environment("JUSTLIFE_PASSING_SLOT")=="passing_old" else 7)
	if checks<minimum:check(false,"The requested phase completed every expected assertion")
	app.queue_free();await frames()
	print("PASSING_FRESH_LOAD checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
func state_controls()->void:
	var street:=LifeStreetLife.new();street.tick(1.0,1.0,1199.0)
	street.hold(PET,"player");street.tick(.1,1.0,1201.0)
	var saved:Dictionary=JSON.parse_string(JSON.stringify(street.snapshot()))
	var copy:=LifeStreetLife.new()
	check(copy.restore(saved,1201.0) and bool(copy.find(PET).active),"A held dog saved after its duty hours remains present on restore")
	copy.hold(PET,"player");var at:Vector3=copy.position_of(copy.find(PET))
	copy.tick(.1,0.0,1201.0)
	check(copy.position_of(copy.find(PET))==at and copy.is_held(PET),"The first paused tick preserves an after-hours held passer")
	street=LifeStreetLife.new();street.tick(4.0,1.0,480.0)
	copy=LifeStreetLife.new();copy.restore(JSON.parse_string(JSON.stringify(street.snapshot())),480.0)
	check(copy.position_of(copy.find("street_walker_dog")).is_equal_approx(street.position_of(street.find("street_walker_dog"))) and int(copy.find("street_walker_dog").dir)==int(copy.find("street_adult").dir),"A leashed dog restores the real offset and direction of its saved walker")
	copy.hold("street_walker_dog","player")
	check(copy.is_held("street_walker_dog") and copy.is_held("street_adult"),"The reconstructed leashed party shares its conversation hold")
	var bad:Dictionary=street.snapshot();bad.passers["unknown_street_person"]={}
	copy=LifeStreetLife.new()
	check(not copy.restore(bad,480.0) and copy.find("unknown_street_person").is_empty(),"Malformed street state cannot invent a passer outside the roster")
	check(not LifeStreetLife.new().restore({"version":1,"passers":{}},480.0),"An empty street snapshot uses legacy reconstruction rather than claiming exact restoration")
	bad=street.snapshot();bad.passers.erase(PET)
	check(not LifeStreetLife.new().restore(bad,480.0),"A truncated snapshot missing the saved dog uses legacy reconstruction")
func produce()->void:
	app.household_profiles=[{"name":"Avery","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();await frames()
	app.sim.autonomy=false;app.household.set_speed(1)
	while not app.sim.action_queue.is_empty():app.sim.cancel_action()
	app.player.position=Vector3(6,.16,6.4)
	check(not app.passing_chat.stand_point(app.street_life.find(PET),app.bound_member_id).is_finite(),"The day-one delivery van correctly blocks standing beside the default dog")
	for i:int in 18:await step()
	app.residents.publish_targets(true)
	app.queue_interaction({"id":PET,"kind":"passer"},"greet_passing_pet")
	for i:int in 4:await step()
	app.household.set_speed(0)
	var action:Dictionary=app.sim.get_current_action()
	check(str(action.get("id",""))=="greet_passing_pet" and str(action.get("phase",""))=="approach" and app.street_life.is_held(PET),"A real on-duty dog greeting is saved during its approach")
	if str(action.get("id",""))!="greet_passing_pet":return
	check(absf(float(app.street_life.find(PET).x)+4.0)>.1,"The saved dog has actually walked away from its default fresh-process position")
	var expected:Dictionary={"street":app.street_life.snapshot(),"id":action.id,"target_id":action.target_id,"paid":action.paid,"elapsed":action.elapsed}
	check(app.save_game("passing_new","Passing street snapshot"),"Public save writes the moving street and queued greeting")
	var old:Dictionary=LifeSaveLibrary.read_slot("passing_new").data
	# The continuous-play checkpoint is day three: the weekly delivery van
	# is absent, so the roster's default dog has legitimate standing space.
	old.day=3
	for member:Dictionary in old.members:
		member.state.day=3
		member.state.career.schedule=LifeCareerSchedule.advance(member.state.career.schedule,3,int(member.state.career.worked_day),true,member.state.career).state
		member.state.character.world_state.erase("street")
		# Controlled old-format fixture: the admitted greeting's owner is now
		# inside, out of sight of the roster's default dog at x=-4.
		if str(member.id)==app.household.selected_id():member.state.character.world_state.player=[-1.0,.16,-2.75]
	var legacy_saved:Dictionary=LifeSaveLibrary.save_slot("passing_old","Legacy passing fixture",old)
	if not bool(legacy_saved.get("ok",false)):print("LEGACY_FIXTURE_ERROR ",legacy_saved)
	check(bool(legacy_saved.get("ok",false)),"A day-three old-format fixture omits street state and places its owner indoors")
	var canonical:Dictionary=app.build_transactions.current()
	check(bool(canonical.get("ok",false)),"The current home has a valid canonical geometry fixture")
	if bool(canonical.get("ok",false)):
		app.world.construction.restore(canonical.state);app.world.rebuild_navigation();app._refresh_sim_targets()
		check(app.save_game("passing_journey","Passing journey snapshot"),"A journey-format save retains the same queued greeting")
		check(LifeSaveLibrary.read_slot("passing_journey").data.has("journeys"),"The canonical fixture really exercises staged journey adoption")
	FileAccess.open("user://passing_fresh_expected.json",FileAccess.WRITE).store_string(JSON.stringify(expected))
func consume()->void:
	var slot:String=OS.get_environment("JUSTLIFE_PASSING_SLOT")
	if slot.is_empty():slot="passing_new"
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://passing_fresh_expected.json"))
	app.load_game(slot);await frames(3)
	if app.mode!="live" or not is_instance_valid(app.player):
		check(false,"The saved household loads into a playable world: "+str(app.notice_text));return
	var action:Dictionary=app.sim.get_current_action()
	if str(action.get("id",""))!=str(expected.id):
		print("PASSING_RESTORE_FAILURE ",JSON.stringify({"slot":slot,"mode":app.mode,"queue":app.sim.action_queue,"notice":app.notice_text,"aside":app.notice_aside,"notices":app.notice_queue,"routes":app.route_failures,"player":str(app.player.position),"pet":app.street_life.find(PET),"admitted":app.passing_chat._restored}))
		var pet_at:Vector3=app.street_life.position_of(app.street_life.find(PET))
		for offset:Vector3 in [Vector3(0,0,-.62),Vector3(-.4464,0,-.4464),Vector3(.4464,0,-.4464),Vector3(-.62,0,0),Vector3(.62,0,0),Vector3(0,0,.62),Vector3(-.4464,0,.4464),Vector3(.4464,0,.4464)]:
			var p:Vector3=pet_at+offset;p.x=snappedf(p.x,.25);p.z=snappedf(p.z,.25)
			print("PASSING_ROUTE_PROBE ",JSON.stringify({"point":str(p),"clear":app.passing_chat.stand_clear(p,pet_at,true,app.bound_member_id),"route":app.traversal._floor_route(app.player.position,p,app.bound_member_id).size(),"legacy":app.world.path_to(app.player.position,p).size(),"graph":app.world.route_to(app.player.position,p)}))
	check(str(action.get("id",""))==str(expected.id) and str(action.get("target_id",""))==PET,"A fresh controller retains the saved passing action and counterpart")
	check(action.get("paid")==expected.paid and is_equal_approx(float(action.get("elapsed",-1)),float(expected.elapsed)),"Fresh load preserves payment and exact activity progress")
	if str(action.get("id",""))!=str(expected.id):return
	if slot!="passing_old":check(near(app.street_life.snapshot(),expected.street),"Fresh load restores the exact street positions, directions and presence before any tick")
	else:
		check(not app.world.sight_line_clear(app.player.position,app.street_life.position_of(app.street_life.find(PET))),"The old-format fallback really starts out of sight of the rebuilt dog")
		app._refresh_sim_targets(false)
		check(is_same(action,app.sim.get_current_action()),"An admitted old-format greeting survives refresh while routing from indoors")
		check(not bool(app.sim.get_action_availability("pet_passing_pet",PET).available),"A new passing request remains unavailable while the saved dog is out of sight")
		var queued:int=app.sim.action_queue.size()
		app.queue_interaction({"id":PET,"kind":"passer"},"pet_passing_pet")
		check(app.sim.action_queue.size()==queued and is_same(action,app.sim.get_current_action()),"The public interaction callback refuses an unseen new request without disturbing the saved greeting")
	check(app.street_life.is_held(PET),"The saved instruction rebuilds the passer's hold")
	var paused:Dictionary=app.street_life.snapshot()
	await step()
	check(near(paused,app.street_life.snapshot()) and app.sim.speed==0,"The first normal paused frame leaves restored street movement frozen")
	app.household.set_speed(3);app.sim.autonomy=false
	for i:int in 1600:
		await step()
		if app.sim.action_queue.is_empty():break
	check(app.sim.action_queue.is_empty() and app.sim.passing_contacts.has(PET),"Freshly loaded greeting reaches the actual dog and earns its ordinary completion")
	for i:int in 3:await step()
	check(not app.street_life.is_held(PET),"Completion releases the restored passer to continue walking")
