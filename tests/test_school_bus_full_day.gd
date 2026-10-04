extends SceneTree
## The school bus over a whole school day, in the real game. It comes once in the
## morning and takes the pupils, stays away through the school day, comes back
## once at the end of school and sets the pupils down one at a time at the curb,
## and then drives off until the next school morning. Each pupil steps off beside
## the bus and walks straight indoors, to a different spot just inside the front
## door. There is no bus at the weekend or for a home without pupils, a pupil
## turned back at the door does not send it away early, and a game saved during
## the school day, even with a pupil still aboard, still brings everyone home.
const DT: float = .05
var app: Node
var checks: int = 0
var failures: Array[String] = []
var notices: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame
func clock(m: float) -> String: return "%02d:%02d" % [int(m) / 60, int(m) % 60]

## A fresh game with one adult and a pupil of each given stage, paused at 07:00
## on `day`. The adult does nothing on their own; the pupils plan their own day.
func boot(stages: Array, day: int = 1, lot: int = 0, adults: int = 1) -> Array:
	if is_instance_valid(app): app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	var names: Array = ["Kit", "Rae", "Sam"]
	var profiles: Array = [{"name": "Parent Vale", "age_stage": "adult", "traits": []}]
	for extra: int in range(1, adults): profiles.append({"name": "Pat Vale", "age_stage": "adult", "traits": []})
	for index: int in stages.size(): profiles.append({"name": "%s Vale" % names[index], "age_stage": stages[index], "traits": []})
	app.household_profiles = profiles
	app.selected_lot = lot
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	notices.clear()
	app.household.notice.connect(func(message: String): notices.append(message))
	app.household.day = day
	var pupils: Array = []
	for member: Dictionary in app.household.members:
		member.sim.day = day
		member.sim.minutes = 420.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
		var pupil: bool = str(member.sim.character.age_stage) in ["child", "teen"]
		member.sim.autonomy = pupil
		if pupil: pupils.append(str(member.id))
	app.household.minutes = 420.0
	# The game starts at 08:00 and the bus has already come for that morning, so start it afresh at 07:00.
	app.school_bus.reset()
	return pupils

## What happened to the bus and to each pupil, frame by frame, until the given time.
func new_record(pupils: Array) -> Dictionary:
	var rec: Dictionary = {"events": [], "last_phase": str(app.school_bus.phase), "pupils": {}, "samples": {}, "marks": [600.0, 720.0, 840.0, 960.0, 1200.0]}
	for id: String in pupils:
		rec.pupils[id] = {"state": "home", "left": -1.0, "flip": -1.0, "off": -1.0, "off_pos": Vector3.INF, "exit": Vector3.INF, "bus_at_off": "", "home": -1.0, "home_pos": Vector3.INF, "home_indoors": false, "boarding": false, "dropped": 0}
	return rec

func step(rec: Dictionary) -> void:
	app._process(DT)
	var d: int = int(app.household.day)
	var now: float = float(app.household.minutes)
	var bus: LifeSchoolBus = app.school_bus
	# Slow time down for the drop-off, so a step-off position is read before the pupil has walked on.
	var want: int = 1 if d == 1 and now >= 897.0 and now < 906.0 else 8
	if app.household.speed != want: app.household.set_speed(want)
	if bus.phase != rec.last_phase:
		rec.events.append({"day": d, "at": now, "from": rec.last_phase, "to": bus.phase})
		print("  [d%d %s] bus %s -> %s" % [d, clock(now), rec.last_phase, bus.phase])
		rec.last_phase = bus.phase
	if d == 1:
		for mark: float in rec.marks:
			if now >= mark and not rec.samples.has(mark):
				rec.samples[mark] = {"phase": bus.phase, "visible": is_instance_valid(app._bus_body) and app._bus_body.visible, "day": d}
	elif d == 2 and now >= 360.0 and not rec.samples.has(2360.0):
		rec.samples[2360.0] = {"phase": bus.phase, "visible": is_instance_valid(app._bus_body) and app._bus_body.visible, "day": d}
	for id: String in rec.pupils:
		var p: Dictionary = rec.pupils[id]
		var sim: LifeSim = app.household.member_sim(id)
		var actor: Node3D = app.world.actors[id]
		var away: String = str(sim.get_away_state().get("phase", "")) if sim.is_away() else ""
		# Walking out to the bus is never cancelled behind the pupil's back, for instance
		# when a brother or sister boarding first changes who is home.
		var front: String = str(sim.get_current_action().get("id", ""))
		if bool(p.boarding) and front not in ["board_school_bus", "school_day"] and away == "": p.dropped = int(p.dropped) + 1
		p.boarding = front == "board_school_bus"
		if d == 1 and away == "away" and float(p.left) < 0.0:
			p.left = now
			print("  [d%d %s] %s is away at school" % [d, clock(now), id])
		if away == "returning" and float(p.flip) < 0.0:
			p.flip = now
			print("  [d%d %s] %s is coming home, bus %s, visible %s" % [d, clock(now), id, bus.phase, str(actor.visible)])
		if away == "returning" and float(p.flip) >= 0.0 and float(p.off) < 0.0 and actor.visible:
			p.off = now
			p.off_pos = actor.position
			p.exit = bus.exit_position()
			p.bus_at_off = bus.phase
			print("  [d%d %s] %s steps off at (%.2f, %.2f), bus exit (%.2f, %.2f), bus %s" % [d, clock(now), id, actor.position.x, actor.position.z, p.exit.x, p.exit.z, bus.phase])
		if float(p.flip) >= 0.0 and float(p.home) < 0.0 and away == "" and p.state == "returning":
			p.home = now
			p.home_pos = actor.position
			p.home_indoors = app.world.construction.floor_contains(Vector2(actor.position.x, actor.position.z), 0)
			print("  [d%d %s] %s is home at (%.2f, %.2f) indoors %s" % [d, clock(now), id, actor.position.x, actor.position.z, str(p.home_indoors)])
		p.state = "returning" if away == "returning" else p.state
		if away == "" and float(p.home) >= 0.0: p.state = "home"

func run_until(rec: Dictionary, day: int, minutes: float, limit: int = 60000) -> void:
	for frame: int in limit:
		step(rec)
		var d: int = int(app.household.day)
		if d > day or (d == day and float(app.household.minutes) >= minutes): return

func events_to(rec: Dictionary, phase: String, day: int = -1) -> Array:
	return rec.events.filter(func(e: Dictionary) -> bool: return str(e.to) == phase and (day < 0 or int(e.day) == day))

func flat(point: Vector3) -> Vector2: return Vector2(point.x, point.z)

## The whole matrix for one household: Monday 07:00 to Tuesday 09:30.
func school_week(label: String, stages: Array, lot: int = 0) -> void:
	print("=== ", label)
	var pupils: Array = await boot(stages, 1, lot)
	check(LifeEducation.weekday(1) and LifeEducation.weekday_name(1) == "Monday", label + ": the day is a Monday")
	var rec: Dictionary = new_record(pupils)
	app.household.set_speed(8)
	run_until(rec, 2, 570.0)
	var bus: LifeSchoolBus = app.school_bus
	# ---- one morning run
	var morning: Array = events_to(rec, "waiting", 1).filter(func(e: Dictionary) -> bool: return float(e.at) < 540.0)
	check(morning.size() == 1 and events_to(rec, "approaching", 1).size() == 1, label + ": exactly one morning run, the bus reaches the curb once before 09:00 (%d, %d)" % [morning.size(), events_to(rec, "approaching", 1).size()])
	var last_left: float = 0.0
	for id: String in pupils: last_left = maxf(last_left, float(rec.pupils[id].left))
	var departing: Array = events_to(rec, "departing", 1)
	check(departing.size() == 1 and float(departing[0].at) >= last_left - 0.5 and float(departing[0].at) < 540.0, label + ": the bus leaves once, after the last pupil has boarded (last boarded %s, left %s)" % [clock(last_left), clock(float(departing[0].at)) if departing.size() > 0 else "never"])
	for id: String in pupils: check(float(rec.pupils[id].left) > 450.0 and float(rec.pupils[id].left) < 540.0, label + ": " + id + " boards the bus on Monday morning (" + clock(float(rec.pupils[id].left)) + ")")
	for id: String in pupils: check(int(rec.pupils[id].dropped) == 0, label + ": " + id + "'s walk out to the bus is never cancelled (" + str(rec.pupils[id].dropped) + " times)")
	# ---- away all school day
	for mark: float in [600.0, 720.0, 840.0]:
		var seen: Dictionary = rec.samples.get(mark, {})
		check(str(seen.get("phase", "")) == "gone" and not bool(seen.get("visible", true)), label + ": no bus at %s (%s, body shown %s)" % [clock(mark), str(seen.get("phase", "")), str(seen.get("visible", ""))])
	# ---- one drop-off
	var returning: Array = events_to(rec, "returning", 1)
	var dropping: Array = events_to(rec, "dropping", 1)
	check(returning.size() == 1 and dropping.size() == 1 and float(dropping[0].at) >= 890.0 and float(dropping[0].at) <= 900.0, label + ": exactly one drop-off, the bus at the curb between 14:50 and 15:00 (%s)" % (clock(float(dropping[0].at)) if dropping.size() > 0 else "never"))
	# ---- riders step off one at a time beside the bus
	var offs: Array = []
	for id: String in pupils:
		var p: Dictionary = rec.pupils[id]
		check(float(p.flip) >= 900.0 and float(p.flip) < 901.0, label + ": " + id + " finishes school at 15:00 (" + clock(float(p.flip)) + ")")
		check(float(p.off) >= float(p.flip) and float(p.off) - float(p.flip) < 2.0 and str(p.bus_at_off) == "dropping", label + ": " + id + " steps off a bus that is stopped at the curb, %.1f minutes after the bell (%s)" % [float(p.off) - float(p.flip), str(p.bus_at_off)])
		check(p.off_pos.is_finite() and flat(p.off_pos).distance_to(flat(p.exit)) < .6, label + ": " + id + " appears at the bus's exit (%.2f m away)" % (flat(p.off_pos).distance_to(flat(p.exit)) if p.off_pos.is_finite() else -1.0))
		offs.append(float(p.off))
	offs.sort()
	for index: int in range(1, offs.size()): check(offs[index] - offs[index - 1] >= LifeSchoolBus.STEP_OFF_GAP - .1, label + ": pupils step off one at a time (%.2f minutes apart)" % (offs[index] - offs[index - 1]))
	var leaving: Array = events_to(rec, "leaving", 1)
	check(leaving.size() == 1 and float(leaving[0].at) >= offs[offs.size() - 1] + LifeSchoolBus.DROP_HOLD - .5 and float(leaving[0].at) < LifeSchoolBus.DROP_GIVE_UP, label + ": the bus leaves only after every pupil is off, before 15:30 (%s)" % (clock(float(leaving[0].at)) if leaving.size() > 0 else "never"))
	# ---- straight indoors, to different places
	var spots: Array = []
	for id: String in pupils:
		var p: Dictionary = rec.pupils[id]
		check(float(p.home) > float(p.off) and float(p.home) < 930.0 and bool(p.home_indoors), label + ": " + id + " walks into the home from the bus, indoors by %s" % clock(float(p.home)))
		spots.append(p.home_pos)
	for a: int in spots.size():
		for b: int in range(a + 1, spots.size()):
			check(spots[a].distance_to(spots[b]) > .6, label + ": two pupils off the same bus come in to different spots (%.2f m apart)" % spots[a].distance_to(spots[b]))
	# ---- gone until the next school day
	var after: Array = rec.events.filter(func(e: Dictionary) -> bool: return int(e.day) == 1 and float(e.at) > float(leaving[0].at)) if leaving.size() > 0 else []
	check(after.size() == 1 and str(after[0].to) == "gone", label + ": after the drop-off the bus drives off and is not seen again that day (%d changes)" % after.size())
	for mark: float in [960.0, 1200.0, 2360.0]:
		var seen: Dictionary = rec.samples.get(mark, {})
		check(str(seen.get("phase", "")) == "gone" and not bool(seen.get("visible", true)), label + ": no bus at %s on %s (%s)" % [clock(360.0 if mark > 2000.0 else mark), "Tuesday" if mark > 2000.0 else "Monday", str(seen.get("phase", ""))])
	var next_morning: Array = rec.events.filter(func(e: Dictionary) -> bool: return int(e.day) == 2 and str(e.to) == "approaching")
	check(next_morning.size() == 1 and float(next_morning[0].at) >= 450.0 and float(next_morning[0].at) < 460.0, label + ": the next bus comes on Tuesday at 07:30 (%s)" % (clock(float(next_morning[0].at)) if next_morning.size() > 0 else "never"))
	check(events_to(rec, "returning", 2).is_empty() and events_to(rec, "dropping", 2).is_empty(), label + ": Tuesday has no drop-off yet at 09:30")
	var tuesday_leaving: Array = events_to(rec, "departing", 2)
	check(tuesday_leaving.size() == 1 and float(tuesday_leaving[0].at) < 540.0, label + ": Tuesday's bus takes the pupils and leaves too")
	for id: String in pupils:
		var sim: LifeSim = app.household.member_sim(id)
		check(int(sim.education.attended) == 1 and int(sim.education.missed) == 0, label + ": " + id + "'s Monday counts as attended, nothing missed")

func saved_while_aboard() -> void:
	# A game saved while the second pupil is still on the bus comes home too.
	print("=== a game saved with a pupil still aboard")
	var aboard_pupils: Array = await boot(["child", "teen"])
	var aboard_rec: Dictionary = new_record(aboard_pupils)
	app.household.set_speed(8)
	run_until(aboard_rec, 1, 898.0)
	var held: String = ""
	for frame: int in 4000:
		step(aboard_rec)
		for id: String in aboard_pupils:
			var p: Dictionary = aboard_rec.pupils[id]
			if float(p.flip) >= 0.0 and float(p.off) < 0.0 and not app.world.actors[id].visible: held = id
		if not held.is_empty() or float(app.household.minutes) > 910.0: break
	check(not held.is_empty() and app.school_bus.aboard.has(held), "The second pupil is still aboard the bus, out of sight, when the game is saved (%s)" % held)
	check(app.save_game("bus_aboard", "Bus aboard"), "A game saved with a pupil still on the bus is accepted")
	var aboard_slot: String = str(app.active_save_id)
	app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.load_game(aboard_slot)
	await frames(6)
	app.set_process(false)
	var back: Dictionary = new_record(aboard_pupils)
	app.household.set_speed(8)
	run_until(back, 1, 930.0)
	for id: String in aboard_pupils:
		var sim: LifeSim = app.household.member_sim(id)
		check(not sim.is_away() and app.world.actors[id].visible and app.world.construction.floor_contains(flat(app.world.actors[id].position), 0), "After loading, %s gets home and is indoors, not left aboard or outside" % id)

func run() -> void:
	await school_week("parent + child", ["child"])
	await school_week("parent + teen", ["teen"])
	await school_week("parent + child + teen", ["child", "teen"])
	await school_week("parent + two children + teen", ["child", "child", "teen"])

	# ---- every starter home lets a pupil in at the front door
	for lot: int in range(1, LifeProperties.starters_for([{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]).size()):
		var label: String = "starter %d" % lot
		print("=== ", label)
		var pupils: Array = await boot(["child"], 1, lot)
		var rec: Dictionary = new_record(pupils)
		app.household.set_speed(8)
		run_until(rec, 1, 930.0)
		var p: Dictionary = rec.pupils[pupils[0]]
		check(float(p.off) > 0.0 and flat(p.off_pos).distance_to(flat(p.exit)) < .6, label + ": the pupil steps off at the bus's exit")
		check(float(p.home) > float(p.off) and bool(p.home_indoors), label + ": and walks indoors (%s)" % clock(float(p.home)))

	# ---- a bus nobody boards still leaves at 09:00 and has nobody to bring home
	print("=== a pupil who stays home")
	var idle_pupils: Array = await boot(["child"])
	app.household.member_sim(idle_pupils[0]).autonomy = false
	var idle: Dictionary = new_record(idle_pupils)
	app.household.set_speed(8)
	run_until(idle, 1, 960.0)
	var idle_departing: Array = events_to(idle, "departing", 1)
	check(events_to(idle, "waiting", 1).size() == 1 and idle_departing.size() == 1 and absf(float(idle_departing[0].at) - 540.0) <= 1.0, "A bus nobody boards waits at the curb and leaves at 09:00 (%s)" % (clock(float(idle_departing[0].at)) if idle_departing.size() > 0 else "never"))
	check(events_to(idle, "returning").is_empty() and events_to(idle, "dropping").is_empty() and str(app.school_bus.phase) == "gone", "With nobody at school there is no afternoon run")

	# ---- no pupils, no bus
	print("=== two adults")
	await boot([], 1, 0, 2)
	var empty: Dictionary = new_record([])
	app.household.set_speed(8)
	run_until(empty, 1, 960.0)
	check(empty.events.is_empty() and str(app.school_bus.phase) == "gone", "A home without a school-age member never sees the bus (%d changes)" % empty.events.size())

	# ---- no bus at the weekend
	print("=== Saturday")
	var weekend_pupils: Array = await boot(["child", "teen"], 6)
	check(not LifeEducation.weekday(6), "Day 6 is a Saturday")
	var weekend: Dictionary = new_record(weekend_pupils)
	app.household.set_speed(8)
	run_until(weekend, 6, 960.0)
	check(weekend.events.is_empty(), "There is no bus on a Saturday (%d changes)" % weekend.events.size())

	# ---- a pupil turned back at the bus door neither sends it away early nor is told they boarded
	print("=== a hungry pupil at the door")
	var hungry_pupils: Array = await boot(["child"])
	var hungry: LifeSim = app.household.member_sim(hungry_pupils[0])
	hungry.autonomy = false
	var hungry_rec: Dictionary = new_record(hungry_pupils)
	app.household.set_speed(8)
	run_until(hungry_rec, 1, 480.0)
	check(app.school_bus.waiting(), "The bus is at the curb at 08:00")
	hungry.needs.hunger = 9.0
	check(hungry.queue_action("board_school_bus", "school_bus_stop", app.school_bus.door_position()), "The hungry pupil is sent to the bus")
	run_until(hungry_rec, 1, 600.0)
	var hungry_leaving: Array = events_to(hungry_rec, "departing", 1)
	check(not hungry.is_away() and int(hungry.education.last_attendance_day) != 1, "A pupil too hungry to go stays home")
	check(notices.any(func(m: String) -> bool: return "urgent needs" in m) and not notices.any(func(m: String) -> bool: return "boards the school bus" in m), "They are told why, not that they boarded (%s)" % str(notices.slice(maxi(0, notices.size() - 3))))
	check(app.school_bus.boarded == 0 and hungry_leaving.size() == 1 and float(hungry_leaving[0].at) >= 540.0 and float(hungry_leaving[0].at) <= 542.0, "The bus did not leave early, and still leaves by 09:00 (%s)" % (clock(float(hungry_leaving[0].at)) if hungry_leaving.size() > 0 else "never"))

	# ---- a game saved during the school day brings the pupil home, and the bus comes from the clock
	print("=== a game saved at noon")
	var saved_pupils: Array = await boot(["child", "teen"])
	var saved_rec: Dictionary = new_record(saved_pupils)
	app.household.set_speed(8)
	run_until(saved_rec, 1, 720.0)
	for id: String in saved_pupils: check(app.household.member_sim(id).is_away(), "At noon %s is at school" % id)
	check(app.save_game("bus_noon", "Bus noon"), "A game saved at noon, with the pupils at school, is accepted")
	var slot: String = str(app.active_save_id)
	app.queue_free(); await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.load_game(slot)
	await frames(6)
	app.set_process(false)
	var loaded_ids: Array = []
	for member: Dictionary in app.household.members:
		if str(member.sim.character.age_stage) in ["child", "teen"]: loaded_ids.append(str(member.id))
	check(loaded_ids.size() == 2 and str(app.school_bus.phase) == "gone" and LifeSchoolBus.active == app.school_bus, "The loaded game has a bare street and one bus (%s)" % app.school_bus.phase)
	var loaded: Dictionary = new_record(loaded_ids)
	app.household.set_speed(8)
	run_until(loaded, 1, 930.0)
	check(events_to(loaded, "returning", 1).size() == 1 and events_to(loaded, "dropping", 1).size() == 1, "The loaded game still gets its one drop-off")
	for id: String in loaded_ids:
		var p: Dictionary = loaded.pupils[id]
		check(float(p.off) > 0.0 and flat(p.off_pos).distance_to(flat(p.exit)) < .6 and bool(p.home_indoors), "After loading, %s steps off at the bus and walks indoors" % id)

	await saved_while_aboard()

	print("SCHOOL_BUS_FULL_DAY ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
