extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_legibility.gd
## Guards the checked-in S-311.69 evidence and its reproducible 20 m setup.

const RENDERER: String = "res://tests/render_gel_legibility.gd"
const OUTPUT: String = "res://../art/gel_character/review_bloque_h/s311_69_legibility"
const LIGHTING: PackedStringArray = ["day", "night"]
const VIEWS: PackedStringArray = ["normal", "deuteranopia", "protanopia"]


func _initialize() -> void:
	var source := FileAccess.get_file_as_string(RENDERER)
	var failures := 0
	failures += _expect("const DISTANCE_METERS: float = 20.0" in source, "Renderer fixes the review distance at 20 m")
	failures += _expect("PlayerAppearance.set_gel_team_accent" in source, "Captures exercise the real team accent")
	failures += _expect("MACHADO" in source, "Captures include the same colour-blind simulation as the palette test")
	var palette: Array = load("res://scripts/gameplay/player/player.gd").get_script_constant_map()["PLAYER_COLORS"]
	var signatures: Dictionary = {}
	for color: Color in palette:
		signatures[PlayerAppearance.gel_team_signature(color)] = true
	failures += _expect(signatures.size() == palette.size(),
		"Every crew colour gets a unique four-band identity pattern")
	for lighting: String in LIGHTING:
		for view: String in VIEWS:
			var name := "s311_69_%s_%s.png" % [lighting, view]
			var image := Image.load_from_file(OUTPUT.path_join(name))
			failures += _expect(image != null and image.get_size() == Vector2i(1280, 720),
				"%s is a checked-in 1280x720 capture" % name)
	var sheet := Image.load_from_file(OUTPUT.path_join("s311_69_contact_sheet.png"))
	failures += _expect(sheet != null and sheet.get_size() == Vector2i(1920, 720),
		"The six views have a checked-in 3x2 contact sheet")
	if failures == 0:
		print("PASS: S-311.69 has day/night and normal/deuteranopia/protanopia evidence at 20 m")
	quit(failures)


func _expect(condition: bool, description: String) -> int:
	if condition:
		return 0
	push_error(description)
	return 1
