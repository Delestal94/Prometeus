extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_studio_delivery.gd
## Guards the complete, reproducible S-311.100 studio delivery without rendering.

const OUTPUT: String = "res://../art/gel_character/review"
const MANIFEST: String = "s311_100_manifest.json"
const README: String = "LEEME.md"
const SHEETS: PackedStringArray = [
	"s311_100_turntable_mint.png",
	"s311_100_turntable_amber.png",
	"s311_100_turntable_coral.png",
	"s311_100_turntable_sky.png",
	"s311_100_turntable_lilac.png",
	"s311_100_turntable_cobalt.png",
]
const PREVIEWS: PackedStringArray = [
	"s311_100_editor_preview.png",
	"s311_100_animation_reel_preview.png",
]
const VIDEOS: PackedStringArray = [
	"s311_100_editor_sliders.avi",
	"s311_100_animation_reel.avi",
]

var _failures: int = 0


func _initialize() -> void:
	_check_images()
	_check_videos()
	_check_manifest()
	_check_readme()
	_check_reproducibility()
	if _failures == 0:
		print("PASS: complete S-311.100 turntables, editor video, animation reel and README")
	quit(_failures)


func _check_images() -> void:
	for file_name: String in SHEETS:
		var image := Image.load_from_file(OUTPUT.path_join(file_name))
		_expect(image != null and image.get_size() == Vector2i(1760, 1080),
			"%s is a 1760x1080 six-preset turntable" % file_name)
	for file_name: String in PREVIEWS:
		var image := Image.load_from_file(OUTPUT.path_join(file_name))
		var expected_size := (
			Vector2i(1280, 720) if file_name == PREVIEWS[0] else Vector2i(960, 540)
		)
		_expect(image != null and image.get_size() == expected_size,
			"%s has the expected recording-frame size" % file_name)


func _check_videos() -> void:
	for file_name: String in VIDEOS:
		var file := FileAccess.open(OUTPUT.path_join(file_name), FileAccess.READ)
		_expect(file != null, "%s exists" % file_name)
		if file == null:
			continue
		var size: int = file.get_length()
		_expect(size > 1_000_000, "%s contains a real recording" % file_name)
		_expect(size < 95_000_000, "%s stays below the GitHub file limit" % file_name)
		var header: PackedByteArray = file.get_buffer(12)
		_expect(
			header.size() == 12
			and header.slice(0, 4).get_string_from_ascii() == "RIFF"
			and header.slice(8, 12).get_string_from_ascii() == "AVI ",
			"%s is a valid AVI container" % file_name
		)


func _check_manifest() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join(MANIFEST)))
	_expect(typeof(parsed) == TYPE_DICTIONARY, "the final manifest is valid JSON")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var manifest: Dictionary = parsed
	_expect(manifest.get(&"task") == "S-311.100", "the manifest names the final task")
	_expect(not bool(manifest.get(&"default_character_changed", true)),
		"the delivery records that the default-character decision was not changed")
	_expect((manifest.get(&"preset_row_order", []) as Array).size() == 6,
		"the manifest covers all six presets")
	_expect((manifest.get(&"colors", []) as Array).size() == 6,
		"the manifest covers all six colors")
	_expect((manifest.get(&"turntable_files", []) as Array).size() == 6,
		"the manifest lists all six turntable sheets")
	_expect((manifest.get(&"turntable_angles_degrees", []) as Array).size() == 8,
		"the manifest records all eight turntable angles")
	_expect(manifest.get(&"video_fps") == 24, "the manifest records 24 FPS")
	for file_name: String in SHEETS + PREVIEWS + VIDEOS:
		_expect(file_name in JSON.stringify(manifest), "%s appears in the manifest" % file_name)


func _check_readme() -> void:
	var readme: String = FileAccess.get_file_as_string(OUTPUT.path_join(README))
	_expect(not readme.is_empty(), "the final LEEME exists")
	for file_name: String in SHEETS + PREVIEWS + VIDEOS:
		_expect(file_name in readme, "%s is documented in LEEME" % file_name)
	for label: String in ["Delgada", "Flaca", "Rellena", "Petisa", "Cabezona", "Larguirucha"]:
		_expect(label in readme, "%s is explained in the preset row order" % label)
	_expect("no modifica la selección del personaje por defecto" in readme,
		"LEEME keeps the default-character decision behind explicit approval")


func _check_reproducibility() -> void:
	var turntable_source: String = FileAccess.get_file_as_string(
		"res://tests/render_gel_final_turntables.gd")
	var editor_source: String = FileAccess.get_file_as_string("res://tests/record_gel_editor.gd")
	var reel_source: String = FileAccess.get_file_as_string(
		"res://tests/record_gel_animation_reel.gd")
	_expect("DisplayServer.get_name() == \"headless\"" in turntable_source,
		"the turntable generator rejects fake headless captures")
	_expect(".s311_100_capture_profile.json" in editor_source,
		"the editor recording isolates its temporary profile")
	_expect("DirAccess.remove_absolute" in editor_source,
		"the editor recording deletes its temporary profile")
	_expect("CATEGORIES" in reel_source and "VictoryDance" in reel_source,
		"the reel is generated from the declared clip categories")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failures += 1
