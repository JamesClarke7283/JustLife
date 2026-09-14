extends SceneTree
## Creator control/state regression. Run privately; rendered art acceptance is
## separately covered by probe_character62 and the independent visual review.

var checks: int = 0
var failures: int = 0
var app: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func press(text_value: String) -> void:
	for button: Button in app.ui.find_children("*", "Button", true, false):
		if button.text == text_value:
			button.pressed.emit()
			await frames()
			return
	check(false, "Visible creator button: " + text_value)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app.set_process(false)
	var world_msaa: int = root.msaa_3d
	var world_scale: float = root.scaling_3d_scale
	app.show_creator()
	await frames()
	check(root.msaa_3d >= Viewport.MSAA_4X and root.scaling_3d_scale >= 1.0, "Studio requests native resolution and at least four-sample edges")
	await press("Face")
	var face_camera_position: Vector3 = app.world.camera.position
	var portrait_center: Vector3 = app.preview.get_portrait_center()
	check(face_camera_position.distance_to(portrait_center) < 1.2, "Face editing gives small feature changes useful screen space")
	var seen: Array[String] = []
	for group_name: String in app.CREATOR_FACE_GROUPS:
		await press(group_name)
		check(app.creator_face_group == group_name, "Selected face group persists")
		var sliders: Array[Node] = app.ui.find_children("FaceFeature_*", "HSlider", true, false)
		check(sliders.size() == app.CREATOR_FACE_GROUPS[group_name].size(), "Only the current face group is shown")
		for slider: HSlider in sliders:
			var feature: String = str(slider.name).trim_prefix("FaceFeature_")
			seen.append(feature)
			check(slider.tooltip_text == app.CREATOR_FACE_LABELS[feature], "Named feature has a readable label")
			check(slider.min_value == (-1.0 if feature in LifeActor.SIGNED_IDENTITY_KEYS else 0.0), "Feature exposes its complete authored domain")
			slider.value = .45
			check(is_equal_approx(float(app.profile[feature]), .45), "Real slider signal updates the chosen feature")
			check(app.world.camera.position.is_equal_approx(face_camera_position), "Changing facial proportions does not move the camera")
	check(seen.size() == LifeActor.IDENTITY_KEYS.size(), "All identity controls are reachable")
	for feature: String in LifeActor.IDENTITY_KEYS:
		check(seen.count(feature) == 1, "Every identity control appears in exactly one group")
	await press("Reset face")
	for feature: String in LifeActor.IDENTITY_KEYS:
		check(is_zero_approx(float(app.profile.get(feature, -1.0))), "Reset clears hidden groups too")
	app.show_creator()
	await frames()
	app.show_lot_selection()
	await frames()
	check(app.mode == "lots", "Creator still leads to choosing a home")
	check(app.world.sun.light_energy > 0.0, "The lot regains outdoor daylight")
	check(root.msaa_3d == world_msaa and is_equal_approx(root.scaling_3d_scale, world_scale), "Repeated studio entry does not overwrite saved world quality")
	app.show_creator()
	await frames()
	app.show_main_menu()
	await frames()
	check(root.msaa_3d == world_msaa and is_equal_approx(root.scaling_3d_scale, world_scale), "Main menu also restores world quality")
	app.show_creator()
	await frames()
	app.queue_free()
	await frames()
	check(root.msaa_3d == world_msaa and is_equal_approx(root.scaling_3d_scale, world_scale), "Freeing the creator restores its viewport settings")
	print("CREATOR_PORTRAIT_RESULT ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
