extends SceneTree

const Library = preload("res://scripts/save_library.gd")
const Household = preload("res://scripts/household.gd")
var checks: int = 0
var failures: int = 0
var backups: Dictionary = {}
var generated_id: String = ""
const TEST_IDS: Array[String] = ["test_library_one", "test_library_two", "test_library_broken", "test_library_large", "test_library_link"]


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func preserve(path: String) -> void:
	backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func listing(id: String) -> Dictionary:
	for entry: Dictionary in Library.list_saves():
		if entry.id == id:
			return entry
	return {}


func run() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path() or not OS.get_environment("XDG_DATA_HOME").is_absolute_path():
		push_error("Save tests require isolated JUSTLIFE_DATA_DIR and XDG_DATA_HOME.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(Library.SAVE_DIR)
	for id: String in TEST_IDS + ["legacy"]:
		for suffix: String in [".json", ".json.tmp", ".png", ".png.tmp"]:
			preserve(Library.SAVE_DIR.path_join(id + suffix))
	preserve(Library.LEGACY_PATH)
	preserve(Library.LEGACY_PATH + ".tmp")
	preserve(Library.SAVE_DIR.path_join("legacy.metadata.json"))
	preserve(Library.SAVE_DIR.path_join("legacy.metadata.json.tmp"))
	var home: LifeHousehold = Household.new()
	root.add_child(home)
	var profiles: Array = []
	for index: int in range(8):
		profiles.append({"name":"Lifelet %d" % index, "traits":["Creative"], "aspiration":"Maker"})
	home.new_household(profiles)
	home.select(7)
	home.selected().queue_action("read", "community_shelf", Vector3(2, .16, 4))
	home.begin_action("housemate_7")
	home.tick(1.0)
	var state: Dictionary = home.get_state([{"id":"favorite_easel", "kind":"easel", "position":Vector3(3, 0, 1)}])
	var preview: Image = Image.create(80, 40, false, Image.FORMAT_RGBA8)
	preview.fill(Color("74a68d"))
	var saved: Dictionary = Library.save_slot("test_library_one", "A quiet home", state, preview)
	check(saved.ok and saved.id == "test_library_one", "A named eight-Lifelet household must save successfully.")
	var entry: Dictionary = listing("test_library_one")
	check(entry.valid and entry.name == "A quiet home" and entry.members.size() == 8 and entry.day == home.day, "Listing metadata must come from the actual household.")
	check(entry.preview_path == Library.SAVE_DIR.path_join("test_library_one.png") and FileAccess.file_exists(entry.preview_path), "Preview paths must point to the exact selected slot's generated PNG.")
	var decoded_preview: Image = Image.load_from_file(entry.preview_path)
	check(decoded_preview.get_width() == 80 and decoded_preview.get_pixel(2, 2).is_equal_approx(Color("74a68d")), "The stored preview must be a usable PNG.")
	var read: Dictionary = Library.read_slot("test_library_one")
	var restored: LifeHousehold = Household.new()
	root.add_child(restored)
	check(read.ok and restored.restore_state(read.data).ok, "A slot must restore through the real household validator.")
	check(restored.members.size() == 8 and restored.selected_id() == "housemate_7" and restored.selected().action_queue.size() == 1, "Save/load must retain all members, selection and an active queue.")
	check(restored.selected().get_current_action().elapsed == 6.0 and restored.selected().get_current_action().target_position == Vector3(2, .16, 4), "Active action progress and destinations must survive the named-slot round-trip.")
	var old_content: PackedByteArray = FileAccess.get_file_as_bytes(Library.SAVE_DIR.path_join("test_library_one.json"))
	var damaged: Dictionary = state.duplicate(true)
	damaged.members[0].state.needs.energy = "bad"
	check(not Library.save_slot("test_library_one", "Must not replace", damaged).ok and FileAccess.get_file_as_bytes(Library.SAVE_DIR.path_join("test_library_one.json")) == old_content, "Invalid state must not replace a previous valid save.")
	check(not FileAccess.file_exists(Library.SAVE_DIR.path_join("test_library_one.json.tmp")), "A completed save must leave no temporary JSON file.")
	check(Library.save_slot("test_library_two", "Another home", state).ok, "A second slot must coexist with the first.")
	check(Library.read_slot("test_library_one").ok and Library.read_slot("test_library_two").ok, "Creating another slot must preserve existing saves.")
	var generated: Dictionary = Library.save_slot("", "New household", state)
	generated_id = str(generated.get("id", ""))
	check(generated.ok and not generated_id.is_empty() and Library.latest_id() == generated_id, "Creating a slot must generate a unique ID and make it the newest readable save.")
	for id: String in ["../test_library_one", "a/b", "a\\b", ".", "A", "%2e%2e"]:
		check(not Library.save_slot(id, "Unsafe path", state).ok and not Library.read_slot(id).ok and not Library.delete_slot(id).ok, "All slot operations must reject path-like or noncanonical IDs.")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Library.SAVE_DIR.path_join("test_library_one.json")))
	envelope.metadata = {"name":{}, "day":9999, "members":["fake"], "preview_path":"/tmp/other-person.png", "saved_at":[]}
	write_json(Library.SAVE_DIR.path_join("test_library_one.json"), envelope)
	entry = listing("test_library_one")
	check(entry.valid and entry.name == "Saved household" and entry.day == home.day and entry.members.size() == 8, "Malformed optional metadata must fall back to validated household information.")
	check(entry.preview_path == Library.SAVE_DIR.path_join("test_library_one.png"), "Metadata must never be able to inject an arbitrary preview path.")
	var broken_file: FileAccess = FileAccess.open(Library.SAVE_DIR.path_join("test_library_broken.json"), FileAccess.WRITE)
	broken_file.store_string("{broken json")
	broken_file.close()
	entry = listing("test_library_broken")
	check(not entry.valid and not entry.error.is_empty() and not Library.read_slot("test_library_broken").ok, "Damaged saves must remain visible for deletion while loading is disabled.")
	var large_file: FileAccess = FileAccess.open(Library.SAVE_DIR.path_join("test_library_large.json"), FileAccess.WRITE)
	large_file.store_string(" ".repeat(Library.MAX_SAVE_BYTES + 1))
	large_file.close()
	check(not Library.read_slot("test_library_large").ok, "Oversized files must be rejected before parsing.")
	var directory: DirAccess = DirAccess.open(Library.SAVE_DIR)
	if OS.get_name() != "Windows":
		var link_status: Error = directory.create_link(ProjectSettings.globalize_path(Library.SAVE_DIR.path_join("test_library_two.json")), "test_library_link.json")
		check(link_status == OK and not Library.read_slot("test_library_link").ok and not Library.delete_slot("test_library_link").ok, "Symbolic links must not let a slot read or delete another file.")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Library.SAVE_DIR.path_join("test_library_link.json")))
	check(Library.save_slot("legacy", "The original home", state, preview).ok, "The fixed legacy slot must support named updates without changing its raw household format.")
	check(Library.read_slot("legacy").ok and listing("legacy").name == "The original home", "Legacy state and its safe metadata sidecar must appear in the picker.")
	var legacy_raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Library.LEGACY_PATH))
	check(legacy_raw.has("household_version") and not legacy_raw.has("save_library_version"), "Legacy saves must remain compatible with the older household loader.")
	var valid_state: Dictionary = restored.get_state()
	for fault: String in ["noncanonical", "self_relation", "missing_relation", "mismatched_name", "fractional_selection", "string_selection"]:
		damaged = state.duplicate(true)
		match fault:
			"noncanonical": damaged.members[1].id = "somebody_else"
			"self_relation": damaged.members[0].state.relationships.player = damaged.members[0].state.relationships.maya.duplicate(true)
			"missing_relation": damaged.members[0].state.relationships.erase("housemate_1")
			"mismatched_name": damaged.members[0].state.relationships.housemate_1.name = "Wrong Lifelet"
			"fractional_selection": damaged.selected_index = .5
			"string_selection": damaged.selected_index = "7"
		check(not restored.restore_state(damaged).ok and restored.get_state() == valid_state, "Malformed household identity '%s' must not mutate the live household." % fault)
	check(Library.delete_slot("test_library_one").ok and not FileAccess.file_exists(Library.SAVE_DIR.path_join("test_library_one.png")), "Deleting a selected slot must remove its state and its own preview.")
	check(Library.read_slot("test_library_two").ok and Library.read_slot(generated_id).ok, "Deleting one slot must preserve every other slot.")
	check(not Library.delete_slot("test_library_one").ok, "Repeated deletion must report a missing slot.")
	check(Library.delete_slot("legacy").ok and not FileAccess.file_exists(Library.LEGACY_PATH), "Deleting legacy must target only its explicit fixed save.")
	Library.delete_slot(generated_id)
	for path: String in backups:
		if backups[path] == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backups[path])
			file.close()
	home.queue_free()
	restored.queue_free()
	await process_frame
	print("Save library: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)
