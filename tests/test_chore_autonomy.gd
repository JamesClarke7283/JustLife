extends SceneTree
## Unprompted cleaning stays conservative: a comfortable Lifelet in a grubby home tidies
## one thing at a time, never at night, never before needs, school or work, never while
## somebody else is already doing it, never twice within ninety minutes, and children only
## tidy their toys. Twelve simulated hours of an ordinary Saturday are played in full.
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

func member(index: int) -> LifeSim:
	return app.household.members[index].sim

func filthy() -> void:
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 12.0 * 1440.0

func set_clock(day: int, minutes: float) -> void:
	for m: Dictionary in app.household.members:
		m.sim.day = day; m.sim.minutes = minutes
	app.household.day = day; app.household.minutes = minutes

## Play from here to `until` game minutes, recording each chore the Lifelets begin.
func play(until: float, starts: Array, overlap: Array, low: Dictionary) -> void:
	app.household.set_speed(8)
	var seen: Dictionary = {}
	for frame: int in 40000:
		app._process(DT)
		var working: int = 0
		for index: int in app.household.members.size():
			var sim: LifeSim = member(index)
			var action: Dictionary = sim.get_current_action()
			var tag: String = "" if action.is_empty() else "%s@%s@%d" % [action.id, action.target_id, int(action.get("started_minutes", -1.0))]
			if not action.is_empty() and (Defs.is_chore(str(action.id)) or str(action.id) in Defs.EXISTING) and seen.get(index, "") != str(action.id) + "@" + str(action.target_id) + "@" + str(action.phase) and str(action.phase) == "approach":
				var snapshot: Array = []
				for need: String in LifeSim.NEED_NAMES: snapshot.append(float(sim.needs[need]))
				starts.append({"who": index, "id": str(action.id), "minute": float(app.household.minutes), "autonomous": bool(action.get("autonomous", false)), "needs": snapshot, "phase": "approach"})
			seen[index] = "" if action.is_empty() else str(action.id) + "@" + str(action.target_id) + "@" + str(action.phase)
			if not action.is_empty() and Defs.is_chore(str(action.id)) and bool(action.autonomous) and str(action.phase) == "active": working += 1
			for need: String in LifeSim.NEED_NAMES: low[index] = minf(float(low.get(index, 100.0)), float(sim.needs[need]))
		if working > 1: overlap.append(working)
		if float(app.household.minutes) >= until: break
	app.household.set_speed(0)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Nia Vale", "age_stage": "adult", "traits": ["Neat"]}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false)
	flow = app.chore_flow
	app.world.add_item({"id": "toy_auto", "kind": "toybox", "x": -2.0, "z": -0.2, "rotation": 0.0})
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	flow.chores().reset(); flow.rebuild_stations(true)
	for index: int in 3: member(index).autonomy = false
	filthy()
	flow.chores().toys["toy_auto"] = 6
	# --------------------------------------------------------------- the choosers
	set_clock(6, 10 * 60.0)
	for m: Dictionary in app.household.members:
		for need: String in LifeSim.NEED_NAMES: m.sim.needs[need] = 90.0
	var ada: LifeSim = member(0)
	var pick: Dictionary = flow.autonomous_choice(ada)
	check(not pick.is_empty() and Defs.is_chore(str(pick.id)), "A comfortable adult, a grubby home, a Saturday morning: one chore (%s)" % pick.get("id", ""))
	var Nia: LifeSim = member(1)
	flow.chores().auto_next.clear()
	flow.chores().toys.clear()
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 1.25 * 1440.0
	var mid_score: float = flow.home_score()
	var neat_pick: Dictionary = flow.autonomous_choice(Nia)
	flow.chores().auto_next.clear()
	var plain_pick: Dictionary = flow.autonomous_choice(ada)
	check(mid_score > 55.0 and mid_score < 75.0, "The home is part-grubby (%.0f%% clean)" % mid_score)
	check(not neat_pick.is_empty() and plain_pick.is_empty(), "A Neat Lifelet minds a home that others let be (neat %s, plain %s)" % [neat_pick.get("id", ""), plain_pick.get("id", "")])
	filthy(); flow.chores().auto_next.clear()
	flow.chores().toys["toy_auto"] = 6
	set_clock(6, 9 * 60.0 + 30.0)
	check(flow.autonomous_choice(ada).is_empty() == false, "Half past nine is a fine time")
	flow.chores().auto_next.clear()
	for early: float in [5.0 * 60.0, 7.5 * 60.0, 21.5 * 60.0, 23.0 * 60.0, 2.0 * 60.0]:
		set_clock(6, early)
		check(flow.autonomous_choice(ada).is_empty(), "Nobody starts at %02d:%02d" % [int(early / 60.0), int(fmod(early, 60.0))])
	set_clock(6, 10 * 60.0)
	member(2).needs.fun = 90.0
	var kid: Dictionary = flow.autonomous_choice(member(2))
	check(kid.is_empty(), "A child takes no station chore on their own; putting toys away is theirs through the toy flow (%s)" % kid.get("id", ""))
	# ----------------------------------------------------- a Saturday, played out
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 7.0 * 1440.0
	flow.chores().auto_next.clear()
	flow.chores().toys["toy_auto"] = 6
	set_clock(6, 8 * 60.0)
	for index: int in 3:
		member(index).autonomy = index != 2
		for need: String in LifeSim.NEED_NAMES: member(index).needs[need] = 95.0
	var starts: Array = []
	var overlap: Array = []
	var low: Dictionary = {}
	var score_before: float = flow.home_score()
	await play(20.0 * 60.0, starts, overlap, low)
	var auto_starts: Array = starts.filter(func(s: Dictionary) -> bool: return bool(s.autonomous) and str(s.phase) == "approach")
	var chore_starts: Array = auto_starts.filter(func(s: Dictionary) -> bool: return Defs.is_chore(str(s.id)))
	print("AUTONOMOUS CHORE STARTS ", chore_starts.map(func(s: Dictionary) -> String: return "%d:%s@%d" % [s.who, s.id, int(s.minute)]))
	check(chore_starts.size() >= 1, "Over a Saturday somebody tidied up unprompted (%d chores)" % chore_starts.size())
	check(overlap.is_empty(), "Never more than one Lifelet at a time cleaned unprompted")
	var needs_ok: bool = true
	for s: Dictionary in chore_starts:
		for need_value: float in s.needs:
			if need_value < 50.0: needs_ok = false
	check(needs_ok, "Every unprompted chore began with every need comfortable")
	var hours_ok: bool = true
	for s: Dictionary in chore_starts:
		if float(s.minute) < 8.0 * 60.0 or float(s.minute) > 21.0 * 60.0: hours_ok = false
	check(hours_ok, "...and in the daytime")
	var spaced: bool = true
	for who: int in 3:
		var mine: Array = chore_starts.filter(func(s: Dictionary) -> bool: return int(s.who) == who)
		for index: int in range(1, mine.size()):
			if float(mine[index].minute) - float(mine[index - 1].minute) < 85.0: spaced = false
	check(spaced, "Nobody began a second chore within ninety minutes of the first")
	var child_ok: bool = chore_starts.filter(func(s: Dictionary) -> bool: return int(s.who) == 2).is_empty()
	check(child_ok, "The child never started a station chore of their own accord")
	check(float(low.get(0, 100.0)) > 30.0 and float(low.get(1, 100.0)) > 30.0, "Nobody let a need fall below 30 over the day (%.0f, %.0f)" % [float(low.get(0, 0.0)), float(low.get(1, 0.0))])
	check(flow.home_score() > score_before, "The home is cleaner for it (%.0f%% -> %.0f%%)" % [score_before, flow.home_score()])
	# Autonomous tasks are ordinary interruptible actions.
	for index: int in 3: member(index).autonomy = false; member(index).action_queue.clear()
	filthy(); flow.chores().auto_next.clear(); set_clock(7, 10 * 60.0)
	for need: String in LifeSim.NEED_NAMES: ada.needs[need] = 90.0
	ada.autonomy = true
	ada._choose_autonomous_action()
	var chosen: Dictionary = ada.get_current_action()
	check(not chosen.is_empty() and Defs.is_chore(str(chosen.id)) and bool(chosen.autonomous), "The chosen chore is queued as an unprompted action")
	check(not chosen.has("chore") or str(chosen.chore.mode) == "task" and chosen.chore.plan.is_empty(), "...a single task, not a round")
	ada.needs.hunger = 8.0
	ada.needs.energy = 8.0
	app.household.set_speed(8)
	for frame: int in 120: app._process(DT)
	var after: Dictionary = ada.get_current_action()
	check(after.is_empty() or not Defs.is_chore(str(after.id)), "A starving, exhausted Lifelet drops the chore for what they need (%s)" % after.get("id", ""))
	# ------------------------------------------------ school and work come first
	for index: int in 3: member(index).action_queue.clear()
	for m: Dictionary in app.household.members:
		for need: String in LifeSim.NEED_NAMES: m.sim.needs[need] = 95.0
	set_clock(8, 7 * 60.0 + 30.0)
	flow.chores().auto_next.clear(); filthy()
	for index: int in 3: member(index).autonomy = true
	var morning: Array = []
	for index: int in 3:
		var which: int = index
		member(index).action_started.connect(func(action: Dictionary) -> void:
			if Defs.is_chore(str(action.id)) and bool(action.get("autonomous", false)): morning.append("%d:%s@%d" % [which, action.id, int(app.household.minutes)]))
	app.household.set_speed(8)
	for frame: int in 1500:
		app._process(DT)
		if float(app.household.minutes) >= 9.2 * 60.0: break
	app.household.set_speed(0)
	check(morning.is_empty(), "On a Monday morning nobody cleans while work and school are due (%s)" % [morning])
	print("CHORE_AUTONOMY %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
