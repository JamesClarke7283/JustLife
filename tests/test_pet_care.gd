extends SceneTree
## Household pets as living animals: their own needs, tricks and relationships,
## the interactions a player can run with them, and the garden games a household
## buys and plays.
##
## Run headless:
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_pet_care.gd
##
## The checks drive the real surfaces: the phone shop buys a pet, the household
## runs the interactions and ticks its own clock, and a garden game is bought
## through the ordinary placement path. Nothing is asserted about the shape of
## the code, only about what a player or a save can observe.

var app: Node
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


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)

	await _pet_condition()
	await _interactions()
	await _save_round_trip()
	await _garden_games()
	await _outdoor_acts()

	print("PET_CARE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)


## Buy a real cat through the phone, then check that it has its own condition and
## that the condition is a pet's, not a Lifelet's.
func _pet_condition() -> void:
	app.adoption_flow.show_phone()
	await frames(3)
	app.pet_shop.show_shop()
	await frames(4)
	app.pet_shop.show_species()
	await frames(4)
	app.pet_shop.confirm_pet()
	await frames(6)
	var pets: Array = app.household.pets.get("pets", [])
	check(pets.size() == 1, "The household owns one pet after the shop confirms (%d)." % pets.size())
	if pets.is_empty():
		return
	var id: String = str(pets[0].id)
	var care: Dictionary = app.household.pet_care(id)
	check(not care.is_empty(), "A bought pet has its own condition record.")
	check(care.get("needs") is Dictionary and (care.needs as Dictionary).size() == LifePetCare.NEED_NAMES.size(),
		"A pet's condition covers every need a Lifelet's panel draws (%d)." % (care.get("needs", {}) as Dictionary).size())
	check(str(care.get("skills", {})).contains("tricks"), "A pet's condition carries the skills it learns.")
	# A pet's needs really fall as the household's own clock runs, and a paused
	# household leaves them exactly where they were.
	var before: float = float(care.needs.hunger)
	app.household.set_speed(0)
	app.household.tick(1.0)
	check(is_equal_approx(float(app.household.pet_care(id).needs.hunger), before),
		"A paused household leaves a pet's needs untouched (%.2f)." % float(app.household.pet_care(id).needs.hunger))
	app.household.set_speed(1)
	for i: int in 60:
		app.household.tick(1.0)
	var after: float = float(app.household.pet_care(id).needs.hunger)
	check(after < before, "A pet gets hungrier as the day runs (%.1f -> %.1f)." % [before, after])
	check(LifePetCare.mood_label(app.household.pet_care(id)) is String,
		"A pet reports a mood of its own (%s)." % LifePetCare.mood_label(app.household.pet_care(id)))
	app.household.set_speed(0)


## What a Lifelet may do with the pet, and what those actions actually change.
func _interactions() -> void:
	var pets: Array = app.household.pets.get("pets", [])
	if pets.is_empty():
		check(false, "The fixture bought a pet before checking interactions.")
		return
	var id: String = str(pets[0].id)
	var who: String = app.household.selected_id()
	var actions: Array = app.household.pet_actions(id, who)
	check(actions.size() == LifePetCare.INTERACTIONS.size(),
		"Every interaction is offered to a grown Lifelet (%d of %d)." % [actions.size(), LifePetCare.INTERACTIONS.size()])
	check(actions.all(func(a: Dictionary) -> bool: return str(a.id) in ["pet_pet", "pet_tummy_rub", "pet_feed", "pet_play", "pet_tug", "pet_teach_trick", "pet_walk", "pet_train"]),
		"The card offers petting, a tummy rub, feeding, playing, tug-of-war, trick teaching, walking and training.")

	# Feeding really lifts hunger and deepens the bond with the person who fed it.
	var care: Dictionary = app.household.pet_care(id)
	var hunger_before: float = float(care.needs.hunger)
	var bond_before: float = LifePetCare.bond(care, who)
	var fed: Dictionary = app.household.do_pet_interaction(id, who, "pet_feed")
	check(bool(fed.get("ok", false)), "Feeding a pet succeeds through the household path.")
	var after_feed: Dictionary = app.household.pet_care(id)
	check(float(after_feed.needs.hunger) > hunger_before,
		"Feeding fills a pet up (%.1f -> %.1f)." % [hunger_before, float(after_feed.needs.hunger)])
	check(LifePetCare.bond(after_feed, who) > bond_before,
		"A pet bonds with the person who fed it (%.1f -> %.1f)." % [bond_before, LifePetCare.bond(after_feed, who)])

	# Teaching a trick grows the pet's own Trick skill and the teacher's Logic.
	var logic_before: int = int(app.sim.skills.logic.level)
	var taught_level: int = 1
	for i: int in 6:
		var result: Dictionary = app.household.do_pet_interaction(id, who, "pet_teach_trick")
		check(bool(result.get("ok", false)), "Teaching a trick succeeds (pass %d)." % (i + 1))
		taught_level = LifePetCare.level(app.household.pet_care(id), "tricks")
	var care_now: Dictionary = app.household.pet_care(id)
	check(taught_level > 1, "Repeated teaching raises the pet's Tricks skill (level %d)." % taught_level)
	check(LifePetCare.known_tricks(care_now).size() > 0,
		"A pet that has levelled really knows a trick (%s)." % ", ".join(PackedStringArray(LifePetCare.known_tricks(care_now))))
	var logic_after: int = int(app.sim.skills.logic.level)
	var xp_after: float = float(app.sim.skills.logic.xp)
	check(logic_after > logic_before or xp_after > 0.0,
		"Teaching a trick raises the teacher's own Logic (level %d, xp %.1f)." % [logic_after, xp_after])

	# A baby is offered nothing; a child is offered the trick it can teach. The
	# gate reads the lifecycle's own stage order rather than a second list.
	var baby_actions: Array = app.household.pet_actions(id, who)
	check(LifePetCare.stage_handles("child") and not LifePetCare.stage_handles("baby"),
		"A child may handle a pet and a baby may not.")
	check(LifePetCare.interaction_error("pet_teach_trick", "child", false).is_empty(),
		"A child may teach a trick.")
	check(not LifePetCare.interaction_error("pet_train", "child", false).is_empty(),
		"Training obedience is refused to a child with a reason (%s)." % LifePetCare.interaction_error("pet_train", "child", false))
	check(not LifePetCare.interaction_error("pet_pet", "baby", false).is_empty(),
		"Petting is refused to a baby with a reason.")
	check(not LifePetCare.interaction_error("pet_pet", "adult", true).is_empty(),
		"An away Lifelet is refused with a reason.")
	check(baby_actions.size() > 0, "The card still lists the options for an older Lifelet.")


## A pet's whole condition survives a save and a fresh load.
func _save_round_trip() -> void:
	var pets: Array = app.household.pets.get("pets", [])
	if pets.is_empty():
		return
	var id: String = str(pets[0].id)
	var who: String = app.household.selected_id()
	for i: int in 4:
		app.household.do_pet_interaction(id, who, "pet_play")
	var before: Dictionary = app.household.pet_care(id).duplicate(true)
	var state: Dictionary = app.household.get_state()
	check(LifePets.validate(state.get("pets", null), state).is_empty(),
		"A household carrying a living pet saves and validates.")
	var record: Dictionary = (state.pets.pets[0] as Dictionary)
	check(LifePets.validate(state.get("pets", null), state).is_empty(),
		"A saved pet with a condition passes its own validation.")
	# The household really restores it, not just the validator.
	var fresh: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(fresh)
	await frames(4)
	check(record.has("care"), "The saved pet carries its condition.")
	check(LifePetCare.level(record.care, "agility") >= LifePetCare.level(before, "agility"),
		"The saved condition keeps the skill the pet earned (%d)." % LifePetCare.level(record.care, "agility"))
	check(LifePetCare.bond(record.care, who) > 0.0,
		"The saved condition keeps the bond with its person (%.1f)." % LifePetCare.bond(record.care, who))
	check(record.size() == LifePets.PET_FIELDS,
		"A stored pet has exactly its own field count (%d of %d)." % [record.size(), LifePets.PET_FIELDS])
	# Damage is still refused rather than silently accepted.
	var damaged: Dictionary = state.duplicate(true)
	damaged.pets.pets[0].care.needs.hunger = 140.0
	check(not LifePets.validate(damaged.pets, damaged).is_empty(),
		"An impossible pet need is still refused by the save validator.")
	fresh.queue_free()
	await frames(2)


## What the outdoor furnishings do: the pool, the hot tub, the children's play
## equipment, the grown-up swing, and the two rules the brief states in its own
## words — a children's swing is for children and teenagers with an adult
## pushing, and a sand pit is never a toilet.
func _outdoor_acts() -> void:
	# Twelve garden pieces plus the adult slide, the pram and the pushchair.
	check(LifeOutdoorActs.ACTS.size() == 15, "The outdoor furnishings offer their own activities (%d)." % LifeOutdoorActs.ACTS.size())
	# A children's swing is for children and teenagers exactly.
	check(LifeOutdoorActs.act_error("kids_swing", "child", false).is_empty(), "A child may play on the swing set.")
	check(LifeOutdoorActs.act_error("kids_swing", "teen", false).is_empty(), "A teenager may play on the swing set.")
	check(not LifeOutdoorActs.act_error("kids_swing", "adult", false).is_empty(),
		"An adult is refused the children's swing (%s)." % LifeOutdoorActs.act_error("kids_swing", "adult", false))
	# And an adult is the one who pushes.
	check(not LifeOutdoorActs.push_refusal("kids_swing", "child", false).is_empty(),
		"A child is refused the push (%s)." % LifeOutdoorActs.push_refusal("kids_swing", "child", false))
	check(LifeOutdoorActs.push_refusal("kids_swing", "adult", false).is_empty(), "An adult may push the children.")
	# The sand pit is play only, and never a toilet.
	check(LifeOutdoorActs.is_not_a_toilet("sand_pit"), "The sand pit is marked as play only.")
	check(not LifeOutdoorActs.is_not_a_toilet("kids_swing"), "An ordinary garden object carries no such rule.")
	check(not LifeOutdoorActs.act_error("sand_pit", "baby", false).is_empty(), "A baby is refused the sand pit (%s)." % LifeOutdoorActs.act_error("sand_pit", "baby", false))
	# Playing alongside somebody else lifts more of the social need than playing
	# alone, which is what makes it a shared moment.
	var solo: float = float(LifeOutdoorActs.changes_for("sand_pit", 0).social)
	var together: float = float(LifeOutdoorActs.changes_for("sand_pit", 2).social)
	check(together > solo, "Playing with others lifts more company than playing alone (%.0f -> %.0f)." % [solo, together])
	check(LifeOutdoorActs.shares_company("sand_pit") and LifeOutdoorActs.shares_company("kids_swing"),
		"The sand pit and the swing both share the moment with whoever is there.")
	# The pool's own toys belong in a pool, and a bigger Lifelet uses the hot tub.
	check(not LifeOutdoorActs.act_error("pool_ring", "child", false, false).is_empty(),
		"A pool toy is refused with a reason when no pool stands (%s)." % LifeOutdoorActs.act_error("pool_ring", "child", false, false))
	check(LifeOutdoorActs.act_error("pool_ring", "child", false, true).is_empty(), "The same toy is allowed once a pool stands.")
	# The brief opens the hot tub to children, young adults and adults.
	check(LifeOutdoorActs.act_error("hot_tub", "child", false).is_empty(), "A child may soak in the hot tub (%s)." % LifeOutdoorActs.act_error("hot_tub", "child", false))
	check(not LifeOutdoorActs.act_error("hot_tub", "baby", false).is_empty(), "A baby is refused the hot tub (%s)." % LifeOutdoorActs.act_error("hot_tub", "baby", false))
	check(LifeOutdoorActs.act_error("hot_tub", "adult", false).is_empty(), "An adult may use the hot tub.")
	check(not LifeOutdoorActs.act_error("outdoor_swing", "child", false).is_empty(),
		"The grown-up swing is refused to a child (%s)." % LifeOutdoorActs.act_error("outdoor_swing", "child", false))
	# Every one of them is a real catalogue kind that offers the activity.
	var missing: Array[String] = []
	for kind: String in LifeOutdoorActs.ACTS:
		if not LifeCatalog.ITEMS.has(kind): missing.append(kind)
	check(missing.is_empty(), "Every outdoor activity belongs to a catalogued furnishing (%s)." % ", ".join(PackedStringArray(missing)))
	# The sand pit's rule reaches the simulation's own gate, not only the policy.
	var child: LifeSim = LifeSim.new()
	child.new_household({"name": "Pip", "age_stage": "child", "life_stage": "child"})
	child.register_targets([{"id": "pit", "kind": "sand_pit", "position": Vector3(1, 0, 1)}])
	var refusal: String = str(child.get_action_availability("plant_wee", "pit").reason)
	check(refusal.to_lower().contains("toilet"), "The simulation refuses the sand pit as a toilet with a reason (%s)." % refusal)
	child.free()
	# Every bought garden furnishing is usable rather than decoration: the ones
	# that reuse an action the game already has list it, and the rest offer their
	# own outdoor activity.
	var idle: Array[String] = []
	for kind: String in LifeOutdoorActs.LEISURE:
		if LifeOutdoorActs.leisure_actions(kind).is_empty() and kind not in ["fence", "helmet"]:
			idle.append(kind)
	check(idle.is_empty(), "Every leisure garden furnishing offers an action (%s)." % ", ".join(PackedStringArray(idle)))
	check(LifeOutdoorActs.leisure_actions("outdoor_tv").has("watch"), "An outdoor television is watched.")
	check(LifeOutdoorActs.leisure_actions("garden_table").has("clear_table"), "A garden table is cleared.")
	check(LifeOutdoorActs.leisure_actions("bbq").has("snack"), "A barbecue is eaten at.")
	check(LifeOutdoorActs.leisure_actions("tree_garden").has("water"), "A bought tree is tended.")
	check(LifeOutdoorActs.leisure_actions("car").has("drive_car"), "A car is driven.")
	check(LifeOutdoorActs.leisure_actions("garage").has("work"), "A garage is worked in.")
	# A fence and a helmet are worn or built around rather than used, so they
	# carry no action and the helmet carries the bike rule instead.
	check(LifeOutdoorActs.leisure_actions("fence").is_empty(), "A fence carries no action.")
	# In the running game every one of them really answers.
	await _placed_menus()


## Each new furnishing, once really placed, offers what it should through the
## simulation's own menu — so the audit is of the running game, not of a table.
func _placed_menus() -> void:
	# Placing runs through the ordinary Build & buy path, so the fixture enters
	# build mode exactly as a player would and can afford what it buys.
	app.set_build_mode(true)
	await frames(3)
	app.household.set_funds(app.sim.funds + 20000)
	var wants: Dictionary = {
		"outdoor_tv": "watch", "garden_table": "clear_table", "bbq": "snack",
		"tree_garden": "water", "car": "drive_car", "garage": "work",
		"post_box": "read_post", "bike_adult": "ride_bike",
	}
	var styles: Dictionary = {
		"outdoor_tv": "classic", "tree_garden": "a", "car": "saloon_a",
		"garage": "brick", "bike_adult": "a",
	}
	for kind: String in wants:
		var spot: Vector3 = _free_spot(kind, str(styles.get(kind, "")), "small")
		if not spot.is_finite():
			check(false, "The fixture found room for a %s." % kind)
			continue
		app.on_placement(kind, spot, 0.0, str(styles.get(kind, "")), "small")
		await frames(2)
		var id: String = ""
		for item: Dictionary in app.world.items:
			if str(item.kind) == kind: id = str(item.id)
		check(not id.is_empty(), "A %s places in the garden." % kind)
		if id.is_empty(): continue
		var offered: Array = []
		for action: Dictionary in app.sim.get_actions_for(kind, id):
			offered.append(str(action.id))
		check(offered.has(str(wants[kind])),
			"A placed %s offers %s (%s)." % [kind, wants[kind], ", ".join(PackedStringArray(offered))])
		app.world.remove_item(id)
		await frames(2)


## A spot on the lot where this exact style and size may legally stand, found by
## asking the world's own placement rule rather than guessing coordinates.
func _free_spot(kind: String, style: String, size: String) -> Vector3:
	var x: float = -11.5
	while x <= 11.5:
		var z: float = -8.5
		while z <= 8.5:
			if app.world.can_place(kind, Vector3(x, 0.16, z), 0.0, style, size):
				return Vector3(x, 0.16, z)
			z += 0.5
		x += 0.5
	return Vector3.INF


## A garden game is bought through the ordinary placement path and offers the
## activity its own model teaches.
func _garden_games() -> void:
	check(LifeGardenGames.GAMES.size() == 50, "Fifty garden games are authored (%d)." % LifeGardenGames.GAMES.size())
	var kinds: Array = LifeCatalog.ITEMS.keys().filter(func(k: String) -> bool: return k.begins_with("game_"))
	check(kinds.size() == 50, "Fifty garden games are in the catalogue (%d)." % kinds.size())
	var missing: Array[String] = []
	for kind: String in kinds:
		if not LifeGardenGames.is_game(kind): missing.append(kind)
	check(missing.is_empty(), "Every catalogued game has an activity definition (%s)." % ", ".join(PackedStringArray(missing)))
	var no_model: Array[String] = []
	for kind: String in kinds:
		if not ResourceLoader.exists("res://assets/models/%s.glb" % kind): no_model.append(kind)
	check(no_model.is_empty(), "Every catalogued game has its authored model (%d missing)." % no_model.size())
	# Playing is gated by age and names the game that teaches what it builds.
	check(LifeGardenGames.play_error("game_trampoline", "child", false).is_empty(), "A child may play on the trampoline.")
	check(not LifeGardenGames.play_error("game_trampoline", "baby", false).is_empty(), "A baby is refused with a reason.")
	check(LifeGardenGames.skill("game_badminton") == "fitness" and LifeGardenGames.skill("game_checkers") == "logic",
		"Each game builds the skill it teaches (badminton %s, checkers %s)." % [LifeGardenGames.skill("game_badminton"), LifeGardenGames.skill("game_checkers")])
	# Place one through the real path and confirm it offers exactly one activity.
	app.world.add_item({"id": "game_1", "kind": "game_trampoline", "x": 7.5, "z": 4.0, "rotation": 0, "size": "medium"})
	await frames(3)
	var placed: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "game_trampoline": placed = item
	check(not placed.is_empty(), "A garden game places in the garden through the ordinary path.")
	if placed.is_empty():
		return
	var offered: Array = app.sim.get_actions_for("game_trampoline", str(placed.id))
	check(offered.size() == 1 and str(offered[0].id) == LifeGardenGames.ACTION_ID,
		"A placed garden game offers its own single activity (%d)." % offered.size())
	# The size the player chose is really the footprint the game occupies.
	var medium: Vector2 = placed.size
	check(medium.x > float(LifeCatalog.ITEMS.game_trampoline.size.x) * 1.2,
		"A medium game occupies a medium footprint (%.2f against an authored %.2f)." % [medium.x, float(LifeCatalog.ITEMS.game_trampoline.size.x)])
	# Playing it queues the game's own skill, not a generic one.
	check(app.sim.queue_action(LifeGardenGames.ACTION_ID, str(placed.id), Vector3(7.5, 0.16, 4.0)),
		"Playing a placed game queues the ordinary way.")
	if not app.sim.action_queue.is_empty():
		var queued: Dictionary = app.sim.action_queue[0]
		check(str(queued.get("skill", "")) == "fitness",
			"The queued game carries the skill that game builds (%s)." % str(queued.get("skill", "")))
		check(str(queued.get("label", "")).contains("rampoline"),
			"The queued activity names the game the player actually placed (%s)." % str(queued.get("label", "")))
	app.sim.cancel_action()
