extends SceneTree
## Exercise the real Lifelet -> dog -> care button path, including approach,
## pet autonomy, paired poses, and completion credit to the chosen person.

var app: Node
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Run with an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
	_run.call_deferred()

func frames(count: int = 2) -> void:
	for index: int in count: await process_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func care_button(label: String) -> Button:
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node is Button and node.text == label: return node
	return null

func click_button(button: Button) -> void:
	var scroll: ScrollContainer = app.overlay.find_child("PetCommands", true, false)
	scroll.ensure_control_visible(button)
	await frames()
	var at: Vector2 = button.get_global_transform_with_canvas() * (button.size * .5)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at; event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event, true)
		await frames()

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames()
	app.set_sound(false)
	app.household_profiles = [
		{"name": "Avery", "age_stage": "adult", "traits": [], "hair": 0},
		{"name": "River", "age_stage": "adult", "traits": [], "hair": 0}]
	app.creator_family_links = []
	app.start_household(); await frames(3)
	app.household.set_speed(0)
	app.set_process(false)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		while not member.sim.action_queue.is_empty(): member.sim.cancel_action()
	var choice: int = 0
	for index: int in LifePets.candidate_count():
		if str(LifePets.candidate(1, index).species) == "dog": choice = index; break
	var draft: Dictionary = LifePets.candidate(1, choice); draft.name = "Rex"
	var prepared: Dictionary = app.household.prepare_pet(draft)
	var home: Vector3 = app.pet_home_spot()
	var committed: Dictionary = app.household.commit_pet(prepared.get("request", {}), home)
	check(bool(committed.get("ok", false)), "A dog joins the household.")
	if not bool(committed.get("ok", false)): quit(1); return
	var pet_id: String = str(committed.pet.id)
	var dog: LifePetActor = app.spawn_pet(pet_id, committed.pet, home, home)
	app.select_household_member(1)
	var member_id: String = app.household.selected_id()
	var member: LifeSim = app.household.member_sim(member_id)
	var first_id: String = str(app.household.members[0].id)
	var bond_before: float = LifePetCare.bond(app.household.pet_care(pet_id), member_id)
	app.on_object_clicked(app.world.pick_extras[pet_id], Vector2(850, 380))
	await frames()
	var play: Button = care_button("Play with the Dog")
	check(is_instance_valid(play) and not play.disabled, "The dog's card offers an enabled play action for the selected Lifelet.")
	if not is_instance_valid(play): app.queue_free(); await frames(); quit(1); return
	await click_button(play)
	check(str(member.get_current_action().get("id", "")) == "pet_play", "Pressing the actual card button queues play for the selected Lifelet.")
	check(str(member.get_current_action().get("target_id", "")) == pet_id, "The clicked dog remains the interaction target.")
	check(app.care_motion().holds(pet_id), "The dog is reserved while its Lifelet approaches.")
	var saw_paired_pose: bool = false
	app.household.set_speed(3)
	for step: int in 1600:
		app._process(.05)
		if str(dog.interaction) == "pet_play": saw_paired_pose = true
		if step % 10 == 0: await process_frame
		if member.get_current_action().is_empty(): break
	check(saw_paired_pose, "Playing starts a visible paired interaction with the dog.")
	check(LifePetCare.bond(app.household.pet_care(pet_id), member_id) > bond_before, "The interaction completes and improves the selected Lifelet's bond.")
	check(is_equal_approx(LifePetCare.bond(app.household.pet_care(pet_id), first_id), 0.0), "The unselected Lifelet receives no interaction credit.")

	# The old unconditional +Z approach landed inside a furnishing. A real
	# mouse click must choose the reachable side and finish the interaction.
	app.household.set_speed(0)
	app.pet_behavior().command(pet_id, "pet_stop_playing")
	dog.position = Vector3(-8, .16, 4.3)
	app.player.position = Vector3(-6, .16, 4.3)
	app.world.add_item({"id": "pet_approach_blocker", "kind": "sofa", "x": -8.0, "z": 5.5, "level": 0, "rotation": 0.0}, false)
	app.world.rebuild_navigation()
	check(not app.world.lot_navigation.point_clear(0, dog.position + Vector3(0, 0, .8)), "A sofa blocks the formerly fixed pet approach point.")
	app.on_object_clicked(app.world.pick_extras[pet_id], Vector2(850, 380))
	await frames()
	var stroke: Button = care_button("Pet")
	await click_button(stroke)
	var pet_action: Dictionary = member.get_current_action()
	check(str(pet_action.get("id", "")) == "pet_pet" and app.world.lot_navigation.point_clear(0, pet_action.get("target_position", Vector3.INF)), "The clicked care button chooses clear floor beside the dog.")
	var second_bond: float = LifePetCare.bond(app.household.pet_care(pet_id), member_id)
	app.household.set_speed(3)
	for step: int in 800:
		app._process(.05)
		if step % 10 == 0: await process_frame
		if member.get_current_action().is_empty(): break
	check(LifePetCare.bond(app.household.pet_care(pet_id), member_id) > second_bond, "Petting completes from the accessible side of the sofa.")

	# All care is interruptible by an explicit pet movement command, including
	# the bath action which is defined outside LifePetCare.INTERACTIONS.
	app.household.set_speed(0)
	app.household.pet_care(pet_id).needs.hygiene = 20.0
	app._queue_pet_action(pet_id, "bathe_pet")
	check(app.care_motion().holds(pet_id), "A queued bath reserves the dog.")
	var move_result: Dictionary = app.pet_behavior().command(pet_id, "pet_move", Vector3(-10, .16, 4.3))
	check(bool(move_result.get("ok", false)) and member.get_current_action().is_empty() and not app.care_motion().holds(pet_id), "An explicit pet move cancels the bath and releases the dog.")
	app.queue_free(); await frames()
	print("PET_MENU_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
