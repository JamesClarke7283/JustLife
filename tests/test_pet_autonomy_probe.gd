extends SceneTree
## Pets rest on beds, cats use litter or outdoors, dogs relieve outdoors only,
## and toy boxes stock toys that pets and Lifelets can take, play with, and put away.
const Building = preload("res://scripts/building_state.gd")
const Land = preload("res://scripts/land.gd")

var checks: int = 0
var failures: Array = []
var app: Node


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	check(LifeCatalog.ITEMS.has("litter_tray"), "Litter tray is in the catalogue")
	check(LifePets.ACCESSORY_KINDS.has("litter_tray"), "Litter tray is a pet accessory")
	check(str(LifePets.ACCESSORY_SPECIES["litter_tray"]) == "cat", "Litter tray requires a cat")
	check(LifePets.TOY_BOX_TOYS["dog_toy_box"] == "pet_toy_dog", "Dog toy box stocks dog toys")
	check(LifePets.TOY_BOX_TOYS["cat_toy_box"] == "pet_toy_cat", "Cat toy box stocks cat toys")
	check(ResourceLoader.exists("res://assets/models/litter_tray.glb"), "Litter tray mesh exists")

	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	app.sim.funds = 20000
	app.set_build_mode(true)
	await frames(2)

	# Place bedding, litter, and a dog toy box.
	var placements := {
		"pet_bed_dog": Vector3(-2.5, 0.16, 2.0),
		"litter_tray": Vector3(2.5, 0.16, 2.0),
		"dog_toy_box": Vector3(0.0, 0.16, 3.2),
	}
	for kind: String in placements.keys():
		var at: Vector3 = placements[kind]
		var ok: bool = app.world.can_place(kind, at, 0.0)
		if not ok:
			for alt: Vector3 in [Vector3(-4.0, 0.16, 3.0), Vector3(4.0, 0.16, 3.0), Vector3(-1.0, 0.16, -2.5), Vector3(1.0, 0.16, -2.5), Vector3(0.0, 0.16, 6.5)]:
				if app.world.can_place(kind, alt, 0.0):
					at = alt; ok = true; break
		if ok:
			app.on_placement(kind, at, 0.0)
		check(ok, "%s placed in the home" % kind)
	await frames(2)

	var litter_count := 0
	var bed_count := 0
	var boxed_toys := 0
	var boxes := 0
	for item: Dictionary in app.world.items:
		if str(item.kind) == "litter_tray": litter_count += 1
		if str(item.kind) == "pet_bed_dog": bed_count += 1
		if str(item.kind) == "dog_toy_box": boxes += 1
		if str(item.kind) == "pet_toy_dog" and str(item.get("box_id", "")) != "":
			boxed_toys += 1
	check(litter_count >= 1, "Litter tray is in the world")
	check(bed_count >= 1, "Dog bed is in the world")
	check(boxes >= 1 and boxed_toys == LifePets.TOYS_PER_BOX, "Dog toy box stocks six nested toys (%d)" % boxed_toys)

	# Adopt a dog and a cat into the household records for autonomy checks.
	var dog: Dictionary = LifePets.record_from(LifePets.candidate(1, 1), "pet_dog_probe", 1)
	dog["species"] = "dog"
	var cat: Dictionary = LifePets.record_from(LifePets.candidate(1, 0), "pet_cat_probe", 1)
	cat["species"] = "cat"
	app.household.pets.pets.append(dog)
	app.household.pets.pets.append(cat)
	app.household.pets.next_serial = 3

	# Dogs never get an indoor bladder errand; cats do when litter exists.
	dog.care.needs["bladder"] = 10.0
	dog.care.needs["hunger"] = 90.0
	dog.care.needs["energy"] = 90.0
	dog.care.needs["fun"] = 90.0
	check(app._pet_needs_errand(dog, dog.care.needs) == "", "Dog does not treat bladder as an indoor errand")
	check(app._pet_outdoor_wanted(dog, dog.care.needs) == "bladder", "Dog bladder sends it outdoors only")

	cat.care.needs["bladder"] = 10.0
	cat.care.needs["hunger"] = 90.0
	cat.care.needs["energy"] = 90.0
	cat.care.needs["fun"] = 90.0
	check(app._pet_needs_errand(cat, cat.care.needs) == "bladder", "Cat with litter uses indoor bladder errand")
	check(app._pet_outdoor_wanted(cat, cat.care.needs) == "", "Cat with litter does not go outside for bladder")

	# Dog energy targets the bed centre.
	dog.care.needs["bladder"] = 90.0
	dog.care.needs["energy"] = 10.0
	check(app._pet_needs_errand(dog, dog.care.needs) == "energy", "Tired dog wants its bed")

	# Fun with a boxed toy: pet can claim one.
	dog.care.needs["energy"] = 90.0
	dog.care.needs["fun"] = 10.0
	var toy: Dictionary = app._pet_play_toy(dog)
	check(not toy.is_empty(), "Dog finds a playable toy from the box")
	check(app._pet_needs_errand(dog, dog.care.needs) == "fun", "Low fun with toys becomes an indoor play errand")
	check(app._pet_outdoor_wanted(dog, dog.care.needs) == "", "Indoor toys keep the dog from outdoor fun")

	# Lifelet take / put toy actions.
	var box: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "dog_toy_box":
			box = item; break
	check(not box.is_empty(), "Toy box is clickable")
	if box.is_empty():
		print("PET_AUTONOMY_PROBE %d/%d" % [checks - failures.size(), checks])
		for failure: String in failures:
			print("FAIL ", failure)
		quit(1)
		return
	var take_actions: Array = app.sim.get_actions_for("dog_toy_box", str(box.id))
	check(take_actions.any(func(a: Dictionary) -> bool: return str(a.id) == "take_pet_toy"), "Toy box offers Take a toy")
	app._lifelet_take_pet_toy(str(box.id))
	var floor_toys := 0
	var still_boxed := 0
	var floor_toy: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) != "pet_toy_dog": continue
		if str(item.get("box_id", "")) == "":
			floor_toys += 1
			floor_toy = item
		else:
			still_boxed += 1
	check(floor_toys == 1 and still_boxed == 5, "Taking a toy leaves five nested and one on the floor")
	var put_actions: Array = app.sim.get_actions_for("pet_toy_dog", str(floor_toy.id))
	check(put_actions.any(func(a: Dictionary) -> bool: return str(a.id) == "put_pet_toy"), "Floor toy offers Put toy away")
	check(put_actions.any(func(a: Dictionary) -> bool: return str(a.id) == "play_with_pet_toy"), "Floor toy offers Play with a pet")
	app._lifelet_put_pet_toy(str(floor_toy.id))
	check(str(floor_toy.get("box_id", "")) == str(box.id), "Put away nests the toy back in the box")

	print("PET_AUTONOMY_PROBE %d/%d" % [checks - failures.size(), checks])
	for failure: String in failures:
		print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
