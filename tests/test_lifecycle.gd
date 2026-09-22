extends SceneTree

var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func advance_minutes(sim: LifeSim, amount: float) -> void:
	while amount > 0.0:
		var step: float = minf(amount,60.0*LifeSim.GAME_MINUTES_PER_SECOND)
		sim.tick(step/LifeSim.GAME_MINUTES_PER_SECOND)
		amount -= step

func _initialize() -> void:
	var sim := LifeSim.new()
	sim.new_household({"age_stage":"teen"})
	sim.autonomy = false
	check(sim.character.life_stage == "minor", "Teen eligibility derives from their age.")
	check(not sim.queue_action("job") and not sim.choose_career("technology"), "Teen cannot join or work a full-time adult career.")
	check(not sim.get_action_availability("flirt", "maya").available, "Adult/minor romance stays unavailable.")
	sim.lifecycle.progress = .5
	sim.set_aging("long", true)
	check(sim.lifecycle.progress == .5 and LifeLifecycle.description("teen", sim.lifecycle).contains("42 days"), "Changing pace preserves fractional age.")
	sim.set_speed(0);sim.tick(60)
	check(sim.lifecycle.progress == .5, "Paused simulation does not age anyone.")
	sim.set_speed(1);sim.set_aging("normal", false);advance_minutes(sim,360.0)
	check(sim.lifecycle.progress == .5, "Automatic birthdays can be disabled independently of the clock.")
	sim.set_aging("short", true)
	sim.lifecycle.progress = 1.0 - 1.0 / (10.5 * 1440)
	sim._step(1)
	check(sim.character.age_stage == "young_adult" and sim.character.life_stage == "adult", "Crossing an age boundary grants adult eligibility.")
	check(sim.lifecycle.history.size() == 1 and sim.lifecycle.progress == 0, "Automatic birthday records one transition and resets stage progress.")
	# The office asks for Logic 3, so the skill is earned before the door opens.
	sim.skills.logic.level = 3
	check(sim.choose_career("technology"), "Young adulthood unlocks joining an actual adult career.")
	check(sim.career.schedule.first_day==sim.day+1 and not sim.get_action_availability("job").available, "Adulthood after noon schedules its first available workday tomorrow.")
	var retained: Dictionary = {"skills":sim.skills.duplicate(true),"relationships":sim.relationships.duplicate(true),"funds":sim.funds}
	check(sim.celebrate_birthday() and sim.character.age_stage == "adult", "A chosen birthday advances a single stage.")
	check(sim.skills == retained.skills and sim.relationships == retained.relationships and sim.funds == retained.funds, "Birthdays preserve learned skills, connections and wallet.")
	var saved: Dictionary = sim.get_state()
	var resumed := LifeSim.new()
	check(resumed.restore_state(JSON.parse_string(JSON.stringify(saved))).ok, "Age progress, settings and history survive actual JSON round trip.")
	check(resumed.lifecycle == sim.lifecycle and resumed.character.age_stage == "adult", "Restored lifecycle matches the saved one.")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.lifecycle.progress = NAN
	check(not resumed.restore_state(invalid).ok and resumed.character.age_stage == "adult", "Reject nonfinite age progress before mutating live state.")
	invalid = saved.duplicate(true); invalid.character.life_stage = "minor"
	check(not resumed.restore_state(invalid).ok, "Reject mismatched visual age and social eligibility.")
	invalid = saved.duplicate(true); invalid.lifecycle.history[0].to = "elder"
	check(not resumed.restore_state(invalid).ok, "Reject skipped birthday stages.")
	invalid = saved.duplicate(true); invalid.lifecycle.history[0].day = sim.day + 1
	check(not resumed.restore_state(invalid).ok, "Reject birthdays in the future.")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("lifecycle"); legacy.erase("education"); legacy.character.erase("age_stage")
	check(resumed.restore_state(legacy).ok and resumed.character.age_stage == "young_adult", "Existing adult saves migrate without losing play state.")
	legacy.character.life_stage = "minor"
	check(resumed.restore_state(legacy).ok and resumed.character.age_stage == "teen" and resumed.character.life_stage == "minor", "Legacy minor saves stay minors.")
	sim.celebrate_birthday()
	check(sim.character.age_stage == "elder" and not sim.celebrate_birthday(), "Elder has no repeated or wrapping birthday.")
	check(str(sim.character.hair_color) in preload("res://scripts/character_identity.gd").ELDER_HAIR_COLORS,
		"Becoming an elder greys the hair so the stage is visible (%s)." % str(sim.character.get("hair_color", "")))
	check(not sim.get_action_availability("birthday").available, "No birthday action is offered beyond the final supported stage.")
	sim.new_household({"age_stage":"child"})
	check(not sim.queue_action("cook") and sim.get_action_availability("snack").available, "Child can get food without adult stove interactions.")
	var household := LifeHousehold.new();root.add_child(household)
	household.new_household([{"name":"Ari", "age_stage":"teen"},{"name":"Bea","age_stage":"adult"}])
	var teen: LifeSim = household.members[0].sim
	teen.celebrate_birthday()
	check(household.members[1].sim.relationships.player.life_stage == "adult", "Birthday updates reciprocal household age context.")
	household.set_aging("long", false)
	check(not teen.lifecycle.auto_age and household.members[1].sim.lifecycle.lifespan == "long", "Household pace applies to every member.")
	var restored := LifeHousehold.new();root.add_child(restored)
	check(restored.restore_state(JSON.parse_string(JSON.stringify(household.get_state()))).ok, "Multi-member aging household survives save/restart validation.")
	var person: LifeSim = household.members[1].sim
	person.relationships.player.family_role = "siblings"
	check(person.relationship_order()[0] == "player", "Family remains visible ahead of unrelated acquaintances.")
	var ordering: Array = person.relationship_order()
	var reordered: Dictionary = {};var reversed: Array = person.relationships.keys();reversed.reverse()
	for id: String in reversed: reordered[id] = person.relationships[id]
	person.relationships = reordered
	check(ordering == person.relationship_order(), "Relationship order survives dictionary/save ordering changes.")
	sim.free();resumed.free();household.free();restored.free()
	print("Lifecycle: %d assertions, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
