class_name Nickname
extends RefCounted
## The name the player goes by in the game (N-606.1): typed in the appearance
## panel (up to MAX_LENGTH characters) and replicated with the rest of the
## appearance (PlayerNickname, a child of the player). The next-day newspaper (NewsDesk) puts
## it in its jokes. It is never the Steam name.
##
## Left empty, the game hands out a funny one from the player's seed. That one
## travels as a translation key (LocText), so every peer reads it in their own
## language; one the player typed is a plain String.

const MAX_LENGTH: int = 16
## The funny names, as keys in strings_ui.csv. Spelled out (not built from a
## number) so the translation test finds every one of them.
const AUTO_KEYS: Array[String] = [
	"UI_NICK_01", "UI_NICK_02", "UI_NICK_03", "UI_NICK_04", "UI_NICK_05", "UI_NICK_06",
	"UI_NICK_07", "UI_NICK_08", "UI_NICK_09", "UI_NICK_10", "UI_NICK_11", "UI_NICK_12",
	"UI_NICK_13", "UI_NICK_14", "UI_NICK_15", "UI_NICK_16", "UI_NICK_17", "UI_NICK_18",
	"UI_NICK_19", "UI_NICK_20", "UI_NICK_21", "UI_NICK_22", "UI_NICK_23", "UI_NICK_24",
]


## What a peer may store as a nickname: no control characters or brackets (the
## name lands in a RichText line on some screens), single spaces, trimmed, at
## most MAX_LENGTH characters. A remote peer's value goes through this too.
static func clean(text: String) -> String:
	var kept: String = ""
	for index: int in text.length():
		var character: String = text[index]
		var code: int = character.unicode_at(0)
		if code < 32 or code == 127 or character in ["[", "]", "<", ">", "%", "{", "}"]:
			continue
		kept += character
	while kept.contains("  "):
		kept = kept.replace("  ", " ")
	return kept.strip_edges().substr(0, MAX_LENGTH).strip_edges()


## The funny name's key for this seed.
static func auto_key(seed_value: int) -> String:
	return AUTO_KEYS[posmod(hash([seed_value, "nickname"]), AUTO_KEYS.size())]


## The nickname as it travels: the typed one (cleaned) as a String, or the
## funny one as a LocText line when nothing was typed.
static func resolve(typed: String, seed_value: int) -> Variant:
	var text: String = clean(typed)
	return text if not text.is_empty() else [auto_key(seed_value)]


## The nickname in this peer's language (resolve() through LocText).
static func display(typed: String, seed_value: int) -> String:
	var value: Variant = resolve(typed, seed_value)
	if value is String:
		return value
	return String(TranslationServer.translate(StringName((value as Array)[0])))
