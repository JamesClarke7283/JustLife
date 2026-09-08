extends SceneTree
## Headless business-logic regressions. Run with a private XDG_DATA_HOME.
## Uses controlled simulator time/arrivals and a minimal world with straight paths.
## This suite makes no rendering, collision, natural-spoil-time or UI-flow claim.

class TestWorld:
	extends Node3D
	var actors: Dictionary = {}
	var items: Array = []
	func closest_item(kind: String, from: Vector3, maximum: float = 100.0) -> Dictionary:
		var nearest: Dictionary = {}
		for entry: Dictionary in items:
			var distance: float = entry.node.position.distance_to(from)
			if entry.kind == kind and distance < maximum:
				nearest = entry
				maximum = distance
		return nearest
	func approach(entry: Dictionary) -> Vector3:
		return entry.node.position
	func path_to(from: Vector3, to: Vector3) -> PackedVector3Array:
		return PackedVector3Array([from, to])
	func activity_anchor(entry: Dictionary, _action: String, _landmarks: Dictionary) -> Dictionary:
		return {"position": entry.node.to_global(Vector3(0, .52, .02)), "yaw": entry.node.rotation.y, "kind": "seat"}

class TestApp:
	extends Node
	var household: LifeHousehold
	var world: TestWorld
	var current_venue: String = "home"
	var pending_move: Dictionary = {}
	func _find_item(id: String) -> Dictionary:
		for entry: Dictionary in world.items:
			if entry.id == id:
				return entry
		return {}

var cases: Array = []
var failures: int = 0
var slots: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	cases.append({"case": label, "passed": ok})
	if not ok:
		failures += 1
	print("CHECK ", "PASS " if ok else "FAIL ", label)

func same_json(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) <= 1e-10
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_json(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index: int in range(a.size()):
			if not same_json(a[index], b[index]): return false
		return true
	return a == b

func add_item(f: Dictionary, id: String, kind: String, at: Vector3) -> Dictionary:
	var node: Node3D = Node3D.new()
	f.world.add_child(node)
	node.position = at
	var entry: Dictionary = {"id": id, "kind": kind, "node": node}
	f.world.items.append(entry)
	return entry

func fixture() -> Dictionary:
	var box: Node = Node.new()
	root.add_child(box)
	var home: LifeHousehold = LifeHousehold.new()
	box.add_child(home)
	home.new_household([{"name": "A", "age_stage": "adult", "traits": []}, {"name": "B", "age_stage": "adult", "traits": []}])
	var world: TestWorld = TestWorld.new()
	box.add_child(world)
	var app: TestApp = TestApp.new()
	box.add_child(app)
	app.household = home
	app.world = world
	var flow: LifeMealFlow = LifeMealFlow.new()
	box.add_child(flow)
	flow.app = app
	for member: Dictionary in home.members:
		member.sim.autonomy = false
		member.sim.needs.hunger = 30.0
		member.sim.meal_service = flow
		var avatar: LifeActor = LifeActor.new()
		avatar._model = Node3D.new()
		avatar.add_child(avatar._model)
		world.add_child(avatar)
		avatar.position = Vector3(0, .16, -.95)
		world.actors[member.id] = avatar
		member.sim.action_started.connect(func(action: Dictionary): flow.resolve(member.sim, action))
	var f: Dictionary = {"box": box, "home": home, "world": world, "app": app, "flow": flow}
	f.table = add_item(f, "dining", "dining", Vector3(0, .16, 0))
	add_item(f, "chair", "chair", Vector3(0, .16, -.95))
	add_item(f, "fridge", "fridge", Vector3(-3, .16, 0))
	add_item(f, "sink", "sink", Vector3(3, .16, 0))
	return f

func place(value: Dictionary, host: Node3D, local: Vector3) -> void:
	var at: Vector3 = host.to_global(local)
	value.offset = [local.x, local.y, local.z]
	value.position = [at.x, at.y, at.z]

func batch(f: Dictionary) -> Dictionary:
	var meal: Dictionary = f.home.meals.create_batch("garden_skillet", "player", 1, "home", 480)
	f.home.meals.set_batch_location(meal.id, "surface", "dining", Vector3(0, 1.007, 0), 480)
	place(meal, f.table.node, Vector3(0, .847, 0))
	return meal

func partial(f: Dictionary, fraction: float = .3700123456789, storage: String = "table") -> Dictionary:
	var meal: Dictionary = batch(f)
	var plate: Dictionary = f.home.meals.claim(meal.id, "player", 480)
	f.home.meals.eat(plate.id, "player", fraction * 32.0, 480)
	var action: Dictionary = f.home.selected().get_action_definition("eat_meal")
	action.merge({"target_id": "chair", "target_position": Vector3(0, .16, -.95), "phase": "active" if storage == "table" else "approach", "elapsed": fraction * 32.0, "progress": fraction, "paid": true, "autonomous": false, "started_day": 1, "started_minutes": 480 - fraction * 32.0, "meal_source": meal.id, "meal_stage": "eat", "meal_plate": plate.id, "meal_seat": "chair" if storage == "table" else ""}, true)
	if storage == "table":
		f.home.meals.put_portion(plate.id, "dining", "chair", f.table.node.to_global(Vector3(0, .847, -.39)), true, Vector3(0, .847, -.39))
	if storage == "surface":
		f.home.meals.release_member("player", Vector3(0, .16, 0))
	else:
		f.home.selected().action_queue = [action]
	return plate

func snapshot(f: Dictionary) -> Dictionary:
	var layout: Array = []
	for entry: Dictionary in f.world.items:
		layout.append({"id": entry.id, "kind": entry.kind, "x": entry.node.position.x, "z": entry.node.position.z, "rotation": entry.node.rotation_degrees.y})
	return JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(f.home.get_state(layout))))

func named_roundtrip(saved: Dictionary, label: String) -> Dictionary:
	var id: String = "meal_state_" + str(Time.get_ticks_usec()) + "_" + str(slots.size())
	slots.append(id)
	var result: Dictionary = LifeSaveLibrary.save_slot(id, label, saved)
	check(bool(result.ok), label + ": named write")
	var read: Dictionary = LifeSaveLibrary.read_slot(id)
	check(bool(read.ok) and same_json(read.get("data", {}).get("meals", {}), saved.meals), label + ": JSON preserves exact food state")
	return read

func reject_atomically(f: Dictionary, bad: Dictionary, label: String) -> void:
	var before: Dictionary = snapshot(f)
	var result: Dictionary = f.home.restore_state(bad)
	check(not bool(result.ok), label + ": restore rejects")
	check(same_json(snapshot(f), before), label + ": household is unchanged")

func conservation() -> void:
	var ledger: LifeMeals = LifeMeals.new()
	var dish: Dictionary = ledger.create_batch("garden_skillet", "a", 1, "home", 480)
	ledger.set_batch_location(dish.id, "surface", "table", Vector3.ZERO, 480)
	ledger.claim(dish.id, "a", 480)
	check(ledger.claim(dish.id, "a", 480).is_empty() and dish.remaining == 3 and ledger.portions.size() == 1, "An existing carrier cannot claim another available serving")
	for person: String in ["b", "c"]: ledger.claim(dish.id, person, 480)
	var fourth: Dictionary = ledger.claim(dish.id, "d", 480)
	check(not fourth.is_empty() and ledger.claim(dish.id, "e", 480).is_empty() and dish.remaining == 0 and dish.served == 4 and ledger.portions.size() == 4, "Only one arrival receives the last serving")
	var storing: LifeMeals = LifeMeals.new()
	var moved: Dictionary = storing.create_batch("garden_skillet", "a", 1, "home", 480)
	storing.set_batch_location(moved.id, "surface", "table", Vector3.ZERO, 480)
	check(storing.set_batch_location(moved.id, "carried", "", Vector3.ZERO, 481, "a") and not storing.set_batch_location(moved.id, "carried", "", Vector3.ZERO, 481, "b") and moved.owner == "a", "Second storer cannot steal the carried serving dish")

func ownership_and_cancel() -> void:
	var f: Dictionary = fixture()
	var plate: Dictionary = partial(f, .5)
	var good: Dictionary = snapshot(f)
	var baseline: Dictionary = named_roundtrip(good, "partial ownership")
	check(bool(baseline.ok), "Partial-plate positive control is valid before corruption")
	for fault: String in ["progress", "owner", "orphan", "source", "company", "count"]:
		var bad: Dictionary = good.duplicate(true)
		match fault:
			"progress":
				bad.members[0].state.action_queue[0].elapsed = 0.0
				bad.members[0].state.action_queue[0].progress = 0.0
			"owner": bad.meals.portions[0].owner = "housemate_1"
			"orphan": bad.members[0].state.action_queue.clear()
			"source": bad.members[0].state.action_queue[0].meal_source = "meal_999999"
			"company": bad.meals.portions[0].company = ["housemate_1", "housemate_1"]
			"count": bad.meals.batches[0].remaining = 4
		reject_atomically(f, bad, "Malformed " + fault)
	var later: Dictionary = f.home.selected().get_action_definition("clean_plate")
	later.merge({"target_id": "unrelated_plate", "target_position": Vector3.ZERO, "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false}, true)
	f.home.selected().action_queue.append(later)
	f.home.selected().cancel_action(1)
	check(plate.owner == "player" and plate.progress == .5 and f.home.selected().action_queue.size() == 1, "Canceling a future wash preserves the active diner's plate")
	var eat: Dictionary = f.home.selected().get_current_action()
	plate.progress = 31.0 / 32.0; plate.expires = 479.0; eat.elapsed = 31.0; eat.progress = plate.progress
	var painting: Dictionary = f.home.selected().get_action_definition("paint")
	painting.merge({"target_id": "easel", "target_position": Vector3.ZERO, "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false}, true)
	f.home.selected().action_queue.append(painting)
	var funds: int = f.home.funds
	f.home.selected()._step(1.0)
	check(f.home.funds == funds and f.home.selected().get_current_action().get("id") == "paint" and painting.elapsed == 0.0 and plate.progress == 31.0 / 32.0, "Expired last bite cancels itself without completing or paying the next painting")
	f.box.queue_free()

func partial_restart() -> void:
	for storage: String in ["table", "carried", "surface"]:
		var original: Dictionary = fixture()
		partial(original, .3700123456789, storage)
		var saved: Dictionary = snapshot(original)
		var read: Dictionary = named_roundtrip(saved, "partial " + storage)
		var resumed: Dictionary = fixture()
		var result: Dictionary = resumed.home.restore_state(read.get("data", {}))
		check(bool(result.ok), storage + ": new household restores")
		if bool(result.ok):
			var person: String = "housemate_1" if storage == "surface" else "player"
			var sim: LifeSim = resumed.home.member_sim(person)
			sim.meal_service = resumed.flow
			var plate: Dictionary = resumed.home.meals.portions[0]
			var fraction: float = plate.progress
			if storage == "surface":
				check(sim.queue_action("eat_meal", plate.id, Vector3.ZERO), "Another Lifelet can queue the unowned partial plate")
				resumed.flow.resolve(sim, sim.get_current_action())
				sim.begin_current_action()
				check(plate.owner == person and absf(sim.get_current_action().elapsed - fraction * 32.0) < 1e-8, "Partial pickup transfers ownership without resetting elapsed")
			sim.begin_current_action()
			var hunger: float = sim.needs.hunger
			var funds: int = resumed.home.funds
			var remaining: float = (1.0 - fraction) * 32.0
			var left: float = remaining
			while left > 1e-9:
				var step: float = minf(1.0, left)
				sim._step(step)
				left -= step
			var nutrition: float = sim.needs.hunger - hunger + float(LifeSim.NEED_DECAY.hunger) * remaining / 60.0
			check(absf(nutrition - (1.0 - fraction) * 70.0) < 1e-6, storage + ": only remaining nutrition is granted")
			check(sim.action_queue.is_empty() and plate.storage == "dirty" and plate.owner == "" and plate.progress == 1.0 and resumed.home.meals.portions.size() == 1 and resumed.home.meals.batches[0].remaining == 3 and resumed.home.funds == funds, storage + ": one dirty plate, no duplicate serving or payment")
		original.box.queue_free(); resumed.box.queue_free()

func support_and_malformed() -> void:
	var f: Dictionary = fixture()
	var plate: Dictionary = partial(f)
	f.home.selected().action_queue.clear(); plate.owner = ""; plate.storage = "dirty"; plate.progress = 1.0; plate.seat = ""
	f.table.node.position = Vector3(1.25, .16, -2.5)
	f.table.node.rotation_degrees.y = 37
	for support: Dictionary in [{"kind": "dining", "height": .847, "plate_x": .64, "dish_z": .382}, {"kind": "counter", "height": .952, "plate_x": .365, "dish_z": .212}, {"kind": "stove", "height": .997, "plate_x": .35, "dish_z": .207}]:
		f.table.kind = support.kind
		place(f.home.meals.batches[0], f.table.node, Vector3(0, support.height, support.dish_z))
		place(plate, f.table.node, Vector3(support.plate_x, support.height, 0))
		var good: Dictionary = snapshot(f)
		named_roundtrip(good, "Rotated " + support.kind + " plate and platter edges")
		for collection: String in ["portions", "batches"]:
			var bad: Dictionary = good.duplicate(true)
			var value: Dictionary = bad.meals[collection][0]
			place(value, f.table.node, Vector3(float(value.offset[0]) + .04 if collection == "portions" else 0, support.height, float(value.offset[2]) + .04 if collection == "batches" else 0))
			reject_atomically(f, bad, support.kind + " matching-transform " + collection + " overhang")
	var good: Dictionary = snapshot(f)
	for bad_offset: Variant in ["invalid", [0, 0], [0, NAN, 0], [0, INF, 0], [0, 2.0, 0]]:
		var bad: Dictionary = good.duplicate(true); bad.meals.portions[0].offset = bad_offset
		reject_atomically(f, bad, "Malformed/nonfinite support " + str(bad_offset))
	for bad_rotation: Variant in ["east", NAN, INF]:
		var bad: Dictionary = good.duplicate(true); bad.world[0].rotation = bad_rotation
		reject_atomically(f, bad, "Malformed/nonfinite host rotation " + str(bad_rotation))
	var inconsistent: Dictionary = good.duplicate(true); inconsistent.meals.portions[0].position[0] += .04
	reject_atomically(f, inconsistent, "In-range offset/world position mismatch")
	f.box.queue_free()

func transport_and_spoil() -> void:
	for kind: String in ["serve_meal", "store_meal", "clean_plate", "discard_meal"]:
		var f: Dictionary = fixture()
		var meal: Dictionary = batch(f)
		var source: String = meal.id
		var stage: String = "pickup"
		if kind == "clean_plate":
			var plate: Dictionary = f.home.meals.claim(meal.id, "player", 480)
			f.home.meals.finish_portion(plate.id)
			plate.owner = "player"; plate.storage = "carried"
			source = plate.id; stage = "wash"
		else:
			f.home.meals.set_batch_location(meal.id, "carried", "", Vector3.ZERO, 480, "player")
			if kind == "store_meal": stage = "store"
			if kind == "discard_meal": stage = "discard"
		var action: Dictionary = f.home.selected().get_action_definition(kind)
		action.merge({"target_id": "sink" if kind in ["clean_plate", "discard_meal"] else "fridge" if kind == "store_meal" else "dining", "target_position": Vector3.ZERO, "phase": "approach", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false, "meal_source": source, "meal_stage": stage}, true)
		f.home.selected().action_queue = [action]
		var good: Dictionary = snapshot(f)
		var read: Dictionary = named_roundtrip(good, kind + " owned transport")
		for key: String in ["meal_plate", "meal_seat"]:
			var bad: Dictionary = good.duplicate(true); bad.members[0].state.action_queue[0][key] = "wrong_identity"
			var slot: String = slots[-1]
			var denied: Dictionary = LifeSaveLibrary.save_slot(slot, "invalid transport", bad)
			var after: Dictionary = LifeSaveLibrary.read_slot(slot)
			check(not bool(denied.ok) and bool(after.ok) and same_json(after.data, read.get("data", {})), kind + ": malformed " + key + " cannot replace named save")
		f.home.selected().cancel_action()
		check(f.home.meals.carried_by("player").is_empty() and f.home.selected().action_queue.is_empty(), kind + ": cancel releases only the current transported food")
		f.box.queue_free()
	for storage: String in ["surface", "fridge"]:
		var f: Dictionary = fixture()
		var meal: Dictionary = batch(f)
		if storage == "fridge":
			f.home.meals.set_batch_location(meal.id, "fridge", "fridge", Vector3(-3, .16, 0), 480)
			meal.offset = [0, 0, 0]
		meal.expires = 479.0 # Isolate spoil clearing; natural expiry timing is not tested here.
		check(not f.flow.action_availability(f.home.selected(), "eat_meal", meal.id).is_empty(), storage + ": spoiled meal cannot be eaten")
		check(f.home.selected().queue_action("discard_meal", meal.id, Vector3.ZERO), storage + ": spoiled meal queues clearing")
		f.home.selected().begin_current_action()
		check(meal.owner == "player" and meal.storage == "carried", storage + ": discard pickup has one carrier")
		var funds: int = f.home.funds
		var hunger: float = f.home.selected().needs.hunger
		f.home.selected().begin_current_action()
		var duration: float = f.home.selected().get_current_action().duration
		f.home.selected()._step(duration)
		check(f.home.meals.batches.is_empty() and f.home.funds == funds and f.home.selected().needs.hunger <= hunger, storage + ": discard clears without serving or payment")
		f.box.queue_free()

func run() -> void:
	conservation()
	ownership_and_cancel()
	partial_restart()
	support_and_malformed()
	transport_and_spoil()
	await process_frame
	for slot: String in slots:
		LifeSaveLibrary.delete_slot(slot)
	var output: FileAccess = FileAccess.open("user://test_meal_state_results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"scope": "Controlled meal business logic, named JSON saves and real layout transforms; no rendering or navigation claim.", "assertions": cases.size(), "failures": failures, "cases": cases}, "\t"))
	output.close()
	print("MEAL_STATE assertions=%d failures=%d" % [cases.size(), failures])
	quit(1 if failures else 0)
