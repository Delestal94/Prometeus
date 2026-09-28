extends RefCounted
## Fixed IDs are safe to persist and replicate; no peer supplies resource paths.
const DEFAULT_EYES: StringName = &"classic"
const DEFAULT_MOUTH: StringName = &"smile"
const EYES: Dictionary = {
	&"classic": "Clásicos", &"joyful": "Contentos", &"sleepy": "Dormilones",
	&"worried": "Preocupados", &"wink": "Guiño", &"lashes": "Pestañas", &"none": "Sin ojos",
}
const MOUTHS: Dictionary = {
	&"smile": "Sonrisa", &"grin": "Dientes", &"surprised": "Sorpresa",
	&"pout": "Puchero", &"tongue": "Lengüita", &"laugh": "Carcajada", &"none": "Sin boca",
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
