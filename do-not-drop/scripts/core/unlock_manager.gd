extends Node
## Persistent local profile for progression.  Currency/cards stay campaign
## scoped in CrewProgression; this deliberately stores only permanent access.

signal unlock_earned(unlock_id: StringName, title: String)
signal progress_changed

const SAVE_PATH := "user://unlock_progress.json"
const PROFILE_VERSION := 1
const UNLOCKS := {
	&"liquid_trap": {"title": "Carga líquida", "deliveries": 3, "score": 250},
	&"explosive_trap": {"title": "Carga explosiva", "deliveries": 7, "score": 750},
	&"hostile_trap": {"title": "Carga hostil", "deliveries": 12, "score": 1500},
	&"violet_paint": {"title": "Pintura violeta", "deliveries": 5, "score": 450},
	&"coral_uniform": {"title": "Uniforme coral", "deliveries": 2, "score": 150},
	&"sky_uniform": {"title": "Uniforme cielo", "deliveries": 9, "score": 1000},
}

const COSMETICS := {
	&"mint_uniform": {"title": "Uniforme menta", "color": Color("83e2ba"), "unlock": &"starter_kit"},
	&"coral_uniform": {"title": "Uniforme coral", "color": Color("f47e6d"), "unlock": &"coral_uniform"},
	&"sky_uniform": {"title": "Uniforme cielo", "color": Color("6db3d6"), "unlock": &"sky_uniform"},
}

var storage_path: String = SAVE_PATH
var total_score: int = 0
var successful_deliveries: int = 0
var completed_runs: int = 0
var unlocked: Dictionary = {&"starter_kit": true}
var selected_cosmetic: StringName = &"mint_uniform"


func _ready() -> void:
	load_profile()
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.run_ended.connect(_on_run_ended)


func reset_profile() -> void:
	total_score = 0
	successful_deliveries = 0
	completed_runs = 0
	unlocked = {&"starter_kit": true}
	selected_cosmetic = &"mint_uniform"
	save_profile()
	progress_changed.emit()


func is_unlocked(unlock_id: StringName) -> bool:
	return bool(unlocked.get(unlock_id, false))


func requirements(unlock_id: StringName) -> Dictionary:
	return Dictionary(UNLOCKS.get(unlock_id, {})).duplicate(true)


func cosmetic_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for cosmetic_id: StringName in COSMETICS:
		var item: Dictionary = Dictionary(COSMETICS[cosmetic_id]).duplicate(true)
		item["id"] = cosmetic_id
		item["available"] = is_unlocked(StringName(item["unlock"]))
		choices.append(item)
	return choices


func cosmetic_color(cosmetic_id: StringName = selected_cosmetic) -> Color:
	var item: Dictionary = Dictionary(COSMETICS.get(cosmetic_id, COSMETICS[&"mint_uniform"]))
	return item.get("color", Color.WHITE)


func select_cosmetic(cosmetic_id: StringName) -> bool:
	var item: Dictionary = Dictionary(COSMETICS.get(cosmetic_id, {}))
	if item.is_empty() or not is_unlocked(StringName(item.get("unlock", &"starter_kit"))):
		return false
	selected_cosmetic = cosmetic_id
	save_profile()
	progress_changed.emit()
	return true


func progress_summary() -> Dictionary:
	return {
		"score": total_score,
		"deliveries": successful_deliveries,
		"runs": completed_runs,
		"unlocked": unlocked.duplicate(true),
	}


func record_run(score: int, results: Dictionary) -> Array[StringName]:
	completed_runs += 1
	total_score += maxi(score, 0)
	if bool(results.get("delivered", false)):
		successful_deliveries += 1
	var newly_unlocked: Array[StringName] = []
	for unlock_id: StringName in UNLOCKS:
		if is_unlocked(unlock_id):
			continue
		var rule: Dictionary = UNLOCKS[unlock_id]
		if successful_deliveries >= int(rule["deliveries"]) and total_score >= int(rule["score"]):
			unlocked[unlock_id] = true
			newly_unlocked.append(unlock_id)
	save_profile()
	progress_changed.emit()
	for unlock_id: StringName in newly_unlocked:
		var title: String = str(UNLOCKS[unlock_id]["title"])
		unlock_earned.emit(unlock_id, title)
		var event_bus := _event_bus()
		if event_bus != null:
			event_bus.emit_signal(&"unlock_earned", unlock_id, title)
	return newly_unlocked


func save_profile() -> void:
	var file := FileAccess.open(storage_path, FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar progreso: " + storage_path)
		return
	file.store_string(JSON.stringify({
		"version": PROFILE_VERSION,
		"total_score": total_score,
		"successful_deliveries": successful_deliveries,
		"completed_runs": completed_runs,
		"unlocked": unlocked,
		"selected_cosmetic": selected_cosmetic,
	}))


func load_profile() -> void:
	if not FileAccess.file_exists(storage_path):
		return
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	total_score = maxi(int(parsed.get("total_score", 0)), 0)
	successful_deliveries = maxi(int(parsed.get("successful_deliveries", 0)), 0)
	completed_runs = maxi(int(parsed.get("completed_runs", 0)), 0)
	unlocked = {&"starter_kit": true}
	for key: Variant in Dictionary(parsed.get("unlocked", {})):
		if bool(parsed["unlocked"].get(key, false)):
			unlocked[StringName(key)] = true
	var saved_cosmetic := StringName(parsed.get("selected_cosmetic", &"mint_uniform"))
	selected_cosmetic = saved_cosmetic if COSMETICS.has(saved_cosmetic) else &"mint_uniform"
	var selected_rule: Dictionary = Dictionary(COSMETICS[selected_cosmetic])
	if not is_unlocked(StringName(selected_rule.get("unlock", &"starter_kit"))):
		selected_cosmetic = &"mint_uniform"


func _on_run_ended(score: int, results: Dictionary) -> void:
	record_run(score, results)


func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus") if is_inside_tree() else null
