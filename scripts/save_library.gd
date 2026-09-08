extends RefCounted
class_name LifeSaveLibrary
## Named local households. All paths are derived here from a restricted slot ID.

const Household = preload("res://scripts/household.gd")
const SAVE_DIR: String = "user://saves"
const LEGACY_PATH: String = "user://justlife_save.json"
const MAX_SAVE_BYTES: int = 8 * 1024 * 1024
const LIBRARY_VERSION: int = 1


static func _valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 64 or id.begins_with("_") or id.begins_with("-"):
		return false
	for character: String in id:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true


static func _directory_safe(create: bool = false) -> bool:
	var user_directory: DirAccess = DirAccess.open("user://")
	if user_directory == null or user_directory.is_link("saves"):
		return false
	if not user_directory.dir_exists("saves"):
		return create and user_directory.make_dir("saves") == OK
	return true


static func _safe_file(path: String) -> bool:
	var directory: DirAccess = DirAccess.open(path.get_base_dir())
	return directory != null and not directory.is_link(path.get_file()) and not directory.dir_exists(path.get_file())


static func _slot_path(id: String) -> String:
	return LEGACY_PATH if id == "legacy" else SAVE_DIR.path_join(id + ".json")


static func _preview_path(id: String) -> String:
	return SAVE_DIR.path_join(id + ".png")


static func _error(message: String) -> Dictionary:
	return {"ok":false, "error":message}


static func _read_json(path: String, maximum_bytes: int = MAX_SAVE_BYTES) -> Dictionary:
	if not _safe_file(path) or not FileAccess.file_exists(path):
		return _error("The selected save is missing or cannot be read safely.")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("The selected save could not be opened.")
	if file.get_length() > maximum_bytes:
		file.close()
		return _error("The selected save exceeds the supported file size.")
	var parser: JSON = JSON.new()
	var status: Error = parser.parse(file.get_as_text())
	file.close()
	if status != OK or not parser.data is Dictionary:
		return _error("The selected save is damaged.")
	return {"ok":true, "data":parser.data}


static func _validate_household(state: Dictionary) -> Dictionary:
	# Guard version conversions in the legacy simulator before asking it to load.
	var member_states: Array = [state]
	if state.has("household_version"):
		if not state.get("members") is Array:
			return _error("The household member list is invalid.")
		member_states = []
		for member: Variant in state.members:
			if not member is Dictionary or not member.get("state") is Dictionary:
				return _error("The household contains an invalid Lifelet.")
			member_states.append(member.state)
	for member_state: Dictionary in member_states:
		var version: Variant = member_state.get("version")
		if not (version is int or version is float) or not is_finite(float(version)) or float(version) != 1.0:
			return _error("This household uses an unsupported simulator version.")
	var household: LifeHousehold = Household.new()
	var result: Dictionary = household.restore_state(state)
	household.free()
	return result


static func _json_safe(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Color:
		return value.to_html()
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_json_safe(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[str(key)] = _json_safe(value[key])
		return result
	return value


static func _atomic_json(path: String, data: Dictionary) -> Dictionary:
	var temporary: String = path + ".tmp"
	if not _safe_file(path) or not _safe_file(temporary):
		return _error("The save location cannot be written safely.")
	var content: String = JSON.stringify(_json_safe(data), "\t")
	if content.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _error("This household is too large to save.")
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("The save file could not be written.")
	file.store_string(content)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _error("Saving failed; the previous save is still available.")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _error("The previous save could not be replaced.")
	return {"ok":true}


static func _new_id() -> String:
	var id: String = "life_%d_%d" % [int(Time.get_unix_time_from_system() * 1000.0), Time.get_ticks_usec()]
	var suffix: int = 0
	while FileAccess.file_exists(_slot_path(id)):
		suffix += 1
		id = "life_%d_%d" % [int(Time.get_unix_time_from_system() * 1000.0), Time.get_ticks_usec() + suffix]
	return id


static func _clean_name(name: String) -> String:
	var result: String = name.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(60)
	return "My household" if result.is_empty() else result


static func _summary(state: Dictionary) -> Dictionary:
	var names: Array[String] = []
	var state_day: int = int(state.get("day", 1))
	var state_minutes: int = int(state.get("minutes", 480))
	if state.has("household_version"):
		for member: Dictionary in state.members:
			names.append(str(member.state.character.name))
		if not state.has("day"):
			state_day = int(state.members[0].state.day)
		if not state.has("minutes"):
			state_minutes = int(state.members[0].state.minutes)
	else:
		names.append(str(state.character.name))
	return {"day":state_day, "minutes":state_minutes, "members":names}


static func save_slot(id: String, name: String, state: Dictionary, preview: Image = null) -> Dictionary:
	if not id.is_empty() and not _valid_id(id):
		return _error("The save slot ID is invalid.")
	var validation: Dictionary = _validate_household(state)
	if not bool(validation.ok):
		return _error(str(validation.get("error", "This household cannot be saved.")))
	if not _directory_safe(true):
		return _error("The save directory cannot be used safely.")
	var slot_id: String = _new_id() if id.is_empty() else id
	var metadata: Dictionary = _summary(state)
	metadata.merge({"id":slot_id, "name":_clean_name(name), "saved_at":Time.get_datetime_string_from_system(true), "saved_at_unix":Time.get_unix_time_from_system()}, true)
	var data: Dictionary = state if slot_id == "legacy" else {"save_library_version":LIBRARY_VERSION, "metadata":metadata, "data":state}
	var written: Dictionary = _atomic_json(_slot_path(slot_id), data)
	if not bool(written.ok):
		return written
	var warning: String = ""
	if slot_id == "legacy":
		var metadata_result: Dictionary = _atomic_json(SAVE_DIR.path_join("legacy.metadata.json"), metadata)
		if not bool(metadata_result.ok):
			warning = "The household was saved, but its display name could not be updated."
	if preview != null and not preview.is_empty():
		var preview_path: String = _preview_path(slot_id)
		var temporary: String = preview_path + ".tmp"
		if not _safe_file(preview_path) or not _safe_file(temporary):
			warning = "The household was saved, but its preview could not be updated."
		else:
			var thumbnail: Image = preview.duplicate()
			var ratio: float = minf(1.0, 640.0 / float(maxi(thumbnail.get_width(), thumbnail.get_height())))
			thumbnail.resize(maxi(1, int(thumbnail.get_width() * ratio)), maxi(1, int(thumbnail.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
			if thumbnail.save_png(temporary) != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(preview_path)) != OK:
				warning = "The household was saved, but its preview could not be updated."
				if _safe_file(temporary) and FileAccess.file_exists(temporary):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	var result: Dictionary = {"ok":true, "id":slot_id}
	if not warning.is_empty():
		result.warning = warning
	return result


static func read_slot(id: String) -> Dictionary:
	if not _valid_id(id) or (id != "legacy" and not _directory_safe()):
		return _error("The save slot ID or directory is invalid.")
	var read: Dictionary = _read_json(_slot_path(id))
	if not bool(read.ok):
		return read
	var state: Dictionary = read.data
	if id != "legacy":
		if state.get("save_library_version") != LIBRARY_VERSION or not state.get("data") is Dictionary:
			return _error("This save uses an unsupported format.")
		state = state.data
	var validation: Dictionary = _validate_household(state)
	if not bool(validation.ok):
		return _error(str(validation.get("error", "The selected household is invalid.")))
	return {"ok":true, "data":state.duplicate(true)}


static func _listing(id: String) -> Dictionary:
	var path: String = _slot_path(id)
	var modified: int = int(FileAccess.get_modified_time(path))
	var entry: Dictionary = {"id":id, "name":"Original household" if id == "legacy" else "Saved household", "saved_at":Time.get_datetime_string_from_unix_time(modified), "day":0, "minutes":0, "members":[], "preview_path":"", "valid":false, "error":"", "_sort_time":float(modified)}
	var read: Dictionary = read_slot(id)
	if not bool(read.ok):
		entry.name = "Unreadable household"
		entry.error = str(read.error)
		return entry
	entry.valid = true
	entry.merge(_summary(read.data), true)
	var metadata_read: Dictionary = _error("No metadata.")
	if id != "legacy":
		metadata_read = _read_json(path)
	elif _directory_safe():
		metadata_read = _read_json(SAVE_DIR.path_join("legacy.metadata.json"), 64 * 1024)
	var metadata: Dictionary = {}
	if bool(metadata_read.ok):
		var source: Variant = metadata_read.data if id == "legacy" else metadata_read.data.get("metadata", {})
		if source is Dictionary:
			metadata = source
	if metadata.get("name") is String:
		entry.name = _clean_name(str(metadata.name))
	if metadata.get("saved_at") is String and str(metadata.saved_at).length() <= 40:
		entry.saved_at = str(metadata.saved_at)
	var stamp: Variant = metadata.get("saved_at_unix")
	if (stamp is int or stamp is float) and is_finite(float(stamp)) and float(stamp) > 0.0 and float(stamp) < 4102444800.0:
		entry._sort_time = float(stamp)
	# Metadata never supplies filesystem paths; derive the one exact preview here.
	if _directory_safe() and _safe_file(_preview_path(id)) and FileAccess.file_exists(_preview_path(id)):
		entry.preview_path = _preview_path(id)
	return entry


static func list_saves() -> Array:
	var entries: Array = []
	if _directory_safe():
		var directory: DirAccess = DirAccess.open(SAVE_DIR)
		for filename: String in directory.get_files():
			if not filename.ends_with(".json"):
				continue
			var id: String = filename.trim_suffix(".json")
			if _valid_id(id) and id != "legacy" and not directory.is_link(filename):
				entries.append(_listing(id))
	if _safe_file(LEGACY_PATH) and FileAccess.file_exists(LEGACY_PATH):
		entries.append(_listing("legacy"))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a._sort_time) == float(b._sort_time):
			return str(a.id) < str(b.id)
		return float(a._sort_time) > float(b._sort_time))
	for entry: Dictionary in entries:
		entry.erase("_sort_time")
	return entries


static func latest_id() -> String:
	for entry: Dictionary in list_saves():
		if bool(entry.valid):
			return str(entry.id)
	return ""


static func delete_slot(id: String) -> Dictionary:
	if not _valid_id(id) or (id != "legacy" and not _directory_safe()):
		return _error("The save slot ID or directory is invalid.")
	var path: String = _slot_path(id)
	if not _safe_file(path) or not FileAccess.file_exists(path):
		return _error("The selected save no longer exists.")
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		return _error("The selected save could not be deleted.")
	if _directory_safe():
		var companions: Array[String] = [_preview_path(id), _preview_path(id) + ".tmp", path + ".tmp"]
		if id == "legacy":
			companions.append(SAVE_DIR.path_join("legacy.metadata.json"))
			companions.append(SAVE_DIR.path_join("legacy.metadata.json.tmp"))
		for companion: String in companions:
			if _safe_file(companion) and FileAccess.file_exists(companion):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(companion))
	return {"ok":true}
