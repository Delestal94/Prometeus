class_name PingCatalog
extends RefCounted
## Shared labels and presentation for the six non-verbal pings.

const OPTIONS: Array[Dictionary] = [
	{"label": "HUD_PING_WARNING", "icon": "!", "color": Color("f4c562")},
	{"label": "HUD_PING_HELP", "icon": "?", "color": Color("f47e6d")},
	{"label": "HUD_PING_BRAKE", "icon": "■", "color": Color("e65f4c")},
	{"label": "HUD_PING_HERE", "icon": "●", "color": Color("6db3d6")},
	{"label": "HUD_PING_THANKS", "icon": "♥", "color": Color("83e2ba")},
	{"label": "HUD_PING_YES_NO", "icon": "✓/✕", "color": Color("c9a0e0")},
]


static func option(label: String) -> Dictionary:
	for value: Dictionary in OPTIONS:
		if String(value["label"]) == label:
			return value
	return OPTIONS[0]
