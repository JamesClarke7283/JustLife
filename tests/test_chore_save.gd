extends SceneTree
## Cleaning through saves: a round in progress saved while paused and loaded again resumes
## exactly (the same plan, the same progress, the tool in hand, the dirt as it was), a save
## from before cleaning existed loads spotless, and corrupt cleaning records are refused.
const Defs = preload("res://scripts/chore_defs.gd")
const Chores = preload("res://scripts/chores.gd")
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

func tools_of(actor: LifeActor) -> Array:
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
	# ----------------------------------------------------------- pure validators
	var good: Dictionary = {"cleaned": {"fvac:0:1:1": 100.0}, "toys": {}, "auto_next": {}}
	check(LifeHouseholdFlow.validate({"chores": good}, [], 5) == "", "A well-formed cleaning record is accepted")
	check(LifeHouseholdFlow.validate({"chores": {"cleaned": {"BAD KEY": 1.0}}}, [], 5) != "", "A malformed zone name is refused")
	check(LifeHouseholdFlow.validate({"chores": {"cleaned": {"fvac:0:1:1": 999999.0}}}, [], 5) != "", "A cleaning time in the far future is refused")
	check(LifeHouseholdFlow.validate({"chores": {"toys": {"nowhere": 2}}}, [], 5) == "", "Toys with no layout to check against are tolerated")
	check(LifeHouseholdFlow.validate({"chores": "x"}, [], 5) != "", "A cleaning record that is not a record is refused")
	var sim: LifeSim = LifeSim.new()
	root.add_child(sim)
	sim.new_household({"name": "Probe", "age_stage": "adult"})
	var base_state: Dictionary = sim.get_state()
	var action: Dictionary = sim.get_action_definition("chore_vacuum")
	action.merge({"target_id": "chore:fvac:0:1:1", "target_position": Vector3(1, .16, 1), "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false, "duration": 3.5}, true)
	var record: Dictionary = {"v": 1, "mode": "quick", "plan": ["chore_mop@chore:fmop:0:1:1", "clear_table@dining_1", "clean_plate@dining_1", "put_pet_toy@toy_1", "empty_bin@bin_1", "clean_litter_tray@litter_1"], "index": 1, "total": 7, "label": "Vacuum", "changes": {"energy": -.5}, "key": "fvac:0:1:1", "item": "", "face": "", "aid": "", "from": 10.0}
	var probe: Dictionary = sim.get_state()
	probe["action_queue"] = [action.merged({"chore": record}, true)]
	check(sim._validate_state(probe) == "", "A queued chore with its round (chores and the existing spills, table, bin, tray and toy actions) validates (%s)" % sim._validate_state(probe))
	for broken: Dictionary in [{"plan": ["not a task"]}, {"mode": "frenzy"}, {"v": 7}, {"index": 9, "total": 2}, {"changes": {"mood": 3.0}}, {"aid": "ladder"}, {"label": "x".repeat(200)}]:
		var bad: Dictionary = record.merged(broken, true)
		probe["action_queue"] = [action.merged({"chore": bad}, true)]
		check(sim._validate_state(probe) != "", "A corrupt round is refused: %s" % [broken.keys()])
	var long_action: Dictionary = action.merged({"chore": record, "duration": 500.0}, true)
	probe["action_queue"] = [long_action]
	check(sim._validate_state(probe) != "", "An impossible chore length is refused")
	var stray: Dictionary = sim.get_action_definition("relax").merged({"target_id": "x", "target_position": Vector3.ZERO, "phase": "queued", "elapsed": 0.0, "progress": 0.0, "paid": false, "autonomous": false, "chore": record}, true)
	probe["action_queue"] = [stray]
	check(sim._validate_state(probe) != "", "Cleaning data on an unrelated action is refused")
	sim.queue_free()

	# ------------------------------------------------------------ a live round
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Elm Vale", "age_stage": "elder", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false)
	app.world.add_item({"id": "toy_save", "kind": "toybox", "x": -2.0, "z": -0.2, "rotation": 0.0})
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	flow = app.chore_flow
	for m: Dictionary in app.household.members:
		m.sim.autonomy = false
		m.sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: m.sim.needs[need] = 95.0
	app.household.minutes = 600.0
	flow.chores().reset(); flow.rebuild_stations(true)
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - (3.0 + float(str(key).hash() % 7)) * 1440.0
	flow.chores().toys["toy_save"] = 3
	var teen: LifeSim = app.household.members[1].sim
	var teen_id: String = str(app.household.members[1].id)
	var started: Dictionary = flow.start(teen_id, "inside")
	check(bool(started.ok), "A round starts for Elm (%s)" % started)
	app.household.set_speed(8)
	var reached: bool = false
	for frame: int in 20000:
		app._process(DT)
		var current: Dictionary = teen.get_current_action()
		if not current.is_empty() and str(current.phase) == "active" and int(current.chore.index) >= 3 and float(current.progress) > .35 and float(current.progress) < .8 and str(current.id) not in ["mop_puddle"]: reached = true; break
	check(reached, "The round is three tasks in, partway through one")
	app.household.set_speed(0)
	for frame: int in 5: app._process(DT)
	var before: Dictionary = teen.get_current_action().duplicate(true)
	var stamps_before: Dictionary = flow.chores().cleaned.duplicate(true)
	var toys_before: Dictionary = flow.chores().toys.duplicate(true)
	var score_before: float = flow.home_score()
	var saved_ok: bool = app.save_game("", "Mid-chore checkpoint")
	check(saved_ok, "The game saves in the middle of a chore (%s | %s | %s)" % [app.notice_text, app.notice_queue, app.notice_aside])
	var slot: String = app.active_save_id
	var epoch: int = app.load_epoch
	app.load_game(slot)
	await frames(4)
	flow = app.chore_flow
	check(app.load_epoch == epoch + 1, "The save loads")
	teen = app.household.member_sim(teen_id)
	var after: Dictionary = teen.get_current_action()
	check(str(after.id) == str(before.id) and str(after.target_id) == str(before.target_id), "The same chore is under way (%s)" % after.get("id", ""))
	check(after.has("chore") and after.chore.plan == before.chore.plan and int(after.chore.index) == int(before.chore.index) and int(after.chore.total) == int(before.chore.total), "The round is intact: task %d of %d, %d to come" % [int(after.chore.index), int(after.chore.total), after.chore.plan.size()])
	check(is_equal_approx(float(after.progress), float(before.progress)) and bool(after.paid) and float(after.elapsed) > 0.0, "The task is as far on as it was (%.2f -> %.2f, %s -> %s)" % [float(before.progress), float(after.progress), before.phase, after.phase])
	check(flow.chores().cleaned == stamps_before, "Every zone's cleaning time is as it was")
	check(flow.chores().toys == toys_before, "The toys left out are as they were")
	check(absf(flow.home_score() - score_before) < .01, "The home is as clean as before (%.1f%%)" % flow.home_score())
	var actor: LifeActor = app.world.actors[teen_id]
	app.household.set_speed(0)
	check(not tools_of(actor).is_empty() or str(after.id) == "chore_fluff", "Paused after loading, the tool is in their hand (%s)" % [tools_of(actor)])
	var held: float = 0.0
	for frame: int in 6:
		app._process(DT)
		held = maxf(held, hand_error(actor))
	check(held < .08, "...and their hands are on it (%.1f mm)" % (held * 1000.0))
	var pose: Transform3D = actor.visual.transform
	for frame: int in 20: app._process(DT)
	check(actor.visual.transform == pose, "The paused pose does not drift")
	# And the round goes on.
	app.household.set_speed(8)
	var moved_on: bool = false
	for frame: int in 20000:
		app._process(DT)
		var current: Dictionary = teen.get_current_action()
		if not current.is_empty() and current.has("chore") and int(current.chore.index) > int(before.chore.index): moved_on = true; break
		if current.is_empty(): break
	check(moved_on, "After the load the round carries on to its next task")
	app.household.set_speed(0)
	teen.action_queue.clear()
	# ----------------------------------------------- a save from before cleaning
	flow.chores().cleaned[flow.chores().cleaned.keys()[0]] = flow.now() - 1000.0
	check(app.save_game("", "Before cleaning"), "A plain save is written")
	var plain_slot: String = app.active_save_id
	var read: Dictionary = LifeSaveLibrary.read_slot(plain_slot)
	var old_data: Dictionary = read.data.duplicate(true)
	check(old_data.extras.has("chores"), "A new save carries the cleaning record")
	old_data.extras.erase("chores")
	check(bool(LifeSaveLibrary.save_slot("old_style", "Old style", old_data).ok), "The same household is written the way an older build wrote it")
	var epoch_old: int = app.load_epoch
	app.load_game("old_style")
	await frames(4)
	flow = app.chore_flow
	check(app.load_epoch == epoch_old + 1, "A save with no cleaning record loads")
	check(flow.home_score() > 99.9, "...and its home is spotless (%.1f%%)" % flow.home_score())
	var everything_clean: bool = true
	for station: Dictionary in flow.list:
		if flow.dirt_of(station) > .5: everything_clean = false
	check(everything_clean, "...every zone of it")
	# A damaged cleaning record is refused outright and the running game is left alone.
	var broken: Dictionary = read.data.duplicate(true)
	broken.extras.chores.cleaned["Not A Zone"] = 5.0
	LifeSaveLibrary.save_slot("broken_zones", "Broken zones", broken)
	var epoch_now: int = app.load_epoch
	app.load_game("broken_zones")
	await frames(2)
	check(app.load_epoch == epoch_now, "A save with a damaged cleaning record is refused (%s)" % app.notice_aside)
	var broken_round: Dictionary = LifeSaveLibrary.read_slot(slot).data.duplicate(true)
	var had_round: bool = false
	for member_state: Dictionary in broken_round.members:
		for queued: Dictionary in member_state.state.get("action_queue", []):
			if queued.has("chore"):
				queued.chore.plan = ["definitely not a task"]; had_round = true
	check(had_round, "The mid-chore save really holds a round")
	LifeSaveLibrary.save_slot("broken_round", "Broken round", broken_round)
	app.load_game("broken_round")
	await frames(2)
	check(app.load_epoch == epoch_now, "A save with a damaged round is refused too")
	print("CHORE_SAVE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
