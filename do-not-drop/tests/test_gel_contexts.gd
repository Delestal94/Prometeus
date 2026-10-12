extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_contexts.gd
## Guards the reproducible S-311.36 visual-review contract without rendering.

const RENDERER: String = "res://tests/render_gel_contexts.gd"
const OUTPUT: String = "res://../art/gel_character/review_bloque_d/s311_36_contexts"
const EXPECTED: PackedStringArray = [
	"day",
	"sunset",
	"night_flashlights",
	"rain",
	"fog",
	"truck_interior",
	"depot",
	"results",
]


func _initialize() -> void:
	var source: String = FileAccess.get_file_as_string(RENDERER)
	var failures: int = 0
	for context: String in EXPECTED:
		if not ('"%s"' % context) in source:
			push_error("Missing gel review context: %s" % context)
			failures += 1
		var capture := Image.load_from_file(OUTPUT.path_join("s311_36_%s.png" % context))
		if capture == null or capture.get_size() != Vector2i(1280, 720):
			push_error("Missing 1280x720 capture for gel context: %s" % context)
			failures += 1
	if not "DisplayServer.get_name() == \"headless\"" in source:
		push_error("The visual renderer must reject headless execution")
		failures += 1
	if not "s311_36_contact_sheet.png" in source:
		push_error("The visual renderer must produce the 4x2 contact sheet")
		failures += 1
	var sheet := Image.load_from_file(OUTPUT.path_join("s311_36_contact_sheet.png"))
	if sheet == null or sheet.get_size() != Vector2i(1920, 540):
		push_error("Missing 1920x540 gel-context contact sheet")
		failures += 1
	if failures == 0:
		print("PASS: S-311.36 renderer covers all eight requested contexts")
	quit(failures)
