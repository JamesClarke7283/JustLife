extends SceneTree
## Automatic saving: a five-minute default, a player-chosen interval, and a real
## write through the ordinary save path that a fresh process can load.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_autosave.gd

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path() or not OS.get_environment("XDG_DATA_HOME").is_absolute_path():
		push_error("The autosave test requires isolated JUSTLIFE_DATA_DIR and XDG_DATA_HOME.")
		quit(2); return
	_run.call_deferred()

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(10)
	app.household.set_speed(0)
	await frames(2)

	check(app.autosave_minutes == 5, "A fresh life saves itself every five minutes by default (%d)." % app.autosave_minutes)

	# --- off until the interval elapses -------------------------------------
	app.autosave_wait = 0.0
	app.tick_autosave(60.0)
	check(app.autosave_wait == 60.0 and app.active_save_id.is_empty(),
		"One minute of play does not write before the interval is up (wait=%.0f)." % app.autosave_wait)

	# --- the interval really writes -----------------------------------------
	for i: int in 4:
		app.tick_autosave(60.0)
	check(not app.active_save_id.is_empty(),
		"Reaching five minutes really writes an automatic save (%s)." % app.active_save_id)
	var slot: String = app.active_save_id
	var read: Dictionary = LifeSaveLibrary.read_slot(slot)
	check(bool(read.get("ok", false)), "The automatic save passes the production validator (%s)." % str(read.get("error", "")))

	# --- repeated writes reuse the one slot ---------------------------------
	app.tick_autosave(300.0)
	check(app.active_save_id == slot, "A later automatic write updates the same slot rather than filling the picker (%s)." % app.active_save_id)
	var saves: Array = LifeSaveLibrary.list_saves()
	var automatic: int = saves.filter(func(s: Dictionary) -> bool: return str(s.get("id", "")) == slot).size()
	check(automatic == 1, "The automatic save is one file in the picker (%d)." % automatic)

	# --- the player's own named save is the one kept current -----------------
	check(app.save_game("", "My named life"), "A named save still works alongside the automatic one.")
	var named: String = app.active_save_id
	check(named != slot, "Naming a save creates the player's own slot (%s)." % named)
	app.tick_autosave(300.0)
	check(app.active_save_id == named, "The automatic write now keeps the player's named save current (%s)." % app.active_save_id)

	# --- an interval the player chose ---------------------------------------
	app.autosave_minutes = 1
	app.active_save_id = ""
	app.autosave_wait = 0.0
	app.tick_autosave(59.0)
	check(app.active_save_id.is_empty(), "A one-minute choice still waits its full minute (wait=%.0f)." % app.autosave_wait)
	app.tick_autosave(2.0)
	check(not app.active_save_id.is_empty(), "A one-minute choice writes after a minute (%s)." % app.active_save_id)

	# --- off means off -------------------------------------------------------
	app.autosave_minutes = 0
	app.active_save_id = ""
	app.autosave_wait = 0.0
	app.tick_autosave(600.0)
	check(app.active_save_id.is_empty() and app.autosave_wait == 0.0,
		"Turning automatic saving off writes nothing however long you play.")

	# --- a paused household does not spend the interval ---------------------
	app.autosave_minutes = 5
	app.autosave_wait = 0.0
	app.overlay_open = true
	app.tick_autosave(600.0)
	check(app.autosave_wait == 0.0, "A paused menu spends no automatic-save interval (%d)." % app.autosave_wait)
	app.overlay_open = false

	# --- the setting rides the save -----------------------------------------
	app.autosave_minutes = 10
	app.active_save_id = ""
	app.autosave_wait = 0.0
	app.tick_autosave(600.0)
	check(not app.active_save_id.is_empty(), "The ten-minute choice writes its own save (%s)." % app.active_save_id)
	var saved: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
	var stored: Variant = null
	for member: Dictionary in (saved.get("data", {}) as Dictionary).get("members", []):
		var ws: Dictionary = (member.get("state", {}) as Dictionary).get("character", {}).get("world_state", {})
		if ws.has("autosave_minutes"): stored = ws.autosave_minutes
	check(stored != null and int(stored) == 10, "The chosen interval rides the save (%s)." % str(stored))
	# And it really comes back: a fresh process loading that exact slot restores
	# it, rather than falling back to the default.
	var before:int=app.autosave_minutes
	app.load_game(app.active_save_id)
	for i: int in 60: await process_frame
	check(app.autosave_minutes == before,
		"A fresh load of that save restores the chosen interval (%d -> %d)." % [before, app.autosave_minutes])

	app.queue_free(); await frames(3)
	print("AUTOSAVE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
