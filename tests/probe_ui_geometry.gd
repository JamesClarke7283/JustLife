extends SceneTree
## Print the exact rectangles of the controls the overlap oracle flags, so a
## reported blockage can be confirmed or dismissed with real geometry.
var app: Node
func _initialize() -> void: _run.call_deferred()
func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func dump(label: String) -> void:
	print("--- ", label)
	for node: Node in app.find_children("*", "Button", true, false):
		var b: Button = node
		if not b.is_visible_in_tree(): continue
		if str(b.name).begins_with("@") and str(b.text).is_empty():
			print("   UNNAMED ", b.get_global_rect(), " parent=", b.get_parent().name, " filter=", b.mouse_filter)
	for text: String in ["Rewards", "Cancel action", "Storage", "Undo", "All"]:
		for node: Node in app.find_children("*", "Button", true, false):
			var b: Button = node
			if b.is_visible_in_tree() and str(b.text) == text:
				print("   ", text, " ", b.get_global_rect(), " parent=", b.get_parent().name)

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	app.start_household()
	await frames(10)
	app.household.set_speed(0)
	app.draw_live()
	await frames(3)
	dump("live HUD")
	app.set_build_mode(true)
	await frames(4)
	dump("build")
	quit()
