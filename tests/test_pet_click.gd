extends SceneTree
## Clicking a pet: buying one and then opening its own card.
##
## A pet's pick body was found by the world's ray but the world had no branch to
## dispatch it: pets live in the controller's own registry, not in `items` or
## `actors`. Every click on a pet therefore fell through to a walk on the ground,
## so the animal could not be selected at all.

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func settle(n: int = 3) -> void:
	for i: int in n:
		await physics_frame


func press(label: String) -> bool:
	for node: Node in app.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and button.is_visible_in_tree() and str(button.text).contains(label):
			button.pressed.emit()
			return true
	return false


func _click_world(point: Vector3) -> Array[String]:
	app.world.update_camera()
	var screen: Vector2 = app.world.camera.unproject_position(point)
	var hits: Array[String] = []
	var listener := func(item: Dictionary, _s: Vector2) -> void: hits.append(str(item.id) + ":" + str(item.kind))
	app.world.object_clicked.connect(listener)
	app.world.pick(screen)
	app.world.object_clicked.disconnect(listener)
	return hits


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.selected_lot = 0
	app.start_household()
	await frames(2)
	app.household.set_speed(0)

	# The phone's pet shop is reachable and its gate is open for a funded home.
	check(app.household.pet_shop_availability().is_empty(), "The pet shop is offered to a funded household.")
	app.adoption_flow.show_phone()
	await frames(2)
	var shop: Button = app.find_child("PhonePetShop", true, false)
	check(shop != null and not shop.disabled, "The phone's Juniper Pet Shop button is clickable.")
	check(press("Juniper Pet Shop"), "The pet shop opens from the phone.")
	await frames(2)
	var adopt: Button = app.find_child("PetShopAdopt", true, false)
	check(adopt != null and not adopt.disabled, "The pet shop's own adopt button is clickable.")
	press("Adopt a cat or dog")
	await frames(2)
	var confirm: Button = app.find_child("PetShopConfirm", true, false)
	check(confirm != null and not confirm.disabled, "The pet picker's confirm button is clickable.")

	# Buying one really charges, and the pet gets a body.
	var funds_before: int = app.household.funds
	press("Take")
	await frames(4)
	check(app.household.pets.pets.size() == 1, "A pet is bought through the real shop flow.")
	check(app.household.funds < funds_before, "Buying the pet charges the household.")
	check(app.pet_actors.size() == 1, "The bought pet gets a body in the world.")
	await settle()

	# Clicking that body opens the pet's own card, not a walk on the ground.
	for id: String in app.pet_actors:
		var actor: LifePetActor = app.pet_actors[id]
		var hits: Array[String] = _click_world(actor.position + Vector3(0, .12, 0))
		print("  click on ", id, " -> ", hits)
		check(hits.size() == 1 and hits[0].begins_with(id + ":pet"), "Clicking the pet's body resolves to the pet itself.")
		if hits.size() == 1:
			app.on_object_clicked({"id": id, "kind": "pet", "label": str(actor.display_name), "node": actor, "size": Vector2(.6, .6)}, Vector2.ZERO)
			await frames(3)
			check(app.overlay_open, "Clicking a pet opens its card.")
			var labels: Array[String] = []
			for node: Node in app.overlay.find_children("*", "Label", true, false):
				if node is Label and (node as Label).is_visible_in_tree():
					labels.append(str((node as Label).text))
			check(labels.any(func(t: String) -> bool: return t.contains(str(actor.display_name))), "The pet's card names the pet.")
			app.close_overlay()
			await frames(2)

	print("PET_CLICK %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
