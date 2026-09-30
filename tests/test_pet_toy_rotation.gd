extends SceneTree
## Model controls plus an optional public legacy-load regression. Full turns
## accrued by an animated toy must never invalidate the household's whole home.
var app: Node
var checks: int = 0
var failures: int = 0
var public_load_complete: bool = false

func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures += 1

func frames(count: int = 2) -> void:
	for i: int in count: await process_frame

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	model_controls()
	if OS.get_environment("JUSTLIFE_ROTATION_FULL_APP") == "1":
		if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
			push_error("Use an isolated absolute JUSTLIFE_DATA_DIR."); quit(2); return
		await public_load_controls()
		check(public_load_complete, "The complete public-load regression reached its final assertions")
	print("PET_TOY_ROTATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func model_controls() -> void:
	var world := LifeWorld.new()
	var original: Array = [{"id":"spun_toy", "kind":"pet_toy_dog", "x":-8.0, "z":3.0, "rotation":23422.853515625}]
	check(world.validate_home_layout(original).is_empty(), "A legitimate legacy toy with many full turns remains loadable")
	var normalized: Array = LifeWorld.normalize_layout_rotations(original)
	check(absf(float(normalized[0].rotation)) < 360 and is_equal_approx(fmod(float(original[0].rotation), 360.0), float(normalized[0].rotation)) and original[0].rotation == 23422.853515625, "Normalization preserves visible orientation without editing the source save")
	for invalid_angle: Variant in [NAN, INF, "90"]:
		var invalid: Array = original.duplicate(true)
		invalid[0].rotation = invalid_angle
		check(world.validate_home_layout(invalid) == "Invalid furnishing transform.", "Nonfinite or nonnumeric rotation remains invalid: " + str(invalid_angle))
	var invalid_position: Array = original.duplicate(true)
	invalid_position[0].x = 20000.0
	check(world.validate_home_layout(invalid_position) == "Invalid furnishing transform.", "Normalizing rotation does not weaken the coordinate bound")
	invalid_position[0].x = 100.0
	check(world.validate_home_layout(invalid_position) == "A furnishing extends beyond the navigable lot.", "A finite position beyond the lot remains invalid")
	var actor := LifePetActor.new()
	var toy := Node3D.new()
	root.add_child(toy)
	toy.position = Vector3(-8,.16,3)
	var item: Dictionary = {"id":"spun_toy", "kind":"pet_toy_dog", "node":toy, "x":-8.0, "z":3.0}
	var owner := Node.new()
	var behavior := LifePetBehavior.new(owner)
	var errand: Dictionary = {"squeak_at":INF}
	var needs: Dictionary = {"fun":0.0}
	var bounded: bool = true
	# Repeated ordinary animation updates cover enough play to cross the old
	# ±10,000-degree save boundary, without invoking routing or loading assets.
	for step: int in 2400:
		behavior._play("dog", actor, errand, item, 1.0, .1, needs)
		bounded = bounded and absf(toy.rotation.y) <= PI
	check(bounded and float(needs.fun) > 0, "The production toy-play animation keeps full-turn accumulation bounded")
	toy.rotation_degrees.y = 23422.853515625
	world.items.append(item)
	var serialized: Array = world.serialize_items()
	check(absf(float(serialized[0].rotation)) < 360 and world.validate_home_layout(serialized).is_empty(), "Serialization also normalizes an already accumulated live toy rotation")
	world.free(); actor.free(); toy.free(); owner.free()

func public_load_controls() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(); app.set_sound(false); app.set_process(false)
	app.household_profiles = [{"name":"Rotation Keeper", "age_stage":"adult", "traits":[], "hair":0}]
	app.creator_family_links = []; app.start_household(); await frames(3)
	app.household.set_speed(0); app.sim.autonomy = false
	while not app.sim.action_queue.is_empty(): app.sim.cancel_action()
	app.world.add_item({"id":"spun_toy", "kind":"pet_toy_dog", "x":-8.0, "z":3.0, "rotation":23422.853515625})
	var saved: bool = app.save_game("rotation_source", "Toy rotation source")
	check(saved, "Public save writes the household and its toy")
	if not saved: app.queue_free(); await frames(); return
	var legacy: Dictionary = LifeSaveLibrary.read_slot("rotation_source").data
	check(not legacy.has("journeys"), "The fixture exercises the legacy household load path")
	for entry: Dictionary in legacy.world:
		if str(entry.get("id","")) == "spun_toy": entry.rotation = 23422.853515625
	check(bool(LifeSaveLibrary.save_slot("rotation_legacy", "Accumulated toy turns", legacy).get("ok",false)), "The old-format fixture retains the original accumulated angle")
	app.world.remove_item("spun_toy")
	app.household.set_funds(int(app.household.funds) - 13)
	app.load_game("rotation_legacy"); await frames(3)
	var loaded_toy: Dictionary = {}
	for entry: Dictionary in app.world.items:
		if str(entry.id) == "spun_toy": loaded_toy = entry
	check(not loaded_toy.is_empty() and int(app.household.funds) == int(legacy.funds) and str(app.active_save_id) == "rotation_legacy" and app.world.last_layout_error.is_empty(), "Public load restores the saved furnishing and household instead of silently retaining the old scene")
	if not loaded_toy.is_empty():
		check(absf(loaded_toy.node.rotation_degrees.y) < 360 and absf(angle_difference(deg_to_rad(23422.853515625), loaded_toy.node.rotation.y)) < .0001, "The loaded toy retains its original visible orientation")
	var previous_world: Node = app.world
	var previous_house: Node = app.world.house
	var previous_sim: Node = app.sim
	var previous_actor: Node = app.player
	var previous_state: Dictionary = app.household.get_state(app.world.serialize_items()).duplicate(true)
	var previous_land: Dictionary = LifeBuildingState.land.duplicate(true)
	var previous_route: Dictionary = app.traversal.snapshot().duplicate(true)
	var previous_slot: String = str(app.active_save_id)
	var previous_venue: String = str(app.current_venue)
	var previous_selected: String = app.household.selected_id()
	for bad_x: float in [20000.0, 100.0]:
		var invalid: Dictionary = legacy.duplicate(true)
		invalid.funds = int(legacy.funds) + 777
		for member: Dictionary in invalid.members:
			member.state.funds = invalid.funds
			member.state.character.name = "Must Not Replace"
		invalid.world[0].x = bad_x
		check(bool(LifeSaveLibrary.save_slot("rotation_invalid", "Invalid home control", invalid).get("ok",false)), "An otherwise different household fixture carries an invalid x coordinate")
		app.load_game("rotation_invalid"); await frames(2)
		check(is_same(app.world,previous_world) and is_same(app.world.house,previous_house) and is_same(app.sim,previous_sim) and is_same(app.player,previous_actor), "Refused legacy layout preserves the live world, house, sim and actor identities")
		check(app.household.get_state(app.world.serialize_items()) == previous_state and app.traversal.snapshot() == previous_route, "Refused legacy layout preserves the complete household, furniture and routes")
		check(LifeBuildingState.land == previous_land and str(app.active_save_id) == previous_slot and str(app.current_venue) == previous_venue and app.household.selected_id() == previous_selected, "Refused legacy layout preserves land, active save, venue and selected member")
		check(str(app.notice_text) == ("Invalid furnishing transform." if bad_x > 10000 else "A furnishing extends beyond the navigable lot."), "The player receives the actual layout refusal reason")
	public_load_complete = true
	app.queue_free(); await frames(3)
