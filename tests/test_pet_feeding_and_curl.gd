extends SceneTree
## The public feeding queue, both authored cups, physical wall detours, a single
## fill gesture and compact cushion poses. Existing saves may omit thirst.
const Building = preload("res://scripts/building_state.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var dog_id: String = "feeding_dog"
var cat_id: String = "feeding_cat"
var bowl: Dictionary

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for n: int in count: await process_frame
func item(kind: String, id: String, at: Vector3) -> Dictionary:
	app.world.add_item({"id": id, "kind": kind, "x": at.x, "z": at.z, "rotation": 0.0, "level": 0}, false)
	return app._find_item(id)
func add_pet(id: String, species: String, at: Vector3) -> void:
	var choice: Dictionary
	var serial: int = int(app.household.pets.next_serial)
	for n: int in LifePets.candidate_count():
		var candidate: Dictionary = LifePets.candidate(serial, n)
		if str(candidate.species) == species: choice = candidate; break
	var pet: Dictionary = LifePets.record_from(choice, id, 1)
	app.household.pets.pets.append(pet)
	app.household.pets.next_serial = serial + 1
	app.spawn_pet(id, pet, at, at)
	reset_pet(id, at)
func reset_pet(id: String, at: Vector3) -> void:
	app.pet_errands.erase(id)
	app.pet_actors[id].position = at
	app.pet_actors[id].clear_behavior()
	app.pet_actors[id].clear_interaction()
	app.pet_behavior().idle_minutes[id] = -1000.0
	for need: String in LifePetCare.NEED_NAMES: app.household.pet_care(id).needs[need] = 90.0

## Measure actual visible mesh vertices in the bed's own coordinates.
func pet_bounds(pet: LifePetActor, bed: Node3D) -> AABB:
	var result := AABB()
	var first: bool = true
	for mesh: MeshInstance3D in pet._model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		for vertex: Vector3 in mesh.mesh.get_faces():
			var at: Vector3 = bed.to_local(mesh.to_global(vertex))
			if first: result = AABB(at, Vector3.ZERO); first = false
			else: result = result.expand(at)
	return result

func fits_bed(pet: LifePetActor, bed: Dictionary) -> bool:
	var bounds: AABB = pet_bounds(pet, bed.node)
	var half: Vector2 = LifeCatalog.ITEMS[str(bed.kind)].size * .5
	return bounds.position.x >= -half.x and bounds.end.x <= half.x and bounds.position.z >= -half.y and bounds.end.z <= half.y and bounds.position.y >= .12

func is_kneeling() -> bool:
	# Both tucked knees distinguish this gesture from the final walking stride.
	return app.player._joints["Shin_R"].rotation.x > .7 and app.player._joints["Shin_L"].rotation.x > .7 and app.player._joints["Leg_R"].rotation.x < -.6

func capture(label: String, at: Vector3, size: float = 3.0) -> void:
	var output: String = OS.get_environment("PET_EVIDENCE_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	app.world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	app.world.camera.size = size
	app.world.camera.global_position = at + Vector3(3.0, 2.1, 4.0)
	app.world.camera.look_at(at + Vector3(0, .35, 0))
	app.ui.visible = false
	await process_frame
	RenderingServer.force_draw(false, 0.0)
	check(root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK, "Rendered " + label)
	app.ui.visible = true

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Avery", "age_stage": "adult", "traits": [], "hair": 0}]
	app.creator_family_links = []
	app.start_household(); await frames()
	app.set_process(false); app.world.set_process(false)
	app.household.set_speed(0); app.sim.autonomy = false
	while not app.sim.action_queue.is_empty(): app.sim.cancel_action()
	for furnishing: Dictionary in app.world.items: furnishing.node.queue_free()
	app.world.items.clear(); await frames()
	var state: Dictionary = Building.fresh()
	state.walls = [{"id": "feeding_partition", "level": 0, "x": 0.0, "z": 0.0, "w": .14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"}]
	app.world.construction.restore(state)
	bowl = item("pet_bowl", "feeding_bowl", Vector3(3, .16, 0))
	var dog_bed: Dictionary = item("pet_bed_dog", "feeding_dog_bed", Vector3(-3, .16, 4))
	var cat_bed: Dictionary = item("pet_bed_cat", "feeding_cat_bed", Vector3(3, .16, 4))
	app.world.rebuild_navigation()
	add_pet(dog_id, "dog", Vector3(-3, .16, 0))
	add_pet(cat_id, "cat", Vector3(-5, .16, 4))
	app.player.position = Vector3(3, .16, 3)
	app._refresh_pet_targets()
	check(not bowl.is_empty(), "Fixture has the authored food and water tray")
	var feeding_at: Vector3 = app.care_motion().feeding_destination(dog_id, app.player.position)
	check(feeding_at.is_finite() and feeding_at.distance_to(app.pet_behavior().bowl_point(bowl)) < .85, "Feeding admits a reachable position within kneeling reach of the real cup")
	app._queue_pet_action(dog_id, "pet_feed")
	check(str(app.sim.get_current_action().get("id", "")) == "pet_feed", "The pet card's public feeding path queues the requested pet")
	app.household.set_speed(3)
	var saw_active: bool = false
	var dog_arrived: bool = false
	var detoured: bool = false
	var collision_free: bool = true
	var approach_close: bool = true
	var kneeling: bool = false
	var bends: int = 0
	var late_kneel: bool = false
	var captured_pour: bool = false
	var captured_eating: bool = false
	var last: Vector3 = app.pet_actors[dog_id].position
	for n: int in 1200:
		app._process(.05)
		var dog: LifePetActor = app.pet_actors[dog_id]
		var level: int = app.world.point_level(dog.position)
		collision_free = collision_free and level >= 0 and app.world.lot_navigation.point_clear(level, dog.position)
		if last.distance_to(dog.position) > .00001:
			collision_free = collision_free and app.world.lot_navigation.segment_clear(level, last, dog.position)
		last = dog.position
		detoured = detoured or absf(dog.position.z) > 2.1
		var current: Dictionary = app.sim.get_current_action()
		if str(current.get("id", "")) == "pet_feed" and str(current.get("phase", "")) == "active":
			saw_active = true
			approach_close = approach_close and app.player.position.distance_to(app.pet_behavior().bowl_point(bowl)) < .85
			var bent: bool = is_kneeling()
			if bent and not kneeling: bends += 1
			kneeling = bent
			if float(app.care_motion().sessions.get(app.household.selected_id(), {}).get("time", 0.0)) > 7.0: late_kneel = late_kneel or bent
			if bent and not captured_pour and float(app.care_motion().sessions.get(app.household.selected_id(), {}).get("time", 0.0)) > 2.0:
				await capture("feeding_single_pour", bowl.node.position)
				captured_pour = true
			if dog.interaction == "pet_feed":
				dog_arrived = true
				check(dog.position.distance_to(app.pet_behavior().bowl_point(bowl)) < .65, "The feeding pose begins only after the dog reaches the bowl")
				# One arrival check suffices while the same pose continues.
				break
		if current.is_empty(): break
		if n % 12 == 0: await process_frame
	# Let the whole action run, collecting the rest of its physical gesture.
	for n: int in 500:
		if app.sim.action_queue.is_empty(): break
		app._process(.05)
		var session: Dictionary = app.care_motion().sessions.get(app.household.selected_id(), {})
		if not captured_eating and bool(session.get("feed_arrived", false)) and float(session.get("time", 0.0)) - float(session.get("feed_arrived_at", 0.0)) >= .6:
			await capture("pet_at_filled_bowl", bowl.node.position)
			captured_eating = true
		var bent: bool = is_kneeling()
		if bent and not kneeling: bends += 1
		kneeling = bent
		if float(session.get("time", 0.0)) > 7.0: late_kneel = late_kneel or bent
		if n % 12 == 0: await process_frame
	check(saw_active and approach_close, "The Lifelet walks to the bowl before starting the fill")
	check(dog_arrived and detoured and collision_free, "The held dog routes around the partition and never enters its wall")
	check(bends == 1 and not late_kneel, "One feeding action bends once and remains standing after the fill (%d bends)" % bends)
	check(app.sim.action_queue.is_empty() and app.care_motion().sessions.is_empty(), "Feeding completes and releases its pair")
	await fast_feeding_once()
	app.household.set_speed(0)
	reset_pet(dog_id, Vector3(-3, .16, 0))
	var behavior: LifePetBehavior = app.pet_behavior()
	var thirsty: Dictionary = app.household.pet_care(dog_id)
	thirsty.needs.thirst = 8.0
	behavior.tick(.05, 1)
	check(str(behavior.state(dog_id).action) == "pet_drink", "A thirsty pet chooses the water cup autonomously")
	var water_reached: bool = false
	collision_free = true; detoured = false
	for n: int in 500:
		var dog: LifePetActor = app.pet_actors[dog_id]
		last = dog.position
		behavior.tick(.05, 1); dog.animate(.05, behavior.moved_ids.has(dog_id))
		collision_free = collision_free and app.world.lot_navigation.point_clear(0, dog.position) and app.world.lot_navigation.segment_clear(0, last, dog.position)
		detoured = detoured or absf(dog.position.z) > 2.1
		if str(behavior.state(dog_id).phase) == "using": water_reached = true; break
	check(water_reached and detoured and collision_free, "The autonomous drink route also goes around the wall")
	behavior.tick(.2, 1)
	check(app.pet_actors[dog_id].behavior == "drink" and float(thirsty.needs.thirst) > 8.0 and app.pet_actors[dog_id].position.distance_to(behavior.bowl_point(bowl, true)) < .65, "Water restores thirst only at the actual water cup")
	var old_care: Dictionary = LifePetCare.fresh()
	old_care.needs.erase("thirst")
	check(LifePetCare.validate(old_care, []).is_empty(), "Care records written before thirst remain readable")
	LifePetCare.tick(old_care, 1.0)
	check(float(old_care.needs.thirst) > 79.0, "An old care record gains a healthy default thirst when its clock runs")
	for pair: Array in [[dog_id, dog_bed, Vector3(-3, .16, 6)], [cat_id, cat_bed, Vector3(3, .16, 6)]]:
		var id: String = pair[0]
		reset_pet(id, pair[2])
		check(bool(behavior.command(id, "pet_go_bed").ok), "The %s accepts its cushion" % app.pet_actors[id].species)
		for n: int in 600:
			behavior.tick(.05, 1)
			app.pet_actors[id].animate(.05, behavior.moved_ids.has(id))
			if str(behavior.state(id).phase) == "using": break
		for n: int in 30:
			behavior.tick(.05, 1); app.pet_actors[id].animate(.05, false)
		var pet: LifePetActor = app.pet_actors[id]
		var bed: Dictionary = pair[1]
		var bounds: AABB = pet_bounds(pet, bed.node)
		var fits: bool = fits_bed(pet, bed)
		check(pet.resting_on_cushion and fits and pet._head.rotation.y > 1.3, "The %s curls with every visible mesh inside its cushioned bed and above its base (%s)" % [pet.species, bounds])
		for length: String in LifePets.COAT_LENGTHS:
			var appearance: Dictionary = pet.coat.duplicate(true)
			appearance.coat_length = length
			pet.configure(pet.pet_id, pet.species, appearance, pet.display_name, pet.sex)
			pet.set_behavior("rest", 16.5, true)
			for n: int in 50: pet.animate(.05, false)
			check(fits_bed(pet, bed), "Every visible mesh of the %s %s coat fits the cushion (%s)" % [pet.species, length, pet_bounds(pet, bed.node)])
		await capture(pet.species + "_curled_bed", bed.node.position, 1.5)
		behavior.command(id, "pet_stop_playing")
		for n: int in 100:
			behavior.tick(.05, 1); pet.animate(.05, behavior.moved_ids.has(id))
			if str(behavior.state(id).phase) == "idle": break
		for n: int in 30: pet.animate(.05, false)
		check(not pet.resting_on_cushion and pet._body.scale.distance_to(Vector3.ONE) < .01 and pet._head.position.distance_to(pet._feature_rest[pet._head.name].position) < .01, "The %s returns to its original proportions after leaving bed" % pet.species)
	blocked_access_exit(cat_bed)
	app.world.remove_item(str(bowl.id)); app.world.rebuild_navigation()
	check(not app.care_motion().feeding_destination(dog_id, app.player.position).is_finite(), "A missing bowl cannot produce a floor-feeding fallback")
	await feeding_stair_cancellation()
	await blocked_stair_arrival()
	app.queue_free(); await frames()
	print("PET_FEEDING_CURL %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fast_feeding_once() -> void:
	app.household.set_speed(0)
	var at: Vector3 = app.pet_behavior().bowl_approach(dog_id, bowl, app.pet_actors[dog_id].position, false, app.player.position)
	reset_pet(dog_id, at)
	app._queue_pet_action(dog_id, "pet_feed")
	app.household.set_speed(8)
	var bends: int = 0
	var kneeling: bool = false
	var clock: float = 0.0
	for n: int in 300:
		app._process(.05)
		var bent: bool = is_kneeling()
		if bent and not kneeling: bends += 1
		kneeling = bent
		clock = maxf(clock, float(app.care_motion().sessions.get(app.household.selected_id(), {}).get("time", 0.0)))
		if app.sim.action_queue.is_empty(): break
	check(bends == 1 and clock >= 5.8 and not is_kneeling() and app.sim.action_queue.is_empty(), "Fast-forward feeding beside the bowl completes its single fill and stands up before finishing")
	app.household.set_speed(0)

func blocked_access_exit(bed: Dictionary) -> void:
	var pet: LifePetActor = app.pet_actors[cat_id]
	reset_pet(cat_id, bed.node.position + Vector3(2, 0, 0))
	app.player.position = bed.node.position + Vector3(0, 0, -.6)
	check(bool(app.pet_behavior().command(cat_id, "pet_go_bed").ok), "A bed with clear floor beside it admits its normal approach")
	var entered: bool = false
	var backed_out: bool = false
	var continuous: bool = true
	for n: int in 500:
		var before: Vector3 = pet.position
		app.pet_behavior().tick(.05, 1)
		var errand: Dictionary = app.pet_errands.get(cat_id, {})
		entered = entered or str(errand.get("phase", "")) == "entering"
		backed_out = backed_out or str(errand.get("phase", "")) == "exiting"
		continuous = continuous and before.distance_to(pet.position) <= .071
		if entered and errand.is_empty(): break
	check(entered and backed_out and continuous and app.world.lot_navigation.point_clear(app.world.point_level(pet.position), pet.position), "A blocked furnishing entry walks back out onto supported floor without stranding or teleporting the pet")

func feeding_stair_cancellation() -> void:
	var state: Dictionary = Building.fresh()
	state.floors = [{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	for level: int in [0, 1]:
		for side: int in [-1, 1]:
			state.walls.append({"id":("upper_" if level else "")+("north" if side<0 else "south"),"level":level,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	var stairs: Dictionary = Building.propose(state, {"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}}, 10000)
	check(bool(stairs.ok), "Feeding across floors uses a supported authored staircase")
	if not bool(stairs.ok): return
	app.world.construction.restore(stairs.after)
	app.world.add_item({"id":"upper_feeding_bowl","kind":"pet_bowl","x":2.0,"z":3.0,"rotation":0.0,"level":1}, false)
	app.world.rebuild_navigation()
	reset_pet(dog_id, Vector3(-2, .16, -2))
	reset_pet(cat_id, Vector3(-4.5, .16, 4))
	app.player.position = Vector3(2, 3.16, 1.5)
	app._refresh_pet_targets()
	app._queue_pet_action(dog_id, "pet_feed")
	app.household.set_speed(3)
	var entered_stairs: bool = false
	for n: int in 500:
		app._process(.05)
		if app.world.point_level(app.pet_actors[dog_id].position) < 0:
			entered_stairs = true; break
		if app.sim.get_current_action().is_empty(): break
		if n % 12 == 0: await process_frame
	check(entered_stairs, "The paired feeding route walks the pet onto the real staircase")
	if not entered_stairs: return
	var dog: LifePetActor = app.pet_actors[dog_id]
	var before: Vector3 = dog.position
	app.cancel_current_action()
	app.care_motion().present_pets(0.0)
	check(dog.position == before and str(app.pet_errands.get(dog_id, {}).get("phase", "")) == "walking", "Canceling feeding retains the pet's physical route to a landing without teleporting")
	var retained: Dictionary = app.pet_errands.get(dog_id, {})
	var landing: Vector3 = retained.get("at", Vector3.INF)
	check(app.world.lot_navigation.point_clear(app.world.point_level(landing), landing) and retained.segments[0].from == dog.position, "The retained flight ends on clear supported floor and begins at the canceled pet position")
	app.household.set_speed(0)
	app.overlay_open = true
	var saved: bool = app.save_game("", "Canceled pet feeding on stairs")
	if not saved: print("SAVE_DIAGNOSTIC ", app.notice_text)
	check(saved, "A public save accepts feeding canceled while the pet is between floors")
	var slot: String = app.active_save_id
	check(bool(LifeSaveLibrary.read_slot(slot).get("ok", false)), "The saved household passes detached validation")
	app.overlay_open = false
	var lower := Vector3(-2, .16, -2)
	var result: Dictionary = app.pet_behavior().command(dog_id, "pet_move", lower)
	check(bool(result.ok) and app.pet_errands.get(dog_id, {}).has("pending_command"), "A replacement command waits until the canceled care route reaches its landing")
	var continuous: bool = true
	for n: int in 1400:
		before = dog.position
		app.pet_behavior().tick(.05, 1.0)
		continuous = continuous and before.distance_to(dog.position) <= .071
		if dog.position.distance_to(lower) < .01: break
	check(continuous and dog.position.distance_to(lower) < .01 and not dog.traversing_stairs, "The pet reaches a landing, follows its replacement and returns downstairs continuously")
	app.load_game(slot)
	await frames(3)
	var restored: LifePetActor = app.pet_actors.get(dog_id)
	check(is_instance_valid(restored) and app.world.lot_navigation.point_clear(app.world.point_level(restored.position), restored.position) and not restored.traversing_stairs, "Loading the canceled feeding save rebuilds the pet on clear supported floor")

func blocked_stair_arrival() -> void:
	app.household.set_speed(0)
	app.pet_errands.clear()
	app.player.position = Vector3(-4.5, .16, 4)
	var record: Dictionary = app.household.pet_record(dog_id)
	var previous: LifePetActor = app.pet_actors[dog_id]
	app.pet_actors.erase(dog_id); previous.queue_free(); await frames()
	var destination := Vector3(2, 3.16, 1.5)
	var dog: LifePetActor = app.spawn_pet(dog_id, record, Vector3(-2, .16, -2), destination)
	var arrival: Dictionary = app.pet_arrivals.get(dog_id, {})
	var landing := Vector3.INF
	for segment: Dictionary in arrival.get("segments", []):
		if str(segment.kind) == "stair" and app.world.point_level(segment.to) == 1: landing = segment.to
	check(landing.is_finite(), "A public cross-floor spawn retains its physical upper stair landing")
	if not landing.is_finite(): return
	app.household.set_speed(3)
	var near_top: bool = false
	for step: int in 400:
		app.world.construction.doors.tick(.15)
		app._advance_pet_arrivals(.05)
		if dog.traversing_stairs and app.world.point_level(dog.position) < 0 and dog.position.y > 2.5:
			near_top = true; break
	check(near_top, "The arriving pet physically climbs close to the upper landing")
	if not near_top: return
	# A person really stands on supported upper floor, preventing the final
	# treads from closing the body gap until they step aside.
	app.player.position = landing
	for step: int in 8: app._advance_pet_arrivals(.05)
	var held_at: Vector3 = dog.position
	var unchanged: bool = true
	for step: int in 80:
		app._advance_pet_arrivals(.05)
		unchanged = unchanged and dog.position == held_at
	check(unchanged and app.pet_arrivals.has(dog_id) and dog.traversing_stairs and app.world.point_level(dog.position) < 0, "A blocked stair-arrival timeout retains the exact supported flight without teleporting the pet")
	app.player.position = Vector3(-4.5, .16, 4)
	var continuous: bool = true
	for step: int in 600:
		var before: Vector3 = dog.position
		app._advance_pet_arrivals(.05)
		continuous = continuous and before.distance_to(dog.position) <= .331
		if not app.pet_arrivals.has(dog_id): break
	check(continuous and not app.pet_arrivals.has(dog_id) and not dog.traversing_stairs and dog.position.distance_to(destination) < .01 and app.world.lot_navigation.point_clear(1, dog.position), "Once the upper landing clears, the arrival resumes continuously to supported upstairs floor")
	app.household.set_speed(0)
