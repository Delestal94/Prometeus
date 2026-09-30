class_name TutorialCatalog
extends RefCounted
## One source for the tutorial panel and the first-time in-game tips.

const TRAP_ORDER: Array[StringName] = [
	&"fragile", &"balance", &"growing_weight", &"liquid", &"noisy", &"explosive", &"hostile",
]
const TRAPS: Dictionary = {
	&"fragile": {
		"title": "UI_TUT_TRAP_FRAGILE", "glyph": "!", "breaks": "UI_TUT_FRAGILE_BREAKS",
		"action": "UI_TUT_FRAGILE_ACTION", "keyboard": "UI_TUT_LEFT_CLICK", "gamepad": "RT",
		"control_label": "UI_TUT_CONTROL_CUSHION",
	},
	&"balance": {
		"title": "UI_TUT_TRAP_BALANCE", "glyph": "↔", "breaks": "UI_TUT_BALANCE_BREAKS",
		"action": "UI_TUT_BALANCE_ACTION", "keyboard": "UI_TUT_CLICK_LEAN", "gamepad": "UI_TUT_TRIGGER_LEAN",
		"control_label": "UI_TUT_CONTROL_STEADY",
	},
	&"growing_weight": {
		"title": "UI_TUT_TRAP_GROWING_WEIGHT", "glyph": "↓", "breaks": "UI_TUT_WEIGHT_BREAKS",
		"action": "UI_TUT_WEIGHT_ACTION", "keyboard": "WASD", "gamepad": "UI_TUT_LEFT_STICK",
		"control_label": "UI_TUT_CONTROL_SEQUENCE",
	},
	&"liquid": {
		"title": "UI_TUT_TRAP_LIQUID", "glyph": "≈", "breaks": "UI_TUT_LIQUID_BREAKS",
		"action": "UI_TUT_LIQUID_ACTION", "keyboard": "A/D", "gamepad": "UI_TUT_LEFT_STICK",
		"control_label": "UI_TUT_CONTROL_DRY",
	},
	&"noisy": {
		"title": "UI_TUT_TRAP_NOISY", "glyph": "♪", "breaks": "UI_TUT_NOISY_BREAKS",
		"action": "UI_TUT_NOISY_ACTION", "keyboard": "UI_TUT_LEFT_CLICK", "gamepad": "RT",
		"control_label": "UI_TUT_CONTROL_CALM",
	},
	&"explosive": {
		"title": "UI_TUT_TRAP_EXPLOSIVE", "glyph": "✹", "breaks": "UI_TUT_EXPLOSIVE_BREAKS",
		"action": "UI_TUT_EXPLOSIVE_ACTION", "keyboard": "WASD", "gamepad": "UI_TUT_LEFT_STICK",
		"control_label": "UI_TUT_CONTROL_SEQUENCE",
	},
	&"hostile": {
		"title": "UI_TUT_TRAP_HOSTILE", "glyph": "◆", "breaks": "UI_TUT_HOSTILE_BREAKS",
		"action": "UI_TUT_HOSTILE_ACTION", "keyboard": "UI_TUT_LEFT_CLICK", "gamepad": "RT",
		"control_label": "UI_TUT_CONTROL_OBEY",
	},
}


static func card(trap_id: StringName) -> Dictionary:
	var result: Dictionary = Dictionary(TRAPS.get(trap_id, {})).duplicate(true)
	for field: String in ["title", "breaks", "action", "keyboard", "gamepad", "control_label"]:
		var value: String = String(result.get(field, ""))
		if value.begins_with("UI_"):
			result[field] = TranslationServer.translate(value)
	return result


static func available_traps(profile: Node) -> Array[StringName]:
	var result: Array[StringName] = []
	for trap_id: StringName in TRAP_ORDER:
		var unlock_id: StringName = StringName(profile.TRAP_UNLOCKS.get(trap_id, &""))
		if unlock_id.is_empty() or bool(profile.call(&"is_unlocked", unlock_id)):
			result.append(trap_id)
	return result


static func control(card_data: Dictionary) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null(^"/root/GameSettings") if tree != null else null
	var using_gamepad: bool = settings != null and bool(settings.get(&"using_gamepad"))
	return String(card_data["gamepad"] if using_gamepad else card_data["keyboard"])


## First time the player runs with a box in their arms (N-115, player_sprint.gd).
static func sprint_carry_tip() -> String:
	return TranslationServer.translate("UI_TUT_TIP_SPRINT_CARRY")


static func tip_text(trap_id: StringName) -> String:
	var data: Dictionary = card(trap_id)
	if data.is_empty():
		return ""
	return "%s — %s  %s" % [data["title"], data["action"], control(data)]
