extends SceneTree
## Saved Everyday / Formal / Athletic / Sleep / Party looks change the current
## clothes through the same wardrobe menu and survive a JSON save.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func wardrobe_ids(sim: LifeSim) -> Array:
	var ids: Array = []
	for entry: Dictionary in sim.get_actions_for("wardrobe"):
		if bool(entry.get("available", false)):
			ids.append(str(entry.id))
	return ids

func complete_wear(sim: LifeSim, id: String) -> bool:
	if not sim.queue_action(id, "wardrobe"):
		return false
	sim.begin_current_action()
	sim.tick(5.0)
	return sim.action_queue.is_empty()

func run() -> void:
	var sim := LifeSim.new()
	root.add_child(sim)
	var look: Dictionary = LifeCharacterIdentity.generate(4401, {"age_stage": "adult", "name": "Jules Vale"})
	sim.new_household(look)
	sim.autonomy = false
	check(str(sim.character.outfit_category) == "everyday", "A new household starts in Everyday clothes")
	check(sim.character.outfit_collection is Dictionary and sim.character.outfit_collection.has("party"), "The household stores a Party look")
	var menu: Array = wardrobe_ids(sim)
	check(menu.has("wear_formal") and menu.has("wear_athletic") and menu.has("change_outfit"), "The wardrobe offers the other saved looks")
	check(not menu.has("wear_everyday"), "The worn Everyday look is not offered again")
	var everyday_outfit: int = int(sim.character.outfit)
	check(complete_wear(sim, "wear_formal"), "Wear formal completes at the wardrobe")
	check(str(sim.character.outfit_category) == "formal" and int(sim.character.outfit) == 1, "Wear formal applies the Formal silhouette")
	check(int(sim.character.outfit) != everyday_outfit or everyday_outfit == 1, "Formal is a visible change unless Everyday was already a jacket")
	check(complete_wear(sim, "wear_athletic"), "Wear athletic completes at the wardrobe")
	check(str(sim.character.outfit_category) == "athletic" and int(sim.character.bottom) == 1, "Wear athletic applies shorts")
	check(complete_wear(sim, "wear_casual"), "Wear casual completes at the wardrobe")
	check(int(sim.character.outfit) == 0 and str(sim.character.outfit_category) == "athletic", "A specific top edits the current saved look")
	check(int(sim.character.outfit_collection.athletic.outfit) == 0, "The Athletic slot remembers the casual shirt")
	check(complete_wear(sim, "change_outfit"), "Change outfit completes at the wardrobe")
	check(str(sim.character.outfit_category) == "sleep", "Change outfit advances to the next saved type")
	var restored := LifeSim.new()
	root.add_child(restored)
	var loaded: Dictionary = restored.restore_state(JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(sim.get_state()))))
	check(bool(loaded.ok), "A wardrobe change survives JSON restore: " + str(loaded.get("error", "")))
	check(str(restored.character.outfit_category) == "sleep", "The worn type is saved")
	check(int(restored.character.outfit_collection.athletic.outfit) == 0, "Edited slots survive the save")
	var legacy := LifeSim.new()
	root.add_child(legacy)
	legacy.new_household({"name": "Alex Rivera", "age_stage": "adult", "outfit": 3, "bottom": 1, "top_color": "7195b3", "bottom_color": "39444f", "shoe_color": "ece4d5"})
	check(str(legacy.character.outfit_category) == "everyday" and int(legacy.character.outfit) == 3, "A save without a collection keeps its current clothes as Everyday")
	check(int(legacy.character.outfit_collection.everyday.outfit) == 3, "Legacy clothes are copied into the Everyday slot")
	var matching_clothes: Dictionary = legacy.character.duplicate(true)
	matching_clothes.outfit_collection.formal = matching_clothes.outfit_collection.everyday.duplicate(true)
	LifeCharacterIdentity.apply_category(matching_clothes, "formal")
	check(LifeCharacterIdentity.wardrobe_fields(legacy.character) != LifeCharacterIdentity.wardrobe_fields(matching_clothes), "Matching palettes still distinguish category-specific garments for live updates")
	var routine := LifeSim.new()
	root.add_child(routine)
	routine.new_household(LifeCharacterIdentity.generate(8802, {"age_stage": "adult", "name": "Robin Vale"}))
	routine.autonomy = false
	check(complete_wear(routine, "wear_everyday") or str(routine.character.outfit_category) == "everyday", "Routine Lifelet can wear Everyday")
	routine.queue_action("sleep", "bed")
	routine.begin_current_action()
	check(str(routine.character.outfit_category) == "sleep", "Going to bed changes into Sleep clothes")
	routine.cancel_action()
	routine.queue_action("jog", "treadmill")
	routine.begin_current_action()
	check(str(routine.character.outfit_category) == "athletic", "A run changes into Athletic clothes")
	routine.cancel_action()
	routine.queue_action("dance", "stereo")
	routine.begin_current_action()
	check(str(routine.character.outfit_category) == "party", "Dancing changes into Party clothes")
	routine.cancel_action()
	for pair: Array in [["nap", "sleep"], ["stretch", "athletic"], ["morning_run", "athletic"], ["ask_partner", "formal"], ["commit", "formal"], ["career_day", "formal"], ["school_day", "everyday"], ["return_home", "everyday"]]:
		LifeCharacterIdentity.apply_category(routine.character, "party")
		routine._wear_for_activity(str(pair[0]))
		check(str(routine.character.outfit_category) == str(pair[1]), "%s wears %s clothes" % [pair[0], pair[1]])
	routine.queue_action("sleep", "bed")
	routine.begin_current_action()
	for _i: int in range(8):
		routine.tick(60.0)
	check(str(routine.character.outfit_category) == "everyday", "Waking from sleep returns Everyday clothes")
	for pair: Array in [["nap", "bed"], ["jog", "treadmill"]]:
		LifeCharacterIdentity.apply_category(routine.character, "party")
		if not routine.queue_action(str(pair[0]), str(pair[1])):
			check(false, "%s can be queued to test Everyday revert" % pair[0])
			continue
		routine.begin_current_action()
		if not routine.action_queue.is_empty():
			routine.action_queue[0]["duration"] = 8.0
			routine.action_queue[0]["elapsed"] = 0.0
		routine.tick(10.0)
		check(str(routine.character.outfit_category) == "everyday", "Finishing %s returns Everyday clothes" % pair[0])
	var starters: Array = []
	for lot: int in [0, 1, 2]:
		var kinds: Array = []
		for item: Dictionary in LifeCatalog.starter_layout(lot):
			kinds.append(str(item.kind))
		starters.append(kinds.has("wardrobe"))
	check(starters == [true, true, true], "Every starter lot includes a wardrobe")
	sim.queue_free()
	restored.queue_free()
	legacy.queue_free()
	routine.queue_free()
	await process_frame
	print("OUTFIT_CATEGORIES_RESULT ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
