extends RefCounted
## Fixed IDs are safe to persist and replicate; no peer supplies resource paths.
## The sheets come from art/rounded_character/build_faces.py: eyes, their brows
## (own layer, so a blink doesn't drag them down) and mouth on one 512 square.
const DEFAULT_EYES: StringName = &"classic"
const DEFAULT_MOUTH: StringName = &"smile"
const EYES: Dictionary = {
	&"classic": "UI_FACE_EYES_CLASSIC", &"joyful": "UI_FACE_EYES_JOYFUL", &"sleepy": "UI_FACE_EYES_SLEEPY",
	&"worried": "UI_FACE_EYES_WORRIED", &"wink": "UI_FACE_EYES_WINK",
	&"lashes": "UI_FACE_EYES_LASHES", &"determined": "UI_FACE_EYES_DETERMINED", &"none": "UI_FACE_EYES_NONE",
}
const MOUTHS: Dictionary = {
	&"smile": "UI_FACE_MOUTH_SMILE", &"grin": "UI_FACE_MOUTH_GRIN", &"surprised": "UI_FACE_MOUTH_SURPRISED",
	&"pout": "UI_FACE_MOUTH_POUT", &"tongue": "UI_FACE_MOUTH_TONGUE",
	&"laugh": "UI_FACE_MOUTH_LAUGH", &"smirk": "UI_FACE_MOUTH_SMIRK", &"none": "UI_FACE_MOUTH_NONE",
}
## Ready-made faces, one tap for both layers (the customisation screen's top
## row). Any eyes + mouth pair is valid; these are just good ones.
const PRESETS: Array[Dictionary] = [
	{"id": &"classic", "title": "UI_FACE_PRESET_CLASSIC", "eyes": &"classic", "mouth": &"smile"},
	{"id": &"cheerful", "title": "UI_FACE_PRESET_CHEERFUL", "eyes": &"joyful", "mouth": &"laugh"},
	{"id": &"cheeky", "title": "UI_FACE_PRESET_CHEEKY", "eyes": &"wink", "mouth": &"smirk"},
	{"id": &"scared", "title": "UI_FACE_PRESET_SCARED", "eyes": &"worried", "mouth": &"surprised"},
	{"id": &"lazy", "title": "UI_FACE_PRESET_LAZY", "eyes": &"sleepy", "mouth": &"pout"},
	{"id": &"cocky", "title": "UI_FACE_PRESET_COCKY", "eyes": &"determined", "mouth": &"grin"},
	{"id": &"goofy", "title": "UI_FACE_PRESET_GOOFY", "eyes": &"lashes", "mouth": &"tongue"},
	{"id": &"toothy", "title": "UI_FACE_PRESET_TOOTHY", "eyes": &"classic", "mouth": &"grin"},
]
## What a card shows of the sheet: every eyes + brows sheet, every mouth sheet,
## the whole face (measured on the SVGs, centred, with a few pixels of air).
const THUMB_EYES: Rect2 = Rect2(106, 78, 300, 214)
const THUMB_MOUTH: Rect2 = Rect2(144, 280, 224, 152)
const THUMB_FACE: Rect2 = Rect2(96, 76, 320, 360)
const DIR: String = "res://assets/textures/characters/faces/"
static var _textures: Dictionary = {}

static func valid_eyes(id: StringName) -> StringName:
	return id if EYES.has(id) else DEFAULT_EYES

static func valid_mouth(id: StringName) -> StringName:
	return id if MOUTHS.has(id) else DEFAULT_MOUTH

## kind is "eyes", "brows" (by eyes id) or "mouth". Null for a face without
## that layer (brows of "none").
static func texture(kind: String, id: StringName) -> Texture2D:
	var safe_id: StringName = valid_mouth(id) if kind == "mouth" else valid_eyes(id)
	var key: String = kind + "_" + String(safe_id)
	if not _textures.has(key):
		var path: String = DIR + key + ".svg"
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key] as Texture2D

static func thumbnail(kind: String, id: StringName) -> AtlasTexture:
	var sheet: Texture2D = texture(kind, id)
	if sheet == null:
		return null
	var result := AtlasTexture.new()
	result.atlas = sheet
	result.region = THUMB_MOUTH if kind == "mouth" else THUMB_EYES
	return result

static func preset(id: StringName) -> Dictionary:
	for each: Dictionary in PRESETS:
		if each.id == id:
			return each
	return {}
