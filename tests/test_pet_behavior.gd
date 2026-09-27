extends SceneTree
## Real-world regression for commanded/automatic pet activity, arrival before
## retrieval, physical rest/climb, two-hour kennel timing and quiet toy play.
const Behavior = preload("res://scripts/pet_behavior.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var controller: RefCounted

func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func advance(id: String, count: int, dt: float = .2) -> void:
	for step: int in range(count):
		controller.tick(dt, 1.0)
		var actor: LifePetActor = app.pet_actors[id]
		actor.animate(dt, bool(app.pet_errands.get(id, {}).get("walking", false)), 1.0)

func until_phase(id: String, phase: String, limit: int = 400) -> bool:
	for step: int in range(limit):
		if str(controller.state(id).phase) == phase: return true
		advance(id, 1)
	return false

func item(kind: String, at: Vector3, id: String) -> Dictionary:
	app.world.add_item({"kind": kind, "id": id, "x": at.x, "z": at.z, "level": 0, "rotation": 0.0}, false)
	return controller._item(id)

func reset(id: String, at: Vector3) -> void:
	app.pet_errands.clear()
	app.pet_arrivals.clear()
	controller.toy_claims.clear()
	app.pet_actors[id].position = at
	app.pet_actors[id].clear_behavior()
	controller.idle_minutes[id] = -1000.0
	for need: String in LifePetCare.NEED_NAMES: app.household.pet_care(id).needs[need] = 90.0

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	print("PET_BEHAVIOR scene ready")
	for n: int in 4: await process_frame
	app.selected_lot = 0
	app.start_household()
	print("PET_BEHAVIOR household ready")
	for n: int in 4: await process_frame
	app.set_process(false)
	app.world.set_process(false)
	app.household.set_speed(0)
	app.set_sound(false)
	controller = Behavior.new(app)
	var dog: Dictionary = LifePets.record_from(LifePets.candidate(1, 1), "pet_behavior_dog", 1)
	var cat: Dictionary = LifePets.record_from(LifePets.candidate(2, 0), "pet_behavior_cat", 1)
	app.household.pets.pets.append(dog)
	app.household.pets.pets.append(cat)
	app.household.pets.next_serial = 3
	var origin := Vector3(-8.0, .16, 6.0)
	app.spawn_pet(str(dog.id), dog, origin, origin)
	app.spawn_pet(str(cat.id), cat, Vector3(8, .16, 6), Vector3(8, .16, 6))
	var bed: Dictionary = item("pet_bed_dog", Vector3(-8, .16, 3), "behavior_bed")
	var kennel: Dictionary = item("kennel", Vector3(-8, .16, -1), "behavior_kennel")
	var tree: Dictionary = item("cat_tree", Vector3(8, .16, 3), "behavior_tree")
	var box: Dictionary = item("dog_toy_box", Vector3(-5, .16, 6), "behavior_box")
	var toy: Dictionary = item("pet_toy_dog", Vector3(-5, .16, 6), "behavior_toy")
	toy["box_id"] = str(box.id)
	var cat_bed: Dictionary = item("pet_bed_cat", Vector3(8, .16, -1), "behavior_cat_bed")
	var cat_box: Dictionary = item("cat_toy_box", Vector3(6, .16, 6), "behavior_cat_box")
	var cat_toy: Dictionary = item("pet_toy_cat", Vector3(6, .16, 6), "behavior_cat_toy")
	cat_toy["box_id"] = str(cat_box.id)
	app.world.rebuild_navigation()
	print("PET_BEHAVIOR furniture ready")
	check(not bed.is_empty() and not kennel.is_empty() and not tree.is_empty(), "Real pet furniture exists in the world")

	reset(str(dog.id), origin)
	check(bool(controller.command(str(dog.id), "pet_go_bed").ok), "Dog accepts Go to Dog Bed")
	check(until_phase(str(dog.id), "using"), "Dog physically walks onto its bed")
	advance(str(dog.id), 2)
	var actor: LifePetActor = app.pet_actors[str(dog.id)]
	check(actor.position.distance_to(bed.node.position) < .25 and actor.behavior == "rest", "Dog lies on the bed cushion")
	var before: Vector3 = actor.position
	var elapsed: float = float(controller.state(str(dog.id)).elapsed_minutes)
	controller.tick(30, 0)
	actor.animate(30, false, 0)
	check(actor.position == before and float(controller.state(str(dog.id)).elapsed_minutes) == elapsed, "Pause freezes rest timing and pose")
	check(bool(controller.command(str(dog.id), "pet_move", origin).ok), "Ground command interrupts bed rest through a physical exit")
	for n: int in 200:
		advance(str(dog.id), 1)
		if actor.position.distance_to(origin) < .12: break
	check(actor.position.distance_to(origin) < .12, "Dog reaches the clicked ground after exiting its bed")

	reset(str(dog.id), Vector3(-8, .16, 1))
	check(bool(controller.command(str(dog.id), "pet_go_dog_house").ok), "Dog accepts outdoor dog house command")
	check(until_phase(str(dog.id), "using"), "Dog walks through the dog house doorway")
	advance(str(dog.id), 2)
	check(actor.position.distance_to(kennel.node.position) < .3 and actor.behavior == "rest", "Dog rests inside the dog house")
	controller.tick(119, 1)
	check(str(controller.state(str(dog.id)).phase) == "using", "Commanded dog stays for nearly two game hours")
	controller.tick(1, 1)
	check(str(controller.state(str(dog.id)).phase) == "exiting", "Dog leaves at the two-hour limit")

	reset(str(cat.id), Vector3(8, .16, 1))
	check(not bool(controller.command(str(cat.id), "pet_go_dog_house").ok), "Cat never accepts a dog house command")
	check(bool(controller.command(str(cat.id), "pet_cat_tree").ok), "Cat accepts play on cat tree")
	check(until_phase(str(cat.id), "using"), "Cat walks to the cat tree")
	advance(str(cat.id), 5)
	var cat_actor: LifePetActor = app.pet_actors[str(cat.id)]
	check(cat_actor.behavior == "scratch", "Cat scratches the post")
	advance(str(cat.id), 45)
	check(cat_actor.behavior == "climb" and cat_actor.position.y > .2, "Cat physically climbs")
	advance(str(cat.id), 20)
	check(cat_actor.behavior == "tree_play" and cat_actor.position.y > 1.3, "Cat plays on the upper platform")
	controller.command(str(cat.id), "pet_stop_playing")
	check(until_phase(str(cat.id), "idle"), "Stop Playing returns cat to the floor")

	reset(str(dog.id), origin)
	app.sound_enabled = true
	check(bool(controller.command(str(dog.id), "pet_play_toys").ok), "Dog accepts toy box command")
	check(str(toy.get("box_id", "")) == str(box.id), "Toy stays in the box before the dog reaches it")
	check(until_phase(str(dog.id), "using"), "Dog walks to its toy box")
	advance(str(dog.id), 20)
	check(not toy.has("box_id") and toy.node.position.distance_to(box.node.position) > .3, "Dog pulls a toy out onto the floor after arrival")
	check(actor.behavior == "toy_play" and actor.squeak_count > 0, "Floor toy play has a distinct squeak")
	var squeaks: int = actor.squeak_count
	controller.command(str(dog.id), "pet_stop_squeaking")
	advance(str(dog.id), 30)
	check(actor.squeak_count == squeaks and actor.behavior == "toy_play", "Stop Squeaking keeps play going quietly")
	controller.command(str(dog.id), "pet_stop_playing")
	advance(str(dog.id), 10)
	check(actor.behavior != "toy_play" and controller.toy_claims.is_empty(), "Stop Playing releases the toy and ends play")
	reset(str(cat.id), Vector3(8, .16, 1))
	check(bool(controller.command(str(cat.id), "pet_go_bed").ok) and until_phase(str(cat.id), "using"), "Cat walks onto its own cat bed")
	advance(str(cat.id), 2)
	check(cat_actor.behavior == "rest" and cat_actor.position.distance_to(cat_bed.node.position) < .25, "Cat lies down on its cat bed")
	reset(str(cat.id), Vector3(8, .16, 6))
	check(bool(controller.command(str(cat.id), "pet_play_toys").ok) and until_phase(str(cat.id), "using"), "Cat walks to its own toy box")
	advance(str(cat.id), 20)
	check(not cat_toy.has("box_id") and cat_actor.behavior == "toy_play" and cat_actor.squeak_count > 0, "Cat retrieves and squeaks its own floor toy")

	reset(str(dog.id), origin)
	controller.idle_minutes[str(dog.id)] = 9.0
	controller.turns[str(dog.id)] = 0
	advance(str(dog.id), 2)
	check(str(controller.state(str(dog.id)).action) == "wander", "Comfortable pet autonomously explores the home")
	reset(str(dog.id), origin)
	app.household.pet_care(str(dog.id)).needs.energy = 10.0
	controller.turns[str(dog.id)] = 0
	advance(str(dog.id), 2)
	check(str(controller.state(str(dog.id)).action) == "pet_go_bed", "Tired dog autonomously chooses its bed")
	reset(str(dog.id), origin)
	controller.idle_minutes[str(dog.id)] = 9.0
	controller.turns[str(dog.id)] = 1
	advance(str(dog.id), 2)
	check(str(controller.state(str(dog.id)).action) == "pet_go_dog_house", "Dog autonomously walks into its outdoor house")
	reset(str(cat.id), Vector3(8, .16, 1))
	controller.idle_minutes[str(cat.id)] = 9.0
	controller.turns[str(cat.id)] = 1
	advance(str(cat.id), 2)
	check(str(controller.state(str(cat.id)).action) == "pet_cat_tree", "Cat autonomously chooses the scratching and climbing tree")
	var care: Dictionary = LifePetCare.fresh()
	LifePetCare.tick(care, 60)
	check(float(care.needs.energy) > 70.0, "An hour of need decay allows sleep to restore energy")
	check(LifePetCare.validate(care, []).is_empty() and LifePetActor.squeak_stream().data.size() > 4000, "Care saves remain valid and squeak contains PCM samples")
	check(controller.commands(str(cat.id)).any(func(entry: Dictionary) -> bool: return str(entry.label) == "Feed the Cat") and not controller.commands(str(cat.id)).any(func(entry: Dictionary) -> bool: return str(entry.label).contains("Dog")), "Cat quick commands contain cat labels only")
	print("PET_BEHAVIOR %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
