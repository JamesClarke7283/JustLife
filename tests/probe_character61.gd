extends SceneTree
## Rendered evidence for iteration 61's character artwork: the creator studio
## across every hairstyle, age family and outfit, plus the live HUD at the
## ordinary play camera. Writes PNGs into evidence/character61/.
##
## Run with a display, e.g.
##   godot --path . --script res://tests/probe_character61.gd

const OUT := "res://evidence/character61"

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

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	image.save_png("%s/%s.png" % [OUT, label])
	print("EVIDENCE_SHOT ", label)

func _frames(n: int) -> void:
	for i: int in range(n):
		await process_frame

func _set_style(app: Node, hair: int, outfit: int, skin: String, top: String) -> void:
	app.profile["hair"] = hair
	app.profile["outfit"] = outfit
	app.profile["skin_color"] = skin
	app.profile["top_color"] = top
	app.refresh_preview()
	await _frames(3)

func _run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	app.show_creator("")
	await _frames(4)
	check(app.mode == "creator", "creator studio opens")
	check(is_instance_valid(app.preview), "creator preview Lifelet exists")

	# Every authored hairstyle, front and three-quarter.
	var names: Array = app.preview.call("authored_hair_styles")
	check(names.size() >= 6, "at least six authored hairstyles (%d)" % names.size())
	for i: int in range(names.size()):
		await _set_style(app, i, i % 5, "d9a17d", "c97c66")
		app.creator_spin = 0.0
		app.frame_creator_camera()
		await _frames(3)
		await _shot("style_%02d_front" % i)
		app.creator_spin = 0.9
		app.frame_creator_camera()
		await _frames(3)
		await _shot("style_%02d_three_quarter" % i)

	# Every authored outfit for the default hairstyle.
	app.creator_spin = 0.0
	for i: int in range(5):
		await _set_style(app, 1, i, "d9a17d", "c97c66")
		app.frame_creator_camera()
		await _frames(3)
		await _shot("outfit_%02d" % i)

	# Face tab close view (the creator's own close crop).
	app.creator_tab = "Face"
	app.frame_creator_camera()
	await _frames(3)
	await _shot("face_close")
	app.creator_tab = "Look"

	# A darker and a lighter skin tone at the same style, to check the
	# material recolour still reaches every new shell.
	await _set_style(app, 1, 0, "8c5a3c", "4f6d8a")
	app.frame_creator_camera()
	await _frames(3)
	await _shot("skin_dark")
	await _set_style(app, 1, 0, "f0cbb0", "e6d3a3")
	app.frame_creator_camera()
	await _frames(3)
	await _shot("skin_light")

	# Live mode at the ordinary play camera, with the HUD drawn.
	app.start_household()
	await _frames(6)
	check(app.mode == "live", "live mode starts after the creator")
	await _shot("live_hud")
	# And from a closer camera, where the head fills more of the frame.
	if is_instance_valid(app.world) and app.world.camera:
		var focus := Vector3(6.5, 1.5, 6.5)
		app.world.camera.position = focus + Vector3(0, 0.35, 2.0)
		app.world.camera.look_at(focus, Vector3.UP)
		await _frames(4)
		await _shot("live_close")

	print("CHARACTER_PROBE: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures:
		print("FAILED ", failure)
	quit(1 if failures.size() > 0 else 0)
