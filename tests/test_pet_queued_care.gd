extends SceneTree
## A pet may start resting while its owner's requested care waits behind a
## different activity. Starting that care must safely bring the animal out.

var app: Node
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Run with an isolated absolute JUSTLIFE_DATA_DIR."); quit(2); return
	_run.call_deferred()

func frames(count: int = 2) -> void:
	for index: int in count: await process_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func step() -> void:
	app._process(.1)
	await process_frame

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Avery", "age_stage": "adult", "traits": [], "hair": 0}]
	app.creator_family_links = []
	app.start_household(); await frames(3)
	app.household.set_speed(0); app.set_process(false)
	app.sim.autonomy = false
	while not app.sim.action_queue.is_empty(): app.sim.cancel_action()
	app.queue_nearest("bookshelf", "read")
	app.household.set_speed(3)
	for index: int in 1800:
		await step()
		if float(app.sim.get_current_action().get("elapsed", 0.0)) >= 30.0: break
	check(str(app.sim.get_current_action().get("id", "")) == "read" and float(app.sim.get_current_action().get("elapsed", 0.0)) >= 30.0, "The Lifelet is reading, with thirty minutes remaining.")
	app.household.set_speed(0)
	var choice: int = 0
	for index: int in LifePets.candidate_count():
		if str(LifePets.candidate(1, index).species) == "dog": choice = index; break
	var draft: Dictionary = LifePets.candidate(1, choice); draft.name = "Rex"
	var prepared: Dictionary = app.household.prepare_pet(draft)
	var spot := Vector3(-8, .16, 4.3)
	var committed: Dictionary = app.household.commit_pet(prepared.get("request", {}), spot)
	check(bool(committed.get("ok", false)), "A dog joins the household.")
	if not bool(committed.get("ok", false)): quit(1); return
	var pet_id: String = str(committed.pet.id)
	var dog: LifePetActor = app.spawn_pet(pet_id, committed.pet, spot, spot)
	app.world.add_item({"id": "queued_care_bed", "kind": "pet_bed_dog", "x": -8.0, "z": 2.5, "level": 0, "rotation": 0.0}, false)
	app.world.rebuild_navigation()
	# Select the natural rest turn; no pet need, action duration or clock is set.
	app.pet_behavior().turns[pet_id] = 3
	app._queue_pet_action(pet_id, "pet_pet")
	check(app.sim.action_queue.size() == 2 and str(app.sim.action_queue[1].id) == "pet_pet", "Petting waits behind the current read.")
	var queued_care: Dictionary = app.sim.action_queue[1]
	var member_id: String = app.household.selected_id()
	var before: float = LifePetCare.bond(app.household.pet_care(pet_id), member_id)
	var saw_rest: bool = false
	var saw_exit: bool = false
	var saw_care: bool = false
	var safe_care: bool = true
	var retained_instruction: bool = false
	var last_phase: String = ""
	app.household.set_speed(3)
	for index: int in 1000:
		await step()
		var state: Dictionary = app.pet_behavior().state(pet_id)
		var current: Dictionary = app.sim.get_current_action()
		var phase: String = str(state.phase) + "/" + str(current.get("id", "idle")) + "/" + str(current.get("phase", ""))
		if phase != last_phase:
			print("PET_QUEUED_STAGE ", JSON.stringify({"phase": phase, "pet": str(dog.position), "person": str(app.player.position), "target": str(current.get("target_position", Vector3.ZERO)), "bond": LifePetCare.bond(app.household.pet_care(pet_id), member_id)}))
			last_phase = phase
		if str(app.sim.get_current_action().get("id", "")) == "read" and str(state.action) == "pet_go_bed" and str(state.phase) == "using": saw_rest = true
		if str(state.phase) == "exiting" and saw_rest: saw_exit = true
		if app.care_motion().exit_waits.has(member_id):
			retained_instruction = is_same(app.care_motion().exit_waits[member_id].action, queued_care)
		if dog.interaction == "pet_pet":
			saw_care = true
			safe_care = safe_care and app.world.point_level(dog.position) == 0 and app._pet_errand(pet_id).is_empty() and Vector3(queued_care.target_position).is_finite()
		if app.sim.action_queue.is_empty(): break
	print("PET_QUEUED_FIRST_RESULT ", JSON.stringify({"paired": saw_care, "safe": safe_care, "before": before, "bond": LifePetCare.bond(app.household.pet_care(pet_id), member_id), "routes": app.route_failures}))
	check(saw_rest, "The dog autonomously rests before the queued care begins.")
	check(saw_exit, "The queued care lets the dog step out of its bed.")
	check(retained_instruction, "The exit wait retains the original queued instruction.")
	check(saw_care and safe_care and LifePetCare.bond(app.household.pet_care(pet_id), member_id) > before, "The same queued petting starts on clear floor and completes after the dog steps down.")
	check(app.pending_pet_care.is_empty() and app.care_motion().exit_waits.is_empty() and not app.care_motion().holds(pet_id), "Completion releases the pet and clears pending care.")
	# Repeat the transition and cancel while the animal steps down. Starting
	# the autonomous bed errand directly keeps this cancellation fixture bounded
	# without changing any need, clock, or activity duration.
	if saw_exit:
		app.household.set_speed(0)
		app.pet_behavior().command(pet_id, "pet_stop_playing")
		app.queue_nearest("bookshelf", "read")
		app.household.set_speed(3)
		for index: int in 1000:
			await step()
			if float(app.sim.get_current_action().get("elapsed", 0.0)) >= 40.0: break
		app.household.set_speed(0)
		app.pet_behavior().command(pet_id, "pet_stop_playing")
		app._queue_pet_action(pet_id, "pet_pet")
		check(app.pet_behavior()._start(pet_id, "pet_go_bed", false), "The cancellation fixture starts an autonomous bed errand.")
		app.household.set_speed(3)
		for index: int in 500:
			await step()
			if app.care_motion().exit_waits.has(member_id) or app.sim.action_queue.is_empty(): break
		check(app.care_motion().exit_waits.has(member_id), "The second care request waits while the dog steps down.")
		var cancel_bond: float = LifePetCare.bond(app.household.pet_care(pet_id), member_id)
		app.cancel_current_action()
		for index: int in 50: await step()
		check(app.sim.action_queue.is_empty() and app.care_motion().exit_waits.is_empty() and is_equal_approx(LifePetCare.bond(app.household.pet_care(pet_id), member_id), cancel_bond), "Canceling during the exit never resurrects or credits the care action.")
	print("PET_QUEUED_CARE_STATE ", JSON.stringify({"dog": str(dog.position), "state": app.pet_behavior().state(pet_id), "queue": app.sim.action_queue, "routes": app.route_failures}))
	app.queue_free(); await frames()
	print("PET_QUEUED_CARE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
