extends SceneTree
## The swim's consequences at the simulation level: who may use the water, the
## swimwear that goes on for it, the wetness that follows, how a towel and a seat
## change it, and that all of it survives a save.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_swim_wetness.gd

var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_access()
	_swimwear_and_drips()
	_towel_and_seat()
	_save_round_trip()
	print("SWIM_WETNESS %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _sim(stage: String = "adult") -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	sim.new_household({"name": "Sam Vale", "age_stage": stage, "life_stage": LifeLifecycle.eligibility(stage)})
	sim.autonomy = false
	sim.funds = 5000
	return sim


func _targets(sim: LifeSim) -> void:
	sim.register_targets([
		{"id": "pool_1", "kind": "pool", "position": Vector3(0, .16, 0)},
		{"id": "tub_1", "kind": "hot_tub", "position": Vector3(4, .16, 0)},
		{"id": "ring_1", "kind": "pool_ring", "position": Vector3(1, .16, 2)},
		{"id": "noodle_1", "kind": "pool_noodle", "position": Vector3(2, .16, 2)},
		{"id": "rack_1", "kind": "towel_rack", "position": Vector3(-2, .16, 0), "towels": 2},
		{"id": "rack_empty", "kind": "towel_rack", "position": Vector3(-3, .16, 0), "towels": 0},
		{"id": "towel_1", "kind": "beach_towel", "position": Vector3(-2, .16, 2)},
		{"id": "sofa_1", "kind": "sofa", "position": Vector3(6, .16, 6)},
		{"id": "swing_1", "kind": "outdoor_swing", "position": Vector3(6, .16, -6)},
	])


func _run_front(sim: LifeSim, minutes: int) -> void:
	sim.begin_current_action()
	for i: int in range(minutes):
		sim.tick(1.0)


## Children, teens, young adults and adults all use every pool and the hot tub.
func _access() -> void:
	for kind: String in ["pool", "hot_tub", "pool_ring", "pool_noodle", "pool_slide", "pool_ladder", "pool_light"]:
		for stage: String in ["child", "teen", "young_adult", "adult"]:
			check(LifeOutdoorActs.act_error(kind, stage, false, true, false).is_empty(), "A %s may use the %s (%s)." % [stage, kind, LifeOutdoorActs.act_error(kind, stage, false, true, false)])
		check(not LifeOutdoorActs.act_error(kind, "baby", false, true, false).is_empty(), "A baby is still kept out of the %s." % kind)
	for stage: String in ["child", "teen", "young_adult", "adult"]:
		var sim: LifeSim = _sim(stage)
		_targets(sim)
		for target: String in ["pool_1", "tub_1"]:
			var actions: Array = sim.get_actions_for("pool" if target == "pool_1" else "hot_tub", target)
			var offered: bool = false
			for action: Dictionary in actions:
				if str(action.id) == LifeOutdoorActs.ACTION_ID and bool(action.available): offered = true
			check(offered, "%s is offered the swim at %s through the real menu." % [stage.capitalize(), target])
		sim.free()


func _swimwear_and_drips() -> void:
	var sim: LifeSim = _sim()
	_targets(sim)
	check(LifeCharacterIdentity.OUTFIT_CATEGORIES.has("swim"), "Swim is a wardrobe category.")
	check(str(sim.character.outfit_category) == "everyday", "The Lifelet starts in everyday clothes.")
	# Deciding to swim puts on swimwear straight away, before the walk to the water.
	check(sim.queue_action(LifeOutdoorActs.ACTION_ID, "pool_1", Vector3(0, .16, 2)), "A swim can be queued.")
	check(str(sim.character.outfit_category) == "swim", "Queuing a swim puts on swimwear.")
	check(sim.auto_swimwear, "Swimwear put on for the water is remembered as automatic.")
	_run_front(sim, 3)
	check(sim.wetness >= 1.0, "In the water the Lifelet is soaked (%.2f)." % sim.wetness)
	check(str(sim.character.outfit_category) == "swim", "The Lifelet stays in swimwear while swimming.")
	var guard: int = 0
	while not sim.action_queue.is_empty() and str(sim.get_current_action().id) == LifeOutdoorActs.ACTION_ID and guard < 200:
		sim.tick(1.0)
		guard += 1
	check(sim.action_queue.is_empty() or str(sim.get_current_action().id) != LifeOutdoorActs.ACTION_ID, "The swim finishes.")
	check(sim.wetness > 0.9, "Straight out of the water the Lifelet is soaking (%.2f)." % sim.wetness)
	var followed: bool = false
	for queued: Dictionary in sim.action_queue:
		if str(queued.id) == LifeWetness.DRY_OFF_ID: followed = true
	check(followed, "Coming out, a wet Lifelet heads for a towel.")
	# Dripping is short: air drying gets under the drip line in about twenty minutes.
	sim.action_queue.clear()
	sim.wetness = 1.0
	for i: int in range(15): sim.tick(1.0)
	check(LifeWetness.drips(sim.wetness), "Still dripping after fifteen minutes (%.2f)." % sim.wetness)
	for i: int in range(10): sim.tick(1.0)
	check(not LifeWetness.drips(sim.wetness) and sim.wetness > 0.0, "Damp but no longer dripping after twenty-five (%.2f)." % sim.wetness)
	for i: int in range(40): sim.tick(1.0)
	check(sim.wetness == 0.0, "Fully dry in the air within the hour.")
	check(str(sim.character.outfit_category) == "everyday", "Dry, the Lifelet changes back out of the swimwear.")
	# Swimwear the player chose stays on.
	var chosen: LifeSim = _sim()
	_targets(chosen)
	LifeCharacterIdentity.apply_category(chosen.character, "swim")
	chosen.wetness = 0.3
	for i: int in range(40): chosen.tick(1.0)
	check(str(chosen.character.outfit_category) == "swim", "Swimwear the player chose is left on when dry.")
	chosen.free()
	# The hot tub is a swim too.
	var soaker: LifeSim = _sim()
	_targets(soaker)
	soaker.queue_action(LifeOutdoorActs.ACTION_ID, "tub_1", Vector3(4, .16, 1))
	check(str(soaker.character.outfit_category) == "swim", "A soak in the hot tub also puts on swimwear.")
	soaker.free()
	sim.free()


func _towel_and_seat() -> void:
	var sim: LifeSim = _sim()
	_targets(sim)
	sim.wetness = 1.0
	# A dry-off asks for a real towel.
	check(not bool(sim.get_action_availability(LifeWetness.DRY_OFF_ID, "rack_empty").available), "An empty rack gives no towel.")
	check(bool(sim.get_action_availability(LifeWetness.DRY_OFF_ID, "rack_1").available), "A stocked rack does.")
	check(bool(sim.get_action_availability(LifeWetness.DRY_OFF_ID, "towel_1").available), "A loose beach towel does.")
	check(not bool(sim.get_action_availability(LifeWetness.DRY_OFF_ID, "sofa_1").available), "A sofa is not a towel.")
	var dry: LifeSim = _sim()
	_targets(dry)
	check(not bool(dry.get_action_availability(LifeWetness.DRY_OFF_ID, "rack_1").available), "A dry Lifelet has nothing to dry off.")
	dry.free()
	# Wrapped in a towel, drying takes minutes, not most of an hour.
	sim.towel = {"source": "rack_1", "kind": "towel_rack", "color": "2f8fb3"}
	for i: int in range(9): sim.tick(1.0)
	check(sim.wetness == 0.0, "Wrapped in a towel the Lifelet is dry in eight or nine minutes.")
	check(sim.towel.is_empty() and sim.towel_returns.size() == 1, "The towel is handed back when the Lifelet is dry.")
	check(str(sim.towel_returns[0].source) == "rack_1", "It goes back to the rack it came from.")
	# Sitting damp on a sofa leaves a puddle; the same seat after a towel does not.
	var damp: LifeSim = _sim()
	_targets(damp)
	damp.wetness = 1.0
	damp.queue_action("relax", "sofa_1", Vector3(6, .16, 5))
	_run_front(damp, 9)
	check(damp.wet_seat_request == "sofa_1", "Sitting damp on the sofa for too long soaks it (%s)." % damp.wet_seat_request)
	damp.free()
	var swing: LifeSim = _sim()
	_targets(swing)
	swing.wetness = 1.0
	swing.queue_action(LifeOutdoorActs.ACTION_ID, "swing_1", Vector3(6, .16, -5))
	_run_front(swing, 9)
	check(swing.wet_seat_request == "swing_1", "The garden swing is a soft seat as well (%s)." % swing.wet_seat_request)
	swing.free()
	var towelled: LifeSim = _sim()
	_targets(towelled)
	towelled.wetness = 0.5
	towelled.towel = {"source": "rack_1", "kind": "towel_rack", "color": "2f8fb3"}
	check(bool(towelled.get_action_availability(LifeWetness.DRY_SIT_ID, "sofa_1").available), "A towelled Lifelet can sit and dry off on a sofa.")
	towelled.queue_action(LifeWetness.DRY_SIT_ID, "sofa_1", Vector3(6, .16, 5))
	_run_front(towelled, 8)
	check(towelled.wet_seat_request.is_empty(), "In a towel the seat stays dry: no puddle.")
	check(towelled.wetness == 0.0 and towelled.towel.is_empty(), "Sitting in the towel finishes the job and returns it.")
	towelled.free()
	# The seat options only appear while there is something to dry.
	var offered_dry: bool = false
	for action: Dictionary in _sim().get_actions_for("sofa", "sofa_1"):
		if str(action.id) == LifeWetness.DRY_SIT_ID: offered_dry = true
	check(not offered_dry, "A dry Lifelet is not offered 'Sit and dry off'.")
	sim.free()


func _save_round_trip() -> void:
	var sim: LifeSim = _sim()
	_targets(sim)
	sim.wetness = 0.62
	sim.towel = {"source": "rack_1", "kind": "towel_rack", "color": "2f8fb3"}
	sim.queue_action(LifeOutdoorActs.ACTION_ID, "pool_1", Vector3(0, .16, 2))
	var state: Dictionary = sim.get_state()
	check(absf(float(state.wetness) - .62) < .001 and state.towel is Dictionary and str(state.towel.source) == "rack_1", "Wetness and the towel are in the saved state.")
	var loaded: LifeSim = LifeSim.new()
	var result: Dictionary = loaded.restore_state(state)
	check(bool(result.ok), "The saved state restores (%s)." % str(result.get("error", "")))
	check(absf(loaded.wetness - .62) < .001 and str(loaded.towel.get("source", "")) == "rack_1", "Wetness and the towel come back.")
	var swim: Dictionary = loaded.get_current_action() if not loaded.action_queue.is_empty() else {}
	check(not swim.is_empty() and float(swim.changes.get("fun", 0)) > 30.0 and str(swim.label) == "Go for a swim", "A saved swim keeps the effects of the pool it was queued at (%s)." % str(swim.get("label", "")))
	# A corrupt value is refused rather than loaded.
	var bad: Dictionary = state.duplicate(true)
	bad["wetness"] = 4.0
	check(not bool(LifeSim.new().restore_state(bad).ok), "An impossible wetness is refused.")
	bad = state.duplicate(true)
	bad["towel"] = {"source": 3, "kind": "towel_rack", "color": "2f8fb3"}
	check(not bool(LifeSim.new().restore_state(bad).ok), "A malformed towel is refused.")
	# An older save has neither and loads dry.
	var old: Dictionary = state.duplicate(true)
	old.erase("wetness")
	old.erase("towel")
	var older: LifeSim = LifeSim.new()
	check(bool(older.restore_state(old).ok) and older.wetness == 0.0 and older.towel.is_empty(), "A save from before wetness loads dry with no towel.")
	sim.free()
	loaded.free()
	older.free()
