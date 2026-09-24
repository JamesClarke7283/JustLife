extends SceneTree
## Focused probe: hungry Lifelet eating from fridge, and remaining-member integrity after a housemate leaves.
const LifeGroceries = preload("res://scripts/groceries.gd")
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
	app.household_profiles = [
		{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Creative"], "body_scale": 1.0, "height_scale": 1.0},
		{"name": "Liz Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Outgoing"], "body_scale": 1.12, "height_scale": 0.95},
	]
	app.creator_family_links = [{"a": "player", "b": "housemate_1", "role": "partners"}]
	app.selected_lot = 0
	app.start_household()
	await process_frame
	await process_frame
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
	app.household.set_speed(1)
	app.household.groceries = LifeGroceries.fresh()
	app.household.groceries["stock"] = 8
	app.household._sync_grocery_mirror()
	var tom: LifeSim = app.household.member_sim("player")
	var liz: LifeSim = app.household.member_sim("housemate_1")
	check(tom != null and liz != null, "Two Lifelets start in the household")
	var spawn_actor: LifeActor = app.world.actors.get("player")
	check(is_instance_valid(spawn_actor), "Tom's actor exists at spawn")
	if is_instance_valid(spawn_actor):
		check(_first_albedo_alpha(spawn_actor) > 0.9, "Tom's body materials are opaque at spawn (alpha=%.2f)" % _first_albedo_alpha(spawn_actor))
	tom.needs.hunger = 0.0
	liz.needs.hunger = 40.0
	app.household.select(0)
	app._bind_member("player")
	app.draw_live()
	await process_frame

	var fridge: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.kind) == "fridge":
			fridge = item
			break
	check(not fridge.is_empty(), "Starter home has a fridge")
	var snack_avail: Dictionary = tom.get_action_availability("snack", str(fridge.id))
	check(bool(snack_avail.available), "Snack is available with a stocked kitchen: %s" % str(snack_avail.reason))
	var before_hunger: float = float(tom.needs.hunger)
	check(tom.queue_action("snack", str(fridge.id), app.world.approach(fridge)), "Starving Lifelet can queue Grab a snack on the fridge")
	var tom_actor: LifeActor = app.world.actors.get("player")
	tom.get_current_action().phase = "approach"
	if is_instance_valid(tom_actor):
		tom_actor.position = Vector3(tom.get_current_action().target_position)
	tom.begin_current_action()
	check(bool(tom.get_current_action().get("paid", false)) or str(tom.get_current_action().get("phase", "")) == "active",
		"Snack begins from kitchen stock (phase=%s paid=%s)" % [str(tom.get_current_action().get("phase", "")), str(tom.get_current_action().get("paid", false))])
	if not tom.get_current_action().is_empty() and str(tom.get_current_action().id) == "snack":
		tom.get_current_action().phase = "active"
		tom.get_current_action()["paid"] = true
		tom.tick(float(tom.get_current_action().duration) / LifeSim.GAME_MINUTES_PER_SECOND + 0.5)
	check(float(tom.needs.hunger) > before_hunger + 10.0, "Eating a snack raises hunger from 0 (now %.1f)" % float(tom.needs.hunger))

	# Leftovers: seed fridge batch, take via leftover queue helper.
	tom.needs.hunger = 0.0
	tom.action_queue.clear()
	app.household.groceries["stock"] = maxi(2, int(app.household.groceries.get("stock", 0)))
	var seeded: Dictionary = app.household.meals.create_batch("garden_skillet", "player", 1, "home", (app.household.day - 1) * 1440.0 + app.household.minutes)
	check(not seeded.is_empty(), "Can seed a leftover batch")
	if not seeded.is_empty():
		app.household.meals.set_batch_location(str(seeded.id), "fridge", str(fridge.id), fridge.node.position, (app.household.day - 1) * 1440.0 + app.household.minutes)
		# Clear carry ownership so claim can take a serving.
		seeded.owner = ""
		seeded.storage = "fridge"
	app.meal_flow.sync_world(true)
	await process_frame
	var leftover_reason: String = tom._fridge_leftover_reason(str(fridge.id))
	check(leftover_reason.is_empty(), "Choose leftovers is available when food is stored: %s" % leftover_reason)
	var hunger_before_leftover: float = float(tom.needs.hunger)
	app.meal_flow._queue_fridge_leftover(str(fridge.id), str(seeded.id), true)
	check(not tom.get_current_action().is_empty() and str(tom.get_current_action().id) == "eat_meal",
		"Leftover queue starts eat_meal (got %s)" % str(tom.get_current_action().get("id", "")))
	for _step: int in range(6):
		var action: Dictionary = tom.get_current_action()
		if action.is_empty() or str(action.id) != "eat_meal":
			break
		if is_instance_valid(tom_actor):
			tom_actor.position = Vector3(action.get("target_position", tom_actor.position))
		if str(action.phase) == "approach":
			tom.begin_current_action()
		elif str(action.phase) == "active":
			tom.tick(float(action.duration) / LifeSim.GAME_MINUTES_PER_SECOND + 0.5)
			break
		await process_frame
	check(float(tom.needs.hunger) > hunger_before_leftover, "Eating leftovers raises hunger (%.1f -> %.1f)" % [hunger_before_leftover, float(tom.needs.hunger)])

	# Empty leftover choice stays disabled rather than a no-op click.
	for batch: Dictionary in app.household.meals.batches.duplicate():
		app.household.meals.batches.erase(batch)
	check(not tom._fridge_leftover_reason(str(fridge.id)).is_empty(), "Choose leftovers is unavailable with an empty fridge")

	# Departure integrity: Liz passes; Tom keeps scale, needs, opaque materials.
	app.household.set_speed(0)
	tom = app.household.member_sim("player")
	liz = app.household.member_sim("housemate_1")
	tom.needs.hunger = 55.0
	tom.needs.energy = 70.0
	tom.action_queue.clear()
	app.household.select(1)
	app._bind_member("housemate_1")
	liz.needs.hunger = 0.0
	liz.starvation_minutes = 9999.0
	tom_actor = app.world.actors.get("player")
	var tom_scale_before: Vector3 = tom_actor.visual.scale if is_instance_valid(tom_actor) else Vector3.ONE
	var tom_alpha_before: float = _first_albedo_alpha(tom_actor) if is_instance_valid(tom_actor) else 1.0
	check(liz.pass_on("hunger"), "Liz can leave the living household as a spirit")
	await process_frame
	await process_frame
	tom = app.household.member_sim("player")
	check(household_selected_living(), "Selection moves to a living Lifelet after departure")
	check(str(app.household.selected_id()) == "player", "Tom is selected after Liz leaves")
	tom_actor = app.world.actors.get("player")
	check(is_instance_valid(tom_actor), "Tom's actor still exists after Liz leaves")
	check(str(tom.character.get("life_status", "living")) == "living", "Tom remains living")
	check(absf(float(tom.needs.hunger) - 55.0) < 0.5, "Tom keeps his own hunger after Liz leaves (got %.3f)" % float(tom.needs.hunger))
	check(absf(float(tom.needs.energy) - 70.0) < 0.5, "Tom keeps his own energy after Liz leaves (got %.3f)" % float(tom.needs.energy))
	if is_instance_valid(tom_actor):
		var scale_now: Vector3 = tom_actor.visual.scale
		check(scale_now.distance_to(tom_scale_before) < 0.05, "Tom's visual scale stays intact (was %s now %s)" % [str(tom_scale_before), str(scale_now)])
		check(absf(scale_now.x - scale_now.y) < 0.2, "Tom's mesh is not flattened (scale %s)" % str(scale_now))
		var tom_alpha: float = _first_albedo_alpha(tom_actor)
		check(tom_alpha > 0.9, "Tom's materials stay opaque after Liz becomes a spirit (alpha=%.2f, before=%.2f)" % [tom_alpha, tom_alpha_before])

	var out := FileAccess.open("res://evidence/hunger_departure_probe.txt", FileAccess.WRITE)
	if out:
		out.store_string("checks=%d failures=%d\n" % [checks, failures.size()])
		for line: String in failures:
			out.store_string("FAIL: %s\n" % line)
		out.close()
	print("HUNGER_DEPARTURE_PROBE assertions=%d failures=%d" % [checks, failures.size()])
	for line: String in failures:
		print("FAIL: ", line)
	app.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)

func household_selected_living() -> bool:
	var selected: LifeSim = app.household.selected()
	return selected != null and not selected.is_spirit()

func _first_albedo_alpha(root: Node) -> float:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for surface_index: int in range(mesh_node.mesh.get_surface_count()):
			var material: Material = mesh_node.get_surface_override_material(surface_index)
			if material == null:
				material = mesh_node.mesh.surface_get_material(surface_index)
			if material is StandardMaterial3D:
				return float((material as StandardMaterial3D).albedo_color.a)
	return 1.0
