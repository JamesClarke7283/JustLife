extends SceneTree
## Verify the creator's Build, Height and Shoes controls really change the model
## and survive into play and a save, rather than only updating a dictionary.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_creator_controls.gd

var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func control(named: String) -> Control:
	return app.find_child(named, true, false)

## Only the material named exactly `Shoes` is recoloured; `Shoes_sole` and
## `Shoes_accent` keep their authored trim colours and must not be sampled.
func shoes_material_color() -> Color:
	for node: Node in app.preview._model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		if mesh.mesh == null: continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_surface_override_material(surface)
			if material == null: material = mesh.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and str((material as StandardMaterial3D).resource_name) == "Shoes":
				return (material as StandardMaterial3D).albedo_color
	return Color.TRANSPARENT

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game()
	await frames(5)
	check(app.mode == "creator", "Creator is open")

	# --- Height -------------------------------------------------------------
	var height: HSlider = control("CreatorHeight") as HSlider
	check(height != null, "The creator exposes a Height control")
	if height != null:
		var shortest: float = 999.0
		var tallest: float = 0.0
		height.value = 0.93
		height.value_changed.emit(0.93)
		await frames(3)
		shortest = app.preview.visual.scale.y
		height.value = 1.08
		height.value_changed.emit(1.08)
		await frames(3)
		tallest = app.preview.visual.scale.y
		check(is_equal_approx(float(app.profile.height_scale), 1.08), "Choosing the top of Height records 1.08")
		check(tallest > shortest + 0.1, "The preview model really grows: %.3f -> %.3f" % [shortest, tallest])

	# --- Build --------------------------------------------------------------
	var sliders: Array = []
	for node: Node in app.find_children("*", "HSlider", true, false):
		if node is HSlider and str(node.name) != "CreatorHeight": sliders.append(node)
	check(not sliders.is_empty(), "The creator exposes a Build slider")
	if not sliders.is_empty():
		var build: HSlider = sliders.front()
		build.value = 1.15
		build.value_changed.emit(1.15)
		await frames(3)
		check(is_equal_approx(float(app.profile.body_scale), 1.15), "Choosing the top of Build records 1.15")
		check(app.preview.visual.scale.x > 1.1, "The preview model really widens: %.3f" % app.preview.visual.scale.x)
		# Height must survive a Build change, not be reset by it.
		check(is_equal_approx(app.preview.visual.scale.y, 1.08), "Changing Build keeps the chosen Height")
		build.value = 1.0
		build.value_changed.emit(1.0)
		await frames(3)

	# --- Shoes --------------------------------------------------------------
	var before: Color = shoes_material_color()
	var chosen: String = "3b302c"
	app.profile.shoe_color = chosen
	app.refresh_preview()
	await frames(4)
	var after: Color = shoes_material_color()
	check(after != Color.TRANSPARENT, "The preview model owns a recolourable Shoes material")
	check(after != before, "Choosing a shoe colour really recolours the shoes: %s -> %s" % [str(before), str(after)])

	# --- The choices survive into play ---------------------------------------
	app.start_household()
	await frames(12)
	check(app.mode == "live", "The household starts living")
	var actor: Node = app.world.actors[str(app.household.selected_id())]
	check(actor != null, "The household member has a live actor")
	if actor != null:
		check(is_equal_approx(actor.visual.scale.y, 1.08), "The live actor keeps the chosen height")
		check(app.profile.shoe_color == chosen, "The live actor keeps the chosen shoe colour")

	print("CREATOR_CONTROLS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
