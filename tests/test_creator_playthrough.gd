extends "res://tests/test_playthrough.gd"
## Targeted creator visual recapture; consequential persistence is checked by home.

func _run() -> void:
	screenshot_dir = "res://art/creator_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.set_sound(false)
	await _enter_new_game()
	await _creator_flow()
	_write_report()
	app.queue_free()
	await frames(3)
	print("CREATOR_RESULT assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
