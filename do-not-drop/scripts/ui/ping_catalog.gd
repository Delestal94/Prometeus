class_name PingCatalog
extends RefCounted
## Shared labels and presentation for the quick callouts (N-505): the ping
## wheel's eight phrases. "label" is what travels over the network (stable,
## never translated); "key" is the strings_ui.csv entry shown on screen.

const OPTIONS: Array[Dictionary] = [
	{"label": "¡Cuidado!", "key": "HUD_CALLOUT_CAREFUL", "icon": "!", "color": Color("f4c562")},
	{"label": "¡Frená!", "key": "HUD_CALLOUT_BRAKE", "icon": "■", "color": Color("e65f4c")},
	{"label": "¡Bache!", "key": "HUD_CALLOUT_BUMP", "icon": "▼", "color": Color("e89a4f")},
	{"label": "¡Ayuda acá!", "key": "HUD_CALLOUT_HELP", "icon": "?", "color": Color("f47e6d")},
	{"label": "¡Se cae!", "key": "HUD_CALLOUT_FALLING", "icon": "↓", "color": Color("ff6f91")},
	{"label": "Tengo la cinta", "key": "HUD_CALLOUT_TAPE", "icon": "+", "color": Color("83e2ba")},
	{"label": "Esperá", "key": "HUD_CALLOUT_WAIT", "icon": "…", "color": Color("6db3d6")},
	{"label": "¡Dale, dale!", "key": "HUD_CALLOUT_GO", "icon": "»", "color": Color("c9a0e0")},
]


static func option(label: String) -> Dictionary:
	for value: Dictionary in OPTIONS:
		if String(value["label"]) == label:
			return value
	return OPTIONS[0]


## How many syllables the callout's babble has (SynthAudio.callout_voice()):
## one per vowel group of the network label, so "¡Dale, dale!" chatters
## four times and "Esperá" three. Counted on the label, never the translated
## text, so every client hears the same call.
static func syllables(label: String) -> int:
	var count: int = 0
	var in_vowel: bool = false
	for character: String in label.to_lower():
		var vowel: bool = "aeiouáéíóú".contains(character)
		if vowel and not in_vowel:
			count += 1
		in_vowel = vowel
	return clampi(count, 1, 5)


## The phrase as this client's language shows it.
static func display_text(label: String) -> String:
	return TranslationServer.translate(String(option(label)["key"]))
