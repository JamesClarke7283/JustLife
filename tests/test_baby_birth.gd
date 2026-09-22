extends SceneTree
## A born baby must be part of the household in every way a player notices: the
## household records the child, the child carries the family's own surname, the
## life box shows a chip to click, that chip really selects and controls them, and
## the child is still there after a save and a fresh process loads it.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_baby_birth.gd

const STAGE_SAVE: String = "baby-birth-probe"

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("The baby test requires an isolated JUSTLIFE_DATA_DIR.")
		quit(2); return
	_run.call_deferred()

## The fresh-process half: load the save the producer wrote and confirm the baby
## is a real member again, with a chip and a controllable body.
func _consume() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	var slot: String = ""
	for entry: Dictionary in LifeSaveLibrary.list_saves():
		if str(entry.get("name", "")) == STAGE_SAVE: slot = str(entry.get("id", ""))
	check(not slot.is_empty(), "The producer's save is really in the picker (%s)." % slot)
	if slot.is_empty():
		app.queue_free(); await frames(2); quit(1); return
	app.load_game(slot)
	for i: int in 60: await process_frame
	var baby_id: String = _baby_id()
	check(app.household.members.size() == 3, "A fresh load restores all three Lifelets (%d)." % app.household.members.size())
	check(not baby_id.is_empty(), "The baby is a member again after a fresh load (%s)." % baby_id)
	if not baby_id.is_empty():
		var baby: LifeSim = app.household.member_sim(baby_id)
		check(str(baby.character.name).ends_with("Stone"),
			"The restored baby keeps the family surname (%s)." % str(baby.character.name))
		app.refresh_hud(); await frames(4)
		check(app.household_chips.has(baby_id),
			"The restored baby has a life-box chip again (%s)." % str(app.household_chips.keys()))
		var index: int = 0
		for i: int in range(app.household.members.size()):
			if str(app.household.members[i].id) == baby_id: index = i
		app.select_household_member(index)
		await frames(4)
		check(str(app.household.selected_id()) == baby_id,
			"The restored baby can be selected and controlled (%s)." % str(app.household.selected_id()))
		check(is_instance_valid(app.world.actors.get(baby_id)) and app.world.actors[baby_id].visible,
			"The restored baby has a visible body on the lot.")
	app.queue_free(); await frames(2)
	print("BABY_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "phase": "consume"}))
	quit(0 if failures.is_empty() else 1)

## Conceive through the game's own plan and run the shipped clock at top speed
## until the birth resolves, exactly as play does.
func _conceive_and_wait(owner_id: String, father_id: String) -> bool:
	app.household.pregnancy = LifeBabyPlan.conceive(
		app.household.member_sim(owner_id), owner_id,
		app.household.member_sim(father_id), father_id,
		app.household.day, app.household.minutes, 1)
	# Snap due so the suite proves the birth path without waiting fourteen days.
	app.household.pregnancy["due_at"] = LifeBabyPlan.now_of(app.household.day, app.household.minutes)
	app.household.set_speed(3)
	var guard: int = 0
	while not app.household.birth_ready() and guard < 60000:
		app._process(.2)
		guard += 1
		if guard % 50 == 0: await process_frame
	return app.household.birth_ready()

## Name the pending baby through the production creator's own confirm.
func _name_and_join() -> void:
	var pending: Dictionary = app.household.pending_baby_profile().duplicate(true)
	pending["age_stage"] = "baby"
	pending["life_stage"] = "minor"
	app.profile = pending
	app.creator_purpose = "baby"
	app.confirm_baby_creator()
	await frames(8)

func _baby_id() -> String:
	for member: Dictionary in app.household.members:
		if str(member.sim.character.age_stage) == "baby": return str(member.id)
	return ""

func _run() -> void:
	# A second run of this same script, sharing the data dir, loads what the
	# first one saved: the baby must be there, chipped and controllable again.
	if OS.get_environment("BABY_BIRTH_PHASE") == "consume":
		await _consume(); return
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
	var owner_id: String = str(app.household.selected_id())
	var before: int = app.household.members.size()
	check(before == 2, "The household starts with the two parents (%d)." % before)

	# ------------------------------------------------------------------ birth
	check(await _conceive_and_wait(owner_id, "housemate_1"),
		"The household really reaches the end of its term.")
	var rolled: Dictionary = app.household.pending_baby_profile()
	check(str(rolled.get("name", "")).ends_with("Stone"),
		"The named baby carries the family's own surname (%s)." % str(rolled.get("name", "")))
	await _name_and_join()

	check(app.household.members.size() == before + 1,
		"Naming the baby really adds them to the household (%d members)." % app.household.members.size())
	var baby_id: String = _baby_id()
	check(not baby_id.is_empty(), "The household holds a member of the baby stage (%s)." % baby_id)
	if baby_id.is_empty():
		app.queue_free(); await frames(2); quit(1); return
	# Hospital stay serializes the baby before they are visible on the lot.
	check(bool(app.household.birth_homecoming.get("active", false)),
		"Confirming the creator starts the hospital homecoming.")
	check(app.household.member_sim(baby_id).is_away(),
		"The newborn is held at the hospital (away) until Welcome Baby Home.")
	app.household.choose_birth_dad(LifeBirthHomecoming.DAD_NOTIFY)
	if app.household.speed <= 0: app.household.set_speed(1)
	app.close_overlay(false)
	app.welcome_baby_home()
	var guard: int = 0
	while not app.birth_arrival.is_empty() and guard < 800:
		app._process(0.2)
		guard += 1
		if guard % 20 == 0: await process_frame
	if not app.birth_arrival.is_empty():
		app.household.finish_welcome_baby_home()
		app._sync_all_away_presence()
		app._end_birth_arrival_cinematic()
	await frames(6)
	var baby: LifeSim = app.household.member_sim(baby_id)
	check(str(baby.character.name).ends_with("Stone"),
		"The member the household added really keeps the family surname (%s)." % str(baby.character.name))
	check(not baby.is_away(),
		"Welcome Baby Home clears the hospital away-state.")

	# ------------------------------------------------- the life box and control
	app.refresh_hud(); await frames(4)
	check(app.household_chips.has(baby_id),
		"The baby has a chip in the life box to click and control (%s)." % str(app.household_chips.keys()))
	if app.household_chips.has(baby_id):
		var chip: Control = app.household_chips[baby_id]
		check(chip.visible and chip.size.x > 0 and chip.size.y > 0,
			"The baby's chip is really shown and pressable (%s)." % str(chip.size))
	# Clicking the chip is what selects the child: dispatch the real press.
	var index: int = 0
	for i: int in range(app.household.members.size()):
		if str(app.household.members[i].id) == baby_id: index = i
	app.select_household_member(index)
	await frames(4)
	check(str(app.household.selected_id()) == baby_id,
		"Selecting the baby's chip really makes them the controlled Lifelet (%s)." % str(app.household.selected_id()))
	check(is_instance_valid(app.world.actors.get(baby_id)),
		"The baby has a live body in the world to control.")
	check(is_instance_valid(app.world.actors.get(baby_id)) and app.world.actors[baby_id].visible,
		"The baby's body is really visible on the lot.")

	# --------------------------------------------------- save and fresh restore
	check(app.save_game("", STAGE_SAVE), "The household with its baby really saves.")
	app.queue_free(); await frames(2)
	print("BABY_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "baby": baby_id}))
	quit(0 if failures.is_empty() else 1)
