extends SceneTree

const Simulation = preload("res://scripts/life_sim.gd")
var _failures: int = 0
var _assertions: int = 0


func _initialize() -> void:
	_test_queue_and_resources()
	_test_pause_and_clock()
	_test_traits_and_relationships()
	_test_income_and_wants()
	_test_autonomy()
	_test_persistence_and_validation()
	print("Simulation: %d assertions, %d failures." % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _new_sim(profile: Dictionary = {}) -> Node:
	var sim: Node = Simulation.new()
	sim.new_household(profile)
	sim.autonomy = false
	return sim


func _check(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error(message)


func _advance(sim: Node, game_minutes: float) -> void:
	var remaining: float = game_minutes
	while remaining > 0.0001:
		var step: float = minf(remaining, 60.0)
		sim.tick(step / Simulation.GAME_MINUTES_PER_SECOND)
		remaining -= step


func _complete(sim: Node, id: String, target: String = "") -> void:
	sim.queue_action(id, target)
	sim.begin_current_action()
	_advance(sim, float(sim.get_current_action()["duration"]))


func _test_queue_and_resources() -> void:
	var sim: Node = _new_sim()
	var started: Array = []
	var finished: Array = []
	sim.action_started.connect(func(action: Dictionary) -> void: started.append(action["id"]))
	sim.action_finished.connect(func(action: Dictionary) -> void: finished.append(action["id"]))
	_check(sim.queue_action("snack", "fridge_1", Vector3(2, 0, 3)), "Snack should queue.")
	_check(sim.queue_action("shower", "shower_1"), "Second activity should queue.")
	_check(started == ["snack"], "Only the front activity should start its approach.")
	var hunger_before: float = float(sim.needs["hunger"])
	_advance(sim, 3)
	_check(float(sim.needs["hunger"]) < hunger_before and sim.funds == 2500, "Approaching must not grant activity effects or spend money.")
	sim.begin_current_action()
	sim.begin_current_action()
	_check(sim.funds == 2492, "Ingredients should be charged only once.")
	_advance(sim, 7.5)
	_check(float(sim.needs["hunger"]) > hunger_before and is_equal_approx(float(sim.get_current_action()["progress"]), 0.5), "Needs should recover gradually with action progress.")
	_advance(sim, 7.5)
	_check(finished == ["snack"] and started == ["snack", "shower"], "Finishing should advance the queue exactly once.")
	_check(str(sim.get_current_action()["phase"]) == "approach", "Next activity must wait for world arrival.")
	sim.cancel_action()
	_check(sim.action_queue.is_empty(), "Canceling the last action should return to idle.")
	for index: int in range(8):
		sim.queue_action("relax", str(index))
	_check(not sim.queue_action("relax") and sim.action_queue.size() == 8, "Queue capacity must prevent a ninth action.")
	_check(not sim.queue_action("missing_action"), "Unknown activity IDs must be rejected.")
	sim.free()


func _test_pause_and_clock() -> void:
	var sim: Node = _new_sim()
	sim.set_speed(0)
	var state: Dictionary = sim.get_state()
	sim.tick(30)
	_check(sim.minutes == state["minutes"] and sim.needs == state["needs"], "Pause should freeze the clock and needs.")
	sim.set_speed(3)
	sim.tick(1.0)
	_check(is_equal_approx(sim.minutes, 498.0), "Speed 3 should advance eighteen game minutes per second.")
	sim.set_speed(2)
	_check(sim.speed == 3, "Unsupported speeds must leave the speed unchanged.")
	sim.set_speed(1)
	sim.minutes = 1439.0
	_advance(sim, 2.0)
	_check(sim.day == 2 and is_equal_approx(sim.minutes, 1.0) and sim.funds == 2465, "Midnight must roll the day and charge one household bill.")
	_check(sim.bills_paid == 35 and sim.last_bill_day == 2, "Bill accounting must match the household charge.")
	for need_name: String in Simulation.NEED_NAMES:
		sim.needs[need_name] = 0.01
	_advance(sim, 120)
	_check(sim.needs.values().all(func(value: Variant) -> bool: return float(value) >= 0.0), "Needs must not fall below zero.")
	sim.free()


func _test_traits_and_relationships() -> void:
	var creative: Node = _new_sim({"traits": ["Creative", "Outgoing"]})
	var neutral: Node = _new_sim({"traits": []})
	_complete(creative, "paint")
	_complete(neutral, "paint")
	_check(int(creative.skills["creativity"]["level"]) > int(neutral.skills["creativity"]["level"]), "Creative must meaningfully accelerate painting skill.")
	_check(float(creative.needs["fun"]) > float(neutral.needs["fun"]), "Creative should enjoy painting more.")
	_complete(creative, "friendly", "maya")
	_complete(neutral, "friendly", "maya")
	_check(float(creative.relationships["maya"]["friendship"]) > float(neutral.relationships["maya"]["friendship"]), "Outgoing should improve social relationship gains.")
	var friendship_before: float = float(neutral.relationships["leo"]["friendship"])
	_complete(neutral, "flirt", "leo")
	_check(float(neutral.relationships["leo"]["romance"]) == 0.0 and float(neutral.relationships["leo"]["friendship"]) < friendship_before, "Premature flirting should have a social consequence.")
	neutral.relationships["leo"]["friendship"] = 45.0
	_complete(neutral, "flirt", "neighbor_leo")
	_check(float(neutral.relationships["leo"]["romance"]) == 16.0, "Flirting with a friend should build romance, including prefixed neighbor IDs.")
	var romance_before: float = float(neutral.relationships["leo"]["romance"])
	_complete(neutral, "argue", "leo")
	_check(float(neutral.relationships["leo"]["romance"]) < romance_before, "Arguments should harm romance.")
	creative.free()
	neutral.free()


func _test_income_and_wants() -> void:
	var sim: Node = _new_sim({"aspiration": "Successful", "traits": []})
	_complete(sim, "job")
	_check(sim.funds == 2680 and int(sim.career["worked_day"]) == 1, "Job shifts should pay the advertised daily salary.")
	_check(not sim.queue_action("job"), "A second job shift on the same day must be rejected.")
	var funds_before: int = sim.funds
	_complete(sim, "work")
	_check(sim.funds > funds_before, "Freelance work should earn money after the daily shift.")
	_complete(sim, "paint")
	_check(sim.satisfaction == 180 and bool(sim.wants[2]["complete"]), "Successful aspiration should reward three completed earning activities.")
	var satisfaction_before: int = sim.satisfaction
	_advance(sim, 10)
	_check(sim.satisfaction == satisfaction_before, "Completed wants must never pay twice.")
	sim.funds = 0
	_check(not sim.queue_action("cook") and sim.queue_action("work"), "Broke households must still have a free way to earn money.")
	sim.cancel_action()
	sim.career["performance"] = 99.0
	sim.career["worked_day"] = 0
	_complete(sim, "job")
	_check(int(sim.career["level"]) == 2 and int(sim.career["salary"]) == 290, "Sufficient career performance should earn a promotion and raise.")
	sim.free()


func _test_autonomy() -> void:
	var sim: Node = _new_sim()
	sim.autonomy = true
	sim.needs["bladder"] = 10.0
	sim.register_targets([{"id": "bathroom_toilet", "kind": "toilet", "position": Vector3(4, 0, 5)}])
	_advance(sim, 15)
	_check(str(sim.get_current_action().get("id", "")) == "toilet", "Autonomy should select a reachable target for the lowest need.")
	_check(bool(sim.get_current_action().get("autonomous", false)), "Autonomous actions should be identifiable in the UI.")
	_check(sim.get_current_action()["target_position"] == Vector3(4, 0, 5), "Autonomy must hand the registered destination to the world.")
	sim.free()


func _test_persistence_and_validation() -> void:
	var sim: Node = _new_sim({"name": "Taylor", "traits": ["Bookworm"], "aspiration": "Maker", "hair_color": 2})
	sim.queue_action("cook", "fridge", Vector3(2, 0, 1))
	sim.begin_current_action()
	_advance(sim, 20)
	sim.queue_action("read", "books", Vector3(-2, 0, 3))
	var saved: Dictionary = sim.get_state()
	var loaded: Node = _new_sim()
	var restored: Dictionary = loaded.restore_state(saved)
	_check(bool(restored["ok"]) and loaded.character["name"] == "Taylor", "In-memory restore should preserve profile and household.")
	_check(loaded.action_queue.size() == 2 and is_equal_approx(float(loaded.get_current_action()["elapsed"]), 20.0), "Restore should preserve queue and action progress.")
	_check(loaded.get_current_action()["target_position"] == Vector3(2, 0, 1), "Restore should preserve vector targets.")
	_check(str(loaded.get_current_action()["phase"]) == "approach", "A loaded action must wait for the world to place the actor.")
	loaded.begin_current_action()
	_check(loaded.funds == saved["funds"], "Resume must not charge ingredients twice.")
	_advance(loaded, 25)
	_check(str(loaded.get_current_action()["id"]) == "read", "Resumed activities must complete using remaining duration.")
	var live_before: Dictionary = loaded.get_state()
	var broken: Dictionary = saved.duplicate(true)
	broken["needs"]["energy"] = "bad"
	_check(not bool(loaded.restore_state(broken)["ok"]) and loaded.get_state() == live_before, "Rejected saves must not partially mutate the current household.")
	broken = saved.duplicate(true)
	broken["action_queue"][0]["id"] = "unknown"
	_check(not bool(loaded.restore_state(broken)["ok"]), "Unknown saved actions should be rejected.")
	broken = saved.duplicate(true)
	broken["skills"]["cooking"] = null
	_check(not bool(loaded.restore_state(broken)["ok"]), "Malformed nested skill data should be rejected safely.")
	# Preserve any existing real save so this executable test remains nondestructive.
	var existed: bool = FileAccess.file_exists(Simulation.SAVE_PATH)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(Simulation.SAVE_PATH) if existed else PackedByteArray()
	var world: Array = [{"id": "easel_new", "kind": "easel", "position": Vector3(6, 0, 2), "rotation": 1.5}]
	_check(sim.save_game(world), "Saving a household should succeed.")
	var disk_result: Dictionary = loaded.load_game()
	_check(bool(disk_result["ok"]) and disk_result["world"][0]["position"] == [6.0, 0.0, 2.0], "Disk save must round-trip furniture using portable vector arrays.")
	_check(loaded.get_current_action()["target_position"] == Vector3(2, 0, 1) and loaded.character["hair_color"] == 2, "Disk load must reconstruct targets and preserve appearance fields.")
	if existed:
		var file: FileAccess = FileAccess.open(Simulation.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Simulation.SAVE_PATH))
	sim.free()
	loaded.free()
