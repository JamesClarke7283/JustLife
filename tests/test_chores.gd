extends SceneTree
## Household cleaning, headless: the dirt model, the stations the starter home gets, who
## may do which chore and why not, a whole round of chores run through the real queue (no
## gaps, one notice, one mood), cancellation, a vanished target, shared rounds, and the
## conservative autonomy. Poses and props are checked in test_chore_motion.gd.
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
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

func member(index: int) -> LifeSim:
	return app.household.members[index].sim
func member_id(index: int) -> String:
	return str(app.household.members[index].id)

## Saturday midday, everybody comfortable: no school or work to interfere.
func calm() -> void:
	for m: Dictionary in app.household.members:
		m.sim.autonomy = false
		m.sim.day = 6; m.sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: m.sim.needs[need] = 90.0
	app.household.day = 6; app.household.minutes = 600.0

func filthy(days: float = 20.0) -> void:
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - days * 1440.0
	for key: Variant in flow.chores().toys.keys(): flow.chores().toys[key] = 8

func run_until_idle(index: int, limit: int = 60000) -> int:
	var spent: int = 0
	for frame: int in limit:
		app._process(DT)
		spent = frame
		if member(index).action_queue.is_empty() and frame > 5: break
	return spent

func run() -> void:
	# ------------------------------------------------------------ the dirt model
	check(is_equal_approx(Chores.dirt_percent("fvac", 0.0, 0.0), 0.0), "A zone cleaned just now is spotless")
	check(is_equal_approx(Chores.dirt_percent("fvac", 0.0, 1.5 * 1440.0), 50.0), "Half of a floor's three-day period is 50% dirty")
	check(is_equal_approx(Chores.dirt_percent("fvac", 0.0, 9.0 * 1440.0), 100.0), "Dirt never passes 100%")
	check(is_equal_approx(Chores.dirt_percent("fvac", 0.0, 1.5 * 1440.0, 2.0), 100.0), "A busier household makes the dirt return twice as fast")
	check(Chores.dirt_percent("sink", 0.0, 1440.0) > Chores.dirt_percent("curt", 0.0, 1440.0) * 5.0, "A sink dirties far faster than a curtain")
	var book: Chores = Chores.new()
	check(book.dirt("fvac:0:1:1", "fvac", 5000.0) == 0.0, "A zone never seen is spotless")
	check(book.ensure("fvac:0:1:1", "fvac", 5000.0) and not book.ensure("fvac:0:1:1", "fvac", 9000.0), "A new zone is stamped once, with the time it was first seen")
	book.soil("fvac:0:1:1", 2160.0)
	check(is_equal_approx(book.dirt("fvac:0:1:1", "fvac", 5000.0), 50.0), "Soiling moves a zone along its period")
	book.clean("fvac:0:1:1", "fvac", 6000.0)
	check(book.dirt("fvac:0:1:1", "fvac", 6000.0) == 0.0, "Cleaning resets it")
	book.add_toys("box", 20)
	check(book.toys_out("box") == Chores.MAX_TOYS, "Toys left out are capped")
	var round_trip: Chores = Chores.new()
	round_trip.restore(book.get_state())
	check(round_trip.cleaned == book.cleaned and round_trip.toys == book.toys, "The record round-trips")
	check(Chores.validate(book.get_state(), {"box": "toybox"}, 100000.0, []) == "", "A good record validates")
	check(Chores.validate(null, {}, 0.0, []) == "", "A save with no cleaning record validates")
	check(Chores.validate({"cleaned": {"Bad Key": 1.0}}, {}, 100.0, []) != "", "A badly named zone is rejected")
	check(Chores.validate({"cleaned": {"fvac:0:1:1": 1e9}}, {}, 100.0, []) != "", "A cleaning time in the future is rejected")
	check(Chores.validate({"cleaned": {"fvac:0:1:1": NAN}}, {}, 100.0, []) != "", "A non-finite cleaning time is rejected")
	check(Chores.validate({"toys": {"nowhere": 3}}, {"x": "toybox"}, 100.0, []) != "", "Toys left out of a missing box are rejected")
	check(Chores.validate({"toys": {"box": 99}}, {"box": "toybox"}, 100.0, []) != "", "An impossible toy count is rejected")
	var oversize: Dictionary = {}
	for i: int in Defs.MAX_KEYS + 5: oversize["fvac:0:%d:0" % i] = 1.0
	check(Chores.validate({"cleaned": oversize}, {}, 100.0, []) != "", "An oversize record is rejected")
	check(Defs.reach("child", false, 2.0, 1.4, "pole").aid == "refused", "A child cannot reach a window, even with help")
	check(Defs.reach("adult", false, 2.05, 1.5, "pole").aid == "stool", "An adult takes the stool for the top of a window")
	check(Defs.reach("elder", false, 2.05, 1.5, "pole").aid == "pole", "An elder takes the pole, never the stool")
	check(Defs.reach("adult", true, 2.05, 1.5, "pole").aid == "pole", "An expectant adult takes the pole too")
	check(Defs.reach("teen", false, 1.45, 1.0, "").aid == "", "A teen reaches a door panel from the floor")

	# ----------------------------------------------------------------- the home
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Teo Vale", "age_stage": "teen", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}, {"name": "Elm Vale", "age_stage": "elder", "traits": []}, {"name": "Bo Vale", "age_stage": "baby", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false)
	flow = app.chore_flow
	calm()
	flow.chores().reset(); flow.rebuild_stations(true)
	var by_chore: Dictionary = {}
	var ids: Dictionary = {}
	for station: Dictionary in flow.list:
		by_chore[station.chore] = int(by_chore.get(station.chore, 0)) + 1
		if ids.has(station.id): check(false, "Station %s is unique" % station.id)
		ids[station.id] = true
	check(ids.size() == flow.list.size(), "Every station id is unique (%d)" % ids.size())
	var odd_labels: Array = []
	for station: Dictionary in flow.list:
		var words: String = str(station.label)
		if words.begins_with("the a ") or words.begins_with("the an ") or words.begins_with("the the "): odd_labels.append(words)
	check(odd_labels.is_empty(), "Station labels read as plain nouns, not article-led catalog names (%s)" % [odd_labels])
	var desk_label: String = ""
	for station: Dictionary in flow.list:
		if str(station.label).begins_with("the desk"): desk_label = str(station.label)
	check(desk_label.begins_with("the desk"), "The starter desk is dusted as \"the desk\", not by its whimsical shop name (%s)" % desk_label)
	check(by_chore.get("chore_wipe_sink", 0) == 2 and by_chore.get("chore_scrub_toilet", 0) == 1, "The starter home has two sinks and a toilet to clean")
	check(by_chore.get("chore_wash_window", 0) == 16, "Four windows give eight faces, each worked in two parts (%d)" % by_chore.get("chore_wash_window", 0))
	check(by_chore.get("chore_sweep_entry", 0) == 2 and by_chore.get("chore_wipe_door", 0) == 3, "Both exterior doors have an entry to sweep; the wide front door is wiped in two parts (%d)" % by_chore.get("chore_wipe_door", 0))
	check(int(by_chore.get("chore_vacuum", 0)) >= 10 and int(by_chore.get("chore_mop", 0)) >= 10, "The floor is cut into patches to vacuum and mop")
	check(int(by_chore.get("chore_dust", 0)) >= 5 and int(by_chore.get("chore_fluff", 0)) >= 1, "Dusting and cushions have stations")
	var inside_refused: int = 0
	var reachable_stations: int = 0
	var footprint: Rect2 = Rect2(-6.04, -5.04, 12.08, 10.08)
	for station: Dictionary in flow.list:
		if not bool(station.ok):
			if str(station.chore) == "chore_wash_window" and not bool(station.outdoor): inside_refused += 1
			continue
		var at: Vector3 = station.position
		if not app.world.lot_navigation.point_clear(int(station.level), at): check(false, "%s has a clear stand %s" % [station.id, at])
		if bool(station.outdoor) and str(station.chore) != "chore_sweep_entry" and str(station.chore) != "chore_wipe_door":
			check(not footprint.has_point(Vector2(at.x, at.z)), "%s is washed from outside the house" % station.id)
		if str(station.id).begins_with("chore:win_out:win_0_-604"): check(at.x >= -6.51, "The outside left window is washed from clear ground (x %.2f)" % at.x)
		if not app.world.path_to(app.player.position, at).is_empty(): reachable_stations += 1
	check(inside_refused == 4, "The two back windows behind the counters are refused from inside (%d parts)" % inside_refused)
	check(reachable_stations == flow.list.size() - inside_refused, "Every station with a stand can be walked to (%d)" % reachable_stations)
	var published: Dictionary = {}
	for target: Dictionary in app.world.simulation_targets(): published[str(target.id)] = true
	var all_published: bool = true
	for station: Dictionary in flow.list:
		if bool(station.ok) and not published.has(str(station.id)): all_published = false
	check(all_published, "Every usable station is a simulation target")
	check(is_equal_approx(flow.home_score(), 100.0), "A new home is spotless")

	# ---------------------------------------------------------- who may do what
	var sink_id: String = ""
	var sofa_id: String = ""
	var window_station: String = "chore:win_out:win_0_-604_220:0"
	for item: Dictionary in app.world.items:
		if str(item.kind) == "sink" and sink_id.is_empty(): sink_id = str(item.id)
		if str(item.kind) == "sofa": sofa_id = str(item.id)
	var door_station: String = "chore:door:gap_0_0.000_5.040_true:0"
	var vac_station: String = ""
	for station: Dictionary in flow.list:
		if str(station.chore) == "chore_vacuum" and bool(station.ok): vac_station = str(station.id); break
	var matrix: Array = [[0, "adult"], [1, "teen"], [2, "child"], [3, "elder"], [4, "baby"]]
	for entry: Array in matrix:
		var sim: LifeSim = member(int(entry[0]))
		var stage: String = str(entry[1])
		var vac: Dictionary = sim.get_action_availability("chore_vacuum", vac_station)
		var wipe: Dictionary = sim.get_action_availability("chore_wipe_sink", sink_id)
		var windows: Dictionary = sim.get_action_availability("chore_wash_window", window_station)
		var door: Dictionary = sim.get_action_availability("chore_wipe_door", door_station)
		var fluff: Dictionary = sim.get_action_availability("chore_fluff", sofa_id)
		check(bool(vac.available) == (stage != "baby"), "%s: vacuuming is %s" % [stage, "allowed" if stage != "baby" else "refused (%s)" % vac.reason])
		check(bool(fluff.available) == (stage != "baby"), "%s: cushions are %s" % [stage, "allowed" if stage != "baby" else "refused"])
		check(bool(wipe.available) == (stage in ["teen", "adult", "elder"]), "%s: a sink is %s %s" % [stage, "wiped" if bool(wipe.available) else "refused:", wipe.reason])
		check(bool(windows.available) == (stage in ["teen", "adult", "elder"]), "%s: a window is %s %s" % [stage, "washed" if bool(windows.available) else "refused:", windows.reason])
		check(bool(door.available) == (stage != "baby"), "%s: the front door is %s %s" % [stage, "wiped" if bool(door.available) else "refused:", door.reason])
		if not bool(windows.available): check(not str(windows.reason).is_empty(), "%s: the refusal says why" % stage)
	var menu: Array = member(0).get_actions_for("sink", sink_id)
	var menu_ids: Array = menu.map(func(a: Dictionary) -> String: return str(a.id))
	check("chore_wipe_sink" in menu_ids, "Clicking a sink offers to wipe it")
	check("chore_fluff" in member(0).get_actions_for("sofa", sofa_id).map(func(a: Dictionary) -> String: return str(a.id)), "Clicking a sofa offers to fluff its cushions")
	check("chore_scrub_toilet" in member(0).get_actions_for("toilet", "item_23").map(func(a: Dictionary) -> String: return str(a.id)), "Clicking the toilet offers to scrub it")
	# Night, expectant, away and carrying all refuse.
	member(0).minutes = 22.0 * 60.0
	check(not bool(member(0).get_action_availability("chore_wipe_door", door_station).available), "Exterior chores wait for daylight")
	check(bool(member(0).get_action_availability("chore_vacuum", vac_station).available), "Indoor chores do not")
	member(0).minutes = 600.0
	check(not bool(member(0).get_action_availability("chore_vacuum", "chore:fvac:0:99:99").available), "A station that does not exist is refused")

	# ---------------------------------------------------------- one task, direct
	var queued: bool = member(0).queue_action("chore_vacuum", vac_station, Vector3.ZERO)
	check(queued and str(member(0).get_current_action().id) == "chore_vacuum", "A single chore queues from a click")
	var action: Dictionary = member(0).get_current_action()
	check(float(action.duration) >= 3.0 and action.has("chore") and str(action.chore.mode) == "task", "It carries its own length and a task record")
	check(absf(float(action.changes.energy) + .15 * float(action.duration)) < .02, "Its effects follow its length")
	var queue_notice: Array = []
	member(0).notice.connect(func(text: String) -> void: queue_notice.append(text))
	app.household.set_speed(8)
	run_until_idle(0)
	check(member(0).action_queue.is_empty(), "The single chore runs to the end")
	check(flow.chores().dirt("fvac:" + vac_station.substr(11), "fvac", flow.now()) < 1.0, "Its patch of floor is clean")
	app.household.set_speed(0)

	# ------------------------------------------------------------- a full round
	filthy()
	check(flow.home_score() < 5.0, "A neglected home is filthy (%.1f%% clean)" % flow.home_score())
	var quick: Dictionary = flow.make_plan(member(0), "quick")
	var full: Dictionary = flow.make_plan(member(0), "full")
	var inside: Dictionary = flow.make_plan(member(0), "inside")
	var outside: Dictionary = flow.make_plan(member(0), "outside")
	check(float(quick.minutes) <= 100.0 and int(quick.count) > 5, "A quick tidy is capped near 90 minutes (%d tasks, %.0f min)" % [quick.count, quick.minutes])
	check(int(full.count) > int(quick.count) and int(inside.count) + int(outside.count) == int(full.count), "Full = inside + outside (%d + %d = %d)" % [inside.count, outside.count, full.count])
	var seen_outside: bool = false
	var order_ok: bool = true
	for entry: Dictionary in full.entries:
		if bool(entry.outdoor): seen_outside = true
		elif seen_outside: order_ok = false
	check(order_ok, "Outdoor tasks come last")
	check(int(flow.make_plan(member(2), "full").count) < int(full.count), "A child's round is shorter: the high and wet jobs are theirs to skip")
	check(not flow.make_plan(member(2), "full").refused.is_empty(), "The child's refusals are counted with their reasons")
	var started: Dictionary = flow.start(member_id(0), "full")
	check(bool(started.ok) and int(started.count) == int(full.count), "Clean Home starts the full round (%s)" % [started])
	var first: Dictionary = member(0).get_current_action()
	check(str(first.chore.mode) == "full" and int(first.chore.index) == 1 and int(first.chore.total) == int(full.count), "The first task knows the round")
	check(flow.status_text(first) == "CLEANING HOME — 1 OF %d" % int(full.count), "The HUD says where the round stands: %s" % flow.status_text(first))
	check(not bool(flow.start(member_id(0), "full").ok), "A second round is refused while one runs")
	app.household.set_speed(8)
	var seen: Array = []
	var gaps: int = 0
	var empty_run: int = 0
	var mood_before: int = member(0).moodlets.size()
	var rounds_notices: Array = []
	member(0).notice.connect(func(text: String) -> void: rounds_notices.append(text))
	var last_label: String = ""
	var empty_streak: int = 0
	for frame: int in 120000:
		app._process(DT)
		var current: Dictionary = member(0).get_current_action()
		if current.is_empty():
			empty_streak += 1
			if empty_streak > 4: break
		else:
			if empty_streak > 0 and frame > 10: gaps += 1
			empty_streak = 0
			var tag: String = "%s@%s" % [current.id, current.target_id]
			if seen.is_empty() or seen.back() != tag: seen.append(tag)
	app.household.set_speed(0)
	check(seen.size() >= int(full.count) - 4, "The round ran %d of its %d tasks" % [seen.size(), full.count])
	check(gaps == 0, "No gap between tasks: the queue is never empty mid-round (%d)" % gaps)
	check(flow.home_score() > 85.0, "The home ends clean apart from the windows that cannot be reached (%.1f%%)" % flow.home_score())
	check(rounds_notices.any(func(text: String) -> bool: return text.contains("finished cleaning")), "One notice closes the round: %s" % [rounds_notices])
	check(rounds_notices.filter(func(text: String) -> bool: return text.contains("finished cleaning")).size() == 1, "...and only one")
	check(member(0).moodlets.any(func(m: Dictionary) -> bool: return str(m.label) == "A tidy home"), "The round leaves a tidy-home mood")
	check(member(0).moodlets.size() <= mood_before + 2, "...and no heap of moodlets")
	check(float(member(0).needs.energy) < 90.0 and float(member(0).needs.energy) > 20.0, "The round tired them but did not exhaust them (%.0f)" % float(member(0).needs.energy))
	check(not member(0).get_current_action().has("chore"), "Nothing is left running")

	# --------------------------------------------- cancel, interrupt and vanish
	calm(); filthy()
	var plan: Dictionary = flow.make_plan(member(0), "inside")
	check(bool(flow.start(member_id(0), "inside").ok), "Another round starts")
	app.household.set_speed(8)
	for frame: int in 400: app._process(DT)
	check(not member(0).action_queue.is_empty(), "It is under way")
	app.household.set_speed(0)
	member(0).cancel_action()
	check(member(0).action_queue.is_empty(), "Cancel action cancels the whole round")
	# A player order queued behind ends the round at the next boundary.
	calm(); filthy()
	flow.start(member_id(1), "inside")
	member(1).queue_action("relax", app.world.closest_item("sofa", Vector3.ZERO).id, app.world.approach(app.world.closest_item("sofa", Vector3.ZERO)))
	app.household.set_speed(8)
	var steps: Array = []
	for frame: int in 6000:
		app._process(DT)
		var current: Dictionary = member(1).get_current_action()
		if not current.is_empty() and (steps.is_empty() or steps.back() != str(current.id)): steps.append(str(current.id))
		if current.is_empty() and frame > 20: break
	app.household.set_speed(0)
	check(steps.size() <= 3 and "relax" in steps, "A later instruction takes over after one task: %s" % [steps])
	# A target that vanishes costs only its own chore.
	calm(); filthy()
	flow.start(member_id(0), "inside")
	var round_before: Dictionary = member(0).get_current_action()
	var doomed: String = ""
	for entry: Variant in round_before.chore.plan:
		if str(entry).begins_with("chore_dust@"): doomed = str(entry).substr(str(entry).find("@") + 1); break
	check(not doomed.is_empty(), "The round plans some dusting")
	var doomed_item: String = doomed.split(":")[2]
	for item: Dictionary in app.world.items:
		if Sites_slug(str(item.id)) == doomed_item:
			app.world.remove_item(str(item.id)); break
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(not flow.stations.has(doomed), "The dusted piece's station is gone (%s)" % doomed)
	var carried_on: bool = false
	for frame: int in 1500:
		app.household.set_speed(8); app._process(DT)
		var current: Dictionary = member(0).get_current_action()
		if current.has("chore") and int(current.chore.index) >= 3: carried_on = true; break
	check(carried_on, "The rest of the round carries on past the vanished piece")
	member(0).action_queue.clear(); app.household.set_speed(0)

	# ------------------------------------------------------------- two cleaners
	calm(); filthy()
	var done_by: Dictionary = {}
	var duplicate_work: Array = []
	for index: int in [0, 1]:
		member(index).action_finished.connect(func(finished: Dictionary) -> void:
			if Defs.is_chore(str(finished.id)):
				if done_by.has(str(finished.target_id)): duplicate_work.append(str(finished.target_id))
				done_by[str(finished.target_id)] = index)
	var first_plan: Dictionary = flow.start(member_id(0), "inside")
	var second_plan: Dictionary = flow.start(member_id(1), "inside")
	check(bool(first_plan.ok) and bool(second_plan.ok), "Two Lifelets can each start a round (%s / %s)" % [first_plan, second_plan])
	app.household.set_speed(8)
	var finished_both: bool = false
	for frame: int in 90000:
		app._process(DT)
		if member(0).action_queue.is_empty() and member(1).action_queue.is_empty() and frame > 20: finished_both = true; break
	app.household.set_speed(0)
	check(finished_both, "Both rounds finish without a deadlock")
	var workers: Dictionary = {}
	for target: Variant in done_by: workers[done_by[target]] = true
	check(workers.size() == 2, "Both of them did real work (%d tasks between them)" % done_by.size())
	check(duplicate_work.is_empty(), "Nothing was cleaned twice: %s" % [duplicate_work])
	check(flow.home_score() > 70.0, "Together they leave the inside clean; only the unreachable windows and the outdoors remain (%.1f%%)" % flow.home_score())

	# --------------------------------------------------------------- autonomy
	calm(); filthy()
	var adult: LifeSim = member(0)
	adult.autonomy = true
	flow.chores().auto_next.clear()
	for m: Dictionary in app.household.members:
		if m.sim != adult: m.sim.autonomy = false
	app.mode = "live"
	var choice: Dictionary = flow.autonomous_choice(adult)
	check(not choice.is_empty() and Defs.is_chore(str(choice.id)), "A comfortable adult in a filthy home picks one chore: %s" % [choice.get("id", "")])
	check(flow.autonomous_choice(adult).is_empty(), "...and then waits out the cooldown")
	flow.chores().auto_next.clear()
	adult.needs.fun = 40.0
	check(flow.autonomous_choice(adult).is_empty(), "A bored Lifelet does not")
	adult.needs.fun = 90.0; adult.minutes = 22.0 * 60.0
	check(flow.autonomous_choice(adult).is_empty(), "Nobody cleans at night")
	adult.minutes = 600.0
	adult.needs.energy = 40.0
	check(flow.autonomous_choice(adult).is_empty(), "A tired Lifelet does not")
	adult.needs.energy = 90.0
	check(flow.autonomous_choice(member(4)).is_empty(), "A baby never does")
	var kid_choice: Dictionary = flow.autonomous_choice(member(2))
	check(kid_choice.is_empty(), "A child takes no station chore on their own")
	adult.queue_action("relax", app.world.closest_item("sofa", Vector3.ZERO).id, app.world.approach(app.world.closest_item("sofa", Vector3.ZERO)))
	check(flow.autonomous_choice(adult).is_empty(), "Somebody with something queued is left alone")
	adult.action_queue.clear()
	flow.chores().auto_next.clear()
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now()
	check(flow.autonomous_choice(adult).is_empty(), "A clean home needs nothing")
	filthy()
	member(1).autonomy = true
	member(1).queue_action("chore_vacuum", vac_station, Vector3.ZERO); member(1).action_queue[0]["autonomous"] = true
	check(flow.autonomous_choice(adult).is_empty(), "Only one Lifelet at a time cleans unasked")
	member(1).action_queue.clear()

	print("CHORES %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func Sites_slug(text: String) -> String:
	return preload("res://scripts/chore_sites.gd")._slug(text)
