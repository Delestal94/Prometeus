class_name UnlockProfile
extends Node
## A persistent local profile of permanent unlocks: a versioned JSON file
## (SafeJson, persistence module), a table of rules -- each unlock earned
## once every one of its stat thresholds is met -- granted retroactively
## when an older profile is loaded, and a set of "seen once" flags.
## Portable module (docs/modulos.md): the game extends it as an autoload,
## keeps its own counters and choices, answers _stat() for the rules'
## keys and adds its fields to the file through the hooks at the end.
##
## A rule is {"title": <translation key>, <stat>: <threshold>, ...}: every
## key but "title" is a stat name the game answers with _stat(). The
## nearest locked reward and its progress come from the same rules.

signal unlock_earned(unlock_id: StringName, title: String)
signal progress_changed

## Configuration the game sets in _init.
var storage_path: String = "user://unlock_progress.json"
## Bumped whenever the file's meaning changes; _read_profile() gets the
## saved version to migrate what it must.
var profile_version: int = 1
var unlock_rules: Dictionary = {}
## The unlock everyone has from the start.
var starter_unlock: StringName = &"starter_kit"

var unlocked: Dictionary = {}
var seen_tips: Dictionary = {}


func _ready() -> void:
	# Under a test script (--script) the main loop has a script of its own:
	# keep tests away from the player's real save.
	if Engine.get_main_loop().get_script() != null:
		storage_path = storage_path.get_base_dir().path_join("test_" + storage_path.get_file())
	unlocked = {starter_unlock: true}
	load_profile()


func reset_profile() -> void:
	unlocked = {starter_unlock: true}
	seen_tips.clear()
	_reset_fields()
	save_profile()
	progress_changed.emit()


func is_unlocked(unlock_id: StringName) -> bool:
	return bool(unlocked.get(unlock_id, false))


## Returns true exactly once per id and persists immediately, so changing
## levels or closing the game cannot replay an already-seen thing.
func mark_tip_seen(tip_id: StringName) -> bool:
	if tip_id.is_empty() or bool(seen_tips.get(tip_id, false)):
		return false
	seen_tips[tip_id] = true
	save_profile()
	return true


func requirements(unlock_id: StringName) -> Dictionary:
	return Dictionary(unlock_rules.get(unlock_id, {})).duplicate(true)


## The closest locked reward, with one conservative percentage: every
## threshold is required, so the slowest one owns the bar. Besides "id",
## "title" and "progress", "current_<stat>" and "target_<stat>" per rule key.
func next_unlock_progress() -> Dictionary:
	var next_id: StringName = &""
	var next_rule: Dictionary = {}
	for unlock_id: StringName in unlock_rules:
		if is_unlocked(unlock_id):
			continue
		var rule: Dictionary = unlock_rules[unlock_id]
		if next_rule.is_empty() or _rule_before(rule, next_rule):
			next_id = unlock_id
			next_rule = rule
	if next_rule.is_empty():
		return {}
	var result: Dictionary = {"id": next_id, "title": String(next_rule.get("title", ""))}
	var progress: float = 1.0
	for key: Variant in next_rule:
		if String(key) == "title":
			continue
		var target: int = int(next_rule[key])
		var current: int = _stat(StringName(key))
		result["current_" + String(key)] = current
		result["target_" + String(key)] = target
		progress = minf(progress, 1.0 if target <= 0 else minf(float(current) / target, 1.0))
	result["progress"] = progress
	return result


## Which of two rules is the nearer reward: the lower thresholds, in the
## rules' key order.
func _rule_before(rule: Dictionary, other: Dictionary) -> bool:
	for key: Variant in rule:
		if String(key) == "title":
			continue
		var mine: int = int(rule[key])
		var theirs: int = int(other.get(key, 0))
		if mine != theirs:
			return mine < theirs
	return false


## Grants every unlock whose thresholds are met; the ids granted now.
func grant_eligible_unlocks() -> Array[StringName]:
	var newly_unlocked: Array[StringName] = []
	for unlock_id: StringName in unlock_rules:
		if is_unlocked(unlock_id):
			continue
		var rule: Dictionary = unlock_rules[unlock_id]
		var eligible: bool = true
		for key: Variant in rule:
			if String(key) != "title" and _stat(StringName(key)) < int(rule[key]):
				eligible = false
		if eligible:
			unlocked[unlock_id] = true
			newly_unlocked.append(unlock_id)
	return newly_unlocked


## Grants what the stats now earn, saves, and announces each new unlock
## with its translated title. What record_* in the game calls after
## counting.
func announce_new_unlocks() -> Array[StringName]:
	var newly_unlocked: Array[StringName] = grant_eligible_unlocks()
	save_profile()
	progress_changed.emit()
	for unlock_id: StringName in newly_unlocked:
		unlock_earned.emit(unlock_id, tr(str((unlock_rules[unlock_id] as Dictionary).get("title", ""))))
	return newly_unlocked


func save_profile() -> void:
	var data: Dictionary = {"version": profile_version, "unlocked": unlocked, "seen_tips": seen_tips}
	data.merge(_profile_fields())
	if not SafeJson.write(storage_path, data):
		push_warning("Could not save the profile: " + storage_path)


func load_profile() -> void:
	if not FileAccess.file_exists(storage_path):
		return
	var parsed: Dictionary = SafeJson.read(storage_path, {})
	if parsed.is_empty():
		reset_profile()
		return
	var saved_version: int = int(parsed.get("version", 1))
	unlocked = {starter_unlock: true}
	for key: Variant in Dictionary(parsed.get("unlocked", {})):
		if bool(parsed["unlocked"].get(key, false)):
			unlocked[StringName(key)] = true
	seen_tips.clear()
	for tip_id: Variant in Dictionary(parsed.get("seen_tips", {})):
		if bool(parsed["seen_tips"].get(tip_id, false)):
			seen_tips[StringName(tip_id)] = true
	_read_profile(parsed, saved_version)
	# An older profile gets every unlock its stats already earn.
	var retroactive: Array[StringName] = grant_eligible_unlocks()
	_after_load(saved_version)
	if saved_version < profile_version or not retroactive.is_empty():
		save_profile()


# --- Hooks the game fills in ---------------------------------------------------

## The value of a stat named in the rules ("score", "deliveries"...).
func _stat(_name: StringName) -> int:
	return 0


## The game's own fields for the file (counters, choices).
func _profile_fields() -> Dictionary:
	return {}


## The game's own fields back from the file; `version` is the file's, to
## migrate what an older one meant differently. Runs before the retroactive
## grant, so counters must be read here.
func _read_profile(_parsed: Dictionary, _version: int) -> void:
	pass


## After the retroactive grant: choices that need an unlock can be checked.
func _after_load(_version: int) -> void:
	pass


## Back to a fresh profile's fields.
func _reset_fields() -> void:
	pass
