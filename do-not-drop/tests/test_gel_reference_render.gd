extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_reference_render.gd
## Guards the reproducible Godot/Blender reference-scene contract for S-311.38.

const RENDER := preload("res://tests/render_gel_reference.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(RENDER.WIDTH == 832 and RENDER.HEIGHT == 1248, "output matches the source photo resolution")
	_expect(RENDER.PRESET_ID == &"delgada", "the Delgada preset is selected")
	_expect(is_equal_approx(RENDER.CAMERA_DISTANCE_M, 4.0), "front camera distance is fixed")
	_expect(is_equal_approx(RENDER.CAMERA_FOV_DEGREES, 30.9), "measured photo framing fixes the vertical FOV")
	_expect(RENDER.POSE_DEGREES == {
		&"upper_arm": 100.0,
		&"forearm": -25.0,
		&"hand": 20.0,
	}, "the relaxed A pose matches the measured reference")
	_expect(RENDER.OUTPUT_PATH.ends_with("s311_38_godot_reference.png"), "the PNG path is stable")

	var root_path: String = ProjectSettings.globalize_path("res://").path_join("..")
	var blender_script: String = root_path.path_join("art/gel_character/build_reference_scene.py")
	var blender_scene: String = root_path.path_join("art/gel_character/gel_reference.blend")
	_expect(FileAccess.file_exists(blender_script), "the reproducible Blender scene builder exists")
	_expect(FileAccess.file_exists(blender_scene), "the ready-to-iterate Blender scene exists")
	if FileAccess.file_exists(blender_script):
		var source: String = FileAccess.get_file_as_string(blender_script)
		for token: String in ["832", "1248", "30.9", "upper_arm", "forearm", "hand", "SoftKeyUpperLeft"]:
			_expect(token in source, "Blender scene shares reference setting %s" % token)
	if _failures == 0:
		print("PASS: S-311.38 Godot and Blender reference scenes share one measured setup")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)
