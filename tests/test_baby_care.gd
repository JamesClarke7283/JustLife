extends SceneTree
## Baby care: a caregiver feeds, changes, cuddles and plays with the baby from the
## nursery furniture, and each action answers the baby's own need rather than the
## caregiver's.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_baby_care.gd

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void: _run.call_deferred()

## Lay the nursery out on the starter home and return each placed family by kind.
func _place_nursery() -> void:
	for kind: String in ["cot", "child_bed", "changing_table", "potty", "baby_toys", "fridge"]:
		var at: Vector3 = _spot(kind)
		if not at.is_finite(): continue
		app.on_placement(kind, at, 0.0)
		await frames(3)

func _spot(kind: String) -> Vector3:
	for radius: int in range(0, 26):
		for x: int in range(-radius, radius + 1):
			for z: int in range(-radius, radius + 1):
				if maxi(abs(x), abs(z)) != radius: continue
				var at := Vector3(float(x) * .5, .16, float(z) * .5)
				if app.world.can_place(kind, at, 0.0): return at
	return Vector3.INF

func _item(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: return item
	return {}

## Birth a baby through the ordinary pregnancy, so the child is a real member.
func _birth_baby() -> LifeSim:
	var owner_id: String = str(app.household.selected_id())
	app.household.pregnancy = LifeBabyPlan.conceive(
		app.household.member_sim(owner_id), owner_id,
		app.household.member_sim("housemate_1"), "housemate_1",
		app.household.day, app.household.minutes, 1)
	app.household.set_speed(3)
	var guard: int = 0
	while not app.household.birth_ready() and guard < 60000:
		app._process(.2); guard += 1
		if guard % 50 == 0: await process_frame
	if not app.household.birth_ready(): return null
	var pending: Dictionary = app.household.pending_baby_profile().duplicate(true)
	pending["age_stage"] = "baby"; pending["life_stage"] = "minor"
	app.profile = pending; app.creator_purpose = "baby"
	app.confirm_baby_creator()
	await frames(8)
	for member: Dictionary in app.household.members:
		if str(member.sim.character.age_stage) == "baby": return member.sim
	return null

## Run one care action to completion through the simulated clock.
func _run_action(target_kind: String, action_id: String) -> Dictionary:
	var item: Dictionary = _item(target_kind)
	if item.is_empty(): return {}
	app.queue_interaction(item, action_id)
	await frames(4)
	var queued: Dictionary = app.sim.get_current_action()
	if str(queued.get("id", "")) != action_id: return {"queued": false, "action": queued}
	app.household.set_speed(3)
	var guard: int = 0
	while guard < 8000:
		app._process(.2); guard += 1
		if guard % 40 == 0: await process_frame
		var now: Dictionary = app.sim.get_current_action()
		if str(now.get("id", "")) != action_id: break
	return {"queued": true, "guard": guard}

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.household_profiles = [
		{"name": "Avery Stone", "age_stage": "young_adult", "traits": [], "hair": 0, "gender": "female"},
		{"name": "River Stone", "age_stage": "young_adult", "traits": [], "hair": 0, "gender": "male"}]
	app.creator_family_links = []
	app.start_household(); await frames(10)
	app.household.set_speed(0)
	app.household.set_funds(900000)
	await frames(2)

	# No baby yet: the care buttons must not appear.
	var fridge_before: Array = app.sim.get_actions_for("fridge", "fridge")
	check(not fridge_before.any(func(a: Dictionary) -> bool: return str(a.get("id", "")).begins_with("feed_baby")),
		"A household with no baby is not offered baby feeding.")
	app.set_build_mode(true); await frames(3)
	await _place_nursery()
	app.set_build_mode(false); await frames(3)
	check(not _item("changing_table").is_empty(), "The nursery furniture is really placed.")
	check(not _item("baby_toys").is_empty(), "The baby toys are really placed.")
	check(not _item("fridge").is_empty(), "A fridge stands in the home.")

	var baby: LifeSim = await _birth_baby()
	check(baby != null, "A baby is born into the household.")
	if baby == null:
		app.queue_free(); await frames(2); quit(1); return
	var baby_name: String = str(baby.character.name).split(" ")[0]
	app.select_household_member(0)   # the caregiver
	await frames(4)
	check(str(app.household.selected_id()) != str(baby.character.name), "The caregiver is the controlled Lifelet.")
	# Let the caregiver finish whatever the birth left them doing, so the first
	# care instruction is judged on its own merits rather than on a busy queue.
	app.household.set_speed(3)
	var settle: int = 0
	while not app.sim.action_queue.is_empty() and settle < 4000:
		app._process(.2); settle += 1
		if settle % 40 == 0: await process_frame
	app.household.set_speed(0)
	await frames(4)
	check(app.sim.action_queue.is_empty(), "The caregiver is free before the care actions start.")

	# ------------------------------------------------------- offered from the fridge
	var offered: Array = app.sim.get_actions_for("fridge", "fridge")
	var ids: Array = offered.map(func(a: Dictionary) -> String: return str(a.get("id", "")))
	check(ids.has("feed_baby_bottle") and ids.has("feed_baby_food"),
		"The fridge offers the bottle and the jar once a baby is here (%s)." % str(ids))

	# ---------------------------------------------------------------- feeding
	baby.needs["hunger"] = 10.0
	var before: float = float(baby.needs["hunger"])
	var run: Dictionary = await _run_action("fridge", "feed_baby_bottle")
	check(bool(run.get("queued", false)), "The bottle action really queues from the fridge.")
	check(float(baby.needs["hunger"]) > before + 20.0,
		"Feeding the bottle really raises the baby's own hunger (%.0f -> %.0f)." % [before, float(baby.needs["hunger"])])

	baby.needs["hunger"] = 8.0
	before = float(baby.needs["hunger"])
	await _run_action("fridge", "feed_baby_food")
	check(float(baby.needs["hunger"]) > before + 40.0,
		"The jar of baby food really fills the baby up (%.0f -> %.0f)." % [before, float(baby.needs["hunger"])])

	# ------------------------------------------------------------ changing
	var table: Array = app.sim.get_actions_for("changing_table", "changing_table")
	check(table.any(func(a: Dictionary) -> bool: return str(a.get("id", "")) == "change_nappy"),
		"The changing table offers a nappy change.")
	baby.needs["hygiene"] = 12.0
	baby.needs["bladder"] = 15.0
	var hyg: float = float(baby.needs["hygiene"])
	var blad: float = float(baby.needs["bladder"])
	await _run_action("changing_table", "change_nappy")
	check(float(baby.needs["hygiene"]) > hyg + 30.0 and float(baby.needs["bladder"]) > blad + 30.0,
		"A nappy change really answers the baby's hygiene and bladder (%.0f/%.0f -> %.0f/%.0f)." % [
			hyg, blad, float(baby.needs["hygiene"]), float(baby.needs["bladder"])])

	# --------------------------------------------------------- social needs
	baby.needs["social"] = 5.0
	before = float(baby.needs["social"])
	await _run_action("baby_toys", "play_with_baby")
	check(float(baby.needs["social"]) > before + 20.0,
		"Playing with the baby really raises their social need (%.0f -> %.0f)." % [before, float(baby.needs["social"])])

	baby.needs["social"] = 5.0
	before = float(baby.needs["social"])
	await _run_action("cot", "cuddle_baby")
	check(float(baby.needs["social"]) > before + 20.0,
		"Picking the baby up for a cuddle really fills their social need (%.0f -> %.0f)." % [before, float(baby.needs["social"])])

	app.queue_free(); await frames(3)
	print("BABY_CARE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
