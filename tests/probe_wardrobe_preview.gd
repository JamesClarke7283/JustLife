extends SceneTree
## Screenshot the wardrobe panel's own close-up preview, once with the look the
## Lifelet arrived in and once after trying a different hairstyle, so the panel is
## checked as the player sees it.
##
##   godot --path . --audio-driver Dummy --script res://tests/probe_wardrobe_preview.gd

var app: Node

func _initialize() -> void:
	_run.call_deferred()

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func shot(name: String) -> void:
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://wardrobe_preview"))
	var path: String = "user://wardrobe_preview/%s.png" % name
	var error: int = root.get_texture().get_image().save_png(path)
	print("WARDROBE_SHOT %s %s %s" % [name, "ok" if error == OK else "FAILED", ProjectSettings.globalize_path(path)])

func try_on(look: Dictionary, index: int) -> void:
	app.world.set_actor_preview(app.bound_member_id, look)
	app.preview_wardrobe_look(look)

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.selected_lot = 0
	app.start_household()
	await frames(12)
	app.household.set_speed(0)
	var mirror: Dictionary = app.world.closest_item("mirror", Vector3.ZERO)
	app.show_wardrobe_panel(str(mirror.id), "hair")
	await frames(8)
	await shot("hair_before")
	# A different hairstyle, through the panel's own row, then a hair colour.
	var look: Dictionary = app.world.actor_preview(app.bound_member_id)
	look["hair"] = 4
	app.preview_wardrobe_look(look)
	await frames(6)
	await shot("hair_after")
	look["hair_color"] = "d7c19a"
	app.preview_wardrobe_look(look)
	await frames(6)
	await shot("hair_colour")
	# Makeup: a lip colour and an eye look, which the panel must show on the face.
	app.show_wardrobe_panel(str(mirror.id), "makeup")
	await frames(8)
	var face: Dictionary = app.world.actor_preview(app.bound_member_id)
	face["makeup_lips"] = "b5453f"
	face["makeup_eyes"] = "6b4a5e"
	app.preview_wardrobe_look(face)
	await frames(6)
	await shot("makeup")
	# Jewelry: a hoop and a chain in a gold metal.
	app.show_wardrobe_panel(str(mirror.id), "jewelry")
	await frames(8)
	var jewelled: Dictionary = app.world.actor_preview(app.bound_member_id)
	jewelled["jewelry_ears"] = "hoop"
	jewelled["jewelry_neck"] = true
	jewelled["jewelry_metal"] = "d8b45a"
	app.preview_wardrobe_look(jewelled)
	await frames(6)
	await shot("jewelry")
	# Clothes: the whole figure, with a different top.
	app.show_wardrobe_panel(str(mirror.id), "clothes")
	await frames(8)
	var dressed: Dictionary = app.world.actor_preview(app.bound_member_id)
	dressed["top_color"] = "557993"
	dressed["bottom_color"] = "343e4b"
	app.preview_wardrobe_look(dressed)
	await frames(6)
	await shot("clothes")
	print("WARDROBE_PREVIEW_DONE")
	app.queue_free(); await frames(3)
	quit(0)
