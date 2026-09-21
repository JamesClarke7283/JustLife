extends SceneTree
## The nursery and child's-bedroom set: a cot for a baby, a child's own bed, a
## changing table, a potty and the feeding and play pieces. Each must exist as a
## real Bedroom family, ship the model the placement ghost loads, and really place
## through the ordinary Build & buy path.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_nursery.gd

const FAMILIES: Array[String] = [
	"cot", "child_bed", "changing_table", "potty", "baby_bottle", "baby_food", "baby_toys",
]

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

## A legal spot the production rules really accept.
func _spot(kind: String, size: String) -> Vector3:
	for radius: int in range(0, 26):
		for x: int in range(-radius, radius + 1):
			for z: int in range(-radius, radius + 1):
				if maxi(abs(x), abs(z)) != radius: continue
				var at := Vector3(float(x) * .5, .16, float(z) * .5)
				if app.world.can_place(kind, at, 0.0, "", size): return at
	return Vector3.INF

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

	check(LifeCatalog.CATEGORIES.has("Bedroom"), "Build & buy offers its own Bedroom section.")
	app.set_build_mode(true); await frames(4)

	var missing: Array[String] = []
	for kind: String in FAMILIES:
		var data: Dictionary = LifeCatalog.get_item(kind)
		check(not data.is_empty(), "The catalogue holds the %s family." % kind)
		if data.is_empty(): missing.append(kind); continue
		check(str(data.get("category", "")) == "Bedroom",
			"%s is filed under Bedroom (%s)." % [kind, str(data.get("label", ""))])
		check(not str(data.get("label", "")).is_empty() and int(data.get("price", 0)) > 0,
			"%s is named and priced (%s, L%d)." % [kind, str(data.get("label", "")), int(data.get("price", 0))])
		# The ghost loads this exact path, so a family without it cannot be placed.
		check(ResourceLoader.exists("res://assets/models/%s.glb" % kind),
			"%s ships the model its ghost loads." % kind)

		var size: String = str(LifeCatalogVariants.sizes(data)[0]) if not LifeCatalogVariants.sizes(data).is_empty() else ""
		var at: Vector3 = _spot(kind, size)
		check(at.is_finite(), "%s has a legal spot on the lot." % kind)
		if not at.is_finite(): missing.append(kind); continue
		app.on_placement(kind, at, 0.0, "", size)
		await frames(4)
		var placed: Array = app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == kind)
		check(placed.size() == 1, "%s really places through Build & buy (%d)." % [kind, placed.size()])
		if placed.size() == 1:
			var item: Dictionary = placed[0]
			check(item.node.position.distance_to(at) < .05,
				"%s stands where it was asked for (%s)." % [kind, str(item.node.position)])
			# And it survives being picked up and moved, the way every other
			# furnishing must.
			app.move_item(item)
			await frames(4)
			var target: Vector3 = _spot(kind, size)
			if not target.is_finite(): target = at
			app.world.placement_requested.emit(kind, target, 0.0)
			await frames(4)
			var moved: int = app.world.items.filter(func(it: Dictionary) -> bool: return str(it.kind) == kind).size()
			check(moved == 1, "%s really moves without crashing (%d)." % [kind, moved])
		# Clear it so the next family starts on a free lot.
		for item: Dictionary in app.world.items.duplicate():
			app.world.remove_item(str(item.id))
		await frames(2)

	check(missing.is_empty(), "Every nursery family is present and placeable (%s)." % str(missing))
	app.set_build_mode(false)
	app.queue_free(); await frames(3)
	print("NURSERY_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
