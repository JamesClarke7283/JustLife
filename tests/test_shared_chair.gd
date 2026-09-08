extends "res://tests/test_school_presentation.gd"
## Public renderer flow: a desk and its support chair are one occupied resource.
var child_sim: LifeSim
var adult_sim: LifeSim
var desk_item: Dictionary
var support_chair: Dictionary

func _run() -> void:
	screenshot_dir = "res://art/shared_chair"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene = app
	await frames(4);app.set_sound(false)
	await _create_school_household()
	child_sim = app.household.members[0].sim;adult_sim = app.household.members[1].sim
	await press("School record",true);await press("Online classes");await press("▶")
	await wait_until(func()->bool:return active_is("school",.065),"child reaches desk before chair contention",45)
	await press("Ⅱ")
	desk_item = app._find_item(str(child_sim.get_current_action().target_id))
	support_chair = app.world.closest_item("chair",desk_item.node.to_global(Vector3(0,0,.88)),1.25)
	check(not support_chair.is_empty(),"The actual desk has a distinct supporting chair.")
	if support_chair.is_empty():_write_report();quit(1);return
	await press_member(ADULT_NAME)
	await _chair_action(support_chair)
	await press("▶")
	await _await_arrival_or_wait("adult approaches occupied support chair")
	await press("Ⅱ")
	check(_sim_active(child_sim,"school") and not _sim_active(adult_sim,"relax"),"Active desk class and separate relax on its support chair cannot overlap.")
	check(app.waiting_for_target and not adult_sim.action_queue.is_empty(),"Adult waits with chair action still queued while the child uses its desk.")
	await screenshot("21_shared_chair_waiting")
	await press_member(CHILD_NAME);await press("Cancel action")
	await press_member(ADULT_NAME);await press("▶")
	await wait_until(func()->bool:return active_is("relax",.025),"canceling class releases supporting chair",20)
	await press("Ⅱ")
	check(child_sim.action_queue.is_empty() and _sim_active(adult_sim,"relax"),"Canceling the desk activity releases the waiting chair action.")

	await press_member(CHILD_NAME);await press("School");await press("School record",true);await press("Online classes");await press("▶")
	await _await_arrival_or_wait("child approaches desk with occupied chair")
	await press("Ⅱ")
	check(_sim_active(adult_sim,"relax") and not _sim_active(child_sim,"school"),"Occupied chair also blocks a newly arriving desk action.")
	check(app.waiting_for_target,"Child visibly waits for the support chair through the desk queue.")
	await press("Cancel action")
	check(child_sim.action_queue.is_empty() and _sim_active(adult_sim,"relax"),"Canceling a waiting desk action leaves the actual chair occupant unchanged.")
	await press("School record",true);await press("Online classes");await press("▶")
	await _await_arrival_or_wait("child requeues desk behind same occupant")
	await press("Ⅱ")
	await press_member(ADULT_NAME);await press("Cancel action")
	await press_member(CHILD_NAME);await press("▶")
	await wait_until(func()->bool:return active_is("school",.025),"canceling chair occupant releases waiting desk",25)
	await press("Ⅱ")
	check(adult_sim.action_queue.is_empty() and _sim_active(child_sim,"school"),"Canceling chair use releases the preserved desk activity.")

	var other_chair: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "chair" and str(item.id) != str(support_chair.id):other_chair = item;break
	check(not other_chair.is_empty(),"A different chair is available for independent use.")
	if not other_chair.is_empty():
		await press_member(ADULT_NAME);await _chair_action(other_chair);await press("▶")
		await wait_until(func()->bool:return active_is("relax",.025),"adult uses unrelated chair while child studies",25)
		await press("Ⅱ")
		check(_sim_active(child_sim,"school") and _sim_active(adult_sim,"relax"),"Reserving a desk's chair does not block unrelated chairs.")
		await screenshot("22_independent_chair_use")
	evidence.append({"desk":desk_item.id,"support_chair":support_chair.id,"child_queue":child_sim._json_safe(child_sim.action_queue),"adult_queue":adult_sim._json_safe(adult_sim.action_queue)})
	_write_report();app.queue_free();await frames(3)
	print("SHARED_CHAIR_RESULT assertions=%d failures=%d" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _chair_action(item: Dictionary) -> void:
	var screen: Vector2 = app.world.camera.unproject_position(item.node.position+Vector3(0,.6,0))
	app.world.object_clicked.emit(item,screen);await frames(2)
	await press(str(app.sim.get_action_definition("relax").label),true)
	check(str(app.sim.get_current_action().target_id) == str(item.id),"Public object interaction queues the intended chair.")

func _sim_active(simulation: LifeSim, action_id: String) -> bool:
	var action: Dictionary = simulation.get_current_action()
	return not action.is_empty() and str(action.id) == action_id and str(action.phase) == "active"

func _await_arrival_or_wait(description: String) -> void:
	await wait_until(func()->bool:return app.waiting_for_target or (not app.sim.get_current_action().is_empty() and app.sim.get_current_action().phase == "active"),description,25)
	await frames(3)
