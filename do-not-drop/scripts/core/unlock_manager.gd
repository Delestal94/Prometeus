extends UnlockProfile
## Take My Package's persistent profile on the unlock_profile module's
## UnlockProfile (docs/modulos.md): the module keeps the file, the unlock
## rules and the "seen once" cards; this file is what this game counts
## (score, deliveries, runs), what it unlocks (traps, paint, uniforms, the
## agile van), the player's choices and how the traps reach the depot's
## shelves. Currency/cards stay campaign scoped in CrewProgression.

const SAVE_PATH := "user://unlock_progress.json"
## 2: "team_color" became the default. Version 1 defaulted everyone to the
## mint uniform, so every teammate looked identical; a v1 profile still on
## mint (never actually chosen) is moved to team_color when loaded.
## 3: Peso creciente and Ruidoso joined the gradual trap curve. Loading an
## older profile grants every unlock its existing progress already earns.
## 4: first-time trap tutorial cards persist in seen_tips.
const PROFILE_VERSION := 4
const FaceCatalog = preload("res://scripts/core/face_catalog.gd")
const NICKNAME = preload("res://scripts/core/nickname.gd")
## Not a uniform: each player keeps the colour of their seat in the crew
## (NetworkManager.color_slot(), N-226), so teammates stay told apart by default.
const TEAM_COLOR := &"team_color"
const UNLOCKS := {
	&"growing_weight_trap": {"title": "UI_UNLOCK_GROWING_WEIGHT", "deliveries": 1, "score": 0},
	&"noisy_trap": {"title": "UI_UNLOCK_NOISY", "deliveries": 2, "score": 100},
	&"liquid_trap": {"title": "UI_UNLOCK_LIQUID", "deliveries": 4, "score": 250},
	&"explosive_trap": {"title": "UI_UNLOCK_EXPLOSIVE", "deliveries": 8, "score": 750},
	&"hostile_trap": {"title": "UI_UNLOCK_HOSTILE", "deliveries": 13, "score": 1500},
	&"violet_paint": {"title": "UI_UNLOCK_VIOLET_PAINT", "deliveries": 5, "score": 450},
	&"coral_uniform": {"title": "UI_UNLOCK_CORAL_UNIFORM", "deliveries": 2, "score": 150},
	&"sky_uniform": {"title": "UI_UNLOCK_SKY_UNIFORM", "deliveries": 9, "score": 1000},
	&"agile_van": {"title": "UI_UNLOCK_AGILE_VAN", "deliveries": 4, "score": 350},
	&"vintage_van": {"title": "UI_UNLOCK_VINTAGE_VAN", "deliveries": 6, "score": 550},
}

## Which trap each unlock above puts on the depot's shelves (by the trap's
## id in data/traps/); traps not listed are there from the first run.
const TRAP_UNLOCKS := {
	&"growing_weight": &"growing_weight_trap",
	&"noisy": &"noisy_trap",
	&"liquid": &"liquid_trap",
	&"explosive": &"explosive_trap",
	&"hostile": &"hostile_trap",
}
const TRAP_DIFFICULTY_ORDER: Array[StringName] = [
	&"fragile", &"balance", &"growing_weight", &"liquid", &"noisy", &"explosive", &"hostile",
]
const BOXES_PER_TRAP := 2
## One house per passenger at the 8-player cap (NetworkManager.MAX_PLAYERS - 1):
## at 4, a full crew on a fresh profile got 7 houses and only 4 orders (N-228.2).
const MAX_DELIVERY_HOUSES := 7

## The truck the host brings to the route (vehicle.gd VARIANTS) and its paint
## (vehicle.gd PAINTS). Same unlock rules as everything else here.
const TRUCKS := {
	&"classic": {"title": "UI_TRUCK_CLASSIC", "detail": "UI_TRUCK_STABLE", "unlock": &"starter_kit"},
	&"agile": {"title": "UI_TRUCK_AGILE", "detail": "UI_TRUCK_NERVOUS", "unlock": &"agile_van"},
	# Manual gears, paid better (vehicle.gd VARIANTS "vintage", N-114).
	&"vintage": {"title": "UI_TRUCK_VINTAGE", "detail": "UI_TRUCK_MANUAL", "unlock": &"vintage_van"},
}
const PAINTS := {
	&"white": {"title": "UI_PAINT_FACTORY_WHITE", "color": Color("dde2e8"), "unlock": &"starter_kit"},
	&"violet": {"title": "UI_PAINT_VIOLET", "color": Color("7b52b9"), "unlock": &"violet_paint"},
}

const COSMETICS := {
	&"team_color": {"title": "UI_UNIFORM_TEAM", "color": Color("f4c562"), "unlock": &"starter_kit", "auto": true},
	&"mint_uniform": {"title": "UI_UNIFORM_MINT", "color": Color("83e2ba"), "unlock": &"starter_kit"},
	&"coral_uniform": {"title": "UI_UNIFORM_CORAL", "color": Color("f47e6d"), "unlock": &"coral_uniform"},
	&"sky_uniform": {"title": "UI_UNIFORM_SKY", "color": Color("6db3d6"), "unlock": &"sky_uniform"},
}

var total_score: int = 0
var successful_deliveries: int = 0
var completed_runs: int = 0
var selected_cosmetic: StringName = TEAM_COLOR
var selected_truck: StringName = &"classic"
var selected_paint: StringName = &"white"
var selected_eyes: StringName = FaceCatalog.DEFAULT_EYES
var selected_mouth: StringName = FaceCatalog.DEFAULT_MOUTH
## What the player typed to be called by (N-606.1), cleaned; empty = the game
## hands out a funny one (Nickname.resolve). Travels with the appearance.
var nickname: String = ""


func _init() -> void:
	storage_path = SAVE_PATH
	profile_version = PROFILE_VERSION
	unlock_rules = UNLOCKS


func _ready() -> void:
	super()
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.run_ended.connect(_on_run_ended)


func _stat(stat_name: StringName) -> int:
	match stat_name:
		&"deliveries":
			return successful_deliveries
		&"score":
			return total_score
	return 0


## Trap ids this profile hasn't unlocked yet: the depot leaves them off its
## shelves (depot.gd withhold_locked). Online it's the host's profile that
## counts, handed to every joiner (NetworkManager.world_locked_traps).
func locked_traps(player_count: int = -1) -> Array[StringName]:
	var locked: Array[StringName] = []
	for trap_id: StringName in TRAP_UNLOCKS:
		if not is_unlocked(StringName(TRAP_UNLOCKS[trap_id])):
			locked.append(trap_id)
	var crew_size := player_count
	if crew_size < 0:
		var network := get_node_or_null(^"/root/NetworkManager") if is_inside_tree() else null
		crew_size = Array(network.get(&"peer_ids")).size() if network != null else 1
	# Same count as RoutePlanner.crew_house_count(): never under two houses (N-119).
	var required_boxes := mini(maxi(crew_size - 1, 2), MAX_DELIVERY_HOUSES)
	return _ensure_trap_capacity(locked, required_boxes)


## Keep enough physical boxes for one order per house. The two starter traps
## give four boxes; a bigger crew releases the easiest locked traps until every
## house has its box, and the invariant survives catalogue or route changes.
func _ensure_trap_capacity(locked: Array[StringName], required_boxes: int) -> Array[StringName]:
	var result := locked.duplicate()
	var available_traps := TRAP_DIFFICULTY_ORDER.size() - result.size()
	for trap_id: StringName in TRAP_DIFFICULTY_ORDER:
		if available_traps * BOXES_PER_TRAP >= required_boxes:
			break
		if result.has(trap_id):
			result.erase(trap_id)
			available_traps += 1
	return result


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


## True when this choice means "the crew colour for my seat" rather than a
## fixed uniform colour.
func cosmetic_is_auto(cosmetic_id: StringName) -> bool:
	return bool(Dictionary(COSMETICS.get(cosmetic_id, {})).get("auto", false))


func select_cosmetic(cosmetic_id: StringName) -> bool:
	var item: Dictionary = Dictionary(COSMETICS.get(cosmetic_id, {}))
	if item.is_empty() or not is_unlocked(StringName(item.get("unlock", &"starter_kit"))):
		return false
	selected_cosmetic = cosmetic_id
	save_profile()
	progress_changed.emit()
	return true


func truck_choices() -> Array[Dictionary]:
	return _choices(TRUCKS)


func paint_choices() -> Array[Dictionary]:
	return _choices(PAINTS)


func _choices(table: Dictionary) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for id: StringName in table:
		var item: Dictionary = Dictionary(table[id]).duplicate(true)
		item["id"] = id
		item["available"] = is_unlocked(StringName(item["unlock"]))
		choices.append(item)
	return choices


func select_truck(truck_id: StringName) -> bool:
	if not TRUCKS.has(truck_id) or not is_unlocked(StringName(TRUCKS[truck_id]["unlock"])):
		return false
	selected_truck = truck_id
	save_profile()
	progress_changed.emit()
	return true


func select_paint(paint_id: StringName) -> bool:
	if not PAINTS.has(paint_id) or not is_unlocked(StringName(PAINTS[paint_id]["unlock"])):
		return false
	selected_paint = paint_id
	save_profile()
	progress_changed.emit()
	return true


func select_eyes(eyes_id: StringName) -> bool:
	if not FaceCatalog.EYES.has(eyes_id):
		return false
	selected_eyes = eyes_id
	save_profile()
	progress_changed.emit()
	return true


func select_mouth(mouth_id: StringName) -> bool:
	if not FaceCatalog.MOUTHS.has(mouth_id):
		return false
	selected_mouth = mouth_id
	save_profile()
	progress_changed.emit()
	return true


func set_nickname(text: String) -> void:
	var cleaned: String = NICKNAME.clean(text)
	if cleaned == nickname:
		return
	nickname = cleaned
	save_profile()
	progress_changed.emit()


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
	var newly_unlocked: Array[StringName] = announce_new_unlocks()
	var event_bus: Node = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus != null:
		for unlock_id: StringName in newly_unlocked:
			event_bus.emit_signal(&"unlock_earned", unlock_id, tr(str(UNLOCKS[unlock_id]["title"])))
	return newly_unlocked


func _profile_fields() -> Dictionary:
	return {
		"total_score": total_score,
		"successful_deliveries": successful_deliveries,
		"completed_runs": completed_runs,
		"selected_cosmetic": selected_cosmetic,
		"selected_truck": selected_truck,
		"selected_paint": selected_paint,
		"selected_eyes": selected_eyes,
		"selected_mouth": selected_mouth,
		"nickname": nickname,
	}


func _read_profile(parsed: Dictionary, version: int) -> void:
	total_score = maxi(int(parsed.get("total_score", 0)), 0)
	successful_deliveries = maxi(int(parsed.get("successful_deliveries", 0)), 0)
	completed_runs = maxi(int(parsed.get("completed_runs", 0)), 0)
	var saved_cosmetic := StringName(parsed.get("selected_cosmetic", TEAM_COLOR))
	if version < 2 and saved_cosmetic == &"mint_uniform":
		saved_cosmetic = TEAM_COLOR
	selected_cosmetic = saved_cosmetic if COSMETICS.has(saved_cosmetic) else TEAM_COLOR
	selected_truck = StringName(parsed.get("selected_truck", &"classic"))
	selected_paint = StringName(parsed.get("selected_paint", &"white"))
	selected_eyes = FaceCatalog.valid_eyes(StringName(parsed.get("selected_eyes", FaceCatalog.DEFAULT_EYES)))
	selected_mouth = FaceCatalog.valid_mouth(StringName(parsed.get("selected_mouth", FaceCatalog.DEFAULT_MOUTH)))
	nickname = NICKNAME.clean(str(parsed.get("nickname", "")))


## Choices that need an unlock this profile doesn't have fall back.
func _after_load(_version: int) -> void:
	var selected_rule: Dictionary = Dictionary(COSMETICS[selected_cosmetic])
	if not is_unlocked(StringName(selected_rule.get("unlock", &"starter_kit"))):
		selected_cosmetic = TEAM_COLOR
	if not TRUCKS.has(selected_truck) or not is_unlocked(StringName(TRUCKS[selected_truck]["unlock"])):
		selected_truck = &"classic"
	if not PAINTS.has(selected_paint) or not is_unlocked(StringName(PAINTS[selected_paint]["unlock"])):
		selected_paint = &"white"


func _reset_fields() -> void:
	total_score = 0
	successful_deliveries = 0
	completed_runs = 0
	selected_cosmetic = TEAM_COLOR
	selected_truck = &"classic"
	selected_paint = &"white"
	selected_eyes = FaceCatalog.DEFAULT_EYES
	selected_mouth = FaceCatalog.DEFAULT_MOUTH
	nickname = ""


func _on_run_ended(score: int, results: Dictionary) -> void:
	record_run(score, results)
