extends SceneTree
## Actual main-controller collision checks, imported stair geometry and floor
## graph, with minimal world setup instead of the decorative neighbourhood.
const Building = preload("res://scripts/building_state.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
var app: Node
var world: LifeWorld
var actor: LifePetActor
var controller: RefCounted
var checks: int = 0
var failures: int = 0
const PET: String = "pet_stair_cat"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
func advance(seconds: float = .05) -> void:
	controller.tick(seconds, 1.0)
	actor.animate(seconds, bool(app.pet_errands.get(PET, {}).get("walking", false)), 1.0)
func until_using() -> bool:
	for n: int in range(1500):
		if str(controller.state(PET).phase) == "using": return true
		advance()
	return false
func run() -> void:
	# The real main methods can be exercised without starting its title screen.
	app = load("res://scripts/main.gd").new()
	world = LifeWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.house = Node3D.new()
	world.add_child(world.house)
	world.furniture = Node3D.new()
	world.house.add_child(world.furniture)
	app.world = world
	app.household = LifeHousehold.new()
	app.sound_enabled = false
	var state: Dictionary = Building.fresh()
	state.floors = [{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	for level: int in [0, 1]:
		for side: int in [-1, 1]:
			state.walls.append({"id":("upper_" if level else "")+("north" if side<0 else "south"),"level":level,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	var stairs: Dictionary = Building.propose(state, {"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}}, 10000)
	check(bool(stairs.ok), "Fixture uses a supported authored staircase")
	if not bool(stairs.ok): quit(1); return
	state = stairs.after
	world.construction.restore(state)
	world.add_item({"id":"upper_pet_bed","kind":"pet_bed_cat","x":-2.0,"z":3.0,"rotation":0.0,"level":1}, false)
	world.rebuild_navigation()
	check(world.construction.stair_nodes.size() == 1, "Stair is present as physical scene geometry")
	var record: Dictionary = LifePets.record_from(LifePets.candidate(1, 0), PET, 1)
	app.household.pets.pets.append(record)
	actor = LifePetActor.new()
	actor.configure(PET, "cat", LifePets.appearance(record), "Stair Cat")
	world.house.add_child(actor)
	actor.position = Vector3(-2, .16, -2)
	app.pet_actors[PET] = actor
	controller = Behavior.new(app)
	var upper := Vector3(2, 3.16, 3)
	var lower := Vector3(-2, .16, -2)
	check(bool(controller.command(PET, "pet_move", upper).ok), "Selected pet accepts an upstairs floor command")
	var segments: Array = app.pet_errands[PET].segments
	check(segments.any(func(segment: Dictionary) -> bool: return str(segment.kind) == "stair"), "Pet route retains real stair segment metadata")
	var continuous: bool = true
	var climbed: bool = false
	for n: int in range(1500):
		var before: Vector3 = actor.position
		advance()
		continuous = continuous and before.distance_to(actor.position) <= .071
		climbed = climbed or (actor.position.y > .2 and actor.position.y < 3.1)
		if str(controller.state(PET).phase) == "using": break
	check(continuous and climbed, "Pet climbs continuously at walking speed without teleporting")
	check(actor.position.distance_to(upper) < .01 and actor.floor_level == 1, "Pet reaches the selected upper floor and changes its picking floor")
	check(bool(controller.command(PET, "pet_move", lower).ok), "Pet accepts walking downstairs")
	var queued: bool = false
	for n: int in range(1500):
		advance()
		if actor.position.y > .5 and actor.position.y < 2.8:
			queued = bool(controller.command(PET, "pet_move", upper).ok)
			break
	check(queued and app.pet_errands[PET].has("pending_command"), "A new command during stair descent waits for a safe landing")
	check(until_using() and actor.position.distance_to(upper) < .01, "Pet reaches a landing then follows the replacement route upstairs")
	check(bool(controller.command(PET, "pet_go_bed").ok) and until_using(), "Upper-floor pet bed is reachable through its own floor graph")
	advance()
	check(actor.behavior == "rest" and actor.floor_level == 1, "Pet lies in its upstairs bed without losing floor identity")
	check(bool(controller.command(PET, "pet_move", lower).ok), "Floor command first exits the upstairs bed")
	check(until_using() and actor.position.distance_to(lower) < .01, "Pet leaves furniture, descends stairs and reaches the ground floor")
	check(not bool(controller.command(PET, "pet_move", Vector3(0, 1.66, 0)).ok), "Arbitrary unsupported mid-air destinations are refused")
	controller.command(PET, "pet_stop_playing")
	app.household.pet_care(PET).needs.energy = 10.0
	advance()
	check(str(controller.state(PET).action) == "pet_go_bed", "Tired cat autonomously selects its own upstairs bed")
	check(until_using(), "Autonomous cat rest follows the same physical staircase route")
	app.household.pet_care(PET).needs.energy = 90.0
	controller.command(PET, "pet_move", lower)
	check(until_using() and actor.position.distance_to(lower) < .01, "Cat returns to ground after its autonomous upstairs rest")
	var no_stair: Dictionary = state.duplicate(true)
	no_stair.stairs.clear()
	no_stair.openings.clear()
	world.construction.restore(no_stair)
	world.rebuild_navigation()
	check(not bool(controller.command(PET, "pet_move", upper).ok), "Disconnected upper floor cannot be reached without its stairs")
	print("PET_STAIRS %d checks, %d failures" % [checks, failures])
	app.household.free()
	app.free()
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
