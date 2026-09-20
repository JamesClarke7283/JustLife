extends SceneTree
## Screenshot the makeup colour pickers in the creator's Style tab and in the
## wardrobe, after mixing a custom shade, so the picker is checked as the player
## uses it.
##
##   godot --path . --audio-driver Dummy --script res://tests/probe_makeup_picker.gd

var app: Node
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func shot(name: String) -> void:
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://makeup_picker"))
	var path: String = "user://makeup_picker/%s.png" % name
	var error: int = root.get_texture().get_image().save_png(path)
	print("MAKEUP_SHOT %s %s %s" % [name, "ok" if error == OK else "FAILED", ProjectSettings.globalize_path(path)])

func press(node: Node, label: String) -> bool:
	for found: Node in node.find_children("*", "Button", true, false):
		var b: Button = found as Button
		if b != null and b.is_visible_in_tree() and str(b.text).contains(label):
			b.pressed.emit(); return true
	return false

## The creator draws on the `ui` layer and the wardrobe on `overlay`, so a probe
## that only searched one would miss the other's controls.
func press_any(label: String) -> bool:
	return press(app, label)

## The lip surface's tint as the face really wears it. The shipped model names
## this surface `Lips`, not `Makeup_Lips`, so the probe must read the surface the
## player actually sees.
func lip_colour(actor: LifeActor) -> Color:
	for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null or mesh.mesh == null: continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_surface_override_material(surface)
			if material == null: material = mesh.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and str((material as StandardMaterial3D).resource_name) == "Lips":
				return (material as StandardMaterial3D).albedo_color
	return Color.TRANSPARENT

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(10)
	app.set_creator_tab("Style")
	await frames(8)
	# The creator offers a custom-shade row for lips and for eyes.
	check(press_any("Custom colour"), "The creator's Style tab offers a custom colour picker")
	await frames(8)
	var picker: ColorPicker = app.find_child("MakeupPicker", true, false) as ColorPicker
	check(picker != null, "The engine colour picker is open")
	if picker != null:
		# Mix a distinctive shade and confirm the face really wears it.
		var custom: Color = Color("3f7fbf")
		picker.color = custom
		picker.color_changed.emit(custom)
		await frames(6)
		check(LifeCharacterIdentity.makeup_value(app.profile, "makeup_lips") == custom.to_html(false), "The mixed shade is written into the look (%s)" % LifeCharacterIdentity.makeup_value(app.profile, "makeup_lips"))
		check(lip_colour(app.preview).is_equal_approx(custom), "The preview face wears the mixed lip shade (%s)" % str(lip_colour(app.preview)))
		await shot("creator_picker_open")
		press_any("Use this shade")
		await frames(8)
		check(app.creator_tab == "Style", "The creator returns to the Style tab after the picker")
		check(LifeCharacterIdentity.makeup_value(app.profile, "makeup_lips") == custom.to_html(false), "The shade survives closing the picker")

	# An arbitrary shade is valid, not only the authored palette entries.
	var offpalette: String = "1f4e79"
	check(not LifeCharacterIdentity.MAKEUP_LIP_COLORS.has(offpalette), "The tested shade is not one of the authored suggestions")
	check(LifeCharacterIdentity.makeup_value({"makeup_lips": offpalette}, "makeup_lips") == offpalette, "Any six-digit shade is a wearable colour")

	app.start_household()
	await frames(12)
	app.household.set_speed(0)
	var mirror: Dictionary = app.world.closest_item("mirror", Vector3.ZERO)
	app.show_wardrobe_panel(str(mirror.id), "makeup")
	await frames(10)
	check(press(app.overlay, "Pick a shade"), "The wardrobe's makeup tab offers a custom shade picker")
	await frames(8)
	check(app.find_child("MakeupPicker", true, false) != null, "The wardrobe's colour picker is open")
	await shot("wardrobe_picker_open")
	press(app.overlay, "Use this shade")
	await frames(10)
	check(app.find_child("WardrobeOptions", true, false) != null, "The wardrobe returns after the picker")
	print("MAKEUP_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
