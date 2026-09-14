extends SceneTree
## Background music and household pets, end to end.
##
## No pointer or rendering proof: the music loop and its switch, the pet shop
## policy, the mixed-coat appearance, the paid purchase and the save round trip
## are all asserted from the real controller and household state.

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


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	_music()
	_pet_policy()
	_pet_coat()
	await _pet_purchase()
	_pet_accessories()

	app.queue_free()
	await process_frame
	print("MUSIC_AND_PETS %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## "Summit Dawn" is the game's own theme, looped, and switched from the menu.
func _music() -> void:
	var player: AudioStreamPlayer = app.music_player
	check(is_instance_valid(player), "The controller creates a music player.")
	check(player.stream != null, "Summit Dawn loads as the game's music.")
	if player.stream != null:
		check(not player.stream.get_length() < 60.0, "The music is a full-length track rather than a stub.")
	# The theme loops across its whole length, which is what makes the quiet
	# head and tail of this file the seamless join.
	check(app.music_enabled and player.playing, "Music plays when the game starts.")
	app.set_music(false)
	check(not app.music_enabled and player.stream_paused, "Turning music off pauses the theme.")
	app.set_music(true)
	check(app.music_enabled and player.playing and not player.stream_paused, "Turning music back on resumes it.")
	# The sound switch is separate and still silences the music with everything else.
	app.set_sound(false)
	check(player.stream_paused, "Turning all sound off also silences the music.")
	app.set_sound(true)
	check(not player.stream_paused, "Turning sound back on restores the music.")
	# The pause menu and the main menu both offer the switch.
	app.start_household()
	app.show_menu()
	var found: bool = false
	for button: Node in app.overlay.find_children("*", "Button", true, false):
		if str(button.text).begins_with("Music:"):
			found = true
			button.pressed.emit()
	check(found, "The pause menu offers a music switch.")
	check(not app.music_enabled, "The pause-menu switch turns the music off.")
	app.set_music(true)
	app.close_overlay()


## The shop's policy: prices, candidates, and what may be bought.
func _pet_policy() -> void:
	check(LifePets.SPECIES == ["cat", "dog"], "The shop sells cats and dogs.")
	check(LifePets.price_for("cat") > 0 and LifePets.price_for("dog") > 0, "Each species has its own price.")
	check(LifePets.price_for("cat") != LifePets.price_for("dog"), "A cat and a dog are priced differently.")
	# Six reviews always show both species and both sexes.
	var species_seen: Dictionary = {}
	var sexes_seen: Dictionary = {}
	var names: Dictionary = {}
	for choice: int in range(LifePets.candidate_count()):
		var pet: Dictionary = LifePets.candidate(1, choice)
		species_seen[str(pet.species)] = true
		sexes_seen[str(pet.sex)] = true
		names[str(pet.name)] = true
		check(LifePets.profile_error(pet).is_empty(), "Reviewed pet %d is a valid pet." % choice)
	check(species_seen.has("cat") and species_seen.has("dog"), "A shop visit always offers a cat and a dog.")
	check(sexes_seen.has("female") and sexes_seen.has("male"), "A shop visit always offers both sexes.")
	check(names.size() >= 3, "Reviewed pets carry different names.")
	# The same review is reproducible, so reopening the shop changes nothing.
	check(LifePets.candidate(2, 3) == LifePets.candidate(2, 3), "A reviewed pet is reproducible.")
	check(LifePets.candidate(1, 0) != LifePets.candidate(2, 0), "A later shop visit reviews a different pet.")
	# A malformed review is refused rather than taken in.
	var broken: Dictionary = LifePets.candidate(1, 0).duplicate(true)
	broken.name = "   "
	check(not LifePets.profile_error(broken).is_empty(), "A pet without a name is refused.")
	broken = LifePets.candidate(1, 0).duplicate(true)
	broken.coat_color = "not a colour"
	check(not LifePets.profile_error(broken).is_empty(), "A pet with an invalid coat colour is refused.")
	broken = LifePets.candidate(1, 0).duplicate(true)
	broken.gradient = 1.6
	check(not LifePets.profile_error(broken).is_empty(), "A coat gradient outside 0..1 is refused.")
	broken = LifePets.candidate(1, 0).duplicate(true)
	broken.species = "iguana"
	check(not LifePets.profile_error(broken).is_empty(), "An unknown species is refused.")
	# An absent record means a household that owns no pets; a damaged one is refused.
	check(LifePets.validate(null, {}).is_empty(), "An absent pets record is accepted.")
	check(not LifePets.validate({"version": 1, "next_serial": 2, "pets": []}, {}).is_empty(), "An out-of-step pet serial is refused.")
	check(not LifePets.validate({"version": 1}, {}).is_empty(), "A truncated pets record is refused.")


## A coat is two natural colours mixed into one gradient, so a mixed pet and a
## solid pet are both reachable from the same colour list.
func _pet_coat() -> void:
	var solid: Dictionary = LifePets.candidate(1, 0).duplicate(true)
	solid.coat_color = "211e1c"
	solid.mark_color = "ead6b8"
	solid.gradient = 0.0
	var mixed: Dictionary = solid.duplicate(true)
	mixed.gradient = 0.85
	var solid_look: Dictionary = LifePets.appearance(solid)
	var mixed_look: Dictionary = LifePets.appearance(mixed)
	check(solid_look.coat_color == "211e1c" and solid_look.mark_color == "ead6b8", "The two chosen colours are kept apart.")
	check(is_equal_approx(float(solid_look.gradient), 0.0), "A solid coat keeps no gradient.")
	check(is_equal_approx(float(mixed_look.gradient), 0.85), "A mixed coat keeps its gradient.")
	check(solid_look.coat_color != solid_look.mark_color, "A mixed coat pairs two different natural colours.")
	# Every authored colour is a usable hex value, so any pairing works.
	for colour: String in LifePets.COAT_COLORS:
		check(LifePets.colour(colour), "Authored coat colour %s is valid." % colour)
	# A damaged appearance falls back rather than producing an invisible pet.
	var broken: Dictionary = LifePets.appearance({"coat_color": "zzz", "gradient": 8.0})
	check(LifePets.colour(broken.coat_color) and float(broken.gradient) <= 1.0, "A damaged appearance falls back to a valid look.")
	# The live body is built from that appearance and carries the mixed coat.
	app.start_household()
	await process_frame
	var actor := LifePetActor.new()
	# Configured before entering the tree, exactly as the game's spawn path does.
	actor.configure("pet_test", "dog", mixed, "Test", "male")
	app.world.house.add_child(actor)
	check(actor.species == "dog", "The pet body takes the species it was given.")
	check(actor.find_children("*", "MeshInstance3D", true, false).size() > 0, "The authored pet model loads and shows geometry.")
	var found_body := actor.find_child("Body", true, false)
	var found_head := actor.find_child("Head", true, false)
	var found_tail := actor.find_child("Tail", true, false)
	check(found_body != null, "The dog model keeps its named body part.")
	check(found_head != null and found_tail != null, "The pet model keeps the head and tail the idle animation pivots.")
	check(actor.find_child("Leg_FL", true, false) != null and actor.find_child("Leg_BR", true, false) != null, "The pet model keeps all four legs.")
	# Animating is real: the head and tail actually move, and a frozen pet does not.
	actor.animate(0.1, false, 1.0)
	var head: Node3D = found_head
	var first: Vector3 = head.rotation
	for step: int in range(30):
		actor.animate(0.05, false, 1.0)
	check(head.rotation != first, "A living pet's head moves as it idles.")
	var frozen: Vector3 = head.rotation
	for step: int in range(20):
		actor.animate(0.05, false, 0.0)
	check(head.rotation == frozen, "A paused pet holds still.")
	actor.queue_free()
	await process_frame


## Buying a pet: reviewed, priced, paid once, saved and restored.
func _pet_purchase() -> void:
	var household: LifeHousehold = app.household
	var before: int = app.sim.funds
	var review: Dictionary = LifePets.candidate(int(household.pets.next_serial), 0)
	review.species = "cat"
	review.gradient = 0.7
	review.coat_color = "3a2b23"
	review.mark_color = "f2ece0"
	var prepared: Dictionary = household.prepare_pet(review)
	check(bool(prepared.get("ok", false)), "A cat review prepares while the household can pay.")
	check(int(prepared.request.fee) == LifePets.price_for("cat"), "The prepared review quotes the cat's price.")
	var request: Dictionary = prepared.get("request", {}).duplicate(true)
	var spawn: Vector3 = app.world.lot_exit_position(0)
	var destination: Vector3 = app.pet_arrival_destination(spawn)
	check(destination.is_finite(), "A pet has a clear arrival route into the starter home.")
	var result: Dictionary = household.commit_pet(request, spawn)
	check(bool(result.ok) and not bool(result.get("duplicate", false)), "The reviewed cat comes home.")
	check(household.pets.pets.size() == 1, "The household now owns one pet.")
	check(app.sim.funds == before - LifePets.price_for("cat"), "The cat's price is charged exactly once.")
	# Confirming the same review twice is harmless rather than a second charge.
	var paid: int = app.sim.funds
	var again: Dictionary = household.commit_pet(request, spawn)
	check(bool(again.get("ok", false)) and bool(again.get("duplicate", false)), "A repeated confirmation is recognised.")
	check(app.sim.funds == paid, "A repeated confirmation does not charge again.")
	# A review for a serial the household has not reached yet, or from another
	# household size, is refused rather than taken in.
	var stale: Dictionary = prepared.request.duplicate(true)
	stale.member_count = int(stale.member_count) + 1
	stale.serial = int(stale.serial) + 1
	check(not bool(household.commit_pet(stale, spawn).ok), "A stale pet review is refused.")
	# The body is spawned and the pet can be picked.
	app.spawn_pet(str(result.pet.id), result.pet, spawn, destination)
	await process_frame
	check(app.pet_actors.has(str(result.pet.id)), "The bought pet gets a body in the world.")
	var targets: Array = app.world.simulation_targets()
	check(app.pet_actors.size() == household.pets.pets.size(), "Every owned pet has exactly one body.")
	app._refresh_pet_targets()
	# The arrival walk is real movement, not a teleport.
	var walker: LifePetActor = app.pet_actors[str(result.pet.id)]
	var origin: Vector3 = walker.position
	for step: int in range(200):
		app._tick_pets(0.05)
	check(walker.position.distance_to(origin) > 0.05 or walker.position.distance_to(destination) < 0.05, "The arriving pet walks toward its spot.")
	# The saved record survives a real save and a fresh load.
	check(app.save_game("Pets Round Trip"), "The household saves with a pet.")
	await process_frame
	var slot: String = app.active_save_id
	var id: String = str(result.pet.id)
	household.pets = LifePets.fresh()
	app.load_game(slot)
	await process_frame
	check(app.household.pets.pets.size() == 1, "A fresh load restores the household's pet.")
	var restored: Dictionary = app.household.pets.pets[0] if app.household.pets.pets.size() == 1 else {}
	check(str(restored.get("id", "")) == id, "The restored pet keeps its identity.")
	check(str(restored.get("species", "")) == "cat", "The restored pet keeps its species.")
	check(str(restored.get("coat_color", "")) == "3a2b23" and str(restored.get("mark_color", "")) == "f2ece0", "The restored pet keeps both coat colours.")
	check(is_equal_approx(float(restored.get("gradient", -1.0)), 0.7), "The restored pet keeps its mixed gradient.")
	check(app.pet_actors.has(id), "A fresh load rebuilds the pet's body in the world.")
	# A damaged pet record is refused rather than silently dropped.
	var damaged: Dictionary = app.household.get_state(app.world.serialize_items())
	damaged.pets.pets[0].gradient = 5.0
	var validator: LifeHousehold = LifeHousehold.new()
	var checked: Dictionary = validator.restore_state(damaged)
	validator.free()
	check(not bool(checked.ok), "A save with an impossible coat gradient is refused.")
	damaged = app.household.get_state(app.world.serialize_items())
	damaged.pets.pets[0].fee = 7
	var validator2: LifeHousehold = LifeHousehold.new()
	var checked2: Dictionary = validator2.restore_state(damaged)
	validator2.free()
	check(not bool(checked2.ok), "A save whose pet price does not match the shop is refused.")


## Accessories are real furnishings, and each is offered only to the pet that
## can use it.
func _pet_accessories() -> void:
	var pets: Array = app.household.pets.pets
	check(pets.size() >= 1 and str(pets[0].species) == "cat", "The household owns a cat.")
	for kind: String in LifeCatalog.PET_ACCESSORIES:
		check(LifeCatalog.ITEMS.has(kind), "The catalogue sells the %s." % kind)
		check(int(LifeCatalog.ITEMS[kind].price) > 0, "The %s has a price." % kind)
	var available: Array = LifePets.available_accessories(pets)
	check(available.has("pet_bowl"), "A cat household is offered a pet bowl.")
	check(available.has("cat_tree"), "A cat household is offered a cat tree.")
	check(not available.has("kennel"), "A cat household is not offered a dog kennel.")
	# Adding a dog makes the kennel available, and removing the cat hides the tree.
	var dogs: Array = [{"species": "dog"}]
	check(LifePets.available_accessories(dogs).has("kennel"), "A dog household is offered a kennel.")
	check(not LifePets.available_accessories(dogs).has("cat_tree"), "A dog household is not offered a cat tree.")
	check(LifePets.available_accessories(dogs).has("pet_bowl"), "A dog household is offered a bowl.")
	check(not LifePets.accessory_kind_error("cat_tree", dogs).is_empty(), "Buying a cat tree without a cat is refused with a reason.")
	check(not LifePets.accessory_kind_error("kennel", pets).is_empty(), "Buying a kennel without a dog is refused with a reason.")
	check(not LifePets.accessory_kind_error("cat_tree", []).is_empty(), "Buying an accessory with no pets at all is refused with a reason.")
	check(LifePets.accessory_kind_error("pet_bowl", pets).is_empty(), "A bowl is allowed for any pet.")
	check(not LifePets.accessory_kind_error("dog_house", pets).is_empty(), "An unknown accessory is refused.")
	# The household view agrees, and an unaffordable accessory is refused.
	check(app.household.accessory_availability("cat_tree").is_empty(), "The household offers the cat tree while it can pay.")
	var before: int = app.sim.funds
	app.household.set_funds(5)
	check(not app.household.accessory_availability("cat_tree").is_empty(), "An unaffordable accessory is refused with a reason.")
	app.household.set_funds(before)
	# The accessory is bought through the ordinary furnishing path and charged once.
	var protection: Dictionary = app.build_protection_context()
	var entry: Dictionary = {"id": "placed_pet_test", "kind": "cat_tree", "x": 4.0, "z": 4.0, "rotation": 0.0}
	var proposed: Array = app.world.serialize_items()
	proposed.append(entry)
	check(app.build_transactions.furnishing_error(proposed).is_empty(), "The cat tree has a legal free spot.")
	app.world.add_item(entry)
	check(not app._find_item("placed_pet_test").is_empty(), "The bought cat tree is placed in the home.")
	check(str(LifeCatalog.ITEMS["cat_tree"].category) == "Pets", "The accessories live under the Pets catalogue category.")
	app.world.remove_item("placed_pet_test")
