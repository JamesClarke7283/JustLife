extends SceneTree
## Run only with JUSTLIFE_DATA_DIR set to an invalid, isolated fixture location.
var checks: int = 0
var failures: int = 0
var app: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func text_present(value: String) -> bool:
	for label: Node in app.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and str(label.text).contains(value):
			return true
	return false

func _run() -> void:
	if OS.get_environment("JUSTLIFE_DATA_DIR") != "invalid-storage-fixture" or not OS.has_environment("XDG_DATA_HOME"):
		push_error("The error picker test requires its isolated invalid-path override.")
		quit(2)
		return
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.set_sound(false)
	await process_frame
	app.menus.show_picker("load")
	await process_frame
	check(app.overlay_open and text_present("Your saves need attention."), "The actual picker displays storage failure distinctly from an empty library.")
	check(text_present("absolute JUSTLIFE_DATA_DIR"), "The actual picker includes actionable path correction text.")
	check(not text_present("Your first story starts here."), "A blocked library does not pretend it contains no saves.")
	check(not LifeSaveLibrary.storage_error().is_empty(), "The backend exposes the same error to the controller.")
	app.close_overlay()
	check(not app.overlay_open and app.mode == "menu", "Closing the error keeps the main menu usable.")
	app.queue_free()
	await process_frame
	await process_frame
	print("Save picker storage: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
