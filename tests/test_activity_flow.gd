extends "res://tests/test_busy_resources.gd"
## Public occupied-furnishing recovery. Run through run_activity_flow.py.
const EASEL_SLOT="life_1788966286736_90579531"
var native_focus_guard:LineEdit
func _run()->void:
	await _start_activity("natural")
	await _natural_owner()
	await _finish()
func _start_activity(default_phase:String)->void:
	test_phase=default_phase
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):test_phase=arg.trim_prefix("--phase=")
	phase_tag=test_phase;screenshot_dir="res://evidence";root.size=Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	node_added.connect(_disable_node_input)
	native_focus_guard=LineEdit.new();native_focus_guard.position=Vector2(-9000,-9000);root.add_child(native_focus_guard)
	app=MainScene.instantiate();root.add_child(app);current_scene=app;_exclude_inputs()
	await frames(4);app.set_sound(false);audit.scenario=test_phase
func _activity_observed_row(_index:int)->bool:
	return false
func frames(count:int=2)->void:
	for i:int in range(count):
		if is_instance_valid(app):_exclude_inputs()
		await process_frame
		if is_instance_valid(app):_exclude_inputs()
func _natural_owner()->void:
	if not await _load_busy(EASEL_SLOT):return
	var id:String="housemate_1";var owner:String="housemate_2"
	var sim:LifeSim=app.household.member_sim(id);var original:Dictionary=sim.get_current_action();var original_facts:Dictionary=original.duplicate(true)
	var other:LifeSim=app.household.member_sim(owner);var owned_action:Dictionary=other.get_current_action()
	var origin:Vector3=app.world.actors[id].position
	var later:Dictionary=app.household.member_sim("player").action_queue.back();var later_facts:Dictionary=later.duplicate(true)
	check(original.id=="paint" and original.phase=="approach" and not original.paid and float(original.elapsed)==0.0 and bool(original.autonomous),"Actual Ellis unpaid autonomous paint approach is unchanged.")
	check(other.get_current_action().id=="paint" and other.get_current_action().phase=="active" and app.world.actors[owner].position==original.target_position,"Morgan actually occupies the same requested easel anchor.")
	check(later.id=="cook" and later.phase=="queued" and not bool(later.autonomous),"Original later explicit Rowan cooking instruction is present before continuation.")
	audit.initial=_busy_record()
	app.household.member_action_finished.connect(func(member_id:String,a:Dictionary):audit.completions.append({"id":member_id,"action":a.duplicate(true),"body":app.world.actors[member_id].position,"at":_now()}))
	var first_wait:float=-1.0;var changed_at:float=-1.0;var waiting_preserved:bool=true;var queued_preserved:bool=true;var no_early:bool=true;var minimum:float=INF
	var clear_id:int=-1;var clear_destination:Vector3=Vector3.INF;var clear_finished:bool=false;var moved:bool=false;var completed:bool=false
	var deadline:int=Time.get_ticks_msec()+120000
	# The shared clock is one game minute per second. This continuation was
	# written when it was six, so normal speed no longer reaches a finished
	# canvas inside 600 steps. Very fast speed restores that game-time budget.
	# Natural and the observation producer share the first107 advancing calls;
	# both must run at very-fast so the producer's frozen prefix matches.
	await press("▶▶▶" if test_phase in ["natural","produce"] else "▶")

	for i:int in range(600):
		if Time.get_ticks_msec()>=deadline:check(false,"Declared120s continuation wall cap is not exhausted.");break
		_exclude_inputs();app._process(.05);await frames(1)
		var row:Dictionary=_busy_record();row.step=i;row.clearance=_clearance_pairs();row.routes=app.traversal.routes.duplicate(true);audit.steps.append(row)
		minimum=minf(minimum,float(row.clearance.all_minimum))
		var current:Dictionary=sim.get_current_action();var motion:Dictionary=app.motion_states[id]
		if bool(motion.waiting) and is_same(current,original):
			if first_wait<0:
				first_wait=float(motion.wait_started);audit.first_wait=row.duplicate(true)
				check(original==original_facts,"Actual nearby admission leaves the complete original unpaid instruction unchanged.")
			waiting_preserved=waiting_preserved and current==original_facts
			no_early=no_early and not current.paid and float(current.elapsed)==0.0 and float(current.progress)==0.0
		if not is_same(current,original) and changed_at<0:changed_at=_now()
		var player_queue:Array=app.household.member_sim("player").action_queue
		if player_queue.has(later) and player_queue.find(later)>0:queued_preserved=queued_preserved and later==later_facts
		if app.world.actors[id].position.distance_to(origin)>.1:moved=true
		if not is_same(other.get_current_action(),owned_action) and clear_id<0 and other.action_queue.is_empty() and bool(app.motion_states[owner].walk) and app.traversal.routes.has(owner):
			clear_id=int(app.traversal.routes[owner].identity);clear_destination=app.traversal.routes[owner].destination;audit.owner_clearing_started=row.duplicate(true)
		if clear_id>=0 and (not app.traversal.routes.has(owner) or int(app.traversal.routes[owner].identity)!=clear_id) and app.world.actors[owner].position==clear_destination:clear_finished=true;audit.owner_clearing_finished=row.duplicate(true)
		completed=audit.completions.any(func(e:Dictionary)->bool:return str(e.id)==id)
		if await _activity_observed_row(i):return
		if first_wait>=0 and completed and clear_finished:break
	await press("Ⅱ")
	check(first_wait>=0,"Ellis naturally enters the real furnishing queue from supported curved access.")
	check(waiting_preserved and no_early,"While waiting the original instruction retains exact identity fields and unpaid zero progress.")
	check(changed_at<0 or changed_at>=first_wait+30.0,"Any autonomous replacement occurs only after the existing30-minute queue policy.")
	check(moved and completed,"Unchanged autonomy reaches and completes an actual useful activity after admission.")
	check(clear_id>=0 and clear_finished,"Morgan finishes painting and physically completes the subsequent original clearing walk.")
	check(queued_preserved,"Later explicit cooking instruction remains exact while it is queued.")
	check(minimum>=LifeTraversal.BODY_GAP-.000001,"All visible body pairs retain the existing.72m clearance through this continuation.")
	check(app.active_save_id==EASEL_SLOT,"No-save continuation retains the loaded slot and performs no save-induced recovery.")
	audit.first_wait_at=first_wait;audit.changed_at=changed_at;audit.minimum_clearance=minimum;audit.owner_clear_id=clear_id;audit.owner_clear_destination=clear_destination;audit.final=_busy_record();audit.courtesy=app.traversal.courtesy.trace.duplicate(true)
func _disable_node_input(node:Node)->void:
	node.set_process_input(false);node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false);node.set_process_shortcut_input(false)
func _exclude_inputs()->void:
	super._exclude_inputs()
	if is_instance_valid(native_focus_guard):native_focus_guard.grab_focus()
func _input_excluded()->bool:
	if not root.gui_disable_input or not root.gui_get_focus_owner() is LineEdit:return false
	for node:Node in [app]+app.find_children("*","Node",true,false):
		if node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input() or node.is_processing_shortcut_input():return false
	return not app.is_processing() and not app.world.is_processing()
