extends SceneTree
## Run through run_save_storage.py: both new storage and old user:// are isolated.
const Library = preload("res://scripts/save_library.gd")
const Storage = preload("res://scripts/save_storage.gd")
const Household = preload("res://scripts/household.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func write_json(path: String, data: Dictionary) -> void:
	write_bytes(path, JSON.stringify(Library._json_safe(data), "\t").to_utf8_buffer())


func write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()


func profile_state(name: String) -> Dictionary:
	var home: LifeHousehold = Household.new()
	home.new_household([{"name":name, "traits":["Creative"], "aspiration":"Maker"}])
	var state: Dictionary = Library._json_safe(home.get_state())
	home.free()
	return state


func listing(id: String) -> Dictionary:
	for entry: Dictionary in Library.list_saves():
		if entry.id == id:
			return entry
	return {}


func _run() -> void:
	if not OS.has_environment("JUSTLIFE_DATA_DIR") or not OS.has_environment("XDG_DATA_HOME"):
		push_error("This test requires isolated JUSTLIFE_DATA_DIR and XDG_DATA_HOME.")
		quit(2)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var phase: String = args[0] if not args.is_empty() else ""
	match phase:
		"fixture": fixture()
		"migrate": migrate()
		"restart": restart()
		"blocked": blocked()
		"recovery_fixture": recovery_fixture()
		"recover": recover()
		"legacy_fixture": legacy_fixture()
		"legacy": legacy()
		"paths": paths()
		"probe_valid": check(preload("res://scripts/release_probe.gd").isolated_environment(), "Release probe accepts both explicit private directories.")
		"probe_invalid": check(not preload("res://scripts/release_probe.gd").isolated_environment(), "Release probe rejects incomplete or mismatched isolation.")
		"empty": check(Library.list_saves().is_empty() and Library.storage_error().is_empty(), "No deleted or linked source is imported.")
		_: check(false, "Unknown storage test phase.")
	print("Save storage %s: %d checks, %d failures." % [phase, checks, failures])
	quit(1 if failures else 0)


func fixture() -> void:
	var root_path: String = Storage.root_path()
	var old_state: Dictionary = profile_state("Old Neighbor")
	old_state.minutes = 527.1234567890123
	old_state.members[0].state.minutes = old_state.minutes
	var native_state: Dictionary = profile_state("New Neighbor")
	var envelope: Dictionary = {"save_library_version":1, "metadata":{"id":"shared", "name":"Old shared"}, "data":old_state}
	write_json("user://saves/shared.json", envelope)
	envelope.metadata.id = "old_only"
	write_json("user://saves/old_only.json", envelope)
	write_bytes("user://justlife_save.json", JSON.stringify(old_state, "\t", true, true).to_utf8_buffer())
	write_bytes("user://saves/damaged.json", "{broken json".to_utf8_buffer())
	var preview: Image = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	preview.fill(Color("74a68d"))
	preview.save_png("user://saves/shared.png")
	preview.save_png("user://saves/legacy.png")
	write_json("user://saves/legacy.metadata.json", {"name":"The old original"})
	write_json(root_path.path_join("saves/shared.json"), {"save_library_version":1, "metadata":{"name":"New shared"}, "data":native_state})
	write_json(root_path.path_join("justlife_save.json"), native_state)
	var sources: Dictionary = {}
	for path: String in ["user://saves/shared.json", "user://saves/old_only.json", "user://saves/damaged.json", "user://saves/shared.png", "user://saves/legacy.png", "user://saves/legacy.metadata.json", "user://justlife_save.json"]:
		sources[path] = FileAccess.get_sha256(path)
	write_json("user://source_hashes.json", sources)
	check(not FileAccess.file_exists(root_path.path_join(Storage.MANIFEST_NAME)), "Fixtures are old and new physical files before first library use.")


func migrate() -> void:
	var saves: Array = Library.list_saves()
	check(Library.storage_error().is_empty() and saves.size() == 6, "First listing imports two named originals, damaged original and legacy while preserving both new collisions.")
	check(Library.read_slot("shared").data.members[0].state.character.name == "New Neighbor", "Named collision keeps the new destination unchanged.")
	check(Library.read_slot("imported_shared_1").data.members[0].state.character.name == "Old Neighbor", "Named collision is readable under a separate stable imported ID.")
	check(Library.read_slot("legacy").data.members[0].state.character.name == "New Neighbor", "Legacy collision keeps the existing raw household unchanged.")
	check(Library.read_slot("imported_legacy_1").data.members[0].state.character.name == "Old Neighbor", "Colliding original household remains accessible through its own named slot.")
	var original_legacy: String = FileAccess.get_file_as_string("user://justlife_save.json")
	var imported_legacy: Dictionary = Library.read_slot("imported_legacy_1").data
	check(FileAccess.get_file_as_string(Library.SAVE_DIR.path_join("imported_legacy_1.json")).contains(original_legacy), "The collision envelope embeds the original raw JSON payload verbatim.")
	check(imported_legacy.minutes == 527.1234567890123 and imported_legacy.members[0].state.minutes == 527.1234567890123, "Legacy collision preserves exact high-precision saved clock values without a tolerance.")
	check(Library.read_slot("old_only").ok, "Noncolliding imported named save retains its original ID.")
	check(not listing("damaged").valid and FileAccess.get_file_as_bytes(Library.SAVE_DIR.path_join("damaged.json")) == FileAccess.get_file_as_bytes("user://saves/damaged.json"), "Damaged originals remain byte-exact and visible as unreadable saves.")
	check(FileAccess.get_file_as_bytes(Library.SAVE_DIR.path_join("imported_shared_1.json")) == FileAccess.get_file_as_bytes("user://saves/shared.json"), "Named migration copies the original bytes even when its slot ID changes.")
	check(FileAccess.get_file_as_bytes(listing("imported_shared_1").preview_path) == FileAccess.get_file_as_bytes("user://saves/shared.png"), "Named collision carries its exact own preview.")
	check(FileAccess.get_file_as_bytes(listing("imported_legacy_1").preview_path) == FileAccess.get_file_as_bytes("user://saves/legacy.png"), "Legacy collision carries its own preview.")
	check(FileAccess.get_file_as_bytes(Library.SAVE_DIR.path_join("old_only.json")) == FileAccess.get_file_as_bytes("user://saves/old_only.json"), "Noncolliding named migration is byte-exact.")
	check(Library.delete_slot("imported_shared_1").ok and Library.delete_slot("damaged").ok, "Selected imported saves can be deleted through the normal backend.")
	var preview: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	preview.fill(Color.BLUE)
	var saved: Dictionary = Library.save_slot("", "A new home", profile_state("Fresh Lifelet"), preview)
	check(saved.ok and FileAccess.file_exists(Library.SAVE_DIR.path_join(str(saved.id) + ".json")), "Creating a named game writes inside the requested storage root/saves.")
	check(Library.SAVE_DIR == OS.get_environment("JUSTLIFE_DATA_DIR").path_join("saves"), "The explicit data-directory override is the final root, without another .justlife suffix.")
	write_json("user://expected.json", {"new_id":saved.id})
	check_sources_unchanged()


func check_sources_unchanged() -> void:
	var sources: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://source_hashes.json"))
	for path: String in sources:
		check(FileAccess.get_sha256(path) == sources[path], "Import and deletion preserve the original bytes: " + path)


func restart() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://expected.json"))
	var saves: Array = Library.list_saves()
	check(saves.size() == 5, "Fresh process contains the four surviving originals and one new game.")
	check(listing("imported_shared_1").is_empty() and listing("damaged").is_empty(), "A completed migration never resurrects deleted imports at restart.")
	var saved: Dictionary = Library.read_slot(expected.new_id)
	check(saved.ok and saved.data.members[0].state.character.name == "Fresh Lifelet", "New game survives a fresh-process load from the requested directory.")
	check(Library.read_slot("imported_legacy_1").ok and Library.read_slot("old_only").ok, "Legacy and named imports remain readable across restart.")
	var preview: String = str(listing(expected.new_id).preview_path)
	check(Library.delete_slot(expected.new_id).ok and not FileAccess.file_exists(preview), "Deleting a new saved game removes its own JSON and preview.")
	check_sources_unchanged()


func paths() -> void:
	check(Storage.resolve_root("", "/home/example") == "/home/example/.justlife", "Desktop Unix home uses the requested dot folder.")
	check(Storage.resolve_root("", "C:/Users/Example") == "C:/Users/Example/.justlife", "Desktop Windows profile uses the requested dot folder.")
	check(Storage.resolve_root("", "C:\\Users\\Example") == "C:/Users/Example/.justlife", "Windows profile backslashes normalize without changing the chosen directory.")
	check(Storage.directory_root("C:/") and Storage.resolve_root("C:/", "") == "C:/", "Windows drive roots retain their slash and end directory recursion.")
	check(Storage.directory_root("//server/share") and not Storage.directory_root("//server/share/folder"), "UNC recursion stops at the share root, not the server or a child folder.")
	check(Storage.resolve_root("/custom/saves", "/home/example") == "/custom/saves", "Override is the exact final root.")
	for path: String in ["relative", "user://saves", "res://saves", "/safe/../other"]:
		check(Storage.resolve_root(path, "/home/example").is_empty(), "Relative/resource/traversal overrides are rejected: " + path)


func blocked() -> void:
	check(Library.list_saves().is_empty() and not Library.storage_error().is_empty(), "Unsafe or damaged storage returns an actionable error rather than a usable library.")
	check(not Library.save_slot("blocked", "Blocked", profile_state("No Write")).ok, "Unsafe storage refuses new save writes.")
	check(not Library.read_slot("legacy").ok and not Library.delete_slot("legacy").ok, "Legacy APIs cannot bypass storage safety.")


func recovery_fixture() -> void:
	var state: Dictionary = profile_state("Recovered Lifelet")
	write_json("user://saves/recovery.json", {"save_library_version":1, "metadata":{"name":"Recovered"}, "data":state})
	var preview: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	preview.fill(Color.RED)
	preview.save_png("user://saves/recovery.png")
	var root_path: String = Storage.root_path()
	DirAccess.make_dir_recursive_absolute(root_path.path_join("saves"))
	var old_root: String = ProjectSettings.globalize_path("user://").trim_suffix("/")
	var plan: Dictionary = Storage._plan(root_path, old_root, Library._valid_id)
	check(Storage._write_manifest(root_path.path_join(Storage.MANIFEST_NAME), plan), "Reserve destinations before the first copied file, as the migration does.")
	write_bytes(root_path.path_join("saves/recovery.json"), FileAccess.get_file_as_bytes("user://saves/recovery.json"))
	check(not FileAccess.file_exists(root_path.path_join("saves/recovery.png")), "Recovery fixture stops between copying the state and preview.")


func recover() -> void:
	check(Library.list_saves().size() == 1 and Library.read_slot("recovery").ok, "A fresh process resumes a partially copied import using the reserved ID.")
	check(FileAccess.get_file_as_bytes(listing("recovery").preview_path) == FileAccess.get_file_as_bytes("user://saves/recovery.png"), "Recovery finishes the previously missing preview without replacing the state.")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Storage.root_path().path_join(Storage.MANIFEST_NAME)))
	check(record.complete, "Successful recovery marks the import complete before normal save operations resume.")


func legacy_fixture() -> void:
	write_json("user://justlife_save.json", profile_state("Original Lifelet"))
	write_json("user://saves/legacy.metadata.json", {"name":"Original chapter"})


func legacy() -> void:
	check(Library.list_saves().size() == 1 and Library.read_slot("legacy").ok and listing("legacy").name == "Original chapter", "A noncolliding raw legacy save retains its fixed ID and display name.")
	check(FileAccess.get_file_as_bytes(Library.LEGACY_PATH) == FileAccess.get_file_as_bytes("user://justlife_save.json"), "Legacy migration without collision preserves the destination bytes exactly.")
	check(Library.delete_slot("legacy").ok and FileAccess.file_exists("user://justlife_save.json"), "Deleting imported legacy preserves its old source.")
