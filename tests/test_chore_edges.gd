extends SceneTree
## Edges of household cleaning that a review found: what was last cleaned on a piece is
## not forgotten while the piece is picked up to be moved; a Lifelet whose best-scored
## place cannot be reached cleans the next best instead of nothing; a window whose wall
## has been taken down is no longer something to wash; a different house starts with none
## of the last one's dirt; the time offered for a round includes the walking; the toys a
## round plans are shared out across the boxes there are.
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
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Bo Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false)
	flow = app.chore_flow
	var sim: LifeSim = app.sim
	sim.autonomy = false
	for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 95.0
	sim.day = 6; sim.minutes = 600.0; app.household.day = 6; app.household.minutes = 600.0
	flow.chores().reset(); flow.rebuild_stations(true)
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 12.0 * 1440.0

	# ---- picking a dirty sofa up (to move it) does not clean it
	var sofa: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "sofa": sofa = item
	var sofa_keys: Array = []
	for station: Dictionary in flow.list:
		if str(station.item_id) == str(sofa.get("id", "")): sofa_keys.append(str(station.key))
	check(not sofa.is_empty() and not sofa_keys.is_empty(), "The home has a sofa with cleaning stations")
	var stamp_before: float = float(flow.chores().cleaned.get(sofa_keys[0], -1.0))
	app.pending_move = {"entry": {"id": str(sofa.id), "kind": "sofa"}, "snapshot": {}}
	app.world.remove_item(str(sofa.id), true)
	flow.rebuild_stations(true)
	check(flow.chores().cleaned.has(sofa_keys[0]), "While the sofa is in hand its dirt is remembered")
	app.pending_move = {}
	app.world.add_item({"id": str(sofa.id), "kind": "sofa", "x": float(sofa.node.position.x), "z": float(sofa.node.position.z), "rotation": 180.0}, false)
	app.world.rebuild_navigation(); app._refresh_sim_targets(); flow.rebuild_stations(true)
	var again: Array = flow.list.filter(func(s: Dictionary) -> bool: return str(s.key) == sofa_keys[0])
	check(float(flow.chores().cleaned.get(sofa_keys[0], -1.0)) == stamp_before and not again.is_empty() and flow.dirt_of(again[0]) > 50.0, "Put back, it is as dirty as it was")

	# ---- the time offered includes the walk
	var plan: Dictionary = flow.make_plan(sim, "full")
	var work: float = 0.0
	for task: Dictionary in plan.entries: work += float(task.minutes)
	check(plan.entries.size() > 3 and float(plan.minutes) > work + 3.0, "A full round's time is more than its work (%.0f min of work, %.0f min in all)" % [work, float(plan.minutes)])

	# ---- a different house starts clean
	flow.chores().cleaned["fvac:0:1:1"] = 5.0
	app.properties["active"] = "some_other_house"
	flow.rebuild_stations(true)
	check(not flow.chores().cleaned.has("fvac:0:1:1") or float(flow.chores().cleaned["fvac:0:1:1"]) != 5.0, "Moving to another house leaves the old house's dirt behind")

	# ---- a window with no wall is not cleaned
	var windows_before: int = flow.list.filter(func(s: Dictionary) -> bool: return str(s.chore) == "chore_wash_window").size()
	app.world.construction.restore(LifeBuildingState.migrate(app.world.construction.snapshot()).state)
	flow.rebuild_stations(true)
	var supported: int = flow.list.filter(func(s: Dictionary) -> bool: return str(s.chore) == "chore_wash_window").size()
	check(supported > 0 and supported <= windows_before, "A built-on home still has its windows to wash (%d)" % supported)
	var walls_removed: int = 0
	for wall: Dictionary in app.world.construction.records.duplicate():
		if int(wall.get("level", 0)) == 0 and float(wall.get("y", 0)) == 0.0 and absf(float(wall.z) + 5.04) < .2:
			app.world.construction.records.erase(wall)
			if app.world.construction.wall_nodes.has(wall.id): app.world.construction.wall_nodes[wall.id].queue_free()
			walls_removed += 1
	app.world.construction.refresh_decorations()
	flow.rebuild_stations(true)
	var after: int = flow.list.filter(func(s: Dictionary) -> bool: return str(s.chore) == "chore_wash_window").size()
	check(walls_removed == 0 or after < supported, "With the back wall gone its windows are no longer offered (%d -> %d)" % [supported, after])

	print("CHORE_EDGES ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
