class_name LegacyUserData
extends RefCounted
## The game's side of the persistence module's UserDataMigration
## (docs/modulos.md): renaming the game from "Do Not Drop" to "Take My
## Package" (2026-09-22) moved user://, so volume, sensitivity and the local
## leaderboard would all have looked reset. These are the folder and files
## that come over, once.

const LEGACY_FOLDER: String = "Do Not Drop"
const FILES: PackedStringArray = ["settings.cfg", "leaderboard.json"]


static func migrate() -> void:
	UserDataMigration.migrate(LEGACY_FOLDER, FILES)


## Tests point it at scratch folders instead of the real save.
static func migrate_between(legacy_dir: String, target_dir: String) -> void:
	UserDataMigration.migrate_between(legacy_dir, target_dir, FILES)
