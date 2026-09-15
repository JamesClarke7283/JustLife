extends SceneTree
## Prove the interface really adapts to different window shapes, by resizing the
## actual window and inspecting the drawn HUD at each size.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_interface_fit.gd
##
## The project stretches with `canvas_items`/`expand`, so a window larger than
## 1440x900 grows the canvas rather than scaling the design. This checks the
## interface is fitted and centred in that grown canvas, at each size, from the
## real rendered frame.

const OUT := "user://interface_fit"
const SIZES: Array[Vector2i] = [
	Vector2i(1440, 900), Vector2i(1280, 614), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(2560, 1080),
]
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

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(12)
	app.household.set_speed(0)
	app.draw_live()
	await frames(4)

	for size: Vector2i in SIZES:
		get_root().size = size
		await frames(8)
		app.draw_live()
		await frames(6)
		var window: Vector2 = root.get_visible_rect().size
		var design: Rect2 = Rect2(app.ui.position, app.ui.size * app.ui.scale)
		var label: String = "%dx%d" % [size.x, size.y]
		print("FIT %s window=%s design=%s" % [label, str(window), str(design)])
		# The design must fit inside the window and fill it on its tight axis.
		check(design.position.x >= -1.0 and design.position.y >= -1.0, "%s: the interface starts inside the window" % label)
		check(design.end.x <= window.x + 1.0 and design.end.y <= window.y + 1.0, "%s: the interface ends inside the window" % label)
		var covered_x: float = design.size.x / window.x
		var covered_y: float = design.size.y / window.y
		check(maxf(covered_x, covered_y) > 0.97, "%s: the interface fills its tight axis (%.3f x, %.3f y)" % [label, covered_x, covered_y])
		# Centring: the leftover margin is shared between both sides.
		var left: float = design.position.x
		var right: float = window.x - design.end.x
		check(absf(left - right) < 4.0, "%s: the interface is horizontally centred (%.1f vs %.1f)" % [label, left, right])
		# The HUD's own top bar must be on screen, not in the leftover margin.
		var bar: Control = null
		for node: Node in app.ui.get_children():
			if node is Panel and (node as Control).name.is_empty(): continue
		for node: Node in app.find_children("*", "Button", true, false):
			if node is Button and str(node.text) == "Build & buy":
				bar = node
				break
		if bar != null:
			var rect: Rect2 = bar.get_global_rect()
			check(rect.position.x >= 0.0 and rect.end.x <= window.x, "%s: the top bar sits inside the window (%s)" % [label, str(rect)])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join("fit_%dx%d.png" % [size.x, size.y]))

	get_root().size = Vector2i(1440, 900)
	await frames(4)
	print("INTERFACE_FIT_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
