extends SceneTree

const WantsManager = preload("res://scripts/wants_manager.gd")

var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	print("--- Starting Wants and Fears Test Suite ---")
	var sim := LifeSim.new()
	root.add_child(sim)
	
	# 1. Initialization
	sim.new_household({
		"name": "Jordan Rivers",
		"traits": ["Creative"],
		"age_stage": "young_adult",
		"life_stage": "adult",
		"wants_and_fears": true
	})
	
	var initial_whims: Array = sim.get_whims()
	check(initial_whims.size() == 3, "Sim initializes with exactly 3 active whim slots.")
	check(initial_whims[0].type == "need", "Slot 0 is a need-based whim.")
	check(initial_whims[1].type == "trait", "Slot 1 is a trait-based whim.")
	check(initial_whims[1].trait == "Creative", "Creative sim receives Creative trait whim (paint).")
	check(initial_whims[2].type == "emotion", "Slot 2 is an emotion-based whim.")
	check(sim.get_fears().is_empty(), "Fresh sim starts with no psychological fears.")
	
	# 2. Pinning & Dismissal
	check(sim.pin_whim(1, true), "Successfully pinned trait whim.")
	check(sim.get_whims()[1].pinned == true, "Trait whim state reports pinned = true.")
	check(not sim.dismiss_whim(1), "Pinned whim cannot be dismissed.")
	check(sim.get_whims()[1].pinned == true, "Whim remains pinned after attempted dismissal.")
	
	check(sim.pin_whim(1, false), "Successfully unpinned trait whim.")
	check(sim.get_whims()[1].pinned == false, "Trait whim state reports pinned = false.")
	
	# Test dismissal on slot 0 (need whim)
	var old_whim_label: String = str(sim.get_whims()[0].label)
	# Force need change to test alternative whim pick
	sim.needs["energy"] = 10.0
	sim.needs["hunger"] = 90.0
	check(sim.dismiss_whim(0), "Unpinned whim dismisses cleanly.")
	var new_whim: Dictionary = sim.get_whims()[0]
	check(new_whim.id == "restful_sleep", "Dismissal dynamically recalculates based on lowest need (energy).")
	
	# 3. Fulfilling Whim
	var starting_sat: int = sim.satisfaction
	var paint_whim_reward: int = int(sim.get_whims()[1].reward)
	check(paint_whim_reward > 0, "Paint whim has positive satisfaction reward.")
	
	# Start and complete 'paint' action
	check(sim.queue_action("paint"), "Sim queues paint action.")
	sim.begin_current_action()
	var cur_act: Dictionary = sim.action_queue[0]
	cur_act.elapsed = cur_act.duration
	sim.tick(0.1) # Finishes action
	
	check(sim.satisfaction == starting_sat + paint_whim_reward, "Fulfilling whim awards exact satisfaction points.")
	check(sim.moodlets.any(func(m): return str(m.get("label", "")) == "Fulfilled Desire"), "Fulfilling whim grants 'Fulfilled Desire' moodlet.")
	
	# 4. Psychological Fears & Conquering
	check(sim.trigger_fear("fear_of_failure"), "Triggering fear of failure succeeds.")
	check(sim.get_fears().has("fear_of_failure"), "Fear of failure is recorded in active fears.")
	check(not sim.trigger_fear("fear_of_failure"), "Duplicate fear cannot be added twice.")
	
	# Conquer fear through work/shift completion
	var sat_before_conquer: int = sim.satisfaction
	# Trigger a cure action: "paint" is in cure_tags for fear_of_failure!
	check(sim.queue_action("paint"), "Sim queues paint to confront fear.")
	sim.begin_current_action()
	var fear_act: Dictionary = sim.action_queue[0]
	fear_act.elapsed = fear_act.duration
	sim.tick(0.1)
	
	check(not sim.get_fears().has("fear_of_failure"), "Conquering fear removes it from active fears list.")
	check(sim.satisfaction >= sat_before_conquer + 150, "Conquering fear awards +150 satisfaction points.")
	check(sim.moodlets.any(func(m): return str(m.get("label", "")) == "Conquered Fear"), "Conquering fear awards 'Conquered Fear' Confident moodlet.")
	
	# 5. Save & Restore Roundtrip
	sim.trigger_fear("fear_of_exhaustion")
	sim.pin_whim(0, true)
	var saved_state: Dictionary = sim.get_state()
	saved_state["world"] = []
	check(saved_state.has("whims"), "State dictionary includes whims system data.")
	
	var json_str: String = JSON.stringify(saved_state)
	var restored_dict: Dictionary = JSON.parse_string(json_str)
	
	var restored_sim := LifeSim.new()
	root.add_child(restored_sim)
	var restore_res: Dictionary = restored_sim.restore_state(restored_dict)
	if not bool(restore_res.get("ok", false)):
		push_error("restore error: " + str(restore_res.get("error", "unknown")))
	check(restore_res.get("ok", false), "Sim with active whims and fears restores successfully.")
	check(restored_sim.get_fears().has("fear_of_exhaustion"), "Active fears survive JSON round trip.")
	check(restored_sim.get_whims().size() == 3, "Restored sim retains 3 whim slots.")
	check(restored_sim.get_whims()[0].pinned == true, "Pinned whim status survives JSON round trip.")
	check(WantsManager.validate_save(restored_dict.whims), "JSON numeric fields remain valid wants and fears data.")
	check(WantsManager.validate_save(WantsManager.fresh_state({}, "Fine", {}, false)), "A disabled system with empty slots remains valid.")

	# Invalid optional data must be refused before any live state is replaced.
	# In particular a valid-looking array can hide a non-dictionary whim, and
	# missing stats used to crash the next completed action after loading.
	var valid_whims: Dictionary = restored_dict.whims
	_check_invalid_whims(restored_sim, restored_dict, [], "non-dictionary wants state")
	var invalid: Dictionary = valid_whims.duplicate(true)
	invalid.whims[0] = "broken"
	_check_invalid_whims(restored_sim, restored_dict, invalid, "non-dictionary whim")
	invalid = valid_whims.duplicate(true)
	invalid.whims.append(valid_whims.whims[0].duplicate(true))
	_check_invalid_whims(restored_sim, restored_dict, invalid, "extra whim slot")
	invalid = valid_whims.duplicate(true)
	invalid.whims[0] = valid_whims.whims[1].duplicate(true)
	_check_invalid_whims(restored_sim, restored_dict, invalid, "wrong slot category")
	invalid = valid_whims.duplicate(true)
	invalid.whims[0].id = "unknown_desire"
	_check_invalid_whims(restored_sim, restored_dict, invalid, "unknown whim identity")
	invalid = valid_whims.duplicate(true)
	invalid.whims[0].action_tags = "sleep"
	_check_invalid_whims(restored_sim, restored_dict, invalid, "invalid action tags")
	invalid = valid_whims.duplicate(true)
	invalid.whims[0].action_tags[0] = 12
	_check_invalid_whims(restored_sim, restored_dict, invalid, "non-string action tag")
	invalid = valid_whims.duplicate(true)
	invalid.whims[0].description = []
	_check_invalid_whims(restored_sim, restored_dict, invalid, "non-string description")
	invalid = valid_whims.duplicate(true)
	invalid.whims[0].reward = 999999
	_check_invalid_whims(restored_sim, restored_dict, invalid, "invented whim reward")
	invalid = valid_whims.duplicate(true)
	invalid.whims[0].pinned = "yes"
	_check_invalid_whims(restored_sim, restored_dict, invalid, "non-boolean pin")
	invalid = valid_whims.duplicate(true)
	invalid.enabled = "yes"
	_check_invalid_whims(restored_sim, restored_dict, invalid, "non-boolean enable flag")
	invalid = valid_whims.duplicate(true)
	invalid.fears = ["unknown_fear"]
	_check_invalid_whims(restored_sim, restored_dict, invalid, "unknown fear")
	invalid = valid_whims.duplicate(true)
	invalid.fears = ["fear_of_loss", "fear_of_loss"]
	_check_invalid_whims(restored_sim, restored_dict, invalid, "duplicate fear")
	invalid = valid_whims.duplicate(true)
	invalid.erase("stats")
	_check_invalid_whims(restored_sim, restored_dict, invalid, "missing counters")
	invalid = valid_whims.duplicate(true)
	invalid.stats.fulfilled = -1
	_check_invalid_whims(restored_sim, restored_dict, invalid, "negative counter")
	invalid = valid_whims.duplicate(true)
	invalid.stats.conquered_fears = 1.5
	_check_invalid_whims(restored_sim, restored_dict, invalid, "fractional counter")
	invalid = valid_whims.duplicate(true)
	invalid.stats.total_satisfaction = INF
	_check_invalid_whims(restored_sim, restored_dict, invalid, "non-finite counter")
	var legacy: Dictionary = restored_dict.duplicate(true)
	legacy.erase("whims")
	check(restored_sim.restore_state(legacy).get("ok", false), "Older saves without wants data still load.")
	check(WantsManager.validate_save(restored_sim.whims), "Older saves receive a complete valid wants state.")
	
	# The Wishes panel runs while the simulation keeps ticking, and its Pin and
	# dismiss handlers act on a whim. Bound to a slot index they acted on whichever
	# whim had since taken that slot, so a press could suppress a desire the player
	# never saw. They are bound to the whim's own identity now.
	sim.needs.fun = 5.0
	sim.needs.hunger = 90.0
	sim.needs.energy = 90.0
	sim.needs.hygiene = 90.0
	sim.needs.social = 90.0
	sim.whims = WantsManager.fresh_state(sim.character, str(sim.get_mood().label), sim.needs, true)
	var shown_id: String = str(sim.get_whims()[0].get("id", ""))
	check(shown_id == "have_fun", "A bored Lifelet's first whim is the fun one (" + shown_id + ").")
	# The player solves Fun and goes hungry: the slot refreshes behind the panel.
	var tags: Array = sim.get_whims()[0].get("action_tags", [])
	WantsManager.evaluate_action(sim.whims, str(tags[0]) if not tags.is_empty() else "")
	sim.needs.fun = 95.0
	sim.needs.hunger = 5.0
	WantsManager.refresh_whims(sim.whims, sim.character, sim.needs, str(sim.get_mood().label))
	var replaced_id: String = str(sim.get_whims()[0].get("id", ""))
	check(replaced_id != shown_id, "The slot really refreshed to a different whim (" + replaced_id + ").")
	sim.pin_whim_id(shown_id, true)
	var pinned_now: Array[String] = []
	for whim: Dictionary in sim.get_whims():
		if bool(whim.get("pinned", false)):
			pinned_now.append(str(whim.get("id", "")))
	check(not pinned_now.has(replaced_id), "Acting on a card never pins the whim that replaced it (" + str(pinned_now) + ").")
	sim.pin_whim_id(replaced_id, true)
	check(bool(sim.get_whims()[0].get("pinned", false)) and str(sim.get_whims()[0].get("id", "")) == replaced_id, "Acting on a card still pins the whim that card names.")
	sim.pin_whim_id(replaced_id, false)
	sim.free()
	restored_sim.free()
	print("Wants and Fears: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check_invalid_whims(sim: LifeSim, saved: Dictionary, value: Variant, detail: String) -> void:
	check(not WantsManager.validate_save(value), "Reject " + detail + " in wants validation.")
	var candidate: Dictionary = saved.duplicate(true)
	candidate.whims = value
	var previous: String = JSON.stringify(sim.get_state())
	var result: Dictionary = sim.restore_state(candidate)
	check(not bool(result.get("ok", false)), "Refuse a save with " + detail + ".")
	check(JSON.stringify(sim.get_state()) == previous, "Refusing " + detail + " preserves the live state.")

func _initialize() -> void:
	call_deferred("run")
