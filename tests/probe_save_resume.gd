extends SceneTree
## Prove that a saved life really resumes with its consequential state intact,
## across a genuine process restart.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_save_resume.gd -- --phase=write
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_save_resume.gd -- --phase=verify
##
## The two phases run in separate processes against the same private
## JUSTLIFE_DATA_DIR, so a passing verify means the state came off disk rather
## than surviving in memory.

const Building = preload("res://scripts/building_state.gd")
const MARKER := "user://save_resume.json"
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

func phase() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			return argument.get_slice("=", 1)
	return "write"

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	if phase() == "write":
		await _write()
	else:
		await _verify()

	print("SAVE_RESUME_RESULT ", JSON.stringify({"phase": phase(), "checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)

func first_valid_spot(kind: String) -> Vector3:
	for xi: int in range(-40, 41):
		for zi: int in range(-40, 41):
			var at := Vector3(float(xi) * 0.25, Building.GROUND_Y, float(zi) * 0.25)
			if app.world.can_place(kind, at, 0.0):
				var proposed: Array = app.world.serialize_items()
				proposed.append({"id": "probe_candidate", "kind": kind, "x": at.x, "z": at.z, "rotation": 0.0})
				if app.build_transactions.furnishing_error(proposed).is_empty():
					return at
	return Vector3(NAN, 0, 0)

func _write() -> void:
	app.new_game()
	await frames(4)
	app.household_profiles[0]["name"] = "Resume Mara"
	app.household_profiles[0]["skin_color"] = "925c40"
	app.household_profiles[0]["height_scale"] = 1.05
	app.add_creator_member()
	await frames(4)
	app.start_household()
	await frames(14)
	check(app.mode == "live", "The household is living before the save")

	# Move time, funds and inventory, so the resumed state has to differ from a
	# fresh game in several independent ways.
	var sim: Object = app.sim
	app.household.set_funds(3456)
	var before: int = app.world.items.size()
	# Buying and placing go through Build & buy, exactly as a player does.
	app.set_build_mode(true)
	await frames(3)
	var spot: Vector3 = first_valid_spot("chair")
	check(spot.is_finite(), "The lot offers a spot the game accepts for a chair")
	app.begin_purchase("chair")
	await frames(3)
	app.on_placement("chair", spot, 0.0)
	await frames(6)
	app.set_build_mode(false)
	await frames(3)
	# Let the clock run, so the day and minute fields really differ from a fresh
	# household rather than being written by the test.
	app.household.set_speed(1)
	await frames(120)
	app.household.set_speed(0)
	await frames(4)

	var name_written: String = str(app.sim.character.name)
	var items_written: int = app.world.items.size()
	check(items_written > before, "A furnishing was really placed before saving (%d -> %d)" % [before, items_written])

	var saved: bool = app.save_game("", "Resume check")
	check(saved, "The life saved through the public save path")
	await frames(6)

	var record: Dictionary = {
		"name": name_written,
		"items": items_written,
		"funds": int(app.sim.funds),
		"day": int(app.household.day),
		"minutes": float(app.household.minutes),
		"played_minutes": float(app.household.minutes),
		"save_id": str(app.active_save_id),
		"members": app.household.members.size(),
	}
	check(not record["save_id"].is_empty(), "The save has an id to resume from")
	var file := FileAccess.open(MARKER, FileAccess.WRITE)
	file.store_string(JSON.stringify(record))
	file.close()
	print("SAVE_RESUME_WROTE ", JSON.stringify(record))

func _verify() -> void:
	check(FileAccess.file_exists(MARKER), "The write phase left a marker to verify against")
	if not FileAccess.file_exists(MARKER):
		return
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MARKER))
	var library: Script = load("res://scripts/save_library.gd")
	var slots: Array = library.list_saves()
	var found: Dictionary = {}
	for slot: Dictionary in slots:
		if str(slot.id) == str(record.save_id):
			found = slot
	check(not found.is_empty(), "The saved life is listed by the save library after restart")
	if found.is_empty():
		return

	app.load_game(str(record.save_id))
	await frames(20)
	check(app.mode == "live", "Loading the saved life returns to Live mode")
	check(str(app.sim.character.name) == str(record.name), "The Lifelet's name resumed (%s vs %s)" % [str(app.sim.character.name), str(record.name)])
	check(app.household.members.size() == int(record.members), "Every household member resumed (%d vs %d)" % [app.household.members.size(), int(record.members)])
	check(int(app.sim.funds) == int(record.funds), "Funds resumed (§%d vs §%d)" % [int(app.sim.funds), int(record.funds)])
	check(int(app.household.day) == int(record.day), "The day resumed (%d vs %d)" % [int(app.household.day), int(record.day)])
	check(absf(float(app.household.minutes) - float(record.minutes)) < 60.0, "The clock resumed (%.0f vs %.0f)" % [float(app.household.minutes), float(record.minutes)])
	check(app.world.items.size() == int(record.items), "The placed furnishing resumed (%d vs %d)" % [app.world.items.size(), int(record.items)])
	# The chosen appearance must survive too, not just the gameplay numbers.
	check(str(app.sim.character.get("skin_color", "")) == "925c40", "The chosen skin tone resumed")
	check(absf(float(app.sim.character.get("height_scale", 0.0)) - 1.05) < 0.001, "The chosen height resumed")

	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://save_resume"))
	root.get_texture().get_image().save_png("user://save_resume/resumed_live.png")
	print("SAVE_RESUME_SHOT ", ProjectSettings.globalize_path("user://save_resume/resumed_live.png"))
