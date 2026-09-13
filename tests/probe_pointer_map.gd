extends SceneTree
## Derive the exact window -> canvas pointer mapping, empirically.
##
##   godot --path . --audio-driver Dummy --script res://tests/probe_pointer_map.gd
##
## `Input.warp_mouse` takes window coordinates while `Viewport.get_mouse_position`
## (which the world previews read) reports canvas coordinates under the game's
## `canvas_items` stretch mode. This warps to known window points and prints what
## comes back, so the conversion can be written from measurement, not assumption.

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

func _frames(n: int) -> void:
	for i: int in range(n):
		await process_frame

func _run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await _frames(8)
	app.start_household()
	await _frames(10)

	var window: Vector2 = Vector2(DisplayServer.window_get_size())
	var viewport_size: Vector2 = Vector2(root.size)
	var visible_rect: Vector2 = root.get_visible_rect().size
	var canvas: Vector2 = (app.get_node("Interface/UI") as Control).size
	print("SPACES window=%s root.size=%s visible_rect=%s canvas=%s" % [
		str(window), str(viewport_size), str(visible_rect), str(canvas)])

	# Warp to several window points and read back the canvas-space pointer.
	var probes: Array = [
		window * 0.25,
		window * 0.5,
		Vector2(window.x * 0.35, window.y * 0.5),
		Vector2(window.x * 0.6, window.y * 0.4),
	]
	var ratios: Array[float] = []
	for target: Vector2 in probes:
		Input.warp_mouse(target)
		var event := InputEventMouseMotion.new()
		event.position = target
		event.global_position = target
		Input.parse_input_event(event)
		await _frames(4)
		var read_back: Vector2 = root.get_mouse_position()
		var ratio: float = read_back.x / target.x if target.x > 1.0 else 0.0
		ratios.append(ratio)
		print("PROBE warp_window=%s -> canvas_read=%s  x_ratio=%.5f" % [
			str(target), str(read_back), ratio])

	# The ratio must be the same across the probes if the mapping is a pure scale.
	var spread: float = 0.0
	if ratios.size() > 1:
		var lo: float = ratios[0]
		var hi: float = ratios[0]
		for r: float in ratios:
			lo = minf(lo, r)
			hi = maxf(hi, r)
		spread = hi - lo
	print("RATIOS min=%.5f max=%.5f spread=%.6f" % [
		ratios.min() if ratios.size() else 0.0, ratios.max() if ratios.size() else 0.0, spread])
	check(spread < 0.002, "The window->canvas pointer mapping is a pure uniform scale")
	# And the scale should match canvas/window if the canvas is the logical space.
	var expected: float = canvas.x / window.x
	print("EXPECTED canvas/window x-scale = %.5f ; measured = %.5f" % [expected, ratios[0]])

	print("POINTER_MAP_PROBE: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)
