extends RefCounted
## Fixed IDs are safe to persist and replicate; no peer supplies resource paths.
const DEFAULT_EYES: StringName = &"classic"
const DEFAULT_MOUTH: StringName = &"smile"
const EYES: Dictionary = {
	&"classic": "UI_FACE_EYES_CLASSIC", &"joyful": "UI_FACE_EYES_JOYFUL", &"sleepy": "UI_FACE_EYES_SLEEPY",
	&"worried": "UI_FACE_EYES_WORRIED", &"wink": "UI_FACE_EYES_WINK",
	&"lashes": "UI_FACE_EYES_LASHES", &"none": "UI_FACE_EYES_NONE",
}
const MOUTHS: Dictionary = {
	&"smile": "UI_FACE_MOUTH_SMILE", &"grin": "UI_FACE_MOUTH_GRIN", &"surprised": "UI_FACE_MOUTH_SURPRISED",
	&"pout": "UI_FACE_MOUTH_POUT", &"tongue": "UI_FACE_MOUTH_TONGUE",
	&"laugh": "UI_FACE_MOUTH_LAUGH", &"none": "UI_FACE_MOUTH_NONE",
}
static var _textures: Dictionary = {}

static func valid_eyes(id: StringName) -> StringName:
	return id if EYES.has(id) else DEFAULT_EYES

static func valid_mouth(id: StringName) -> StringName:
	return id if MOUTHS.has(id) else DEFAULT_MOUTH

static func texture(kind: String, id: StringName) -> Texture2D:
	var safe_id: StringName = valid_eyes(id) if kind == "eyes" else valid_mouth(id)
	var prefix: String = "eyes" if kind == "eyes" else "mouth"
	var key: String = prefix + "_" + String(safe_id)
	if not _textures.has(key):
		_textures[key] = load("res://assets/textures/characters/faces/" + key + ".svg")
	return _textures[key] as Texture2D

static func thumbnail(kind: String, id: StringName) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = texture(kind, id)
	result.region = Rect2(128, 126, 256, 148) if kind == "eyes" else Rect2(161, 297, 190, 109)
	return result
