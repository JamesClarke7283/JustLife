extends SceneTree
## A child comes home from school (by the real bus) and goes straight to somewhere
## to sit and do their homework, in the order pupils reach for one: the study desk
## with laptop, the home office desk (and the older desk and computer beside each),
## then their own desk and chair or a dining table with a chair; never standing at a
## shelf while a seat is free, and never standing idle when there is nowhere to do
## it. (tests/test_homework_desks.gd covers the study and office desks themselves.)
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

## Run Monday from 07:30 to `until` and report what the child did.
func school_day(starter: String, strip: Array = [], until: float = 1080.0) -> Dictionary:
	if is_instance_valid(app): app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find(starter))
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	for kind: String in strip:
		for item: Dictionary in app.world.items.duplicate():
			if str(item.kind) == kind: app.world.remove_item(str(item.id))
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	var kit: String = ""
	for member: Dictionary in app.household.members:
		if str(member.sim.character.age_stage) == "child": kit = str(member.id)
		member.sim.minutes = 450.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
		member.sim.autonomy = str(member.sim.character.age_stage) == "child"
	app.household.minutes = 450.0
	var sim: LifeSim = app.household.member_sim(kit)
	var out: Dictionary = {"kit": kit, "returned": -1.0, "hw_started": -1.0, "hw_kind": "", "anchor": "", "palm": INF, "idle": 0.0, "done": false, "away_at_midnight": false}
	app.household.set_speed(8)
	var last_minutes: float = 450.0
	for frame: int in 40000:
		app._process(DT)
		var now: float = float(app.household.minutes)
		if now >= until: break
		if out.returned < 0.0 and now > 700.0 and not sim.is_away(): out.returned = now
		var action: Dictionary = sim.get_current_action()
		if out.returned >= 0.0 and action.is_empty() and not sim.is_away() and now > float(out.returned) + 3.0: out.idle = float(out.idle) + (now - last_minutes)
		last_minutes = now
		if str(action.get("id", "")) == "homework" and str(action.get("phase", "")) == "active":
			if out.hw_started < 0.0:
				out.hw_started = now
				out.hw_kind = str(app._find_item(str(action.get("target_id", ""))).get("kind", ""))
			var actor: LifeActor = app.world.actors[kit]
			if frame % 10 == 0 and str(actor._activity_anchor.get("kind", "")) == "seat": out.anchor = "seat"
			elif frame % 10 == 0 and out.anchor.is_empty(): out.anchor = str(actor._activity_anchor.get("kind", ""))
			if actor._activity_anchor.has("hand_center") and now > float(out.hw_started) + 2.0:
				var near: float = INF
				for side: String in ["L", "R"]:
					near = minf(near, actor._joints["Forearm_" + side].to_global(actor._palm_offset(side)).distance_to(actor._activity_anchor.hand_center))
				out.palm = minf(float(out.palm), near)
	out.done = int(sim.education.homework) >= 1 and int(sim.education.last_homework_day) == int(sim.day)
	out["attended"] = int(sim.education.last_attendance_day) == int(sim.day)
	out["missed"] = int(sim.education.missed)
	return out

## The kind of furnishing this pupil would do homework at now.
func _station_kind(pupil: LifeSim) -> String:
	var pick: Dictionary = pupil.homework_station()
	return str(app._find_item(str(pick.get("target_id", ""))).get("kind", "none"))

func run() -> void:
	# ---- the default home: a child who takes the bus is home at three with attendance
	var willow: Dictionary = await school_day("willow")
	check(float(willow.returned) > 880.0 and float(willow.returned) < 1000.0, "The child is back from school between 14:40 and 16:40 (%.0f)" % float(willow.returned))
	check(bool(willow.attended) and int(willow.missed) == 0, "Their school day counts as attended, not missed")
	check(float(willow.hw_started) > 0.0 and float(willow.hw_started) - float(willow.returned) < 60.0, "They start their homework within the hour (%.0f -> %.0f)" % [float(willow.returned), float(willow.hw_started)])
	check(str(willow.hw_kind) in ["study_desk", "office_desk", "desk", "computer", "dining", "child_desk"], "They do it at a desk or table, not at the bookshelf (%s)" % str(willow.hw_kind))
	check(str(willow.anchor) == "seat", "They sit down to do it (%s)" % str(willow.anchor))
	check(bool(willow.done), "The homework is done for the day")

	# ---- the family starters: their own desk and chair
	for starter: String in ["lumen", "haven"]:
		var home: Dictionary = await school_day(starter)
		check(float(home.returned) > 880.0 and float(home.returned) < 1000.0, "%s: back from school at three (%.0f)" % [starter, float(home.returned)])
		check(str(home.hw_kind) in ["study_desk", "office_desk", "child_desk", "dining", "desk", "computer"], "%s: homework at their own desk or a table (%s)" % [starter, str(home.hw_kind)])
		check(str(home.anchor) == "seat", "%s: they sit (%s)" % [starter, str(home.anchor)])
		check(float(home.palm) < .25, "%s: their hands are on the desk (%.2f m)" % [starter, float(home.palm)])
		check(bool(home.done), "%s: the homework is finished" % starter)

	# ---- a game saved while the child does homework at their own desk loads
	await school_day("lumen", [], 905.0)
	var homework_sim: LifeSim = app.household.member_sim(str(app.household.members[1].id))
	var saving: bool = false
	for frame: int in 3000:
		app._process(DT)
		if str(homework_sim.get_current_action().get("id", "")) == "homework" and str(homework_sim.get_current_action().get("phase", "")) == "active":
			saving = true
			break
	check(saving, "The child is doing their homework")
	check(app.save_game("homework_save", "Homework"), "A game saved during homework at the child desk is accepted")
	var save_restored: LifeSim = LifeSim.new()
	var save_result: Dictionary = save_restored.restore_state(JSON.parse_string(JSON.stringify(homework_sim._json_safe(homework_sim.get_state()))))
	check(bool(save_result.ok), "And a fresh sim loads it (%s)" % str(save_result.get("error", "")))

	# ---- no desk or shelf: the dining table and its chair
	var table: Dictionary = await school_day("willow", ["desk", "bookshelf", "computer"])
	check(str(table.hw_kind) == "dining" and str(table.anchor) == "seat", "With only a dining table, they sit at it (%s, %s)" % [str(table.hw_kind), str(table.anchor)])
	check(bool(table.done), "And finish the homework there")

	# ---- nowhere to do it: they play, not stand
	var nowhere: Dictionary = await school_day("willow", ["desk", "bookshelf", "computer", "dining", "chair"], 1200.0)
	check(float(nowhere.hw_started) < 0.0, "With nowhere to sit there is no homework to start")
	check(float(nowhere.idle) < 120.0, "They find something to do rather than stand about (%.0f idle minutes)" % float(nowhere.idle))

	# ---- somewhere to sit always outranks the shelf, even with a queue for it
	await school_day("lumen", [], 1080.0)
	var pupil: LifeSim = app.household.member_sim(str(app.household.members[1].id))
	var parent: LifeSim = app.household.member_sim(str(app.household.members[0].id))
	parent.autonomy = false; pupil.autonomy = false
	for candidate: Vector2 in [Vector2(-3.0, -3.4), Vector2(-1.0, -3.4), Vector2(1.0, -3.4), Vector2(-3.0, 3.4), Vector2(2.0, 3.4), Vector2(-4.5, 1.0)]:
		if app.world.can_place("bookshelf", Vector3(candidate.x, .16, candidate.y), 0):
			app.world.add_item({"id": "hw_shelf", "kind": "bookshelf", "x": candidate.x, "z": candidate.y, "rotation": 0.0})
			break
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(not app._find_item("hw_shelf").is_empty(), "A bookshelf stands in the home beside the child desk")
	pupil.education.last_homework_day = 0
	pupil.education.homework = maxi(0, int(pupil.education.homework) - 1)
	pupil.minutes = 1000.0
	check(_station_kind(pupil) == "child_desk", "Their own desk and chair come before the shelf (%s)" % _station_kind(pupil))
	var desk_id: String = ""
	for item: Dictionary in app.world.items:
		if str(item.kind) == "child_desk": desk_id = str(item.id)
	parent.action_queue.push_front({"id": "homework", "target_id": desk_id, "phase": "active", "duration": 45.0, "elapsed": 1.0})
	check(_station_kind(pupil) == "child_desk", "A sibling already at that desk does not send them to the shelf (%s)" % _station_kind(pupil))
	parent.action_queue.clear()
	app.pending_move = {}
	for item: Dictionary in app.world.items.duplicate():
		if str(item.kind) in ["child_chair"]: app.world.remove_item(str(item.id))
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(_station_kind(pupil) == "child_desk", "A child desk with no chair still beats the shelf (%s)" % _station_kind(pupil))
	app.world.remove_item(desk_id)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	check(_station_kind(pupil) == "bookshelf", "With no desk, table or chair in the home the shelf is the fallback (%s)" % _station_kind(pupil))
	check(str(pupil.homework_station().get("id", "")) == "homework", "That fallback is homework, not a pastime")

	# ---- the Homework button follows the same order, at any hour
	await school_day("willow", ["desk", "computer"], 1080.0)
	var hud_pupil: LifeSim = app.household.member_sim(str(app.household.members[1].id))
	app.household.member_sim(str(app.household.members[0].id)).autonomy = false
	hud_pupil.autonomy = false
	hud_pupil.education.last_homework_day = 0
	hud_pupil.education.homework = maxi(0, int(hud_pupil.education.homework) - 1)
	hud_pupil.minutes = 600.0
	app.select_household_member(1)
	while not hud_pupil.action_queue.is_empty(): hud_pupil.cancel_action()
	app.queue_homework_desk()
	var hud_kind: String = str(app._find_item(str(hud_pupil.get_current_action().get("target_id", ""))).get("kind", "none"))
	check(hud_kind == "dining", "At ten in the morning the Homework button sends them to the table and its chair, not the shelf (%s)" % hud_kind)

	print("HOMEWORK_AFTER_SCHOOL ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
