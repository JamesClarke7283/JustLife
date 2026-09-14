extends SceneTree
## Rendered evidence for the pet shop, the pet picker and live pets.
##
## This is a real forward-rendered capture of the actual game: it opens the
## public phone shop, the public picker, buys a cat and a dog through the real
## paid path and photographs them standing in the home. Run with a display, e.g.
##   JUSTLIFE_DATA_DIR=... XDG_DATA_HOME=... godot --path . --audio-driver Dummy \
##     --script res://tests/capture_pets.gd

var app: Node
var out_dir: String = "res://evidence/pets_v63"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await _settle(4)
	app.set_sound(false)

	# The shop as the player first sees it.
	app.start_household()
	await _settle(3)
	app.pet_shop.show_shop()
	await _settle(4)
	await _shot("01_pet_shop")

	# The pet picker, showing a mixed two-tone coat.
	app.pet_shop.show_species()
	await _settle(4)
	app.pet_shop.draft.species = "dog"
	app.pet_shop.draft.sex = "male"
	app.pet_shop.draft.name = "Bramble"
	app.pet_shop.draft.coat_color = "3a2b23"
	app.pet_shop.draft.mark_color = "f2ece0"
	app.pet_shop.draft.gradient = 0.8
	app.pet_shop.draft.coat_length = "long"
	app.pet_shop.draft.marking = "bicolour"
	app.pet_shop.draw_picker()
	await _settle(5)
	await _shot("02_pet_picker_mixed_coat")

	# A solid-coat cat, to show the same picker reaching the other extreme.
	app.pet_shop.draft.species = "cat"
	app.pet_shop.draft.sex = "female"
	app.pet_shop.draft.name = "Willow"
	app.pet_shop.draft.coat_color = "6b6f73"
	app.pet_shop.draft.mark_color = "ead6b8"
	app.pet_shop.draft.gradient = 0.0
	app.pet_shop.draft.coat_length = "short"
	app.pet_shop.draft.marking = "plain"
	app.pet_shop.draft.marking = "none"
	app.pet_shop.draw_picker()
	await _settle(5)
	await _shot("03_pet_picker_solid_coat")

	# Buy both through the real paid path, then photograph them in the home.
	app.close_overlay()
	await _settle(2)
	_buy("cat", "female", "Willow", "6b6f73", "ead6b8", 0.0, "short", "none")
	_buy("dog", "male", "Bramble", "3a2b23", "f2ece0", 0.8, "long", "bicolour")
	await _settle(4)
	app.set_process(false)
	# Let the arriving pets walk to their places while the render loop is held.
	for step: int in range(240):
		app._tick_pets(0.05)
	await _settle(2)
	await _shot("04_live_pets_in_home")

	# A close look at each animal. Each pet is temporarily stood on clear open
	# grass in front of the home so the coat is photographed unoccluded; the
	# pets themselves are untouched and the harness restores them afterwards.
	var saved_positions: Dictionary = {}
	for index: int in range(app.pet_actors.size()):
		var id: String = str(app.pet_actors.keys()[index])
		var actor: LifePetActor = app.pet_actors[id]
		saved_positions[id] = actor.position
		actor.position = Vector3(-4.5 + float(index) * 2.5, 0.16, 6.0)
		actor.rotation.y = 0.0
		app.world.camera.size = 2.6
		app.world.camera_angle = 0.85
		app.world.camera_elevation = 0.34
		app.world.camera_target = Vector3(actor.position.x, 0, actor.position.z)
		app.world.update_camera()
		await _settle(4)
		await _shot("05_%s_close" % str(app.household.pets.pets[index].species))
	for id: String in saved_positions:
		var actor: LifePetActor = app.pet_actors.get(id)
		if is_instance_valid(actor): actor.position = saved_positions[id]
	app.world.camera.size = 16.0
	app.world.camera_elevation = 0.82
	app.world.update_camera()

	# The pet card.
	var first_id: String = str(app.pet_actors.keys()[0])
	app.show_pet_card(first_id)
	await _settle(4)
	await _shot("06_pet_card")

	# The shop once the household owns pets: the roster and the accessories the
	# household can now actually use.
	app.close_overlay()
	app.set_build_mode(false)
	await _settle(2)
	app.pet_shop.show_shop()
	await _settle(4)
	await _shot("08_pet_shop_with_pets")

	# The accessories, once a cat and a dog are both here.
	app.set_build_mode(true)
	app.catalog_category = "Pets"
	app.draw_live()
	await _settle(5)
	await _shot("07_pet_catalogue")

	print("JUSTLIFE_PETS_CAPTURE_DONE")
	quit(0)


func _buy(species: String, sex: String, name: String, coat: String, mark: String, gradient: float, length: String, marking: String) -> void:
	var household: LifeHousehold = app.household
	var review: Dictionary = LifePets.candidate(int(household.pets.next_serial), 0)
	review.species = species
	review.sex = sex
	review.name = name
	review.coat_color = coat
	review.mark_color = mark
	review.gradient = gradient
	review.coat_length = length
	review.marking = marking
	var prepared: Dictionary = household.prepare_pet(review)
	if not bool(prepared.get("ok", false)):
		push_error("CAPTURE pet prepare failed: " + str(prepared.get("error", "")))
		return
	var spawn: Vector3 = app.world.lot_exit_position(household.members.size())
	var destination: Vector3 = app.pet_arrival_destination(spawn)
	var result: Dictionary = household.commit_pet(prepared.request, spawn)
	if not bool(result.get("ok", false)):
		push_error("CAPTURE pet commit failed: " + str(result.get("error", "")))
		return
	app.spawn_pet(str(result.pet.id), result.pet, spawn, destination)


func _settle(frames: int) -> void:
	for index: int in range(frames):
		await process_frame
	RenderingServer.force_draw(false, 0.0)


func _shot(name: String) -> void:
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	var image: Image = root.get_texture().get_image()
	var path: String = out_dir.path_join(name + ".png")
	var error: int = image.save_png(path)
	print("JUSTLIFE_PET_SHOT ", name, " ", "ok" if error == OK else "FAILED", " ", image.get_width(), "x", image.get_height())
