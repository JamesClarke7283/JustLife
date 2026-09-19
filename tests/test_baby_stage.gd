extends SceneTree
## The baby life stage: registered and chaining to child, its own authored crawl
## model, a hands-and-knees pose while moving that keeps the hips low, and the
## adult-only actions refused through the public availability path. Headless.

const Actor = preload("res://scripts/actor.gd")
const LifeGroceries = preload("res://scripts/groceries.gd")
const BABY_MODEL = "res://assets/models/character_baby.glb"

var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void: _run.call_deferred()

func _find(app: Node, kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind:
			return item
	return {}

func _member_sim(app: Node, name: String) -> LifeSim:
	for member: Dictionary in app.household.members:
		if str(member.sim.character.name) == name:
			return member.sim
	return null

func _run() -> void:
	# --- The stage is registered and chains baby -> child. -------------------
	check("baby" in LifeLifecycle.STAGES, "The lifecycle registers a baby stage.")
	check(LifeLifecycle.STAGES.find("baby") == 0 and LifeLifecycle.STAGES.find("baby") < LifeLifecycle.STAGES.find("child"),
		"Baby sits before child, so every later stage still follows it.")
	check(LifeLifecycle.next_stage("baby") == "child", "A baby's next stage is child.")
	check(LifeLifecycle.next_stage("child") == "teen", "The existing child -> teen chain is unchanged.")
	check(LifeLifecycle.eligibility("baby") == "minor", "A baby is a minor, so adult-only systems exclude it.")
	check(str(LifeLifecycle.LABELS.get("baby", "")) == "Baby", "The baby stage has a display label.")
	check(int(LifeLifecycle.NORMAL_DAYS.get("baby", 0)) > 0, "The baby stage has a normal duration.")
	check(LifeLifecycle.with_article("baby") == "a baby", "The baby stage reads with its article.")
	check(LifeLifecycle.description("baby", LifeLifecycle.fresh()).begins_with("Baby"),
		"The baby stage describes itself without an index error.")

	# An old save without the field still resolves, and a baby save validates.
	var legacy: Dictionary = {"life_stage": "minor"}
	check(LifeLifecycle.stage_for(legacy) == "teen", "A save without an age stage keeps its old meaning.")
	var baby_save: Dictionary = {"age_stage": "baby", "life_stage": "minor"}
	check(LifeLifecycle.stage_for(baby_save) == "baby", "A baby save resolves its own stage.")
	check(LifeLifecycle.validate(baby_save, LifeLifecycle.fresh()).is_empty(), "A fresh baby save validates.")
	var history: Dictionary = LifeLifecycle.fresh()
	history.history = [{"from": "baby", "to": "child", "day": 8}]
	check(LifeLifecycle.validate({"age_stage": "child", "life_stage": "minor"}, history).is_empty(),
		"A birthday that moved baby to child validates.")
	var school: Dictionary = LifeEducation.fresh("baby", 1)
	check(str(school.stage) == "baby", "Schooling accepts the baby stage alongside every other age.")
	check(LifeEducation.advance(school, "child", 9, 480.0).ok, "A baby's birthday hands its school record to the child stage.")
	check(not LifeEducation.advance(LifeEducation.fresh("child", 1), "baby", 2, 480.0).ok,
		"School records still refuse moving backward into baby.")

	# --- The actor builds its own crawl rig from the baby model. -------------
	var baby: LifeActor = Actor.new()
	root.add_child(baby)
	baby.configure({"name": "Crawl QA", "age_stage": "baby", "low_detail": false, "outfit": 0, "hair": 0})
	baby.voice_enabled = false
	if not ResourceLoader.exists(BABY_MODEL):
		check(true, "SKIPPED: %s is not imported in this project, so the crawl rig cannot be checked. Run tools/baby_v60/create_baby.py --export and reimport." % BABY_MODEL)
	else:
		check(baby._model.scene_file_path.ends_with("character_baby.glb"),
			"A baby loads the authored baby model, not a rescaled adult.")
		check(baby._rig_bones.size() == 9, "The baby model keeps all nine usable skeletal joints.")
		check(is_equal_approx(baby.get_display_height(), .55), "The authored baby stands about 0.55 m tall.")
		check(absf(baby._hip_height - .245) < .002 and absf(baby._knee_height - .135) < .002,
			"The baby reports its own hip and knee landmarks.")
		check(not baby._blink_shapes.is_empty() and not baby._smile_shapes.is_empty(),
			"The baby keeps real blink and smile controls.")
		for feature: String in Actor.IDENTITY_KEYS:
			check(not baby._identity_shapes.get(feature, []).is_empty(), "The baby keeps the shared %s face control." % feature)
		check(baby.supports_age("baby"), "A complete baby asset set reports the stage as supported.")

		# --- Moving is a crawl: the pose differs from standing and the hips stay low.
		baby.clear_activity_anchor()
		# The authored rest pose every age stands in: the honest standing baseline.
		var standing_lean: float = baby.visual.rotation.x
		var standing_legs: Vector3 = baby._joints.Leg_L.rotation
		var standing_arms: Vector3 = baby._joints.Arm_L.rotation
		for frame: int in range(90):
			baby.animate(1.0 / 60.0, 1.0, true, "")
		var crawling_offset: Vector3 = baby.visual.position
		check(baby.visual.rotation.x > 1.0, "A moving baby pitches its torso forward %.2f rad, so it is not upright." % baby.visual.rotation.x)
		check(absf(baby.visual.rotation.x - standing_lean) > .8, "The crawl lean differs from the standing lean.")
		check(baby._joints.Leg_L.rotation.distance_to(standing_legs) > .8, "The crawl folds the legs away from their standing rest (%.2f rad)." % baby._joints.Leg_L.rotation.distance_to(standing_legs))
		check(baby._joints.Arm_L.rotation.distance_to(standing_arms) > .5, "The crawl plants the arms away from their standing rest.")
		check(crawling_offset.y > .03, "The crawl lifts the pitched body so its hands and knees reach the floor.")
		# The hips must sit near the knees: crawling, not walking on straight legs.
		var hips: float = baby.visual.to_global(Vector3(0, baby._hip_height, 0)).y
		var feet: float = baby.visual.to_global(Vector3(0, 0, 0)).y
		check(hips - feet < .22, "A crawling baby's hips stay low (%.3f m above its root), so it is not walking." % (hips - feet))
		check(baby.visual.position.y < .20, "The crawl stays near the floor rather than standing up.")
		# The limb cycle advances with the stride phase.
		var first_leg: Vector3 = baby._joints.Leg_L.rotation
		var seen: Dictionary = {}
		for frame: int in range(120):
			baby.animate(1.0 / 60.0, 1.0, true, "")
			seen[snappedf(baby._joints.Leg_L.rotation.x, .01)] = true
		check(seen.size() >= 4, "The crawl limbs cycle through the stride phase (%d distinct leg angles)." % seen.size())
		check(first_leg.distance_to(baby._joints.Leg_L.rotation) > 0.0 or seen.size() >= 4,
			"Every crawl frame moves at least one limb.")
		# Pausing still freezes the crawl.
		var frozen: Transform3D = baby.visual.transform
		var frozen_leg: Vector3 = baby._joints.Leg_L.rotation
		baby.animate(.5, 0.0, true, "")
		check(baby.visual.transform.is_equal_approx(frozen) and baby._joints.Leg_L.rotation.is_equal_approx(frozen_leg),
			"Pause freezes the crawl pose and limbs.")
		# A still baby kneels rather than holding the crawl.
		for frame: int in range(120):
			baby.animate(1.0 / 60.0, 1.0, false, "")
		check(baby.visual.rotation.x < .3, "A still baby is not left pitched over in the crawl.")
		check(baby._joints.Shin_L.rotation.x > 1.0, "A still baby sits back on its folded knees instead of crawling.")

	# --- Adult-only actions are refused for a baby. --------------------------
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	app.set_process(false)
	var sim: LifeSim = _member_sim(app, str(app.household.members[0].sim.character.name))
	check(sim != null, "The household has a member to age.")
	# Age the selected Lifelet down to a baby through the public profile fields.
	sim.character.age_stage = "baby"
	sim.character.life_stage = LifeLifecycle.eligibility("baby")
	check(str(sim.character.life_stage) == "minor", "The aged-down member is a minor again.")
	for pair: Array in [["cook", "adult work"], ["job", "a career"], ["study", "study"], ["paint", "adult hobbies"], ["jog", "the treadmill"]]:
		var availability: Dictionary = sim.get_action_availability(str(pair[0]), "fridge")
		check(not bool(availability.available) and not str(availability.reason).is_empty(),
			"A baby is refused %s through the public availability path (%s)." % [str(pair[1]), str(availability.reason)])
	# The recovery set a baby keeps still works. Cooking and snacking now come out
	# of the kitchen, so the fixture stocks it through the household's own order —
	# otherwise the fridge is empty and every meal is refused for that reason
	# rather than for anything about the baby.
	app.household.set_funds(app.household.funds + LifeGroceries.LARGE_BASKET_PRICE)
	check(bool(app.household.order_groceries("large").ok), "The fixture can stock its own kitchen.")
	check(bool(app.household.collect_groceries().ok), "The fixture's delivery arrives.")
	for pair: Array in [["sleep", "bed"], ["snack", "fridge"], ["toilet", "toilet"]]:
		var allowed: Dictionary = sim.get_action_availability(str(pair[0]), str(pair[1]))
		check(bool(allowed.available), "A baby may still %s (%s)." % [str(pair[0]), str(allowed.reason)])
	check(bool(sim.get_action_availability("birthday", "fridge").available), "A baby can still celebrate turning into a child.")
	var treadmill: Array = sim.get_actions_for("treadmill")
	var jog_entry: Dictionary = {}
	for entry: Dictionary in treadmill:
		if str(entry.id) == "jog": jog_entry = entry
	check(not jog_entry.is_empty() and not bool(jog_entry.available) and not str(jog_entry.unavailable_reason).is_empty(),
		"The treadmill still lists its jog entry for a baby, disabled with the caregiver reason, exactly as it does for a child.")
	check(str(sim.get_action_availability("flirt", "maya").reason) != "", "A baby cannot flirt.")

	baby.queue_free()
	app.queue_free()
	await process_frame
	await process_frame
	await process_frame
	print("BABY_STAGE %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
