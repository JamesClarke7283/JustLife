extends SceneTree
## Real authored pet mesh bounds throughout heading-aware wall and door routes.
const Building = preload("res://scripts/building_state.gd")
var app: Node
var world: LifeWorld
var pet: LifePetActor
var checks: int = 0
var failures: int = 0
var id: String = "wall_hull_pet"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("CHECK ", "PASS " if ok else "FAIL ", label)
func wall(name: String, x: float, z: float, width: float, depth: float) -> Dictionary:
	return {"id":name,"level":0,"x":x,"z":z,"w":width,"d":depth,"height":2.6,"cut":true,"material":"eae7d7"}
func structure(walls: Array) -> void:
	var state: Dictionary = Building.fresh()
	state.walls = walls
	world.construction.restore(state)
	world.rebuild_navigation()
func reset(species: String, at: Vector3, yaw: float) -> void:
	app.pet_errands.clear()
	var choice: Dictionary
	for index: int in LifePets.candidate_count():
		var candidate: Dictionary = LifePets.candidate(1, index)
		if str(candidate.species) == species: choice = candidate; break
	choice.coat_length = "long"
	var record: Dictionary = LifePets.record_from(choice, id, 1)
	app.household.pets.pets = [record]
	app.household.pets.next_serial = 2
	pet.configure(id, species, LifePets.appearance(record), species.capitalize())
	pet.position = at; pet.rotation.y = yaw; pet.clear_behavior(); pet.clear_interaction()
	app.pet_behavior().idle_minutes[id] = -1000.0
	for need: String in LifePetCare.NEED_NAMES: record.care.needs[need] = 90.0
	for step: int in 30: pet.animate(.05, false)

## Each visible mesh's transformed bounds enclose its actual vertices. Check
## their convex footprint and vertical extent against full physical walls.
func meshes_clear() -> bool:
	for mesh: MeshInstance3D in pet._model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var bounds: AABB = mesh.mesh.get_aabb()
		var points := PackedVector2Array()
		var low: float = INF; var high: float = -INF
		for corner: int in 8:
			var at: Vector3 = mesh.to_global(bounds.position + bounds.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1))
			points.append(Vector2(at.x, at.z)); low = minf(low, at.y); high = maxf(high, at.y)
		var polygon: PackedVector2Array = Geometry2D.convex_hull(points)
		for record: Dictionary in world.construction.records:
			var base: float = Building.level_y(int(record.get("level", 0)))
			if high <= base or low >= base + float(record.height): continue
			var area: Rect2 = Building.rect(record)
			var wall_polygon := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
			if not Geometry2D.intersect_polygons(polygon, wall_polygon).is_empty(): return false
	return true

func journey(target: Vector3, label: String, expect_detour: bool = false, doorway: bool = false) -> void:
	var accepted: Dictionary = app.pet_behavior().command(id, "pet_move", target)
	check(bool(accepted.ok), label + " admits a route")
	if not bool(accepted.ok): return
	var continuous: bool = true; var clear: bool = meshes_clear(); var detoured: bool = false
	var aligned: bool = true; var arrived: bool = false; var saw_turn: bool = false
	for leg: Dictionary in app.pet_errands[id].segments: saw_turn = saw_turn or bool(leg.get("turn", false))
	for step: int in 1500:
		var before: Vector3 = pet.position
		var yaw: float = pet.rotation.y
		app.pet_behavior().tick(.025, 1.0)
		pet.animate(.025, app.pet_behavior().moved_ids.has(id), 1.0)
		continuous = continuous and before.distance_to(pet.position) <= .036 and absf(angle_difference(yaw, pet.rotation.y)) <= .088
		clear = clear and meshes_clear()
		detoured = detoured or absf(pet.position.z) > 3.65
		if doorway and absf(pet.position.z) < .65: aligned = aligned and absf(sin(pet.rotation.y)) < .05
		if pet.position.distance_to(target) < .001:
			arrived = true; break
	check(arrived and continuous, label + " arrives with continuous movement and checked turns")
	check(clear, label + " keeps every visible mesh, nose and tail outside the walls")
	if expect_detour: check(detoured and saw_turn, label + " leaves the narrow corridor before turning its whole body")
	if doorway: check(aligned, label + " stays aligned while passing through the narrow doorway")

func run() -> void:
	app = load("res://scripts/main.gd").new()
	world = LifeWorld.new(); root.add_child(world); world.set_process(false)
	world.house = Node3D.new(); world.add_child(world.house)
	world.furniture = Node3D.new(); world.house.add_child(world.furniture)
	app.world = world; app.household = LifeHousehold.new(); app.sound_enabled = false
	pet = LifePetActor.new(); world.house.add_child(pet); app.pet_actors[id] = pet
	for species: String in ["dog", "cat"]:
		structure([wall("door_left", -2.225, 0, 3.55, .10), wall("door_right", 2.225, 0, 3.55, .10)])
		reset(species, Vector3(0, .16, -2), 0)
		journey(Vector3(0, .16, 2), species + " through a 0.9m doorway", false, true)
		structure([wall("corner", 0, 0, .10, 4)])
		reset(species, Vector3(-3, .16, 0), PI * .5)
		journey(Vector3(3, .16, 0), species + " around a thin wall corner")
		reset(species, Vector3(-3, .16, 0), PI * .5)
		journey(Vector3(-.5, .16, 0), species + " beside a wall without pointing its nose through it")
	structure([wall("corridor_left", -.5, 0, .10, 6), wall("corridor_right", .5, 0, .10, 6)])
	reset("dog", Vector3(0, .16, 2), 0)
	journey(Vector3(0, .16, -2), "Long-coated dog returning along a 0.9m corridor", true)
	print("PET_WALL_HULL %d checks, %d failures" % [checks, failures])
	app.household.free(); app.free(); world.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
