extends SceneTree
## The family brief's motion and building work, checked in the running game:
## ten authored curtain styles that centre on a window; room packs that build a
## carpeted room with a doorway against the house and furnish it; pet-care beats
## posed on both the Lifelet and the pet (stroking, tummy rub, tug-of-war, kibble
## pour, lead clip and walk); front-crawl laps and a hot-tub soak; and getting
## into the car with a child buckled in first.
##
##   JUSTLIFE_DATA_DIR=/tmp/x godot --headless --path . --audio-driver Dummy --script res://tests/test_family_motion.gd

const DT: float = 1.0 / 30.0
const CarEntry = preload("res://scripts/car_entry.gd")

var app: Node
## Where each household member stood when the game started, so the real trip
## at the end leaves from ordinary places.
var start_spots: Dictionary = {}
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("This test needs an isolated JUSTLIFE_DATA_DIR.")
		quit(2); return
	_run.call_deferred()


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	app.household.set_funds(20000)
	for id: String in app.world.actors: start_spots[id] = (app.world.actors[id] as Node3D).global_position
	await _curtains()
	await _room_pack()
	await _pet_motion()
	await _water()
	await _car()
	print("FAMILY_MOTION %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: print("  FAILED: ", failure)
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ curtains

func _curtains() -> void:
	var data: Dictionary = LifeCatalog.get_item("curtains")
	var signatures: Dictionary = {}
	for style: String in data.styles:
		var path: String = LifeCatalogVariants.model_path("curtains", style)
		check(ResourceLoader.exists(path), "Curtain style %s has its own authored model." % style)
		if not ResourceLoader.exists(path): continue
		var scene: Node3D = load(path).instantiate()
		var tint: bool = false
		var vertices: int = 0
		var box := AABB()
		for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			if LifeCatalogVariants.is_tint(mesh.name): tint = true
			for surface: int in range(mesh.mesh.get_surface_count()):
				vertices += (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			box = box.merge(mesh.transform * mesh.mesh.get_aabb()) if box.has_volume() else mesh.transform * mesh.mesh.get_aabb()
		scene.free()
		check(tint, "Curtain style %s carries a Tint fabric surface for its ten colours." % style)
		signatures["%d|%.2f|%.2f" % [vertices, box.size.y, box.position.y]] = style
		check(box.size.x > 2.2 and box.size.x < 2.9 and box.end.y > 2.3, "Curtain style %s spans the window (%.2f wide, top %.2f)." % [style, box.size.x, box.end.y])
	check(signatures.size() == 10, "The ten curtain styles are ten different shapes (%d distinct)." % signatures.size())
	check(LifeCatalogVariants.style_label("03", data) == "Tied back", "The style picker names curtain styles.")
	check(LifeCatalog.passable("curtains"), "Curtains hang flat on the wall and never block a route.")
	# Window snapping on the live house.
	var window: Node3D = null
	for node: Node in app.world.house.get_children():
		if node is Node3D and node.has_meta("window_aperture") and node.visible and (node as Node3D).global_position.y < 3.0:
			window = node; break
	check(window != null, "The starter home has a window to hang curtains at.")
	if window == null: return
	var inward: Vector3 = window.global_basis.z.normalized()
	var along := Vector3(inward.z, 0, -inward.x)
	var near: Vector3 = window.global_position + inward * .5 + along * .9
	near.y = LifeBuildingState.level_y(0)
	var snap: Dictionary = app.world.wall_snap("curtains", near, 1.0)
	check(not snap.is_empty(), "A curtain set slides onto the window's wall.")
	if snap.is_empty(): return
	var centred: Vector3 = app.world.window_snap("curtains", snap.position, float(snap.angle))
	check(absf((centred - window.global_position).dot(along)) < .02, "The curtain set centres on the window (off by %.3f m)." % absf((centred - window.global_position).dot(along)))
	check(absf((Vector3(snap.position) - window.global_position).dot(along)) > .5, "Window snapping really moved it from where it was pointed.")
	app.set_build_mode(true)
	await frames(2)
	var before: int = app.world.items.size()
	app.on_placement("curtains", centred, float(snap.angle), "03", "")
	await frames(2)
	var hung: Array = app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == "curtains")
	check(app.world.items.size() == before + 1 and not hung.is_empty(), "A styled curtain set is really placed and built (it was dropped before styles had models).")
	if not hung.is_empty():
		check(str((hung[-1].variant as Dictionary).get("style", "")) == "03", "The placed set keeps the chosen style.")


# ----------------------------------------------------------------- room pack

func _room_pack() -> void:
	if app.mode != "build": app.set_build_mode(true)
	await frames(2)
	var state: Dictionary = app.build_transactions.current().state
	var house := Rect2()
	for wall: Dictionary in state.walls:
		house = LifeBuildingState.rect(wall) if not house.has_area() else house.merge(LifeBuildingState.rect(wall))
	var funds: int = int(app.sim.funds)
	var result: Dictionary = {}
	var tried: Array = []
	for offset: Vector2 in [Vector2(2.25 + .35, 0), Vector2(2.25 + .35, 2.0), Vector2(2.25 + .35, -2.0), Vector2(2.25 + .35, 3.0)]:
		var click := Vector3(house.end.x + offset.x, LifeBuildingState.level_y(0), house.get_center().y + offset.y)
		tried.append(click)
		result = app._place_room_pack("nursery_room_pack", click, 0.0)
		if not result.is_empty(): break
	check(not result.is_empty(), "A nursery room pack builds beside the house (tried %s)." % str(tried))
	if result.is_empty(): return
	var area: Rect2 = result.area
	state = app.build_transactions.current().state
	check(absf(area.position.x - house.end.x) < .1, "The pack snapped onto the house's east wall (%.2f vs %.2f)." % [area.position.x, house.end.x])
	var carpet: Array = state.floors.filter(func(floor: Dictionary) -> bool: return str(floor.material) == LifeCatalog.room_pack_carpet("nursery_room_pack") and LifeBuildingState.rect(floor).is_equal_approx(area))
	check(carpet.size() == 1, "The room is carpeted with its own floor record.")
	var door: String = str(result.door)
	check(door == "west", "The doorway opens through the shared wall into the house (%s)." % door)
	for side: String in LifeBuildingEdits.ROOM_PACK_SIDES:
		var edge: Dictionary = LifeBuildingEdits._pack_edge(area, side)
		var open: Array = LifeBuildingEdits._uncovered_spans(state, edge, 0)
		if side == door:
			check(open.size() == 1 and absf((open[0] as Vector2).y - (open[0] as Vector2).x - 1.06) < .05, "The %s wall has one standard 1.06 m doorway (%s)." % [side, str(open)])
		else:
			check(open.is_empty(), "The %s wall is closed (%s)." % [side, str(open)])
	var west_walls: int = 0
	for wall: Dictionary in state.walls:
		if float(wall.w) < float(wall.d) and absf(float(wall.x) - area.position.x) < .08: west_walls += 1
	check(west_walls >= 2, "The house wall was reused and cut, not doubled (%d panels on that line)." % west_walls)
	check(int(result.placed) >= 8, "The nursery is furnished (%d placed, skipped %s)." % [int(result.placed), str(result.skipped)])
	check(funds - int(app.sim.funds) == 2000, "The pack costs ℒ2000 all in (paid %d: structure %d + furnishings %d)." % [funds - int(app.sim.funds), int(result.structure_cost), int(result.furnishing_cost)])
	var kinds: Array = app.world.items.map(func(item: Dictionary) -> String: return str(item.kind))
	for kind: String in ["cot", "changing_table", "rocking_chair", "baby_mat"]:
		check(kinds.has(kind), "The nursery pack placed a %s." % kind)
	var inside: Array = app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == "cot" and area.grow(-.05).has_point(Vector2(item.node.global_position.x, item.node.global_position.z)))
	check(not inside.is_empty(), "The cot stands inside the new room.")
	var edge: Dictionary = LifeBuildingEdits._pack_edge(area, door)
	var mid: float = float(result.door_at) if not is_nan(float(result.door_at)) else (float(edge.low) + float(edge.high)) * .5
	var doorway: Vector2 = Vector2(mid, float(edge.line)) if edge.horizontal else Vector2(float(edge.line), mid)
	var step_in: Vector2 = doorway + (area.get_center() - doorway).normalized() * .7
	var route: Dictionary = app.world.lot_navigation.route(LifeLotNavigation.floor_location(0, Vector3(step_in.x, .16, step_in.y)), LifeLotNavigation.floor_location(0, app.world.lot_exit_position()))
	check(bool(route.ok), "The new room is reachable through its doorway (%s)." % str(route.get("error", "")))
	app.undo_build()
	await frames(1)
	app.undo_build()
	await frames(1)
	state = app.build_transactions.current().state
	check(int(app.sim.funds) == funds, "Undoing the pack refunds all ℒ2000 (%d vs %d)." % [int(app.sim.funds), funds])
	check(state.floors.filter(func(floor: Dictionary) -> bool: return LifeBuildingState.rect(floor).is_equal_approx(area)).is_empty(), "Undoing the pack removes its room.")
	app.set_build_mode(false)
	await frames(2)


# ----------------------------------------------------------------- pet care

func _palm(actor: LifeActor) -> Vector3:
	return (actor._joints["Forearm_R"] as Node3D).to_global(actor._palm_offset("R"))


func _pet_motion() -> void:
	app.adoption_flow.show_phone(); await frames(3)
	app.pet_shop.show_shop(); await frames(3)
	app.pet_shop.show_species(); await frames(3)
	app.pet_shop.set_species("dog"); await frames(2)
	app.pet_shop.confirm_pet(); await frames(6)
	app.close_overlay()
	var pets: Array = app.household.pets.get("pets", [])
	check(not pets.is_empty() and str(pets[-1].species) == "dog", "The household has a dog to care for.")
	if pets.is_empty(): return
	var pet_id: String = str(pets[-1].id)
	var pet: LifePetActor = app.pet_actors.get(pet_id)
	var member: String = app.household.selected_id()
	var person: LifeActor = app.world.actors.get(member)
	check(is_instance_valid(pet) and is_instance_valid(person), "Both bodies are in the world.")
	if not is_instance_valid(pet) or not is_instance_valid(person): return
	app.set_process(false)
	app.household.set_speed(1)
	pet_arrive(pet)
	var garden := Vector3(2.0, .16, 7.0)
	person.global_position = garden
	pet.global_position = garden + Vector3(0, 0, .8)
	var motion = app.care_motion()

	# Stroking the coat.
	# Lambdas capture locals by value, so every tally lives in this dictionary.
	var seen: Dictionary = {"nearest": INF}
	var strokes: Array[float] = []
	_beat(motion, member, pet, person, "pet_pet", 0.3, 90, func(i: int) -> void:
		var palm: Vector3 = _palm(person)
		if i > 40:
			seen.nearest = minf(seen.nearest, palm.distance_to(pet.back_point()))
			strokes.append(palm.dot(pet.global_basis.z)))
	check(motion.holds(pet_id) and pet.interaction == "pet_pet", "The dog stays for the stroke and knows it is being petted.")
	check(seen.nearest < .22, "The hand reaches the dog's back (%.2f m)." % seen.nearest)
	check(not strokes.is_empty() and strokes.max() - strokes.min() > .12, "The hand runs along the coat, head to tail (%.2f m)." % (strokes.max() - strokes.min() if not strokes.is_empty() else 0.0))
	check(absf(pet.global_position.distance_to(person.global_position) - .62) < .15, "The dog comes to arm's length (%.2f m)." % pet.global_position.distance_to(person.global_position))
	check(pet._model.rotation.x < -.25, "The dog sits up to be stroked (pitch %.2f)." % pet._model.rotation.x)

	# Tummy rub: the dog rolls onto its back and kicks.
	var kicks: Array[float] = []
	seen.nearest = INF
	_beat(motion, member, pet, person, "pet_tummy_rub", 0.3, 90, func(i: int) -> void:
		if i > 45:
			seen.nearest = minf(seen.nearest, _palm(person).distance_to(pet.belly_point()))
			kicks.append(pet._legs[2].rotation.x))
	check(pet._model.rotation.z > 2.4, "The dog rolls onto its back (roll %.2f)." % pet._model.rotation.z)
	check(seen.nearest < .25, "The hand circles on the tummy (%.2f m)." % seen.nearest)
	check(not kicks.is_empty() and kicks.max() - kicks.min() > .5, "A back leg kicks (%.2f rad swing)." % (kicks.max() - kicks.min() if not kicks.is_empty() else 0.0))

	# Tug-of-war: a rope from both hands to the dog's mouth, the dog in a bow.
	seen.rope = false
	_beat(motion, member, pet, person, "pet_tug", 0.3, 60, func(i: int) -> void:
		if i == 59 and is_instance_valid(person._care_props):
			var rope: MeshInstance3D = person._care_props._rope
			var mouth: Vector3 = pet.mouth_point()
			var top: Vector3 = rope.global_transform * Vector3(0, .5, 0)
			var bottom: Vector3 = rope.global_transform * Vector3(0, -.5, 0)
			seen.rope = rope.visible and minf(top.distance_to(mouth), bottom.distance_to(mouth)) < .05)
	check(seen.rope, "A rope toy runs from the Lifelet's hands to the dog's mouth.")
	check(pet._model.rotation.x > .15, "The dog drops into a play bow (%.2f)." % pet._model.rotation.x)
	check(person.visual.rotation.x < -.05, "The Lifelet leans back against the pull (%.2f)." % person.visual.rotation.x)

	# Feeding: bag lifted and tipped, kibble falling into the bowl.
	app.world.add_item({"id": "motion_bowl", "kind": "pet_bowl", "x": garden.x + .9, "z": garden.z + .2, "rotation": 0})
	seen.bag = false
	seen.kibble = 0
	_beat(motion, member, pet, person, "pet_feed", 0.3, 110, func(i: int) -> void:
		if is_instance_valid(person._care_props):
			seen.bag = seen.bag or person._care_props._bag.visible
			var falling: int = 0
			for bit: MeshInstance3D in person._care_props._kibble: falling += 1 if bit.visible else 0
			seen.kibble = maxi(seen.kibble, falling))
	check(seen.bag, "The Lifelet lifts a kibble bag.")
	check(seen.kibble >= 4, "Kibble pours from the tipped bag (%d bits in the air)." % seen.kibble)
	var bowl: Dictionary = app._find_item("motion_bowl")
	if not bowl.is_empty():
		check(pet.global_position.distance_to(bowl.node.global_position) < .6, "The dog comes to the bowl (%.2f m)." % pet.global_position.distance_to(bowl.node.global_position))

	# Walk: kneel and clip the lead on, then walk a loop together.
	person.global_position = garden
	seen.leash = false
	_beat(motion, member, pet, person, "pet_walk", 0.02, 60, func(i: int) -> void:
		if is_instance_valid(person._care_props) and person._care_props._leash.visible: seen.leash = true)
	check(seen.leash, "The lead is clipped to the collar.")
	var walked_from: Vector3 = person.global_position
	seen.moved = 0.0
	seen.phase = ""
	var dog_moving: bool = false
	for progress: float in [.25, .4, .55]:
		_beat(motion, member, pet, person, "pet_walk", progress, 20, func(i: int) -> void:
			seen.phase = str(person._activity_anchor.get("care_phase", ""))
			seen.moved = maxf(seen.moved, Vector3(person._activity_anchor.get("position", walked_from)).distance_to(walked_from)), false)
		dog_moving = dog_moving or motion.present_pets(DT).has(pet_id)
	check(seen.phase == "walk", "After the clip the pair walk (%s)." % seen.phase)
	check(seen.moved > .8, "The walk really moves the Lifelet round a loop (%.2f m)." % seen.moved)
	check(dog_moving, "The dog walks along on the lead.")
	app.sim.action_queue.clear()
	motion.present_pets(DT)
	check(pet.interaction.is_empty() and not motion.holds(pet_id), "The dog is released when the beat ends.")
	app.household.set_speed(0)
	app.set_process(true)


func pet_arrive(pet: LifePetActor) -> void:
	app.pet_arrivals.erase(pet.pet_id)
	app.pet_errands.erase(pet.pet_id)


## Run one care beat for `count` frames with the action really at the front of
## the Lifelet's queue, as the controller and both bodies see it every frame.
func _beat(motion, member: String, pet: LifePetActor, person: LifeActor, id: String, progress: float, count: int, each: Callable, fresh: bool = true) -> void:
	if fresh:
		app.sim.action_queue.clear()
		motion.sessions.erase(member)
	if app.sim.action_queue.is_empty():
		app.sim.action_queue.append({"id": id, "target_id": pet.pet_id, "target_kind": "pet", "phase": "active", "progress": progress, "elapsed": 0.0, "duration": 30.0})
	app.sim.action_queue[0]["progress"] = progress
	for i: int in count:
		var care: Dictionary = motion.anchor(member, app.sim.action_queue[0], id, DT)
		person.set_activity_anchor(care.position, care.yaw, "standing", id, care)
		person.animate(DT, 1.0, false, id)
		var walking: Dictionary = motion.present_pets(DT)
		pet.animate(DT, walking.has(pet.pet_id), 1.0)
		each.call(i)


# -------------------------------------------------------------------- water

func _place(kind: String, spots: Array) -> Dictionary:
	for spot: Vector2 in spots:
		var at := Vector3(spot.x, LifeBuildingState.level_y(0), spot.y)
		if app.world.can_place(kind, at, 0.0):
			var id: String = "motion_%s" % kind
			app.world.add_item({"id": id, "kind": kind, "x": at.x, "z": at.z, "rotation": 0})
			return app._find_item(id)
	return {}


func _water() -> void:
	var person: LifeActor = app.world.actors.get(app.household.selected_id())
	var pool: Dictionary = _place("pool", [Vector2(-12, 4), Vector2(12, 4), Vector2(-12, -8), Vector2(12, -8), Vector2(-13, 0)])
	check(not pool.is_empty(), "A pool fits in the garden for the swim check.")
	if not pool.is_empty():
		var anchor: Dictionary = app.world.activity_anchor(pool, LifeOutdoorActs.ACTION_ID, {})
		check(str(anchor.get("kind", "")) == "swim" and Vector3(anchor.swim_from).distance_to(anchor.swim_to) > 1.0, "A swimmer is anchored to laps along the pool, not its edge.")
		var water_y: float = Vector3(anchor.swim_from).y
		var arms: Array[Quaternion] = []
		var heads: Array[float] = []
		var along: Array[Vector3] = []
		for i: int in 150:
			person.set_activity_anchor(anchor.position, anchor.yaw, anchor.kind, LifeOutdoorActs.ACTION_ID, anchor)
			person.animate(DT, 1.0, false, LifeOutdoorActs.ACTION_ID)
			if i % 15 == 0: arms.append((person._joints["Arm_R"] as Node3D).quaternion)
			if i > 60:
				heads.append((person._joints["Head"] as Node3D).global_position.y)
				along.append((person._joints["Head"] as Node3D).global_position)
		check(person.visual.rotation.x > 1.2, "The swimmer lies face down along the water (%.2f rad)." % person.visual.rotation.x)
		check(absf(heads.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / heads.size() - water_y) < .35, "The swimmer's head stays at the waterline.")
		var spread: float = 0.0
		for q: Quaternion in arms: spread = maxf(spread, q.angle_to(arms[0]))
		check(spread > 1.0, "The arms turn over in a stroke (%.2f rad)." % spread)
		var travel: float = 0.0
		for point: Vector3 in along: travel = maxf(travel, point.distance_to(along[0]))
		check(travel > .8, "The swimmer travels along the lap (%.2f m)." % travel)
	var tub: Dictionary = _place("hot_tub", [Vector2(-9, 7), Vector2(9, 7), Vector2(-15, 6), Vector2(15, 6), Vector2(-15, -4)])
	check(not tub.is_empty(), "A hot tub fits in the garden for the soak check.")
	if not tub.is_empty():
		var seat: Dictionary = app.world.activity_anchor(tub, LifeOutdoorActs.ACTION_ID, {})
		for i: int in 60:
			person.set_activity_anchor(seat.position, seat.yaw, seat.kind, LifeOutdoorActs.ACTION_ID, seat)
			person.animate(DT, 1.0, false, LifeOutdoorActs.ACTION_ID)
		check(str(seat.kind) == "seat" and person._sit_amount > .8, "The soaker sits down in the tub (sit %.2f)." % person._sit_amount)
		var hip: float = (person._joints["Leg_L"] as Node3D).global_position.y
		check(hip < tub.node.global_position.y + .72, "The soaker's hips are under the water line (%.2f)." % (hip - tub.node.global_position.y))
	person.clear_activity_anchor()


# ---------------------------------------------------------------------- car

func _car() -> void:
	var members: Array = app.household.members
	var adult: String = str(members[0].id)
	# A real child body for the car seat, built the way the game spawns one.
	var profile: Dictionary = (members[0].sim.character as Dictionary).duplicate(true)
	profile["age_stage"] = "child"; profile["life_stage"] = "minor"; profile["low_detail"] = true
	var kid := LifeActor.new(); kid.name = "MotionChild"
	app.world.house.add_child(kid)
	kid.configure(profile)
	var child: String = "motion_child"
	var party: Array = [{"id": adult, "stage": "adult"}, {"id": child, "stage": "child"}]
	var steps: Array = CarEntry.plan(party)
	check(str(steps[0].kind) == ("buckle" if not child.is_empty() else "board"), "A child is buckled in before the grown-ups get in.")
	check(str(steps[-1].kind) == "board" and str(steps[-1].door) == "front", "The grown-up then gets in the front.")
	var car: Node3D = load("res://assets/models/juniper_car.glb").instantiate()
	app.world.house.add_child(car)
	car.position = Vector3(0, 0, 10.25); car.rotation.y = PI * .5
	var entry = CarEntry.new(car, party)
	check(entry.doors.size() == 2, "The car gets its two kerb-side doors.")
	var bodies: Dictionary = {}
	for member: Dictionary in party:
		var body: LifeActor = kid if str(member.id) == child else app.world.actors.get(str(member.id))
		body.visible = true
		body.global_position = Vector3(float(bodies.size()) - .5, .16, 7.5)
		bodies[str(member.id)] = body
	var rear_open: float = 0.0
	var front_open: float = 0.0
	var buckling: bool = false
	var child_seated: float = INF
	var done: bool = false
	for i: int in int(30.0 / DT):
		done = entry.tick(DT, bodies)
		rear_open = maxf(rear_open, entry.door_amount("rear"))
		front_open = maxf(front_open, entry.door_amount("front"))
		var beat: Dictionary = entry.current()
		if not beat.is_empty() and str(beat.part) == "buckle":
			buckling = buckling or bodies[adult]._motion_action == "car_buckle"
			if not child.is_empty(): child_seated = minf(child_seated, bodies[child].global_position.distance_to(entry.seat_point("rear")))
		if done: break
	check(done and entry.total < 15.0, "Everyone is in within the beats (%.1f s)." % entry.total)
	check(front_open > .95, "The front door swings open for the driver.")
	check(entry.door_amount("front") < .01 and entry.door_amount("rear") < .01, "Both doors are shut again.")
	var hidden: bool = true
	for id: String in bodies: hidden = hidden and not (bodies[id] as Node3D).visible
	check(hidden, "The party is inside the car.")
	if not child.is_empty():
		check(rear_open > .95, "The rear door opens for the child's seat.")
		check(child_seated < .12, "The child is settled into the rear seat (%.2f m)." % child_seated)
		check(buckling, "The grown-up leans in and fastens the harness.")
	car.queue_free()
	kid.queue_free()
	bodies.erase(child)
	for id: String in bodies: (bodies[id] as Node3D).visible = true
	# The real trip: walk to the household's own car when one is parked, doors,
	# then drive away. Without a parked car the shared Juniper stand-in is used.
	var destination: String = ""
	for place: String in LifeNeighborhood.travel_ids():
		if LifeNeighborhood.is_venue(place) and place != app.current_venue: destination = place; break
	check(not destination.is_empty(), "There is a venue to drive to.")
	if destination.is_empty(): return
	for id: String in start_spots:
		var body: Node3D = app.world.actors.get(id)
		if is_instance_valid(body): body.global_position = start_spots[id]; body.visible = true
	# Park an estate on the lot so Drive… uses it rather than the shared car.
	if app.mode != "build": app.set_build_mode(true)
	await frames(2)
	var parked_at := Vector3.INF
	for radius: int in range(0, 40):
		for x: int in range(-radius, radius + 1):
			for z: int in range(-radius, radius + 1):
				if maxi(abs(x), abs(z)) != radius: continue
				var at := Vector3(float(x) * .5, .16, float(z) * .5)
				if app.world.can_place("car", at, 90.0, "estate", "medium"):
					parked_at = at; break
			if parked_at.is_finite(): break
		if parked_at.is_finite(): break
	check(parked_at.is_finite(), "There is room on the lot for an estate car.")
	if not parked_at.is_finite(): return
	app.on_placement("car", parked_at, 90.0, "estate", "medium")
	await frames(3)
	app.set_build_mode(false)
	await frames(2)
	var parked: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "car": parked = item; break
	check(not parked.is_empty(), "An estate car is parked on the lot.")
	if parked.is_empty(): return
	app.world.rebuild_navigation()
	app.household.set_speed(1)
	app.residents.preferred_vehicle_id = str(parked.get("id", ""))
	var started: bool = app.residents.begin_trip(destination, [adult])
	check(started, "A trip to %s begins (%s)." % [destination, app.notice_label.text if is_instance_valid(app.notice_label) else ""])
	if not started: return
	check(bool(app.residents.trip.get("own_car", false)), "Drive… boards the household's own car.")
	check(app.residents.uses_household_car() and str(app.residents.trip_vehicle.get("style", "")) == "estate",
		"The trip remembers the parked estate's model.")
	if is_instance_valid(app.residents.car) and is_instance_valid(parked.get("node")):
		check(app.residents.car.global_position.distance_to((parked.node as Node3D).global_position) < .05,
			"The trip car sits on the parked car's own spot.")
		check(not (parked.node as Node3D).visible, "The parked body is hidden while the trip car boards.")
	var saw_door: bool = false
	var departed: bool = false
	for i: int in int(90.0 / DT):
		app.residents.tick_trip(DT)
		if is_instance_valid(app.residents.car) and app.residents.car_entry != null:
			saw_door = saw_door or app.residents.car_entry.door_amount("front") > .9
		if str(app.residents.trip.get("phase", "")) in ["departure", "arrival"] or app.residents.trip.is_empty():
			departed = true; break
		if i % 30 == 0: await process_frame
	check(saw_door, "On a real trip the driver opens the car door at the kerb.")
	check(departed, "Once everyone is in, the car drives off.")
