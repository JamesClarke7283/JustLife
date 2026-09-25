extends SceneTree
## A child actually queues and performs play on the Baby & Kids pieces and the
## garden. Solo objects do not wait for a teen or an adult. A rattle is for a
## sitting baby, not a school-age child.

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _sim(stage: String) -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	sim.new_household({"name":"Player","age_stage":stage,"traits":[]})
	sim.autonomy = false
	sim.household_bills_enabled = false
	sim.set_aging("normal", false)
	sim.wants.clear()
	sim.minutes = 1100.0
	for need: String in LifeSim.NEED_NAMES:
		sim.needs[need] = 80.0
	sim.needs.fun = 8.0
	return sim

func _at(kind: String, id: String = "") -> Dictionary:
	return {"id": id if not id.is_empty() else kind, "kind": kind, "position": Vector3(1, .16, 1)}

func _perform(sim: LifeSim) -> void:
	sim.begin_current_action()
	var action: Dictionary = sim.get_current_action()
	var remaining: float = float(action.get("duration", 0.0)) - float(action.get("elapsed", 0.0))
	sim.tick(remaining / LifeSim.GAME_MINUTES_PER_SECOND + 0.05)

func _play_alone(stage: String, kind: String, action_id: String, label: String) -> void:
	var sim: LifeSim = _sim(stage)
	sim.register_targets([_at(kind)])
	var choice: Dictionary = sim.autonomy_need_choice("fun")
	check(str(choice.get("id")) == action_id and str(choice.get("target_id")) == kind,
		"%s autonomy chooses %s on %s (%s @ %s)." % [label, action_id, kind, str(choice.get("id")), str(choice.get("target_id"))])
	var before: float = float(sim.needs.fun)
	var queued: bool = sim.make_child_play() if stage == "child" else sim.queue_action(action_id, kind, Vector3(1, .16, 1))
	check(queued and str(sim.get_current_action().get("id")) == action_id,
		"%s queues %s." % [label, action_id])
	_perform(sim)
	check(float(sim.needs.fun) > before and sim.get_current_action().is_empty(),
		"%s finishes %s and fun rises (%.1f -> %.1f)." % [label, action_id, before, float(sim.needs.fun)])
	sim.free()

func _initialize() -> void:
	_play_alone("child", "toy_chest", "play_toys", "Toy chest")
	_play_alone("child", "train_set", "play_toys", "Train set")
	_play_alone("child", "dollhouse", "play_dollhouse", "Dollhouse")
	_play_alone("child", "child_desk", "child_desk_study", "Child desk")
	_play_alone("child", "kids_slide", LifeOutdoorActs.ACTION_ID, "Slide")
	_play_alone("child", "kids_swing", LifeOutdoorActs.ACTION_ID, "Swing")
	_play_alone("child", "climbing_frame", LifeOutdoorActs.ACTION_ID, "Climbing frame")
	_play_alone("child", "game_hopscotch", LifeGardenGames.ACTION_ID, "Garden")
	var mixed: LifeSim = _sim("child")
	mixed.register_targets([
		_at("garden_bed", "bed_plot"), _at("kids_slide", "slide"), _at("adult_slide", "big"),
		_at("kids_swing", "swings"),
	])
	var outdoor: Dictionary = mixed.autonomy_need_choice("fun")
	check(str(outdoor.get("id")) == LifeOutdoorActs.ACTION_ID and str(outdoor.get("target_id")) in ["slide", "swings"],
		"Garden work and the adult slide lose to solo child play (%s @ %s)." % [str(outdoor.get("id")), str(outdoor.get("target_id"))])
	check(mixed.queue_action(LifeOutdoorActs.ACTION_ID, "swings", Vector3(1, .16, 1)),
		"A child starts the swings with nobody else in the household.")
	check(not mixed.get_action_availability(LifeOutdoorActs.PUSH_ID, "swings").available,
		"Pushing is optional; a child is not asked to provide an adult.")
	mixed.free()
	var child: LifeSim = _sim("child")
	child.register_targets([_at("baby_rattle"), _at("baby_mat")])
	check(child.get_actions_for("baby_rattle", "baby_rattle").is_empty() or not bool(child.get_actions_for("baby_rattle", "baby_rattle")[0].available),
		"A child is not sent to the baby rattle.")
	child.free()
	var baby: LifeSim = _sim("baby")
	baby.character["infant_born_day"] = baby.day - LifeBabyPlan.INFANT_SITTING_DAYS
	LifeBabyPlan.advance_infant_phase(baby.character, baby.day)
	baby.register_targets([_at("baby_rattle"), _at("baby_mat")])
	var rattle: Dictionary = baby.autonomy_need_choice("fun")
	check(str(rattle.get("id")) == "play_rattle" and str(rattle.get("target_id")) == "baby_rattle",
		"A sitting baby chooses the rattle (%s)." % str(rattle.get("id")))
	var before: float = float(baby.needs.fun)
	check(baby.queue_action("play_rattle", "baby_rattle", Vector3(1, .16, 1)), "A sitting baby queues the rattle alone.")
	_perform(baby)
	check(float(baby.needs.fun) > before, "The rattle session raises the baby's fun.")
	var mat: Dictionary = baby.get_action_availability("play_baby_mat", "baby_mat")
	baby.register_targets([_at("baby_mat")])
	check(baby.get_action_availability("play_baby_mat", "baby_mat").available, "The play mat is age-appropriate for a sitting baby (%s)." % str(mat))
	baby.free()
	var newborn: LifeSim = _sim("baby")
	LifeBabyPlan.seed_infant(newborn.character, newborn.day)
	newborn.register_targets([_at("baby_rattle"), _at("dollhouse")])
	check(not newborn.get_action_availability("play_rattle", "baby_rattle").available,
		"A newborn is too young for the rattle.")
	check(not newborn.get_action_availability("play_dollhouse", "dollhouse").available,
		"A newborn is too young for the dollhouse.")
	newborn.free()
	print("CHILD_PLAY %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
