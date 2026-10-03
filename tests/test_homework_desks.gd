extends SceneTree
## The study desk with laptop and the home office desk (and the older desk and
## computer beside each) work for every age from child up: the menus, who may do
## homework there, how a pupil ranks the places in a home, the desk chair as a real
## seat, and a live home where two pupils come home from the bus and sit at them.
const DT: float = .05
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

func desk_targets(extra: Array = []) -> Array:
	return [
		{"id": "sd", "kind": "study_desk", "position": Vector3(1, .16, 1), "study_seat": "c1"},
		{"id": "od", "kind": "office_desk", "position": Vector3(3, .16, 1), "study_seat": "c2"},
		{"id": "ld", "kind": "desk", "position": Vector3(5, .16, 1), "study_seat": "c3"},
		{"id": "pc", "kind": "computer", "position": Vector3(7, .16, 1), "study_seat": "c4"},
		{"id": "dc", "kind": "desk_chair", "position": Vector3(1, .16, 2)},
	] + extra

func make(stage: String, minutes: float = 1000.0, targets: Array = []) -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	sim.new_household({"name": "Pat", "age_stage": stage, "traits": []})
	sim.autonomy = false; sim.household_bills_enabled = false; sim.set_aging("normal", false); sim.wants.clear()
	sim.minutes = minutes
	for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 80.0
	sim.register_targets(targets if not targets.is_empty() else desk_targets())
	return sim

func ids_at(sim: LifeSim, kind: String, target: String) -> Array:
	var out: Array = []
	# Dusting is the housekeeping menu every tabletop has; it is not the desk's own.
	for entry: Dictionary in sim.get_actions_for(kind, target):
		if not str(entry.id).begins_with("chore_"): out.append(str(entry.id))
	return out

func same_set(a: Array, b: Array) -> bool:
	var left: Array = a.duplicate(); var right: Array = b.duplicate()
	left.sort(); right.sort()
	return left == right

func has_all(have: Array, wanted: Array) -> bool:
	for id: Variant in wanted:
		if not have.has(id): return false
	return true

func run_homework(sim: LifeSim, target: String) -> bool:
	if not sim.queue_action("homework", target, Vector3(1, .16, 1)): return false
	sim.begin_current_action()
	sim.tick(float(sim.get_current_action().duration) / LifeSim.GAME_MINUTES_PER_SECOND + .05)
	return sim.get_current_action().is_empty()

func station_id(sim: LifeSim) -> String:
	return str(sim.homework_station().get("target_id", ""))

func run() -> void:
	# ---- (a) the menus, for every age
	var computer_menu: Array = ids_at(make("adult"), "computer", "pc")
	for stage: String in ["child", "teen", "young_adult", "adult", "elder"]:
		var sim: LifeSim = make(stage)
		var study: Array = ids_at(sim, "study_desk", "sd")
		var office: Array = ids_at(sim, "office_desk", "od")
		var plain: Array = ids_at(sim, "desk", "ld")
		var computer: Array = ids_at(sim, "computer", "pc")
		check(same_set(office, computer), "%s: the home office desk answers like the computer (%s)" % [stage, str(office)])
		check(not study.is_empty() and not study.is_empty(), "%s: the study desk has a real menu (%s)" % [stage, str(study)])
		if stage in ["child", "teen"]:
			var wanted: Array = ["school", "homework", "study", "study_hard", "play_games"]
			check(has_all(study, wanted) and has_all(office, wanted), "%s: online classes, homework, study and games at both desks" % stage)
			check(has_all(plain, ["school", "homework", "study", "study_hard"]) and not plain.has("play_games"), "%s: the older desk keeps its menu" % stage)
			if stage == "teen": check(same_set(study, wanted), "teen: exactly the five pupil choices at the study desk (%s)" % str(study))
			else: check(has_all(study, ["child_desk_study", "read"]), "child: the study desk also offers Study Logic and a book")
		else:
			check(has_all(study, ["work", "study", "job", "study_hard", "play_games"]) and not study.has("homework") and not study.has("school"), "%s: freelance work, a shift, study and games at the study desk (%s)" % [stage, str(study)])
			check(has_all(office, ["order_groceries", "work", "study", "job", "play_games", "study_hard", "computer_logic"]), "%s: the office desk has the whole computer menu" % stage)
			check(not study.has("order_groceries") and not study.has("computer_logic"), "%s: the study desk has no groceries or mastery study" % stage)
	var baby: LifeSim = make("baby")
	var any_open: bool = false
	for kind: String in ["study_desk", "office_desk"]:
		for entry: Dictionary in baby.get_actions_for(kind, "sd" if kind == "study_desk" else "od"):
			if str(entry.id) in ["homework", "school", "work", "job", "study", "study_hard"] and bool(entry.available): any_open = true
	check(not any_open, "A baby cannot use either desk")
	check(ids_at(make("adult"), "desk_chair", "dc").has("relax"), "The desk chair can be sat on")

	# ---- (b) pupils may do homework at either desk; others are refused
	for stage: String in ["child", "teen"]:
		for pair: Array in [["study_desk", "sd"], ["office_desk", "od"], ["desk", "ld"], ["computer", "pc"]]:
			var pupil: LifeSim = make(stage)
			check(bool(pupil.get_action_availability("homework", str(pair[1])).available), "%s may do homework at the %s" % [stage, str(pair[0])])
			check(run_homework(pupil, str(pair[1])) and int(pupil.education.homework) == 1, "%s finishes homework at the %s" % [stage, str(pair[0])])
	var grown: LifeSim = make("adult")
	check(str(grown.get_action_availability("homework", "sd").reason) == "Online classes and homework are for children and teens.", "An adult is refused homework with the plain reason")
	var classes: LifeSim = make("teen", 600.0)
	check(bool(classes.get_action_availability("school", "od").available), "Online classes are open at the home office desk")
	check(not make("teen").get_action_availability("school", "dc").available, "Online classes are refused at a desk chair")

	# ---- (c) the ranking
	var child: LifeSim = make("child", 1000.0, desk_targets([{"id": "cd", "kind": "child_desk", "position": Vector3(9, .16, 1), "study_seat": "cc"}, {"id": "tb", "kind": "dining", "position": Vector3(11, .16, 1), "study_seat": "tc"}, {"id": "bk", "kind": "bookshelf", "position": Vector3(13, .16, 1)}]))
	check(child.homework_place_rank("sd") == 0.0 and child.homework_place_rank("ld") == 2.0 and child.homework_place_rank("od") == 5.0 and child.homework_place_rank("pc") == 7.0, "Place ranks run study desk, older desk, office desk, computer")
	check(child.homework_place_rank("cd") == 10.0 and child.homework_place_rank("tb") == 12.0 and child.homework_place_rank("bk") == 1020.0, "Then the child desk, the table, and the bookcase last of all")
	check(is_inf(child.homework_place_rank("nothing")), "A place the pupil has no target for has no rank")
	check(station_id(child) == "sd", "The study desk with laptop is chosen first (%s)" % station_id(child))
	var table_only: LifeSim = make("child", 1000.0, [{"id": "tb", "kind": "dining", "position": Vector3(11, .16, 1), "study_seat": "tc"}])
	check(is_equal_approx(table_only.homework_place_rank("tb"), 12.0), "A child's table ranks 12")
	var teen_table: LifeSim = make("teen", 1000.0, [{"id": "tb", "kind": "dining", "position": Vector3(11, .16, 1), "study_seat": "tc"}])
	check(is_equal_approx(teen_table.homework_place_rank("tb"), 16.0), "A teenager likes the family table least (16)")
	var home: LifeHousehold = LifeHousehold.new()
	home.new_household([{"name": "Kit", "age_stage": "child", "traits": []}, {"name": "Teo", "age_stage": "teen", "traits": []}])
	var full: Array = desk_targets([{"id": "cd", "kind": "child_desk", "position": Vector3(9, .16, 1), "study_seat": "cc"}, {"id": "tb", "kind": "dining", "position": Vector3(11, .16, 1), "study_seat": "tc"}, {"id": "bk", "kind": "bookshelf", "position": Vector3(13, .16, 1)}])
	home.register_targets(full)
	var kit: LifeSim = home.members[0].sim
	var teo: LifeSim = home.members[1].sim
	for sim: LifeSim in [kit, teo]:
		sim.autonomy = false; sim.household_bills_enabled = false; sim.set_aging("normal", false); sim.wants.clear(); sim.minutes = 1000.0
		for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 80.0
	check(station_id(kit) == "sd" and station_id(teo) == "sd", "Both pupils would take the study desk")
	teo.action_queue.push_front({"id": "homework", "target_id": "sd", "phase": "active", "duration": 45.0, "elapsed": 1.0})
	check(station_id(kit) == "ld", "With the study desk busy the older laptop desk is next (%s)" % station_id(kit))
	home.register_targets(full.filter(func(t: Dictionary) -> bool: return str(t.id) != "ld"))
	check(station_id(kit) == "od", "Then the home office desk (%s)" % station_id(kit))
	teo.action_queue.push_front({"id": "homework", "target_id": "od", "phase": "active", "duration": 45.0, "elapsed": 1.0})
	check(station_id(kit) in ["pc", "cd", "od", "sd"] and station_id(kit) != "bk", "With every desk busy a seat is still waited for, never the bookcase (%s)" % station_id(kit))
	teo.action_queue.clear()
	var chairless: Array = [
		{"id": "sd", "kind": "study_desk", "position": Vector3(1, .16, 1), "study_seat": ""},
		{"id": "od", "kind": "office_desk", "position": Vector3(3, .16, 1), "study_seat": ""},
		{"id": "bk", "kind": "bookshelf", "position": Vector3(13, .16, 1)}]
	var standing: LifeSim = make("child", 1000.0, chairless)
	check(station_id(standing) == "sd" and bool(standing.homework_is_standing("sd")), "A study desk with no chair is only a standing place")
	check(standing.homework_place_rank("sd") == 1000.0 and standing.homework_place_rank("od") == 1005.0 and standing.homework_place_rank("bk") == 1020.0, "Chairless desks (1000, 1005) sit just ahead of the bookcase (1020)")
	var with_table: LifeSim = make("child", 1000.0, chairless + [{"id": "tb", "kind": "dining", "position": Vector3(11, .16, 1), "study_seat": "tc"}])
	check(station_id(with_table) == "tb", "A table with a chair beats a chairless desk (%s)" % station_id(with_table))
	var shelf_only: LifeSim = make("child", 1000.0, [{"id": "bk", "kind": "bookshelf", "position": Vector3(13, .16, 1)}])
	check(station_id(shelf_only) == "bk", "With no desk and no seat the bookcase is the fallback")
	var unsaid: LifeSim = make("child", 1000.0, [{"id": "sd", "kind": "study_desk", "position": Vector3(1, .16, 1)}, {"id": "bk", "kind": "bookshelf", "position": Vector3(13, .16, 1)}])
	check(station_id(unsaid) == "sd" and not unsaid.homework_is_standing("sd"), "A desk that does not say which chair it has is taken as seated")

	# ---- (e) a save made during homework at the study desk loads
	var saver: LifeSim = make("child", 1000.0)
	check(saver.queue_action("homework", "sd", Vector3(1, .16, 1)), "Homework is queued at the study desk")
	saver.begin_current_action(); saver.tick(10.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	var state: Dictionary = JSON.parse_string(JSON.stringify(saver._json_safe(saver.get_state())))
	check(str(state.action_queue[0].target_kind) == "study_desk", "The saved action names the study desk")
	var loaded: LifeSim = LifeSim.new()
	var result: Dictionary = loaded.restore_state(state)
	check(bool(result.ok), "A fresh sim loads it (%s)" % str(result.get("error", "")))
	state.action_queue[0].target_kind = "dining_chair"
	check(not bool(LifeSim.new().restore_state(state).ok), "A saved homework at a place that is no desk is still refused")

	# the working ages' own choices at the new desks run and save too
	for stage: String in ["young_adult", "adult", "elder"]:
		for choice: Array in [["study", "sd"], ["play_games", "od"], ["work", "sd"]]:
			var worker: LifeSim = make(stage, 600.0)
			var queued: bool = worker.queue_action(str(choice[0]), str(choice[1]), Vector3(1, .16, 1))
			if not queued: continue
			worker.begin_current_action(); worker.tick(5.0 / LifeSim.GAME_MINUTES_PER_SECOND)
			var saved: Dictionary = JSON.parse_string(JSON.stringify(worker._json_safe(worker.get_state())))
			check(bool(LifeSim.new().restore_state(saved).ok), "%s: a save made while doing %s at the %s loads" % [stage, str(choice[0]), "study desk" if str(choice[1]) == "sd" else "office desk"])
	var gamer: LifeSim = make("teen", 1000.0)
	check(gamer.queue_action("play_games", "od", Vector3(3, .16, 1)), "A teenager can play games at the office desk")

	# ---- (f) homework together works at the new desks
	var pair_home: LifeHousehold = LifeHousehold.new(); root.add_child(pair_home)
	pair_home.new_household([{"name": "Rowan", "age_stage": "child", "traits": []}, {"name": "Ellis", "age_stage": "adult", "traits": []}])
	pair_home.configure_family([{"a": "housemate_1", "b": "player", "role": "parent"}])
	for member: Dictionary in pair_home.members:
		member.sim.autonomy = false; member.sim.wants.clear()
	pair_home.register_targets([{"id": "sd", "kind": "study_desk", "position": Vector3(0, .16, 0)}, {"id": "od", "kind": "office_desk", "position": Vector3(3, .16, 0)}, {"id": "player", "kind": "neighbor", "position": Vector3(1, .16, 0)}, {"id": "housemate_1", "kind": "neighbor", "position": Vector3(-1, .16, 0)}])
	for desk: String in ["sd", "od"]:
		check(bool(pair_home.queue_supported_homework("player", "housemate_1", desk, Vector3(0, .16, 0), Vector3(.75, .16, 0)).ok), "A parent can do homework together at the %s" % desk)
		pair_home.cancel_cooperative_action("player")
		for member: Dictionary in pair_home.members: member.sim.action_queue.clear()

	# ---- (d) a live home: two pupils come home on the bus and use the two desks
	var live: Dictionary = await live_home()
	check(bool(live.ok), "The live home is set up (%s)" % str(live.get("why", "")))
	if bool(live.ok):
		await live_checks(live)

	print("HOMEWORK_DESKS ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	if is_instance_valid(app): app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

## Willow with the plain desk, computer and dining set taken out, a study desk where
## the desk stood (its chair kept) and a home office desk with a desk chair.
func live_home(keep_study: bool = true, keep_office: bool = true) -> Dictionary:
	if is_instance_valid(app): app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}, {"name": "Teo Vale", "age_stage": "teen", "traits": []}]
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find("willow"))
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	for item: Dictionary in app.world.items.duplicate():
		if str(item.kind) in ["desk", "computer", "dining", "bookshelf", "chair"]:
			app.world.remove_item(str(item.id))
	if keep_study:
		app.world.add_item({"id": "hw_study", "kind": "study_desk", "x": 3.4, "z": 4.3, "rotation": 180.0})
		app.world.add_item({"id": "hw_study_chair", "kind": "desk_chair", "x": 3.4, "z": 3.48, "rotation": 0.0})
	var placed: bool = not keep_office
	for spot: Vector2 in [Vector2(-3.4, -1.9), Vector2(-3.4, -3.3), Vector2(0.4, -3.3), Vector2(-1.0, 1.0), Vector2(1.2, 4.3)]:
		if placed: break
		if app.world.can_place("office_desk", Vector3(spot.x, .16, spot.y), 0) and app.world.can_place("desk_chair", Vector3(spot.x, .16, spot.y + .82), 0):
			app.world.add_item({"id": "hw_office", "kind": "office_desk", "x": spot.x, "z": spot.y, "rotation": 0.0})
			app.world.add_item({"id": "hw_office_chair", "kind": "desk_chair", "x": spot.x, "z": spot.y + .82, "rotation": 180.0})
			placed = true
	if not placed: return {"ok": false, "why": "no room for the office desk"}
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	return {"ok": true}

func pupils() -> Dictionary:
	var out: Dictionary = {}
	for member: Dictionary in app.household.members:
		out[str(member.sim.character.age_stage)] = member
	return out

## Monday from 07:30 until `until`; what each pupil did at which place.
func run_day(until: float = 1080.0) -> Dictionary:
	var out: Dictionary = {"seen": {}, "palm": {}, "anchor": {}, "bookcase": false}
	for member: Dictionary in app.household.members:
		member.sim.minutes = 450.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
		member.sim.autonomy = str(member.sim.character.age_stage) in ["child", "teen"]
	app.household.minutes = 450.0
	app.household.set_speed(8)
	for frame: int in 40000:
		app._process(DT)
		if float(app.household.minutes) >= until: break
		for member: Dictionary in app.household.members:
			var stage: String = str(member.sim.character.age_stage)
			var action: Dictionary = member.sim.get_current_action()
			if str(action.get("id", "")) != "homework" or str(action.get("phase", "")) != "active": continue
			var kind: String = str(app._find_item(str(action.get("target_id", ""))).get("kind", ""))
			out.seen[stage] = kind
			if kind == "bookshelf": out.bookcase = true
			var actor: LifeActor = app.world.actors[str(member.id)]
			if frame % 10 == 0 and str(actor._activity_anchor.get("kind", "")) == "seat": out.anchor[stage] = "seat"
			if actor._activity_anchor.has("hand_center"):
				var near: float = INF
				for side: String in ["L", "R"]:
					near = minf(near, actor._joints["Forearm_" + side].to_global(actor._palm_offset(side)).distance_to(actor._activity_anchor.hand_center))
				if near < float(out.palm.get(stage, INF)): out.palm[stage] = near
	return out

func live_checks(_live: Dictionary) -> void:
	var study: Dictionary = app._find_item("hw_study")
	var office: Dictionary = app._find_item("hw_office")
	check(not study.is_empty() and not office.is_empty(), "A study desk and a home office desk stand in the home")
	check(str(app.world.desk_chair(study).get("id", "")) == "hw_study_chair" and str(app.world.desk_chair(office).get("id", "")) == "hw_office_chair", "Each desk finds its desk chair")
	var ids: Array = app.world.activity_resource_ids(study)
	check(ids.has("hw_study_chair"), "Using the study desk also holds its chair")
	# the desk model carries one laptop, and no second one is added
	var laptops: int = 0
	for node: Node in study.node.find_children("*Laptop*", "Node3D", true, false): laptops += 1
	check(study.node.find_child("LaptopKeyboard", true, false) == null and study.node.find_child("LaptopScreen", true, false) == null, "No second, boxed laptop is added to the study desk")
	check(laptops == 2, "The desk model's own laptop is there once (base and display: %d nodes)" % laptops)
	var plan: Dictionary = app.world.supported_homework_plan(study, Vector3(0, .16, 0), Vector3(1, .16, 0))
	check(str(plan.get("error", "")) != "Place a chair at the desk before doing homework together.", "The desk chair counts as the desk's chair for homework together (%s)" % str(plan.get("error", "ok")))
	var members: Dictionary = pupils()
	var kit: LifeSim = members.child.sim
	var teo: LifeSim = members.teen.sim
	kit.autonomy = false; teo.autonomy = false
	check(str(kit.homework_station().get("target_id", "")) == "hw_study", "At the start the study desk is the child's first choice")
	kit.autonomy = true; teo.autonomy = true
	var day: Dictionary = await run_day()
	check(day.seen.has("child") and day.seen.has("teen"), "Both pupils did homework (%s)" % str(day.seen))
	var kinds: Array = [str(day.seen.get("child", "")), str(day.seen.get("teen", ""))]
	check(kinds.has("study_desk") and kinds.has("office_desk"), "One used the study desk and the other the home office desk (%s)" % str(kinds))
	check(not bool(day.bookcase), "Nobody stood at a bookcase")
	check(str(day.anchor.get("child", "")) == "seat" and str(day.anchor.get("teen", "")) == "seat", "Both sat down (%s)" % str(day.anchor))
	check(float(day.palm.get("child", INF)) < .25 and float(day.palm.get("teen", INF)) < .25, "Their palms are on the desks (child %.2f m, teen %.2f m)" % [float(day.palm.get("child", INF)), float(day.palm.get("teen", INF))])
	check(int(kit.education.homework) == 1 and int(teo.education.homework) == 1, "Both assignments are done")

	# the study desk gone: the office desk takes both
	var again: Dictionary = await live_home(false, true)
	check(bool(again.ok), "A home with only the office desk")
	var members2: Dictionary = pupils()
	var seen_kind: String = str((await run_day(1080.0)).seen.get("child", ""))
	check(seen_kind == "office_desk", "With the study desk gone the child goes to the office desk (%s)" % seen_kind)
	# neither desk: the pupils fall back to the bookcase only if one exists
	var none: Dictionary = await live_home(false, false)
	check(bool(none.ok), "A home with neither desk")
	app.world.add_item({"id": "hw_shelf", "kind": "bookshelf", "x": -0.05, "z": -2.8, "rotation": 0.0})
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	var shelf_day: Dictionary = await run_day(1080.0)
	check(bool(shelf_day.bookcase) or shelf_day.seen.is_empty(), "With no desk or seat a bookcase is the fallback (%s)" % str(shelf_day.seen))
	members2.clear()

	# School record and the work-from-home button find a study or office desk
	var found: Dictionary = await live_home(true, true)
	check(bool(found.ok), "A home with a study desk and no plain desk")
	var adult: LifeSim = pupils().adult.sim
	app.select_household_member(0)
	adult.minutes = 600.0
	app.queue_nearest_of(LifeCatalog.WORK_DESKS, "work")
	check(str(adult.get_current_action().get("id", "")) == "work" and str(app._find_item(str(adult.get_current_action().get("target_id", ""))).get("kind", "")) == "study_desk", "Work from the first laptop desk found when there is no plain desk")
