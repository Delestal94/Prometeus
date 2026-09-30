extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_texture_import_3d.gd
##
## Texturas 3D con compresion de VRAM y mipmaps (N-314):
## - Cada textura de assets/textures/{detail,terrain,cargo} (la lista sale de
##   scripts/tools/texture_import_3d.gd) se importa como VRAM Compressed
##   (compress/mode=2), con mipmaps y con el remap marcado "vram_texture".
##   Falla si alguien agrega una textura nueva a esas carpetas sin pasarla por
##   la herramienta (se veria con parpadeo de lejos y ocuparia 4x de VRAM).
## - Hay al menos 14 texturas (las 10 de detalle, las 3 de terreno y la
##   etiqueta del courier) y todas cargan como Texture2D.

const TextureImport3D = preload("res://scripts/tools/texture_import_3d.gd")
const MIN_TEXTURES: int = 14

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var paths: Array[String] = TextureImport3D.textures()
	_expect(paths.size() >= MIN_TEXTURES,
		"at least %d 3D textures listed (got %d)" % [MIN_TEXTURES, paths.size()])
	for path in paths:
		var config := ConfigFile.new()
		_expect(config.load(path + ".import") == OK, "%s.import is readable" % path)
		_expect(int(config.get_value("params", "compress/mode", -1)) == 2,
			"%s is VRAM compressed (compress/mode=%s)" % [path, config.get_value("params", "compress/mode")])
		_expect(bool(config.get_value("params", "mipmaps/generate", false)),
			"%s generates mipmaps" % path)
		var metadata: Dictionary = config.get_value("remap", "metadata", {})
		_expect(bool(metadata.get("vram_texture", false)),
			"%s was reimported as a VRAM texture (remap metadata %s)" % [path, metadata])
		_expect(load(path) is Texture2D, "%s loads as Texture2D" % path)
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
