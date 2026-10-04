class_name CompanySave
extends RefCounted
## Versioned save file of the company ("Modo Empresa", expansion D-0206).
##
## One JSON file per slot under user://saves/company/<slot>.json (the path
## Steam Auto-Cloud will sync, D-0237): {"version": N, "saved_at": unix,
## "company": CompanyState.to_dict()}. Writing goes through SafeJson, so a cut
## mid-write leaves the previous file intact and a stray .tmp is never read.
##
## An older file climbs MIGRATIONS one version at a time (key = the version it
## migrates FROM) before CompanyState.from_dict() reads it. A corrupt file is
## quarantined by SafeJson (.bad) and the company starts fresh with a warning; a
## file from a newer build is left untouched and not loaded.
##
## It takes the CompanyState node as a parameter instead of naming the autoload,
## so a --script run that loads this class keeps compiling (lesson N-919).
## When to save (day SUMMARY, back to the menu) is wired by DayCycle (D-0203)
## and the company scene (D-0214).

enum LoadResult { LOADED, MISSING, CORRUPT, TOO_NEW }

const VERSION: int = 1
const SAVE_DIR: String = "user://saves/company"
const DEFAULT_SLOT: String = "company"
## from version -> Callable(Dictionary) -> Dictionary returning the next version's
## "company" dictionary. Empty while the format is v1.
const MIGRATIONS: Dictionary = {}


## Full path of a slot's file. Slot names are made filename-safe.
static func path_for(slot: String = DEFAULT_SLOT, dir: String = SAVE_DIR) -> String:
	var safe: String = slot.strip_edges().validate_filename()
	if safe.is_empty():
		safe = DEFAULT_SLOT
	return dir.path_join(safe + ".json")


## Writes the state's to_dict() to the slot. False when the folder or the file
## could not be written (the previous save, if any, stays as it was).
static func save(state: Object, slot: String = DEFAULT_SLOT, dir: String = SAVE_DIR) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return false
	var payload: Dictionary = {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"company": state.call("to_dict"),
	}
	return SafeJson.write(path_for(slot, dir), payload)


## Loads the slot into the state. LOADED: the company is active with the saved
## data. CORRUPT: the file is quarantined and the state holds a new company.
## MISSING and TOO_NEW leave the state untouched. `migrations` and `version` are
## for tests; the game uses the defaults.
static func load_into(
	state: Object,
	slot: String = DEFAULT_SLOT,
	dir: String = SAVE_DIR,
	migrations: Dictionary = MIGRATIONS,
	version: int = VERSION
) -> LoadResult:
	var path: String = path_for(slot, dir)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return LoadResult.MISSING
	var raw: Dictionary = SafeJson.read(path, {})
	var saved_version: int = _version_of(raw)
	if saved_version > version:
		push_warning(
			"CompanySave: %s is version %d, this build reads up to %d; not loaded"
			% [path, saved_version, version]
		)
		return LoadResult.TOO_NEW
	var company: Variant = raw.get("company")
	var data: Dictionary = {}
	if saved_version > 0 and company is Dictionary:
		data = migrate(company, saved_version, migrations, version)
	if data.is_empty() or not bool(state.call("from_dict", data)):
		push_warning("CompanySave: %s is unreadable; starting a new company" % path)
		if FileAccess.file_exists(path):
			# Valid JSON that is not a company save: reading it as an Array makes
			# SafeJson quarantine it to .bad, like a file that does not parse.
			SafeJson.read(path, [])
		state.call("new_company")
		return LoadResult.CORRUPT
	return LoadResult.LOADED


## Climbs `company` from `from_version` up to `to_version`. Empty when a step is
## missing or does not return a dictionary.
static func migrate(
	company: Dictionary, from_version: int, migrations: Dictionary = MIGRATIONS, to_version: int = VERSION
) -> Dictionary:
	var data: Dictionary = company.duplicate(true)
	for step: int in range(from_version, to_version):
		var migration: Variant = migrations.get(step)
		if not migration is Callable:
			return {}
		var next: Variant = (migration as Callable).call(data)
		if not next is Dictionary:
			return {}
		data = next
	return data


static func exists(slot: String = DEFAULT_SLOT, dir: String = SAVE_DIR) -> bool:
	return FileAccess.file_exists(path_for(slot, dir))


## 0 when the file has no usable version (not a save of ours).
static func _version_of(raw: Dictionary) -> int:
	var value: Variant = raw.get("version")
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return maxi(int(value), 0)
	return 0
