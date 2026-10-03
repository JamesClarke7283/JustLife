extends SceneTree
## Party items in Build & buy: balloons, streamers, the party food platter, the festive
## tablecloth on the gathering table, and the plumbing a friend's potluck dish uses.
##
## Run headless:
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_party_decor.gd
##
## The first half needs only a world (a MealApp stands in for the app, as in
## test_kitchen_meal_surfaces). The second half boots the real app and drives the same
## paths a player does: the Party tab, the placement path and its price, the table's card
## and menu, move, storage, undo, and a real save and load.

const PartyProps = preload("res://scripts/party_props.gd")
const PartyFood = preload("res://scripts/party_food.gd")
const PartyDecor = preload("res://scripts/party_decor.gd")

class MealApp extends Node:
	var world: LifeWorld
	var household: Dictionary = {"meals": LifeMeals.new(), "members": [], "day": 1, "minutes": 600.0}
	var current_venue: String = "home"
	var residents: Variant = null
	func _find_item(id: String) -> Dictionary:
		for item: Dictionary in world.items:
			if str(item.id) == id: return item
		return {}

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)


func frames(n: int = 3) -> void:
	for i: int in n: await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _world_part()
	await _app_part()
	print("PARTY_DECOR %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


# ----------------------------------------------------------------- helpers

## The box a built model fills, in the model's own coordinates.
func _bounds(node: Node3D, xf: Transform3D = Transform3D.IDENTITY, box: AABB = AABB(), seen: Array = []) -> AABB:
	var here: Transform3D = xf * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var local: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = here * (local.position + local.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1))
			box = AABB(point, Vector3.ZERO) if seen.is_empty() else box.expand(point)
			seen.append(true)
	for child: Node in node.get_children():
		if child is Node3D: box = _bounds(child as Node3D, here, box, seen)
	return box


func _meshes(node: Node) -> Array[Node]:
	return node.find_children("*", "MeshInstance3D", true, false)


func _tinted(node: Node) -> int:
	var count: int = 0
	for mesh: Node in _meshes(node):
		if LifeCatalogVariants.is_tint(str(mesh.name)): count += 1
	return count


func props_visible(host: Dictionary, pattern: String) -> bool:
	var props: Array = host.node.find_children(pattern, "Node3D", true, false)
	return not props.is_empty() and props.all(func(node: Node3D) -> bool: return node.visible)


func _item(world: LifeWorld, id: String) -> Dictionary:
	for item: Dictionary in world.items:
		if str(item.id) == id: return item
	return {}


## A party platter set on a host the way a purchase does: the world's own support rule.
func _place_platter(world: LifeWorld, id: String, host: Dictionary, local: Vector3, style: String = "cupcakes") -> Dictionary:
	var at: Vector3 = host.node.to_global(local)
	at.y = LifeWorld.Building.level_y(world.item_level(host))
	var entry: Dictionary = {"id": id, "kind": "party_food", "x": at.x, "z": at.z, "rotation": host.node.rotation_degrees.y, "style": style}
	entry.merge(world.surface_placement("party_food", at, host.node.rotation_degrees.y), true)
	world.add_item(entry)
	return _item(world, id)


# ------------------------------------------------------------- the world half

func _world_part() -> void:
	_catalogue_rules()
	_shapes()
	var harness := MealApp.new()
	root.add_child(harness)
	harness.world = LifeWorld.new()
	harness.add_child(harness.world)
	harness.world.create_home([])
	harness.world.set_process(false)
	var world: LifeWorld = harness.world
	var flow := LifeMealFlow.new()
	harness.add_child(flow)
	flow.app = harness
	world.add_item({"id": "table", "kind": "dining", "x": -3.0, "z": 1.0, "rotation": 90.0})
	# Each part rebuilds the home and may leave the table as a new record, so it is fetched again.
	_cloth_on_table(world, flow, _item(world, "table"))
	await frames(2)
	_platter_on_tables(world, flow, _item(world, "table"))
	await frames(2)
	_streamers_on_wall(world)
	await frames(2)
	_potluck(world, flow, _item(world, "table"))
	harness.queue_free()
	await frames(2)


func _catalogue_rules() -> void:
	for kind: String in ["party_balloons", "party_streamers", "party_food"]:
		check(LifeCatalog.ITEMS.has(kind) and str(LifeCatalog.ITEMS[kind].category) == "Party", "%s is sold in the Party category." % kind)
		check(LifeCatalog.procedural(kind), "%s is drawn from code (LifeCatalog.procedural)." % kind)
		check(not kind.begins_with("game_"), "%s keeps clear of the garden-game prefix." % kind)
	check(LifeCatalog.CATEGORIES.has("Party") and LifeCatalog.CATEGORIES.find("Party") == LifeCatalog.CATEGORIES.find("Decor") + 1, "The Party tab follows Decor.")
	check(LifeCatalog.passable("party_streamers") and not LifeCatalog.passable("party_balloons") and not LifeCatalog.passable("party_food"),
		"Streamers hang clear of the floor; balloons and the platter are solid.")
	check(LifeCatalog.wall_mounted("party_streamers") and not LifeCatalog.wall_mounted("party_balloons"), "Streamers hang on a wall.")
	check(not LifeCatalog.ITEMS.has("party_tablecloth"), "The festive tablecloth is a setting on the table, not a furnishing of its own.")
	check(LifeCatalog.PARTY_COLORS.size() == 10 and LifeCatalogVariants.colors(LifeCatalog.get_item("party_balloons")).size() == 10, "Balloons and streamers come in ten colours.")
	check(LifeCatalogVariants.styles(LifeCatalog.get_item("party_balloons")).size() == 3 and LifeCatalogVariants.styles(LifeCatalog.get_item("party_streamers")).size() == 3
		and LifeCatalogVariants.styles(LifeCatalog.get_item("party_food")).size() == 3, "Each party item offers three styles.")
	check(int(LifeCatalog.get_item("party_food").servings) == 8 and PartyFood.capacity() == 8 and PartyFood.REFILL_COST == 30, "The platter holds eight servings and a refill costs ℒ30.")
	var dining_hosts: bool = PartyDecor.hosts("dining") and not PartyDecor.hosts("table") and not PartyDecor.hosts("chair")
	check(dining_hosts, "Only the gathering table takes a festive cloth.")
	# The three hand-kept lists are one list now: the code-made kinds from before are all in it.
	for kind: String in ["memorial", "kids_toy", "bath_mat", "framed_picture", "home_phone", "burglar_alarm", "garden_gate", "garden_gate_double", "garden_gate_drive"]:
		check(LifeCatalog.procedural(kind), "%s is still a code-made kind." % kind)
	check(not LifeCatalog.procedural("dining") and not LifeCatalog.procedural("sofa"), "Furniture with authored art is not listed as code-made.")


func _shapes() -> void:
	var limits: Dictionary = {
		"party_balloons": [Vector3(.62, 1.93, .62), Vector3(.0, .0, .0)],
		"party_streamers": [Vector3(2.4, .6, .09), Vector3(0, 0, 0)],
		"party_food": [Vector3(.51, .2, .35), Vector3(0, 0, 0)],
	}
	for kind: String in limits:
		var data: Dictionary = LifeCatalog.get_item(kind)
		for style: String in LifeCatalogVariants.styles(data):
			var model: Node3D = PartyProps.build(kind, LifeCatalogVariants.resolve(data, {"style": style}))
			var box: AABB = _bounds(model)
			var count: int = _meshes(model).size()
			var span: Vector3 = limits[kind][0]
			check(count >= 8 and count <= 40, "%s %s is %d shapes (8 to 40)." % [kind, style, count])
			check(box.size.x <= span.x and box.size.z <= span.z and box.size.y <= span.y, "%s %s stays inside its footprint (%s)." % [kind, style, str(box.size)])
			if kind == "party_streamers":
				check(box.end.y <= .04 and box.position.y >= -.56 and absf(box.get_center().x) < .05, "%s %s hangs below its attachment line, centred (%.2f to %.2f)." % [kind, style, box.position.y, box.end.y])
			else:
				check(box.position.y >= -.001, "%s %s stands on its base (%.3f)." % [kind, style, box.position.y])
			if kind != "party_food":
				check(_tinted(model) >= 3, "%s %s has surfaces that take the chosen colour (%d)." % [kind, style, _tinted(model)])
			else:
				check(model.find_children("Serving_*", "Node3D", true, false).size() == 8, "%s %s has eight servings." % [kind, style])
				PartyProps.show_servings(model, 3)
				check(PartyProps.servings_shown(model) == 3, "%s %s shows three servings when three are left." % [kind, style])
			model.free()
	var cloth: Node3D = PartyProps.build_cloth("ef476f")
	var sheet: MeshInstance3D = cloth.find_child("TintClothTop", true, false)
	var sheet_top: float = sheet.position.y + (sheet.mesh as BoxMesh).size.y * .5
	check(sheet_top > .845 and sheet_top <= .847 + 1e-6, "The cloth lies above the table top (.845 m) and no higher than a dish's .847 m (%.4f)." % sheet_top)
	var spread: AABB = _bounds(cloth)
	check(spread.size.x <= 1.67 and spread.size.z <= 1.19 and spread.position.y >= .6, "The cloth spreads just past the table and hangs a short skirt (%s)." % str(spread))
	check(_tinted(cloth) == 5, "The sheet and its four skirts take the chosen colour (%d)." % _tinted(cloth))
	cloth.free()


func _cloth_on_table(world: LifeWorld, flow: LifeMealFlow, table: Dictionary) -> void:
	check(world.item_cloth(table).is_empty() and table.node.get_node_or_null("TableCloth") == null, "A gathering table starts bare.")
	check(props_visible(table, "Fruit*"), "The dining fruit bowl is visible on a bare table.")
	check(world.set_item_cloth(table, "ef476f") and world.item_cloth(table) == "ef476f" and table.node.get_node_or_null("TableCloth") != null, "A festive cloth is laid on the table.")
	check(not world.set_item_cloth(table, "not-a-hex") and world.item_cloth(table) == "ef476f", "A cloth shade that is not a hex colour is refused.")
	check(world.festive_count(0) == 1 and world.festive_count(1) == 0, "A clothed table counts as one festive touch on its floor.")
	var chair: Dictionary = {}
	world.add_item({"id": "chair_a", "kind": "chair", "x": 0.0, "z": 0.0, "rotation": 0.0})
	chair = _item(world, "chair_a")
	check(not world.set_item_cloth(chair, "ef476f"), "A chair cannot wear a table cloth.")
	world.remove_item("chair_a")
	check(flow._surface_clear(table, Vector3(.4, .847, 0), LifeMeals.PLATE_HALF_SIZE), "A plate still fits on a table with a cloth.")
	check(flow._surface_slot(table, LifeMeals.PLATTER_HALF_SIZE).is_finite(), "A serving dish still finds its place on a clothed table.")
	check(props_visible(table, "Fruit*"), "The fruit bowl stays visible on a clothed table.")
	# The cloth is a thin sheet: no new body to click, and the table's own box is untouched.
	var bodies: Array = table.node.find_children("*", "StaticBody3D", true, false)
	check(bodies.size() == 1 and (bodies[0] as StaticBody3D).get_child_count() == 1, "The cloth adds no collision body (%d)." % bodies.size())
	# It rides the saved layout, in any record order, and survives a rebuild.
	var saved: Array = world.serialize_items()
	var saved_table: Dictionary = {}
	for entry: Dictionary in saved:
		if str(entry.get("id", "")) == "table": saved_table = entry
	check(str(saved_table.get("cloth", "")) == "ef476f", "The saved layout record carries the cloth (%s)." % str(saved_table.get("cloth", "")))
	saved.reverse()
	world.create_home(saved)
	table = _item(world, "table")
	check(world.item_cloth(table) == "ef476f" and table.node.get_node_or_null("TableCloth") != null, "A reloaded layout lays the cloth again.")
	var tinted_painted: bool = false
	for mesh: Node in table.node.get_node("TableCloth").find_children("TintClothTop", "MeshInstance3D", true, false):
		tinted_painted = (mesh as MeshInstance3D).material_override is StandardMaterial3D and ((mesh as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.to_html(false) == "ef476f"
	check(tinted_painted, "The reloaded cloth wears the chosen colour.")
	# A change of colour replaces the drape rather than stacking another.
	check(world.set_item_cloth(table, "118ab2") and table.node.find_children("TableCloth", "Node3D", false, false).size() == 1 and world.item_cloth(table) == "118ab2", "A new colour replaces the cloth.")
	# Damaged saved values are ignored rather than trusted.
	for bad: Variant in ["zzzzzz", "ef476", 7, "", null, ["ef476f"]]:
		var broken: Array = world.serialize_items()
		for entry: Dictionary in broken:
			if str(entry.get("id", "")) == "table": entry["cloth"] = bad
		world.create_home(broken)
		check(world.item_cloth(_item(world, "table")).is_empty() and _item(world, "table").node.get_node_or_null("TableCloth") == null, "A saved cloth of %s is ignored." % str(bad))
	table = _item(world, "table")
	world.set_item_cloth(table, "ef476f")
	check(world.set_item_cloth(table, "") and world.item_cloth(table).is_empty() and table.node.get_node_or_null("TableCloth") == null, "Taking the cloth off bares the table.")
	for entry: Dictionary in world.serialize_items():
		if str(entry.get("id", "")) == "table": check(not entry.has("cloth"), "A bare table saves no cloth.")


func _platter_on_tables(world: LifeWorld, flow: LifeMealFlow, table: Dictionary) -> void:
	world.set_item_cloth(table, "ffd166")
	check(world.can_place("party_food", table.node.position, 90.0, "snacks"), "A platter can go in the middle of a gathering table.")
	check(not world.can_place("party_food", Vector3(-8.0, .16, 3.0), 0.0), "A platter is refused on bare floor.")
	world.add_item({"id": "desk", "kind": "study_desk", "x": 3.0, "z": 2.0, "rotation": 0.0})
	check(not world.can_place("party_food", Vector3(3.0, .16, 2.0), 0.0) and world.surface_placement("party_food", Vector3(3.0, .16, 2.0), 0.0).is_empty(), "A platter keeps off a desk's laptop workspace.")
	world.remove_item("desk")
	world.add_item({"id": "coffee", "kind": "coffee_table", "x": 3.0, "z": 3.0, "rotation": 0.0})
	var low: Dictionary = _item(world, "coffee")
	check(world.can_place("party_food", low.node.position, 0.0), "A platter can go on a coffee table.")
	world.remove_item("coffee")
	var platter: Dictionary = _place_platter(world, "snacks", table, Vector3.ZERO, "snacks")
	check(not platter.is_empty() and str(platter.get("support_id", "")) == "table" and is_equal_approx(float(platter.hang), .847), "A platter is carried by the table at the meal surface height.")
	check(int(platter.servings) == 8 and PartyProps.servings_shown(platter.node.get_node("PartyModel")) == 8, "A new platter holds and shows eight servings.")
	var body: StaticBody3D = platter.node.find_children("*", "StaticBody3D", true, false)[0]
	check((body.collision_layer & LifeWorld.PICK_SURFACE) != 0, "The platter is picked on the food ray, above its table's taller box.")
	world.add_item({"id": "other", "kind": "chair", "x": 0.0, "z": 0.0, "rotation": 0.0})
	world.remove_item("other")
	body = _item(world, "snacks").node.find_children("*", "StaticBody3D", true, false)[0]
	check((body.collision_layer & LifeWorld.PICK_SURFACE) != 0 and (body.collision_layer & LifeWorld.pick_layer(0)) != 0, "A table rebuild keeps the platter pickable.")
	flow._sync_table_settings()
	check(not props_visible(table, "Fruit*"), "A platter over the centre hides the overlapping fruit.")
	check(not flow._surface_clear(table, Vector3(0, .847, 0), LifeMeals.PLATE_HALF_SIZE) and flow._surface_clear(table, Vector3(.6, .847, 0), LifeMeals.PLATE_HALF_SIZE), "A plate cannot land on the platter but fits beside it on the clothed table.")
	check(world.simulation_targets().any(func(target: Dictionary) -> bool: return str(target.id) == "snacks" and int(target.get("servings", -1)) == 8), "The sims are told how many servings are left.")
	var anchor: Dictionary = world.activity_anchor(platter, "eat_party_food", {"standing_position": Vector3(-3.0, .16, 2.4)})
	check(str(anchor.kind) == "standing" and is_equal_approx(float(anchor.position.y), .16), "A hungry Lifelet stands on the floor to eat from the platter.")
	# Servings are state: set, shown, saved, and kept through a rebuild.
	check(world.set_party_servings("snacks", 3) and int(_item(world, "snacks").servings) == 3 and PartyProps.servings_shown(_item(world, "snacks").node.get_node("PartyModel")) == 3, "Three servings left shows three.")
	check(world.set_party_servings("snacks", 99) and int(_item(world, "snacks").servings) == 8, "A platter never holds more than eight.")
	world.set_party_servings("snacks", 3)
	var saved: Array = world.serialize_items()
	for entry: Dictionary in saved:
		if str(entry.get("id", "")) == "snacks": check(int(entry.servings) == 3 and str(entry.support_id) == "table" and str(entry.style) == "snacks", "The platter saves its servings, its support and its style (%s)." % str(entry))
	saved.reverse()
	world.create_home(saved)
	platter = _item(world, "snacks")
	check(int(platter.servings) == 3 and str(platter.support_id) == "table" and PartyProps.servings_shown(platter.node.get_node("PartyModel")) == 3 and world.item_cloth(_item(world, "table")) == "ffd166", "A reload keeps the servings, the support and the cloth.")
	for bad: Variant in ["many", -4, 800, null, 2.5, 1e30]:
		var broken: Array = world.serialize_items()
		for entry: Dictionary in broken:
			if str(entry.get("id", "")) == "snacks": entry["servings"] = bad
		world.create_home(broken)
		var shown: int = int(_item(world, "snacks").servings)
		check(shown >= 0 and shown <= 8, "A saved count of %s becomes a real count (%d)." % [str(bad), shown])
	world.create_home(saved)
	# Selling the table drops its platter to the floor with its servings.
	world.remove_item("table")
	platter = _item(world, "snacks")
	check(not platter.has("support_id") and int(platter.servings) == 3, "A platter whose table goes keeps its servings and loses its support.")
	world.remove_item("snacks")
	world.add_item({"id": "table", "kind": "dining", "x": -3.0, "z": 1.0, "rotation": 90.0})
	world.set_item_cloth(_item(world, "table"), "ef476f")


func _streamers_on_wall(world: LifeWorld) -> void:
	var near_wall: Vector3 = Vector3(-3.0, .16, -4.3)
	var snap: Dictionary = world.wall_snap("party_streamers", near_wall, 1.0)
	check(not snap.is_empty(), "Streamers find the back wall to hang from.")
	if snap.is_empty(): return
	world.placement_kind = "party_streamers"
	world.placement_hang = 2.05
	check(world.can_place("party_streamers", snap.position, float(snap.angle)), "Streamers can hang flat against a wall.")
	check(not world.can_place("party_streamers", Vector3(-3.0, .16, -1.5), 0.0), "Streamers are refused in the middle of a room.")
	world.add_item({"id": "banner", "kind": "party_streamers", "x": snap.position.x, "z": snap.position.z, "rotation": float(snap.angle), "hang": 2.05, "style": "crepe", "color": "9b5de5"})
	var banner: Dictionary = _item(world, "banner")
	check(not banner.is_empty() and is_equal_approx(banner.node.position.y, 2.05 + LifeWorld.Building.level_y(0)), "The streamers hang at 2.05 m (%.2f)." % banner.node.position.y)
	var saved: Array = world.serialize_items()
	for entry: Dictionary in saved:
		if str(entry.get("id", "")) == "banner": check(is_equal_approx(float(entry.hang), 2.05) and str(entry.style) == "crepe" and str(entry.color) == "9b5de5", "The saved streamers keep their height, style and colour (%s)." % str(entry))
	world.create_home(saved)
	banner = _item(world, "banner")
	check(not banner.is_empty() and is_equal_approx(banner.node.position.y, 2.05 + LifeWorld.Building.level_y(0)), "Streamers keep their height through a reload.")
	var painted: bool = false
	for mesh: Node in banner.node.find_children("Tint*", "MeshInstance3D", true, false):
		painted = painted or ((mesh as MeshInstance3D).material_override is StandardMaterial3D and ((mesh as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.to_html(false) == "9b5de5")
	check(painted, "The chosen colour reaches the streamers' tinted surfaces.")
	world.remove_item("banner")
	world.placement_kind = ""


func _potluck(world: LifeWorld, flow: LifeMealFlow, table: Dictionary) -> void:
	check(LifeMeals.potluck_recipe("maya", 3) == LifeMeals.potluck_recipe("maya", 3), "The same friend brings the same dish on the same day.")
	var seen: Dictionary = {}
	var easy: bool = true
	for day: int in range(1, 15):
		var recipe: String = LifeMeals.potluck_recipe("leo", day)
		seen[recipe] = true
		easy = easy and int(LifeMeals.RECIPES[recipe].skill) <= LifeMeals.POTLUCK_MAX_SKILL
	check(easy, "Every day's potluck dish is one anyone can make.")
	check(seen.size() >= 3, "Different days bring different dishes (%d)." % seen.size())
	var batch: Dictionary = flow.place_potluck("maya", "table", "chef")
	check(not batch.is_empty() and str(batch.brought_by) == "maya" and str(batch.chef) == "chef", "A potluck dish names its cook and the friend who brought it.")
	check(str(batch.storage) == "surface" and str(batch.owner).is_empty() and str(batch.host) == "table" and int(batch.remaining) == int(batch.initial), "The dish is set out on the table, uncarried and untouched.")
	check(int(batch.remaining) == int(LifeMeals.RECIPES[str(batch.recipe)].servings) and str(batch.recipe) == LifeMeals.potluck_recipe("maya", 1), "It holds its recipe's servings and the recipe the friend brings.")
	var offset: Array = batch.offset
	check(absf(float(offset[1]) - .847) < .003, "It stands at the table's meal height (%s)." % str(offset))
	check(flow.place_potluck("stranger", "table", "chef").is_empty() and flow.place_potluck("leo", "missing_table", "chef").is_empty(), "An unknown friend or table sets nothing out.")
	var second: Dictionary = flow.place_potluck("leo", "table", "chef")
	check(not second.is_empty() and absf(float(second.offset[0]) - float(batch.offset[0])) + absf(float(second.offset[2]) - float(batch.offset[2])) > .3, "A second friend's dish lands beside the first, not on it.")
	var state: Dictionary = flow.food().get_state()
	var now: float = float(flow.now())
	check(LifeMeals.validate(state, ["chef"], now).is_empty(), "A ledger with friends' dishes validates (%s)." % LifeMeals.validate(state, ["chef"], now))
	var tampered: Dictionary = state.duplicate(true)
	tampered.batches[0]["brought_by"] = "nobody"
	check(not LifeMeals.validate(tampered, ["chef"], now).is_empty(), "A dish brought by an unknown friend is refused on load.")
	tampered.batches[0]["brought_by"] = 7
	check(not LifeMeals.validate(tampered, ["chef"], now).is_empty(), "A friend's name that is not text is refused on load.")
	var plain: Dictionary = flow.food().place_batch("garden_salad", "chef", 2, "home", now, "table", Vector3.ZERO, Vector3(.5, .847, .3))
	check(not plain.has("brought_by"), "A dish nobody brought carries no friend.")
	check(flow.food().place_batch("garden_salad", "chef", 2, "home", now, "table", Vector3.INF, Vector3.ZERO).is_empty(), "A dish with a nonsense place is refused.")
	flow.food().clear()


# --------------------------------------------------------------- the app half

func _app_part() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.set_sound(false)
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	app.household.set_funds(20000)
	await frames(2)
	app.set_build_mode(true)
	await frames(4)
	await _party_tab_and_thumbnails()
	await _purchases()
	await _cloth_through_the_ui()
	await _platter_eating()
	await _move_store_and_save()
	await _upper_floor()
	app.queue_free()
	await frames(2)


func _funds() -> int:
	return int(app.sim.funds)


func _first(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: return item
	return {}


func _find_button(text: String) -> Button:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree(): return node as Button
	return null


func _party_tab_and_thumbnails() -> void:
	app.catalog_category = "Party"
	app.draw_live()
	await frames(3)
	var cards: Array[String] = []
	for node: Node in app.find_children("Catalog_*", "Button", true, false):
		cards.append(str(node.name))
	cards.sort()
	check(cards == ["Catalog_party_balloons", "Catalog_party_food", "Catalog_party_streamers"], "The Party tab offers exactly the three party items (%s)." % str(cards))
	check(app.find_child("CatalogCategory_Party", true, false) != null, "The Party filter is in the category row.")
	app.catalog_category = "Decor"
	app.draw_live()
	await frames(2)
	check(app.find_children("Catalog_party_*", "Button", true, false).is_empty(), "The Decor tab does not list party items.")
	app.catalog_category = "All"
	app.draw_live()
	await frames(2)
	# A thumbnail is a packed model of the kind. Every code-made kind gets one, which also
	# fills the cells that were blank for framed pictures and toys.
	for kind: String in LifeCatalog.PROCEDURAL:
		var data: Dictionary = LifeCatalog.get_item(kind)
		for style: String in LifeCatalogVariants.styles(data):
			var packed: Resource = app._variant_model(kind, style, data)
			var made: bool = packed is PackedScene
			if made:
				var node: Node = (packed as PackedScene).instantiate()
				made = node != null and not _meshes(node).is_empty()
				if node != null: node.free()
			check(made, "%s (%s) has a shop thumbnail model." % [kind, style])
	app.pick_furnishing("party_balloons")
	await frames(4)
	check(app.overlay.find_children("VariantStyle_*", "Button", true, false).size() == 3 and app.overlay.find_children("VariantColor_*", "Button", true, false).size() == 10, "The balloon picker offers three styles and ten colours.")
	check(app.overlay.find_child("VariantPreview", true, false) != null, "The picker previews the balloons.")
	app.close_overlay()
	await frames(2)


## A spot near `around` where the world, with the app's own reach rule, lets this kind stand.
func _spot_near(kind: String, around: Vector3, first_ring: int) -> Vector3:
	for ring: int in range(first_ring, 16):
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring: continue
				var candidate: Vector3 = Vector3(around.x + float(dx) * .5, around.y, around.z + float(dz) * .5)
				if app.world.can_place(kind, candidate, float(app.world.placement_angle)): return candidate
	return Vector3.INF


func _free_floor(kind: String, style: String) -> Vector3:
	for ring: int in range(0, 30):
		for x: int in range(-ring, ring + 1):
			for z: int in range(-ring, ring + 1):
				if maxi(absi(x), absi(z)) != ring: continue
				var at := Vector3(-8.0 + float(x) * .5, .16, 0.0 + float(z) * .5)
				if app.world.can_place(kind, at, 0.0, style, ""): return at
	return Vector3.INF


func _purchases() -> void:
	var table: Dictionary = _first("dining")
	check(not table.is_empty(), "The starter home has a gathering table.")
	# Balloons: bought on the floor, in a chosen style and colour, for their price once.
	var before: int = _funds()
	var spot: Vector3 = _free_floor("party_balloons", "column")
	check(spot.is_finite(), "There is floor for balloons.")
	app.world.begin_placement("party_balloons", "column", "", "118ab2")
	check(is_instance_valid(app.world.ghost) and not _meshes(app.world.ghost).is_empty(), "The balloon placement ghost shows balloons.")
	app.on_placement("party_balloons", spot, 0.0, "column")
	await frames(2)
	var balloons: Dictionary = _first("party_balloons")
	check(not balloons.is_empty() and before - _funds() == 25, "Balloons are charged ℒ25 once (%d)." % (before - _funds()))
	check(str(balloons.variant.style) == "column" and str(balloons.variant.color) == "118ab2", "The chosen style and colour are remembered (%s)." % str(balloons.variant))
	check(balloons.node.find_children("TintGloss*", "MeshInstance3D", true, false).any(func(mesh: Node) -> bool: return ((mesh as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.to_html(false) == "118ab2"), "The colour reaches the balloons, which keep their shine.")
	# Streamers: hung on the back wall at 2.05 m for their price once.
	before = _funds()
	var snap: Dictionary = app.world.wall_snap("party_streamers", Vector3(-3.0, .16, -4.3), 1.0)
	app.world.begin_placement("party_streamers", "bunting", "", "ffd166")
	check(is_equal_approx(app.world.placement_hang, 2.05), "The streamers' ghost starts at the party hang height.")
	app.on_placement("party_streamers", snap.position, float(snap.angle), "bunting")
	await frames(2)
	var streamers: Dictionary = _first("party_streamers")
	check(not streamers.is_empty() and before - _funds() == 15, "Streamers are charged ℒ15 once (%d)." % (before - _funds()))
	check(not streamers.is_empty() and is_equal_approx(streamers.node.position.y, 2.05 + LifeBuildingState.level_y(0)), "The streamers hang at 2.05 m.")
	# The platter: set on the gathering table for its price once.
	before = _funds()
	var middle: Vector3 = table.node.position
	app.world.begin_placement("party_food", "cupcakes")
	check(not app.world.can_place("party_food", Vector3(-8.0, .16, 4.0), 0.0), "The platter is refused on open floor.")
	app.on_placement("party_food", middle, table.node.rotation_degrees.y, "cupcakes")
	await frames(2)
	var platter: Dictionary = _first("party_food")
	check(not platter.is_empty() and before - _funds() == 40, "The platter is charged ℒ40 once (%d)." % (before - _funds()))
	check(not platter.is_empty() and str(platter.get("support_id", "")) == str(table.id) and int(platter.servings) == 8, "The platter stands on the table with eight servings.")
	# Refusals charge nothing.
	before = _funds()
	app.on_placement("party_food", Vector3(-8.0, .16, 4.0), 0.0, "cupcakes")
	check(before == _funds(), "A refused platter costs nothing.")


func _cloth_through_the_ui() -> void:
	var table: Dictionary = _first("dining")
	var before: int = _funds()
	app.show_build_object(table, Vector2(700, 300))
	await frames(2)
	var lay: Button = app.overlay.find_child("TableClothLay", true, false) as Button
	check(lay != null and lay.text == "Lay a festive tablecloth · ℒ15" and not lay.disabled, "The table's Build card offers 'Lay a festive tablecloth · ℒ15'.")
	check(app.overlay.find_child("TableClothRemove", true, false) == null, "A bare table's card has no 'Take the tablecloth off'.")
	if lay != null: lay.pressed.emit()
	await frames(2)
	table = _first("dining")
	check(before - _funds() == 15 and app.world.item_cloth(table) == "ef476f", "Laying the cloth costs ℒ15 once (%d) and puts it on the table." % (before - _funds()))
	app.show_build_object(table, Vector2(700, 300))
	await frames(2)
	var off: Button = app.overlay.find_child("TableClothRemove", true, false) as Button
	check(app.overlay.find_child("TableClothLay", true, false) == null and off != null and off.text == "Take the tablecloth off", "A clothed table's card offers 'Take the tablecloth off'.")
	check(app.overlay.find_child("TableClothColour", true, false) != null, "It also offers a free colour change.")
	app.show_build_object(table, Vector2(700, 300))
	await frames(1)
	var colour: Button = app.overlay.find_child("TableClothColour", true, false) as Button
	if colour != null: colour.pressed.emit()
	await frames(2)
	var chips: Array = app.overlay.find_children("TableClothColor_*", "Button", true, false)
	check(chips.size() == 10, "The cloth picker shows the ten party colours (%d)." % chips.size())
	var paid: int = _funds()
	if chips.size() == 10: (chips[3] as Button).pressed.emit()
	await frames(2)
	check(app.world.item_cloth(_first("dining")) == "118ab2" and _funds() == paid, "A new cloth colour is applied and costs nothing.")
	# Build mode's Undo takes the changes back, refunding the cloth.
	app.close_overlay()
	app.undo_build()
	await frames(2)
	check(app.world.item_cloth(_first("dining")) == "ef476f", "Undo steps the cloth back to its earlier colour.")
	app.undo_build()
	await frames(2)
	check(app.world.item_cloth(_first("dining")).is_empty() and _funds() == before, "Undo takes the laid cloth off and refunds ℒ15 (%d)." % (_funds() - before))
	check(_first("dining").node.get_node_or_null("TableCloth") == null, "The undone cloth is gone from the table.")
	# Live mode: the same two choices on the table's own menu.
	app.set_build_mode(false)
	await frames(3)
	table = _first("dining")
	app.show_interactions(table, Vector2(700, 300))
	await frames(2)
	var menu_lay: Button = _find_button("Lay a festive tablecloth · ℒ15")
	check(menu_lay != null and not menu_lay.disabled, "The table's menu offers 'Lay a festive tablecloth · ℒ15'.")
	var live_before: int = _funds()
	if menu_lay != null: menu_lay.pressed.emit()
	await frames(2)
	check(app.world.item_cloth(_first("dining")) == "ef476f" and live_before - _funds() == 15, "Laying it from the menu charges ℒ15 once (%d)." % (live_before - _funds()))
	app.show_interactions(_first("dining"), Vector2(700, 300))
	await frames(2)
	check(_find_button("Lay a festive tablecloth · ℒ15") == null and _find_button("Take the tablecloth off") != null, "A clothed table's menu offers 'Take the tablecloth off'.")
	var take_off: Button = _find_button("Take the tablecloth off")
	if take_off != null: take_off.pressed.emit()
	await frames(2)
	check(app.world.item_cloth(_first("dining")).is_empty() and _funds() == live_before - 15, "Taking it off from the menu is free and leaves the table bare.")
	# A Lifelet too poor for the cloth is told so.
	var purse: int = _funds()
	app.household.set_funds(10)
	app.show_interactions(_first("dining"), Vector2(700, 300))
	await frames(2)
	var poor: Button = _find_button("Lay a festive tablecloth · ℒ15")
	check(poor != null and poor.disabled and str(poor.tooltip_text).contains("ℒ15"), "Without ℒ15 the choice is greyed out and says why.")
	app.close_overlay()
	app.household.set_funds(purse)
	# Lay it again for the move, storage and save checks.
	check(PartyDecor.apply(app, PartyDecor.LAY, str(_first("dining").id)), "The cloth can be laid again.")
	app.set_build_mode(true)
	await frames(3)


func _platter_eating() -> void:
	var platter: Dictionary = _first("party_food")
	var id: String = str(platter.id)
	var menu: Array = app.sim.get_actions_for("party_food", id).map(func(a: Dictionary) -> String: return str(a.id))
	check(menu == ["eat_party_food", "refill_party_food"], "The platter offers eating and refilling (%s)." % str(menu))
	var refill: Dictionary = app.sim.get_action_availability("refill_party_food", id)
	check(not bool(refill.available) and str(refill.reason).contains("full"), "A full platter cannot be refilled (%s)." % str(refill.reason))
	app.household.set_speed(0)
	app.set_build_mode(false)
	await frames(3)
	app.sim.needs.hunger = 20.0
	var hunger: float = float(app.sim.needs.hunger)
	app.sim.speed = 1
	var purse: int = _funds()
	app.sim.queue_action("eat_party_food", id, platter.node.global_position)
	app.sim.begin_current_action()
	var guard: int = 0
	while not app.sim.get_current_action().is_empty() and guard < 600:
		app.sim.tick(1.0)
		guard += 1
	await frames(2)
	check(float(app.sim.needs.hunger) > hunger + 20.0 and _funds() == purse, "A bite from the platter feeds the Lifelet and costs nothing (%.0f)." % app.sim.needs.hunger)
	check(int(_first("party_food").servings) == 7, "Eating through the sim takes one serving (%d)." % int(_first("party_food").servings))
	# Seven more, taken as the app is told each finishes.
	for left: int in range(6, -1, -1):
		app.on_action_finished({"id": "eat_party_food", "target_id": id})
		await frames(2)
		var model: Node3D = _first("party_food").node.get_node("PartyModel")
		check(int(_first("party_food").servings) == left and PartyProps.servings_shown(model) == left, "%d servings are left and %d show." % [left, PartyProps.servings_shown(model)])
	var empty: Dictionary = app.sim.get_action_availability("eat_party_food", id)
	check(not bool(empty.available) and str(empty.reason).contains("ℒ30"), "An empty platter refuses a bite and names the refill (%s)." % str(empty.reason))
	app.sim.queue_action("eat_party_food", id, platter.node.global_position)
	check(app.sim.get_current_action().is_empty(), "A bite from an empty platter is not queued.")
	app.on_action_finished({"id": "eat_party_food", "target_id": id})
	check(int(_first("party_food").servings) == 0, "Servings never fall below none.")
	var offered: Array = app.sim.get_actions_for("party_food", id)
	var refill_entry: Dictionary = {}
	for entry: Dictionary in offered:
		if str(entry.id) == "refill_party_food": refill_entry = entry
	check(bool(refill_entry.get("available", false)) and int(refill_entry.cost) == 30, "The empty platter offers a ℒ30 refill.")
	# A refill really is paid for and really restores the platter.
	purse = _funds()
	app.sim.queue_action("refill_party_food", id, platter.node.global_position)
	app.sim.begin_current_action()
	guard = 0
	while not app.sim.get_current_action().is_empty() and guard < 600:
		app.sim.tick(1.0)
		guard += 1
	await frames(2)
	check(purse - _funds() == 30, "A refill costs ℒ30 once (%d)." % (purse - _funds()))
	check(int(_first("party_food").servings) == 8 and PartyProps.servings_shown(_first("party_food").node.get_node("PartyModel")) == 8, "A refill sets out all eight servings again.")
	check(not bool(app.sim.get_action_availability("refill_party_food", id).available), "A full platter cannot be refilled again.")
	app.on_action_finished({"id": "eat_party_food", "target_id": id})
	await frames(2)
	check(bool(app.sim.get_action_availability("refill_party_food", id).available), "A platter short of one serving can be topped up.")
	var poor_purse: int = _funds()
	app.household.set_funds(10)
	await frames(1)
	var broke: Dictionary = app.sim.get_action_availability("refill_party_food", id)
	check(not bool(broke.available) and str(broke.reason).contains("ℒ30"), "Without ℒ30 a refill is refused (%s)." % str(broke.reason))
	app.household.set_funds(poor_purse)
	app.on_action_finished({"id": "eat_party_food", "target_id": "not_a_platter"})
	check(int(_first("party_food").servings) == 7, "An action for some other target leaves the platter alone.")
	app.set_build_mode(true)
	await frames(3)


func _move_store_and_save() -> void:
	var table: Dictionary = _first("dining")
	var platter: Dictionary = _first("party_food")
	var platter_id: String = str(platter.id)
	app.world.set_party_servings(platter_id, 5)
	check(PartyDecor.apply(app, PartyDecor.RECOLOUR, str(table.id), "9b5de5"), "The cloth colour can change again.")
	# Move the platter to a new spot on the table: it keeps its servings.
	app.move_item(_first("party_food"))
	await frames(2)
	var shifted: Vector3 = table.node.to_global(Vector3(.45, 0, 0))
	shifted.y = LifeBuildingState.level_y(0)
	app.on_placement("party_food", shifted, table.node.rotation_degrees.y, "cupcakes")
	await frames(2)
	platter = _first("party_food")
	check(not platter.is_empty() and str(platter.get("support_id", "")) == str(table.id) and int(platter.servings) == 5, "A moved platter keeps its servings (%d)." % int(platter.get("servings", -1)))
	# Move the table: the cloth goes with it, and so does the platter on it.
	var table_id: String = str(table.id)
	var from: Vector3 = table.node.position
	app.move_item(_first("dining"))
	await frames(2)
	var to: Vector3 = _spot_near("dining", from, 2)
	check(to.is_finite(), "There is room to move the table.")
	app.on_placement("dining", to, float(app.world.placement_angle))
	await frames(2)
	table = _first("dining")
	check(str(table.id) == table_id and table.node.position.distance_to(from) > .5, "The table moved.")
	check(app.world.item_cloth(table) == "9b5de5" and table.node.get_node_or_null("TableCloth") != null, "A moved table keeps its cloth.")
	platter = _first("party_food")
	check(str(platter.get("support_id", "")) == table_id and int(platter.servings) == 5 and Vector2(platter.node.global_position.x - table.node.global_position.x, platter.node.global_position.z - table.node.global_position.z).length() < .8, "The platter moved with its table, servings intact.")
	# Storage: the platter and then the table go into the storage unit and come out unchanged.
	app.store_item(_first("party_food"))
	await frames(2)
	var stored_platter: Dictionary = {}
	for record: Dictionary in app.household_flow.storage:
		if str(record.kind) == "party_food": stored_platter = record
	check(not stored_platter.is_empty() and int(stored_platter.servings) == 5 and app.world.items.all(func(item: Dictionary) -> bool: return str(item.kind) != "party_food"), "A stored platter keeps its servings in the storage unit.")
	app.withdraw_stored(str(stored_platter.id))
	await frames(2)
	app.on_placement("party_food", Vector3(table.node.position.x, LifeBuildingState.level_y(0), table.node.position.z), table.node.rotation_degrees.y, "cupcakes")
	await frames(2)
	platter = _first("party_food")
	check(not platter.is_empty() and int(platter.servings) == 5 and str(platter.get("support_id", "")) == table_id, "A platter taken out of storage has its servings and its table (%d)." % int(platter.get("servings", -1)))
	app.store_item(_first("party_food"))
	await frames(1)
	app.store_item(_first("dining"))
	await frames(2)
	var stored_table: Dictionary = {}
	for record: Dictionary in app.household_flow.storage:
		if str(record.kind) == "dining": stored_table = record
	check(not stored_table.is_empty() and str(stored_table.get("cloth", "")) == "9b5de5", "A stored table keeps its cloth (%s)." % str(stored_table.get("cloth", "")))
	check(LifeHouseholdFlow.validate({"serial": 0, "books": [], "fill": {}, "storage": [{"id": "x", "kind": "dining", "x": 1.0, "z": 1.0, "rotation": 0.0, "level": 0, "cloth": "ef476f"}]}, app.world.serialize_items()).is_empty(), "A stored table with a cloth validates.")
	for bad_record: Dictionary in [{"cloth": "nonsense"}, {"cloth": 3}, {"servings": -1}, {"servings": 99}, {"servings": "eight"}]:
		var record: Dictionary = {"id": "x", "kind": "party_food", "x": 1.0, "z": 1.0, "rotation": 0.0, "level": 0}
		record.merge(bad_record, true)
		check(not LifeHouseholdFlow.validate({"serial": 0, "books": [], "fill": {}, "storage": [record]}, app.world.serialize_items()).is_empty(), "A stored record with %s is refused." % str(bad_record))
	app.withdraw_stored(str(stored_table.id))
	await frames(2)
	app.on_placement("dining", _spot_near("dining", from, 1), float(app.world.placement_angle))
	await frames(2)
	table = _first("dining")
	check(not table.is_empty() and app.world.item_cloth(table) == "9b5de5", "A table taken out of storage wears its cloth.")
	# A platter back on the table for the save, then a real save and load.
	app.world.begin_placement("party_food", "sandwiches")
	app.on_placement("party_food", table.node.position, table.node.rotation_degrees.y, "sandwiches")
	await frames(2)
	platter = _first("party_food")
	var saved_id: String = str(platter.id)
	app.world.set_party_servings(saved_id, 2)
	# A bite from the platter waiting in the queue is saved with the household.
	app.household.set_speed(0)
	app.sim.queue_action("eat_party_food", saved_id, platter.node.global_position)
	check(str(app.sim.get_current_action().get("id", "")) == "eat_party_food", "A bite is queued at the platter before the save.")
	check(app.save_game("Party decor round trip"), "The household saves with party items placed.")
	await frames(2)
	var slot: String = app.active_save_id
	app.world.set_party_servings(saved_id, 8)
	app.world.set_item_cloth(_first("dining"), "")
	app.load_game(slot)
	await frames(4)
	table = _first("dining")
	platter = _first("party_food")
	check(app.world.item_cloth(table) == "9b5de5" and table.node.get_node_or_null("TableCloth") != null, "A real save and load keeps the tablecloth.")
	check(not platter.is_empty() and int(platter.servings) == 2 and PartyProps.servings_shown(platter.node.get_node("PartyModel")) == 2 and str(platter.get("support_id", "")) == str(table.id), "A real save and load keeps the platter's servings and its table (%d)." % int(platter.get("servings", -1)))
	check(not _first("party_balloons").is_empty() and str(_first("party_balloons").variant.color) == "118ab2" and not _first("party_streamers").is_empty() and is_equal_approx(_first("party_streamers").node.position.y, 2.05 + LifeBuildingState.level_y(0)), "Balloons and streamers survive the save with their colour and height.")
	var waiting: Dictionary = app.sim.get_current_action()
	check(waiting.is_empty() or (str(waiting.id) == "eat_party_food" and str(waiting.target_id) == str(platter.id)), "A queued bite is either restored at the platter or dropped, never garbled.")
	app.sim.cancel_action()
	# And the sims hear of the reloaded platter.
	var offered: Array = app.sim.get_actions_for("party_food", str(platter.id))
	check(not offered.is_empty() and bool(offered[0].available), "A reloaded platter can be eaten from (%s)." % str(offered.map(func(a: Dictionary) -> String: return str(a.get("unavailable_reason", "")))))


## The same items stand on an upper storey: bought there, carried by an upstairs table,
## eaten from, and kept by a real save and load.
func _upper_floor() -> void:
	app.set_build_mode(true)
	await frames(2)
	app.household.set_funds(20000)
	var quote: Dictionary = app.build_transactions.prepare({"op": "add_storey"})
	check(bool(quote.ok), "A storey can be added for the upstairs checks (%s)." % str(quote.get("error", "")))
	if not bool(quote.ok): return
	app.build_transactions.commit(quote)
	app._refresh_sim_targets(false)
	app.set_build_level(1)
	await frames(3)
	var up: float = LifeBuildingState.level_y(1)
	var before: int = _funds()
	var spot: Vector3 = Vector3.INF
	for x: float in [-3.5, -2.5, -1.5, -0.5, 0.5, 1.5]:
		for z: float in [-2.0, -1.0, 0.0, 1.0, 2.0]:
			if not spot.is_finite() and app.world.can_place("party_balloons", Vector3(x, up, z), 0.0, "trio"): spot = Vector3(x, up, z)
	check(spot.is_finite(), "There is room for balloons upstairs.")
	app.world.begin_placement("party_balloons", "trio", "", "06d6a0")
	app.on_placement("party_balloons", spot, 0.0, "trio")
	await frames(2)
	var balloons: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "party_balloons" and app.world.item_level(item) == 1: balloons = item
	check(not balloons.is_empty() and is_equal_approx(balloons.node.position.y, up) and before - _funds() == 25, "Balloons are bought upstairs for ℒ25 (%d)." % (before - _funds()))
	# A table upstairs, with a cloth and a platter.
	before = _funds()
	var table_at: Vector3 = Vector3.INF
	for x: float in [2.5, 3.0, 3.5, 4.0, -4.5, -4.0]:
		for z: float in [-2.5, -1.5, 0.0, 1.5, 2.5, 3.5]:
			if not table_at.is_finite() and app.world.can_place("dining", Vector3(x, up, z), 0.0): table_at = Vector3(x, up, z)
	check(table_at.is_finite(), "There is room for a gathering table upstairs.")
	app.world.begin_placement("dining")
	app.on_placement("dining", table_at, 0.0)
	await frames(2)
	var table: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "dining" and app.world.item_level(item) == 1: table = item
	check(not table.is_empty() and before - _funds() == 280, "A gathering table is bought upstairs (%d)." % (before - _funds()))
	if table.is_empty(): return
	before = _funds()
	check(PartyDecor.apply(app, PartyDecor.LAY, str(table.id)) and before - _funds() == 15 and app.world.item_cloth(table) == "ef476f", "The upstairs table is dressed with a cloth for ℒ15.")
	check(is_equal_approx(table.node.get_node("TableCloth").global_position.y, up), "The upstairs cloth sits on the upstairs table.")
	before = _funds()
	app.world.begin_placement("party_food", "snacks")
	app.on_placement("party_food", table_at, 0.0, "snacks")
	await frames(2)
	var platter: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "party_food" and app.world.item_level(item) == 1: platter = item
	check(not platter.is_empty() and before - _funds() == 40 and str(platter.get("support_id", "")) == str(table.id), "A platter is bought for the upstairs table for ℒ40 (%d)." % (before - _funds()))
	if platter.is_empty(): return
	check(is_equal_approx(platter.node.position.y, up + .847) and int(platter.servings) == 8, "It stands at the meal height of its own floor with eight servings (%.3f)." % platter.node.position.y)
	var body: StaticBody3D = platter.node.find_children("*", "StaticBody3D", true, false)[0]
	check((body.collision_layer & LifeWorld.PICK_SURFACE) != 0 and (body.collision_layer & LifeWorld.pick_layer(1)) != 0, "It is picked on its own floor.")
	# Streamers on the upstairs wall.
	before = _funds()
	var snap: Dictionary = app.world.wall_snap("party_streamers", Vector3(0.0, up, -4.3), 1.2)
	check(not snap.is_empty(), "The upstairs back wall takes streamers.")
	if not snap.is_empty():
		app.world.begin_placement("party_streamers", "tassel", "", "f15bb5")
		app.on_placement("party_streamers", snap.position, float(snap.angle), "tassel")
		await frames(2)
	var streamers: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "party_streamers" and app.world.item_level(item) == 1: streamers = item
	check(not streamers.is_empty() and before - _funds() == 15 and is_equal_approx(streamers.node.position.y, up + 2.05), "Streamers hang upstairs at 2.05 m above that floor for ℒ15.")
	# Eating upstairs, then a real save and load.
	var upstairs_id: String = str(platter.id)
	app.on_action_finished({"id": "eat_party_food", "target_id": upstairs_id})
	await frames(2)
	check(int(app.world.items.filter(func(item: Dictionary) -> bool: return str(item.id) == upstairs_id)[0].servings) == 7, "A bite upstairs takes a serving.")
	check(app.save_game("Party decor upstairs"), "The household saves with party items on two floors.")
	await frames(2)
	var slot: String = app.active_save_id
	app.world.set_party_servings(upstairs_id, 8)
	app.world.set_item_cloth(table, "")
	app.load_game(slot)
	await frames(4)
	var kinds_upstairs: Dictionary = {}
	for item: Dictionary in app.world.items:
		if app.world.item_level(item) == 1: kinds_upstairs[str(item.kind)] = item
	check(kinds_upstairs.has("party_balloons") and kinds_upstairs.has("party_streamers") and kinds_upstairs.has("party_food") and kinds_upstairs.has("dining"), "Every party item upstairs is still upstairs after the load.")
	if kinds_upstairs.has("party_food") and kinds_upstairs.has("dining"):
		check(int(kinds_upstairs.party_food.servings) == 7 and str(kinds_upstairs.party_food.get("support_id", "")) == str(kinds_upstairs.dining.id) and app.world.item_cloth(kinds_upstairs.dining) == "ef476f", "The upstairs servings, support and cloth survive the load.")
		check(is_equal_approx(kinds_upstairs.party_food.node.position.y, up + .847) and is_equal_approx(kinds_upstairs.party_streamers.node.position.y, up + 2.05), "Heights upstairs survive the load.")
	check(app.world.items.filter(func(item: Dictionary) -> bool: return str(item.kind) == "party_food").size() == 2, "The platter downstairs is still there beside the one upstairs.")
	check(app.world.festive_count(1) == 3 and app.world.festive_count(0) >= 3, "Party hosting can count the festive touches on each floor (%d up, %d down)." % [app.world.festive_count(1), app.world.festive_count(0)])
