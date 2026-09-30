class_name UserDataMigration
extends RefCounted
## One-time carry-over of player data from an older save folder.
##
## Godot names the user:// folder after application/config/name, so renaming
## a game silently points everyone at a fresh, empty folder: settings and
## local scores would all look reset. This copies the named files over once,
## never over newer data.
##
## A marker file makes it run only the first time. Without it, a test that
## deletes a settings file to check the defaults would get the old file
## copied right back.

const MARKER_NAME: String = ".legacy_data_migrated"


## Copies `files` from the sibling save folder `legacy_folder` (the old
## application name) into this game's user:// folder.
static func migrate(legacy_folder: String, files: PackedStringArray) -> void:
	var user_dir: String = OS.get_user_data_dir()
	migrate_between(user_dir.get_base_dir().path_join(legacy_folder), user_dir, files)


## Split out so tests can point it at scratch folders instead of the real save.
static func migrate_between(legacy_dir: String, target_dir: String, files: PackedStringArray) -> void:
	var marker_path: String = target_dir.path_join(MARKER_NAME)
	if FileAccess.file_exists(marker_path):
		return
	DirAccess.make_dir_recursive_absolute(target_dir)
	if legacy_dir != target_dir and DirAccess.dir_exists_absolute(legacy_dir):
		for file_name: String in files:
			var source: String = legacy_dir.path_join(file_name)
			var target: String = target_dir.path_join(file_name)
			if FileAccess.file_exists(source) and not FileAccess.file_exists(target):
				DirAccess.copy_absolute(source, target)
	var marker: FileAccess = FileAccess.open(marker_path, FileAccess.WRITE)
	if marker != null:
		marker.store_string(legacy_dir.get_file())
