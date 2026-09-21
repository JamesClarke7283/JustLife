extends SceneTree
## Two player-facing defects:
##
## 1. A pet's own card action ("Give a tummy rub") crashed on a real press:
##    `queue_interaction` read `item.node` through `world.approach` before its
##    pet branch, and a pet item carries no node.
## 2. An expectant mother rendered a giant bubble instead of a baby bump:
##    `_update_bump` overwrote the authored ellipsoid scale with a bare uniform
##    one, leaving the sphere at its mesh radius of one metre.

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void: _run.call_deferred()

## The world-space size of a node's own authored box.
func _world_extent(node: MeshInstance3D) -> Vector3:
	return node.get_aabb().size * node.global_transform.basis.get_scale().abs()

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	# Two young adults, so the household can really conceive a child.
	app.household_profiles = [
		{"name": "Avery", "age_stage": "young_adult", "traits": [], "hair": 0},
		{"name": "River", "age_stage": "young_adult", "traits": [], "hair": 0}]
	app.creator_family_links = []
	app.start_household(); await frames(10)
	app.household.set_speed(0)

	# ---------------------------------------------------------------- the pet
	var dog_choice: int = -1
	for choice: int in LifePets.candidate_count():
		if str(LifePets.candidate(1, choice).species) == "dog": dog_choice = choice; break
	var draft: Dictionary = LifePets.candidate(1, dog_choice)
	draft.name = "Rex"
	var prepared: Dictionary = app.household.prepare_pet(draft)
	var spawn: Vector3 = app.world.lot_exit_position(app.household.members.size())
	var committed: Dictionary = app.household.commit_pet(prepared.get("request", {}), spawn)
	check(bool(committed.get("ok", false)), "A dog really joins the household.")
	if not bool(committed.get("ok", false)):
		app.queue_free(); await frames(2); quit(1); return
	var pet_id: String = str(committed.pet.id)
	app.spawn_pet(pet_id, committed.pet, spawn, app.pet_arrival_destination(spawn))
	await frames(4)
	# Queue the card's own button, which is what crashed.
	app._queue_pet_action(pet_id, "pet_tummy_rub")
	await frames(4)
	var action: Dictionary = app.sim.get_current_action()
	check(str(action.get("id", "")) == "pet_tummy_rub",
		"The pet card's own action button really queues without crashing (%s)." % str(action.get("id", "")))
	check(Vector3(action.get("target_position", Vector3.ZERO)).is_finite() and Vector3(action.target_position) != Vector3.ZERO,
		"A pet action carries a real approach point from the animal's own body (%s)." % str(action.get("target_position", null)))
	# And it really completes, raising the pet's affection.
	app.household.set_speed(3)
	for i: int in 3000:
		app._process(.05)
		if i % 5 == 0: await process_frame
		if str(app.sim.get_current_action().get("id", "")) != "pet_tummy_rub": break
	var affection: int = int((app.household.pets.get("pets", [{}]) as Array)[0].get("affection", 0))
	check(affection > 0, "The tummy rub completes and really raises affection (%d)." % affection)

	# ------------------------------------------------------------ the bump
	# Conceive through the game's own plan, so the controller's per-frame line
	# sets the bump exactly as it does in play.
	var mother_id: String = str(app.household.selected_id())
	var mother: LifeActor = app.world.actors[mother_id]
	check(is_instance_valid(mother), "The selected Lifelet has a body.")
	var partner_id: String = ""
	for member: Dictionary in app.household.members:
		var other: String = str(member["id"])
		if other != mother_id: partner_id = other; break
	check(not partner_id.is_empty(), "The household has a second member to father the child.")
	var mother_sim: LifeSim = app.household.member_sim(mother_id)
	var partner_sim: LifeSim = app.household.member_sim(partner_id)
	app.household.pregnancy = LifeBabyPlan.conceive(mother_sim, mother_id, partner_sim, partner_id, app.household.day, app.household.minutes, 1)
	check(app.household.pregnancy_mother_id() == mother_id, "The household really records the mother.")
	app.household.set_speed(3)
	# Move the household clock to mid-term, where the bump is plainly shown.
	var due: float = float(app.household.pregnancy.due_at)
	var term: float = LifeBabyPlan.PREGNANCY_MINUTES

	# ---- mid-term: really shown, and body-sized ------------------------------
	var mid: float = due - term * 0.5
	app.household.day = int(floor(mid / LifeBabyPlan.MINUTES_PER_DAY)) + 1
	app.household.minutes = mid - float(app.household.day - 1) * LifeBabyPlan.MINUTES_PER_DAY
	app._process(.05)
	await frames(3)
	var bump: MeshInstance3D = mother.find_child("PregnancyBump", true, false)
	check(is_instance_valid(bump), "The expectant body owns a PregnancyBump mesh.")
	if not is_instance_valid(bump):
		app.queue_free(); await frames(2); quit(1); return
	var mid_progress: float = app.household.pregnancy_progress()
	check(bump.visible and mid_progress > 0.4 and mid_progress < 0.6,
		"An expectant mother really shows her bump mid-term (%.2f)." % mid_progress)
	var mid_size: Vector3 = _world_extent(bump)
	print("PROBE mid_extent=", mid_size, " progress=", mid_progress)
	# A believable baby bump is a fraction of a metre across on every axis. The
	# bug drew a ~2 m sphere around her.
	check(mid_size.x < 0.45 and mid_size.y < 0.55 and mid_size.z < 0.45,
		"The mid-term bump is a body-sized belly, not a giant bubble (%s m)." % str(mid_size))

	# ---- near birth: grown, still body-sized --------------------------------
	var late_at: float = due - term * 0.02
	app.household.day = int(floor(late_at / LifeBabyPlan.MINUTES_PER_DAY)) + 1
	app.household.minutes = late_at - float(app.household.day - 1) * LifeBabyPlan.MINUTES_PER_DAY
	app._process(.05)
	await frames(3)
	bump = mother.find_child("PregnancyBump", true, false)
	var late_progress: float = app.household.pregnancy_progress()
	check(late_progress > 0.95, "The household clock really reaches the end of the term (%.2f)." % late_progress)
	var late_size: Vector3 = _world_extent(bump)
	print("PROBE late_extent=", late_size, " progress=", late_progress)
	check(bump.visible and late_size.x > mid_size.x and late_size.x < 0.45,
		"The bump grows toward birth and stays body-sized (%.3f -> %.3f m)." % [mid_size.x, late_size.x])

	app.queue_free(); await frames(3)
	print("PET_BUMP_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
