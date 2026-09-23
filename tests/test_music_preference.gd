extends SceneTree
## Music/sound toggles must survive a restart without a household save.
##
##   JUSTLIFE_DATA_DIR=… XDG_DATA_HOME=… godot --headless --path . \
##     --audio-driver Dummy --script res://tests/test_music_preference.gd

var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _music_playing(app: Node) -> bool:
	var player: AudioStreamPlayer = app.music_player
	return is_instance_valid(player) and player.playing and not player.stream_paused

func _spawn_app() -> Node:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	return app

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path() or not OS.get_environment("XDG_DATA_HOME").is_absolute_path():
		push_error("The music preference test requires isolated JUSTLIFE_DATA_DIR and XDG_DATA_HOME.")
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var prefs_path: String = OS.get_environment("JUSTLIFE_DATA_DIR").path_join("settings.json")
	check(not FileAccess.file_exists(prefs_path), "A fresh data dir starts with no audio settings file.")

	var app: Node = _spawn_app()
	await frames(8)
	check(app.music_enabled and app.sound_enabled, "Default launch enables music and sound.")
	check(_music_playing(app), "Default launch starts the theme while music is on.")

	app.set_music(false)
	await frames(2)
	check(not app.music_enabled, "Turning music off updates the in-memory toggle.")
	check(not _music_playing(app), "Turning music off stops the theme immediately.")
	check(FileAccess.file_exists(prefs_path), "Turning music off writes settings.json under the data dir.")
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(prefs_path))
	check(stored is Dictionary and stored.get("music") == false and stored.get("sound") == true,
		"settings.json records music off while leaving sound on.")

	app.queue_free()
	await frames(4)

	# Same process, fresh controller: mirrors quitting and launching again against
	# the same JUSTLIFE_DATA_DIR without touching a household save.
	app = _spawn_app()
	await frames(8)
	check(not app.music_enabled, "A fresh controller reads music off from settings.json.")
	check(app.sound_enabled, "Sound stays on when only music was muted.")
	check(not _music_playing(app), "A restart with music off does not start the theme.")

	app.set_music(true)
	await frames(2)
	check(app.music_enabled and _music_playing(app), "Turning music back on starts the theme again.")
	stored = JSON.parse_string(FileAccess.get_file_as_string(prefs_path))
	check(stored is Dictionary and stored.get("music") == true, "Turning music on rewrites settings.json.")

	app.queue_free()
	await frames(4)
	app = _spawn_app()
	await frames(8)
	check(app.music_enabled and _music_playing(app), "A later restart keeps music on after it was re-enabled.")

	app.set_sound(false)
	await frames(2)
	check(not app.sound_enabled and not _music_playing(app), "Sound off also silences the theme.")
	app.queue_free()
	await frames(4)
	app = _spawn_app()
	await frames(8)
	check(not app.sound_enabled and app.music_enabled and not _music_playing(app),
		"A restart keeps sound off and leaves music preference on but silent.")

	print("MUSIC_PREF_RESULT assertions=%d failures=%d" % [checks, failures.size()])
	for why: String in failures: printerr("CHECK FAIL: ", why)
	quit(0 if failures.is_empty() else 1)
