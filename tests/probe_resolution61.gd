extends SceneTree
## Render the live HUD and the creator at a smaller supported window, to check
## the interface still fits and stays legible.
##
##   godot --path . --audio-driver Dummy --script res://tests/probe_resolution61.gd
##
## The project's configured viewport is 1440x900; this exercises the same
## screens at 960x600, which the iteration 61 review left unverified.

const OUT := "res://evidence/resolution61"
const SIZES: Array = [Vector2i(1440, 900), Vector2i(960, 600), Vector2i(1280, 720)]

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

## Every visible Control must sit inside the viewport, and any that does not is
## named. The canvas layer itself is a CanvasLayer, so the walk starts from its
## Control children.
func _offscreen(app: Node, size: Vector2i) -> Array[String]:
	var bad: Array[String] = []
	var stack: Array = []
	var visited: int = 0
	for child: Node in app.get_node("Interface").get_children():
		if child is Control:
			stack.append(child)
	while not stack.is_empty():
		var node: Control = stack.pop_back()
		visited += 1
		for child: Node in node.get_children():
			if child is Control:
				stack.append(child)
		if not node.visible:
			continue
		var rect: Rect2 = node.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		# Allow a small tolerance for the expand stretch mode's rounding.
		if rect.position.x < -2.0 or rect.position.y < -2.0 \
				or rect.end.x > float(size.x) + 2.0 or rect.end.y > float(size.y) + 2.0:
			var name: String = node.name
			if node is Label or node is Button:
				name = "%s(%s)" % [node.name, str(node.get("text")).left(24)]
			bad.append("%s at %s" % [name, str(rect)])
	# A traversal that visited almost nothing would pass vacuously; the game
	# always draws dozens of controls, so assert the walk actually happened.
	if visited < 20:
		bad.append("walk visited only %d controls — the check did not run" % visited)
	return bad

func _run() -> void:
	var requested: Array = SIZES.duplicate()
	for size: Vector2i in requested:
		DisplayServer.window_set_size(size)
		await _frames(6)
		# The window manager may refuse the resize; measure what we actually got
		# and check against that, so the result is never a comparison between
		# the requested size and a differently-sized real viewport.
		var actual: Vector2i = DisplayServer.window_get_size()
		var viewport: Vector2i = Vector2i(root.size)
		var app = load("res://scenes/main.tscn").instantiate()
		root.add_child(app)
		await _frames(6)

		var label := "asked %dx%d, got window %dx%d / viewport %dx%d" % [
			size.x, size.y, actual.x, actual.y, viewport.x, viewport.y]
		print("RESOLUTION ", label)

		app.start_household()
		await _frames(8)
		# The UI is laid out in canvas space, which the `expand` stretch mode
		# scales to the window; `root.size` is the physical viewport and is not
		# the space the controls live in. The full-rect `UI` control IS the canvas.
		var canvas: Vector2 = (app.get_node("Interface/UI") as Control).size
		print("RESOLUTION canvas %s for viewport %s" % [str(canvas), str(viewport)])
		var live_bad: Array[String] = _offscreen(app, Vector2i(canvas))
		check(live_bad.is_empty(), "Live HUD fits canvas %s%s" % [str(canvas),
			"" if live_bad.is_empty() else " — overflowing: " + ", ".join(live_bad.slice(0, 3))])
		await _shot("live_%d" % size.x)

		# The creator's right-hand rubric card is the widest panel in the game.
		app.show_creator("")
		await _frames(8)
		canvas = (app.get_node("Interface/UI") as Control).size
		var creator_bad: Array[String] = _offscreen(app, Vector2i(canvas))
		check(creator_bad.is_empty(), "Creator fits canvas %s%s" % [str(canvas),
			"" if creator_bad.is_empty() else " — overflowing: " + ", ".join(creator_bad.slice(0, 3))])
		await _shot("creator_%d" % size.x)

		app.queue_free()
		await _frames(3)

	print("RESOLUTION_PROBE: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures:
		print("FAILED ", failure)
	quit(1 if failures.size() > 0 else 0)
