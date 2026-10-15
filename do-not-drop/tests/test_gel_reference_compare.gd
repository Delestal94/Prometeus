extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_reference_compare.gd
## Guards the S-311.39 comparison report, the S-311.40 approval gate, and the
## S-311.42 requirement that approval uses the Godot render seen by players.

const REPORT_PATH: String = "res://../art/gel_character/review_bloque_e/round_01/report.json"
const APPROVED_REPORT_PATH: String = "res://../art/gel_character/review_bloque_e/round_149/report.json"

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
	var approval := data.get("approval", {}) as Dictionary
	var thresholds := approval.get("thresholds", {}) as Dictionary
	_expect(is_equal_approx(float(thresholds.get("minimum_silhouette_iou", 0.0)), 0.92),
		"approval requires silhouette IoU >= 0.92")
	_expect(is_equal_approx(float(thresholds.get("maximum_mean_delta_e_per_zone", 0.0)), 8.0),
		"approval requires mean Delta E <= 8 in every zone")
	_expect(int(thresholds.get("required_visual_yes", 0)) == 12,
		"approval requires all 12 visual criteria")
	var visual := approval.get("visual_review", {}) as Dictionary
	_expect(int(visual.get("criteria_total", 0)) == 12, "visual review has 12 criteria")
	var visual_path: String = String(visual.get("path", ""))
	var visual_absolute: String = ProjectSettings.globalize_path("res://../" + visual_path)
	_expect(not visual_path.is_empty() and FileAccess.file_exists(visual_absolute),
		"visual review file exists")
	if FileAccess.file_exists(visual_absolute):
		var review := JSON.parse_string(FileAccess.get_file_as_string(visual_absolute)) as Dictionary
		var criteria := review.get("criteria", []) as Array
		_expect(criteria.size() == 12, "visual review lists exactly 12 criteria")
		for criterion: Dictionary in criteria:
			_expect(criterion.get("result") in ["yes", "no", "pending"],
				"visual criterion uses a supported result")
	var automatic := approval.get("automatic", {}) as Dictionary
	var gated_zones := automatic.get("color_zones", {}) as Dictionary
	_expect(gated_zones.size() == 4, "all four color zones are gated")
	for zone: String in ["head", "torso", "arms", "legs"]:
		_expect(gated_zones.has(zone), "%s has an approval gate" % zone)
	_expect(approval.get("passed") == false, "baseline round is not falsely approved")
	_verify_approved_godot_report()
	if _failures == 0:
		print("PASS: S-311.39-40/42 records comparisons, enforces approval, and uses Godot output")
	quit(_failures)


func _verify_approved_godot_report() -> void:
	var absolute: String = ProjectSettings.globalize_path(APPROVED_REPORT_PATH)
	_expect(FileAccess.file_exists(absolute), "approved round report exists")
	if not FileAccess.file_exists(absolute):
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute))
	_expect(report is Dictionary, "approved round report is valid JSON")
	if not report is Dictionary:
		return
	var data := report as Dictionary
	var render_path: String = String(data.get("render", ""))
	var mask_path: String = String(data.get("mask_render", ""))
	_expect(render_path.ends_with("/round_149/godot_render.png"),
		"approved comparison uses the Godot color render")
	_expect(mask_path.ends_with("/round_149/godot_render_mask.png"),
		"approved silhouette uses the Godot mask render")
	_expect(FileAccess.file_exists(ProjectSettings.globalize_path("res://../" + render_path)),
		"approved Godot color render exists")
	_expect(FileAccess.file_exists(ProjectSettings.globalize_path("res://../" + mask_path)),
		"approved Godot mask render exists")
	var approval := data.get("approval", {}) as Dictionary
	_expect(approval.get("passed") == true,
		"the report sourced from Godot is the approved comparison")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)
