extends SceneTree
## A Lifelet is sent to a pool toy from their own card and really fetches it: walks
## to it, picks it up, carries it round the water to the edge, gets in with it in
## swimwear and rides it — sitting in the ring, or chest-down over the noodle with
## the legs kicking and the hands paddling — then climbs out dripping.
##
##   JUSTLIFE_DATA_DIR=/tmp/x XDG_DATA_HOME=/tmp/y godot --headless --path . --audio-driver Dummy --script res://tests/test_pool_toys.gd

const DT: float = 1.0 / 20.0

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("This test needs an isolated JUSTLIFE_DATA_DIR.")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}, {"name": "Ada Vale", "age_stage": "young_adult", "life_stage": "adult", "traits": ["Creative"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_funds(20000)
	app.household.set_speed(3)
	# What happens is the toy flow's doing, not the morning commute's or the school run's.
	for member: Dictionary in app.household.members: member.sim.autonomy = false
	var pool: Dictionary = _place("pool", [Vector2(-12, 4), Vector2(12, 4), Vector2(-12, -8), Vector2(12, -8), Vector2(-13, 0)])
	check(not pool.is_empty(), "A pool fits in the garden.")
	if pool.is_empty():
		_finish()
		return
	var ring: Dictionary = _beside(pool, "pool_ring", [Vector2(3.6, 0), Vector2(-3.6, 0), Vector2(0, 3.2), Vector2(0, -3.2), Vector2(4.4, 1.5), Vector2(-4.4, 1.5)])
	var noodle: Dictionary = _beside(pool, "pool_noodle", [Vector2(3.6, 1.6), Vector2(-3.6, 1.6), Vector2(1.6, 3.2), Vector2(1.6, -3.2), Vector2(4.4, -1.5), Vector2(-4.4, -1.5)])
	check(not ring.is_empty() and not noodle.is_empty(), "A rubber ring and a pool noodle lie on the deck beside it.")
	if ring.is_empty() or noodle.is_empty():
		_finish()
		return
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	await frames(2)
	await _fetch_and_ride(pool, ring, "pool_ring")
	await _fetch_and_ride(pool, noodle, "pool_noodle")
	await _panel(pool, ring)
	await _housemate(pool, noodle)
	_finish()


func _finish() -> void:
	print("POOL_TOYS %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: print("  FAILED: ", failure)
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)


func _place(kind: String, spots: Array) -> Dictionary:
	for spot: Vector2 in spots:
		var at := Vector3(spot.x, LifeBuildingState.level_y(0), spot.y)
		if app.world.can_place(kind, at, 0.0):
			var id: String = "toy_%s" % kind
			app.world.add_item({"id": id, "kind": kind, "x": at.x, "z": at.z, "rotation": 0})
			return app._find_item(id)
	return {}


func _beside(pool: Dictionary, kind: String, offsets: Array) -> Dictionary:
	var centre: Vector3 = pool.node.global_position
	for offset: Vector2 in offsets:
		var at := Vector3(centre.x + offset.x, LifeBuildingState.level_y(0), centre.z + offset.y)
		if app.world.can_place(kind, at, 0.0):
			var id: String = "toy_%s" % kind
			app.world.add_item({"id": id, "kind": kind, "x": at.x, "z": at.z, "rotation": 0})
			return app._find_item(id)
	return {}


## Where the middle of a toy is. The noodle's own origin is at one end of it.
func _middle(toy: Dictionary) -> Vector3:
	var node: Node3D = toy.node
	return node.global_position - node.global_basis.x * .6 if str(toy.kind) == "pool_noodle" else node.global_position


func _in_water(pool: Dictionary, at: Vector3) -> bool:
	for panel: Rect2 in app.world.item_panels(pool):
		if panel.grow(-.05).has_point(Vector2(at.x, at.z)): return true
	return false


func _step(count: int) -> void:
	for i: int in count:
		app._process(DT)


func _fetch_and_ride(pool: Dictionary, toy: Dictionary, kind: String) -> void:
	var id: String = app.household.selected_id()
	var person: LifeActor = app.world.actors[id]
	var sim: LifeSim = app.sim
	sim.action_queue.clear()
	sim.wetness = 0.0
	LifeCharacterIdentity.apply_category(sim.character, "everyday")
	var label: String = "ring" if kind == "pool_ring" else "noodle"
	# It is offered on the Lifelet's own card and only lists toys that can be used.
	var options: Array = app.water_flow.toy_options(id)
	var listed: bool = false
	for option: Dictionary in options:
		if str(option.id) == str(toy.id) and bool(option.available): listed = true
	check(listed, "The %s is offered on the Lifelet's toy panel." % label)
	check(not app._pool_toy_action(id).is_empty() and bool(app._pool_toy_action(id).available), "The Lifelet's card offers 'Use pool toy…'.")
	var result: Dictionary = app.water_flow.queue_toy(id, str(toy.id))
	check(bool(result.ok), "The %s is queued (%s)." % [label, str(result.get("error", ""))])
	check(str(sim.character.outfit_category) == "swim", "Choosing a toy puts on swimwear (%s)." % str(sim.character.outfit_category))
	var seen: Dictionary = {}
	var rest: Vector3 = toy.node.global_position
	var picked_near: float = INF
	var carried_gap: Array[float] = []
	var walked_through_water: bool = false
	var swim_frames: int = 0
	var toy_height: float = INF
	var toy_in_water: bool = false
	var lean: float = 0.0
	var anchor_kind: String = ""
	var dripping: bool = false
	for frame: int in range(2600):
		app._process(DT)
		var action: Dictionary = sim.get_current_action()
		if action.is_empty() and frame > 20: break
		var stage: String = str(action.get("toy_stage", "")) if not action.is_empty() else ""
		var phase: String = str(action.get("phase", "")) if not action.is_empty() else ""
		seen[stage + "/" + phase] = true
		var presented: String = str(person.water_presentation.get("stage", ""))
		if presented == "pickup":
			picked_near = minf(picked_near, person.global_position.distance_to(rest))
		if presented == "carry" and not seen.has("saved_layout"):
			# Saved mid-carry, the toy is written where it was picked up from and the
			# layout still loads: never a point in the air or over the water.
			seen["saved_layout"] = true
			var record: Dictionary = {}
			for entry: Dictionary in app.world.serialize_items():
				if str(entry.get("id", "")) == str(toy.id): record = entry
			check(not record.is_empty() and Vector2(float(record.x) - rest.x, float(record.z) - rest.z).length() < .01, "A toy saved mid-carry keeps the place it was picked up from.")
			check(app.world.validate_home_layout(app.world.serialize_items()).is_empty(), "The layout saved mid-carry passes validation.")
		if presented == "carry":
			var held: Vector3 = _middle(toy) - person.global_position
			# In the arms: close in front of them, at about chest height.
			carried_gap.append(Vector2(held.x, held.z).length() if held.y > .8 and held.y < 1.7 else 99.0)
			if _in_water(pool, person.global_position): walked_through_water = true
		if stage == "swim" and phase == "active":
			swim_frames += 1
			if swim_frames == 60:
				toy_height = _middle(toy).y
				toy_in_water = _in_water(pool, _middle(toy))
				lean = person.visual.rotation.x
				anchor_kind = str(person._activity_anchor.get("kind", ""))
	check(seen.has("fetch/approach") or seen.has("fetch/queued"), "The Lifelet first goes to fetch the %s." % label)
	check(seen.has("pickup/approach"), "Arriving, they stop to pick the %s up." % label)
	check(picked_near < 1.4, "They are right beside the %s when they pick it up (%.2f m)." % [label, picked_near])
	check(seen.has("carry/approach"), "They carry it to the pool.")
	var worst_gap: float = 0.0
	for gap: float in carried_gap: worst_gap = maxf(worst_gap, gap)
	check(not carried_gap.is_empty() and worst_gap < 1.0, "The %s is in their arms while they carry it (%d frames, worst gap %.2f)." % [label, carried_gap.size(), worst_gap])
	check(not walked_through_water, "The carry goes round the water, never across it.")
	check(seen.has("enter/approach"), "At the edge they step into the water with it.")
	check(swim_frames >= 100, "Then they ride it for the length of the activity (%d frames)." % swim_frames)
	check(toy_in_water and toy_height < .5, "While they ride it the %s floats in the pool (y %.2f)." % [label, toy_height])
	if kind == "pool_ring":
		check(anchor_kind == "seat" and lean < -.3, "In the ring they sit reclined in its opening (%s, lean %.2f)." % [anchor_kind, lean])
	else:
		check(anchor_kind == "swim" and lean > 1.0, "On the noodle they lie chest-down along the water (%s, lean %.2f)." % [anchor_kind, lean])
	check(bool(sim.get_current_action().is_empty()) or str(sim.get_current_action().id) != LifeOutdoorActs.ACTION_ID, "The swim ends.")
	check(not bool(toy.get("carried", false)), "The %s is put down at the end." % label)
	check(not _in_water(pool, _middle(toy)), "…on the deck, not left in the water.")
	check(sim.wetness > .5, "The Lifelet comes out wet (%.2f)." % sim.wetness)
	check(str(sim.character.outfit_category) == "swim", "Still in swimwear until dry.")
	person.animate(.02, 1.0, false, "")
	check(person._drips.emitting, "Water drips off them as they climb out.")


func _panel(pool: Dictionary, ring: Dictionary) -> void:
	app.show_pool_toys(app.household.selected_id())
	await frames(2)
	var found: Button = null
	for node: Node in app.overlay.find_children("UsePoolToy_*", "Button", true, false):
		found = node
	check(found != null, "The toy panel lists each toy with its own button.")
	app.close_overlay()


## Clicking a housemate offers the same panel, and they take the toy too.
func _housemate(pool: Dictionary, toy: Dictionary) -> void:
	var other: String = ""
	for member: Dictionary in app.household.members:
		if str(member.id) != app.household.selected_id(): other = str(member.id)
	check(not other.is_empty(), "There is a second Lifelet in the household.")
	if other.is_empty(): return
	var actor_node: LifeActor = app.world.actors[other]
	var teen: LifeSim = app.household.member_sim(other)
	teen.action_queue.clear()
	var entry: Dictionary = app._pool_toy_action(other)
	check(not entry.is_empty() and bool(entry.available), "A housemate is offered 'Use pool toy…' too.")
	app.show_interactions({"id": other, "kind": "neighbor", "label": "Ada Vale"}, Vector2(600, 400))
	await frames(2)
	var listed: bool = false
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if (node as Button).text == "Use pool toy…": listed = true
	check(listed, "The housemate's click menu lists 'Use pool toy…'.")
	app.close_overlay()
	var queued: Dictionary = app.water_flow.queue_toy(other, str(toy.id))
	check(bool(queued.ok), "The housemate can be sent to the noodle (%s)." % str(queued.get("error", "")))
	for frame: int in range(1500):
		app._process(DT)
		if teen.action_queue.is_empty() and frame > 20: break
	check(teen.wetness > .5 and str(teen.character.outfit_category) == "swim", "The housemate swam in swimwear and came out wet.")
