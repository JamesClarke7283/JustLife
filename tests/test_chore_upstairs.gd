extends SceneTree
## Cleaning a two-storey home: the upper floor gets its own floor patches, an en-suite wet
## room and interior window faces (nothing outside, there is no ladder), every one of them
## reachable by the stairs, and a chore upstairs runs end to end on the upper floor.
const Building = preload("res://scripts/building_state.gd")
const Presets = preload("res://scripts/upstairs_presets.gd")
const Defs = preload("res://scripts/chore_defs.gd")
const DT: float = 1.0 / 30.0
var app: Node
var flow: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i: int in count: await process_frame

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false)
	app.sim.autonomy = false
	app.household.funds = 60000; app.sim.funds = 60000
	var tx: LifeBuildTransactions = app.build_transactions
	var choices: Dictionary = {"choice": 1, "wall_color": "8faf9f", "floor_color": "896953", "roof_color": "56606b", "roof_style": "hipped", "window_style": "c", "door_style": "b", "window_sides": Presets.SIDES.duplicate()}
	var quote: Dictionary = {}
	for operation: Dictionary in Presets.candidates(tx.current().state, choices):
		quote = tx.prepare(operation)
		if bool(quote.ok): break
	check(bool(quote.get("ok", false)), "An upstairs preset can be bought (%s)" % quote.get("error", ""))
	if not bool(quote.get("ok", false)): quit(1); return
	var purchase: Dictionary = tx.commit(quote)
	check(bool(purchase.ok), "...and is built (%s)" % purchase.get("error", ""))
	await frames(4)
	app._refresh_sim_targets()
	flow = app.chore_flow
	flow.chores().reset(); flow.rebuild_stations(true)
	for m: Dictionary in app.household.members:
		m.sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: m.sim.needs[need] = 95.0
	app.household.minutes = 600.0
	var upper: Array = flow.list.filter(func(s: Dictionary) -> bool: return int(s.level) == 1)
	var lower: Array = flow.list.filter(func(s: Dictionary) -> bool: return int(s.level) == 0)
	check(not upper.is_empty() and not lower.is_empty(), "Both floors have things to clean (%d upstairs, %d downstairs)" % [upper.size(), lower.size()])
	var upper_floor: int = upper.filter(func(s: Dictionary) -> bool: return str(s.chore) in ["chore_vacuum", "chore_mop"]).size()
	check(upper_floor >= 4, "The upper floor is cut into patches to vacuum and mop (%d)" % upper_floor)
	check(upper.filter(func(s: Dictionary) -> bool: return str(s.chore) == "chore_wash_window" and bool(s.outdoor)).is_empty(), "No upstairs window is washed from outside: there is no ladder")
	# Put a toilet in the en-suite: its room becomes a wet room of its own.
	var ensuite: Dictionary = {}
	for room: Dictionary in app.world.construction.snapshot().upstairs_preset.rooms:
		if str(room.kind) == "ensuite": ensuite = room; break
	check(not ensuite.is_empty(), "The preset has an en-suite")
	var placed: bool = false
	for dx: float in [0.0, .5, -.5, 1.0, -1.0]:
		for dz: float in [0.0, .5, -.5, 1.0, -1.0]:
			if placed: continue
			var at: Vector3 = Vector3(float(ensuite.x) + dx, Building.level_y(1), float(ensuite.z) + dz)
			if app.world.can_place("toilet", at, 0.0):
				app.world.add_item({"id": "toilet_up", "kind": "toilet", "x": at.x, "z": at.z, "rotation": 0.0, "level": 1})
				placed = true
	check(placed, "A toilet fits in the en-suite")
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	flow.rebuild_stations(true)
	upper = flow.list.filter(func(s: Dictionary) -> bool: return int(s.level) == 1)
	var wet_upper: Array = upper.filter(func(s: Dictionary) -> bool: return bool(s.wet))
	check(not wet_upper.is_empty(), "The en-suite is a wet room of its own upstairs (%d stations)" % wet_upper.size())
	check(upper.filter(func(s: Dictionary) -> bool: return str(s.chore) == "chore_scrub_toilet").size() == 1, "...with a toilet to scrub")
	var reachable: int = 0
	var usable: int = 0
	for station: Dictionary in upper:
		if not bool(station.ok): continue
		usable += 1
		if not app.world.path_to(app.player.position, station.position).is_empty(): reachable += 1
	check(usable > 0 and reachable == usable, "Every usable upstairs station can be walked to over the stairs (%d of %d)" % [reachable, usable])
	var level_ok: bool = true
	for station: Dictionary in upper:
		if bool(station.ok) and absf(float(station.position.y) - Building.level_y(1)) > .03: level_ok = false
	check(level_ok, "Their stands are on the upper floor")
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 6.0 * 1440.0
	var pick: Dictionary = {}
	for station: Dictionary in upper:
		if str(station.chore) == "chore_vacuum" and bool(station.ok): pick = station; break
	check(not pick.is_empty(), "There is an upstairs patch to vacuum")
	var sim: LifeSim = app.sim
	check(sim.queue_action("chore_vacuum", str(pick.id), pick.position), "It queues")
	app.household.set_speed(8)
	var upstairs: bool = false
	var active: bool = false
	for frame: int in 12000:
		app._process(DT)
		var action: Dictionary = sim.get_current_action()
		if not action.is_empty() and str(action.phase) == "active" and not active:
			active = true
			upstairs = absf(app.player.global_position.y - Building.level_y(1)) < .05
		if sim.action_queue.is_empty() and frame > 30: break
	app.household.set_speed(0)
	check(active and upstairs, "Ada climbs the stairs and works on the upper floor")
	check(flow.dirt_of(pick) < 1.0, "The upstairs patch is clean afterwards (%.0f%%)" % flow.dirt_of(pick))
	# A round that spans both floors.
	for m: Dictionary in app.household.members:
		for need: String in LifeSim.NEED_NAMES: m.sim.needs[need] = 95.0
	var plan: Dictionary = flow.make_plan(sim, "inside")
	var floors_seen: Dictionary = {}
	for entry: Dictionary in plan.entries:
		var station: Dictionary = flow.stations.get(str(entry.target), {})
		if not station.is_empty(): floors_seen[int(station.level)] = true
	check(floors_seen.has(0) and floors_seen.has(1), "A full round covers both floors (%d tasks)" % int(plan.count))
	print("CHORE_UPSTAIRS %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
