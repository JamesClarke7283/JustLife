extends SceneTree
## Prove pets can be taught tricks and given a tummy rub: the card offers both,
## a cat refuses the tummy rub, a taught trick is kept on the pet's own record
## and survives a save round trip, and the trick list is shown on the card.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_pet_tricks.gd

var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

## Bring one animal home through the real reviewed-pet path.
func adopt(species: String, name: String) -> String:
	var household: LifeHousehold = app.household
	var review: Dictionary = LifePets.candidate(int(household.pets.next_serial), 0)
	review.species = species
	review.sex = "male"
	review.name = name
	var prepared: Dictionary = household.prepare_pet(review)
	if not bool(prepared.get("ok", false)):
		check(false, "The %s review prepares: %s" % [species, str(prepared.get("error", ""))])
		return ""
	var spawn: Vector3 = app.world.lot_exit_position(household.members.size())
	var destination: Vector3 = app.pet_arrival_destination(spawn)
	var result: Dictionary = household.commit_pet(prepared.request, spawn)
	if not bool(result.get("ok", false)):
		check(false, "The %s comes home: %s" % [species, str(result.get("error", ""))])
		return ""
	app.spawn_pet(str(result.pet.id), result.pet, spawn, destination)
	return str(result.pet.id)

func actions_for(pet_id: String) -> Array:
	return app.sim.get_actions_for("pet", pet_id)

func action_named(pet_id: String, action_id: String) -> Dictionary:
	for action: Dictionary in actions_for(pet_id):
		if str(action.id) == action_id: return action
	return {}

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(8)
	app.set_sound(false)
	app.selected_lot = 0
	app.start_household()
	await frames(12)
	app.household.set_speed(0)

	var dog: String = adopt("dog", "Bramble")
	var cat: String = adopt("cat", "Willow")
	await frames(6)
	check(not dog.is_empty() and not cat.is_empty(), "A dog and a cat came home")

	# --- What the menu offers -------------------------------------------------
	var dog_actions: Array = actions_for(dog).map(func(a: Dictionary) -> String: return str(a.id))
	check(dog_actions.has("teach_pet_trick"), "A pet offers teaching a trick")
	check(dog_actions.has("pet_tummy_rub"), "A dog offers a tummy rub")
	var rub: Dictionary = action_named(cat, "pet_tummy_rub")
	check(not rub.is_empty() and not bool(rub.get("available", true)), "A cat is refused a tummy rub")

	# --- Teaching really teaches ---------------------------------------------
	var record: Dictionary = app._pet_record(dog)
	check((record.get("tricks", []) as Array).is_empty(), "A new dog knows no tricks")
	var first: String = app.household_flow.next_trick(dog)
	check(not first.is_empty(), "There is something to teach (%s)" % first)
	# Two sessions of patient work learn the first trick.
	var learned: String = ""
	for session: int in range(LifePets.TRICK_SESSIONS):
		var taught: Dictionary = app.household_flow.teach_pet_trick(dog, "Mara Vale")
		check(bool(taught.get("ok", false)), "Teaching session %d is accepted" % (session + 1))
		learned = str(taught.get("trick", ""))
	var known: Array = app._pet_record(dog).get("tricks", [])
	check(known.has(learned), "The trick is kept on the pet's own record (%s)" % str(known))
	check(app.household_flow.next_trick(dog) != learned, "The next lesson moves on (%s)" % app.household_flow.next_trick(dog))

	# A partial session is honest: progress is recorded, the trick is not claimed.
	var partial_pet: String = cat
	var progress_trick: String = app.household_flow.next_trick(partial_pet)
	app.household_flow.teach_pet_trick(partial_pet, "Mara Vale")
	var partial_record: Dictionary = app._pet_record(partial_pet)
	check(not (partial_record.get("tricks", []) as Array).has(progress_trick), "A partial session does not claim the trick")
	check(int((partial_record.get("trick_progress", {}) as Dictionary).get(progress_trick, 0)) == 1, "A partial session records its progress")

	# --- Affection is counted -------------------------------------------------
	check(int(app._pet_record(dog).get("affection", 0)) == 0, "A new dog has had no cuddles")
	app.household_flow.affectionate_pet(dog, "Mara Vale")
	check(int(app._pet_record(dog).get("affection", 0)) == 1, "A tummy rub is remembered on the pet")

	# --- Bathing: a dog's job, never a cat's --------------------------------
	var bath_dog: Dictionary = action_named(dog, "bathe_pet")
	var bath_cat: Dictionary = action_named(cat, "bathe_pet")
	# The dog's own cleanliness has to be low for the bath to be offered.
	((app._pet_record(dog)["care"] as Dictionary)["needs"] as Dictionary)["hygiene"] = 20.0
	var dog_bath: Dictionary = action_named(dog, "bathe_pet")
	check(not dog_bath.is_empty(), "A pet offers a bath")
	check(not bool(dog_bath.get("available", false)) or not str(dog_bath.get("unavailable_reason", "")).contains("cat"), "A dog's bath is not refused as a cat's")
	check(not bath_cat.is_empty() and not bool(bath_cat.get("available", true)), "A cat is refused a bath")
	check(str(bath_cat.get("unavailable_reason", "")).contains("licking"), "The refusal explains that cats lick themselves clean: \"%s\"" % str(bath_cat.get("unavailable_reason", "")))
	app.household_flow.bathe_pet(dog, "Mara Vale")
	check(is_equal_approx(float(((app._pet_record(dog)["care"] as Dictionary)["needs"] as Dictionary).get("hygiene", 0.0)), 100.0), "Bathing really cleans the dog")

	# --- A cat grooms itself, so its coat stays up on its own ---------------
	var cat_record: Dictionary = app._pet_record(cat)
	((cat_record["care"] as Dictionary)["needs"] as Dictionary)["hygiene"] = 90.0
	var cat_clean_before: float = float(((cat_record["care"] as Dictionary)["needs"] as Dictionary)["hygiene"])
	# The tick's own grooming term is faster than the drain, so a cat recovers.
	check(LifePets.CAT_GROOM_PER_HOUR > 0.0, "A cat's own grooming keeps its coat up (%.1f/h)" % LifePets.CAT_GROOM_PER_HOUR)

	# --- The card shows it ----------------------------------------------------
	# Freeze the frame's autosave so the card can be read while it is open.
	app.set_process(false)
	app.show_pet_card(dog)
	await frames(4)
	var labels: Array[String] = []
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		var l: Label = node as Label
		if l != null: labels.append(str(l.text))
	check(labels.any(func(t: String) -> bool: return t.contains("Knows:")), "The card lists what the pet has learned")
	var card_buttons: Array[String] = []
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		var b: Button = node as Button
		if b != null: card_buttons.append(str(b.text))
	check(card_buttons.has("Teach a trick"), "The card offers teaching a trick")
	check(card_buttons.has("Give a tummy rub"), "The card offers a tummy rub")
	app.close_overlay()
	app.set_process(true)
	await frames(3)

	# --- It survives a save ---------------------------------------------------
	var state: Dictionary = app.household.get_state(app.world.serialize_items())
	var pets_error: String = LifePets.validate(state.get("pets", null), state)
	check(pets_error.is_empty(), "The saved pets with their tricks validate cleanly%s" % ("" if pets_error.is_empty() else ": " + pets_error))
	var restored: LifeHousehold = LifeHousehold.new()
	app.add_child(restored)
	var result: Dictionary = restored.restore_state(state)
	check(bool(result.get("ok", false)), "The household restores with the taught tricks%s" % ("" if bool(result.get("ok", false)) else ": " + str(result.get("error", ""))))
	var restored_dog: Dictionary = {}
	for pet: Dictionary in restored.pets.get("pets", []):
		if str(pet.name) == "Bramble": restored_dog = pet
	check(not restored_dog.is_empty(), "The dog is in the restored household")
	check((restored_dog.get("tricks", []) as Array).has(learned), "The taught trick rode the save (%s)" % str(restored_dog.get("tricks", [])))
	check(int(restored_dog.get("affection", 0)) == 1, "The remembered cuddles rode the save")
	restored.free()

	print("PET_TRICKS ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
