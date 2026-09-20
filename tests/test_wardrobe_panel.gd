extends SceneTree
## The wardrobe, the full-length mirror and the dressing table.
##
## Every option is tried on the real Lifelet before it is bought: the panel
## previews the working look on the actor and the ordinary wardrobe sync is held
## off while it does, so what the player sees is what they would keep. The mirror
## grants a whole Charisma level once a game day, and the dressing table offers
## makeup and jewelry.

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


func press_in(node: Node, label: String) -> bool:
	for found: Node in node.find_children("*", "Button", true, false):
		var b: Button = found as Button
		if b != null and b.is_visible_in_tree() and str(b.text).contains(label):
			b.pressed.emit()
			return true
	return false


## The LifeActor inside the panel's own preview SubViewport. It is the only actor
## under the WardrobePreview holder, and is what the player actually looks at.
func _preview_actor() -> LifeActor:
	var holder: Node = app.find_child("WardrobePreview", true, false)
	if holder == null:
		return null
	for node: Node in holder.find_children("*", "Node3D", true, false):
		if node is LifeActor:
			return node as LifeActor
	return null


## A recoloured surface material by its authored name, to prove a try-on reached
## the preview's own model rather than only the dictionary.
func _material_named(actor: LifeActor, surface_name: String) -> StandardMaterial3D:
	for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_surface_override_material(surface)
			if material == null:
				material = mesh.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and str((material as StandardMaterial3D).resource_name) == surface_name:
				return material as StandardMaterial3D
	return null


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.selected_lot = 0
	app.start_household()
	await frames(2)
	app.household.set_speed(0)

	# The starter home has a wardrobe and a full-length mirror.
	var wardrobe: Dictionary = app.world.closest_item("wardrobe", Vector3.ZERO)
	var mirror: Dictionary = app.world.closest_item("mirror", Vector3.ZERO)
	check(not wardrobe.is_empty(), "The starter home has a wardrobe.")
	check(not mirror.is_empty(), "The starter home has a full-length mirror.")
	check(str(LifeCatalog.ITEMS["mirror"].label) == "Full-length mirror", "The mirror is a full-length mirror.")

	# The mirror offers talking to yourself and changing wardrobe.
	var mirror_ids: Array = app.sim.get_actions_for("mirror", str(mirror.id)).map(func(a: Dictionary) -> String: return str(a.id))
	check(mirror_ids.has("talk_to_myself"), "The full-length mirror offers talking to yourself.")
	check(mirror_ids.has("change_in_mirror"), "The full-length mirror offers changing your wardrobe.")
	check(mirror_ids.has("practice_speech"), "The mirror still offers practising a speech.")

	# Talking to yourself grants a whole Charisma level, once a day.
	var before: int = int(app.sim.skills.charisma.level)
	app.queue_interaction(mirror, "talk_to_myself")
	var queued: bool = not app.sim.action_queue.is_empty()
	check(queued, "Talking to yourself can be queued.")
	if queued:
		app.sim.action_queue[0].phase = "active"
		app.sim.action_queue[0].elapsed = float(app.sim.action_queue[0].duration)
		app.sim._finish_front()
		var after: int = int(app.sim.skills.charisma.level)
		print("  charisma ", before, " -> ", after)
		check(after == before + 1, "Talking in the mirror raises Charisma by a whole level.")
		# A second time on the same day gives nothing more. The grant records the
		# day it last paid, so no reset here: the guard is what is under test.
		app.queue_interaction(mirror, "talk_to_myself")
		if not app.sim.action_queue.is_empty():
			app.sim.action_queue[0].phase = "active"
			app.sim.action_queue[0].elapsed = float(app.sim.action_queue[0].duration)
			app.sim._finish_front()
		check(int(app.sim.skills.charisma.level) == after, "A second mirror talk the same day gives nothing.")

	# The wardrobe panel opens, previews, and buys a look.
	app.world.set_process(false)
	app.show_wardrobe_panel(str(mirror.id), "clothes")
	await frames(3)
	check(app.overlay_open, "The wardrobe panel opens from the mirror.")
	check(app.find_child("WardrobeOptions", true, false) != null, "The wardrobe panel lists options.")
	check(app.find_child("WardrobeBuy", true, false) != null, "The wardrobe panel offers a buy button.")
	var clothes_rows: int = 0
	var options: Node = app.find_child("WardrobeOptions", true, false)
	if options != null:
		for b: Node in options.find_children("*", "Button", true, false):
			if b is Button and str((b as Button).text) == "Try on":
				clothes_rows += 1
	check(clothes_rows >= 10, "The clothes tab offers plenty of options to try (%d rows)." % clothes_rows)

	# Trying one on changes the preview without charging.
	var funds_before: int = app.household.funds
	var preview_before: String = str(app.world.actor_preview(str(app.household.selected_id())).get("top_color", ""))
	var outfit_before: int = int(app.world.actor_preview(str(app.household.selected_id())).get("outfit", 0))
	var row_buttons: Array[Button] = []
	for b: Node in options.find_children("*", "Button", true, false):
		if b is Button and str((b as Button).text) == "Try on":
			row_buttons.append(b)
	print("  row count=", row_buttons.size())
	if row_buttons.size() > 1:
		row_buttons[1].pressed.emit()
	else:
		print("  !! only ", row_buttons.size(), " rows")
	await frames(3)
	var outfit_after: int = int(app.world.actor_preview(str(app.household.selected_id())).get("outfit", 0))
	print("  preview outfit ", outfit_before, " -> ", outfit_after, " top ", preview_before)
	check(outfit_after != outfit_before, "Trying another top on really changes what is shown.")
	check(app.household.funds == funds_before, "Trying a look on costs nothing.")

	# Buying keeps it.
	press_in(app.overlay, "Buy this look")
	await frames(3)
	check(app.household.funds == funds_before - app.WARDROBE_LOOK_PRICE, "Buying the look charges exactly ℒ%d." % app.WARDROBE_LOOK_PRICE)
	check(not app.overlay_open, "Buying the look closes the panel.")

	# Makeup tab, with the limited men's set for a male Lifelet.
	app.show_wardrobe_panel(str(mirror.id), "makeup")
	await frames(3)
	var makeup_rows: int = 0
	options = app.find_child("WardrobeOptions", true, false)
	if options != null:
		for b: Node in options.find_children("*", "Button", true, false):
			if b is Button and str((b as Button).text) == "Try on":
				makeup_rows += 1
	check(makeup_rows >= 2, "The makeup tab offers lip and eye looks (%d rows)." % makeup_rows)
	app.close_overlay()
	await frames(2)

	# The dressing table itself.
	var table_found: bool = false
	for x: float in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		if app.world.can_place("dressing_table", Vector3(x, .16, 1.0), 0.0):
			table_found = true
	check(table_found, "The dressing table is placeable.")
	app.set_build_mode(true)
	await frames(2)
	app.begin_purchase("dressing_table")
	await frames(2)
	var spot: Vector3 = Vector3.INF
	for x: float in range(-11, 12):
		for z: float in range(-8, 11):
			if app.world.can_place("dressing_table", Vector3(float(x), .16, float(z)), 0.0):
				spot = Vector3(float(x), .16, float(z))
				break
		if spot.is_finite():
			break
	app.on_placement("dressing_table", spot, 0.0)
	await frames(2)
	var table: Dictionary = app.world.closest_item("dressing_table", spot)
	check(not table.is_empty(), "A dressing table is bought and placed.")
	var table_ids: Array = app.sim.get_actions_for("dressing_table", str(table.id)).map(func(a: Dictionary) -> String: return str(a.id)) if not table.is_empty() else []
	check(table_ids.has("do_makeup"), "The dressing table offers doing your makeup.")
	check(table_ids.has("change_jewelry"), "The dressing table offers changing your jewelry.")

	# The wardrobe furnishing itself opens the same panel, with a Hair tab: the
	# user asked to click the wardrobe and get hairstyles, jewelry and clothes,
	# previewed on the Lifelet.
	app.close_overlay()
	await frames(2)
	var wardrobe_ids: Array = app.sim.get_actions_for("wardrobe", str(wardrobe.id)).map(func(a: Dictionary) -> String: return str(a.id))
	check(wardrobe_ids.has("change_in_wardrobe"), "Clicking the wardrobe offers opening it.")
	var open_action: Dictionary = {}
	for a: Dictionary in app.sim.get_actions_for("wardrobe", str(wardrobe.id)):
		if str(a.id) == "change_in_wardrobe":
			open_action = a
	check(not open_action.is_empty() and bool(open_action.get("available", false)), "The wardrobe's open action is available.")
	# Completing that beat opens the panel, exactly as the mirror's does.
	app.queue_interaction(wardrobe, "change_in_wardrobe")
	if not app.sim.action_queue.is_empty():
		var action: Dictionary = app.sim.action_queue[0]
		action.phase = "active"
		action.elapsed = float(action.duration)
		app.sim._finish_front()
		app.on_action_finished(action)
	await frames(3)
	check(app.overlay_open, "Finishing the wardrobe beat opens the styling panel.")
	await frames(2)
	check(app.find_child("WardrobeTab_hair", true, false) != null, "The panel offers a Hair tab.")
	check(app.find_child("WardrobeTab_jewelry", true, false) != null, "The panel offers a Jewelry tab.")
	var hair_rows: int = 0
	var hair_options: Node = app.find_child("WardrobeOptions", true, false)
	if hair_options != null and app.wardrobe_tab == "hair":
		for b: Node in hair_options.find_children("*", "Button", true, false):
			if b is Button and str((b as Button).text) == "Try on":
				hair_rows += 1
	app.show_wardrobe_panel(str(wardrobe.id), "hair")
	await frames(3)
	hair_rows = 0
	hair_options = app.find_child("WardrobeOptions", true, false)
	if hair_options != null:
		for b: Node in hair_options.find_children("*", "Button", true, false):
			if b is Button and str((b as Button).text) == "Try on":
				hair_rows += 1
	check(hair_rows >= 18, "The Hair tab offers every authored style plus the hair and eye colours (%d rows)." % hair_rows)
	# Trying a hairstyle really changes what is shown on the Lifelet.
	var hair_before: int = int(app.world.actor_preview(str(app.household.selected_id())).get("hair", 0))
	var hair_buttons: Array[Button] = []
	for b: Node in hair_options.find_children("*", "Button", true, false):
		if b is Button and str((b as Button).text) == "Try on":
			hair_buttons.append(b)
	# Not row 0: the Lifelet is already wearing the first authored style, and the
	# assertion below is that the preview really changes.
	if hair_buttons.size() > 3:
		hair_buttons[3].pressed.emit()
	await frames(3)
	var hair_after: int = int(app.world.actor_preview(str(app.household.selected_id())).get("hair", 0))
	check(hair_after != hair_before, "Trying another hairstyle really changes what is shown (%d -> %d)." % [hair_before, hair_after])
	# And on the actor's own model, only the chosen style is visible.
	var visible_styles: Array[String] = []
	for style_name: String in LifeActor.HAIR_NAMES:
		var group: Node3D = app.player.find_child(style_name, true, false) as Node3D
		if group != null and group.visible:
			visible_styles.append(style_name)
	check(visible_styles.size() == 1, "Exactly one hairstyle is visible on the Lifelet (%s)." % str(visible_styles))
	# The panel's own close-up shows the same thing. Without it the actor at the
	# furniture stands behind the card, so a try-on would be invisible.
	var preview_actor: LifeActor = _preview_actor()
	check(preview_actor != null, "The panel carries its own close-up preview of the Lifelet.")
	if preview_actor != null:
		var shown: Array[String] = []
		for style_name: String in LifeActor.HAIR_NAMES:
			var group: Node3D = preview_actor.find_child(style_name, true, false) as Node3D
			if group != null and group.visible:
				shown.append(style_name)
		check(shown.size() == 1, "The close-up wears exactly one hairstyle (%s)." % str(shown))
		check(int(preview_actor.profile.get("hair", -1)) == hair_after, "The close-up wears the hairstyle being tried on (%d)." % int(preview_actor.profile.get("hair", -1)))
		check(shown.front() == LifeActor.HAIR_NAMES[hair_after], "The close-up shows the same cut as the tried-on row (%s)." % str(shown.front()))
		# A colour try-on must reach the close-up too, not only the actor.
		preview_actor.apply_wardrobe({"hair_color": "d7c19a"})
		await frames(2)
		var hair_material: StandardMaterial3D = _material_named(preview_actor, "Hair")
		check(hair_material != null and hair_material.albedo_color.is_equal_approx(Color("d7c19a")), "The close-up recolours its hair with the tried-on colour (%s)." % str(hair_material.albedo_color if hair_material != null else "missing"))
	# Buying the hairstyle keeps it on the saved look.
	var funds_pre: int = app.household.funds
	press_in(app.overlay, "Buy this look")
	await frames(3)
	check(int(app.sim.character.get("hair", -1)) == hair_after, "Buying the look keeps the chosen hairstyle in the saved look.")
	check(app.household.funds == funds_pre - app.WARDROBE_LOOK_PRICE, "Keeping the styling costs one look price.")

	print("WARDROBE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
