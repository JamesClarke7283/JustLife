extends SceneTree

const Simulation = preload("res://scripts/life_sim.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_four_day_story_and_chapters()
	_test_pending_events_and_affordability()
	_test_practice_at_skill_cap()
	_test_saved_day_sets_and_reentrant_choices()
	_test_later_choice_requirements()
	_test_new_story_kinds()
	_test_legacy_and_malformed_saves()
	print("Story progression: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func make_sim(aspiration: String = "Maker") -> LifeSim:
	var sim: LifeSim = Simulation.new()
	sim.new_household({"name":"Morgan Vale", "aspiration":aspiration, "traits":[]})
	sim.autonomy = false
	return sim


func advance(sim: LifeSim, game_minutes: float) -> void:
	var remaining: float = game_minutes
	while remaining > .0001:
		var step: float = minf(remaining, minf(180.0, 60.0*Simulation.GAME_MINUTES_PER_SECOND))
		sim.tick(step / Simulation.GAME_MINUTES_PER_SECOND)
		remaining -= step


func next_morning(sim: LifeSim) -> void:
	advance(sim, 1440.0 - sim.minutes + 480.0)


func complete(sim: LifeSim, action_id: String, target_id: String = "") -> void:
	check(sim.queue_action(action_id, target_id), "Activity %s must be available in the sustained playthrough." % action_id)
	sim.begin_current_action()
	advance(sim, float(sim.get_current_action().duration))


func xp_total(sim: LifeSim, skill_name: String) -> float:
	var level: int = int(sim.skills[skill_name].level)
	return float(level * (level - 1) * 25) + float(sim.skills[skill_name].xp)


func _test_four_day_story_and_chapters() -> void:
	var sim: LifeSim = make_sim()
	check(sim.get_story_events().is_empty(), "Move-in day leaves room for the first household routine.")
	complete(sim, "cook")
	for i: int in range(3):
		complete(sim, "paint")
	complete(sim, "friendly", "maya")
	complete(sim, "friendly", "maya")
	check(sim.satisfaction == 320, "Initial Maker rewards must stay exactly 60 + 80 + 180.")
	check(sim.aspiration_history.size() == 1 and sim.aspiration_history[0].reward == 320, "The completed first chapter must retain its wants and total rewards.")
	check(sim.aspiration_next_day == 2 and sim.wants.size() == 3, "A completed chapter announces tomorrow's goals without expanding the UI list.")
	var satisfied: int = sim.satisfaction
	advance(sim, 2)
	check(sim.satisfaction == satisfied, "Archived rewards must never pay a second time.")
	next_morning(sim)
	check(sim.day == 2 and sim.aspiration_stage == 2 and sim.aspiration_next_day == 0, "A fresh chapter must open the following morning.")
	check(sim.wants.size() == 3 and not sim.wants[0].complete, "Recurring chapters must contain fresh, uncompleted wants.")
	var events: Array = sim.get_story_events()
	check(events.size() == 1 and events[0].kind == "neighbor_invitation", "Day two must offer an original neighbor invitation.")
	check(events[0].choices.size() == 3 and events[0].choices[0].effects.contains("Pay ℒ24"), "Choices must explain concrete costs before selection.")
	events[0].choices[0].label = "tampered label"
	check(sim.get_story_events()[0].choices[0].label != "tampered label", "The UI must receive independent choice data.")
	sim.needs.energy = 60.0
	sim.needs.social = 40.0
	var money: int = sim.funds
	var friendship: float = float(sim.relationships.maya.friendship)
	var cooking_xp: float = xp_total(sim, "cooking")
	var clock: float = sim.minutes
	check(sim.choose_story_event("story_day_2", "bring_dish"), "An affordable invitation choice must apply.")
	check(sim.funds == money - 24 and sim.needs.energy == 52.0 and sim.needs.social == 64.0, "The dish choice must apply its advertised money and need tradeoffs.")
	check(is_equal_approx(float(sim.relationships.maya.friendship), friendship + 14.0) and is_equal_approx(xp_total(sim, "cooking"), cooking_xp + 20.0), "The invitation must build the specified friendship and cooking experience.")
	check(sim.minutes == clock and sim.action_queue.is_empty(), "A story choice must not secretly advance the clock or replace the action queue.")
	check(not sim.choose_story_event("story_day_2", "bring_dish") and sim.funds == money - 24, "A resolved story cannot be replayed for duplicate rewards.")
	complete(sim, "paint")
	complete(sim, "paint")
	complete(sim, "cook")
	complete(sim, "read")
	complete(sim, "friendly", "leo")
	complete(sim, "joke", "maya")
	check(sim.wants[0].complete and sim.wants[1].complete and sim.wants[2].progress == 1.0, "Creative work and variety count, while repeated chats on one day count only one social day.")
	next_morning(sim)
	check(sim.day == 3 and sim.get_story_events()[0].kind == "career_opportunity", "Day three must offer a different, career-focused story.")
	money = sim.funds
	# Mentoring builds the skill the Lifelet's own job is plied with, so both the
	# baseline and the assertion read that job's skill rather than assuming one.
	var job_skill: String = str(LifeCareers.job(str(sim.career.get("track", ""))).get("skill", ""))
	var career_xp: float = xp_total(sim, job_skill)
	check(sim.choose_story_event("story_day_3", "mentoring"), "Career mentoring must be selectable.")
	check(sim.funds == money - 30 and is_equal_approx(xp_total(sim, job_skill), career_xp + 65.0) and sim.career.performance == 6.0, "Mentoring must exchange funds for the offered career skill and performance.")
	complete(sim, "deep_talk", "maya")
	check(sim.aspiration_history.size() == 2 and sim.aspiration_next_day == 4, "Completing a second real chapter must archive it and schedule another.")
	check(sim.satisfaction == 720, "Only the three stated recurring want rewards should be paid.")
	next_morning(sim)
	check(sim.day == 4 and sim.aspiration_stage == 3 and sim.wants.size() <= 4, "Progression must remain active after three full game days.")
	check(sim.get_story_events()[0].kind == "hobby_exhibition", "Day four must offer the hobby exhibition.")
	var snapshot: Dictionary = sim.get_state()
	var loaded: LifeSim = make_sim("Balanced")
	check(loaded.restore_state(snapshot).ok, "Multi-day story and chapter state must validate.")
	check(loaded.get_story_events() == sim.get_story_events() and loaded.story_history == sim.story_history and loaded.aspiration_history == sim.aspiration_history, "Pending events, decisions and completed chapters must survive restore exactly.")
	check(loaded.choose_story_event("story_day_4", "show_work"), "A pending saved exhibition must remain actionable after restore.")
	check(loaded.story_history.size() == 3 and loaded.story_history[0].offered_day == 4, "Choices must retain their offered and chosen calendar days.")
	var existed: bool = FileAccess.file_exists(Simulation.SAVE_PATH)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(Simulation.SAVE_PATH) if existed else PackedByteArray()
	check(loaded.save_game(), "Story history must save through the real JSON writer.")
	check(sim.load_game().ok and sim.story_history == loaded.story_history and sim.aspiration_stage == 3, "The real disk round-trip must preserve three days of choices and recurring chapters.")
	if existed:
		var file: FileAccess = FileAccess.open(Simulation.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Simulation.SAVE_PATH))
	sim.free()
	loaded.free()


func _test_pending_events_and_affordability() -> void:
	var sim: LifeSim = make_sim()
	for i: int in range(6):
		next_morning(sim)
	check(sim.day == 7 and sim.story_events.size() == 3, "Unanswered events must stay bounded at three.")
	check(sim.story_events[0].day == 2, "An unanswered invitation must remain available instead of expiring.")
	check(sim.funds == 2500 and not sim.pending_bill.is_empty(), "Ignoring stories must charge no penalty: bills wait to be paid rather than being taken silently.")
	sim.funds = 0
	check(not sim.get_story_events()[0].choices[0].available, "The UI must see that a paid choice is unavailable when broke.")
	var before: Dictionary = sim.get_state()
	check(not sim.choose_story_event("story_day_2", "bring_dish") and sim.get_state() == before, "An unaffordable choice must leave all simulation state untouched.")
	check(not sim.choose_story_event("story_day_2", "invented") and sim.get_state() == before, "An unknown choice must not mutate or consume the event.")
	check(sim.choose_story_event("story_day_2", "keep_day_free"), "A no-cost opt-out must always remain available.")
	check(sim.funds == 0 and sim.needs == before.needs and sim.skills == before.skills and sim.relationships == before.relationships, "Declining must not impose invisible stat penalties.")
	check(sim.story_history[0].offered_day == 2 and sim.story_history[0].day == 7, "Delayed choices must preserve their actual timeline.")
	next_morning(sim)
	check(sim.story_events.size() == 3 and sim.story_events.back().day == 8, "A freed pending slot must allow the next day's invitation.")
	sim.free()


func _test_practice_at_skill_cap() -> void:
	var sim: LifeSim = make_sim("Successful")
	sim.skills.logic.level = 3
	sim.choose_career("technology")
	sim.aspiration_stage = 2
	sim._create_recurring_wants()
	sim.skills.logic.level = 10
	sim.skills.logic.xp = 0.0
	complete(sim, "read")
	check(is_equal_approx(float(sim.wants[1].progress), 25.0) and sim.skills.logic.level == 10, "New chapters must remain completable after a skill reaches its cap.")
	check(sim.wants[2].progress == 1.0, "A completed reading session must count as one distinct recovery activity.")
	complete(sim, "read")
	check(sim.wants[2].progress == 1.0, "Repeating one activity must not satisfy a variety goal.")
	sim.free()


func _test_legacy_and_malformed_saves() -> void:
	var sim: LifeSim = make_sim()
	next_morning(sim)
	var state: Dictionary = sim.get_state()
	var legacy: Dictionary = state.duplicate(true)
	for key: String in ["aspiration_stage", "aspiration_next_day", "aspiration_history", "story_events", "story_history", "story_generated_day"]:
		legacy.erase(key)
	var loaded: LifeSim = make_sim()
	check(loaded.restore_state(legacy).ok and loaded.aspiration_stage == 1 and loaded.story_events.is_empty(), "Legacy saves must acquire safe empty story/chapter defaults.")
	var before: Dictionary = loaded.get_state()
	var broken: Dictionary = state.duplicate(true)
	broken.story_events[0].context.skill = "unknown"
	check(not loaded.restore_state(broken).ok and loaded.get_state() == before, "Malformed story context must be rejected before live state changes.")
	broken = state.duplicate(true)
	broken.story_events.append(broken.story_events[0].duplicate(true))
	check(not loaded.restore_state(broken).ok, "Duplicate pending events must be rejected.")
	broken = state.duplicate(true)
	broken.aspiration_stage = "bad"
	check(not loaded.restore_state(broken).ok, "Malformed chapter counters must be rejected.")
	broken = state.duplicate(true)
	broken.wants[0].metric = "variety"
	broken.wants[0].actions = null
	check(not loaded.restore_state(broken).ok, "Malformed nested recurring progress must be rejected safely.")
	sim.choose_story_event("story_day_2", "keep_day_free")
	broken = sim.get_state()
	broken.story_history[0].day = "bad"
	check(not loaded.restore_state(broken).ok, "Malformed story dates must be rejected safely.")
	sim.free()
	loaded.free()


func _test_saved_day_sets_and_reentrant_choices() -> void:
	var sim: LifeSim = make_sim()
	sim.day = 2
	sim.career.schedule = LifeCareerSchedule.fresh(sim.day) # Fresh calendar for this deliberately selected fixture day.
	sim.aspiration_stage = 2
	sim._create_recurring_wants()
	complete(sim, "friendly", "maya")
	var parser: JSON = JSON.new()
	parser.parse(JSON.stringify(sim.get_state()))
	var loaded: LifeSim = make_sim()
	check(loaded.restore_state(parser.data).ok, "A chapter with partially filled day sets must load from JSON.")
	complete(loaded, "joke", "leo")
	check(loaded.wants[2].progress == 1.0, "Resuming on the same day must not count a floating-point JSON date as a different social day.")
	sim._offer_daily_story()
	sim.skills.cooking.level = 1
	sim.skills.cooking.xp = 45.0
	var attempts: Array = []
	sim.notice.connect(func(_message: String) -> void: attempts.append(sim.choose_story_event("story_day_2", "bring_dish")))
	var money: int = sim.funds
	check(sim.choose_story_event("story_day_2", "bring_dish"), "A story choice that emits skill notifications must still complete.")
	check(not attempts.is_empty() and not attempts.has(true) and sim.funds == money - 24, "Signal listeners must not be able to replay a choice while its effects are being applied.")
	sim.free()
	loaded.free()


func _test_later_choice_requirements() -> void:
	var sim: LifeSim = make_sim()
	sim.day = 5
	sim._offer_daily_story()
	sim.needs.energy = 50.0
	sim.needs.hygiene = 50.0
	var money: int = sim.funds
	check(sim.choose_story_event("story_day_5", "set_up"), "The garden exchange offers a way to earn money without paying first.")
	check(sim.funds == money + 30 and sim.needs.energy == 38.0 and sim.needs.hygiene == 42.0, "Garden work must trade energy and hygiene for its stated payment.")
	sim.day = 6
	sim._offer_daily_story()
	# Teaching is gated on the skill the Lifelet's own job is plied with.
	var job_skill: String = str(LifeCareers.job(str(sim.career.get("track", ""))).get("skill", ""))
	var reason: String = str(sim.get_story_events()[0].choices[1].unavailable_reason)
	check(not sim.get_story_events()[0].choices[1].available and reason.contains("level 2") and reason.contains(job_skill.capitalize()), "Teaching must explain its actual skill requirement.")
	check(not sim.choose_story_event("story_day_6", "teach"), "An unmet skill requirement must prevent the teaching choice.")
	sim.skills[job_skill].level = 2
	check(sim.get_story_events()[0].choices[1].available and sim.choose_story_event("story_day_6", "teach"), "The pending teaching choice must unlock after skill improves.")
	sim.day = 7
	sim._offer_daily_story()
	sim.needs.energy = 25.0
	sim.needs.fun = 25.0
	money = sim.funds
	check(sim.choose_story_event("story_day_7", "quiet_reset") and sim.needs.energy == 43.0 and sim.needs.fun == 35.0 and sim.funds == money, "The community picnic includes a real no-cost restorative alternative.")
	sim.free()

func _test_new_story_kinds() -> void:
	var sim: LifeSim = make_sim()
	# Days 2-7 keep their kinds; the appended kinds land on days 8 and 9.
	sim.day = 2
	sim._offer_daily_story()
	check(sim.get_story_events()[0].kind == "neighbor_invitation", "Extending the rotation must not move day two's invitation.")
	sim.day = 8
	sim._offer_daily_story()
	var party: Dictionary = sim.get_story_events().back()
	check(str(party.kind) == "block_party", "Day eight must offer the block party.")
	check(party.choices.size() == 3 and party.title == "The lane closes for the evening", "The block party carries three labelled choices.")
	sim.needs.energy = 80.0
	sim.needs.social = 40.0
	sim.needs.fun = 40.0
	var money: int = sim.funds
	var cooking_xp: float = xp_total(sim, "cooking")
	var friendship: float = float(sim.relationships.priya.friendship)
	check(sim.choose_story_event("story_day_8", "bring_party_dish"), "The party dish must be selectable.")
	check(sim.funds == money - 20 and is_equal_approx(xp_total(sim, "cooking"), cooking_xp + 30.0) and is_equal_approx(float(sim.relationships.priya.friendship), friendship + 10.0), "The party dish must apply its cost, cooking XP and friendship exactly.")
	check(sim.needs.social == 60.0 and sim.needs.fun == 52.0 and sim.needs.energy == 70.0, "The party dish must apply its advertised need tradeoffs.")
	sim.day = 9
	sim._offer_daily_story()
	check(sim.get_story_events().back().kind == "flea_market", "Day nine must offer the flea market.")
	sim.needs.energy = 80.0
	sim.needs.social = 40.0
	var satisfaction: int = sim.satisfaction
	money = sim.funds
	var charisma_xp: float = xp_total(sim, "charisma")
	check(sim.choose_story_event("story_day_9", "rent_table"), "Renting a flea-market table must be selectable.")
	check(sim.funds == money + 60, "Selling at the flea market must pay its stated income.")
	check(is_equal_approx(xp_total(sim, "charisma"), charisma_xp + 20.0), "Selling must practice charisma exactly (+20 XP).")
	check(sim.satisfaction == satisfaction + 10, "Selling must pay its stated satisfaction.")
	check(sim.needs.energy == 68.0 and sim.needs.social == 54.0, "The table choice must apply its energy and social tradeoffs.")
	check(not sim.choose_story_event("story_day_9", "rent_table"), "The market choice cannot be replayed.")
	sim.free()
