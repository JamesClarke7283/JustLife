extends SceneTree
## Every chore in the running game: queued from a click at its station, walked to, played
## on the real actor with the right tool in hand, finished, and its zone left clean. The
## hands are measured against the tool's grips on frames throughout; a paused chore is
## frozen exactly; a cancelled one puts everything back.
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
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

func visible_tools(actor: LifeActor) -> Array:
	var out: Array = []
	if not is_instance_valid(actor._chore_props): return out
	for key: String in actor._chore_props._tools:
		if actor._chore_props._tools[key].visible: out.append(key)
	return out

func hand_error(actor: LifeActor) -> float:
	var plan: Dictionary = actor._activity_anchor.get("chore_plan", {})
	var worst: float = 0.0
	for side: String in plan.get("hands", {}):
		var hand: Dictionary = plan.hands[side]
		var wanted: Vector3 = hand.world if hand.has("world") else actor._model.to_global(hand.local)
		worst = maxf(worst, actor.palm_world(side).distance_to(wanted))
	return worst

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false)
	app.world.add_item({"id": "cur_live", "kind": "curtains", "x": -5.88, "z": 2.2, "rotation": 90.0})
	app.world.add_item({"id": "toy_live", "kind": "toybox", "x": -2.0, "z": -0.2, "rotation": 0.0})
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	flow = app.chore_flow
	flow.chores().reset(); flow.rebuild_stations(true)
	var sim: LifeSim = app.sim
	sim.autonomy = false
	for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 95.0
	sim.day = 6; sim.minutes = 600.0; app.household.day = 6; app.household.minutes = 600.0
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 12.0 * 1440.0
	var cases: Array = [
		["chore_vacuum", "hoover"], ["chore_mop", ""], ["chore_dust", "duster"], ["chore_wipe_sink", "sponge"], ["chore_scrub_toilet", "brush"],
		["chore_fluff", ""], ["chore_vacuum_curtains", "nozzle"], ["chore_sweep_entry", "broom"], ["chore_wipe_door", "cloth"], ["chore_wash_window", "squeegee"],
	]
	for entry: Array in cases:
		var id: String = entry[0]
		var want_tool: String = entry[1]
		var station: Dictionary = {}
		for candidate: Dictionary in flow.list:
			if str(candidate.chore) == id and bool(candidate.ok) and flow.dirt_of(candidate) > 40.0 and (id != "chore_wash_window" or not bool(candidate.outdoor)):
				station = candidate; break
		check(not station.is_empty(), "%s: a dirty station is there to clean" % id)
		if station.is_empty(): continue
		sim.action_queue.clear()
		sim.minutes = 600.0
		var before: float = flow.dirt_of(station)
		var queued: bool = sim.queue_action(id, str(station.id), station.position)
		check(queued and str(sim.get_current_action().id) == id, "%s: queues at its station" % id)
		app.household.set_speed(8)
		var active: bool = false
		for frame: int in 5000:
			app._process(DT)
			if str(sim.get_current_action().get("phase", "")) == "active" and frame > 3: active = true; break
		check(active, "%s: the Lifelet walks there and starts" % id)
		if not active: continue
		app.household.set_speed(1)
		for frame: int in 24: app._process(DT)
		var actor: LifeActor = app.player
		var anchor: Dictionary = actor._activity_anchor
		check(anchor.has("chore_aim") and str(anchor.get("action", "")) in [id, "mop_puddle"], "%s: the actor is anchored to the work" % id)
		if want_tool != "":
			check(want_tool in visible_tools(actor), "%s: %s is in hand (%s)" % [id, want_tool, visible_tools(actor)])
		elif id == "chore_mop":
			check(actor._mop.visible, "chore_mop: the mop is in hand")
		else:
			check(visible_tools(actor).is_empty(), "%s: no tool is shown (%s)" % [id, visible_tools(actor)])
		var worst: float = 0.0
		for frame: int in 20:
			app._process(DT)
			if id != "chore_mop": worst = maxf(worst, hand_error(actor))
		check(worst < .03, "%s: the hands stay on the tool (%.1f mm)" % [id, worst * 1000.0])
		# Pause freezes the pose exactly.
		app.household.set_speed(0)
		var frozen: Vector3 = actor.palm_world("R")
		var before_pose: Transform3D = actor.visual.transform
		for frame: int in 20: app._process(DT)
		check(actor.palm_world("R") == frozen and actor.visual.transform == before_pose, "%s: pausing freezes the pose" % id)
		app.household.set_speed(8)
		var finished: bool = false
		for frame: int in 9000:
			app._process(DT)
			if sim.action_queue.is_empty(): finished = true; break
		check(finished, "%s: runs to completion" % id)
		app.household.set_speed(0)
		for frame: int in 4: app._process(DT)
		check(flow.dirt_of(station) < before * .2, "%s: the zone is clean afterwards (%.0f%% -> %.0f%%)" % [id, before, flow.dirt_of(station)])
		check(visible_tools(app.player).is_empty() and not app.player._mop.visible, "%s: nothing is left in their hands" % id)
	# A cancelled chore leaves no tool behind.
	sim.action_queue.clear()
	var vac: Dictionary = {}
	for candidate: Dictionary in flow.list:
		if str(candidate.chore) == "chore_vacuum" and bool(candidate.ok): vac = candidate; break
	sim.queue_action("chore_vacuum", str(vac.id), vac.position)
	app.household.set_speed(8)
	for frame: int in 3000:
		app._process(DT)
		if str(sim.get_current_action().get("phase", "")) == "active" and frame > 10: break
	app.household.set_speed(1)
	for frame: int in 30: app._process(DT)
	check("hoover" in visible_tools(app.player), "The vacuum is out while cleaning")
	sim.cancel_action()
	for frame: int in 20: app._process(DT)
	check(visible_tools(app.player).is_empty(), "Cancelling puts the vacuum away")
	# ------------------------------------------------ a stray pet toy joins the round
	sim.action_queue.clear()
	var spot_box: Vector3 = Vector3.INF
	var spot_toy: Vector3 = Vector3.INF
	for x: float in [2.0, 2.5, 3.0, 1.5]:
		for z: float in [.8, 1.2, 1.6, 2.0]:
			var at: Vector3 = Vector3(x, .16, z)
			if app.world.can_place("cat_toy_box", at, 0.0) and not spot_box.is_finite(): spot_box = at
			elif app.world.can_place("pet_toy_cat", at, 0.0) and spot_box.is_finite() and at.distance_to(spot_box) > 1.0 and not spot_toy.is_finite(): spot_toy = at
	check(spot_box.is_finite() and spot_toy.is_finite(), "There is floor for a toy box and a toy")
	if spot_box.is_finite() and spot_toy.is_finite():
		app.world.add_item({"id": "box_stray", "kind": "cat_toy_box", "x": spot_box.x, "z": spot_box.z, "rotation": 0.0})
		app.world.add_item({"id": "toy_stray", "kind": "pet_toy_cat", "x": spot_toy.x, "z": spot_toy.z, "rotation": 0.0})
		app.world.rebuild_navigation(); app._refresh_sim_targets()
		sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 95.0
		var plan: Dictionary = flow.make_plan(sim, "quick")
		var stray: Array = plan.entries.filter(func(entry: Dictionary) -> bool: return str(entry.id) == "put_pet_toy")
		check(stray.size() == 1 and str(stray[0].target) == "toy_stray", "A toy left on the floor is in the round (%s)" % [plan.entries.map(func(e: Dictionary) -> String: return str(e.id))])
		var begun: Dictionary = flow.start(str(app.household.members[0].id), "custom", ["toys"])
		check(bool(begun.ok) and str(sim.get_current_action().id) == "put_pet_toy", "It is the existing put-away action that is queued (%s)" % sim.get_current_action().get("id", ""))
		app.household.set_speed(8)
		for frame: int in 6000:
			app._process(DT)
			if sim.action_queue.is_empty(): break
		app.household.set_speed(0)
		check(str(app._find_item("toy_stray").get("box_id", "")) == "box_stray", "The toy has gone back in its box")
		check(flow.make_plan(sim, "quick").entries.filter(func(entry: Dictionary) -> bool: return str(entry.id) == "put_pet_toy").is_empty(), "...and is no longer in the way")
	print("CHORE_LIVE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
