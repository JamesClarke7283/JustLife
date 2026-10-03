extends SceneTree
## The edges of the toy flow that a review found: a box taken out of storage must not
## re-create ids a toy left out already has; a toy in a hand whose record is rebuilt
## (an undo) or that is clicked is put on the floor, level, when its tidy ends; a toy
## being carried cannot be moved; a child's toy can be moved and drawn as a ghost; play
## leaves no more toys than the chest can take; saves made at every stage of a tidy
## (in a home that has been built on) are accepted and the saved tidy starts again from
## the walk to its toy; a box sold under a Lifelet who is drawing from it does not eat
## the next queued action; carried links survive moving house; older saves with an
## eight-minute put-away still load.
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

func boot(canonical: bool = false) -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find("willow"))
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		member.sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
	app.household.minutes = 600.0
	app.sim.funds = 50000
	if canonical:
		app.set_build_mode(true); await frames(2)
		app.set_build_level(1); app.set_build_level(0)
		app.set_build_mode(false); await frames(2)

func buy(kind: String, near: Vector3) -> Dictionary:
	var at: Vector3 = Vector3.INF
	for offset: Vector3 in [Vector3.ZERO, Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4), Vector3(2.6, 0, 1.2), Vector3(-2.6, 0, 1.2), Vector3(0, 0, 2.8)]:
		if app.world.can_place(kind, near + offset, 0.0): at = near + offset; break
	if not at.is_finite(): return {}
	app.set_build_mode(true); await frames(2)
	app.on_placement(kind, at, 0.0)
	await frames(2)
	app.set_build_mode(false); await frames(2)
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: return item
	return {}

func ids_unique() -> bool:
	var seen: Dictionary = {}
	for item: Dictionary in app.world.items:
		if seen.has(str(item.id)): return false
		seen[str(item.id)] = true
	return true

func run_until(done: Callable, limit: int = 3000, speed: int = 3) -> bool:
	app.household.set_speed(speed)
	for frame: int in limit:
		app._process(DT)
		if frame % 3 == 0: await process_frame
		if bool(done.call()):
			app.household.set_speed(0)
			return true
	app.household.set_speed(0)
	return false

func run() -> void:
	# ---- a box that goes into storage and comes out again restocks with ids of its own
	await boot()
	var parent: String = str(app.household.members[0].id)
	var box: Dictionary = await buy("dog_toy_box", Vector3(0, .16, 3.2))
	check(not box.is_empty(), "A dog toy box is bought")
	app.toy_flow.unnest(app.toy_flow.contents(str(box.id))[0], Vector3(box.node.position.x + 1.0, .16, box.node.position.z + 1.2))
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	app.set_build_mode(true); await frames(2)
	app.store_item(box); await frames(2)
	var stored: Dictionary = {}
	for entry: Dictionary in app.household_flow.storage:
		if str(entry.kind) == "dog_toy_box": stored = entry
	app.withdraw_stored(str(stored.id)); await frames(2)
	app.on_placement("dog_toy_box", Vector3(0, .16, 3.2), 0.0); await frames(2)
	app.set_build_mode(false); await frames(2)
	check(ids_unique(), "Every id in the home is unique after the box comes out of storage")
	check(app.world.validate_home_layout(app.world.serialize_items()).is_empty(), "And the home still validates")
	check(app.save_game("edges_a", "Edges A"), "The game saves")
	app.load_game("edges_a"); await frames(4)
	app.set_process(false); app.household.set_speed(0)
	check(ids_unique() and app.toy_flow.invariant_errors().is_empty(), "And loads %s" % str(app.toy_flow.invariant_errors()))
	var duplicated: Array = LifeToyFlow.normalize_layout([{"id": "toy_x_0", "kind": "pet_toy_dog", "x": 1.0, "z": 1.0, "rotation": 0.0}, {"id": "toy_x_0", "kind": "pet_toy_dog", "x": 2.0, "z": 1.0, "rotation": 0.0}])
	check(str(duplicated[0].id) != str(duplicated[1].id), "A layout with two toys of one id gives the later one an id of its own")

	# ---- moving house keeps what is in a box
	var carried_over: Array = LifeProperties.merge_move_layout([{"id": "a", "kind": "dog_toy_box", "x": 0.0, "z": 0.0, "rotation": 0.0}, {"id": "t", "kind": "pet_toy_dog", "x": 0.0, "z": 0.0, "rotation": 0.0, "box_id": "a"}, {"id": "u", "kind": "pet_toy_dog", "x": 1.0, "z": 0.0, "rotation": 0.0, "box_id": "gone"}], [])
	check(str(carried_over[1].get("box_id", "")) == str(carried_over[0].id) and not carried_over[2].has("box_id"), "Moving house points a nested toy at its box's new id, and frees one whose box did not come")

	# ---- a tidy whose toy record is rebuilt under it still ends with the toy on the floor
	await boot()
	parent = str(app.household.members[0].id)
	box = await buy("dog_toy_box", Vector3(0, .16, 3.2))
	app.toy_flow.unnest(app.toy_flow.contents(str(box.id))[0], Vector3(box.node.position.x + 2.0, .16, box.node.position.z + 1.4))
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	var toy: Dictionary = app.toy_flow.loose_toys()[0]
	check(bool(app.toy_flow.queue_tidy(parent, str(toy.id)).ok), "A tidy is queued")
	check(await run_until(func() -> bool: return str((app.toy_flow.stages.get(parent, {}) as Dictionary).get("stage", "")) == "carry", 4000), "The Lifelet carries the toy")
	var collider: bool = false
	for body: Node in toy.node.find_children("*", "StaticBody3D", false, false):
		if (body as StaticBody3D).collision_layer != 0: collider = true
	check(not collider, "A toy in a hand cannot be clicked, and so cannot be moved or sold from under it")
	app.set_build_mode(true); await frames(2)
	await buy("plant", Vector3(0, .16, -2.5))
	app.set_build_mode(true); await frames(2)
	app.undo_build(); await frames(2)
	app.set_build_mode(false); await frames(2)
	app.household.member_sim(parent).cancel_action(); await frames(3)
	toy = app._find_item(str(toy.id))
	check(not toy.is_empty() and app.toy_flow.is_floor(toy) and toy.node.position.y < .3 and toy.node.visible, "After an undo and a cancel the toy lies on the floor (y %.2f)" % (toy.node.position.y if not toy.is_empty() else -1.0))
	check(app.toy_flow.invariant_errors().is_empty() and not app.world.serialize_items().any(func(entry: Variant) -> bool: return entry is Dictionary and str(entry.get("id", "")) == str(toy.id) and entry.has("hang")), "It is not saved floating")

	# ---- a child's toy can be moved: the ghost is drawn
	var kid_toy: Dictionary = {"id": "edge_kid_toy", "kind": "kids_toy", "style": "bear", "x": 3.0, "z": 2.0, "rotation": 0.0}
	app.world.add_item(kid_toy, false)
	app.world.begin_placement("kids_toy", "bear")
	check(app.world.ghost != null, "Placing a child's toy draws its ghost, so it can be moved")
	app.world.clear_placement()

	# ---- play leaves no more toys than the chest can take
	var chest: Dictionary = await buy("toy_chest", Vector3(4.0, .16, 3.0))
	for stray: Dictionary in app.toy_flow.loose_toys("kids_toy"): app.world.remove_item(str(stray.id))
	for index: int in LifeToyFlow.capacity("toy_chest"):
		var packed: Dictionary = {"id": "edge_packed_%d" % index, "kind": "kids_toy", "style": "ball", "x": -2.0 + float(index) * .3, "z": -9.0, "rotation": 0.0}
		app.world.add_item(packed, false)
		app.toy_flow.nest(app._find_item(str(packed.id)), chest)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(app.toy_flow.contents(str(chest.id)).size() == LifeToyFlow.capacity("toy_chest") and app.toy_flow.scatter_after_play(parent, {"id": "play_toys"}) == 0, "A full chest means play leaves nothing out that cannot be put away")
	check(app.toy_flow.furnishing_room() > 0, "The home has room for more furnishings (%d)" % app.toy_flow.furnishing_room())

	# ---- a saved tidy starts again from the walk to its toy, and a save is accepted at every stage
	await boot(true)
	parent = str(app.household.members[0].id)
	box = await buy("dog_toy_box", Vector3(0, .16, 3.2))
	app.toy_flow.unnest(app.toy_flow.contents(str(box.id))[0], Vector3(box.node.position.x + 2.2, .16, box.node.position.z + 1.4))
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	toy = app.toy_flow.loose_toys()[0]
	var toy_id: String = str(toy.id)
	check(bool(app.toy_flow.queue_tidy(parent, toy_id).ok), "A tidy is queued in a home built on")
	var saved_stages: Array[String] = []
	var save_refused: Array[String] = []
	var seen: Dictionary = {}
	app.household.set_speed(3)
	for frame: int in 6000:
		app._process(DT)
		if frame % 3 == 0: await process_frame
		var stage: String = str((app.toy_flow.stages.get(parent, {}) as Dictionary).get("stage", ""))
		var action: Dictionary = app.household.member_sim(parent).get_current_action()
		if stage.is_empty() and str(action.get("toy_stage", "")) == "done" and str(action.get("phase", "")) == "active": stage = "done"
		if not stage.is_empty() and not seen.has(stage) and (stage != "pickup" or float(app.toy_flow.stages.get(parent, {}).get("t", 0.0)) > .5):
			seen[stage] = true
			var accepted: bool = app.save_game("edges_%s" % stage, "Edges %s" % stage)
			saved_stages.append(stage)
			if not accepted: save_refused.append(stage)
		if app.household.member_sim(parent).get_current_action().is_empty() and seen.has("done"): break
	app.household.set_speed(0)
	check(saved_stages == ["pickup", "carry", "place", "done"] and save_refused.is_empty(), "A save is accepted at every stage of a tidy (%s; refused: %s)" % [str(saved_stages), str(save_refused)])
	# put the toy out again, start a tidy and save while carrying it
	app.toy_flow.unnest(app._find_item(toy_id), Vector3(box.node.position.x + 2.2, .16, box.node.position.z + 1.4))
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(bool(app.toy_flow.queue_tidy(parent, toy_id).ok), "Another tidy is queued")
	check(await run_until(func() -> bool: return str((app.toy_flow.stages.get(parent, {}) as Dictionary).get("stage", "")) == "carry", 4000), "It reaches the carry")
	check(app.save_game("edges_carry2", "Edges carry"), "Saved while carrying")
	app.load_game("edges_carry2"); await frames(4)
	app.set_process(false); app.household.set_speed(0)
	var after: Dictionary = app.household.member_sim(parent).get_current_action()
	toy = app._find_item(toy_id)
	check(not after.is_empty() and str(after.get("id", "")) == "put_pet_toy" and str(after.get("toy_stage", "")) == "fetch", "The loaded tidy begins again (%s)" % str(after.get("toy_stage", "")))
	check(Vector3(after.get("target_position", Vector3.INF)).distance_to(app.world.approach(toy)) < .3, "And heads for the toy, not the box (%s vs %s)" % [str(after.get("target_position", "")), str(app.world.approach(toy))])
	check(await run_until(func() -> bool: return app.toy_flow.is_boxed(app._find_item(toy_id)), 6000), "It is then finished")

	# ---- a box sold while a Lifelet draws from it leaves the next queued action alone
	await boot()
	parent = str(app.household.members[0].id)
	box = await buy("dog_toy_box", Vector3(0, .16, 3.2))
	app.select_household_member(0); await frames(2)
	app.queue_interaction(box, "take_pet_toy")
	check(await run_until(func() -> bool: return str((app.toy_flow.stages.get(parent, {}) as Dictionary).get("stage", "")) == "draw", 4000), "The Lifelet is drawing a toy")
	app.household.member_sim(parent).queue_action("relax", str(app.world.closest_item("sofa", Vector3.ZERO).id), app.world.approach(app.world.closest_item("sofa", Vector3.ZERO)))
	var queued_before: int = app.household.member_sim(parent).action_queue.size()
	app.set_build_mode(true); await frames(2)
	app.sell_item(box); await frames(2)
	app.set_build_mode(false); await frames(2)
	var queue_ids: Array = app.household.member_sim(parent).action_queue.map(func(entry: Dictionary) -> String: return str(entry.id))
	check(queued_before == 2 and queue_ids == ["relax"], "Selling the box ends the draw and keeps the next action (%s)" % str(queue_ids))
	check(app.toy_flow.invariant_errors().is_empty(), "And nothing is left out of step %s" % str(app.toy_flow.invariant_errors()))

	# ---- a save with the older eight-minute put-away still loads
	var older := LifeSim.new()
	older.new_household({"name": "Old", "age_stage": "adult", "traits": []})
	older.autonomy = false
	older.register_targets([{"id": "toy_old", "kind": "pet_toy_dog", "position": Vector3(1, .16, 1)}, {"id": "lot_exit", "kind": "lot_exit", "position": Vector3(0, .16, 8.5)}])
	older.queue_action("put_pet_toy", "toy_old", Vector3(1, .16, 1))
	var old_state: Dictionary = JSON.parse_string(JSON.stringify(older._json_safe(older.get_state())))
	old_state.action_queue[0]["duration"] = 8.0
	var reloaded := LifeSim.new()
	var verdict: Dictionary = reloaded.restore_state(old_state)
	check(bool(verdict.ok), "A save with the eight-minute put-away of an earlier build loads (%s)" % str(verdict.get("error", "")))

	print("TOY_FLOW_EDGES ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
