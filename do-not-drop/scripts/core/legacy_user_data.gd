class_name LegacyUserData
extends RefCounted
## One-time carry-over of player data from the working-title save folder.
##
## Godot names the user:// folder after application/config/name, so renaming
## the game from "Do Not Drop" to "Take My Package" (2026-09-22) silently
## pointed everyone at a fresh, empty folder: volume, sensitivity and the
## local leaderboard would all look reset. This copies them over once.
##
## A marker file makes it run only the first time. Without it, a test that
## deletes settings.cfg to check the defaults would get the old file copied
## right back.

const LEGACY_FOLDER: String = "Do Not Drop"
const FILES: PackedStringArray = ["settings.cfg", "leaderboard.json"]
const MARKER_NAME: String = ".legacy_data_migrated"


static func migrate() -> void:
	var user_dir: String = OS.get_user_data_dir()
	migrate_between(user_dir.get_base_dir().path_join(LEGACY_FOLDER), user_dir)


## Split out so tests can point it at scratch folders instead of the real save.
static func migrate_between(legacy_dir: String, target_dir: String) -> void:
	var marker_path: String = target_dir.path_join(MARKER_NAME)
	if FileAccess.file_exists(marker_path):
		return
	if legacy_dir != target_dir and DirAccess.dir_exists_absolute(legacy_dir):
		DirAccess.make_dir_recursive_absolute(target_dir)
		for file_name: String in FILES:
			var source: String = legacy_dir.path_join(file_name)
			var target: String = target_dir.path_join(file_name)
			if FileAccess.file_exists(source) and not FileAccess.file_exists(target):
				DirAccess.copy_absolute(source, target)
	var marker: FileAccess = FileAccess.open(marker_path, FileAccess.WRITE)
	if marker != null:
		marker.store_string(LEGACY_FOLDER)
