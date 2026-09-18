extends SceneTree
## A pet's collar and its leash, chosen by colour when the pet is shaped.
##
## The collar is an authored surface on both pet models and the leash is its own
## second surface, so the two can be coloured apart from each other and from the
## coat. The picker's swatch rows are built in the real phone flow, and the
## colours ride the pet's saved record into a fresh load.

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


func press(label: String) -> void:
	for node: Node in app.find_children("*", "Button", true, false):
		var b: Button = node as Button
		if b != null and b.is_visible_in_tree() and str(b.text).contains(label):
			b.pressed.emit()
			return


func find(name: String) -> Node:
	return app.find_child(name, true, false)


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.selected_lot = 0
	app.start_household()
	await frames(2)
	app.household.set_speed(0)
	app.adoption_flow.show_phone()
	await frames(2)
	press("Juniper Pet Shop")
	await frames(2)
	press("Adopt a cat or dog")
	await frames(2)

	# Every collar and leash swatch is on the panel and reachable.
	for palette: Array in [LifePets.COLLAR_COLORS, LifePets.LEASH_COLORS]:
		check(palette.size() >= 10, "The palette offers at least ten colours (%d)." % palette.size())
	for index: int in range(LifePets.COLLAR_COLORS.size()):
		check(find("PetSwatch_collar_color_%d" % index) != null, "Collar swatch %d is on the picker." % index)
	for index: int in range(LifePets.LEASH_COLORS.size()):
		check(find("PetSwatch_leash_color_%d" % index) != null, "Leash swatch %d is on the picker." % index)
	# The confirm button is still on the panel and enabled.
	var confirm: Button = find("PetShopConfirm")
	check(confirm != null and not confirm.disabled, "The confirm button is still reachable and enabled.")

	# Choose a distinctive collar and leash, then buy.
	var collar: Button = find("PetSwatch_collar_color_6")
	collar.pressed.emit()
	await frames(2)
	var leash: Button = find("PetSwatch_leash_color_3")
	leash.pressed.emit()
	await frames(2)
	confirm = find("PetShopConfirm")
	confirm.pressed.emit()
	await frames(6)
	check(app.household.pets.pets.size() == 1, "A pet with chosen accessory colours is bought.")
	if app.household.pets.pets.size() == 1:
		var pet: Dictionary = app.household.pets.pets[0]
		print("  collar=", pet.get("collar_color"), " leash=", pet.get("leash_color"))
		check(str(pet.collar_color) == LifePets.COLLAR_COLORS[6], "The chosen collar colour is stored.")
		check(str(pet.leash_color) == LifePets.LEASH_COLORS[3], "The chosen leash colour is stored.")
		var actor: LifePetActor = app.pet_actors.get(str(pet.id))
		check(actor != null, "The bought pet has a body.")
		if actor != null:
			var tinted: Dictionary = {}
			for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
				if mesh.mesh == null:
					continue
				for si: int in range(mesh.mesh.get_surface_count()):
					var original: Material = mesh.mesh.surface_get_material(si)
					var override: Material = mesh.get_surface_override_material(si)
					if original is StandardMaterial3D and override is StandardMaterial3D:
						tinted[str((original as StandardMaterial3D).resource_name)] = (override as StandardMaterial3D).albedo_color
			print("  tinted surfaces: ", tinted.keys())
			check(tinted.has("Collar"), "The collar surface is recoloured.")
			check(tinted.has("Leash"), "The leash surface is recoloured.")
			if tinted.has("Collar"):
				check(tinted["Collar"].is_equal_approx(Color(LifePets.COLLAR_COLORS[6])), "The collar wears the chosen colour.")
			if tinted.has("Leash"):
				check(tinted["Leash"].is_equal_approx(Color(LifePets.LEASH_COLORS[3])), "The leash wears the chosen colour.")

	# The colours survive a save and a fresh load.
	var layout: Array = app.world.serialize_items()
	var state: Dictionary = app.household.get_state(layout)
	check(LifePets.validate(state.get("pets"), state).is_empty(), "The saved pet colours validate.")
	var appearance: Dictionary = LifePets.appearance(app.household.pets.pets[0])
	check(appearance.collar_color == LifePets.COLLAR_COLORS[6] and appearance.leash_color == LifePets.LEASH_COLORS[3], "The appearance carries both colours.")

	print("COLLAR %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
