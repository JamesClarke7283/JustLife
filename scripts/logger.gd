extends RefCounted
class_name LifeLogger
## Centralized verbose logging for JustLife.
## Writes detailed runtime logs to ~/.justlife/logs/justlife.log (or $JUSTLIFE_DATA_DIR/logs/justlife.log).
## Immediately flushes on warnings and errors so crashes or failures can always be inspected.

const LOG_SUBFOLDER: String = "logs"
const MAIN_LOG_NAME: String = "justlife.log"
const PREV_LOG_NAME: String = "justlife_prev.log"

static var _file: FileAccess = null
static var _log_path: String = ""
static var _initialized: bool = false
static var _verbose: bool = true

enum Level { DEBUG, INFO, WARN, ERROR, PERF }

static func initialize(verbose_mode: bool = true) -> bool:
	_verbose = verbose_mode
	var root: String = ""
	var storage_script = load("res://scripts/save_storage.gd")
	if storage_script != null and storage_script.has_method("root_path"):
		root = str(storage_script.root_path())
	if root.is_empty():
		var home: String = OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
		if not home.is_empty():
			root = home.replace("\\", "/").path_join(".justlife")
		else:
			root = OS.get_user_data_dir()

	var logs_dir: String = root.path_join(LOG_SUBFOLDER)
	if not DirAccess.dir_exists_absolute(logs_dir):
		DirAccess.make_dir_recursive_absolute(logs_dir)

	_log_path = logs_dir.path_join(MAIN_LOG_NAME)
	var prev_path: String = logs_dir.path_join(PREV_LOG_NAME)

	if FileAccess.file_exists(_log_path):
		var old_file = FileAccess.open(_log_path, FileAccess.READ)
		if old_file != null and old_file.get_length() > 0:
			old_file.close()
			# Rotate old log to previous
			var da = DirAccess.open(logs_dir)
			if da != null:
				da.copy(_log_path, prev_path)

	_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _file == null:
		push_error("LifeLogger: Failed to open log file at %s (error %d)" % [_log_path, FileAccess.get_open_error()])
		return false

	_initialized = true
	var time_str: String = Time.get_datetime_string_from_system(false, true)
	var os_name: String = OS.get_name()
	var version_info: Dictionary = Engine.get_version_info()
	var engine_ver: String = "%s.%s.%s" % [version_info.get("major", 4), version_info.get("minor", 0), version_info.get("patch", 0)]
	var video_adapter: String = RenderingServer.get_video_adapter_name()

	_write_raw("================================================================================")
	_write_raw("JustLife Runtime Log — Started %s" % time_str)
	_write_raw("Engine: Godot %s | OS: %s | Video: %s" % [engine_ver, os_name, video_adapter])
	_write_raw("Storage Root: %s | Log File: %s" % [root, _log_path])
	_write_raw("Cmdline: %s" % str(OS.get_cmdline_args()))
	_write_raw("================================================================================")
	_file.flush()
	return true


static func get_log_path() -> String:
	return _log_path


static func _write_raw(line: String) -> void:
	if _file != null:
		_file.store_line(line)


static func log_entry(level: Level, category: String, message: String, context: Dictionary = {}) -> void:
	if not _initialized:
		initialize()

	var level_str: String = "INFO"
	match level:
		Level.DEBUG: level_str = "DEBUG"
		Level.INFO: level_str = "INFO"
		Level.WARN: level_str = "WARN"
		Level.ERROR: level_str = "ERROR"
		Level.PERF: level_str = "PERF"

	var time_str: String = Time.get_datetime_string_from_system(false, true)
	var context_str: String = ""
	if not context.is_empty():
		context_str = " | " + JSON.stringify(context)

	var line: String = "[%s] [%-5s] [%s] %s%s" % [time_str, level_str, category.to_upper(), message, context_str]

	if _file != null:
		_file.store_line(line)
		if level == Level.WARN or level == Level.ERROR or level == Level.PERF:
			_file.flush()

	# Also emit to console
	if level == Level.ERROR:
		push_error(line)
	elif level == Level.WARN:
		push_warning(line)
	elif _verbose or level != Level.DEBUG:
		print(line)


static func info(category: String, message: String, context: Dictionary = {}) -> void:
	log_entry(Level.INFO, category, message, context)


static func warn(category: String, message: String, context: Dictionary = {}) -> void:
	log_entry(Level.WARN, category, message, context)


static func error(category: String, message: String, context: Dictionary = {}) -> void:
	log_entry(Level.ERROR, category, message, context)


static func debug(category: String, message: String, context: Dictionary = {}) -> void:
	if _verbose:
		log_entry(Level.DEBUG, category, message, context)


static func perf(operation: String, duration_ms: float, details: String = "") -> void:
	var ctx: Dictionary = {"duration_ms": duration_ms}
	if not details.is_empty():
		ctx["details"] = details
	log_entry(Level.PERF, "PERF", "%s took %.2f ms" % [operation, duration_ms], ctx)


static func flush() -> void:
	if _file != null:
		_file.flush()


static func shutdown() -> void:
	if _file != null:
		var time_str: String = Time.get_datetime_string_from_system(false, true)
		_write_raw("[%s] [INFO ] [LIFECYCLE] JustLife cleanly shutting down." % time_str)
		_file.flush()
		_file.close()
		_file = null
	_initialized = false
