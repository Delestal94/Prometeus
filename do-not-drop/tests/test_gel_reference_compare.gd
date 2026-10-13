extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_reference_compare.gd
## Guards the S-311.39 per-round comparison report and review artifacts.

const REPORT_PATH: String = "res://../art/gel_character/review_bloque_e/round_01/report.json"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var absolute: String = ProjectSettings.globalize_path(REPORT_PATH)
	_expect(FileAccess.file_exists(absolute), "round 01 report exists")
	if not FileAccess.file_exists(absolute):
		quit(_failures)
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	_expect(report is Dictionary, "report is valid JSON")
	if not report is Dictionary:
		quit(_failures)
		return
	var data := report as Dictionary
	_expect(data.get("schema_version") == 1, "report schema is versioned")
	_expect(data.get("round") == 1, "report identifies the iteration")
	var resolution := data.get("resolution", []) as Array
	_expect(resolution.size() == 2 and int(resolution[0]) == 832 and int(resolution[1]) == 1248,
		"comparison keeps source resolution")
	var mask := data.get("mask", {}) as Dictionary
	_expect(mask.get("white_distance_threshold_srgb8") == 8,
		"white-background threshold is recorded")
	var silhouette := data.get("silhouette", {}) as Dictionary
	_expect(float(silhouette.get("iou", -1.0)) >= 0.0, "silhouette IoU is recorded")
	var reference_box := silhouette.get("reference_box_px", []) as Array
	_expect(reference_box.size() == 4 and int(reference_box[0]) == 148
		and int(reference_box[1]) == 98 and int(reference_box[2]) == 676
		and int(reference_box[3]) == 1135,
		"subject threshold excludes the cast shadow")
	var color := data.get("color", {}) as Dictionary
	var zones := color.get("zones", {}) as Dictionary
	for zone: String in ["head", "torso", "arms", "legs"]:
		_expect(zones.has(zone), "%s Delta E zone is recorded" % zone)
		if zones.has(zone):
			_expect(int((zones[zone] as Dictionary).get("sample_pixels", 0)) > 0,
				"%s has foreground samples" % zone)
	var artifacts := data.get("artifacts", {}) as Dictionary
	for artifact: String in ["side_by_side", "difference"]:
		var path: String = String(artifacts.get(artifact, ""))
		_expect(not path.is_empty() and FileAccess.file_exists(ProjectSettings.globalize_path("res://../" + path)),
			"%s PNG exists" % artifact)
	if _failures == 0:
		print("PASS: S-311.39 records IoU, zoned Delta E and review PNGs per round")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)
