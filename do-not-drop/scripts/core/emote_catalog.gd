class_name EmoteCatalog
extends RefCounted
## Stable emote choices shared by the radial UI and PlayerAnimator. The clip
## name is what already travels in Player.anim_clip; labels stay local.

const OPTIONS: Array[Dictionary] = [
	{"clip": &"Wave", "key": "UI_EMOTE_WAVE", "icon": "~", "color": Color("6db3d6"), "duration": 2.2},
	{"clip": &"Clap", "key": "UI_EMOTE_CLAP", "icon": "++", "color": Color("f4c562"), "duration": 2.4},
	{"clip": &"Facepalm", "key": "UI_EMOTE_FACEPALM", "icon": "!", "color": Color("f47e6d"), "duration": 2.2},
	{"clip": &"Shrug", "key": "UI_EMOTE_SHRUG", "icon": "?", "color": Color("c9a0e0"), "duration": 2.0},
	{"clip": &"Point", "key": "UI_EMOTE_POINT", "icon": ">", "color": Color("e89a4f"), "duration": 2.0},
	{"clip": &"ThumbsUp", "key": "UI_EMOTE_THUMBS_UP", "icon": "+", "color": Color("83e2ba"), "duration": 2.0},
	{"clip": &"MeltAndReturn", "key": "UI_EMOTE_MELT", "icon": "≈", "color": Color("ff6f91"), "duration": 3.0},
	{"clip": &"ShakeLikeDog", "key": "UI_EMOTE_SHAKE", "icon": "*", "color": Color("8bc9a8"), "duration": 1.8},
]


static func option(clip: StringName) -> Dictionary:
	for value: Dictionary in OPTIONS:
		if value["clip"] == clip:
			return value
	return {}


static func clips() -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Dictionary in OPTIONS:
		result.append(value["clip"] as StringName)
	return result


static func display_text(clip: StringName) -> String:
	var value: Dictionary = option(clip)
	return TranslationServer.translate(String(value.get("key", "")))


static func lock_msec(clip: StringName) -> int:
	var value: Dictionary = option(clip)
	return maxi(1, roundi(float(value.get("duration", 0.1)) * 1000.0))
