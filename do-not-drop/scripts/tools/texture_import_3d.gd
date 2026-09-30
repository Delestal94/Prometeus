extends SceneTree
## Run (from the repo root), then let Godot reimport and rewrite the .import files:
##   Godot --headless --path do-not-drop --script res://scripts/tools/texture_import_3d.gd
##   Godot --headless --path do-not-drop --import
##
## Textures that only live on 3D surfaces (detail maps, terrain, the courier
## label) are loaded from code, so the editor never sees them on a material and
## its "detect 3D" never switches them to VRAM compression: they stayed
## lossless and without mipmaps, which shimmers at a distance and costs 4x the
## video memory (N-314). This sets the importer params for every texture in
## DIRS; the --import pass is what writes the final .import (dest files and
## metadata), so no .import is edited by hand. Idempotent: a second run
## changes nothing. test_texture_import_3d.gd fails if a texture in DIRS
## is not imported this way.

const DIRS: Array[String] = [
	"res://assets/textures/detail",
	"res://assets/textures/terrain",
	"res://assets/textures/cargo",
]
const EXTENSIONS: Array[String] = ["png", "jpg", "webp"]
## compress/mode: 2 = VRAM Compressed (S3TC/BPTC on desktop).
const PARAMS: Dictionary = {
	"compress/mode": 2,
	"mipmaps/generate": true,
	"detect_3d/compress_to": 0,
}


func _initialize() -> void:
	var changed: int = 0
	for path in textures():
		var import_path: String = ProjectSettings.globalize_path(path + ".import")
		var config := ConfigFile.new()
		if config.load(import_path) != OK:
			push_error("texture_import_3d: cannot read %s" % import_path)
			continue
		var dirty: bool = false
		for key: String in PARAMS:
			if config.get_value("params", key, null) != PARAMS[key]:
				config.set_value("params", key, PARAMS[key])
				dirty = true
		if dirty:
			config.save(import_path)
			changed += 1
			print("texture_import_3d: %s" % path)
	print("texture_import_3d: %d changed; now run Godot --headless --import" % changed)
	quit(0)


## Every texture under DIRS (res:// paths), sorted.
static func textures() -> Array[String]:
	var out: Array[String] = []
	for dir in DIRS:
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() in EXTENSIONS:
				out.append(dir.path_join(file))
	out.sort()
	return out
