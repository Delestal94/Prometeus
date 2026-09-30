class_name RunLog
extends Node
## One small JSON file per run in a folder of the user's save, named by
## date and time, oldest pruned past a cap: a local playtest log that never
## leaves the machine. Portable module (docs/modulos.md): the game extends
## it, listens to whatever it wants to record and hands save_record() a
## plain Dictionary of numbers, strings and arrays. Writes go through
## SafeJson (persistence module), so a crash mid-write never leaves half a
## file.

## Where the files go. Tests point it at a throwaway folder.
var directory: String = "user://run_log"
## Oldest files go first past this many, so leaving the option on for
## months can't slowly fill the disk.
var max_files: int = 300
## Path of the last file written ("" until one is), for tests and the UI.
var last_file: String = ""


func _ready() -> void:
	# Under a test script (--script) keep away from the player's real log.
	if Engine.get_main_loop().get_script() != null:
		directory = directory.get_base_dir().path_join("test_" + directory.get_file())


## Writes the record as a new file under `directory`, named `stem` (the
## date and time by default; "_2", "_3"... when that name is taken). Returns
## the path, or "" if the disk said no (a warning, never a crash: a log must
## not be able to break the screen that asked for it).
func save_record(record: Dictionary, stem: String = "") -> String:
	var folder: String = ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(folder) != OK and not DirAccess.dir_exists_absolute(folder):
		push_warning("[RunLog] Could not create the folder: " + directory)
		return ""
	var path: String = free_path(stem if not stem.is_empty() else file_stem(Time.get_datetime_dict_from_system()))
	if not SafeJson.write(path, record):
		push_warning("[RunLog] Could not save the record: " + path)
		return ""
	last_file = path
	prune()
	return path


## "2026-09-30_15-42-10": date and time, sortable, and free of the characters
## Windows refuses in a file name (":" above all).
static func file_stem(datetime: Dictionary) -> String:
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [int(datetime.get("year", 0)), int(datetime.get("month", 0)),
			int(datetime.get("day", 0)), int(datetime.get("hour", 0)), int(datetime.get("minute", 0)),
			int(datetime.get("second", 0))]


func free_path(stem: String) -> String:
	var path: String = "%s/%s.json" % [directory, stem]
	var copy: int = 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.json" % [directory, stem, copy]
		copy += 1
	return path


## The oldest files past max_files go, by name (the stems sort by date).
func prune() -> void:
	var names: PackedStringArray = []
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".json"):
			names.append(file_name)
	if names.size() <= max_files:
		return
	names.sort()
	for index: int in names.size() - max_files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [directory, names[index]]))
