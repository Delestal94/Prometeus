class_name PingCatalog
extends RefCounted
## Shared labels and presentation for the six non-verbal pings.

const OPTIONS: Array[Dictionary] = [
	{"label": "¡Cuidado!", "icon": "!", "color": Color("f4c562")},
	{"label": "¡Ayuda!", "icon": "?", "color": Color("f47e6d")},
	{"label": "¡Frená!", "icon": "■", "color": Color("e65f4c")},
	{"label": "Acá", "icon": "●", "color": Color("6db3d6")},
	{"label": "Gracias", "icon": "♥", "color": Color("83e2ba")},
	{"label": "Sí/No", "icon": "✓/✕", "color": Color("c9a0e0")},
]


static func option(label: String) -> Dictionary:
	for value: Dictionary in OPTIONS:
		if String(value["label"]) == label:
			return value
	return OPTIONS[0]
