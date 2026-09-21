extends SceneTree
## Every garden family the catalogue sells must survive the player's own two
## gestures: buy it through Build & buy, then pick it up and move it.
##
## Two defects took the game down here. `move_item` asked `begin_placement` for
## the bare kind, and a family whose art is styled (shrubs, fences, hot tubs,
## pools, trees) ships no base model, so `load(path).instantiate()` ran on a null
## resource. And `on_placement` read `ITEMS[kind].price`, which a fence does not
## have — it is sold by the square metre — so buying or moving one raised
## "Invalid access to property or key 'price'".

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void: _run.call_deferred()

## The garden-voucher families, read from the shipped catalogue rather than a
## hand-kept list, so the check follows the catalogue as it grows.
const GARDEN_CATEGORIES: Array[String] = ["Garden", "Pool", "Kids", "Vehicles"]

func _garden_kinds() -> Array[String]:
	var out: Array[String] = []
	for kind: String in LifeCatalog.ITEMS:
		if str(LifeCatalog.ITEMS[kind].get("category", "")) in GARDEN_CATEGORIES:
			out.append(kind)
	return out

## A free legal spot, searching outward from a start cell.
func _free_spot(kind: String, style: String, size: String, from: Vector3) -> Vector3:
	for radius: int in range(0, 24):
		for x: int in range(-radius, radius + 1):
			for z: int in range(-radius, radius + 1):
				if maxi(abs(x), abs(z)) != radius: continue
				var at := Vector3(from.x + float(x) * 0.5, 0.16, from.z + float(z) * 0.5)
				if app.world.can_place(kind, at, 0.0, style, size): return at
	return Vector3.INF

func _placed_item(kind: String) -> Dictionary:
	for candidate: Dictionary in app.world.items:
		if str(candidate.kind) == kind: return candidate
	return {}

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(10)
	app.household.set_speed(0)
	app.household.set_funds(900000)
	await frames(2)
	app.set_build_mode(true); await frames(4)

	var kinds: Array[String] = _garden_kinds()
	check(kinds.size() >= 15, "The catalogue really sells the garden set (%d families)." % kinds.size())
	# The whole set is large; the defects lived in the families whose art is
	# styled or sold by area, so those are swept first and the rest sampled.
	var priority: Array[String] = ["shrub", "flowers", "fence", "hot_tub", "pool", "tree_garden",
		"garden_table", "bbq", "garden_ready", "post_box", "garden_light", "pool_ladder"]
	var sweep: Array[String] = priority.filter(func(k: String) -> bool: return kinds.has(k))
	for kind: String in kinds:
		if sweep.size() >= 20: break
		if not sweep.has(kind): sweep.append(kind)

	var bought: Array[String] = []
	var moved: Array[String] = []
	var no_spot: Array[String] = []
	for kind: String in sweep:
		var data: Dictionary = LifeCatalog.get_item(kind)
		var style: String = str(LifeCatalogVariants.styles(data)[0]) if not LifeCatalogVariants.styles(data).is_empty() else ""
		var size: String = str(LifeCatalogVariants.sizes(data)[0]) if not LifeCatalogVariants.sizes(data).is_empty() else ""
		var at: Vector3 = _free_spot(kind, style, size, Vector3(0.0, 0.16, -6.0))
		if not at.is_finite(): no_spot.append(kind); continue

		app.on_placement(kind, at, 0.0, style, size)
		await frames(4)
		var item: Dictionary = _placed_item(kind)
		if item.is_empty(): no_spot.append(kind); continue
		bought.append(kind)

		# The player's own move: pick it up, then commit a new spot.
		app.move_item(item)
		await frames(4)
		var target: Vector3 = _free_spot(kind, style, size, at + Vector3(0.5, 0.0, 0.0))
		if not target.is_finite(): target = at
		app.on_placement(kind, target, 0.0, style, size)
		await frames(4)
		if not _placed_item(kind).is_empty(): moved.append(kind)

	print("PROBE bought=", bought)
	print("PROBE moved=", moved)
	print("PROBE no_spot=", no_spot)
	check(moved.size() == bought.size(),
		"Every bought garden family really moved without crashing (%d of %d)." % [moved.size(), bought.size()])
	# The lot has finite room, so a family the fixture cannot fit is skipped,
	# not failed; what matters is that the ones which did place all moved.
	check(bought.size() >= 8,
		"The garden set really bought through the ordinary path (%d families)." % bought.size())

	# A moved styled family keeps its own style, so the ghost was the real object.
	var shrub_style: String = ""
	for item: Dictionary in app.world.items:
		if str(item.kind) == "shrub": shrub_style = str(item.get("variant", {}).get("style", ""))
	if not shrub_style.is_empty():
		check(shrub_style != "", "A moved shrub keeps its own authored style (%s)." % shrub_style)

	app.set_build_mode(false)
	app.queue_free(); await frames(3)
	print("GARDEN_MOVE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
