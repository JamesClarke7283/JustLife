extends RefCounted
## Desktop saves live in ~/.justlife. user:// remains an import source only.

const MANIFEST_NAME: String = "save_import.json"
const MAX_IMPORT_BYTES: int = 8 * 1024 * 1024
static var last_error: String = ""
static var _ready: bool = false


static func resolve_root(override_path: String, home_path: String) -> String:
	var path: String = override_path.replace("\\", "/") if not override_path.is_empty() else home_path.replace("\\", "/").path_join(".justlife")
	# Godot's resource aliases and relative paths must never redirect desktop saves.
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://") or not path.is_absolute_path():
		return ""
	if path.replace("\\", "/").split("/").has(".."):
		return ""
	var normalized: String = path.simplify_path()
	return normalized if directory_root(normalized) else normalized.trim_suffix("/")


static func root_path() -> String:
	var home: String = OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	if not OS.has_environment("JUSTLIFE_DATA_DIR") and home.is_empty():
		return ""
	var override_path: String = OS.get_environment("JUSTLIFE_DATA_DIR")
	# An explicitly empty override is a configuration error, not permission to use HOME.
	if OS.has_environment("JUSTLIFE_DATA_DIR") and override_path.is_empty():
		return ""
	return resolve_root(override_path, home)


static func _fail(message: String) -> bool:
	last_error = message
	return false


static func directory_root(path: String) -> bool:
	if path == "/" or (path.length() == 3 and path.substr(1) == ":/"):
		return true
	return path.begins_with("//") and path.trim_prefix("//").split("/", false).size() == 2


static func safe_directory(path: String, create: bool = false) -> bool:
	if path.is_empty() or not path.is_absolute_path():
		return false
	var parent: String = path.get_base_dir()
	if directory_root(path) or parent == path or parent.is_empty():
		return DirAccess.open(path) != null
	if not safe_directory(parent, create):
		return false
	var directory: DirAccess = DirAccess.open(parent)
	var name: String = path.get_file()
	if directory == null or directory.is_link(name):
		return false
	if directory.dir_exists(name):
		return true
	return create and not directory.file_exists(name) and directory.make_dir(name) == OK


static func safe_file(path: String) -> bool:
	if not safe_directory(path.get_base_dir()):
		return false
	var directory: DirAccess = DirAccess.open(path.get_base_dir())
	return directory != null and not directory.is_link(path.get_file()) and not directory.dir_exists(path.get_file())


static func _exists(path: String) -> bool:
	var directory: DirAccess = DirAccess.open(path.get_base_dir())
	return directory != null and (directory.file_exists(path.get_file()) or directory.dir_exists(path.get_file()) or directory.is_link(path.get_file()))


static func _read(path: String) -> Dictionary:
	if not safe_file(path):
		return {"ok":false}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_IMPORT_BYTES:
		return {"ok":false}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	var complete: bool = file.get_position() == file.get_length() and file.get_error() == OK
	file.close()
	return {"ok":complete, "bytes":bytes}


static func _digest(bytes: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


static func _write(path: String, bytes: PackedByteArray, replace: bool = false) -> bool:
	var temporary: String = path + ".tmp"
	if not safe_file(path) or not safe_file(temporary) or (not replace and _exists(path)):
		return false
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	if ok and (replace or not _exists(path)):
		ok = DirAccess.rename_absolute(temporary, path) == OK
	else:
		ok = false
	if not ok and safe_file(temporary):
		DirAccess.remove_absolute(temporary)
	return ok


static func _write_manifest(path: String, manifest: Dictionary) -> bool:
	var bytes: PackedByteArray = JSON.stringify(manifest, "\t").to_utf8_buffer()
	return bytes.size() <= MAX_IMPORT_BYTES and _write(path, bytes, true)


static func _destination_taken(root: String, id: String, reserved: Array) -> bool:
	if reserved.has(id):
		return true
	var paths: Array = [root.path_join("justlife_save.json")] if id == "legacy" else [root.path_join("saves").path_join(id + ".json")]
	paths.append(root.path_join("saves").path_join(id + ".png"))
	if id == "legacy":
		paths.append(root.path_join("saves/legacy.metadata.json"))
	for path: String in paths:
		if _exists(path) or _exists(path + ".tmp"):
			return true
	return false


static func _plan(root: String, old_root: String, valid_id: Callable) -> Dictionary:
	var candidates: Array = []
	var old_saves: String = old_root.path_join("saves")
	if safe_directory(old_saves):
		var directory: DirAccess = DirAccess.open(old_saves)
		for filename: String in directory.get_files():
			var id: String = filename.trim_suffix(".json")
			if filename.ends_with(".json") and id != "legacy" and valid_id.call(id) and safe_file(old_saves.path_join(filename)):
				candidates.append({"source": "saves/" + filename, "id":id})
	if safe_file(old_root.path_join("justlife_save.json")) and FileAccess.file_exists(old_root.path_join("justlife_save.json")):
		candidates.append({"source":"justlife_save.json", "id":"legacy"})
	var reserved: Array = []
	var entries: Array = []
	for candidate: Dictionary in candidates:
		var id: String = candidate.id
		var destination_id: String = id
		var suffix: int = 0
		while _destination_taken(root, destination_id, reserved):
			suffix += 1
			destination_id = "imported_" + id.left(40) + "_" + str(suffix)
		reserved.append(destination_id)
		var entry: Dictionary = {"source":candidate.source, "id":destination_id, "legacy":id == "legacy", "files":[]}
		var destination: String = "justlife_save.json" if destination_id == "legacy" else "saves/" + destination_id + ".json"
		entry.files.append({"source":candidate.source, "destination":destination, "wrap_legacy":id == "legacy" and destination_id != "legacy"})
		for companion: String in [".png", ".metadata.json"] if id == "legacy" else [".png"]:
			var source: String = "saves/" + id + companion
			if companion == ".metadata.json" and destination_id != "legacy":
				continue
			if safe_file(old_root.path_join(source)) and FileAccess.file_exists(old_root.path_join(source)):
				entry.files.append({"source":source, "destination":"saves/" + destination_id + companion, "wrap_legacy":false})
		for item: Dictionary in entry.files:
			var read: Dictionary = _read(old_root.path_join(item.source))
			if not bool(read.ok):
				return {"ok":false}
			item.source_hash = _digest(read.bytes)
		entries.append(entry)
	return {"ok":true, "version":1, "complete":false, "entries":entries}


static func _valid_manifest(manifest: Dictionary, valid_id: Callable) -> bool:
	if manifest.get("version") != 1 or not manifest.get("complete") is bool or not manifest.get("entries") is Array:
		return false
	var targets: Array = []
	for entry: Variant in manifest.entries:
		if not entry is Dictionary or not entry.get("id") is String or not valid_id.call(entry.id) or not entry.get("legacy") is bool or not entry.get("files") is Array:
			return false
		for item: Variant in entry.files:
			if not item is Dictionary or not item.get("source") is String or not item.get("destination") is String or not item.get("source_hash") is String or not item.get("wrap_legacy") is bool:
				return false
			var source: String = item.source
			var source_id: String = source.get_file().trim_suffix(".metadata.json").trim_suffix(".json").trim_suffix(".png")
			if source != "justlife_save.json" and (source.get_base_dir() != "saves" or not valid_id.call(source_id) or not (source.ends_with(".json") or source.ends_with(".png"))):
				return false
			var allowed: Array[String] = ["saves/" + str(entry.id) + ".json", "saves/" + str(entry.id) + ".png"]
			if entry.id == "legacy":
				allowed = ["justlife_save.json", "saves/legacy.png", "saves/legacy.metadata.json"]
			if not allowed.has(item.destination) or targets.has(item.destination) or item.source_hash.length() != 64:
				return false
			targets.append(item.destination)
	return true


static func prepare(valid_id: Callable) -> bool:
	var root: String = root_path()
	if root.is_empty():
		return _fail("Choose an absolute JUSTLIFE_DATA_DIR, or make your home folder available for .justlife saves.")
	if not safe_directory(root, true) or not safe_directory(root.path_join("saves"), true):
		return _fail("The .justlife save folder is unavailable, linked, or cannot be created. Your existing saves were not changed.")
	if _ready:
		last_error = ""
		return true
	var path: String = root.path_join(MANIFEST_NAME)
	var old_root: String = ProjectSettings.globalize_path("user://").trim_suffix("/")
	var manifest: Dictionary
	if _exists(path):
		var read: Dictionary = _read(path)
		if not bool(read.ok):
			return _fail("The save import record cannot be read safely. Your existing saves were not changed.")
		var parser: JSON = JSON.new()
		if parser.parse(read.bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary or not _valid_manifest(parser.data, valid_id):
			return _fail("The save import record is damaged. Your existing saves were not changed.")
		manifest = parser.data
	else:
		manifest = _plan(root, old_root, valid_id) if root != old_root else {"ok":true, "version":1, "complete":true, "entries":[]}
		if not bool(manifest.ok) or not _write_manifest(path, manifest):
			return _fail("Older saves could not be imported safely. The originals remain in Godot's user data folder.")
	if not bool(manifest.complete):
		for entry: Dictionary in manifest.entries:
			for item: Dictionary in entry.files:
				var read: Dictionary = _read(old_root.path_join(item.source))
				if not bool(read.ok) or _digest(read.bytes) != item.source_hash:
					return _fail("An older save changed during import. Its original file and all existing saves were preserved.")
				var bytes: PackedByteArray = read.bytes
				if bool(item.wrap_legacy):
					var parser: JSON = JSON.new()
					if parser.parse(bytes.get_string_from_utf8()) == OK and parser.data is Dictionary:
						# Preserve every original numeric token; re-stringifying parsed
						# doubles with default JSON precision can change action progress.
						var metadata: String = JSON.stringify({"name":"Imported original household", "id":entry.id})
						bytes = ("{\n\t\"save_library_version\": 1,\n\t\"metadata\": " + metadata + ",\n\t\"data\": " + bytes.get_string_from_utf8() + "\n}").to_utf8_buffer()
				var destination: String = root.path_join(item.destination)
				if _exists(destination):
					var previous: Dictionary = _read(destination)
					if not bool(previous.ok) or previous.bytes != bytes:
						return _fail("An import destination is occupied. Existing saves and older originals were preserved.")
				elif not _write(destination, bytes):
					return _fail("An older save could not be copied. The original is still available in Godot's user data folder.")
		manifest.complete = true
		if not _write_manifest(path, manifest):
			return _fail("The save import could not be completed. Existing saves and older originals were preserved.")
	_ready = true
	last_error = ""
	return true
