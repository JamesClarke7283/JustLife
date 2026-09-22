extends "res://tests/test_courtesy.gd"
const BUSY_SLOT="life_1788953596100_30587280"
const WAITER="housemate_3"
var test_phase:String="natural_complete"
func _run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):test_phase=arg.trim_prefix("--phase=")
	phase_tag=test_phase;screenshot_dir="res://evidence";root.size=Vector2i(1440,900)
	app=MainScene.instantiate();root.add_child(app);current_scene=app;_exclude_inputs()
	await frames(4);app.set_sound(false)
	audit.scenario=test_phase
	match test_phase:
		"natural_complete":await _natural_busy()
		"fresh":await _fresh_wait()
		"explicit":await _explicit_queue()
		"fifo":await _fifo_busy()
		"fresh_fifo":await _fifo_resume()
		"negative":await _negative_busy()
		"witness_negative":await _witness_negative()
		"build_arrived","build_pair":await _build_independent()
		"build_target":await _build_target_mutation()
		_:check(false,"Unknown busy-resource test phase: "+test_phase)
	await _finish()
func _exclude_inputs()->void:
	root.gui_disable_input=true;app.set_process(false)
	if is_instance_valid(app.world):app.world.set_process(false)
	for node:Node in [app]+app.find_children("*","Node",true,false):
		node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false);node.set_process_shortcut_input(false)
func _project_queue(queue:Array)->Array:
	# The loader rebuilds each stored action from the live definition table and
	# adopts the saved progress, so a definition-derived field (`label`, `changes`,
	# `cost`, `description`, `skill`, `xp`) reflects today's code rather than the
	# text that was saved — which is what lets a retuned activity load. The saved
	# duration, elapsed, identity, payment and ownership are what a load must
	# preserve, and they are compared here through this projection.
	var result:Array=queue.duplicate(true)
	for action:Dictionary in result:
		action.progress=clampf(float(action.elapsed)/float(action.duration),0.0,1.0)
		var definition:Dictionary=app.sim._actions.get(str(action.get("id","")),{})
		if definition.is_empty():continue
		var rebuilt:Dictionary=definition.duplicate(true)
		if str(action.get("id",""))=="cook":rebuilt=LifeMeals.cooking_definition(rebuilt,str(action.get("recipe","garden_skillet")))
		for key:String in ["label","changes","cost","description","skill","xp"]:
			if rebuilt.has(key):action[key]=rebuilt[key]
	return result
func _busy_record()->Dictionary:
	var value:Dictionary=_record();value.funds=app.household.funds;value.waits={}
	for member:Dictionary in app.household.members:
		var motion:Dictionary=app.motion_states.get(str(member.id),{})
		var at:Vector3=motion.get("wait_destination",Vector3.INF)
		value.waits[member.id]={"waiting":bool(motion.get("waiting",false)),"started":float(motion.get("wait_started",-1.0)),"destination":LifeJourneyState.packed(at) if at.is_finite() else [],"resume_active":bool(motion.get("resume_active",false))}
	return value
func _load_busy(slot:String)->bool:
	var read:Dictionary=LifeSaveLibrary.read_slot(slot)
	check(bool(read.ok),"Actual named busy-furnishing slot validates: "+slot)
	if not bool(read.ok):return false
	await _load_slot(slot);_exclude_inputs()
	check(app.mode=="live" and app.active_save_id==slot and app.household.speed==0,"Public load reconstructs the real household paused.")
	check(_same(_project_journeys(read.data.journeys),app.traversal.snapshot()),"Decoded authoritative journey facts reconstruct with exact typed body/vector projection.")
	for member:Dictionary in read.data.members:
		check(_same(_project_queue(member.state.action_queue),app.household.member_sim(str(member.id)).action_queue),"Exact queue/elapsed/payment with existing derived progress formula: "+str(member.id))
	check(_same(read.data.meals,app.household.meals.get_state()),"Saved food ledger/custody are unchanged by load.")
	var before:Dictionary=_busy_record()
	for i:int in range(10):_exclude_inputs();app._process(.05);await frames(1)
	check(before==_busy_record(),"Ten ordinary paused calls retain physical state, needs, queues, waits, food and funds exactly.")
	return failures.is_empty()
func _save_wait()->void:
	await press("Ⅱ");var before:Dictionary=_busy_record()
	await _public_save("Busy furnishing — natural waiting");_exclude_inputs()
	var read:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(read.ok),"Public save accepts the naturally admitted resource waiting phase.")
	check(before==_busy_record(),"Public waiting save preserves bodies, complete queues, paid/progress, FIFO facts and funds.")
	if bool(read.ok):audit.saves.append({"slot":app.active_save_id,"data":read.data,"facts":_busy_record()})
	for i:int in range(5):_exclude_inputs();app._process(.05);await frames(1)
	check(before==_busy_record(),"Natural waiting remains exactly paused after the saved checkpoint.")
	await press("▶")
## Normal speed runs one game minute per real second since the clock pacing
## change, so the thirty-minute waiting rule needs 900 of these .05 s steps.
func _natural_busy()->void:
	if not await _load_busy(BUSY_SLOT):return
	var sim:LifeSim=app.household.member_sim(WAITER);var original:Dictionary=sim.get_current_action();var origin:Vector3=app.world.actors[WAITER].position
	check(original.id=="sleep" and original.phase=="approach" and str(original.target_id)=="item_16" and app.household.member_sim("player").get_current_action().phase=="active","Actual natural checkpoint contains Casey approaching Rowan's occupied bed.")
	check(origin.distance_to(original.target_position)==.75 and not bool(original.paid) and float(original.elapsed)==0.0,"The waiting body is genuinely near the occupied anchor, with no early payment/progress.")
	audit.initial=_busy_record();var first_wait:float=-1.0;var switch_at:float=-1.0;var saved:bool=false;var minimum:float=INF;var wait_identity:bool=true;var no_early_progress:bool=true
	await press("▶")
	for i:int in range(900):
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();audit.steps.append(row);minimum=minf(minimum,float(row.clearance.household_minimum))
		var current:Dictionary=sim.get_current_action();var motion:Dictionary=app.motion_states.get(WAITER,{})
		if bool(motion.get("waiting",false)):
			if first_wait<0:first_wait=float(motion.wait_started)
			wait_identity=wait_identity and is_same(current,original) and current.target_id=="item_16"
			no_early_progress=no_early_progress and not bool(current.paid) and float(current.elapsed)==0.0 and float(current.progress)==0.0
			if not saved:saved=true;await _save_wait()
		if not is_same(current,original) and switch_at<0:switch_at=_now()
		if switch_at>=0 and not current.is_empty() and current.phase=="active" and float(current.elapsed)>.6:break
	await press("Ⅱ")
	audit.first_wait=first_wait;audit.switch_at=switch_at;audit.minimum_clearance=minimum;audit.final=_busy_record()
	check(first_wait>=0 and saved,"Candidate naturally enters existing resource waiting and creates a real checkpoint.")
	check(wait_identity and no_early_progress,"Waiting retains the original full action identity and unpaid zero progress.")
	check(switch_at>=first_wait+30.0,"Alternate autonomy begins only after at least30 actual game minutes in the resource queue.")
	var final:Dictionary=sim.get_current_action()
	check(switch_at>=0 and final.target_id!="item_16" and final.phase=="active" and float(final.elapsed)>.6,"Ordinary waiting reconsideration reaches and starts a real alternative recovery.")
	check(minimum>=LifeTraversal.BODY_GAP-.000001,"Household-versus-visible actor spacing preserves the existing .72m body clearance.")
func _fresh_wait()->void:
	var produced:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/natural_slots.json"))
	check(produced.saves.size()==1,"Producer supplies one actual natural waiting save.")
	if produced.saves.is_empty():return
	var slot:String=str(produced.saves[0].slot)
	if not await _load_busy(slot):return
	var sim:LifeSim=app.household.member_sim(WAITER);var action:Dictionary=sim.get_current_action();var original_wait:Dictionary=_busy_record().waits[WAITER]
	check(bool(original_wait.waiting) and float(original_wait.started)>=0 and not bool(action.paid),"Fresh load retains original resource FIFO time and unpaid queued ownership.")
	audit.initial=_busy_record();var switched:float=-1.0;var minimum:float=INF
	await press("▶")
	for i:int in range(900):
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();audit.steps.append(row);minimum=minf(minimum,float(row.clearance.household_minimum))
		var next:Dictionary=sim.get_current_action()
		if not is_same(next,action) and switched<0:switched=_now()
		if switched>=0 and not next.is_empty() and next.phase=="active" and float(next.elapsed)>.6:break
	await press("Ⅱ")
	check(switched>=float(original_wait.started)+30.0,"Fresh waiting uses the saved FIFO origin before legitimate autonomous reconsideration.")
	var final:Dictionary=sim.get_current_action()
	check(switched>=0 and final.target_id!="item_16" and final.phase=="active" and float(final.elapsed)>.6,"Fresh continuation physically starts an alternative recovery without resetting the queue timer.")
	check(minimum>=LifeTraversal.BODY_GAP-.000001,"Fresh waiting and recovery preserve existing physical body clearance.")
	audit.final=_busy_record();audit.switched=switched;audit.minimum_clearance=minimum
func _finish()->void:
	var ambience:WeakRef=weakref(app.ambience_player.stream);var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free();await frames(2)
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Private app audio releases before exit.")
	audit.assertions=assertions;audit.failures=failures
	var f:=FileAccess.open(screenshot_dir.path_join(test_phase+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(_finite_json(audit),"  ",true,true));f.close()
	print("BUSY_RESULT assertions=%d failures=%d"%[assertions,failures.size()]);quit(0 if failures.is_empty() else 1)

func _natural_slot()->String:
	return str(JSON.parse_string(FileAccess.get_file_as_string("res://evidence/natural_slots.json")).saves[0].slot)
func _select_busy(id:String)->void:
	var chip:Button=app.household_chips[id];chip.pressed.emit();await frames(2);_exclude_inputs()
	check(app.bound_member_id==id,"Public household portrait selects "+id)
func _interact_busy(item:Dictionary,id:String)->void:
	app.show_interactions(item,Vector2(760,350));await frames(2)
	await press(str(app.sim._actions[id].label));_exclude_inputs()
func _explicit_queue()->void:
	if not await _load_busy(_natural_slot()):return
	await _select_busy(WAITER)
	await _interact_busy(first_item("bookshelf"),"read")
	var sim:LifeSim=app.household.member_sim(WAITER);var later:Dictionary=sim.action_queue.back();var later_facts:Dictionary=later.duplicate(true)
	check(sim.action_queue.size()==2 and later.id=="read" and not bool(later.get("autonomous",false)),"A public directed reading instruction is queued behind the naturally waiting sleep.")
	audit.initial=_busy_record();var start:float=app.motion_states[WAITER].wait_started;var original:Dictionary=sim.get_current_action();var switch_at:float=-1.0;var preserved:bool=true
	await press("▶")
	for i:int in range(900):
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;audit.steps.append(row)
		preserved=preserved and sim.action_queue.has(later) and is_same(sim.action_queue.back(),later) and later==later_facts
		var current:Dictionary=sim.get_current_action()
		if not is_same(current,original) and switch_at<0:switch_at=_now()
		if switch_at>=0 and current.phase=="active" and float(current.elapsed)>.6:break
	await press("Ⅱ")
	check(switch_at>=start+30 and sim.get_current_action().id=="nap" and sim.get_current_action().phase=="active","Normal delayed recovery still reaches a real nap with a later player instruction present.")
	check(preserved,"The complete later explicit action object, target, unpaid state and position in the queue remain exact through waiting and recovery.")
	audit.final=_busy_record();audit.switched=switch_at

## Component-only no-free-wait-point contract; no production behavior is overridden in natural/fresh flows.
class PackedWaitController extends "res://scripts/main.gd":
	func _wait_position_clear(_destination:Vector3,_arrived_owner:bool=false)->bool:return false
func _negative_busy()->void:
	if not await _load_busy(BUSY_SLOT):return
	await _select_busy(WAITER)
	var before:Dictionary=_busy_record();var action:Dictionary=app.sim.get_current_action();var original:Dictionary=action.duplicate(true);var route:Dictionary=app.traversal.routes[WAITER];var original_route:Dictionary=route.duplicate(true);var body:Vector3=app.player.position
	audit.initial=before;audit.scope="Declared component guard cases temporarily alter one input fact without simulation, then restore it. They are not natural crossing/arrival evidence."
	app.walk_only=true;check(not app._queue_near_busy_activity(),"An explicit walk cannot acquire a furnishing queue.");app.walk_only=false
	app.resume_activity=true;check(not app._queue_near_busy_activity(),"A paid active owner returning to position is excluded from new queue arrival.");app.resume_activity=false
	action.phase="active";check(not app._queue_near_busy_activity(),"An active action cannot become a new resource waiter.");action.phase=original.phase
	action.cooperation_id="component_pair";check(not app._queue_near_busy_activity(),"Cooperative homework ownership is excluded.");action.erase("cooperation_id")
	action.id="friendly";check(not app._queue_near_busy_activity(),"Social approach remains on its own body-aware admission path.");action.id=original.id
	action.target_id="missing_component_item";check(not app._queue_near_busy_activity(),"A missing furnishing cannot receive a queue reservation.");action.target_id=original.target_id
	for stage:String in ["entry","transit","clear"]:
		route.phase=stage;check(not app._queue_near_busy_activity(),"Protected stair "+stage+" cannot be replaced by resource waiting.")
	route.phase=original_route.phase;route.safety=true;check(not app._queue_near_busy_activity(),"An owned safety crossing cannot acquire a resource wait.");route.safety=original_route.safety
	route.courtesy={"beneficiary_id":"housemate_2"};route.courtesy_action=action
	check(app.traversal.courtesy.preserve_request(app.traversal,WAITER,action.target_position) and not app._queue_near_busy_activity(),"An existing same-instruction courtesy owner retains its movement ownership.")
	route.erase("courtesy");route.erase("courtesy_action")
	app.player.position=body-Vector3(.5,0,0);check(app.player.position.distance_to(action.target_position)>1 and not app._queue_near_busy_activity(),"An approach farther than1m cannot receive early arrival.");app.player.position=body
	app.player.position=Vector3(-4.25,3.16,.75);check(app.world.point_level(app.player.position)==1 and not app._queue_near_busy_activity(),"A supported Upper body cannot queue for a Ground activity anchor.");app.player.position=body
	app.player.position=action.target_position;check(not app.traversal._free(WAITER,app.player.position) and not app._queue_near_busy_activity(),"Body overlap at the occupied anchor cannot be accepted as clear waiting floor.");app.player.position=body
	var owner_sim:LifeSim=app.household.member_sim("player");var owner_queue:Array=owner_sim.action_queue.duplicate();owner_sim.action_queue.clear()
	check(app._activity_available(action) and not app._queue_near_busy_activity(),"A currently available furnishing continues ordinary arrival instead of creating a wait.")
	owner_sim.action_queue.assign(owner_queue)
	var wall_pair:Array=[]
	for x:int in range(-20,21):
		if not wall_pair.is_empty():break
		for z:int in range(-16,17):
			var p:=Vector3(x*.25,.16,z*.25)
			if not app.world.lot_navigation.point_clear(0,p):continue
			for delta:Vector3 in [Vector3(.75,0,0),Vector3(0,0,.75),Vector3(1,0,0),Vector3(0,0,1)]:
				var q:Vector3=p+delta
				if app.world.lot_navigation.point_clear(0,q) and not app.world.lot_navigation.segment_clear(0,p,q):wall_pair=[p,q];break
			if not wall_pair.is_empty():break
	check(wall_pair.size()==2,"Current authored geometry supplies two nearby supported points separated by a real wall.")
	if wall_pair.size()==2:
		app.player.position=wall_pair[0];action.target_position=wall_pair[1]
		check(not app._queue_near_busy_activity(),"A real intervening wall refuses nearby queue admission.")
		app.player.position=body;action.target_position=original.target_position
	audit.wall_pair=wall_pair
	check(before==_busy_record() and action==original and route==original_route,"All guard controls restore exact production facts without paying, progressing or changing queues.")
	var packed:=PackedWaitController.new();packed.world=app.world;packed.traversal=app.traversal;packed.player=app.player;packed.bound_member_id=WAITER;packed.path=app.path;packed.path_index=app.path_index
	packed._route_to_wait_position(action)
	check(packed.wait_destination==body and packed.path.is_empty() and not app.traversal.active(WAITER),"Declared fully packed waiting-space contract retires the old traversal and waits at the clear body.")
	check(action==original and app.player.position==body,"No-space fallback preserves the action, payment and physical body.")
	packed.free();app.traversal.routes[WAITER]=route
	audit.final=_busy_record()
func _fifo_busy()->void:
	if not await _load_busy(_natural_slot()):return
	var bed:Dictionary=app._find_item("item_16")
	await _select_busy(WAITER);await press("Cancel action");await _interact_busy(bed,"sleep");await _interact_busy(first_item("bookshelf"),"read")
	var early:LifeSim=app.household.member_sim(WAITER);var early_action:Dictionary=early.get_current_action();var later:Dictionary=early.action_queue.back();var later_facts:Dictionary=later.duplicate(true)
	check(early_action.id=="sleep" and not bool(early_action.get("autonomous",false)) and early.action_queue.size()==2,"Public replacement requests explicit Sleep with reading later.")
	await _select_busy("housemate_1");await press("Cancel action");await _interact_busy(bed,"sleep")
	var late:LifeSim=app.household.member_sim("housemate_1");var late_action:Dictionary=late.get_current_action()
	check(late_action.id=="sleep" and not bool(late_action.get("autonomous",false)),"A second Lifelet publicly requests the same occupied bed.")
	audit.initial=_busy_record();var minimum:float=INF;var both_waiting:bool=false;var before_pay:bool=true;var preserved:bool=true
	await press("▶")
	for i:int in range(1200):
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();audit.steps.append(row);minimum=minf(minimum,float(row.clearance.household_minimum))
		preserved=preserved and early.action_queue.has(later) and is_same(early.action_queue.back(),later) and later==later_facts
		before_pay=before_pay and not bool(early_action.paid) and not bool(late_action.paid) and early_action.elapsed==0.0 and late_action.elapsed==0.0
		if bool(row.waits[WAITER].waiting) and bool(row.waits.housemate_1.waiting) and _now()-float(row.waits[WAITER].started)>35:both_waiting=true;break
	await press("Ⅱ");audit.queued=_busy_record()
	check(both_waiting,"Both real bodies reach the busy furnishing queue; the first remains explicit beyond30minutes.")
	check(before_pay and preserved,"Neither waiter pays/progresses before admission, and the later reading object remains exact.")
	if not both_waiting:return
	var early_started:float=app.motion_states[WAITER].wait_started;var late_started:float=app.motion_states.housemate_1.wait_started
	check(early_started<late_started,"Physical arrival establishes distinct FIFO timestamps.")
	await _public_save("Busy furnishing — two explicit waiters");_exclude_inputs();audit.saves.append({"slot":app.active_save_id,"facts":_busy_record()})
	await _select_busy("player");await press("Cancel action");await _interact_busy(first_item("bookshelf"),"read")
	await press("▶");var started:bool=false
	for i:int in range(250):
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();audit.steps.append(row);minimum=minf(minimum,float(row.clearance.household_minimum))
		if early_action.phase=="active" and float(early_action.elapsed)>.6:started=true;break
	await press("Ⅱ")
	check(started and early_action.target_position==app.world.actors[WAITER].position,"After the owner's public cancellation and departure, the earlier waiter physically reaches and starts Sleep.")
	check(late.get_current_action()==late_action and late_action.phase=="approach" and not bool(late_action.paid) and late_action.elapsed==0.0,"The later physical waiter cannot steal the earlier reservation.")
	check(is_same(early.action_queue.back(),later) and later==later_facts,"Actual FIFO admission retains the later explicit reading action exactly.")
	check(minimum>=LifeTraversal.BODY_GAP-.000001,"Full FIFO approach/admission preserves existing household-versus-visible spacing.")
	audit.final=_busy_record();audit.minimum_clearance=minimum

func _finite_json(value:Variant)->Variant:
	if value is float and not is_finite(value):return {"nonfinite":"positive_infinity" if value>0 else "negative_infinity" if value<0 else "nan"}
	if value is Vector3:return [_finite_json(value.x),_finite_json(value.y),_finite_json(value.z)]
	if value is Array or value is PackedVector3Array:
		var result:Array=[]
		for entry:Variant in value:result.append(_finite_json(entry))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[key]=_finite_json(value[key])
		return result
	return value

func _build_independent()->void:
	for operation:String in ["cancel","commit"]:
		if not await _load_busy(_fifo_slot() if test_phase=="build_pair" else _natural_slot()):return
		if test_phase=="build_arrived":
			await press("▶")
			for i:int in range(70):
				_exclude_inputs();app._process(.05);await frames(1)
				if app.world.actors[WAITER].position==app.motion_states[WAITER].wait_destination:break
			await press("Ⅱ")
			check(app.world.actors[WAITER].position==app.motion_states[WAITER].wait_destination and bool(app.motion_states[WAITER].waiting),"Ordinary movement physically reaches the retained waiting point before independent Build "+operation)
		var before:Dictionary=_busy_record();audit[operation+"_initial"]=before
		await press("Build & buy");await press("Ground")
		check(before.waits==_busy_record().waits,"Build entry retains all FIFO facts before "+operation)
		var plant:Dictionary=first_item("plant");app.show_build_object(plant,Vector2(760,350));await press("Move furnishing")
		check(not app.pending_move.is_empty() and before.waits==_busy_record().waits,"Lifting an unrelated plant retains the same reservation before "+operation)
		if operation=="cancel":app.cancel_placement();await frames(2)
		else:
			# A bathroom spot that keeps the shower's standing place reachable; the
			# doorway rule refuses the old (4, -3) because it boxed that place in.
			var point:=Vector3(3.5,.16,-3.5)
			check(app.world.can_place("plant",point,0),"Independent commit uses a real supported production quote.")
			app.world.placement_requested.emit("plant",point,0.0);await frames(2)
			check(app.pending_move.is_empty() and app._find_item(str(plant.id)).node.position==point,"Independent commit moves the actual plant.")
		check(before.waits==_busy_record().waits,"Completed unrelated Build "+operation+" retains FIFO ownership before returning Live.")
		await press("Live");_exclude_inputs();var after:Dictionary=_busy_record()
		check(before.waits==after.waits,"Returning Live retains the exact old FIFO age, destination and waiting ownership: "+operation)
		check(before.at==after.at and before.people==after.people and before.funds==after.funds,"Independent Build "+operation+" preserves paused clock, physical bodies, complete actions, needs and funds.")
		for i:int in range(5):_exclude_inputs();app._process(.05);await frames(1)
		check(after==_busy_record(),"Ordinary paused frames after independent Build "+operation+" cannot advance anything.")
		audit[operation+"_final"]=_busy_record()
	await _public_save("Busy furnishing — after independent Build");_exclude_inputs()
	audit.saves.append({"slot":app.active_save_id,"facts":_busy_record()})

func _fifo_slot()->String:return str(JSON.parse_string(FileAccess.get_file_as_string("res://evidence/fifo_slots.json")).saves[0].slot)
func _fifo_resume()->void:
	if not await _load_busy(_fifo_slot()):return
	var early:LifeSim=app.household.member_sim(WAITER);var late:LifeSim=app.household.member_sim("housemate_1")
	var early_action:Dictionary=early.get_current_action();var late_action:Dictionary=late.get_current_action();var later:Dictionary=early.action_queue.back();var later_facts:Dictionary=later.duplicate(true)
	check(bool(app.motion_states[WAITER].waiting) and bool(app.motion_states.housemate_1.waiting) and app.motion_states[WAITER].wait_started<app.motion_states.housemate_1.wait_started,"Fresh public load preserves both original FIFO owners and order.")
	audit.initial=_busy_record();await _select_busy("player");await press("Cancel action");await _interact_busy(first_item("bookshelf"),"read")
	var minimum:float=INF;var early_started:bool=false;var late_unpaid:bool=true
	await press("▶")
	for i:int in range(250):
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();audit.steps.append(row);minimum=minf(minimum,float(row.clearance.household_minimum))
		late_unpaid=late_unpaid and not bool(late_action.paid) and late_action.elapsed==0.0
		if early_action.phase=="active" and float(early_action.elapsed)>.6:early_started=true;break
	await press("Ⅱ")
	check(early_started and app.world.actors[WAITER].position==early_action.target_position,"Fresh earlier waiter physically reaches the bed before payment and actual sleep progress.")
	check(late_unpaid and late.get_current_action()==late_action,"Fresh later waiter cannot receive early sleep or steal FIFO ownership.")
	check(is_same(early.action_queue.back(),later) and later==later_facts,"The saved later explicit reading action remains exact through the first turn.")
	audit.first_turn=_busy_record();await _select_busy(WAITER);await press("Cancel action")
	check(is_same(early.get_current_action(),later) and later.id=="read" and later.target_id==later_facts.target_id and later.elapsed==0.0 and not bool(later.paid),"Public cancellation releases the first bed turn and starts the preserved later reading approach.")
	var second_started:bool=false;await press("▶")
	for i:int in range(900):
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();audit.steps.append(row);minimum=minf(minimum,float(row.clearance.household_minimum))
		if late_action.phase=="active" and float(late_action.elapsed)>.6:second_started=true;break
	await press("Ⅱ")
	check(second_started and late.get_current_action()==late_action and app.world.actors.housemate_1.position==late_action.target_position,"The second saved waiter physically reaches the bed and starts its own turn after the first releases it.")
	check(minimum>=LifeTraversal.BODY_GAP-.000001,"Both fresh physical turns preserve household-versus-visible body clearance.")
	audit.final=_busy_record();audit.minimum_clearance=minimum
func _witness_negative()->void:
	if not await _load_busy(_fifo_slot()):return
	await _select_busy("housemate_1")
	var action:Dictionary=app.sim.get_current_action();var peer:LifeSim=app.household.member_sim(WAITER);var peer_action:Dictionary=peer.get_current_action();var motion:Dictionary=app.motion_states[WAITER];var original_motion:Dictionary=motion.duplicate();var body:Vector3=app.player.position;var before:Dictionary=_busy_record()
	audit.initial=before;audit.scope="Declared component changes exercise witness guards without advancing the genuine saved household. Original fields restored exactly."
	check(app._near_arrived_resource_waiter(action,0),"The genuine saved around-corner pair has a supported <=1m same-resource witness.")
	check(app._wait_position_clear(body,true),"An exact physically clear arrived queue body retains its legitimate point.")
	check(not app._wait_position_clear(body),"The ordinary new-position rule retains its original wider spacing and padding.")
	check(not app._wait_position_clear(body+Vector3(.001,0,0),true),"An off-body destination cannot use the retained-arrived exemption.")

	motion.wait_destination+=Vector3(.5,0,0);check(not app._near_arrived_resource_waiter(action,0),"An in-flight peer whose body has not reached its reservation cannot grant proximity.");motion.wait_destination=original_motion.wait_destination
	motion.wait_started=-1;check(not app._near_arrived_resource_waiter(action,0),"A peer without an actual arrived FIFO timestamp cannot grant proximity.");motion.wait_started=original_motion.wait_started
	motion.pending=peer_action.duplicate(true);check(not app._near_arrived_resource_waiter(action,0),"A replacement instruction cannot inherit old peer ownership merely by equal fields.");motion.pending=original_motion.pending
	peer_action.cooperation_id="component_cooperation";check(not app._near_arrived_resource_waiter(action,0),"A cooperative peer cannot grant an ordinary furnishing queue.");peer_action.erase("cooperation_id")
	var target:String=peer_action.target_id;peer_action.target_id="item_14";check(not app._near_arrived_resource_waiter(action,0),"A nearby waiter for a different actual furnishing does not share this queue.");peer_action.target_id=target
	motion.resume_active=true;check(not app._near_arrived_resource_waiter(action,0),"A saved paid owner resuming activity is excluded as an arrived queue peer.");motion.resume_active=original_motion.resume_active
	for donor:String in [WAITER,"player"]:
		app.traversal.routes[donor]={"phase":"route","safety":false,"courtesy":{"beneficiary_id":"player" if donor==WAITER else WAITER}}
		check(not app._near_arrived_resource_waiter(action,0),"An active courtesy "+("donor" if donor==WAITER else "beneficiary")+" cannot witness ordinary resource admission.")
		app.traversal.routes.erase(donor)
	app.player.position=Vector3(1.5,.16,.75)
	var occupied:Array[Vector3]=app.traversal._occupied("housemate_1");occupied.erase(app.world.actors[WAITER].position)
	var long_route:Dictionary=app.world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(0,app.player.position),LifeLotNavigation.floor_location(0,app.world.actors[WAITER].position),occupied,LifeTraversal.ROUTE_CLEARANCE)
	check(app.player.position.distance_to(app.world.actors[WAITER].position)<=1 and bool(long_route.ok) and float(long_route.distance)>1 and not app._near_arrived_resource_waiter(action,0),"A Euclidean-near caller with a supported route longer than1m cannot claim nearby queue access.")
	audit.long_route=long_route;app.player.position=body

	app.player.position=Vector3(1.25,.16,.75)
	check(app.player.position.distance_to(app.world.actors[WAITER].position)>1 and not app._near_arrived_resource_waiter(action,0),"A caller farther than1m cannot use a longer queue witness.");app.player.position=body
	check(not app._near_arrived_resource_waiter(action,1),"An other-floor witness request cannot use this Ground-floor queue.")
	var third:Dictionary=app.motion_states.housemate_2;var third_original:Dictionary=third.duplicate()
	third.waiting=true;third.wait_destination=body;third.wait_started=_now()-1
	check(not app._near_arrived_resource_waiter(action,0),"An earlier third resource reservation at the proposed held body refuses admission.")
	check(not app._wait_position_clear(body,true),"A retained arrived body still respects an earlier foreign unarrived reservation.")
	third.assign(third_original)
	var other_body:Vector3=app.world.actors.housemate_2.position;app.world.actors.housemate_2.position=Vector3(1.5,.16,1.25)
	check(not app._near_arrived_resource_waiter(action,0),"Another visible body closing the only short corner route is retained as an obstacle.");app.world.actors.housemate_2.position=other_body
	check(before==_busy_record(),"All witness guard controls restore exact bodies, timers, actions, funds and custody.")
	audit.final=_busy_record()

func _build_target_mutation()->void:
	for operation:String in ["move","sell"]:
		if not await _load_busy(_fifo_slot()):return
		var before:Dictionary=_busy_record();var early:LifeSim=app.household.member_sim(WAITER);var later:Dictionary=early.action_queue.back();var later_facts:Dictionary=later.duplicate(true)
		audit[operation+"_initial"]=before
		await press("Build & buy");await press("Ground")
		var bed:Dictionary=app._find_item("item_16");var original_position:Vector3=bed.node.position;app.show_build_object(bed,Vector2(760,350))
		if operation=="sell":await press("Sell  +ℒ%d"%int(LifeCatalog.ITEMS.bed.price*.7))
		else:
			await press("Move furnishing")
			if not app.pending_move.is_empty():
				var placed:bool=false
				for point:Vector3 in [Vector3(3.5,.16,1),Vector3(4,.16,1.5),Vector3(3,.16,1.5),Vector3(3.5,.16,.5),Vector3(3.5,.16,2),Vector3(-.5,.16,-4.5)]:
					if app.world.can_place("bed",point,0):
						app.world.placement_requested.emit("bed",point,0.0);await frames(2)
						if app.pending_move.is_empty():placed=true;break
				check(placed,"A supported public destination is available for the legally lifted current bed.")
				if not placed:app.cancel_placement();await frames(2)
		var changed:bool=app._find_item("item_16").is_empty() if operation=="sell" else not app._find_item("item_16").is_empty() and app._find_item("item_16").node.position!=original_position
		audit[operation+"_changed"]=changed;audit[operation+"_notice"]=app.notice_label.text if is_instance_valid(app.notice_label) else ""
		await press("Live");_exclude_inputs();var after:Dictionary=_busy_record();audit[operation+"_after"]=after
		if changed:
			check(not bool(app.motion_states[WAITER].waiting) and app.motion_states[WAITER].wait_started<0,"Actual target "+operation+" releases stale furnishing FIFO entitlement.")
			check(early.action_queue.has(later) and later.target_id==later_facts.target_id and later.elapsed==0.0 and not bool(later.paid),"Actual target "+operation+" preserves the later explicit instruction without early progress/payment.")
			check(before.at==after.at and before.people[WAITER].position==after.people[WAITER].position,"Target "+operation+" does not teleport or advance simulation time.")
		else:check(before.waits==after.waits and before.people==after.people and before.at==after.at and before.funds==after.funds,"Refused target "+operation+" retains the exact prior queue, body, ownership, clock and funds.")
