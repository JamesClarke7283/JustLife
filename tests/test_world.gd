extends SceneTree
## Isolated integration check: godot --headless --path <project> --script tests/test_world.gd
## Does not load a household save or invoke the main UI. Avoid running in parallel with
## the MCP-enabled project: copy scripts/tests and asset imports into a project with no autoload.

const World = preload("res://scripts/world.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Simulation = preload("res://scripts/life_sim.gd")
const START = Vector3(-0.7, 0.16, 2.8)
var failures: int = 0
var assertions: int = 0
var warnings: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(detail)

func _run() -> void:
	var world: Node3D = World.new()
	root.add_child(world)
	await process_frame
	var sim: Node = Simulation.new()
	sim.new_household({})
	for lot: int in [0, 1, 2]:
		var layout: Array = Catalog.starter_layout(lot)
		world.create_home(layout)
		await process_frame
		check(world.items.size() == layout.size(), "Lot %d: every starter furnishing must load; loaded %d/%d." % [lot, world.items.size(), layout.size()])
		var interactables: int = 0
		for item: Dictionary in world.items:
			if sim.get_actions_for(str(item.kind)).is_empty():
				continue
			interactables += 1
			var destination: Vector3 = world.approach(item)
			var path: PackedVector3Array = world.path_to(START, destination)
			var label: String = "Lot %d %s %s at %s -> %s" % [lot, item.id, item.kind, item.node.position, destination]
			check(not path.is_empty(), label + " must have a route from the initial player position.")
			if path.is_empty():
				continue
			check(path[0].distance_to(START) <= 0.4, label + " route must start near the player, without teleportation.")
			check(path[-1].distance_to(destination) <= 0.2, label + " route must reach its interaction point.")
			check(not _path_crosses_wall(world, path), label + " route must avoid actual wall geometry.")
			check(_first_furniture_crossing(world, path).is_empty(), label + " route crosses furniture: " + _first_furniture_crossing(world, path))
			check(not _wall_between(world, destination, item.node.position), label + " interaction point must be on the usable side of the room wall.")
			var intended: Vector3 = item.node.to_global(Vector3(0, 0, item.size.y * 0.5 + 0.55))
			intended.y = 0.16
			if intended.distance_to(destination) > 0.65:
				warnings.append(label + " approach displaced %.2fm from the intended front; inspect furniture clearance." % intended.distance_to(destination))
			print("ROUTE ", label, " points=", path.size())
		for neighbor: Dictionary in [{"id": "maya", "position": Vector3(7.0, 0.16, 4.1)}, {"id": "leo", "position": Vector3(-7.0, 0.16, 5.4)}]:
			var route: PackedVector3Array = world.path_to(START, neighbor.position)
			check(not route.is_empty(), "Lot %d must route through the front entrance to neighbor %s at %s." % [lot, neighbor.id, neighbor.position])
			if not route.is_empty():
				check(route[-1].distance_to(neighbor.position) < 0.2, "Neighbor path must reach the requested conversational distance.")
				check(not _path_crosses_wall(world, route), "Lot %d neighbor %s route must not clip the front entrance walls." % [lot, neighbor.id])
				check(_first_furniture_crossing(world, route).is_empty(), "Neighbor route must not pass through a furnishing.")
		print("Lot ", lot, ": checked ", interactables, " interactables and 2 neighbors.")
	# Every authored starter furnishing must also be one a player can actually
	# click. A furnishing the lot itself places inside a neighbour's footprint
	# still passes can_place (that rule is for new placements) and still routes,
	# but its own pick body is buried: iteration 64 authored the kitchen rubbish
	# bin at (-1.35, -4.55), inside both the sink and the counter, and no ray
	# aimed at it could ever return it.
	await _check_starter_furnishings_are_pickable(world, sim)
	_test_placement(world)
	_test_memorial_exhaustion(world)
	# Doorway blocking is a usability diagnostic, not a claim that build mode currently
	# promises to preserve every route after arbitrary remodeling.
	world.create_home([])
	await process_frame
	var blocks_door: bool = world.can_place("sofa", Vector3(0, 0.16, 4.25), 0)
	if blocks_door:
		world.add_item({"id": "entrance_sofa", "kind": "sofa", "x": 0.0, "z": 4.25, "rotation": 0.0})
		if world.path_to(START, Vector3(0, 0.16, 6.2)).is_empty():
			warnings.append("Build mode accepts a sofa at (0, 4.25), rotation 0, which blocks the only front exit. Consider protecting an entry clearance zone.")
	for warning: String in warnings:
		print("USABILITY: ", warning)
	world.queue_free()
	sim.free()
	await process_frame
	print("World: %d assertions, %d failures, %d usability observations." % [assertions, failures, warnings.size()])
	quit(0 if failures == 0 else 1)

func _first_furniture_crossing(world: Node3D, path: PackedVector3Array) -> String:
	# Inspect physical furnishing rectangles directly instead of consulting AStar's
	# occupancy flags. Dense segment samples catch paths that clip a rotated corner.
	for i: int in range(1, path.size()):
		var steps: int = maxi(1, int(ceil(path[i-1].distance_to(path[i]) / 0.04)))
		for step: int in range(steps + 1):
			var point: Vector3 = path[i-1].lerp(path[i], float(step) / steps)
			for item: Dictionary in world.items:
				if item.kind in ["rug", "painting"]:
					continue
				var local: Vector3 = item.node.to_local(point)
				if absf(local.x) < item.size.x * 0.5 and absf(local.z) < item.size.y * 0.5:
					return "%s at %s" % [item.id, point]
	return ""

func _path_crosses_wall(world: Node3D, path: PackedVector3Array) -> bool:
	for i: int in range(1, path.size()):
		if _wall_between(world, path[i-1], path[i]):
			print("WALL_CROSSING segment ", path[i-1], " -> ", path[i])
			return true
	return false

func _wall_between(world: Node3D, from: Vector3, to: Vector3) -> bool:
	# Read actual long, thin wall meshes made by create_home; this is independent of
	# the AStar grid's hard-coded wall mask, so a free cell across a wall cannot pass.
	var steps: int = maxi(1, int(ceil(from.distance_to(to) / 0.025)))
	for child: Node in world.construction.find_children("*", "MeshInstance3D", true, false):
		if not child is MeshInstance3D or not child.mesh is BoxMesh:
			continue
		var dimensions: Vector3 = child.mesh.size
		var wall_like: bool = dimensions.y > 0.5 and ((dimensions.x < 0.2 and dimensions.z > 1.5) or (dimensions.z < 0.2 and dimensions.x > 1.5))
		if not wall_like:
			continue
		for i: int in range(steps + 1):
			var point: Vector3 = child.to_local(from.lerp(to, float(i) / steps))
			if absf(point.x) <= dimensions.x * 0.5 and absf(point.z) <= dimensions.z * 0.5:
				return true
	return false

## Loads every starter lot again and drops rays straight down onto each
## furnishing the player can act on. The first pick body a downward ray meets is
## the one the player would click, so a furnishing that no sample of its own
## footprint returns is buried under a neighbour and its menu is unreachable.
## The ray is deliberately vertical and uses the world's own pick layer, so this
## measures authored geometry rather than one camera angle. Iteration 64 placed
## the kitchen rubbish bin at (-1.35, -4.55), inside both the sink and the
## counter: the counter's taller body took every ray and "Empty the bin" could
## never be opened.
func _check_starter_furnishings_are_pickable(world: Node3D, simulation: Node) -> void:
	world.live_enabled = true
	for lot: int in [0, 1, 2, 3]:
		world.create_home(Catalog.starter_layout(lot))
		# The previous lot frees itself on the next frame; rays taken before that
		# would meet two houses at once.
		await process_frame
		for item: Dictionary in world.items:
			var kind: String = str(item.kind)
			if Catalog.passable(kind) or simulation.get_actions_for(kind).is_empty():
				continue
			var size: Vector2 = Catalog.ITEMS[kind].size
			var basis: Basis = Basis(Vector3.UP, deg_to_rad(float(item.rotation)))
			var half: Vector2 = Vector2(absf((basis * Vector3(size.x * 0.5, 0, 0)).x) + absf((basis * Vector3(0, 0, size.y * 0.5)).x),
				absf((basis * Vector3(size.x * 0.5, 0, 0)).z) + absf((basis * Vector3(0, 0, size.y * 0.5)).z))
			var layer: int = World.PICK_GROUND if world.item_level(item) == 0 else World.PICK_UPPER
			var reached: int = 0
			var sampled: int = 0
			for ix: int in range(5):
				for iz: int in range(5):
					var x: float = float(item.node.position.x) + (float(ix) / 4.0 - 0.5) * 2.0 * half.x
					var z: float = float(item.node.position.z) + (float(iz) / 4.0 - 0.5) * 2.0 * half.y
					var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(x, 8.0, z), Vector3(x, -1.0, z), layer)
					var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
					sampled += 1
					if not hit.is_empty() and str(hit.collider.get_meta("item_id", "")) == str(item.id):
						reached += 1
			check(reached > 0, "Lot %d: no downward ray of %d on %s (%s) reaches it, so its menu is buried and unreachable." % [lot, sampled, item.id, kind])
			print("PICK lot=", lot, " ", item.id, " ", kind, " ", reached, "/", sampled)
	world.live_enabled = false

func _test_placement(world: Node3D) -> void:
	world.create_home([])
	check(world.can_place("plant", Vector3(-2, 0.16, 1), 0), "A furnishing wholly inside an empty room should be placeable.")
	check(not world.can_place("plant", Vector3(-5.8, 0.16, 1), 0), "Furniture crossing the outer left wall should be rejected.")
	check(not world.can_place("plant", Vector3(1, 0.16, 2), 0), "Furniture overlapping the bedroom divider should be rejected.")
	check(not world.can_place("chair", Vector3(2, 0.16, -1.15), 0), "Furniture overlapping the bathroom divider should be rejected.")
	check(world.can_place("bed", Vector3(4.8, 0.16, 2.5), 0), "An unrotated bed fitting against the right wall should be accepted.")
	check(not world.can_place("bed", Vector3(4.8, 0.16, 2.5), 90), "Rotating the same bed across the wall should be rejected.")
	world.add_item({"id": "test_sofa", "kind": "sofa", "x": -2.0, "z": 1.0, "rotation": 90.0})
	check(not world.can_place("plant", Vector3(-2, 0.16, 1), 0), "Placing a solid object inside existing furniture should be rejected.")
	check(not world.can_place("chair", Vector3(-2, 0.16, 2.35), 0), "Collision must use the existing furnishing's rotation.")
	check(world.can_place("plant", Vector3(-4, 0.16, 1), 0), "A clearly separated furnishing should still be accepted.")
	check(world.can_place("rug", Vector3(-2, 0.16, 1), 0), "Floor rugs should be allowed beneath furniture.")
	var removed: Dictionary = world.remove_item("test_sofa")
	check(not removed.is_empty() and world.can_place("plant", Vector3(-2, 0.16, 1), 0), "Removing an item should free its footprint for replacement.")

func _test_memorial_exhaustion(world: Node3D) -> void:
	world.create_home([])
	check(world.ensure_memorial("remembered"), "A remembrance stone is placed when the lot has room.")
	var first_layout: Array = world.serialize_items()
	check(world.ensure_memorial("remembered") and world.serialize_items() == first_layout, "Requesting an existing remembrance stone does not duplicate it.")
	# Purchased stones share these positions too. Fill available memorial places
	# until the public placement method reports exhaustion, then verify that the
	# final attempt preserves a loadable lot instead of adding its last rejected
	# fallback outside the lot.
	var exhausted: bool = false
	for index: int in range(64):
		var before: Array = world.serialize_items()
		if not world.ensure_memorial("capacity_%d" % index):
			exhausted = true
			check(world.serialize_items() == before, "An exhausted memorial placement leaves the lot unchanged.")
			break
		var layout_error: String = world.validate_home_layout(world.serialize_items())
		check(layout_error.is_empty(), "Every remembrance stone keeps the lot loadable: " + layout_error)
		if not layout_error.is_empty():
			break
	check(exhausted, "A full set of memorial places is reported without creating an invalid fallback.")
	var crowded: bool = false
	var spacing: float = float(Catalog.ITEMS.memorial.size.x) + 0.18
	for first: int in range(world.items.size()):
		for second: int in range(first + 1, world.items.size()):
			var a: Vector3 = world.items[first].node.position
			var b: Vector3 = world.items[second].node.position
			if Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) < spacing:
				crowded = true
	check(not crowded, "Exhausting memorial places never stacks stones on each other.")
