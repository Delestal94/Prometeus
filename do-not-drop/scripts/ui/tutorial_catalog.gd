class_name TutorialCatalog
extends RefCounted
## One source for the tutorial panel and the first-time in-game tips.

const TRAP_ORDER: Array[StringName] = [
	&"fragile", &"balance", &"growing_weight", &"liquid", &"noisy", &"explosive", &"hostile",
]
const TRAPS: Dictionary = {
	&"fragile": {
		"title": "Frágil", "glyph": "!", "breaks": "Los golpes fuertes le quitan integridad.",
		"action": "Manejá suave y asegurala antes de salir.", "keyboard": "W/S", "gamepad": "RT/LT",
		"control_label": "conducir suave",
	},
	&"balance": {
		"title": "Equilibrio", "glyph": "↔", "breaks": "Quedar inclinada demasiado tiempo.",
		"action": "Mantené la acción para enderezarla.", "keyboard": "Click izq.", "gamepad": "RT",
		"control_label": "enderezar",
	},
	&"growing_weight": {
		"title": "Peso creciente", "glyph": "↓", "breaks": "No completar la secuencia antes de que pese demasiado.",
		"action": "Seguí las flechas sin soltar la caja.", "keyboard": "WASD", "gamepad": "Stick izq.",
		"control_label": "secuencia",
	},
	&"liquid": {
		"title": "Líquido", "glyph": "≈", "breaks": "Inclinarla y dejar crecer el charco.",
		"action": "Mantené la acción para secar el derrame.", "keyboard": "Click izq.", "gamepad": "RT",
		"control_label": "secar",
	},
	&"noisy": {
		"title": "Ruidoso", "glyph": "♪", "breaks": "Los golpes lo alteran hasta que escapa.",
		"action": "Mantené la acción para calmarlo.", "keyboard": "Click izq.", "gamepad": "RT",
		"control_label": "calmar",
	},
	&"explosive": {
		"title": "Explosivo", "glyph": "✹", "breaks": "Dejar que la cuenta regresiva llegue a cero.",
		"action": "Repetí la secuencia de flechas a tiempo.", "keyboard": "WASD", "gamepad": "Stick izq.",
		"control_label": "secuencia",
	},
	&"hostile": {
		"title": "Hostil", "glyph": "◆", "breaks": "Tocar cuando ordena NO TOCAR o ignorar CALMÁ.",
		"action": "Mantené o soltá según la orden de la caja.", "keyboard": "Click izq.", "gamepad": "RT",
		"control_label": "obedecer",
	},
}


static func card(trap_id: StringName) -> Dictionary:
	return Dictionary(TRAPS.get(trap_id, {})).duplicate(true)


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


static func tip_text(trap_id: StringName) -> String:
	var data: Dictionary = card(trap_id)
	if data.is_empty():
		return ""
	return "%s — %s  %s" % [data["title"], data["action"], control(data)]
