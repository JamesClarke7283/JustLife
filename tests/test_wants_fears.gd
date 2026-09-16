extends SceneTree

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
	
	sim.free()
	restored_sim.free()
	print("Wants and Fears: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	call_deferred("run")
