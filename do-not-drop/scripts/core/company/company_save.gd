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
##
## The file always holds a day's opening (D-0251, docs/expansion-distritos/diseno/guardado.md
## rule 1): the close saves the next day's, and a new company its day 1. A day the host's world
## closed before the day did (D-2005: the session ended, or the host went back to the menu) writes
## nothing of that day: mark_interrupted() only sets "interrupted": true next to "version", so
## loading it plays that day again from the opening, as it was before the day began. A file without
## the key (every v1 save before D-2005) is not interrupted, so the format stays version 1.
##
## Several companies live side by side, one per slot (D-0235): list_slots() describes
## them for the picker (name, day, money, date) without moving any file, delete()
## removes one with its leftovers and new_slot_id() hands out a free slot name.

enum LoadResult { LOADED, MISSING, CORRUPT, TOO_NEW }

const VERSION: int = 1
## The CompanyState autoload's script (no class_name): its sanitize_options() reads a slot's modifiers.
const COMPANY_STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
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


## Writes the state's to_dict() to the slot; `interrupted` marks a day cut short
## (D-2005), which load_into() starts again from the opening (the game marks the
## opening already saved instead, mark_interrupted()). False when the
## folder or the file could not be written (the previous save, if any, stays as
## it was), and when the slot holds a save from a newer build: load_into() left
## it alone (TOO_NEW), so the company here is not that one and must not erase it.
static func save(
	state: Object, slot: String = DEFAULT_SLOT, dir: String = SAVE_DIR, interrupted: bool = false
) -> bool:
	var path: String = path_for(slot, dir)
	var saved_version: int = _version_of(_peek(path))
	if saved_version > VERSION:
		push_warning(
			"CompanySave: %s is version %d, this build writes %d; not overwritten"
			% [path, saved_version, VERSION]
		)
		return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return false
	var payload: Dictionary = {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"interrupted": interrupted,
		"company": state.call("to_dict"),
	}
	return SafeJson.write(path, payload)


## Loads the slot into the state. LOADED: the company is active with the saved
## data (an interrupted day with its clock back at the opening). CORRUPT: the
## file is quarantined and the state holds a new company. MISSING and TOO_NEW
## leave the state untouched. `migrations` and `version` are for tests; the game
## uses the defaults.
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
	if _interrupted(raw):
		# Same day, from its opening. A file marked by mark_interrupted() already is that opening
		# (D-0251); one written whole with `interrupted` (D-2005, before D-0251) only gets its clock
		# back, and keeps what was played of the day.
		state.set("clock_minutes", CompanyTuning.DAY_START_MIN)
	return LoadResult.LOADED


## Marks the save in the slot as a day cut short (D-0251): only "interrupted" changes, the company
## in the file (that day's opening) stays as it was, so nothing of the day cut reaches the disk.
## Reads the .bak a cut write left when the file is missing. False, touching nothing, when the slot
## holds no save of ours or one from a newer build, and when the file could not be written.
static func mark_interrupted(slot: String = DEFAULT_SLOT, dir: String = SAVE_DIR) -> bool:
	var path: String = path_for(slot, dir)
	var raw: Dictionary = _peek(path)
	var saved_version: int = _version_of(raw)
	if saved_version <= 0 or not raw.get("company") is Dictionary:
		return false
	if saved_version > VERSION:
		push_warning(
			"CompanySave: %s is version %d, this build writes %d; not marked"
			% [path, saved_version, VERSION]
		)
		return false
	raw["interrupted"] = true
	return SafeJson.write(path, raw)


## Writes the modifiers of the company in the slot (D-1904, "Opciones" on a saved company in the
## main menu; diseno/dificultad.md §3: only outside a match). Only "company.options" changes, cleaned
## by CompanyState.sanitize_options(); the rest of the file (the day's opening) stays as it was. False,
## touching nothing, like mark_interrupted(): no save of ours, a newer build's, or a write error.
static func write_options(options: Dictionary, slot: String = DEFAULT_SLOT, dir: String = SAVE_DIR) -> bool:
	var path: String = path_for(slot, dir)
	var raw: Dictionary = _peek(path)
	var saved_version: int = _version_of(raw)
	if saved_version <= 0 or saved_version > VERSION or not raw.get("company") is Dictionary:
		return false
	(raw["company"] as Dictionary)["options"] = COMPANY_STATE_SCRIPT.sanitize_options(options)
	return SafeJson.write(path, raw)


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


## True when the slot holds a day cut short (saved with `interrupted`, D-2005), in
## its file or, without one, in the .bak a cut write left (as load_into() reads it).
## Only reads: a missing or unreadable file is false and is left as it is
## (load_into() is what quarantines a bad one).
static func was_interrupted(slot: String = DEFAULT_SLOT, dir: String = SAVE_DIR) -> bool:
	return _interrupted(_peek(path_for(slot, dir)))


## One entry per company saved in `dir`, the last played first (`saved_at` descending,
## ties by `slot` ascending): {"slot", "name", "day", "money", "saved_at", "interrupted",
## "version"}. "slot" is what load_into() takes; "name" falls back to the slot when the
## company has none. A slot whose only file is the <slot>.json.bak a cut write left counts
## (load_into() recovers it). Loose .tmp / .bad files and JSON that is not a save of ours
## are left out; a save from a newer build is listed with its "version" so the UI can show
## it disabled. Only reads: nothing is moved or quarantined. No folder is an empty list.
static func list_slots(dir: String = SAVE_DIR) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var folder: DirAccess = DirAccess.open(dir)
	if folder == null:
		return slots
	var seen: Dictionary = {}
	for file_name: String in folder.get_files():
		var slot: String = ""
		if file_name.ends_with(".json"):
			slot = file_name.trim_suffix(".json")
		elif file_name.ends_with(".json.bak"):
			slot = file_name.trim_suffix(".json.bak")
		# A name path_for() would change could not be loaded back by its slot.
		if slot.is_empty() or seen.has(slot) or path_for(slot, dir) != dir.path_join(slot + ".json"):
			continue
		seen[slot] = true
		var raw: Dictionary = _peek(path_for(slot, dir))
		var version: int = _version_of(raw)
		var company: Variant = raw.get("company")
		if version <= 0 or not company is Dictionary:
			continue
		var title: String = ""
		var company_name: Variant = (company as Dictionary).get("company_name")
		if typeof(company_name) == TYPE_STRING:
			title = (company_name as String).strip_edges()
		slots.append({
			"slot": slot,
			"name": title if not title.is_empty() else slot,
			"day": _int_of((company as Dictionary).get("day")),
			"money": _int_of((company as Dictionary).get("money")),
			"saved_at": _int_of(raw.get("saved_at")),
			"interrupted": _interrupted(raw),
			"options": COMPANY_STATE_SCRIPT.sanitize_options((company as Dictionary).get("options")),
			"version": version,
		})
	slots.sort_custom(_slot_before)
	return slots


## Removes the slot's file and what a cut write or a quarantine left next to it (.bak,
## .tmp, .bad). True when none of them is left, also when there was nothing to remove.
static func delete(slot: String, dir: String = SAVE_DIR) -> bool:
	var path: String = path_for(slot, dir)
	var clear: bool = true
	for suffix: String in ["", ".bak", ".tmp", ".bad"]:
		var leftover: String = path + suffix
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))
		if FileAccess.file_exists(leftover):
			clear = false
	return clear


## A slot name nobody uses in `dir`: DEFAULT_SLOT when free, else "company_2", "company_3"...
## Taken means a .json or the .bak a cut write left (both are a company to list_slots()).
static func new_slot_id(dir: String = SAVE_DIR) -> String:
	var candidate: String = DEFAULT_SLOT
	var n: int = 2
	while _slot_taken(candidate, dir):
		candidate = "%s_%d" % [DEFAULT_SLOT, n]
		n += 1
	return candidate


static func _slot_taken(slot: String, dir: String) -> bool:
	var path: String = path_for(slot, dir)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


static func _slot_before(a: Dictionary, b: Dictionary) -> bool:
	if a["saved_at"] != b["saved_at"]:
		return int(a["saved_at"]) > int(b["saved_at"])
	return String(a["slot"]) < String(b["slot"])


## 0 for anything that is not a number (a hand-edited file).
static func _int_of(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0


## The JSON object in `path` or, when it is missing, in its .bak; {} when neither is
## there or it is not an object. Unlike SafeJson.read() it moves no file.
static func _peek(path: String) -> Dictionary:
	var source: String = path
	if not FileAccess.file_exists(source):
		source = path + ".bak"
		if not FileAccess.file_exists(source):
			return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(source)) != OK or not json.data is Dictionary:
		return {}
	return json.data


## Only a JSON true counts: a missing key (a save from before D-2005) or any other
## value is a day that was not cut short.
static func _interrupted(raw: Dictionary) -> bool:
	var value: Variant = raw.get("interrupted", false)
	return typeof(value) == TYPE_BOOL and bool(value)


## 0 when the file has no usable version (not a save of ours).
static func _version_of(raw: Dictionary) -> int:
	var value: Variant = raw.get("version")
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return maxi(int(value), 0)
	return 0
