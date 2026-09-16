extends SceneTree
## An elder who finishes their last stage passes on at home, leaves the purse
## with the living household, and can be remembered after a JSON save.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func run() -> void:
	var home := LifeHousehold.new()
	root.add_child(home)
	home.new_household([
		{"name": "Sage Vale", "age_stage": "elder", "traits": ["Creative"], "aspiration": "Balanced"},
		{"name": "Robin Vale", "age_stage": "adult", "traits": ["Outgoing"], "aspiration": "Connected"},
	])
	home.set_speed(1)
	var elder: LifeSim = home.member_sim("player")
	var heir: LifeSim = home.member_sim("housemate_1")
	elder.autonomy = false
	heir.autonomy = false
	elder.lifecycle.progress = 1.0
	var purse: int = home.funds
	home.tick(0.25)
	check(elder.is_spirit(), "An idle elder at the end of their stage becomes a spirit")
	check(str(elder.character.life_status) == "passed", "The elder's life status is recorded as passed")
	check(bool(elder.lifecycle.get("passed", false)), "The age line records that they have passed")
	check(not heir.is_spirit(), "A living housemate stays living")
	check(home.funds == purse + LifeHousehold.ESTATE_GIFT, "The household receives an estate gift that was not already in the purse")
	check(home.heirlooms.size() == 1 and str(home.heirlooms[0].from) == "Sage Vale", "A named keepsake is left for the living household")
	check(home.memorials.size() == 1 and str(home.memorials[0].member_id) == "player", "The household keeps a memorial for the person who passed")
	check(str(home.memorials[0].name) == "Sage Vale", "The memorial remembers their name")
	var mourning: bool = false
	for mood: Dictionary in heir.moodlets:
		if str(mood.label) == "In mourning":
			mourning = true
	check(mourning, "The living housemate mourns")
	var farewell: bool = false
	for memory: Dictionary in heir.memories:
		if str(memory.label) == "A farewell":
			farewell = true
	check(farewell, "The living housemate inherits a farewell memory")
	check(not bool(elder.get_action_availability("career_day").available), "A spirit cannot leave for work")
	check(not bool(elder.get_action_availability(LifeBabyPlan.ACTION_ID).available), "A spirit cannot start a new family")
	check(not bool(elder.get_action_availability("cook").available), "A spirit cannot cook")
	check(not bool(elder.get_action_availability("flirt").available), "A spirit cannot flirt")
	check(str(elder.passing_cause()) == "old_age", "Old-age passing records its cause")
	check(str(home.heirlooms[0].get("note", "")).contains("long life"), "The keepsake can be inspected")
	var restored := LifeHousehold.new()
	root.add_child(restored)
	var loaded: Dictionary = restored.restore_state(JSON.parse_string(JSON.stringify(home.json_safe(home.get_state()))))
	check(bool(loaded.ok), "A passing survives JSON restore: " + str(loaded.get("error", "")))
	check(restored.member_sim("player").is_spirit(), "The restored elder is still a spirit")
	check(restored.memorials.size() == 1 and str(restored.memorials[0].name) == "Sage Vale", "The memorial survives the save")
	check(restored.funds == purse + LifeHousehold.ESTATE_GIFT, "The estate gift survives the save")
	check(restored.heirlooms.size() == 1, "The keepsake survives the save")
	check(LifeLifecycle.description("elder", restored.member_sim("player").lifecycle).contains("spirit"), "The restored age line names a spirit")
	var solo := LifeSim.new()
	root.add_child(solo)
	solo.new_household({"name": "Ellis Vale", "age_stage": "elder"})
	solo.autonomy = false
	solo.lifecycle.progress = 1.0
	solo.tick(0.25)
	check(solo.is_spirit(), "A last remaining elder also becomes a playable spirit")
	var hungry := LifeSim.new()
	root.add_child(hungry)
	hungry.new_household({"name": "Noa Vale", "age_stage": "adult"})
	hungry.autonomy = false
	hungry.needs.hunger = 0.0
	for _i: int in range(4):
		hungry.tick(60.0)
	check(hungry.is_spirit() and hungry.passing_cause() == "hunger", "A Lifelet who stays starving becomes a spirit")
	var runner := LifeSim.new()
	root.add_child(runner)
	runner.new_household({"name": "Kit Vale", "age_stage": "adult"})
	runner.autonomy = false
	runner.queue_action("jog", "treadmill")
	runner.begin_current_action()
	if not runner.action_queue.is_empty():
		runner.action_queue[0]["duration"] = 90.0
	runner.needs.energy = 0.0
	for _j: int in range(2):
		runner.tick(60.0)
	check(runner.is_spirit() and runner.passing_cause() == "exhaustion", "Overexertion on a run can pass a Lifelet")
	var busy := LifeHousehold.new()
	root.add_child(busy)
	busy.new_household([{"name": "Blair Vale", "age_stage": "elder"}])
	var waiting: LifeSim = busy.member_sim("player")
	waiting.autonomy = false
	waiting.lifecycle.progress = 1.0
	waiting.queue_action("read", "bookshelf")
	waiting.begin_current_action()
	waiting.action_queue[0]["duration"] = 400.0
	for _k: int in range(5):
		waiting.tick(60.0)
	check(waiting.is_spirit(), "An elder cannot queue passing away forever")
	var lot := LifeWorld.new()
	root.add_child(lot)
	await process_frame
	lot.create_home(LifeCatalog.starter_layout(0))
	check(lot.ensure_memorial("player"), "A remembrance stone can be placed on a starter lot")
	var stones: int = 0
	for item: Dictionary in lot.items:
		if str(item.get("kind", "")) == "memorial" and str(item.get("for", "")) == "player":
			stones += 1
	check(stones == 1, "The garden stone is recorded on the lot")
	# The garden stone is walkable, so can_place accepts it anywhere and cannot
	# report the stones already standing there. Without comparing against them,
	# every later remembrance was planted inside the first one.
	var spots: Dictionary = {}
	for index: int in range(10):
		lot.ensure_memorial("filler_%d" % index)
	for item: Dictionary in lot.items:
		if str(item.get("kind", "")) != "memorial":
			continue
		var at: Vector2 = Vector2(item.node.position.x, item.node.position.z)
		spots[at] = int(spots.get(at, 0)) + 1
	var crowded: Array[String] = []
	for at: Vector2 in spots:
		if int(spots[at]) > 1:
			crowded.append("%s x%d" % [str(at), int(spots[at])])
	check(spots.size() == 11 and crowded.is_empty(), "Eleven remembrance stones each stand in their own place (distinct %d, crowded %s)." % [spots.size(), str(crowded)])
	# A passing ends every plan, and a queued meal action owns a dish in the meal
	# ledger. The dish must be released, not left owned with no action to claim
	# it, or the household's own save is refused afterwards with "A carried or
	# active food has no matching action."
	var carried: Dictionary = home.meals.create_batch("garden_skillet", "player", 2, "home", 0.0)
	var batches: Array = home.meals.get_state().get("batches", [])
	var held_id: String = str(home.meals.carried_by("player").get("id", ""))
	check(not held_id.is_empty(), "The carrier really holds a cooked dish")
	var living: Array = [{"id": "player", "state": {"character": {"life_status": "living"}}}]
	check(LifeMeals.validate_actions(home.meals.get_state(), living) != "", "A living Lifelet holding an unclaimed dish is refused, as before")
	var passed_members: Array = [{"id": "player", "state": {"character": {"life_status": "passed"}}}]
	check(LifeMeals.validate_actions(home.meals.get_state(), passed_members) == "", "A passed Lifelet's released dish no longer blocks the save")
	var carrier := LifeSim.new()
	root.add_child(carrier)
	carrier.new_household({"name": "Carrier", "age_stage": "elder"})
	carrier.register_targets([{"id": "plate", "kind": "plate", "position": Vector3.ZERO}], false)
	carrier.queue_action("eat_meal", "plate", Vector3.ZERO)
	check(carrier.get_current_action().id == "eat_meal", "The carrier has a real eating action to interrupt")
	carrier.lifecycle.progress = 1.0
	check(carrier.pass_on(), "The carrier passes on while a plate is in hand")
	check(carrier.action_queue.is_empty(), "The passing empties the queue")
	carrier.queue_free()
	home.queue_free()
	restored.queue_free()
	solo.queue_free()
	hungry.queue_free()
	runner.queue_free()
	busy.queue_free()
	lot.queue_free()
	await process_frame
	print("PASSING_RESULT ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
