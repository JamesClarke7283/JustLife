extends SceneTree
## Pet click opens needs card; placed curtain swatch recolours the live mesh.
const Variants = preload("res://scripts/catalog_variants.gd")
var checks: int = 0
var failures: Array = []
var app: Node

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Creative"]}]
	app.selected_lot = 0
	app.start_household()
	await process_frame
	await process_frame
	app.household.set_speed(0)

	# Buy a dog so a live pet exists to click.
	var pets: Dictionary = app.household.pets
	var dog: Dictionary = {
		"id": "pet_dog_1",
		"species": "dog",
		"name": "Rusty",
		"sex": "male",
		"coat_color": "8b5a2b",
		"mark_color": "3b2a1a",
		"care": preload("res://scripts/pet_care.gd").fresh(),
		"tricks": [],
	}
	if not pets.has("pets") or not pets.pets is Array:
		pets["pets"] = []
	pets.pets.append(dog)
	app.household.pets = pets
	app.sync_pets()
	await process_frame
	check(app.pet_actors.has("pet_dog_1"), "Dog body is spawned for clicking")
	app.on_object_clicked({"id": "pet_dog_1", "kind": "pet", "label": "Rusty"}, Vector2(800, 400))
	await process_frame
	check(app.overlay_open, "Clicking the dog opens an overlay")
	var need_labels: Array[String] = []
	for label: Node in app.overlay.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			need_labels.append(str(label.text))
	for expected: String in ["Hunger", "Affection", "Energy", "Bladder"]:
		check(need_labels.any(func(t: String) -> bool: return expected in t), "Pet card shows %s" % expected)
	check(need_labels.any(func(t: String) -> bool: return "Tricks" in t or "Logic" in t or "Level" in t), "Pet card shows Logic/Tricks")

	app.close_overlay()
	# Place curtains and recolour them. Build mode is not required for world.add_item.
	var curtain_data: Dictionary = LifeCatalog.get_item("curtains")
	var colors: Array = Variants.colors(curtain_data)
	check(colors.size() >= 2, "Curtains offer multiple colours")
	var first: String = str(colors[0])
	var second: String = str(colors[1])
	var entry: Dictionary = {"id": "curtain_test", "kind": "curtains", "x": 0.0, "z": -4.5, "rotation": 180.0, "style": "01", "color": first}
	entry.merge(Variants.record(curtain_data, "01", first, ""), true)
	app.world.add_item(entry)
	await process_frame
	var placed: Dictionary = app._find_item("curtain_test")
	check(not placed.is_empty() and is_instance_valid(placed.get("node")), "Curtains exist in the world")
	var tint_before: Color = _tint_color(placed.node)
	app._recolour_placed_item("curtain_test", second)
	await process_frame
	placed = app._find_item("curtain_test")
	var tint_after: Color = _tint_color(placed.node)
	check(str(placed.get("color", "")) == second or str(placed.get("variant", {}).get("color", "")) == second, "Curtain record stores the new colour")
	check(tint_after.is_equal_approx(Color(second)), "Curtain Tint mesh uses the chosen colour (was %s now %s)" % [str(tint_before), str(tint_after)])

	var out := FileAccess.open("res://evidence/pet_curtain_probe.txt", FileAccess.WRITE)
	if out:
		out.store_string("checks=%d failures=%d\n" % [checks, failures.size()])
		for line: String in failures:
			out.store_string("FAIL: %s\n" % line)
		out.close()
	print("PET_CURTAIN_PROBE assertions=%d failures=%d" % [checks, failures.size()])
	for line: String in failures:
		print("FAIL: ", line)
	app.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)

func _tint_color(root: Node) -> Color:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if not Variants.is_tint(str(node.name)):
			continue
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var material: Material = mesh_node.material_override
		if material is StandardMaterial3D:
			return (material as StandardMaterial3D).albedo_color
	return Color.BLACK
