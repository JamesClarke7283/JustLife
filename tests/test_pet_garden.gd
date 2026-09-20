extends SceneTree
## The garden, the dog house and the pet furnishings, through the public path.
##
## The garden was the strip of lawn the old lot allowed. Two defects made pet
## ownership unworkable: no furnishing could be bought anywhere except on a built
## floor slab, so the dog kennel could not go in the garden at all, and the lot
## was too small for a kennel plus a garden bed plus a walk between them.

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(v: bool, m: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if v else "FAIL ", m)
	if not v:
		failures.append(m)


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.selected_lot = 0
	app.start_household()
	await frames(2)
	app.set_process(false)
	app.world.set_process(false)

	print("LOT=", LifeBuildingState.LOT, " cells=", LifeBuildingState.cell_range())
	# A point well outside the old lot but inside the new one.
	for at: Vector3 in [Vector3(-10.5, .16, 0), Vector3(10.5, .16, 0), Vector3(0, .16, -7.5), Vector3(0, .16, 7.5), Vector3(-8.5, .16, 6.5)]:
		var clear: bool = app.world.lot_navigation.point_clear(0, at)
		var free: bool = not app.world.navigation.is_point_solid(Vector2i(roundi(at.x * 4), roundi(at.z * 4)))
		check(clear and free, "The garden reaches %s (graph=%s grid=%s)." % [at, clear, free])

	# The old edge is still there, and the new one is walkable to the very rim.
	var reach: int = 0
	for x: float in [-11.0, -10.0, 10.0, 11.0]:
		for z: float in [-8.0, -6.0, 0.0, 6.0, 8.0]:
			if app.world.lot_navigation.point_clear(0, Vector3(x, .16, z)):
				reach += 1
	check(reach >= 16, "Most of the enlarged rim is walkable (%d of 20)." % reach)

	# The kennel must be placeable in the garden, on the ground, outside the house.
	var kennel_ok: int = 0
	for at: Vector3 in [Vector3(-6.0, .16, 7.0), Vector3(6.0, .16, 7.0), Vector3(-9.0, .16, 2.0), Vector3(9.0, .16, 2.0)]:
		if app.world.can_place("kennel", at, 0.0):
			kennel_ok += 1
	check(kennel_ok >= 3, "The dog kennel can be placed in the garden (%d of 4 spots)." % kennel_ok)
	check(not app.world.can_place("kennel", Vector3(-20, .16, 0), 0.0), "The kennel is refused outside the lot.")

	# The new pet furnishings are all placeable somewhere legal too.
	for kind: String in ["pet_bed_cat", "pet_bed_dog", "pet_toy_cat", "pet_toy_dog", "cat_toy_box", "dog_toy_box"]:
		var placed: bool = false
		for x: float in [-4.0, -2.0, 0.0, 2.0, 4.0]:
			for z: float in [-3.0, 0.0, 2.5]:
				if app.world.can_place(kind, Vector3(x, .16, z), 0.0):
					placed = true
					break
			if placed:
				break
		var info: Dictionary = LifeCatalog.ITEMS[kind]
		check(placed, "%s can be placed in the home." % str(info.label))
		check(int(info.price) > 0, "%s has a price (ℒ%d)." % [str(info.label), int(info.price)])

	check(int(LifeCatalog.ITEMS["cat_toy_box"].price) == 50 and int(LifeCatalog.ITEMS["dog_toy_box"].price) == 50,
		"Both toy boxes cost ℒ50.")
	check(str(LifeCatalog.ITEMS["cat_toy_box"].label) == "Cat Toy Box" and str(LifeCatalog.ITEMS["dog_toy_box"].label) == "Dog Toy Box",
		"The toy boxes are named Cat Toy Box and Dog Toy Box.")

	print("GARDEN %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
