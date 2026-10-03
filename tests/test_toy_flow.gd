extends SceneTree
## Toys have one truth: a toy is in its box, in somebody's hands or on the floor, and
## the state, the node and the save always agree. Lifelets really stoop, lift,
## carry and set toys into their boxes (and draw them out); pets leave toys where
## they are dropped; play leaves children's toys out; and nothing a load, an undo, a
## sale, a move or a cancel does can leave a toy hidden outside a box or lying in the
## air.
const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

func boot(profiles: Array = [], starter: String = "willow") -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = profiles if not profiles.is_empty() else [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find(starter))
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		member.sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
	app.household.minutes = 600.0
	app.sim.funds = 50000

func member_id(stage: String) -> String:
	for member: Dictionary in app.household.members:
		if str(member.sim.character.age_stage) == stage: return str(member.id)
	return ""

func spot_for(kind: String, near: Vector3) -> Vector3:
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4), Vector3(2.6, 0, 1.2), Vector3(-2.6, 0, 1.2), Vector3(2.6, 0, -1.2), Vector3(-2.6, 0, -1.2), Vector3(0, 0, 2.8)]
	for offset: Vector3 in offsets:
		var at: Vector3 = near + offset
		if app.world.can_place(kind, at, 0.0): return at
	return Vector3.INF

func buy(kind: String, near: Vector3) -> Dictionary:
	var at: Vector3 = spot_for(kind, near)
	if not at.is_finite(): return {}
	app.set_build_mode(true); await frames(2)
	app.on_placement(kind, at, 0.0)
	await frames(2)
	app.set_build_mode(false); await frames(2)
	var found: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: found = item
	return found

func floor_toy(kind: String, at: Vector3, id: String, style: String = "") -> Dictionary:
	var record: Dictionary = {"id": id, "kind": kind, "x": at.x, "z": at.z, "rotation": 20.0}
	if not style.is_empty(): record["style"] = style
	app.world.add_item(record, false)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	return app._find_item(id)

func nested(box: Dictionary) -> Array:
	return app.toy_flow.contents(str(box.id))

func errors() -> Array[String]:
	return app.toy_flow.invariant_errors()

func hips(actor: LifeActor) -> float:
	return actor._joints["Leg_R"].global_position.y

func palm(actor: LifeActor) -> Vector3:
	return actor._joints["Forearm_R"].to_global(actor._palm_offset("R"))

## Run frames at speed 3 until `done` is true; invariants are checked on every one.
func run_until(done: Callable, limit: int = 3000, watch: Callable = Callable(), speed: int = 3) -> bool:
	app.household.set_speed(speed)
	for frame: int in limit:
		app._process(DT)
		if frame % 3 == 0: await process_frame
		var broken: Array[String] = errors()
		if not broken.is_empty():
			check(false, "A toy was out of step mid-flow: %s" % str(broken))
			app.household.set_speed(0)
			return false
		if watch.is_valid(): watch.call()
		if bool(done.call()):
			app.household.set_speed(0)
			return true
	app.household.set_speed(0)
	return false

func run() -> void:
	await boot()
	var parent: String = member_id("adult")
	var kit: String = member_id("child")
	var dog: Dictionary = LifePets.record_from(LifePets.candidate(1, 1), "toy_dog", 1)
	app.household.pets.pets.append(dog); app.household.pets.next_serial = 2
	var dog_home := Vector3(-8.0, .16, 6.0)
	app.spawn_pet(str(dog.id), dog, dog_home, dog_home)

	# ---- A. one truth, kept through everything
	var box: Dictionary = await buy("dog_toy_box", Vector3(0, .16, 3.2))
	check(not box.is_empty(), "A dog toy box can be bought")
	check(nested(box).size() == 6, "It comes with six toys nested in it (%d)" % nested(box).size())
	check(errors().is_empty(), "Every toy is consistent after the purchase %s" % str(errors()))
	var hidden: int = 0; var clickable: int = 0
	for toy: Dictionary in nested(box):
		if not toy.node.visible: hidden += 1
		for body: Node in toy.node.find_children("*", "StaticBody3D", false, false):
			if (body as StaticBody3D).collision_layer != 0: clickable += 1
	check(hidden == 6 and clickable == 0, "Nested toys are hidden and cannot be clicked")
	var record_written: bool = true
	var written: int = 0
	for entry: Variant in app.world.serialize_items():
		if entry is Dictionary and str(entry.get("kind", "")) == "pet_toy_dog":
			written += 1
			if str(entry.get("box_id", "")) != str(box.id): record_written = false
	check(written == 6 and record_written, "The layout records which box each toy is in")

	check(app.save_game("toy_a", "Toy A"), "The game saves")
	app.load_game("toy_a"); await frames(4)
	app.set_process(false); app.household.set_speed(0)
	box = app._find_item(str(box.id))
	check(nested(box).size() == 6 and errors().is_empty(), "After a save and load all six toys are still nested and hidden %s" % str(errors()))
	check(app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == "pet_toy_dog" and item.node.visible).is_empty(), "No nested toy has popped out onto the floor")

	var spare: Dictionary = await buy("plant", Vector3(0, .16, -2.5))
	app.set_build_mode(true); await frames(2)
	app.undo_build(); await frames(2)
	app.set_build_mode(false); await frames(2)
	box = app._find_item(str(box.id))
	check(not spare.is_empty() and nested(box).size() == 6 and errors().is_empty(), "Undoing an unrelated purchase keeps the toys nested")

	# ---- legacy and damaged layouts are mended, not refused
	var box_record: Dictionary = {"id": "box1", "kind": "dog_toy_box", "x": 2.0, "z": 3.0, "rotation": 0.0}
	var legacy: Array = LifeToyFlow.normalize_layout([box_record,
		{"id": "toy_box1_0", "kind": "pet_toy_dog", "x": 2.1, "z": 3.0, "rotation": 0.0},
		{"id": "toy_box1_1", "kind": "pet_toy_dog", "x": 2.0, "z": 3.1, "rotation": 30.0},
		{"id": "stray", "kind": "pet_toy_dog", "x": -4.0, "z": 3.0, "rotation": 0.0},
		{"id": "cat_in_dog_box", "kind": "pet_toy_cat", "x": 2.0, "z": 3.0, "rotation": 0.0, "box_id": "box1"},
		{"id": "orphan", "kind": "pet_toy_dog", "x": 5.0, "z": 5.0, "rotation": 0.0, "box_id": "gone"},
		{"id": "upstairs", "kind": "pet_toy_dog", "x": 2.0, "z": 3.0, "rotation": 0.0, "box_id": "box1", "level": 1}])
	var by_id: Dictionary = {}
	for entry: Dictionary in legacy: by_id[str(entry.id)] = entry
	check(str(by_id.toy_box1_0.get("box_id", "")) == "box1" and str(by_id.toy_box1_1.get("box_id", "")) == "box1", "Toys an older build left lying at their box are put back in it")
	check(not by_id.stray.has("box_id"), "A toy lying elsewhere stays on the floor")
	check(not by_id.cat_in_dog_box.has("box_id") and not by_id.orphan.has("box_id") and not by_id.upstairs.has("box_id"), "A toy in a box that does not take it, is gone, or is on another floor is let out")
	var crowded: Array = [box_record]
	for index: int in 9: crowded.append({"id": "toy_box1_%d" % index, "kind": "pet_toy_dog", "x": 2.0, "z": 3.0, "rotation": 0.0, "box_id": "box1"})
	var kept: int = 0
	for entry: Dictionary in LifeToyFlow.normalize_layout(crowded):
		if entry.has("box_id"): kept += 1
	check(kept == LifeToyFlow.capacity("dog_toy_box"), "A box over capacity keeps only what it holds (%d)" % kept)

	# ---- B. the container's lifecycle
	app.set_build_mode(true); await frames(2)
	app.move_item(box); await frames(2)
	var moved_to: Vector3 = spot_for("dog_toy_box", Vector3(-3.5, .16, 3.0))
	app.on_placement("dog_toy_box", moved_to, 90.0); await frames(2)
	app.set_build_mode(false); await frames(2)
	box = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "dog_toy_box": box = item
	var near_box: bool = true
	for toy: Dictionary in nested(box):
		if Vector2(toy.node.position.x - box.node.position.x, toy.node.position.z - box.node.position.z).length() > .3: near_box = false
	check(nested(box).size() == 6 and near_box and errors().is_empty(), "Moving a box carries its toys with it %s" % str(errors()))
	check(app.save_game("toy_b", "Toy B"), "Saving after the move")
	app.load_game("toy_b"); await frames(4)
	app.set_process(false); app.household.set_speed(0)
	check(app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == "pet_toy_dog" and item.node.visible).is_empty(), "No toy is left visible at the box's old place after loading")

	app.set_build_mode(true); await frames(2)
	box = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "dog_toy_box": box = item
	app.store_item(box); await frames(2)
	var stored: Dictionary = {}
	for entry: Dictionary in app.household_flow.storage:
		if str(entry.kind) == "dog_toy_box": stored = entry
	check(not stored.is_empty() and int(stored.get("toys", -1)) == 6, "Storing a box records its six toys")
	check(app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == "pet_toy_dog").is_empty(), "Stored with it: no orphan toy is left behind, hidden or not")
	check(app.world.serialize_items().filter(func(entry: Variant) -> bool: return entry is Dictionary and str(entry.get("kind", "")) == "pet_toy_dog").is_empty(), "And none is written to the layout")
	app.withdraw_stored(str(stored.id)); await frames(2)
	app.on_placement("dog_toy_box", spot_for("dog_toy_box", Vector3(0, .16, 3.2)), 0.0); await frames(2)
	box = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "dog_toy_box": box = item
	check(nested(box).size() == 6 and errors().is_empty(), "Taking it out of storage brings the toys back, nested (%d)" % nested(box).size())
	app.sell_item(box); await frames(2)
	check(app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == "pet_toy_dog").is_empty() and errors().is_empty(), "Selling a box sells its toys too: none is left hidden and clickable")
	app.undo_build(); await frames(2)
	box = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "dog_toy_box": box = item
	check(not box.is_empty() and nested(box).size() == 6 and errors().is_empty(), "Undoing the sale brings the box back with its toys nested")
	app.set_build_mode(false); await frames(2)

	# ---- C. putting a toy away: the Lifelet really stoops, lifts, carries and sets it in
	var toy: Dictionary = nested(box)[0]
	app.toy_flow.unnest(toy)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(app.toy_flow.is_floor(toy) and toy.node.visible and errors().is_empty(), "A toy taken out lies on the floor, visible, and clickable")
	var away: Vector3 = Vector3(box.node.position.x + 3.0, .16, box.node.position.z + 0.6)
	toy["x"] = away.x
	app.world.remove_item(str(toy.id))
	toy = floor_toy("pet_toy_dog", Vector3(box.node.position.x + 2.4, .16, box.node.position.z + 1.2), "tidy_target")
	check(app.toy_flow.is_floor(toy), "A toy left in the open is a floor toy")
	app.select_household_member(0); await frames(2)
	var person: LifeActor = app.world.actors[parent]
	var result: Dictionary = app.toy_flow.queue_tidy(parent, "tidy_target")
	check(bool(result.ok), "The adult can be told to put it away (%s)" % str(result.get("error", "")))
	var seen: Array[String] = []
	var standing_hips: float = hips(person)
	var measured: Dictionary = {"pickup_gap": INF, "dip": 0.0, "lean": 0.0, "palm_floor": INF, "palm_lift": 0.0, "rise": 0.0, "carry_gap": 0.0, "carry_height": 0.0, "place_gap": INF}
	var rest_y: float = 0.0
	var watch: Callable = func() -> void:
		var state: Dictionary = app.toy_flow.stages.get(parent, {})
		if state.is_empty(): return
		var stage: String = str(state.stage)
		if seen.is_empty() or seen.back() != stage: seen.append(stage)
		var node: Node3D = toy.node
		var gap: float = Vector2(node.global_position.x - person.global_position.x, node.global_position.z - person.global_position.z).length()
		if stage == "pickup":
			measured.pickup_gap = minf(float(measured.pickup_gap), gap)
			measured.dip = maxf(float(measured.dip), standing_hips - hips(person))
			measured.lean = maxf(float(measured.lean), absf(person.visual.rotation.x))
			measured.palm_floor = minf(float(measured.palm_floor), palm(person).distance_to(Vector3(state.rest) + Vector3(0, .04, 0)))
			if float(state.t) > .8 and float(state.t) < 1.2: measured.palm_lift = maxf(float(measured.palm_lift), palm(person).distance_to(node.global_position + Vector3(0, .04, 0)))
			measured.rise = maxf(float(measured.rise), node.global_position.y)
		elif stage == "carry":
			measured.carry_gap = maxf(float(measured.carry_gap), gap)
			measured.carry_height = maxf(float(measured.carry_height), node.global_position.y)
		elif stage == "place":
			measured.place_gap = minf(float(measured.place_gap), person.global_position.distance_to(box.node.global_position))
	check(await run_until(func() -> bool: return app.toy_flow.is_boxed(toy), 9000, watch, 1), "The toy ends up in the box")
	check(seen == ["pickup", "carry", "place"], "It was picked up, carried, then placed (%s)" % str(seen))
	check(float(measured.pickup_gap) < 1.0, "They stood beside it to pick it up (%.2f m)" % float(measured.pickup_gap))
	check(float(measured.dip) >= .3 and float(measured.lean) >= .8, "They bent right down to reach it (hips lowered %.2f m, leaned %.2f rad)" % [float(measured.dip), float(measured.lean)])
	check(float(measured.palm_floor) < .15, "Their hand reaches the toy on the floor (%.2f m)" % float(measured.palm_floor))
	check(float(measured.palm_lift) < .15, "And stays on it as they lift it (worst %.2f m)" % float(measured.palm_lift))
	check(float(measured.carry_height) > .4 and float(measured.carry_gap) < .6, "Carried, it is in their hand: %.2f m up, %.2f m from them" % [float(measured.carry_height), float(measured.carry_gap)])
	check(float(measured.place_gap) < 1.2, "They were at the box when it went in (%.2f m)" % float(measured.place_gap))
	check(not toy.node.visible and str(toy.box_id) == str(box.id) and not toy.has("carried"), "In the same step the toy is hidden and recorded in the box")
	check(await run_until(func() -> bool: return app.sim.get_current_action().is_empty() and app.household.member_sim(parent).get_current_action().is_empty(), 600), "The action then finishes by itself")
	check(nested(box).size() == 6 and errors().is_empty(), "The box holds its six again")

	# ---- a child can do it too, at their own height
	var child_actor: LifeActor = app.world.actors[kit]
	toy = floor_toy("pet_toy_dog", Vector3(box.node.position.x - 2.2, .16, box.node.position.z + 1.4), "child_toy")
	app.toy_flow.unnest(nested(box)[0], Vector3(box.node.position.x - 1.8, .16, box.node.position.z + 1.0))
	app._refresh_sim_targets()
	check(bool(app.toy_flow.queue_tidy(kit, "child_toy").ok), "A child can be told to put a toy away")
	var child_standing: float = hips(child_actor)
	var child_dip: Dictionary = {"dip": 0.0}
	var child_watch: Callable = func() -> void:
		if str((app.toy_flow.stages.get(kit, {}) as Dictionary).get("stage", "")) == "pickup": child_dip.dip = maxf(float(child_dip.dip), child_standing - hips(child_actor))
	check(await run_until(func() -> bool: return app.toy_flow.is_boxed(toy), 4000, child_watch), "The child puts it away")
	check(float(child_dip.dip) > .15, "They bent down for it (hips lowered %.2f m)" % float(child_dip.dip))
	check(await run_until(func() -> bool: return app.household.member_sim(kit).get_current_action().is_empty(), 600), "The child's action finishes")

	# ---- refusals say why
	var full_box: Dictionary = box
	while nested(full_box).size() < LifeToyFlow.capacity("dog_toy_box"):
		var extra: Dictionary = floor_toy("pet_toy_dog", Vector3(full_box.node.position.x + 1.0, .16, full_box.node.position.z + 2.5), "filler_%d" % nested(full_box).size())
		check(app.toy_flow.nest(extra, full_box), "A box takes toys up to its capacity")
	var seventh: Dictionary = floor_toy("pet_toy_dog", Vector3(full_box.node.position.x + 1.4, .16, full_box.node.position.z + 2.5), "seventh")
	var full: Dictionary = app.toy_flow.queue_tidy(parent, "seventh")
	check(not bool(full.ok) and "full" in str(full.error), "A full box refuses another toy: %s" % str(full.get("error", "")))
	check(not app.toy_flow.nest(seventh, full_box) and app.toy_flow.is_floor(seventh), "Forcing it in does nothing")
	var babe := LifeSim.new()
	babe.new_household({"name": "Little", "age_stage": "baby", "traits": []})
	check(LifeStagePolicy.action_error("baby", "baby", "put_pet_toy").contains("cannot put them away") and LifeStagePolicy.can_use("baby", "baby", "play_toys"), "A baby may play with toys but is refused tidying them, with a reason")
	app.world.remove_item("seventh")
	var claimed_toy: Dictionary = floor_toy("pet_toy_dog", Vector3(full_box.node.position.x - 1.4, .16, full_box.node.position.z + 2.5), "claimed")
	app.pet_behavior().toy_claims["claimed"] = str(dog.id)
	var pet_claim: Dictionary = app.toy_flow.queue_tidy(parent, "claimed")
	check(not bool(pet_claim.ok), "A toy a pet is playing with is not taken from it: %s" % str(pet_claim.get("error", "")))
	app.pet_behavior().toy_claims.erase("claimed")
	app.world.remove_item("claimed")
	for toy_in: Dictionary in nested(full_box).slice(6): app.toy_flow.unnest(toy_in)
	app.world.rebuild_navigation(); app._refresh_sim_targets()

	# ---- D. interruption never strands a toy
	for cut: String in ["approach", "pickup", "carry", "place"]:
		var test_toy: Dictionary = floor_toy("pet_toy_dog", Vector3(full_box.node.position.x + 2.2, .16, full_box.node.position.z + 1.6), "cut_%s" % cut)
		var home_x: float = test_toy.node.position.x
		for stale: Dictionary in nested(full_box).slice(5): app.toy_flow.unnest(stale, Vector3(full_box.node.position.x - 2.8, .16, full_box.node.position.z + 3.2))
		app.world.rebuild_navigation(); app._refresh_sim_targets()
		check(bool(app.toy_flow.queue_tidy(parent, "cut_%s" % cut).ok), "Queued a tidy to cut at %s" % cut)
		var reached: bool = await run_until(func() -> bool:
			if cut == "approach": return (app.toy_flow.stages.get(parent, {}) as Dictionary).is_empty() and str(app.household.member_sim(parent).get_current_action().get("phase", "")) == "approach" and person.global_position.distance_to(test_toy.node.global_position) < 4.0
			return str((app.toy_flow.stages.get(parent, {}) as Dictionary).get("stage", "")) == cut, 4000)
		check(reached, "Reached %s" % cut)
		if cut in ["pickup", "carry", "place"]: await run_until(func() -> bool: return float((app.toy_flow.stages.get(parent, {}) as Dictionary).get("t", 0.0)) > .5, 600)
		app.household.member_sim(parent).cancel_action(); await frames(3)
		check(app.toy_flow.is_floor(test_toy) and test_toy.node.visible and not test_toy.has("rest") and errors().is_empty(), "Cancelled at %s the toy is back on the floor, visible: %s" % [cut, str(errors())])
		check(test_toy.node.position.y < .3 and absf(test_toy.node.rotation.x) < .01 and absf(test_toy.node.rotation.z) < .01, "It lies level on the ground, not in the air (y %.2f)" % test_toy.node.position.y)
		check(app.toy_flow.stages.is_empty() and person.toy_presentation.is_empty(), "No fetch is left in flight")
		app.world.remove_item("cut_%s" % cut)
		app.world.rebuild_navigation(); app._refresh_sim_targets()

	# a save in the middle of a carry
	var carried_toy: Dictionary = floor_toy("pet_toy_dog", Vector3(full_box.node.position.x + 2.2, .16, full_box.node.position.z + 1.6), "carried_toy")
	app.toy_flow.unnest(nested(full_box).back(), Vector3(full_box.node.position.x - 2.8, .16, full_box.node.position.z + 3.2))
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(bool(app.toy_flow.queue_tidy(parent, "carried_toy").ok), "Queued a tidy to save in the middle of")
	await run_until(func() -> bool: return str((app.toy_flow.stages.get(parent, {}) as Dictionary).get("stage", "")) == "carry", 4000)
	var mid: Array = app.world.serialize_items()
	var mid_record: Dictionary = {}
	for entry: Variant in mid:
		if entry is Dictionary and str(entry.get("id", "")) == "carried_toy": mid_record = entry
	check(not mid_record.is_empty() and not mid_record.has("hang") and not mid_record.has("box_id") and absf(float(mid_record.x) - float(app.toy_flow.stages[parent].rest.x)) < .01, "A toy in the hand is saved where it lay: no hang, no box (y lift %s)" % str(mid_record.get("hang", 0.0)))
	check(app.save_game("toy_c", "Toy C"), "Saved with a toy in the hand")
	app.load_game("toy_c"); await frames(4)
	app.set_process(false); app.household.set_speed(0)
	carried_toy = app._find_item("carried_toy")
	check(not carried_toy.is_empty() and app.toy_flow.is_floor(carried_toy) and carried_toy.node.visible and errors().is_empty(), "After loading, that toy is on the floor where it was %s" % str(errors()))
	check(await run_until(func() -> bool: return app.toy_flow.is_boxed(app._find_item("carried_toy")), 5000), "The loaded tidy starts again and finishes it")

	# ---- G. taking one out
	if not app.sim.get_current_action().is_empty(): app.sim.cancel_action()
	box = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "dog_toy_box": box = item
	var before: int = nested(box).size()
	app.queue_interaction(box, "take_pet_toy")
	var drawn: Array[String] = []
	var draw_watch: Callable = func() -> void:
		var state: Dictionary = app.toy_flow.stages.get(parent if app.sim == app.household.member_sim(parent) else kit, {})
		if not state.is_empty() and (drawn.is_empty() or drawn.back() != str(state.stage)): drawn.append(str(state.stage))
	check(await run_until(func() -> bool: return nested(box).size() < before and app.sim.get_current_action().is_empty(), 4000, draw_watch), "A Lifelet can take a toy out of the box")
	check(drawn == ["draw"] and nested(box).size() == before - 1, "By reaching in and drawing it out (%s, %d left)" % [str(drawn), nested(box).size()])
	var out: Dictionary = {}
	for entry: Dictionary in app.toy_flow.loose_toys("pet_toy_dog"):
		if str(entry.id).begins_with("toy_%s_" % str(box.id)) or str(entry.id) == "carried_toy": out = entry
	check(not out.is_empty() and app.toy_flow.is_floor(out) and out.node.visible, "It was set down on the floor, visible")
	check(errors().is_empty(), "Everything is still consistent %s" % str(errors()))

	# ---- E. pets
	var pet_actor: LifePetActor = app.pet_actors[str(dog.id)]
	var controller: RefCounted = app.pet_behavior()
	app.pet_errands.clear(); controller.toy_claims.clear()
	pet_actor.position = dog_home
	for need: String in LifePetCare.NEED_NAMES: app.household.pet_care(str(dog.id)).needs[need] = 90.0
	app.household.pet_care(str(dog.id)).needs.fun = 5.0
	var play: Dictionary = controller.command(str(dog.id), "pet_play_toys")
	check(bool(play.ok), "The dog can be told to play with a toy (%s)" % str(play.get("message", play.get("error", ""))))
	var guard: int = 0
	while app.pet_errands.has(str(dog.id)) and guard < 4000:
		controller.tick(.2, 1.0)
		pet_actor.animate(.2, bool(app.pet_errands.get(str(dog.id), {}).get("walking", false)), 1.0)
		guard += 1
	check(errors().is_empty(), "After a whole play session every toy is consistent %s" % str(errors()))
	var loose_after: Array = app.toy_flow.loose_toys("pet_toy_dog")
	check(not loose_after.is_empty(), "The toy the dog played with is left out for somebody to tidy (%d)" % loose_after.size())
	var tidy_pick: Dictionary = app.toy_flow.autonomous_tidy_choice(app.household.member_sim(parent))
	check(str(tidy_pick.get("id", "")) == "put_pet_toy" and app.toy_flow.is_floor(app._find_item(str(tidy_pick.get("target_id", "")))), "An idle adult picks it as something to tidy")

	# fetch: dropped in front, not under the dog, and a save while it is carried is clean
	var care: Dictionary = app.household.pet_care(str(dog.id))
	if not (care.get("skills", {}) as Dictionary).has("tricks"): care.skills["tricks"] = {}
	care.skills.tricks["level"] = 10
	var fetch_toy: Dictionary = app.toy_flow.contents(str(box.id)).front() if not app.toy_flow.contents(str(box.id)).is_empty() else {}
	if not fetch_toy.is_empty():
		app.pet_errands.clear(); controller.toy_claims.clear()
		var fetch: Dictionary = controller.command(str(dog.id), "pet_trick:fetch@" + str(fetch_toy.id))
		if bool(fetch.get("ok", false)):
			var carried_saved: bool = false
			var hang_free: bool = true
			guard = 0
			while app.pet_errands.has(str(dog.id)) and guard < 5000:
				controller.tick(.2, 1.0)
				pet_actor.animate(.2, bool(app.pet_errands.get(str(dog.id), {}).get("walking", false)), 1.0)
				if bool(fetch_toy.get("carried", false)) and not carried_saved:
					carried_saved = true
					for entry: Variant in app.world.serialize_items():
						if entry is Dictionary and str(entry.get("id", "")) == str(fetch_toy.id) and entry.has("hang"): hang_free = false
				guard += 1
			check(carried_saved and hang_free, "A toy in a dog's mouth is saved at its resting place, not floating")
			check(app.toy_flow.is_floor(fetch_toy) and fetch_toy.node.position.y < .3, "After the fetch the toy is on the floor, level")
			check(Vector2(fetch_toy.node.position.x - pet_actor.position.x, fetch_toy.node.position.z - pet_actor.position.z).length() > .15, "It was dropped in front of the dog, not under it")
			check(errors().is_empty(), "And still consistent %s" % str(errors()))
		else:
			print("  (fetch not available in this fixture: %s)" % str(fetch))

	# ---- F. autonomy and the household chore list
	for stray: Dictionary in app.toy_flow.loose_toys():
		if str(stray.kind) == "pet_toy_dog": app.world.remove_item(str(stray.id))
	app._refresh_sim_targets()
	var idle: LifeSim = app.household.member_sim(parent)
	idle.autonomy = true
	idle.minutes = 1000.0
	for need: String in LifeSim.NEED_NAMES: idle.needs[need] = 90.0
	var lone: Dictionary = floor_toy("pet_toy_dog", Vector3(box.node.position.x + 1.6, .16, box.node.position.z + 2.2), "autonomy_toy")
	for stale: Dictionary in nested(box).slice(5): app.toy_flow.unnest(stale, Vector3(box.node.position.x - 2.8, .16, box.node.position.z + 3.2))
	app._refresh_sim_targets()
	var chosen: Dictionary = idle._autonomous_choice([])
	check(str(chosen.get("id", "")) == "put_pet_toy", "An idle adult with nothing else to do tidies the toy away (%s)" % str(chosen.get("id", "")))
	idle.needs.hunger = 8.0
	check(str(idle._autonomous_choice([]).get("id", "")) != "put_pet_toy", "But a hungry one eats first")
	idle.needs.hunger = 90.0
	var chores: Array = app.toy_flow.chores(parent)
	check(chores.size() == app.toy_flow.loose_toys().size() and not chores.is_empty() and str(chores[0].chore) == "tidy_toys", "The chore list matches the toys on the floor (%d)" % chores.size())
	idle.autonomy = false
	var many: Dictionary = app.toy_flow.queue_tidy_all(parent, "pet_toy_dog")
	check(bool(many.ok) and int(many.queued) <= 6 and int(many.queued) == app.household.member_sim(parent).action_queue.size(), "Tidy toys queues one cancellable action per toy (%d)" % int(many.queued))
	for queued: Dictionary in idle.action_queue.duplicate(): idle.cancel_action(0)
	check(idle.action_queue.is_empty() and app.toy_flow.stages.is_empty() and errors().is_empty(), "Cancelling them all leaves nothing in flight %s" % str(errors()))

	# ---- children's toys: play leaves them out, tidying puts them in the chest
	for stray: Dictionary in app.toy_flow.loose_toys(): app.world.remove_item(str(stray.id))
	var chest: Dictionary = await buy("toy_chest", Vector3(4.0, .16, 3.0))
	check(not chest.is_empty() and nested(chest).is_empty(), "A toy chest is bought empty")
	var kid: LifeSim = app.household.member_sim(kit)
	child_actor = app.world.actors[kit]
	kid.minutes = 700.0
	for need: String in LifeSim.NEED_NAMES: kid.needs[need] = 60.0
	kid.needs.fun = 20.0
	app.select_household_member(1); await frames(2)
	app.queue_interaction(chest, "play_toys")
	check(await run_until(func() -> bool: return not app.toy_flow.loose_toys("kids_toy").is_empty(), 5000), "After play the child has left toys out")
	check(await run_until(func() -> bool: return app.household.member_sim(kit).get_current_action().is_empty(), 3000), "The play finishes")
	var left: Array = app.toy_flow.loose_toys("kids_toy")
	check(left.size() >= 1 and left.size() <= 3 and errors().is_empty(), "One to three toys are left on the floor (%d)" % left.size())
	var near: bool = true
	for entry: Dictionary in left:
		if Vector2(entry.node.position.x - child_actor.position.x, entry.node.position.z - child_actor.position.z).length() > 1.6: near = false
		if LifeCatalog.ITEMS.has("kids_toy") and entry.node.find_children("*", "MeshInstance3D", true, false).is_empty(): near = false
	check(near, "They lie close to where the child played, and are drawn")
	check(bool(app.toy_flow.queue_tidy(kit, str(left[0].id)).ok), "The child can put one in the chest")
	check(await run_until(func() -> bool: return app.toy_flow.is_boxed(left[0]), 5000), "It goes into the toy chest")
	check(str(left[0].box_id) == str(chest.id) and not left[0].node.visible, "Recorded in the chest, hidden")
	var padlock: bool = true
	for loose_toy: Dictionary in app.toy_flow.loose_toys("kids_toy"): padlock = padlock and str(app.toy_flow.tidy_error(app.household.member_sim(kit), str(loose_toy.id))).is_empty()
	check(padlock, "Any other the child could tidy is offered")
	var saved_chest: bool = app.save_game("toy_d", "Toy D")
	app.load_game("toy_d"); await frames(4)
	app.set_process(false); app.household.set_speed(0)
	var reloaded_chest: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "toy_chest": reloaded_chest = item
	check(saved_chest and not reloaded_chest.is_empty() and nested(reloaded_chest).size() >= 1 and errors().is_empty(), "A chest's toys survive a save and load %s" % str(errors()))
	# no more than eight are ever left out
	for index: int in 12:
		var spill: Dictionary = {"id": "spill_%d" % index, "kind": "kids_toy", "x": -2.0 + float(index) * .3, "z": -9.0, "rotation": 0.0, "style": "ball"}
		app.world.add_item(spill, false)
	app.world.rebuild_navigation()
	var before_made: int = app.toy_flow.loose_toys("kids_toy").size()
	var made: int = app.toy_flow.scatter_after_play(kit, {"id": "play_toys"})
	check(made == 0 and app.toy_flow.loose_toys("kids_toy").size() == before_made, "A home with plenty out already gets no more (%d)" % before_made)
	# ---- Clean Home: a round puts every toy away for real, and a full box skips a toy instead of ending the round
	for stray: Dictionary in app.toy_flow.loose_toys(): app.world.remove_item(str(stray.id))
	var reloaded: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "toy_chest": reloaded = item
	var room_left: int = LifeToyFlow.capacity("toy_chest") - app.toy_flow.contents(str(reloaded.id)).size()
	for index: int in range(room_left - 1):
		var packed: Dictionary = floor_toy("kids_toy", Vector3(-2.0 + float(index) * .3, .16, -9.0), "packed_%d" % index, "ball")
		app.toy_flow.nest(packed, reloaded)
	for index: int in 3: floor_toy("kids_toy", Vector3(4.5 + float(index) * .45, .16, 4.4), "round_%d" % index, "bear")
	var cleaner: LifeSim = app.household.member_sim(parent)
	cleaner.autonomy = false
	for need: String in LifeSim.NEED_NAMES: cleaner.needs[need] = 95.0
	cleaner.minutes = 600.0; app.household.minutes = 600.0
	var round_plan: Dictionary = app.chore_flow.make_plan(cleaner, "custom", ["toys"])
	check(round_plan.entries.size() >= 1 and str(round_plan.entries[0].id) == "put_pet_toy", "A Clean Home round plans a real tidy for the toys out (%d)" % round_plan.entries.size())
	var started: Dictionary = app.chore_flow.start(parent, "custom", ["toys"])
	check(bool(started.ok), "A toys-only round starts (%s)" % str(started.get("error", "")))
	check(await run_until(func() -> bool: return app.household.member_sim(parent).action_queue.is_empty(), 9000), "The round runs to its end even though the chest fills up")
	check(app.toy_flow.contents(str(reloaded.id)).size() == LifeToyFlow.capacity("toy_chest") and app.toy_flow.loose_toys("kids_toy").size() == 2, "One toy fitted and the rest were left out, not lost (%d out)" % app.toy_flow.loose_toys("kids_toy").size())
	check(errors().is_empty() and app.toy_flow.stages.is_empty(), "Nothing is left in flight %s" % str(errors()))
	check(errors().is_empty(), "Every toy in the home is consistent at the end %s" % str(errors()))

	print("TOY_FLOW ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
